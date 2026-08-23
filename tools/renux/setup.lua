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

----------------------------------------------------------------------------
-- Package manager detection
----------------------------------------------------------------------------

-- Manager short names: apt pacman dnf zypper apk xbps emerge brew
--                      pkg pkgin pkg_add
local function detect_linux_distro()
    local f = io.open("/etc/os-release", "r")
    if f then
        local body = f:read("*a"); f:close()
        local id = body:match('^ID="?([%w%-]+)"?')
        return id or ""
    end
    return ""
end

local function detect_manager()
    if host_os == "Darwin" then return H.have("brew") and "brew" or nil end
    if host_os == "FreeBSD" or host_os == "DragonFly" then
        return H.have("pkg") and "pkg" or nil
    end
    if host_os == "NetBSD" then return H.have("pkgin") and "pkgin" or nil end
    if host_os == "OpenBSD" then return "pkg_add" end

    local distro = detect_linux_distro()
    local prefer = {
        ubuntu = "apt", debian = "apt", linuxmint = "apt", pop = "apt",
        raspbian = "apt", kali = "apt",
        arch = "pacman", manjaro = "pacman", endeavouros = "pacman",
        garuda = "pacman", cachyos = "pacman",
        fedora = "dnf", rhel = "dnf", centos = "dnf", rocky = "dnf",
        almalinux = "dnf", amzn = "dnf",
        opensuse = "zypper", ["opensuse-tumbleweed"] = "zypper",
        ["opensuse-leap"] = "zypper", suse = "zypper",
        alpine = "apk", void = "xbps", gentoo = "emerge",
    }
    if prefer[distro] then
        local bins = { apt = "apt-get", dnf = "dnf", zypper = "zypper" }
        local bin = bins[prefer[distro]] or prefer[distro]
        if H.have(bin) then return prefer[distro] end
    end
    -- Fall back to whatever is installed.
    local order = { "apt-get", "pacman", "dnf", "yum", "zypper", "apk",
                    "xbps-install", "emerge" }
    local names = { apt = "apt", pacman = "pacman", dnf = "dnf",
                    yum = "dnf", zypper = "zypper", apk = "apk",
                    ["xbps-install"] = "xbps", emerge = "emerge" }
    for _, bin in ipairs(order) do
        if H.have(bin) then return names[bin] end
    end
    return nil
end

local MANAGER_PKG = nil  -- (reserved for future per-manager aliases)

----------------------------------------------------------------------------
-- Tool tables: pkgs[manager] = package name (nil = provided by base OS)
----------------------------------------------------------------------------

