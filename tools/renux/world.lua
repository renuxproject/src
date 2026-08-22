--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    world.lua - world staging: pkg fork, root login, permissions.
]]

local cfg    = require("renux.config")
local H      = require("renux.helpers")
local loader = require("renux.loader")

local function build_pkg()
    if cfg.runcmd == "echo" then H.status("build renux pkg fork"); return end

    local pin     = "9c33ec4c6"
    local pkg_src = cfg.imagdir .. "/pkg-fork"
    local tgt     = cfg.target .. "-unknown-freebsd15.0"
    local sysroot = H.W()
    local make_j  = cfg.parallel or "-j4"

    H.status("Building the Renux pkg fork (parallel downloads) into the world root")

    if not os.execute("[ -d '" .. pkg_src .. "/.git' ]") then
        if not H.sh("git clone --depth 1 https://github.com/renuxproject/pkg.git '" .. pkg_src .. "' 2>&1") then
            H.status("warning: could not clone the Renux pkg fork; keeping the FreeBSD pkg bootstrap")
            return
        end
    end
    H.sh("cd '" .. pkg_src .. "' && git fetch --depth 1 origin '" .. pin .. "' 2>/dev/null && git checkout -f '" .. pin .. "' 2>/dev/null")

    local cc = "clang -target " .. tgt .. " --sysroot=" .. sysroot .. " -fuse-ld=lld"
    local cflags = "-I" .. sysroot .. "/usr/include"
    local ldflags = "-L" .. sysroot .. "/lib -L" .. sysroot .. "/usr/lib" ..
        " -Wl,-rpath-link," .. sysroot .. "/lib -Wl,-rpath-link," .. sysroot .. "/usr/lib" ..
        " -Wl,--undefined-version"
    local ok = H.sh("cd '" .. pkg_src .. "' && ./configure 'CC=" .. cc .. "' 'CFLAGS=" .. cflags ..
        "' 'LDFLAGS=" .. ldflags .. "' --prefix=/usr/local 2>&1")
    if ok then ok = H.sh("cd '" .. pkg_src .. "' && make " .. make_j .. " 2>&1") end
    if ok then ok = H.sh("cd '" .. pkg_src .. "' && make DESTDIR='" .. sysroot .. "' install 2>&1") end

    if not ok then
        H.status("warning: the Renux pkg fork failed to build; keeping the FreeBSD pkg bootstrap")
        return
    end

    H.sh("cp -f '" .. sysroot .. "/usr/local/sbin/pkg' '" .. sysroot .. "/usr/sbin/pkg' 2>/dev/null")
    H.status("Renux pkg fork installed (parallel downloads, PKG_PARALLEL_JOBS)")
end

local function stage_root_login()
    local etc = H.W() .. "/etc"
    H.mkdir_p(etc .. "/pkg"); H.mkdir_p(H.W() .. "/root")

    H.write_file(etc .. "/master.passwd", H.capture("cat '" .. cfg.srcdir .. "/etc/master.passwd'"))
    H.write_file(etc .. "/group", H.capture("cat '" .. cfg.srcdir .. "/etc/group'"))
    H.write_file(etc .. "/passwd", "root::0:0:Charlie &:/root:/bin/sh\n")

    H.write_file(etc .. "/fstab", [[
/dev/iso9660/RENUX	/	cd9660	ro	0 0
tmpfs			/tmp	tmpfs	rw,nosuid,mode=1777	0 0
tmpfs			/var/run	tmpfs	rw,nosuid		0 0
tmpfs			/var/tmp	tmpfs	rw,nosuid		0 0
tmpfs			/var/log	tmpfs	rw,nosuid		0 0
tmpfs			/var/db	tmpfs	rw,nosuid		0 0
]])

    if os.execute("[ -f '" .. etc .. "/ttys' ]") then
        H.sh("sed 's/[[:space:]]insecure[[:space:]]/ secure /g' '" .. etc .. "/ttys' > '" .. etc .. "/ttys.new' && mv -f '" .. etc .. "/ttys.new' '" .. etc .. "/ttys'")
    end

    H.write_file(etc .. "/rc.conf", 'hostname="renux"\nhostid_enable="NO"\n')
    H.write_file(etc .. "/rc.local", "/usr/sbin/pwd_mkdb -p /etc/master.passwd 2>/dev/null\n")
    H.sh("chmod 755 '" .. etc .. "/rc.local' 2>/dev/null")

    H.write_file(etc .. "/motd.template", [[
Welcome to Renux!

Renux is a modern BSD operating system - easy to maintain and debug, built
for portability and performance, and community-driven and decentralized.

Source code:  https://github.com/renuxproject/src
Website:      https://renuxproject.github.io
]])
    H.sh("chmod 644 '" .. etc .. "/motd.template' 2>/dev/null")
    H.sh("rm -f '" .. etc .. "/motd'; ln -s /var/run/motd '" .. etc .. "/motd' 2>/dev/null")

    H.sh("rm -f '" .. etc .. "/resolv.conf'; ln -s /var/run/resolv.conf '" .. etc .. "/resolv.conf' 2>/dev/null")

    if os.execute("[ -f '" .. etc .. "/pkg/FreeBSD.conf' ]") then
        H.sh("sed 's#\\${ABI}#FreeBSD:15:amd64#g' '" .. etc .. "/pkg/FreeBSD.conf' > '" .. etc .. "/pkg/FreeBSD.conf.new' && mv -f '" .. etc .. "/pkg/FreeBSD.conf.new' '" .. etc .. "/pkg/FreeBSD.conf'")
    end
