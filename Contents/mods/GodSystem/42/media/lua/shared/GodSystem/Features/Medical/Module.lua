require "GodSystem/Core/Result"

GodSystemMedicalFeatureModule = GodSystemMedicalFeatureModule or {}

local Descriptor = GodSystemMedicalFeatureModule

Descriptor.id = "feature.medical"
Descriptor.dependencies = {
    "medical.config",
    "medical.state",
    "medical.body",
    "medical.wallet",
    "metrics",
    "clock",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local ACTIONS = {
    checkInfection = true,
    healInjuries = true,
    cureInfection = true,
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

local function safeCost(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    value = math.floor(value)
    if value < 0 or value > 9007199254740991 then return nil end
    return value
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    return value ~= "" and value or nil
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "medical.config", { "cost" })
    local state = requiredPort(dependencies, "medical.state", { "load", "save" })
    local body = requiredPort(dependencies, "medical.body", { "inspect", "snapshot", "apply", "restore" })
    local wallet = requiredPort(dependencies, "medical.wallet", { "charge", "refund" })
    local metrics = requiredPort(dependencies, "metrics", { "increment" })
    local clock = requiredPort(dependencies, "clock", { "nowHours" })
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

    local function begin(action, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = callPort(operations.begin, moduleId, id, "medical|" .. action, request)
        if not called then return nil, makeResult(false, "portError", { stage = "operationBegin" }, request) end
        if status == "replay" then return nil, value end
        if status ~= "new" then return nil, makeResult(false, value or "operationPending", nil, request) end
        return id
    end

    local function finish(id, result, request)
        local called, stored = callPort(operations.finish, moduleId, id, result, request)
        if not called or stored == false then
            instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
            return makeResult(false, "operationOutcomeUnknown", { original = result }, request)
        end
        return result
    end

    local function save(actor, data, request)
        local called, saved, code = callPort(state.save, actor, data, request)
        if not called then return false, "portError" end
        return saved == true, code or "stateSaveFailed"
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local action = tostring(request.action or "")
        if not ACTIONS[action] then return makeResult(false, "medicalActionInvalid", nil, request) end
        local id, replay = begin(action, request)
        if replay then return replay end
        local loadCalled, data, loadCode = callPort(state.load, request.actor, request)
        if not loadCalled or type(data) ~= "table" then
            return finish(id, makeResult(false,
                loadCalled and (loadCode or "stateUnavailable") or "portError", nil, request), request)
        end
        local inspectCalled, status, inspectCode = callPort(body.inspect, request.actor, request)
        if not inspectCalled or type(status) ~= "table" then
            return finish(id, makeResult(false,
                inspectCalled and (inspectCode or "medicalUnavailable") or "portError", nil, request), request)
        end
        if action == "cureInfection" and status.infected ~= true then
            return finish(id, makeResult(false, "infectionNotDetected", nil, request), request)
        end
        if action == "healInjuries" and status.injured ~= true then
            return finish(id, makeResult(false, "injuryNotDetected", nil, request), request)
        end
        local quoteCalled, rawCost = callPort(config.cost, action, request.actor, data, request)
        local cost = quoteCalled and safeCost(rawCost) or nil
        if cost == nil then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local snapshotCalled, bodySnapshot, snapshotCode = callPort(body.snapshot, request.actor, action, request)
        if not snapshotCalled or bodySnapshot == nil then
            return finish(id, makeResult(false,
                snapshotCalled and (snapshotCode or "medicalSnapshotFailed") or "portError", nil, request), request)
        end
        local paymentReceipt
        if cost > 0 then
            local chargeCalled, charged, receiptOrCode = callPort(wallet.charge, request.actor, cost, request)
            if not chargeCalled or charged ~= true or receiptOrCode == nil then
                return finish(id, makeResult(false,
                    chargeCalled and (receiptOrCode or "insufficientFunds") or "portError", nil, request), request)
            end
            paymentReceipt = receiptOrCode
        end
        local applyCalled, applied, outcomeOrCode = callPort(body.apply, request.actor, action, bodySnapshot, request)
        if not applyCalled or applied ~= true then
            local bodyCalled, bodyRestored = callPort(body.restore, request.actor, bodySnapshot, request)
            local walletRestored = true
            if paymentReceipt then
                local refundCalled, refunded = callPort(wallet.refund, request.actor, paymentReceipt, request)
                walletRestored = refundCalled and refunded ~= false
            end
            local rollbackOk = bodyCalled and bodyRestored ~= false and walletRestored
            return finish(id, makeResult(false,
                rollbackOk and (applyCalled and (outcomeOrCode or "medicalApplyFailed") or "portError")
                    or "rollbackIncomplete", nil, request), request)
        end
        local before = copy(data)
        local timeCalled, now = callPort(clock.nowHours, request)
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local bodyCalled, bodyRestored = callPort(body.restore, request.actor, bodySnapshot, request)
            local walletRestored = true
            if paymentReceipt then
                local refundCalled, refunded = callPort(wallet.refund, request.actor, paymentReceipt, request)
                walletRestored = refundCalled and refunded ~= false
            end
            local stateRestored = save(request.actor, before, request)
            local rollbackOk = bodyCalled and bodyRestored ~= false and walletRestored and stateRestored
            return finish(id, makeResult(false, rollbackOk and saveCode or "rollbackIncomplete", nil, request), request)
        end
        if cost > 0 then
            local metricCalled, counted, metricReceiptOrCode = callPort(
                metrics.increment, request.actor, { spentPoints = cost }, request)
            if not metricCalled or counted ~= true then
                local bodyCalled, bodyRestored = callPort(
                    body.restore, request.actor, bodySnapshot, request)
                local walletRestored = true
                if paymentReceipt then
                    local refundCalled, refunded = callPort(
                        wallet.refund, request.actor, paymentReceipt, request)
                    walletRestored = refundCalled and refunded ~= false
                end
                local stateRestored = save(request.actor, before, request)
                local rollbackOk = bodyCalled and bodyRestored ~= false
                    and walletRestored and stateRestored
                return finish(id, makeResult(false,
                    rollbackOk and (metricCalled
                        and (metricReceiptOrCode or "metricUpdateFailed")
                        or "portError") or "rollbackIncomplete", nil, request), request)
            end
        end
        return finish(id, makeResult(true, "medicalCompleted", {
            action = action,
            result = outcomeOrCode,
            cost = cost,
            completedAt = timeCalled and now or nil,
        }, request), request)
    end

    instance.public = {
        execute = execute,
        checkInfection = function(request)
            request = copy(type(request) == "table" and request or {})
            request.action = "checkInfection"
            return execute(request)
        end,
        healInjuries = function(request)
            request = copy(type(request) == "table" and request or {})
            request.action = "healInjuries"
            return execute(request)
        end,
        cureInfection = function(request)
            request = copy(type(request) == "table" and request or {})
            request.action = "cureInfection"
            return execute(request)
        end,
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
