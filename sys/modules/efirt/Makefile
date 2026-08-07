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

.if exists(${SRCTOP}/sys/arch/${MACHINE})
MACHINE_SRC=	${SRCTOP}/sys/arch/${MACHINE}
.else
MACHINE_SRC=	${SRCTOP}/sys/${MACHINE}
.endif
.PATH: ${MACHINE_SRC}/${MACHINE}
.PATH: ${SRCTOP}/sys/dev/efidev

KMOD=	efirt
SRCS=	efirt.c efirt_machdep.c efidev.c
SRCS+=	efirtc.c
SRCS+=	efirt_support.S
SRCS+=  device_if.h bus_if.h clock_if.h
DPSRCS+= assym.inc

.if ${MACHINE_CPUARCH} == "amd64"
SRCS+=	opt_acpi.h opt_hwpmc_hooks.h opt_kstack_pages.h
.endif

efirt_support.o:	efirt_support.S assym.inc
	${CC} -c -x assembler-with-cpp -DLOCORE ${CFLAGS} \
	    ${.IMPSRC} -o ${.TARGET}

EXPORT_SYMS=	YES

.include <bsd.kmod.mk>
