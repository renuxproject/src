--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    helpers.lua - utility functions for the Renux build utility.
]]

local cfg = require("renux.config")

----------------------------------------------------------------------------
-- ANSI colors (disabled when stdout is not a TTY or NO_COLOR is set)
----------------------------------------------------------------------------

local no_color = os.getenv("NO_COLOR") ~= nil

local function use_color()
    if no_color then return false end
    if os.getenv("FORCE_COLOR") then return true end
    local ok = os.execute("test -t 1 2>/dev/null")
    if ok == nil then ok = os.execute("[ -t 1 ] 2>/dev/null") end
    return ok == true
end

local c = use_color() and {
    reset   = "\27[0m",
    bold    = "\27[1m",
    dim     = "\27[2m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",
} or {
    reset   = "", bold = "", dim = "",
    red     = "", green = "", yellow = "",
    blue    = "", magenta = "", cyan = "", white = "",
}

----------------------------------------------------------------------------
-- Shell helpers
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
    if cfg.runcmd == "echo" then
        print(c.dim .. "$ " .. cmd .. c.reset)
        return true
    end
    print(c.green .. c.bold .. "+" .. c.reset .. " " .. cmd)
    return sh(cmd)
end

local function bomb(msg)
    io.stderr:write(c.red .. c.bold .. "error" .. c.reset .. ": " .. c.bold .. msg .. c.reset .. "\n")
    os.exit(1)
end

local function status(msg)
    print(c.cyan .. c.bold .. "=>" .. c.reset .. " " .. msg)
end

local function warn(msg)
    print(c.yellow .. c.bold .. "warning" .. c.reset .. ": " .. c.bold .. msg .. c.reset)
end

----------------------------------------------------------------------------
-- System detection
----------------------------------------------------------------------------

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

----------------------------------------------------------------------------
-- Filesystem
----------------------------------------------------------------------------

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

local function abs_path(p)
    sh("mkdir -p '" .. p .. "' 2>/dev/null")
    local h = io.popen("cd '" .. p .. "' && pwd")
    local out = h:read("*l"); h:close()
    return out or p
end

local function W()
    return cfg.worlddir
end

----------------------------------------------------------------------------
-- Banner
----------------------------------------------------------------------------

local function banner()
    print(c.green .. c.bold .. [[
 _____                       
 |  __ \                      
 | |__) |___ _ __  _   ___  __
 |  _  // _ \ '_ \| | | \ \/ /
 | | \ \  __/ | | | |_| |>  < 
 |_|  \_\___|_| |_|\__,_/_/\_\  ]] ..
    c.white .. c.bold .. "v" .. cfg.version .. c.reset)
    print()
end

----------------------------------------------------------------------------
-- Table export
----------------------------------------------------------------------------

return {
    sh          = sh,
    capture     = capture,
    run         = run,
    bomb        = bomb,
    status      = status,
    warn        = warn,
    is_bsd      = is_bsd,
    is_darwin   = is_darwin,
    have        = have,
    write_file  = write_file,
    mkdir_p     = mkdir_p,
    objroot     = objroot,
    abs_path    = abs_path,
    W           = W,
    banner      = banner,
    c           = c,
}
