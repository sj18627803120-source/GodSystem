_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Recycle"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Recycle then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Recycle = true
    setfenv(1, runtimeEnvironment)

function GodSystemApp.services.runtime.buyShopItem(shopItem, quantity)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableShop") == false then
        GodSystemApp.services.runtime.notify("Shop disabled")
        return false
    end
    if not shopItem then
        return false
    end
    if shopItem.featureKey and GodSystemRuntimeConfig.isFeatureEnabled(shopItem.featureKey) == false then
        GodSystemApp.services.runtime.notify("Shop item disabled")
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    if shopItem.unlocked == true then
        local variantKey = shopItem.variantKey or GodSystemShopVariants.getKey(shopItem.fullType, shopItem.worldSprite)
        local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
        if not stored then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopItemMissing", "This player-listed item no longer exists."))
            return false
        elseif stored.hidden == true then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ShopHiddenAlreadyListed", "This item is hidden. Restore it from hidden management."))
            return false
        end
    end
    local primaryFullType = GodSystemApp.services.runtime.getShopPrimaryFullType(shopItem)
    if primaryFullType and GodSystemItemConfig.isShopItemEnabled(primaryFullType, true) == false then
        GodSystemApp.services.runtime.notify("Shop item disabled")
        return false
    end
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local unitPrice = GodSystemApp.services.runtime.getShopItemUnitPrice(shopItem)
    local price = unitPrice * quantity
    if not GodSystemApp.services.runtime.canAfford(price) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local available, reason, availableItems, missingItems = GodSystemApp.services.runtime.shopItemIsAvailable(shopItem)
    if not available then
        GodSystemApp.services.runtime.notify(reason)
        return false
    end

    local expected = 0
    local grantItems = gsMultiplyItems(availableItems or shopItem.items, quantity)
    for i = 1, #(grantItems or {}) do
        expected = expected + math.max(1, math.floor(grantItems[i].count or 1))
    end
    local given, _, addedItems = GodSystemApp.services.runtime.giveItems(grantItems, true)
    if expected > 0 and given < expected then
        GodSystemApp.services.runtime.removeAddedItems(addedItems)
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ItemGrantFailed", "Failed to give item, no currency spent"))
        return false
    end
    if not GodSystemApp.services.runtime.addPoints(-price) then
        GodSystemApp.services.runtime.removeAddedItems(addedItems)
        return false
    end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + price
    data.stats.boughtItems = (data.stats.boughtItems or 0) + quantity
    local quantityText = quantity > 1 and (" x" .. tostring(quantity)) or ""
    gsAppendHistory(data, { kind = "shop", text = GodSystemApp.services.runtime.text("History_Bought", "Bought: ") .. tostring(GodSystemApp.services.runtime.getShopLabel(shopItem)) .. quantityText .. " -" .. tostring(price) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    if missingItems and #missingItems > 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BoughtPartial", "Bought available items, skipped missing: ") .. tostring(#missingItems))
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Bought", "Bought: ") .. tostring(GodSystemApp.services.runtime.getShopLabel(shopItem)) .. quantityText)
    end
    GodSystemApp.services.runtime.save()
    return true
end

function gsGetRecycleValue(item, allowContainers)
    if not item then
        return 0
    end
    local fullType = item:getFullType()
    if allowContainers == true then
        local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "recycle" })
        return math.max(0, math.floor(tonumber(quote and quote.recycleValue) or 0))
    end
    local fullType = item.getFullType and item:getFullType() or ""
    if GodSystemConfig.RecycleBlacklist[fullType] then
        return 0
    end
    if allowContainers ~= true and GodSystemConfig.AllowRecycleContainers ~= true and gsItemHasInventory(item) then
        return 0
    end
    local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "recycle" })
    if quote.eligible ~= true then return 0 end
    return math.max(1, math.floor(tonumber(quote.recycleValue) or 1))
end

function GodSystemApp.services.runtime.getRecycleValue(item)
    return gsGetRecycleValue(item, false)
