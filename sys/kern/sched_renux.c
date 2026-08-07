/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026 The Renux Project.
 *
 * Renux scheduler.
 *
 * A DragonFly-flavoured scheduler for the Renux kernel:
 *
 *  - Per-CPU run queues with O(1) highest-priority selection (the generic
 *    bitmap-based struct runq).
 *  - Strong CPU affinity: a thread stays on the CPU it last ran on, and is
 *    only migrated when that CPU is overloaded.
 *  - Lazy migration: an idle CPU steals the highest priority thread from the
 *    most loaded CPU instead of eagerly balancing.
 *  - Time slicing: each thread runs for sched_renux_slice ticks, then is
 *    rescheduled.
 *
 * Locking is deliberately simple and safe: a single global spin lock
 * (sched_lock) protects all run queues, in the spirit of the classic 4BSD
 * sched_lock.  This serializes queue operations but still gives per-CPU
 * locality.  It can later be refined to per-CPU locks.
 *
 * It is compiled only when the kernel config selects "options SCHED_RENUX",
 * so the default ULE scheduler is left untouched.
 */

#include "opt_sched.h"

#include <sys/systm.h>
#include <sys/kdb.h>
#include <sys/kernel.h>
#include <sys/ktr.h>
#include <sys/limits.h>
#include <sys/lock.h>
#include <sys/mutex.h>
#include <sys/proc.h>
#include <sys/resource.h>
#include <sys/resourcevar.h>
#include <sys/runq.h>
#include <sys/sched.h>
#include <sys/smp.h>
#include <sys/sysctl.h>
#include <sys/turnstile.h>
#include <sys/vmmeter.h>
#include <sys/cpuset.h>

#include <machine/cpu.h>
#include <machine/smp.h>

#define	KTR_RENUX	0

/* Thread time slice is over; force a reschedule at the next switch. */
#define	TDF_SLICEEND	TDF_SCHED2

/*
 * Per-thread scheduler data.  Allocated directly after struct thread
 * (see td_get_sched()).
 */
struct td_sched {
	struct runq	*ts_runq;	/* Run queue the thread is on. */
	int		ts_cpu;		/* CPU it is on, or last ran on. */
	u_int		ts_slice;	/* Ticks of slice remaining. */
	u_int		ts_estcpu;	/* Simple CPU usage estimate. */
	u_int		ts_flags;	/* TSF_* flags. */
};
#define	TSF_BOUND	0x0001		/* Thread may not migrate. */

#define	THREAD_CAN_MIGRATE(td)	((td)->td_pinned == 0)
#define	THREAD_CAN_SCHED(td, cpu)	\
    CPU_ISSET((cpu), &(td)->td_cpuset->cs_mask)

/* Simple cap on the CPU usage estimate. */
#define	ESTCPULIM(e)	((e) < 100 ? (e) : 100)

/*
 * Global scheduler state.
 *
 * sched_lock protects every per-CPU run queue and the load counters.
 * Every thread uses sched_lock as its td_lock, so thread_lock() always
 * acquires it.
 */
static struct mtx		sched_lock;
static struct runq		runq_pcpu[MAXCPU];
static int			runq_length[MAXCPU];
static int			sched_renux_total;	/* Total runnable. */

/* Tunables. */
static int sched_renux_slice = 5;	/* Ticks per time slice. */
static int sched_renux_affinity_enable = 1;	/* Strong affinity on by default. */
SYSCTL_INT(_kern_sched, OID_AUTO, renux_slice, CTLFLAG_RW,
    &sched_renux_slice, 0, "Renux scheduler time slice in ticks");
SYSCTL_INT(_kern_sched, OID_AUTO, renux_affinity, CTLFLAG_RW,
    &sched_renux_affinity_enable, 0, "Renux scheduler CPU affinity");

#define	RENUX_LOCK()	mtx_lock_spin(&sched_lock)
#define	RENUX_UNLOCK()	mtx_unlock_spin(&sched_lock)
#define	RENUX_LOCK_ASSERT()	mtx_assert(&sched_lock, MA_OWNED)

