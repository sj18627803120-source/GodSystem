-- MP catalogue transport cache.  It is intentionally separate from the
-- persisted player table: a missing chunk means "not loaded", never "not
-- listed".  SP continues to read its local listing table directly.
GodSystemShopListingStore = GodSystemShopListingStore or {}
local Store = GodSystemShopListingStore
Store.rows, Store.queue = Store.rows or {}, Store.queue or {}
Store.revision, Store.count, Store.cursor = Store.revision or 0, Store.count or 0, Store.cursor
Store.ready, Store.pending = Store.ready == true, Store.pending == true
Store.prices, Store.pricePending = Store.prices or {}, Store.pricePending == true
Store.requestSerial = Store.requestSerial or 0

local function multiplayer()
    return GodSystemNetwork and GodSystemNetwork.isMultiplayer == true
end

local function nowMs()
    return GodSystemShopCatalog and GodSystemShopCatalog.nowMs and GodSystemShopCatalog.nowMs()
        or getTimestampMs and getTimestampMs() or 0
end

function Store.reset(revision, count)
    Store.rows, Store.buildRows, Store.queue, Store.cursor = {}, {}, {}, nil
    Store.nextCursor, Store.done, Store.pendingId, Store.pendingAtMs = nil, false, nil, nil
    Store.prices, Store.pricePending, Store.pricePendingId, Store.pricePendingAtMs = {}, false, nil, nil
    Store.revision, Store.count = math.max(0, tonumber(revision) or 0), math.max(0, tonumber(count) or 0)
    Store.ready, Store.pending = Store.count == 0, false
end

function Store.resetSession()
    Store.reset(0, 0)
    Store.ready = false
end

function Store.onState(data)
    if not multiplayer() or type(data) ~= "table" then return end
    local revision, count = math.max(0, tonumber(data.shopCatalogRevision) or 0), math.max(0, tonumber(data.shopCatalogCount) or 0)
    if revision ~= Store.revision or count ~= Store.count then Store.reset(revision, count) end
end

function Store.rowsFor(data)
    if not multiplayer() then return type(data) == "table" and data.unlockedShopItems or {}, true end
    return Store.rows, Store.ready
end

function Store.request()
    if not multiplayer() or Store.ready or Store.pending or not GodSystemNetwork or not GodSystemNetwork.send then return end
    Store.requestSerial = Store.requestSerial + 1
    Store.pendingId = tostring(Store.requestSerial)
    Store.pending = true
    Store.pendingAtMs = nowMs()
    if GodSystemNetwork.send("shopCatalogChunk", { revision = Store.revision, cursor = Store.cursor, requestId = Store.pendingId }) == false then
        Store.pending, Store.pendingId, Store.pendingAtMs = false, nil, nil
    end
end

function Store.receive(payload)
    if type(payload) ~= "table" or not Store.pending
        or tostring(payload.requestId or "") ~= Store.pendingId then return false end
    Store.pending = false
    Store.pendingId, Store.pendingAtMs = nil, nil
    if payload.reset == true then Store.reset(payload.revision, payload.total); return true end
    if tonumber(payload.revision) ~= Store.revision then return false end
    for i = 1, #(payload.items or {}) do Store.queue[#Store.queue + 1] = payload.items[i] end
    Store.nextCursor, Store.done = payload.nextCursor, payload.done == true
    return true
end

function Store.requestPrices(rows)
    if Store.pricePending and Store.pricePendingAtMs and nowMs() - Store.pricePendingAtMs >= 10000 then
        Store.pricePending, Store.pricePendingId, Store.pricePendingAtMs = false, nil, nil
    end
    if not multiplayer() or Store.pricePending or type(rows) ~= "table" or not GodSystemNetwork or not GodSystemNetwork.send then return end
    local ids = {}
    for i = 1, math.min(20, #rows) do if rows[i] and rows[i].item and rows[i].item.id then ids[#ids + 1] = rows[i].item.id end end
    if #ids == 0 then return end
    Store.pricePending = true
    Store.requestSerial = Store.requestSerial + 1
    Store.pricePendingId = tostring(Store.requestSerial)
    Store.pricePendingAtMs = nowMs()
    if GodSystemNetwork.send("shopPagePrices", { ids = ids, requestId = Store.pricePendingId }) == false then
        Store.pricePending, Store.pricePendingId, Store.pricePendingAtMs = false, nil, nil
    end
end

function Store.receivePrices(payload)
    if not Store.pricePending or tostring(payload and payload.requestId or "") ~= Store.pricePendingId then return false end
    Store.pricePending, Store.pricePendingId, Store.pricePendingAtMs = false, nil, nil
    for i = 1, #((payload and payload.rows) or {}) do
        local row = payload.rows[i]
        if row and row.id then Store.prices[tostring(row.id)] = row end
    end
    return true
end

function Store.step(limit, budgetMs)
    if not multiplayer() or Store.ready then return end
    local started, done = (GodSystemShopCatalog and GodSystemShopCatalog.nowMs and GodSystemShopCatalog.nowMs()) or 0, 0
    limit, budgetMs = math.max(1, math.min(50, tonumber(limit) or 50)), tonumber(budgetMs) or 2
    while #Store.queue > 0 and done < limit do
        if GodSystemShopCatalog and GodSystemShopCatalog.nowMs and GodSystemShopCatalog.nowMs() - started >= budgetMs then break end
        local row = table.remove(Store.queue, 1)
        local key = tostring(row and row.variantKey or "")
        if key ~= "" then Store.buildRows[key] = row end
        done = done + 1
    end
    if #Store.queue == 0 and Store.done then Store.rows, Store.buildRows, Store.ready = Store.buildRows, {}, true
    elseif #Store.queue == 0 then
        if Store.pending and Store.pendingAtMs and nowMs() - Store.pendingAtMs >= 10000 then
            Store.pending, Store.pendingId, Store.pendingAtMs = false, nil, nil
        end
        if not Store.pending then Store.cursor = Store.nextCursor; Store.request() end
    end
end

return Store
