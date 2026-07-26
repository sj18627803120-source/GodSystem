local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    package.path,
}, ";")

GodSystemConfig = { DataKey = "GodSystem_V11665_Test" }

local function javaList(values)
    return {
        values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
        contains = function(self, value)
            for i = 1, #self.values do
                if self.values[i] == value then return true end
            end
            return false
        end,
    }
end

local nextId = 1000
local function controllerItem()
    nextId = nextId + 1
    return {
        id = nextId,
        data = {},
        getID = function(self) return self.id end,
        getFullType = function() return "GodSystem.StorageController" end,
        getModData = function(self) return self.data end,
        getContainer = function(self) return self.container end,
        getInventory = function() return nil end,
        transmitModData = function() end,
    }
end

local function inventory()
    local result = { values = {} }
    result.getItems = function(self) return javaList(self.values) end
    result.AddItem = function(self, value)
        if type(value) == "string" then value = controllerItem() end
        self.values[#self.values + 1] = value
        value.container = self
        return value
    end
    result.Remove = function(self, value)
        for i = 1, #self.values do
            if self.values[i] == value then
                table.remove(self.values, i)
                value.container = nil
                return
            end
        end
    end
    result.setDrawDirty = function() end
    return result
end

local playerInventory = inventory()
local player = {
    getInventory = function() return playerInventory end,
    getUsername = function() return "tester" end,
    getOnlineID = function() return 1 end,
    getX = function() return 10 end,
    getY = function() return 20 end,
    getZ = function() return 0 end,
    getAccessLevel = function() return "None" end,
}

local globalStore = {}
ModData = {
    getOrCreate = function(key)
        globalStore[key] = globalStore[key] or {}
        return globalStore[key]
    end,
    transmit = function() end,
}
InventoryItemFactory = {
    CreateItem = function(fullType)
        assert(fullType == "GodSystem.StorageController")
        return controllerItem()
    end,
}
SafeHouse = nil
getCell = function()
    return { getGridSquare = function() return nil end }
end
getTimestampMs = function()
    nextId = nextId + 1
    return nextId * 10
end
ZombRand = function() return 77 end

local Storage = require "GodSystem_Storage"
local Manager = require "GodSystem_StorageManager"

assert(Storage.ControllerRecoveryCost == 2000)
local initial = assert(Manager.controllerStatus(player))
assert(initial.state == "unclaimed" and initial.nextCost == 0)

local committedCost = -1
local ok, reason, first = Manager.claimController(player, {
    charge = function() error("first claim must not charge") end,
    onCommit = function(cost) committedCost = cost end,
})
assert(ok == true and reason == nil)
assert(first.recovered == false and first.cost == 0)
assert(committedCost == 0)
assert(#playerInventory.values == 1)

local ownedOk, ownedReason = Manager.claimController(player, {})
assert(ownedOk == false and ownedReason == "controllerOwned")
assert(#playerInventory.values == 1, "repeat claim must not create a second controller")

local current = playerInventory.values[1]
local networkId, currentToken = Storage.getControllerIdentity(current)
playerInventory:Remove(current)
local expired = controllerItem()
Storage.setControllerIdentity(expired, networkId, "expired-token")
playerInventory:AddItem(expired)

local charged = 0
local recoveryCommitted = 0
local recoveredOk, recoveredReason, recovered = Manager.claimController(player, {
    charge = function(cost)
        charged = charged + cost
        return true, { test = true }
    end,
    onCommit = function(cost)
        recoveryCommitted = recoveryCommitted + cost
    end,
})
assert(recoveredOk == true and recoveredReason == nil)
assert(recovered.recovered == true and recovered.cost == 2000)
assert(charged == 2000 and recoveryCommitted == 2000)
assert(#playerInventory.values == 1, "paid recovery must clean same-network expired inventory duplicates")
local finalNetworkId, finalToken = Storage.getControllerIdentity(playerInventory.values[1])
assert(finalNetworkId == networkId)
assert(finalToken ~= currentToken and finalToken ~= "expired-token")

local finalStatus = assert(Manager.controllerStatus(player))
assert(finalStatus.state == "kit" and finalStatus.nextCost == 2000)

playerInventory:Remove(playerInventory.values[1])
local originalFactory = InventoryItemFactory.CreateItem
local originalInventoryAdd = playerInventory.AddItem
InventoryItemFactory.CreateItem = function() return nil end
playerInventory.AddItem = function() return nil end
local failureCharged, failureRefunded = 0, 0
local failureOk, failureReason = Manager.claimController(player, {
    charge = function(cost)
        failureCharged = failureCharged + cost
        return true, { amount = cost }
    end,
    refund = function(receipt)
        failureRefunded = failureRefunded + (receipt and receipt.amount or 0)
        return true
    end,
})
assert(failureOk == false and failureReason == "createFailed")
assert(failureCharged == 2000 and failureRefunded == 2000, "failed recovery creation must refund exactly once")
InventoryItemFactory.CreateItem = originalFactory
playerInventory.AddItem = originalInventoryAdd

print("Test-GodSystemV11665Runtime passed")
