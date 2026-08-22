--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    make.lua - make.py driver.  Constructs the build command from operations.
]]

local cfg = require("renux.config")
local H   = require("renux.helpers")

local function build_make_cmd(ops)
    local shims = cfg.srcdir .. "/tools/renux/shims"
    local cmd = 'PATH="' .. shims .. ':$PATH" MAKEOBJDIRPREFIX="' .. cfg.makeobjdir .. '" python3 "' .. cfg.make_py .. '"'
    if H.have("clang") and not H.is_darwin() then
        local cb = H.capture("cd \"$(dirname \"$(command -v clang)\")\" && pwd")
        if cb ~= "" then cmd = cmd .. " --cross-bindir=" .. cb end
    end
    if cfg.update then cmd = cmd .. " --no-clean" end
    if cfg.parallel then cmd = cmd .. " " .. cfg.parallel end
    cmd = cmd .. " TARGET=" .. cfg.target .. " TARGET_ARCH=" .. cfg.target_arch
    cmd = cmd .. " MK_SSP=no MK_TESTS=no"
    if cfg.extra_args ~= "" then cmd = cmd .. " " .. cfg.extra_args end

    local have_kernel = false
    local did = false
    for _, op in ipairs(ops) do
        if op == "build" then
            if cfg.kernel_only then
                did, have_kernel = true, true
                cmd = cmd .. " KERNCONF=" .. cfg.kernconf .. " WERROR= kernel-toolchain buildkernel"
            else
                did, have_kernel = true, true
                cmd = cmd .. " buildworld buildkernel"
            end
        elseif op == "world" or op == "distribution" then
            if cfg.kernel_only then
                did, have_kernel = true, true
                cmd = cmd .. " KERNCONF=" .. cfg.kernconf .. " WERROR= kernel-toolchain buildkernel"
            else
                did = true; cmd = cmd .. " buildworld"
            end
        elseif op == "release" then
            did = true
            if not cfg.kernel_only then cmd = cmd .. " buildworld buildkernel" end
        elseif op == "tools" then
            did = true; cmd = cmd .. " toolchain"
        elseif op == "kernels" then
            did, have_kernel = true, true
            cmd = cmd .. " WERROR= kernel-toolchain buildkernel"
        elseif op:match("^kernel=") then
            did, have_kernel = true, true
            cfg.kernconf = op:match("^kernel=(.*)$")
            cmd = cmd .. " KERNCONF=" .. cfg.kernconf .. " WERROR= kernel-toolchain buildkernel"
        elseif op:match("^kernel.gdb=") then
            did, have_kernel = true, true
            cfg.kernconf = op:match("^kernel.gdb=(.*)$")
            cmd = cmd .. " KERNCONF=" .. cfg.kernconf .. " WERROR= kernel-toolchain buildkernel"
        elseif op:match("^install=") then
            did = true
            cmd = cmd .. " DESTDIR=" .. op:match("^install=(.*)$") .. " installworld installkernel"
        elseif op == "worldiso" then
            did, have_kernel = true, true
            for _, d in ipairs({
                "/bin", "/sbin", "/etc", "/root", "/dev", "/tmp", "/var", "/usr",
                "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
                "/usr/include", "/usr/src", "/usr/tests", "/usr/lib/debug",
                "/usr/lib32", "/usr/local",
                "/var/run/devd", "/var/tmp", "/var/log", "/var/db",
                "/var/spool", "/var/empty", "/var/mail", "/var/account",
            }) do
                H.sh("mkdir -p '" .. cfg.worlddir .. d .. "'")
            end
            H.sh("touch '" .. cfg.worlddir .. "/METALOG'")
            cmd = cmd .. " DESTDIR=" .. cfg.worlddir .. " installworld distribution installkernel"
        elseif op == "iso" or op == "bootimage" or op == "qemu" or op == "run" then
            if not have_kernel then
                did, have_kernel = true, true
                cmd = cmd .. " KERNCONF=" .. cfg.kernconf .. " WERROR= kernel-toolchain buildkernel"
            end
        end
    end
    return cmd, did
end

return {
    build_make_cmd = build_make_cmd,
}
