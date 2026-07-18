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
    base = 12,
    modData = {},
}

function player:getMaxWeightDelta() return self.delta end
function player:setMaxWeightDelta(value) self.delta = value end
function player:getMaxWeight() return self.base + self.delta end
function player:getModData() return self.modData end

local ok = GodSystemCarryCapacity.apply(player, 1)
assert(ok == true and player.delta == 2)
ok = GodSystemCarryCapacity.apply(player, 1)
assert(ok == true and player.delta == 2)

player.delta = player.delta + 3
ok = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and player.delta == 7)

GodSystemCarryCapacity.clearRuntime(player)
ok = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and player.delta == 7)

player.delta = 3
GodSystemCarryCapacity.clearRuntime(player)
ok = GodSystemCarryCapacity.apply(player, 2)
assert(ok == true and player.delta == 7)

local status = GodSystemCarryCapacity.getStatus(player, 2)
assert(status.level == 2)
assert(status.bonus == 4)
assert(status.applied == true)
assert(status.base == 15)
assert(status.total == 19)

print("Test-GodSystemV11657Runtime passed")
