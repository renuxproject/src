#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 The Renux Project.
#
# import-freebsd.sh - bring a FreeBSD change into the Renux tree.
#
# Renux keeps a FreeBSD-derived base but reorganizes it (MD code under
# sys/arch/, custom scheduler/allocator, etc.).  This script translates a
# FreeBSD change to the Renux layout, applies it, runs a test, and reverts
# the change if the test fails.
#
# Usage:
#   ./tools/build/import-freebsd.sh <ref> [test command...]
#
#   <ref>   a commit on the 'freebsd' upstream remote (e.g. freebsd/main or
#           a 40-char SHA), a path to a .patch/.diff file, or an https:// URL.
#   test    optional command to verify the change (default: build the kernel).
#           If it exits non-zero the change is reverted.
#
# Examples:
#   git fetch freebsd stable/16
#   ./tools/build/import-freebsd.sh freebsd/<sha>
#   ./tools/build/import-freebsd.sh my-fix.patch
#   ./tools/build/import-freebsd.sh https://.../patch.txt 'make -C lib/libc check'
#
# Translation rules (Renux layout): sys/<machine>/ -> sys/arch/<machine>/.
# Extend TRANSLATIONS as Renux keeps diverging.

set -u

# Top of the Renux source tree.
HERE="$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
cd "$HERE" || exit 1

# sed -e script applied to every FreeBSD patch.
TRANSLATIONS="
s|sys/amd64/|sys/arch/amd64/|g
s|sys/i386/|sys/arch/i386/|g
s|sys/arm64/|sys/arch/arm64/|g
s|sys/arm/|sys/arch/arm/|g
s|sys/riscv/|sys/arch/riscv/|g
s|sys/powerpc/|sys/arch/powerpc/|g
"

# Default test: build the kernel (the Renux build.sh entry point).
DEFAULT_TEST="sh ./build.sh kernel=GENERIC"

usage()
{
	cat <<EOF
usage: $0 <ref> [test command...]

Apply a FreeBSD change to Renux with layout translation, test it, and
revert it if the test fails.

<ref> may be:
  a git ref on the 'freebsd' remote (e.g. freebsd/<sha>),
  a path to a .patch/.diff file,
  an https:// URL to a patch.

The default test is: $DEFAULT_TEST
Override it by passing a command after <ref>.
EOF
}

dryrun=false
if [ "${1:-}" = "-n" ] || [ "${1:-}" = "--dry-run" ]; then
	dryrun=true
	shift
fi

ref="${1:-}"
[ -n "$ref" ] || { usage; exit 1; }
shift

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
orig="$tmp/orig.patch"
translated="$tmp/translated.patch"

############################################################ Obtain the patch

case "$ref" in
http://*|https://*)
	curl -fsSL "$ref" -o "$orig" || { echo "error: could not fetch $ref"; exit 1; }
	;;
*/*|*.patch|*.diff)
	if [ -f "$ref" ]; then
		cp "$ref" "$orig"
	else
		echo "error: no such patch file: $ref"
		exit 1
	fi
	;;
*)
	git rev-parse --verify "$ref^{commit}" >/dev/null 2>&1 || {
		echo "error: '$ref' is not a patch file, URL or git ref."
		echo "hint: 'git fetch freebsd stable/16' first, then use freebsd/<sha>."
		exit 1
	}
	git format-patch -1 --stdout "$ref" > "$orig" || exit 1
	;;
esac

[ -s "$orig" ] || { echo "error: empty patch"; exit 1; }

############################################################ Translate

sed -e "$TRANSLATIONS" "$orig" > "$translated"

echo "Translated patch:"
git apply --stat "$translated"

if [ "$dryrun" = true ]; then
	echo "Dry run: not applying."
	exit 0
fi

############################################################ Apply

if ! git apply --whitespace=nowarn "$translated" 2> "$tmp/apply.err"; then
	echo "error: patch did not apply cleanly:"
	cat "$tmp/apply.err"
	exit 1
fi
echo "Applied. Files changed:"
git diff --stat

############################################################ Test

if [ "$#" -gt 0 ]; then
	sh -c "$*"
else
	sh -c "$DEFAULT_TEST"
fi
status=$?

############################################################ Revert on failure

if [ "$status" -ne 0 ]; then
	echo ""
	echo "TEST FAILED (exit $status). Reverting the FreeBSD change..."
	if git apply -R "$translated" 2> "$tmp/revert.err"; then
		echo "Reverted. The FreeBSD change was discarded."
	else
		echo "warning: automatic revert failed:"
		cat "$tmp/revert.err"
		echo "You may need to 'git checkout' the files manually."
	fi
	exit 1
fi

echo ""
echo "Test passed. The change is applied but NOT committed."
echo "Review it with 'git diff' and commit when ready."
