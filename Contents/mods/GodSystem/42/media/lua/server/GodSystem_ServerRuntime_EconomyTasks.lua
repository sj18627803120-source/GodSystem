_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_EconomyTasks"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_EconomyTasks then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_EconomyTasks = true
    setfenv(1, runtimeEnvironment)

function normalizeTraitType(traitType)
    return tostring(traitType or ""):gsub("[%s_%-]", ""):lower()
end

function traitTokenString(token)
    if token == nil then return "" end
    local tokenType = type(token)
    if tokenType == "string" or tokenType == "number" or tokenType == "boolean" then return tostring(token) end
    if token.toString then return tostring(token:toString()) end
    return tostring(token)
end

function arrayFromList(list)
    local result = {}
    if not list then return result end
    if type(list) == "table" then
        for i = 1, #list do result[#result + 1] = list[i] end
        return result
    end
    if list.size and list.get then
        for i = 0, list:size() - 1 do result[#result + 1] = list:get(i) end
        return result
    end
    return result
end

function characterTraitDefinitionByType(traitType)
    local target = normalizeTraitType(traitType)
    if target == "" or not CharacterTraitDefinition or not CharacterTraitDefinition.getTraits then return nil end
    local list = arrayFromList(CharacterTraitDefinition.getTraits())
    for i = 1, #list do
        local trait = list[i]
        if trait and trait.getType then
            local token = trait:getType()
            if normalizeTraitType(traitTokenString(token)) == target then
                return trait, token
            end
        end
    end
    return nil
end

function traitCostPoints(traitType)
    local trait = characterTraitDefinitionByType(traitType)
    if trait and trait.getCost then
        local cost = tonumber(trait:getCost())
        if cost then return math.floor(cost) end
    end
    local catalog = GodSystemConfig.TraitFallbackCatalog or {}
    local target = normalizeTraitType(traitType)
    for i = 1, #catalog do
        if normalizeTraitType(catalog[i].type) == target then
            return floor(catalog[i].cost, 0)
        end
    end
    return 0
end

function traitTokenForType(traitType)
    local _, token = characterTraitDefinitionByType(traitType)
    if token then return token end
    if CharacterTrait then
        local okDirect, direct = pcall(function() return CharacterTrait[traitType] end)
        if okDirect and direct then return direct end
        if type(CharacterTrait) == "table" then
            local target = normalizeTraitType(traitType)
            for key, value in pairs(CharacterTrait) do
                if normalizeTraitType(key) == target then return value end
            end
        end
    end
    return traitType
end

function playerHasTrait(player, traitType)
    local token = traitTokenForType(traitType)
    if player and player.hasTrait and token and type(token) ~= "string" then
        local ok, value = pcall(function() return player:hasTrait(token) end)
        if ok then return value == true end
    end
    local traits = player and player.getCharacterTraits and player:getCharacterTraits() or nil
    if traits and traits.getKnownTraits then
        local known = arrayFromList(traits:getKnownTraits())
        local target = normalizeTraitType(traitType)
        for i = 1, #known do
            if normalizeTraitType(traitTokenString(known[i])) == target then return true end
        end
    end
    return false
end

function traitBoostCount(value)
    if value and value.intValue then
        local ok, result = pcall(function() return value:intValue() end)
        if ok and tonumber(result) then return math.floor(tonumber(result)) end
    end
    return math.floor(tonumber(tostring(value)) or 0)
end

function applyTraitBenefits(player, traitType)
    local trait = characterTraitDefinitionByType(traitType)
    if not player or not trait then return false, 0 end
    local applied = 0
    local allOk = true

    local boosts = trait.getXpBoosts and trait:getXpBoosts() or nil
    if boosts then
        local boostTable = nil
        if transformIntoKahluaTable then
            local ok, converted = pcall(transformIntoKahluaTable, boosts)
            if ok then
                boostTable = converted
            else
                allOk = false
            end
        elseif type(boosts) == "table" then
            boostTable = boosts
        end
        if boostTable then
            for perk, value in pairs(boostTable) do
                local count = math.max(0, traitBoostCount(value))
                for _ = 1, count do
                    local level = 0
                    if player.getPerkLevel then
                        local okLevel, current = pcall(function() return player:getPerkLevel(perk) end)
                        if okLevel then level = tonumber(current) or 0 end
                    end
                    if level >= 10 then break end
                    if player.LevelPerk then
                        local okLevelUp = pcall(function() player:LevelPerk(perk) end)
                        if okLevelUp then
                            applied = applied + 1
                        else
                            allOk = false
                            break
                        end
                    else
                        allOk = false
                        break
                    end
                    if luautils and luautils.updatePerksXp then
                        pcall(luautils.updatePerksXp, perk, player)
                    end
                end
            end
        end
    end

    local hasRecipes = trait.hasGrantedRecipes and trait:hasGrantedRecipes() or false
    if hasRecipes then
        local recipes = trait.getGrantedRecipes and trait:getGrantedRecipes() or nil
        local recipeList = arrayFromList(recipes)
        for i = 1, #recipeList do
            if player.learnRecipe then
                local okRecipe = pcall(function() player:learnRecipe(recipeList[i]) end)
                if okRecipe then
                    applied = applied + 1
                else
                    allOk = false
                end
            end
        end
    end

    return allOk, applied
end

function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function moduleName(fullType)
    return fullType and string.match(fullType, "^([^%.]+)%.") or nil
end

function pricingCategory(fullType, item)
    return GodSystemEconomyPolicy.quote(fullType, item, { kind = "category" }).category
end

function itemPriceInfo(fullType, item)
    local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "economy" })
    return { buyPrice = quote.finalBuy, sellPrice = quote.recycleValue, category = quote.category, quote = quote }
