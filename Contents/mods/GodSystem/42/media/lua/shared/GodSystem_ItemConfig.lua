require "GodSystem_ConversionRelations"

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
        migrationVersion = math.max(2, math.floor(tonumber(input.migrationVersion) or 2)),
        itemOverrides = GodSystemItemConfig.sanitizeItemOverrides(input.itemOverrides),
        shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(input.shopVariantOverrides),
        economyRevision = math.max(1, math.floor(tonumber(input.economyRevision) or 1)),
        conversionRelations = copyTable(input.conversionRelations),
        conversionBuiltinOverrides = copyTable(input.conversionBuiltinOverrides),
        conversionBuiltinDisabled = copyTable(input.conversionBuiltinDisabled),
        conversionBuiltinRemoved = copyTable(input.conversionBuiltinRemoved),
        conversionSequence = math.max(0, math.floor(tonumber(input.conversionSequence) or 0)),
        conversionRevision = math.max(1, math.floor(tonumber(input.conversionRevision) or 1)),
    }
end

function GodSystemItemConfig.migrate(target, legacy)
    target = type(target) == "table" and target or {}
    if math.floor(tonumber(target.migrationVersion) or 0) >= 1 then
        local normalized = GodSystemItemConfig.normalize(target)
        target.migrationVersion = 2
        target.itemOverrides = normalized.itemOverrides
        target.shopVariantOverrides = normalized.shopVariantOverrides
        target.economyRevision = normalized.economyRevision
        target.conversionRelations = normalized.conversionRelations
        target.conversionBuiltinOverrides = normalized.conversionBuiltinOverrides
        target.conversionBuiltinDisabled = normalized.conversionBuiltinDisabled
        target.conversionBuiltinRemoved = normalized.conversionBuiltinRemoved
        target.conversionSequence = normalized.conversionSequence
        target.conversionRevision = normalized.conversionRevision
        return target
    end
    legacy = type(legacy) == "table" and legacy or {}
    target.migrationVersion = 2
    target.itemOverrides = GodSystemItemConfig.sanitizeItemOverrides(legacy.itemOverrides)
    target.shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(legacy.shopVariantOverrides)
    target.economyRevision = math.max(1, math.floor(tonumber(legacy.economyRevision) or 1))
    target.conversionRelations = copyTable(legacy.conversionRelations)
    target.conversionBuiltinOverrides = copyTable(legacy.conversionBuiltinOverrides)
    target.conversionBuiltinDisabled = copyTable(legacy.conversionBuiltinDisabled)
    target.conversionBuiltinRemoved = copyTable(legacy.conversionBuiltinRemoved)
    target.conversionSequence = math.max(0, math.floor(tonumber(legacy.conversionSequence) or 0))
    target.conversionRevision = math.max(1, math.floor(tonumber(legacy.conversionRevision) or 1))
    return target
end

function GodSystemItemConfig.applyRuntime(itemOverrides, shopVariantOverrides, economyRevision, conversionData)
    local merged = GodSystemItemConfig.sanitizeItemOverrides(
        GodSystemConfig and GodSystemConfig.ItemOverrides or {}
    )
    local dynamic = GodSystemItemConfig.sanitizeItemOverrides(itemOverrides)
    for fullType, override in pairs(dynamic) do merged[fullType] = override end
    GodSystemItemConfig.Current = {
        migrationVersion = 2,
        itemOverrides = merged,
        shopVariantOverrides = GodSystemItemConfig.sanitizeShopVariantOverrides(shopVariantOverrides),
        economyRevision = math.max(1, math.floor(tonumber(economyRevision) or 1)),
        conversionRelations = copyTable(conversionData and conversionData.conversionRelations),
        conversionBuiltinOverrides = copyTable(conversionData and conversionData.conversionBuiltinOverrides),
        conversionBuiltinDisabled = copyTable(conversionData and conversionData.conversionBuiltinDisabled),
        conversionBuiltinRemoved = copyTable(conversionData and conversionData.conversionBuiltinRemoved),
        conversionSequence = math.max(0, math.floor(tonumber(conversionData and conversionData.conversionSequence) or 0)),
        conversionRevision = math.max(1, math.floor(tonumber(conversionData and conversionData.conversionRevision) or 1)),
        conversionFloors = copyTable(conversionData and conversionData.conversionFloors),
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
        conversionRevision = current.conversionRevision,
        conversionFloors = copyTable(current.conversionFloors),
    }
end

function GodSystemItemConfig.getItemOverride(fullType)
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return current.itemOverrides[tostring(fullType or "")]
end

function GodSystemItemConfig.getConversionFloor(fullType)
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return math.max(0, math.floor(tonumber((current.conversionFloors or {})[tostring(fullType or "")]) or 0))
end

function GodSystemItemConfig.getConversionRevision()
    local current = GodSystemItemConfig.Current or GodSystemItemConfig.applyRuntime({}, {}, 1)
    return math.max(1, math.floor(tonumber(current.conversionRevision) or 1))
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
    if fullType == "GodSystem.DurabilityCore" then return "disabled" end
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
    -- Existing cores and their use logic are unchanged; only storefront availability is retired.
    if fullType == "GodSystem.DurabilityCore" then return false end
    if GodSystemItemConfig.getShopMode(fullType) == "disabled" then return false end
    return fallback ~= false
end

function GodSystemItemConfig.applyCategory(fullType, category)
    local override = GodSystemItemConfig.getItemOverride(fullType)
    if override and override.category and override.category ~= "" then return override.category end
    return category
end

GodSystemItemConfig.PRESET_DEFAULT = "default"
GodSystemItemConfig.PRESET_SLOTS = { "1", "2", "3" }
GodSystemItemConfig.PRESET_LIMIT = 3
GodSystemItemConfig.PRESET_NAME_MAX = 32

