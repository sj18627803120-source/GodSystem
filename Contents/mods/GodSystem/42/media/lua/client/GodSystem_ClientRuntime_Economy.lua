_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Economy"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Economy then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Economy = true
    setfenv(1, runtimeEnvironment)

function GodSystemApp.services.runtime.getItemModData(item)
    if not item or not item.getModData then
        return nil
    end
    local ok, data = pcall(function() return item:getModData() end)
    if ok then
        return data
    end
    return nil
end

function GodSystemApp.services.runtime.getShopRewardText(shopItem)
    if not shopItem then
        return ""
    end
    local parts = {}
    local items = shopItem.items or {}
    for i = 1, #items do
        local name = GodSystemApp.services.runtime.getItemDisplayName(items[i].fullType)
        if not GodSystemApp.services.runtime.itemExists(items[i].fullType) then
            name = GodSystemApp.services.runtime.text("Detail_MissingItem", "Missing: ") .. tostring(items[i].fullType)
        end
        table.insert(parts, name .. " x" .. tostring(items[i].count or 1))
    end
    if #parts == 0 then
        return GodSystemApp.services.runtime.text("None_Item", "No item")
    end
    return table.concat(parts, ", ")
end

function GodSystemApp.services.runtime.getShopBuyReference(fullType)
    local best = nil
    for i = 1, #GodSystemConfig.ShopItems do
        local shopItem = GodSystemConfig.ShopItems[i]
        local items = shopItem.items or {}
        for j = 1, #items do
            if items[j].fullType == fullType then
                local unitPrice = GodSystemApp.services.runtime.getShopItemUnitPrice(shopItem)
                if not best or unitPrice < best.price then
                    best = {
                        label = GodSystemApp.services.runtime.getShopLabel(shopItem),
                        price = unitPrice,
                    }
                end
            end
        end
    end
    local unlocked = GodSystemApp.services.runtime.getData().unlockedShopItems or {}
    for _, autoItem in pairs(unlocked) do
        if autoItem and autoItem.fullType == fullType then
            local buyPrice = GodSystemApp.services.runtime.getAutoShopBuyPriceForItem(fullType, autoItem.sellPrice or 1)
            if not best or buyPrice < best.price then
                best = {
                    label = GodSystemApp.services.runtime.getUnlockedShopLabel(fullType, autoItem),
                    price = buyPrice,
                }
            end
        end
    end
    return best
end

function GodSystemApp.services.runtime.getConfiguredShopPriceForFullType(fullType)
    local best = nil
    for i = 1, #GodSystemConfig.ShopItems do
        local shopItem = GodSystemConfig.ShopItems[i]
        local items = shopItem.items or {}
        for j = 1, #items do
            if items[j].fullType == fullType then
                local price = GodSystemApp.services.runtime.getShopItemUnitPrice(shopItem)
                if price > 0 and (not best or price < best) then
                    best = price
                end
            end
        end
    end
    return best
end

function GodSystemApp.services.runtime.getScriptItemCategory(fullType)
    local scriptItem = getScriptManager and getScriptManager() and getScriptManager():FindItem(fullType) or nil
    if not scriptItem then
        return ""
    end
    local methods = { "getTypeString", "getDisplayCategory", "getType", "getCategory" }
    for i = 1, #methods do
        local value = GodSystemB42JavaCalls.value(scriptItem, methods[i], nil)
        if value then return tostring(value) end
    end
    return ""
end

function GodSystemApp.services.runtime.getScriptItemDisplayCategory(fullType)
    local scriptItem = getScriptManager and getScriptManager() and getScriptManager():FindItem(fullType) or nil
    if not scriptItem then
        return ""
    end
    local methods = { "getDisplayCategory", "getTypeString", "getType", "getCategory" }
    for i = 1, #methods do
        local value = GodSystemB42JavaCalls.value(scriptItem, methods[i], nil)
        if value and tostring(value) ~= "" then return tostring(value) end
    end
    return ""
end

function gsTrim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function GodSystemApp.services.runtime.getShopPrimaryFullType(shopItem)
    if not shopItem then
        return nil
    end
    if shopItem.fullType then
        return shopItem.fullType
    end
    if shopItem.items and shopItem.items[1] then
        return shopItem.items[1].fullType
    end
    return nil