end

function itemBuyPrice(fullType)
    return itemPriceInfo(fullType).buyPrice or 0
end

function itemSellPrice(fullType, item)
    return itemPriceInfo(fullType, item).sellPrice or 0
end

function autoShopBuyPriceForItem(fullType, sellValue)
    return GodSystemEconomyPolicy.quote(fullType, nil, { kind = "shop" }).finalBuy
end

function autoShopListOnlyCost(fullType, sellValue)
    return GodSystemEconomyPolicy.listingCost(fullType, nil)
end

function isAutoShopListOnlyAllowed(fullType)
    if not fullType or fullType == "" then return false end
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableShop") == false then return false end
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableRecycle") == false then return false end
    if not GodSystemConfig.AutoUnlockShopFromRecycle then return false end
    if (GodSystemConfig.AutoShopBlacklist or {})[fullType] or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return false end
    if GodSystemItemConfig.isShopItemEnabled(fullType, true) == false then return false end
    if GodSystemItemEligibility.isEconomicItemAllowed and GodSystemItemEligibility.isEconomicItemAllowed(fullType, "shop") == false then return false end
    local mod = moduleName(fullType)
    if GodSystemConfig.AutoShopAllowAnyModule == true then return mod ~= nil end
    return mod ~= nil and (GodSystemConfig.AutoShopAllowedModules or {})[mod] == true
end

function shopUnitPrice(shopItem)
    if not shopItem then return 0 end
    local total = 0
    for i = 1, #(shopItem.items or {}) do
        total = total + itemBuyPrice(shopItem.items[i].fullType) * math.max(1, floor(shopItem.items[i].count, 1))
    end
    if total > 0 then return total end
    return math.max(0, floor(shopItem.price, 0))
end

