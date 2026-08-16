#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Renan Lucas Vieira Hilário.
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
#   <ref>   a commit on the 'freebsd' upstream remote (e.g. freebsd/<sha>
#           or a SHA), a path to a .patch/.diff file, or an https:// URL.
#   test    optional command to verify the change (default: build the kernel).
#           If it exits non-zero the change is reverted.
#
# For git refs the change is applied with git cherry-pick (a real 3-way
# merge, which copes with the drift between the FreeBSD release Renux is
# based on and FreeBSD current).  Set up upstream first:
#
#   git remote add freebsd https://github.com/freebsd/freebsd-src.git
#   git fetch --filter=tree:0 freebsd main
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

# Revert the given files to HEAD, removing any that are new.
revert_files()
{
	for f in "$@"; do
		[ -z "$f" ] && continue
		git checkout HEAD -- "$f" 2>/dev/null || rm -f "$f"
	done
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
touched=""

############################################################ Obtain the change

case "$ref" in
http://*|https://*)
	curl -fsSL "$ref" -o "$orig" || { echo "error: could not fetch $ref"; exit 1; }
	sed -e "$TRANSLATIONS" "$orig" > "$translated"
	touched="$(awk '/^diff --git/{for(i=1;i<=NF;i++) if($i ~ /^b\//) {p=$i; sub(/^b\//,"",p); print p}}' "$translated")"
	;;
*/*|*.patch|*.diff)
	if [ -f "$ref" ]; then
		sed -e "$TRANSLATIONS" "$ref" > "$translated"
		touched="$(awk '/^diff --git/{for(i=1;i<=NF;i++) if($i ~ /^b\//) {p=$i; sub(/^b\//,"",p); print p}}' "$translated")"
	else
		echo "error: no such patch file: $ref"
		exit 1
	fi
	;;
*)
	git rev-parse --verify "$ref^{commit}" >/dev/null 2>&1 || {
		echo "error: '$ref' is not a patch file, URL or git ref."
		echo "hint: 'git fetch --filter=tree:0 freebsd main' first, then use a SHA."
		exit 1
	}
	git format-patch -1 --stdout "$ref" | sed -e "$TRANSLATIONS" > "$translated"
	touched="$(git show --format= --name-only "$ref")"
	;;
esac

if [ -s "$translated" ]; then
	echo "Translated patch:"
	git apply --stat "$translated"
fi

if [ "$dryrun" = true ]; then
	echo "Dry run: not applying."
	exit 0
fi

############################################################ Apply

case "$ref" in
http://*|https://*|*/*|*.patch|*.diff)
	if ! git apply --whitespace=nowarn "$translated" 2> "$tmp/apply.err"; then
		if git apply --whitespace=nowarn --3way "$translated" 2> "$tmp/apply3.err"; then
			echo "Applied via 3-way merge."
			git reset -q
		else
			echo "error: patch did not apply cleanly:"
			cat "$tmp/apply.err"
			cat "$tmp/apply3.err"
			exit 1
		fi
	fi
	;;
*)
	# git ref: cherry-pick does a real 3-way merge against the current tree.
	if ! git cherry-pick -n "$ref" 2> "$tmp/cp.err"; then
		echo "error: cherry-pick failed:"
		cat "$tmp/cp.err"
		echo "note: run 'git cherry-pick --abort' to clean up."
		exit 1
	fi
	echo "Applied via git cherry-pick."
	git reset -q
	;;
esac

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
	revert_files $touched
	echo "Reverted. The FreeBSD change was discarded."
	exit 1
fi

echo ""
echo "Test passed. The change is applied but NOT committed."
echo "Review it with 'git diff' and commit when ready."