end

function gsShopCategoryFromRaw(raw)
    raw = gsTrim(raw)
    if raw == "" then
        return "other", GodSystemApp.services.runtime.text("ShopCategory_Other", "Other")
    end

    local compact = string.lower(raw):gsub("[%s_%-%./\\|>]+", "")
    if compact == "" then
        return "other", GodSystemApp.services.runtime.text("ShopCategory_Other", "Other")
    end

    if compact == "unlocked" then
        return "unlocked", GodSystemApp.services.runtime.text("Group_Unlocked", "Unlocked")
    end
    if string.find(compact, "accessory", 1, true) or string.find(compact, "jewelry", 1, true) then
        return "accessory", GodSystemApp.services.runtime.text("ShopCategory_Accessory", "Accessory")
    end
    if string.find(compact, "casing", 1, true) or string.find(compact, "casings", 1, true) then
        return "casing", GodSystemApp.services.runtime.text("ShopCategory_Casing", "Casing")
    end
    if string.find(compact, "security", 1, true) then
        return "security", GodSystemApp.services.runtime.text("ShopCategory_Security", "Security")
    end
    if string.find(compact, "firstaid", 1, true) or string.find(compact, "medical", 1, true) then
        return "medical", GodSystemApp.services.runtime.text("ShopCategory_Medical", "Medical")
    end
    if string.find(compact, "beverage", 1, true) or string.find(compact, "water", 1, true) or string.find(compact, "drink", 1, true) then
        return "drink", GodSystemApp.services.runtime.text("ShopCategory_Drink", "Drink")
    end
    if string.find(compact, "food", 1, true) or string.find(compact, "canned", 1, true) then
        return "food", GodSystemApp.services.runtime.text("ShopCategory_Food", "Food")
    end
    if string.find(compact, "container", 1, true) then
        return "container", GodSystemApp.services.runtime.text("ShopCategory_Container", "Container")
    end
    if string.find(compact, "cooking", 1, true) or string.find(compact, "utensil", 1, true) then
        return "cooking", GodSystemApp.services.runtime.text("ShopCategory_Cooking", "Cooking")
    end
    if string.find(compact, "firesource", 1, true) or string.find(compact, "fire", 1, true) then
        return "fire", GodSystemApp.services.runtime.text("ShopCategory_Fire", "Fire")
    end
    if string.find(compact, "tool", 1, true) or string.find(compact, "maintenance", 1, true) then
        return "tool", GodSystemApp.services.runtime.text("ShopCategory_Tool", "Tool")
    end
    if string.find(compact, "material", 1, true) then
        return "material", GodSystemApp.services.runtime.text("ShopCategory_Material", "Material")
    end
    if string.find(compact, "ammo", 1, true) or string.find(compact, "bullet", 1, true) or string.find(compact, "shell", 1, true) then
        return "ammo", GodSystemApp.services.runtime.text("ShopCategory_Ammo", "Ammo")
    end
    if string.find(compact, "weapon", 1, true) then
        return "weapon", GodSystemApp.services.runtime.text("ShopCategory_Weapon", "Weapon")
    end
    if string.find(compact, "cloth", 1, true) or string.find(compact, "clothing", 1, true) then
        return "clothing", GodSystemApp.services.runtime.text("ShopCategory_Clothing", "Clothing")
    end
    if string.find(compact, "literature", 1, true) or string.find(compact, "book", 1, true) or string.find(compact, "map", 1, true) then
        return "literature", GodSystemApp.services.runtime.text("ShopCategory_Literature", "Literature")
    end
    if string.find(compact, "drainable", 1, true) then
        return "drainable", GodSystemApp.services.runtime.text("ShopCategory_Drainable", "Drainable")
    end
    if string.find(compact, "elect", 1, true) or string.find(compact, "radio", 1, true) then
        return "electronics", GodSystemApp.services.runtime.text("ShopCategory_Electronics", "Electronics")
    end
    if string.find(compact, "farm", 1, true) or string.find(compact, "seed", 1, true) then
        return "farming", GodSystemApp.services.runtime.text("ShopCategory_Farming", "Farming")
    end
    if string.find(compact, "vehicle", 1, true) or string.find(compact, "mechanic", 1, true) then
        return "vehicle", GodSystemApp.services.runtime.text("ShopCategory_Vehicle", "Vehicle")
    end
    if string.find(compact, "key", 1, true) then
        return "key", GodSystemApp.services.runtime.text("ShopCategory_Key", "Key")
    end
    if compact == "normal" or compact == "survival" then
        return compact, compact == "survival" and GodSystemApp.services.runtime.text("ShopCategory_Survival", "Survival") or GodSystemApp.services.runtime.text("ShopCategory_Other", "Other")
    end

    return compact, raw