function shopById(data, id)
    id = tostring(id or "")
    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local row = GodSystemConfig.ShopItems[i]
        if tostring(row.id or "") == id then
            if row.featureKey and GodSystemRuntimeConfig.isFeatureEnabled(row.featureKey) == false then
                return nil, "disabled"
            end
            local items = row.items or {}
            for j = 1, #items do
                if items[j].fullType and GodSystemItemConfig.isShopItemEnabled(items[j].fullType, true) == false then
                    return nil, "disabled"
                end
            end
            return row
        end
    end
    local forcedKey = id:match("^admin:(.+)$")
    if forcedKey then
        local variant = GodSystemItemConfig.getShopVariantOverride(forcedKey)
        local fullType = variant and variant.fullType or forcedKey
        local worldSprite = variant and variant.worldSprite or nil
        local mode = GodSystemItemConfig.getShopVariantMode(forcedKey, fullType)
        if mode ~= "forced" or not itemExists(fullType)
            or (GodSystemItemEligibility.isEconomicItemAllowed and GodSystemItemEligibility.isEconomicItemAllowed(fullType, "shop") == false) then
            return nil, "disabled"
        end
        return {
            id = id,
            fullType = fullType,
            worldSprite = worldSprite,
            variantKey = forcedKey,
            group = "admin",
            adminForced = true,
            items = { { fullType = fullType, worldSprite = worldSprite, count = 1 } },
        }
    end
    for variantKey, item in pairs(data.unlockedShopItems or {}) do
        local fullType = item.fullType or variantKey
        local unlockedId = "unlocked_" .. tostring(variantKey)
        if unlockedId == id or tostring(variantKey) == id then
            local mode = GodSystemItemConfig.getShopVariantMode(variantKey, fullType)
            if mode == "forced" then
                return shopById(data, "admin:" .. tostring(variantKey))
            end
            if item.hidden == true then return nil, "hidden" end
            if mode == "disabled" or GodSystemItemConfig.isShopItemEnabled(fullType, true) == false then return nil, "disabled" end
            return {
                id = unlockedId,
                fullType = fullType,
                worldSprite = item.worldSprite,
                variantKey = variantKey,
                group = "unlocked",
                unlocked = true,
                label = item.label,
                price = autoShopBuyPriceForItem(fullType, item.sellPrice or 1),
                items = { { fullType = fullType, worldSprite = item.worldSprite, count = 1 } },
            }
        end
    end
    return nil, "missing"
end

function itemHasInventory(item)
    if not item or not item.getInventory then return false end
    local ok, child = GodSystemB42JavaCalls.try(item, "getInventory")
    return ok and child ~= nil
end

function calculateRecyclePayout(fullType, rawValue, count)
    rawValue = floor(rawValue, 0)
    if rawValue <= 0 then return 0 end
    return math.max(1, rawValue)
end

function recycleValue(item, allowContainers)
    if not item or not item.getFullType then return 0 end
    local fullType = item:getFullType()
    if allowContainers == true then
        local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "recycle" })
        return math.max(0, math.floor(tonumber(quote and quote.recycleValue) or 0))
    end
    if (GodSystemConfig.RecycleBlacklist or {})[fullType] then return 0 end
    if allowContainers ~= true and GodSystemConfig.AllowRecycleContainers ~= true and itemHasInventory(item) then return 0 end
    local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "recycle" })
    if quote.eligible ~= true then return 0 end
    return math.max(1, math.floor(tonumber(quote.recycleValue) or 1))
end

function itemInventoryCount(item)
    if not itemHasInventory(item) then return 0 end
    local okInventory, inventory = GodSystemB42JavaCalls.try(item, "getInventory")
    if not okInventory or not inventory or not inventory.getItems then return 0 end
    local okItems, items = GodSystemB42JavaCalls.try(inventory, "getItems")
    if not okItems or not items or not items.size then return 0 end
    return items:size()
end

function isKeyItem(item)
    if not item then return false end
    if instanceof and instanceof(item, "Key") then return true end
    if item.isItemType and ItemType and ItemType.KEY_RING then
        local ok, value = GodSystemB42JavaCalls.try(item, "isItemType", ItemType.KEY_RING)
        if ok and value == true then return true end
    end
    if item.hasTag and ItemTag and ItemTag.KEY_RING then
        local ok, value = GodSystemB42JavaCalls.try(item, "hasTag", ItemTag.KEY_RING)
        if ok and value == true then return true end
    end
    return false
end

function canContextRecycleItem(item)
    return GodSystemManualRecycle.canRecycle(item)
end

function canContextListItem(data, item)
    local allowed, reason = canContextRecycleItem(item)
    if not allowed then return false, reason end
    local fullType = item:getFullType()
    if not isAutoShopListOnlyAllowed(fullType) then return false, "notListable" end
    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local mode = GodSystemItemConfig.getShopVariantMode(variantKey, fullType)
    if mode == "disabled" then return false, "disabled" end
    if mode == "forced" then return false, "configuredListed" end
    local listed, source = GodSystemShopVariants.isListingKnown(data, GodSystemServer.getConfiguredShopKeySet(), variantKey)
    if listed then
        if source == "configured" then return false, "configuredListed" end
        if data.unlockedShopItems and data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            return false, "hiddenListed"
        end
        return false, "alreadyListed"
    end
    return true, nil
end

