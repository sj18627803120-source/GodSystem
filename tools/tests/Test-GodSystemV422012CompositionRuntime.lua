local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Composition"

local stateRoot = {}
local broken = {
    id = "test.broken",
    dependencies = {},
    stateVersion = 1,
    create = function()
        error("expected isolated failure")
    end,
}
local dependent = {
    id = "test.dependent",
    dependencies = { "test.broken" },
    stateVersion = 1,
    create = function()
        error("blocked module must not be created")
    end,
}

local runtime = GodSystemComposition.create({
    version = "42.20.1.2",
    protocolVersion = "42.20.1.2",
    environment = "test",
    descriptors = { broken, dependent },
    adapters = {
        state = {
            load = function() return stateRoot end,
            save = function(_, nextRoot)
                stateRoot = nextRoot
                return true
            end,
        },
    },
})

assert(runtime.startResult and runtime.startResult.ok == true, "composition did not start")
assert(runtime.registry:status("feature.wallet").state == "started", "wallet was not composed")
assert(runtime.registry:status("wallet").state == "started", "wallet public port was not composed")
assert(runtime.registry:status("feature.maintenance").state == "started", "maintenance was not composed")
assert(runtime.registry:status("feature.autoloader").state == "started", "autoloader was not composed")
assert(runtime.registry:status("test.broken").state == "failed", "broken module failure was not isolated")
assert(runtime.registry:status("test.dependent").state == "blocked", "dependent module was not blocked")

local health = runtime:health()
assert(#health.modules == 21, "composition health omitted registered modules")
assert(type(runtime.registry:get("feature.wallet")) == "table", "wallet public API unavailable")
assert(type(runtime.registry:get("feature.autoloader")) == "table", "autoloader public API unavailable")

runtime:stop("test")
assert(runtime.registry:status("feature.wallet").state == "stopped", "composition did not stop modules")

print("Test-GodSystemV422012CompositionRuntime passed")
