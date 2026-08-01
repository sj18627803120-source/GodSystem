local sourcePath = assert(arg[1], "Terminal food service path is required")

GodSystemConfig = {
    TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
    TerminalFreshnessLevels = {
        { level = 1, restorePerDay = 0.25, upgradeCost = 1250 },
        { level = 2, restorePerDay = 0.5, upgradeCost = 3250 },
        { level = 3, restorePerDay = 1.0, upgradeCost = 7000 },
    },
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

local function terminal(items)
    local container = { items = items }
    function container:getItems()
        local list = { values = self.items }
        function list:size() return #self.values end
        function list:get(index) return self.values[index + 1] end
        return list
    end
    local value = { inv = container }
    function value:getInventory() return self.inv end
    return value
end

local data = {}
GodSystemTerminalFood.normalizeData(data)
assert(GodSystemTerminalFood.getFreshnessLevel(data) == 0, "new local test data starts with freshness efficiency disabled")
assert(GodSystemTerminalFood.getRemainingHours(data) == 0, "new local test data starts with no service time")
assert(GodSystemTerminalFood.canPurchaseService(data, 1) == false, "service purchase requires freshness efficiency level 1")

assert(GodSystemTerminalFood.setFreshnessLevel(data, 1) == true, "freshness efficiency level 1 is accepted")
local fresh = food(4, 8, false)
local rotten = food(12, 8, true)
local protected = food(4, 8, false, "GodSystem.SystemTerminalRelief")
local directTerminal = terminal({ fresh, rotten, protected })
assert(GodSystemTerminalFood.purchaseService(data, 10) == true, "10-day package is purchasable after enabling freshness efficiency")
local beforeHours = GodSystemTerminalFood.getRemainingHours(data)
local settlement = GodSystemTerminalFood.settle(data, directTerminal, 24)
assert(settlement.hoursConsumed == 24, "active service consumes online elapsed hours")
assert(GodSystemTerminalFood.getRemainingHours(data) == beforeHours - 24, "service balance decrements exactly once")
assert(fresh.age == 2, "level 1 restores 25 percent of the direct food fresh window per day")
assert(rotten.age == 12, "rotten food is not restored")
assert(protected.age == 4, "protected terminal internals are not restored")
assert(settlement.changedItems and settlement.changedItems[1] == fresh and #settlement.changedItems == 1,
    "settlement reports only direct food instances whose age changed")

GodSystemTerminalFood.setFreshnessLevel(data, 3)
fresh.age = 8
data.terminalFood.remainingHours = 24
settlement = GodSystemTerminalFood.settle(data, directTerminal, 24)
assert(fresh.age == 0, "level 3 restores one full fresh window per game day")

data.terminalFood.remainingHours = 24
data.terminalFood.lastSettledHour = 10
assert(GodSystemTerminalFood.beginOnlineSession(data, 50) == true, "resumed online session resets the settlement clock")
settlement = GodSystemTerminalFood.settleOnline(data, directTerminal, 50)
assert(settlement.hoursConsumed == 0 and GodSystemTerminalFood.getRemainingHours(data) == 24,
    "offline elapsed time is never charged to the service")

data.terminalFood.expiryNotified = false
settlement = GodSystemTerminalFood.settle(data, nil, 24)
assert(settlement.hoursConsumed == 24 and GodSystemTerminalFood.getRemainingHours(data) == 0,
    "service time continues while the terminal is missing")
assert(settlement.expired == true, "service expiry is reported once")

print("Test-GodSystemV422016TerminalFoodRuntime passed")
