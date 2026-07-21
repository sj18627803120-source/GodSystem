require "NPCs/BodyLocations"

local slot = GodSystemRegistries
    and GodSystemRegistries.BodyLocations
    and GodSystemRegistries.BodyLocations.SystemSpaceTerminal
local group = BodyLocations and BodyLocations.getGroup and BodyLocations.getGroup("Human") or nil

if slot and group then
    group:getOrCreateLocation(slot)
else
    print("[GodSystem][TerminalWear] body-location registration unavailable")
end
