require "GodSystem_Config"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_RuntimeConfig"
require "GodSystem_ItemConfig"
require "GodSystem_B42JavaCalls"

GodSystemEconomyPolicy = GodSystemEconomyPolicy or {}

local Policy = GodSystemEconomyPolicy
local Config = GodSystemConfig or {}
local Admin = GodSystemItemConfig or {}
local DEFAULT_CATEGORY = "normal"

Policy.revision = math.max(1, tonumber(Policy.revision) or 1)
Policy.quoteCache = Policy.quoteCache or {}

local function finiteNumber(value, fallback)
    local numberValue = tonumber(value)
    if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
        return fallback or 0
    end
    return numberValue
end

local function integer(value, fallback)
    return math.floor(finiteNumber(value, fallback or 0))
end

local function safeCeil(value)
    return math.ceil(finiteNumber(value, 0) - 0.000000001)
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function moduleName(fullType)
    return tostring(fullType or ""):match("^([^%.]+)%.")
end

local function itemValue(item, methodName)
    if not item or not item[methodName] then return nil end
    local ok, value = pcall(function() return item[methodName](item) end)
    return ok and value or nil
end

local function categoryFromRaw(raw)
    local compact = trim(raw):lower():gsub("[%s_%-%./\\|>]+", "")
    if compact == "" then return DEFAULT_CATEGORY end
    if compact:find("accessory", 1, true) or compact:find("jewelry", 1, true) then return "accessory" end
    if compact:find("casing", 1, true) then return "casing" end
    if compact:find("security", 1, true) then return "security" end
    if compact:find("firstaid", 1, true) or compact:find("medical", 1, true) then return "medical" end
    if compact:find("beverage", 1, true) or compact:find("water", 1, true) or compact:find("drink", 1, true) then return "drink" end
    if compact:find("food", 1, true) or compact:find("canned", 1, true) then return "food" end
    if compact:find("container", 1, true) then return "container" end
    if compact:find("cooking", 1, true) or compact:find("utensil", 1, true) then return "cooking" end
    if compact:find("fire", 1, true) then return "fire" end
    if compact:find("tool", 1, true) or compact:find("maintenance", 1, true) then return "tool" end
    if compact:find("material", 1, true) then return "material" end
    if compact:find("ammo", 1, true) or compact:find("bullet", 1, true) or compact:find("shell", 1, true) then return "ammo" end
    if compact:find("weapon", 1, true) then return "weapon" end
    if compact:find("cloth", 1, true) or compact:find("clothing", 1, true) then return "clothing" end
    if compact:find("literature", 1, true) or compact:find("book", 1, true) or compact:find("map", 1, true) then return "literature" end
    if compact:find("drainable", 1, true) then return "drainable" end
    if compact:find("elect", 1, true) or compact:find("radio", 1, true) then return "electronics" end
    if compact:find("farm", 1, true) or compact:find("seed", 1, true) then return "farming" end
    if compact:find("vehicle", 1, true) or compact:find("mechanic", 1, true) then return "vehicle" end
    if compact:find("key", 1, true) then return "key" end
    if compact == "survival" then return "survival" end
    return DEFAULT_CATEGORY
end

local function categoryFor(fullType, item)
    local configured = Config.VanillaItemPriceCategories and Config.VanillaItemPriceCategories[fullType]
    local raw = configured or itemValue(item, "getDisplayCategory") or itemValue(item, "getCategory") or fullType
    local category = configured or categoryFromRaw(raw)
    if Admin.applyCategory then category = Admin.applyCategory(fullType, category) end
    category = tostring(category or DEFAULT_CATEGORY):lower():gsub("[^a-z0-9_]+", "_")
    return category ~= "" and category or DEFAULT_CATEGORY
end

local function fallbackBuy(category)
    local prices = Config.ModCategoryBuyPrices or {}
    local price = finiteNumber(prices[category] or prices.normal, 120)
    return math.max(1, integer(price, 1))
end

local function isUnknownThirdParty(fullType)
    if (Config.VanillaItemBuyPrices or {})[fullType] ~= nil then return false end
    local mod = moduleName(fullType)
    return mod ~= nil and (Config.RecycleDefaultAllowedModules or {})[mod] ~= true
end

local function baseReference(fullType, item)
    local category = categoryFor(fullType, item)
    local configured = (Config.VanillaItemBuyPrices or {})[fullType]
    if configured ~= nil then
        return math.max(1, integer(configured, 1)), category, "price_table", false, true
    end
    return fallbackBuy(category), category, "category_fallback", isUnknownThirdParty(fullType), false
