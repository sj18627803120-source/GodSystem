_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Foundation"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Foundation then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Foundation = true
    setfenv(1, runtimeEnvironment)

function gsPlayer()
    return getPlayer and getPlayer() or nil
end

function GodSystemApp.services.runtime.getPlayerLoadText()
    local player = gsPlayer()
    if not player then return "-" end
    local inventory = player.getInventory and player:getInventory() or nil
    if not inventory then return "-" end
    local weight = inventory.getCapacityWeight and inventory:getCapacityWeight()
        or inventory.getWeight and inventory:getWeight()
        or 0
    local maximum = player.getMaxWeight and player:getMaxWeight() or 0
    return string.format("%.1f / %d", tonumber(weight) or 0, math.floor(tonumber(maximum) or 0))
end

function gsNowHours()
    if GameTime and GameTime:getInstance() then
        return GameTime:getInstance():getWorldAgeHours()
    end
    return 0
end

function gsNowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return math.floor(gsNowHours() * 3600000)
end

function gsCurrentDay()
    return math.floor(gsNowHours() / 24)
end

function gsRandomIndex(max)
    if not max or max <= 1 then
        return 1
    end
    if ZombRand then
        return ZombRand(max) + 1
    end
    return math.random(max)
end

function gsFormatText(template, args)
    local text = tostring(template or "")
    for i = 1, #(args or {}) do
        text = text:gsub("{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return text
end

function gsSafeIsFavorite(item)
    if item and item.isFavorite then
        local ok, value = pcall(function() return item:isFavorite() end)
        return ok and value
    end
    return false
end

function gsSafeIsBroken(item)
    if item and item.isBroken then
        local ok, value = pcall(function() return item:isBroken() end)
        return ok and value
    end
    return false
end

function gsSafeUsedDelta(item)
    if item and item.getUsedDelta then
        local ok, value = pcall(function() return item:getUsedDelta() end)
        if ok and value and value > 0 and value < 1 then
            return value
        end
    end
    return nil
end

function gsItemHasInventory(item)
    if not item or not item.getInventory then
        return false
    end
    local ok, child = pcall(function() return item:getInventory() end)
    return ok and child ~= nil
end

function gsItemInventoryCount(item)
    if not item or not item.getInventory then
        return 0
    end
    local ok, child = pcall(function() return item:getInventory() end)
    if not ok or not child or not child.getItems then
        return 0
    end
    local okItems, items = pcall(function() return child:getItems() end)
    if not okItems or not items or not items.size then
        return 0
    end
    return items:size()
end

function GodSystemApp.services.runtime.getContextContainerSignature(item)
    if not item or not item.getInventory then return "0:7" end
    local tokens = {}
    local function collect(inventory, depth)
        if not inventory or depth > 32 or not inventory.getItems then return end
        local okItems, items = pcall(function() return inventory:getItems() end)
        if not okItems or not items or not items.size then return end
        for i = 0, items:size() - 1 do
            local child = items:get(i)
            if child then
                local id = child.getID and child:getID() or ""
                local fullType = child.getFullType and child:getFullType() or ""
                tokens[#tokens + 1] = tostring(id or "") .. ":" .. tostring(fullType or "")
                if child.getInventory then
                    local okChild, childInventory = pcall(function() return child:getInventory() end)
                    if okChild and childInventory then collect(childInventory, depth + 1) end
                end
            end
        end
    end
    local okInventory, inventory = pcall(function() return item:getInventory() end)
    if okInventory and inventory then collect(inventory, 1) end
    table.sort(tokens)
    local hash = 7
    for i = 1, #tokens do
        local token = tokens[i]
        for j = 1, #token do hash = ((hash * 131) + string.byte(token, j)) % 2147483647 end
        hash = ((hash * 131) + 10) % 2147483647
    end
    return tostring(#tokens) .. ":" .. tostring(hash)
end

function gsCopyItems(items)
    local result = {}
    if not items then
        return result
    end
    for i = 1, #items do
        result[i] = { fullType = items[i].fullType, worldSprite = items[i].worldSprite, count = items[i].count or 1 }
    end
    return result
end

function gsMultiplyItems(items, multiplier)
    local result = {}
    multiplier = math.max(1, math.floor(tonumber(multiplier) or 1))
    if not items then
        return result
    end
    for i = 1, #items do
        result[i] = {
            fullType = items[i].fullType,
            worldSprite = items[i].worldSprite,
            count = math.max(1, math.floor(items[i].count or 1)) * multiplier,
        }
    end
    return result
end

function gsCopyStringArray(items)
    local result = {}
    if not items then
        return result
    end
    for i = 1, #items do
        result[i] = items[i]
    end
    return result
end

function gsFormatText(template, args)
    local text = tostring(template or "")
    for i = 1, #(args or {}) do
        text = string.gsub(text, "{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return text
end

function gsAppendHistory(data, entry)
    data.history = data.history or {}
    entry.time = gsNowHours()
    table.insert(data.history, 1, entry)
    local limit = GodSystemConfig.HistoryLimit or 40
    while #data.history > limit do
        table.remove(data.history)
    end
end

function gsCollectInventoryItems(container, result, fullType, includeFavorite, includeEquipped)
    if not container or not container.getItems then
        return
    end

    local player = gsPlayer()
    local primary = player and player:getPrimaryHandItem() or nil
    local secondary = player and player:getSecondaryHandItem() or nil
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local matches = (not fullType) or item:getFullType() == fullType
            local equipped = item == primary or item == secondary
            local favorite = gsSafeIsFavorite(item)
            if matches and (includeEquipped or not equipped) and (includeFavorite or not favorite) then
                table.insert(result, { item = item, container = container })
            end

            if item.getInventory then
                local ok, child = pcall(function() return item:getInventory() end)
                if ok and child then
                    gsCollectInventoryItems(child, result, fullType, includeFavorite, includeEquipped)
                end
            end
        end
    end
end

function gsFindInventoryItems(fullType, includeFavorite, includeEquipped)
    local player = gsPlayer()
    local result = {}
    if not player then
        return result
    end
    gsCollectInventoryItems(player:getInventory(), result, fullType, includeFavorite, includeEquipped)
    return result
end

function gsInventoryItemById(itemId)
    itemId = tostring(itemId or "")
    if itemId == "" then return nil, nil end
    local found = gsFindInventoryItems(nil, true, true)
    for i = 1, #found do
        local item = found[i].item
        if item and item.getID and tostring(item:getID()) == itemId then
            return item, found[i].container
        end
    end
    return nil, nil
end

function gsCurrencyDenoms()
    return GodSystemConfig.CurrencyItems or {}
end

function gsRestoreRemovedCurrency(removed)
    local byType = {}
    for i = 1, #(removed or {}) do
        local fullType = removed[i].fullType
        if fullType then
            byType[fullType] = byType[fullType] or { count = 0, value = math.max(1, math.floor(tonumber(removed[i].value) or 1)) }
            byType[fullType].count = byType[fullType].count + 1
        end
    end

    local okAll = true
    local failedValue = 0
    for fullType, row in pairs(byType) do
        local ok, added = GodSystemApp.services.runtime.giveItem(fullType, row.count)
        if not ok or #(added or {}) < row.count then
            okAll = false
            failedValue = failedValue + row.count * row.value
        end
    end
    return okAll, failedValue
end

function gsEnsureKillTaskProgress(task, baselineKills)
    if not task or task.kind ~= "kill" then
        return 0
    end
    if task.killProgress == nil then
        baselineKills = math.max(0, math.floor(tonumber(baselineKills) or 0))
        task.killProgress = math.max(0, baselineKills - math.max(0, math.floor(tonumber(task.startKills) or baselineKills)))
    end
    task.killProgress = math.max(0, math.floor(tonumber(task.killProgress) or 0))
    return task.killProgress
end

function gsApplyKillTaskDelta(data, delta, baselineKills)
    delta = math.max(0, math.floor(tonumber(delta) or 0))
    if delta <= 0 or not data or not data.tasks then
        return false
    end
    local changed = false
    for i = 1, #data.tasks do
        local task = data.tasks[i]
        if task and task.status == "active" and task.kind == "kill" then
            local current = gsEnsureKillTaskProgress(task, baselineKills)
            task.killProgress = current + delta
            changed = true
        end
    end
    return changed
end

function GodSystemApp.services.runtime.text(key, fallback)
    local fullKey = "IGUI_GodSystem_" .. tostring(key)
    if getText then
        local ok, value = pcall(function() return getText(fullKey) end)
        if ok and value and value ~= fullKey then
            return value
        end
    end

    local language = ""
    if getCore then
        pcall(function()
            local core = getCore()
            if core and core.getLanguage then language = tostring(core:getLanguage() or "") end
        end)
    end
    language = string.upper(language)
    local fallbackTable = (language == "EN" or string.find(language, "EN", 1, true))
        and GodSystemFallbackText and GodSystemFallbackText.en
        or GodSystemFallbackText and GodSystemFallbackText.zh
    if fallbackTable and fallbackTable[key] then
        return fallbackTable[key]
    end
    return fallback or fullKey
end

function gsGetModuleName(fullType)
    if not fullType then
        return nil
    end
    return string.match(fullType, "^([^%.]+)%.")
end

BANK_INVESTMENT_IDS = { "stable", "balanced", "aggressive" }

function gsNormalizeBankInvestments(bank)
    bank = bank or {}
    bank.investments = bank.investments or {}
    for i = 1, #BANK_INVESTMENT_IDS do
        local tierId = BANK_INVESTMENT_IDS[i]
        local account = bank.investments[tierId]
        if type(account) ~= "table" then
            account = {}
            bank.investments[tierId] = account
        end
        account.tierId = tierId
        account.balance = math.max(0, math.floor(tonumber(account.balance) or 0))
        account.onlineHours = math.max(0, tonumber(account.onlineHours) or 0)
        account.settlementCount = math.max(0, math.floor(tonumber(account.settlementCount) or 0))
        account.redeemUnlocked = account.redeemUnlocked == true
        account.lastDelta = math.floor(tonumber(account.lastDelta) or 0)
        account.lastOutcome = tostring(account.lastOutcome or "flat")
        account.lastSettledHour = tonumber(account.lastSettledHour)
    end
    return bank.investments
end

function GodSystemApp.services.runtime.getData()
    if GodSystemApp.services.runtime.data then
        return GodSystemApp.services.runtime.data
    end

    local data = ModData.getOrCreate(GodSystemConfig.DataKey)
    local previousVersion = data.version
    data.version = GodSystemConfig.Version
    data.lastGeneratedDay = data.lastGeneratedDay or -1
    data.tasks = data.tasks or {}
    data.history = data.history or {}
    data.unlockedShopItems = data.unlockedShopItems or {}
    GodSystemShopVariants.normalizeUnlocked(data, GodSystemApp.services.runtime.configuredShopKeySet)
    data.stats = data.stats or {}
    data.stats.recycledItems = data.stats.recycledItems or 0
    data.stats.recycledPoints = data.stats.recycledPoints or 0
    data.stats.spentPoints = data.stats.spentPoints or 0
    data.stats.boughtItems = data.stats.boughtItems or 0
    data.stats.moveDistance = data.stats.moveDistance or 0
    data.stats.modifiedTraits = data.stats.modifiedTraits or 0
    data.stats.completedTasks = data.stats.completedTasks or 0
    data.stats.failedTasks = data.stats.failedTasks or 0
    data.stats.bankDeposited = data.stats.bankDeposited or 0
    data.stats.bankWithdrawn = data.stats.bankWithdrawn or 0
    data.stats.bankInterest = data.stats.bankInterest or 0
    data.stats.bankPenalty = data.stats.bankPenalty or 0
    data.stats.bankInvestmentProfit = data.stats.bankInvestmentProfit or 0
    data.stats.bankInvestmentLoss = data.stats.bankInvestmentLoss or 0
    data.stats.bankInvestmentDeposited = data.stats.bankInvestmentDeposited or 0
    data.stats.bankInvestmentRedeemed = data.stats.bankInvestmentRedeemed or 0
    data.recycleLimitDay = data.recycleLimitDay or gsCurrentDay()
    data.recycleLimitUsed = data.recycleLimitUsed or 0
    if data.recycleUnlockMode == nil then
        data.recycleUnlockMode = true
    end
    data.upgrades = data.upgrades or {}
    data.upgrades.maxActiveTasks = math.max(GodSystemConfig.MaxActiveTasks or 3, math.floor(tonumber(data.upgrades.maxActiveTasks) or (GodSystemConfig.MaxActiveTasks or 3)))
    data.upgrades.maxActiveTasks = math.min(data.upgrades.maxActiveTasks, GodSystemConfig.MaxActiveTaskLimit or 10)
    data.upgrades.dailyTaskCount = math.max(GodSystemConfig.DailyTaskCount or 5, math.floor(tonumber(data.upgrades.dailyTaskCount) or (GodSystemConfig.DailyTaskCount or 5)))
    data.upgrades.dailyTaskCount = math.min(data.upgrades.dailyTaskCount, GodSystemConfig.MaxDailyTaskLimit or 20)
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.getLevel(data, gsPlayer())
    data.homeSystem = data.homeSystem or {}
    data.homeSystem.tempSlots = data.homeSystem.tempSlots or {}
    data.homeSystem.returnPoint = data.homeSystem.returnPoint or nil
    data.homeSystem.safeZone = data.homeSystem.safeZone or {}
    data.homeSystem.safeZone.level = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.level) or 0))
    data.homeSystem.safeZone.enabled = data.homeSystem.safeZone.enabled == true
    data.homeSystem.safeZone.lastScanHours = tonumber(data.homeSystem.safeZone.lastScanHours) or 0
    data.homeSystem.safeZone.lastNoticeHours = tonumber(data.homeSystem.safeZone.lastNoticeHours) or -999
    data.homeSystem.safeZone.lastCleared = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.lastCleared) or 0))
    data.homeSystem.safeZone.lastClearHour = tonumber(data.homeSystem.safeZone.lastClearHour) or 0
    data.homeSystem.safeZone.nextZombieScanIndex = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.nextZombieScanIndex) or 0))
    data.bank = data.bank or {}
    data.bank.current = math.max(0, math.floor(tonumber(data.bank.current) or 0))
    data.bank.fixed = data.bank.fixed or {}
    data.bank.nextId = math.max(1, math.floor(tonumber(data.bank.nextId) or 1))
    data.bank.lastDeathPenaltyHour = tonumber(data.bank.lastDeathPenaltyHour) or -999
    data.bank.autoDepositEnabled = data.bank.autoDepositEnabled == true
    data.bank.lastAutoDepositHour = tonumber(data.bank.lastAutoDepositHour) or gsNowHours()
    gsNormalizeBankInvestments(data.bank)
    local tempLimit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, tempLimit do
        data.homeSystem.tempSlots[i] = data.homeSystem.tempSlots[i] or { owned = false, point = nil }
        data.homeSystem.tempSlots[i].owned = data.homeSystem.tempSlots[i].owned == true
    end
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled == true
    data.lastAutoTaskClaimHour = tonumber(data.lastAutoTaskClaimHour) or gsNowHours()
    data.companion = GodSystemCompanionConfig.ensureData(data.companion)
    data.ui = data.ui or {}
    data.ui.x = data.ui.x or GodSystemConfig.FloatingButton.x
    data.ui.y = data.ui.y or GodSystemConfig.FloatingButton.y
    data.ui.showHeadUpNotifications = data.ui.showHeadUpNotifications ~= false
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    GodSystemRuntimeConfig.readSandbox()
    if not (isClient and isClient()) then
        GodSystemItemConfig.applyRuntime(
            data.itemConfig.itemOverrides,
            data.itemConfig.shopVariantOverrides,
            data.itemConfig.economyRevision
        )
    end

    if previousVersion and previousVersion ~= GodSystemConfig.Version then
        gsAppendHistory(data, { kind = "system", text = GodSystemApp.services.runtime.text("History_Upgraded", "God System upgraded to v") .. tostring(GodSystemConfig.Version) })
    end

    local player = gsPlayer()
    if player and data.lastKnownKills == nil then
        data.lastKnownKills = player:getZombieKills()
    end

    GodSystemApp.services.runtime.data = data
    return data
