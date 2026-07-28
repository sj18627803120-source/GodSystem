local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path

GodSystemConfig = { DataKey = "GodSystem_Test_Storage_Refresh_11672" }
package.loaded.GodSystem_Config = true

local nowMs = 0
getTimestampMs = function() return nowMs end

local tickHandlers = {}
local function event(capture)
    return {
        Add = function(handler) if capture then tickHandlers[#tickHandlers + 1] = handler end end,
        Remove = function() end,
    }
end
Events = {
    OnFillWorldObjectContextMenu = event(), OnFillInventoryObjectContextMenu = event(),
    OnPreUIDraw = event(), OnTick = event(true), OnServerCommand = event(),
    OnDisconnect = event(), OnMainMenuEnter = event(),
    LoadGridsquare = event(),
}

local Storage = require "GodSystem_Storage"
local refreshCalls = 0
GodSystemStorageManager = {
    networkSummaryForPlayer = function()
        refreshCalls = refreshCalls + 1
        return { connectedObjectIds = { connected = true } }
    end,
    processJobs = function() end,
    calibrateLoadedSquare = function() end,
}
GodSystemStorageUI = { open = function() end, depositExternalSelection = function() end }
GodSystemStorageClient = {}
package.loaded.GodSystem_StorageManager = true
package.loaded.GodSystem_StorageUI = true
package.loaded["ISUI/ISInventoryPaneContextMenu"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true

local player = {
    getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    getPlayerNum = function() return 0 end,
}
getPlayer = function() return player end
getSpecificPlayer = function() return player end
getCell = function() return { getGridSquare = function() return nil end } end
isClient = function() return false end
GodSystem = { text = function(_, fallback) return fallback end, notify = function() end }

local Client = require "GodSystem_StorageClient"
local Context = require "GodSystem_StorageContext"
local contextTickRegistered = false
for index = 1, #tickHandlers do
    if tickHandlers[index] == Context.onTick then contextTickRegistered = true end
end
assert(contextTickRegistered, "connection mode must register its periodic refresh handler")
assert(Context.RefreshIntervalMs == 5000, "connection mode refresh interval must be five seconds")

Context.setConnectMode(true)
assert(Context.connectMode == true and refreshCalls == 1, "enabling connection mode must refresh state immediately")
assert(Client.networkState and Client.networkState.connectedObjectIds.connected == true,
    "SP connection refresh must publish the real manager network summary")
nowMs = 4999
Context.onTick()
assert(refreshCalls == 1, "connection state must not refresh before five seconds")
nowMs = 5000
Context.onTick()
assert(refreshCalls == 2, "connection state must refresh at five seconds")
nowMs = 9999
Context.onTick()
assert(refreshCalls == 2, "the next refresh must remain interval-gated")
nowMs = 10000
Context.onTick()
assert(refreshCalls == 3, "connection state must continue refreshing every five seconds")

Context.setConnectMode(false)
nowMs = 15000
Context.onTick()
assert(refreshCalls == 3, "disabling connection mode must stop periodic refreshes")
Context.reset()
assert(Context.connectMode == false and Context.lastRefreshMs == 0,
    "connection-mode reset must clear the timer state")

print("Test-GodSystemV11672StorageRefreshRuntime passed")
