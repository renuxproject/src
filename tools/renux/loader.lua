--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    loader.lua - EFI and BIOS loader discovery.
]]

local cfg     = require("renux.config")
local H       = require("renux.helpers")
local objroot = H.objroot

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

return {
    find_loader     = find_loader,
    find_loader_efi = find_loader_efi,
    find_bios_loader = find_bios_loader,
    find_cdboot     = find_cdboot,
}