local REQUIRED_TOOLS = {
    { cmd = "make",     note = "GNU make",
      pkgs = { apt = "make", pacman = "make", dnf = "make", zypper = "make",
               apk = "make", xbps = "make", brew = "make", pkg = "gmake",
               pkgin = "gmake", pkg_add = "gmake" } },
    { cmd = "git",      note = "source fetch",
      pkgs = { apt = "git", pacman = "git", dnf = "git", zypper = "git",
               apk = "git", xbps = "git", brew = "git", pkg = "git",
               pkgin = "git-base", pkg_add = "git" } },
    { cmd = "patch",    note = "patching",
      pkgs = { apt = "patch", pacman = "patch", dnf = "patch",
               zypper = "patch", apk = "patch", xbps = "patch",
               brew = "patch", pkg = "patch", pkg_add = "patch" } },
    { cmd = "bmake",    note = "build system (auto-bootstrapped if missing)",
      optional = true,
      pkgs = { apt = "bmake", pacman = "bmake", dnf = "bmake",
               zypper = "bmake", apk = "bmake", xbps = "bmake",
               brew = "bmake", pkg = "bmake", pkgin = "bmake",
               pkg_add = "bmake" } },
    { cmd = "mktemp",   note = "temp files",
      pkgs = { apt = "coreutils", pacman = "coreutils", dnf = "coreutils",
               zypper = "coreutils", apk = "coreutils", xbps = "coreutils" } },
    { cmd = "install",  note = "file install",
      pkgs = { apt = "coreutils", pacman = "coreutils", dnf = "coreutils",
               zypper = "coreutils", apk = "coreutils", xbps = "coreutils" } },
    { cmd = "stat",     note = "file stat",
      pkgs = { apt = "coreutils", pacman = "coreutils", dnf = "coreutils",
               zypper = "coreutils", apk = "coreutils", xbps = "coreutils" } },
    { cmd = "readlink", note = "symlink read",
      pkgs = { apt = "coreutils", pacman = "coreutils", dnf = "coreutils",
               zypper = "coreutils", apk = "coreutils", xbps = "coreutils" } },
    { cmd = "realpath", note = "path resolve", optional = true,
      pkgs = { apt = "coreutils", pacman = "coreutils", dnf = "coreutils",
               zypper = "coreutils", apk = "coreutils", xbps = "coreutils" } },
    { cmd = "find",     note = "file search",
      pkgs = { apt = "findutils", pacman = "findutils", dnf = "findutils",
               zypper = "findutils", apk = "findutils",
               xbps = "findutils" } },
    { cmd = "tar",      note = "archives",
      pkgs = { apt = "tar", pacman = "tar", dnf = "tar", zypper = "tar",
               apk = "tar", xbps = "tar" } },
    { cmd = "xz",       note = "compression", optional = true,
      pkgs = { apt = "xz-utils", pacman = "xz", dnf = "xz", zypper = "xz",
               apk = "xz", xbps = "xz", brew = "xz", pkg = "xz",
               pkgin = "xz", pkg_add = "xz" } },
    { cmd = "grep",     note = "text search",
      pkgs = { apt = "grep", pacman = "grep", dnf = "grep", zypper = "grep",
               apk = "grep", xbps = "grep" } },
    { cmd = "sed",      note = "text edit",
      pkgs = { apt = "sed", pacman = "sed", dnf = "sed", zypper = "sed",
               apk = "sed", xbps = "sed" } },
    { cmd = "awk",      note = "text processing",
      pkgs = { apt = "gawk", pacman = "gawk", dnf = "gawk", zypper = "gawk",
               apk = "gawk", xbps = "gawk", brew = "gawk",
               pkg = "gawk", pkgin = "gawk" } },
}

local ISO_TOOLS = {
    { cmd = "mkisofs",  note = "ISO creation",
      pkgs = { apt = "genisoimage", pacman = "cdrtools", dnf = "genisoimage",
               zypper = "genisoimage", apk = "genisoimage", xbps = "cdrtools",
               brew = "cdrtools", pkg = "cdrtools", pkgin = "cdrtools",
               pkg_add = "cdrtools" } },
    { cmd = "xorriso",  note = "ISO creation (alt)", optional = true,
      pkgs = { apt = "xorriso", pacman = "xorriso", dnf = "xorriso",
               zypper = "xorriso", apk = "xorriso", xbps = "xorriso",
               brew = "xorriso", pkg = "xorriso", pkgin = "xorriso",
               pkg_add = "xorriso" } },
    { cmd = "mkfs.fat", note = "FAT ESP", optional = true,
      pkgs = { apt = "dosfstools", pacman = "dosfstools", dnf = "dosfstools",
               zypper = "dosfstools", apk = "dosfstools",
               xbps = "dosfstools", brew = "dosfstools", pkg = "dosfstools",
               pkgin = "dosfstools", pkg_add = "dosfstools" } },
    { cmd = "mcopy",    note = "FAT copy", optional = true,
      pkgs = { apt = "mtools", pacman = "mtools", dnf = "mtools",
               zypper = "mtools", apk = "mtools", xbps = "mtools",
               brew = "mtools", pkg = "mtools", pkgin = "mtools",
               pkg_add = "mtools" } },
}

local function check_tools(list)
    local missing = {}
    for _, tool in ipairs(list) do
        local found = H.have(tool.cmd)
        if not found and tool.alt then
            found = H.have(tool.alt)
        end
        if not found then
            missing[#missing + 1] = { cmd = tool.cmd, note = tool.note,
                                      pkgs = tool.pkgs,
                                      optional = tool.optional }
        end
    end
    return missing
end

