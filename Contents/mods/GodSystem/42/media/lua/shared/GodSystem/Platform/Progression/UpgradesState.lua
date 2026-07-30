require "GodSystem/Platform/Progression/StateFactory"

GodSystemUpgradesStatePlatform = GodSystemUpgradesStatePlatform or GodSystemProgressionStateFactory.descriptor(
    "upgrades.state", {
        upgrades = { carryCapacityLevel = 0, maxActiveTasks = 3, dailyTaskCount = 5 },
        tasks = {},
        autoRecyclerCapacityLevel = 1,
        autoRecyclerReductionLevel = 1,
        autoRecyclerReliefLevel = 1,
    })

return GodSystemUpgradesStatePlatform
