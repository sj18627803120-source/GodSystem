local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. package.path
GodSystemConfig = { DataKey = "GodSystem_Test" }
package.loaded.GodSystem_Config = true

local function list(values)
    local result = { values = values or {} }
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    function result:contains(value)
        for i = 1, #self.values do if self.values[i] == value then return true end end
        return false
    end
    return result
end

local squares = {}
local function squareKey(x, y, z) return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) end
local function squareAt(x, y, z)
    local key = squareKey(x, y, z)
    if not squares[key] then
        local square = {
            x = x, y = y, z = z,
            objects = list({}), specialObjects = list({}), worldObjects = list({}),
        }
        function square:getX() return self.x end
        function square:getY() return self.y end
        function square:getZ() return self.z end
        function square:getObjects() return self.objects end
        function square:getSpecialObjects() return self.specialObjects end
        function square:getWorldObjects() return self.worldObjects end
        function square:transmitRemoveItemFromSquare(object)
            for i = #self.objects.values, 1, -1 do
                if self.objects.values[i] == object then table.remove(self.objects.values, i) end
            end
        end
        squares[key] = square
    end
    return squares[key]
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return squares[squareKey(x, y, z)] end,
    }
end

local stores = {}
ModData = {
    getOrCreate = function(key)
        stores[key] = stores[key] or {}
        return stores[key]
    end,
    transmit = function() end,
}

local nextItemId = 1000
local function item(fullType, name, weight)
    nextItemId = nextItemId + 1
    local value = {
        data = {}, fullType = fullType, displayName = name or fullType,
        weight = weight or 1, id = nextItemId, container = nil,
    }
    function value:getModData() return self.data end
    function value:transmitModData() self.transmitted = true end
    function value:getFullType() return self.fullType end
    function value:getDisplayName() return self.displayName end
    function value:getName() return self.displayName end
    function value:getID() return self.id end
    function value:getActualWeight() return self.weight end
    function value:getWeight() return self.weight end
    function value:getCategory() return "Material" end
    function value:getCondition() return 100 end
    function value:getConditionMax() return 100 end
    function value:getContainer() return self.container end
    return value
end