static void
sched_renux_load_add(void)
{
	sched_renux_total++;
}

static void
sched_renux_load_rem(void)
{
	sched_renux_total--;
}

/*
 * Find the best CPU for a thread: its previous CPU when the affinity and
 * the cpuset allow it, otherwise the least loaded CPU in the cpuset.
 */
static void
sched_renux_fork(struct thread *td, struct thread *childtd);
static void
sched_renux_fork_thread(struct thread *td, struct thread *childtd);
static void
sched_renux_exit_thread(struct thread *td, struct thread *child);

static int
sched_renux_pickcpu(struct thread *td)
{
	struct td_sched *ts;
	int cpu, cur, best, bestload;

	ts = td_get_sched(td);
	cur = PCPU_GET(cpuid);

	if (!smp_started)
		return (cur);

	if ((ts->ts_flags & TSF_BOUND) != 0)
		return (ts->ts_cpu);

	cpu = ts->ts_cpu;
	if (cpu >= 0 && THREAD_CAN_SCHED(td, cpu) &&
	    (runq_length[cpu] == 0 || sched_renux_affinity_enable == 0 ||
	     (cpu == cur && runq_length[cpu] < 2)))
		return (cpu);

	best = cur;
	bestload = INT_MAX;
	for (cpu = 0; cpu < mp_ncpus; cpu++) {
		if (!THREAD_CAN_SCHED(td, cpu))
			continue;
		if (runq_length[cpu] < bestload) {
			best = cpu;
			bestload = runq_length[cpu];
		}
	}
	return (best);
}

/*
 * Wake / preempt the destination CPU if needed.
 */
static void
sched_renux_kick(struct thread *td, int cpu)
{
	struct thread *ctd;
	int cur;

	cur = PCPU_GET(cpuid);
	if (cpu != cur) {
#ifdef SMP
		ipi_cpu(cpu, IPI_PREEMPT);
#endif
		return;
	}
	ctd = curthread;
	if (TD_IS_IDLETHREAD(ctd))
		return;
	if (td->td_priority < ctd->td_priority) {
		ctd->td_owepreempt = 1;
		ast_sched_locked(ctd, TDA_SCHED);
	}
}

static void
sched_renux_add(struct thread *td, int flags)
{
	struct td_sched *ts;
	int cpu;

	THREAD_LOCK_ASSERT(td, MA_OWNED);
	KASSERT((td->td_inhibitors == 0),
	    ("sched_add: trying to run inhibited thread"));
	KASSERT((TD_CAN_RUN(td) || TD_IS_RUNNING(td)),
	    ("sched_add: bad thread state"));
	KASSERT(td->td_flags & TDF_INMEM,
	    ("sched_add: thread swapped out"));

	KTR_STATE2(KTR_RENUX, "thread", sched_tdname(td), "runq add",
	    "prio:%d", td->td_priority, KTR_ATTR_LINKED, sched_tdname(curthread));

	ts = td_get_sched(td);
	cpu = sched_renux_pickcpu(td);
	if (td->td_lock != &sched_lock) {
		mtx_lock_spin(&sched_lock);
		if ((flags & SRQ_HOLD) != 0)
			td->td_lock = &sched_lock;
		else
			thread_lock_set(td, &sched_lock);
	}
	ts->ts_cpu = cpu;
	ts->ts_runq = &runq_pcpu[cpu];
	runq_length[cpu]++;
	runq_add(ts->ts_runq, td, flags);
	TD_SET_RUNQ(td);
	if ((td->td_flags & TDF_NOLOAD) == 0)
		sched_renux_load_add();
	RENUX_LOCK_ASSERT();

	if ((flags & SRQ_YIELDING) == 0)
		sched_renux_kick(td, cpu);
	if ((flags & SRQ_HOLDTD) == 0)
		thread_unlock(td);
}

