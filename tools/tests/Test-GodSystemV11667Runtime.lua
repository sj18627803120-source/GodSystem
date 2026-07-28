local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. package.path
GodSystemConfig = { DataKey = "GodSystem_Test" }
package.loaded.GodSystem_Config = true

local function list(values)
    return {
        values = values or {},
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
    }
end

local squares = {}
local function squareAt(x, y, z)
    local key = x .. ":" .. y .. ":" .. z
    if not squares[key] then
        local square = { x = x, y = y, z = z, objects = list({}) }
        function square:getX() return self.x end
        function square:getY() return self.y end
        function square:getZ() return self.z end
        function square:getObjects() return self.objects end
        function square:getSpecialObjects() return list({}) end
        function square:getWorldObjects() return list({}) end
        squares[key] = square
    end
    return squares[key]
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return squares[x .. ":" .. y .. ":" .. z] end,
    }
end

local function container(kind)
    return {
        kind = kind or "crate",
        getType = function(self) return self.kind end,
        getItems = function() return list({}) end,
        getCapacity = function() return 50 end,
        getContentsWeight = function() return 0 end,
    }
end

local function objectAt(x, y, z, slotKinds)
    local square = squareAt(x, y, z)
    local object = { data = {}, square = square, slots = {} }
    function object:getModData() return self.data end
    function object:transmitModData() self.transmitted = true end
    function object:getSquare() return self.square end
    function object:getSprite() return { getName = function() return "test_storage_sprite" end } end
    function object:getContainerCount() return #self.slots end
    function object:getContainerByIndex(index) return self.slots[index + 1] end
    local kinds = slotKinds or { "crate" }
    for i = 1, #kinds do
        local slot = container(kinds[i])
        slot.getParent = function() return object end
        object.slots[i] = slot
    end
    square.objects.values[#square.objects.values + 1] = object
    return object
end

local Storage = require "GodSystem_Storage"

local function mark(object, scopeKey, name)
    assert(Storage.setNetworkContainerMarker(object, {
        scopeKey = scopeKey,
        owner = "tester",
        name = name,
        role = "auto",
        priority = 50,
    }))
end

local controller = objectAt(0, 0, 0, {})
assert(Storage.markInstalledController(controller, "network-a", "token-a", "controller-a"))
local nested = controller:getModData().movableData
assert(nested.GodSystemStorageNetworkId == "network-a")
assert(Storage.isController(controller), "world Moveable identity must identify the controller without getItem")

local scope = "personal:tester"
local left = objectAt(-1, 0, 0)
local farLeft = objectAt(-2, 0, 0)
local right = objectAt(1, 0, 0, { "fridge", "freezer" })
local stacked = objectAt(1, 0, 0)
local diagonal = objectAt(2, 1, 0)
local otherFloor = objectAt(1, 0, 1)
mark(left, scope, "Left")
mark(farLeft, scope, "Far Left")
mark(right, scope, "Fridge")
mark(stacked, scope, "Stacked")
mark(diagonal, scope, "Diagonal")
mark(otherFloor, scope, "Other Floor")

local network = {
    networkId = "network-a",
    scopeKey = scope,
    controller = { x = 0, y = 0, z = 0 },
    revision = 1,
}
local view = Storage.discoverNetwork(network, controller)
assert(view.nodeCount == 4, "controller must bridge left/right components and include same-square stacking only")
assert(view.truncated == false)
assert(view.connectedObjectIds[Storage.getObjectId(left, false)])
assert(view.connectedObjectIds[Storage.getObjectId(farLeft, false)])
assert(view.connectedObjectIds[Storage.getObjectId(right, false)])
assert(view.connectedObjectIds[Storage.getObjectId(stacked, false)])
assert(not view.connectedObjectIds[Storage.getObjectId(diagonal, false)], "diagonal furniture must not connect")
assert(not view.connectedObjectIds[Storage.getObjectId(otherFloor, false)], "cross-floor furniture must not connect")
local linkCount = 0
for _ in pairs(view.links) do linkCount = linkCount + 1 end
assert(linkCount == 5, "multi-container furniture must expose all storage compartments")

assert(Storage.clearNetworkContainerMarker(left))
view = Storage.discoverNetwork(network, controller)
assert(view.nodeCount == 2, "removing the bridge marker must disconnect the far-left component")

local oldId = Storage.getObjectId(right, false)
assert(Storage.clearNetworkContainerMarker(right))
local replacement = objectAt(1, 0, 0)
view = Storage.discoverNetwork(network, controller)
assert(not view.connectedObjectIds[oldId], "a replacement at the same coordinates must not inherit the old marker")
assert(Storage.getNetworkContainerMarker(replacement) == nil)

local chainController = objectAt(0, 10, 0, {})
local chainScope = "personal:chain"
for x = 1, 130 do mark(objectAt(x, 10, 0), chainScope, "Node " .. x) end
local chain = Storage.discoverNetwork({
    networkId = "network-chain",
    scopeKey = chainScope,
    controller = { x = 0, y = 10, z = 0 },
}, chainController)
assert(chain.nodeCount == 128 and chain.truncated == true, "physical topology must enforce the 128-node cap")

print("Test-GodSystemV11667Runtime passed")
