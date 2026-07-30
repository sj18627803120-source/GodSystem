require "GodSystem/Core/Result"

GodSystemWalletFeatureModule = GodSystemWalletFeatureModule or {}

local Descriptor = GodSystemWalletFeatureModule

Descriptor.id = "feature.wallet"
Descriptor.dependencies = {
    "wallet.funds",
    "operations",
}
Descriptor.stateVersion = 1

local MUTATIONS = {
    grant = true,
    charge = true,
    refund = true,
    transfer = true,
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
    return call(callback, port, ...)
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

local function positiveAmount(value)
    value = tonumber(value)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
        or value <= 0
    then
        return nil
    end
    value = math.floor(value)
    if value <= 0 then return nil end
    return value
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function scope(value, fallback)
    value = tostring(value or fallback or "")
    if value == "" then return tostring(fallback or "spendable") end
    return value
end

local function receiptId(receipt)
    if type(receipt) ~= "table" then return tostring(receipt or "") end
    return tostring(receipt.id or receipt.operationId or receipt.kind or "")
end

local function fingerprint(action, amount, fromScope, toScope, receipt)
    return table.concat({
        tostring(action or ""),
        tostring(amount or 0),
        tostring(fromScope or ""),
        tostring(toScope or ""),
        receiptId(receipt),
    }, "|")
end

local function withRequest(request, suffix, extra)
    local copy = {}
    for key, value in pairs(type(request) == "table" and request or {}) do copy[key] = value end
    local parentId = operationId(request)
    copy.operationId = parentId and (parentId .. ":" .. tostring(suffix)) or nil
    for key, value in pairs(type(extra) == "table" and extra or {}) do copy[key] = value end
    return copy
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local funds = requiredPort(dependencies, "wallet.funds",
        { "balance", "debit", "credit", "restore" })
    local operations = requiredPort(dependencies, "operations",
        { "begin", "finish", "markUnknown" })

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

    local function begin(action, amount, fromScope, toScope, receipt, request)
        local id = operationId(request)
        if not id then return nil, result(false, "operationIdRequired", nil, request) end
        local called, row, ledgerResult = method(operations, "begin", id,
            fingerprint(action, amount, fromScope, toScope, receipt))
        if not called then return nil, portFailure("operationBegin", row, request) end
        if not row then
            local code = type(ledgerResult) == "table" and ledgerResult.code or "operationInvalid"
            return nil, result(false, code, type(ledgerResult) == "table" and ledgerResult.data or nil, request)
        end
        if ledgerResult then
            if row.status == "done" and type(row.result) == "table" then
                return nil, row.result
            end
            if row.status == "unknown" then
                return nil, result(false, "operationOutcomeUnknown", nil, request)
            end
            return nil, result(false, "operationPending", nil, request)
        end
        return row
    end

    local function finish(request, value)
        local id = operationId(request)
        local called, finished = method(operations, "finish", id, value)
        if called and type(finished) == "table" then return finished end
        method(operations, "markUnknown", id, "operationOutcomeUnknown")
        instance.lastIssue = {
            stage = "operationFinish",
            code = "operationOutcomeUnknown",
            message = tostring(finished),
        }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = value and value.ok == true,
        }, id)
    end

    local function mutate(action, actor, amount, fromScope, toScope, receipt, request, callback)
        if not instance.started then
            return result(false, "moduleStopped", nil, request)
        end
        if actor == nil then return result(false, "actorRequired", nil, request) end
        local row, replay = begin(action, amount, fromScope, toScope, receipt, request)
        if not row then return replay end
        local called, value = call(callback)
        if not called then
            method(operations, "markUnknown", operationId(request), "portError")
            return portFailure(action, value, request)
        end
        return finish(request, value)
    end

    local function balance(actor, requestedScope)
        if actor == nil then return 0, "actorRequired" end
        local called, value = method(funds, "balance", actor, scope(requestedScope, "spendable"))
        if not called then
            instance.lastIssue = { stage = "balance", code = "portError", message = tostring(value) }
            return 0, "portError"
        end
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
            instance.lastIssue = { stage = "balance", code = "balanceInvalid", message = tostring(value) }
            return 0, "balanceInvalid"
        end
        return math.floor(value)
    end

    local function grant(actor, amount, request)
        amount = positiveAmount(amount)
        if not amount then
            local value = result(false, "amountInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local targetScope = scope(request and request.scope, "cash")
        local value = mutate("grant", actor, amount, "", targetScope, nil, request, function()
            local called, ok, portReceipt, data = method(funds, "credit",
                actor, amount, targetScope, request)
            if not called then return portFailure("credit", ok, request) end
            if ok ~= true then return result(false, portReceipt or "grantFailed", data, request) end
            if portReceipt == nil then
                return result(false, "receiptMissing", { stage = "credit" }, request)
            end
            return result(true, "granted", {
                receipt = {
                    kind = "grant",
                    amount = amount,
                    scope = targetScope,
                    sourceReceipt = portReceipt,
                },
                amount = amount,
                scope = targetScope,
            }, request)
        end)
        local receipt = value.ok and value.data and value.data.receipt or value.code
        return value.ok, receipt, value.data, value
    end

    local function charge(actor, amount, request)
        amount = positiveAmount(amount)
        if not amount then
            local value = result(false, "amountInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local sourceScope = scope(request and request.scope, "spendable")
        local value = mutate("charge", actor, amount, sourceScope, "", nil, request, function()
            local available, balanceCode = balance(actor, sourceScope)
            if balanceCode then return result(false, balanceCode, nil, request) end
            if available < amount then
                return result(false, "balanceInsufficient", {
                    available = available,
                    required = amount,
                }, request)
            end
            local called, ok, portReceipt, data = method(funds, "debit",
                actor, amount, sourceScope, request)
            if not called then return portFailure("debit", ok, request) end
            if ok ~= true then return result(false, portReceipt or "chargeFailed", data, request) end
            if portReceipt == nil then
                return result(false, "receiptMissing", { stage = "debit" }, request)
            end
            return result(true, "charged", {
                receipt = {
                    kind = "charge",
                    amount = amount,
                    scope = sourceScope,
                    sourceReceipt = portReceipt,
                },
                amount = amount,
                scope = sourceScope,
            }, request)
        end)
        local receipt = value.ok and value.data and value.data.receipt or value.code
        return value.ok, receipt, value.data, value
    end

    local function refund(actor, paymentReceipt, request)
        if type(paymentReceipt) ~= "table"
            or paymentReceipt.kind ~= "charge"
            or paymentReceipt.sourceReceipt == nil
        then
            local value = result(false, "receiptInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local amount = positiveAmount(paymentReceipt.amount)
        if not amount then
            local value = result(false, "receiptInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local sourceScope = scope(paymentReceipt.scope, "spendable")
        local value = mutate("refund", actor, amount, sourceScope, "", paymentReceipt, request, function()
            local called, ok, code, data = method(funds, "restore",
                actor, paymentReceipt.sourceReceipt, request)
            if not called then return portFailure("restore", ok, request) end
            if ok ~= true then return result(false, code or "refundFailed", data, request) end
            return result(true, "refunded", {
                amount = amount,
                scope = sourceScope,
                receiptId = receiptId(paymentReceipt.sourceReceipt),
            }, request)
        end)
        return value.ok, value.ok and value.data or value.code, value.data, value
    end

    local function transfer(actor, amount, request)
        amount = positiveAmount(amount)
        if not amount then
            local value = result(false, "amountInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local fromScope = scope(request and request.fromScope, "spendable")
        local toScope = scope(request and request.toScope, "cash")
        if fromScope == toScope then
            local value = result(false, "transferScopeInvalid", nil, request)
            return false, value.code, value.data, value
        end
        local value = mutate("transfer", actor, amount, fromScope, toScope, nil, request, function()
            local available, balanceCode = balance(actor, fromScope)
            if balanceCode then return result(false, balanceCode, nil, request) end
            if available < amount then
                return result(false, "balanceInsufficient", {
                    available = available,
                    required = amount,
                }, request)
            end
            local debitCalled, debited, debitReceipt, debitData = method(funds, "debit",
                actor, amount, fromScope, withRequest(request, "debit"))
            if not debitCalled then return portFailure("transferDebit", debited, request) end
            if debited ~= true then
                return result(false, debitReceipt or "chargeFailed", debitData, request)
            end
            if debitReceipt == nil then
                return result(false, "receiptMissing", { stage = "transferDebit" }, request)
            end
            local creditCalled, credited, creditReceipt, creditData = method(funds, "credit",
                actor, amount, toScope, withRequest(request, "credit"))
            if creditCalled and credited == true and creditReceipt ~= nil then
                return result(true, "transferred", {
                    receipt = {
                        kind = "transfer",
                        amount = amount,
                        fromScope = fromScope,
                        toScope = toScope,
                        debitReceipt = debitReceipt,
                        creditReceipt = creditReceipt,
                    },
                }, request)
            end
            local restoreCalled, restored = method(funds, "restore",
                actor, debitReceipt, withRequest(request, "rollback"))
            if not restoreCalled or restored ~= true then
                return result(false, "rollbackIncomplete", {
                    stage = "transferCredit",
                    cause = creditCalled and (creditReceipt or "grantFailed") or tostring(credited),
                }, request)
            end
            if not creditCalled then return portFailure("transferCredit", credited, request) end
            return result(false, creditReceipt or "grantFailed", creditData, request)
        end)
        local receipt = value.ok and value.data and value.data.receipt or value.code
        return value.ok, receipt, value.data, value
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        local action = tostring(request.action or "")
        if not MUTATIONS[action] then
            return result(false, "actionInvalid", { action = action }, request)
        end
        if action == "grant" then
            local _, _, _, value = grant(request.actor, request.amount, request)
            return value
        elseif action == "charge" then
            local _, _, _, value = charge(request.actor, request.amount, request)
            return value
        elseif action == "refund" then
            local _, _, _, value = refund(request.actor, request.receipt, request)
            return value
        end
        local _, _, _, value = transfer(request.actor, request.amount, request)
        return value
    end

    instance.public = {
        getBalance = balance,
        grant = grant,
        charge = charge,
        refund = refund,
        transfer = transfer,
        execute = execute,
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
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
        }
        if type(funds.health) == "function" then
            local called, healthy, detail = method(funds, "health")
            if not called or healthy == false then
                data.funds = detail or healthy
                return GodSystemResult.fail(moduleId, "fundsUnhealthy", data)
            end
        end
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