end

local function generate_passwd_db()
    local etc = H.W() .. "/etc"
    if not os.execute("[ -f '" .. etc .. "/master.passwd' ]") then return end
    local pwdmkdb = H.objroot() .. "/tmp/legacy/usr/sbin/pwd_mkdb"
    if not os.execute("[ -x '" .. pwdmkdb .. "' ]") then
        H.status("warning: host pwd_mkdb not found; skipping passwd db generation")
        return
    end
    if H.run("'" .. pwdmkdb .. "' -d '" .. etc .. "' '" .. etc .. "/master.passwd'") then
        H.status("Generated " .. etc .. "/pwd.db and spwd.db")
    end
end

local function stage_world_root()
    local efi = loader.find_loader_efi()
    if not efi then H.bomb("EFI loader not found; build it first") end
    H.mkdir_p(H.W() .. "/EFI/BOOT")
    if cfg.runcmd ~= "echo" then
        if not os.execute("[ -f '" .. H.W() .. "/boot/kernel/kernel' ]") then
            H.bomb("world root missing kernel at " .. H.W() .. "/boot/kernel/kernel")
        end
        H.run("cp '" .. efi .. "' '" .. H.W() .. "/EFI/BOOT/BOOTX64.EFI'")
    end
    H.run("cp " .. cfg.srcdir .. "/stand/lua/*.lua '" .. H.W() .. "/boot/lua/'")
    H.run("cp " .. cfg.srcdir .. "/stand/images/*.png '" .. H.W() .. "/boot/images/'")
end

local function fix_world_root_perms()
    if cfg.runcmd == "echo" then H.status("fix world root perms"); return end
    H.mkdir_p(H.W() .. "/tmp " .. H.W() .. "/var/run/devd " .. H.W() .. "/var/tmp " .. H.W() .. "/var/log " .. H.W() .. "/var/db")
    H.sh("touch '" .. H.W() .. "/tmp/.keep' '" .. H.W() .. "/var/run/.keep' '" .. H.W() .. "/var/run/devd/.keep' '" .. H.W() .. "/var/tmp/.keep' '" .. H.W() .. "/var/log/.keep' '" .. H.W() .. "/var/db/.keep' 2>/dev/null")

    if H.have("chown") then
        local c = "chown -R 0:0 '" .. H.W() .. "'"
        if not H.sh(c .. " 2>/dev/null") and H.have("sudo") then H.sh("sudo " .. c .. " 2>/dev/null") end
    end

    for _, f in ipairs({
        "usr/bin/su", "usr/bin/passwd", "usr/bin/chpass", "usr/bin/lock",
        "usr/bin/login", "usr/bin/newgrp", "usr/bin/quota", "usr/bin/crontab",
        "usr/bin/at", "usr/bin/atq", "usr/bin/atrm", "usr/bin/batch", "usr/sbin/ppp",
    }) do
        H.sh("chmod u+s '" .. H.W() .. "/" .. f .. "' 2>/dev/null")
    end

    if os.execute("[ -d '" .. H.W() .. "/usr/include' ]") then
        local h = io.popen("find '" .. H.W() .. "/usr/include' -type l 2>/dev/null")
        for l in h:lines() do
            local tgt = H.capture("readlink '" .. l .. "'")
            local rel = tgt:gsub("^([%.%./]*)", ""):gsub("^%/", "")
            if rel ~= "" and os.execute("[ -f '" .. cfg.srcdir .. "/" .. rel .. "' ]") then
                H.sh("cp -f '" .. cfg.srcdir .. "/" .. rel .. "' '" .. l .. "' 2>/dev/null")
            end
        end
        h:close()
    end
end

return {
    build_pkg              = build_pkg,
    stage_root_login       = stage_root_login,
    generate_passwd_db     = generate_passwd_db,
    stage_world_root       = stage_world_root,
    fix_world_root_perms   = fix_world_root_perms,
}
