local luaRoot = assert(arg[1], "lua root is required"):gsub("\\", "/")
package.path = luaRoot .. "/shared/?.lua;" .. package.path

require "GodSystem_B42JavaCalls"
require "GodSystem_Config"
MoodleType = MoodleType or {
    HUNGRY = "HUNGRY",
    THIRST = "THIRST",
    SICK = "SICK",
    BLEEDING = "BLEEDING",
    INJURED = "INJURED",
}
require "GodSystem_CarryCapacity"
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
expect(Bridge.value({}, "getUsedDelta", 1) == 1, "missing optional userdata method did not use fallback")

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

local function mockPlayer(weightMod, delta, moodles, final, modData)
    local player = {
        base = 14,
        weightMod = weightMod,
        delta = delta,
        final = final,
        moodles = moodles or {},
        modData = modData or {},
    }
    local moodleState = {
        getMoodleLevel = function(_, moodle) return player.moodles[moodle] or 0 end,
    }
    function player:getMaxWeightBase() return self.base end
    function player:getWeightMod() return self.weightMod end
    function player:getMaxWeightDelta() return self.delta end
    function player:setMaxWeightDelta(value) self.delta = value end
    function player:getMaxWeight() return self.final end
    function player:setMaxWeight(value) self.final = math.floor(value + 0.0001) end
    function player:getMoodles() return moodleState end
    function player:getModData() return self.modData end
    function player:updateVanilla()
        local reducers = 0
        local rules = {
            { MoodleType.HUNGRY, { [2] = 1, [3] = 2, [4] = 2 } },
            { MoodleType.THIRST, { [2] = 1, [3] = 2, [4] = 2 } },
            { MoodleType.SICK, { [2] = 1, [3] = 2, [4] = 3 } },
            { MoodleType.BLEEDING, { [2] = 1, [3] = 1, [4] = 1 } },
            { MoodleType.INJURED, { [2] = 1, [3] = 2, [4] = 3 } },
        }
        local nativeCapacity = math.floor(self.base * self.weightMod)
        for i = 1, #rules do
            reducers = reducers + (rules[i][2][self.moodles[rules[i][1]] or 0] or 0)
        end
        nativeCapacity = math.max(0, nativeCapacity - reducers)
        self.final = math.floor(nativeCapacity * self.delta)
    end
    return player
end

local neutral = mockPlayer(1.0, 1.0, {}, 14)
local applied, status = GodSystemCarryCapacity.apply(neutral, 1)
expect(applied == true, "neutral carry upgrade should apply")
expect(status.total == 16 and status.base == 14 and status.actualBonus == 2, "neutral carry result must be native final plus two")
neutral:updateVanilla()
expect(neutral.final == 16, "neutral carry must survive the vanilla strength update")
local repeated, repeatedStatus = GodSystemCarryCapacity.reconcile(neutral, 1)
expect(repeated == true and repeatedStatus.total == 16, "repeated neutral carry recalibration must not stack")

local strong = mockPlayer(1.0, 1.5, {}, 21)
local strongApplied, strongStatus = GodSystemCarryCapacity.apply(strong, 1)
expect(strongApplied == true and strongStatus.total == 23 and strongStatus.actualBonus == 2, "Strong carry must add two to the vanilla final")
strong:updateVanilla()
expect(strong.final == 23, "Strong carry must survive the vanilla strength update")

local weak = mockPlayer(1.0, 0.75, {}, 10)
local weakApplied, weakStatus = GodSystemCarryCapacity.apply(weak, 1)
expect(weakApplied == true and weakStatus.total == 12 and weakStatus.actualBonus == 2, "Weak carry must add two after vanilla flooring")
weak:updateVanilla()
expect(weak.final == 12, "Weak carry must survive the vanilla strength update")

local injured = mockPlayer(1.0, 1.0, {
    [MoodleType.HUNGRY] = 2,
    [MoodleType.SICK] = 2,
    [MoodleType.INJURED] = 3,
}, 10)
local injuredApplied, injuredStatus = GodSystemCarryCapacity.apply(injured, 1)
expect(injuredApplied == true and injuredStatus.base == 10 and injuredStatus.total == 12 and injuredStatus.actualBonus == 2, "Moodle reducers must be included before the carry bonus")
injured:updateVanilla()
expect(injured.final == 12, "Moodle-aware carry must survive the vanilla strength update")

local legacy = mockPlayer(1.0, 1.142857142857, {}, 16, {
    GodSystemCarryAppliedBonus = 2,
    GodSystemCarryAppliedDelta = 1.142857142857,
    GodSystemCarryAppliedFactor = 0.142857142857,
    GodSystemCarryBaseline = 14,
})
local migrated, migratedStatus = GodSystemCarryCapacity.apply(legacy, 2)
expect(migrated == true and migratedStatus.base == 14 and migratedStatus.total == 18 and migratedStatus.actualBonus == 4, "legacy carry markers must migrate without stacking the old factor")
legacy:updateVanilla()
expect(legacy.final == 18, "migrated carry must survive the vanilla strength update")

print("Test-GodSystemV422024Runtime OK")
