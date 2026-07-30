require "GodSystem/Core/Result"
require "GodSystem/Features/Attributes/Rules"
require "GodSystem/Features/Attributes/State"

GodSystemAttributesFeatureModule = GodSystemAttributesFeatureModule or {}

local Descriptor = GodSystemAttributesFeatureModule
local Rules = GodSystemAttributesFeatureRules
local State = GodSystemAttributesFeatureState

Descriptor.id = "feature.attributes"
Descriptor.dependencies = {
    "attributes.query",
    "attributes.mutation",
    "admin.config",
    "wallet",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

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

local function required(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. id)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. id .. " is missing method " .. methods[index])
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
    result.operationId = tostring(operationId(request) or "") .. ":" .. tostring(suffix)
    return result
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

function Descriptor.create(dependencies, context)
    dependencies, context = dependencies or {}, context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local query = required(dependencies, "attributes.query", {
        "ownerKey", "listPerks", "resolvePerk", "perkState",
        "listTraits", "resolveTrait", "hasTrait",
    })
    local mutation = required(dependencies, "attributes.mutation", {
        "addXp", "syncXp", "setTrait", "applyTraitBenefits",
    })
    local config = required(dependencies, "admin.config", { "getSetting", "isFeatureEnabled" })
    local wallet = required(dependencies, "wallet", { "charge", "refund" })
    local operations = required(dependencies, "operations", { "begin", "finish", "markUnknown" })
    local notifications = required(dependencies, "notifications", { "publish" })
    local state = State.new(assert(context.state, "feature.attributes state context required"))
    local instance = { started = false, completed = 0, failed = 0, lastIssue = nil }

    local function makeResult(ok, code, data, request)
        if ok then instance.completed = instance.completed + 1
        else instance.failed = instance.failed + 1 end
        local result = ok and GodSystemResult.ok(moduleId, code, data, operationId(request))
            or GodSystemResult.fail(moduleId, code, data, operationId(request))
        local called, published = call(notifications.publish, result, request)
        if not called or published == false then
            instance.lastIssue = { stage = "notify", code = "notificationFailed" }
        end
        return result
    end

    local function begin(action, identity, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local fingerprint = table.concat({
            tostring(action or ""), tostring(identity or ""),
            tostring(request and request.mode or ""), tostring(request and request.value or ""),
        }, "|")
        local called, status, value = call(operations.begin, moduleId, id, fingerprint, request)
        if not called then
            instance.lastIssue = { stage = "operationBegin", code = "portError", message = tostring(status) }
            return nil, makeResult(false, "portError", { stage = "operationBegin" }, request)
        end
        if status == "replay" then return nil, value end
        if status ~= "new" then
            return nil, makeResult(false,
                type(value) == "table" and value.code or tostring(value or "operationPending"), nil, request)
        end
        return id
    end

    local function finish(id, result, request)
        local called, stored = call(operations.finish, moduleId, id, result, request)
        if called and stored ~= false then return result end
        call(operations.markUnknown, moduleId, id, "operationOutcomeUnknown", request)
        instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = result and result.ok == true,
        }, id)
    end

    local function actorState(actor)
        local called, owner = call(query.ownerKey, actor)
        if not called or tostring(owner or "") == "" then return nil, nil, "ownerUnavailable" end
        local data, code = state.load(owner)
        return owner, data, code
    end

    local function setting(key, fallback)
        local called, value = call(config.getSetting, key, fallback)
        if not called then
            instance.lastIssue = { stage = "config", code = "portError", message = tostring(value) }
            return fallback
        end
        return value
    end

    local function enabled(key)
        local called, value = call(config.isFeatureEnabled, key)
        if not called then
            instance.lastIssue = { stage = "config", code = "portError", message = tostring(value) }
            return false
        end
        return value == true
    end

    local function attributeQuote(actor, perkIndex, mode, value)
        if not instance.started then return nil, "moduleStopped" end
        if not enabled("EnableAttributes") then return nil, "attributesDisabled" end
        local called, info, reason = call(query.resolvePerk, perkIndex)
        if not called then return nil, "portError" end
        if type(info) ~= "table" then return nil, reason or "perkMissing" end
        local stateCalled, playerState, stateCode = call(query.perkState, actor, info)
        if not stateCalled then return nil, "portError" end
        if type(playerState) ~= "table" then return nil, stateCode or "stateMissing" end
        return Rules.attributeQuote(info, playerState, mode, value,
            setting("AttributeXPPerCoin", Rules.defaultXpPerCoin))
    end

    local function listPerks(actor, search)
        if not instance.started then return {} end
        local called, rows = call(query.listPerks, actor)
        if not called or type(rows) ~= "table" then
            instance.lastIssue = { stage = "listPerks", code = "portError", message = tostring(rows) }
            return {}
        end
        search = tostring(search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if search == "" then return rows end
        local result = {}
        for index = 1, #rows do
            local row = rows[index]
            local text = (tostring(row.label or "") .. " " .. tostring(row.parentLabel or "")):lower()
            if string.find(text, search, 1, true) then result[#result + 1] = row end
        end
        return result
    end

    local function settlePartial(actor, receipt, finalCost, request)
        local refundedCall, refunded = call(wallet.refund,
            actor, receipt, childRequest(request, "partial-refund"))
        if not refundedCall or refunded ~= true then return nil, "partialRefundFailed" end
        local chargedCall, charged, replacement = call(wallet.charge,
            actor, finalCost, childRequest(request, "partial-charge"))
        if not chargedCall or charged ~= true or replacement == nil then
            return nil, "partialRechargeFailed"
        end
        return replacement
    end

    local function purchaseAttribute(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("attribute", request.perkIndex, request)
        if replay then return replay end
        local quote, quoteCode = attributeQuote(
            request.actor, request.perkIndex, request.mode, request.value)
        if not quote then return finish(id, makeResult(false, quoteCode, nil, request), request) end
        local owner, data, stateCode = actorState(request.actor)
        if not data then
            return finish(id, makeResult(false, stateCode or "stateUnavailable", nil, request), request)
        end
        local chargeCalled, charged, receipt = call(wallet.charge,
            request.actor, quote.cost, childRequest(request, "charge"))
        if not chargeCalled or charged ~= true or receipt == nil then
            return finish(id, makeResult(false,
                chargeCalled and (receipt or "balanceInsufficient") or "portError", nil, request), request)
        end
        local applyCalled, applied, applyCode = call(
            mutation.addXp, request.actor, quote.info, quote.actualXp, request)
        local stateCalled, after = call(query.perkState, request.actor, quote.info)
        local appliedXp = stateCalled and type(after) == "table"
            and math.max(0, (tonumber(after.currentXp) or 0) - quote.currentXp) or 0
        if not applyCalled or applied ~= true or appliedXp <= 0 then
            local refundCalled, refunded = call(
                wallet.refund, request.actor, receipt, childRequest(request, "rollback"))
            local rollbackOk = refundCalled and refunded == true
            return finish(id, makeResult(false,
                rollbackOk and (applyCalled and (applyCode or "attributeApplyFailed") or "portError")
                    or "rollbackIncomplete", nil, request), request)
        end
        local chargedCost = Rules.finalAttributeCost(quote, appliedXp)
        if chargedCost < quote.cost then
            local replacement, settleCode = settlePartial(request.actor, receipt, chargedCost, request)
            if not replacement then
                call(operations.markUnknown, moduleId, id, settleCode, request)
                instance.lastIssue = { stage = "settlement", code = settleCode }
                return makeResult(false, "operationOutcomeUnknown", {
                    stage = "partialSettlement", appliedXp = appliedXp,
                }, request)
            end
            receipt = replacement
        end
        local syncCalled, synced = call(mutation.syncXp, request.actor, request)
        data.stats.spentPoints = (tonumber(data.stats.spentPoints) or 0) + chargedCost
        data.attributeSyncPending = not (syncCalled and synced == true)
        local saved, saveCode = state.save(owner, data)
        if not saved then
            call(operations.markUnknown, moduleId, id, saveCode or "stateSaveFailed", request)
            return makeResult(false, "operationOutcomeUnknown", {
                stage = "stateSave", appliedXp = appliedXp, chargedCost = chargedCost,
            }, request)
        end
        return finish(id, makeResult(true,
            data.attributeSyncPending and "attributePurchasedSyncPending" or "attributePurchased", {
                perkIndex = quote.info.index,
                label = quote.info.label,
                appliedXp = appliedXp,
                chargedCost = chargedCost,
                level = after and after.currentLevel or quote.currentLevel,
                syncPending = data.attributeSyncPending,
            }, request), request)
    end

    local function traitQuote(actor, action, traitType)
        if not instance.started then return nil, "moduleStopped" end
        if not enabled("EnableTraits") then return nil, "traitsDisabled" end
        local called, info, reason = call(query.resolveTrait, actor, traitType)
        if not called then return nil, "portError" end
        if type(info) ~= "table" then return nil, reason or "traitMissing" end
        local ownedCalled, owned = call(query.hasTrait, actor, info.traitType)
        if not ownedCalled then return nil, "portError" end
        return Rules.traitQuote(info, owned == true, action,
            setting("PositiveTraitCostPerPoint", Rules.defaultPositiveCostPerPoint),
            setting("NegativeTraitRemoveCostPerPoint", Rules.defaultNegativeRemoveCostPerPoint))
    end

    local function listTraits(actor, action)
        if not instance.started then return {} end
        local called, rows = call(query.listTraits, actor, action)
        if not called or type(rows) ~= "table" then
            instance.lastIssue = { stage = "listTraits", code = "portError", message = tostring(rows) }
            return {}
        end
        local result = {}
        for index = 1, #rows do
            local quote = traitQuote(actor, action, rows[index].traitType)
            local row = copy(rows[index])
            row.quote = quote
            row.price = quote and quote.cost or nil
            result[#result + 1] = row
        end
        return result
    end

    local function modifyTrait(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("trait:" .. tostring(request.action), request.traitType, request)
        if replay then return replay end
        local quote, quoteCode = traitQuote(request.actor, request.action, request.traitType)
        if not quote then return finish(id, makeResult(false, quoteCode, nil, request), request) end
        local owner, data, stateCode = actorState(request.actor)
        if not data then
            return finish(id, makeResult(false, stateCode or "stateUnavailable", nil, request), request)
        end
        local enable = quote.action == "buy"
        local mutationCalled, changed, mutationCode = call(
            mutation.setTrait, request.actor, quote.info or quote, enable, request)
        local verifyCalled, owned = call(query.hasTrait, request.actor, quote.traitType)
        if not mutationCalled or changed ~= true or not verifyCalled or owned ~= enable then
            return finish(id, makeResult(false,
                mutationCalled and (mutationCode or "traitApplyFailed") or "portError", nil, request), request)
        end
        local receipt
        if quote.cost > 0 then
            local chargeCalled, charged, receiptOrCode = call(
                wallet.charge, request.actor, quote.cost, childRequest(request, "charge"))
            if not chargeCalled or charged ~= true or receiptOrCode == nil then
                local rollbackCalled, rolledBack = call(
                    mutation.setTrait, request.actor, quote.info or quote, not enable, request)
                local verifyRollback, current = call(query.hasTrait, request.actor, quote.traitType)
                local rollbackOk = rollbackCalled and rolledBack == true
                    and verifyRollback and current == (not enable)
                return finish(id, makeResult(false,
                    rollbackOk and (chargeCalled and (receiptOrCode or "balanceInsufficient") or "portError")
                        or "rollbackIncomplete", nil, request), request)
            end
            receipt = receiptOrCode
        end
        data.stats.spentPoints = (tonumber(data.stats.spentPoints) or 0) + quote.cost
        data.stats.modifiedTraits = (tonumber(data.stats.modifiedTraits) or 0) + 1
        local saved, saveCode = state.save(owner, data)
        if not saved then
            local traitRollbackCalled, traitRolledBack = call(
                mutation.setTrait, request.actor, quote.info or quote, not enable, request)
            local walletRollback = true
            if receipt then
                local refundCalled, refunded = call(
                    wallet.refund, request.actor, receipt, childRequest(request, "rollback"))
                walletRollback = refundCalled and refunded == true
            end
            return finish(id, makeResult(false,
                traitRollbackCalled and traitRolledBack == true and walletRollback
                    and (saveCode or "stateSaveFailed") or "rollbackIncomplete", nil, request), request)
        end
        local benefitsOk, benefitsApplied = true, 0
        if enable then
            local benefitsCalled, ok, count = call(
                mutation.applyTraitBenefits, request.actor, quote.info or quote, request)
            benefitsOk = benefitsCalled and ok ~= false
            benefitsApplied = tonumber(count) or 0
        end
        return finish(id, makeResult(true, benefitsOk and "traitModified" or "traitModifiedBenefitsPending", {
            action = quote.action,
            traitType = quote.traitType,
            chargedCost = quote.cost,
            benefitsApplied = benefitsApplied,
            benefitsOk = benefitsOk,
        }, request), request)
    end

    instance.public = {
        listPerks = listPerks,
        quoteAttribute = attributeQuote,
        purchaseAttribute = purchaseAttribute,
        listTraits = listTraits,
        quoteTrait = traitQuote,
        modifyTrait = modifyTrait,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
        }
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
