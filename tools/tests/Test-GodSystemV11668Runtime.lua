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
        local square = {
            x = x,
            y = y,
            z = z,
            objects = list({}),
            specialObjects = list({}),
            worldObjects = list({}),
        }
        function square:getX() return self.x end
        function square:getY() return self.y end
        function square:getZ() return self.z end
        function square:getObjects() return self.objects end
        function square:getSpecialObjects() return self.specialObjects end
        function square:getWorldObjects() return self.worldObjects end
        squares[key] = square
    end
    return squares[key]
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return squares[x .. ":" .. y .. ":" .. z] end,
    }
end

local nextItemId = 100
local function item(fullType, name, weight)
    nextItemId = nextItemId + 1
    local value = {
        data = {},
        fullType = fullType,
        displayName = name,
        weight = weight or 1,
        id = nextItemId,
    }
    function value:getModData() return self.data end
    function value:getFullType() return self.fullType end
    function value:getDisplayName() return self.displayName end
    function value:getName() return self.displayName end
    function value:getID() return self.id end
    function value:getActualWeight() return self.weight end
    function value:getWeight() return self.weight end
    function value:getCategory() return "Material" end
    function value:getCondition() return 100 end
    function value:getConditionMax() return 100 end
    return value
end

local function container(kind, values)
    local value = {
        kind = kind or "crate",
        items = list(values or {}),
    }
    function value:getType() return self.kind end
    function value:getItems() return self.items end
    function value:getCapacity() return 50 end
    function value:getContentsWeight()
        local total = 0
        for i = 1, #self.items.values do total = total + (self.items.values[i].weight or 0) end
        return total
    end
    return value
end

local function containerObjectAt(x, y, z, slotValues)
    local square = squareAt(x, y, z)
    local object = { data = {}, square = square, slots = {} }
    function object:getModData() return self.data end
    function object:transmitModData() self.transmitted = true end
    function object:getSquare() return self.square end
    function object:getSprite() return { getName = function() return "test_storage_sprite" end } end
    function object:getContainerCount() return #self.slots end
    function object:getContainerByIndex(index) return self.slots[index + 1] end
    for i = 1, #(slotValues or {}) do
        local slot = container(slotValues[i].kind, slotValues[i].items)
        slot.getParent = function() return object end
        object.slots[i] = slot
    end
    square.objects.values[#square.objects.values + 1] = object
    return object
end

local function worldItemObjectAt(x, y, z, inventoryItem)
    local square = squareAt(x, y, z)
    local object = { data = {}, square = square, item = inventoryItem }
    function object:getModData() return self.data end
    function object:transmitModData() self.transmitted = true end
    function object:getSquare() return self.square end
    function object:getItem() return self.item end
    square.worldObjects.values[#square.worldObjects.values + 1] = object
    return object
end

local Storage = require "GodSystem_Storage"

local controllerItem = item(Storage.ControllerFullType, "System Storage Controller", 2)
assert(Storage.setControllerIdentity(controllerItem, "network-a", "token-a"))
local controllerObject = worldItemObjectAt(0, 0, 0, controllerItem)
local foundObject, foundItem = Storage.findWorldController(0, 0, 0, controllerItem:getID(), "token-a")
assert(foundObject == controllerObject and foundItem == controllerItem,
    "a placed normal world item must retain controller identity and remain discoverable")
assert(Storage.markInstalledController(controllerObject, "network-a", "token-a", "controller-object-a"))

local storedItem = item("Base.Plank", "Plank", 3)
local crate = containerObjectAt(1, 0, 0, {
    { kind = "crate", items = { storedItem } },
})
assert(Storage.setNetworkContainerMarker(crate, {
    scopeKey = "personal:tester",
    owner = "tester",
    name = "Crate",
    role = "auto",
    priority = 50,
}))

local network = {
    networkId = "network-a",
    scopeKey = "personal:tester",
    topologyMode = "physical",
    controller = { x = 0, y = 0, z = 0 },
    revision = 1,
}
local view = Storage.discoverNetwork(network, controllerObject)
assert(view.nodeCount == 1, "the adjacent marked crate must connect to the placed controller")

local job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
local snapshot = Storage.buildSnapshot(job, view)
assert(snapshot.onlineLinks == 1, "the connected crate must be online")
assert(snapshot.itemCount == 1 and snapshot.groupCount == 1, "pre-existing crate contents must be indexed")
assert(snapshot.groups[1].fullType == "Base.Plank" and snapshot.groups[1].count == 1,
    "the visible snapshot must contain the pre-existing plank")

print("Test-GodSystemV11668Runtime passed")
