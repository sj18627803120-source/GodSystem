require "GodSystem_Config"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_AdminConfig"

GodSystemEconomyPolicy = GodSystemEconomyPolicy or {}

local Policy = GodSystemEconomyPolicy
local Config = GodSystemConfig or {}
local Admin = GodSystemAdminConfig or {}
local MAX_DEPTH = 32
local DEFAULT_CATEGORY = "normal"

Policy.revision = math.max(1, tonumber(Policy.revision) or 1)
Policy.quoteCache = Policy.quoteCache or {}
Policy.transformIndex = Policy.transformIndex or nil
Policy.unverifiedTypes = Policy.unverifiedTypes or {}
Policy.indexStats = Policy.indexStats or { recipes = 0, replacements = 0, warnings = 0 }

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

local function safeMethod(object, methodName, fallback, ...)
    if not object or not methodName then return fallback end
    local method = object[methodName]
    if type(method) ~= "function" then return fallback end
    local args = { ... }
    local unpackFn = unpack or (table and table.unpack)
    local ok, value = pcall(function()
        return method(object, unpackFn(args))
    end)
    if ok and value ~= nil then return value end
    return fallback
end

local function listSize(list)
    if not list then return 0 end
    if type(list) == "table" and type(list.size) ~= "function" then return #list end
    return math.max(0, integer(safeMethod(list, "size", 0), 0))
end

local function listGet(list, index)
    if type(list) == "table" and type(list.get) ~= "function" then return list[index + 1] end
    return safeMethod(list, "get", nil, index)
end

local function scriptManager()
    if not getScriptManager then return nil end
    local ok, manager = pcall(getScriptManager)
    if ok then return manager end
    return nil
end

local function scriptItem(fullType)
    local manager = scriptManager()
    if not manager then return nil end
    return safeMethod(manager, "FindItem", nil, fullType)
end

local function scriptValue(fullType, methods)
    local item = scriptItem(fullType)
    if not item then return "" end
    for i = 1, #methods do
        local value = safeMethod(item, methods[i], nil)
        if value ~= nil and trim(value) ~= "" then return trim(value) end
    end
    return ""
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
    local raw = configured or scriptValue(fullType, { "getDisplayCategory", "getTypeString", "getType", "getCategory" })
    if trim(raw) == "" and item then raw = safeMethod(item, "getCategory", "") end
    local category = configured or categoryFromRaw(raw)
    if Admin.applyCategory then category = Admin.applyCategory(fullType, category) end
    category = tostring(category or DEFAULT_CATEGORY):lower():gsub("[^a-z0-9_]+", "_")
    if category == "" or category == "unlocked" then return DEFAULT_CATEGORY end
    return category
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
    local multiplier = 1
    if safeMethod(item, "isBroken", false) == true then multiplier = multiplier * 0.5 end
    local used = finiteNumber(safeMethod(item, "getUsedDelta", 1), 1)
    if used > 0 and used < 1 then multiplier = multiplier * used end
    return multiplier
end

local function itemFullType(value, defaultModule)
    value = trim(value)
    if value == "" then return nil end
    value = value:gsub("^Item_", "")
    if not value:find("%.") and defaultModule and defaultModule ~= "" then value = defaultModule .. "." .. value end
    return value
end