static void
sched_renux_rem(struct thread *td)
{
	struct td_sched *ts;

	ts = td_get_sched(td);
	KASSERT(TD_ON_RUNQ(td), ("sched_rem: thread not on run queue"));
	RENUX_LOCK_ASSERT();
	KTR_STATE1(KTR_RENUX, "thread", sched_tdname(td), "runq rem",
	    "prio:%d", td->td_priority);

	if (ts->ts_runq >= &runq_pcpu[0] &&
	    ts->ts_runq < &runq_pcpu[MAXCPU])
		runq_length[ts->ts_runq - &runq_pcpu[0]]--;
	runq_remove(ts->ts_runq, td);
	TD_SET_CAN_RUN(td);
	if ((td->td_flags & TDF_NOLOAD) == 0)
		sched_renux_load_rem();
}

/*
 * Pick the next thread to run on this CPU.  Prefer this CPU's run queue;
 * if it is empty, steal the highest priority thread from the most loaded
 * CPU (lazy migration).
 */
static struct thread *
sched_renux_choose(void)
{
	struct thread *td;
	struct runq *rq;
	struct td_sched *ts;
	int cpu, best, bestload, i;

	RENUX_LOCK_ASSERT();
	cpu = PCPU_GET(cpuid);
	rq = &runq_pcpu[cpu];
	td = runq_choose(rq);
	if (td != NULL) {
		runq_length[cpu]--;
		runq_remove(rq, td);
		ts = td_get_sched(td);
		ts->ts_cpu = cpu;
		ts->ts_runq = rq;
		return (td);
	}

	if (!smp_started)
		return (PCPU_GET(idlethread));

	best = -1;
	bestload = 0;
	for (i = 0; i < mp_ncpus; i++) {
		if (i == cpu)
			continue;
		if (runq_length[i] > bestload) {
			best = i;
			bestload = runq_length[i];
		}
	}
	if (best < 0)
		return (PCPU_GET(idlethread));
	td = runq_choose(&runq_pcpu[best]);
	if (td == NULL)
		return (PCPU_GET(idlethread));
	runq_length[best]--;
	runq_remove(&runq_pcpu[best], td);
	ts = td_get_sched(td);
	ts->ts_cpu = cpu;
	ts->ts_runq = &runq_pcpu[cpu];
	return (td);
}

static void
sched_renux_clock(struct thread *td, int cnt)
{
	struct td_sched *ts;

	THREAD_LOCK_ASSERT(td, MA_OWNED);
	ts = td_get_sched(td);
	for (; cnt > 0; cnt--) {
		ts->ts_estcpu++;
		if (!TD_IS_IDLETHREAD(td) && --ts->ts_slice <= 0) {
			ts->ts_slice = sched_renux_slice;
			if (PRI_BASE(td->td_pri_class) == PRI_ITHD) {
				td->td_owepreempt = 1;
			} else {
				td->td_flags |= TDF_SLICEEND;
				ast_sched_locked(td, TDA_SCHED);
			}
		}
	}
}

