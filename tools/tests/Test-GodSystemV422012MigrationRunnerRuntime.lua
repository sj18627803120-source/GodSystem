local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/State/MigrationRunner"

local saved
local adapter = {
    load = function() return saved or {} end,
    save = function(_, value) saved = value return true end,
}
local function legacy(current)
    return {
        playerData = {
            version = "42.20.1.1",
            started = true,
            currencyInitialized = true,
            points = 0,
            tasks = {},
            unlockedShopItems = {},
            upgrades = {},
            bank = { current = current },
            homeSystem = {},
            companion = {},
            adminConfig = {},
            history = {},
            stats = { spentPoints = current, recycledItems = 2 },
            ui = {},
        },
    }
end

local result = GodSystemMigrationRunner.run({
    adapter = adapter,
    snapshots = {
        { actorKey = "alice", snapshot = legacy(120) },
        { actorKey = "bob", snapshot = legacy(350) },
    },
})
assert(result.ok and result.code == "migrationComplete", "runner migration failed")
assert(saved.modules["wallet.accounts"].data.accounts.alice.current == 120,
    "alice account missing")
assert(saved.modules["wallet.accounts"].data.accounts.bob.current == 350,
    "bob account missing")
assert(saved.modules.metrics.data.counters.alice.spentPoints == 120
    and saved.modules.metrics.data.counters.bob.recycledItems == 2,
    "legacy cross-module counters were not migrated")
assert(next(result.disabledModules) == nil, "healthy migration disabled a module")

saved.modules["wallet.accounts"].data.accounts.alice.current = 999
local repeated = GodSystemMigrationRunner.run({
    adapter = adapter,
    snapshots = { { actorKey = "alice", snapshot = legacy(120) } },
})
assert(repeated.root.modules["wallet.accounts"].data.accounts.alice.current == 999,
    "runner repeat overwrote new state")

local corrupt = legacy(50)
corrupt.playerData.tasks = "bad"
saved = nil
local partial = GodSystemMigrationRunner.run({
    adapter = adapter,
    snapshots = { { actorKey = "alice", snapshot = corrupt } },
})
assert(not partial.ok and partial.code == "migrationPartial", "partial migration not reported")
assert(partial.disabledModules["tasks.state"], "failed state owner was not disabled")
assert(not partial.disabledModules["wallet.accounts"], "independent module was disabled")

local corruptMetrics = legacy(75)
corruptMetrics.playerData.stats = "bad"
saved = nil
local metricsPartial = GodSystemMigrationRunner.run({
    adapter = adapter,
    snapshots = { { actorKey = "alice", snapshot = corruptMetrics } },
})
assert(metricsPartial.disabledModules.metrics
    and not metricsPartial.disabledModules["system.state"],
    "corrupt legacy counters disabled an unrelated state owner")

print("Test-GodSystemV422012MigrationRunnerRuntime passed")
