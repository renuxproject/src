--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilário.  All rights reserved.

    renux.lua - the Renux build utility (Lua core, run by flua).

    A clean, elegant driver for building the Renux operating system.  It
    delegates the heavy lifting (world, kernel, installworld) to make.py /
    bmake, and stages bootable live/installer media itself.

    Usage: ./renux [options] operation [operation...]
]]

local os, io = os, io
local exit, getenv = os.exit, os.getenv

----------------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------------

local script_dir = arg[0]:match("^(.+)/[^/]+$") or "."
local _p = io.popen("cd '" .. script_dir .. "' && pwd")
local root = _p:read("*l"); _p:close()

local cfg = {
    srcdir          = root,
    makeobjdir      = getenv("MAKEOBJDIRPREFIX") or root .. "/obj",
    target          = getenv("TARGET") or "amd64",
    target_arch     = getenv("TARGET_ARCH") or "amd64",
    kernconf        = "GENERIC",
    imagdir         = "release",
    parallel        = nil,
    runcmd          = "",                 -- "" or "echo"
    qemu_mem        = getenv("QEMU_MEM") or "1024",
    qemu_display    = getenv("QEMU_DISPLAY") or "default",
    qemu_serial     = getenv("QEMU_SERIAL") or "stdio",
    espmb           = 128,
    update          = false,
    kernel_only     = false,
    make_py         = root .. "/tools/build/make.py",
}

-- Resolve a path to absolute (installworld's NO_ROOT -M/-D flags are used
-- from sub-makes whose CWD is the object tree, so relative paths break).
-- Defined here; initialized with a call after the helpers below.
local abs_path
cfg.worlddir = cfg.imagdir .. "/world-root"

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function sh(cmd)
    return os.execute(cmd)
end

local function capture(cmd)
    local h = io.popen(cmd)
    if not h then return "" end
    local out = h:read("*a"); h:close()
    return (out or ""):gsub("%s+$", "")
end

local function run(cmd)
    if cfg.runcmd == "echo" then print(cmd); return true end
    print("+ " .. cmd)
    return sh(cmd)
end

local function bomb(msg)
    io.stderr:write("ERROR: " .. msg .. "\n")
    exit(1)
end

local function status(msg)
    print("==> " .. msg)
end

local function is_bsd()
    local u = capture("uname -s")
    return u == "FreeBSD" or u == "NetBSD" or u == "OpenBSD" or u == "DragonFly"
end

local function is_darwin()
    return capture("uname -s") == "Darwin"
end

local function have(cmd)
    return sh("command -v '" .. cmd .. "' >/dev/null 2>&1")
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then bomb("cannot write " .. path .. ": " .. tostring(err)) end
    f:write(content); f:close()
end

local function mkdir_p(dir)
    return sh("mkdir -p '" .. dir .. "'")
end

local function objroot()
    return cfg.makeobjdir .. cfg.srcdir .. "/" .. cfg.target .. "." .. cfg.target_arch
end

abs_path = function(p)
    sh("mkdir -p '" .. p .. "' 2>/dev/null")
    local h = io.popen("cd '" .. p .. "' && pwd")
    local out = h:read("*l"); h:close()
    return out or p
end
cfg.imagdir = abs_path(cfg.imagdir)
cfg.worlddir = cfg.imagdir .. "/world-root"

local W = function() return cfg.worlddir end

----------------------------------------------------------------------------
-- Loader discovery
----------------------------------------------------------------------------

local function find_loader(patterns)
    local obj = objroot()
    for _, tmpl in ipairs(patterns) do
        local c = tmpl:gsub("{OBJ}", obj):gsub("{SRC}", cfg.srcdir)
        if os.execute("[ -f '" .. c .. "' ]") then return c end
    end
    return nil
end

