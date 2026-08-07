/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026 Renux contributors.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */


#include "linux32_assym.h"			/* system definitions */
#include <machine/asmacros.h>			/* miscellaneous asm macros */

#include <arch/amd64/linux32/linux32_syscall.h>	/* system call numbers */

.data

	.globl linux_platform
linux_platform:
	.asciz "i686"

.text
.code32

ENTRY(linux32_vdso_sigcode)
	.cfi_startproc
	.cfi_signal_frame
	.cfi_def_cfa	%esp, LINUX_SIGF_SC
	.cfi_offset	%gs, L_SC_GS
	.cfi_offset	%fs, L_SC_FS
	.cfi_offset	%es, L_SC_ES
	.cfi_offset	%ds, L_SC_DS
	.cfi_offset	%cs, L_SC_CS
	.cfi_offset	%ss, L_SC_SS
#ifdef __clang__
	.cfi_offset	%flags, L_SC_EFLAGS
#else
	.cfi_offset	%eflags, L_SC_EFLAGS
#endif
	.cfi_offset	%edi, L_SC_EDI
	.cfi_offset	%esi, L_SC_ESI
	.cfi_offset	%ebp, L_SC_EBP
	.cfi_offset	%ebx, L_SC_EBX
	.cfi_offset	%edx, L_SC_EDX
	.cfi_offset	%ecx, L_SC_ECX
	.cfi_offset	%eax, L_SC_EAX
	.cfi_offset	%eip, L_SC_EIP
	.cfi_offset	%esp, L_SC_ESP

	movl	%esp, %ebx			/* sigframe for sigreturn */
	call	*%edi				/* call signal handler */
	popl	%eax				/* gcc unwind code need this */
	.cfi_def_cfa	%esp, LINUX_SIGF_SC-4
	movl	$LINUX32_SYS_linux_sigreturn, %eax
	int	$0x80
0:	jmp	0b
	.cfi_endproc
END(linux32_vdso_sigcode)


ENTRY(linux32_vdso_rt_sigcode)
	.cfi_startproc
	.cfi_signal_frame
	.cfi_def_cfa	%esp, LINUX_RT_SIGF_UC + LINUX_RT_SIGF_SC
	.cfi_offset	%gs, L_SC_GS
	.cfi_offset	%fs, L_SC_FS
	.cfi_offset	%es, L_SC_ES
	.cfi_offset	%ds, L_SC_DS
	.cfi_offset	%cs, L_SC_CS
	.cfi_offset	%ss, L_SC_SS
#ifdef __clang__
	.cfi_offset	%flags, L_SC_EFLAGS
#else
	.cfi_offset	%eflags, L_SC_EFLAGS
#endif
	.cfi_offset	%edi, L_SC_EDI
	.cfi_offset	%esi, L_SC_ESI
	.cfi_offset	%ebp, L_SC_EBP
	.cfi_offset	%ebx, L_SC_EBX
	.cfi_offset	%edx, L_SC_EDX
	.cfi_offset	%ecx, L_SC_ECX
	.cfi_offset	%eax, L_SC_EAX
	.cfi_offset	%eip, L_SC_EIP
	.cfi_offset	%esp, L_SC_ESP

	leal	LINUX_RT_SIGF_UC(%esp), %ebx	/* linux ucontext for rt_sigreturn */
	call	*%edi				/* call signal handler */
	movl	$LINUX32_SYS_linux_rt_sigreturn, %eax
	int	$0x80
0:	jmp	0b
	.cfi_endproc
END(linux32_vdso_rt_sigcode)

ENTRY(__kernel_sigreturn)
	.cfi_startproc
	.cfi_signal_frame
	movl	%esp, %ebx			/* sigframe for sigreturn */
	call	*%edi				/* call signal handler */
	popl	%eax				/* gcc unwind code need this */
	movl	$LINUX32_SYS_linux_sigreturn, %eax
	int	$0x80
0:	jmp	0b
	.cfi_endproc
END(__kernel_sigreturn)

ENTRY(__kernel_rt_sigreturn)
	.cfi_startproc
	.cfi_signal_frame
	leal	LINUX_RT_SIGF_UC(%esp), %ebx	/* linux ucontext for rt_sigreturn */
	call	*%edi				/* call signal handler */
	movl	$LINUX32_SYS_linux_rt_sigreturn, %eax
	int	$0x80
0:	jmp	0b
	.cfi_endproc
END(__kernel_rt_sigreturn)

ENTRY(__kernel_vsyscall)
	.cfi_startproc
	int $0x80
	ret
	.cfi_endproc
END(__kernel_vsyscall)

#if 0
	.section .note.Linux, "a",@note
	.long 2f - 1f		/* namesz */
	.balign 4
	.long 4f - 3f		/* descsz */
	.long 0
1:
	.asciz "Linux"
2:
	.balign 4
3:
	.long LINUX_VERSION_CODE
4:
	.balign 4
	.previous
#endif