static void
sched_renux_sswitch(struct thread *td, int flags)
{
	struct thread *newtd;
	struct mtx *tmtx;
	int preempted;

	tmtx = &sched_lock;

	THREAD_LOCK_ASSERT(td, MA_OWNED);

	td->td_lastcpu = td->td_oncpu;
	preempted = (td->td_flags & TDF_SLICEEND) == 0 &&
	    (flags & SW_PREEMPT) != 0;
	td->td_flags &= ~TDF_SLICEEND;
	ast_unsched_locked(td, TDA_SCHED);
	td->td_owepreempt = 0;
	td->td_oncpu = NOCPU;

	if (TD_IS_IDLETHREAD(td)) {
		TD_SET_CAN_RUN(td);
	} else if (TD_IS_RUNNING(td)) {
		sched_renux_add(td, SRQ_HOLDTD | SRQ_OURSELF | SRQ_YIELDING |
		    (preempted ? SRQ_PREEMPTED : 0));
	}

	if (td->td_lock != &sched_lock) {
		mtx_lock_spin(&sched_lock);
		tmtx = thread_lock_block(td);
		mtx_unlock_spin(tmtx);
	}
	MPASS(td->td_lock == &sched_lock);

	if ((td->td_flags & TDF_NOLOAD) == 0)
		sched_renux_load_rem();

	newtd = choosethread();
	MPASS(newtd->td_lock == &sched_lock);

	KTR_STATE1(KTR_RENUX, "thread", sched_tdname(td), "switched out",
	    "prio:%d", td->td_priority);

	if (td != newtd) {
		td->td_oncpu = NOCPU;
		cpu_switch(td, newtd, tmtx);
	} else {
		td->td_lock = &sched_lock;
	}
	sched_lock.mtx_lock = (uintptr_t)td;
	td->td_oncpu = PCPU_GET(cpuid);
	spinlock_enter();
	mtx_unlock_spin(&sched_lock);
	KASSERT(curthread->td_md.md_spinlock_count == 1,
	    ("invalid count %d", curthread->td_md.md_spinlock_count));

	KTR_STATE1(KTR_RENUX, "thread", sched_tdname(td), "running",
	    "prio:%d", td->td_priority);
}

static void
sched_renux_idletd(void *dummy)
{
	for (;;) {
		mtx_assert(&Giant, MA_NOTOWNED);
		while (!sched_runnable()) {
			cpu_idle(false);
		}
		RENUX_LOCK();
		mi_switch(SW_VOL | SWT_IDLE);
	}
}

static void
sched_renux_throw_tail(struct thread *td)
{
	struct thread *newtd;

	RENUX_LOCK_ASSERT();
	KASSERT(curthread->td_md.md_spinlock_count == 1, ("invalid count"));

	newtd = choosethread();
	cpu_throw(td, newtd);	/* doesn't return */
}

static void
sched_renux_ap_entry(void)
{
	RENUX_LOCK();
	spinlock_exit();
	PCPU_SET(switchtime, cpu_ticks());
	PCPU_SET(switchticks, ticks);
	sched_renux_throw_tail(NULL);
}

static void
sched_renux_throw(struct thread *td)
{
	MPASS(td != NULL);
	MPASS(td->td_lock == &sched_lock);
	td->td_lastcpu = td->td_oncpu;
	td->td_oncpu = NOCPU;
	sched_renux_throw_tail(td);
}

static void
sched_renux_fork_exit(struct thread *td)
{
	td->td_oncpu = PCPU_GET(cpuid);
	THREAD_LOCK_ASSERT(td, MA_OWNED | MA_NOTRECURSED);
	KTR_STATE1(KTR_RENUX, "thread", sched_tdname(td), "running",
	    "prio:%d", td->td_priority);
}

static void
sched_renux_fork(struct thread *td, struct thread *childtd)
{
	sched_renux_fork_thread(td, childtd);
}

static void
sched_renux_fork_thread(struct thread *td, struct thread *childtd)
{
	struct td_sched *ts, *tsc;

	childtd->td_oncpu = NOCPU;
	childtd->td_lastcpu = NOCPU;
	childtd->td_lock = &sched_lock;
	childtd->td_cpuset = cpuset_ref(td->td_cpuset);
	childtd->td_domain.dr_policy = td->td_cpuset->cs_domain;
	childtd->td_priority = childtd->td_base_pri;
	ts = td_get_sched(childtd);
	bzero(ts, sizeof(*ts));
	tsc = td_get_sched(td);
	ts->ts_cpu = tsc->ts_cpu;
	ts->ts_estcpu = tsc->ts_estcpu;
	ts->ts_slice = sched_renux_slice;
}

static void
sched_renux_exit(struct proc *p, struct thread *childtd)
{
	PROC_LOCK_ASSERT(p, MA_OWNED);
	sched_renux_exit_thread(FIRST_THREAD_IN_PROC(p), childtd);
}