local function find_loader_efi()
    return find_loader({
        "{OBJ}/stand/efi/loader_lua/loader_lua.efi",
        "{SRC}/stand/efi/loader_lua/loader_lua.efi",
        "{OBJ}/stand/efi/loader_simp/loader_simp.efi",
        "{SRC}/stand/efi/loader_simp/loader_simp.efi",
    })
end

local function find_bios_loader()
    return find_loader({
        "{OBJ}/stand/i386/loader_lua/loader_lua",
        "{SRC}/stand/i386/loader_lua/loader_lua",
    })
end

local function find_cdboot()
    return find_loader({ "{OBJ}/stand/i386/cdboot/cdboot", "{SRC}/stand/i386/cdboot/cdboot" })
end

----------------------------------------------------------------------------
-- make.py driver
----------------------------------------------------------------------------

local function build_make_cmd(ops)
    local cmd = "python3 '" .. cfg.make_py .. "'"
    if have("clang") and not is_darwin() then
        local cb = capture("cd \"$(dirname \"$(command -v clang)\")\" && pwd")
        if cb ~= "" then cmd = cmd .. " --cross-bindir=" .. cb end
    end
    if cfg.update then cmd = cmd .. " --no-clean" end
    if cfg.parallel then cmd = cmd .. " " .. cfg.parallel end
    cmd = cmd .. " TARGET=" .. cfg.target .. " TARGET_ARCH=" .. cfg.target_arch
    cmd = cmd .. " MK_SSP=no MK_TESTS=no"

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
            did = true; cmd = cmd .. " buildtools"
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
            -- NO_ROOT installworld only records dirs in the METALOG
            -- (distrib-dirs) instead of creating them physically, so a fresh
            -- DESTDIR lacks them.  Pre-create the base dirs + an empty
            -- METALOG so installworld works on the first attempt.
            for _, d in ipairs({
                "/bin", "/sbin", "/etc", "/root", "/dev", "/tmp", "/var", "/usr",
                "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
                "/usr/include", "/usr/src", "/usr/tests", "/usr/lib/debug",
                "/usr/lib32", "/usr/local",
                "/var/run/devd", "/var/tmp", "/var/log", "/var/db",
                "/var/spool", "/var/empty", "/var/mail", "/var/account",
            }) do
                sh("mkdir -p '" .. cfg.worlddir .. d .. "'")
            end
            sh("touch '" .. cfg.worlddir .. "/METALOG'")
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

----------------------------------------------------------------------------
-- World staging
----------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Build the Renux pkg (the parallel-download fork) into the world root.
--
-- Cross-compiles the renuxproject/pkg fork against the installed world as
-- the sysroot and replaces the base FreeBSD bootstrap at /usr/sbin/pkg, so
-- the live/installed system never downloads pkg from pkg.FreeBSD.org.
-- On failure we warn and keep the bootstrap, so the ISO still builds.
---------------------------------------------------------------------------

