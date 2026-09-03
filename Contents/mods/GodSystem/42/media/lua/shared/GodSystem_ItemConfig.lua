GodSystemItemConfig = GodSystemItemConfig or {}

local function clampNumber(value, minimum, maximum, integer)
    local number = tonumber(value)
    if number == nil then return nil end
    if number < minimum then number = minimum end
    if number > maximum then number = maximum end
    if integer then number = math.floor(number) end
    return number
end

local function sanitizeText(value, maximum)
    local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if #text > maximum then text = text:sub(1, maximum) end
    return text
end

local function copyTable(input)
    local result = {}
    if type(input) ~= "table" then return result end
    for key, value in pairs(input) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

function GodSystemItemConfig.sanitizeItemOverride(input)
    if type(input) ~= "table" then return nil end
    local result = {}
    if input.buyPrice ~= nil and tostring(input.buyPrice) ~= "" then
        result.buyPrice = clampNumber(input.buyPrice, 0, 10000000, true)
    end
    if input.sellPrice ~= nil and tostring(input.sellPrice) ~= "" then
        result.sellPrice = clampNumber(input.sellPrice, 0, 10000000, true)
    end
    if input.category ~= nil and tostring(input.category) ~= "" then
        local category = sanitizeText(input.category, 32):lower():gsub("[^a-z0-9_]+", "_")
        if category ~= "" then result.category = category end
    end
    local shopMode = tostring(input.shopMode or "auto"):lower()
    if shopMode ~= "auto" and shopMode ~= "forced" and shopMode ~= "disabled" then
        shopMode = "auto"
    end
    result.shopMode = shopMode
    if input.note ~= nil and tostring(input.note) ~= "" then
        result.note = sanitizeText(input.note, 120)
    end
    return result
end

function GodSystemItemConfig.sanitizeItemOverrides(input)
    local result = {}
    if type(input) ~= "table" then return result end
    for fullType, override in pairs(input) do
        local key = sanitizeText(fullType, 120)
        local clean = GodSystemItemConfig.sanitizeItemOverride(override)
        if key ~= "" and clean then result[key] = clean end
    end
    return result
end

function GodSystemItemConfig.sanitizeShopVariantOverride(input)
    if type(input) ~= "table" then return nil end
    local fullType = sanitizeText(input.fullType, 120)
    local worldSprite = sanitizeText(input.worldSprite, 180)
    local shopMode = tostring(input.shopMode or "auto"):lower()
    if shopMode ~= "auto" and shopMode ~= "forced" and shopMode ~= "disabled" then
        shopMode = "auto"
    end
    if fullType == "" or worldSprite == "" then return nil end
    return { fullType = fullType, worldSprite = worldSprite, shopMode = shopMode }
end

function GodSystemItemConfig.sanitizeShopVariantOverrides(input)
    local result = {}
    if type(input) ~= "table" then return result end
    for variantKey, override in pairs(input) do
        local key = sanitizeText(variantKey, 320)
        local clean = GodSystemItemConfig.sanitizeShopVariantOverride(override)
        if key ~= "" and clean then result[key] = clean end
    end
    return result
end

function GodSystemItemConfig.normalize(input)
    input = type(input) == "table" and input or {}
    return {
        migrationVersion = math.max(1, math.floor(tonumber(input.migrationVersion) or 1)),
        itemOverrides = GodSystemItemConfig.sanitizeItemOverrides(input.itemOverrides),
        shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(input.shopVariantOverrides),
        economyRevision = math.max(1, math.floor(tonumber(input.economyRevision) or 1)),
    }
end

function GodSystemItemConfig.migrate(target, legacy)
    target = type(target) == "table" and target or {}
    if math.floor(tonumber(target.migrationVersion) or 0) >= 1 then
        local normalized = GodSystemItemConfig.normalize(target)
        target.migrationVersion = normalized.migrationVersion
        target.itemOverrides = normalized.itemOverrides
        target.shopVariantOverrides = normalized.shopVariantOverrides
        target.economyRevision = normalized.economyRevision
        return target
    end
    legacy = type(legacy) == "table" and legacy or {}
    target.migrationVersion = 1
    target.itemOverrides = GodSystemItemConfig.sanitizeItemOverrides(legacy.itemOverrides)
    target.shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(legacy.shopVariantOverrides)
    target.economyRevision = math.max(1, math.floor(tonumber(legacy.economyRevision) or 1))
    return target