function canRecycleItem(item)
    if not item or not item.getFullType then return false end
    local fullType = item:getFullType()
    if isLegacyHiddenItem(fullType) or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return false end
    if item.isFavorite then
        local ok, favorite = GodSystemB42JavaCalls.try(item, "isFavorite")
        if ok and favorite then return false end
    end
    if GodSystemConfig.AllowRecycleContainers ~= true and itemHasInventory(item) then return false end
    return recycleValue(item) > 0
end

function applyRecycleDailyPayout(data, rawValue)
    local state = {
        day = data.recycleLimitDay,
        used = data.recycleLimitUsed,
    }
    local result = GodSystemRecyclePayout.applyDaily(
        state,
        rawValue,
        currentDay(),
        GodSystemConfig.DailyRecycleSoftCap or 0,
        GodSystemConfig.DiminishedRecyclePayout or 1
    )
    data.recycleLimitDay = state.day
    data.recycleLimitUsed = state.used
    return result.payout, result.diminished
end

function unlockAutoShopItem(data, fullType, label, sellValue, itemOrSprite)
    if not fullType or not GodSystemConfig.AutoUnlockShopFromRecycle then return nil end
    if (GodSystemConfig.AutoShopBlacklist or {})[fullType] or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return nil end
    local mod = moduleName(fullType)
    if GodSystemConfig.AutoShopAllowAnyModule ~= true and not ((GodSystemConfig.AutoShopAllowedModules or {})[mod]) then return nil end
    data.unlockedShopItems = data.unlockedShopItems or {}
    local baseSell = math.max(1, floor(sellValue, 1))
    local buyPrice = autoShopBuyPriceForItem(fullType, baseSell)
    local worldSprite = GodSystemShopVariants.getWorldSprite(itemOrSprite)
    local variantKey = GodSystemShopVariants.getKey(fullType, worldSprite)
    local mode = GodSystemItemConfig.getShopVariantMode(variantKey, fullType)
    if mode == "disabled" or mode == "forced" then return nil, variantKey, mode end
    local listed, source = GodSystemShopVariants.isListingKnown(data, GodSystemServer.getConfiguredShopKeySet(), variantKey)
    if listed then return nil, variantKey, source end
    data.unlockedShopItems[variantKey] = {
        fullType = fullType,
        worldSprite = worldSprite,
        variantKey = variantKey,
        label = label,
        sellPrice = baseSell,
        buyPrice = buyPrice,
        unlockedAt = nowHours(),
        hidden = false,
    }
    return data.unlockedShopItems[variantKey], variantKey, "created"
end

function maxActiveTasks(data)
    return math.min(GodSystemConfig.MaxActiveTaskLimit or 10, math.max(GodSystemConfig.MaxActiveTasks or 3, floor(data.upgrades.maxActiveTasks, GodSystemConfig.MaxActiveTasks or 3)))
end

function dailyTaskCount(data)
    return math.min(GodSystemConfig.MaxDailyTaskLimit or 20, math.max(GodSystemConfig.DailyTaskCount or 5, floor(data.upgrades.dailyTaskCount, GodSystemConfig.DailyTaskCount or 5)))
end

function isTaskTemplateAvailable(template)
    if not template then return false end
    local blacklist = GodSystemConfig.TaskItemBlacklist or {}
    if template.kind == "turnInItem" then
        return not blacklist[template.item] and itemExists(template.item)
    end
    if template.kind == "turnInAnyItem" then
        for i = 1, #(template.items or {}) do
            local fullType = template.items[i]
            if not blacklist[fullType] and itemExists(fullType) then return true end
        end
        return false
    end
    return true
end

