#! /usr/bin/env sh
#	$Id$
#
# Renux build.sh -- adapted from NetBSD's build.sh
#
# Copyright (c) 2026 Renux contributors.
#	$NetBSD: build.sh,v 1.405 2026/08/01 20:14:38 thorpej Exp $
#
# This script is derived from the NetBSD build.sh, and is used to build
# or cross-build Renux (a Unix operating system with a NetBSD-style build)
# on any Unix host: FreeBSD, Linux, NetBSD, OpenBSD, DragonFly, macOS.
#
# On hosts other than FreeBSD, all world/kernel building is delegated to the
# official cross-build driver ${SRCDIR}/tools/build/make.py, which
# bootstraps bmake from this source and infers the cross-compiler
# (clang/lld).  No preinstalled FreeBSD host or toolchain is required.
#

#
# {{{ Begin shell feature tests.
#
# We try to determine whether or not this script is being run under
# a shell that supports the features that we use. If not, we try to
# re-exec the script under another shell. If we can't find another
# suitable shell, then we show a message and exit.
#

errmsg=			# error message, if not empty
shelltest=false		# if true, exit after testing the shell
re_exec_allowed=true	# if true, we may exec under another shell

case "$1" in
--shelltest)
    shelltest=true
    re_exec_allowed=false
    shift
    ;;
--no-re-exec)
    re_exec_allowed=false
    shift
    ;;
esac

if test -z "$errmsg"
then
    if ( eval '! false' ) >/dev/null 2>&1
    then
	:
    else
	errmsg='Shell does not support "!".'
    fi
fi

if test -z "$errmsg"	# functions
then
    if ! ( eval 'somefunction() { : ; }' ) >/dev/null 2>&1
    then
	errmsg='Shell does not support functions.'
    fi
fi

if test -z "$errmsg"	# the "local" keyword
then
    if ! (
	eval 'f() { local v=2; }; v=1; f && test x"$v" = x1'
    ) >/dev/null 2>&1
    then
	errmsg='Shell does not support the "local" keyword in functions.'
    fi
fi

if test -z "$errmsg"	# standard parameter expansion
then
    if ! (
	eval 'var=a/b/c ;
	      test x"${var#*/};${var##*/};${var%/*};${var%%/*}" = \
		   x"b/c;c;a/b;a" ;'
    ) >/dev/null 2>&1
    then
	errmsg='Shell does not support "${var%suffix}" or "${var#prefix}".'
    fi
fi

if test -z "$errmsg"	# getopts/getopt
then
    if ! ( eval 'type getopts || type getopt' ) >/dev/null 2>&1
    then
	errmsg='Shell does not support getopts or getopt.'
    fi
fi

if "$shelltest"
then
    if test -n "$errmsg"
    then
	echo >&2 "$0: $errmsg"
	exit 1
    else
	exit 0
    fi
fi

if test -n "$errmsg"
then
    if "$re_exec_allowed"
    then
	for othershell in \
	    "${HOST_SH}" bash zsh dash mksh pdksh ksh
	do
	    test -n "$othershell" || continue
	    if eval 'type "$othershell"' >/dev/null 2>&1 \
		&& $othershell "$0" --shelltest >/dev/null 2>&1
	    then
		echo "$0: $errmsg"
		echo "$0: Retrying under $othershell"
		HOST_SH="$othershell"
		export HOST_SH
		exec $othershell "$0" --no-re-exec "$@"
	    fi
	done
    fi
    cat <<EOF
$0: $errmsg

The Renux build requires a shell that supports modern POSIX features
and the "local" keyword.  Re-run under a suitable shell, or set:

	HOST_SH=/path/to/suitable/shell
	export HOST_SH
	\${HOST_SH} $0 ...
EOF
    exit 1
fi

#
# }}} End shell feature tests.
#

progname=${0##*/}
toppid=$$
results=/dev/null
tab='	'
nl='
'
trap "exit 1" 1 2 3 15

bomb()
{
	cat >&2 <<ERRORMESSAGE

ERROR: $*

*** BUILD ABORTED ***
ERRORMESSAGE
	kill ${toppid}		# in case we were invoked from a subshell
	exit 1
}

# Quote args to make them safe in the shell.
shell_quote()
(
	local result=
	local arg qarg
	LC_COLLATE=C ; export LC_COLLATE
	for arg in "$@"
	do
		case "${arg}" in
		'')
			qarg="''"
			;;
		*[!-./a-zA-Z0-9]*)
			qarg=$(printf "%s\n" "$arg" |
			    ${SED:-sed} -e "s/'/'\\\\''/g" \
				-e "1s/^/'/" -e "\$s/\$/'/" \
				-e "1s/^''//" -e "\$s/''\$//" \
				-e "s/'''/'/g"
			    )
			;;
		*)
			qarg="${arg}"
			;;
		esac
		result="${result}${result:+ }${qarg}"
	done
	printf "%s\n" "$result"
)