local function build_pkg()
    if cfg.runcmd == "echo" then status("build renux pkg fork"); return end

    local pin     = "9c33ec4c6"
    local pkg_src = cfg.imagdir .. "/pkg-fork"
    local tgt     = cfg.target .. "-unknown-freebsd15.0"
    local sysroot = W()
    local make_j  = cfg.parallel or "-j4"

    status("Building the Renux pkg fork (parallel downloads) into the world root")

    if not os.execute("[ -d '" .. pkg_src .. "/.git' ]") then
        if not sh("git clone --depth 1 https://github.com/renuxproject/pkg.git '" .. pkg_src .. "' 2>&1") then
            status("warning: could not clone the Renux pkg fork; keeping the FreeBSD pkg bootstrap")
            return
        end
    end
    sh("cd '" .. pkg_src .. "' && git fetch --depth 1 origin '" .. pin .. "' 2>/dev/null && git checkout -f '" .. pin .. "' 2>/dev/null")

    local cc = "clang -target " .. tgt .. " --sysroot=" .. sysroot .. " -fuse-ld=lld"
    local cflags = "-I" .. sysroot .. "/usr/include"
    local ldflags = "-L" .. sysroot .. "/lib -L" .. sysroot .. "/usr/lib" ..
        " -Wl,-rpath-link," .. sysroot .. "/lib -Wl,-rpath-link," .. sysroot .. "/usr/lib" ..
        " -Wl,--undefined-version"
    local ok = sh("cd '" .. pkg_src .. "' && ./configure 'CC=" .. cc .. "' 'CFLAGS=" .. cflags ..
        "' 'LDFLAGS=" .. ldflags .. "' --prefix=/usr/local 2>&1")
    if ok then ok = sh("cd '" .. pkg_src .. "' && make " .. make_j .. " 2>&1") end
    if ok then ok = sh("cd '" .. pkg_src .. "' && make DESTDIR='" .. sysroot .. "' install 2>&1") end

    if not ok then
        status("warning: the Renux pkg fork failed to build; keeping the FreeBSD pkg bootstrap")
        return
    end

    -- Make `pkg` unambiguously the Renux fork: replace the base bootstrap
    -- (/usr/sbin/pkg), which sits before /usr/local/sbin on the default PATH.
    sh("cp -f '" .. sysroot .. "/usr/local/sbin/pkg' '" .. sysroot .. "/usr/sbin/pkg' 2>/dev/null")
    status("Renux pkg fork installed (parallel downloads, PKG_PARALLEL_JOBS)")
end

local function stage_root_login()
    local etc = W() .. "/etc"
    mkdir_p(etc .. "/pkg"); mkdir_p(W() .. "/root")

    write_file(etc .. "/master.passwd", capture("cat '" .. cfg.srcdir .. "/etc/master.passwd'"))
    write_file(etc .. "/group", capture("cat '" .. cfg.srcdir .. "/etc/group'"))
    write_file(etc .. "/passwd", "root::0:0:Charlie &:/root:/bin/sh\n")

    write_file(etc .. "/fstab", [[
/dev/iso9660/RENUX	/	cd9660	ro	0 0
tmpfs			/tmp	tmpfs	rw,nosuid,mode=1777	0 0
tmpfs			/var/run	tmpfs	rw,nosuid		0 0
tmpfs			/var/tmp	tmpfs	rw,nosuid		0 0
tmpfs			/var/log	tmpfs	rw,nosuid		0 0
tmpfs			/var/db	tmpfs	rw,nosuid		0 0
]])

    if os.execute("[ -f '" .. etc .. "/ttys' ]") then
        sh("sed 's/[[:space:]]insecure[[:space:]]/ secure /g' '" .. etc .. "/ttys' > '" .. etc .. "/ttys.new' && mv -f '" .. etc .. "/ttys.new' '" .. etc .. "/ttys'")
    end

    write_file(etc .. "/rc.conf", 'hostname="renux"\nhostid_enable="NO"\n')
    write_file(etc .. "/rc.local", "/usr/sbin/pwd_mkdb -p /etc/master.passwd 2>/dev/null\n")
    sh("chmod 755 '" .. etc .. "/rc.local' 2>/dev/null")

    write_file(etc .. "/motd.template", [[
Welcome to Renux!

Renux is a modern BSD operating system - easy to maintain and debug, built
for portability and performance, and community-driven and decentralized.

Source code:  https://github.com/renuxproject/src
Website:      https://renuxproject.github.io
]])
    sh("chmod 644 '" .. etc .. "/motd.template' 2>/dev/null")
    sh("rm -f '" .. etc .. "/motd'; ln -s /var/run/motd '" .. etc .. "/motd' 2>/dev/null")

    sh("rm -f '" .. etc .. "/resolv.conf'; ln -s /var/run/resolv.conf '" .. etc .. "/resolv.conf' 2>/dev/null")

    if os.execute("[ -f '" .. etc .. "/pkg/FreeBSD.conf' ]") then
        sh("sed 's#\\${ABI}#FreeBSD:15:amd64#g' '" .. etc .. "/pkg/FreeBSD.conf' > '" .. etc .. "/pkg/FreeBSD.conf.new' && mv -f '" .. etc .. "/pkg/FreeBSD.conf.new' '" .. etc .. "/pkg/FreeBSD.conf'")
    end
