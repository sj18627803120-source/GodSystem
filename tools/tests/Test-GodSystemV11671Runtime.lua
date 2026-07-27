local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. package.path
GodSystemConfig = { DataKey = "GodSystem_Test_11671" }
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
        local square = { x = x, y = y, z = z, objects = list({}), specialObjects = list({}), worldObjects = list({}) }
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
    return { getGridSquare = function(_, x, y, z) return squares[squareKey(x, y, z)] end }
end

local stores = {}
ModData = {
    getOrCreate = function(key) stores[key] = stores[key] or {}; return stores[key] end,
    transmit = function() end,
}

local nextItemId = 2000
local function item(fullType, name, options)
    options = options or {}
    nextItemId = nextItemId + 1
    local value = {
        data = {}, fullType = fullType, displayName = name or fullType,
        weight = options.weight or 1, id = nextItemId, container = nil,
        favorite = options.favorite == true, category = options.category or "Material",
        inventory = nil,
    }
    function value:getModData() return self.data end
    function value:transmitModData() end
    function value:getFullType() return self.fullType end
    function value:getDisplayName() return self.displayName end
    function value:getName() return self.displayName end
    function value:getID() return self.id end
    function value:getActualWeight() return self.weight end
    function value:getWeight() return self.weight end
    function value:getCategory() return self.category end
    function value:getCondition() return 100 end
    function value:getConditionMax() return 100 end
    function value:getContainer() return self.container end
    function value:getInventory() return self.inventory end
    function value:isFavorite() return self.favorite end
    function value:getAttachedSlot() return -1 end
    return value
end

local function container(kind, capacity, values)
    local result = { kind = kind or "crate", capacity = capacity or 50, items = list(values or {}), parent = nil }
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
            if self.items.values[i] == value then table.remove(self.items.values, i); value.container = nil; return end
        end
    end
    function result:getContentsWeight()
        local total = 0
        for i = 1, #self.items.values do total = total + (self.items.values[i].weight or 0) end
        return total
    end
    function result:hasRoomFor(first, second)
        local value = second or first
        return self:getContentsWeight() + ((value and value.weight) or 0) <= self.capacity
    end
    function result:isItemAllowed() return true end
    for i = 1, #result.items.values do result.items.values[i].container = result end
    return result
end

local function containerItem(fullType, name, capacity, values, options)
    local value = item(fullType, name, options)
    value.category = (options and options.category) or "Container"
    value.inventory = container("bag", capacity, values)
    value.inventory.parent = value
    return value
end

