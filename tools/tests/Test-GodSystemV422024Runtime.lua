local luaRoot = assert(arg[1], "lua root is required"):gsub("\\", "/")
package.path = luaRoot .. "/shared/?.lua;" .. package.path

require "GodSystem_B42JavaCalls"
require "GodSystem_Config"
require "GodSystem_TerminalRelief"
require "GodSystem_TerminalFood"
require "GodSystem_TerminalUpgrades"
require "GodSystem_AutoLoader"
require "GodSystem_Storage"
require "GodSystem_Attributes"

local Bridge = GodSystemB42JavaCalls

local function expect(value, message)
    if not value then error(message, 2) end
end

local parentItem = { marker = "parent" }
local nestedContainer = {
    getContainingItem = function(self) return parentItem end,
}
expect(Bridge.getContainingItem(nestedContainer) == parentItem, "nested container ownership lookup failed")

local dynamicTable = {
    customMethod = function(self, value) return value + 1 end,
}
expect(Bridge.value(dynamicTable, "customMethod", nil, 4) == 5, "plain Lua table fallback failed")
expect(Bridge.value({}, "getCapacity", 17) == 17, "missing mapped method did not use fallback")

local function list(items)
    return {
        size = function(self) return #items end,
        get = function(self, index) return items[index + 1] end,
    }
end

local inventory = {
    capacity = 10,
    reduction = 50,
    items = list({}),
    getCapacity = function(self) return self.capacity end,
    setCapacity = function(self, value) self.capacity = value end,
    getWeightReduction = function(self) return self.reduction end,
    setWeightReduction = function(self, value) self.reduction = value end,
    getItems = function(self) return self.items end,
}
local terminal = {
    capacity = 10,
    reduction = 50,
    inventory = inventory,
    modData = {},
    getCapacity = function(self) return self.capacity end,
    setCapacity = function(self, value) self.capacity = value end,
    getWeightReduction = function(self) return self.reduction end,
    setWeightReduction = function(self, value) self.reduction = value end,
    getInventory = function(self) return self.inventory end,
    getModData = function(self) return self.modData end,
}

local snapshot = GodSystemTerminalUpgrades.snapshotTerminal(terminal)
expect(snapshot.outerCapacity == 10 and snapshot.innerCapacity == 10, "terminal capacity snapshot failed")
expect(snapshot.outerReduction == 50 and snapshot.innerReduction == 50, "terminal reduction snapshot failed")
terminal.capacity, inventory.capacity = 49, 49
terminal.reduction, inventory.reduction = 99, 99
local restored = GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
expect(restored == true, "terminal snapshot restore failed")
expect(terminal.capacity == 10 and inventory.capacity == 10, "terminal capacity rollback mismatch")
expect(terminal.reduction == 50 and inventory.reduction == 50, "terminal reduction rollback mismatch")

local stubborn = {
    capacity = 49,
    reduction = 99,
    getCapacity = function(self) return self.capacity end,
    setCapacity = function(self, value) end,
    getWeightReduction = function(self) return self.reduction end,
    setWeightReduction = function(self, value) end,
}
local failed = GodSystemTerminalUpgrades.restoreSnapshot({
    terminal = stubborn,
    inventory = stubborn,
    outerCapacity = 10,
    innerCapacity = 10,
    outerReduction = 50,
    innerReduction = 50,
    relief = {},
})
expect(failed == false, "terminal write verification failure was not reported")

local magazine = {
    id = 42,
    rounds = 7,
    getID = function(self) return self.id end,
    getCurrentAmmoCount = function(self) return self.rounds end,
}
expect(GodSystemAutoLoader.itemId(magazine) == "42", "auto-loader item ID read failed")
expect(GodSystemAutoLoader.safeCall(magazine, "getCurrentAmmoCount", -1) == 7, "auto-loader ammo read failed")

local itemList = list({ magazine })
local storageInventory = { getItems = function(self) return itemList end }
expect(GodSystemStorage.safeCall(storageInventory, "getItems", nil) == itemList, "storage inventory read failed")
expect(GodSystemStorage.safeCall(itemList, "size", -1) == 1, "storage list size read failed")
expect(GodSystemStorage.safeCall(itemList, "get", nil, 0) == magazine, "storage list item read failed")

local xp = { getXP = function(self, perk) return perk == "mock" and 123 or 0 end }
expect(Bridge.value(xp, "getXP", nil, "mock") == 123, "attribute XP read failed")

print("Test-GodSystemV422024Runtime OK")