end

local function itemConditionMultiplier(item)
    if not item then return 1 end
    local multiplier = itemValue(item, "isBroken") == true and 0.5 or 1
    local used = finiteNumber(itemValue(item, "getUsedDelta"), 1)
    if used > 0 and used < 1 then multiplier = multiplier * used end
    return multiplier
end

local function eligible(fullType, context)
    if GodSystemItemEligibility and GodSystemItemEligibility.isEconomicItemAllowed then
        return GodSystemItemEligibility.isEconomicItemAllowed(fullType, context) == true
    end
    return fullType ~= ""
end

local function baseRecycle(fullType, item)
    local reference, category, source, unknownThirdParty, hasExactPrice = baseReference(fullType, item)
    local recycle = unknownThirdParty
        and math.max(1, integer(Config.UnknownModItemRecycleValue, 1))
        or math.max(1, math.floor(reference * finiteNumber(Config.RecycleSellRatio, 0.05)))
    if Admin.applySellPrice then recycle = Admin.applySellPrice(fullType, recycle) end
    recycle = math.max(0, math.floor(recycle * itemConditionMultiplier(item)))
    if recycle > 0 then recycle = math.max(1, recycle) end
    return reference, recycle, category, source, unknownThirdParty, hasExactPrice
end

function Policy.invalidate(reason)
    Policy.revision = Policy.revision + 1
    Policy.quoteCache = {}
    Policy.lastInvalidationReason = tostring(reason or "runtime")
end

function Policy.getShopMode(fullType)
    if Admin.getShopMode then return Admin.getShopMode(fullType) end
    return Admin.isShopItemEnabled and (Admin.isShopItemEnabled(fullType, true) and "auto" or "disabled") or "auto"
end

function Policy.quote(fullType, item, context)
    fullType = trim(fullType)
    context = type(context) == "table" and context or { kind = context }
    if fullType == "" then
        return { eligible = false, category = DEFAULT_CATEGORY, referenceBuy = 0, recycleValue = 0, conversionValue = 0, safeMinimum = 0, finalBuy = 0, buyPrice = 0, sellPrice = 0, priceSource = "missing", verificationStatus = "invalid", warnings = {} }
    end
    local economyRevision = Admin.Current and Admin.Current.economyRevision or 1
    local cacheKey = item == nil and (fullType .. "|" .. tostring(context.kind or "default") .. "|" .. tostring(Policy.revision) .. "|" .. tostring(economyRevision)) or nil
    if cacheKey and Policy.quoteCache[cacheKey] then return Policy.quoteCache[cacheKey] end

    local allowed = eligible(fullType, context.kind or "economy")
    local reference, recycle, category, source, unknownThirdParty, hasExactPrice = baseRecycle(fullType, item)
    local finalBuy = Admin.applyShopBuyPrice and Admin.applyShopBuyPrice(fullType, reference) or reference
    finalBuy = math.max(0, integer(finalBuy, reference))
    local warnings = {}
    if not allowed then warnings[#warnings + 1] = "ineligible" end
    local result = {
        eligible = allowed,
        category = category,
        referenceBuy = reference,
        recycleValue = recycle,
        conversionValue = 0,
        safeMinimum = 0,
        finalBuy = finalBuy,
        buyPrice = finalBuy,
        sellPrice = recycle,
        priceSource = source,
        verificationStatus = "not_applicable",
        warnings = warnings,
        unknownThirdParty = unknownThirdParty,
        hasExactPrice = hasExactPrice,
        dynamicConversionUnknown = false,
        dynamicFloor = 0,
        shopMode = Policy.getShopMode(fullType),
        policyRevision = Policy.revision,
    }
    if cacheKey then Policy.quoteCache[cacheKey] = result end
    return result
end

function Policy.listingCost(fullType, item)
    local quote = Policy.quote(fullType, item, { kind = "shop" })
    local ratio = math.max(0, finiteNumber(Config.AutoShopListOnlyCostRatio, 0.5))
    local minimum = math.max(0, integer(Config.AutoShopListOnlyMinCost, 50))
    return math.max(minimum, safeCeil(quote.finalBuy * ratio)), quote.finalBuy
end

function Policy.health()
    return { ok = true, moduleId = "economyPolicy", revision = Policy.revision, recipes = 0, replacements = 0, warnings = 0 }
end

return Policy