end

local function generate_passwd_db()
    local etc = W() .. "/etc"
    if not os.execute("[ -f '" .. etc .. "/master.passwd' ]") then return end
    local pwdmkdb = objroot() .. "/tmp/legacy/usr/sbin/pwd_mkdb"
    if not os.execute("[ -x '" .. pwdmkdb .. "' ]") then
        status("warning: host pwd_mkdb not found; skipping passwd db generation")
        return
    end
    if run("'" .. pwdmkdb .. "' -d '" .. etc .. "' '" .. etc .. "/master.passwd'") then
        status("Generated " .. etc .. "/pwd.db and spwd.db")
    end
end

local function stage_world_root()
    local loader = find_loader_efi()
    if not loader then bomb("EFI loader not found; build it first") end
    mkdir_p(W() .. "/EFI/BOOT")
    if cfg.runcmd ~= "echo" then
        if not os.execute("[ -f '" .. W() .. "/boot/kernel/kernel' ]") then
            bomb("world root missing kernel at " .. W() .. "/boot/kernel/kernel")
        end
        run("cp '" .. loader .. "' '" .. W() .. "/EFI/BOOT/BOOTX64.EFI'")
    end
    run("cp " .. cfg.srcdir .. "/stand/lua/*.lua '" .. W() .. "/boot/lua/'")
    run("cp " .. cfg.srcdir .. "/stand/images/*.png '" .. W() .. "/boot/images/'")
end

local function fix_world_root_perms()
    if cfg.runcmd == "echo" then status("fix world root perms"); return end
    mkdir_p(W() .. "/tmp " .. W() .. "/var/run/devd " .. W() .. "/var/tmp " .. W() .. "/var/log " .. W() .. "/var/db")
    sh("touch '" .. W() .. "/tmp/.keep' '" .. W() .. "/var/run/.keep' '" .. W() .. "/var/run/devd/.keep' '" .. W() .. "/var/tmp/.keep' '" .. W() .. "/var/log/.keep' '" .. W() .. "/var/db/.keep' 2>/dev/null")

    if have("chown") then
        local c = "chown -R 0:0 '" .. W() .. "'"
        if not sh(c .. " 2>/dev/null") and have("sudo") then sh("sudo " .. c .. " 2>/dev/null") end
    end

    for _, f in ipairs({
        "usr/bin/su", "usr/bin/passwd", "usr/bin/chpass", "usr/bin/lock",
        "usr/bin/login", "usr/bin/newgrp", "usr/bin/quota", "usr/bin/crontab",
        "usr/bin/at", "usr/bin/atq", "usr/bin/atrm", "usr/bin/batch", "usr/sbin/ppp",
    }) do
        sh("chmod u+s '" .. W() .. "/" .. f .. "' 2>/dev/null")
    end

    if os.execute("[ -d '" .. W() .. "/usr/include' ]") then
        local h = io.popen("find '" .. W() .. "/usr/include' -type l 2>/dev/null")
        for l in h:lines() do
            local tgt = capture("readlink '" .. l .. "'")
            local rel = tgt:gsub("^([%.%./]*)", ""):gsub("^%/", "")
            if rel ~= "" and os.execute("[ -f '" .. cfg.srcdir .. "/" .. rel .. "' ]") then
                sh("cp -f '" .. cfg.srcdir .. "/" .. rel .. "' '" .. l .. "' 2>/dev/null")
            end
        end
        h:close()
    end
end

