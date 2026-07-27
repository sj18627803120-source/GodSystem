local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/server/?.lua;" .. package.path

GodSystemConfig = { AutoLoaderFullType = "GodSystem.SystemAutoLoader", AutoLoaderAmmoCapacity = 2000 }
package.loaded.GodSystem_Config = true
GodSystemAdminConfig = { getSetting = function(_, fallback) return fallback end }
package.loaded.GodSystem_AdminConfig = true
isServer = function() return true end
sendServerCommand = function() end
local function event() return { Add = function() end, Remove = function() end } end
Events = { OnClientCommand = event(), OnTick = event() }

local Server = require "GodSystem_AutoLoaderServer"
ISBaseTimedAction = {
    derive = function(self)
        local value = setmetatable({}, { __index = self })
        value.__index = value
        return value
    end,
    new = function(self, character) return setmetatable({ character = character }, self) end,
}
package.preload["TimedActions/ISBaseTimedAction"] = function() return ISBaseTimedAction end
require "TimedActions/ISGodSystemAutoLoaderDepositAction"
local DepositAction = ISGodSystemAutoLoaderDepositAction
local authoritativeRecords = {}
for index = 1, 1000 do authoritativeRecords[index] = index end
GodSystemAutoLoader.runtime.sessions["authoritative-session"] = {
    records = authoritativeRecords,
    batchCount = 2,
}
local durationAction = DepositAction:new({}, "client-loader", "authoritative-session", 1, 999, 1)
assert(durationAction:getDuration() == 150,
    "server duration must ignore client counts and use the authoritative 1000-item, 2-batch session")

local first = { loaderId = "5", count = 100, fullType = "Base.Bullets9mm" }
local same = { fullType = "Base.Bullets9mm", loaderId = "5", count = 100 }
local changed = { loaderId = "6", count = 100, fullType = "Base.Bullets9mm" }
assert(Server.fingerprint("withdraw", first) == Server.fingerprint("withdraw", same),
    "fingerprint must normalize scalar request order")
assert(Server.fingerprint("withdraw", first) ~= Server.fingerprint("withdraw", changed),
    "fingerprint must bind the exact loader")

print("Test-GodSystemV11672ServerRuntime passed")
