-- Runtime-only marketplace presentation cache.  The server remains the
-- authority for availability, prices and settlement; this only avoids doing
-- the same catalogue work again for every page turn or text keystroke.
GodSystemShopCatalog = GodSystemShopCatalog or {}

local Catalog = GodSystemShopCatalog
Catalog.MAX_STEP_RECORDS = 50
Catalog.MAX_STEP_MS = 2
Catalog.snapshot = Catalog.snapshot or nil
Catalog.builder = Catalog.builder or nil
Catalog.generation = tonumber(Catalog.generation) or 0
Catalog.diagnostics = Catalog.diagnostics or { builds = 0, records = 0, pages = 0, filters = 0, buildMs = 0, filterMs = 0 }

local function diagnosticEnabled()
    return GodSystemConfig and GodSystemConfig.EnablePerformanceDiagnostics == true
end

local function note(key, value)
    if diagnosticEnabled() then Catalog.diagnostics[key] = (Catalog.diagnostics[key] or 0) + (value or 1) end
end
Catalog.note = note

local function nowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and value then return tonumber(value) or 0 end
    end
    return math.floor(((os and os.clock and os.clock()) or 0) * 1000)
end
Catalog.nowMs = nowMs
function Catalog.flushDiagnostics()
    if not diagnosticEnabled() then return end
    local now = nowMs()
    if Catalog.lastDiagnosticAt and now - Catalog.lastDiagnosticAt < 30000 then return end
    Catalog.lastDiagnosticAt = now
    local keys, fields = {}, {}
    for key in pairs(Catalog.diagnostics) do keys[#keys + 1] = key end
    table.sort(keys)
    for _,key in ipairs(keys) do fields[#fields + 1] = key .. "=" .. tostring(Catalog.diagnostics[key]) end
    print("[GodSystem performance] " .. table.concat(fields, " "))
end

local function keyFor(item)
    if GodSystemShopInflation and GodSystemShopInflation.key then
        return tostring(GodSystemShopInflation.key(item) or "")
    end
    return tostring(item and (item.variantKey or item.id) or "")
end

local function rowLess(a, b)
    if a.sortLabel == b.sortLabel then return a.key < b.key end
    return a.sortLabel < b.sortLabel
end

local function text(value)
    return tostring(value or ""):lower()
end

local function createSources(data)
    local itemConfig = GodSystemItemConfig or {}
    -- Capture iterators, not a synchronously materialized copy of the catalogue.
    local function source(kind, values)
        local iterator, state, key = pairs(values or {})
        return { kind = kind, iterator = iterator, state = state, key = key }
    end
    local unlocked = data and data.unlockedShopItems
    local ready = true
    if GodSystemShopListingStore then unlocked, ready = GodSystemShopListingStore.rowsFor(data) end
    if not ready then return nil end
    return { cursor = 1, stage = 1, blocks = {}, seen = {}, categories = {}, categoryMap = {}, startedMs = nowMs(),
        generation = Catalog.generation, dataRef = data, sources = {
            source("configured", GodSystemConfig.ShopItems), source("unlocked", unlocked),
            source("forced", itemConfig.getItemOverrides and itemConfig.getItemOverrides()),
            source("forcedVariant", itemConfig.getShopVariantOverrides and itemConfig.getShopVariantOverrides()),
        } }
end

local function nextSource(builder)
    while builder.stage <= #builder.sources do
        local source = builder.sources[builder.stage]
        local key, value = source.iterator(source.state, source.key)
        source.key = key
        if key ~= nil then
            if source.kind == "configured" then return { kind = source.kind, item = value } end
            return { kind = source.kind, item = { variantKey = key, fullType = key, row = value, override = value } }
        end
        builder.stage = builder.stage + 1
    end
    return nil
end

local function materialize(source)
    local runtime = GodSystemApp.services.runtime
    local itemConfig = GodSystemItemConfig or {}
    local kind, value = source.kind, source.item
    if kind == "configured" then
        local feature = not value.featureKey or not GodSystemRuntimeConfig or not GodSystemRuntimeConfig.isFeatureEnabled or GodSystemRuntimeConfig.isFeatureEnabled(value.featureKey) ~= false
        local available, _, _, missing = runtime.shopItemIsAvailable(value)
        if feature and available and (not missing or #missing == 0) then return value end
        return nil
    end
    if kind == "unlocked" then
        local stored = value.row
        if type(stored) ~= "table" then return nil end
        local fullType = tostring(stored.fullType or value.variantKey or "")
        local variantKey = tostring(stored.variantKey or value.variantKey or "")
        local mode = itemConfig.getShopVariantMode and itemConfig.getShopVariantMode(variantKey, fullType) or "auto"
        if stored.hidden == true or mode == "disabled" or mode == "forced" or not runtime.itemExists(fullType) then return nil end
        return { id = "unlocked_" .. variantKey, fullType = fullType, worldSprite = stored.worldSprite, variantKey = variantKey,
            label = runtime.getUnlockedShopLabel(fullType, stored), group = "unlocked", price = runtime.getAutoShopBuyPriceForItem(fullType, stored.sellPrice or 1),
            description = "Unlocked by recycling.", items = { { fullType = fullType, worldSprite = stored.worldSprite, count = 1 } }, unlocked = true }
    end
    if kind == "forced" then
        if not value.override or value.override.shopMode ~= "forced" then return nil end
        local fullType = tostring(value.fullType or "")
        if fullType == "" or fullType == "Moveables.Moveable" or not runtime.itemExists(fullType)
            or (GodSystemItemEligibility and GodSystemItemEligibility.isEconomicItemAllowed and not GodSystemItemEligibility.isEconomicItemAllowed(fullType, "shop")) then return nil end
        return { id = "admin:" .. fullType, fullType = fullType, variantKey = fullType, label = runtime.getItemDisplayName(fullType), group = "admin",
            items = { { fullType = fullType, count = 1 } }, adminForced = true }
    end
    local override, variantKey = value.override, tostring(value.variantKey or "")
    local fullType = override and tostring(override.fullType or "") or ""
    if not itemConfig.getShopVariantMode or itemConfig.getShopVariantMode(variantKey, fullType) ~= "forced" then return nil end
    if fullType == "" or not runtime.itemExists(fullType) or (GodSystemItemEligibility and GodSystemItemEligibility.isEconomicItemAllowed and not GodSystemItemEligibility.isEconomicItemAllowed(fullType, "shop")) then return nil end
    return { id = "admin:" .. variantKey, fullType = fullType, worldSprite = override.worldSprite, variantKey = variantKey,
        label = runtime.getItemDisplayName(fullType), group = "admin", items = { { fullType = fullType, worldSprite = override.worldSprite, count = 1 } }, adminForced = true }
end

local function buildRow(builder, source)
    local item = materialize(source)
    if not item then return nil end
    local key = keyFor(item)
    if key == "" or builder.seen[key] then return nil end
    builder.seen[key] = true
    local category = GodSystemApp.services.runtime.getShopPrimaryCategory(item)
    local label = GodSystemApp.services.runtime.getShopLabel(item)
    if not builder.categoryMap[category.key] then
        builder.categoryMap[category.key] = true; builder.categories[#builder.categories + 1] = category
    end
    return { item = item, key = key, category = category, label = label, sortLabel = text(label),
        searchText = text(label .. " " .. tostring(item.fullType or "") .. " " .. tostring(category.label or "") .. " " .. tostring(category.key or "") .. " " .. tostring(item.group or "")),
        order = builder.cursor }
end

function Catalog.invalidate(reason)
    Catalog.generation = Catalog.generation + 1
    Catalog.builder = nil
    Catalog.lastReason = reason or "changed"
end

function Catalog.clear()
    Catalog.snapshot, Catalog.builder = nil, nil
    Catalog.generation = Catalog.generation + 1
    if GodSystemTerminalDesign and GodSystemTerminalDesign.clearIcons then GodSystemTerminalDesign.clearIcons() end
end

function Catalog.invalidatePrices()
    Catalog.priceGeneration = (Catalog.priceGeneration or 0) + 1
end
function Catalog.invalidatePreferences()
    Catalog.preferenceGeneration = (Catalog.preferenceGeneration or 0) + 1
end

function Catalog.cancelBuild()
    Catalog.builder = nil
end

function Catalog.ensure()
    local data = GodSystemApp.services.runtime.getData()
    -- MP replaces the projected data table on every packet. Business revisions,
    -- not table identity, determine whether its directory has changed.
    if not (GodSystemNetwork and GodSystemNetwork.isMultiplayer) then
        if (Catalog.snapshot and Catalog.snapshot.dataRef ~= data) or (Catalog.builder and Catalog.builder.dataRef ~= data) then Catalog.clear() end
    end
    if Catalog.snapshot and Catalog.snapshot.generation == Catalog.generation then return Catalog.snapshot end
    if not Catalog.builder or Catalog.builder.generation ~= Catalog.generation then
        Catalog.builder = createSources(data)
        if not Catalog.builder and GodSystemShopListingStore then GodSystemShopListingStore.request() end
    end
    return nil
end

function Catalog.isBuilding()
    return Catalog.builder ~= nil and not (Catalog.snapshot and Catalog.snapshot.generation == Catalog.generation)
end

function Catalog.progress()
    local builder = Catalog.builder
    if not builder then return 1, 0, 0 end
    local processed = builder.cursor - 1
    return builder.exhausted and 1 or 0, processed, builder.exhausted and processed or nil
end

local function complete(builder)
    local rows, categories = builder.blocks[1] or {}, builder.categories
    table.sort(categories, function(a, b) return tostring(a.label) < tostring(b.label) end)
    Catalog.snapshot = { generation = builder.generation, dataRef = builder.dataRef, rows = rows, categories = categories, filters = {}, builtAtMs = nowMs() }
    Catalog.builder = nil
    note("builds")
    note("buildMs", math.max(0, nowMs() - builder.startedMs))
end

local function beginMerge(builder)
    builder.merging, builder.mergeIndex, builder.nextBlocks, builder.mergePair = true, 1, {}, nil
end

local function mergeStep(builder, maxRecords, budgetMs, started)
    local processed = 0
    while processed < maxRecords and nowMs() - started < budgetMs do
        local pair = builder.mergePair
        if not pair then
            local left = builder.blocks[builder.mergeIndex]
            local right = builder.blocks[builder.mergeIndex + 1]
            if not left then
                if #builder.nextBlocks == 1 then builder.blocks = builder.nextBlocks; complete(builder); return true, processed end
                builder.blocks, builder.nextBlocks, builder.mergeIndex = builder.nextBlocks, {}, 1
                pair = nil
            elseif not right then
                builder.nextBlocks[#builder.nextBlocks + 1] = left
                builder.mergeIndex = builder.mergeIndex + 2
            else
                pair = { left = left, right = right, li = 1, ri = 1, result = {} }
                builder.mergePair = pair
            end
        end
        if pair then
            if pair.li <= #pair.left and pair.ri <= #pair.right then
                if rowLess(pair.left[pair.li], pair.right[pair.ri]) then pair.result[#pair.result + 1] = pair.left[pair.li]; pair.li = pair.li + 1
                else pair.result[#pair.result + 1] = pair.right[pair.ri]; pair.ri = pair.ri + 1 end
            elseif pair.li <= #pair.left then pair.result[#pair.result + 1] = pair.left[pair.li]; pair.li = pair.li + 1
            elseif pair.ri <= #pair.right then pair.result[#pair.result + 1] = pair.right[pair.ri]; pair.ri = pair.ri + 1
            else
                builder.nextBlocks[#builder.nextBlocks + 1] = pair.result
                builder.mergeIndex, builder.mergePair = builder.mergeIndex + 2, nil
            end
            processed = processed + 1
        end
    end
    return false, processed
end

function Catalog.step(limit, budgetMs)
    local builder = Catalog.builder
    if not builder or builder.generation ~= Catalog.generation then return false end
    local started = nowMs()
    local maxRecords = math.max(1, math.min(Catalog.MAX_STEP_RECORDS, math.floor(tonumber(limit) or Catalog.MAX_STEP_RECORDS)))
    local maxMs = math.max(1, tonumber(budgetMs) or Catalog.MAX_STEP_MS)
    if builder.merging then
        local completed, processed = mergeStep(builder, maxRecords, maxMs, started)
        note("records", processed)
        return completed
    end
    local batch, processed = {}, 0
    while not builder.exhausted and processed < maxRecords do
        local source = nextSource(builder)
        if not source then builder.exhausted = true; break end
        builder.cursor = builder.cursor + 1
        local row = buildRow(builder, source)
        if row then batch[#batch + 1] = row end
        processed = processed + 1
        if nowMs() - started >= maxMs then break end
    end
    note("records", processed)
    if #batch > 0 then table.sort(batch, rowLess); builder.blocks[#builder.blocks + 1] = batch end
    if builder.exhausted then
        if #builder.blocks <= 1 then complete(builder); return true end
        beginMerge(builder)
    end
    return false
end

function Catalog.view(categoryKey, searchText)
    local snapshot = Catalog.ensure()
    if not snapshot then return nil end
    categoryKey, searchText = tostring(categoryKey or "all"), text(searchText)
    local signature = categoryKey .. "\n" .. searchText .. "\n" .. tostring(Catalog.preferenceGeneration or 0)
    local cached = snapshot.filters[signature]
    if cached then return cached end
    local started = nowMs()
    local ui = (GodSystemApp.services.runtime.getData() or {}).ui or {}
    local favorites, recent = ui.shopFavorites or {}, ui.shopRecent or {}
    local ranks = {}
    for i = 1, #recent do ranks[tostring(recent[i])] = i end
    local result = {}
    for i = 1, #snapshot.rows do
        local row = snapshot.rows[i]
        if (categoryKey == "all" or row.category.key == categoryKey) and (searchText == "" or string.find(row.searchText, searchText, 1, true)) then
            row.favoriteRank = favorites[row.key] == true and 1 or 0
            row.recentRank = ranks[row.key] or 999999
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if a.favoriteRank ~= b.favoriteRank then return a.favoriteRank > b.favoriteRank end
        if a.recentRank ~= b.recentRank then return a.recentRank < b.recentRank end
        return rowLess(a, b)
    end)
    -- Keep only the current filter. Search text and preference combinations are
    -- unbounded user input and must not retain an array for every past query.
    snapshot.filters = {}
    snapshot.filters[signature] = result
    note("filters")
    note("filterMs", math.max(0, nowMs() - started))
    return result
end

function Catalog.price(row)
    if not row then return 0, nil end
    local now = nowMs()
    if row.priceGeneration == Catalog.priceGeneration and row.priceAtMs and now - row.priceAtMs < 1000 then return row.currentPrice, row.quote end
    local runtime = GodSystemApp.services.runtime
    if GodSystemShopListingStore and GodSystemNetwork and GodSystemNetwork.isMultiplayer then
        local cached = GodSystemShopListingStore.prices[tostring(row.item and row.item.id or "")]
        if cached then
            row.quote = { total = cached.price, basePrice = cached.basePrice, layers = cached.layers,
                nextExpiryMinute = cached.nextExpiryMinute, onlineMinute = cached.onlineMinute }
            row.currentPrice, row.priceAtMs, row.priceGeneration = cached.price, now, Catalog.priceGeneration
            return row.currentPrice, row.quote
        end
    end
    local quote = runtime.getShopInflationQuote and runtime.getShopInflationQuote(row.item, 1, nil) or nil
    local fallback = not quote and (runtime.getShopBaseUnitPrice and runtime.getShopBaseUnitPrice(row.item) or runtime.getShopItemUnitPrice and runtime.getShopItemUnitPrice(row.item) or 0) or 0
    row.quote, row.currentPrice, row.priceAtMs = quote, quote and quote.total or fallback, now
    row.priceGeneration = Catalog.priceGeneration
    return row.currentPrice, quote
end

function Catalog.requestPagePrices(rows)
    if GodSystemShopListingStore then GodSystemShopListingStore.requestPrices(rows) end
end

function Catalog.getDiagnostics()
    return Catalog.diagnostics
end

return Catalog
