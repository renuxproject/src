--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    main.lua - Renux build utility entry point.
]]

local cfg     = require("renux.config")
local H       = require("renux.helpers")
local Make    = require("renux.make")
local World   = require("renux.world")
local Image   = require("renux.image")
local Setup   = require("renux.setup")
local c       = H.c

cfg.abs_init(H.abs_path)

local function show_params()
    local t = {
        { "SRCDIR",           cfg.srcdir },
        { "MAKEOBJDIRPREFIX", cfg.makeobjdir },
        { "TARGET",           cfg.target },
        { "TARGET_ARCH",      cfg.target_arch },
        { "KERNCONF",         cfg.kernconf },
        { "IMAGEDIR",         cfg.imagdir },
        { "WORLDDIR",         cfg.worlddir },
    }
    for _, row in ipairs(t) do
        print(c.bold .. c.white .. string.format("%-18s", row[1]) .. c.reset .. " " .. c.dim .. "=" .. c.reset .. " " .. c.cyan .. row[2] .. c.reset)
    end
end

local function list_arch()
    local archs = {}
    local h = io.popen("ls -1 '" .. cfg.srcdir .. "/sys/arch/' 2>/dev/null")
    if not h then H.bomb("could not list sys/arch/") end
    for line in h:lines() do
        if line ~= "x86" then archs[#archs + 1] = line end
    end
    h:close()
    table.sort(archs)
    for _, m in ipairs(archs) do
        print("  " .. c.cyan .. m .. c.reset)
    end
end

local function usage()
    H.banner()
    print(c.bold .. "Usage:" .. c.reset .. " " .. c.green .. "./renux" .. c.reset ..
        " [options] " .. c.yellow .. "operation" .. c.reset ..
        " [" .. c.yellow .. "operation" .. c.reset .. "...]")
    print()
    print(c.bold .. "Options:" .. c.reset)
    local opts = {
        { "-j N",           "parallel make (-j N)" },
        { "-I DIR",         "image output directory (default: release)" },
        { "-K",             "kernel-only (skip buildworld)" },
        { "-m MACHINE",     "target machine (default: amd64)" },
        { "-a ARCH",        "target architecture (default: amd64)" },
        { "-M DIR",         "object root (MAKEOBJDIRPREFIX)" },
        { "-n, --dry-run",  "dry run (show commands only)" },
        { "-u",             "incremental build (no clean)" },
        { "--",             "pass remaining flags to make.py" },
        { "-h, --help",     "show this help" },
        { "-v, --version",  "show version" },
    }
    for _, o in ipairs(opts) do
        print("  " .. c.cyan .. string.format("%-16s", o[1]) .. c.reset .. " " .. o[2])
    end
    print()
    print(c.bold .. "Build:" .. c.reset)
    local builds = {
        { "build",          "buildworld + buildkernel" },
        { "kernel=KERN",    "build only the kernel" },
        { "kernels",        "build all kernels" },
        { "world",          "buildworld" },
        { "tools",          "buildtools" },
        { "release",        "build a release" },
    }
    for _, b in ipairs(builds) do
        print("  " .. c.green .. string.format("%-16s", b[1]) .. c.reset .. " " .. b[2])
    end
    print()
    print(c.bold .. "Images:" .. c.reset)
    local imgs = {
        { "iso",            "kernel-only boot ISO + UEFI disk image" },
        { "bootimage",      "kernel-only boot images" },
        { "worldiso",       "full live/installer hybrid ISO" },
        { "qemu|run",       "boot in QEMU" },
    }
    for _, im in ipairs(imgs) do
        print("  " .. c.magenta .. string.format("%-16s", im[1]) .. c.reset .. " " .. im[2])
    end
    print()
    print(c.bold .. "System:" .. c.reset)
    local sys = {
        { "install=DIR",    "installworld + installkernel into DIR" },
        { "clean",          "remove the object tree" },
        { "update",         "git pull --ff-only" },
        { "show-params",    "show the build parameters" },
        { "list-arch",      "list supported architectures" },
    }
    for _, s in ipairs(sys) do
        print("  " .. c.white .. string.format("%-16s", s[1]) .. c.reset .. " " .. s[2])
    end
    print()
    print(c.bold .. "Examples:" .. c.reset)
    print("  " .. c.dim .. "# Build everything" .. c.reset)
    print("  ./renux build")
    print("  " .. c.dim .. "# Build kernel only" .. c.reset)
    print("  ./renux kernel=GENERIC")
    print("  " .. c.dim .. "# Build and boot in QEMU" .. c.reset)
    print("  ./renux build worldiso qemu")
    print("  " .. c.dim .. "# Forward flags to make.py" .. c.reset)
    print("  ./renux kernels " .. c.dim .. "-- -s -DWITH_DISK_IMAGE_TOOLS_BOOTSTRAP" .. c.reset)
    print()
end

return function(main_arg)
    local args = {}
    for i = 1, #main_arg do args[i] = main_arg[i] end

    local operations = {}
    local pos = 1
    while pos <= #args do
        local a = args[pos]
        if a == "-j" or a == "-I" or a == "-m" or a == "-a" or a == "-M" then
            local val = args[pos + 1] or ""
            if a == "-j" then cfg.parallel = "-j " .. val
            elseif a == "-I" then cfg.imagdir = H.abs_path(val); cfg.worlddir = cfg.imagdir .. "/world-root"
            elseif a == "-m" then cfg.target = val
            elseif a == "-a" then cfg.target_arch = val
            elseif a == "-M" then cfg.makeobjdir = val
            end
            pos = pos + 2
        elseif a == "-K" then cfg.kernel_only = true; pos = pos + 1
        elseif a == "-n" or a == "--dry-run" then cfg.runcmd = "echo"; pos = pos + 1
        elseif a == "-u" then cfg.update = true; pos = pos + 1
        elseif a == "-v" or a == "--version" then
            print(c.bold .. "renux" .. c.reset .. " " .. c.cyan .. cfg.version .. c.reset)
            os.exit(0)
        elseif a == "-h" or a == "--help" then usage(); os.exit(0)
        elseif a == "--" then
            pos = pos + 1
            local extra = {}
            while pos <= #args do
                local x = args[pos]
                if x:match("^%-%-") or x:match("^%-[^-]") or x:match("^[A-Z_]+=") then
                    extra[#extra + 1] = x
                else
                    operations[#operations + 1] = x
                end
                pos = pos + 1
            end
            cfg.extra_args = table.concat(extra, " ")
        elseif a:sub(1, 1) == "-" then
            io.stderr:write(c.red .. "error" .. c.reset .. ": unknown option: " .. a .. "\n")
            os.exit(1)
        else
            operations[#operations + 1] = a; pos = pos + 1
        end
    end

    if #operations == 0 then usage(); os.exit(0) end

    for _, op in ipairs(operations) do
        if op == "show-params" then show_params(); os.exit(0) end
        if op == "list-arch" then list_arch(); os.exit(0) end
        if op == "clean" then
            H.status("Cleaning object tree: " .. cfg.makeobjdir)
            H.sh("rm -rf '" .. cfg.makeobjdir .. "'")
            H.status("Clean done")
            os.exit(0)
        end
        if op == "update" then
            H.status("Pulling latest changes...")
            H.sh("cd '" .. cfg.srcdir .. "' && git pull --ff-only")
            os.exit(0)
        end
    end

    H.banner()

    local needs_build = false
    local needs_image = false
    for _, op in ipairs(operations) do
        if op == "build" or op == "world" or op == "tools" or op == "release" or
           op:match("^kernel=") or op:match("^kernel.gdb=") or op == "kernels" or
           op:match("^install=") or op == "worldiso" then
            needs_build = true
        end
        if op == "worldiso" or op == "iso" or op == "bootimage" or op == "qemu" or op == "run" then
            needs_image = true
        end
    end

    if needs_build or needs_image then
        Setup.run(needs_image)
        print()
    end

    local do_image, world_image = false, false
    for _, op in ipairs(operations) do
        if op == "worldiso" then do_image, world_image = true, true
        elseif op == "iso" or op == "bootimage" or op == "qemu" or op == "run" then do_image = true end
    end

    H.status("Building for " .. c.bold .. c.white .. cfg.target .. "/" .. cfg.target_arch .. c.reset ..
             " (kernel: " .. c.bold .. c.magenta .. cfg.kernconf .. c.reset .. ")")
    print()

    local cmd, did = Make.build_make_cmd(operations)

    if did then
        H.status("Command: " .. c.dim .. cmd .. c.reset)
        if cfg.runcmd ~= "echo" then
            print()
            if not H.sh(cmd) then H.bomb("make.py build command failed") end
        end
    end

    if do_image then
        H.mkdir_p(cfg.imagdir)
        if world_image then
            World.build_pkg()
            World.stage_root_login()
            World.generate_passwd_db()
            World.stage_world_root()
            World.fix_world_root_perms()
            Image.make_world_esp()
            Image.make_world_hybrid_iso()
        else
            H.bomb("kernel-only images not ported yet; use 'worldiso'")
        end
    end

    print()
    H.status(c.bold .. c.green .. "renux: done" .. c.reset)
end
