local carryPath = assert(arg[1], "carry module path is required")
local adminPath = assert(arg[2], "admin configuration module path is required")

GodSystemConfig = {
    CarryCapacityPerLevel = 2,
    CarryCapacityBaseCost = 1234,
    CarryCapacityCostMultiplier = 1.25,
}
package.preload["GodSystem_Config"] = function() return GodSystemConfig end

dofile(carryPath)

assert(GodSystemCarryCapacity.getNextCost(0) == 1234, "configured base cost must apply at level zero")
assert(GodSystemCarryCapacity.getNextCost(1) == 1543, "configured multiplier must apply at level one")
assert(GodSystemCarryCapacity.getNextCost(2) == 1929, "configured multiplier must continue across levels")

GodSystemConfig.CarryCapacityBaseCost = 75
GodSystemConfig.CarryCapacityCostMultiplier = 2
assert(GodSystemCarryCapacity.getNextCost(3) == 600, "runtime configuration changes must reach the shared quote")

GodSystemConfig.CarryCapacityBaseCost = 0
GodSystemConfig.CarryCapacityCostMultiplier = 0.5
assert(GodSystemCarryCapacity.getNextCost(3) == 1, "invalid settings keep the existing safe lower bounds")

GodSystemConfig.CarryCapacityBaseCost = 2000
GodSystemConfig.CarryCapacityCostMultiplier = 1.5
dofile(adminPath)
local settings = GodSystemAdminConfig.getDefaults()
settings.CarryCapacityBaseCost = 90
settings.CarryCapacityCostMultiplier = 2
GodSystemAdminConfig.applyRuntime(settings, {}, {}, 1)
assert(GodSystemConfig.CarryCapacityBaseCost == 90, "admin base-cost setting must update the runtime config")
assert(GodSystemConfig.CarryCapacityCostMultiplier == 2, "admin multiplier setting must update the runtime config")
assert(GodSystemCarryCapacity.getNextCost(3) == 720, "shared quote must use the administrator runtime settings")

print("V422023CarryRuntimeOK")