function availableTaskTemplates()
    local result = {}
    for i = 1, #(GodSystemConfig.TaskTemplates or {}) do
        local t = GodSystemConfig.TaskTemplates[i]
        if isTaskTemplateAvailable(t) then result[#result + 1] = t end
    end
    if #result == 0 then return GodSystemConfig.TaskTemplates or {} end
    return result
end

function generateTask(template)
    local now = nowHours()
    return {
        taskId = tostring(template.id) .. "_" .. tostring(math.floor(now * 100)) .. "_" .. tostring(randomIndex(9999)),
        sourceId = template.id,
        title = template.title,
        kind = template.kind,
        target = template.target,
        item = template.item,
        items = copyStringArray(template.items),
        limitHours = template.limitHours or GodSystemConfig.DefaultTaskLimitHours,
        rewardPoints = GodSystemRuntimeConfig.applyTaskReward(template.rewardPoints or 0),
        rewardItems = copyItems(template.rewardItems),
        penaltyPoints = GodSystemRuntimeConfig.applyTaskPenalty(template.penaltyPoints or 0),
        description = template.description,
        status = "open",
        createdAt = now,
        createdDay = currentDay(),
    }
end

function generateDailyTasks(data, force)
    local day = currentDay()
    if not force and data.lastGeneratedDay == day then return end
    local kept = {}
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" then
            kept[#kept + 1] = task
        elseif task.status == "claimed" then
            appendHistory(data, taskHistoryEntry("TaskStatusClaimed", task))
        elseif task.status == "failed" then
            appendHistory(data, taskHistoryEntry("TaskStatusFailed", task))
        end
    end
    local templates = availableTaskTemplates()
    local count = math.min(dailyTaskCount(data), #templates)
    for _ = 1, count do
        kept[#kept + 1] = generateTask(templates[randomIndex(#templates)])
    end
    data.lastGeneratedDay = day
    data.tasks = kept
    appendHistory(data, historyEntry("system", "DailyTasks", { count }))
end

function findTask(data, taskId)
    for i = 1, #(data.tasks or {}) do
        if tostring(data.tasks[i].taskId or "") == tostring(taskId or "") then return data.tasks[i] end
    end
    return nil
end

function ensureKillTaskProgress(task, baselineKills)
    if not task or task.kind ~= "kill" then return 0 end
    if task.killProgress == nil then
        baselineKills = math.max(0, floor(baselineKills, 0))
        task.killProgress = math.max(0, baselineKills - math.max(0, floor(task.startKills, baselineKills)))
    end
    task.killProgress = math.max(0, floor(task.killProgress, 0))
    return task.killProgress
end

function applyKillTaskDelta(data, delta, baselineKills)
    delta = math.max(0, floor(delta, 0))
    if delta <= 0 or not data or not data.tasks then return false end
    local changed = false
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" and task.kind == "kill" then
            local current = ensureKillTaskProgress(task, baselineKills)
            task.killProgress = current + delta
            changed = true
        end
    end
    return changed
end

function taskProgress(data, player, task)
    if not task then return 0 end
    if task.kind == "kill" then
        local kills = player and player.getZombieKills and player:getZombieKills() or 0
        return ensureKillTaskProgress(task, kills)
    elseif task.kind == "recycleItems" then
        return math.max(0, (data.stats.recycledItems or 0) - (task.startRecycledItems or 0))
    elseif task.kind == "recyclePoints" then
        return math.max(0, (data.stats.recycledPoints or 0) - (task.startRecycledPoints or 0))
    elseif task.kind == "surviveHours" then
        return math.max(0, math.floor(nowHours() - (task.acceptedAt or nowHours())))
    elseif task.kind == "turnInItem" then
        return #inventoryItems(player, task.item, false, false)
    elseif task.kind == "turnInAnyItem" then
        local total = 0
        for i = 1, #(task.items or {}) do total = total + #inventoryItems(player, task.items[i], false, false) end
        return total
    elseif task.kind == "spendPoints" then
        return math.max(0, (data.stats.spentPoints or 0) - (task.startSpentPoints or 0))
    elseif task.kind == "buyItems" then
        return math.max(0, (data.stats.boughtItems or 0) - (task.startBoughtItems or 0))
    elseif task.kind == "moveDistance" then
        return math.max(0, math.floor((data.stats.moveDistance or 0) - (task.startMoveDistance or 0)))
    end
    return 0
end

function isTurnInTask(task)
    return task and (task.kind == "turnInItem" or task.kind == "turnInAnyItem")
end

function turnInAllowedTypes(task)
    local allowed = {}
    if task and task.kind == "turnInItem" and task.item then
        allowed[tostring(task.item)] = true
    elseif task and task.kind == "turnInAnyItem" then
        for i = 1, #(task.items or {}) do
            allowed[tostring(task.items[i])] = true
        end
    end
    return allowed
end

function restoreTurnInItems(player, removed)
    local restoredAll = true
    local inventory = player and player.getInventory and player:getInventory() or nil
    for i = #removed, 1, -1 do
        local row = removed[i]
        local restored = false
        if row and row.container and row.item then
            pcall(function() row.container:AddItem(row.item) end)
            restored = GodSystemServerContainerContainsItem(row.container, row.item)
            if restored and sendAddItemToContainer then
                pcall(sendAddItemToContainer, row.container, row.item)
            end
            if restored and row.container.setDrawDirty then
                pcall(function() row.container:setDrawDirty(true) end)
            end
        end
        if not restored and inventory and row and row.item then
            pcall(function() inventory:AddItem(row.item) end)
            restored = GodSystemServerContainerContainsItem(inventory, row.item)
            if restored and sendAddItemToContainer then
                pcall(sendAddItemToContainer, inventory, row.item)
            end
        end
        restoredAll = restoredAll and restored
    end
    if inventory then markInventoryDirty(player, inventory) end
    return restoredAll
end

function claimTaskForPlayer(player, data, task, claimArgs)
    claimArgs = claimArgs or {}
    if not task or task.status ~= "active" then return false, "TaskStateInvalid" end
    if isTurnInTask(task) then return false, "TaskTurnInManualRequired" end
    local progress = taskProgress(data, player, task)
    progress = math.max(0, floor(claimArgs.clientProgress, progress))
    if task.kind == "kill" then
        task.killProgress = math.max(ensureKillTaskProgress(task, player and player.getZombieKills and player:getZombieKills() or 0), progress)
        progress = task.killProgress
    elseif task.kind == "moveDistance" then
        data.stats.moveDistance = math.max(data.stats.moveDistance or 0, (task.startMoveDistance or 0) + progress)
    end
    if claimArgs.clientExpired == true and progress < (task.target or 1) then
        failTask(player, data, task, "TaskFailed")
        return false, "TaskFailed"
    end
    if progress < (task.target or 1) then return false, "TaskIncomplete" end
    if (task.rewardPoints or 0) > 0 then addPoints(player, task.rewardPoints) end
    for i = 1, #(task.rewardItems or {}) do giveItem(player, task.rewardItems[i].fullType, task.rewardItems[i].count or 1) end
    task.status = "claimed"
    task.claimedAt = nowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    appendHistory(data, taskHistoryEntry("ClaimTask", task))
    return true, "TaskClaimed"
end

function submitTurnInTaskForPlayer(player, data, task, args)
    if not task or task.status ~= "active" then return false, "TaskStateInvalid" end
    if not isTurnInTask(task) then return false, "TaskTurnInManualRequired" end

    local target = math.max(1, floor(task.target, 1))
    local itemIds = args and args.itemIds or nil
    if type(itemIds) ~= "table" or #itemIds ~= target then
        return false, "TaskTurnInSelectionInvalid"
    end

    local selectedItemIds = {}
    for i = 1, target do
        local itemId = itemIds[i]
        if type(itemId) ~= "string" or itemId == "" or selectedItemIds[itemId] then
            return false, "TaskTurnInSelectionInvalid"
        end
        selectedItemIds[itemId] = true
    end

    local allowed = turnInAllowedTypes(task)
    local byId = {}
    local found = inventoryItems(player, nil, false, false)
    for i = 1, #found do
        local row = found[i]
        local item = row and row.item or nil
        local itemId = GodSystemMaintenance.itemId(item)
        if itemId and selectedItemIds[itemId] then
            byId[itemId] = row
        end
    end

    local selected = {}
    for i = 1, target do
        local itemId = itemIds[i]
        local row = byId[itemId]
        local fullType = row and row.item and row.item.getFullType and tostring(row.item:getFullType() or "") or ""
        if not row or allowed[fullType] ~= true then
            return false, "TaskTurnInNotEnough"
        end
        selected[#selected + 1] = row
    end

    local removed = {}
    for i = 1, #selected do
        local row = selected[i]
        if not removeItemFromContainer(row.container, row.item) then
            restoreTurnInItems(player, removed)
            return false, "TaskTurnInFailed"
        end
        removed[#removed + 1] = row
    end

    if (task.rewardPoints or 0) > 0 then addPoints(player, task.rewardPoints) end
    for i = 1, #(task.rewardItems or {}) do
        giveItem(player, task.rewardItems[i].fullType, task.rewardItems[i].count or 1)
    end
    task.status = "claimed"
    task.claimedAt = nowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    appendHistory(data, taskHistoryEntry("ClaimTask", task))
    return true, "TaskClaimed"
end
end