end

function GodSystemApp.services.runtime.getShopPrimaryCategory(shopItem)
    local fullType = GodSystemApp.services.runtime.getShopPrimaryFullType(shopItem)
    local raw = fullType and GodSystemApp.services.runtime.getScriptItemDisplayCategory(fullType) or ""
    if raw == "" then
        raw = GodSystemApp.services.runtime.getShopGroup(shopItem)
    end
    raw = tostring(raw or "")
    raw = raw:gsub("\\", "/")
    raw = string.match(raw, "^[^/%-%|>]+") or raw
    raw = gsTrim(raw)
    local key, label = gsShopCategoryFromRaw(raw)
    key = tostring(key or "other"):lower():gsub("[^a-z0-9_]+", "_")
    if key == "" then
        key = "other"
    end
    return { key = key, label = label }
end

function GodSystemApp.services.runtime.getShopCategoryLabel(categoryKey)
    categoryKey = tostring(categoryKey or "all")
    if categoryKey == "" or categoryKey == "all" then
        return GodSystemApp.services.runtime.text("ShopCategory_All", "All categories")
    end
    local _, label = gsShopCategoryFromRaw(categoryKey)
    return label or categoryKey
end

function GodSystemApp.services.runtime.getPricingCategoryKey(fullType, item)
    return GodSystemEconomyPolicy.quote(fullType, item, { kind = "category" }).category
end

function GodSystemApp.services.runtime.getItemPriceInfo(fullType, item)
    local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "economy" })
    return {
        buyPrice = quote.finalBuy,
        sellPrice = quote.recycleValue,
        category = quote.category,
        source = quote.priceSource,
        quote = quote,
    }
end

function GodSystemApp.services.runtime.getItemBuyPrice(fullType, item)
    return (GodSystemApp.services.runtime.getItemPriceInfo(fullType, item).buyPrice or 0)
end

function GodSystemApp.services.runtime.getItemSellPrice(fullType, item)
    return (GodSystemApp.services.runtime.getItemPriceInfo(fullType, item).sellPrice or 0)
end

function GodSystemApp.services.runtime.getShopItemUnitPrice(shopItem)
    if not shopItem then
        return 0
    end
    local items = shopItem.items or {}
    if #items > 0 then
        local total = 0
        for i = 1, #items do
            local fullType = items[i].fullType
            local count = math.max(1, math.floor(tonumber(items[i].count) or 1))
            if not fullType then
                return math.max(0, math.floor(tonumber(shopItem.price) or 0))
            end
            total = total + (GodSystemApp.services.runtime.getItemBuyPrice(fullType) * count)
        end
        if total > 0 then
            return total
        end
    end
    return math.max(0, math.floor(tonumber(shopItem.price) or 0))
end

function GodSystemApp.services.runtime.getAutoShopBuyPriceForItem(fullType, sellValue)
    return GodSystemEconomyPolicy.quote(fullType, nil, { kind = "shop" }).finalBuy
end

function GodSystemApp.services.runtime.getAutoShopListOnlyCost(fullType, sellValue)
    return GodSystemEconomyPolicy.listingCost(fullType, nil)
end

function GodSystemApp.services.runtime.getEconomyQuote(fullType, item, context)
    return GodSystemEconomyPolicy.quote(fullType, item, context or { kind = "display" })
end

