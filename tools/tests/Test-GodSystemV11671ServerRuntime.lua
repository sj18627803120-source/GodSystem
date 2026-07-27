local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/server/?.lua;" .. package.path
GodSystemConfig = { DataKey = "GodSystem_Test_Server_11671" }
package.loaded.GodSystem_Config = true
isServer = function() return true end
sendServerCommand = function() end

local function event()
    return { Add = function() end, Remove = function() end }
end
Events = { OnClientCommand = event(), OnTick = event(), OnInitGlobalModData = event(), LoadGridsquare = event() }

local Server = require "GodSystem_StorageServer"
local base = {
    networkId = "network", coreToken = "token", coreObjectId = "host",
    coreX = 1, coreY = 2, coreZ = 0,
    mode = "selected", sourceItemId = "bag", targetItemId = "belt",
    itemIds = { "3", "1", "2", "2" },
    requests = {
        { groupKey = "Base.Plank", itemIds = { "9", "7", "9" } },
        { groupKey = "Base.Nails", count = 4 },
    },
}
local reordered = {
    networkId = "network", coreToken = "token", coreObjectId = "host",
    coreX = 1, coreY = 2, coreZ = 0,
    mode = "selected", sourceItemId = "bag", targetItemId = "belt",
    itemIds = { "2", "3", "1" },
    requests = {
        { groupKey = "Base.Nails", count = 4 },
        { groupKey = "Base.Plank", itemIds = { "7", "9" } },
    },
}
assert(Server.fingerprint("deposit", base) == Server.fingerprint("deposit", reordered),
    "fingerprint must normalize selection and request ordering")
reordered.sourceItemId = "otherBag"
assert(Server.fingerprint("deposit", base) ~= Server.fingerprint("deposit", reordered),
    "fingerprint must bind the source container")
reordered.sourceItemId = "bag"
reordered.targetItemId = "main"
assert(Server.fingerprint("withdraw", base) ~= Server.fingerprint("withdraw", reordered),
    "fingerprint must bind the target container")
reordered.targetItemId = "belt"
reordered.requests[1].count = 5
assert(Server.fingerprint("withdraw", base) ~= Server.fingerprint("withdraw", reordered),
    "fingerprint must bind normalized selection content")

print("Test-GodSystemV11671ServerRuntime passed")
