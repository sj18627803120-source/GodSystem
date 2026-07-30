require "GodSystem/Core/Result"
require "GodSystem/Features/Terminal/Rules"

GodSystemTerminalFeatureModule = GodSystemTerminalFeatureModule or {}

local Descriptor = GodSystemTerminalFeatureModule
local Rules = GodSystemTerminalFeatureRules

Descriptor.id = "feature.terminal"
Descriptor.dependencies = {
    "terminal.config",
    "terminal.state",
    "terminal.instances",
    "wallet",
    "operations",
    "terminal.audit",
}
Descriptor.stateVersion = Rules.stateVersion

local MUTATIONS = {
    claim = true,
    recover = true,
    reconcile = true,
    upgradeCapacity = true,
    upgradeReduction = true,
    upgradeRelief = true,
}

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function call(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function method(port, name, ...)
    local callback = port and port[name]
    if type(callback) ~= "function" then return false, "missing method " .. tostring(name) end
    return call(callback, ...)
end

local function requiredPort(dependencies, dependencyId, methods)
    local port = dependencies[dependencyId]
    assert(type(port) == "table", "missing dependency: " .. dependencyId)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. dependencyId .. " is missing method " .. methods[index])
    end
    return port
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function childRequest(request, suffix)
    local result = {}
    for key, value in pairs(type(request) == "table" and request or {}) do result[key] = value end
    local parentId = operationId(request)
    result.operationId = parentId and (parentId .. ":" .. tostring(suffix)) or nil
    return result
end