local function sudo_prefix()
    local h = io.popen("id -u 2>/dev/null")
    local uid = h and h:read("*l") or "1"
    if h then h:close() end
    if uid == "0" then return "" end
    if H.have("sudo") then return "sudo " end
    if H.have("doas") then return "doas " end
    return nil  -- no privilege escalation available
end

-- Build the install command line for one manager.
local function install_cmd(manager, pkg)
    local rootless = { brew = true, pkg = true, pkgin = true }
    local pre = ""
    if not rootless[manager] then
        pre = sudo_prefix()
        if pre == nil then return nil end
    end

    if manager == "apt" then
        return pre .. "apt-get update -qq && " .. pre ..
               "apt-get install -y --no-install-recommends " .. pkg
    elseif manager == "pacman" then
        return pre .. "pacman -S --needed --noconfirm " .. pkg
    elseif manager == "dnf" then
        return pre .. "dnf install -y " .. pkg
    elseif manager == "zypper" then
        return pre .. "zypper --non-interactive install " .. pkg
    elseif manager == "apk" then
        return pre .. "apk add " .. pkg
    elseif manager == "xbps" then
        return pre .. "xbps-install -Sy " .. pkg
    elseif manager == "emerge" then
        return pre .. "emerge -1 " .. pkg
    elseif manager == "brew" then
        return "brew install " .. pkg .. " || true"
    elseif manager == "pkg" then
        return pre .. "pkg install -y " .. pkg
    elseif manager == "pkgin" then
        return pre .. "pkgin -y install " .. pkg
    elseif manager == "pkg_add" then
        return pre .. "pkg_add -I " .. pkg
    end
    return nil
end

-- Try to install every missing tool with the detected package manager.
local function install_missing(missing, manager)
    if not manager or #missing == 0 then return false end
    local batch, seen = {}, {}
    for _, m in ipairs(missing) do
        local pkg = m.pkgs and m.pkgs[manager]
        if pkg and pkg ~= "" and not seen[pkg] then
            seen[pkg] = true
            batch[#batch + 1] = pkg
        end
    end
    if #batch == 0 then return false end

    H.status("Installing dependencies via " .. c.bold .. c.white ..
             manager .. c.reset .. ": " .. table.concat(batch, " "))
    local cmd = install_cmd(manager, table.concat(batch, " "))
    if not cmd then
        H.warn("cannot build an install command for " .. tostring(manager))
        return false
    end
    return H.run(cmd)
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
        local manager = detect_manager()
        H.warn("missing tools:")
        for _, m in ipairs(missing) do
            local hint = ""
            if manager and m.pkgs and m.pkgs[manager] then
                hint = c.dim .. " (" .. manager .. ": " .. m.pkgs[manager] .. ")" .. c.reset
            end
            print("  " .. c.red .. m.cmd .. c.reset .. " - " .. m.note .. hint)
        end
        print()

        if cfg.no_deps then
            H.status("skipping dependency install (--no-deps)")
        else
            if not manager then
                H.warn("no supported package manager found; install the tools above manually")
            elseif not install_missing(missing, manager) then
                H.warn("could not install everything automatically; install the missing tools above manually")
            end
        end

        -- Re-check after any install attempt.
        local still = check_tools(REQUIRED_TOOLS)
        if check_iso then
            local iso_missing = check_tools(ISO_TOOLS)
            for _, m in ipairs(iso_missing) do still[#still + 1] = m end
        end
        local fatal = {}
        for _, m in ipairs(still) do
            if not m.optional then fatal[#fatal + 1] = m.cmd end
        end
        if #fatal > 0 then
            if cfg.runcmd == "echo" then
                H.status("dry-run: " .. table.concat(fatal, ", ") ..
                         " would be installed on the real build")
            else
                H.bomb("required tools still missing: " .. table.concat(fatal, ", "))
            end
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
    detect_manager  = detect_manager,
    install_missing = install_missing,
    install_cmd     = install_cmd,
    provision_shims = provision_shims,
    create_arch_symlinks    = create_arch_symlinks,
    create_kernel_symlinks  = create_kernel_symlinks,
}