function GodSystemApp.services.runtime.getEconomyQuoteDetail(fullType, item, adminDetail)
    local quote = GodSystemApp.services.runtime.getEconomyQuote(fullType, item, { kind = "display" })
    local statusLabels = {
        verified = GodSystemApp.services.runtime.text("EconomyValue_Verified", "Verified"),
        unverified = GodSystemApp.services.runtime.text("EconomyValue_Unverified", "Unverified"),
        not_applicable = GodSystemApp.services.runtime.text("EconomyValue_NotApplicable", "No conversion"),
        invalid = GodSystemApp.services.runtime.text("EconomyValue_Excluded", "Excluded"),
    }
    local sourceLabels = {
        price_table = GodSystemApp.services.runtime.text("EconomySource_PriceTable", "Reference price table"),
        category_fallback = GodSystemApp.services.runtime.text("EconomySource_Category", "Category fallback"),
    }
    local lines = {
        GodSystemApp.services.runtime.text("EconomyDetail_Buy", "Shop price") .. ": " .. tostring(quote.finalBuy or 0),
        GodSystemApp.services.runtime.text("EconomyDetail_Recycle", "Recycle value") .. ": " .. tostring(quote.recycleValue or 0),
    }
    if (quote.conversionValue or 0) > 0 then
        lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_Conversion", "Unpack recycle total") .. ": " .. tostring(quote.conversionValue)
            .. " | " .. GodSystemApp.services.runtime.text("EconomyDetail_SafeMinimum", "safe minimum") .. ": " .. tostring(quote.safeMinimum or 0)
    elseif quote.verificationStatus == "unverified" then
        if (quote.dynamicFloor or 0) > 0 then
            lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_Unverified", "Dynamic output is not verifiable; a conservative shop floor is applied.")
        else
            lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_UnverifiedExact", "Dynamic output is not verifiable; the existing exact price is retained without the generic risk floor.")
        end
    end
    if adminDetail == true then
        lines[#lines + 1] = "fullType: " .. tostring(fullType or "")
        lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_Reference", "Reference") .. ": " .. tostring(quote.referenceBuy or 0)
            .. " | " .. GodSystemApp.services.runtime.text("EconomyDetail_Category", "Category") .. ": " .. tostring(GodSystemApp.services.runtime.getShopCategoryLabel(quote.category or "normal"))
            .. " | " .. GodSystemApp.services.runtime.text("EconomyDetail_Source", "Source") .. ": " .. tostring(sourceLabels[quote.priceSource] or quote.priceSource or "")
        lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_Status", "Verification") .. ": " .. tostring(statusLabels[quote.verificationStatus] or quote.verificationStatus or "")
    end
    for i = 1, #(quote.warnings or {}) do
        if quote.warnings[i] == "admin_below_safe_minimum" then
            lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyWarning_Arbitrage", "Warning: administrator price is below the safe minimum and may allow repeated profit.")
        elseif adminDetail == true then
            local warningKey = "EconomyWarning_" .. tostring(quote.warnings[i]):gsub("[^A-Za-z0-9]+", "_")
            lines[#lines + 1] = GodSystemApp.services.runtime.text("EconomyDetail_Warning", "Warning") .. ": " .. GodSystemApp.services.runtime.text(warningKey, tostring(quote.warnings[i]))
        end
    end
    return table.concat(lines, "\n"), quote
end

function GodSystemApp.services.runtime.calculateRecyclePayout(fullType, rawValue, removedCount)
    rawValue = math.floor(tonumber(rawValue) or 0)
    if rawValue <= 0 then
        return 0
    end
    return rawValue
end

function GodSystemApp.services.runtime.getShopLabel(shopItem)
    if not shopItem then
        return GodSystemApp.services.runtime.text("Shop_Missing_Label", "Unknown")
    end
    if shopItem.unlocked then
        return GodSystemApp.services.runtime.getUnlockedShopLabel(shopItem.fullType, shopItem)
    end
    local fallback = shopItem.id or "Shop item"
    if shopItem.items and #shopItem.items == 1 then
        fallback = GodSystemApp.services.runtime.getItemDisplayName(shopItem.items[1].fullType, fallback)
    end
    return GodSystemApp.services.runtime.text("Shop_" .. tostring(shopItem.id) .. "_Label", fallback)
end

function GodSystemApp.services.runtime.getUnlockedShopLabel(fullType, item)
    local localized = GodSystemApp.services.runtime.getItemDisplayName(fullType)
    local label = item and item.label or nil
    if localized and localized ~= "" and localized ~= fullType then
        return localized
    end
    if label and tostring(label) ~= "" and tostring(label) ~= tostring(fullType or "") then
        return tostring(label)
    end
    return fullType or (item and item.id) or GodSystemApp.services.runtime.text("Shop_Unlocked_Label", "Unlocked item")
end

function GodSystemApp.services.runtime.getShopGroup(shopItem)
    if not shopItem then
        return GodSystemApp.services.runtime.text("Group_Shop", "Shop")
    end
    if shopItem.unlocked then
        return GodSystemApp.services.runtime.text("Group_Unlocked", "Unlocked")
    end
    return GodSystemApp.services.runtime.text("Shop_" .. tostring(shopItem.id) .. "_Group", shopItem.group or "Shop")
end

function GodSystemApp.services.runtime.getShopDescription(shopItem)
    if not shopItem then
        return ""
    end
    if shopItem.unlocked then
        return GodSystemApp.services.runtime.text("Shop_Unlocked_Description", "This item was unlocked by recycling it.")
    end
    return GodSystemApp.services.runtime.text("Shop_" .. tostring(shopItem.id) .. "_Description", shopItem.description or "")
end

function GodSystemApp.services.runtime.getTaskTitle(task)
    if not task then
        return GodSystemApp.services.runtime.text("Task_Missing_Title", "Task")
    end
    local id = task.sourceId or task.id or "missing"
    return GodSystemApp.services.runtime.text("Task_" .. tostring(id) .. "_Title", task.title or id)
end

function GodSystemApp.services.runtime.getTaskDescription(task)
    if not task then
        return ""
    end
    local id = task.sourceId or task.id or "missing"
    return GodSystemApp.services.runtime.text("Task_" .. tostring(id) .. "_Description", task.description or "")
end

function GodSystemApp.services.runtime.getTaskKindLabel(task)
    local kind = task and task.kind or ""
    local fallback = {
        kill = "Kill",
        recycleItems = "Recycle",
        recyclePoints = "Recycle",
        surviveHours = "Survive",
        turnInItem = "Turn in",
        turnInAnyItem = "Turn in",
        spendPoints = "Spend",
        buyItems = "Buy",
        moveDistance = "Move",
    }
    return GodSystemApp.services.runtime.text("TaskKind_" .. tostring(kind), fallback[kind] or tostring(kind or "Task"))
end

function GodSystemApp.services.runtime.getTaskDifficulty(task)
    return GodSystemTaskOrder.difficultyLabel(task)
end

function GodSystemApp.services.runtime.getTaskListTitle(task)
    if not task then
        return GodSystemApp.services.runtime.text("Task_Missing_Title", "Task")
    end
    return "[" .. GodSystemApp.services.runtime.getTaskKindLabel(task) .. "][" .. GodSystemApp.services.runtime.getTaskDifficulty(task) .. "] " .. GodSystemApp.services.runtime.getTaskTitle(task)
end

function GodSystemApp.services.runtime.getTaskListStatusLine(task)
    if not task then
        return ""
    end
    local progress = math.min(GodSystemApp.services.runtime.getTaskDisplayProgress(task), math.max(1, math.floor(tonumber(task.target) or 1)))
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    local parts = { tostring(progress) .. "/" .. tostring(target) }
    if task.status == "active" then
        table.insert(parts, GodSystemApp.services.runtime.text("Short_Remain", "Left") .. tostring(GodSystemApp.services.runtime.getRemainingHours(task)) .. GodSystemApp.services.runtime.text("Unit_Hour", "h"))
    else
        table.insert(parts, GodSystemApp.services.runtime.getTaskStatusText(task))
    end
    return table.concat(parts, "  ")
end

function GodSystemApp.services.runtime.isAutoShopUnlockAllowed(fullType)
    if not GodSystemConfig.AutoUnlockShopFromRecycle then
        return false
    end
    if GodSystemItemConfig.isShopItemEnabled(fullType, true) == false then
        return false
    end
    if not fullType or GodSystemConfig.AutoShopBlacklist[fullType] or GodSystemConfig.RecycleBlacklist[fullType] then
        return false
    end
    local moduleName = gsGetModuleName(fullType)
    if GodSystemConfig.AutoShopAllowAnyModule == true then
        return moduleName ~= nil
    end
    return moduleName ~= nil and GodSystemConfig.AutoShopAllowedModules[moduleName] == true
end

function GodSystemApp.services.runtime.getConfiguredShopKeySet()
    local result = {}
    for key, value in pairs(GodSystemApp.services.runtime.configuredShopKeySet or {}) do result[key] = value end
    for fullType, override in pairs(GodSystemItemConfig.getItemOverrides() or {}) do
        if override.shopMode == "forced" and fullType ~= "Moveables.Moveable" then
            result[GodSystemShopVariants.getKey(fullType)] = true
        end
    end
    for variantKey, override in pairs(GodSystemItemConfig.getShopVariantOverrides() or {}) do
        if GodSystemItemConfig.getShopVariantMode(variantKey, override.fullType) == "forced" then
            result[variantKey] = true
        end
    end
    return result
end

function GodSystemApp.services.runtime.getForcedShopItemsList()
    local result = {}
    for fullType, override in pairs(GodSystemItemConfig.getItemOverrides() or {}) do
        if override.shopMode == "forced" and GodSystemApp.services.runtime.itemExists(fullType)
            and fullType ~= "Moveables.Moveable"
            and GodSystemItemEligibility.isEconomicItemAllowed(fullType, "shop") then
            result[#result + 1] = {
                id = "admin:" .. fullType,
                fullType = fullType,
                variantKey = fullType,
                label = GodSystemApp.services.runtime.getItemDisplayName(fullType),
                group = "admin",
                items = { { fullType = fullType, count = 1 } },
                adminForced = true,
            }
        end
    end
    for variantKey, override in pairs(GodSystemItemConfig.getShopVariantOverrides() or {}) do
        if GodSystemItemConfig.getShopVariantMode(variantKey, override.fullType) == "forced"
            and GodSystemApp.services.runtime.itemExists(override.fullType)
            and GodSystemItemEligibility.isEconomicItemAllowed(override.fullType, "shop") then
            result[#result + 1] = {
                id = "admin:" .. variantKey,
                fullType = override.fullType,
                worldSprite = override.worldSprite,
                variantKey = variantKey,
                label = GodSystemApp.services.runtime.getItemDisplayName(override.fullType),
                group = "admin",
                items = { { fullType = override.fullType, worldSprite = override.worldSprite, count = 1 } },
                adminForced = true,
            }
        end
    end
    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

function GodSystemApp.services.runtime.unlockAutoShopItem(fullType, label, sellValue, itemOrSprite)
    if not GodSystemApp.services.runtime.isAutoShopUnlockAllowed(fullType) then
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    data.unlockedShopItems = data.unlockedShopItems or {}
    local baseSell = math.max(1, math.floor(tonumber(sellValue) or 1))
    local buyPrice = GodSystemApp.services.runtime.getAutoShopBuyPriceForItem(fullType, baseSell)
    local worldSprite = GodSystemShopVariants.getWorldSprite(itemOrSprite)
    local variantKey = GodSystemShopVariants.getKey(fullType, worldSprite)
    local known, source = GodSystemShopVariants.isListingKnown(data, GodSystemApp.services.runtime.getConfiguredShopKeySet(), variantKey)
    if known then return false, source, variantKey end

    data.unlockedShopItems[variantKey] = {
        fullType = fullType,
        worldSprite = worldSprite,
        variantKey = variantKey,
        module = gsGetModuleName(fullType),
        label = label or GodSystemApp.services.runtime.getItemDisplayName(fullType),
        sellPrice = baseSell,
        buyPrice = buyPrice,
        unlockedAt = math.floor(gsNowHours()),
        hidden = false,
    }
    GodSystemApp.services.runtime.save()
    return true, "created", variantKey
end

function GodSystemApp.services.runtime.listOnlyAutoShopItem(fullType, itemId)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false or GodSystemApp.services.runtime.isFeatureEnabled("EnableShop") == false then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end
    if not fullType or fullType == "" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    if not GodSystemApp.services.runtime.isAutoShopUnlockAllowed(fullType) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    if itemId == nil or tostring(itemId or "") == "" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListItemChanged", "The selected item changed; reopen the recycle page"))
        return false
    end
    local item = gsInventoryItemById(itemId)
    if item and item.getFullType and item:getFullType() ~= fullType then item = nil end
    if not item then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end

    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local known, source = GodSystemShopVariants.isListingKnown(data, GodSystemApp.services.runtime.getConfiguredShopKeySet(), variantKey)
    if known then
        if source == "configured" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopConfiguredAlreadyListed", "This built-in shop item is already listed."))
        elseif data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopHiddenAlreadyListed", "This item is listed but hidden. Restore it from hidden management."))
        else
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyAlreadyUnlocked", "This item is already listed."))
        end
        return false
    end
    if not GodSystemApp.services.runtime.canContextRecycleItem(item) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end
    local label = (item and item.getDisplayName and item:getDisplayName()) or GodSystemApp.services.runtime.getItemDisplayName(fullType)
    local sellValue = GodSystemApp.services.runtime.getItemSellPrice(fullType, item)
    local cost, buyPrice = GodSystemApp.services.runtime.getAutoShopListOnlyCost(fullType, sellValue)
    if GodSystemApp.services.runtime.getSpendableBalance() < cost then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyInsufficient", "Not enough system coins to list this item."))
        return false
    end
    local paid, fromBank, fromCash = GodSystemApp.services.runtime.spendCurrency(cost)
    if not paid then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyInsufficient", "Not enough system coins to list this item."))
        return false
    end
    local created, failureSource = GodSystemApp.services.runtime.unlockAutoShopItem(fullType, label, sellValue, item)
    if not created then
        GodSystemApp.services.runtime.refundCurrencySources(fromBank, fromCash)
        if failureSource == "configured" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopConfiguredAlreadyListed", "This built-in shop item is already listed."))
        elseif data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopHiddenAlreadyListed", "This item is listed but hidden. Restore it from hidden management."))
        else
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyAlreadyUnlocked", "This item is already listed."))
        end
        return false
    end

    gsAppendHistory(data, { kind = "shop", text = gsFormatText(GodSystemApp.services.runtime.text("History_ListOnlyAutoShop", "Listed {1}, fee {2} coins."), { label, cost, buyPrice }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_ListOnlySuccess", "Listed {1}, fee {2} coins."), { label, cost, buyPrice }))
    return true
end

function GodSystemApp.services.runtime.getUnlockedShopItemsList(includeHidden)
    local data = GodSystemApp.services.runtime.getData()
    local result = {}
    local rows = GodSystemShopVariants.getUnlockedRows(data, includeHidden)
    for i = 1, #rows do
        local item = rows[i]
        local variantKey = item.variantKey or GodSystemShopVariants.getKey(item.fullType, item.worldSprite)
        local fullType = item.fullType or variantKey
        local mode = GodSystemItemConfig.getShopVariantMode(variantKey, fullType)
        if mode ~= "disabled" and mode ~= "forced" and GodSystemApp.services.runtime.itemExists(fullType) then
            table.insert(result, {
                id = "unlocked_" .. variantKey,
                fullType = fullType,
                worldSprite = item.worldSprite,
                variantKey = variantKey,
                label = GodSystemApp.services.runtime.getUnlockedShopLabel(fullType, item),
                group = "unlocked",
                price = GodSystemApp.services.runtime.getAutoShopBuyPriceForItem(fullType, item.sellPrice or 1),
                description = "Unlocked by recycling.",
                items = { { fullType = fullType, worldSprite = item.worldSprite, count = 1 } },
                unlocked = true,
                hidden = item.hidden == true,
            })
        end
    end
    table.sort(result, function(a, b)
        local left = tostring(a.label or a.id)
        local right = tostring(b.label or b.id)
        if left == right then return tostring(a.variantKey or a.id) < tostring(b.variantKey or b.id) end
        return left < right
    end)
    return result
end

function GodSystemApp.services.runtime.setShopItemHidden(variantKey, hidden)
    if not variantKey then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
    if GodSystemItemConfig.getShopVariantMode(variantKey, stored and stored.fullType or variantKey) == "forced" then return false end
    local ok, changed, item = GodSystemShopVariants.setHidden(data, variantKey, hidden)
    if not ok or not item then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local label = item.label or GodSystemApp.services.runtime.getItemDisplayName(item.fullType or variantKey)
    local targetHidden = hidden == true
    if changed then
        local historyKey = targetHidden and "History_ShopItemHidden" or "History_ShopItemVisible"
        local historyFallback = targetHidden and "Hidden shop item: " or "Restored shop item: "
        gsAppendHistory(data, { kind = "shop", text = GodSystemApp.services.runtime.text(historyKey, historyFallback) .. tostring(label) })
        GodSystemApp.services.runtime.save()
    end
    local notifyKey = targetHidden and "Notify_ShopItemHidden" or "Notify_ShopItemVisible"
    local notifyFallback = targetHidden and "Hidden shop item: " or "Restored shop item: "
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(notifyKey, notifyFallback) .. tostring(label))
    return true
end

function GodSystemApp.services.runtime.normalizeShopHiddenVariantKeys(values)
    local keys, seen = {}, {}
    for i = 1, #(values or {}) do
        local key = tostring(values[i] or "")
        if key ~= "" and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

function GodSystemApp.services.runtime.setShopItemsHidden(variantKeys, hidden)
    local keys = GodSystemApp.services.runtime.normalizeShopHiddenVariantKeys(variantKeys)
    if #keys == 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    if #keys > 500 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopItemsTooMany", "Select at most 500 shop items at once."))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local changedKeys, skippedKeys = {}, {}
    for i = 1, #keys do
        local stored = data.unlockedShopItems and data.unlockedShopItems[keys[i]] or nil
        local forced = GodSystemItemConfig.getShopVariantMode(keys[i], stored and stored.fullType or keys[i]) == "forced"
        local found, changed = false, false
        if not forced then found, changed = GodSystemShopVariants.setHidden(data, keys[i], hidden == true) end
        if found and changed then changedKeys[#changedKeys + 1] = keys[i]
        else skippedKeys[#skippedKeys + 1] = keys[i] end
    end
    local targetHidden = hidden == true
    if #changedKeys > 0 then
        local historyKey = targetHidden and "History_ShopItemsHidden" or "History_ShopItemsVisible"
        local historyFallback = targetHidden and "Hidden {1} shop items" or "Restored {1} shop items"
        gsAppendHistory(data, {
            kind = "shop",
            text = GodSystemApp.services.runtime.text(historyKey, historyFallback):gsub("{1}", tostring(#changedKeys)),
        })
        GodSystemApp.services.runtime.save()
    end
    local notifyKey = targetHidden and "Notify_ShopItemsHidden" or "Notify_ShopItemsVisible"
    local notifyFallback = targetHidden and "Shop items changed: {1}; skipped: {2}" or "Shop items restored: {1}; skipped: {2}"
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(notifyKey, notifyFallback)
        :gsub("{1}", tostring(#changedKeys)):gsub("{2}", tostring(#skippedKeys)))
    return true
end

function GodSystemApp.services.runtime.deleteShopItem(variantKey)
    if not variantKey then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
    if GodSystemItemConfig.getShopVariantMode(variantKey, stored and stored.fullType or variantKey) == "forced" then return false end
    local ok, item = GodSystemShopVariants.deleteUnlocked(data, variantKey)
    if not ok or not item then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopItemMissing", "The player-listed item no longer exists."))
        return false
    end
    local label = item.label or GodSystemApp.services.runtime.getItemDisplayName(item.fullType or variantKey)
    gsAppendHistory(data, { kind = "shop", text = GodSystemApp.services.runtime.text("History_ShopItemDeleted", "Delisted shop item: ") .. tostring(label) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopItemDeleted", "Delisted shop item: ") .. tostring(label))
    return true
end

function GodSystemApp.services.runtime.getConfiguredShopFullTypeSet()
    local result = {}
    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local shopItem = GodSystemConfig.ShopItems[i]
        local items = shopItem and shopItem.items or {}
        for j = 1, #items do
            if items[j].fullType then
                result[items[j].fullType] = true
            end
        end
    end
    return result
end
end
