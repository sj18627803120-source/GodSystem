require "GodSystem/Core/Result"

GodSystemUpgradesFeatureModule = GodSystemUpgradesFeatureModule or {}

local Descriptor = GodSystemUpgradesFeatureModule

Descriptor.id = "feature.upgrades"
Descriptor.dependencies = {
    "upgrades.config",
    "upgrades.state",
    "upgrades.abilities",
    "upgrades.tasks",
    "upgrades.wallet",
    "metrics",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local TYPES = {
    carryCapacity = { field = "carryCapacityLevel", nested = true, ability = true },
    activeTasks = { field = "maxActiveTasks", nested = true },
    dailyTasks = { field = "dailyTaskCount", nested = true, task = true },
    terminalCapacity = { field = "autoRecyclerCapacityLevel", ability = true },
    terminalReduction = { field = "autoRecyclerReductionLevel", ability = true },
    terminalRelief = { field = "autoRecyclerReliefLevel", ability = true },
}

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function callPort(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function requiredPort(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. id)
    for i = 1, #methods do
        assert(type(port[methods[i]]) == "function", "dependency " .. id .. " is missing method " .. methods[i])
    end
    return port
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeInteger(value)
    if not finite(value) then return nil end
    value = math.floor(tonumber(value))
    if math.abs(value) > 9007199254740991 then return nil end
    return value
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    return value ~= "" and value or nil
end

local function getLevel(data, definition)
    if definition.nested then
        data.upgrades = type(data.upgrades) == "table" and data.upgrades or {}
        return safeInteger(data.upgrades[definition.field]) or 0
    end
    return safeInteger(data[definition.field]) or 1
end

local function setLevel(data, definition, value)
    if definition.nested then
        data.upgrades = type(data.upgrades) == "table" and data.upgrades or {}
        data.upgrades[definition.field] = value
    else
        data[definition.field] = value
    end
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "upgrades.config", { "quote" })
    local state = requiredPort(dependencies, "upgrades.state", { "load", "save" })
    local abilities = requiredPort(dependencies, "upgrades.abilities", { "snapshot", "apply", "restore" })
    local tasks = requiredPort(dependencies, "upgrades.tasks", { "addOpen", "rollback" })
    local wallet = requiredPort(dependencies, "upgrades.wallet", { "charge", "refund" })
    local metrics = requiredPort(dependencies, "metrics", { "snapshot", "get", "increment", "restore" })
    local operations = requiredPort(dependencies, "operations", { "begin", "finish" })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })
    local instance = { started = false, completed = 0, failed = 0, lastIssue = nil }

    local function makeResult(ok, code, data, request)
        local result
        if ok then
            instance.completed = instance.completed + 1
            result = GodSystemResult.ok(moduleId, code, data, operationId(request))
        else
            instance.failed = instance.failed + 1
            result = GodSystemResult.fail(moduleId, code, data, operationId(request))
        end
        local called, value = callPort(notifications.publish, result, request)
        if not called or value == false then instance.lastIssue = { stage = "notify", code = "notificationFailed" } end
        return result
    end

    local function begin(action, upgradeType, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = callPort(
            operations.begin, moduleId, id, action .. "|" .. tostring(upgradeType or ""), request)
        if not called then return nil, makeResult(false, "portError", { stage = "operationBegin" }, request) end
        if status == "replay" then return nil, value end
        if status ~= "new" then return nil, makeResult(false, value or "operationPending", nil, request) end
        return id, nil
    end

    local function finish(id, result, request)
        local called, stored = callPort(operations.finish, moduleId, id, result, request)
        if not called or stored == false then
            instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
            return makeResult(false, "operationOutcomeUnknown", { original = result }, request)
        end
        return result
    end

    local function load(actor, request)
        local called, data, code = callPort(state.load, actor, request)
        if not called then return nil, makeResult(false, "portError", { stage = "stateLoad" }, request) end
        if type(data) ~= "table" then return nil, makeResult(false, code or "stateUnavailable", nil, request) end
        data.upgrades = type(data.upgrades) == "table" and data.upgrades or {}
        return data
    end

    local function incrementMetric(actor, changes, request)
        local called, updated, receiptOrCode = callPort(metrics.increment, actor, changes, request)
        if not called then return false, "portError" end
        if updated ~= true or type(receiptOrCode) ~= "table" then
            return false, receiptOrCode or "metricUpdateFailed"
        end
        return true, receiptOrCode
    end

    local function save(actor, data, request)
        local called, saved, code = callPort(state.save, actor, data, request)
        if not called then return false, "portError" end
        return saved == true, code or "stateSaveFailed"
    end

    local function restoreAbility(actor, upgradeType, snapshot, request)
        if snapshot == nil then return true end
        local called, restored = callPort(abilities.restore, actor, upgradeType, snapshot, request)
        return called and restored ~= false
    end

    local function upgrade(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local upgradeType = tostring(request.upgradeType or "")
        local definition = TYPES[upgradeType]
        if not definition then return makeResult(false, "upgradeTypeInvalid", nil, request) end
        local id, replay = begin("upgrade", upgradeType, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local current = getLevel(data, definition)
        local quoteCalled, quote, quoteCode = callPort(config.quote, request.actor, upgradeType, current, data, request)
        if not quoteCalled or type(quote) ~= "table" then
            return finish(id, makeResult(false, quoteCalled and (quoteCode or "upgradeMaxed") or "portError", nil, request), request)
        end
        local nextValue = safeInteger(quote.nextValue)
        local cost = safeInteger(quote.cost)
        if nextValue == nil or nextValue <= current then
            return finish(id, makeResult(false, "quoteInvalid", { field = "nextValue" }, request), request)
        end
        if cost == nil or cost < 0 then
            local code = quote.cost == nil and "upgradeMaxed" or "quoteInvalid"
            return finish(id, makeResult(false, code, { field = "cost" }, request), request)
        end
        local before = copy(data)
        local abilitySnapshot, abilityReport
        if definition.ability then
            local snapshotCalled, snapshot, snapshotCode = callPort(
                abilities.snapshot, request.actor, upgradeType, current, data, request)
            if not snapshotCalled or snapshot == nil then
                return finish(id, makeResult(false,
                    snapshotCalled and (snapshotCode or "abilitySnapshotFailed") or "portError", nil, request), request)
            end
            abilitySnapshot = snapshot
            local applyCalled, applied, reportOrCode = callPort(
                abilities.apply, request.actor, upgradeType, nextValue, data, request)
            if not applyCalled or applied ~= true then
                restoreAbility(request.actor, upgradeType, abilitySnapshot, request)
                return finish(id, makeResult(false,
                    applyCalled and (reportOrCode or "abilityApplyFailed") or "portError", nil, request), request)
            end
            abilityReport = reportOrCode
        end
        local paymentReceipt
        if cost > 0 then
            local chargeCalled, charged, receiptOrCode = callPort(wallet.charge, request.actor, cost, request)
            if not chargeCalled or charged ~= true or receiptOrCode == nil then
                local restored = restoreAbility(request.actor, upgradeType, abilitySnapshot, request)
                return finish(id, makeResult(false,
                    restored and (chargeCalled and (receiptOrCode or "insufficientFunds") or "portError")
                        or "rollbackIncomplete", nil, request), request)
            end
            paymentReceipt = receiptOrCode
        end
        setLevel(data, definition, nextValue)
        local taskReceipt
        if definition.task then
            local taskCalled, added, receiptOrCode = callPort(tasks.addOpen, request.actor, data, request)
            if not taskCalled or added ~= true or receiptOrCode == nil then
                local taskRestored = true
                local walletRestored = true
                if paymentReceipt then
                    local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                    walletRestored = refundCalled and value ~= false
                end
                local abilityRestored = restoreAbility(request.actor, upgradeType, abilitySnapshot, request)
                local stateRestored = save(request.actor, before, request)
                return finish(id, makeResult(false,
                    taskRestored and walletRestored and abilityRestored and stateRestored and
                        (taskCalled and (receiptOrCode or "taskAddFailed") or "portError") or "rollbackIncomplete",
                    nil, request), request)
            end
            taskReceipt = receiptOrCode
        end
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local taskRestored = true
            if taskReceipt then
                local taskCalled, value = callPort(tasks.rollback, request.actor, taskReceipt, request)
                taskRestored = taskCalled and value ~= false
            end
            local walletRestored = true
            if paymentReceipt then
                local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                walletRestored = refundCalled and value ~= false
            end
            local abilityRestored = restoreAbility(request.actor, upgradeType, abilitySnapshot, request)
            local stateRestored = save(request.actor, before, request)
            local rollbackOk = taskRestored and walletRestored and abilityRestored and stateRestored
            return finish(id, makeResult(false, rollbackOk and saveCode or "rollbackIncomplete", nil, request), request)
        end
        if cost > 0 then
            local counted, countCode = incrementMetric(
                request.actor, { spentPoints = cost }, request)
            if not counted then
                local taskRestored = true
                if taskReceipt then
                    local taskCalled, value = callPort(
                        tasks.rollback, request.actor, taskReceipt, request)
                    taskRestored = taskCalled and value ~= false
                end
                local walletRestored = true
                if paymentReceipt then
                    local refundCalled, value = callPort(
                        wallet.refund, request.actor, paymentReceipt, request)
                    walletRestored = refundCalled and value ~= false
                end
                local abilityRestored = restoreAbility(
                    request.actor, upgradeType, abilitySnapshot, request)
                local stateRestored = save(request.actor, before, request)
                local rollbackOk = taskRestored and walletRestored
                    and abilityRestored and stateRestored
                return finish(id, makeResult(false,
                    rollbackOk and countCode or "rollbackIncomplete", nil, request), request)
            end
        end
        return finish(id, makeResult(true, "upgraded", {
            upgradeType = upgradeType,
            previous = current,
            level = nextValue,
            cost = cost,
            report = abilityReport,
        }, request), request)
    end

    local function refresh(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local upgradeType = tostring(request.upgradeType or "carryCapacity")
        local definition = TYPES[upgradeType]
        if not definition or not definition.ability then return makeResult(false, "refreshUnsupported", nil, request) end
        local id, replay = begin("refresh", upgradeType, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local current = getLevel(data, definition)
        local snapshotCalled, snapshot, snapshotCode = callPort(
            abilities.snapshot, request.actor, upgradeType, current, data, request)
        if not snapshotCalled or snapshot == nil then
            return finish(id, makeResult(false,
                snapshotCalled and (snapshotCode or "abilitySnapshotFailed") or "portError", nil, request), request)
        end
        local applyCalled, applied, reportOrCode = callPort(
            abilities.apply, request.actor, upgradeType, current, data, request)
        if not applyCalled or applied ~= true then
            local restored = restoreAbility(request.actor, upgradeType, snapshot, request)
            return finish(id, makeResult(false,
                restored and (applyCalled and (reportOrCode or "refreshFailed") or "portError")
                    or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "refreshed", {
            upgradeType = upgradeType,
            level = current,
            report = reportOrCode,
        }, request), request)
    end

    local function summary(actor, request)
        if not instance.started then return GodSystemResult.fail(moduleId, "moduleStopped") end
        local data, failure = load(actor, type(request) == "table" and request or {})
        if not data then return failure end
        local upgrades = type(data.upgrades) == "table" and data.upgrades or {}
        return GodSystemResult.ok(moduleId, "summary", {
            carryCapacityLevel = math.max(0, integer(upgrades.carryCapacityLevel, 0)),
            maxActiveTasks = math.max(0, integer(upgrades.maxActiveTasks, 3)),
            dailyTaskCount = math.max(0, integer(upgrades.dailyTaskCount, 5)),
            terminalCapacityLevel = math.max(1, integer(data.autoRecyclerCapacityLevel, 1)),
            terminalReductionLevel = math.max(1, integer(data.autoRecyclerReductionLevel, 1)),
            terminalReliefLevel = math.max(1, integer(data.autoRecyclerReliefLevel, 1)),
        })
    end

    instance.public = {
        upgrade = upgrade,
        refresh = refresh,
        summary = summary,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        local data = { started = self.started, completed = self.completed, failed = self.failed, lastIssue = self.lastIssue }
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end
    return instance
end

return Descriptor
