--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    setup.lua - automatic environment detection and provisioning.
]]

local cfg = require("renux.config")
local H   = require("renux.helpers")

local c = H.c

local host_os   = H.capture("uname -s")
local host_arch = H.capture("uname -m")

local function host_info()
    return host_os, host_arch
end

local function is_cross_build()
    if host_os == "FreeBSD" and cfg.target == "amd64" then return false end
    if host_os == "FreeBSD" and cfg.target == cfg.target_arch then return false end
    return true
end

local function detect_cc()
    local candidates = { "clang", "gcc", "cc" }
    for _, name in ipairs(candidates) do
        local path = H.capture("command -v " .. name .. " 2>/dev/null")
        if path ~= "" then return path, name end
    end
    return nil, nil
end

local function detect_linker()
    local candidates = { "ld.lld", "lld", "ld" }
    for _, name in ipairs(candidates) do
        local path = H.capture("command -v " .. name .. " 2>/dev/null")
        if path ~= "" then return path, name end
    end
    return nil, nil
end

local REQUIRED_TOOLS = {
    { cmd = "make",     pkg_linux = "make",        pkg_bsd = "devel/gmake",  note = "GNU make" },
    { cmd = "git",      pkg_linux = "git",          pkg_bsd = "devel/git",    note = "source fetch" },
    { cmd = "patch",    pkg_linux = "patch",        pkg_bsd = "sysutils/patch", note = "patching" },
    { cmd = "bmake",    pkg_linux = "bmake",        pkg_bsd = "devel/bmake",  note = "build system", alt = "make" },
    { cmd = "mktemp",   pkg_linux = "coreutils",    pkg_bsd = "",             note = "temp files" },
    { cmd = "install",  pkg_linux = "coreutils",    pkg_bsd = "BSD tool",     note = "file install" },
    { cmd = "stat",     pkg_linux = "coreutils",    pkg_bsd = "BSD tool",     note = "file stat" },
    { cmd = "readlink", pkg_linux = "coreutils",    pkg_bsd = "BSD tool",     note = "symlink read" },
    { cmd = "realpath", pkg_linux = "coreutils",    pkg_bsd = "",             note = "path resolve", optional = true },
    { cmd = "find",     pkg_linux = "findutils",    pkg_bsd = "BSD tool",     note = "file search" },
    { cmd = "tar",      pkg_linux = "tar",          pkg_bsd = "archivers/tar", note = "archives" },
    { cmd = "xz",       pkg_linux = "xz",           pkg_bsd = "archivers/xz", note = "compression", optional = true },
    { cmd = "grep",     pkg_linux = "grep",         pkg_bsd = "BSD tool",     note = "text search" },
    { cmd = "sed",      pkg_linux = "sed",          pkg_bsd = "BSD tool",     note = "text edit" },
    { cmd = "awk",      pkg_linux = "gawk",         pkg_bsd = "converters/gawk", note = "text processing" },
}

local ISO_TOOLS = {
    { cmd = "mkisofs",  pkg_linux = "genisoimage",  pkg_bsd = "sysutils/cdrtools", note = "ISO creation" },
    { cmd = "xorriso",  pkg_linux = "xorriso",      pkg_bsd = "sysutils/xorriso",  note = "ISO creation (alt)" },
    { cmd = "mkfs.fat", pkg_linux = "dosfstools",   pkg_bsd = "",                   note = "FAT ESP", optional = true },
    { cmd = "mcopy",    pkg_linux = "mtools",        pkg_bsd = "",                   note = "FAT copy", optional = true },
}