local function fingerprint(request)
    return table.concat({
        tostring(request.action or ""),
        tostring(request.upgradeType or ""),
        tostring(request.expectedItemId or ""),
        tostring(request.forceRecovery == true),
    }, "|")
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "terminal.config",
        { "snapshot", "health" })
    local state = requiredPort(dependencies, "terminal.state",
        { "load", "commit", "health" })
    local instances = requiredPort(dependencies, "terminal.instances", {
        "findOwned", "create", "remove", "snapshot", "apply", "restore",
        "cleanupEscapedRelief", "inspect", "health",
    })
    local wallet = requiredPort(dependencies, "wallet",
        { "getBalance", "charge", "refund" })
    local operations = requiredPort(dependencies, "operations",
        { "begin", "finish", "markUnknown" })
    local audit = requiredPort(dependencies, "terminal.audit",
        { "record", "health" })
    local configCalled, featureConfig = method(config, "snapshot")
    assert(configCalled and type(featureConfig) == "table",
        "terminal.config snapshot failed")

    local instance = {
        started = false,
        completed = 0,
        failed = 0,
        lastIssue = nil,
    }

    local function result(ok, code, data, request)
        if ok then instance.completed = instance.completed + 1
        else instance.failed = instance.failed + 1 end
        if ok then return GodSystemResult.ok(moduleId, code, data, operationId(request)) end
        return GodSystemResult.fail(moduleId, code, data, operationId(request))
    end

    local function portFailure(stage, message, request)
        instance.lastIssue = {
            stage = stage,
            code = "portError",
            message = tostring(message),
        }
        return result(false, "portError", {
            stage = stage,
            message = tostring(message),
        }, request)
    end

    local function begin(request)
        local id = operationId(request)
        if not id then return nil, result(false, "operationIdRequired", nil, request) end
        local called, status, ledgerResult = call(operations.begin,
            moduleId, id, fingerprint(request), request)
        if not called then return nil, portFailure("operationBegin", status, request) end
        if status == "replay" then return nil, ledgerResult end
        if status ~= "new" then
            local code = type(ledgerResult) == "table"
                and ledgerResult.code or "operationInvalid"
            return nil, result(false, code,
                type(ledgerResult) == "table" and ledgerResult.data or nil, request)
        end
        return ledgerResult
    end

    local function finish(request, value)
        local id = operationId(request)
        local called, finished = call(operations.finish,
            moduleId, id, value, request)
        if called and type(finished) == "table" then return finished end
        call(operations.markUnknown, moduleId, id,
            "operationOutcomeUnknown", request)
        instance.lastIssue = {
            stage = "operationFinish",
            code = "operationOutcomeUnknown",
            message = tostring(finished),
        }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = value and value.ok == true,
        }, id)
    end

    local function loadState(actor, request)
        local called, value, revision = method(state, "load", actor)
        if not called then return nil, nil, portFailure("stateLoad", value, request) end
        if value == nil then value = {} end
        if type(value) ~= "table" then
            return nil, nil, result(false, "stateInvalid", nil, request)
        end
        return Rules.normalizeState(value), revision
    end

    local function commitState(actor, value, revision, request)
        local called, ok, code, nextRevision = method(state, "commit",
            actor, Rules.normalizeState(value), revision, request)
        if not called then return false, portFailure("stateCommit", ok, request) end
        if ok ~= true then return false, result(false, code or "stateCommitFailed", nil, request) end
        return true, nextRevision
    end

    local function ownedTerminal(actor, request)
        local called, item, code = method(instances, "findOwned",
            actor, request.expectedItemId)
        if not called then return nil, portFailure("findOwned", item, request) end
        if not item then return nil, result(false, code or "terminalMissing", nil, request) end
        return item
    end

    local function applySpec(actor, item, terminalState, request)
        local snapshotCalled, snapshot = method(instances, "snapshot", actor, item)
        if not snapshotCalled then return false, nil, portFailure("instanceSnapshot", snapshot, request) end
        if snapshot == nil then
            return false, nil, result(false, "instanceSnapshotFailed", nil, request)
        end
        local applyCalled, applied, code, report = method(instances, "apply",
            actor, item, Rules.spec(terminalState), request)
        if not applyCalled then
            method(instances, "restore", actor, item, snapshot, request)
            return false, nil, portFailure("instanceApply", applied, request)
        end
        if applied ~= true then
            local restoredCalled, restored = method(instances, "restore",
                actor, item, snapshot, request)
            if not restoredCalled or restored ~= true then
                return false, nil, result(false, "rollbackIncomplete", {
                    cause = code or "terminalApplyFailed",
                    instance = false,
                }, request)
            end
            return false, nil, result(false, code or "terminalApplyFailed", report, request)
        end
        return true, snapshot, nil, report
    end

    local function rollbackApply(actor, item, snapshot, request)
        local called, restored = method(instances, "restore",
            actor, item, snapshot, request)
        return called and restored == true
    end

    local function walletCharge(actor, amount, request)
        local called, balance = method(wallet, "getBalance", actor, "spendable")
        if not called then return nil, portFailure("walletBalance", balance, request) end
        balance = tonumber(balance)
        if not balance or balance < amount then
            return nil, result(false, "balanceInsufficient", {
                available = math.max(0, math.floor(balance or 0)),
                required = amount,
            }, request)
        end
        local paidCalled, paid, receipt, data = method(wallet, "charge",
            actor, amount, childRequest(request, "charge"))
        if not paidCalled then return nil, portFailure("walletCharge", paid, request) end
        if paid ~= true then
            return nil, result(false, receipt or "chargeFailed", data, request)
        end
        return receipt
    end

    local function walletRefund(actor, receipt, request)
        if not receipt then return true end
        local called, refunded = method(wallet, "refund",
            actor, receipt, childRequest(request, "refund"))
        return called and refunded == true
    end

    local function auditRecord(actor, action, data, request)
        local called, value = method(audit, "record",
            actor, action, data, request)
        if not called then
            instance.lastIssue = {
                stage = "audit",
                code = "auditFailed",
                message = tostring(value),
            }
        end
    end

    local function status(actor, request)
        if featureConfig.enabled == false then
            return result(false, "TerminalDisabled", nil, request)
        end
        local terminalState, revision, loadError = loadState(actor, request)
        if not terminalState then return loadError end
        local called, item, findCode = method(instances, "findOwned", actor,
            request and request.expectedItemId)
        if not called then return portFailure("findOwned", item, request) end
        local applied
        if item then
            local inspected, value = method(instances, "inspect",
                actor, item, Rules.spec(terminalState))
            if not inspected then return portFailure("instanceInspect", value, request) end
            applied = value
        end
        return result(true, "TerminalStatus", {
            state = terminalState,
            revision = revision,
            owned = item ~= nil,
            item = item,
            findCode = findCode,
            applied = applied,
            recoveryCost = terminalState.claimedOnce and Rules.recoveryCost(terminalState) or 0,
            capacity = Rules.upgradeInfo(terminalState, "capacity"),
            reduction = Rules.upgradeInfo(terminalState, "reduction"),
            relief = Rules.upgradeInfo(terminalState, "relief"),
        }, request)
    end

    local function requestStatus(request)
        request = type(request) == "table" and request or {}
        return status(request.actor, request)
    end

    local function claim(actor, request)
        local terminalState, revision, loadError = loadState(actor, request)
        if not terminalState then return loadError end
        local foundCalled, existing = method(instances, "findOwned", actor,
            request.expectedItemId)
        if not foundCalled then return portFailure("findOwned", existing, request) end
        if existing then
            return result(true, "TerminalOwned", {
                item = existing,
                recovered = false,
                cost = 0,
            }, request)
        end
        local recovery = terminalState.claimedOnce == true
        local cost = recovery and Rules.recoveryCost(terminalState) or 0
        local receipt, paymentError
        if cost > 0 then
            receipt, paymentError = walletCharge(actor, cost, request)
            if not receipt then return paymentError end
        end
        local createCalled, item, createCode = method(instances, "create",
            actor, Rules.terminalFullType, request)
        if not createCalled then
            if not walletRefund(actor, receipt, request) then
                return result(false, "rollbackIncomplete", {
                    cause = "instanceCreatePortError",
                    wallet = false,
                }, request)
            end
            return portFailure("instanceCreate", item, request)
        end
        if not item then
            if not walletRefund(actor, receipt, request) then
                return result(false, "rollbackIncomplete", {
                    cause = createCode or "terminalCreateFailed",
                    wallet = false,
                }, request)
            end
            return result(false, createCode or "terminalCreateFailed", nil, request)
        end
        local applied, snapshot, applyError, report = applySpec(
            actor, item, terminalState, request)
        if not applied then
            local removedCalled, removed = method(instances, "remove",
                actor, item, request)
            local refunded = walletRefund(actor, receipt, request)
            if not removedCalled or removed ~= true or not refunded then
                return result(false, "rollbackIncomplete", {
                    cause = applyError,
                    instance = removedCalled and removed == true,
                    wallet = refunded,
                }, request)
            end
            return applyError
        end
        terminalState.claimedOnce = true
        local committed, commitValue = commitState(actor,
            terminalState, revision, request)
        if not committed then
            rollbackApply(actor, item, snapshot, request)
            local removedCalled, removed = method(instances, "remove",
                actor, item, request)
            local refunded = walletRefund(actor, receipt, request)
            if not removedCalled or removed ~= true or not refunded then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    instance = removedCalled and removed == true,
                    wallet = refunded,
                }, request)
            end
            return commitValue
        end
        method(instances, "cleanupEscapedRelief", actor, item)
        auditRecord(actor, recovery and "TerminalRecovered" or "TerminalClaimed", {
            cost = cost,
            recovery = recovery,
        }, request)
        return result(true, recovery and "TerminalRecovered" or "TerminalClaimed", {
            item = item,
            cost = cost,
            recovered = recovery,
            state = terminalState,
            applied = report,
        }, request)
    end

    local function upgrade(actor, kind, request)
        local terminalState, revision, loadError = loadState(actor, request)
        if not terminalState then return loadError end
        local nextState, advanceCode, quote = Rules.advance(terminalState, kind)
        if not nextState then return result(false, advanceCode, nil, request) end
        local item, terminalError = ownedTerminal(actor, request)
        if not item then return terminalError end
        local applied, snapshot, applyError, report = applySpec(
            actor, item, nextState, request)
        if not applied then return applyError end
        local receipt, paymentError = walletCharge(actor, quote.nextCost, request)
        if not receipt then
            if not rollbackApply(actor, item, snapshot, request) then
                return result(false, "rollbackIncomplete", {
                    cause = paymentError,
                    instance = false,
                }, request)
            end
            return paymentError
        end
        local committed, commitValue = commitState(actor,
            nextState, revision, request)
        if not committed then
            local restored = rollbackApply(actor, item, snapshot, request)
            local refunded = walletRefund(actor, receipt, request)
            if not restored or not refunded then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    instance = restored,
                    wallet = refunded,
                }, request)
            end
            return commitValue
        end
        auditRecord(actor, "TerminalUpgrade", {
            kind = kind,
            level = Rules.level(nextState, kind),
            value = Rules.value(nextState, kind),
            cost = quote.nextCost,
        }, request)
        return result(true, "TerminalUpgraded", {
            kind = kind,
            level = Rules.level(nextState, kind),
            value = Rules.value(nextState, kind),
            cost = quote.nextCost,
            state = nextState,
            applied = report,
        }, request)
    end

    local function reconcile(actor, request)
        local terminalState, _, loadError = loadState(actor, request)
        if not terminalState then return loadError end
        local item, terminalError = ownedTerminal(actor, request)
        if not item then return terminalError end
        local applied, _, applyError, report = applySpec(
            actor, item, terminalState, request)
        if not applied then return applyError end
        local cleanupCalled, removed = method(instances,
            "cleanupEscapedRelief", actor, item)
        if not cleanupCalled then return portFailure("cleanupRelief", removed, request) end
        return result(true, "TerminalReconciled", {
            removedEscapedRelief = tonumber(removed) or 0,
            applied = report,
        }, request)
    end

    local function executeAction(request)
        if request.action == "claim" or request.action == "recover" then
            return claim(request.actor, request)
        end
        if request.action == "reconcile" then return reconcile(request.actor, request) end
        if request.action == "upgradeCapacity" then
            return upgrade(request.actor, "capacity", request)
        end
        if request.action == "upgradeReduction" then
            return upgrade(request.actor, "reduction", request)
        end
        if request.action == "upgradeRelief" then
            return upgrade(request.actor, "relief", request)
        end
        return result(false, "actionInvalid", { action = request.action }, request)
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        request.action = tostring(request.action or "")
        if not instance.started then return result(false, "moduleStopped", nil, request) end
        if request.actor == nil then return result(false, "actorRequired", nil, request) end
        if featureConfig.enabled == false then
            return result(false, "TerminalDisabled", nil, request)
        end
        if not MUTATIONS[request.action] then
            return result(false, "actionInvalid", { action = request.action }, request)
        end
        local row, replay = begin(request)
        if not row then return replay end
        local called, value = call(executeAction, request)
        if not called then
            call(operations.markUnknown, moduleId,
                operationId(request), "portError", request)
            return portFailure("execute", value, request)
        end
        return finish(request, value)
    end

    instance.public = {
        execute = execute,
        status = status,
        requestStatus = requestStatus,
        claim = function(request)
            request = type(request) == "table" and request or {}
            request.action = "claim"
            return execute(request)
        end,
        recover = function(request)
            request = type(request) == "table" and request or {}
            request.action = "recover"
            return execute(request)
        end,
        reconcile = function(request)
            request = type(request) == "table" and request or {}
            request.action = "reconcile"
            return execute(request)
        end,
        upgrade = function(request)
            request = type(request) == "table" and request or {}
            local kind = Rules.kind(request.upgradeType)
            request.action = kind == "capacity" and "upgradeCapacity"
                or kind == "reduction" and "upgradeReduction"
                or kind == "relief" and "upgradeRelief"
                or ""
            return execute(request)
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        local checks = {}
        local healthy = true
        for _, row in ipairs({
            { id = "config", port = config },
            { id = "state", port = state },
            { id = "instances", port = instances },
            { id = "audit", port = audit },
        }) do
            local called, ok, data = method(row.port, "health")
            checks[row.id] = {
                ok = called and ok ~= false,
                data = called and data or tostring(ok),
            }
            if not checks[row.id].ok then healthy = false end
        end
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
            checks = checks,
        }
        if self.lastIssue or not healthy then
            return GodSystemResult.fail(moduleId,
                self.lastIssue and self.lastIssue.code or "dependencyUnhealthy", data)
        end
        return GodSystemResult.ok(moduleId,
            self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
