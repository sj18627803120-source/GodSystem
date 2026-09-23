GodSystemShopInflation = GodSystemShopInflation or {}

local S = GodSystemShopInflation
local MAX_SAFE = 9007199254740000
-- Runtime-only baselines must never survive disconnects or server restarts.
local sessions = setmetatable({}, { __mode = "k" })
local cleanup = setmetatable({}, { __mode = "k" })

function S.observeConfig(root, config)
    local on = config.EnableShopDynamicInflation ~= false
    root.inflationGeneration = tonumber(root.inflationGeneration) or 0
    if root.inflationEnabled ~= false and not on then
        root.inflationGeneration = root.inflationGeneration + 1
    end
    root.inflationEnabled = on
    config.ShopInflationGeneration = root.inflationGeneration
end

local function configToken(config)
    return table.concat({tostring(config.EnableShopDynamicInflation ~= false),
        tostring(config.ShopDynamicInflationPercent or 10), tostring(config.ShopDynamicInflationHours or 24),
        tostring(config.ShopInflationGeneration or 0)}, "|")
end

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return fallback or 0 end
    return math.floor(value)
end

local function enabled(config)
    return config and config.EnableShopDynamicInflation ~= false
end

local function rate(config)
    return math.max(0, math.min(100, tonumber(config and config.ShopDynamicInflationPercent) or 10)) / 100
end

local function duration(config)
    return math.max(1, integer((tonumber(config and config.ShopDynamicInflationHours) or 24) * 60, 1440))
end

function S.key(shopItem)
    if not shopItem then return nil end
    local items = shopItem.items or {}
    if #items == 1 and math.max(1, integer(items[1].count, 1)) == 1 and GodSystemShopVariants then
        return GodSystemShopVariants.getKey(items[1].fullType, items[1].worldSprite)
    end
    return "shop:" .. tostring(shopItem.id or "")
end

function S.state(data, config, worldMinute)
    if type(data) ~= "table" then return nil end
    local state = data.shopInflation
    if type(state) ~= "table" then
        state = { onlineMinute = 0, lastWorldMinute = integer(worldMinute, 0), listings = {}, quotes = {}, nextQuote = 1 }
        data.shopInflation = state
    end
    state.onlineMinute = math.max(0, integer(state.onlineMinute, 0))
    state.lastWorldMinute = integer(state.lastWorldMinute, integer(worldMinute, 0))
    state.listings = type(state.listings) == "table" and state.listings or {}
    state.quotes = type(state.quotes) == "table" and state.quotes or {}
    state.nextQuote = math.max(1, integer(state.nextQuote, 1))
    local generation = config and config.ShopInflationGeneration or 0
    if state.generation ~= generation or (not enabled(config) and state.enabled ~= false) then
        -- The feature is configured off: discard, rather than maintain, old layers.
        state.listings, state.quotes = {}, {}
        cleanup[data] = nil
    end
    state.generation, state.enabled = generation, enabled(config)
    return state
end

function S.advance(data, config, worldMinute, online)
    local state = S.state(data, config, worldMinute)
    if not state then return nil end
    worldMinute = integer(worldMinute, state.lastWorldMinute)
    local previous = sessions[data]
    if online and previous and enabled(config) and worldMinute > previous then
        state.onlineMinute = math.min(MAX_SAFE, state.onlineMinute + (worldMinute - previous))
    end
    if online then sessions[data] = worldMinute end
    state.lastWorldMinute = worldMinute
    return state
end

function S.pause(data, config, worldMinute)
    sessions[data] = nil
    return S.advance(data, config, worldMinute, false)
end

