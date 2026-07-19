GodSystemConfig = {
    AutoRecyclerLevels = { {}, {}, {}, {}, {}, {}, {}, {} },
    TerminalCapacityLevels = {
        { value = 10 }, { value = 15, upgradeCost = 60 }, { value = 20, upgradeCost = 120 }, { value = 25, upgradeCost = 220 },
        { value = 30, upgradeCost = 350 }, { value = 35, upgradeCost = 550 }, { value = 42, upgradeCost = 800 }, { value = 49, upgradeCost = 1100 },
    },
    TerminalReductionLevels = {
        { value = 50 }, { value = 55, upgradeCost = 100 }, { value = 60, upgradeCost = 200 }, { value = 65, upgradeCost = 400 },
        { value = 70, upgradeCost = 700 }, { value = 80, upgradeCost = 1100 }, { value = 90, upgradeCost = 1700 }, { value = 99, upgradeCost = 2500 },
    },
    TerminalCompressionLevels = {
        { value = 0 }, { value = 15, upgradeCost = 500 }, { value = 30, upgradeCost = 1000 }, { value = 45, upgradeCost = 2000 },
        { value = 60, upgradeCost = 3500 }, { value = 75, upgradeCost = 5500 }, { value = 85, upgradeCost = 8000 }, { value = 90, upgradeCost = 12000 },
    },
}
package.preload["GodSystem_Config"] = function() return GodSystemConfig end

local function list(values)
    return {
        values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
    }
end

local function makeItem(id, weight, custom)
    local item = { id = id, weight = weight, custom = custom == true, modData = {} }
    function item:getID() return self.id end
    function item:getActualWeight() return self.weight end
    function item:setActualWeight(value) self.weight = value end
    function item:isCustomWeight() return self.custom end
    function item:setCustomWeight(value) self.custom = value == true end
    function item:getModData() return self.modData end
    return item
end

local function makeInventory(values)
    local inventory = { values = values, capacity = 0, reduction = 0 }
    function inventory:getItems() return list(self.values) end
    function inventory:setCapacity(value) self.capacity = value end
    function inventory:getCapacity() return self.capacity end
    function inventory:setWeightReduction(value) self.reduction = value end
    function inventory:getWeightReduction() return self.reduction end
    return inventory
end

dofile(arg[1])

local migrated = { autoRecyclerLevel = 5 }
GodSystemTerminalUpgrades.normalizeData(migrated)
assert(migrated.autoRecyclerCapacityLevel == 5)
assert(migrated.autoRecyclerReductionLevel == 5)
assert(migrated.autoRecyclerCompressionLevel == 1)

local normal = makeItem(10, 10, false)
local custom = makeItem(11, 10, true)
local inventory = makeInventory({ normal, custom })
local terminal = { modData = {} }
function terminal:getID() return 99 end
function terminal:getInventory() return inventory end
function terminal:getModData() return self.modData end
function terminal:setCapacity(value) self.capacity = value end
function terminal:getCapacity() return self.capacity end
function terminal:setWeightReduction(value) self.reduction = value end
function terminal:getWeightReduction() return self.reduction end

local data = { autoRecyclerCapacityLevel = 1, autoRecyclerReductionLevel = 7, autoRecyclerCompressionLevel = 8 }
local ok, report = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true)
assert(math.abs(normal.weight - 1) < 0.0001)
assert(normal.custom == true)
assert(math.abs(custom.weight - 10) < 0.0001)
assert(report.skipped == 1)
assert(inventory.capacity == 10 and inventory.reduction == 90)

ok = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true and math.abs(normal.weight - 1) < 0.0001)
data.autoRecyclerCompressionLevel = 7
ok = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true and math.abs(normal.weight - 1.5) < 0.0001)

inventory.values = { custom }
ok, report = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true and math.abs(normal.weight - 10) < 0.0001 and normal.custom == false)
assert(#report.restoredItems == 1)

local info = GodSystemTerminalUpgrades.getUpgradeInfo(data, "capacity")
assert(info.level == 1 and info.nextValue == 15 and info.nextCost == 60)
print("Test-GodSystemV11657TerminalRuntime passed")