static void
sched_renux_exit_thread(struct thread *td, struct thread *child)
{
	thread_lock(td);
	td_get_sched(td)->ts_estcpu =
	    ESTCPULIM(td_get_sched(td)->ts_estcpu +
	    td_get_sched(child)->ts_estcpu);
	thread_unlock(td);
	thread_lock(child);
	if ((child->td_flags & TDF_NOLOAD) == 0)
		sched_renux_load_rem();
	thread_unlock(child);
}

static void
sched_renux_nice(struct proc *p, int nice)
{
	PROC_LOCK_ASSERT(p, MA_OWNED);
	p->p_nice = nice;
}

static void
sched_renux_prio(struct thread *td, u_char prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td->td_priority = prio;
}

static void
sched_renux_user_prio(struct thread *td, u_char prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td->td_user_pri = prio;
	if (PRI_BASE(td->td_pri_class) == PRI_TIMESHARE)
		sched_renux_prio(td, prio);
}

static void
sched_renux_ithread_prio(struct thread *td, u_char prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td->td_priority = prio;
}

static void
sched_renux_lend_prio(struct thread *td, u_char prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	if (td->td_priority > prio) {
		td->td_priority = prio;
		td->td_flags |= TDF_BORROWING;
		KTR_STATE1(KTR_RENUX, "thread", sched_tdname(td),
		    "lend prio", "prio:%d", prio);
	}
}

static void
sched_renux_unlend_prio(struct thread *td, u_char prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td->td_flags &= ~TDF_BORROWING;
	sched_renux_prio(td, prio);
}

static void
sched_renux_lend_user_prio(struct thread *td, u_char pri)
{
	sched_renux_lend_prio(td, pri);
	td->td_user_pri = pri;
}

static void
sched_renux_lend_user_prio_cond(struct thread *td, u_char pri)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	if (td->td_user_pri > pri)
		sched_renux_lend_user_prio(td, pri);
}

static void
sched_renux_userret_slowpath(struct thread *td)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	sched_renux_prio(td, td->td_user_pri);
}

static void
sched_renux_sleep(struct thread *td, int prio)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	if (prio)
		sched_renux_prio(td, prio);
}

static void
sched_renux_wakeup(struct thread *td, int srqflags)
{
	sched_renux_add(td, srqflags);
}

static void
sched_renux_preempt(struct thread *td)
{
	struct thread *ctd;

	ctd = curthread;
	thread_lock(ctd);
	ctd->td_owepreempt = 1;
	ast_sched_locked(ctd, TDA_SCHED);
	thread_unlock(ctd);
}

static void
sched_renux_relinquish(struct thread *td)
{
	mi_switch(SW_INVOL | SWT_RELINQUISH);
}

static void
sched_renux_affinity(struct thread *td)
{
	struct td_sched *ts;

	ts = td_get_sched(td);
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	if (!THREAD_CAN_SCHED(td, ts->ts_cpu) || ts->ts_cpu < 0)
		ts->ts_cpu = PCPU_GET(cpuid);
}

static void
sched_renux_bind(struct thread *td, int cpu)
{
	struct td_sched *ts;

	ts = td_get_sched(td);
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	ts->ts_flags |= TSF_BOUND;
	ts->ts_cpu = cpu;
}

static void
sched_renux_unbind(struct thread *td)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td_get_sched(td)->ts_flags &= ~TSF_BOUND;
}

static int
sched_renux_is_bound(struct thread *td)
{
	return ((td_get_sched(td)->ts_flags & TSF_BOUND) != 0);
}

static void
sched_renux_class(struct thread *td, int class)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	td->td_pri_class = class;
}

static u_int
sched_renux_estcpu(struct thread *td)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	return (td_get_sched(td)->ts_estcpu);
}

