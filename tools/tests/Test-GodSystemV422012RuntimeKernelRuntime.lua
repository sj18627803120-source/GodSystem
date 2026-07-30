local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local persisted = {}
local saveCount = 0
local stateAdapter = {
    load = function() return persisted end,
    save = function(_, value)
        persisted = value
        saveCount = saveCount + 1
        return true
    end,
}
local eventAdapter = {
    add = function() return true end,
    remove = function() return true end,
}
local commandAdapter = {
    send = function() return true end,
}

require "GodSystem/Runtime/Kernel"
local legacy = {
    playerData = {
        version = "42.20.1.1",
        started = true,
        currencyInitialized = true,
        points = 0,
        tasks = {},
        unlockedShopItems = {},
        upgrades = {},
        bank = { current = 75 },
        homeSystem = {},
        companion = {},
        adminConfig = {},
        history = {},
        stats = {},
        ui = {},
    },
}
local runtime = GodSystemRuntimeKernel.create({
    environment = "sp",
    stateAdapter = stateAdapter,
    eventAdapter = eventAdapter,
    commandAdapter = commandAdapter,
    legacySnapshots = { { actorKey = "local", snapshot = legacy } },
    configSnapshot = { tasks = { templates = {} } },
})
assert(runtime.version == "42.20.1.2", "runtime version mismatch")
assert(runtime.protocolVersion == "42.20.1.2", "runtime protocol mismatch")
assert(runtime.startResult and runtime.startResult.ok, "runtime did not start")
assert(runtime.diagnostics.migration.code == "migrationComplete",
    "runtime diagnostics omitted migration")
assert(runtime.registry:get("feature.bank"), "runtime omitted bank feature")
assert(runtime.registry:get("feature.admin"), "runtime omitted admin feature")
assert(runtime.registry:get("feature.attributes"), "runtime omitted attributes feature")
assert(persisted.modules["wallet.accounts"].data.accounts["local"].current == 75,
    "runtime did not migrate before module state load")
assert(runtime.configSnapshot.tasks and type(runtime.configSnapshot.tasks.templates) == "table",
    "runtime did not build a configuration snapshot")
local savesBeforeDiagnostics = saveCount
local diagnostics = runtime:dispatch({
    protocol = "42.20.1.2",
    requestId = "kernel-diagnostics",
    action = "diagnostics.snapshot",
    args = {},
}, { actorKey = "local" })
assert(diagnostics.ok and diagnostics.moduleId == "runtime.diagnostics",
    "runtime diagnostics endpoint failed")
assert(type(diagnostics.data.modules) == "table"
    and diagnostics.data.version == "42.20.1.2",
    "runtime diagnostics snapshot was incomplete")
assert(saveCount == savesBeforeDiagnostics,
    "read-only diagnostics unexpectedly saved player state")
local dispatched = runtime:dispatch({
    protocol = "42.20.1.2",
    requestId = "kernel-balance",
    action = "wallet.balance",
    args = {},
}, { actorKey = "local" })
assert(dispatched.ok and dispatched.code == "balance", "runtime dispatcher was not connected")
local bankSummary = runtime:dispatch({
    protocol = "42.20.1.2",
    requestId = "kernel-bank-summary",
    action = "bank.summary",
    args = {},
}, { actorKey = "local" })
assert(bankSummary.ok and bankSummary.data.current == 75,
    "request-style bank summary lost the actor")
local taskSnapshot = runtime:dispatch({
    protocol = "42.20.1.2",
    requestId = "kernel-task-snapshot",
    action = "tasks.snapshot",
    args = {},
}, { actorKey = "local" })
assert(taskSnapshot.ok and type(taskSnapshot.data.tasks) == "table",
    "request-style task snapshot failed")
local homeSnapshot = runtime:dispatch({
    protocol = "42.20.1.2",
    requestId = "kernel-home-snapshot",
    action = "home.snapshot",
    args = {},
}, { actorKey = "local" })
assert(homeSnapshot.ok and type(homeSnapshot.data.homeSystem) == "table",
    "request-style home snapshot failed")
assert(runtime:save() == true, "runtime save failed")
runtime:stop("test")

print("Test-GodSystemV422012RuntimeKernelRuntime passed")
