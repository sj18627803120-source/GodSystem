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
local configConsumer = {
    id = "test.config",
    dependencies = {},
    stateVersion = 1,
    create = function(_, context)
        assert(context.configSnapshot and context.configSnapshot.marker == "available",
            "configuration snapshot was not injected")
        return {
            public = {},
            start = function() return true end,
            stop = function() return true end,
            health = function()
                return { ok = true, code = "healthy", moduleId = "test.config" }
            end,
        }
    end,
}

local runtime = GodSystemComposition.create({
    version = "42.20.1.2",
    protocolVersion = "42.20.1.2",
    environment = "test",
    descriptors = { broken, dependent, configConsumer },
    configSnapshot = { marker = "available" },
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
assert(runtime.registry:status("feature.tasks").state == "started", "tasks were not composed")
assert(runtime.registry:status("feature.shop").state == "started", "shop was not composed")
assert(runtime.registry:status("feature.recycle").state == "started", "recycle was not composed")
assert(runtime.registry:status("feature.upgrades").state == "started", "upgrades were not composed")
assert(runtime.registry:status("upgrades.read").state == "started", "upgrade read port was not composed")
assert(runtime.registry:status("feature.medical").state == "started", "medical was not composed")
assert(runtime.registry:status("feature.home").state == "started", "home was not composed")
assert(runtime.registry:status("test.broken").state == "failed", "broken module failure was not isolated")
assert(runtime.registry:status("test.dependent").state == "blocked", "dependent module was not blocked")
assert(runtime.registry:status("test.config").state == "started", "configuration consumer did not start")

local random = assert(runtime.registry:get("random"), "random service unavailable")
local randomIndex = random.index(4)
assert(randomIndex and randomIndex >= 1 and randomIndex <= 4, "random index contract is invalid")

local operations = assert(runtime.registry:get("operations"), "operation service unavailable")
local operationStatus = operations.begin("test.module", "composition-op", "fingerprint")
assert(operationStatus == "new", "direct operation contract did not return new")
local finishedOperation = operations.finish("test.module", "composition-op", { ok = true })
assert(type(finishedOperation) == "table" and finishedOperation.ok == true,
    "direct operation could not finish")
local replayStatus, replayResult = operations.begin("test.module", "composition-op", "fingerprint")
assert(replayStatus == "replay" and replayResult.ok == true, "direct operation did not replay")
local playerA = { actorKey = "player-a" }
local playerB = { actorKey = "player-b" }
assert(operations.begin("test.scope", "same-operation", "same", playerA) == "new",
    "first player operation did not start")
assert(operations.begin("test.scope", "same-operation", "same", playerB) == "new",
    "second player operation collided with first player")
operations.finish("test.scope", "same-operation", { ok = true }, playerA)
operations.finish("test.scope", "same-operation", { ok = true }, playerB)

local health = runtime:health()
assert(#health.modules >= 43, "composition health omitted registered modules")
assert(type(runtime.registry:get("feature.wallet")) == "table", "wallet public API unavailable")
assert(type(runtime.registry:get("feature.autoloader")) == "table", "autoloader public API unavailable")

runtime:stop("test")
assert(runtime.registry:status("feature.wallet").state == "stopped", "composition did not stop modules")

print("Test-GodSystemV422012CompositionRuntime passed")
