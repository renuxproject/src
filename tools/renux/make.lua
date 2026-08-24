--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    make.lua - native bmake driver.  Finds (or bootstraps) bmake, infers
    the compiler environment and assembles the final build command,
    replacing the old python3 make.py wrapper.
]]

local cfg = require("renux.config")
local H   = require("renux.helpers")

----------------------------------------------------------------------------
-- Small utilities
----------------------------------------------------------------------------

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function which(bin)
    local out = H.capture("command -v " .. q(bin) .. " 2>/dev/null")
    if out ~= "" and file_exists(out) then return out end
    return nil
end

local function bmake_version(path)
    local v = H.capture(q(path) .. " -r -f /dev/null -V MAKE_VERSION 2>/dev/null")
    return tonumber(v)
end

local function src_version()
    local f = io.open(cfg.srcdir .. "/contrib/bmake/VERSION", "r")
    if not f then H.bomb("cannot read contrib/bmake/VERSION") end
    local body = f:read("*a"); f:close()
    return tonumber(body:match('_MAKE_VERSION="?(%d+)"?'))
end

local brew_prefix_cache = {}
local function brew_prefix(pkg)
    if brew_prefix_cache[pkg] == nil then
        brew_prefix_cache[pkg] = H.capture("brew --prefix " .. q(pkg) .. " 2>/dev/null")
    end
    return brew_prefix_cache[pkg]
end

local function bindir_has(bindir, bin)
    if bindir == nil or bindir == "" then return false end
    return file_exists(bindir .. "/bin/" .. bin)
end

-- Resolve a directory containing the cross tools, mirroring make.py:
-- explicit --cross-bindir wins; otherwise Homebrew llvm/lld on macOS.
local function cross_bindir(binary_name, package, args)
    if args.cross_bindir then return args.cross_bindir end
    if H.is_darwin() and H.have("brew") then
        package = package or "llvm"
        local p = brew_prefix(package)
        if p ~= "" and bindir_has(p, binary_name) then return p .. "/bin" end
        -- lld is a separate Homebrew package for LLVM 19+
        if binary_name == "ld.lld" then
            local lp = brew_prefix(package:gsub("llvm", "lld"))
            if lp ~= "" and bindir_has(lp, binary_name) then return lp .. "/bin" end
        end
    end
    return nil
end