statusmsg()
{
	${runcmd} echo "===> $*" | tee -a "${results}"
}

statusmsg2()
{
	local msg

	msg=${1}
	shift

	case "${msg}" in
	??????????*)	msg="${msg}   ";;
	?????*)		msg="${msg}        ";;
	*)		msg="${msg}             ";;
	esac
	statusmsg "${msg}$*"
}

warning()
{
	statusmsg "Warning: $*"
}

find_in_PATH()
{
	local prog="$1"
	local result="${2-$1}"
	local dir
	local IFS=:

	for dir in ${PATH}
	do
		if [ -x "${dir}/${prog}" ]
		then
			result=${dir}/${prog}
			break
		fi
	done
	echo "${result}"
}

# valid_targets -- table of supported Renux targets.
#
# Each line contains a MACHINE and a MACHINE_ARCH pair.  Aliases, and
# a DEFAULT marker for when only MACHINE is given.
#
valid_targets='
MACHINE=amd64 MACHINE_ARCH=amd64 DEFAULT
MACHINE=i386 MACHINE_ARCH=i386 DEFAULT
MACHINE=arm64 MACHINE_ARCH=arm64 ALIAS=aarch64 DEFAULT
MACHINE=armv7 MACHINE_ARCH=armv7 DEFAULT
MACHINE=riscv64 MACHINE_ARCH=riscv64 DEFAULT
MACHINE=powerpc MACHINE_ARCH=powerpc DEFAULT
MACHINE=powerpc64 MACHINE_ARCH=powerpc64 DEFAULT
MACHINE=sparc64 MACHINE_ARCH=sparc64 DEFAULT
'

# getarch -- resolve MACHINE to MACHINE_ARCH.
getarch()
{
	local IFS line match=

	IFS="${nl}"
	for line in ${valid_targets}
	do
		case "${line} " in
		"MACHINE=${MACHINE} MACHINE_ARCH="*)
			match="$line"
			break
			;;
		esac
	done
	[ -n "${match}" ] ||
	    bomb "Unknown target MACHINE: ${MACHINE}"
	MACHINE_ARCH="${match#*MACHINE_ARCH=}"
	MACHINE_ARCH="${MACHINE_ARCH%% *}"
}

# validatearch: check the MACHINE/MACHINE_ARCH pair is supported.
validatearch()
{
	local IFS line found=false

	case "${MACHINE_ARCH}" in
	"" ) bomb "No MACHINE_ARCH provided." \
			"Use 'build.sh -m ${MACHINE} list-arch' to see options" ;;
	esac

	IFS="${nl}"
	for line in ${valid_targets}
	do
		case "${line} " in
		"MACHINE=${MACHINE} MACHINE_ARCH=${MACHINE_ARCH} "*)
			found=true
			break
			;;
		esac
	done
	[ "$found" = true ] ||
	    bomb "MACHINE_ARCH=${MACHINE_ARCH} not supported for MACHINE=${MACHINE}"
}

# listarch -- show the supported target table, optionally narrowed.
listarch()
{
	local machglob="$1" archglob="$2" IFS
	local line found=false

	: "${machglob:=*}"
	: "${archglob:=*}"
	IFS="${nl}"
	for line in ${valid_targets}
	do
		[ -n "${line}" ] || continue
		case "${line}" in
		MACHINE=${machglob}*MACHINE_ARCH=${archglob}*)
			found=true
			echo "${line}"
			;;
		esac
	done
	[ "$found" = true ] || {
		echo >&2 "No match for MACHINE=${machglob} MACHINE_ARCH=${archglob}"
		return 1
	}
	return 0
}

setmakeenv()
{
	eval "$1='$2'; export $1"
}

unsetmakeenv()
{
	eval "unset $1"
}

safe_setmakeenv()
{
	case "$1" in
	*[!A-Za-z0-9_]*)	usage "Bad variable name (-V): '$1'" ;;
	esac
	setmakeenv "$@"
}

safe_unsetmakeenv()
{
	case "$1" in
	[!A-Za-z_]*|*[!A-Za-z0-9_]*)	usage "Bad variable name (-Z): '$1'" ;;
	esac
	eval "unset $1"
}

