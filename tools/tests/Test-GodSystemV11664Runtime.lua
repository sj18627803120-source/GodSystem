local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    package.path,
}, ";")

GodSystemConfig = {
    DataKey = "GodSystem_Test",
}

local function list(values)
    return {
        values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
        contains = function(self, value)
            for i = 1, #self.values do if self.values[i] == value then return true end end
            return false
        end,
    }
end

local nextId = 100
local function item(fullType, name, category, weight, child)
    nextId = nextId + 1
    return {
        id = nextId,
        fullType = fullType,
        name = name,
        category = category,
        weight = weight or 1,
        child = child,
        getID = function(self) return self.id end,
        getFullType = function(self) return self.fullType end,
        getDisplayName = function(self) return self.name end,
        getName = function(self) return self.name end,
        getDisplayCategory = function(self) return self.category end,
        getType = function() return "Normal" end,
        getActualWeight = function(self) return self.weight end,
        getWeight = function(self) return self.weight end,
        getCondition = function() return 90 end,
        getConditionMax = function() return 100 end,
        getUsedDelta = function() return 0.75 end,
        getOffAge = function(self) return self.food and 10 or 1000000 end,
        getAge = function() return 2 end,
        getInventory = function(self) return self.child end,
        getContainer = function(self) return self.container end,
        getScriptItem = function() return nil end,
        getModData = function(self) self.modData = self.modData or {}; return self.modData end,
        isFavorite = function(self) return self.favorite == true end,
        isRotten = function() return false end,
        isStale = function() return false end,
        isCooked = function() return false end,
        isCooking = function() return false end,
        isFrozen = function() return false end,
    }
end

instanceof = function(value, typeName)
    return typeName == "Food" and value and value.food == true
end

