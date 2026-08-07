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

.if exists(${SRCTOP}/sys/arch/${MACHINE_CPUARCH})
CPUARCH_SRC=	${SRCTOP}/sys/arch/${MACHINE_CPUARCH}
.else
CPUARCH_SRC=	${SRCTOP}/sys/${MACHINE_CPUARCH}
.endif
.PATH:	${SRCTOP}/sys/dev/cpufreq		\
	${CPUARCH_SRC}/cpufreq

KMOD=	cpufreq
SRCS=	ichss.c
SRCS+=	bus_if.h cpufreq_if.h device_if.h pci_if.h

.if ${MACHINE} == "i386" || ${MACHINE} == "amd64"
.PATH:	${SRCTOP}/sys/x86/cpufreq

SRCS+=	acpi_if.h opt_acpi.h
SRCS+=	est.c p4tcc.c powernow.c
SRCS+=	hwpstate_amd.c hwpstate_common.c hwpstate_intel.c
.endif

.if ${MACHINE} == "i386"
SRCS+=	smist.c
.endif

.if ${MACHINE} == "powerpc"
.PATH:	${SRCTOP}/sys/powerpc/cpufreq
SRCS+= dfs.c
.endif

.include <bsd.kmod.mk>