resolvepath()
{
	local var="$1"
	local val
	eval val=\"\${${var}}\"
	case "${val}" in
	/) ;;
	/*)	val="${val%/}" ;;
	*)	val="${TOP}/${val%/}" ;;
	esac
	eval $var=\"${val}\"
}

# ---------------------------------------------------------------------
# synopsis / help / usage
# ---------------------------------------------------------------------
synopsis()
{
	cat <<_usage_

Usage: ${progname} [options] [operation ...]
       ${progname} ( -h | -? )

_usage_
}

help()
{
	synopsis
	cat <<_usage_
 Build OPERATIONs:
    build               Run "make buildworld" then "make buildkernel".
    world               Run "make buildworld".
    distribution        Run "make distribution".
    release             Run "make release".

 Other OPERATIONs:
    help                Show this help message, and exit.
    clean               Remove the object tree.
    obj                 Create the object tree.
    tools               Build only the build tools (make buildtools).
    update              Update the source tree (git pull --ff-only).
    kernel=CONF         Build kernel with configuration file CONF.
    kernel.gdb=CONF     Build kernel (with kernel.gdb) with CONF.
    kernels             Build all kernels.
    install=IDIR        Install world into IDIR (installworld + installkernel).
    iso                 Build the kernel (if needed), the EFI loader and a
                        UEFI-bootable ISO image.
    bootimage           Build the kernel (if needed), the EFI loader and a
                        bootable GPT+ESP disk image (renux.img).
    qemu                Boot the bootimage in QEMU (graphical by default).
    show-params         Show the build parameters in use.
    list-arch           List the supported architectures and exit.

 Options:
    -a ARCH        Set TARGET_ARCH=ARCH.  [Default: deduced from MACHINE]
    -B BID         Set BUILDID=BID.
    -c COMPILER    Select compiler: clang or gcc.
    -D DEST        Set DESTDIR=DEST.
    -E             Set "expert" mode; disables various safety checks.
    -h             Show this help message, and exit.
    -I IMGDIR      Directory for generated images.  [Default: obj/renux-images]
    -j NJOB        Run up to NJOB parallel make jobs.
    -K             Kernel-only mode: never build world/userland, even if a
                   world-producing operation is requested.
    -M MOBJ        Set obj root directory MOBJ (MAKEOBJDIRPREFIX=MOBJ).
    -m MACH        Set TARGET=MACH (MACHINE), deduce TARGET_ARCH.
    -N NOISY       Set MAKEVERBOSE level (0-4).  [Default: 2]
    -n             Show commands that would be executed, do not run them.
    -O OOBJ        Set object root directory OOBJ (MAKEOBJDIRPREFIX=OOBJ).
    -o             Do not create objdirs at start of build.
    -R RELEASE     Set RELEASEDIR=RELEASE.
    -T TOOLS       Accepted for compatibility (object/tool dir are handled
                   via MAKEOBJDIRPREFIX).
    -U             Build unprivileged (NO_ROOT=yes).
    -u             Incremental build (do not run cleanWorld first).
    -V VAR=[VAL]   Set make variable VAR=[VAL].
    -X X11SRC      Ignored on Renux.
    -x             Ignored on Renux.
    -Z VAR         Unset ("zap") variable VAR.
    -?             Show this help message, and exit.

_usage_
}

usage()
{
	if [ -n "$*" ]
	then
		echo 1>&2 ""
		echo 1>&2 "${progname}: $*"
	fi
	synopsis 1>&2
	exit 1
}

# ---------------------------------------------------------------------
#
# parseoptions
# ---------------------------------------------------------------------
parseoptions()
{
	opts='a:B:c:D:EI:j:KM:m:N:nO:oR:S:T:uUV:w:X:xZ:'
	opt_a=false
	opt_m=false

	if type getopts >/dev/null 2>&1
	then
		getoptcmd='getopts :${opts} opt && opt=-${opt}'
		optargcmd=':'
		optremcmd='shift $((${OPTIND} -1))'
	else
		type getopt >/dev/null 2>&1 || bomb "Need getopts or getopt"
		args="$(getopt $opts $*)"
		[ $? = 0 ] || usage
		set -- $args
		getoptcmd='[ $# -gt 0 ] && opt="$1" && shift'
		optargcmd='OPTARG="$1"; shift'
		optremcmd=':'
	fi

	OPTIND=1
	# shellcheck disable=SC2086
	while eval $getoptcmd
	do
		case "$opt" in
		-a) eval $optargcmd; MACHINE_ARCH="$OPTARG"; opt_a=true ;;
		-B) eval $optargcmd; BUILDID="$OPTARG" ;;
		-c) eval $optargcmd; setmakeenv COMPILER "$OPTARG" ;;
		-D) eval $optargcmd; resolvepath OPTARG; DESTDIR="$OPTARG";
		    export DESTDIR ;;
		-E) do_expertmode=true ;;
		-h) help; exit 0 ;;
		-I) eval $optargcmd; IMAGEDIR="$OPTARG" ;;
		-j) eval $optargcmd; parallel="-j $OPTARG" ;;
		-K) kernel_only=true ;;
		-M) eval $optargcmd; MAKEOBJDIRPREFIX="$OPTARG" ;;
		-m) eval $optargcmd; MACHINE="$OPTARG"; opt_m=true ;;
		-N) eval $optargcmd; setmakeenv MAKEVERBOSE "$OPTARG" ;;
		-n) runcmd=echo ;;
		-O) eval $optargcmd; MAKEOBJDIRPREFIX="$OPTARG" ;;
		-o) MKOBJDIRS=no ;;
		-R) eval $optargcmd; RELEASEDIR="$OPTARG" ;;
		-S) eval $optargcmd; BUILDSEED="$OPTARG" ;;
		-T) eval $optargcmd; TOOLDIR="$OPTARG" ;;
		-u) MKUPDATE=yes ;;
		-U) setmakeenv NO_ROOT yes ;;
		-V) eval $optargcmd
		    case "${OPTARG}" in
		    [a-zA-Z_]*=*) safe_setmakeenv "${OPTARG%%=*}" "${OPTARG#*=}" ;;
		    [a-zA-Z_]*)    safe_setmakeenv "${OPTARG}" "" ;;
		    *) usage "-V argument must be VAR[=VAL]" ;;
		    esac ;;
		-w) eval $optargcmd; WRAPPER="$OPTARG" ;;
		-X) eval $optargcmd; setmakeenv X11SRCDIR "$OPTARG" ;;
		-x) MKX11=yes ;;
		-Z) eval $optargcmd; safe_unsetmakeenv "$OPTARG" ;;
		-\?) help; exit 0 ;;
		--) break ;;
		*) usage "Unknown option ${opt}" ;;
		esac
	done
	eval $optremcmd
	while [ $# -gt 0 ]
	do
		op=$1; shift
		operations="${operations} ${op}"
		case "${op}" in
		help) help; exit 0 ;;
		list-arch) listarch "${MACHINE}" "${MACHINE_ARCH}" ; exit ;;
		build|world|distribution|release|tools|clean|obj|update|\
		show-params|kernels|iso|bootimage|qemu|run)
			;;
		kernel=*|kernel.gdb=*|install=*)
			arg=${op#*=}
			[ -n "${arg}" ] ||
			    bomb "Must supply a name with '${op%%=*}=...'"
			;;
		*) usage "Unknown OPERATION '${op}'" ;;
		esac
		op="$( echo "${op}" | tr -s '.-' '_' )"
		eval do_${op}=true
	done

	[ -n "${operations}" ] || usage "Missing OPERATION to perform"

	# Determine MACHINE and MACHINE_ARCH.
	if [ -z "${MACHINE}" ]
	then
		MACHINE="$(host_tune_m)"
	fi
	if $opt_m && ! $opt_a
	then
		getarch
	fi
	[ -n "${MACHINE_ARCH}" ] || getarch
	validatearch
	# Renux/FreeBSD names:
	TARGET="${MACHINE}"
	TARGET_ARCH="${MACHINE_ARCH}"
	export TARGET TARGET_ARCH
}

# host_tune_m: guess the Renux target (MACHINE) from the host.
host_tune_m()
{
	case "$(uname -m)" in
	x86_64|amd64)	echo amd64 ;;
	i386|i[3-6]86)	echo i386 ;;
	aarch64|arm64)	echo arm64 ;;
	riscv64)	echo riscv64 ;;
	powerpc64)	echo powerpc64 ;;
	powerpc)	echo powerpc ;;
	sparc64)	echo sparc64 ;;
	*)		bomb "Cannot GUESS MACHINE; use -m or -a" ;;
	esac
}

# ---------------------------------------------------------------------
#
# build driver (delegates to make.py)
#
# ---------------------------------------------------------------------
if [ -z "${SRCDIR}" ]
then
	d="$(cd "$(dirname "$0")" && pwd)"
	if [ -f "${d}/Makefile" ] && [ -f "${d}/tools/build/make.py" ]
	then
		SRCDIR="${d}"
	else
		SRCDIR="${d}/src"
	fi
fi
MAKE_PY="${SRCDIR}/tools/build/make.py"
[ -f "${SRCDIR}/Makefile" ] ||
    bomb "source tree not found at ${SRCDIR} (set SRCDIR)"
[ -x "${MAKE_PY}" ] ||
    bomb "make.py not found at ${MAKE_PY}"

# object directory (inside the source tree, like NetBSD's OBJ)
[ -n "${MAKEOBJDIRPREFIX}" ] || MAKEOBJDIRPREFIX="${SRCDIR}/obj"
export MAKEOBJDIRPREFIX

ncpu=
if command -v getconf >/dev/null 2>&1 ; then
	ncpu="$(getconf NPROCESSORS_ONLN 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '')"
fi
: ${auto_parallel="-j ${ncpu:-2}"}

TIMEOUT="${TIMEOUT:-7200}"

# ---------------------------------------------------------------------------
# Auto-provision missing host tools.
#
# Some Unixes lack a few utilities that the FreeBSD build expects in the
# host PATH (e.g. GNU/Linux has no standalone /usr/bin/time, and 'bc' or
# 'hostname' may be absent).  We generate tiny wrappers in a directory we
# control and prepend it to PATH, so no manual PATH tweaking is needed.
# ---------------------------------------------------------------------------
HOST_SHIMS="${HOST_SHIMS:-${MAKEOBJDIRPREFIX}/host-shims}"

provision_host_tool()
{
	local name="$1"
	# 'time' is a shell keyword, so command -v cannot reliably detect it;
	# always provide our self-resolving wrapper for it.
	if [ "${name}" != time ]; then
		command -v "${name}" >/dev/null 2>&1 && return 0
	fi
	mkdir -p "${HOST_SHIMS}" || return 1
	case "${name}" in
	time)	cat > "${HOST_SHIMS}/time" <<'EOF'
#!/bin/sh
# portable fallback for the build's "time <cmd>" invocations
if command -v /usr/bin/time >/dev/null 2>&1; then
	exec /usr/bin/time "$@"
fi
exec "$@"
EOF
		;;
	hostname)	cat > "${HOST_SHIMS}/hostname" <<'EOF'
#!/bin/sh
uname -n
EOF
		;;
	bc)	cat > "${HOST_SHIMS}/bc" <<'EOF'
#!/bin/sh
# minimal bc fallback used by a few build-time calculations
if command -v python3 >/dev/null 2>&1; then
	exec python3 -c "import sys,re; s=' '.join(sys.argv[1:]); print(int(eval(re.sub(r'[^0-9+*/().-]','',s))))" "$@"