end

function GodSystemApp.services.runtime.applyRuntimeConfigSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    GodSystemRuntimeConfig.applySnapshot(snapshot)
    return true
end

function GodSystemApp.services.runtime.applyEconomySnapshot(snapshot)
    if type(snapshot) ~= "table" then return false end
    GodSystemItemConfig.applyRuntime(
        snapshot.itemOverrides or {},
        snapshot.shopVariantOverrides or {},
        snapshot.economyRevision
    )
    GodSystemApp.services.runtime.economySnapshot = GodSystemItemConfig.publicSnapshot()
    return true
end

function GodSystemApp.services.runtime.applyEconomyDelta(delta)
    if type(delta) ~= "table" then return false end
    local snapshot = GodSystemApp.services.runtime.getItemConfigSnapshot()
    snapshot.itemOverrides = snapshot.itemOverrides or {}
    snapshot.shopVariantOverrides = snapshot.shopVariantOverrides or {}
    if delta.fullType and delta.fullType ~= "" then
        snapshot.itemOverrides[tostring(delta.fullType)] = delta.override
    end
    if delta.variantKey and delta.variantKey ~= "" then
        snapshot.shopVariantOverrides[tostring(delta.variantKey)] = delta.variantOverride
    end
    snapshot.economyRevision = math.max(
        tonumber(snapshot.economyRevision) or 1,
        tonumber(delta.revision) or 1
    )
    return GodSystemApp.services.runtime.applyEconomySnapshot(snapshot)