local function addRoute(index, sourceType, outputs, source)
    if not sourceType or type(outputs) ~= "table" or #outputs == 0 then return false end
    local clean = {}
    for i = 1, #outputs do
        local output = outputs[i]
        local fullType = itemFullType(output.fullType, moduleName(sourceType))
        local count = math.max(1, integer(output.count, 1))
        if fullType then clean[#clean + 1] = { fullType = fullType, count = count } end
    end
    if #clean == 0 then return false end
    index[sourceType] = index[sourceType] or {}
    index[sourceType][#index[sourceType] + 1] = { outputs = clean, source = source or "runtime" }
    return true
end

local function sourceItems(source, defaultModule)
    local result = {}
    local values = safeMethod(source, "getItems", nil)
    if values then
        for i = 0, listSize(values) - 1 do
            local value = listGet(values, i)
            local fullType = itemFullType(value, defaultModule)
            if fullType then result[#result + 1] = fullType end
        end
    end
    if #result == 0 then
        local value = safeMethod(source, "getType", nil) or safeMethod(source, "getFullType", nil) or source.type
        local fullType = itemFullType(value, defaultModule)
        if fullType then result[#result + 1] = fullType end
    end
    return result
end

local function recipeModuleName(recipe)
    local module = safeMethod(recipe, "getModule", nil)
    local name = safeMethod(module, "getName", nil)
        or safeMethod(recipe, "getModuleName", nil)
    name = trim(name)
    return name ~= "" and name or nil
end

local function recipeOutputs(recipe, defaultModule)
    local result = safeMethod(recipe, "getResult", nil)
    if not result then return nil end
    local fullType = safeMethod(result, "getFullType", nil)
        or safeMethod(result, "getType", nil)
        or result.fullType or result.type
    fullType = itemFullType(fullType, defaultModule)
    if not fullType then return nil end
    local count = safeMethod(result, "getCount", nil) or result.count or 1
    return { { fullType = fullType, count = math.max(1, integer(count, 1)) } }
end

local function scanRecipes(index, unverified, manager, stats)
    local recipes = safeMethod(manager, "getAllRecipes", nil)
    for i = 0, listSize(recipes) - 1 do
        local recipe = listGet(recipes, i)
        local recipeModule = recipeModuleName(recipe)
        local sources = recipe and safeMethod(recipe, "getSource", nil) or nil
        local consumedGroups = {}
        for sourceIndex = 0, listSize(sources) - 1 do
            local source = listGet(sources, sourceIndex)
            local keep = safeMethod(source, "isKeep", false) == true
            local destroy = safeMethod(source, "isDestroy", false) == true
            if not keep then
                local items = sourceItems(source, recipeModule)
                if #items > 0 then consumedGroups[#consumedGroups + 1] = { items = items, destroy = destroy } end
            end
        end
        local luaCreate = trim(safeMethod(recipe, "getLuaCreate", ""))
        local outputs = recipeOutputs(recipe, recipeModule)
        -- Only a recipe with one consumed source group can describe a direct
        -- unpack/open conversion. Multi-input crafting recipes must not make
        -- every ingredient look like a risky container.
        if #consumedGroups == 1 then
            local group = consumedGroups[1]
            local deterministic = not group.destroy and outputs ~= nil and luaCreate == ""
            for j = 1, #group.items do
                if deterministic then
                    if addRoute(index, group.items[j], outputs, "recipe") then stats.recipes = stats.recipes + 1 end
                else
                    unverified[group.items[j]] = true
                end
            end
        end
    end
end

local function scanReplacements(index, manager, stats)
    local items = safeMethod(manager, "getAllItems", nil)
    for i = 0, listSize(items) - 1 do
        local script = listGet(items, i)
        local fullType = script and (safeMethod(script, "getFullName", nil) or safeMethod(script, "getFullType", nil)) or nil
        if not fullType and script then
            local mod = safeMethod(script, "getModuleName", nil)
            local name = safeMethod(script, "getName", nil)
            if mod and name then fullType = tostring(mod) .. "." .. tostring(name) end
        end
        fullType = itemFullType(fullType)
        if fullType then
            local mod = moduleName(fullType)
            local seen = {}
            local fields = { "getReplaceOnUse", "getReplaceOnDeplete" }
            for j = 1, #fields do
                local replacement = itemFullType(safeMethod(script, fields[j], nil), mod)
                if replacement and not seen[replacement] then
                    seen[replacement] = true
                    if addRoute(index, fullType, { { fullType = replacement, count = 1 } }, fields[j]) then
                        stats.replacements = stats.replacements + 1
                    end
                end
            end
            -- Item.getLuaCreate is an item-creation callback, not proof that
            -- this item can itself be opened or dismantled. Recipe scanning is
            -- the only source of dynamic one-item conversion risk.
        end
    end
end

function Policy.invalidate(reason)
    Policy.revision = Policy.revision + 1
    Policy.quoteCache = {}
    Policy.lastInvalidationReason = tostring(reason or "runtime")
end

function Policy.rebuildTransformIndex(manager)
    local index = {}
    local unverified = {}
    local stats = { recipes = 0, replacements = 0, warnings = 0 }

    -- B42.20 MoneyBundle is a deterministic one-to-many unpack operation. Keep this
    -- explicit rule so headless tests and servers without loaded recipe scripts use
    -- the same safe price as a fully loaded game client.
    addRoute(index, "Base.MoneyBundle", { { fullType = "Base.Money", count = 100 } }, "builtin")

    manager = manager or scriptManager()
    if manager then
        local okRecipes = pcall(scanRecipes, index, unverified, manager, stats)
        local okReplacements = pcall(scanReplacements, index, manager, stats)
        if not okRecipes then stats.warnings = stats.warnings + 1 end
        if not okReplacements then stats.warnings = stats.warnings + 1 end
    end
    Policy.transformIndex = index
    Policy.unverifiedTypes = unverified
    Policy.indexStats = stats
    Policy.invalidate("transform_index")
    return stats
end

function Policy.setTransformIndexForTests(index, unverified)
    Policy.transformIndex = index or {}
    Policy.unverifiedTypes = unverified or {}
    Policy.invalidate("test_transform_index")
end

local function ensureTransformIndex()
    if Policy.transformIndex == nil then Policy.rebuildTransformIndex() end
end

local function eligible(fullType, context)
    if not fullType or fullType == "" then return false end
    if GodSystem and GodSystem.isEconomicItemAllowed then
        return GodSystem.isEconomicItemAllowed(fullType, context) == true
    end
    return true
end

local function baseRecycle(fullType, item)
    local reference, category, source, unknownThirdParty, hasExactPrice = baseReference(fullType, item)
    local recycle
    if unknownThirdParty then
        recycle = math.max(1, integer(Config.UnknownModItemRecycleValue, 1))
    else
        recycle = math.max(1, math.floor(reference * finiteNumber(Config.RecycleSellRatio, 0.05)))
    end
    if Admin.applySellPrice then recycle = Admin.applySellPrice(fullType, recycle) end
    recycle = math.max(0, math.floor(recycle * itemConditionMultiplier(item)))
    if recycle > 0 then recycle = math.max(1, recycle) end
    return reference, recycle, category, source, unknownThirdParty, hasExactPrice
end

local function terminalRecycleValue(fullType, visiting, depth)
    if depth > MAX_DEPTH or visiting[fullType] then return 0, false, "cycle" end
    visiting[fullType] = true
    local _, ownRecycle = baseRecycle(fullType, nil)
    local routes = (Policy.transformIndex or {})[fullType]
    local best = 0
    local verified = false
    if routes then
        for i = 1, #routes do
            local total = 0
            local routeValid = true
            for j = 1, #(routes[i].outputs or {}) do
                local output = routes[i].outputs[j]
                local nested, nestedVerified = terminalRecycleValue(output.fullType, visiting, depth + 1)
                if nested <= 0 then
                    local _, outputRecycle = baseRecycle(output.fullType, nil)
                    nested = outputRecycle
                end
                if nested <= 0 then routeValid = false end
                total = total + math.max(0, nested) * math.max(1, integer(output.count, 1))
                verified = verified or nestedVerified
            end
            if routeValid and total > best then best = total; verified = true end
        end
    end
    visiting[fullType] = nil
    if best > 0 then return best, verified, "verified" end
    return ownRecycle, false, "none"
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
    ensureTransformIndex()
    local cacheKey = item == nil and (fullType .. "|" .. tostring(context.kind or "default") .. "|" .. tostring(Policy.revision)) or nil
    if cacheKey and Policy.quoteCache[cacheKey] then return Policy.quoteCache[cacheKey] end

    local allowed = eligible(fullType, context.kind or "economy")
    local reference, recycle, category, source, unknownThirdParty, hasExactPrice = baseRecycle(fullType, item)
    local conversion, converted, conversionStatus = terminalRecycleValue(fullType, {}, 1)
    if not (Policy.transformIndex or {})[fullType] then conversion = 0 end
    local margin = math.max(0, finiteNumber(Config.EconomyConversionSafetyMargin, 0.10))
    local safeMinimum = conversion > 0 and safeCeil(conversion * (1 + margin)) or 0
    local unverified = Policy.unverifiedTypes[fullType] == true
    local dynamicFloor = 0
    if unverified and not hasExactPrice then
        local assumed = math.max(1, integer(Config.EconomyUnknownDynamicOutputCount, 500))
        local minimumRecycle = math.max(1, integer(Config.UnknownModItemRecycleValue, 1))
        dynamicFloor = safeCeil(assumed * minimumRecycle * (1 + margin))
        safeMinimum = math.max(safeMinimum, dynamicFloor)
    end
    local automaticBuy = math.max(reference, safeMinimum)
    local finalBuy = Admin.applyShopBuyPrice and Admin.applyShopBuyPrice(fullType, automaticBuy) or automaticBuy
    finalBuy = math.max(0, integer(finalBuy, automaticBuy))
    local warnings = {}
    if unverified then warnings[#warnings + 1] = "dynamic_unverified" end
    if conversionStatus == "cycle" then warnings[#warnings + 1] = "conversion_cycle" end
    if finalBuy < safeMinimum then warnings[#warnings + 1] = "admin_below_safe_minimum" end
    if not allowed then warnings[#warnings + 1] = "ineligible" end
    local status = converted and "verified" or (unverified and "unverified" or "not_applicable")
    local result = {
        eligible = allowed,
        category = category,
        referenceBuy = reference,
        recycleValue = recycle,
        conversionValue = conversion,
        safeMinimum = safeMinimum,
        finalBuy = finalBuy,
        buyPrice = finalBuy,
        sellPrice = recycle,
        priceSource = source,
        verificationStatus = status,
        warnings = warnings,
        unknownThirdParty = unknownThirdParty,
        hasExactPrice = hasExactPrice,
        dynamicConversionUnknown = unverified,
        dynamicFloor = dynamicFloor,
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
    ensureTransformIndex()
    return {
        ok = true,
        moduleId = "economyPolicy",
        revision = Policy.revision,
        recipes = Policy.indexStats.recipes or 0,
        replacements = Policy.indexStats.replacements or 0,
        warnings = Policy.indexStats.warnings or 0,
    }
end