fi
echo 0
EOF
		;;
	*)	return 1 ;;
	esac
	chmod +x "${HOST_SHIMS}/${name}"
	PATH="${HOST_SHIMS}:${PATH}"
	export PATH
}

provision_host_shims()
{
	local t
	for t in time hostname bc
	do
		provision_host_tool "${t}" || :
	done
	command -v python3 >/dev/null 2>&1 ||
	    bomb "python3 is required to run ${MAKE_PY##*/}; install it or set PATH"
}

# run a make.py driver
run_make_py()
{
	if [ "${runcmd}" = echo ]; then
		echo "$*"
		return 0
	fi
	[ "${MKOBJDIRS-no}" != no ] && mkdir -p "${MAKEOBJDIRPREFIX}"
	if [ "${TIMEOUT}" -gt 0 ] 2>/dev/null; then
		timeout --signal=TERM --kill-after=60 --preserve-status \
		    "${TIMEOUT}" sh -c "$*"
		return $?
	fi
	sh -c "$*"
}

# provision bmake so make.py can reuse it (avoids flaky bmake unit tests
# on non-FreeBSD shells).
provision_bmake()
{
	python3 - "$SRCDIR" "${MAKEOBJDIRPREFIX}/bmake-install" <<'PY'
import glob, shlex, shutil, sys
from pathlib import Path
src=Path(sys.argv[1]); inst=Path(sys.argv[2]); bn=inst/"bin"/"bmake"
if bn.exists(): sys.exit(0)
cand=glob.glob(str(src/"obj"/"bmake-build"/"*"/"bmake"))
if not cand: sys.exit(1)
bn.parent.mkdir(parents=True, exist_ok=True)
(inst/"share"/"mk").mkdir(parents=True, exist_ok=True)
shutil.copy2(cand[0], bn)
for m in (src/"contrib"/"bmake"/"mk").iterdir():
    if m.is_file(): shutil.copy2(m, inst/"share"/"mk"/m.name)
cfg=[f"--with-default-sys-path=.../share/mk:{inst/'share'/'mk'}",
     "--with-machine=amd64","--without-filemon",f"--prefix={inst}"]
(inst/".make-py-config").write_text(" ".join(shlex.quote(x) for x in cfg))
PY
}

