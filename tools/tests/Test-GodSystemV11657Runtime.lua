GodSystemConfig = {
    CarryCapacityPerLevel = 2,
    CarryCapacityBaseCost = 2000,
    CarryCapacityCostMultiplier = 1.5,
}
package.preload["GodSystem_Config"] = function() return GodSystemConfig end

dofile(arg[1])

local expected = { 2000, 3000, 4500, 6750, 10125, 15188, 22782 }
for level = 0, #expected - 1 do
    assert(GodSystemCarryCapacity.getNextCost(level) == expected[level + 1])
    assert(GodSystemCarryCapacity.getBonus(level) == level * 2)
end

local function float32(value)
    if value == 0 then return 0 end
    local sign = value < 0 and -1 or 1
    value = math.abs(value)
    local exponent = math.floor(math.log(value) / math.log(2))
    local step = 2 ^ (exponent - 23)
    return sign * math.floor((value / step) + 0.5) * step
end

local function makePlayer(base, modelOffset, delta)
    local player = {
        delta = delta ~= nil and delta or (modelOffset == 1 and 0 or 1),
        base = base,
        modelOffset = modelOffset,
        final = 0,
        modData = {},
    }
    function player:getMaxWeightDelta() return self.delta end
    function player:setMaxWeightDelta(value) self.delta = float32(value) end
    function player:getMaxWeightBase() return self.base end
    function player:getMaxWeight() return self.final end
    function player:setMaxWeight(value) self.final = value end
    function player:getModData() return self.modData end
    function player:recalculateMaxWeight()
        self.final = math.max(0, math.ceil(self.base * (self.delta + self.modelOffset)))
    end
    player:recalculateMaxWeight()
    return player
end

-- Reproduce the live B42 boundary without changing the configured behavior.
local boundary = makePlayer(14, 1)
boundary:setMaxWeightDelta(2 / 14)
boundary:recalculateMaxWeight()
assert(boundary:getMaxWeight() == 17)

local player = makePlayer(14, 1)
local ok, result = GodSystemCarryCapacity.apply(player, 1)
assert(ok == true)
assert(result.predictedFinal == 17 and result.predictedIncrease == 3)
assert(result.base == 14 and result.total == 16 and result.actualBonus == 2)
player:recalculateMaxWeight()
local status = GodSystemCarryCapacity.getStatus(player, 1)
assert(status.base == 14 and status.total == 17 and status.actualBonus == 3)

local before = player:getMaxWeight()
ok, result = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and result.predictedIncrease == result.predictedFinal - before)
player:recalculateMaxWeight()
status = GodSystemCarryCapacity.getStatus(player, 2)
assert(status.total == result.predictedFinal)
assert(status.actualBonus == status.total - status.base)

local stable = status.total
for _ = 1, 10 do
    ok, result = GodSystemCarryCapacity.apply(player, 2)
    assert(ok == true and result.predictedFinal == stable)
    player:recalculateMaxWeight()
    assert(player:getMaxWeight() == stable)
end

local external = makePlayer(14, 1, 0.5)
before = external:getMaxWeight()
ok, result = GodSystemCarryCapacity.apply(external, 2)
assert(ok == true and result.predictedIncrease == result.predictedFinal - before)
external:recalculateMaxWeight()
status = GodSystemCarryCapacity.getStatus(external, 2)
assert(status.base == 21 and status.total == result.predictedFinal)
assert(status.actualBonus == status.total - 21)

-- Measurement adapts when an interface exposes maxWeightDelta as a neutral
-- one total multiplier instead of a neutral zero additive delta.
local multiplier = makePlayer(14, 0, 1)
ok, result = GodSystemCarryCapacity.apply(multiplier, 1)
assert(ok == true and result.predictedFinal == 17 and result.predictedIncrease == 3)
multiplier:recalculateMaxWeight()
status = GodSystemCarryCapacity.getStatus(multiplier, 1)
assert(status.base == 14 and status.total == 17 and status.actualBonus == 3)

local legacy = makePlayer(14, 1, 6)
legacy.modData = {
    GodSystemCarryAppliedBonus = 6,
    GodSystemCarryAppliedDelta = legacy.delta,
}
ok, result = GodSystemCarryCapacity.apply(legacy, 3)
assert(ok == true and result.predictedFinal ~= nil)
legacy:recalculateMaxWeight()
status = GodSystemCarryCapacity.getStatus(legacy, 3)
assert(status.total == result.predictedFinal and status.actualBonus == status.total - 14)

local rejected = makePlayer(14, 1)
function rejected:setMaxWeight(_) end
ok = GodSystemCarryCapacity.apply(rejected, 1)
assert(ok == false and rejected.delta == 0 and rejected.final == 14)

print("Test-GodSystemV11657Runtime passed")
