Copyright (c) 2026 Renan Lucas Vieira Hilário.

# Hacking Renux

Renux is designed to be hacked. It is meant to be understood, modified and
rebuilt by whoever uses it - and, once running, tuned and probed at runtime
without recompiling. This document is a practical guide to both.

The Renux philosophy (see also `DECENTRALIZATION.md`):

- one `build.sh` drives the whole build, no preinstalled toolchain needed;
- machine-dependent code lives under `sys/arch/`, the rest is machine-independent;
- components (kernel, init, libc, userland) can evolve independently;
- the system is tunable and traceable at runtime (sysctl, kld, DTrace, DDB);
- forks and independent efforts are first-class citizens.

---

## 1. Building from source

No FreeBSD host or toolchain is required.

```sh
git clone https://github.com/renuxproject/src.git /usr/src/renux
cd /usr/src/renux

./build.sh build            # world (userland) + kernel
./build.sh kernel=GENERIC   # just the kernel
./build.sh iso              # bootable kernel-only ISO
./build.sh qemu             # boot it in QEMU
```

The object tree lives under `MAKEOBJDIRPREFIX` (default `obj/`).

## 2. Rebuilding after a source change

Edit something, for example `sys/kern/sched_renux.c`, then:

```sh
./build.sh kernel=GENERIC            # rebuild the kernel
./build.sh build worldiso            # full world + live ISO (slow)
```

To build a full live ISO with the whole userland:

```sh
./build.sh build worldiso
```

## 3. Runtime hacking (no recompile)

Once Renux is running you can inspect, tune and extend it live.

### 3.1 sysctl - runtime tuning

Every subsystem can expose `SYSCTL` nodes. `sched_renux` already exposes a
batch of them:

```sh
sysctl kern.sched_renux            # list scheduler tunables
sysctl kern.sched_renux.slice      # read one
sysctl kern.sched_renux.slice=10   # change it live
```

Persistent tunables can also be set from the loader with `loader.conf`, or at
boot via `sysctl.conf`. On the live ISO `/etc` is read-only, so use the
runtime form or `loader.conf` for boot-time values.

### 3.2 kld - kernel modules

Load and unload kernel code without rebuilding the kernel:

```sh
kldload /boot/kernel/dtrace.ko     # load a module
kldstat                            # what is loaded
kldunload dtrace                   # unload it
```

Custom modules can be written, built against the tree, and loaded at runtime.

### 3.3 DTrace - trace and probe the kernel

The GENERIC kernel is built with `KDTRACE_HOOKS` and CTF data. Enable DTrace:

```sh
kldload dtraceall                  # or: dtrace fbt sdt ...
```

Then trace anything without recompiling:

```sh
dtruss -c ls                       # syscall counts
dtruss -e ls                       # syscall trace of a command
dtrace -n 'fbt::sched_*:entry { @[probefunc] = count(); }'
dtrace -n 'syscall::read:entry { @[execname] = count(); }'
```

`dtrace`, `dtruss`, `lockstat` and `plockstat` ship in `cddl/usr.sbin` and
are part of the world build.

### 3.4 DDB / kgdb - live kernel debugging

The kernel is built with `KDB`, `DDB` and debug symbols.

```sh
sysctl debug.kdb.enter=1            # drop into DDB
# in DDB: bt (backtrace), x/s (examine), trace, show pcpu ...
```

With a debug kernel (`./build.sh kernel.gdb=GENERIC`) you can also attach
kgdb over a serial line or via `netgdb`.

### 3.5 Userland tracing

```sh
truss -f -e open ls                 # trace syscalls
ktrace -di ls; kdump                # ktrace session
```

## 4. Writing your first kernel module

Here is a minimal module that creates a sysctl you can poke from userland.

```c
#include <sys/param.h>
#include <sys/kernel.h>
#include <sys/module.h>
#include <sys/sysctl.h>

static int renux_hack_value = 0;
SYSCTL_INT(_kern, OID_AUTO, renux_hack, CTLFLAG_RW,
    &renux_hack_value, 0, "my runtime hack");

static int
renux_hack_modevent(module_t mod, int type, void *unused)
{
	return (0);
}

static moduledata_t renux_hack_mod = {
	"renux_hack", renux_hack_modevent, NULL
};
DECLARE_MODULE(renux_hack, renux_hack_mod, SI_SUB_DRIVERS, SI_ORDER_ANY);
```

Build and load it (a module under `sys/modules/` is built as part of
`buildkernel`; the module framework compiles it and installs it to
`/boot/kernel/`):

```sh
kldload /boot/kernel/renux_hack.ko
sysctl kern.renux_hack=42
```

## 5. Where the interesting code lives

- `sys/arch/amd64/` - machine-dependent code (per-arch, kept separate).
- `sys/kern/sched_renux.c` - the Renux scheduler (ULE-derived).
- `sys/kern/renux_kern_malloc.c` - the Renux memory allocator.
- `sys/fs/`, `sys/dev/`, `sys/net/` - filesystems, drivers, networking.
- `stand/` - the boot loader.
- `usr.sbin/renuxinstaller/` - the installer.
- `usr.sbin/bsdinstall/` - the FreeBSD-derived install framework.

## 6. Testing your changes

```sh
./build.sh kernel=GENERIC
./build.sh iso            # kernel-only bootable image
./build.sh qemu           # boot it
```

For the full live environment with everything above:

```sh
./build.sh build worldiso
```
