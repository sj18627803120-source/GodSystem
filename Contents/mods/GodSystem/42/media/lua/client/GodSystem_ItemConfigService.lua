require "GodSystem_ItemCatalog"

local service = GodSystemApp.getService("itemConfig") or GodSystemApp.createService("itemConfig")
service.MAX_RESULTS = 8
local state = { search = "" }

local function isMultiplayer()
    return isClient and isClient() == true
end

local function result(ok, code, args, data, operationId)
    return { ok = ok == true, code = code, args = args or {}, data = data or {}, operationId = operationId }
end

local function selectedDetails(row, authoritative, ready)
    local detail, quote = GodSystemApp.services.runtime.getEconomyQuoteDetail(row.fullType, nil, true)
    local hasAuthoritativeDetails = type(authoritative) == "table"
    authoritative = type(authoritative) == "table" and authoritative or {}
    local override, variantOverride
    if hasAuthoritativeDetails then
        override = authoritative.override
        variantOverride = authoritative.variantOverride
    else
        override = GodSystemItemConfig.getItemOverride(row.fullType)
        if row.variantKey then variantOverride = GodSystemItemConfig.getShopVariantOverride(row.variantKey) end
    end
    return {
        key = tostring(row.key or row.variantKey or row.fullType or ""),
        fullType = tostring(row.fullType or ""),
        label = tostring(row.label or row.fullType or ""),
        variantKey = row.variantKey,
        worldSprite = row.worldSprite,
        detail = tostring(detail or ""),
        category = quote.category,
        quote = quote,
        override = override,
        variantOverride = variantOverride,
        shopMode = row.variantKey and GodSystemItemConfig.getShopVariantMode(row.variantKey, row.fullType)
            or GodSystemItemConfig.getShopMode(row.fullType),
        eligible = quote.eligible == true,
        ready = ready == true,
        revision = authoritative.revision or (GodSystemItemConfig.Current or {}).economyRevision or 1,
    }
end

local function emptyPage()
    return { rows = {}, total = 0, page = 1, pageCount = 1, complete = false, built = 0 }
end

local function viewModel()
    local allowed = GodSystemApp.services.runtime.isItemConfigAllowed()
    local catalog = GodSystemItemCatalog.getShared()
    if not allowed then
        return {
            allowed = false,
            search = state.search,
            page = emptyPage(),
            details = GodSystemApp.services.runtime.itemConfigDetails or {},
        }
    end
    if not catalog.complete then catalog:buildStep(64) end
    local page = catalog:query(state.search, 1, service.MAX_RESULTS)
    return {
        allowed = true,
        search = state.search,
        page = page,
        details = GodSystemApp.services.runtime.itemConfigDetails or {},
    }
end

service:setViewModelProvider(function()
    return viewModel()
end)

service:setExecutor(function(playerNum, intent, payload, callback)
    intent = tostring(intent or "")
    payload = type(payload) == "table" and payload or {}
    if not GodSystemApp.services.runtime.isItemConfigAllowed() then
        local denied = result(false, "AdminRequired")
        if callback then callback(denied) end
        return nil
    end
    if intent == "catalogQuery" then
        state.search = tostring(payload.search or ""):match("^%s*(.-)%s*$") or ""
        if callback then callback(result(true, "ItemCatalogUpdated", nil, viewModel())) end
        return "catalog"
    elseif intent == "detailsGet" then
        local key = tostring(payload.variantKey or payload.fullType or "")
        if key == "" or tostring(payload.fullType or "") == "" then
            if callback then callback(result(false, "ItemFullTypeRequired")) end
            return nil
        end
        GodSystemApp.services.runtime.itemConfigDetails = GodSystemApp.services.runtime.itemConfigDetails or {}
        if isMultiplayer() then
            GodSystemApp.services.runtime.itemConfigDetails[key] = selectedDetails(payload, nil, false)
            local sent = GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigDetailsGet", {
                fullType = payload.fullType,
                variantKey = payload.variantKey,
            })
            if callback then callback(result(sent == true, sent and "ItemDetailsQueued" or "ItemDetailsSendFailed")) end
            return sent and "details" or nil
        end
        GodSystemApp.services.runtime.itemConfigDetails[key] = selectedDetails(payload, nil, true)
        if callback then callback(result(true, "ItemDetailsReady", nil, GodSystemApp.services.runtime.itemConfigDetails[key])) end
        return "details"
    elseif intent == "set" then
        local sent = GodSystemApp.services.runtime.saveEconomyOverride(
            payload.fullType, payload.override, payload.variantKey, payload.worldSprite, payload.shopMode
        )
        if sent and not isMultiplayer() then service:handleChanged() end
        if callback then callback(result(sent == true, sent and "ItemOverrideQueued" or "ItemOverrideInvalid")) end
        return sent and "set" or nil
    elseif intent == "clear" then
        local sent = GodSystemApp.services.runtime.clearEconomyOverride(payload.fullType, payload.variantKey)
        if sent and not isMultiplayer() then service:handleChanged() end
        if callback then callback(result(sent == true, sent and "ItemOverrideClearQueued" or "ItemFullTypeRequired")) end
        return sent and "clear" or nil
    end
    if callback then callback(result(false, "ServiceIntentUnsupported")) end
    return nil
end)

function service:handleChanged()
    if GodSystemInventoryContext and GodSystemInventoryContext.invalidateEconomyCache then
        GodSystemInventoryContext.invalidateEconomyCache()
    end
    service:publish(0, "changed", { revision = (GodSystemItemConfig.Current or {}).economyRevision or 1 })
end

function service:handleDetails(authoritative)
    authoritative = type(authoritative) == "table" and authoritative or {}
    local key = tostring(authoritative.variantKey ~= "" and authoritative.variantKey or authoritative.fullType or "")
    if key == "" then return end
    GodSystemApp.services.runtime.itemConfigDetails = GodSystemApp.services.runtime.itemConfigDetails or {}
    local pending = GodSystemApp.services.runtime.itemConfigDetails[key] or {}
    pending.fullType = authoritative.fullType or pending.fullType
    pending.variantKey = authoritative.variantKey ~= "" and authoritative.variantKey or pending.variantKey
    GodSystemApp.services.runtime.itemConfigDetails[key] = selectedDetails(pending, authoritative, true)
    service:publish(0, "detailsChanged", { key = key, revision = authoritative.revision })
end

GodSystemItemCatalog.subscribe(function(catalog, built)
    if catalog == GodSystemItemCatalog.Shared then
        service:publish(0, "catalogChanged", { built = built, complete = catalog.complete == true })
    end
end)

return service
