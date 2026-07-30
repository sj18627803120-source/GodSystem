require "GodSystem/Core/Result"

GodSystemShopFeatureModule = GodSystemShopFeatureModule or {}

local Descriptor = GodSystemShopFeatureModule

Descriptor.id = "feature.shop"
Descriptor.dependencies = {
    "shop.config",
    "shop.state",
    "shop.identity",
    "shop.inventory",
    "shop.wallet",
    "metrics",
    "item.eligibility",
    "clock",
    "random",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

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

local function stableToken(value)
    value = tostring(value or "")
    return value:gsub("|", "%%7C")
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "shop.config",
        { "resolveProduct", "configuredCandidates", "isConfigured", "purchasePrice", "listingPrice", "lotteryPrice" })
    local state = requiredPort(dependencies, "shop.state", { "load", "save" })
    local identity = requiredPort(dependencies, "shop.identity", { "variantKey", "productId" })
    local inventory = requiredPort(dependencies, "shop.inventory", { "resolve", "grant", "revoke" })
    local wallet = requiredPort(dependencies, "shop.wallet", { "charge", "refund" })
    local metrics = requiredPort(dependencies, "metrics", { "snapshot", "get", "increment", "restore" })
    local eligibility = requiredPort(dependencies, "item.eligibility", { "allowed" })
    local clock = requiredPort(dependencies, "clock", { "nowHours" })
    local random = requiredPort(dependencies, "random", { "index" })
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

    local function begin(action, fingerprint, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = callPort(operations.begin, moduleId, id, action .. "|" .. fingerprint, request)
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
        data.unlockedShopItems = type(data.unlockedShopItems) == "table" and data.unlockedShopItems or {}
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

    local function keyFor(fullType, worldSprite, request)
        local called, key = callPort(identity.variantKey, tostring(fullType or ""), worldSprite, request)
        if not called or tostring(key or "") == "" then return nil end
        return tostring(key)
    end

    local function productIdFor(row, source, request)
        local called, id = callPort(identity.productId, row, source, request)
        if not called or tostring(id or "") == "" then return nil end
        return tostring(id)
    end

    local function validItems(entries, usage, request)
        entries = type(entries) == "table" and entries or {}
        if #entries == 0 then return false, "productEmpty" end
        for i = 1, #entries do
            local fullType = tostring(entries[i].fullType or "")
            if fullType == "" then return false, "itemInvalid" end
            local called, allowed, code = callPort(eligibility.allowed, fullType, usage, entries[i], request)
            if not called then return false, "portError" end
            if allowed ~= true then return false, code or "itemNotEligible" end
        end
        return true
    end

    local function resolveProduct(actor, data, productId, request)
        local called, product, sourceOrCode = callPort(config.resolveProduct, actor, productId, request)
        if not called then return nil, "portError" end
        if type(product) == "table" then
            product.source = sourceOrCode or "configured"
            return product
        end
        for variantKey, row in pairs(data.unlockedShopItems) do
            if type(row) == "table" then
                row.variantKey = tostring(row.variantKey or variantKey)
                local id = productIdFor(row, "unlocked", request)
                if tostring(productId or "") == id or tostring(productId or "") == row.variantKey then
                    return {
                        id = id,
                        source = "unlocked",
                        variantKey = row.variantKey,
                        hidden = row.hidden == true,
                        label = row.label,
                        price = row.buyPrice,
                        items = {
                            {
                                fullType = row.fullType,
                                worldSprite = row.worldSprite,
                                count = 1,
                            },
                        },
                    }
                end
            end
        end
        return nil, sourceOrCode or "productMissing"
    end

    local function listItem(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("list", stableToken(request.itemId), request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local called, item, code = callPort(inventory.resolve, request.actor, request.itemId, request)
        if not called or type(item) ~= "table" then
            return finish(id, makeResult(false, called and (code or "itemMissing") or "portError", nil, request), request)
        end
        local allowed, allowedCode = validItems({ item }, "list", request)
        if not allowed then return finish(id, makeResult(false, allowedCode, nil, request), request) end
        local variantKey = keyFor(item.fullType, item.worldSprite, request)
        if not variantKey then return finish(id, makeResult(false, "variantInvalid", nil, request), request) end
        local configuredCall, configured = callPort(config.isConfigured, variantKey, request)
        if not configuredCall then return finish(id, makeResult(false, "portError", { stage = "configured" }, request), request) end
        if configured == true then
            return finish(id, makeResult(true, "configuredAlreadyListed", { variantKey = variantKey }, request), request)
        end
        local existing = data.unlockedShopItems[variantKey]
        if existing then
            local codeValue = existing.hidden == true and "hiddenAlreadyListed" or "alreadyListed"
            return finish(id, makeResult(true, codeValue, { variantKey = variantKey }, request), request)
        end
        local priceCalled, price = callPort(config.listingPrice, request.actor, item, request)
        price = priceCalled and math.max(0, integer(price, -1)) or -1
        if price < 0 then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local paymentReceipt
        if price > 0 then
            local chargeCalled, paid, receiptOrCode = callPort(wallet.charge, request.actor, price, request)
            if not chargeCalled or paid ~= true or receiptOrCode == nil then
                return finish(id, makeResult(false, chargeCalled and (receiptOrCode or "insufficientFunds") or "portError", nil, request), request)
            end
            paymentReceipt = receiptOrCode
        end
        local before = copy(data)
        local nowCalled, now = callPort(clock.nowHours, request)
        data.unlockedShopItems[variantKey] = {
            fullType = item.fullType,
            worldSprite = item.worldSprite,
            variantKey = variantKey,
            label = item.label,
            sellPrice = item.sellPrice,
            buyPrice = item.buyPrice,
            categoryKey = item.categoryKey,
            hidden = false,
            unlockedAt = nowCalled and now or nil,
        }
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local refunded = true
            if paymentReceipt then
                local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                refunded = refundCalled and value ~= false
            end
            local restored = save(request.actor, before, request)
            return finish(id, makeResult(false, refunded and restored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        if price > 0 then
            local counted, countCode = incrementMetric(
                request.actor, { spentPoints = price }, request)
            if not counted then
                local refunded = true
                if paymentReceipt then
                    local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                    refunded = refundCalled and value ~= false
                end
                local restored = save(request.actor, before, request)
                return finish(id, makeResult(false,
                    refunded and restored and countCode or "rollbackIncomplete", nil, request), request)
            end
        end
        return finish(id, makeResult(true, "listed", {
            variantKey = variantKey,
            productId = productIdFor(data.unlockedShopItems[variantKey], "unlocked", request),
            cost = price,
        }, request), request)
    end

    local function changeListing(action, request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local variantKey = tostring(request.variantKey or "")
        local fingerprint = stableToken(variantKey) .. "|" .. tostring(request.hidden == true)
        local id, replay = begin(action, fingerprint, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local row = data.unlockedShopItems[variantKey]
        if type(row) ~= "table" then return finish(id, makeResult(false, "listingMissing", nil, request), request) end
        local before = copy(data)
        local code
        if action == "delete" then
            data.unlockedShopItems[variantKey] = nil
            code = "deleted"
        else
            local target = request.hidden == true
            local changed = row.hidden ~= target
            row.hidden = target
            code = changed and (target and "hidden" or "visible") or "unchanged"
        end
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restored = save(request.actor, before, request)
            return finish(id, makeResult(false, restored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, code, { variantKey = variantKey }, request), request)
    end

    local function purchase(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local quantity = math.max(1, integer(request.quantity, 1))
        local id, replay = begin("purchase", stableToken(request.productId) .. "|" .. quantity, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local product, productCode = resolveProduct(request.actor, data, request.productId, request)
        if not product then return finish(id, makeResult(false, productCode, nil, request), request) end
        if product.source == "unlocked" and product.hidden == true then
            return finish(id, makeResult(false, "productHidden", nil, request), request)
        end
        local allowed, allowedCode = validItems(product.items, "purchase", request)
        if not allowed then return finish(id, makeResult(false, allowedCode, nil, request), request) end
        local priceCalled, price = callPort(config.purchasePrice, request.actor, product, quantity, request)
        price = priceCalled and integer(price, -1) or -1
        if price < 0 then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local grantEntries = {}
        for i = 1, #product.items do
            grantEntries[#grantEntries + 1] = {
                fullType = product.items[i].fullType,
                worldSprite = product.items[i].worldSprite,
                count = math.max(1, integer(product.items[i].count, 1)) * quantity,
            }
        end
        local grantCalled, granted, grantReceiptOrCode = callPort(inventory.grant, request.actor, grantEntries, request)
        if not grantCalled or granted ~= true or grantReceiptOrCode == nil then
            return finish(id, makeResult(false, grantCalled and (grantReceiptOrCode or "grantFailed") or "portError", nil, request), request)
        end
        local grantReceipt = grantReceiptOrCode
        local paymentReceipt
        if price > 0 then
            local chargeCalled, paid, receiptOrCode = callPort(wallet.charge, request.actor, price, request)
            if not chargeCalled or paid ~= true or receiptOrCode == nil then
                local revokeCalled, revoked = callPort(inventory.revoke, request.actor, grantReceipt, request)
                local rollbackOk = revokeCalled and revoked ~= false
                return finish(id, makeResult(false,
                    rollbackOk and (chargeCalled and (receiptOrCode or "insufficientFunds") or "portError") or "rollbackIncomplete",
                    nil, request), request)
            end
            paymentReceipt = receiptOrCode
        end
        local counted, countCode = incrementMetric(request.actor, {
            spentPoints = price,
            boughtItems = quantity,
        }, request)
        if not counted then
            local refundOk = true
            if paymentReceipt then
                local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                refundOk = refundCalled and value ~= false
            end
            local revokeCalled, revoked = callPort(inventory.revoke, request.actor, grantReceipt, request)
            local rollbackOk = refundOk and revokeCalled and revoked ~= false
            return finish(id, makeResult(false,
                rollbackOk and countCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "purchased", {
            productId = request.productId,
            quantity = quantity,
            cost = price,
            items = grantEntries,
        }, request), request)
    end

    local function lottery(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local count = math.max(1, integer(request.count, 1))
        local category = tostring(request.category or "all")
        local id, replay = begin("lottery", stableToken(category) .. "|" .. count, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local candidatesCalled, configured = callPort(config.configuredCandidates, request.actor, category, request)
        if not candidatesCalled or type(configured) ~= "table" then
            return finish(id, makeResult(false, "candidateUnavailable", nil, request), request)
        end
        local candidates, seen = {}, {}
        local function addCandidate(row)
            if type(row) ~= "table" then return end
            local items = row.items or {}
            local first = items[1]
            local fullType = first and tostring(first.fullType or "") or tostring(row.fullType or "")
            if fullType == "" or seen[fullType] then return end
            local rowCategory = tostring(row.categoryKey or "normal")
            if category ~= "all" and rowCategory ~= category then return end
            local allowed = validItems(#items > 0 and items or { { fullType = fullType } }, "lottery", request)
            if not allowed then return end
            seen[fullType] = true
            candidates[#candidates + 1] = {
                fullType = fullType,
                label = row.label,
                categoryKey = rowCategory,
                items = #items > 0 and copy(items) or { { fullType = fullType, count = 1 } },
                hidden = row.hidden == true,
            }
        end
        for i = 1, #configured do addCandidate(configured[i]) end
        for variantKey, row in pairs(data.unlockedShopItems) do
            if type(row) == "table" then
                row.variantKey = tostring(row.variantKey or variantKey)
                addCandidate({
                    fullType = row.fullType,
                    label = row.label,
                    categoryKey = row.categoryKey,
                    hidden = row.hidden == true,
                    items = { { fullType = row.fullType, worldSprite = row.worldSprite, count = 1 } },
                })
            end
        end
        if #candidates == 0 then return finish(id, makeResult(false, "lotteryEmpty", nil, request), request) end
        local priceCalled, price = callPort(config.lotteryPrice, request.actor, category, count, request)
        price = priceCalled and integer(price, -1) or -1
        if price < 0 then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local selected, grantEntries = {}, {}
        for _ = 1, count do
            local randomCalled, index = callPort(random.index, #candidates, request)
            if not randomCalled then return finish(id, makeResult(false, "portError", { stage = "random" }, request), request) end
            index = math.max(1, math.min(#candidates, integer(index, 1)))
            local picked = candidates[index]
            selected[#selected + 1] = { fullType = picked.fullType, hidden = picked.hidden }
            for j = 1, #picked.items do
                grantEntries[#grantEntries + 1] = {
                    fullType = picked.items[j].fullType,
                    worldSprite = picked.items[j].worldSprite,
                    count = math.max(1, integer(picked.items[j].count, 1)),
                }
            end
        end
        local grantCalled, granted, grantReceiptOrCode = callPort(inventory.grant, request.actor, grantEntries, request)
        if not grantCalled or granted ~= true or grantReceiptOrCode == nil then
            return finish(id, makeResult(false, grantCalled and (grantReceiptOrCode or "grantFailed") or "portError", nil, request), request)
        end
        local grantReceipt = grantReceiptOrCode
        local paymentReceipt
        if price > 0 then
            local chargeCalled, paid, receiptOrCode = callPort(wallet.charge, request.actor, price, request)
            if not chargeCalled or paid ~= true or receiptOrCode == nil then
                local revokeCalled, revoked = callPort(inventory.revoke, request.actor, grantReceipt, request)
                return finish(id, makeResult(false,
                    revokeCalled and revoked ~= false and (receiptOrCode or "insufficientFunds") or "rollbackIncomplete",
                    nil, request), request)
            end
            paymentReceipt = receiptOrCode
        end
        local counted, countCode = incrementMetric(request.actor, {
            spentPoints = price,
            lotteryDraws = count,
        }, request)
        if not counted then
            local refundOk = true
            if paymentReceipt then
                local refundCalled, value = callPort(wallet.refund, request.actor, paymentReceipt, request)
                refundOk = refundCalled and value ~= false
            end
            local revokeCalled, revoked = callPort(inventory.revoke, request.actor, grantReceipt, request)
            local rollbackOk = refundOk and revokeCalled and revoked ~= false
            return finish(id, makeResult(false,
                rollbackOk and countCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "lotteryCompleted", {
            category = category,
            count = count,
            cost = price,
            selected = selected,
        }, request), request)
    end

    local function catalog(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local data, failure = load(request.actor, request)
        if not data then return failure end
        local category = tostring(request.category or "all")
        local called, configured = callPort(
            config.configuredCandidates, request.actor, category, request)
        if not called or type(configured) ~= "table" then
            return makeResult(false, called and "shopConfigUnavailable" or "portError",
                nil, request)
        end
        local products = {}
        for index = 1, #configured do
            local row = copy(configured[index])
            row.source = "configured"
            products[#products + 1] = row
        end
        for variantKey, unlocked in pairs(data.unlockedShopItems) do
            if type(unlocked) == "table" then
                local row = copy(unlocked)
                row.variantKey = tostring(row.variantKey or variantKey)
                row.id = productIdFor(row, "unlocked", request)
                row.source = "unlocked"
                if category == "all"
                    or tostring(row.categoryKey or row.group or "normal") == category
                then
                    products[#products + 1] = row
                end
            end
        end
        table.sort(products, function(left, right)
            local leftLabel = tostring(left.label or left.name or left.id or "")
            local rightLabel = tostring(right.label or right.name or right.id or "")
            if leftLabel ~= rightLabel then return leftLabel < rightLabel end
            return tostring(left.id or left.variantKey or "")
                < tostring(right.id or right.variantKey or "")
        end)
        return makeResult(true, "catalog", {
            products = products,
        }, request)
    end

    instance.public = {
        catalog = catalog,
        listItem = listItem,
        setHidden = function(request) return changeListing("visibility", request) end,
        deleteListing = function(request) return changeListing("delete", request) end,
        purchase = purchase,
        lottery = lottery,
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
