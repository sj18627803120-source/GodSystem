require "GodSystem/Core/Result"

GodSystemRecycleFeatureModule = GodSystemRecycleFeatureModule or {}

local Descriptor = GodSystemRecycleFeatureModule

Descriptor.id = "feature.recycle"
Descriptor.dependencies = {
    "recycle.config",
    "recycle.state",
    "recycle.inventory",
    "recycle.wallet",
    "metrics",
    "item.eligibility",
    "shop.identity",
    "shop.listings",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local MODES = {
    recycle = true,
    recycleAndList = true,
    listOnly = true,
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

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return fallback or 0 end
    return math.floor(value)
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    return value ~= "" and value or nil
end

local function fingerprint(mode, itemIds)
    local unique = {}
    for i = 1, #(itemIds or {}) do
        local value = tostring(itemIds[i] or "")
        if value ~= "" then unique[value] = true end
    end
    local values = {}
    for value in pairs(unique) do values[#values + 1] = value end
    table.sort(values)
    return tostring(mode or "") .. "|" .. table.concat(values, ",")
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "recycle.config", { "recycleValue", "payout", "listingPrice" })
    local state = requiredPort(dependencies, "recycle.state", { "load", "save" })
    local inventory = requiredPort(dependencies, "recycle.inventory", { "resolve", "remove", "restore" })
    local wallet = requiredPort(dependencies, "recycle.wallet",
        { "charge", "refund", "credit", "revokeCredit" })
    local metrics = requiredPort(dependencies, "metrics", { "snapshot", "get", "increment", "restore" })
    local eligibility = requiredPort(dependencies, "item.eligibility", { "canRecycle", "canList" })
    local identity = requiredPort(dependencies, "shop.identity", { "variantKey" })
    local listings = requiredPort(dependencies, "shop.listings", { "isKnown", "add", "remove" })
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

    local function begin(request, mode)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = callPort(
            operations.begin, moduleId, id, "batch|" .. fingerprint(mode, request.itemIds), request)
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
        return data, nil
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

    local function variantKey(item, request)
        local called, key = callPort(identity.variantKey, item.fullType, item.worldSprite, request)
        if not called or tostring(key or "") == "" then return nil end
        return tostring(key)
    end

    local function restoreRemoved(actor, receipts, request)
        local restored = true
        for i = #receipts, 1, -1 do
            local called, value = callPort(inventory.restore, actor, receipts[i], request)
            restored = restored and called and value ~= false
        end
        return restored
    end

    local function rollbackListings(actor, receipts, request)
        local restored = true
        for i = #receipts, 1, -1 do
            local called, value = callPort(listings.remove, actor, receipts[i], request)
            restored = restored and called and value ~= false
        end
        return restored
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local mode = tostring(request.mode or "")
        if not MODES[mode] then return makeResult(false, "selectionInvalid", nil, request) end
        local id, replay = begin(request, mode)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end

        local selected, seen = {}, {}
        local skipped = math.max(0, integer(request.clientSkipped, 0))
        for i = 1, #(request.itemIds or {}) do
            local itemId = tostring(request.itemIds[i] or "")
            if itemId ~= "" and not seen[itemId] then
                seen[itemId] = true
                local called, item, code = callPort(inventory.resolve, request.actor, itemId, request)
                if not called or type(item) ~= "table" then
                    return finish(id, makeResult(false, called and (code or "selectionChanged") or "portError", nil, request), request)
                end
                item.id = tostring(item.id or itemId)
                item.fullType = tostring(item.fullType or "")
                local eligibleCall, eligible, eligibleCode = callPort(
                    eligibility.canRecycle, item, mode, request)
                if not eligibleCall then
                    return finish(id, makeResult(false, "portError", { stage = "canRecycle" }, request), request)
                end
                if eligible ~= true then
                    skipped = skipped + 1
                else
                    local key = variantKey(item, request)
                    if not key then
                        return finish(id, makeResult(false, "variantInvalid", nil, request), request)
                    end
                    if mode ~= "recycle" then
                        local listCall, listable = callPort(eligibility.canList, item, request)
                        if not listCall then
                            return finish(id, makeResult(false, "portError", { stage = "canList" }, request), request)
                        end
                        local knownCall, known = callPort(listings.isKnown, request.actor, key, request)
                        if not knownCall then
                            return finish(id, makeResult(false, "portError", { stage = "listingLookup" }, request), request)
                        end
                        if listable ~= true or known == true then
                            skipped = skipped + 1
                            eligible = false
                        end
                    end
                    if eligible == true then
                        item.variantKey = key
                        selected[#selected + 1] = item
                    end
                end
            end
        end

        if #selected == 0 then
            return finish(id, makeResult(false, "selectionEmptySkipped", {
                processedCount = 0,
                skippedCount = skipped,
            }, request), request)
        end

        local groups, groupOrder = {}, {}
        for i = 1, #selected do
            local item = selected[i]
            local groupKey = mode == "recycle" and item.fullType or item.variantKey
            if not groups[groupKey] then
                groups[groupKey] = {
                    key = groupKey,
                    fullType = item.fullType,
                    worldSprite = item.worldSprite,
                    label = item.label,
                    count = 0,
                    rawValue = 0,
                    sample = item,
                }
                groupOrder[#groupOrder + 1] = groupKey
            end
            local valueCalled, value = callPort(config.recycleValue, item, request)
            if not valueCalled or tonumber(value) == nil or tonumber(value) < 0 then
                return finish(id, makeResult(false, "quoteInvalid", { itemId = item.id }, request), request)
            end
            groups[groupKey].count = groups[groupKey].count + 1
            groups[groupKey].rawValue = groups[groupKey].rawValue + tonumber(value)
        end

        if mode == "listOnly" then
            local totalCost, rows = 0, {}
            for i = 1, #groupOrder do
                local row = groups[groupOrder[i]]
                local quoteCalled, cost, buyPrice = callPort(config.listingPrice, row.sample, request)
                cost = quoteCalled and integer(cost, -1) or -1
                if cost < 0 then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
                totalCost = totalCost + cost
                rows[#rows + 1] = {
                    variantKey = row.key,
                    fullType = row.fullType,
                    worldSprite = row.worldSprite,
                    label = row.label,
                    buyPrice = buyPrice,
                    sellPrice = row.sample.sellPrice,
                }
            end
            local paymentReceipt
            if totalCost > 0 then
                local chargeCalled, paid, receiptOrCode = callPort(wallet.charge, request.actor, totalCost, request)
                if not chargeCalled or paid ~= true or receiptOrCode == nil then
                    return finish(id, makeResult(false,
                        chargeCalled and (receiptOrCode or "insufficientFunds") or "portError", nil, request), request)
                end
                paymentReceipt = receiptOrCode
            end
            local listingReceipts = {}
            for i = 1, #rows do
                local addCalled, added, receiptOrCode = callPort(listings.add, request.actor, rows[i], request)
                if not addCalled or added ~= true or receiptOrCode == nil then
                    local listingsRestored = rollbackListings(request.actor, listingReceipts, request)
                    local walletRestored = true
                    if paymentReceipt then
                        local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                        walletRestored = refundCalled and value ~= false
                    end
                    return finish(id, makeResult(false,
                        listingsRestored and walletRestored and
                            (addCalled and (receiptOrCode or "selectionChanged") or "portError") or "rollbackIncomplete",
                        nil, request), request)
                end
                listingReceipts[#listingReceipts + 1] = receiptOrCode
            end
            if totalCost > 0 then
                local counted, countCode = incrementMetric(
                    request.actor, { spentPoints = totalCost }, request)
                if not counted then
                    local listingsRestored = rollbackListings(
                        request.actor, listingReceipts, request)
                    local walletRestored = true
                    if paymentReceipt then
                        local refundCalled, value = callPort(
                            wallet.refund, request.actor, paymentReceipt, request)
                        walletRestored = refundCalled and value ~= false
                    end
                    return finish(id, makeResult(false,
                        listingsRestored and walletRestored and countCode
                            or "rollbackIncomplete", nil, request), request)
                end
            end
            local code = skipped > 0 and "listOnlyPartial" or "listOnly"
            return finish(id, makeResult(true, code, {
                processedCount = #rows,
                selectedCount = #selected,
                skippedCount = skipped,
                cost = totalCost,
                listedCount = #rows,
            }, request), request)
        end

        local groupRows = {}
        for i = 1, #groupOrder do groupRows[#groupRows + 1] = groups[groupOrder[i]] end
        local payoutCalled, payout, payoutState = callPort(config.payout, groupRows, data, request)
        payout = payoutCalled and integer(payout, -1) or -1
        if payout <= 0 then return finish(id, makeResult(false, "selectionEmpty", nil, request), request) end
        local before = copy(data)
        if type(payoutState) == "table" then
            for key, value in pairs(payoutState) do data[key] = value end
        end

        local removeReceipts = {}
        for i = 1, #selected do
            local removeCalled, removed, receiptOrCode = callPort(inventory.remove, request.actor, selected[i], request)
            if not removeCalled or removed ~= true or receiptOrCode == nil then
                local restored = restoreRemoved(request.actor, removeReceipts, request)
                local stateRestored = save(request.actor, before, request)
                return finish(id, makeResult(false,
                    restored and stateRestored and
                        (removeCalled and (receiptOrCode or "selectionFailed") or "portError") or "rollbackIncomplete",
                    nil, request), request)
            end
            removeReceipts[#removeReceipts + 1] = receiptOrCode
        end

        local creditCalled, credited, creditReceiptOrCode = callPort(wallet.credit, request.actor, payout, request)
        if not creditCalled or credited ~= true or creditReceiptOrCode == nil then
            local restored = restoreRemoved(request.actor, removeReceipts, request)
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false,
                restored and stateRestored and
                    (creditCalled and (creditReceiptOrCode or "payoutFailed") or "portError") or "rollbackIncomplete",
                nil, request), request)
        end
        local creditReceipt = creditReceiptOrCode

        local listingReceipts = {}
        if mode == "recycleAndList" then
            for i = 1, #groupRows do
                local row = groupRows[i]
                local listing = {
                    variantKey = row.key,
                    fullType = row.fullType,
                    worldSprite = row.worldSprite,
                    label = row.label,
                    sellPrice = row.sample.sellPrice,
                    buyPrice = row.sample.buyPrice,
                }
                local addCalled, added, receiptOrCode = callPort(listings.add, request.actor, listing, request)
                if not addCalled or added ~= true or receiptOrCode == nil then
                    local listingsRestored = rollbackListings(request.actor, listingReceipts, request)
                    local revokeCalled, revoked = callPort(wallet.revokeCredit, request.actor, creditReceipt, request)
                    local itemsRestored = restoreRemoved(request.actor, removeReceipts, request)
                    local stateRestored = save(request.actor, before, request)
                    local rollbackOk = listingsRestored and revokeCalled and revoked ~= false and
                        itemsRestored and stateRestored
                    return finish(id, makeResult(false,
                        rollbackOk and (addCalled and (receiptOrCode or "selectionChanged") or "portError") or "rollbackIncomplete",
                        nil, request), request)
                end
                listingReceipts[#listingReceipts + 1] = receiptOrCode
            end
        end

        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local listingsRestored = rollbackListings(request.actor, listingReceipts, request)
            local revokeCalled, revoked = callPort(wallet.revokeCredit, request.actor, creditReceipt, request)
            local itemsRestored = restoreRemoved(request.actor, removeReceipts, request)
            local stateRestored = save(request.actor, before, request)
            local rollbackOk = listingsRestored and revokeCalled and revoked ~= false and itemsRestored and stateRestored
            return finish(id, makeResult(false, rollbackOk and saveCode or "rollbackIncomplete", nil, request), request)
        end
        local counted, countCode = incrementMetric(request.actor, {
            recycledItems = #selected,
            recycledPoints = payout,
        }, request)
        if not counted then
            local listingsRestored = rollbackListings(request.actor, listingReceipts, request)
            local revokeCalled, revoked = callPort(
                wallet.revokeCredit, request.actor, creditReceipt, request)
            local itemsRestored = restoreRemoved(request.actor, removeReceipts, request)
            local stateRestored = save(request.actor, before, request)
            local rollbackOk = listingsRestored and revokeCalled and revoked ~= false
                and itemsRestored and stateRestored
            return finish(id, makeResult(false,
                rollbackOk and countCode or "rollbackIncomplete", nil, request), request)
        end

        local baseCode = mode == "recycleAndList" and "recycledAndListed" or "recycled"
        local code = skipped > 0 and (baseCode .. "Partial") or baseCode
        return finish(id, makeResult(true, code, {
            processedCount = #selected,
            skippedCount = skipped,
            payout = payout,
            listedCount = #listingReceipts,
        }, request), request)
    end

    instance.public = { execute = execute }
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