local function make_world_esp()
    local img = cfg.imagdir .. "/renux-esp-boot.img"
    local stage = cfg.imagdir .. "/esp-boot-stage"
    local loader = find_loader_efi()
    if not loader then bomb("EFI loader not found") end
    mkdir_p(stage .. "/EFI/BOOT")
    run("cp '" .. loader .. "' '" .. stage .. "/EFI/BOOT/BOOTX64.EFI'")
    status("Building EFI boot ESP " .. img)
    if is_bsd() then
        if not have("makefs") then bomb("makefs is required on this host") end
        run("makefs -t msdos -o fat_type=32 -o volume_label=RENUX '" .. img .. "' '" .. stage .. "'")
    else
        if not (have("mkfs.fat") and have("mcopy")) then bomb("mkfs.fat and mcopy are required") end
        run("rm -f '" .. img .. "'")
        run("truncate -s " .. (cfg.espmb * 1024 * 1024) .. " '" .. img .. "'")
        run("mkfs.fat -F32 -n RENUX '" .. img .. "' >/dev/null")
        run("mcopy -i '" .. img .. "' -s '" .. stage .. "/*' ::/")
    end
end

local function make_world_hybrid_iso()
    local cdboot = find_cdboot() or "<cdboot>"
    local loader = find_bios_loader() or "<bios-loader>"
    if cfg.runcmd ~= "echo" then
        run("cp '" .. cdboot .. "' '" .. W() .. "/cdboot'")
        run("cp '" .. loader .. "' '" .. W() .. "/boot/loader'")
    end
    write_file(W() .. "/boot/loader.conf", [[
autoboot_delay="2"
loader_logo="renux"
vfs.root.mountfrom="cd9660:/dev/iso9660/RENUX"
]])
    run("cp '" .. W() .. "/boot/loader.conf' '" .. W() .. "/boot/defaults/loader.conf'")

    local iso = cfg.imagdir .. "/renux-installer.iso"
    status("Building hybrid BIOS+UEFI world ISO " .. iso)
    if is_bsd() then
        if not have("makefs") then bomb("makefs is required on this host") end
        run("makefs -t cd9660 -o label=RENUX -o bootimage=i386\\;" .. cdboot .. " -o no-emul-boot -o bootimage=efi\\;" .. cfg.imagdir .. "/renux-esp-boot.img -o no-emul-boot -o platformid=efi '" .. W() .. "' '" .. iso .. "'")
    else
        if not have("xorriso") then bomb("xorriso is required to build an ISO on this host") end
        run("cp '" .. cfg.imagdir .. "/renux-esp-boot.img' '" .. W() .. "/renux-esp.img'")
        run("xorriso -as mkisofs -V RENUX -o '" .. iso .. "' -R -b cdboot -c boot.cat -no-emul-boot -boot-load-size 4 -eltorito-alt-boot -e renux-esp.img -no-emul-boot -isohybrid-gpt-basdat '" .. W() .. "'")
        run("rm -f '" .. W() .. "/renux-esp.img'")
    end
    -- Ship a max-compression .xz too (GitHub caps release assets at 2 GiB,
    -- and a compressed image is a much smaller download).
    if have("xz") then
        status("Compressing " .. iso .. " (xz -9e)...")
        if cfg.runcmd ~= "echo" then
            run("xz -9e -T0 -c '" .. iso .. "' > '" .. iso .. ".xz'")
        else
            print("xz -9e -T0 -c '" .. iso .. "' > '" .. iso .. ".xz'")
        end
    else
        status("warning: xz not found; skipping .xz build")
    end
end

----------------------------------------------------------------------------
-- Informational
----------------------------------------------------------------------------

local function show_params()
    print("SRCDIR           = " .. cfg.srcdir)
    print("MAKEOBJDIRPREFIX = " .. cfg.makeobjdir)
    print("TARGET           = " .. cfg.target)
    print("TARGET_ARCH      = " .. cfg.target_arch)
    print("KERNCONF         = " .. cfg.kernconf)
    print("IMAGEDIR         = " .. cfg.imagdir)
    print("WORLDDIR         = " .. cfg.worlddir)