local function container(kind, capacity, values)
    local result = {
        kind = kind or "crate",
        capacity = capacity or 50,
        items = list(values or {}),
        parent = nil,
    }
    function result:getType() return self.kind end
    function result:getItems() return self.items end
    function result:getCapacity() return self.capacity end
    function result:setCapacity(value) self.capacity = value end
    function result:getParent() return self.parent end
    function result:AddItem(value)
        self.items.values[#self.items.values + 1] = value
        value.container = self
        return value
    end
    function result:Remove(value)
        for i = #self.items.values, 1, -1 do
            if self.items.values[i] == value then
                table.remove(self.items.values, i)
                value.container = nil
                return
            end
        end
    end
    function result:getContentsWeight()
        local total = 0
        for i = 1, #self.items.values do total = total + (self.items.values[i].weight or 0) end
        return total
    end
    function result:hasRoomFor() return self.capacity > 0 end
    function result:isItemAllowed() return true end
    for i = 1, #result.items.values do result.items.values[i].container = result end
    return result
end

local function furnitureAt(x, y, z, capacities, initialItems)
    local square = squareAt(x, y, z)
    local object = { data = {}, square = square, slots = {}, spriteName = "test_storage_sprite" }
    function object:getModData() return self.data end
    function object:transmitModData() self.transmitted = true end
    function object:getSquare() return self.square end
    function object:getSprite()
        local name = self.spriteName
        return { getName = function() return name end }
    end
    function object:getContainerCount() return #self.slots end
    function object:getContainerByIndex(index) return self.slots[index + 1] end
    for i = 1, #capacities do
        local values = initialItems and initialItems[i] or {}
        local slot = container("slot" .. tostring(i), capacities[i], values)
        slot.parent = object
        object.slots[i] = slot
    end
    square.objects.values[#square.objects.values + 1] = object
    return object
end

local playerInventory = container("inventory", 100, {})
local player = { x = 0, y = 0, z = 0, inventory = playerInventory }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:getUsername() return "tester" end
function player:getOnlineID() return 1 end
function player:getInventory() return self.inventory end
function player:getAccessLevel() return "None" end

InventoryItemFactory = {
    CreateItem = function(fullType) return item(fullType, "System Storage Core", 0.5) end,
}

local Storage = require "GodSystem_Storage"
local Manager = require "GodSystem_StorageManager"

local claimed, claimReason, claimPayload = Manager.claimCore(player, {})
assert(claimed, tostring(claimReason))
assert(claimPayload.cost == 0 and claimPayload.state == "kit", "first core must be free")
local core = playerInventory.items.values[1]
assert(Storage.itemFullType(core) == Storage.CoreFullType, "claim must create the stable core fullType")
local coreNetworkId, coreToken = Storage.getCoreIdentity(core)
assert(coreNetworkId ~= "" and coreToken ~= "", "core identity must be stored directly")
assert(core.data[Storage.MovableDataKey] == nil, "new core must not use Moveable identity")

local leftItem = item("Base.Plank", "Plank", 3)
local rightItem = item("Base.DuctTape", "Duct Tape", 0.3)
local host = furnitureAt(0, 0, 0, { 50, 20 }, nil)
local left = furnitureAt(-1, 0, 0, { 40 }, { { leftItem } })
local right = furnitureAt(1, 0, 0, { 30 }, { { rightItem } })
local blocked = furnitureAt(0, 1, 0, { 25 }, { { item("Base.Nails", "Nails", 0.1) } })

local function mark(object)
    local position = Storage.objectCoordinates(object)
    local ok, reason = Manager.setNetworkContainer(player, {
        x = position.x, y = position.y, z = position.z,
        objectIndex = Storage.getObjectIndex(object),
        sprite = Storage.objectSpriteName(object),
        name = "Test",
        enabled = true,
    })
    assert(ok, tostring(reason))
end

mark(host)
mark(left)
mark(right)
mark(blocked)

local blockedOk, blockedReason = Storage.lockCoreHost(blocked, coreNetworkId, coreToken)
assert(not blockedOk and blockedReason == "coreHostNotEmpty", "non-empty furniture must reject core installation")
assert(blocked.slots[1]:getCapacity() == 25, "failed installation must not change capacity")

local installed, installReason, installPayload = Manager.installCore(player, {
    networkId = coreNetworkId,
    coreToken = coreToken,
    coreItemId = Storage.itemId(core),
    x = 0, y = 0, z = 0,
    objectIndex = Storage.getObjectIndex(host),
    sprite = Storage.objectSpriteName(host),
})
assert(installed, tostring(installReason))
assert(installPayload.state == "installed", "install must return installed state")
assert(#playerInventory.items.values == 0, "installed core item must be consumed")
assert(host.slots[1]:getCapacity() == 0 and host.slots[2]:getCapacity() == 0,
    "every host slot must be locked to zero")
assert(Storage.isCoreHost(host), "host ModData must record the installed core")

local network = assert(Manager.getNetwork(coreNetworkId))
local view = Manager.connectedNetwork(network, host)
assert(view.nodeCount == 4, "host must bridge all touching marked furniture")
assert(Manager.linkCount(view) == 3, "core host slots must be excluded from storage links")

local job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
local snapshot = Storage.buildSnapshot(job, view)
assert(snapshot.itemCount == 3, "connected ordinary containers must remain indexable")
assert(snapshot.onlineLinks == 3, "only ordinary container slots count as online links")

local hostSquare = squares[squareKey(0, 0, 0)]
squares[squareKey(0, 0, 0)] = nil
local unloadedStatus = assert(Manager.coreStatus(player))
assert(unloadedStatus.state == "installed", "unloaded host must not be treated as missing")
squares[squareKey(0, 0, 0)] = hostSquare
local loadedStatus = assert(Manager.coreStatus(player))
assert(loadedStatus.state == "installed", "reloaded host must remain installed")
assert(host.slots[1]:getCapacity() == 0 and host.slots[2]:getCapacity() == 0,
    "reloaded host must be recalibrated to zero capacity")

local retrieved, retrieveReason = Manager.retrieveCore(player, {
    networkId = coreNetworkId,
    coreToken = coreToken,
    coreObjectId = Storage.getCoreHostMarker(host).objectId,
    x = 0, y = 0, z = 0,
})
assert(retrieved, tostring(retrieveReason))
assert(host.slots[1]:getCapacity() == 50 and host.slots[2]:getCapacity() == 20,
    "retrieve must restore every original capacity")
assert(Storage.getNetworkContainerMarker(host) ~= nil, "retrieve must preserve the network-container mark")
assert(not Storage.isCoreHost(host), "retrieve must clear only the core-host state")
assert(#playerInventory.items.values == 1, "retrieve must return exactly one core")

local returnedCore = playerInventory.items.values[1]
local reinstalled, reinstallReason = Manager.installCore(player, {
    networkId = coreNetworkId,
    coreToken = coreToken,
    coreItemId = Storage.itemId(returnedCore),
    x = 0, y = 0, z = 0,
    objectIndex = Storage.getObjectIndex(host),
    sprite = Storage.objectSpriteName(host),
})
assert(reinstalled, tostring(reinstallReason))
squares[squareKey(0, 0, 0)] = nil
local charged = 0
local recovered, recoverReason, recoverPayload = Manager.claimCore(player, {
    forceRecovery = true,
    charge = function(cost) charged = cost; return true, { cost = cost } end,
})
assert(recovered, tostring(recoverReason))
assert(charged == Storage.CoreRecoveryCost and recoverPayload.cost == 2000,
    "lost installed core recovery must charge exactly 2000")
assert(type(network.pendingCoreUnlock) == "table", "unloaded old host must enter pending unlock")
squares[squareKey(0, 0, 0)] = hostSquare
Manager.calibrateLoadedSquare(hostSquare)
assert(host.slots[1]:getCapacity() == 50 and host.slots[2]:getCapacity() == 20,
    "loading an expired host must restore its original capacities")
assert(network.pendingCoreUnlock == nil, "completed pending unlock must be removed")
assert(#playerInventory.items.values == 1, "paid recovery must still leave exactly one valid core")

print("Test-GodSystemV11670Runtime passed")