end

function GodSystemApp.services.runtime.getItemConfigSnapshot()
    if GodSystemApp.services.runtime.economySnapshot then
        return GodSystemApp.services.runtime.economySnapshot
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    GodSystemItemConfig.applyRuntime(
        data.itemConfig.itemOverrides,
        data.itemConfig.shopVariantOverrides,
        data.itemConfig.economyRevision
    )
    GodSystemApp.services.runtime.economySnapshot = GodSystemItemConfig.publicSnapshot()
    return GodSystemApp.services.runtime.economySnapshot
end

function GodSystemApp.services.runtime.isItemConfigAllowed()
    if isClient and isClient() then
        return GodSystemApp.services.runtime.serverAdmin == true
    end
    return true
end

function GodSystemApp.services.runtime.isFeatureEnabled(key)
    return GodSystemRuntimeConfig.isFeatureEnabled(key)
end

function GodSystemApp.services.runtime.saveItemOverride(fullType, override)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then return false end
    local clean = GodSystemItemConfig.sanitizeItemOverride(override or {})
    if not clean then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideSet", { fullType = fullType, override = clean })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.itemOverrides[fullType] = clean
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.clearItemOverride(fullType)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideClear", { fullType = fullType })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.itemOverrides[fullType] = nil
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.saveShopVariantOverride(variantKey, override)
    variantKey = tostring(variantKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local clean = GodSystemItemConfig.sanitizeShopVariantOverride(override or {})
    if variantKey == "" or not clean then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideSet", { variantKey = variantKey, variantOverride = clean })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.shopVariantOverrides[variantKey] = clean
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.clearShopVariantOverride(variantKey)
    variantKey = tostring(variantKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if variantKey == "" then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideClear", { variantKey = variantKey })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.shopVariantOverrides[variantKey] = nil
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.saveEconomyOverride(fullType, override, variantKey, worldSprite, shopMode)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local clean = GodSystemItemConfig.sanitizeItemOverride(override or {})
    if fullType == "" or not clean then return false end
    local variant = nil
    if variantKey and worldSprite then
        variant = GodSystemItemConfig.sanitizeShopVariantOverride({
            fullType = fullType,
            worldSprite = worldSprite,
            shopMode = shopMode,
        })
        if not variant then return false end
    end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideSet", {
            fullType = fullType,
            override = clean,
            variantKey = variantKey,
            variantOverride = variant,
        })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.itemOverrides[fullType] = clean
    if variant and variantKey then data.itemConfig.shopVariantOverrides[variantKey] = variant end
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.clearEconomyOverride(fullType, variantKey)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("itemConfigOverrideClear", { fullType = fullType, variantKey = variantKey })
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    data.itemConfig.itemOverrides[fullType] = nil
    if variantKey then data.itemConfig.shopVariantOverrides[variantKey] = nil end
    data.itemConfig.economyRevision = data.itemConfig.economyRevision + 1
    GodSystemApp.services.runtime.economySnapshot = nil
    GodSystemApp.services.runtime.getItemConfigSnapshot()
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.save()
    if ModData and ModData.transmit then
        pcall(function() ModData.transmit(GodSystemConfig.DataKey) end)
    end