end

function GodSystemApp.services.runtime.getContextRecycleValue(item)
    return gsGetRecycleValue(item, true)
end

function gsIsKeyItem(item)
    if not item then return false end
    if instanceof and instanceof(item, "Key") then return true end
    if item.isItemType and ItemType and ItemType.KEY_RING then
        local ok, value = pcall(function() return item:isItemType(ItemType.KEY_RING) end)
        if ok and value == true then return true end
    end
    if item.hasTag and ItemTag and ItemTag.KEY_RING then
        local ok, value = pcall(function() return item:hasTag(ItemTag.KEY_RING) end)
        if ok and value == true then return true end
    end
    return false
end

function GodSystemApp.services.runtime.canContextRecycleItem(item)
    return GodSystemManualRecycle.canRecycle(item)
end

function GodSystemApp.services.runtime.canContextListItem(item, contextCache)
    local allowed, reason
    local cachedRecycle = contextCache and contextCache.recycle and contextCache.recycle[item] or nil
    if cachedRecycle then
        allowed, reason = cachedRecycle.allowed, cachedRecycle.reason
    else
        allowed, reason = GodSystemApp.services.runtime.canContextRecycleItem(item)
    end
    if not allowed then return false, reason end
    local fullType = item:getFullType()
    if not GodSystemApp.services.runtime.isAutoShopUnlockAllowed(fullType) then return false, "notListable" end
    local data = contextCache and contextCache.data or GodSystemApp.services.runtime.getData()
    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local configured = contextCache and contextCache.configuredShopKeySet
        or GodSystemApp.services.runtime.getConfiguredShopKeySet()
    local known, source = GodSystemShopVariants.isListingKnown(data, configured, variantKey)
    if known then
        if source == "configured" then return false, "configuredListed" end
        if data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then return false, "hiddenListed" end
        return false, "alreadyListed"
    end
    return true, nil
end