local function compact(state, key)
    local row = state.listings[key]
    if type(row) ~= "table" then return 0, nil end
    local kept, layers, nextExpiry = {}, 0, nil
    for i = 1, #row do
        local bucket = row[i]
        local expiry = integer(bucket and bucket.expiryMinute, 0)
        local count = math.max(0, integer(bucket and bucket.count, 0))
        if expiry > state.onlineMinute and count > 0 then
            kept[#kept + 1] = { expiryMinute = expiry, count = count }
            layers = layers + count
            if not nextExpiry or expiry < nextExpiry then nextExpiry = expiry end
        end
    end
    if #kept == 0 then state.listings[key] = nil else state.listings[key] = kept end
    return layers, nextExpiry
end

local function cleanupIndex(data)
    local index = cleanup[data]
    if not index then
        index = {keys={}, known={}, cursor=1}
        for key in pairs(data.shopInflation.listings) do
            index.keys[#index.keys+1]=key; index.known[key]=true
        end
        cleanup[data]=index
    end
    return index
end

function S.sweep(data, budget)
    if not data or not data.shopInflation then return end
    local index = cleanupIndex(data)
    for i=1,math.min(8, budget or 8) do
        if #index.keys==0 then return end
        if index.cursor>#index.keys then index.cursor=1 end
        local key=index.keys[index.cursor]
        compact(data.shopInflation,key)
        if not data.shopInflation.listings[key] then
            index.known[key]=nil
            index.keys[index.cursor]=index.keys[#index.keys]
            index.keys[#index.keys]=nil
        else index.cursor=index.cursor+1 end
    end
end

function S.quote(data, config, worldMinute, key, basePrice, quantity, online)
    local state = online == nil and S.state(data, config, worldMinute) or S.advance(data, config, worldMinute, online == true)
    if not state then return nil, "ShopQuoteChanged" end
    quantity = tonumber(quantity) or 1
    basePrice = tonumber(basePrice)
    if quantity ~= quantity or quantity < 1 or quantity > 1000 or quantity ~= math.floor(quantity)
        or not basePrice or basePrice ~= basePrice or basePrice < 0 or basePrice > MAX_SAFE then return nil, "ShopPriceLimit" end
    -- The request budget above does not cap accumulated gameplay layers.
    if not enabled(config) then
        if math.ceil(basePrice) > math.floor(MAX_SAFE / quantity) then return nil, "ShopPriceLimit" end
        return { total = math.ceil(basePrice) * quantity, basePrice = basePrice, layers = 0, nextExpiryMinute = nil,
            onlineMinute = state.onlineMinute, durationMinutes = duration(config) }
    end
    if not key or key == "" then return nil, "ShopQuoteChanged" end
    local layers, nextExpiry = compact(state, key)
    if layers > MAX_SAFE - quantity then return nil, "ShopPriceLimit" end
    local total = 0
    local multiplier = rate(config)
    for i = 0, quantity - 1 do
        -- Lua doubles can represent an exact 110 as 110.00000000000001 after
        -- applying a decimal sandbox rate. Do not turn that into 111.
        local price = math.ceil((basePrice * (1 + (layers + i) * multiplier)) - 0.000000001)
        if price < 0 or price > MAX_SAFE or total > MAX_SAFE - price then return nil, "ShopPriceLimit" end
        total = total + price
    end
    return { total = total, basePrice = basePrice, layers = layers, nextExpiryMinute = nextExpiry,
        onlineMinute = state.onlineMinute, durationMinutes = duration(config) }
end

function S.commit(data, config, worldMinute, key, quantity, online)
    local state = S.advance(data, config, worldMinute, online == true)
    if not state or not enabled(config) then return true end
    quantity = math.max(1, integer(quantity, 1))
    if not key or key == "" or quantity > MAX_SAFE then return false end
    local layers = compact(state, key)
    if layers > MAX_SAFE - quantity then return false end
    -- Purchases are sampled at whole minutes: expire at the following boundary,
    -- never up to one minute earlier than the purchased duration.
    local expiry = state.onlineMinute + duration(config) + 1
    local row = state.listings[key] or {}
    local index = cleanupIndex(data)
    if not index.known[key] then index.keys[#index.keys+1]=key; index.known[key]=true end
    for i = 1, #row do
        if row[i].expiryMinute == expiry then
            if row[i].count > MAX_SAFE - quantity then return false end
            row[i].count = row[i].count + quantity
            state.listings[key] = row
            return true
        end
    end
    row[#row + 1] = { expiryMinute = expiry, count = quantity }
    state.listings[key] = row
    return true
end

function S.issueQuote(data, config, worldMinute, key, basePrice, quantity, online)
    local quote, reason = S.quote(data, config, worldMinute, key, basePrice, quantity, online)
    if not quote then return nil, reason end
    quote.configVersion = configToken(config)
    local state = S.state(data, config, worldMinute)
    if state.nextQuote >= MAX_SAFE then return nil, "ShopPriceLimit" end
    local id = tostring(state.nextQuote)
    state.nextQuote = state.nextQuote + 1
    -- One outstanding confirmation per account; repeated browsing cannot grow a save.
    state.quotes = {}
    state.quotes[id] = { key = key, quantity = quantity, total = quote.total, basePrice = quote.basePrice,
        configToken = configToken(config), layers = quote.layers, onlineMinute = quote.onlineMinute, expiresMinute = quote.onlineMinute + 2 }
    return quote, id
end

function S.consumeQuote(data, config, worldMinute, quoteId, key, basePrice, quantity, online)
    local state = S.advance(data, config, worldMinute, online == true)
    local saved = state and state.quotes[tostring(quoteId or "")]
    if not saved or saved.key ~= key or saved.quantity ~= quantity or saved.basePrice ~= basePrice
        or saved.configToken ~= configToken(config)
        or saved.expiresMinute < state.onlineMinute then return nil, "ShopQuoteChanged" end
    local quote, reason = S.quote(data, config, worldMinute, key, basePrice, quantity, false)
    if not quote or quote.total ~= saved.total or quote.layers ~= saved.layers then return nil, reason or "ShopQuoteChanged" end
    state.quotes[tostring(quoteId)] = nil
    return quote
end

function S.describe(data, config, worldMinute, key, basePrice, online)
    return S.quote(data, config, worldMinute, key, basePrice, 1, online)
end

return S
