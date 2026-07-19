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

local function makeItem(id, weight, custom, options)
    options = options or {}
    local item = {
        id = id,
        weight = weight,
        defaultWeight = weight,
        custom = custom == true,
        modData = {},
        options = options,
    }
    function item:getID() return self.id end
    function item:getFullType() return "Test.Item" .. tostring(self.id) end
    function item:getActualWeight() return self.weight end
    function item:setActualWeight(value)
        if self.options.failWrite then error("simulated item weight failure") end
        self.weight = value
    end
    function item:isCustomWeight() return self.custom end
    function item:setCustomWeight(value)
        value = value == true
        if value and not self.custom and self.options.resetWhenCustomEnabled then
            self.weight = self.defaultWeight
        end
        self.custom = value
    end
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

local function makeTerminal(id, inventory)
    local terminal = { id = id, inventory = inventory, modData = {}, capacity = 0, reduction = 50 }
    function terminal:getID() return self.id end
    function terminal:getInventory() return self.inventory end
    function terminal:getModData() return self.modData end
    function terminal:setCapacity(value) self.capacity = value end
    function terminal:getCapacity() return self.capacity end
    function terminal:setWeightReduction(value) self.reduction = value end
    function terminal:getWeightReduction() return self.reduction end
    return terminal
end

dofile(arg[1])

local normal = makeItem(10, 10, false, { resetWhenCustomEnabled = true })
local custom = makeItem(11, 10, true)
local failing = makeItem(12, 10, false, { failWrite = true })
local inventory = makeInventory({ normal, custom, failing })
local terminal = makeTerminal(99, inventory)
local data = { autoRecyclerCapacityLevel = 8, autoRecyclerReductionLevel = 8, autoRecyclerCompressionLevel = 8 }

local ok, report = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true)
assert(terminal.capacity == 49 and inventory.capacity == 49)
assert(terminal.reduction == 99 and inventory.reduction == 99)
assert(math.abs(normal.weight - 1) < 0.0001 and normal.custom == true)
assert(math.abs(custom.weight - 10) < 0.0001 and custom.custom == true)
assert(math.abs(failing.weight - 10) < 0.0001 and failing.custom == false)
assert(report.processed == 1 and report.skipped == 2 and report.failed == 1)
assert(report.reasonCounts.customWeight == 1 and report.reasonCounts.writeExceptionRestoreFailed == 1)

local status = GodSystemTerminalUpgrades.getAppliedStatus(terminal, data)
assert(status.capacityApplied == true and status.reductionApplied == true)
assert(status.outerReduction == 99 and status.innerReduction == 99)
assert(status.processed == 1 and status.skipped == 2 and status.failed == 1)

ok = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true and math.abs(normal.weight - 1) < 0.0001)

local newlyAdded = makeItem(13, 20, false, { resetWhenCustomEnabled = true })
inventory.values[#inventory.values + 1] = newlyAdded
ok, report = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true and math.abs(newlyAdded.weight - 2) < 0.0001 and newlyAdded.custom == true)
assert(report.processed == 2 and report.failed == 1)

inventory.values = { custom, failing }
ok, report = GodSystemTerminalUpgrades.applyTerminal(terminal, data)
assert(ok == true)
assert(math.abs(normal.weight - 10) < 0.0001 and normal.custom == false)
assert(math.abs(newlyAdded.weight - 20) < 0.0001 and newlyAdded.custom == false)
assert(#report.restoredItems == 2)

local bulkValues = {}
for i = 1, 96 do
    bulkValues[#bulkValues + 1] = makeItem(1000 + i, 10, false, { resetWhenCustomEnabled = true })
end
bulkValues[#bulkValues + 1] = makeItem(2000, 10, false, { failWrite = true })
local bulkInventory = makeInventory(bulkValues)
local bulkTerminal = makeTerminal(100, bulkInventory)
ok, report = GodSystemTerminalUpgrades.applyTerminal(bulkTerminal, data)
assert(ok == true and report.processed == 96 and report.skipped == 1 and report.failed == 1)
for i = 1, 96 do assert(math.abs(bulkValues[i].weight - 1) < 0.0001) end

print("Test-GodSystemV11658TerminalRuntime passed")