-- Infer one tool into env unless already set; mirrors make.py's
-- check_required_make_env_var.
local function infer_tool(env, varname, binary, bindir)
    if os.getenv(varname) then return end
    if not bindir then
        H.bomb("could not infer $" .. varname .. ": set $" .. varname ..
               ", pass --cross-bindir=<dir> or install llvm (macOS)")
    end
    local guess = bindir .. "/" .. binary
    if not file_exists(guess) then
        H.bomb("could not infer $" .. varname .. ": " .. guess .. " does not exist")
    end
    env[#env + 1] = { varname, guess }
end

----------------------------------------------------------------------------
-- Argument handling: pull our flags out of the forwarded extra_args
----------------------------------------------------------------------------

local function parse_extra()
    local args = { cross_bindir = nil, cross_toolchain = nil,
                   host_bindir = "/usr/bin", compiler_type = "clang",
                   force_bootstrap = false, clean = nil, rest = {} }
    local toks = {}
    for tok in cfg.extra_args:gmatch("%S+") do toks[#toks + 1] = tok end
    local i = 1
    while i <= #toks do
        local t = toks[i]
        local key, val = t:match("^(%-%-[%w-]+)=(.*)$")
        if not key and t:match("^%-%-[%w-]+$") and toks[i + 1] and
           not toks[i + 1]:match("^%-") then
            key, val = t, toks[i + 1]; i = i + 1
        end
        if t == "--bootstrap-bmake" then args.force_bootstrap = true
        elseif t == "--clean" then args.clean = true
        elseif t == "--no-clean" then args.clean = false
        elseif t == "--debug" then -- verbose already
        elseif key == "--cross-bindir" then args.cross_bindir = val
        elseif key == "--cross-toolchain" then args.cross_toolchain = val
        elseif key == "--host-bindir" then args.host_bindir = val
        elseif key == "--cross-compiler-type" then args.compiler_type = val
        else args.rest[#args.rest + 1] = t end
        i = i + 1
    end
    return args
end

----------------------------------------------------------------------------
-- bmake discovery / bootstrap
----------------------------------------------------------------------------

local function find_or_bootstrap_bmake(env, force_bootstrap, srcver)
    if not force_bootstrap then
        local sys = which("bmake")
        if sys then
            local v = bmake_version(sys)
            if v and v >= srcver then
                H.status("Using system bmake (" .. v .. ")")
                env[#env + 1] = { "MAKESYSPATH", cfg.srcdir .. "/share/mk" }
                return sys
            end
        end
    end

    local install = cfg.makeobjdir .. "/bmake-install"
    local build   = cfg.makeobjdir .. "/bmake-build"
    local bin     = install .. "/bin/bmake"

    if not force_bootstrap and file_exists(bin) and bmake_version(bin) == srcver then
        H.status("Using cached bootstrapped bmake")
        return bin
    end

    H.status("Bootstrapping bmake...")
    local envstr = ""
    for _, kv in ipairs(env) do
        envstr = envstr .. kv[1] .. "=" .. q(kv[2]) .. " "
    end
    local cfgargs =
        "--with-default-sys-path=.../share/mk:" .. install .. "/share/mk " ..
        "--with-machine=amd64 --without-filemon --prefix=" .. install

    H.sh("rm -rf " .. q(build) .. " " .. q(install))
    H.mkdir_p(build)
    local bs = q(cfg.srcdir .. "/contrib/bmake/boot-strap")
    if not H.run("cd " .. q(build) .. " && " .. envstr .. "sh " .. bs .. " " .. cfgargs) or
       not H.run(envstr .. "sh " .. bs .. " " .. cfgargs .. " op=install") then
        H.bomb("failed to bootstrap bmake")
    end
    if not file_exists(bin) then H.bomb("bootstrapped bmake not found at " .. bin) end
    return bin
end

----------------------------------------------------------------------------
-- Command assembly
----------------------------------------------------------------------------

local function build_make_cmd(ops)
    local shims = cfg.srcdir .. "/tools/renux/shims"
    local args = parse_extra()

    -- Machine-independent targets do not need TARGET/TARGET_ARCH.
    local mach_indep = {
        cleanuniverse=true, universe=true, ["universe-toolchain"]=true,
        tinderbox=true, worlds=true, kernels=true,
        ["kernel-toolchains"]=true, targets=true, toolchains=true,
        makeman=true, sysent=true,
    }
    local needs_target = false
    for _, op in ipairs(ops) do
        if not mach_indep[op] and not op:match("^kernel") and not op:match("^install=") then
            needs_target = true
        end
    end
    if needs_target and not H.is_bsd() and
       (cfg.target == "" or cfg.target_arch == "") then
        H.bomb("TARGET= and TARGET_ARCH= must be set explicitly on non-FreeBSD hosts")
    end

    local srcver = src_version()
    if not srcver then H.bomb("invalid _MAKE_VERSION in contrib/bmake/VERSION") end

    local env = {}

    -- Dry-run skips tool inference entirely (no side effects, no failures
    -- caused by a missing toolchain); the echoed command is representative.
    local live = cfg.runcmd ~= "echo"

    if live and not H.is_bsd() then
        -- Host tools used to build bootstrap binaries.
        local hb = args.host_bindir
        infer_tool(env, "CC",  "cc",  hb)
        infer_tool(env, "CXX", "c++", hb)
        infer_tool(env, "CPP", "cpp", hb)

        -- Cross tools used to build target binaries.
        local gcc = args.compiler_type == "gcc"
        local xb_cc  = cross_bindir(gcc and "gcc"     or "clang",     args.cross_toolchain, args)
        local xb_cxx = cross_bindir(gcc and "g++"     or "clang++",   args.cross_toolchain, args)
        local xb_cpp = cross_bindir(gcc and "cpp"     or "clang-cpp", args.cross_toolchain, args)
        local xb_ld  = cross_bindir(gcc and "ld"      or "ld.lld",    args.cross_toolchain, args)
        infer_tool(env, "XCC",  gcc and "gcc"     or "clang",     xb_cc)
        infer_tool(env, "XCXX", gcc and "g++"     or "clang++",   xb_cxx)
        infer_tool(env, "XCPP", gcc and "cpp"     or "clang-cpp", xb_cpp)
        infer_tool(env, "XLD",  gcc and "ld"      or "ld.lld",    xb_ld)

        if not H.have("strip") then
            if H.is_darwin() then
                H.bomb("cannot find required tool 'strip'")
            end
            infer_tool(env, "STRIPBIN", args.compiler_type == "clang" and
                       "llvm-strip" or "strip", hb)
            local have_xstrip = false
            for _, kv in ipairs(env) do
                if kv[1] == "XSTRIPBIN" then have_xstrip = true end
            end
            if not have_xstrip and not os.getenv("XSTRIPBIN") then
                env[#env + 1] = { "XSTRIPBIN", "strip" }
            end
        end
    end

    local bmake
    if live then
        bmake = find_or_bootstrap_bmake(env, args.force_bootstrap, srcver)
    else
        bmake = which("bmake") or cfg.makeobjdir .. "/bmake-install/bin/bmake"
    end

    local envstr = 'PATH="' .. shims .. ':$PATH" MAKEOBJDIRPREFIX="' ..
                   cfg.makeobjdir .. '" '
    for _, kv in ipairs(env) do
        envstr = envstr .. kv[1] .. "=" .. q(kv[2]) .. " "
    end

local parts = { envstr .. q(bmake) }
    if not cfg.verbose then parts[#parts + 1] = "-s" end
    if cfg.parallel then parts[#parts + 1] = cfg.parallel end
    parts[#parts + 1] = "-DWITH_AUTO_OBJ"
    if args.clean == false or args.clean == nil then
        parts[#parts + 1] = "-DWITHOUT_CLEAN"
    end
    for _, t in ipairs(args.rest) do parts[#parts + 1] = t end
    parts[#parts + 1] = "TARGET=" .. cfg.target
    parts[#parts + 1] = "TARGET_ARCH=" .. cfg.target_arch
    parts[#parts + 1] = "MK_SSP=no MK_TESTS=no"

    local cmd = table.concat(parts, " ")

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