end

function GodSystemApp.services.runtime.getHeadUpNotificationsEnabled()
    local data = GodSystemApp.services.runtime.getData()
    return data.ui and data.ui.showHeadUpNotifications ~= false
end

function GodSystemApp.services.runtime.setHeadUpNotificationsEnabled(enabled)
    local data = GodSystemApp.services.runtime.getData()
    data.ui = data.ui or {}
    data.ui.showHeadUpNotifications = enabled ~= false
    GodSystemApp.services.runtime.save()
    return data.ui.showHeadUpNotifications
end

function GodSystemApp.services.runtime.getCurrencyTotal()
    local total = 0
    local denoms = gsCurrencyDenoms()
    local values = {}
    for i = 1, #denoms do
        values[denoms[i].fullType] = math.max(0, math.floor(tonumber(denoms[i].value) or 0))
    end
    local player = gsPlayer()
    local root = player and player.getInventory and player:getInventory() or nil
    local seenContainers = {}
    local seenItems = {}
    local function scan(container, depth)
        if not container or seenContainers[container] or depth > 32 or not container.getItems then return end
        seenContainers[container] = true
        local ok, items = pcall(function() return container:getItems() end)
        if not ok or not items or not items.size then return end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and not seenItems[item] then
                seenItems[item] = true
                local fullType = item.getFullType and item:getFullType() or nil
                total = total + (values[fullType] or 0)
                if item.getInventory then
                    local childOk, child = pcall(function() return item:getInventory() end)
                    if childOk and child then scan(child, depth + 1) end
                end
            end
        end
    end
    scan(root, 0)
    return total