local PRESET_CONTENT_KEYS = {
    "itemOverrides",
    "shopVariantOverrides",
    "conversionRelations",
    "conversionBuiltinOverrides",
    "conversionBuiltinDisabled",
    "conversionBuiltinRemoved",
    "conversionSequence",
}

function GodSystemItemConfig.sanitizePresetName(input)
    local name = sanitizeText(input, GodSystemItemConfig.PRESET_NAME_MAX)
    if name == "" then return nil end
    if name == GodSystemItemConfig.PRESET_DEFAULT then return nil end
    if name:lower() == GodSystemItemConfig.PRESET_DEFAULT then return nil end
    return name
end

function GodSystemItemConfig.isPresetSlot(name)
    return name == "1" or name == "2" or name == "3"
end

function GodSystemItemConfig.sanitizePresetRemark(input)
    local remark = tostring(input or ""):match("^%s*(.-)%s*$") or ""
    remark = remark:gsub("[%c]", " ")
    if #remark <= 120 then return remark end
    if #"\228\184\173" == 1 then return remark:sub(1, 120) end
    local index, last = 1, 0
    while index <= #remark do
        local first = string.byte(remark, index)
        local width = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
        if index + width - 1 > 120 then break end
        last = index + width - 1
        index = last + 1
    end
    return remark:sub(1, last)
end

function GodSystemItemConfig.ensurePresets(data)
    if type(data) ~= "table" then return nil end
    local store = data.itemConfigPresets
    if type(store) ~= "table" then
        store = { order = {}, presets = {}, remarks = {}, active = GodSystemItemConfig.PRESET_DEFAULT }
        data.itemConfigPresets = store
    end
    if type(store.order) ~= "table" then store.order = {} end
    if type(store.presets) ~= "table" then store.presets = {} end
    if type(store.remarks) ~= "table" then store.remarks = {} end
    local seen = {}
    local order = {}
    for _, name in ipairs(GodSystemItemConfig.PRESET_SLOTS) do
        if type(store.presets[name]) == "table" then
            seen[name] = true
            order[#order + 1] = name
        end
    end
    store.order = order
    if type(store.active) ~= "string" or store.active == "" then
        store.active = GodSystemItemConfig.PRESET_DEFAULT
    end
    if store.active ~= GodSystemItemConfig.PRESET_DEFAULT and not seen[store.active] then
        store.active = GodSystemItemConfig.PRESET_DEFAULT
    end
    return store
end

function GodSystemItemConfig.presetSnapshot(data)
    local normalized = GodSystemItemConfig.normalize(data)
    local snapshot = {}
    for _, key in ipairs(PRESET_CONTENT_KEYS) do
        snapshot[key] = normalized[key]
    end
    return snapshot
end

function GodSystemItemConfig.presetListPayload(data)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store then return { order = {}, remarks = {}, active = GodSystemItemConfig.PRESET_DEFAULT } end
    local order = {}
    for index, name in ipairs(store.order) do order[index] = name end
    local remarks = {}
    for _, name in ipairs(GodSystemItemConfig.PRESET_SLOTS) do remarks[name] = store.remarks[name] or "" end
    return { order = order, remarks = remarks, active = store.active }
end

local function writePresetContent(data, snapshot)
    for _, key in ipairs(PRESET_CONTENT_KEYS) do
        data[key] = copyTable(snapshot[key])
    end
    data.economyRevision = math.max(1, math.floor(tonumber(data.economyRevision) or 1)) + 1
    data.conversionRevision = math.max(1, math.floor(tonumber(data.conversionRevision) or 1)) + 1
end

function GodSystemItemConfig.savePreset(data, name)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store then return nil, "Invalid" end
    name = GodSystemItemConfig.sanitizePresetName(name)
    if not GodSystemItemConfig.isPresetSlot(name) then return nil, "Invalid" end
    if store.presets[name] == nil and #store.order >= GodSystemItemConfig.PRESET_LIMIT then
        return nil, "Limit"
    end
    store.presets[name] = GodSystemItemConfig.presetSnapshot(data)
    local found = false
    for _, existing in ipairs(store.order) do
        if existing == name then
            found = true
            break
        end
    end
    if not found then store.order[#store.order + 1] = name end
    store.active = name
    return store
end

function GodSystemItemConfig.setPresetRemark(data, name, remark)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store or not GodSystemItemConfig.isPresetSlot(name) then return nil, "Invalid" end
    store.remarks[name] = GodSystemItemConfig.sanitizePresetRemark(remark)
    return store
end

function GodSystemItemConfig.deletePreset(data, name)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store then return nil end
    name = tostring(name or "")
    if not GodSystemItemConfig.isPresetSlot(name) then return nil end
    if type(store.presets[name]) ~= "table" then return nil end
    store.presets[name] = nil
    local order = {}
    for _, existing in ipairs(store.order) do
        if existing ~= name then order[#order + 1] = existing end
    end
    store.order = order
    if store.active == name then store.active = GodSystemItemConfig.PRESET_DEFAULT end
    return store
end

function GodSystemItemConfig.applyPreset(data, name)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store then return nil end
    name = tostring(name or "")
    if name == GodSystemItemConfig.PRESET_DEFAULT then
        writePresetContent(data, GodSystemItemConfig.normalize({}))
        store.active = GodSystemItemConfig.PRESET_DEFAULT
        return store
    end
    if not GodSystemItemConfig.isPresetSlot(name) then return nil end
    local snapshot = store.presets[name]
    if type(snapshot) ~= "table" then return nil end
    writePresetContent(data, GodSystemItemConfig.normalize(snapshot))
    store.active = name
    return store
end
