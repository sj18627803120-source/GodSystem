local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    package.path,
}, ";")

Events = {}
local eventAddCount = 0
local eventRemoveCount = 0
local eventDispatcher = nil
Events.OnTick = {
    Add = function(handler)
        eventAddCount = eventAddCount + 1
        eventDispatcher = handler
    end,
    Remove = function(handler)
        assert(handler == eventDispatcher, "gateway removed an unknown dispatcher")
        eventRemoveCount = eventRemoveCount + 1
    end,
}

require "GodSystem/Bootstrap"

local stateRoot = {}
local stateAdapter = {
    load = function() return stateRoot end,
    save = function(_, root)
        stateRoot = root
        return true
    end,
}

local runtime = GodSystemBootstrap.create({
    version = "42.20.1.2",
    protocolVersion = "42.20.1.2",
    environment = "test",
    adapters = { state = stateAdapter },
})

assert(runtime:register({
    id = "service.alpha",
    dependencies = {},
    create = function(dependencies)
        assert(next(dependencies) == nil, "root module received undeclared dependencies")
        return {
            public = { value = 7 },
            health = function()
                return GodSystemResult.ok("service.alpha", "ok", { value = 7 })
            end,
        }
    end,
}))

assert(runtime:register({
    id = "feature.beta",
    dependencies = { "service.alpha" },
    create = function(dependencies, context)
        assert(dependencies["service.alpha"].value == 7, "declared dependency was not injected")
        assert(context.moduleId == "feature.beta", "module context was not scoped")
        return {
            public = { name = "beta" },
            start = function(self, activeRuntime)
                self.startedIn = activeRuntime.environment
                return true
            end,
            health = function(self)
                return GodSystemResult.ok("feature.beta", "ok", { environment = self.startedIn })
            end,
        }
    end,
}))

assert(runtime:register({
    id = "feature.failed",
    dependencies = {},
    create = function()
        error("expected isolated failure")
    end,
}))

assert(runtime:register({
    id = "feature.blocked",
    dependencies = { "feature.failed" },
    create = function()
        error("blocked module must not be created")
    end,
}))

local startResult = runtime:start()
assert(startResult.ok == true, "runtime did not complete isolated startup")
assert(runtime.registry:status("service.alpha").state == "started", "independent service did not start")
assert(runtime.registry:status("feature.beta").state == "started", "dependent feature did not start")
assert(runtime.registry:status("feature.failed").state == "failed", "failing feature was not isolated")
assert(runtime.registry:status("feature.blocked").state == "blocked", "dependent failure did not block only its branch")

local alphaState = runtime.state:scoped("service.alpha", 1)
local betaState = runtime.state:scoped("feature.beta", 1)
alphaState:get().value = 11
betaState:get().value = 22
assert(alphaState:get().value == 11, "alpha state changed unexpectedly")
assert(betaState:get().value == 22, "module state scopes are not isolated")
assert(runtime.state:save() == true, "state adapter save failed")

local tickCalls = {}
assert(runtime.events:subscribe("service.alpha", "OnTick", function() tickCalls[#tickCalls + 1] = "alpha" end, 0))
assert(runtime.events:subscribe("feature.beta", "OnTick", function() tickCalls[#tickCalls + 1] = "beta" end, 10))
assert(eventAddCount == 1, "gateway registered more than one PZ dispatcher for one event")
eventDispatcher()
assert(tickCalls[1] == "beta" and tickCalls[2] == "alpha", "gateway priority ordering failed")

assert(runtime.commands:register("GodSystem", "ping", function(_, args)
    return GodSystemResult.ok("feature.beta", "pong", { value = args.value }, args.operationId)
end))
local mismatch = runtime.commands:dispatch("GodSystem", "ping", nil, {
    protocolVersion = "old",
    operationId = "op-1",
})
assert(mismatch.ok == false and mismatch.code == "protocolMismatch", "exact protocol check failed")
local pong = runtime.commands:dispatch("GodSystem", "ping", nil, {
    protocolVersion = "42.20.1.2",
    operationId = "op-2",
    value = 9,
})
assert(pong.ok == true and pong.code == "pong" and pong.data.value == 9, "command dispatch failed")

local health = runtime:health()
assert(type(health.modules) == "table" and #health.modules == 4, "module health report is incomplete")
local simple = runtime.diagnostics:simpleReport()
assert(simple.version == "42.20.1.2", "diagnostics version missing")
assert(simple.lastIssue and simple.lastIssue.moduleId == "feature.failed", "isolated failure was not recorded")

runtime:stop("test")
assert(eventRemoveCount == 1, "gateway did not remove its PZ dispatcher")

local cycleRuntime = GodSystemBootstrap.create({
    version = "42.20.1.2",
    environment = "test",
    adapters = { state = stateAdapter },
})
assert(cycleRuntime:register({ id = "a", dependencies = { "b" }, create = function() return {} end }))
assert(cycleRuntime:register({ id = "b", dependencies = { "a" }, create = function() return {} end }))
local cycleResult = cycleRuntime:start()
assert(cycleResult.ok == false and cycleResult.code == "dependencyCycle", "dependency cycle was not rejected")

print("Test-GodSystemV422012ArchitectureRuntime passed")
