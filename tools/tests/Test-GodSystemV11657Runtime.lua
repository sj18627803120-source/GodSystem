GodSystemConfig = {
    CarryCapacityPerLevel = 2,
    CarryCapacityBaseCost = 2000,
    CarryCapacityCostMultiplier = 1.5,
}
package.preload["GodSystem_Config"] = function() return GodSystemConfig end

MoodleType = {
    HUNGRY = "HUNGRY",
    THIRST = "THIRST",
    SICK = "SICK",
    BLEEDING = "BLEEDING",
    INJURED = "INJURED",
}

dofile(arg[1])

local expected = { 2000, 3000, 4500, 6750, 10125, 15188, 22782 }
for level = 0, #expected - 1 do
    assert(GodSystemCarryCapacity.getNextCost(level) == expected[level + 1])
    assert(GodSystemCarryCapacity.getBonus(level) == level * 2)
end

local function makePlayer(weightMod, delta, final, moodles, modData)
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
    function player:getMaxWeightDelta() return self.delta end
    function player:setMaxWeightDelta(value) self.delta = value end
    function player:getMaxWeightBase() return self.base end
    function player:getWeightMod() return self.weightMod end
    function player:getMaxWeight() return self.final end
    function player:setMaxWeight(value) self.final = math.floor(value + 0.0001) end
    function player:getMoodles() return moodleState end
    function player:getModData() return self.modData end
    function player:recalculateMaxWeight()
        local reducers = 0
        local rules = {
            { MoodleType.HUNGRY, { [2] = 1, [3] = 2, [4] = 2 } },
            { MoodleType.THIRST, { [2] = 1, [3] = 2, [4] = 2 } },
            { MoodleType.SICK, { [2] = 1, [3] = 2, [4] = 3 } },
            { MoodleType.BLEEDING, { [2] = 1, [3] = 1, [4] = 1 } },
            { MoodleType.INJURED, { [2] = 1, [3] = 2, [4] = 3 } },
        }
        for i = 1, #rules do
            reducers = reducers + (rules[i][2][self.moodles[rules[i][1]] or 0] or 0)
        end
        local capacity = math.max(0, math.floor(self.base * self.weightMod) - reducers)
        self.final = math.floor(capacity * self.delta)
    end
    return player
end

local neutral = makePlayer(1.0, 1.0, 14)
local ok, result = GodSystemCarryCapacity.apply(neutral, 1)
assert(ok == true and result.base == 14 and result.total == 16 and result.actualBonus == 2)
neutral:recalculateMaxWeight()
assert(neutral:getMaxWeight() == 16)
ok, result = GodSystemCarryCapacity.reconcile(neutral, 1)
assert(ok == true and result.total == 16)

local strong = makePlayer(1.0, 1.5, 21)
ok, result = GodSystemCarryCapacity.apply(strong, 1)
assert(ok == true and result.total == 23 and result.actualBonus == 2)
strong:recalculateMaxWeight()
assert(strong:getMaxWeight() == 23)

local weak = makePlayer(1.0, 0.75, 10)
ok, result = GodSystemCarryCapacity.apply(weak, 1)
assert(ok == true and result.total == 12 and result.actualBonus == 2)
weak:recalculateMaxWeight()
assert(weak:getMaxWeight() == 12)

local injured = makePlayer(1.0, 1.0, 10, {
    [MoodleType.HUNGRY] = 2,
    [MoodleType.SICK] = 2,
    [MoodleType.INJURED] = 3,
})
ok, result = GodSystemCarryCapacity.apply(injured, 1)
assert(ok == true and result.base == 10 and result.total == 12 and result.actualBonus == 2)
injured:recalculateMaxWeight()
assert(injured:getMaxWeight() == 12)

local legacy = makePlayer(1.0, 1.142857142857, 16, {}, {
    GodSystemCarryAppliedBonus = 2,
    GodSystemCarryAppliedDelta = 1.142857142857,
    GodSystemCarryAppliedFactor = 0.142857142857,
    GodSystemCarryBaseline = 14,
})
ok, result = GodSystemCarryCapacity.apply(legacy, 2)
assert(ok == true and result.base == 14 and result.total == 18 and result.actualBonus == 4)
legacy:recalculateMaxWeight()
assert(legacy:getMaxWeight() == 18)

local rejected = makePlayer(1.0, 1.0, 14)
function rejected:setMaxWeight(_) end
ok = GodSystemCarryCapacity.apply(rejected, 1)
assert(ok == false and rejected.delta == 1.0 and rejected.final == 14)

print("Test-GodSystemV11657Runtime passed")
