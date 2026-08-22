--[[
    SPDX-License-Identifier: BSD-2-Clause
    Copyright (c) 2026 Renan Lucas Vieira Hilario.  All rights reserved.

    image.lua - EFI System Partition and hybrid ISO creation.
]]

local cfg    = require("renux.config")
local H      = require("renux.helpers")
local loader = require("renux.loader")

local function make_world_esp()
    local img   = cfg.imagdir .. "/renux-esp-boot.img"
    local stage = cfg.imagdir .. "/esp-boot-stage"
    local efi   = loader.find_loader_efi()
    if not efi then H.bomb("EFI loader not found") end
    H.mkdir_p(stage .. "/EFI/BOOT")
    H.run("cp '" .. efi .. "' '" .. stage .. "/EFI/BOOT/BOOTX64.EFI'")
    H.status("Building EFI boot ESP " .. img)
    if H.is_bsd() then
        if not H.have("makefs") then H.bomb("makefs is required on this host") end
        H.run("makefs -t msdos -o fat_type=32 -o volume_label=RENUX '" .. img .. "' '" .. stage .. "'")
    else
        if not (H.have("mkfs.fat") and H.have("mcopy")) then H.bomb("mkfs.fat and mcopy are required") end
        H.run("rm -f '" .. img .. "'")
        H.run("truncate -s " .. (cfg.espmb * 1024 * 1024) .. " '" .. img .. "'")
        H.run("mkfs.fat -F32 -n RENUX '" .. img .. "' >/dev/null")
        H.run("mcopy -i '" .. img .. "' -s '" .. stage .. "/*' ::/")
    end
end

local function make_world_hybrid_iso()
    local cdboot = loader.find_cdboot() or "<cdboot>"
    local bios   = loader.find_bios_loader() or "<bios-loader>"
    if cfg.runcmd ~= "echo" then
        H.run("cp '" .. cdboot .. "' '" .. H.W() .. "/cdboot'")
        H.run("cp '" .. bios .. "' '" .. H.W() .. "/boot/loader'")
    end
    H.write_file(H.W() .. "/boot/loader.conf", [[
autoboot_delay="2"
loader_logo="renux"
vfs.root.mountfrom="cd9660:/dev/iso9660/RENUX"
]])
    H.run("cp '" .. H.W() .. "/boot/loader.conf' '" .. H.W() .. "/boot/defaults/loader.conf'")

    local iso = cfg.imagdir .. "/renux-installer.iso"
    H.status("Building hybrid BIOS+UEFI world ISO " .. iso)
    if H.is_bsd() then
        if not H.have("makefs") then H.bomb("makefs is required on this host") end
        H.run("makefs -t cd9660 -o label=RENUX -o bootimage=i386\\;" .. cdboot .. " -o no-emul-boot -o bootimage=efi\\;" .. cfg.imagdir .. "/renux-esp-boot.img -o no-emul-boot -o platformid=efi '" .. H.W() .. "' '" .. iso .. "'")
    else
        if not H.have("xorriso") then H.bomb("xorriso is required to build an ISO on this host") end
        H.run("cp '" .. cfg.imagdir .. "/renux-esp-boot.img' '" .. H.W() .. "/renux-esp.img'")
        H.run("xorriso -as mkisofs -V RENUX -o '" .. iso .. "' -R -b cdboot -c boot.cat -no-emul-boot -boot-load-size 4 -eltorito-alt-boot -e renux-esp.img -no-emul-boot -isohybrid-gpt-basdat '" .. H.W() .. "'")
        H.run("rm -f '" .. H.W() .. "/renux-esp.img'")
    end
    if H.have("xz") then
        H.status("Compressing " .. iso .. " (xz -9e)...")
        if cfg.runcmd ~= "echo" then
            H.run("xz -9e -T0 -c '" .. iso .. "' > '" .. iso .. ".xz'")
        else
            print("xz -9e -T0 -c '" .. iso .. "' > '" .. iso .. ".xz'")
        end
    else
        H.status("warning: xz not found; skipping .xz build")
    end
end

return {
    make_world_esp        = make_world_esp,
    make_world_hybrid_iso = make_world_hybrid_iso,
}