run_make_py_retry()
{
	local rc
	run_make_py "$@"
	rc=$?
	if [ "$rc" -ne 0 ] && [ ! -f "${MAKEOBJDIRPREFIX}/bmake-install/bin/bmake" ]; then
		if ls "${MAKEOBJDIRPREFIX}"/bmake-build/*/bmake >/dev/null 2>&1; then
			echo "${progname}: bmake self-tests flaky; provisioning bmake and retrying..." 1>&2
			provision_bmake
			run_make_py "$@"
			rc=$?
		fi
	fi
	return "$rc"
}

# ---------------------------------------------------------------------------
#
# bootable image / ISO helpers
#
# Build the EFI loader from stand/, then assemble a bootable GPT+ESP disk
# image and/or a UEFI-bootable ISO.  Everything is cross-built with the
# same toolchain that produced the kernel, so no FreeBSD host is needed.
#
# ---------------------------------------------------------------------------

KERNCONF_DEFAULT="${KERNCONF_DEFAULT:-GENERIC}"

objroot_for_target()
{
	echo "${MAKEOBJDIRPREFIX}${SRCDIR}/${TARGET}.${TARGET_ARCH}"
}

kernel_image()
{
	local kc="${1:-${KERNCONF_DEFAULT}}"
	echo "$(objroot_for_target)/sys/${kc}/kernel"
}

mach_triple()
{
	case "${TARGET_ARCH}" in
	amd64)			echo "x86_64-unknown-freebsd15.1" ;;
	arm64|aarch64)		echo "aarch64-unknown-freebsd15.1" ;;
	i386)			echo "i386-unknown-freebsd15.1" ;;
	riscv64)		echo "riscv64-unknown-freebsd15.1" ;;
	powerpc64)		echo "powerpc64-unknown-freebsd15.1" ;;
	*)			echo "${TARGET_ARCH}-unknown-freebsd15.1" ;;
	esac
}

# Run a command inside the cross-build environment used for kernel/loader.
run_cross()
{
	local obj tmp tri
	obj="$(objroot_for_target)"; tmp="${obj}/tmp"; tri="$(mach_triple)"
	if [ "${runcmd}" = echo ]; then
		echo "$*"
		return 0
	fi
	env MACHINE="${TARGET}" MACHINE_ARCH="${TARGET_ARCH}" \
	    TARGET="${TARGET}" TARGET_ARCH="${TARGET_ARCH}" \
	    CC="/usr/bin/clang -target ${tri} --sysroot=${tmp} -B${tmp}/usr/bin" \
	    CXX="/usr/bin/clang++ -target ${tri} --sysroot=${tmp} -B${tmp}/usr/bin" \
	    LD="/usr/bin/ld.lld" \
	    PATH="${obj}/tmp/bin:${obj}/tmp/usr/sbin:${obj}/tmp/usr/bin:${obj}/tmp/legacy/usr/sbin:${obj}/tmp/legacy/usr/bin:${obj}/tmp/legacy/bin:${HOST_SHIMS}:${PATH}" \
	    SYSROOT="${tmp}" WORLDTMP="${tmp}" \
	    INSTALL="sh ${SRCDIR}/tools/install.sh" \
	    MAKEOBJDIRPREFIX="${obj}" "$@"
}

build_efi_loader()
{
	statusmsg "Building EFI loader (stand/efi)"
	run_cross "${BMAKE}" -C "${SRCDIR}/stand" -m "${SRCDIR}/share/mk" \
	    -j "${njobs}" -DWITH_AUTO_OBJ -DWITHOUT_CLEAN efi ||
	    bomb "EFI loader build failed"
}

find_loader_efi()
{
	local obj found
	obj="$(objroot_for_target)"
	# Prefer the lua loader: it draws the boot banner (logo + wordmark).
	for l in \
	    "${obj}/stand/efi/loader_lua/loader_lua.efi" \
	    "${SRCDIR}/stand/efi/loader_lua/loader_lua.efi" \
	    "${obj}/stand/efi/loader_simp/loader_simp.efi" \
	    "${SRCDIR}/stand/efi/loader_simp/loader_simp.efi"
	do
		[ -f "${l}" ] && { echo "${l}"; return 0; }
	done
	found="$(find "${obj}" \( -path "*loader_lua/loader_lua.efi" -o -path "*loader_simp/loader_simp.efi" \) 2>/dev/null | head -1)"
	[ -n "${found}" ] && { echo "${found}"; return 0; }
	return 1
}

# Create a FAT32 EFI System Partition image (whole-file volume) holding the
# EFI loader and the kernel.
make_boot_esp()
{
	local img loader kern
	img="${IMAGEDIR}/renux-esp.img"
	loader="$(find_loader_efi)"
	if [ -z "${loader}" ]; then
		if [ "${runcmd}" = echo ]; then
			loader="<loader.efi>"
		else
			bomb "EFI loader not found; build it with 'iso' or 'bootimage'"
		fi
	fi
	kern="$(kernel_image "${KERNCONF:-${KERNCONF_DEFAULT}}")"
	[ -f "${kern}" ] ||
	    bomb "kernel not built at ${kern}; run 'build.sh kernel=...' first"
	command -v mkfs.fat >/dev/null 2>&1 || bomb "mkfs.fat (dosfstools) is required to build images"
	command -v mcopy >/dev/null 2>&1 || bomb "mtools is required to build images"

	rm -f "${img}"
	if [ "${runcmd}" = echo ]; then
		echo "truncate -s ${ESP_MB:-128}M ${img}"
	else
		truncate -s "${ESP_MB:-128}M" "${img}"
	fi
	statusmsg "Formatting ESP image ${img}"
	${runcmd} mkfs.fat -F32 -n RENUX "${img}" >/dev/null
	[ "${runcmd}" = echo ] && return 0
	mmd -i "${img}" /EFI
	mmd -i "${img}" /EFI/BOOT
	mmd -i "${img}" /boot
	mmd -i "${img}" /boot/kernel
	mmd -i "${img}" /boot/defaults
	mmd -i "${img}" /boot/lua
	mcopy -i "${img}" "${loader}" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "${img}" "${kern}" ::/boot/kernel/kernel
	# Lua loader scripts (boot menu / banner drawing).
	mcopy -i "${img}" -s ${SRCDIR}/stand/lua/*.lua ::/boot/lua/
	cat > "${IMAGEDIR}/loader.conf" <<'EOF'
# Renux boot configuration (FreeBSD-style BIOS banner, "RENUX" wordmark).
# Remove the "#" below for a graphical BMP splash screen:
#splash_bmp_load="YES"
#bitmap_load="YES"
#bitmap_name="/boot/splash.bmp"
autoboot_delay="2"			# seconds to wait before auto-boot
loader_logo="beastie"			# classic beastie logo + RENUX banner
console="vidconsole"
EOF
	mcopy -i "${img}" "${IMAGEDIR}/loader.conf" ::/boot/loader.conf
	mcopy -i "${img}" "${IMAGEDIR}/loader.conf" ::/boot/defaults/loader.conf
}

# Wrap the ESP image in a GPT disk so QEMU/OVMF can boot it as a hard disk.
make_boot_image()
{
	local disk start esp_sectors esp_bytes
	disk="${IMAGEDIR}/renux.img"
	esp_sectors=$(( ${ESP_MB:-128} * 1024 * 1024 / 512 ))
	start=2048
	rm -f "${disk}"
	truncate -s $(( (start + esp_sectors + 4096) * 512 )) "${disk}"
	statusmsg "Assembling GPT boot image ${disk}"
	${runcmd} sh -c \
	    "printf 'label: gpt\\nstart=${start}, size=${esp_sectors}, type=uefi, bootable\\n' | sfdisk ${disk}" ||
	    bomb "sfdisk failed; is it installed?"
	[ "${runcmd}" = echo ] && return 0
	dd if="${IMAGEDIR}/renux-esp.img" of="${disk}" bs=512 seek=${start} conv=notrunc
}

# UEFI-bootable ISO (El Torito) using the ESP image as the EFI boot medium.
make_iso()
{
	command -v xorriso >/dev/null 2>&1 || bomb "xorriso is required to build an ISO"
	rm -rf "${IMAGEDIR}/isofiles"
	mkdir -p "${IMAGEDIR}/isofiles"
	if [ "${runcmd}" = echo ]; then
		echo "cp ${IMAGEDIR}/renux-esp.img ${IMAGEDIR}/isofiles/"
	else
		cp "${IMAGEDIR}/renux-esp.img" "${IMAGEDIR}/isofiles/"
	fi
	statusmsg "Building ISO ${IMAGEDIR}/renux.iso"
	${runcmd} xorriso -as mkisofs \
	    -V RENUX \
	    -o "${IMAGEDIR}/renux.iso" \
	    -eltorito-alt-boot -e renux-esp.img -no-emul-boot -isohybrid-gpt-basdat \
	    "${IMAGEDIR}/isofiles" ||
	    bomb "xorriso failed"
}

run_qemu()
{
	local img ovmf
	img="${IMAGEDIR}/renux.img"
	[ -f "${img}" ] || make_boot_image
	command -v qemu-system-x86_64 >/dev/null 2>&1 ||
	    bomb "qemu-system-x86_64 is required for the 'qemu' operation"
	ovmf=
	for f in /usr/share/OVMF/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd
	do
		[ -f "${f}" ] && { ovmf="${f}"; break; }
	done
	statusmsg "Starting QEMU: ${img}"
	if [ "${runcmd}" = echo ]; then
		echo "qemu-system-x86_64 -drive file=${img} -m ${QEMU_MEM:-1024} -display ${QEMU_DISPLAY:-default}"
		return 0
	fi
	qemu-system-x86_64 -machine q35,accel=tcg \
	    -m "${QEMU_MEM:-1024}" \
	    ${ovmf:+-drive if=pflash,format=raw,readonly=on,file=${ovmf}} \
	    -drive file="${img}",format=raw,if=none,id=disk \
	    -device ide-hd,drive=disk,bus=ide.0 \
	    -display "${QEMU_DISPLAY:-default}" -no-reboot &
}

# ---------------------------------------------------------------------------
#
# main
#
# ---------------------------------------------------------------------------
main()
{
	# defaults
	operations=
	runcmd=
	do_expertmode=false
	MKOBJDIRS="${MKOBJDIRS-yes}"
	parallel="${parallel:-${auto_parallel}}"
	BUILDID=
	RELEASEDIR=
	BUILDSEED=
	TOOLDIR=
	MKX11=
	X11SRCDIR=
	MKUPDATE=no
	kernel_only=false
	IMAGEDIR="${IMAGEDIR:-${MAKEOBJDIRPREFIX}/renux-images}"
	do_image=false
	have_kernel=false

	build_start=$(date)
	statusmsg "${progname}: started: ${build_start}"

	parseoptions "$@"
	provision_host_shims

	BMAKE="${MAKEOBJDIRPREFIX}/bmake-install/bin/bmake"
	njobs="${parallel#-j }"
	[ -n "${njobs}" ] || njobs="${ncpu:-2}"

	# extra make variables sent to the driver
	extra=""
	[ -n "${BUILDID}" ]       && extra="${extra} BUILDID=${BUILDID}"
	[ -n "${RELEASEDIR}" ]    && extra="${extra} RELEASEDIR=${RELEASEDIR}"
	[ -n "${BUILDSEED}" ]     && extra="${extra} BUILDSEED=${BUILDSEED}"

	# The driver for make:
	cmd="python3 \"${MAKE_PY}\""
	if command -v clang >/dev/null 2>&1 && [ "$(uname -s)" != Darwin ]
	then
		cb="$(cd "$(dirname "$(command -v clang)")" && pwd)"
		cmd="${cmd} --cross-bindir=${cb}"
	fi
	[ "${MKUPDATE}" = yes ] && cmd="${cmd} --no-clean"
	[ "${do_expertmode}" = false ] || :
	[ -n "${parallel}" ] && cmd="${cmd} ${parallel}"
	cmd="${cmd} TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH}"

	did=false
	for op in ${operations}
	do
		case "$op" in
		build)
			if [ "${kernel_only}" = true ]; then
				did=true; have_kernel=true
				cmd="${cmd} KERNCONF=${KERNCONF:-${KERNCONF_DEFAULT}} WERROR= kernel-toolchain buildkernel"
			else
				did=true; cmd="${cmd} buildworld buildkernel"
			fi
			;;
		world|distribution|release)
			if [ "${kernel_only}" = true ]; then
				warning "${op} ignored in kernel-only mode (-K)"
				did=true; have_kernel=true
				cmd="${cmd} KERNCONF=${KERNCONF:-${KERNCONF_DEFAULT}} WERROR= kernel-toolchain buildkernel"
			else
				did=true; cmd="${cmd} buildworld"
			fi
			;;
		tools)           did=true; cmd="${cmd} buildtools" ;;
		kernels)         did=true; have_kernel=true; cmd="${cmd} WERROR= kernel-toolchain buildkernel" ;;
		kernel=*)        did=true; have_kernel=true; KERNCONF="${op#kernel=}"; cmd="${cmd} KERNCONF=${KERNCONF} WERROR= kernel-toolchain buildkernel" ;;
		kernel.gdb=*)    did=true; have_kernel=true; KERNCONF="${op#kernel.gdb=}"; cmd="${cmd} KERNCONF=${KERNCONF} WERROR= kernel-toolchain buildkernel" ;;
		install=*)       did=true
			cmd="${cmd} DESTDIR=${op#install=} installworld installkernel" ;;
		iso|bootimage|qemu|run)
			do_image=true
			if [ "${have_kernel}" = false ]; then
				did=true; have_kernel=true
				cmd="${cmd} KERNCONF=${KERNCONF:-${KERNCONF_DEFAULT}} WERROR= kernel-toolchain buildkernel"
			fi
			;;
		clean)
			rm -rf "${MAKEOBJDIRPREFIX}"/bmake-build "${MAKEOBJDIRPREFIX}"/buildworld* 2>/dev/null
			;;
		obj)
			if [ "${MKOBJDIRS-no}" != no ]; then
				if [ "${runcmd}" != echo ]; then
					mkdir -p "${MAKEOBJDIRPREFIX}"
				else
					echo "echo mkdir -p ${MAKEOBJDIRPREFIX}"
				fi
			fi
			;;
		update)
			if [ "${runcmd}" = echo ]; then
				echo "git -C ${SRCDIR} pull --ff-only"
			else
				git -C "${SRCDIR}" pull --ff-only
			fi
			;;
		show-params)
			${runcmd} echo "SRCDIR=${SRCDIR}"
			${runcmd} echo "TARGET=${TARGET}"
			${runcmd} echo "TARGET_ARCH=${TARGET_ARCH}"
			${runcmd} echo "MAKEOBJDIRPREFIX=${MAKEOBJDIRPREFIX}"
			${runcmd} echo "DESTDIR=${DESTDIR}"
			${runcmd} echo "parallel=${parallel}"
			;;
		*)
			bomb "Unknown OPERATION '${op}'"
			;;
		esac
	done

	if [ "$did" = true ]
	then
		statusmsg "Command: ${cmd}"
		run_make_py_retry "${cmd}"
	fi

	if [ "${do_image}" = true ]
	then
		mkdir -p "${IMAGEDIR}"
		build_efi_loader
		make_boot_esp
		make_boot_image
		for op in ${operations}
		do
			case "$op" in
			iso)	make_iso ;;
			qemu|run)	run_qemu ;;
			esac
		done
	fi

	statusmsg "${progname}: ended: $(date)"
}

main "$@"