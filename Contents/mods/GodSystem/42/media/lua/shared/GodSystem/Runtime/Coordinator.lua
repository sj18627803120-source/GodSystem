GodSystemRuntimeCoordinator = GodSystemRuntimeCoordinator or {}

local Coordinator = GodSystemRuntimeCoordinator

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function invoke(callback, ...)
    local args = { ... }
    local function run() return callback(unpack(args)) end
    if xpcall then return xpcall(run, traceback) end
    return pcall(run)
end

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

local function operationPart(value)
    value = tostring(value or ""):gsub("[^%w%._%-]", "_")
    return value ~= "" and value:sub(1, 80) or "actor"
end

function Coordinator.new(options)
    options = type(options) == "table" and options or {}
    local events = assert(options.events, "coordinator events missing")
    local registry = assert(options.registry, "coordinator registry missing")
    local diagnostics = options.diagnostics
    local save = assert(options.save, "coordinator save callback missing")
    local binding = type(options.binding) == "table" and options.binding or {}
    local config = type(options.config) == "table" and options.config or {}
    local progression = type(config.progression) == "table" and config.progression or {}
    local killPointReward = math.max(0,
        math.floor(tonumber(progression.killPointReward) or 0))
    local version = tostring(options.version or "")
    local instance = {
        started = false,
        actors = {},
        ticks = 0,
        failures = 0,
    }

    local function record(moduleId, stage, code, message)
        instance.failures = instance.failures + 1
        if diagnostics and type(diagnostics.record) == "function" then
            diagnostics:record({
                moduleId = moduleId,
                stage = stage,
                code = code,
                message = tostring(message or ""),
            })
        end
    end

    local function actorKey(actor)
        if type(binding.actorKey) == "function" then
            local ok, value = invoke(binding.actorKey, actor)
            if ok and tostring(value or "") ~= "" then return tostring(value) end
        end
        if type(actor) == "table" and actor.actorKey ~= nil then
            return tostring(actor.actorKey)
        end
        return tostring(actor)
    end

    local function public(moduleId)
        return registry:get(moduleId)
    end

    local function callModule(moduleId, method, request)
        local port = public(moduleId)
        if type(port) ~= "table" or type(port[method]) ~= "function" then
            return nil, "moduleUnavailable"
        end
        local ok, value = invoke(port[method], request)
        if not ok then
            registry:fail(moduleId, "runtimeCallbackFailed", {
                stage = method,
                message = tostring(value),
            })
            record(moduleId, method, "runtimeCallbackFailed", value)
            return nil, "runtimeCallbackFailed"
        end
        return value
    end

    local function callDirect(moduleId, method, ...)
        local port = public(moduleId)
        if type(port) ~= "table" or type(port[method]) ~= "function" then
            return nil, "moduleUnavailable"
        end
        local ok, value = invoke(port[method], ...)
        if not ok then
            registry:fail(moduleId, "runtimeCallbackFailed", {
                stage = method,
                message = tostring(value),
            })
            record(moduleId, method, "runtimeCallbackFailed", value)
            return nil, "runtimeCallbackFailed"
        end
        return value
    end

    local function operation(row, action, period)
        return table.concat({
            "runtime", operationPart(row.key), operationPart(action),
            operationPart(period),
        }, ":")
    end

    local function readPosition(actor)
        if type(binding.position) ~= "function" then return nil end
        local ok, x, y, z = invoke(binding.position, actor)
        if not ok or not finite(x) or not finite(y) or not finite(z) then return nil end
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end

    local function readKills(actor)
        if type(binding.zombieKills) ~= "function" then return nil end
        local ok, value = invoke(binding.zombieKills, actor)
        if not ok or not finite(value) then return nil end
        return math.max(0, math.floor(tonumber(value)))
    end

    local function track(actor)
        if actor == nil then return nil end
        local key = actorKey(actor)
        local row = instance.actors[key]
        if not row then
            row = {
                key = key,
                actor = actor,
                pendingKills = 0,
                pendingDistance = 0,
            }
            instance.actors[key] = row
        else
            row.actor = actor
        end
        return row
    end

    local function observe(actor)
        local row = track(actor)
        if not row then return false end
        local kills = readKills(actor)
        if kills ~= nil then
            if row.lastKills ~= nil and kills >= row.lastKills then
                row.pendingKills = row.pendingKills + (kills - row.lastKills)
            end
            row.lastKills = kills
        end
        local point = readPosition(actor)
        if point then
            if row.lastPoint and row.lastPoint.z == point.z then
                local dx, dy = point.x - row.lastPoint.x, point.y - row.lastPoint.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if finite(distance) and distance <= 50 then
                    row.pendingDistance = row.pendingDistance + distance
                end
            end
            row.lastPoint = point
        end
        return true
    end

    local function flush(row)
        local changes = {}
        local kills = math.floor(row.pendingKills)
        local distance = math.floor(row.pendingDistance)
        if kills > 0 then changes.zombieKills = kills end
        if distance > 0 then changes.moveDistance = distance end
        if next(changes) == nil then return true end
        local metrics = public("metrics")
        if not metrics or type(metrics.increment) ~= "function" then return false end
        if kills > 0 and killPointReward > 0 then
            local rewarded = callModule("feature.wallet", "requestGrant", {
                actor = row.actor,
                amount = kills * killPointReward,
                scope = "cash",
                reason = "KillReward",
                operationId = operation(row, "kill-reward",
                    tostring(row.lastKills or kills)),
            })
            if not rewarded or rewarded.ok ~= true then return false end
        end
        local ok, updated = invoke(metrics.increment, row.actor, changes)
        if not ok then
            registry:fail("metrics", "runtimeCallbackFailed", {
                stage = "increment",
                message = tostring(updated),
            })
            record("metrics", "increment", "runtimeCallbackFailed", updated)
            return false
        end
        if updated ~= true then return false end
        row.pendingKills = row.pendingKills - kills
        row.pendingDistance = row.pendingDistance - distance
        return true
    end

    local function hourPeriod()
        local clock = public("clock")
        if clock and type(clock.nowHours) == "function" then
            local ok, value = invoke(clock.nowHours)
            if ok and finite(value) then return tostring(math.floor(tonumber(value))) end
        end
        return tostring(instance.ticks)
    end

    local function exactHours()
        local clock = public("clock")
        if clock and type(clock.nowHours) == "function" then
            local ok, value = invoke(clock.nowHours)
            if ok and finite(value) then return tonumber(value) end
        end
        return tonumber(instance.ticks) or 0
    end

    local function dayPeriod()
        local clock = public("clock")
        if clock and type(clock.currentDay) == "function" then
            local ok, value = invoke(clock.currentDay)
            if ok and finite(value) then return tostring(math.floor(tonumber(value))) end
        end
        return hourPeriod()
    end

    local function initialize(row, lifecycle)
        local initialized = callModule("feature.system", "ensureInitialized", {
            actor = row.actor,
            operationId = operation(row, "initialize", version),
        })
        if not initialized or initialized.ok ~= true then return initialized end
        if lifecycle == true then
            row.lifecycle = (row.lifecycle or 0) + 1
            callModule("feature.upgrades", "refresh", {
                actor = row.actor,
                upgradeType = "carryCapacity",
                operationId = operation(row, "refresh-carry", row.lifecycle),
            })
            callModule("feature.terminal", "reconcile", {
                actor = row.actor,
                operationId = operation(row, "terminal-reconcile", row.lifecycle),
            })
            callModule("feature.tasks", "generate", {
                actor = row.actor,
                operationId = operation(row, "generate", dayPeriod()),
            })
        end
        return initialized
    end

    local function failTasks(row, reason, onlyExpired)
        local snapshot = callModule("feature.tasks", "snapshot", {
            actor = row.actor,
        })
        if not snapshot or snapshot.ok ~= true or type(snapshot.data) ~= "table" then
            return 0
        end
        local now = tonumber(hourPeriod()) or 0
        local failed = 0
        for index = 1, #(snapshot.data.tasks or {}) do
            local task = snapshot.data.tasks[index]
            local expired = tonumber(task.deadline) and now > tonumber(task.deadline)
            if task.status == "active"
                and (not onlyExpired or (expired and task.complete ~= true))
            then
                local value = callModule("feature.tasks", "fail", {
                    actor = row.actor,
                    taskId = task.taskId,
                    reason = reason,
                    operationId = operation(row,
                        reason .. "-" .. tostring(task.taskId), hourPeriod()),
                })
                if value and value.ok == true then failed = failed + 1 end
            end
        end
        return failed
    end

    local function death(actor)
        local row = track(actor)
        if not row then return false end
        row.deaths = (row.deaths or 0) + 1
        flush(row)
        callModule("feature.bank", "execute", {
            actor = row.actor,
            action = "deathPenalty",
            operationId = operation(row, "death-bank", row.deaths),
        })
        failTasks(row, "death", false)
        row.lastPoint = nil
        row.lastKills = readKills(row.actor)
        return save() == true
    end

    local function autoTasks(row, period)
        local snapshot = callModule("feature.tasks", "snapshot", {
            actor = row.actor,
        })
        if not snapshot or snapshot.ok ~= true or not snapshot.data
            or snapshot.data.autoClaimEnabled ~= true
        then
            return
        end
        for index = 1, #(snapshot.data.tasks or {}) do
            local task = snapshot.data.tasks[index]
            if task.status == "active" and task.complete == true then
                callModule("feature.tasks", "claim", {
                    actor = row.actor,
                    taskId = task.taskId,
                    operationId = operation(row, "claim-" .. tostring(task.taskId), period),
                })
            end
        end
    end

    local function hourly(actor)
        local row = track(actor)
        if not row then return false end
        flush(row)
        initialize(row, false)
        local hour = hourPeriod()
        callModule("feature.tasks", "generate", {
            actor = row.actor,
            operationId = operation(row, "generate", dayPeriod()),
        })
        autoTasks(row, hour)
        callModule("feature.bank", "execute", {
            actor = row.actor,
            action = "syncInvestmentHours",
            hours = 1,
            operationId = operation(row, "bank-investments", hour),
        })
        callModule("feature.bank", "execute", {
            actor = row.actor,
            action = "updateLoan",
            operationId = operation(row, "bank-loan", hour),
        })
        callModule("feature.bank", "execute", {
            actor = row.actor,
            action = "processAutoDeposit",
            operationId = operation(row, "bank-auto-deposit", hour),
        })
        callModule("feature.home", "clearSafeZone", {
            actor = row.actor,
            manual = false,
            operationId = operation(row, "safe-zone", hour),
        })
        return save() == true
    end

    local function minute()
        for _, row in pairs(instance.actors) do
            flush(row)
            failTasks(row, "timeout", true)
            autoTasks(row, hourPeriod())
            local now = exactHours()
            callModule("feature.recycle", "processAuto", {
                actor = row.actor,
                nowHours = now,
                operationId = operation(row, "auto-recycle",
                    tostring(math.floor(now * 60))),
            })
        end
        return save() == true
    end

    local function tick()
        instance.ticks = instance.ticks + 1
        callDirect("feature.storage", "processJobs")
    end

    local function saveAll()
        for _, row in pairs(instance.actors) do flush(row) end
        return save() == true
    end

    local function actorDisconnected(actor)
        if actor == nil then return false end
        local key = actorKey(actor)
        local row = instance.actors[key]
        if not row then return false end
        flush(row)
        instance.actors[key] = nil
        return save() == true
    end

    function instance:start()
        if self.started then return true end
        local subscriptions = {
            { "OnCreatePlayer", function(_, actor)
                local row = track(actor)
                if row then initialize(row, true) end
            end },
            { "OnPlayerUpdate", observe },
            { "OnPlayerDeath", death },
            { "EveryOneMinute", minute },
            { "EveryHours", function()
                for _, row in pairs(instance.actors) do hourly(row.actor) end
            end },
            { "OnTick", tick },
            { "OnSave", saveAll },
        }
        for index = 1, #subscriptions do
            local ok, code = events:subscribe(
                "runtime.coordinator", subscriptions[index][1], subscriptions[index][2], 0)
            if not ok then
                record("runtime.coordinator", "subscribe",
                    code or "eventUnavailable", subscriptions[index][1])
            end
        end
        self.started = true
        return true
    end

    function instance:stop()
        if not self.started then return true end
        saveAll()
        events:unsubscribeModule("runtime.coordinator")
        self.started = false
        return true
    end

    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.started
                and (self.failures == 0 and "healthy" or "degraded")
                or "stopped",
            data = {
                actors = (function()
                    local count = 0
                    for _ in pairs(self.actors) do count = count + 1 end
                    return count
                end)(),
                ticks = self.ticks,
                failures = self.failures,
            },
            moduleId = "runtime.coordinator",
        }
    end

    instance.observe = observe
    instance.actorCreated = function(actor)
        local row = track(actor)
        if not row then return false end
        initialize(row, true)
        return true
    end
    instance.actorDeath = death
    instance.actorDisconnected = actorDisconnected
    instance.minute = minute
    instance.hour = hourly
    instance.tick = tick
    instance.saveAll = saveAll
    return instance
end

return Coordinator