static fixpt_t
sched_renux_pctcpu(struct thread *td)
{
	THREAD_LOCK_ASSERT(td, MA_OWNED);
	return (0);
}

static int
sched_renux_load(void)
{
	return (sched_renux_total);
}

static int
sched_renux_rr_interval(void)
{
	return (hz / 10);
}

static bool
sched_renux_runnable(void)
{
	int cpu, i;

	if (runq_not_empty(&runq_pcpu[PCPU_GET(cpuid)]))
		return (true);
	if (smp_started && sched_renux_total > 0) {
		for (i = 0; i < mp_ncpus; i++) {
			cpu = i;
			if (runq_not_empty(&runq_pcpu[cpu]))
				return (true);
		}
	}
	return (false);
}

static int
sched_renux_sizeof_proc(void)
{
	return (sizeof(struct proc));
}

static int
sched_renux_sizeof_thread(void)
{
	return (sizeof(struct thread) + sizeof(struct td_sched));
}

static char *
sched_renux_tdname(struct thread *td)
{
#ifdef KTR
	struct td_sched *ts = td_get_sched(td);
	static char buf[TS_NAME_LEN];

	snprintf(buf, sizeof(buf), "%s td %p", td->td_name, td);
	return (buf);
#else
	return ("??");
#endif
}

static void
sched_renux_clear_tdname(struct thread *td)
{
#ifdef KTR
	td->td_name[0] = '\0';
#endif
}

static bool
sched_renux_do_timer_accounting(void)
{
	return (false);
}

static int
sched_renux_find_l2_neighbor(int cpuid)
{
	return (-1);
}

static void
sched_renux_init(void)
{
	int i;

	mtx_init(&sched_lock, "sched lock", NULL, MTX_SPIN);
	thread0.td_lock = &sched_lock;
	for (i = 0; i < MAXCPU; i++) {
		runq_init(&runq_pcpu[i]);
		runq_length[i] = 0;
	}
	sched_renux_total = 0;
}

static void
sched_renux_init_ap(void)
{
}

static void
sched_renux_setup(void)
{
}

static void
sched_renux_initticks(void)
{
}

static void
sched_renux_schedcpu(void)
{
}

/*
 * The scheduler instance registered in the linker set.  The shim
 * (sched_shim.c) dispatches the generic sched_*() calls to this instance.
 */
struct sched_instance sched_renux_instance = {
#define	SLOT(name) .name = sched_renux_##name
	SLOT(load),
	SLOT(rr_interval),
	SLOT(runnable),
	SLOT(exit),
	SLOT(fork),
	SLOT(fork_exit),
	SLOT(class),
	SLOT(nice),
	SLOT(ap_entry),
	SLOT(exit_thread),
	SLOT(estcpu),
	SLOT(fork_thread),
	SLOT(ithread_prio),
	SLOT(lend_prio),
	SLOT(lend_user_prio),
	SLOT(lend_user_prio_cond),
	SLOT(pctcpu),
	SLOT(prio),
	SLOT(sleep),
	SLOT(sswitch),
	SLOT(throw),
	SLOT(unlend_prio),
	SLOT(user_prio),
	SLOT(userret_slowpath),
	SLOT(add),
	SLOT(choose),
	SLOT(clock),
	SLOT(idletd),
	SLOT(preempt),
	SLOT(relinquish),
	SLOT(rem),
	SLOT(wakeup),
	SLOT(bind),
	SLOT(unbind),
	SLOT(is_bound),
	SLOT(affinity),
	SLOT(sizeof_proc),
	SLOT(sizeof_thread),
	SLOT(tdname),
	SLOT(clear_tdname),
	SLOT(do_timer_accounting),
	SLOT(find_l2_neighbor),
	SLOT(init),
	SLOT(init_ap),
	SLOT(setup),
	SLOT(initticks),
	SLOT(schedcpu),
#undef SLOT
};
DECLARE_SCHEDULER(renux_sched_selector, "RENUX", &sched_renux_instance);
