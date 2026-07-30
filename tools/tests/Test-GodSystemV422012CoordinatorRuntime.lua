local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local Coordinator = require "GodSystem/Runtime/Coordinator"

local handlers = {}
local events = {}
function events:subscribe(moduleId, eventName, handler)
    assert(moduleId == "runtime.coordinator", "unexpected coordinator module id")
    handlers[eventName] = handler
    return true
end
function events:unsubscribeModule(moduleId)
    assert(moduleId == "runtime.coordinator", "unexpected unsubscribe module id")
    handlers = {}
    return true
end

local actor = { id = "player-one", x = 0, y = 0, z = 0, kills = 4 }
local metrics = { zombieKills = 4, moveDistance = 0 }
local calls = {
    initialized = 0,
    generated = 0,
    claimed = 0,
    bank = {},
    cleared = 0,
    storage = 0,
    saves = 0,
    failed = {},
}
local modules = {
    metrics = {
        increment = function(_, changes)
            for name, amount in pairs(changes) do
                metrics[name] = (metrics[name] or 0) + amount
            end
            return true, { changes = changes }
        end,
    },
    ["feature.system"] = {
        ensureInitialized = function(request)
            assert(request.actor == actor and request.operationId, "system initialize request")
            calls.initialized = calls.initialized + 1
            return { ok = true, code = "initialized" }
        end,
    },
    ["feature.tasks"] = {
        generate = function(request)
            assert(request.operationId, "task generation operation id")
            calls.generated = calls.generated + 1
            return { ok = true, code = "generated" }
        end,
        snapshot = function()
            return {
                ok = true,
                data = {
                    autoClaimEnabled = true,
                    tasks = {
                        { taskId = "ready", status = "active", complete = true },
                        { taskId = "waiting", status = "active", complete = false },
                    },
                },
            }
        end,
        claim = function(request)
            assert(request.taskId == "ready", "coordinator claimed incomplete task")
            calls.claimed = calls.claimed + 1
            return { ok = true, code = "claimed" }
        end,
    },
    ["feature.bank"] = {
        execute = function(request)
            calls.bank[#calls.bank + 1] = request.action
            return { ok = true, code = request.action }
        end,
    },
    ["feature.home"] = {
        clearSafeZone = function(request)
            assert(request.manual == false, "automatic clear marked manual")
            calls.cleared = calls.cleared + 1
            return { ok = true, code = "cleared" }
        end,
    },
    ["feature.storage"] = {
        processJobs = function()
            calls.storage = calls.storage + 1
            return { indexJobs = 0, organizerJobs = 0 }
        end,
    },
    clock = {
        nowHours = function() return 48 end,
        currentDay = function() return 2 end,
    },
}
local registry = {}
function registry:get(moduleId) return modules[moduleId] end
function registry:fail(moduleId, code, detail)
    calls.failed[#calls.failed + 1] = {
        moduleId = moduleId,
        code = code,
        detail = detail,
    }
    modules[moduleId] = nil
    return true
end
local diagnostics = { rows = {} }
function diagnostics:record(row)
    self.rows[#self.rows + 1] = row
end

local coordinator = Coordinator.new({
    version = "42.20.1.2",
    events = events,
    registry = registry,
    diagnostics = diagnostics,
    save = function() calls.saves = calls.saves + 1 return true end,
    binding = {
        actorKey = function(value) return value.id end,
        position = function(value) return value.x, value.y, value.z end,
        zombieKills = function(value) return value.kills end,
    },
})
assert(coordinator:start(), "coordinator start")
assert(handlers.OnCreatePlayer and handlers.OnPlayerUpdate
    and handlers.EveryOneMinute and handlers.EveryHours
    and handlers.OnTick and handlers.OnSave,
    "coordinator did not register bounded lifecycle events")

handlers.OnCreatePlayer(0, actor)
assert(calls.initialized == 1, "player initialization not coordinated")
handlers.OnPlayerUpdate(actor)
actor.x, actor.y, actor.kills = 3, 4, 6
handlers.OnPlayerUpdate(actor)
assert(metrics.zombieKills == 4 and metrics.moveDistance == 0,
    "player update wrote persistent metrics every frame")
handlers.EveryOneMinute()
assert(metrics.zombieKills == 6 and metrics.moveDistance == 5,
    "minute flush did not write accumulated metrics")
assert(calls.claimed == 1 and calls.saves == 1,
    "minute pass did not auto-claim once and save once")

handlers.EveryHours()
assert(calls.generated == 1 and calls.claimed == 2,
    "hour pass did not generate and auto-claim")
assert(#calls.bank == 2 and calls.bank[1] == "syncInvestmentHours"
    and calls.bank[2] == "updateLoan", "bank periodic actions changed")
assert(calls.cleared == 1 and calls.saves == 2,
    "hour pass did not clear safe zone and save once")

handlers.OnTick()
assert(calls.storage == 1 and calls.saves == 2,
    "bounded storage tick unexpectedly saved every frame")

modules["feature.storage"].processJobs = function() error("storage probe failure") end
handlers.OnTick()
assert(#calls.failed == 1 and calls.failed[1].moduleId == "feature.storage",
    "runtime callback failure was not isolated to its module")
assert(#diagnostics.rows >= 1, "runtime callback failure was not diagnosed")

handlers.OnSave()
assert(calls.saves == 3, "save event did not persist once")
assert(coordinator:stop(), "coordinator stop")
assert(calls.saves == 4, "coordinator stop did not flush state")
assert(coordinator:health().code == "stopped", "coordinator health after stop")

print("Test-GodSystemV422012CoordinatorRuntime passed")
