require "GodSystem/Core/Result"

GodSystemMaintenanceFeatureModule = GodSystemMaintenanceFeatureModule or {}

local Descriptor = GodSystemMaintenanceFeatureModule

Descriptor.id = "feature.maintenance"
Descriptor.dependencies = {
    "inventory.query",
    "inventory.mutation",
    "wallet",
    "maintenance.rules",
    "notifications",
}
Descriptor.stateVersion = 1

local ACTIONS = {
    repairItem = true,
    enhanceDurability = true,
    repairVehicle = true,
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

local function requiredPort(dependencies, dependencyId, methods)
    local port = dependencies[dependencyId]
    assert(type(port) == "table", "missing dependency: " .. dependencyId)
    for i = 1, #methods do
        assert(type(port[methods[i]]) == "function",
            "dependency " .. dependencyId .. " is missing method " .. methods[i])
    end
    return port
end

local function operationId(request)
    local value = request and request.operationId
    value = tostring(value or "")
    return value ~= "" and value or nil
end

local function safeCost(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge or value < 0 then return nil end
    return math.floor(value)
end

local function withAction(request, action)
    local copy = {}
    for key, value in pairs(type(request) == "table" and request or {}) do copy[key] = value end
    copy.action = action
    return copy
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local query = requiredPort(dependencies, "inventory.query", { "resolveItem", "resolveVehicle" })
    local mutation = requiredPort(dependencies, "inventory.mutation", { "consume", "restore" })
    local wallet = requiredPort(dependencies, "wallet", { "charge", "refund" })
    local rules = requiredPort(dependencies, "maintenance.rules", { "validate", "snapshot", "apply", "rollback" })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })

    local instance = {
        started = false,
        lastIssue = nil,
        completed = 0,
        failed = 0,
    }

    local function result(ok, code, data, request)
        local value
        if ok then
            instance.completed = instance.completed + 1
            value = GodSystemResult.ok(moduleId, code, data, operationId(request))
        else
            instance.failed = instance.failed + 1
            value = GodSystemResult.fail(moduleId, code, data, operationId(request))
        end

        local notified, notifyError = callPort(notifications.publish, value, request)
        if not notified then
            instance.lastIssue = {
                stage = "notify",
                code = "notificationFailed",
                message = tostring(notifyError),
            }
        end
        return value
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

    local function rollback(action, actor, target, snapshot, consumeReceipt, paymentReceipt, request)
        local state = {
            target = true,
            inventory = consumeReceipt == nil,
            wallet = paymentReceipt == nil,
        }

        local targetCall, targetRestored = callPort(rules.rollback, action, target, snapshot, request)
        state.target = targetCall and targetRestored ~= false

        if consumeReceipt ~= nil then
            local inventoryCall, inventoryRestored = callPort(
                mutation.restore, actor, consumeReceipt, request)
            state.inventory = inventoryCall and inventoryRestored ~= false
        end

        if paymentReceipt ~= nil then
            local walletCall, walletRestored = callPort(wallet.refund, actor, paymentReceipt, request)
            state.wallet = walletCall and walletRestored ~= false
        end

        state.complete = state.target and state.inventory and state.wallet
        return state
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        if not instance.started then
            return result(false, "moduleStopped", nil, request)
        end

        local action = tostring(request.action or "")
        if not ACTIONS[action] then
            return result(false, "actionInvalid", { action = action }, request)
        end

        local actor = request.actor
        if actor == nil then
            return result(false, "actorRequired", nil, request)
        end

        local targetCall, target, targetCode
        if action == "repairVehicle" then
            targetCall, target, targetCode = callPort(
                query.resolveVehicle, actor, request.vehicleId or request.targetId, request)
        else
            targetCall, target, targetCode = callPort(
                query.resolveItem, actor, request.targetId, "target", request)
        end
        if not targetCall then return portFailure("resolveTarget", target, request) end
        if target == nil then
            return result(false, targetCode or "targetMissing", { action = action }, request)
        end

        local consumableCall, consumable, consumableCode = callPort(
            query.resolveItem, actor, request.consumableId, "consumable", request)
        if not consumableCall then return portFailure("resolveConsumable", consumable, request) end
        if consumable == nil then
            return result(false, consumableCode or "consumableMissing", { action = action }, request)
        end

        local validateCall, valid, quoteOrCode, validationData = callPort(
            rules.validate, action, actor, target, consumable, request)
        if not validateCall then return portFailure("validate", valid, request) end
        if valid ~= true then
            return result(false, quoteOrCode or "validationFailed", validationData, request)
        end
        local quote = type(quoteOrCode) == "table" and quoteOrCode or {}
        local cost = safeCost(quote.cost)
        if cost == nil then
            return result(false, "quoteInvalid", { action = action }, request)
        end

        local snapshotCall, snapshot, snapshotCode, snapshotData = callPort(
            rules.snapshot, action, target, request)
        if not snapshotCall then return portFailure("snapshot", snapshot, request) end
        if snapshot == nil or snapshot == false then
            return result(false, snapshotCode or "snapshotFailed", snapshotData, request)
        end

        local paymentReceipt = nil
        if cost > 0 then
            local chargeCall, paid, receiptOrCode, paymentData = callPort(
                wallet.charge, actor, cost, request)
            if not chargeCall then return portFailure("charge", paid, request) end
            if paid ~= true then
                return result(false, receiptOrCode or "paymentFailed", paymentData, request)
            end
            paymentReceipt = receiptOrCode
            if paymentReceipt == nil then
                return result(false, "rollbackIncomplete", {
                    causeCode = "paymentReceiptMissing",
                    wallet = false,
                }, request)
            end
        end

        local consumeCall, consumed, consumeReceiptOrCode, consumeData = callPort(
            mutation.consume, actor, consumable, request)
        if not consumeCall then
            if paymentReceipt ~= nil then
                local refundCall, refunded = callPort(wallet.refund, actor, paymentReceipt, request)
                if not refundCall or refunded == false then
                    return result(false, "rollbackIncomplete", {
                        causeCode = "portError",
                        stage = "consume",
                        wallet = false,
                        message = tostring(consumed),
                    }, request)
                end
            end
            return portFailure("consume", consumed, request)
        end
        if consumed ~= true then
            local walletRestored = true
            if paymentReceipt ~= nil then
                local refundCall, refunded = callPort(wallet.refund, actor, paymentReceipt, request)
                walletRestored = refundCall and refunded ~= false
            end
            if not walletRestored then
                return result(false, "rollbackIncomplete", {
                    causeCode = consumeReceiptOrCode or "consumeFailed",
                    wallet = false,
                }, request)
            end
            return result(false, consumeReceiptOrCode or "consumeFailed", consumeData, request)
        end
        local consumeReceipt = consumeReceiptOrCode
        if consumeReceipt == nil then
            local walletRestored = true
            if paymentReceipt ~= nil then
                local refundCall, refunded = callPort(wallet.refund, actor, paymentReceipt, request)
                walletRestored = refundCall and refunded ~= false
            end
            return result(false, "rollbackIncomplete", {
                causeCode = "consumeReceiptMissing",
                inventory = false,
                wallet = walletRestored,
            }, request)
        end

        local applyCall, applied, applyPayloadOrCode, applyData = callPort(
            rules.apply, action, target, snapshot, request)
        if applyCall and applied == true then
            return result(true, "completed", {
                action = action,
                cost = cost,
                outcome = applyPayloadOrCode,
            }, request)
        end

        local causeCode = applyCall and (applyPayloadOrCode or "applyFailed") or "portError"
        local causeData = applyCall and applyData or {
            stage = "apply",
            message = tostring(applied),
        }
        local rollbackState = rollback(
            action, actor, target, snapshot, consumeReceipt, paymentReceipt, request)
        if not rollbackState.complete then
            instance.lastIssue = {
                stage = "rollback",
                code = "rollbackIncomplete",
                message = tostring(causeCode),
            }
            return result(false, "rollbackIncomplete", {
                causeCode = causeCode,
                cause = causeData,
                rollback = rollbackState,
            }, request)
        end
        return result(false, causeCode, {
            cause = causeData,
            rollback = rollbackState,
        }, request)
    end

    instance.public = {
        execute = execute,
        repairItem = function(request)
            return execute(withAction(request, "repairItem"))
        end,
        enhanceDurability = function(request)
            return execute(withAction(request, "enhanceDurability"))
        end,
        repairVehicle = function(request)
            return execute(withAction(request, "repairVehicle"))
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
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
        }
        if self.lastIssue then
            return GodSystemResult.fail(moduleId, self.lastIssue.code, data)
        end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
