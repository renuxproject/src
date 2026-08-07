# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Renux contributors.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

.include <kmod.opts.mk>

.if exists(${SRCTOP}/sys/arch/${MACHINE})
MACHINE_SRC=	${SRCTOP}/sys/arch/${MACHINE}
.else
MACHINE_SRC=	${SRCTOP}/sys/${MACHINE}
.endif

KMOD=	vmm

.if ${MACHINE_CPUARCH} == "amd64"
.endif

SRCS+=	acpi_if.h bus_if.h device_if.h pci_if.h pcib_if.h vnode_if.h

CFLAGS+= -DVMM_KEEP_STATS
CFLAGS+= -I${MACHINE_SRC}/vmm

# generic vmm support
.PATH: ${SRCTOP}/sys/dev/vmm ${MACHINE_SRC}/vmm

SRCS+=	vmm.c			\
	vmm_dev.c		\
	vmm_dev_machdep.c	\
	vmm_instruction_emul.c	\
	vmm_mem.c		\
	vmm_stat.c		\
	vmm_vm.c

.if ${MACHINE_CPUARCH} == "aarch64"
CFLAGS+= -I${MACHINE_SRC}/vmm/io
DPSRCS+=	assym.inc

# TODO: Add the new EL2 code
SRCS+=	vmm_arm64.c \
	vmm_reset.c \
	vmm_call.S \
	vmm_handlers.c \
	vmm_mmu.c \
	vmm_vhe_exception.S \
	vmm_vhe.c \
	vmm_hyp_el2.S

.PATH: ${MACHINE_SRC}/vmm/io
SRCS+=	vgic.c \
	vgic_if.h \
	vgic_if.c \
	vgic_v3.c \
	vtimer.c

CLEANFILES+=	vmm_nvhe_exception.o vmm_nvhe.o

CLEANFILES+=	vmm_hyp_blob.elf.full
CLEANFILES+=	vmm_hyp_blob.elf vmm_hyp_blob.bin

vmm_nvhe_exception.o: vmm_nvhe_exception.S vmm_hyp_exception.S
	${CC} -c -x assembler-with-cpp -DLOCORE \
	    ${NOSAN_CFLAGS:N-mbranch-protection*} ${.IMPSRC} -o ${.TARGET} -fpie

vmm_nvhe.o: vmm_nvhe.c vmm_hyp.c
	${CC} -c ${NOSAN_CFLAGS:N-mbranch-protection*} ${.IMPSRC} \
	    -o ${.TARGET} -fpie

vmm_hyp_blob.elf.full:	vmm_nvhe_exception.o vmm_nvhe.o
	${LD} -m ${LD_EMULATION} -Bdynamic -L ${SYSDIR}/conf -T ${SYSDIR}/conf/ldscript.arm64 \
	    ${_LDFLAGS:N-zbti-report*} --no-warn-mismatch --warn-common --export-dynamic \
	    --dynamic-linker /red/herring -X -o ${.TARGET} ${.ALLSRC} \
	    --defsym=_start='0x0' --defsym=text_start='0x0'

vmm_hyp_blob.elf:	vmm_hyp_blob.elf.full
	${OBJCOPY} --strip-debug ${.ALLSRC} ${.TARGET}

vmm_hyp_blob.bin:	vmm_hyp_blob.elf
	${OBJCOPY} --output-target=binary ${.ALLSRC} ${.TARGET}

vmm_hyp_el2.o:	vmm_hyp_blob.bin

.elif ${MACHINE_CPUARCH} == "amd64"
CFLAGS+= -I${MACHINE_SRC}/vmm/io
DPSRCS+=	vmx_assym.h svm_assym.h
DPSRCS+=	vmx_genassym.c svm_genassym.c offset.inc

CFLAGS+= -I${SRCTOP}/sys/arch/amd64/vmm/intel
CFLAGS+= -I${SRCTOP}/sys/arch/amd64/vmm/amd

SRCS+=	opt_acpi.h		\
	opt_bhyve_snapshot.h	\
	opt_ddb.h

SRCS+=	vmm_host.c	\
	vmm_ioport.c	\
	vmm_lapic.c	\
	vmm_mem_machdep.c \
	vmm_util.c	\
	x86.c

.PATH: ${MACHINE_SRC}/vmm/io
SRCS+=	iommu.c		\
	ppt.c           \
	vatpic.c	\
	vatpit.c	\
	vhpet.c		\
	vioapic.c	\
	vlapic.c	\
	vpmtmr.c	\
	vrtc.c

# intel-specific files
.PATH: ${SRCTOP}/sys/arch/amd64/vmm/intel
SRCS+=	ept.c		\
	vmcs.c		\
	vmx_msr.c	\
	vmx_support.S	\
	vmx.c		\
	vtd.c

# amd-specific files
.PATH: ${SRCTOP}/sys/arch/amd64/vmm/amd
SRCS+=	vmcb.c		\
	amdviiommu.c	\
	ivhd_if.c	\
	ivhd_if.h	\
	svm.c		\
	svm_support.S	\
	npt.c		\
	ivrs_drv.c	\
	amdvi_hw.c	\
	svm_msr.c

SRCS.BHYVE_SNAPSHOT=	vmm_snapshot.c

CLEANFILES+=	vmx_assym.h vmx_genassym.o svm_assym.h svm_genassym.o

OBJS_DEPEND_GUESS.vmx_support.o+= vmx_assym.h
OBJS_DEPEND_GUESS.svm_support.o+= svm_assym.h

vmx_assym.h:    vmx_genassym.o
	sh ${SYSDIR}/kern/genassym.sh vmx_genassym.o > ${.TARGET}

svm_assym.h:    svm_genassym.o
	sh ${SYSDIR}/kern/genassym.sh svm_genassym.o > ${.TARGET}

vmx_support.o:
	${CC} -c -x assembler-with-cpp -DLOCORE ${CFLAGS} \
	    ${.IMPSRC} -o ${.TARGET}

svm_support.o:
	${CC} -c -x assembler-with-cpp -DLOCORE ${CFLAGS} \
	    ${.IMPSRC} -o ${.TARGET}

hyp_genassym.o: offset.inc
	${CC} -c ${NOSAN_CFLAGS:N-flto*:N-fno-common} -fcommon ${.IMPSRC}

vmx_genassym.o: offset.inc
	${CC} -c ${NOSAN_CFLAGS:N-flto*:N-fno-common} -fcommon ${.IMPSRC}

svm_genassym.o: offset.inc
	${CC} -c ${NOSAN_CFLAGS:N-flto*:N-fno-common} -fcommon ${.IMPSRC}

.elif ${MACHINE_CPUARCH} == "riscv"

SRCS+=	vmm_aplic.c	\
	vmm_fence.c	\
	vmm_riscv.c	\
	vmm_sbi.c	\
	vmm_switch.S	\
	vmm_vtimer.c

.endif

.include <bsd.kmod.mk>
