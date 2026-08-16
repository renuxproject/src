#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Renan Lucas Vieira Hilário.
#
# build.sh - compatibility shim.  The Renux build utility is now ./renux
# (Lua).  This file only forwards to it so existing commands keep working.
exec "$(cd "$(dirname "$0")" && pwd)/renux" "$@"
