#! /usr/bin/env sh
#	$Id$
#
# Renux build.sh -- adapted from NetBSD's build.sh
#
# Copyright (c) 2023-2026 Renux contributors.
#	$NetBSD: build.sh,v 1.405 2026/08/01 20:14:38 thorpej Exp $
#
# This script is derived from the NetBSD build.sh, and is used to build
# or cross-build Renux (a FreeBSD fork) on any Unix host: FreeBSD, Linux,
# NetBSD, OpenBSD, DragonFly, macOS.
#
# On non-FreeBSD hosts, all world/kernel building is delegated to the
# official cross-build driver ${SRCDIR}/tools/build/make.py, which
# bootstraps bmake from this source and infers the cross-compiler
# (clang/lld).  No FreeBSD host or preinstalled toolchain is required.
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

# valid_targets -- table of supported Renux/FreeBSD targets.
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
    show-params         Show the build parameters in use.
    list-arch           List the supported architectures and exit.

 Options:
    -a ARCH        Set TARGET_ARCH=ARCH.  [Default: deduced from MACHINE]
    -B BID         Set BUILDID=BID.
    -c COMPILER    Select compiler: clang or gcc.
    -D DEST        Set DESTDIR=DEST.
    -E             Set "expert" mode; disables various safety checks.
    -h             Show this help message, and exit.
    -j NJOB        Run up to NJOB parallel make jobs.
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
    -X X11SRC      Ignored on this fork.
    -x             Ignored on this fork.
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
	opts='a:B:c:D:Ej:M:m:N:nO:oR:S:T:uUV:w:X:xZ:'
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
		-j) eval $optargcmd; parallel="-j $OPTARG" ;;
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
		show-params|kernels)
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
# build driver for this fork (delegates to make.py)
#
# ---------------------------------------------------------------------
SRCDIR="${SRCDIR:-$(cd "$(dirname "$0")" && pwd)/src}"
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

	build_start=$(date)
	statusmsg "${progname}: started: ${build_start}"

	parseoptions "$@"
	provision_host_shims

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
		build)           did=true; cmd="${cmd} buildworld buildkernel" ;;
		world)           did=true; cmd="${cmd} buildworld" ;;
		distribution)    did=true; cmd="${cmd} distribution" ;;
		release)         did=true; cmd="${cmd} release" ;;
		tools)           did=true; cmd="${cmd} buildtools" ;;
		kernels)         did=true; cmd="${cmd} WERROR= kernel-toolchain buildkernel" ;;
		kernel=*)        did=true; cmd="${cmd} KERNCONF=${op#kernel=} WERROR= kernel-toolchain buildkernel" ;;
		kernel.gdb=*)    did=true; cmd="${cmd} KERNCONF=${op#kernel.gdb=} WERROR= kernel-toolchain buildkernel" ;;
		install=*)       did=true
			cmd="${cmd} DESTDIR=${op#install=} installworld installkernel" ;;
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

	statusmsg "${progname}: ended: $(date)"
}

main "$@"