end

function GodSystemItemConfig.applyRuntime(itemOverrides, shopVariantOverrides, economyRevision)
    local merged = GodSystemItemConfig.sanitizeItemOverrides(
        GodSystemConfig and GodSystemConfig.ItemOverrides or {}
    )
    local dynamic = GodSystemItemConfig.sanitizeItemOverrides(itemOverrides)
    for fullType, override in pairs(dynamic) do merged[fullType] = override end
    GodSystemItemConfig.Current = {
        migrationVersion = 1,
        itemOverrides = merged,
        shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(shopVariantOverrides),
        economyRevision = math.max(1, math.floor(tonumber(economyRevision) or 1)),
    }
    return GodSystemItemConfig.Current
end

function GodSystemItemConfig.applyShopBuyPrice(fullType, price)
    price = math.max(0, math.floor(tonumber(price) or 0))
    local override = GodSystemItemConfig.getItemOverride(fullType)
    if override and override.buyPrice ~= nil then
        return math.max(0, math.floor(tonumber(override.buyPrice) or 0))
    end
    local multiplier = GodSystemRuntimeConfig and GodSystemRuntimeConfig.get
        and tonumber(GodSystemRuntimeConfig.get("ShopBuyPriceMultiplier", 1)) or 1
    return math.max(0, math.floor(price * multiplier))
end

function GodSystemItemConfig.applySellPrice(fullType, price)
    price = math.max(0, math.floor(tonumber(price) or 0))
    local override = GodSystemItemConfig.getItemOverride(fullType)
    if override and override.sellPrice ~= nil then
        return math.max(0, math.floor(tonumber(override.sellPrice) or 0))
    end
    local multiplier = GodSystemRuntimeConfig and GodSystemRuntimeConfig.get
        and tonumber(GodSystemRuntimeConfig.get("RecycleSellPriceMultiplier", 1)) or 1
    return math.max(0, math.floor(price * multiplier))
end

function GodSystemItemConfig.publicSnapshot()
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    local itemOverrides = {}
    for fullType, override in pairs(current.itemOverrides or {}) do
        itemOverrides[fullType] = {
            buyPrice = override.buyPrice,
            sellPrice = override.sellPrice,
            category = override.category,
            shopMode = override.shopMode,
        }
    end
    return {
        itemOverrides = itemOverrides,
        shopVariantOverrides = copyTable(current.shopVariantOverrides),
        economyRevision = current.economyRevision,
    }
end

function GodSystemItemConfig.getItemOverride(fullType)
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return current.itemOverrides[tostring(fullType or "")]
end

function GodSystemItemConfig.getItemOverrides()
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return copyTable(current.itemOverrides)
end

function GodSystemItemConfig.getShopVariantOverride(variantKey)
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return current.shopVariantOverrides[tostring(variantKey or "")]
end

function GodSystemItemConfig.getShopVariantOverrides()
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return copyTable(current.shopVariantOverrides)
end

function GodSystemItemConfig.getShopMode(fullType)
    local override = GodSystemItemConfig.getItemOverride(fullType)
    local mode = override and tostring(override.shopMode or "auto") or "auto"
    if mode == "forced" or mode == "disabled" then return mode end
    return "auto"
end

function GodSystemItemConfig.getShopVariantMode(variantKey, fullType)
    local itemMode = GodSystemItemConfig.getShopMode(fullType)
    if itemMode == "disabled" then return "disabled" end
    local override = GodSystemItemConfig.getShopVariantOverride(variantKey)
    local variantMode = override and tostring(override.shopMode or "auto") or "auto"
    if variantMode == "forced" or variantMode == "disabled" then return variantMode end
    return itemMode
end

function GodSystemItemConfig.isShopItemEnabled(fullType, fallback)
    if GodSystemItemConfig.getShopMode(fullType) == "disabled" then return false end
    return fallback ~= false
end

function GodSystemItemConfig.applyCategory(fullType, category)
    local override = GodSystemItemConfig.getItemOverride(fullType)
    if override and override.category and override.category ~= "" then return override.category end
    return category
end
