--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    config.lua - Renux build configuration.
]]

local getenv = os.getenv

local VERSION = "0.1-CURRENT"

local script_dir = arg[0]:match("^(.+)/[^/]+$") or "."
local _p = io.popen("cd '" .. script_dir .. "' && pwd")
local root = _p:read("*l"); _p:close()

local cfg = {
    version         = VERSION,
    srcdir          = root,
    makeobjdir      = getenv("MAKEOBJDIRPREFIX") or root .. "/obj",
    target          = getenv("TARGET") or "amd64",
    target_arch     = getenv("TARGET_ARCH") or "amd64",
    kernconf        = "GENERIC",
    imagdir         = "release",
    parallel        = nil,
    runcmd          = "",
    qemu_mem        = getenv("QEMU_MEM") or "1024",
    qemu_display    = getenv("QEMU_DISPLAY") or "default",
    qemu_serial     = getenv("QEMU_SERIAL") or "stdio",
    espmb           = 128,
    update          = false,
    kernel_only     = false,
    worlddir        = "",
    extra_args      = "",
}

function cfg.abs_init(abs_path)
    cfg.imagdir = abs_path(cfg.imagdir)
    cfg.worlddir = cfg.imagdir .. "/world-root"
end

return cfg
