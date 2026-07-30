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
local actorTwo = { id = "player-two", x = 10, y = 10, z = 0, kills = 0 }
local metrics = { zombieKills = 4, moveDistance = 0 }
local calls = {
    initialized = 0,
    generated = 0,
    claimed = 0,
    bank = {},
    bankHours = {},
    cleared = 0,
    storage = 0,
    carryRefresh = 0,
    terminalReconcile = 0,
    killRewards = 0,
    autoRecycle = 0,
    taskFailures = {},
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
            assert((request.actor == actor or request.actor == actorTwo)
                and request.operationId, "system initialize request")
            calls.initialized = calls.initialized + 1
            return { ok = true, code = "initialized" }
        end,
    },
    ["feature.wallet"] = {
        requestGrant = function(request)
            assert(request.amount == 2 and request.scope == "cash",
                "kill reward request changed")
            calls.killRewards = calls.killRewards + 1
            return { ok = true, code = "granted" }
        end,
    },
    ["feature.upgrades"] = {
        refresh = function(request)
            assert(request.upgradeType == "carryCapacity",
                "create-player carry refresh changed")
            calls.carryRefresh = calls.carryRefresh + 1
            return { ok = true, code = "refreshed" }
        end,
    },
    ["feature.terminal"] = {
        reconcile = function()
            calls.terminalReconcile = calls.terminalReconcile + 1
            return { ok = true, code = "reconciled" }
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
                        {
                            taskId = "ready",
                            status = calls.claimed > 0 and "completed" or "active",
                            complete = true,
                        },
                        {
                            taskId = "waiting",
                            status = calls.taskFailures.waiting and "failed" or "active",
                            complete = false,
                            deadline = 47,
                        },
                        {
                            taskId = "death-only",
                            status = calls.deathReady
                                and not calls.taskFailures["death-only"]
                                and "active" or "available",
                            complete = false,
                            deadline = 99,
                        },
                    },
                },
            }
        end,
        claim = function(request)
            assert(request.taskId == "ready", "coordinator claimed incomplete task")
            calls.claimed = calls.claimed + 1
            return { ok = true, code = "claimed" }
        end,
        fail = function(request)
            calls.taskFailures[request.taskId] = request.reason or true
            return { ok = true, code = "failed" }
        end,
    },
    ["feature.bank"] = {
        execute = function(request)
            calls.bank[#calls.bank + 1] = request.action
            calls.bankHours[#calls.bankHours + 1] = request.hours
            return { ok = true, code = request.action }
        end,
    },
    ["feature.recycle"] = {
        processAuto = function(request)
            assert(request.nowHours == 48 and request.operationId,
                "automatic recycle schedule changed")
            calls.autoRecycle = calls.autoRecycle + 1
            return { ok = true, code = "autoRecycleEmpty" }
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
    config = { progression = { killPointReward = 1 } },
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
    and handlers.OnPlayerDeath
    and handlers.EveryOneMinute and handlers.EveryHours
    and handlers.OnTick and handlers.OnSave,
    "coordinator did not register bounded lifecycle events")

handlers.OnCreatePlayer(0, actor)
assert(calls.initialized == 1, "player initialization not coordinated")
assert(calls.generated == 1 and calls.carryRefresh == 1
    and calls.terminalReconcile == 1,
    "create-player lifecycle reconciliation changed")
handlers.OnPlayerUpdate(actor)
actor.x, actor.y, actor.kills = 3, 4, 6
handlers.OnPlayerUpdate(actor)
assert(metrics.zombieKills == 4 and metrics.moveDistance == 0,
    "player update wrote persistent metrics every frame")
handlers.EveryOneMinute()
assert(metrics.zombieKills == 6 and metrics.moveDistance == 5,
    "minute flush did not write accumulated metrics")
assert(calls.killRewards == 1 and calls.taskFailures.waiting == "timeout",
    "minute reward or task timeout workflow changed")
assert(calls.autoRecycle == 1, "minute pass did not check automatic recycle")
assert(calls.claimed == 1 and calls.saves == 1,
    "minute pass did not auto-claim once and save once")

handlers.EveryHours()
assert(calls.generated == 2 and calls.claimed == 1,
    "hour pass did not generate without reclaiming completed task")
assert(#calls.bank == 3 and calls.bank[1] == "syncInvestmentHours"
    and calls.bank[2] == "updateLoan"
    and calls.bank[3] == "processAutoDeposit", "bank periodic actions changed")
assert(calls.bankHours[1] == 1,
    "investment progress did not use one online world hour")
assert(calls.cleared == 1 and calls.saves == 2,
    "hour pass did not clear safe zone and save once")

calls.deathReady = true
handlers.OnPlayerDeath(actor)
assert(calls.bank[4] == "deathPenalty"
    and calls.taskFailures["death-only"] == "death",
    "death settlement workflow changed")
assert(calls.saves == 3, "death settlement was not persisted")

handlers.OnTick()
assert(calls.storage == 1 and calls.saves == 3,
    "bounded storage tick unexpectedly saved every frame")

modules["feature.storage"].processJobs = function() error("storage probe failure") end
handlers.OnTick()
assert(#calls.failed == 1 and calls.failed[1].moduleId == "feature.storage",
    "runtime callback failure was not isolated to its module")
assert(#diagnostics.rows >= 1, "runtime callback failure was not diagnosed")

handlers.OnSave()
assert(calls.saves == 4, "save event did not persist once")
handlers.OnCreatePlayer(1, actorTwo)
assert(coordinator:health().data.actors == 2,
    "second online actor was not tracked")
assert(coordinator.actorDisconnected(actor),
    "disconnected actor was not removed")
local recycleBeforeDisconnectPass = calls.autoRecycle
handlers.EveryOneMinute()
assert(calls.autoRecycle == recycleBeforeDisconnectPass + 1,
    "offline actor still received periodic processing")
assert(coordinator:health().data.actors == 1,
    "disconnect removed wrong actor or retained stale actor")
assert(coordinator:stop(), "coordinator stop")
assert(calls.saves == 7, "disconnect, minute, or stop state was not saved")
assert(coordinator:health().code == "stopped", "coordinator health after stop")

print("Test-GodSystemV422012CoordinatorRuntime passed")
