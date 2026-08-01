local sourcePath = assert(arg[1], "Terminal food service path is required")

GodSystemConfig = {
    TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
    TerminalCoolingLevels = {
        { level = 1, multiplier = 2, ageFactor = 0.5, upgradeCost = 1250 },
        { level = 2, multiplier = 4, ageFactor = 0.25, upgradeCost = 3250 },
        { level = 3, multiplier = 8, ageFactor = 0.125, upgradeCost = 7000 },
    },
    TerminalFreshnessRestorePerDay = { [1] = 0.25, [2] = 0.5, [3] = 1.0 },
    TerminalFreshnessMaxDays = 365,
    TerminalFreshnessPackages = {
        [1] = 100,
        [10] = 900,
        [20] = 1600,
        [30] = 2100,
    },
}

package.preload["GodSystem_Config"] = function()
    return GodSystemConfig
end

function instanceof(item, class)
    return class == "Food" and item and item.__food == true
end

dofile(sourcePath)

local function food(age, offAge, rotten, fullType)
    local item = { __food = true, age = age, offAge = offAge, rotten = rotten == true, fullType = fullType or "Base.Apple" }
    function item:getAge() return self.age end
    function item:setAge(value) self.age = value end
    function item:getOffAge() return self.offAge end
    function item:isRotten() return self.rotten end
    function item:getFullType() return self.fullType end
    return item
end

local function inventory(items)
    local container = { items = items, ageFactor = 1 }
    function container:getItems()
        local list = { values = self.items }
        function list:size() return #self.values end
        function list:get(index) return self.values[index + 1] end
        return list
    end
    function container:getAgeFactor() return self.ageFactor end
    function container:setAgeFactor(value) self.ageFactor = value end
    return container
end

local function terminal(items)
    local value = { inv = inventory(items), modData = {} }
    function value:getInventory() return self.inv end
    function value:getModData() return self.modData end
    return value
end

local data = {}
GodSystemTerminalFood.normalizeData(data)
assert(GodSystemTerminalFood.getCoolingLevel(data) == 0, "old saves must start at cooling level 0")
assert(GodSystemTerminalFood.getRemainingHours(data) == 0, "old saves must start with no freshness service")

assert(GodSystemTerminalFood.setCoolingLevel(data, 1) == true, "cooling level 1 must be accepted")
local coldTerminal = terminal({})
local applied, report = GodSystemTerminalFood.applyCooling(coldTerminal, data)
assert(applied == true and report.ageFactor == 0.5, "level 1 must configure a two-times native age factor")
assert(coldTerminal.inv.ageFactor == 0.5, "container age factor must be applied")

local fresh = food(4, 8, false)
local rotten = food(12, 8, true)
local protected = food(4, 8, false, "GodSystem.SystemTerminalRelief")
coldTerminal = terminal({ fresh, rotten, protected })
assert(GodSystemTerminalFood.purchaseService(data, 10) == true, "freshness package must be purchasable after cooling")
local beforeHours = GodSystemTerminalFood.getRemainingHours(data)
local settlement = GodSystemTerminalFood.settle(data, coldTerminal, 24)
assert(settlement.hoursConsumed == 24, "active service must consume online elapsed hours")
assert(GodSystemTerminalFood.getRemainingHours(data) == beforeHours - 24, "service balance must decrement once")
assert(fresh.age == 2, "level 1 must restore 25 percent of an eight-day fresh window per day")
assert(rotten.age == 12, "rotten food must not be restored")
assert(protected.age == 4, "protected terminal internals must not be restored")
assert(settlement.changedItems and settlement.changedItems[1] == fresh and #settlement.changedItems == 1,
    "settlement must report only the direct food instances whose age changed")

data.terminalFood.remainingHours = 24
data.terminalFood.lastSettledHour = 10
data.terminalFood.expiryNotified = false
assert(GodSystemTerminalFood.beginOnlineSession(data, 50) == true,
    "a resumed online session must reset the persisted settlement clock")
settlement = GodSystemTerminalFood.settleOnline(data, coldTerminal, 50)
assert(settlement.hoursConsumed == 0 and GodSystemTerminalFood.getRemainingHours(data) == 24,
    "a resumed session must not charge time while the player was offline")

GodSystemTerminalFood.setCoolingLevel(data, 3)
fresh.age = 8
settlement = GodSystemTerminalFood.settle(data, coldTerminal, 24)
assert(fresh.age == 0, "level 3 must restore one fresh window per game day")

data.terminalFood.remainingHours = 24
data.terminalFood.expiryNotified = false
settlement = GodSystemTerminalFood.settle(data, nil, 24)
assert(settlement.hoursConsumed == 24 and GodSystemTerminalFood.getRemainingHours(data) == 0,
    "service must keep counting while the terminal is missing")
assert(settlement.expired == true, "service expiry must be reported once")

print("Test-GodSystemV422015TerminalFoodRuntime passed")
