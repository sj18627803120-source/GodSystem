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

local player = {
    delta = 0,
    base = 14,
    modData = {},
}

function player:getMaxWeightDelta() return self.delta end
function player:setMaxWeightDelta(value) self.delta = value end
function player:getMaxWeightBase() return self.base end
function player:getMaxWeight() return self.base * (1 + self.delta) end
function player:getModData() return self.modData end

local ok = GodSystemCarryCapacity.apply(player, 1)
assert(ok == true and math.abs(player:getMaxWeight() - 16) < 0.01)
ok = GodSystemCarryCapacity.apply(player, 1)
assert(ok == true and math.abs(player:getMaxWeight() - 16) < 0.01)

player.delta = player.delta + 0.5
ok = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and math.abs(player:getMaxWeight() - 25) < 0.01)

GodSystemCarryCapacity.clearRuntime(player)
ok = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and math.abs(player:getMaxWeight() - 25) < 0.01)

local status = GodSystemCarryCapacity.getStatus(player, 2)
assert(status.level == 2)
assert(status.bonus == 4)
assert(status.applied == true)
assert(math.abs(status.base - 21) < 0.01)
assert(math.abs(status.total - 25) < 0.01)

local legacy = { delta = 6, base = 14, modData = {
    GodSystemCarryAppliedBonus = 6,
    GodSystemCarryAppliedDelta = 6,
} }
function legacy:getMaxWeightDelta() return self.delta end
function legacy:setMaxWeightDelta(value) self.delta = value end
function legacy:getMaxWeightBase() return self.base end
function legacy:getMaxWeight() return self.base * (1 + self.delta) end
function legacy:getModData() return self.modData end
ok = GodSystemCarryCapacity.apply(legacy, 3)
assert(ok == true and math.abs(legacy:getMaxWeight() - 20) < 0.01)

print("Test-GodSystemV11657Runtime passed")