end

local function list_arch()
    local h = io.popen("grep '^MACHINE=' '" .. cfg.srcdir .. "/build.sh' 2>/dev/null")
    for line in h:lines() do
        local m = line:match("^MACHINE=([%w]+) MACHINE_ARCH=([%w]+)")
        if m then print(m .. " " .. m) end
    end
    h:close()
end

local function usage()
    print([[
renux - the Renux build utility.

Usage: ./renux [options] operation [operation...]

Options:
  -j N           parallel make (-j N)
  -I DIR         image output directory (default: release)
  -K             kernel-only (skip buildworld)
  -m MACHINE     target machine (default: amd64)
  -a ARCH        target architecture (default: amd64)
  -M DIR         object root (MAKEOBJDIRPREFIX)
  -n             dry run (show commands only)
  -u             incremental build (no clean)
  -h, --help     show this help

Operations:
  build            buildworld + buildkernel
  kernel=KERNCONF  build only the kernel
  kernels          build all kernels
  world            buildworld
  iso              kernel-only boot ISO + UEFI disk image
  bootimage        kernel-only boot images
  worldiso         full live/installer hybrid ISO (renux-installer.iso)
  install=DIR      installworld + installkernel into DIR
  qemu|run         boot in QEMU
  clean            remove the object tree
  update           git pull --ff-only
  show-params      show the build parameters
  list-arch        list supported architectures
]])
end

----------------------------------------------------------------------------
-- Main
----------------------------------------------------------------------------

local args = {}
for i = 1, #arg do args[i] = arg[i] end

local operations = {}
local pos = 1
while pos <= #args do
    local a = args[pos]
    if a == "-j" or a == "-I" or a == "-m" or a == "-a" or a == "-M" then
        local val = args[pos + 1] or ""
        if a == "-j" then cfg.parallel = "-j " .. val
        elseif a == "-I" then cfg.imagdir = abs_path(val); cfg.worlddir = cfg.imagdir .. "/world-root"
        elseif a == "-m" then cfg.target = val
        elseif a == "-a" then cfg.target_arch = val
        elseif a == "-M" then cfg.makeobjdir = val
        end
        pos = pos + 2
    elseif a == "-K" then cfg.kernel_only = true; pos = pos + 1
    elseif a == "-n" then cfg.runcmd = "echo"; pos = pos + 1
    elseif a == "-u" then cfg.update = true; pos = pos + 1
    elseif a == "-h" or a == "--help" then usage(); exit(0)
    elseif a:sub(1, 1) == "-" then
        io.stderr:write("renux: unknown option: " .. a .. "\n"); exit(1)
    else
        operations[#operations + 1] = a; pos = pos + 1
    end
end

if #operations == 0 then usage(); exit(0) end

for _, op in ipairs(operations) do
    if op == "show-params" then show_params(); exit(0) end
    if op == "list-arch" then list_arch(); exit(0) end
end

local do_image, world_image = false, false
for _, op in ipairs(operations) do
    if op == "worldiso" then do_image, world_image = true, true
    elseif op == "iso" or op == "bootimage" or op == "qemu" or op == "run" then do_image = true end
end

local cmd, did = build_make_cmd(operations)

if did then
    status("Command: " .. cmd)
    if cfg.runcmd == "echo" then print(cmd) else
        if not sh(cmd) then bomb("make.py build command failed") end
    end
end

if do_image then
    mkdir_p(cfg.imagdir)
    if world_image then
        build_pkg()
        stage_root_login()
        generate_passwd_db()
        stage_world_root()
        fix_world_root_perms()
        make_world_esp()
        make_world_hybrid_iso()
    else
        bomb("kernel-only images: the mini-userland is not ported yet; use 'worldiso'")
    end
end

status("renux: done")
