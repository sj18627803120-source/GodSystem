local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local persisted = {}
local stateAdapter = {
    load = function() return persisted end,
    save = function(_, value) persisted = value return true end,
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
assert(persisted.modules["wallet.accounts"].data.accounts["local"].current == 75,
    "runtime did not migrate before module state load")
assert(runtime:save() == true, "runtime save failed")
runtime:stop("test")

print("Test-GodSystemV422012RuntimeKernelRuntime passed")