local function furnitureAt(x, y, z, capacities, initialItems)
    local square = squareAt(x, y, z)
    local object = { data = {}, square = square, slots = {}, spriteName = "test_storage_sprite" }
    function object:getModData() return self.data end
    function object:transmitModData() end
    function object:getSquare() return self.square end
    function object:getSprite() local name = self.spriteName; return { getName = function() return name end } end
    function object:getContainerCount() return #self.slots end
    function object:getContainerByIndex(index) return self.slots[index + 1] end
    for i = 1, #capacities do
        local slot = container("slot" .. tostring(i), capacities[i], initialItems and initialItems[i] or {})
        slot.parent = object
        object.slots[i] = slot
    end
    square.objects.values[#square.objects.values + 1] = object
    return object
end

local playerInventory = container("inventory", 100, {})
local wornEntries = list({})
local player = { x = 0, y = 0, z = 0, inventory = playerInventory, primary = nil, secondary = nil }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:getUsername() return "tester" end
function player:getOnlineID() return 1 end
function player:getInventory() return self.inventory end
function player:getAccessLevel() return "None" end
function player:getPrimaryHandItem() return self.primary end
function player:getSecondaryHandItem() return self.secondary end
function player:getWornItems() return wornEntries end
function player:getAttachedItems() return list({}) end
function player:isEquipped(value)
    if value == self.primary or value == self.secondary then return true end
    for i = 0, wornEntries:size() - 1 do if wornEntries:get(i):getItem() == value then return true end end
    return false
end

InventoryItemFactory = { CreateItem = function(fullType) return item(fullType, "System Storage Core", { weight = 0.5 }) end }

local Storage = require "GodSystem_Storage"
local Manager = require "GodSystem_StorageManager"

local hostItem = item("Base.Hammer", "Hammer")
local host = furnitureAt(0, 0, 0, { 50, 20 }, { { hostItem }, {} })
local left = furnitureAt(-1, 0, 0, { 40 }, { { item("Base.Plank", "Plank") } })

local function mark(object)
    local position = Storage.objectCoordinates(object)
    local ok, reason = Manager.setNetworkContainer(player, {
        x = position.x, y = position.y, z = position.z,
        objectIndex = Storage.getObjectIndex(object), sprite = Storage.objectSpriteName(object),
        name = "Test", enabled = true,
    })
    assert(ok, tostring(reason))
end
mark(host)
mark(left)

local claimed, claimReason = Manager.claimCore(player, {})
assert(claimed, tostring(claimReason))
local core = playerInventory.items.values[1]
local networkId, token = Storage.getCoreIdentity(core)
local coreArgs = {
    networkId = networkId, coreToken = token, coreItemId = Storage.itemId(core),
    x = 0, y = 0, z = 0, objectIndex = Storage.getObjectIndex(host), sprite = Storage.objectSpriteName(host),
}
local installed, installReason = Manager.installCore(player, coreArgs)
assert(installed, tostring(installReason))
assert(host.slots[1]:getCapacity() == 50 and host.slots[2]:getCapacity() == 20,
    "install must preserve every host-slot capacity")
assert(Storage.containerContains(host.slots[1], hostItem), "install must preserve existing host items")

local network = assert(Manager.getNetwork(networkId))
local view = Manager.connectedNetwork(network, host)
assert(view.nodeCount == 2, "host and adjacent furniture must be connected")
assert(Manager.linkCount(view) == 3, "both host slots and the adjacent slot must be normal links")
local hostLinkId
for linkId, link in pairs(view.links) do if link.isCoreHost == true then hostLinkId = linkId end end
assert(hostLinkId, "host links must expose isCoreHost")

local job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
local snapshot = Storage.buildSnapshot(job, view)
assert(snapshot.itemCount == 2, "host items must participate in the storage index")
local hostSummary
for i = 1, #snapshot.containers do if snapshot.containers[i].isCoreHost then hostSummary = snapshot.containers[i] end end
assert(hostSummary and hostSummary.objectId == Storage.getObjectId(host, false),
    "container summaries must expose host object identity")

local marker = Storage.getCoreHostMarker(host)
marker.hostVersion = nil
marker.capacityMode = nil
host.slots[1]:setCapacity(0)
host.slots[2]:setCapacity(0)
local resolved, _, migratedMarker, resolveReason = Manager.resolveCoreHost(player, coreArgs)
assert(resolved and not resolveReason, tostring(resolveReason))
assert(host.slots[1]:getCapacity() == 50 and host.slots[2]:getCapacity() == 20,
    "opening an old v1.16.70 host must restore its original capacities")
assert(migratedMarker.hostVersion == Storage.CoreHostVersion, "old host migration must be one-time and versioned")

local unlinkOk, unlinkReason = Manager.unlinkContainer(player, coreArgs, hostLinkId)
assert(not unlinkOk and unlinkReason == "coreInstalled", "core-host links must not be removable")
local updateOk, updateReason = Manager.updateLink(player, coreArgs, { linkId = hostLinkId, priority = 80, role = "material" })
assert(updateOk, tostring(updateReason))
assert(Storage.getNetworkContainerMarker(host).priority == 80, "core host must retain routing controls")

local favorite = item("Base.Saw", "Favorite Saw", { favorite = true })
local key = item("Base.Key1", "Key", { category = "Key" })
local protected = item("GodSystem.SystemSpaceTerminal", "Terminal")
local bulkNormal = item("Base.Nails", "Nails")
local bulkFavorite = item("Base.Axe", "Favorite Axe", { favorite = true })
local nestedChild = item("Base.Screwdriver", "Nested Screwdriver")
local nestedBag = containerItem("Base.Bag_DuffelBag", "Nested Bag", 20, { nestedChild })
local sourceBag = containerItem("Base.Bag_Schoolbag", "School Bag", 20, { bulkNormal, bulkFavorite, nestedBag })
playerInventory:AddItem(favorite)
playerInventory:AddItem(key)
playerInventory:AddItem(protected)
playerInventory:AddItem(sourceBag)
wornEntries.values[1] = { getItem = function() return sourceBag end, getLocation = function() return "Back" end }

local bulkOk, bulkReason, bulkStats = Manager.deposit(player, coreArgs, {
    mode = "sourceAll", sourceItemId = Storage.itemId(sourceBag),
})
assert(bulkOk, tostring(bulkReason))
assert(bulkStats.success == 2 and bulkStats.skipped == 1, "sourceAll must move only eligible direct children")
assert(Storage.containerContains(sourceBag.inventory, bulkFavorite), "sourceAll must keep favorites")
assert(Storage.containerContains(nestedBag.inventory, nestedChild), "sourceAll must not recurse into nested containers")

local manualOk, manualReason, manualStats = Manager.deposit(player, coreArgs, {
    mode = "selected", sourceItemId = nil,
    itemIds = { Storage.itemId(favorite), Storage.itemId(key), Storage.itemId(protected), Storage.itemId(favorite) },
})
assert(manualOk, tostring(manualReason))
assert(manualStats.requested == 3 and manualStats.success == 2 and manualStats.failed == 1,
    "manual deposit must deduplicate, allow favorite/key items, and reject protected items")
assert(#manualStats.successItemIds == 2 and #manualStats.failedItems == 1,
    "deposit results must identify successful and failed instances")

view = Manager.connectedNetwork(network, host)
job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
snapshot = Storage.buildSnapshot(job, view)
job.snapshot = snapshot
Manager.runtime.snapshotJobs[snapshot.snapshotId] = job
local favoriteGroup = Storage.itemGroupKey(favorite)
local keyGroup = Storage.itemGroupKey(key)
local withdrawn, withdrawReason, withdrawStats = Manager.withdraw(player, coreArgs, {
    snapshotId = snapshot.snapshotId,
    targetItemId = Storage.itemId(sourceBag),
    requests = {
        { groupKey = favoriteGroup, itemIds = { Storage.itemId(favorite) } },
        { groupKey = keyGroup, count = 1 },
        { groupKey = favoriteGroup, itemIds = { Storage.itemId(favorite) } },
    },
})
assert(withdrawn, tostring(withdrawReason))
assert(withdrawStats.requested == 2 and withdrawStats.success == 2,
    "multi-group withdraw must deduplicate exact instances")
assert(Storage.containerContains(sourceBag.inventory, favorite) and Storage.containerContains(sourceBag.inventory, key),
    "withdraw target must be the selected character container")

view = Manager.connectedNetwork(network, host)
local resetRoleOk, resetRoleReason = Manager.updateLink(player, coreArgs, { linkId = hostLinkId, role = "auto" })
assert(resetRoleOk, tostring(resetRoleReason))
view = Manager.connectedNetwork(network, host)
for _, link in pairs(view.links) do
    local _, target = Storage.resolveLink(link)
    target.capacity = target:getContentsWeight()
end
host.slots[2].capacity = host.slots[2]:getContentsWeight() + 1
local partialA = item("Base.Rope", "Rope", { weight = 1 })
local partialB = item("Base.Rope", "Rope", { weight = 1 })
playerInventory:AddItem(partialA)
playerInventory:AddItem(partialB)
local partialRoutes = Storage.routeCandidates(view, player, partialA)
assert(#partialRoutes == 1, "partial-capacity fixture must expose exactly one route, got " .. tostring(#partialRoutes))
local partialOk, partialReason, partialStats = Manager.deposit(player, coreArgs, {
    mode = "selected", sourceItemId = nil,
    itemIds = { Storage.itemId(partialA), Storage.itemId(partialB) },
})
assert(partialOk, tostring(partialReason))
assert(partialStats.requested == 2 and partialStats.success == 1 and partialStats.failed == 1,
    "capacity exhaustion must report one success and one failed instance")
assert(#partialStats.successItemIds == 1 and #partialStats.failedItems == 1,
    "partial deposit results must identify both outcomes")

view = Manager.connectedNetwork(network, host)
job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
snapshot = Storage.buildSnapshot(job, view)
job.snapshot = snapshot
Manager.runtime.snapshotJobs[snapshot.snapshotId] = job
local movedPartialId = partialStats.successItemIds[1]
local partialGroup = Storage.itemGroupKey(partialA)
playerInventory:Remove(sourceBag)
wornEntries.values = {}
local changedOk, changedReason = Manager.withdraw(player, coreArgs, {
    snapshotId = snapshot.snapshotId,
    targetItemId = Storage.itemId(sourceBag),
    requests = { { groupKey = partialGroup, itemIds = { movedPartialId } } },
})
assert(not changedOk and changedReason == "targetInvalid",
    "a changed character target must be rejected before moving warehouse items")
assert(Storage.findNetworkItems(view, { [movedPartialId] = true })[movedPartialId],
    "target changes must leave the requested instance in the warehouse")
playerInventory:AddItem(sourceBag)
wornEntries.values[1] = { getItem = function() return sourceBag end, getLocation = function() return "Back" end }

local expiredOk, expiredReason = Manager.withdraw(player, coreArgs, {
    snapshotId = "expired-snapshot",
    targetItemId = Storage.itemId(sourceBag),
    requests = { { groupKey = partialGroup, itemIds = { movedPartialId } } },
})
assert(not expiredOk and expiredReason == "snapshotExpired", "expired snapshots must be rejected without mutation")

local firstConcurrent, firstConcurrentReason = Manager.withdraw(player, coreArgs, {
    snapshotId = snapshot.snapshotId,
    targetItemId = Storage.itemId(sourceBag),
    requests = { { groupKey = partialGroup, itemIds = { movedPartialId } } },
})
assert(firstConcurrent, tostring(firstConcurrentReason))
local secondConcurrent, secondConcurrentReason, secondConcurrentStats = Manager.withdraw(player, coreArgs, {
    snapshotId = snapshot.snapshotId,
    targetItemId = Storage.itemId(sourceBag),
    requests = { { groupKey = partialGroup, itemIds = { movedPartialId } } },
})
assert(not secondConcurrent and secondConcurrentReason == "nothingMoved" and secondConcurrentStats.skipped == 1,
    "a stale concurrent request for the same instance must skip instead of duplicating it")
assert(Storage.findDirectItem(sourceBag.inventory, movedPartialId) ~= nil,
    "the winning concurrent request must place exactly the real instance in the selected target")

local operation, operationState = Manager.beginOperation(player, "v11671-retry", "same-request")
assert(operation and operationState == nil, "the first operation ID use must start")
local pendingOperation, pendingState = Manager.beginOperation(player, "v11671-retry", "same-request")
assert(pendingOperation == operation and pendingState == "pending", "identical in-flight retries must remain pending")
Manager.finishOperation(operation, true, nil, { success = 1 })
local doneOperation, doneState = Manager.beginOperation(player, "v11671-retry", "same-request")
assert(doneOperation == operation and doneState == "done", "identical completed retries must replay the stored result")
local mismatchOperation, mismatchState = Manager.beginOperation(player, "v11671-retry", "different-request")
assert(mismatchOperation == nil and mismatchState == "operationMismatch",
    "the same operation ID must reject a different normalized request")

view = Manager.connectedNetwork(network, host)
job = Storage.newIndexJob(view)
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
local beforePressure = Storage.buildSnapshot(job, view).itemCount
host.slots[1].capacity = 20000
for i = 1, 10000 do host.slots[1]:AddItem(item("Base.Nails", "Nails", { weight = 0.01 })) end
local pressureStarted = os.clock()
job = Storage.newIndexJob(Manager.connectedNetwork(network, host))
while not Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) do end
local pressureSnapshot = Storage.buildSnapshot(job, view)
assert(pressureSnapshot.itemCount == beforePressure + 10000 and pressureSnapshot.incomplete ~= true,
    "the storage index must complete a 10,000-item pressure fixture within the 20,000-item limit")
print(string.format("Test-GodSystemV11671Pressure items=10000 seconds=%.3f", os.clock() - pressureStarted))

local capacityBeforeRetrieve1 = host.slots[1]:getCapacity()
local capacityBeforeRetrieve2 = host.slots[2]:getCapacity()
local retrieved, retrieveReason = Manager.retrieveCore(player, coreArgs)
assert(retrieved, tostring(retrieveReason))
assert(Storage.containerContains(host.slots[1], hostItem), "retrieving the core must not remove host contents")
assert(host.slots[1]:getCapacity() == capacityBeforeRetrieve1 and host.slots[2]:getCapacity() == capacityBeforeRetrieve2,
    "retrieving the core must leave capacities unchanged")
assert(Storage.getNetworkContainerMarker(host) ~= nil and not Storage.isCoreHost(host),
    "retrieving must remove only core identity and preserve the network marker")

print("Test-GodSystemV11671Runtime passed")