local function check_tools(list)
    local missing = {}
    for _, tool in ipairs(list) do
        local found = H.have(tool.cmd)
        if not found and tool.alt then
            found = H.have(tool.alt)
        end
        if not found and not tool.optional then
            local pkg
            if host_os == "Linux" then
                pkg = tool.pkg_linux
            elseif host_os == "FreeBSD" or host_os == "NetBSD" or host_os == "OpenBSD" or host_os == "DragonFly" then
                pkg = tool.pkg_bsd
            else
                pkg = tool.pkg_linux
            end
            missing[#missing + 1] = { cmd = tool.cmd, pkg = pkg, note = tool.note }
        end
    end
    return missing
end

local function provision_shims()
    local shim_dir = cfg.srcdir .. "/tools/renux/shims"
    H.mkdir_p(shim_dir)

    local hostname_shim = shim_dir .. "/hostname"
    if not os.execute("[ -f '" .. hostname_shim .. "' ]") then
        H.write_file(hostname_shim, [[#!/bin/sh
exec /bin/hostname "$@"
]])
        H.sh("chmod +x '" .. hostname_shim .. "'")
    end

    local bc_shim = shim_dir .. "/bc"
    if not os.execute("[ -f '" .. bc_shim .. "' ]") then
        H.write_file(bc_shim, [[#!/bin/sh
exec /usr/bin/bc "$@"
]])
        H.sh("chmod +x '" .. bc_shim .. "'")
    end

    local time_shim = shim_dir .. "/time"
    if not os.execute("[ -f '" .. time_shim .. "' ]") then
        H.write_file(time_shim, [[#!/bin/sh
exec /usr/bin/time "$@"
]])
        H.sh("chmod +x '" .. time_shim .. "'")
    end

    return shim_dir
end

local function create_arch_symlinks(objdir, srcdir, target, target_arch)
    H.mkdir_p(objdir)

    local links = {}
    links["machine"] = srcdir .. "/sys/arch/" .. target .. "/include"

    if target == "amd64" then
        links["i386"] = srcdir .. "/sys/arch/i386/include"
    end

    if target_arch == "amd64" or target_arch == "i386" then
        links["x86"] = srcdir .. "/sys/arch/x86/include"
    end

    for name, dest in pairs(links) do
        local link_path = objdir .. "/" .. name
        local dest_exists = os.execute("[ -d '" .. dest .. "' ]")
        if dest_exists then
            local current = H.capture("readlink '" .. link_path .. "' 2>/dev/null")
            if current ~= dest then
                H.sh("ln -fns '" .. dest .. "' '" .. link_path .. "'")
            end
        end
    end
end

local function create_kernel_symlinks(objdir, srcdir, target, target_arch, kernconf)
    local kernel_obj = objdir .. "/sys/" .. target .. "." .. target_arch .. "/compile/" .. kernconf
    H.sh("mkdir -p '" .. kernel_obj .. "'")
    create_arch_symlinks(kernel_obj, srcdir, target, target_arch)
end

local function setup_cross_env(objdir, srcdir, target, target_arch)
    local kernel_obj = objdir .. "/sys/" .. target .. "." .. target_arch .. "/compile/" .. cfg.kernconf

    create_arch_symlinks(kernel_obj, srcdir, target, target_arch)

    local shim_dir = provision_shims()
    return shim_dir
end

local function print_summary(host_os, host_arch, cross, cc_path, ld_name)
    H.status("Host: " .. c.bold .. c.white .. host_os .. "/" .. host_arch .. c.reset)
    if cross then
        H.status("Cross-compile: " .. c.bold .. c.yellow .. "yes" .. c.reset ..
                 " -> " .. c.cyan .. cfg.target .. "/" .. cfg.target_arch .. c.reset)
    else
        H.status("Target: " .. c.bold .. c.cyan .. cfg.target .. "/" .. cfg.target_arch .. c.reset)
    end
    if cc_path then
        H.status("CC: " .. c.green .. cc_path .. c.reset)
    end
    if ld_name then
        H.status("LD: " .. c.green .. ld_name .. c.reset)
    end
end

local function run(check_iso)
    local h_os, h_arch = host_info()
    local cross = is_cross_build()

    local cc_path, cc_name = detect_cc()
    local ld_path, ld_name = detect_linker()

    local missing = check_tools(REQUIRED_TOOLS)
    if check_iso then
        local iso_missing = check_tools(ISO_TOOLS)
        for _, m in ipairs(iso_missing) do
            missing[#missing + 1] = m
        end
    end

    if #missing > 0 then
        H.warn("missing required tools:")
        print()
        for _, m in ipairs(missing) do
            local install_hint = ""
            if h_os == "Linux" and m.pkg ~= "" then
                install_hint = c.dim .. " (install: " .. m.pkg .. ")" .. c.reset
            elseif h_os == "FreeBSD" and m.pkg ~= "" then
                install_hint = c.dim .. " (install: pkg install " .. m.pkg .. ")" .. c.reset
            end
            print("  " .. c.red .. m.cmd .. c.reset .. " - " .. m.note .. install_hint)
        end
        print()

        local has_critical = false
        for _, m in ipairs(missing) do
            if m.cmd == "make" or m.cmd == "git" or m.cmd == "patch" then
                has_critical = true
            end
        end
        if has_critical then
            H.bomb("install the missing tools above before building")
        end
    end

    local objdir = cfg.makeobjdir
    local shim_dir = setup_cross_env(objdir, cfg.srcdir, cfg.target, cfg.target_arch)

    if cross then
        local amd64_obj = objdir .. "/sys/" .. cfg.target .. "." .. cfg.target_arch
        create_arch_symlinks(amd64_obj, cfg.srcdir, cfg.target, cfg.target_arch)
        create_kernel_symlinks(objdir, cfg.srcdir, cfg.target, cfg.target_arch, cfg.kernconf)
    end

    if not cross then
        local machine_dir = objdir .. "/sys/" .. cfg.target .. "." .. cfg.target_arch
        if not os.execute("[ -d '" .. machine_dir .. "' ]") then
            H.sh("mkdir -p '" .. machine_dir .. "'")
        end
        create_arch_symlinks(machine_dir, cfg.srcdir, cfg.target, cfg.target_arch)
        create_kernel_symlinks(objdir, cfg.srcdir, cfg.target, cfg.target_arch, cfg.kernconf)
    end

    print_summary(h_os, h_arch, cross, cc_path, ld_name)

    return shim_dir
end

return {
    run             = run,
    host_info       = host_info,
    is_cross_build  = is_cross_build,
    detect_cc       = detect_cc,
    detect_linker   = detect_linker,
    check_tools     = check_tools,
    provision_shims = provision_shims,
    create_arch_symlinks    = create_arch_symlinks,
    create_kernel_symlinks  = create_kernel_symlinks,
}
