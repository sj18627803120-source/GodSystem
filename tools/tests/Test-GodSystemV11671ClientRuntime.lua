local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path

GodSystemConfig = { DataKey = "GodSystem_Test_Client_11671" }
package.loaded.GodSystem_Config = true
local Storage = require "GodSystem_Storage"

local refreshCalls = 0
local markerRefreshCalls = 0
local networkStateCalls = 0
local manager = {
    deposit = function()
        return true, nil, { success = 1, skipped = 0, failed = 0, successItemIds = { "item-1" } }
    end,
    startIndex = function(_, _, callback)
        refreshCalls = refreshCalls + 1
        local network = { networkId = "network", connectedObjectIds = { connected = true }, links = {} }
        callback({}, { snapshotId = "snapshot-" .. tostring(refreshCalls), groups = {}, containers = {} })
        return true, nil, { network = network }
    end,
    networkSummary = function(_, network) return network end,
    setNetworkContainer = function() return true, nil, { enabled = true } end,
    networkSummaryForPlayer = function()
        return { networkId = "network", connectedObjectIds = { newlyConnected = true }, links = {} }
    end,
}
GodSystemStorageManager = manager
package.loaded.GodSystem_StorageManager = true

local testPlayer = {
    getUsername = function() return "tester" end,
    getOnlineID = function() return 1 end,
}
getPlayer = function() return testPlayer end
isClient = function() return false end

local function event()
    return { Add = function() end, Remove = function() end }
end
Events = { OnServerCommand = event(), OnTick = event(), OnDisconnect = event(), OnMainMenuEnter = event() }

GodSystemStorageUI = {
    onOperationResult = function() error("simulated UI result failure") end,
    onSnapshot = function() end,
    onNetworkState = function() networkStateCalls = networkStateCalls + 1 end,
}
GodSystemStorageContext = {
    refreshHighlights = function() markerRefreshCalls = markerRefreshCalls + 1 end,
}

GodSystemStorageClient = {
    core = { x = 1, y = 2, z = 0, token = "token", networkId = "network", objectId = "host" },
}
local Client = require "GodSystem_StorageClient"

local originalPrint = print
print = function() end
local ok = pcall(function() Client.depositItems({ "item-1" }, nil) end)
print = originalPrint
assert(ok, "SP deposit must still complete its refresh when the UI result callback fails")
assert(refreshCalls == 1, "SP deposit success must request a fresh storage snapshot")

Client.core = nil
Client.networkState = nil
local marked = Client.setNetworkContainer({ x = 3, y = 4, z = 0, objectIndex = 1, enabled = true })
assert(marked == true, "SP network-container marking fixture must succeed")
assert(Client.networkState and Client.networkState.connectedObjectIds.newlyConnected == true,
    "marking a container must refresh connectivity even when the storage window was not opened first")
assert(networkStateCalls >= 1 and markerRefreshCalls >= 1,
    "fresh connectivity must be published to both the storage UI and world markers")

print("Test-GodSystemV11671ClientRuntime passed")