end

function GodSystemApp.services.runtime.getCurrencyDisplayTotal()
    local now = gsNowMs()
    local cache = GodSystemApp.services.runtime.currencyDisplayCache
    if cache and now - (cache.at or 0) < 250 then return cache.total or 0 end
    local total = GodSystemApp.services.runtime.getCurrencyTotal()
    GodSystemApp.services.runtime.currencyDisplayCache = { at = now, total = total }
    return total
end

function GodSystemApp.services.runtime.giveCurrency(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return false
    end

    local denoms = gsCurrencyDenoms()
    local success = true
    local grantedItems = {}
    for i = 1, #denoms do
        local denom = denoms[i]
        local value = denom.value or 1
        local count = math.floor(amount / value)
        if count > 0 then
            local ok, addedItems = GodSystemApp.services.runtime.giveItem(denom.fullType, count)
            if not ok or #(addedItems or {}) < count then
                success = false
                break
            end
            for j = 1, #(addedItems or {}) do
                table.insert(grantedItems, addedItems[j])
            end
            amount = amount - (count * value)
        end
    end
    if not success then
        local player = gsPlayer()
        local inventory = player and player:getInventory()
        for i = 1, #grantedItems do
            pcall(function()
                if inventory then
                    inventory:Remove(grantedItems[i])
                end
            end)
        end
    end
    return success
end

function GodSystemApp.services.runtime.consolidateCurrency()
    local denoms = gsCurrencyDenoms()
    local total = 0
    local removed = {}
    local originalCount = 0
    for i = 1, #denoms do
        local denom = denoms[i]
        local value = math.max(1, math.floor(tonumber(denom.value) or 1))
        local found = gsFindInventoryItems(denom.fullType, true, true)
        for j = 1, #found do
            if not GodSystemApp.services.runtime.removeCurrencyItem(found[j].container, found[j].item) then
                GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyConsolidateFailed", "Currency consolidation failed"))
                return false
            end
            table.insert(removed, { fullType = denom.fullType, value = value })
            total = total + value
            originalCount = originalCount + 1
        end
    end
    if total <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyConsolidateNone", "No system currency to consolidate"))
        return false
    end
    if not GodSystemApp.services.runtime.giveCurrency(total) then
        GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyConsolidateFailed", "Currency consolidation failed"))
        return false
    end
    local newCount = 0
    local remaining = total
    for i = 1, #denoms do
        local value = math.max(1, math.floor(tonumber(denoms[i].value) or 1))
        local count = math.floor(remaining / value)
        newCount = newCount + count
        remaining = remaining - (count * value)
    end
    gsAppendHistory(GodSystemApp.services.runtime.getData(), { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_CurrencyConsolidated", "Currency consolidated: {1} coins, {2} items -> {3} items"), { total, originalCount, newCount }) })
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_CurrencyConsolidated", "Currency consolidated: {1} coins, {2} items -> {3} items"), { total, originalCount, newCount }))
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.containerContainsItem(container, item)
    if not container or not item or not container.getItems then return false end
    local ok, contains = pcall(function()
        local items = container:getItems()
        return items and items.contains and items:contains(item) == true
    end)
    return ok and contains == true
end

function GodSystemApp.services.runtime.removeCurrencyItem(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:Remove(item) end)
    if not ok or GodSystemApp.services.runtime.containerContainsItem(container, item) then return false end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    return true
end

function GodSystemApp.services.runtime.removeCurrency(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end

    local total = GodSystemApp.services.runtime.getCurrencyTotal()
    if total < amount then
        return false
    end

    local denoms = gsCurrencyDenoms()
    local remaining = amount
    local removedValue = 0
    local removed = {}
    for i = 1, #denoms do
        if remaining <= 0 then
            break
        end
        local denom = denoms[i]
        local value = math.max(1, math.floor(tonumber(denom.value) or 1))
        local need = math.floor(remaining / value)
        if need > 0 then
            local found = gsFindInventoryItems(denom.fullType, true, true)
            for j = 1, #found do
                if need <= 0 then
                    break
                end
                if not GodSystemApp.services.runtime.removeCurrencyItem(found[j].container, found[j].item) then
                    GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
                    return false
                end
                table.insert(removed, { fullType = denom.fullType, value = value })
                removedValue = removedValue + value
                remaining = remaining - value
                need = need - 1
            end
        end
    end

    if remaining > 0 then
        for i = #denoms, 1, -1 do
            if remaining <= 0 then
                break
            end
            local denom = denoms[i]
            local value = math.max(1, math.floor(tonumber(denom.value) or 1))
            local found = gsFindInventoryItems(denom.fullType, true, true)
            for j = 1, #found do
                if not GodSystemApp.services.runtime.removeCurrencyItem(found[j].container, found[j].item) then
                    GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
                    return false
                end
                table.insert(removed, { fullType = denom.fullType, value = value })
                removedValue = removedValue + value
                remaining = remaining - value
                break
            end
        end
    end

    if removedValue < amount then
        GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
        return false
    end

    local change = removedValue - amount
    if change > 0 and not GodSystemApp.services.runtime.giveCurrency(change) then
        GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
        return false
    end
    return true
end

function GodSystemApp.services.runtime.updateKillTaskProgress(delta, baselineKills)
    local data = GodSystemApp.services.runtime.getData()
    local changed = gsApplyKillTaskDelta(data, delta, baselineKills)
    if changed then
        GodSystemApp.services.runtime.save()
    end
    return changed
end

function GodSystemApp.services.runtime.normalizeActiveKillTasks(baselineKills)
    local data = GodSystemApp.services.runtime.getData()
    local player = gsPlayer()
    local kills = baselineKills or (player and player.getZombieKills and player:getZombieKills() or 0)
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" and task.kind == "kill" then
            gsEnsureKillTaskProgress(task, kills)
        end
    end
end

function GodSystemApp.services.runtime.ensureCurrencyInitialized()
    local data = GodSystemApp.services.runtime.getData()
    if data.currencyInitialized then
        return
    end

    local grant = 0
    if data.points and data.points > 0 then
        grant = math.floor(data.points)
    elseif not data.started then
        grant = GodSystemConfig.StartingPoints or 0
    end

    if grant > 0 then
        if not GodSystemApp.services.runtime.giveCurrency(grant) then
            data.started = true
            data.currencyInitialized = false
            data.points = grant
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Error_CurrencyGrantFailed", "Currency item grant failed. Check mod install: ") .. "GodSystem_Items.txt")
            GodSystemApp.services.runtime.save()
            return
        end
    end

    data.started = true
    data.currencyInitialized = true
    data.points = 0

    if grant > 0 then
        gsAppendHistory(data, { kind = "system", text = GodSystemApp.services.runtime.text("History_InitialCurrency", "System activated, initial currency ") .. tostring(grant) })
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_InitialCurrency", "System activated, currency +") .. tostring(grant))
    end
    GodSystemApp.services.runtime.save()
end

function GodSystemApp.services.runtime.notifyNow(text)
    local player = gsPlayer()
    if not player then
        return
    end
    text = tostring(text or "")
    if text == "" then
        return
    end
    if not GodSystemApp.services.runtime.getHeadUpNotificationsEnabled() then
        return
    end
    if player.Say then
        player:Say(text)
    end
end

function GodSystemApp.services.runtime.processNotifyQueue()
    local queue = GodSystemApp.services.runtime.notifyQueue or {}
    if #queue <= 0 then
        GodSystemApp.services.runtime.notifyQueueActive = false
        if Events and Events.OnTick then
            Events.OnTick.Remove(GodSystemApp.services.runtime.processNotifyQueue)
        end
        return
    end

    local now = gsNowMs()
    local interval = math.max(800, math.floor(tonumber(GodSystemConfig.NotifyQueueIntervalMs) or 1600))
    if now - (GodSystemApp.services.runtime.notifyLastMs or 0) < interval then
        return
    end
    GodSystemApp.services.runtime.notifyLastMs = now
    local text = table.remove(queue, 1)
    GodSystemApp.services.runtime.notifyNow(text)
end

function GodSystemApp.services.runtime.notify(text)
    text = tostring(text or "")
    if text == "" then
        return
    end
    GodSystemApp.services.runtime.notifyQueue = GodSystemApp.services.runtime.notifyQueue or {}
    table.insert(GodSystemApp.services.runtime.notifyQueue, text)
    if Events and Events.OnTick then
        if not GodSystemApp.services.runtime.notifyQueueActive then
            GodSystemApp.services.runtime.notifyQueueActive = true
            Events.OnTick.Remove(GodSystemApp.services.runtime.processNotifyQueue)
            Events.OnTick.Add(GodSystemApp.services.runtime.processNotifyQueue)
        end
    else
        GodSystemApp.services.runtime.processNotifyQueue()
    end
end

function GodSystemApp.services.runtime.addPoints(amount, reason)
    local data = GodSystemApp.services.runtime.getData()
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then
        return true
    end

    local ok = true
    if amount > 0 then
        ok = GodSystemApp.services.runtime.giveCurrency(amount)
    else
        ok = GodSystemApp.services.runtime.spendCurrency(math.abs(amount))
    end
    if not ok then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    if reason then
        local sign = amount > 0 and "+" or ""
        gsAppendHistory(data, { kind = "points", text = reason .. " " .. sign .. tostring(amount) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
        GodSystemApp.services.runtime.notify(reason .. " " .. sign .. tostring(amount) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"))
    end
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.canAfford(cost)
    return GodSystemApp.services.runtime.getSpendableBalance() >= math.max(0, math.floor(tonumber(cost) or 0))
end

function GodSystemApp.services.runtime.getMaxActiveTasks()
    local data = GodSystemApp.services.runtime.getData()
    local base = GodSystemConfig.MaxActiveTasks or 3
    local limit = GodSystemConfig.MaxActiveTaskLimit or 10
    local value = data.upgrades and data.upgrades.maxActiveTasks or base
    return math.min(limit, math.max(base, math.floor(tonumber(value) or base)))
end

function GodSystemApp.services.runtime.getDailyTaskCount()
    local data = GodSystemApp.services.runtime.getData()
    local base = GodSystemConfig.DailyTaskCount or 5
    local limit = GodSystemConfig.MaxDailyTaskLimit or 20
    local value = data.upgrades and data.upgrades.dailyTaskCount or base
    return math.min(limit, math.max(base, math.floor(tonumber(value) or base)))
end

function GodSystemApp.services.runtime.getCarryCapacityLevel()
    local data = GodSystemApp.services.runtime.getData()
    data.upgrades = data.upgrades or {}
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.getLevel(data, gsPlayer())
    return data.upgrades.carryCapacityLevel
end

function GodSystemApp.services.runtime.restoreCarryCapacity(player, data)
    player = player or gsPlayer()
    data = data or GodSystemApp.services.runtime.getData()
    if not player or not data then return false, "noPlayer" end
    return GodSystemCarryCapacity.restore(player, GodSystemCarryCapacity.getLevel(data, player))
end

function GodSystemApp.services.runtime.refreshCarryCapacity()
    local ok, reason = GodSystemApp.services.runtime.restoreCarryCapacity(gsPlayer(), GodSystemApp.services.runtime.getData())
    if ok then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CarryCapacityRestored", "Carry base restored"))
        return true
    end
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CarryCapacityRestoreFailed", "Unable to restore carry base") .. " (" .. tostring(reason or "unknown") .. ")")
    return false
end
end
