local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Runtime/UseCaseDispatcher"

local calls = {}
local issues = {}
local dispatcher = GodSystemUseCaseDispatcher.new({
    protocolVersion = "42.20.1.2",
    routes = {
        ["test.run"] = { moduleId = "feature.test", method = "run" },
        ["test.explode"] = { moduleId = "feature.test", method = "explode" },
        ["missing.module"] = { moduleId = "feature.missing", method = "run" },
        ["missing.method"] = { moduleId = "feature.test", method = "missing" },
    },
    resolve = function(moduleId)
        if moduleId ~= "feature.test" then return nil end
        return {
            run = function(request)
                calls[#calls + 1] = request
                return {
                    ok = true,
                    code = "executed",
                    data = { amount = request.amount },
                }
            end,
            explode = function() error("expected failure") end,
        }
    end,
    diagnostics = {
        record = function(_, issue) issues[#issues + 1] = issue end,
    },
})

local actor = { username = "alice" }
local sourceArgs = { amount = 7 }
local result = dispatcher:dispatch({
    protocol = "42.20.1.2",
    requestId = "request-1",
    operationId = "operation-1",
    action = "test.run",
    args = sourceArgs,
}, actor)
assert(result.ok and result.code == "executed", "valid request failed")
assert(result.moduleId == "feature.test" and result.operationId == "operation-1",
    "result envelope was not normalized")
assert(calls[1].actor == actor and calls[1].amount == 7, "actor or arguments were not injected")
assert(sourceArgs.actor == nil and sourceArgs.operationId == nil, "source arguments were mutated")

local mismatch = dispatcher:dispatch({
    protocol = "42.20.1.1",
    action = "test.run",
}, actor)
assert(not mismatch.ok and mismatch.code == "protocolMismatch", "mixed protocol was accepted")

local unknown = dispatcher:dispatch({
    protocol = "42.20.1.2",
    action = "test.unknown",
}, actor)
assert(not unknown.ok and unknown.code == "actionUnknown", "unknown action was accepted")

local unavailable = dispatcher:dispatch({
    protocol = "42.20.1.2",
    action = "missing.module",
}, actor)
assert(not unavailable.ok and unavailable.code == "moduleUnavailable",
    "missing module was not isolated")

local missingMethod = dispatcher:dispatch({
    protocol = "42.20.1.2",
    action = "missing.method",
}, actor)
assert(not missingMethod.ok and missingMethod.code == "useCaseUnavailable",
    "missing method was not isolated")

local exploded = dispatcher:dispatch({
    protocol = "42.20.1.2",
    operationId = "operation-2",
    action = "test.explode",
}, actor)
assert(not exploded.ok and exploded.code == "useCaseFailed", "exception escaped dispatcher")
assert(#issues == 1 and issues[1].moduleId == "feature.test"
    and issues[1].operationId == "operation-2", "exception was not diagnosable")

print("Test-GodSystemV422012UseCaseDispatcherRuntime passed")