local function container(values, ctype, capacity, powered)
    local result = {
        values = values or {},
        ctype = ctype or "crate",
        capacity = capacity or 50,
        powered = powered == true,
        rejectAdd = false,
        getItems = function(self) return list(self.values) end,
        getType = function(self) return self.ctype end,
        getCapacity = function(self) return self.capacity end,
        getContentsWeight = function(self)
            local total = 0
            for i = 1, #self.values do total = total + (self.values[i].weight or 0) end
            return total
        end,
        isPowered = function(self) return self.powered end,
        isItemAllowed = function() return true end,
        hasRoomFor = function(self) return #self.values < self.capacity end,
        Remove = function(self, value)
            for i = 1, #self.values do
                if self.values[i] == value then table.remove(self.values, i); value.container = nil; return end
            end
        end,
        AddItem = function(self, value)
            if self.rejectAdd then return nil end
            self.values[#self.values + 1] = value
            value.container = self
            return value
        end,
        setDrawDirty = function() end,
    }
    for i = 1, #result.values do result.values[i].container = result end
    return result
end

local squares = {}
local function objectAt(x, y, z, objectId, linkId, slotContainer, slotIndex)
    local square
    local object = {
        data = {
            GodSystemStorageObjectId = objectId,
            GodSystemStorageLinks = {
                [tostring(slotIndex or 0)] = {
                    objectId = objectId,
                    linkId = linkId,
                },
            },
        },
        getModData = function(self) return self.data end,
        getContainerCount = function() return 1 end,
        getContainerByIndex = function(self, index) if index == (slotIndex or 0) then return slotContainer end end,
        getSquare = function() return square end,
        getSprite = function() return { getName = function() return "test_sprite" end } end,
    }
    slotContainer.getParent = function() return object end
    square = {
        objects = list({ object }),
        getObjects = function(self) return self.objects end,
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
    squares[x .. ":" .. y .. ":" .. z] = square
    return object, square
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return squares[x .. ":" .. y .. ":" .. z] end,
    }
end

local Storage = require "GodSystem_Storage"

assert(Storage.ControllerFullType == "GodSystem.StorageController")
assert(Storage.DefaultRadius == 30)
assert(Storage.DefaultMaxLinks == 64)
assert(Storage.MaxIndexedItems == 20000)
assert(Storage.IndexBatchItems == 250)
assert(Storage.IndexBudgetMs == 2)

local food = item("Base.TestFood", "Test Food", "Food", 2)
food.food = true
assert(Storage.categoryOf(food) == "perishable")
assert(Storage.linkRoleAccepts({ role = "food" }, "perishable") == true)
assert(Storage.linkRoleAccepts({ role = "medical" }, "weapon") == false)

local protected = item("GodSystem.StorageController", "Controller", "Electronics", 2)
assert(Storage.isProtected(protected) == true)
local favorite = item("Base.Favorite", "Favorite", "Normal", 1)
favorite.favorite = true
local player = {
    getPrimaryHandItem = function() return nil end,
    getSecondaryHandItem = function() return nil end,
    getAttachedItems = function() return list({}) end,
    getWornItems = function() return list({}) end,
}
assert(Storage.isSafeDepositItem(player, protected) == false)
assert(Storage.isSafeDepositItem(player, favorite) == false)

local nestedItem = item("Base.Nested", "Nested", "Material", 1)
local child = container({ nestedItem }, "bag", 10, false)
local bag = item("Base.Bag", "Bag", "Container", 1, child)
local plank = item("Base.Plank", "Plank", "Material", 3)
local linkedContainer = container({ food, bag, protected, plank }, "fridge", 50, true)
objectAt(10, 10, 0, "object-a", "link-a", linkedContainer, 0)
local network = {
    networkId = "network-a",
    scope = "personal",
    controller = { x = 10, y = 10, z = 0 },
    radius = 30,
    links = {
        ["link-a"] = {
            linkId = "link-a", objectId = "object-a", x = 10, y = 10, z = 0,
            slotIndex = 0, name = "Fridge", role = "fridge", priority = 80,
        },
    },
    revision = 1,
}

local job = Storage.newIndexJob(network)
while not Storage.stepIndexJob(job, 250, 2) do end
local snapshot = Storage.buildSnapshot(job, network)
assert(snapshot.itemCount == 4, "protected items must not count as indexed storage instances")
assert(snapshot.groupCount == 4, "protected controller must not appear in grouped results")
assert(snapshot.onlineLinks == 1 and snapshot.offlineLinks == 0)
assert(snapshot.groups[1] ~= nil)
local live = Storage.findNetworkItems(network, {
    [tostring(nestedItem.id)] = true,
    [tostring(plank.id)] = true,
})
assert(live[tostring(nestedItem.id)].item == nestedItem, "bounded live lookup must find nested items")
assert(live[tostring(plank.id)].source == linkedContainer, "bounded live lookup must preserve the true source container")

local replacementContainer = container({}, "fridge", 50, true)
local replacement = objectAt(10, 10, 0, "object-new", "different-link", replacementContainer, 0)
local resolved, _, reason = Storage.resolveLink(network.links["link-a"])
assert(resolved == nil and reason == "objectMissing", "same-coordinate replacement must not inherit a link")

local source = container({ plank }, "crate", 10, false)
local target = container({}, "crate", 10, false)
local ok = Storage.transferItem(player, plank, source, target, nil)
assert(ok == true and #source.values == 0 and #target.values == 1)

local rollbackItem = item("Base.Rollback", "Rollback", "Material", 1)
local rollbackSource = container({ rollbackItem }, "crate", 10, false)
local failingTarget = container({}, "crate", 10, false)
failingTarget.rejectAdd = true
local moved, transferReason = Storage.transferItem(player, rollbackItem, rollbackSource, failingTarget, nil)
assert(moved == false and transferReason == "targetAddFailed")
assert(#rollbackSource.values == 1 and rollbackSource.values[1] == rollbackItem, "failed target add must restore source")

local changedItem = item("Base.TargetChanged", "Target Changed", "Material", 1)
local changedSource = container({ changedItem }, "crate", 10, false)
local changedTarget = container({}, "crate", 10, false)
local validationCalls = 0
local changed, changedReason = Storage.transferItem(player, changedItem, changedSource, changedTarget, nil, nil, function()
    validationCalls = validationCalls + 1
    return validationCalls < 3
end)
assert(changed == false and changedReason == "targetChanged")
assert(#changedSource.values == 1 and #changedTarget.values == 0, "post-insert target changes must restore the original source")

print("Test-GodSystemV11664Runtime passed")