function GodSystemApp.services.runtime.getInventoryRecycleGroups()
    local player = gsPlayer()
    local result = {}
    local order = {}
    if not player then
        return result, order
    end

    local found = gsFindInventoryItems(nil, false, false)
    for i = 1, #found do
        local item = found[i].item
        if item then
            local fullType = item:getFullType()
            local value = GodSystemApp.services.runtime.getRecycleValue(item)
            if value > 0 then
                if not result[fullType] then
                    result[fullType] = {
                        fullType = fullType,
                        label = item:getDisplayName() or GodSystemApp.services.runtime.getItemDisplayName(fullType),
                        count = 0,
                        valueEach = value,
                        rawTotalValue = 0,
                        totalValue = 0,
                        itemIds = {},
                    }
                    table.insert(order, fullType)
                end
                if item.getID then result[fullType].itemIds[#result[fullType].itemIds + 1] = tostring(item:getID()) end
                if not result[fullType].listItemId then
                    local listable = GodSystemApp.services.runtime.canContextListItem(item)
                    if listable == true and item.getID then
                        result[fullType].listItemId = tostring(item:getID())
                        result[fullType].listVariantKey = GodSystemShopVariants.getKey(fullType, item)
                        result[fullType].listWorldSprite = GodSystemShopVariants.getWorldSprite(item)
                    end
                end
                result[fullType].count = result[fullType].count + 1
                result[fullType].rawTotalValue = result[fullType].rawTotalValue + value
                result[fullType].totalValue = GodSystemApp.services.runtime.calculateRecyclePayout(fullType, result[fullType].rawTotalValue, result[fullType].count)
            end
        end
    end

    table.sort(order, function(a, b)
        return (result[a].label or a) < (result[b].label or b)
    end)
    return result, order
end

function GodSystemApp.services.runtime.removeInventoryItems(fullType, count)
    local player = gsPlayer()
    if not player then
        return 0, 0
    end

    local found = gsFindInventoryItems(fullType, false, false)
    local totalValue = 0
    local removedDetails = {}
    count = math.max(1, math.floor(count or 1))

    local removed = 0
    for i = 1, #found do
        if removed >= count then
            break
        end
        local item = found[i].item
        local value = GodSystemApp.services.runtime.getRecycleValue(item)
        if value > 0 then
            local unlockValue = GodSystemApp.services.runtime.getItemSellPrice(item:getFullType(), item) or value
            totalValue = totalValue + value
            table.insert(removedDetails, {
                fullType = item:getFullType(),
                label = item:getDisplayName() or GodSystemApp.services.runtime.getItemDisplayName(item:getFullType()),
                sellValue = unlockValue,
                worldSprite = GodSystemShopVariants.getWorldSprite(item),
            })
            found[i].container:Remove(item)
            removed = removed + 1
        end
    end

    return removed, totalValue, removedDetails
end

function GodSystemApp.services.runtime.removeAnyInventoryItems(fullTypes, count)
    local removed = 0
    local totalValue = 0
    if not fullTypes then
        return removed, totalValue
    end
    for i = 1, #fullTypes do
        if removed >= count then
            break
        end
        local take, value = GodSystemApp.services.runtime.removeInventoryItems(fullTypes[i], count - removed)
        removed = removed + take
        totalValue = totalValue + value
    end
    return removed, totalValue
end

function GodSystemApp.services.runtime.recycleInventoryItems(fullType, count)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false then
        GodSystemApp.services.runtime.notify("Recycle disabled")
        return false
    end
    local found = gsFindInventoryItems(fullType, false, false)
    if #found <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end
    count = math.max(1, math.floor(count or 1))
    count = math.min(count, #found)
    local removed, totalValue, removedDetails = GodSystemApp.services.runtime.removeInventoryItems(fullType, count)
    if removed <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end
    local rawValue = GodSystemApp.services.runtime.calculateRecyclePayout(fullType, totalValue, removed)
    if rawValue <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end
    local totalValue, diminished = GodSystemApp.services.runtime.applyRecycleDailyPayout(rawValue)

    local data = GodSystemApp.services.runtime.getData()
    data.stats.recycledItems = (data.stats.recycledItems or 0) + removed
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + totalValue
    GodSystemApp.services.runtime.addPoints(totalValue, GodSystemApp.services.runtime.text("Reason_Recycle", "Recycle"))
    if GodSystemApp.services.runtime.isRecycleUnlockMode() then
        for i = 1, #(removedDetails or {}) do
            local detail = removedDetails[i]
            GodSystemApp.services.runtime.unlockAutoShopItem(detail.fullType, detail.label, detail.sellValue, detail.worldSprite)
        end
    end
    local historyText = GodSystemApp.services.runtime.text("History_Recycled", "Recycled ") .. tostring(removed) .. GodSystemApp.services.runtime.text("Unit_Item", " items, gained ") .. tostring(totalValue) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins")
    if diminished then
        historyText = historyText .. " (" .. GodSystemApp.services.runtime.text("History_RecycleDiminished", "daily limit diminished from ") .. tostring(rawValue) .. ")"
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleDiminished", "Daily recycle limit reached, payout: ") .. tostring(totalValue) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
    end
    gsAppendHistory(data, { kind = "recycle", text = historyText })
    GodSystemApp.services.runtime.save()
    return true
end

function gsContainerContainsItem(container, item)
    return GodSystemApp.services.runtime.containerContainsItem(container, item)
end

function gsRestoreContextItems(player, removed)
    local inventory = player and player:getInventory() or nil
    if not inventory then return false end
    local restored = true
    for i = 1, #(removed or {}) do
        local row = removed[i]
        local ok = pcall(function() inventory:AddItem(row.item) end)
        restored = restored and ok
        if ok and row.equipment then
            GodSystemManualRecycle.restoreEquipped(player, row.item, row.equipment, GodSystemManualRecycle.defaultBridge())
        end
    end
    return restored
end

function gsRestoreContextUseState(player, row)
    if not player or not row or not row.item then return end
    if row.equipment then
        GodSystemManualRecycle.restoreEquipped(player, row.item, row.equipment, GodSystemManualRecycle.defaultBridge())
    end
end

function GodSystemApp.services.runtime.recycleSelectedItems(mode, itemIds, allowDestroyContents, containerContentSignatures, clientSkipped)
    mode = tostring(mode or "")
    if mode ~= "recycle" and mode ~= "recycleAndList" and mode ~= "listOnly" then return false end
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleDisabled", "Recycle is disabled"))
        return false
    end
    local player = gsPlayer()
    if not player then return false end

    local selected = {}
    local seen = {}
    local types = {}
    local typeOrder = {}
    local skipped = math.min(10000, math.max(0, math.floor(tonumber(clientSkipped) or 0)))
    local listingSkipped = 0
    for i = 1, #(itemIds or {}) do
        local id = tostring(itemIds[i] or "")
        if id ~= "" and not seen[id] then
            seen[id] = true
            local item, container = gsInventoryItemById(id)
            if not item or not container then
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleSelectionChanged", "Selected items changed; action cancelled"))
                return false
            end
            local allowed = GodSystemApp.services.runtime.canContextRecycleItem(item)
            local fullType = item:getFullType()
            local eligible = allowed == true
            local listable = true
            if eligible and mode ~= "recycle" then
                listable = GodSystemApp.services.runtime.canContextListItem(item) == true
                if not listable and mode == "listOnly" then eligible = false end
                if not listable and mode == "recycleAndList" then listingSkipped = listingSkipped + 1 end
            end
            if not eligible then
                skipped = skipped + 1
            elseif mode ~= "listOnly" then
                local expected = type(containerContentSignatures) == "table" and containerContentSignatures[id] or nil
                local hasContents = gsItemInventoryCount(item) > 0
                if (hasContents or expected) and (allowDestroyContents ~= true or not expected or GodSystemApp.services.runtime.getContextContainerSignature(item) ~= expected) then
                    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleSelectionContainerChanged", "Container contents require confirmation"))
                    return false
                end
            end
            if eligible then
                local variantKey = GodSystemShopVariants.getKey(fullType, item)
                local groupKey = mode == "recycle" and fullType or variantKey
                selected[#selected + 1] = { item = item, container = container, fullType = fullType, variantKey = variantKey }
                if not types[groupKey] then
                    types[groupKey] = { item = item, fullType = fullType, raw = 0, count = 0, listable = listable }
                    typeOrder[#typeOrder + 1] = groupKey
                end
                types[groupKey].raw = types[groupKey].raw + GodSystemApp.services.runtime.getContextRecycleValue(item)
                types[groupKey].count = types[groupKey].count + 1
            end
        end
    end
    skipped = math.max(skipped, listingSkipped)
    if #selected <= 0 then
        GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_RecycleSelectionEmptySkipped", "No eligible items; skipped {1}"), { skipped }))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    if mode == "listOnly" then
        local totalCost = 0
        local listRows = {}
        for i = 1, #typeOrder do
            local variantKey = typeOrder[i]
            local row = types[variantKey]
            local fullType = row.fullType
            local sellValue = GodSystemApp.services.runtime.getItemSellPrice(fullType, row.item)
            local cost = GodSystemApp.services.runtime.getAutoShopListOnlyCost(fullType, sellValue)
            totalCost = totalCost + cost
            listRows[#listRows + 1] = { fullType = fullType, item = row.item, sellValue = sellValue }
        end
        local paid, fromBank, fromCash = GodSystemApp.services.runtime.spendCurrency(totalCost)
        if not paid then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListOnlyInsufficient", "Not enough system coins"))
            return false
        end
        local unlocked = {}
        for i = 1, #listRows do
            local row = listRows[i]
            if not GodSystemApp.services.runtime.unlockAutoShopItem(row.fullType, row.item:getDisplayName(), row.sellValue, row.item) then
                for j = 1, #unlocked do data.unlockedShopItems[unlocked[j]] = nil end
                GodSystemApp.services.runtime.refundCurrencySources(fromBank, fromCash)
                GodSystemApp.services.runtime.save()
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleSelectionChanged", "Selected items changed; action cancelled"))
                return false
            end
            unlocked[#unlocked + 1] = GodSystemShopVariants.getKey(row.fullType, row.item)
        end
        local data = GodSystemApp.services.runtime.getData()
        gsAppendHistory(data, { kind = "shop", text = gsFormatText(GodSystemApp.services.runtime.text("History_RecycleSelectionListOnly", "Listed {1} item types for {2} coins"), { #listRows, totalCost }) })
        GodSystemApp.services.runtime.save()
        local notifyKey = skipped > 0 and "Notify_RecycleSelectionListOnlyPartial" or "Notify_RecycleSelectionListOnly"
        GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text(notifyKey, "Listed {1} item types for {2} coins; skipped {3}"), { #listRows, totalCost, skipped }))
        return true
    end

    local rawPayout = 0
    for i = 1, #typeOrder do
        local row = types[typeOrder[i]]
        rawPayout = rawPayout + GodSystemApp.services.runtime.calculateRecyclePayout(row.fullType, row.raw, row.count)
    end
    local removed = {}
    local equipmentBridge = GodSystemManualRecycle.defaultBridge()
    for i = 1, #selected do
        local row = selected[i]
        local item = row.item
        local equipment = GodSystemManualRecycle.captureEquipped(player, item, equipmentBridge)
        if not GodSystemManualRecycle.detachEquipped(player, item, equipmentBridge) then
            GodSystemManualRecycle.restoreEquipped(player, item, equipment, equipmentBridge)
            gsRestoreContextItems(player, removed)
            return false
        end
        local ok = pcall(function() row.container:Remove(item) end)
        if not ok or gsContainerContainsItem(row.container, item) then
            local current = {
                item = item,
                equipment = equipment,
            }
            if gsContainerContainsItem(row.container, item) then
                gsRestoreContextUseState(player, current)
            else
                removed[#removed + 1] = current
            end
            gsRestoreContextItems(player, removed)
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleSelectionFailed", "Recycle failed; items restored"))
            return false
        end
        removed[#removed + 1] = {
            item = item,
            equipment = equipment,
        }
    end

    local oldLimitDay = data.recycleLimitDay
    local oldLimitUsed = data.recycleLimitUsed
    local payout = GodSystemApp.services.runtime.applyRecycleDailyPayout(rawPayout)
    if payout > 0 and not GodSystemApp.services.runtime.giveCurrency(payout) then
        data.recycleLimitDay = oldLimitDay
        data.recycleLimitUsed = oldLimitUsed
        gsRestoreContextItems(player, removed)
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleSelectionFailed", "Recycle failed; items restored"))
        return false
    end
    if mode == "recycleAndList" then
        for i = 1, #typeOrder do
            local row = types[typeOrder[i]]
            if row.listable then
                GodSystemApp.services.runtime.unlockAutoShopItem(row.fullType, row.item:getDisplayName(), GodSystemApp.services.runtime.getItemSellPrice(row.fullType, row.item), row.item)
            end
        end
    end
    data.stats.recycledItems = (data.stats.recycledItems or 0) + #removed
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
    local key = mode == "recycleAndList" and "Notify_RecycleSelectionAndList" or "Notify_RecycleSelectionSuccess"
    if skipped > 0 then key = key .. "Partial" end
    gsAppendHistory(data, { kind = "recycle", text = gsFormatText(GodSystemApp.services.runtime.text("History_RecycleSelection", "Recycled {1} items for {2} coins"), { #removed, payout }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text(key, "Recycled {1} items for {2} coins; skipped {3}"), { #removed, payout, skipped }))
    return true
end
end
