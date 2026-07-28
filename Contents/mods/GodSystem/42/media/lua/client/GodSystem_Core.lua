require "GodSystem_Config"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_Localization"
require "GodSystem_Localization_Override"
require "GodSystem_AdminConfig"
require "GodSystem_CompanionConfig"
require "GodSystem_Attributes"
require "GodSystem_CarryCapacity"
require "GodSystem_TerminalUpgrades"
require "GodSystem_ShopVariants"
require "GodSystem_Storage"

GodSystem = GodSystem or {}
GodSystem.data = nil
GodSystem.configuredShopKeySet = GodSystemShopVariants.getConfiguredKeySet(GodSystemConfig.ShopItems or {})
GodSystem.updateTicks = 0
GodSystem.notifyQueue = GodSystem.notifyQueue or {}
GodSystem.notifyQueueActive = GodSystem.notifyQueueActive == true
GodSystem.notifyLastMs = tonumber(GodSystem.notifyLastMs) or 0

local function gsPlayer()
    return getPlayer and getPlayer() or nil
end

local function gsNowHours()
    if GameTime and GameTime:getInstance() then
        return GameTime:getInstance():getWorldAgeHours()
    end
    return 0
end

local function gsNowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return math.floor(gsNowHours() * 3600000)
end

local function gsCurrentDay()
    return math.floor(gsNowHours() / 24)
end

local function gsRandomIndex(max)
    if not max or max <= 1 then
        return 1
    end
    if ZombRand then
        return ZombRand(max) + 1
    end
    return math.random(max)
end

local function gsFormatText(template, args)
    local text = tostring(template or "")
    for i = 1, #(args or {}) do
        text = text:gsub("{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return text
end

local function gsSafeIsFavorite(item)
    if item and item.isFavorite then
        local ok, value = pcall(function() return item:isFavorite() end)
        return ok and value
    end
    return false
end

local function gsSafeIsBroken(item)
    if item and item.isBroken then
        local ok, value = pcall(function() return item:isBroken() end)
        return ok and value
    end
    return false
end

local function gsSafeUsedDelta(item)
    if item and item.getUsedDelta then
        local ok, value = pcall(function() return item:getUsedDelta() end)
        if ok and value and value > 0 and value < 1 then
            return value
        end
    end
    return nil
end

local function gsItemHasInventory(item)
    if not item or not item.getInventory then
        return false
    end
    local ok, child = pcall(function() return item:getInventory() end)
    return ok and child ~= nil
end

local function gsItemInventoryCount(item)
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

function GodSystem.getContextContainerSignature(item)
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

local function gsCopyItems(items)
    local result = {}
    if not items then
        return result
    end
    for i = 1, #items do
        result[i] = { fullType = items[i].fullType, worldSprite = items[i].worldSprite, count = items[i].count or 1 }
    end
    return result
end

local function gsMultiplyItems(items, multiplier)
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

local function gsCopyStringArray(items)
    local result = {}
    if not items then
        return result
    end
    for i = 1, #items do
        result[i] = items[i]
    end
    return result
end

local function gsFormatText(template, args)
    local text = tostring(template or "")
    for i = 1, #(args or {}) do
        text = string.gsub(text, "{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return text
end

local function gsAppendHistory(data, entry)
    data.history = data.history or {}
    entry.time = gsNowHours()
    table.insert(data.history, 1, entry)
    local limit = GodSystemConfig.HistoryLimit or 40
    while #data.history > limit do
        table.remove(data.history)
    end
end

local function gsCollectInventoryItems(container, result, fullType, includeFavorite, includeEquipped)
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

local function gsFindInventoryItems(fullType, includeFavorite, includeEquipped)
    local player = gsPlayer()
    local result = {}
    if not player then
        return result
    end
    gsCollectInventoryItems(player:getInventory(), result, fullType, includeFavorite, includeEquipped)
    return result
end

local function gsInventoryItemById(itemId)
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

local function gsCurrencyDenoms()
    return GodSystemConfig.CurrencyItems or {}
end

local function gsRestoreRemovedCurrency(removed)
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
        local ok, added = GodSystem.giveItem(fullType, row.count)
        if not ok or #(added or {}) < row.count then
            okAll = false
            failedValue = failedValue + row.count * row.value
        end
    end
    return okAll, failedValue
end

local function gsEnsureKillTaskProgress(task, baselineKills)
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

local function gsApplyKillTaskDelta(data, delta, baselineKills)
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

function GodSystem.text(key, fallback)
    local fullKey = "IGUI_GodSystem_" .. tostring(key)
    local fallbackValue = nil
    if GodSystemFallbackText and GodSystemFallbackText.zh and GodSystemFallbackText.zh[key] then
        fallbackValue = GodSystemFallbackText.zh[key]
    end
    if fallbackValue then
        return fallbackValue
    end
    if getText then
        local value = getText(fullKey)
        if value and value ~= fullKey then
            return value
        end
    end
    return fallback or fullKey
end

local function gsGetModuleName(fullType)
    if not fullType then
        return nil
    end
    return string.match(fullType, "^([^%.]+)%.")
end

local BANK_INVESTMENT_IDS = { "stable", "balanced", "aggressive" }

local function gsNormalizeBankInvestments(bank)
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

function GodSystem.getData()
    if GodSystem.data then
        return GodSystem.data
    end

    local data = ModData.getOrCreate(GodSystemConfig.DataKey)
    local previousVersion = data.version
    data.version = GodSystemConfig.Version
    data.lastGeneratedDay = data.lastGeneratedDay or -1
    data.tasks = data.tasks or {}
    data.history = data.history or {}
    data.unlockedShopItems = data.unlockedShopItems or {}
    GodSystemShopVariants.normalizeUnlocked(data, GodSystem.configuredShopKeySet)
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
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.normalizeLevel(data.upgrades.carryCapacityLevel)
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
    data.autoRecyclerClaimed = data.autoRecyclerClaimed == true
    GodSystemTerminalUpgrades.normalizeData(data)
    data.lastAutoRecyclerHour = data.lastAutoRecyclerHour or math.floor(gsNowHours())
    data.waistAutoRecycleUnlocked = data.waistAutoRecycleUnlocked == true
    data.waistAutoRecycleEnabled = data.waistAutoRecycleEnabled == true
    data.waistRecycleUnlockMode = data.waistRecycleUnlockMode == true
    data.lastWaistAutoRecycleHour = data.lastWaistAutoRecycleHour or math.floor(gsNowHours())
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled == true
    data.lastAutoTaskClaimHour = tonumber(data.lastAutoTaskClaimHour) or gsNowHours()
    data.companion = GodSystemCompanionConfig.ensureData(data.companion)
    data.ui = data.ui or {}
    data.ui.x = data.ui.x or GodSystemConfig.FloatingButton.x
    data.ui.y = data.ui.y or GodSystemConfig.FloatingButton.y
    data.adminConfig = data.adminConfig or {}
    if data.adminConfig.settings == nil then
        data.adminConfig.settings = GodSystemAdminConfig.getSandboxDefaults()
    else
        data.adminConfig.settings = GodSystemAdminConfig.sanitizeSettings(data.adminConfig.settings)
    end
    data.adminConfig.itemOverrides = data.adminConfig.itemOverrides or {}
    if not (isClient and isClient()) then
        GodSystemAdminConfig.applyRuntime(data.adminConfig.settings, data.adminConfig.itemOverrides)
    end

    if previousVersion and previousVersion ~= GodSystemConfig.Version then
        gsAppendHistory(data, { kind = "system", text = GodSystem.text("History_Upgraded", "God System upgraded to v") .. tostring(GodSystemConfig.Version) })
    end

    local player = gsPlayer()
    if player and data.lastKnownKills == nil then
        data.lastKnownKills = player:getZombieKills()
    end

    GodSystem.data = data
    return data
end

function GodSystem.applyAdminConfigSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    local settings, itemOverrides = GodSystemAdminConfig.applyRuntime(snapshot.settings or {}, snapshot.itemOverrides or {})
    GodSystem.adminConfigSnapshot = {
        settings = settings,
        itemOverrides = itemOverrides,
        meta = snapshot.meta or GodSystemAdminConfig.getMeta(),
    }
    return true
end

function GodSystem.getAdminConfigSnapshot()
    if GodSystem.adminConfigSnapshot then
        return GodSystem.adminConfigSnapshot
    end
    local data = GodSystem.getData()
    data.adminConfig = data.adminConfig or {}
    data.adminConfig.settings = GodSystemAdminConfig.sanitizeSettings(data.adminConfig.settings or {})
    data.adminConfig.itemOverrides = data.adminConfig.itemOverrides or {}
    local snapshot = {
        settings = data.adminConfig.settings,
        itemOverrides = data.adminConfig.itemOverrides,
        meta = GodSystemAdminConfig.getMeta(),
    }
    GodSystem.applyAdminConfigSnapshot(snapshot)
    return GodSystem.adminConfigSnapshot
end

function GodSystem.isAdminConfigAllowed()
    if isClient and isClient() then
        return GodSystem.serverAdmin == true
    end
    return true
end

function GodSystem.isFeatureEnabled(key)
    return GodSystemAdminConfig.isFeatureEnabled(key)
end

function GodSystem.saveAdminSettings(settings)
    settings = GodSystemAdminConfig.sanitizeSettings(settings or {})
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("adminConfigSet", { settings = settings })
    end
    local data = GodSystem.getData()
    data.adminConfig = data.adminConfig or {}
    data.adminConfig.settings = settings
    GodSystem.applyAdminConfigSnapshot(data.adminConfig)
    if GodSystem.refreshAutoRecyclerContainers then
        GodSystem.refreshAutoRecyclerContainers(true)
    end
    GodSystem.save()
    return true
end

function GodSystem.saveItemOverride(fullType, override)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then return false end
    local clean = GodSystemAdminConfig.sanitizeItemOverride(override or {})
    if not clean then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("adminItemOverrideSet", { fullType = fullType, override = clean })
    end
    local data = GodSystem.getData()
    data.adminConfig = data.adminConfig or {}
    data.adminConfig.itemOverrides = data.adminConfig.itemOverrides or {}
    data.adminConfig.itemOverrides[fullType] = clean
    GodSystem.applyAdminConfigSnapshot(data.adminConfig)
    GodSystem.save()
    return true
end

function GodSystem.clearItemOverride(fullType)
    fullType = tostring(fullType or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then return false end
    if isClient and isClient() then
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("adminItemOverrideClear", { fullType = fullType })
    end
    local data = GodSystem.getData()
    data.adminConfig = data.adminConfig or {}
    data.adminConfig.itemOverrides = data.adminConfig.itemOverrides or {}
    data.adminConfig.itemOverrides[fullType] = nil
    GodSystem.applyAdminConfigSnapshot(data.adminConfig)
    GodSystem.save()
    return true
end

function GodSystem.save()
    if ModData and ModData.transmit then
        pcall(function() ModData.transmit(GodSystemConfig.DataKey) end)
    end
end

function GodSystem.getCurrencyTotal()
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

function GodSystem.getCurrencyDisplayTotal()
    local now = gsNowMs()
    local cache = GodSystem.currencyDisplayCache
    if cache and now - (cache.at or 0) < 250 then return cache.total or 0 end
    local total = GodSystem.getCurrencyTotal()
    GodSystem.currencyDisplayCache = { at = now, total = total }
    return total
end

function GodSystem.giveCurrency(amount)
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
            local ok, addedItems = GodSystem.giveItem(denom.fullType, count)
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

function GodSystem.consolidateCurrency()
    local denoms = gsCurrencyDenoms()
    local total = 0
    local removed = {}
    local originalCount = 0
    for i = 1, #denoms do
        local denom = denoms[i]
        local value = math.max(1, math.floor(tonumber(denom.value) or 1))
        local found = gsFindInventoryItems(denom.fullType, true, true)
        for j = 1, #found do
            if not GodSystem.removeCurrencyItem(found[j].container, found[j].item) then
                GodSystem.restoreRemovedCurrencyOrBank(removed)
                GodSystem.notify(GodSystem.text("Notify_CurrencyConsolidateFailed", "Currency consolidation failed"))
                return false
            end
            table.insert(removed, { fullType = denom.fullType, value = value })
            total = total + value
            originalCount = originalCount + 1
        end
    end
    if total <= 0 then
        GodSystem.notify(GodSystem.text("Notify_CurrencyConsolidateNone", "No system currency to consolidate"))
        return false
    end
    if not GodSystem.giveCurrency(total) then
        GodSystem.restoreRemovedCurrencyOrBank(removed)
        GodSystem.notify(GodSystem.text("Notify_CurrencyConsolidateFailed", "Currency consolidation failed"))
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
    gsAppendHistory(GodSystem.getData(), { kind = "bank", text = gsFormatText(GodSystem.text("History_CurrencyConsolidated", "Currency consolidated: {1} coins, {2} items -> {3} items"), { total, originalCount, newCount }) })
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_CurrencyConsolidated", "Currency consolidated: {1} coins, {2} items -> {3} items"), { total, originalCount, newCount }))
    GodSystem.save()
    return true
end

function GodSystem.containerContainsItem(container, item)
    if not container or not item or not container.getItems then return false end
    local ok, contains = pcall(function()
        local items = container:getItems()
        return items and items.contains and items:contains(item) == true
    end)
    return ok and contains == true
end

function GodSystem.removeCurrencyItem(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:Remove(item) end)
    if not ok or GodSystem.containerContainsItem(container, item) then return false end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    return true
end

function GodSystem.removeCurrency(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end

    local total = GodSystem.getCurrencyTotal()
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
                if not GodSystem.removeCurrencyItem(found[j].container, found[j].item) then
                    GodSystem.restoreRemovedCurrencyOrBank(removed)
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
                if not GodSystem.removeCurrencyItem(found[j].container, found[j].item) then
                    GodSystem.restoreRemovedCurrencyOrBank(removed)
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
        GodSystem.restoreRemovedCurrencyOrBank(removed)
        return false
    end

    local change = removedValue - amount
    if change > 0 and not GodSystem.giveCurrency(change) then
        GodSystem.restoreRemovedCurrencyOrBank(removed)
        return false
    end
    return true
end

function GodSystem.updateKillTaskProgress(delta, baselineKills)
    local data = GodSystem.getData()
    local changed = gsApplyKillTaskDelta(data, delta, baselineKills)
    if changed then
        GodSystem.save()
    end
    return changed
end

function GodSystem.normalizeActiveKillTasks(baselineKills)
    local data = GodSystem.getData()
    local player = gsPlayer()
    local kills = baselineKills or (player and player.getZombieKills and player:getZombieKills() or 0)
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" and task.kind == "kill" then
            gsEnsureKillTaskProgress(task, kills)
        end
    end
end

function GodSystem.ensureCurrencyInitialized()
    local data = GodSystem.getData()
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
        if not GodSystem.giveCurrency(grant) then
            data.started = true
            data.currencyInitialized = false
            data.points = grant
            GodSystem.notify(GodSystem.text("Error_CurrencyGrantFailed", "Currency item grant failed. Check mod install: ") .. "GodSystem_Items.txt")
            GodSystem.save()
            return
        end
    end

    data.started = true
    data.currencyInitialized = true
    data.points = 0

    if grant > 0 then
        gsAppendHistory(data, { kind = "system", text = GodSystem.text("History_InitialCurrency", "System activated, initial currency ") .. tostring(grant) })
        GodSystem.notify(GodSystem.text("Notify_InitialCurrency", "System activated, currency +") .. tostring(grant))
    end
    GodSystem.save()
end

function GodSystem.notifyNow(text)
    local player = gsPlayer()
    if not player then
        return
    end
    text = tostring(text or "")
    if text == "" then
        return
    end
    if player.Say then
        player:Say(text)
    end
end

function GodSystem.processNotifyQueue()
    local queue = GodSystem.notifyQueue or {}
    if #queue <= 0 then
        GodSystem.notifyQueueActive = false
        if Events and Events.OnTick then
            Events.OnTick.Remove(GodSystem.processNotifyQueue)
        end
        return
    end

    local now = gsNowMs()
    local interval = math.max(800, math.floor(tonumber(GodSystemConfig.NotifyQueueIntervalMs) or 1600))
    if now - (GodSystem.notifyLastMs or 0) < interval then
        return
    end
    GodSystem.notifyLastMs = now
    local text = table.remove(queue, 1)
    GodSystem.notifyNow(text)
end

function GodSystem.notify(text)
    text = tostring(text or "")
    if text == "" then
        return
    end
    GodSystem.notifyQueue = GodSystem.notifyQueue or {}
    table.insert(GodSystem.notifyQueue, text)
    if Events and Events.OnTick then
        if not GodSystem.notifyQueueActive then
            GodSystem.notifyQueueActive = true
            Events.OnTick.Remove(GodSystem.processNotifyQueue)
            Events.OnTick.Add(GodSystem.processNotifyQueue)
        end
    else
        GodSystem.processNotifyQueue()
    end
end

function GodSystem.addPoints(amount, reason)
    local data = GodSystem.getData()
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then
        return true
    end

    local ok = true
    if amount > 0 then
        ok = GodSystem.giveCurrency(amount)
    else
        ok = GodSystem.spendCurrency(math.abs(amount))
    end
    if not ok then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    if reason then
        local sign = amount > 0 and "+" or ""
        gsAppendHistory(data, { kind = "points", text = reason .. " " .. sign .. tostring(amount) .. GodSystem.text("Unit_Coin", " coins") })
        GodSystem.notify(reason .. " " .. sign .. tostring(amount) .. GodSystem.text("Unit_Coin", " coins"))
    end
    GodSystem.save()
    return true
end

function GodSystem.canAfford(cost)
    return GodSystem.getSpendableBalance() >= math.max(0, math.floor(tonumber(cost) or 0))
end

function GodSystem.getMaxActiveTasks()
    local data = GodSystem.getData()
    local base = GodSystemConfig.MaxActiveTasks or 3
    local limit = GodSystemConfig.MaxActiveTaskLimit or 10
    local value = data.upgrades and data.upgrades.maxActiveTasks or base
    return math.min(limit, math.max(base, math.floor(tonumber(value) or base)))
end

function GodSystem.getDailyTaskCount()
    local data = GodSystem.getData()
    local base = GodSystemConfig.DailyTaskCount or 5
    local limit = GodSystemConfig.MaxDailyTaskLimit or 20
    local value = data.upgrades and data.upgrades.dailyTaskCount or base
    return math.min(limit, math.max(base, math.floor(tonumber(value) or base)))
end

function GodSystem.getCarryCapacityLevel()
    local data = GodSystem.getData()
    data.upgrades = data.upgrades or {}
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.normalizeLevel(data.upgrades.carryCapacityLevel)
    return data.upgrades.carryCapacityLevel
end

function GodSystem.applyCarryCapacity(player, data)
    player = player or gsPlayer()
    data = data or GodSystem.getData()
    if not player or not data then return false, "noPlayer" end
    return GodSystemCarryCapacity.apply(player, GodSystemCarryCapacity.getLevel(data))
end

function GodSystem.refreshCarryCapacity()
    local ok, reason = GodSystem.applyCarryCapacity(gsPlayer(), GodSystem.getData())
    if ok then
        GodSystem.notify(GodSystem.text("Notify_CarryCapacityRefreshed", "Carry capacity bonus refreshed"))
        return true
    end
    GodSystem.notify(GodSystem.text("Notify_CarryCapacityRefreshFailed", "Unable to refresh carry capacity bonus") .. " (" .. tostring(reason or "unknown") .. ")")
    return false
end

function GodSystem.getSystemUpgradeInfo(upgradeType)
    local data = GodSystem.getData()
    data.upgrades = data.upgrades or {}
    if upgradeType == "activeTasks" then
        local current = GodSystem.getMaxActiveTasks()
        local maxValue = GodSystemConfig.MaxActiveTaskLimit or 10
        local nextValue = math.min(maxValue, current + 1)
        local cost = nil
        if current < maxValue then
            cost = (GodSystemConfig.ActiveTaskUpgradeCosts or {})[nextValue] or (nextValue * 120)
        end
        return {
            upgradeType = upgradeType,
            current = current,
            nextValue = nextValue,
            maxValue = maxValue,
            cost = cost,
            label = GodSystem.text("Upgrade_ActiveTasks", "Active task slots"),
            desc = GodSystem.text("Upgrade_ActiveTasksDesc", "Increase the maximum number of active tasks by 1."),
        }
    end
    if upgradeType == "dailyTasks" then
        local current = GodSystem.getDailyTaskCount()
        local maxValue = GodSystemConfig.MaxDailyTaskLimit or 20
        local nextValue = math.min(maxValue, current + 1)
        local cost = nil
        if current < maxValue then
            cost = (GodSystemConfig.DailyTaskUpgradeCosts or {})[nextValue] or (nextValue * 30)
        end
        return {
            upgradeType = upgradeType,
            current = current,
            nextValue = nextValue,
            maxValue = maxValue,
            cost = cost,
            label = GodSystem.text("Upgrade_DailyTasks", "Daily task display"),
            desc = GodSystem.text("Upgrade_DailyTasksDesc", "Increase the number of tasks generated each day by 1. Adds one open task immediately."),
        }
    end
    if upgradeType == "carryCapacity" then
        local level = GodSystem.getCarryCapacityLevel()
        local cost = GodSystemCarryCapacity.getNextCost(level)
        local status = GodSystemCarryCapacity.getStatus(gsPlayer(), level)
        return {
            upgradeType = upgradeType,
            current = level,
            nextValue = level + 1,
            maxValue = nil,
            cost = cost,
            label = GodSystem.text("Upgrade_CarryCapacity", "Carry capacity"),
            desc = GodSystem.text("Upgrade_CarryCapacityDesc", "Permanently increase player carry capacity; the actual bonus is calculated from the current character state."),
            carryStatus = status,
        }
    end
    if upgradeType == "terminalCapacity" or upgradeType == "terminalReduction" or upgradeType == "terminalRelief" then
        local terminalType = string.gsub(upgradeType, "^terminal", "")
        terminalType = string.lower(string.sub(terminalType, 1, 1)) .. string.sub(terminalType, 2)
        local terminalInfo = GodSystemTerminalUpgrades.getUpgradeInfo(GodSystem.getData(), terminalType)
        if not terminalInfo then return nil end
        local labels = {
            capacity = GodSystem.text("Upgrade_TerminalCapacity", "Terminal capacity"),
            reduction = GodSystem.text("Upgrade_TerminalReduction", "Terminal reduction"),
            relief = GodSystem.text("Upgrade_TerminalRelief", "Space relief"),
        }
        return {
            upgradeType = upgradeType,
            terminalType = terminalType,
            current = terminalInfo.level,
            nextValue = terminalInfo.level + 1,
            maxValue = terminalInfo.maxLevel,
            cost = terminalInfo.nextCost,
            label = labels[terminalType] or upgradeType,
            desc = terminalType == "relief"
                and GodSystem.text("Upgrade_TerminalReliefDesc", "Adds protected hidden relief inside the terminal without changing its native capacity.")
                or GodSystem.text("Upgrade_TerminalIndependentDesc", "This upgrade only changes the selected terminal property."),
            terminalInfo = terminalInfo,
        }
    end
    return nil
end

function GodSystem.getSystemUpgradeDetailText(upgradeType)
    local info = GodSystem.getSystemUpgradeInfo(upgradeType)
    if not info then
        return ""
    end
    if upgradeType == "carryCapacity" then
        local status = info.carryStatus or {}
        local base = status.base ~= nil and tostring(status.base) or "?"
        local total = status.total ~= nil and tostring(status.total) or "?"
        local actualBonus = tonumber(status.actualBonus) or 0
        local actualBonusText = actualBonus >= 0 and ("+" .. tostring(actualBonus)) or tostring(actualBonus)
        local costText = info.cost and (tostring(info.cost) .. GodSystem.text("Unit_CoinShort", "c")) or GodSystem.text("Upgrade_CostOverflow", "Unavailable")
        return tostring(info.desc or "")
            .. " | " .. GodSystem.text("Upgrade_CarryBase", "Current base") .. " " .. base
            .. " | " .. GodSystem.text("Upgrade_CarryBonus", "Actual bonus") .. " " .. actualBonusText
            .. " | " .. GodSystem.text("Upgrade_CarryTotal", "Final carry") .. " " .. total
            .. " | " .. GodSystem.text("Upgrade_Level", "Level") .. " " .. tostring(info.current)
            .. " | " .. GodSystem.text("Upgrade_Cost", "Cost") .. " " .. costText
    end
    local nextText = info.cost and (tostring(info.current) .. " -> " .. tostring(info.nextValue)) or tostring(info.current)
    local costText = info.cost and (tostring(info.cost) .. GodSystem.text("Unit_CoinShort", "c")) or GodSystem.text("Upgrade_Maxed", "Maxed")
    return tostring(info.desc or "") .. " | " .. GodSystem.text("Upgrade_Current", "Current") .. " " .. tostring(info.current) .. "/" .. tostring(info.maxValue) .. " | " .. GodSystem.text("Upgrade_Next", "Next") .. " " .. nextText .. " | " .. GodSystem.text("Upgrade_Cost", "Cost") .. " " .. costText
end

function GodSystem.upgradeSystem(upgradeType)
    local info = GodSystem.getSystemUpgradeInfo(upgradeType)
    if not info then
        return false
    end
    if not info.cost then
        if upgradeType == "carryCapacity" then
            GodSystem.notify(GodSystem.text("Notify_CarryCapacityCostOverflow", "The next cost exceeds the safe numeric range"))
        else
            GodSystem.notify(GodSystem.text("Notify_UpgradeMaxed", "Already at max level"))
        end
        return false
    end
    if not GodSystem.canAfford(info.cost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    if info.terminalType then
        local entry = GodSystem.getAutoRecyclerContainer(true)
        if not entry or not entry.item then
            GodSystem.notify(GodSystem.text("Notify_AutoRecyclerMissing", "System space terminal not found"))
            return false
        end
        local data = GodSystem.getData()
        local previousLevel = GodSystemTerminalUpgrades.getLevel(data, info.terminalType)
        local snapshot = GodSystemTerminalUpgrades.snapshotTerminal(entry.item, gsPlayer())
        GodSystemTerminalUpgrades.setLevel(data, info.terminalType, previousLevel + 1)
        local applied, report = GodSystemTerminalUpgrades.applyTerminal(entry.item, data, gsPlayer())
        if not applied then
            GodSystemTerminalUpgrades.setLevel(data, info.terminalType, previousLevel)
            GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
            GodSystemTerminalUpgrades.applyTerminal(entry.item, data, gsPlayer())
            local failureKey = info.terminalType == "relief" and "Notify_TerminalReliefApplyFailed" or "Notify_TerminalUpgradeApplyFailed"
            GodSystem.notify(GodSystem.text(failureKey, "Terminal upgrade failed; no currency spent"))
            return false
        end
        if not GodSystem.addPoints(-info.cost) then
            GodSystemTerminalUpgrades.setLevel(data, info.terminalType, previousLevel)
            GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
            GodSystemTerminalUpgrades.applyTerminal(entry.item, data, gsPlayer())
            return false
        end
        data.autoRecyclerClaimed = true
        data.stats = data.stats or {}
        data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
        gsAppendHistory(data, {
            kind = "upgrade",
            text = tostring(info.label) .. " Lv." .. tostring(previousLevel + 1) .. " -" .. tostring(info.cost) .. GodSystem.text("Unit_Coin", " coins"),
        })
        GodSystem.save()
        GodSystem.notify(tostring(info.label) .. " Lv." .. tostring(previousLevel + 1))
        return true
    end

    if upgradeType == "carryCapacity" then
        local player = gsPlayer()
        local data = GodSystem.getData()
        local previousLevel = GodSystem.getCarryCapacityLevel()
        local nextLevel = previousLevel + 1
        local applied, applyResult = GodSystemCarryCapacity.apply(player, nextLevel)
        if not applied then
            GodSystem.notify(GodSystem.text("Notify_CarryCapacityApplyFailed", "Carry capacity upgrade could not be applied") .. " (" .. tostring(applyResult or "unknown") .. ")")
            return false
        end
        if not GodSystem.addPoints(-info.cost) then
            GodSystemCarryCapacity.apply(player, previousLevel)
            return false
        end
        data.upgrades = data.upgrades or {}
        data.upgrades.carryCapacityLevel = nextLevel
        data.stats = data.stats or {}
        data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
        local measuredIncrease = tonumber(applyResult and applyResult.predictedIncrease) or 0
        local measuredIncreaseText = measuredIncrease >= 0 and ("+" .. tostring(measuredIncrease)) or tostring(measuredIncrease)
        local measuredFinal = tonumber(applyResult and applyResult.predictedFinal) or tonumber(applyResult and applyResult.total) or "?"
        gsAppendHistory(data, {
            kind = "upgrade",
            text = gsFormatText(GodSystem.text("History_CarryCapacityUpgrade", "Carry capacity upgrade: Lv.{1}, measured increase {2}, estimated final {3}, cost {4}"), {
                nextLevel,
                measuredIncreaseText,
                measuredFinal,
                info.cost,
            }),
        })
        GodSystem.save()
        GodSystem.notify(gsFormatText(GodSystem.text("Notify_CarryCapacityUpgraded", "Carry capacity upgraded to Lv.{1}; measured increase {2}; estimated final {3}"), {
            nextLevel,
            measuredIncreaseText,
            measuredFinal,
        }))
        return true
    end
    if not GodSystem.addPoints(-info.cost) then
        return false
    end

    local data = GodSystem.getData()
    data.upgrades = data.upgrades or {}
    if upgradeType == "activeTasks" then
        data.upgrades.maxActiveTasks = info.nextValue
    elseif upgradeType == "dailyTasks" then
        data.upgrades.dailyTaskCount = info.nextValue
        local templates = GodSystem.getAvailableTaskTemplates()
        if #templates > 0 then
            data.tasks = data.tasks or {}
            table.insert(data.tasks, GodSystem.generateTaskFromTemplate(templates[gsRandomIndex(#templates)]))
        end
    end
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
    gsAppendHistory(data, { kind = "upgrade", text = GodSystem.text("History_SystemUpgrade", "System upgrade: ") .. tostring(info.label) .. " " .. tostring(info.current) .. " -> " .. tostring(info.nextValue) .. " -" .. tostring(info.cost) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_SystemUpgrade", "System upgraded: ") .. tostring(info.label) .. " " .. tostring(info.nextValue))
    return true
end

function GodSystem.getBank()
    local data = GodSystem.getData()
    data.bank = data.bank or {}
    data.bank.current = math.max(0, math.floor(tonumber(data.bank.current) or 0))
    data.bank.fixed = data.bank.fixed or {}
    data.bank.nextId = math.max(1, math.floor(tonumber(data.bank.nextId) or 1))
    data.bank.lastDeathPenaltyHour = tonumber(data.bank.lastDeathPenaltyHour) or -999
    data.bank.nextLoanId = math.max(1, math.floor(tonumber(data.bank.nextLoanId) or 1))
    data.bank.loanFrozenUntilHour = tonumber(data.bank.loanFrozenUntilHour) or 0
    data.bank.loanCreditSpentOffset = math.max(0, math.floor(tonumber(data.bank.loanCreditSpentOffset) or 0))
    data.bank.loanBankruptcyCount = math.max(0, math.floor(tonumber(data.bank.loanBankruptcyCount) or 0))
    data.bank.autoDepositEnabled = data.bank.autoDepositEnabled == true
    data.bank.lastAutoDepositHour = tonumber(data.bank.lastAutoDepositHour) or gsNowHours()
    gsNormalizeBankInvestments(data.bank)
    local now = gsNowHours()
    for i = #data.bank.fixed, 1, -1 do
        local entry = data.bank.fixed[i]
        if not entry or math.max(0, math.floor(tonumber(entry.principal) or 0)) <= 0 then
            table.remove(data.bank.fixed, i)
        else
            entry.id = tostring(entry.id or ("F" .. tostring(i)))
            entry.termId = tostring(entry.termId or "")
            entry.principal = math.max(0, math.floor(tonumber(entry.principal) or 0))
            entry.startHour = tonumber(entry.startHour) or now
            entry.matureHour = tonumber(entry.matureHour) or entry.startHour
            entry.rate = tonumber(entry.rate) or 0
            entry.days = math.max(1, math.floor(tonumber(entry.days) or math.max(1, math.ceil((entry.matureHour - entry.startHour) / 24))))
        end
    end
    if type(data.bank.loan) == "table" then
        local loan = data.bank.loan
        loan.id = tostring(loan.id or ("L" .. tostring(data.bank.nextLoanId or 1)))
        loan.kind = tostring(loan.kind or "single")
        loan.planId = tostring(loan.planId or loan.kind or "single")
        loan.principal = math.max(0, math.floor(tonumber(loan.principal) or 0))
        loan.createdHour = tonumber(loan.createdHour) or now
        loan.totalInterest = math.max(0, math.floor(tonumber(loan.totalInterest) or 0))
        loan.totalDue = math.max(loan.principal + loan.totalInterest, math.floor(tonumber(loan.totalDue) or 0))
        loan.paid = math.max(0, math.floor(tonumber(loan.paid) or 0))
        loan.schedule = type(loan.schedule) == "table" and loan.schedule or {}
        loan.overdueStartHour = tonumber(loan.overdueStartHour)
        for i = #loan.schedule, 1, -1 do
            local bill = loan.schedule[i]
            if type(bill) ~= "table" then
                table.remove(loan.schedule, i)
            else
                bill.index = math.max(1, math.floor(tonumber(bill.index) or i))
                bill.dueHour = tonumber(bill.dueHour) or loan.createdHour
                bill.principalPart = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
                bill.interestPart = math.max(0, math.floor(tonumber(bill.interestPart) or 0))
                bill.paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
            end
        end
        if loan.principal <= 0 or loan.totalDue <= 0 or loan.paid >= loan.totalDue then
            data.bank.loan = nil
        end
    else
        data.bank.loan = nil
    end
    return data.bank
end

function GodSystem.getSpendableBalance()
    local bank = GodSystem.getBank()
    return math.max(0, math.floor(tonumber(bank.current) or 0)) + math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0))
end

function GodSystem.spendCurrency(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return true, 0, 0
    end
    local bank = GodSystem.getBank()
    local cash = math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0))
    local current = math.max(0, math.floor(tonumber(bank.current) or 0))
    if current + cash < amount then
        return false, 0, 0
    end
    local fromBank = math.min(current, amount)
    if fromBank > 0 then
        bank.current = math.max(0, current - fromBank)
    end
    local fromCash = amount - fromBank
    if fromCash > 0 and not GodSystem.removeCurrency(fromCash) then
        if fromBank > 0 then
            bank.current = (bank.current or 0) + fromBank
        end
        return false, 0, 0
    end
    return true, fromBank, fromCash
end

function GodSystem.refundCurrencySources(fromBank, fromCash)
    local bank = GodSystem.getBank()
    local bankAmount = math.max(0, math.floor(tonumber(fromBank) or 0))
    local cashAmount = math.max(0, math.floor(tonumber(fromCash) or 0))
    bank.current = (bank.current or 0) + bankAmount
    if cashAmount <= 0 then return true end
    if GodSystem.giveCurrency(cashAmount) then return true end
    bank.current = (bank.current or 0) + cashAmount
    return false
end

function GodSystem.recordStorageControllerClaim(cost, recovered)
    local data = GodSystem.getData()
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    data.stats = data.stats or {}
    if cost > 0 then
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    end
    local key = recovered and "History_StorageControllerRecovered" or "History_StorageControllerClaimed"
    local fallback = recovered and "Storage controller recovered" or "Storage controller claimed"
    local suffix = cost > 0 and (" -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins")) or ""
    gsAppendHistory(data, {
        kind = "storage",
        text = GodSystem.text(key, fallback) .. suffix,
    })
end

function GodSystem.restoreRemovedCurrencyOrBank(removed)
    local ok, failedValue = gsRestoreRemovedCurrency(removed)
    if failedValue > 0 then
        local bank = GodSystem.getBank()
        bank.current = (bank.current or 0) + failedValue
    end
    return ok, failedValue
end

function GodSystem.getCompanionData()
    local data = GodSystem.getData()
    data.companion = GodSystemCompanionConfig.ensureData(data.companion)
    return data.companion
end

local function gsCompanionPurchaseFailed(key, fallback)
    GodSystem.notify(GodSystem.text(key, fallback))
    return false
end

function GodSystem.purchaseCompanionNode(nodeId)
    if (isClient and isClient()) or (isServer and isServer()) then return false end
    if not GodSystemCompanionConfig.isEnabled() then
        return gsCompanionPurchaseFailed("Notify_CompanionDisabled", "Companion system is disabled")
    end

    nodeId = tostring(nodeId or "")
    local data = GodSystem.getData()
    local companion = GodSystem.getCompanionData()
    local cost = nil
    local apply = nil

    local unlock = GodSystemCompanionConfig.Unlocks[nodeId]
    if unlock then
        if GodSystemCompanionConfig.isUnlocked(companion, nodeId) then
            return gsCompanionPurchaseFailed("Notify_CompanionAlreadyUnlocked", "Already unlocked")
        end
        if unlock.requires and not GodSystemCompanionConfig.isUnlocked(companion, unlock.requires) then
            return gsCompanionPurchaseFailed("Notify_CompanionRequiresProjection", "Unlock the projection first")
        end
        cost = GodSystemCompanionConfig.scaleCost(unlock.cost)
        apply = function()
            if nodeId == "projection" then companion.unlocked = true else companion.unlocks[nodeId] = true end
        end
    elseif GodSystemCompanionConfig.Stats[nodeId] then
        local definition = GodSystemCompanionConfig.Stats[nodeId]
        if not GodSystemCompanionConfig.isUnlocked(companion, definition.requires) then
            return gsCompanionPurchaseFailed("Notify_CompanionAbilityLocked", "Required ability is locked")
        end
        cost = GodSystemCompanionConfig.getUpgradeCost(companion, nodeId)
        if not cost then
            return gsCompanionPurchaseFailed("Notify_CompanionMaxLevel", "Already at maximum level")
        end
        apply = function() companion.levels[nodeId] = companion.levels[nodeId] + 1 end
    elseif GodSystemCompanionConfig.Effects[nodeId] then
        if not companion.unlocks.attack then
            return gsCompanionPurchaseFailed("Notify_CompanionAbilityLocked", "Required ability is locked")
        end
        if GodSystemCompanionConfig.isEffectUnlocked(companion, nodeId) then
            return gsCompanionPurchaseFailed("Notify_CompanionAlreadyUnlocked", "Already unlocked")
        end
        cost = GodSystemCompanionConfig.getEffectCost(companion, nodeId)
        if not cost then
            return gsCompanionPurchaseFailed("Notify_CompanionEffectOrder", "Unlock the previous attack effect first")
        end
        apply = function() companion.effects[nodeId] = true end
    elseif nodeId == "resonance" then
        if not GodSystemCompanionConfig.canPurchaseResonance(companion) then
            return gsCompanionPurchaseFailed("Notify_CompanionResonanceLocked", "Max all functional upgrades and unlock every attack effect first")
        end
        cost = GodSystemCompanionConfig.getResonanceCost(companion)
        apply = function() companion.resonance = companion.resonance + 1 end
    else
        return false
    end

    local paid = GodSystem.spendCurrency(cost)
    if not paid then
        return gsCompanionPurchaseFailed("Notify_CurrencyNotEnough", "Not enough currency")
    end
    apply()
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    gsAppendHistory(data, {
        kind = "system",
        text = GodSystem.text("History_CompanionUpgrade", "Companion upgrade") .. " " .. nodeId .. " -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins"),
    })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_CompanionUpgradeSuccess", "Companion upgraded"))
    return true
end

function GodSystem.getBankFixedEntry(entryId)
    entryId = tostring(entryId or "")
    local bank = GodSystem.getBank()
    for i = 1, #(bank.fixed or {}) do
        if tostring(bank.fixed[i].id or "") == entryId then
            return bank.fixed[i], i
        end
    end
    return nil
end

function GodSystem.getBankFixedInterest(entry)
    if not entry then return 0 end
    return math.max(0, math.floor((tonumber(entry.principal) or 0) * (tonumber(entry.rate) or 0)))
end

function GodSystem.isBankFixedMature(entry)
    if not entry then return false end
    return gsNowHours() >= (tonumber(entry.matureHour) or 0)
end

function GodSystem.getBankFixedPayout(entry)
    if not entry then return 0, 0, false end
    local principal = math.max(0, math.floor(tonumber(entry.principal) or 0))
    if GodSystem.isBankFixedMature(entry) then
        local interest = GodSystem.getBankFixedInterest(entry)
        return principal + interest, interest, true
    end
    local penalty = math.max(0, math.floor(principal * (GodSystemConfig.BankEarlyWithdrawPenaltyRatio or 0.05)))
    return math.max(0, principal - penalty), -penalty, false
end

function GodSystem.getBankInvestmentProfiles()
    local profiles = GodSystemConfig.BankInvestmentProfiles or {}
    local result = {}
    for i = 1, #BANK_INVESTMENT_IDS do
        local tierId = BANK_INVESTMENT_IDS[i]
        local profile = profiles[tierId] or {}
        local gainChance = math.max(0, math.min(100, math.floor(tonumber(profile.gainChance) or 0)))
        result[#result + 1] = {
            id = tierId,
            gainChance = gainChance,
            lossChance = math.max(0, math.min(100 - gainChance, math.floor(tonumber(profile.lossChance) or 0))),
            gainPercent = math.max(0, tonumber(profile.gainPercent) or 0),
            lossPercent = math.max(0, tonumber(profile.lossPercent) or 0),
        }
    end
    return result
end

function GodSystem.getBankInvestmentProfile(tierId)
    tierId = tostring(tierId or "")
    local profiles = GodSystem.getBankInvestmentProfiles()
    for i = 1, #profiles do
        if profiles[i].id == tierId then
            return profiles[i]
        end
    end
    return nil
end

function GodSystem.getBankInvestmentAccount(tierId)
    local profile = GodSystem.getBankInvestmentProfile(tierId)
    if not profile then
        return nil
    end
    local bank = GodSystem.getBank()
    return bank.investments and bank.investments[profile.id] or nil
end

function GodSystem.getBankInvestmentLabel(tierId)
    local keys = {
        stable = "Bank_InvestmentStable",
        balanced = "Bank_InvestmentBalanced",
        aggressive = "Bank_InvestmentAggressive",
    }
    tierId = tostring(tierId or "")
    local key = keys[tierId]
    if not key then return tierId end
    return GodSystem.text(key, tierId)
end

function GodSystem.getBankInvestmentMinimum()
    return math.max(1, math.floor(tonumber(GodSystemConfig.BankInvestmentMinAmount) or 1))
end

local function gsPrepareInvestmentDeposit(tierId, amount)
    if GodSystem.isFeatureEnabled("EnableBankInvestments") == false then
        GodSystem.notify(GodSystem.text("Notify_BankInvestmentDisabled", "Investment feature is disabled"))
        return nil, nil, nil
    end
    local profile = GodSystem.getBankInvestmentProfile(tierId)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local minimum = GodSystem.getBankInvestmentMinimum()
    if not profile then
        GodSystem.notify(GodSystem.text("Notify_BankInvestmentSelect", "Select an investment account"))
        return nil, nil, nil
    end
    if amount < minimum then
        GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankInvestmentMinimum", "Minimum investment is {1}"), { minimum }))
        return nil, nil, nil
    end
    local bank = GodSystem.getBank()
    local account = bank.investments[profile.id]
    return profile, account, amount
end

local function gsAddBankInvestment(profile, account, amount, source)
    if (account.balance or 0) <= 0 then
        account.balance = 0
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    account.balance = (account.balance or 0) + amount
    local data = GodSystem.getData()
    data.stats.bankInvestmentDeposited = (data.stats.bankInvestmentDeposited or 0) + amount
    local label = GodSystem.getBankInvestmentLabel(profile.id)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankInvestmentCreated", "Invested {2} coins in {1}"), { label, amount, source }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankInvestmentCreated", "Invested {2} coins in {1}"), { label, amount }))
    return true
end

function GodSystem.investBankCurrent(tierId, amount)
    local profile, account, cleanAmount = gsPrepareInvestmentDeposit(tierId, amount)
    if not profile then return false end
    local bank = GodSystem.getBank()
    if (bank.current or 0) < cleanAmount then
        GodSystem.notify(GodSystem.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - cleanAmount
    return gsAddBankInvestment(profile, account, cleanAmount, "current")
end

function GodSystem.investBankCash(tierId, amount)
    local profile, account, cleanAmount = gsPrepareInvestmentDeposit(tierId, amount)
    if not profile then return false end
    if not GodSystem.removeCurrency(cleanAmount) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    return gsAddBankInvestment(profile, account, cleanAmount, "cash")
end

function GodSystem.redeemBankInvestment(tierId, amount)
    local profile = GodSystem.getBankInvestmentProfile(tierId)
    local account = profile and GodSystem.getBankInvestmentAccount(profile.id) or nil
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    if not profile or not account or (account.balance or 0) <= 0 then
        GodSystem.notify(GodSystem.text("Notify_BankInvestmentSelect", "Select an investment account"))
        return false
    end
    if account.redeemUnlocked ~= true then
        GodSystem.notify(GodSystem.text("Notify_BankInvestmentLocked", "Investment can be redeemed after its first settlement"))
        return false
    end
    if amount > (account.balance or 0) then
        GodSystem.notify(GodSystem.text("Notify_BankInvestmentBalanceLow", "Investment balance is not enough"))
        return false
    end
    account.balance = math.max(0, (account.balance or 0) - amount)
    local bank = GodSystem.getBank()
    bank.current = (bank.current or 0) + amount
    local data = GodSystem.getData()
    data.stats.bankInvestmentRedeemed = (data.stats.bankInvestmentRedeemed or 0) + amount
    local label = GodSystem.getBankInvestmentLabel(profile.id)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankInvestmentRedeemed", "Redeemed {2} coins from {1}"), { label, amount }) })
    if account.balance <= 0 then
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankInvestmentRedeemed", "Redeemed {2} coins from {1}"), { label, amount }))
    return true
end

local bankInvestmentRuntimeHour = nil

local function gsSettleBankInvestmentAccount(account, profile, nowHour)
    local before = math.max(0, math.floor(tonumber(account.balance) or 0))
    if before <= 0 then return 0, "flat" end
    local roll = gsRandomIndex(100)
    local delta = 0
    local outcome = "flat"
    if roll <= (profile.gainChance or 0) then
        local percent = math.max(0, tonumber(profile.gainPercent) or 0)
        if percent > 0 then
            delta = math.max(1, math.floor(before * percent / 100))
            account.balance = before + delta
            outcome = "gain"
        end
    elseif roll > 100 - (profile.lossChance or 0) then
        local percent = math.max(0, tonumber(profile.lossPercent) or 0)
        if percent > 0 then
            local loss = math.max(1, math.floor(before * percent / 100))
            loss = math.min(before, loss)
            delta = -loss
            account.balance = before - loss
            outcome = "loss"
        end
    end
    account.redeemUnlocked = true
    account.settlementCount = (account.settlementCount or 0) + 1
    account.lastDelta = delta
    account.lastOutcome = outcome
    account.lastSettledHour = nowHour
    return delta, outcome
end

function GodSystem.updateBankInvestments()
    local nowHour = gsNowHours()
    if bankInvestmentRuntimeHour == nil then
        bankInvestmentRuntimeHour = nowHour
        return false
    end
    local elapsed = nowHour - bankInvestmentRuntimeHour
    bankInvestmentRuntimeHour = nowHour
    if elapsed <= 0 then
        return false
    end
    if GodSystem.isFeatureEnabled("EnableBankInvestments") == false then
        return false
    end
    local bank = GodSystem.getBank()
    local profiles = GodSystem.getBankInvestmentProfiles()
    local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
    local settledCount = 0
    local totalDelta = 0
    local data = GodSystem.getData()
    for i = 1, #profiles do
        local profile = profiles[i]
        local account = bank.investments[profile.id]
        if account and (account.balance or 0) > 0 then
            account.onlineHours = math.max(0, tonumber(account.onlineHours) or 0) + elapsed
            while account.onlineHours >= settlementHours and (account.balance or 0) > 0 do
                account.onlineHours = account.onlineHours - settlementHours
                local before = account.balance
                local delta = gsSettleBankInvestmentAccount(account, profile, nowHour)
                totalDelta = totalDelta + delta
                settledCount = settledCount + 1
                if delta > 0 then
                    data.stats.bankInvestmentProfit = (data.stats.bankInvestmentProfit or 0) + delta
                elseif delta < 0 then
                    data.stats.bankInvestmentLoss = (data.stats.bankInvestmentLoss or 0) + math.abs(delta)
                end
                local label = GodSystem.getBankInvestmentLabel(profile.id)
                gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankInvestmentSettled", "Investment settled: {1} {2} -> {4} ({3})"), { label, before, delta, account.balance }) })
            end
        end
    end
    if settledCount <= 0 then
        return false
    end
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankInvestmentSettled", "Investment settlement: {1} account(s), total change {2}"), { settledCount, totalDelta }))
    return true
end

function GodSystem.getBankSummary()
    local bank = GodSystem.getBank()
    local fixedPrincipal = 0
    local fixedMatureValue = 0
    local investmentTotal = 0
    for i = 1, #(bank.fixed or {}) do
        local entry = bank.fixed[i]
        fixedPrincipal = fixedPrincipal + math.max(0, math.floor(tonumber(entry.principal) or 0))
        fixedMatureValue = fixedMatureValue + math.max(0, math.floor((tonumber(entry.principal) or 0) + GodSystem.getBankFixedInterest(entry)))
    end
    for _, account in pairs(bank.investments or {}) do
        investmentTotal = investmentTotal + math.max(0, math.floor(tonumber(account.balance) or 0))
    end
    local deathPenalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    return {
        cash = GodSystem.getCurrencyTotal(),
        current = bank.current or 0,
        fixedPrincipal = fixedPrincipal,
        fixedMatureValue = fixedMatureValue,
        fixedCount = #(bank.fixed or {}),
        investmentTotal = investmentTotal,
        deathPenalty = deathPenalty,
    }
end

function GodSystem.getBankLoanPlans()
    local plans = {
        {
            id = "single",
            kind = "single",
            periods = 1,
            dueHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanSingleDueHours) or 72)),
            totalInterestRate = tonumber(GodSystemConfig.BankLoanSingleInterestRate) or 0.05,
        },
    }
    local periodHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanPeriodHours) or 72))
    for i = 1, #(GodSystemConfig.BankLoanInstallmentPlans or {}) do
        local row = GodSystemConfig.BankLoanInstallmentPlans[i]
        local periods = math.max(1, math.floor(tonumber(row.periods) or 1))
        plans[#plans + 1] = {
            id = tostring(row.id or ("i" .. tostring(periods))),
            kind = "installment",
            periods = periods,
            dueHours = periodHours,
            totalInterestRate = tonumber(row.totalInterestRate) or 0,
        }
    end
    return plans
end

local function gsGetBankLoanPlan(planId)
    planId = tostring(planId or "single")
    local plans = GodSystem.getBankLoanPlans()
    for i = 1, #plans do
        if tostring(plans[i].id or "") == planId then
            return plans[i]
        end
    end
    return nil
end

local function gsBankLoanUnpaidPrincipal(loan)
    local total = 0
    if not loan or type(loan.schedule) ~= "table" then
        return 0
    end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local partTotal = math.max(0, math.floor((tonumber(bill.principalPart) or 0) + (tonumber(bill.interestPart) or 0)))
        local paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        local principal = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
        if partTotal > 0 and paid < partTotal then
            local principalPaid = math.min(principal, paid)
            total = total + math.max(0, principal - principalPaid)
        end
    end
    return total
end

local function gsBankLoanAmounts(loan, now)
    now = tonumber(now) or gsNowHours()
    local result = {
        due = 0,
        futurePrincipal = 0,
        futureInterest = 0,
        unpaidPrincipal = 0,
        unpaidInterest = 0,
        unpaidTotal = 0,
        overdueStartHour = nil,
        nextDueHour = nil,
    }
    if not loan or type(loan.schedule) ~= "table" then
        return result
    end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local principal = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
        local interest = math.max(0, math.floor(tonumber(bill.interestPart) or 0))
        local total = principal + interest
        local paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        if total > paid then
            local remaining = total - paid
            local principalPaid = math.min(principal, paid)
            local interestPaid = math.max(0, paid - principal)
            local principalLeft = math.max(0, principal - principalPaid)
            local interestLeft = math.max(0, interest - interestPaid)
            result.unpaidPrincipal = result.unpaidPrincipal + principalLeft
            result.unpaidInterest = result.unpaidInterest + interestLeft
            result.unpaidTotal = result.unpaidTotal + remaining
            local dueHour = tonumber(bill.dueHour) or now
            if now >= dueHour then
                result.due = result.due + remaining
                if not result.overdueStartHour or dueHour < result.overdueStartHour then
                    result.overdueStartHour = dueHour
                end
            else
                result.futurePrincipal = result.futurePrincipal + principalLeft
                result.futureInterest = result.futureInterest + interestLeft
                if not result.nextDueHour or dueHour < result.nextDueHour then
                    result.nextDueHour = dueHour
                end
            end
        end
    end
    return result
end

local function gsRefreshBankLoanStatus(loan, now)
    if not loan then
        return gsBankLoanAmounts(nil, now)
    end
    local amounts = gsBankLoanAmounts(loan, now)
    loan.overdueStartHour = amounts.overdueStartHour
    return amounts
end

local function gsBankLoanOverduePenalty(loan, now, amounts)
    amounts = amounts or gsRefreshBankLoanStatus(loan, now)
    if not loan or not amounts.overdueStartHour then
        return 0
    end
    now = tonumber(now) or gsNowHours()
    local overdueDays = math.max(0, math.floor((now - amounts.overdueStartHour) / 24))
    if overdueDays <= 0 then
        return 0
    end
    local principal = math.max(0, math.floor(tonumber(loan.principal) or 0))
    local dailyRate = tonumber(GodSystemConfig.BankLoanOverduePenaltyDailyRate) or 0.05
    local maxRate = tonumber(GodSystemConfig.BankLoanOverduePenaltyMaxRate) or 0.5
    return math.max(0, math.floor(math.min(principal * maxRate, principal * dailyRate * overdueDays)))
end

local function gsBankLoanCredit(data, bank)
    data = data or GodSystem.getData()
    bank = bank or GodSystem.getBank()
    local base = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanBaseCredit) or 2000))
    local step = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanCreditSpendStep) or 100))
    local perStep = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanCreditPerStep) or 5))
    local spent = math.max(0, math.floor(tonumber(data.stats and data.stats.spentPoints) or 0))
    local offset = math.max(0, math.floor(tonumber(bank.loanCreditSpentOffset) or 0))
    local growth = math.floor(math.max(0, spent - offset) / step) * perStep
    local total = base + growth
    local used = gsBankLoanUnpaidPrincipal(bank.loan)
    return total, math.max(0, total - used), growth, used
end

local function gsCreateBankLoanSchedule(plan, amount, now)
    local schedule = {}
    local periods = math.max(1, math.floor(tonumber(plan.periods) or 1))
    local totalInterest = math.max(0, math.floor(amount * (tonumber(plan.totalInterestRate) or 0)))
    local principalLeft = amount
    local interestLeft = totalInterest
    for i = 1, periods do
        local principalPart = (i == periods) and principalLeft or math.floor(amount / periods)
        local interestPart = (i == periods) and interestLeft or math.floor(totalInterest / periods)
        principalLeft = principalLeft - principalPart
        interestLeft = interestLeft - interestPart
        schedule[#schedule + 1] = {
            index = i,
            dueHour = now + math.max(1, math.floor(tonumber(plan.dueHours) or 72)) * i,
            principalPart = principalPart,
            interestPart = interestPart,
            paid = 0,
        }
    end
    return schedule, totalInterest
end

local function gsApplyBankLoanPayment(loan, amount, now, includeFuture)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local paid = 0
    if not loan or amount <= 0 then
        return 0
    end
    now = tonumber(now) or gsNowHours()
    for i = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[i]
        local total = math.max(0, math.floor((tonumber(bill.principalPart) or 0) + (tonumber(bill.interestPart) or 0)))
        local billPaid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        if total > billPaid and (includeFuture or now >= (tonumber(bill.dueHour) or now)) then
            local add = math.min(amount, total - billPaid)
            bill.paid = billPaid + add
            loan.paid = math.max(0, math.floor(tonumber(loan.paid) or 0)) + add
            amount = amount - add
            paid = paid + add
            if amount <= 0 then
                break
            end
        end
    end
    return paid
end

function GodSystem.spawnBankLoanDebtZombies(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 or not addZombiesInOutfit then
        return 0
    end
    local player = gsPlayer()
    if not player or not player.getX then
        return 0
    end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local minDist = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanZombieMinDistance) or 20))
    local maxDist = math.max(minDist, math.floor(tonumber(GodSystemConfig.BankLoanZombieMaxDistance) or 45))
    local spawned = 0
    local tries = 0
    while spawned < count and tries < count * 8 do
        tries = tries + 1
        local dist = minDist + gsRandomIndex(math.max(1, maxDist - minDist + 1)) - 1
        local dx = gsRandomIndex(dist * 2 + 1) - dist - 1
        local dySign = gsRandomIndex(2) == 1 and -1 or 1
        local dy = dySign * math.max(minDist, dist - math.abs(dx))
        local x = math.floor(px + dx)
        local y = math.floor(py + dy)
        local batch = math.min(10, count - spawned)
        local ok = pcall(addZombiesInOutfit, x, y, pz, batch, nil, nil)
        if ok then
            spawned = spawned + batch
        end
    end
    return spawned
end

function GodSystem.applyBankLoanBankruptcy(bank, loan, debt)
    local data = GodSystem.getData()
    bank = bank or GodSystem.getBank()
    loan = loan or bank.loan
    if not loan then
        return false, 0
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    debt = math.max(0, math.floor(tonumber(debt) or (amounts.unpaidTotal + gsBankLoanOverduePenalty(loan, now, amounts))))
    local perZombie = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanZombieDebtPerZombie) or 50))
    local maxZombies = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanZombieMaxCount) or 100))
    local zombieCount = math.min(maxZombies, math.max(1, math.floor(debt / perZombie)))
    local cash = math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0))
    if cash > 0 then
        GodSystem.removeCurrency(cash)
    end
    bank.loan = nil
    bank.current = 0
    bank.loanFrozenUntilHour = now + math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanFreezeHours) or 168))
    bank.loanCreditSpentOffset = math.max(0, math.floor(tonumber(data.stats and data.stats.spentPoints) or 0))
    bank.loanBankruptcyCount = math.max(0, math.floor(tonumber(bank.loanBankruptcyCount) or 0)) + 1
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + debt
    local spawned = GodSystem.spawnBankLoanDebtZombies(zombieCount)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankLoanBankruptcy", "Loan bankruptcy cleared debt {1}, spawned debt zombies {2}"), { debt, spawned }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankLoanBankruptcy", "Loan bankruptcy! Debt cleared, current account and carried cash removed, debt zombies spawned: {1}"), { spawned }))
    return true, spawned
end

function GodSystem.getBankLoanSummary()
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local now = gsNowHours()
    local loan = bank.loan
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local creditTotal, creditAvailable, creditGrowth, creditUsed = gsBankLoanCredit(data, bank)
    local freezeLeft = math.max(0, math.ceil((tonumber(bank.loanFrozenUntilHour) or 0) - now))
    local graceHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanBankruptcyGraceHours) or 240))
    if loan and not (GodSystemNetwork and GodSystemNetwork.isMultiplayer == true) and amounts.overdueStartHour and now - amounts.overdueStartHour >= graceHours then
        GodSystem.applyBankLoanBankruptcy(bank, loan, amounts.unpaidTotal + penalty)
        return GodSystem.getBankLoanSummary()
    end
    return {
        creditTotal = creditTotal,
        creditAvailable = creditAvailable,
        creditGrowth = creditGrowth,
        creditUsed = creditUsed,
        loan = bank.loan,
        dueNow = amounts.due + penalty,
        dueBase = amounts.due,
        overduePenalty = penalty,
        payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5),
        unpaidTotal = amounts.unpaidTotal + penalty,
        nextDueHour = amounts.nextDueHour,
        overdueStartHour = amounts.overdueStartHour,
        freezeLeftHours = freezeLeft,
        frozen = freezeLeft > 0,
        bankruptcyInHours = amounts.overdueStartHour and math.max(0, math.ceil(graceHours - (now - amounts.overdueStartHour))) or nil,
    }
end

function GodSystem.borrowBankLoan(planId, amount)
    if GodSystem.isFeatureEnabled("EnableBankLoan") == false then
        GodSystem.notify(GodSystem.text("Notify_BankLoanFrozen", "Loan feature is disabled"))
        return false
    end
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    local plan = gsGetBankLoanPlan(planId)
    if not plan then
        GodSystem.notify(GodSystem.text("Notify_BankSelectTerm", "Select a fixed term first"))
        return false
    end
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local summary = GodSystem.getBankLoanSummary()
    if bank.loan then
        GodSystem.notify(GodSystem.text("Notify_BankLoanActive", "There is already an active loan"))
        return false
    end
    if summary.frozen then
        GodSystem.notify(GodSystem.text("Notify_BankLoanFrozen", "Loan feature is frozen"))
        return false
    end
    if amount > (summary.creditAvailable or 0) then
        GodSystem.notify(GodSystem.text("Notify_BankLoanCreditLow", "Available credit is not enough"))
        return false
    end
    local now = gsNowHours()
    local schedule, totalInterest = gsCreateBankLoanSchedule(plan, amount, now)
    local id = "L" .. tostring(bank.nextLoanId or 1)
    bank.nextLoanId = (bank.nextLoanId or 1) + 1
    bank.loan = {
        id = id,
        kind = plan.kind,
        planId = plan.id,
        principal = amount,
        createdHour = now,
        totalInterest = totalInterest,
        totalDue = amount + totalInterest,
        paid = 0,
        schedule = schedule,
    }
    bank.current = (bank.current or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankLoanBorrowed", "Bank loan received {1} coins"), { amount }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankLoanBorrowed", "Loan paid to current account: {1}"), { amount }))
    return true
end

function GodSystem.repayBankLoanDue()
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local loan = bank.loan
    if not loan then
        GodSystem.notify(GodSystem.text("Notify_BankLoanNoActive", "No active loan"))
        return false
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local due = amounts.due + penalty
    if due <= 0 then
        GodSystem.notify(GodSystem.text("Notify_BankLoanNoDue", "No due bill now"))
        return false
    end
    if (bank.current or 0) < due then
        GodSystem.notify(GodSystem.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - due
    gsApplyBankLoanPayment(loan, amounts.due, now, false)
    if penalty > 0 then
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    end
    if (loan.paid or 0) >= (loan.totalDue or 0) then
        bank.loan = nil
    else
        gsRefreshBankLoanStatus(loan, now)
    end
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankLoanRepaid", "Loan repaid {1} coins"), { due }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankLoanRepaid", "Loan repaid: {1}"), { due }))
    return true
end

function GodSystem.payoffBankLoan()
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local loan = bank.loan
    if not loan then
        GodSystem.notify(GodSystem.text("Notify_BankLoanNoActive", "No active loan"))
        return false
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5)
    payoff = math.max(0, math.floor(payoff))
    if payoff <= 0 then
        bank.loan = nil
        GodSystem.save()
        return true
    end
    if (bank.current or 0) < payoff then
        GodSystem.notify(GodSystem.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - payoff
    bank.loan = nil
    if penalty > 0 then
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    end
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankLoanPayoff", "Loan paid off early {1} coins"), { payoff }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankLoanPayoff", "Loan paid off early: {1}"), { payoff }))
    return true
end

function GodSystem.depositBankCurrent(amount)
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    if not GodSystem.removeCurrency(amount) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    bank.current = (bank.current or 0) + amount
    data.stats.bankDeposited = (data.stats.bankDeposited or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = GodSystem.text("History_BankDeposit", "Bank deposit ") .. tostring(amount) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_BankDeposit", "Deposited to current account: ") .. tostring(amount))
    return true
end

function GodSystem.depositAllCashToBankCurrent(silent)
    local amount = math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0))
    if amount <= 0 then
        if not silent then
            GodSystem.notify(GodSystem.text("Notify_BankDepositAllEmpty", "No carried system currency to deposit"))
        end
        return false
    end
    if not GodSystem.removeCurrency(amount) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    bank.current = (bank.current or 0) + amount
    data.stats.bankDeposited = (data.stats.bankDeposited or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystem.text("History_BankDepositAll", "Deposited all carried cash into current account: {1} coins"), { amount }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_BankDepositAll", "Deposited all carried cash into current account: {1}"), { amount }))
    return true
end

function GodSystem.toggleBankAutoDeposit()
    local bank = GodSystem.getBank()
    bank.autoDepositEnabled = bank.autoDepositEnabled ~= true
    bank.lastAutoDepositHour = gsNowHours()
    GodSystem.save()
    GodSystem.notify(GodSystem.text(bank.autoDepositEnabled and "Notify_AutoDepositEnabled" or "Notify_AutoDepositDisabled", bank.autoDepositEnabled and "Auto deposit enabled" or "Auto deposit disabled"))
    return bank.autoDepositEnabled
end

function GodSystem.processBankAutoDeposit()
    local bank = GodSystem.getBank()
    if bank.autoDepositEnabled ~= true then return false end
    local nowHour = gsNowHours()
    if nowHour < (bank.lastAutoDepositHour or nowHour) then
        bank.lastAutoDepositHour = nowHour
    end
    if nowHour - (bank.lastAutoDepositHour or nowHour) < 1 then
        return false
    end
    bank.lastAutoDepositHour = nowHour
    if math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0)) <= 0 then
        GodSystem.save()
        return false
    end
    return GodSystem.depositAllCashToBankCurrent(true)
end

function GodSystem.withdrawBankCurrent(amount)
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    if (bank.current or 0) < amount then
        GodSystem.notify(GodSystem.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    if not GodSystem.giveCurrency(amount) then
        GodSystem.notify(GodSystem.text("Notify_BankWithdrawFailed", "Withdrawal failed"))
        return false
    end
    bank.current = (bank.current or 0) - amount
    data.stats.bankWithdrawn = (data.stats.bankWithdrawn or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = GodSystem.text("History_BankWithdraw", "Bank withdraw ") .. tostring(amount) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_BankWithdraw", "Withdrawn from current account: ") .. tostring(amount))
    return true
end

function GodSystem.withdrawBankFixed(entryId)
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local entry, index = GodSystem.getBankFixedEntry(entryId)
    if not entry or not index then
        GodSystem.notify(GodSystem.text("Notify_BankSelectFixed", "Select a fixed deposit first"))
        return false
    end
    local payout, interestOrPenalty, mature = GodSystem.getBankFixedPayout(entry)
    bank.current = (bank.current or 0) + payout
    table.remove(bank.fixed, index)
    if mature then
        data.stats.bankInterest = (data.stats.bankInterest or 0) + math.max(0, interestOrPenalty)
        gsAppendHistory(data, { kind = "bank", text = GodSystem.text("History_BankFixedWithdraw", "Fixed deposit matured ") .. "+" .. tostring(payout) .. GodSystem.text("Unit_Coin", " coins") })
        GodSystem.notify(GodSystem.text("Notify_BankFixedWithdraw", "Fixed deposit paid to current account: ") .. tostring(payout))
    else
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + math.abs(math.min(0, interestOrPenalty))
        gsAppendHistory(data, { kind = "bank", text = GodSystem.text("History_BankFixedEarlyWithdraw", "Fixed deposit withdrawn early ") .. "+" .. tostring(payout) .. GodSystem.text("Unit_Coin", " coins") })
        GodSystem.notify(GodSystem.text("Notify_BankFixedEarlyWithdraw", "Early withdrawal paid to current account: ") .. tostring(payout))
    end
    GodSystem.save()
    return true
end

function GodSystem.performBankAction(action, amount, termId, entryId)
    if GodSystem.isFeatureEnabled("EnableBank") == false then
        GodSystem.notify("Bank disabled")
        return false
    end
    if action == "deposit" then
        return GodSystem.depositBankCurrent(amount)
    elseif action == "depositAllCash" then
        return GodSystem.depositAllCashToBankCurrent()
    elseif action == "toggleAutoDeposit" then
        return GodSystem.toggleBankAutoDeposit()
    elseif action == "withdraw" then
        return GodSystem.withdrawBankCurrent(amount)
    elseif action == "withdrawFixed" then
        return GodSystem.withdrawBankFixed(entryId)
    elseif action == "investFromCurrent" then
        return GodSystem.investBankCurrent(termId, amount)
    elseif action == "investFromCash" then
        return GodSystem.investBankCash(termId, amount)
    elseif action == "redeemInvestment" then
        return GodSystem.redeemBankInvestment(termId, amount)
    elseif action == "borrowLoan" then
        return GodSystem.borrowBankLoan(termId, amount)
    elseif action == "repayLoanDue" then
        return GodSystem.repayBankLoanDue()
    elseif action == "payoffLoan" then
        return GodSystem.payoffBankLoan()
    end
    GodSystem.notify(GodSystem.text("Notify_BankUnknownAction", "Unknown bank operation"))
    return false
end

function GodSystem.applyBankDeathPenalty()
    local data = GodSystem.getData()
    local bank = GodSystem.getBank()
    local now = gsNowHours()
    if now - (bank.lastDeathPenaltyHour or -999) < 0.1 then
        return false
    end
    bank.lastDeathPenaltyHour = now
    local penalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    if penalty <= 0 then
        GodSystem.save()
        return false
    end
    bank.current = math.max(0, (bank.current or 0) - penalty)
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    gsAppendHistory(data, { kind = "bank", text = GodSystem.text("History_BankDeathPenalty", "Death penalty deducted from current account ") .. tostring(penalty) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_BankDeathPenalty", "Death penalty deducted from current account: ") .. tostring(penalty))
    return true
end

function GodSystem.payTaskFailurePenalty(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return 0, 0, 0
    end
    local bank = GodSystem.getBank()
    local fromBank = math.min(bank.current or 0, amount)
    if fromBank > 0 then
        bank.current = math.max(0, (bank.current or 0) - fromBank)
    end
    local remaining = amount - fromBank
    local fromCash = 0
    if remaining > 0 then
        local cash = math.max(0, math.floor(tonumber(GodSystem.getCurrencyTotal()) or 0))
        fromCash = math.min(cash, remaining)
        if fromCash > 0 and not GodSystem.removeCurrency(fromCash) then
            fromCash = 0
        end
    end
    local paid = fromBank + fromCash
    local data = GodSystem.getData()
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + fromBank
    return paid, fromBank, fromCash
end

function GodSystem.ensureRecycleDailyLimit()
    local data = GodSystem.getData()
    local day = gsCurrentDay()
    if data.recycleLimitDay ~= day then
        data.recycleLimitDay = day
        data.recycleLimitUsed = 0
        GodSystem.save()
    end
    return data
end

function GodSystem.getRecycleDailyRemaining()
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then
        return 999999
    end
    local data = GodSystem.ensureRecycleDailyLimit()
    return math.max(0, cap - (data.recycleLimitUsed or 0))
end

function GodSystem.isRecycleUnlockMode()
    local data = GodSystem.getData()
    if data.recycleUnlockMode == nil then
        data.recycleUnlockMode = true
    end
    return data.recycleUnlockMode == true
end

function GodSystem.toggleRecycleUnlockMode()
    local data = GodSystem.getData()
    data.recycleUnlockMode = not GodSystem.isRecycleUnlockMode()
    GodSystem.save()
    if data.recycleUnlockMode then
        GodSystem.notify(GodSystem.text("Notify_RecycleModeUnlock", "Recycle mode: unlock shop"))
    else
        GodSystem.notify(GodSystem.text("Notify_RecycleModeOnly", "Recycle mode: recycle only"))
    end
    return data.recycleUnlockMode
end

function GodSystem.isWaistRecycleUnlockMode()
    local data = GodSystem.getData()
    data.waistRecycleUnlockMode = data.waistRecycleUnlockMode == true
    return data.waistRecycleUnlockMode == true
end

function GodSystem.toggleWaistRecycleUnlockMode()
    local data = GodSystem.getData()
    data.waistRecycleUnlockMode = not GodSystem.isWaistRecycleUnlockMode()
    GodSystem.save()
    if data.waistRecycleUnlockMode then
        GodSystem.notify(GodSystem.text("Notify_WaistRecycleModeUnlock", "Waist mode: sell and list"))
    else
        GodSystem.notify(GodSystem.text("Notify_WaistRecycleModeOnly", "Waist mode: sell only"))
    end
    return data.waistRecycleUnlockMode
end

function GodSystem.getDailyTaskRefreshCountdown()
    local now = gsNowHours()
    local nextDay = (math.floor(now / 24) + 1) * 24
    local remain = math.max(0, nextDay - now)
    local hours = math.floor(remain)
    local minutes = math.floor((remain - hours) * 60)
    return hours, minutes, remain
end

function GodSystem.getDailyTaskRefreshText()
    local hours, minutes = GodSystem.getDailyTaskRefreshCountdown()
    return string.format("%02d:%02d", hours, minutes)
end

function GodSystem.previewRecycleDailyPayout(rawValue)
    rawValue = math.max(0, math.floor(tonumber(rawValue) or 0))
    if rawValue <= 0 then
        return 0, false
    end
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then
        return rawValue, false
    end
    local remaining = GodSystem.getRecycleDailyRemaining()
    if remaining > 0 then
        local payout = math.min(rawValue, remaining)
        return payout, payout < rawValue
    end
    return math.max(1, GodSystemConfig.DiminishedRecyclePayout or 1), true
end

function GodSystem.applyRecycleDailyPayout(rawValue)
    local payout, diminished = GodSystem.previewRecycleDailyPayout(rawValue)
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap > 0 and payout > 0 then
        local data = GodSystem.ensureRecycleDailyLimit()
        local remaining = math.max(0, cap - (data.recycleLimitUsed or 0))
        if remaining > 0 then
            data.recycleLimitUsed = math.min(cap, (data.recycleLimitUsed or 0) + math.min(payout, remaining))
        end
    end
    return payout, diminished
end

function GodSystem.applyAutoRecyclerDailyPayout(rawValue, diminishedUnits)
    rawValue = math.max(0, math.floor(tonumber(rawValue) or 0))
    diminishedUnits = math.max(1, math.floor(tonumber(diminishedUnits) or 1))
    if rawValue <= 0 then
        return 0, false
    end

    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then
        return rawValue, false
    end

    local data = GodSystem.ensureRecycleDailyLimit()
    local remaining = math.max(0, cap - (data.recycleLimitUsed or 0))
    if remaining >= rawValue then
        data.recycleLimitUsed = math.min(cap, (data.recycleLimitUsed or 0) + rawValue)
        return rawValue, false
    end

    local diminishedValue = math.max(1, GodSystemConfig.DiminishedRecyclePayout or 1)
    if remaining <= 0 then
        return diminishedUnits * diminishedValue, true
    end

    data.recycleLimitUsed = cap
    local coveredUnits = math.floor((remaining / rawValue) * diminishedUnits)
    local overflowUnits = math.max(1, diminishedUnits - coveredUnits)
    return remaining + (overflowUnits * diminishedValue), true
end

function GodSystem.itemExists(fullType)
    if not fullType then
        return false
    end
    if getScriptManager and getScriptManager() then
        return getScriptManager():FindItem(fullType) ~= nil
    end
    return true
end

function GodSystem.getItemDisplayName(fullType, fallback)
    if getText and fullType then
        local key = "ItemName_" .. tostring(fullType)
        local value = getText(key)
        if value and value ~= key then
            return value
        end
    end
    if GodSystemFallbackItems and GodSystemFallbackItems[fullType] then
        return GodSystemFallbackItems[fullType]
    end
    if getScriptManager and getScriptManager() then
        local scriptItem = getScriptManager():FindItem(fullType)
        if scriptItem and scriptItem:getDisplayName() then
            return scriptItem:getDisplayName()
        end
    end
    return fallback or fullType
end

function GodSystem.shopItemIsAvailable(shopItem)
    if not shopItem then
        return false, GodSystem.text("Error_ShopItemMissing", "Shop item missing")
    end
    local items = shopItem.items or {}
    if #items == 0 then
        return true, "", {}, {}
    end
    local availableItems = {}
    local missingItems = {}
    for i = 1, #items do
        if not GodSystem.itemExists(items[i].fullType) then
            table.insert(missingItems, tostring(items[i].fullType))
        else
            table.insert(availableItems, { fullType = items[i].fullType, worldSprite = items[i].worldSprite, count = items[i].count or 1 })
        end
    end
    if #availableItems == 0 then
        return false, GodSystem.text("Error_AllItemsMissing", "All items missing"), availableItems, missingItems
    end
    if #missingItems > 0 then
        return true, GodSystem.text("Error_MissingSome", "Some missing: ") .. tostring(#missingItems), availableItems, missingItems
    end
    return true, "", availableItems, missingItems
end

function GodSystem.giveItem(fullType, count)
    local player = gsPlayer()
    if not player or not fullType then
        return false, {}
    end
    if not GodSystem.itemExists(fullType) then
        GodSystem.notify(GodSystem.text("Error_ItemNotFound", "Item not found: ") .. tostring(fullType))
        return false, {}
    end

    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if not okInventory or not inventory or not inventory.AddItem then
        GodSystem.notify(GodSystem.text("Error_ItemGiveFailed", "Item grant failed: ") .. tostring(fullType))
        return false, {}
    end
    count = math.max(1, math.floor(count or 1))
    local addedItems = {}
    local failed = false
    for _ = 1, count do
        local okAdd, item = pcall(function() return inventory:AddItem(fullType) end)
        if okAdd and item then
            table.insert(addedItems, item)
        else
            failed = true
            break
        end
    end
    if failed then
        for i = 1, #addedItems do
            pcall(function() inventory:Remove(addedItems[i]) end)
        end
        GodSystem.notify(GodSystem.text("Error_ItemGiveFailed", "Item grant failed: ") .. tostring(fullType))
        return false, {}
    end
    return #addedItems > 0, addedItems
end

function GodSystem.giveItems(items, silentMissing)
    if not items then
        return 0, {}, {}
    end
    local given = 0
    local missing = {}
    local addedItems = {}
    local player = gsPlayer()
    local inventory = player and player.getInventory and player:getInventory() or nil
    for i = 1, #items do
        if GodSystem.itemExists(items[i].fullType) then
            local ok, added = nil, nil
            if items[i].worldSprite then
                ok, added = GodSystemShopVariants.addItems(inventory, items[i].fullType, items[i].worldSprite, items[i].count or 1)
            else
                ok, added = GodSystem.giveItem(items[i].fullType, items[i].count or 1)
            end
            if ok then
                for j = 1, #(added or {}) do
                    table.insert(addedItems, added[j])
                end
                given = given + #(added or {})
            end
        else
            table.insert(missing, tostring(items[i].fullType))
        end
    end
    if #missing > 0 and not silentMissing then
        GodSystem.notify(GodSystem.text("Error_MissingSome", "Some missing: ") .. tostring(#missing))
    end
    return given, missing, addedItems
end

function GodSystem.removeAddedItems(addedItems)
    local player = gsPlayer()
    if not player or not addedItems then
        return
    end
    for i = 1, #addedItems do
        local item = addedItems[i]
        if item then
            local container = nil
            if item.getContainer then
                local ok, found = pcall(function() return item:getContainer() end)
                if ok then
                    container = found
                end
            end
            if container and container.Remove then
                pcall(function() container:Remove(item) end)
            else
                pcall(function() player:getInventory():Remove(item) end)
            end
        end
    end
end

local function gsSafeGetText(key)
    if not key or not getText then
        return nil
    end
    local ok, value = pcall(function() return getText(key) end)
    if ok and value and tostring(value) ~= tostring(key) then
        return tostring(value)
    end
    return nil
end

local function gsSafeCall(object, methodName, fallback, ...)
    if not object or not methodName then
        return fallback
    end
    local method = object[methodName]
    if type(method) ~= "function" then
        return fallback
    end
    local args = { ... }
    local unpackFn = unpack or (table and table.unpack)
    local ok, value = pcall(function()
        if unpackFn then
            return method(object, unpackFn(args))
        end
        return method(object)
    end)
    if ok and value ~= nil then
        return value
    elseif ok then
        return fallback
    end
    return fallback
end

local function gsArrayFromList(list)
    local result = {}
    if not list then
        return result
    end

    if type(list) == "table" then
        for _, value in pairs(list) do
            table.insert(result, value)
        end
        return result
    end

    if not list.size or not list.get then
        return result
    end

    local size = tonumber(list:size()) or 0
    if not size then
        return result
    end
    for i = 0, size - 1 do
        local value = list:get(i)
        if value ~= nil then
            table.insert(result, value)
        end
    end
    return result
end

local function gsArrayFromMapValues(map)
    local result = {}
    if not map then
        return result
    end
    if type(map) == "table" then
        for _, value in pairs(map) do
            table.insert(result, value)
        end
        return result
    end
    if map.values then
        local values = map:values()
        if values then
            local list = gsArrayFromList(values)
            for i = 1, #list do
                table.insert(result, list[i])
            end
        end
    end
    return result
end

local MEDICAL_SERVICE_ORDER = {
    "checkInfection",
    "healInjuries",
    "cureInfection",
}

local function gsMedicalPlayer(targetPlayer)
    if targetPlayer then
        return targetPlayer
    end
    if getPlayer then
        return getPlayer()
    end
    return nil
end

local function gsMedicalBody(targetPlayer)
    local p = gsMedicalPlayer(targetPlayer)
    if not p then
        return nil
    end
    return gsSafeCall(p, "getBodyDamage", nil)
end

local function gsMedicalBool(object, methods)
    for i = 1, #(methods or {}) do
        local value = gsSafeCall(object, methods[i], nil)
        if value == true then
            return true
        elseif value == false then
            return false
        end
    end
    return false
end

local function gsMedicalNumber(object, methods, fallback)
    for i = 1, #(methods or {}) do
        local value = tonumber(gsSafeCall(object, methods[i], nil))
        if value ~= nil then
            return value
        end
    end
    return fallback
end

local function gsMedicalBodyParts(body)
    local parts = gsSafeCall(body, "getBodyParts", nil)
    return gsArrayFromList(parts)
end

local function gsMedicalCaptureInfection(body)
    return {
        infected = gsMedicalBool(body, { "IsInfected", "isInfected" }),
        fakeInfected = gsMedicalBool(body, { "IsFakeInfected", "isFakeInfected" }),
        infectionTime = gsMedicalNumber(body, { "getInfectionTime" }, nil),
        mortalityDuration = gsMedicalNumber(body, { "getInfectionMortalityDuration" }, nil),
        infectionLevel = gsMedicalNumber(body, { "getInfectionLevel" }, nil),
    }
end

local function gsMedicalRestoreInfection(body, snapshot)
    if not body or not snapshot or snapshot.infected ~= true then
        return
    end
    gsSafeCall(body, "setInfected", nil, true)
    gsSafeCall(body, "setIsFakeInfected", nil, snapshot.fakeInfected == true)
    if snapshot.infectionTime ~= nil then
        gsSafeCall(body, "setInfectionTime", nil, snapshot.infectionTime)
    end
    if snapshot.mortalityDuration ~= nil then
        gsSafeCall(body, "setInfectionMortalityDuration", nil, snapshot.mortalityDuration)
    end
    if snapshot.infectionLevel ~= nil then
        gsSafeCall(body, "setInfectionLevel", nil, snapshot.infectionLevel)
    end
end

local function gsMedicalIsInfected(body)
    if not body then
        return false
    end
    if gsMedicalBool(body, { "IsInfected", "isInfected" }) then
        return true
    end
    local level = gsMedicalNumber(body, { "getInfectionLevel" }, 0) or 0
    if level > 0 then
        return true
    end
    local time = gsMedicalNumber(body, { "getInfectionTime" }, -1) or -1
    return time > 0
end

local function gsMedicalHasInjury(body)
    if not body then
        return false
    end
    local overall = gsMedicalNumber(body, { "getOverallBodyHealth", "getHealth" }, nil)
    if overall and overall < 99.5 then
        return true
    end

    local boolMethods = {
        "HasInjury",
        "hasInjury",
        "isBleeding",
        "IsBleeding",
        "bleeding",
        "isDeepWounded",
        "deepWounded",
        "haveBullet",
        "haveGlass",
        "isBurnt",
        "stitched",
    }
    local timeMethods = {
        "getBleedingTime",
        "getDeepWoundTime",
        "getScratchTime",
        "getCutTime",
        "getBiteTime",
        "getBurnTime",
        "getFractureTime",
        "getWoundInfectionLevel",
        "getAdditionalPain",
    }
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        local part = parts[i]
        local health = gsMedicalNumber(part, { "getHealth" }, nil)
        if health and health < 99.5 then
            return true
        end
        for j = 1, #boolMethods do
            if gsSafeCall(part, boolMethods[j], false) == true then
                return true
            end
        end
        for j = 1, #timeMethods do
            local value = tonumber(gsSafeCall(part, timeMethods[j], 0)) or 0
            if value > 0 then
                return true
            end
        end
    end
    return false
end

local function gsMedicalClearBodyPartInfection(part)
    if not part then
        return
    end
    gsSafeCall(part, "SetInfected", nil, false)
    gsSafeCall(part, "SetFakeInfected", nil, false)
    gsSafeCall(part, "setInfectedWound", nil, false)
    gsSafeCall(part, "setWoundInfectionLevel", nil, -1)
end

local function gsMedicalClearInfection(body, targetPlayer)
    if not body then
        return false
    end
    local p = gsMedicalPlayer(targetPlayer)
    if p and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil then
        local stats = gsSafeCall(p, "getStats", nil)
        if stats then
            pcall(function()
                stats:set(CharacterStat.ZOMBIE_INFECTION, 0)
            end)
        end
    end
    gsSafeCall(body, "setInfectionTime", nil, -1.0)
    gsSafeCall(body, "setInfectionLevel", nil, 0)
    gsSafeCall(body, "setInfected", nil, false)
    gsSafeCall(body, "setIsFakeInfected", nil, false)
    gsSafeCall(body, "setInfectionMortalityDuration", nil, -1.0)
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        gsMedicalClearBodyPartInfection(parts[i])
    end
    return gsMedicalIsInfected(body) ~= true
end

local function gsMedicalFormatTemplate(template, args)
    local text = tostring(template or "")
    args = args or {}
    for i = 1, #args do
        text = string.gsub(text, "{" .. tostring(i) .. "}", function()
            return tostring(args[i] or "")
        end)
    end
    return text
end

local function gsMedicalHealPart(part)
    if not part then
        return
    end
    gsSafeCall(part, "SetHealth", nil, 100)
    gsSafeCall(part, "setHealth", nil, 100)
    gsSafeCall(part, "setBleedingTime", nil, 0)
    gsSafeCall(part, "setDeepWoundTime", nil, 0)
    gsSafeCall(part, "setScratchTime", nil, 0)
    gsSafeCall(part, "setCutTime", nil, 0)
    gsSafeCall(part, "setBiteTime", nil, 0)
    gsSafeCall(part, "setBurnTime", nil, 0)
    gsSafeCall(part, "setFractureTime", nil, 0)
    gsSafeCall(part, "setAdditionalPain", nil, 0)
    gsSafeCall(part, "setWoundInfectionLevel", nil, 0)
    gsSafeCall(part, "setHaveBullet", nil, false, 0)
    gsSafeCall(part, "setHaveGlass", nil, false)
    gsSafeCall(part, "setStitched", nil, false)
    gsSafeCall(part, "setSplint", nil, false, 0)
    gsSafeCall(part, "setBandaged", nil, false, 0, false, "", nil)
end

local function gsMedicalHealInjuries(targetPlayer, body)
    body = body or gsMedicalBody(targetPlayer)
    if not body then
        return false
    end
    local snapshot = gsMedicalCaptureInfection(body)
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        gsMedicalHealPart(parts[i])
    end
    gsSafeCall(body, "setOverallBodyHealth", nil, 100)
    local p = gsMedicalPlayer(targetPlayer)
    if p then
        gsSafeCall(p, "setHealth", nil, 1.0)
    end
    gsMedicalRestoreInfection(body, snapshot)
    return true
end

function GodSystem.getMedicalStatus(targetPlayer)
    local body = gsMedicalBody(targetPlayer)
    if not body then
        return { hasBody = false, infected = false, hasInjury = false }
    end
    return {
        hasBody = true,
        infected = gsMedicalIsInfected(body),
        hasInjury = gsMedicalHasInjury(body),
        infectionTime = gsMedicalNumber(body, { "getInfectionTime" }, nil),
        infectionLevel = gsMedicalNumber(body, { "getInfectionLevel" }, nil),
        mortalityDuration = gsMedicalNumber(body, { "getInfectionMortalityDuration" }, nil),
    }
end

function GodSystem.getMedicalServiceInfo(action)
    action = tostring(action or "")
    if action == "checkInfection" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalCheckInfectionCost) or 50)),
            label = GodSystem.text("Upgrade_Medical_CheckInfection", "Check infection"),
            desc = GodSystem.text("Upgrade_Medical_CheckInfectionDesc", "Pay to check whether this character has zombie infection."),
            button = GodSystem.text("Btn_Medical_CheckInfection", "Check"),
        }
    elseif action == "healInjuries" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalHealInjuriesCost) or 5000)),
            label = GodSystem.text("Upgrade_Medical_HealInjuries", "Heal injuries"),
            desc = GodSystem.text("Upgrade_Medical_HealInjuriesDesc", "Clear wounds and restore health. This does not remove zombie infection."),
            button = GodSystem.text("Btn_Medical_HealInjuries", "Heal"),
        }
    elseif action == "cureInfection" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalCureInfectionCost) or 2000)),
            label = GodSystem.text("Upgrade_Medical_CureInfection", "Cure infection"),
            desc = GodSystem.text("Upgrade_Medical_CureInfectionDesc", "Fully remove zombie infection. Wounds are not healed."),
            button = GodSystem.text("Btn_Medical_CureInfection", "Cure"),
        }
    end
    return nil
end

function GodSystem.getMedicalServiceList()
    local result = {}
    for i = 1, #MEDICAL_SERVICE_ORDER do
        local info = GodSystem.getMedicalServiceInfo(MEDICAL_SERVICE_ORDER[i])
        if info then
            result[#result + 1] = info
        end
    end
    return result
end

function GodSystem.applyMedicalServiceLocally(action, targetPlayer)
    local body = gsMedicalBody(targetPlayer)
    if not body then
        return false, "bodyMissing"
    end
    action = tostring(action or "")
    if action == "checkInfection" then
        return true, gsMedicalIsInfected(body) and "infected" or "clean"
    elseif action == "healInjuries" then
        return gsMedicalHealInjuries(targetPlayer, body), "healed"
    elseif action == "cureInfection" then
        if not gsMedicalIsInfected(body) then
            return true, "notInfected"
        end
        return gsMedicalClearInfection(body, targetPlayer), "cured"
    end
    return false, "unknown"
end

function GodSystem.performMedicalService(action)
    local info = GodSystem.getMedicalServiceInfo(action)
    if not info then
        GodSystem.notify(GodSystem.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end
    local status = GodSystem.getMedicalStatus()
    if status.hasBody ~= true then
        GodSystem.notify(GodSystem.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end
    if action == "cureInfection" and status.infected ~= true then
        GodSystem.notify(GodSystem.text("Notify_Medical_NotInfected", "No zombie infection detected"))
        return false
    end
    if action == "healInjuries" and status.hasInjury ~= true then
        GodSystem.notify(GodSystem.text("Notify_Medical_NoInjury", "No injuries need treatment"))
        return false
    end
    if not GodSystem.canAfford(info.cost or 0) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    if (info.cost or 0) > 0 and not GodSystem.addPoints(-info.cost) then
        return false
    end

    local ok, result = GodSystem.applyMedicalServiceLocally(action)
    if not ok then
        if (info.cost or 0) > 0 then
            GodSystem.addPoints(info.cost)
        end
        GodSystem.notify(GodSystem.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end

    local data = GodSystem.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + (info.cost or 0)
    local messageKey = "Notify_Medical_Healed"
    if action == "checkInfection" then
        messageKey = result == "infected" and "Notify_Medical_CheckResultInfected" or "Notify_Medical_CheckResultClean"
    elseif action == "cureInfection" then
        messageKey = "Notify_Medical_Cured"
    end
    local message = GodSystem.text(messageKey, "Medical service complete")
    gsAppendHistory(data, { kind = "medical", text = GodSystem.text("History_MedicalService", "Medical service: ") .. tostring(info.label) .. " -" .. tostring(info.cost or 0) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.notify(message)
    GodSystem.save()
    return true
end

function GodSystem.getAttributePerks(query)
    if GodSystemAttributes.isEnabled() ~= true then return {} end
    local rows = GodSystemAttributes.enumerate(gsPlayer())
    query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return rows end
    local filtered = {}
    for i = 1, #rows do
        local row = rows[i]
        local haystack = (tostring(row.label or "") .. " " .. tostring(row.parentLabel or "")):lower()
        if string.find(haystack, query, 1, true) then filtered[#filtered + 1] = row end
    end
    return filtered
end

function GodSystem.getAttributeQuote(perkIndex, mode, value)
    return GodSystemAttributes.quote(gsPlayer(), perkIndex, mode, value, GodSystemAttributes.getXpPerCoin())
end

function GodSystem.performAttributePurchase(perkIndex, mode, value)
    if GodSystemAttributes.isEnabled() ~= true then
        GodSystem.notify(GodSystem.text("Notify_AttributesDisabled", "Attribute purchases are disabled"))
        return false
    end
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true and GodSystemNetwork.send then
        return GodSystemNetwork.send((GodSystemProtocol and GodSystemProtocol.C2S and GodSystemProtocol.C2S.Attribute) or "attribute", {
            perkIndex = math.floor(tonumber(perkIndex) or -1),
            mode = tostring(mode or "amount"),
            value = math.floor(tonumber(value) or 0),
        })
    end

    local player = gsPlayer()
    local quote, reason = GodSystemAttributes.quote(player, perkIndex, mode, value, GodSystemAttributes.getXpPerCoin())
    if not quote then
        local key = reason == "maxed" and "Notify_AttributeMaxed" or "Notify_AttributeInvalid"
        GodSystem.notify(GodSystem.text(key, "Unable to purchase attribute XP"))
        return false
    end
    if not GodSystem.canAfford(quote.cost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local paid, fromBank, fromCash = GodSystem.spendCurrency(quote.cost)
    if not paid then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local before = quote.currentXp
    local xp = player and player.getXp and player:getXp() or nil
    if xp and xp.AddXP then
        pcall(function() xp:AddXP(quote.info.perk, quote.actualXp, false, false, false, false) end)
    end
    local state = GodSystemAttributes.getPlayerState(player, quote.info)
    local appliedXp = state and math.max(0, state.currentXp - before) or 0
    if appliedXp <= 0 then
        local originalSourcesRestored = GodSystem.refundCurrencySources(fromBank, fromCash)
        local key = originalSourcesRestored and "Notify_AttributeApplyFailed" or "Notify_AttributeApplyFailedBankRefund"
        GodSystem.notify(GodSystem.text(key, "Attribute XP could not be applied; payment was refunded"))
        GodSystem.save()
        return false
    end

    local chargedCost = quote.cost
    if appliedXp + 0.0001 < quote.actualXp then
        chargedCost = math.max(1, math.min(quote.cost, math.ceil(appliedXp / GodSystemAttributes.getXpPerCoin())))
        local refund = quote.cost - chargedCost
        local refundCash = math.min(math.max(0, math.floor(tonumber(fromCash) or 0)), refund)
        GodSystem.refundCurrencySources(refund - refundCash, refundCash)
    end
    if type(SyncXp) == "function" then pcall(function() SyncXp(player) end) end
    local data = GodSystem.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + chargedCost
    gsAppendHistory(data, {
        kind = "attribute",
        text = GodSystem.text("History_AttributePurchased", "Attribute XP purchased: ") .. tostring(quote.info.label) .. " +" .. tostring(math.floor(appliedXp)) .. " XP -" .. tostring(chargedCost) .. GodSystem.text("Unit_Coin", " coins"),
    })
    GodSystem.notify(GodSystem.text("Notify_AttributePurchased", "Attribute XP purchased: ") .. tostring(quote.info.label) .. " +" .. tostring(math.floor(appliedXp)) .. " XP")
    GodSystem.save()
    return true
end

local function gsTraitTokenString(token)
    if token == nil then
        return ""
    end
    local tokenType = type(token)
    if tokenType == "string" or tokenType == "number" or tokenType == "boolean" then
        return tostring(token)
    end
    if token.toString then
        local value = token:toString()
        return tostring(value)
    end
    return tostring(token)
end

local function gsNormalizeTraitType(traitType)
    return tostring(traitType or ""):gsub("[%s_%-]", ""):lower()
end

local function gsTraitMapLookup(map, traitType)
    if not map or not traitType then
        return nil
    end
    local direct = map[traitType]
    if direct ~= nil then
        return direct
    end
    if type(map) == "table" then
        local target = gsNormalizeTraitType(traitType)
        for key, value in pairs(map) do
            if gsNormalizeTraitType(key) == target then
                return value
            end
        end
    end
    return nil
end

local GodSystemTraitDefinitionCache = nil

local function gsBuildCharacterTraitDefinitionCache()
    local cache = { list = {}, byType = {}, byToken = {} }
    if not CharacterTraitDefinition then
        return cache
    end
    local traits = nil
    if CharacterTraitDefinition.getTraits then
        traits = CharacterTraitDefinition.getTraits()
    end
    if traits then
        cache.list = gsArrayFromList(traits)
    end
    for i = 1, #cache.list do
        local trait = cache.list[i]
        if trait and trait.getType then
            local token = trait:getType()
            local traitType = gsTraitTokenString(token)
            local key = gsNormalizeTraitType(traitType)
            if key ~= "" then
                cache.byType[key] = trait
                cache.byToken[key] = token
            end
        end
    end
    return cache
end

local function gsCharacterTraitDefinitionCache()
    if not GodSystemTraitDefinitionCache then
        GodSystemTraitDefinitionCache = gsBuildCharacterTraitDefinitionCache()
    end
    return GodSystemTraitDefinitionCache
end

local function gsCharacterTraitDefinitionList()
    return gsCharacterTraitDefinitionCache().list or {}
end

local function gsCharacterTraitDefinitionByType(traitType)
    local target = gsNormalizeTraitType(traitType)
    if target == "" then
        return nil
    end
    local cache = gsCharacterTraitDefinitionCache()
    return cache.byType[target], cache.byToken[target]
end

local function gsTraitFactory()
    if TraitFactory then
        return TraitFactory
    end
    if GodSystemTraitFactoryClass then
        return GodSystemTraitFactoryClass
    end
    if luajava and luajava.bindClass then
        local ok, factory = pcall(function() return luajava.bindClass("zombie.characters.traits.TraitFactory") end)
        if ok and factory then
            GodSystemTraitFactoryClass = factory
            return factory
        end
    end
    return nil
end

local function gsFallbackTraitByType(traitType)
    if not traitType then
        return nil
    end
    local catalog = GodSystemConfig.TraitFallbackCatalog or {}
    for i = 1, #catalog do
        local entry = catalog[i]
        if entry and gsNormalizeTraitType(entry.type) == gsNormalizeTraitType(traitType) then
            return entry
        end
    end
    return nil
end

local function gsFallbackTraitList()
    local result = {}
    local catalog = GodSystemConfig.TraitFallbackCatalog or {}
    for i = 1, #catalog do
        if catalog[i] and catalog[i].type then
            table.insert(result, catalog[i])
        end
    end
    return result
end

local function gsTraitFactoryGetTrait(traitType)
    if not traitType then
        return nil
    end
    local characterTrait = gsCharacterTraitDefinitionByType(traitType)
    if characterTrait then
        return characterTrait
    end
    local token = gsTraitTokenForType(traitType)
    if CharacterTraitDefinition and CharacterTraitDefinition.getCharacterTraitDefinition and token and type(token) ~= "string" then
        characterTrait = CharacterTraitDefinition.getCharacterTraitDefinition(token)
        if characterTrait then
            return characterTrait
        end
    end
    local factory = gsTraitFactory()
    local trait = nil
    if factory and factory.getTrait and type(traitType) == "string" then
        trait = factory.getTrait(traitType)
    end
    if trait then
        return trait
    end
    return gsFallbackTraitByType(traitType)
end

local function gsTraitTokenForType(traitType)
    if not traitType then
        return nil
    end
    if type(traitType) ~= "string" then
        return traitType
    end

    local trait, token = gsCharacterTraitDefinitionByType(traitType)
    if token then
        return token
    end
    if trait and trait.getType then
        return trait:getType()
    end

    if CharacterTrait then
        local found = gsTraitMapLookup(CharacterTrait, traitType)
        if found then
            return found
        end
    end
    return traitType
end

local function gsTraitFactoryList()
    local traitList = gsCharacterTraitDefinitionList()
    if #traitList > 0 then
        return traitList, "CharacterTraitDefinition"
    end

    local factory = gsTraitFactory()
    local traits = nil
    if factory and factory.getTraits then
        traits = factory.getTraits()
    end
    traitList = gsArrayFromList(traits)
    if #traitList > 0 then
        return traitList, "TraitFactory"
    end

    if BaseGameCharacterDetails and BaseGameCharacterDetails.traits then
        traitList = gsArrayFromList(BaseGameCharacterDetails.traits)
        if #traitList > 0 then
            return traitList, "BaseGameCharacterDetails"
        end
    end

    return gsFallbackTraitList(), "FallbackCatalog"
end

local function gsTraitType(trait)
    if type(trait) == "table" then
        return tostring(trait.type or trait.traitType or "")
    end
    if trait and trait.getType then
        local traitType = trait:getType()
        if traitType ~= nil then
            return gsTraitTokenString(traitType)
        end
    end
    return tostring(trait or "")
end

local function gsTraitLabel(trait, traitType)
    traitType = traitType or gsTraitType(trait)
    if type(trait) == "table" then
        local label = gsSafeGetText(trait.labelKey)
        if label and label ~= "" then
            return label
        end
        if trait.label and tostring(trait.label) ~= "" then
            return tostring(trait.label)
        end
        return tostring(traitType or "")
    end
    if trait and trait.getLabel then
        local label = trait:getLabel()
        if label and tostring(label) ~= "" then
            return tostring(label)
        end
    end
    return tostring(traitType or "")
end

local function gsTraitLabelByType(traitType)
    local trait = gsTraitFactoryGetTrait(traitType)
    if trait then
        return gsTraitLabel(trait, traitType)
    end
    return tostring(traitType or "")
end

local function gsTraitCost(trait)
    if type(trait) == "table" then
        return math.floor(tonumber(trait.cost or trait.costPoints) or 0)
    end
    if trait and trait.getCost then
        local cost = tonumber(trait:getCost())
        if cost then
            return math.floor(cost)
        end
    end
    return 0
end

local function gsTraitIsFree(trait)
    if type(trait) == "table" then
        return trait.free == true
    end
    if trait and trait.isFree then
        return trait:isFree() == true
    end
    return false
end

local function gsTraitIsProfession(trait)
    if not trait then
        return false
    end
    if type(trait) == "table" then
        return trait.prof == true or trait.profession == true
    end
    return false
end

local function gsTraitDescription(trait)
    if type(trait) == "table" then
        local description = gsSafeGetText(trait.descriptionKey)
        if description and description ~= "" then
            return description
        end
        return tostring(trait.description or "")
    end
    if trait and trait.getDescription then
        local description = trait:getDescription()
        if description and tostring(description) ~= "" then
            return tostring(description)
        end
    end
    return ""
end

local function gsTraitMutualTypes(trait)
    if type(trait) == "table" then
        return gsArrayFromList(trait.mutual or trait.mutualTypes or {})
    end
    local raw = nil
    if trait and trait.getMutuallyExclusiveTraits then
        raw = trait:getMutuallyExclusiveTraits()
    end
    local values = gsArrayFromList(raw)
    local result = {}
    for i = 1, #values do
        local traitType = gsTraitTokenString(values[i])
        if traitType ~= "" then
            table.insert(result, traitType)
        end
    end
    return result
end

local function gsJoinLabels(labels)
    if not labels or #labels == 0 then
        return GodSystem.text("None", "None")
    end
    return table.concat(labels, ", ")
end

function GodSystem.getPlayerTraits()
    local player = gsPlayer()
    if player then
        if player.getCharacterTraits then
            return player:getCharacterTraits()
        end
        if player.getTraits then
            return player:getTraits()
        end
    end
    return nil
end

function GodSystem.playerHasTrait(traitType)
    if not traitType then
        return false
    end
    local player = gsPlayer()
    local token = gsTraitTokenForType(traitType)
    if player and player.hasTrait and token and type(token) ~= "string" then
        return player:hasTrait(token) == true
    end
    local traits = GodSystem.getPlayerTraits()
    if traits then
        local known = nil
        if traits.getKnownTraits then
            known = traits:getKnownTraits()
        end
        local knownList = gsArrayFromList(known)
        local target = gsNormalizeTraitType(traitType)
        for i = 1, #knownList do
            if gsNormalizeTraitType(gsTraitTokenString(knownList[i])) == target then
                return true
            end
        end
    end
    return false
end

local function gsApplyTraitBenefits(traitType)
    local player = gsPlayer()
    local trait = gsCharacterTraitDefinitionByType(traitType)
    if not player or not trait then
        return
    end

    local boosts = trait.getXpBoosts and trait:getXpBoosts() or nil
    if boosts then
        local boostTable = nil
        if transformIntoKahluaTable then
            boostTable = transformIntoKahluaTable(boosts)
        elseif type(boosts) == "table" then
            boostTable = boosts
        end
        if boostTable then
            for perk, value in pairs(boostTable) do
                local count = tonumber(tostring(value)) or 0
                for _ = 1, count do
                    local level = player.getPerkLevel and player:getPerkLevel(perk) or 0
                    if tonumber(level) and tonumber(level) >= 10 then
                        break
                    end
                    if player.LevelPerk then
                        player:LevelPerk(perk)
                    end
                    if luautils and luautils.updatePerksXp then
                        luautils.updatePerksXp(perk, player)
                    end
                end
            end
        end
    end

    local hasRecipes = trait.hasGrantedRecipes and trait:hasGrantedRecipes() or false
    if hasRecipes then
        local recipes = trait.getGrantedRecipes and trait:getGrantedRecipes() or nil
        local recipeList = gsArrayFromList(recipes)
        for i = 1, #recipeList do
            if player.learnRecipe then
                player:learnRecipe(recipeList[i])
            end
        end
    end
end

function GodSystem.setPlayerTrait(traitType, enabled)
    local traits = GodSystem.getPlayerTraits()
    if not traits or not traitType then
        return false
    end

    local token = gsTraitTokenForType(traitType)
    if type(token) == "string" then
        return false
    end
    if enabled and not GodSystem.playerHasTrait(traitType) then
        if traits.add then
            traits:add(token)
        end
    elseif not enabled and GodSystem.playerHasTrait(traitType) then
        if traits.remove then
            traits:remove(token)
        end
    end

    local success = GodSystem.playerHasTrait(traitType) == (enabled == true)
    if success and enabled then
        gsApplyTraitBenefits(traitType)
    end
    return success
end

function GodSystem.getTraitOperationCost(costPoints, action)
    costPoints = math.floor(tonumber(costPoints) or 0)
    if action == "buy" then
        return math.max(0, costPoints) * (GodSystemConfig.PositiveTraitCostPerPoint or 800)
    end
    return math.abs(math.min(0, costPoints)) * (GodSystemConfig.NegativeTraitRemoveCostPerPoint or 500)
end

function GodSystem.getTraitRiskText(entry)
    if not entry or entry.risk ~= true then
        return GodSystem.text("Trait_RiskStable", "Stable")
    end
    return GodSystem.text("Trait_RiskExperimental", "Risk")
end

function GodSystem.isTraitBlocked(traitType, trait, cost)
    if not traitType or traitType == "" then
        return true, GodSystem.text("Trait_BlockUnknown", "Unknown trait")
    end
    if gsTraitMapLookup(GodSystemConfig.TraitBlockedTypes or {}, traitType) then
        return true, GodSystem.text("Trait_BlockBodySkill", "Body weight / strength / fitness traits are not available yet")
    end
    if gsTraitIsFree(trait) or gsTraitIsProfession(trait) or (tonumber(cost) or 0) == 0 then
        return true, GodSystem.text("Trait_BlockFree", "Free or profession trait")
    end
    return false, ""
end

function GodSystem.getTraitEntryFromTrait(trait, action)
    if not trait then
        return nil
    end
    local traitType = gsTraitType(trait)
    local cost = gsTraitCost(trait)
    local blocked, reason = GodSystem.isTraitBlocked(traitType, trait, cost)
    if blocked then
        return nil, reason
    end
    if action == "buy" and cost <= 0 then
        return nil, ""
    end
    if action == "remove" and cost >= 0 then
        return nil, ""
    end

    local label = gsTraitLabel(trait, traitType)
    local mutualTypes = gsTraitMutualTypes(trait)
    local conflictLabels = {}
    local ownedConflictLabels = {}
    for i = 1, #mutualTypes do
        local conflictType = mutualTypes[i]
        local conflictLabel = gsTraitLabelByType(conflictType)
        table.insert(conflictLabels, conflictLabel)
        if GodSystem.playerHasTrait(conflictType) then
            table.insert(ownedConflictLabels, conflictLabel)
        end
    end

    local owned = GodSystem.playerHasTrait(traitType)
    local entry = {
        kind = "trait",
        action = action,
        traitType = traitType,
        label = label,
        description = gsTraitDescription(trait),
        costPoints = cost,
        price = GodSystem.getTraitOperationCost(cost, action),
        risk = not (gsTraitMapLookup(GodSystemConfig.TraitStableTypes or {}, traitType) == true),
        conflictTypes = mutualTypes,
        conflictLabels = conflictLabels,
        ownedConflictLabels = ownedConflictLabels,
        owned = owned,
        disabledReason = nil,
    }

    if action == "buy" then
        if owned then
            entry.disabledReason = GodSystem.text("Trait_StatusOwned", "Owned")
        elseif #ownedConflictLabels > 0 then
            entry.disabledReason = GodSystem.text("Trait_StatusConflict", "Conflict: ") .. gsJoinLabels(ownedConflictLabels)
        end
    elseif action == "remove" and not owned then
        entry.disabledReason = GodSystem.text("Trait_StatusNotOwned", "Not owned")
    end

    return entry, ""
end

function GodSystem.getTraitModificationLists()
    local traitList, source = gsTraitFactoryList()

    local function collectTraits(list)
        local positive = {}
        local negative = {}
        local blockedCount = 0
        for i = 1, #list do
            local trait = list[i]
            local cost = gsTraitCost(trait)
            local traitType = gsTraitType(trait)
            local blocked = GodSystem.isTraitBlocked(traitType, trait, cost)
            if blocked then
                blockedCount = blockedCount + 1
            elseif cost > 0 then
                local entry = GodSystem.getTraitEntryFromTrait(trait, "buy")
                if entry then
                    table.insert(positive, entry)
                end
            elseif cost < 0 and GodSystem.playerHasTrait(traitType) then
                local entry = GodSystem.getTraitEntryFromTrait(trait, "remove")
                if entry then
                    table.insert(negative, entry)
                end
            end
        end
        return positive, negative, blockedCount
    end

    local positive, negative, blockedCount = collectTraits(traitList)
    if #positive == 0 and source ~= "FallbackCatalog" then
        local fallbackList = gsFallbackTraitList()
        local fallbackPositive, fallbackNegative, fallbackBlocked = collectTraits(fallbackList)
        if #fallbackPositive > 0 then
            positive = fallbackPositive
            negative = fallbackNegative
            blockedCount = fallbackBlocked
            traitList = fallbackList
            source = "FallbackCatalog"
        end
    end

    local function sortTraits(a, b)
        if a.risk ~= b.risk then
            return a.risk ~= true
        end
        if math.abs(a.costPoints or 0) ~= math.abs(b.costPoints or 0) then
            return math.abs(a.costPoints or 0) < math.abs(b.costPoints or 0)
        end
        return tostring(a.label or "") < tostring(b.label or "")
    end
    table.sort(positive, sortTraits)
    table.sort(negative, sortTraits)
    GodSystem.lastTraitRead = {
        source = source,
        total = #traitList,
        positive = #positive,
        negative = #negative,
        blocked = blockedCount,
    }
    return positive, negative, blockedCount
end

function GodSystem.getTraitModificationEntry(action, traitType)
    local positive, negative = GodSystem.getTraitModificationLists()
    local list = action == "remove" and negative or positive
    for i = 1, #list do
        if list[i].traitType == traitType then
            return list[i]
        end
    end
    return nil
end

function GodSystem.getTraitDetailText(entry)
    if not entry then
        return ""
    end
    local parts = {}
    table.insert(parts, GodSystem.text("Trait_PointCost", "Trait points ") .. tostring(entry.costPoints or 0))
    table.insert(parts, GodSystem.text("Trait_Price", "Cost ") .. tostring(entry.price or 0) .. GodSystem.text("Unit_CoinShort", "c"))
    table.insert(parts, GodSystem.text("Trait_Risk", "Risk: ") .. GodSystem.getTraitRiskText(entry))
    if entry.conflictLabels and #entry.conflictLabels > 0 then
        table.insert(parts, GodSystem.text("Trait_Conflicts", "Conflicts: ") .. gsJoinLabels(entry.conflictLabels))
    end
    if entry.disabledReason then
        table.insert(parts, GodSystem.text("Trait_Status", "Status: ") .. tostring(entry.disabledReason))
    end
    if entry.description and entry.description ~= "" then
        table.insert(parts, entry.description)
    end
    return table.concat(parts, " | ")
end

function GodSystem.performTraitModification(action, traitType)
    if GodSystem.isFeatureEnabled("EnableTraits") == false then
        GodSystem.notify("Traits disabled")
        return false
    end
    local entry = GodSystem.getTraitModificationEntry(action, traitType)
    if not entry then
        GodSystem.notify(GodSystem.text("Notify_TraitUnavailable", "Trait is not available"))
        return false
    end
    if entry.disabledReason then
        GodSystem.notify(entry.disabledReason)
        return false
    end
    if not GodSystem.canAfford(entry.price or 0) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local enable = action == "buy"
    if not GodSystem.setPlayerTrait(entry.traitType, enable) then
        GodSystem.notify(GodSystem.text("Notify_TraitFailed", "Trait modification failed"))
        return false
    end
    if not GodSystem.addPoints(-(entry.price or 0)) then
        GodSystem.setPlayerTrait(entry.traitType, not enable)
        GodSystem.notify(GodSystem.text("Notify_TraitFailed", "Trait modification failed"))
        return false
    end

    local data = GodSystem.getData()
    data.stats.spentPoints = (data.stats.spentPoints or 0) + (entry.price or 0)
    data.stats.modifiedTraits = (data.stats.modifiedTraits or 0) + 1
    local historyKey = enable and "History_TraitBought" or "History_TraitRemoved"
    local notifyKey = enable and "Notify_TraitBought" or "Notify_TraitRemoved"
    local riskText = entry.risk and (" | " .. GodSystem.text("Trait_RiskExperimental", "Risk")) or ""
    gsAppendHistory(data, { kind = "trait", text = GodSystem.text(historyKey, "Trait modified: ") .. tostring(entry.label) .. " -" .. tostring(entry.price or 0) .. GodSystem.text("Unit_Coin", " coins") .. riskText })
    GodSystem.save()
    GodSystem.notify(GodSystem.text(notifyKey, "Trait modified: ") .. tostring(entry.label) .. " -" .. tostring(entry.price or 0) .. GodSystem.text("Unit_Coin", " coins"))
    return true
end

function GodSystem.getItemModData(item)
    if not item or not item.getModData then
        return nil
    end
    local ok, data = pcall(function() return item:getModData() end)
    if ok then
        return data
    end
    return nil
end

function GodSystem.getAutoRecyclerLevels()
    return GodSystemTerminalUpgrades.getLevels("capacity")
end

function GodSystem.getAutoRecyclerMaxLevel()
    local levels = GodSystem.getAutoRecyclerLevels()
    return math.max(1, #levels)
end

function GodSystem.getAutoRecyclerLevelData(level)
    local data = GodSystem.getData()
    local capacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity", level)
    local reduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction", level)
    return {
        level = math.max(1, math.floor(tonumber(level) or GodSystemTerminalUpgrades.getLevel(data, "capacity"))),
        capacity = capacity.value or 10,
        weightReduction = reduction.value or 50,
        upgradeCost = capacity.upgradeCost or 0,
    }
end

function GodSystem.getAutoRecyclerLevel()
    return GodSystemTerminalUpgrades.getLevel(GodSystem.getData(), "capacity")
end

function GodSystem.getAutoRecyclerRecoverCost()
    local level = GodSystemTerminalUpgrades.getRecoveryLevel(GodSystem.getData())
    local costs = GodSystemConfig.AutoRecyclerRecoverCosts or {}
    for i = 1, #costs do
        if level <= (costs[i].maxLevel or level) then
            return costs[i].cost or 0
        end
    end
    return 0
end

function GodSystem.getWaistAutoRecycleUnlockCost()
    return math.max(0, math.floor(tonumber(GodSystemConfig.WaistAutoRecycleUnlockCost) or 100))
end

function GodSystem.getWaistAutoRecycleIntervalHours()
    return math.max(1, math.floor(tonumber(GodSystemConfig.WaistAutoRecycleIntervalHours) or 1))
end

function GodSystem.getAutoRecyclerDisplayName(level)
    level = level or GodSystem.getAutoRecyclerLevel()
    return GodSystem.text("AutoRecycler_Name", "System Space Terminal") .. " Lv." .. tostring(level)
end

function GodSystem.isAutoRecyclerFullType(fullType)
    return fullType == (GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal")
end

function GodSystem.applyAutoRecyclerContainerStats(item, level)
    if not item then return false end
    if (isClient and isClient()) or (GodSystemNetwork and GodSystemNetwork.isMultiplayer == true) then
        return true
    end
    local data = GodSystem.getData()
    return GodSystemTerminalUpgrades.applyTerminal(item, data, gsPlayer())
end

function GodSystem.markAutoRecyclerContainer(item, level)
    if not item or not item.getFullType then
        return false
    end
    if not GodSystem.isAutoRecyclerFullType(item:getFullType()) then
        return false
    end
    if (isClient and isClient()) or (GodSystemNetwork and GodSystemNetwork.isMultiplayer == true) then
        GodSystem.autoRecyclerCache = { item = item }
        return true
    end
    local playerData = GodSystem.getData()
    level = GodSystemTerminalUpgrades.getLevel(playerData, "capacity")
    local data = GodSystem.getItemModData(item)
    if data then
        data[GodSystemConfig.AutoRecyclerMarkerKey or "GodSystemAutoRecycler"] = true
        data[GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"] = level
    end
    if item.setName then
        pcall(function() item:setName(GodSystem.getAutoRecyclerDisplayName(level)) end)
    end
    if item.setCustomName then
        pcall(function() item:setCustomName(true) end)
    end
    if not (GodSystemNetwork and GodSystemNetwork.isMultiplayer == true) then
        GodSystemTerminalRelief.removeEscapedFromPlayer(gsPlayer(), item)
    end
    local applied = GodSystem.applyAutoRecyclerContainerStats(item)
    GodSystem.autoRecyclerCache = { item = item }
    return applied == true
end

function GodSystem.getAutoRecyclerItemLevel(item)
    local data = GodSystem.getItemModData(item)
    local level = data and data[GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"] or nil
    return math.max(1, math.min(math.floor(tonumber(level) or GodSystem.getAutoRecyclerLevel()), GodSystem.getAutoRecyclerMaxLevel()))
end

local function gsAddAutoRecyclerCandidate(result, seen, item, container)
    if not item or not item.getFullType then
        return
    end
    if not GodSystem.isAutoRecyclerFullType(item:getFullType()) then
        return
    end
    if seen[item] then
        return
    end
    seen[item] = true
    table.insert(result, { item = item, container = container })
end

function GodSystem.findAutoRecyclerCandidates()
    local result = {}
    local seen = {}
    local aliases = GodSystemConfig.AutoRecyclerFullTypes or { [GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal"] = true }
    for fullType, enabled in pairs(aliases) do
        if enabled == true then
            local found = gsFindInventoryItems(fullType, true, true)
            for i = 1, #found do
                gsAddAutoRecyclerCandidate(result, seen, found[i].item, found[i].container)
            end
        end
    end

    local player = gsPlayer()
    if player then
        local primary = player.getPrimaryHandItem and player:getPrimaryHandItem() or nil
        local secondary = player.getSecondaryHandItem and player:getSecondaryHandItem() or nil
        gsAddAutoRecyclerCandidate(result, seen, primary, nil)
        gsAddAutoRecyclerCandidate(result, seen, secondary, nil)

        if player.getWornItems then
            local okWorn, wornItems = pcall(function() return player:getWornItems() end)
            if okWorn and wornItems and wornItems.size and wornItems.get then
                local okSize, size = pcall(function() return wornItems:size() end)
                if okSize and size then
                    for i = 0, size - 1 do
                        local okWornItem, wornItem = pcall(function() return wornItems:get(i) end)
                        if okWornItem and wornItem then
                            local item = nil
                            if wornItem.getItem then
                                local okItem, value = pcall(function() return wornItem:getItem() end)
                                if okItem then
                                    item = value
                                end
                            elseif wornItem.getFullType then
                                item = wornItem
                            end
                            gsAddAutoRecyclerCandidate(result, seen, item, nil)
                        end
                    end
                end
            end
        end

        if player.getAttachedItems then
            local okAttached, attachedItems = pcall(function() return player:getAttachedItems() end)
            if okAttached and attachedItems and attachedItems.size then
                local okSize, size = pcall(function() return attachedItems:size() end)
                if okSize and size then
                    for i = 0, size - 1 do
                        local item = nil
                        if attachedItems.getItemByIndex then
                            local okItem, value = pcall(function() return attachedItems:getItemByIndex(i) end)
                            if okItem then
                                item = value
                            end
                        end
                        if not item and attachedItems.get then
                            local okAttachedItem, attachedItem = pcall(function() return attachedItems:get(i) end)
                            if okAttachedItem and attachedItem then
                                if attachedItem.getItem then
                                    local okItem, value = pcall(function() return attachedItem:getItem() end)
                                    if okItem then
                                        item = value
                                    end
                                elseif attachedItem.getFullType then
                                    item = attachedItem
                                end
                            end
                        end
                        gsAddAutoRecyclerCandidate(result, seen, item, nil)
                    end
                end
            end
        end
    end
    return result
end

function GodSystem.isAutoRecyclerOwnedByPlayer(item)
    local player = gsPlayer()
    if not player or not item then return false end
    local root = player.getInventory and player:getInventory() or nil
    local current = item
    local seen = {}
    for _ = 1, 34 do
        if not current or seen[current] then return false end
        seen[current] = true
        local ok, container = pcall(function() return current:getContainer() end)
        if not ok or not container then return false end
        if container == root then return true end
        local parent = nil
        if container.getContainingItem then
            local parentOk, value = pcall(function() return container:getContainingItem() end)
            if parentOk then parent = value end
        end
        current = parent
    end
    return false
end

function GodSystem.getCachedAutoRecyclerContainer()
    local cache = GodSystem.autoRecyclerCache
    local item = cache and cache.item or nil
    if item and GodSystem.isAutoRecyclerContainer(item) and GodSystem.isAutoRecyclerOwnedByPlayer(item) then
        return { item = item, container = item.getContainer and item:getContainer() or nil }
    end
    GodSystem.autoRecyclerCache = nil
    return nil
end

function GodSystem.getAutoRecyclerContainer(forceSearch)
    local cached = GodSystem.getCachedAutoRecyclerContainer()
    if cached then
        GodSystem.markAutoRecyclerContainer(cached.item)
        return cached
    end
    if forceSearch == false then return nil end
    local found = GodSystem.findAutoRecyclerCandidates()
    local candidates = {}
    for i = 1, #found do
        local item = found[i].item
        if GodSystem.isAutoRecyclerContainer(item) then
            table.insert(candidates, found[i])
        end
    end
    if #candidates <= 0 then
        return nil
    end
    table.sort(candidates, function(a, b)
        local levelA = GodSystem.getAutoRecyclerItemLevel(a.item)
        local levelB = GodSystem.getAutoRecyclerItemLevel(b.item)
        if levelA ~= levelB then
            return levelA > levelB
        end
        return gsItemInventoryCount(a.item) > gsItemInventoryCount(b.item)
    end)
    local primary = candidates[1]
    local data = GodSystem.getData()
    local level = math.max(GodSystem.getAutoRecyclerItemLevel(primary.item), GodSystem.getAutoRecyclerLevel())
    data.autoRecyclerClaimed = true
    GodSystemTerminalUpgrades.setLevel(data, "capacity", level)
    GodSystem.markAutoRecyclerContainer(primary.item)
    return primary
end

function GodSystem.refreshAutoRecyclerContainers(forceSearch)
    local entry = GodSystem.getAutoRecyclerContainer(forceSearch == true)
    return entry
end

function GodSystem.getShopRewardText(shopItem)
    if not shopItem then
        return ""
    end
    local parts = {}
    local items = shopItem.items or {}
    for i = 1, #items do
        local name = GodSystem.getItemDisplayName(items[i].fullType)
        if not GodSystem.itemExists(items[i].fullType) then
            name = GodSystem.text("Detail_MissingItem", "Missing: ") .. tostring(items[i].fullType)
        end
        table.insert(parts, name .. " x" .. tostring(items[i].count or 1))
    end
    if #parts == 0 then
        return GodSystem.text("None_Item", "No item")
    end
    return table.concat(parts, ", ")
end

function GodSystem.getShopBuyReference(fullType)
    local best = nil
    for i = 1, #GodSystemConfig.ShopItems do
        local shopItem = GodSystemConfig.ShopItems[i]
        local items = shopItem.items or {}
        for j = 1, #items do
            if items[j].fullType == fullType then
                local unitPrice = GodSystem.getShopItemUnitPrice(shopItem)
                if not best or unitPrice < best.price then
                    best = {
                        label = GodSystem.getShopLabel(shopItem),
                        price = unitPrice,
                    }
                end
            end
        end
    end
    local unlocked = GodSystem.getData().unlockedShopItems or {}
    for _, autoItem in pairs(unlocked) do
        if autoItem and autoItem.fullType == fullType then
            local buyPrice = GodSystem.getAutoShopBuyPriceForItem(fullType, autoItem.sellPrice or 1)
            if not best or buyPrice < best.price then
                best = {
                    label = autoItem.label or fullType,
                    price = buyPrice,
                }
            end
        end
    end
    return best
end

function GodSystem.getConfiguredShopPriceForFullType(fullType)
    local best = nil
    for i = 1, #GodSystemConfig.ShopItems do
        local shopItem = GodSystemConfig.ShopItems[i]
        local items = shopItem.items or {}
        for j = 1, #items do
            if items[j].fullType == fullType then
                local price = GodSystem.getShopItemUnitPrice(shopItem)
                if price > 0 and (not best or price < best) then
                    best = price
                end
            end
        end
    end
    return best
end

function GodSystem.getAutoShopBuyPrice(sellValue)
    sellValue = math.max(1, math.floor(tonumber(sellValue) or 1))
    local multiplied = sellValue * (GodSystemConfig.AutoShopBuyMultiplier or 3)
    local marked = sellValue + (GodSystemConfig.AutoShopMinMarkup or 10)
    return math.max(multiplied, marked)
end

function GodSystem.getScriptItemCategory(fullType)
    local scriptItem = getScriptManager and getScriptManager() and getScriptManager():FindItem(fullType) or nil
    if not scriptItem then
        return ""
    end
    local methods = { "getTypeString", "getDisplayCategory", "getType", "getCategory" }
    for i = 1, #methods do
        local methodName = methods[i]
        if scriptItem[methodName] then
            local ok, value = pcall(function() return scriptItem[methodName](scriptItem) end)
            if ok and value then
                return tostring(value)
            end
        end
    end
    return ""
end

function GodSystem.getScriptItemDisplayCategory(fullType)
    local scriptItem = getScriptManager and getScriptManager() and getScriptManager():FindItem(fullType) or nil
    if not scriptItem then
        return ""
    end
    local methods = { "getDisplayCategory", "getTypeString", "getType", "getCategory" }
    for i = 1, #methods do
        local methodName = methods[i]
        if scriptItem[methodName] then
            local ok, value = pcall(function() return scriptItem[methodName](scriptItem) end)
            if ok and value and tostring(value) ~= "" then
                return tostring(value)
            end
        end
    end
    return ""
end

local function gsTrim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function GodSystem.getShopPrimaryFullType(shopItem)
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

local function gsShopCategoryFromRaw(raw)
    raw = gsTrim(raw)
    if raw == "" then
        return "other", GodSystem.text("ShopCategory_Other", "Other")
    end

    local compact = string.lower(raw):gsub("[%s_%-%./\\|>]+", "")
    if compact == "" then
        return "other", GodSystem.text("ShopCategory_Other", "Other")
    end

    if compact == "unlocked" then
        return "unlocked", GodSystem.text("Group_Unlocked", "Unlocked")
    end
    if string.find(compact, "accessory", 1, true) or string.find(compact, "jewelry", 1, true) then
        return "accessory", GodSystem.text("ShopCategory_Accessory", "Accessory")
    end
    if string.find(compact, "casing", 1, true) or string.find(compact, "casings", 1, true) then
        return "casing", GodSystem.text("ShopCategory_Casing", "Casing")
    end
    if string.find(compact, "security", 1, true) then
        return "security", GodSystem.text("ShopCategory_Security", "Security")
    end
    if string.find(compact, "firstaid", 1, true) or string.find(compact, "medical", 1, true) then
        return "medical", GodSystem.text("ShopCategory_Medical", "Medical")
    end
    if string.find(compact, "beverage", 1, true) or string.find(compact, "water", 1, true) or string.find(compact, "drink", 1, true) then
        return "drink", GodSystem.text("ShopCategory_Drink", "Drink")
    end
    if string.find(compact, "food", 1, true) or string.find(compact, "canned", 1, true) then
        return "food", GodSystem.text("ShopCategory_Food", "Food")
    end
    if string.find(compact, "container", 1, true) then
        return "container", GodSystem.text("ShopCategory_Container", "Container")
    end
    if string.find(compact, "cooking", 1, true) or string.find(compact, "utensil", 1, true) then
        return "cooking", GodSystem.text("ShopCategory_Cooking", "Cooking")
    end
    if string.find(compact, "firesource", 1, true) or string.find(compact, "fire", 1, true) then
        return "fire", GodSystem.text("ShopCategory_Fire", "Fire")
    end
    if string.find(compact, "tool", 1, true) or string.find(compact, "maintenance", 1, true) then
        return "tool", GodSystem.text("ShopCategory_Tool", "Tool")
    end
    if string.find(compact, "material", 1, true) then
        return "material", GodSystem.text("ShopCategory_Material", "Material")
    end
    if string.find(compact, "ammo", 1, true) or string.find(compact, "bullet", 1, true) or string.find(compact, "shell", 1, true) then
        return "ammo", GodSystem.text("ShopCategory_Ammo", "Ammo")
    end
    if string.find(compact, "weapon", 1, true) then
        return "weapon", GodSystem.text("ShopCategory_Weapon", "Weapon")
    end
    if string.find(compact, "cloth", 1, true) or string.find(compact, "clothing", 1, true) then
        return "clothing", GodSystem.text("ShopCategory_Clothing", "Clothing")
    end
    if string.find(compact, "literature", 1, true) or string.find(compact, "book", 1, true) or string.find(compact, "map", 1, true) then
        return "literature", GodSystem.text("ShopCategory_Literature", "Literature")
    end
    if string.find(compact, "drainable", 1, true) then
        return "drainable", GodSystem.text("ShopCategory_Drainable", "Drainable")
    end
    if string.find(compact, "elect", 1, true) or string.find(compact, "radio", 1, true) then
        return "electronics", GodSystem.text("ShopCategory_Electronics", "Electronics")
    end
    if string.find(compact, "farm", 1, true) or string.find(compact, "seed", 1, true) then
        return "farming", GodSystem.text("ShopCategory_Farming", "Farming")
    end
    if string.find(compact, "vehicle", 1, true) or string.find(compact, "mechanic", 1, true) then
        return "vehicle", GodSystem.text("ShopCategory_Vehicle", "Vehicle")
    end
    if string.find(compact, "key", 1, true) then
        return "key", GodSystem.text("ShopCategory_Key", "Key")
    end
    if compact == "normal" or compact == "survival" then
        return compact, compact == "survival" and GodSystem.text("ShopCategory_Survival", "Survival") or GodSystem.text("ShopCategory_Other", "Other")
    end

    return compact, raw
end

function GodSystem.getShopPrimaryCategory(shopItem)
    local fullType = GodSystem.getShopPrimaryFullType(shopItem)
    local raw = fullType and GodSystem.getScriptItemDisplayCategory(fullType) or ""
    if raw == "" then
        raw = GodSystem.getShopGroup(shopItem)
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

function GodSystem.getShopCategoryLabel(categoryKey)
    categoryKey = tostring(categoryKey or "all")
    if categoryKey == "" or categoryKey == "all" then
        return GodSystem.text("ShopCategory_All", "All categories")
    end
    local _, label = gsShopCategoryFromRaw(categoryKey)
    return label or categoryKey
end

function GodSystem.getPricingCategoryKey(fullType, item)
    if fullType and GodSystemConfig.VanillaItemPriceCategories and GodSystemConfig.VanillaItemPriceCategories[fullType] then
        return GodSystemAdminConfig.applyCategory(fullType, GodSystemConfig.VanillaItemPriceCategories[fullType])
    end
    local raw = fullType and GodSystem.getScriptItemDisplayCategory(fullType) or ""
    if raw == "" and item and item.getCategory then
        local ok, value = pcall(function() return item:getCategory() end)
        if ok and value then
            raw = tostring(value)
        end
    end
    local key = select(1, gsShopCategoryFromRaw(raw))
    key = tostring(key or "normal"):lower():gsub("[^a-z0-9_]+", "_")
    if key == "" or key == "unlocked" then
        key = "normal"
    end
    return GodSystemAdminConfig.applyCategory(fullType, key)
end

function GodSystem.getCategoryFallbackBuyPrice(categoryKey, fullType)
    local prices = GodSystemConfig.ModCategoryBuyPrices or {}
    local key = tostring(categoryKey or "normal")
    local price = prices[key] or prices.normal or 120
    local moduleName = gsGetModuleName(fullType)
    if moduleName and not (GodSystemConfig.RecycleDefaultAllowedModules or {})[moduleName] then
        if key == "weapon" then
            price = math.max(price, GodSystemConfig.AutoShopModWeaponMinBuy or price)
        elseif key == "ammo" then
            price = math.max(price, GodSystemConfig.AutoShopModAmmoMinBuy or price)
        elseif key == "clothing" then
            price = math.max(price, GodSystemConfig.AutoShopModClothingMinBuy or price)
        else
            price = math.max(price, GodSystemConfig.AutoShopModMinBuy or price)
        end
    end
    return math.max(1, math.floor(tonumber(price) or 1))
end

function GodSystem.getItemPriceInfo(fullType, item)
    if not fullType then
        return { buyPrice = 0, sellPrice = 0, category = "normal", source = "missing" }
    end
    local categoryKey = GodSystem.getPricingCategoryKey(fullType, item)
    local buyPrice = nil
    local source = "fallback"
    if GodSystemConfig.VanillaItemBuyPrices and GodSystemConfig.VanillaItemBuyPrices[fullType] then
        buyPrice = GodSystemConfig.VanillaItemBuyPrices[fullType]
        source = "vanilla"
    else
        buyPrice = GodSystem.getCategoryFallbackBuyPrice(categoryKey, fullType)
    end
    buyPrice = math.max(1, math.floor(tonumber(buyPrice) or 1))
    local baseBuyPrice = buyPrice
    local moduleName = gsGetModuleName(fullType)
    local ratio = GodSystemConfig.RecycleSellRatio or 0.05
    if moduleName and not (GodSystemConfig.RecycleDefaultAllowedModules or {})[moduleName] then
        ratio = GodSystemConfig.ModItemSellRatio or ratio
    end
    buyPrice = GodSystemAdminConfig.applyShopBuyPrice(fullType, baseBuyPrice)
    local sellPrice = GodSystemAdminConfig.applySellPrice(fullType, math.max(1, math.floor(baseBuyPrice * ratio)))
    return {
        buyPrice = buyPrice,
        sellPrice = sellPrice,
        category = categoryKey,
        source = source,
    }
end

function GodSystem.getItemBuyPrice(fullType, item)
    return (GodSystem.getItemPriceInfo(fullType, item).buyPrice or 0)
end

function GodSystem.getItemSellPrice(fullType, item)
    return (GodSystem.getItemPriceInfo(fullType, item).sellPrice or 0)
end

function GodSystem.getShopItemUnitPrice(shopItem)
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
            total = total + (GodSystem.getItemBuyPrice(fullType) * count)
        end
        if total > 0 then
            return total
        end
    end
    return math.max(0, math.floor(tonumber(shopItem.price) or 0))
end

function GodSystem.getAutoShopBuyPriceForItem(fullType, sellValue)
    if fullType then
        local info = GodSystem.getItemPriceInfo(fullType)
        if info and (info.buyPrice or 0) > 0 then
            return info.buyPrice
        end
    end
    local price = GodSystem.getAutoShopBuyPrice(sellValue)
    local moduleName = gsGetModuleName(fullType)
    if moduleName and not (GodSystemConfig.RecycleDefaultAllowedModules or {})[moduleName] then
        local minPrice = GodSystemConfig.AutoShopModMinBuy or 200
        local category = GodSystem.getScriptItemCategory(fullType)
        if category == "Weapon" or string.find(category, "Weapon", 1, true) then
            minPrice = GodSystemConfig.AutoShopModWeaponMinBuy or minPrice
        elseif category == "Ammo" or string.find(category, "Ammo", 1, true) then
            minPrice = GodSystemConfig.AutoShopModAmmoMinBuy or minPrice
        elseif category == "Clothing" or string.find(category, "Clothing", 1, true) then
            minPrice = GodSystemConfig.AutoShopModClothingMinBuy or minPrice
        end
        price = math.max(price, minPrice)
    end
    local configuredPrice = GodSystem.getConfiguredShopPriceForFullType(fullType)
    if configuredPrice then
        price = math.max(price, configuredPrice)
    end
    return GodSystemAdminConfig.applyShopBuyPrice(fullType, price)
end

function GodSystem.getAutoShopListOnlyCost(fullType, sellValue)
    local baseSell = math.max(1, math.floor(tonumber(sellValue) or 1))
    local buyPrice = math.max(1, math.floor(tonumber(GodSystem.getAutoShopBuyPriceForItem(fullType, baseSell)) or 1))
    local ratio = tonumber(GodSystemConfig.AutoShopListOnlyCostRatio) or 0.5
    local minCost = math.max(0, math.floor(tonumber(GodSystemConfig.AutoShopListOnlyMinCost) or 50))
    local cost = math.ceil(buyPrice * math.max(0, ratio))
    return math.max(minCost, cost), buyPrice
end

function GodSystem.isLooseAmmoRecycleItem(fullType, item)
    if not fullType then
        return false
    end
    local text = tostring(fullType)
    if string.find(text, "Box", 1, true)
        or string.find(text, "Carton", 1, true)
        or string.find(text, "Clip", 1, true)
        or string.find(text, "Magazine", 1, true)
        or string.find(text, "AmmoBox", 1, true)
        or string.find(text, "Strap", 1, true)
        or string.find(text, "Case", 1, true)
        or string.find(text, "Bag_", 1, true) then
        return false
    end
    local lowerText = string.lower(text)
    local looksLikeLooseAmmoName = string.find(lowerText, "bullet", 1, true)
        or string.find(lowerText, "shell", 1, true)
        or string.find(lowerText, "ammo", 1, true)
        or string.find(lowerText, "round", 1, true)
        or string.find(lowerText, "cartridge", 1, true)
        or string.find(lowerText, "caliber", 1, true)
        or string.find(lowerText, "9mm", 1, true)
        or string.find(lowerText, "308", 1, true)
        or string.find(lowerText, "556", 1, true)
        or string.find(lowerText, "3030", 1, true)
    if not looksLikeLooseAmmoName then
        return false
    end
    local category = item and item.getCategory and item:getCategory() or nil
    if category == "Ammo" then
        return true
    end
    local configuredCategory = GodSystemConfig.VanillaItemPriceCategories and GodSystemConfig.VanillaItemPriceCategories[fullType] or nil
    if configuredCategory == "ammo" then
        return true
    end
    if GodSystem.getPricingCategoryKey and GodSystem.getPricingCategoryKey(fullType, item) == "ammo" then
        return true
    end
    if string.find(text, "Bullets", 1, true) or string.find(text, "ShotgunShells", 1, true) then
        return true
    end
    return false
end

function GodSystem.getRecycleUnitDivisor(fullType, item)
    if not fullType then
        return 1
    end
    if GodSystem.isLooseAmmoRecycleItem(fullType, item) then
        return 1
    end
    local text = tostring(fullType)
    if string.find(text, "ShotgunShells", 1, true) and not string.find(text, "Box", 1, true) then
        return GodSystemConfig.LooseShellRecycleDivisor or 5
    end
    if string.find(text, "Bullets", 1, true) and not string.find(text, "Box", 1, true) then
        return GodSystemConfig.LooseAmmoRecycleDivisor or 10
    end
    if string.find(text, "Nails", 1, true) and not string.find(text, "Box", 1, true) then
        return GodSystemConfig.SmallUnitRecycleDivisor or 10
    end
    if string.find(text, "Screws", 1, true) and not string.find(text, "Box", 1, true) then
        return GodSystemConfig.SmallUnitRecycleDivisor or 10
    end
    local category = item and item.getCategory and item:getCategory() or nil
    if category == "Ammo" then
        return GodSystemConfig.LooseAmmoRecycleDivisor or 10
    end
    return 1
end

function GodSystem.calculateRecyclePayout(fullType, rawValue, removedCount)
    rawValue = math.floor(tonumber(rawValue) or 0)
    if rawValue <= 0 then
        return 0
    end
    local divisor = GodSystem.getRecycleUnitDivisor(fullType)
    if divisor > 1 then
        return math.floor(rawValue / divisor)
    end
    return rawValue
end

function GodSystem.getShopLabel(shopItem)
    if not shopItem then
        return GodSystem.text("Shop_Missing_Label", "Unknown")
    end
    if shopItem.unlocked then
        return GodSystem.getUnlockedShopLabel(shopItem.fullType, shopItem)
    end
    local fallback = shopItem.id or "Shop item"
    if shopItem.items and #shopItem.items == 1 then
        fallback = GodSystem.getItemDisplayName(shopItem.items[1].fullType, fallback)
    end
    return GodSystem.text("Shop_" .. tostring(shopItem.id) .. "_Label", fallback)
end

function GodSystem.getUnlockedShopLabel(fullType, item)
    local localized = GodSystem.getItemDisplayName(fullType)
    local label = item and item.label or nil
    if localized and localized ~= "" and localized ~= fullType then
        return localized
    end
    if label and tostring(label) ~= "" and tostring(label) ~= tostring(fullType or "") then
        return tostring(label)
    end
    return fullType or (item and item.id) or GodSystem.text("Shop_Unlocked_Label", "Unlocked item")
end

function GodSystem.getShopGroup(shopItem)
    if not shopItem then
        return GodSystem.text("Group_Shop", "Shop")
    end
    if shopItem.unlocked then
        return GodSystem.text("Group_Unlocked", "Unlocked")
    end
    return GodSystem.text("Shop_" .. tostring(shopItem.id) .. "_Group", shopItem.group or "Shop")
end

function GodSystem.getShopDescription(shopItem)
    if not shopItem then
        return ""
    end
    if shopItem.unlocked then
        return GodSystem.text("Shop_Unlocked_Description", "This item was unlocked by recycling it.")
    end
    return GodSystem.text("Shop_" .. tostring(shopItem.id) .. "_Description", shopItem.description or "")
end

function GodSystem.getTaskTitle(task)
    if not task then
        return GodSystem.text("Task_Missing_Title", "Task")
    end
    local id = task.sourceId or task.id or "missing"
    return GodSystem.text("Task_" .. tostring(id) .. "_Title", task.title or id)
end

function GodSystem.getTaskDescription(task)
    if not task then
        return ""
    end
    local id = task.sourceId or task.id or "missing"
    return GodSystem.text("Task_" .. tostring(id) .. "_Description", task.description or "")
end

function GodSystem.getTaskKindLabel(task)
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
    return GodSystem.text("TaskKind_" .. tostring(kind), fallback[kind] or tostring(kind or "Task"))
end

function GodSystem.getTaskDifficulty(task)
    local penalty = math.max(0, math.floor(tonumber(task and task.penaltyPoints) or 0))
    if penalty >= 150 then return "D4" end
    if penalty >= 80 then return "D3" end
    if penalty >= 30 then return "D2" end
    return "D1"
end

function GodSystem.getTaskListTitle(task)
    if not task then
        return GodSystem.text("Task_Missing_Title", "Task")
    end
    return "[" .. GodSystem.getTaskKindLabel(task) .. "][" .. GodSystem.getTaskDifficulty(task) .. "] " .. GodSystem.getTaskTitle(task)
end

function GodSystem.getTaskListStatusLine(task)
    if not task then
        return ""
    end
    local progress = math.min(GodSystem.getTaskProgress(task), math.max(1, math.floor(tonumber(task.target) or 1)))
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    local parts = { tostring(progress) .. "/" .. tostring(target) }
    if task.status == "active" then
        table.insert(parts, GodSystem.text("Short_Remain", "Left") .. tostring(GodSystem.getRemainingHours(task)) .. GodSystem.text("Unit_Hour", "h"))
    else
        table.insert(parts, GodSystem.getTaskStatusText(task))
    end
    return table.concat(parts, "  ")
end

function GodSystem.isAutoShopUnlockAllowed(fullType)
    if not GodSystemConfig.AutoUnlockShopFromRecycle then
        return false
    end
    if GodSystemAdminConfig.isShopItemEnabled(fullType, true) == false or GodSystemAdminConfig.isRecycleItemEnabled(fullType, true) == false then
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

function GodSystem.getConfiguredShopKeySet()
    return GodSystem.configuredShopKeySet or {}
end

function GodSystem.unlockAutoShopItem(fullType, label, sellValue, itemOrSprite)
    if not GodSystem.isAutoShopUnlockAllowed(fullType) then
        return false
    end

    local data = GodSystem.getData()
    data.unlockedShopItems = data.unlockedShopItems or {}
    local baseSell = math.max(1, math.floor(tonumber(sellValue) or 1))
    local buyPrice = GodSystem.getAutoShopBuyPriceForItem(fullType, baseSell)
    local worldSprite = GodSystemShopVariants.getWorldSprite(itemOrSprite)
    local variantKey = GodSystemShopVariants.getKey(fullType, worldSprite)
    local known, source = GodSystemShopVariants.isListingKnown(data, GodSystem.getConfiguredShopKeySet(), variantKey)
    if known then return false, source, variantKey end

    data.unlockedShopItems[variantKey] = {
        fullType = fullType,
        worldSprite = worldSprite,
        variantKey = variantKey,
        module = gsGetModuleName(fullType),
        label = label or GodSystem.getItemDisplayName(fullType),
        sellPrice = baseSell,
        buyPrice = buyPrice,
        unlockedAt = math.floor(gsNowHours()),
        hidden = false,
    }
    GodSystem.save()
    return true, "created", variantKey
end

function GodSystem.listOnlyAutoShopItem(fullType, itemId)
    if GodSystem.isFeatureEnabled("EnableRecycle") == false or GodSystem.isFeatureEnabled("EnableShop") == false then
        GodSystem.notify(GodSystem.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end
    if not fullType or fullType == "" then
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    if not GodSystem.isAutoShopUnlockAllowed(fullType) then
        GodSystem.notify(GodSystem.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end

    local data = GodSystem.getData()
    if itemId == nil or tostring(itemId or "") == "" then
        GodSystem.notify(GodSystem.text("Notify_ListItemChanged", "The selected item changed; reopen the recycle page"))
        return false
    end
    local item = gsInventoryItemById(itemId)
    if item and item.getFullType and item:getFullType() ~= fullType then item = nil end
    if not item then
        GodSystem.notify(GodSystem.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end

    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local known, source = GodSystemShopVariants.isListingKnown(data, GodSystem.getConfiguredShopKeySet(), variantKey)
    if known then
        if source == "configured" then
            GodSystem.notify(GodSystem.text("Notify_ShopConfiguredAlreadyListed", "This built-in shop item is already listed."))
        elseif data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            GodSystem.notify(GodSystem.text("Notify_ShopHiddenAlreadyListed", "This item is listed but hidden. Restore it from hidden management."))
        else
            GodSystem.notify(GodSystem.text("Notify_ListOnlyAlreadyUnlocked", "This item is already listed."))
        end
        return false
    end
    if not GodSystem.canContextRecycleItem(item) then
        GodSystem.notify(GodSystem.text("Notify_ListOnlyDisabled", "This item cannot be listed."))
        return false
    end
    local label = (item and item.getDisplayName and item:getDisplayName()) or GodSystem.getItemDisplayName(fullType)
    local sellValue = GodSystem.getItemSellPrice(fullType, item)
    local cost, buyPrice = GodSystem.getAutoShopListOnlyCost(fullType, sellValue)
    if GodSystem.getSpendableBalance() < cost then
        GodSystem.notify(GodSystem.text("Notify_ListOnlyInsufficient", "Not enough system coins to list this item."))
        return false
    end
    local paid, fromBank, fromCash = GodSystem.spendCurrency(cost)
    if not paid then
        GodSystem.notify(GodSystem.text("Notify_ListOnlyInsufficient", "Not enough system coins to list this item."))
        return false
    end
    local created, failureSource = GodSystem.unlockAutoShopItem(fullType, label, sellValue, item)
    if not created then
        GodSystem.refundCurrencySources(fromBank, fromCash)
        if failureSource == "configured" then
            GodSystem.notify(GodSystem.text("Notify_ShopConfiguredAlreadyListed", "This built-in shop item is already listed."))
        elseif data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            GodSystem.notify(GodSystem.text("Notify_ShopHiddenAlreadyListed", "This item is listed but hidden. Restore it from hidden management."))
        else
            GodSystem.notify(GodSystem.text("Notify_ListOnlyAlreadyUnlocked", "This item is already listed."))
        end
        return false
    end

    gsAppendHistory(data, { kind = "shop", text = gsFormatText(GodSystem.text("History_ListOnlyAutoShop", "Listed {1}, fee {2} coins."), { label, cost, buyPrice }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text("Notify_ListOnlySuccess", "Listed {1}, fee {2} coins."), { label, cost, buyPrice }))
    return true
end

function GodSystem.getUnlockedShopItemsList(includeHidden)
    local data = GodSystem.getData()
    local result = {}
    local rows = GodSystemShopVariants.getUnlockedRows(data, includeHidden)
    for i = 1, #rows do
        local item = rows[i]
        local variantKey = item.variantKey or GodSystemShopVariants.getKey(item.fullType, item.worldSprite)
        local fullType = item.fullType or variantKey
        if GodSystem.itemExists(fullType) then
            table.insert(result, {
                id = "unlocked_" .. variantKey,
                fullType = fullType,
                worldSprite = item.worldSprite,
                variantKey = variantKey,
                label = GodSystem.getUnlockedShopLabel(fullType, item),
                group = "unlocked",
                price = GodSystem.getAutoShopBuyPriceForItem(fullType, item.sellPrice or 1),
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

function GodSystem.setShopItemHidden(variantKey, hidden)
    if not variantKey then
        GodSystem.notify(GodSystem.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local data = GodSystem.getData()
    local ok, changed, item = GodSystemShopVariants.setHidden(data, variantKey, hidden)
    if not ok or not item then
        GodSystem.notify(GodSystem.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local label = item.label or GodSystem.getItemDisplayName(item.fullType or variantKey)
    local targetHidden = hidden == true
    if changed then
        local historyKey = targetHidden and "History_ShopItemHidden" or "History_ShopItemVisible"
        local historyFallback = targetHidden and "Hidden shop item: " or "Restored shop item: "
        gsAppendHistory(data, { kind = "shop", text = GodSystem.text(historyKey, historyFallback) .. tostring(label) })
        GodSystem.save()
    end
    local notifyKey = targetHidden and "Notify_ShopItemHidden" or "Notify_ShopItemVisible"
    local notifyFallback = targetHidden and "Hidden shop item: " or "Restored shop item: "
    GodSystem.notify(GodSystem.text(notifyKey, notifyFallback) .. tostring(label))
    return true
end

function GodSystem.deleteShopItem(variantKey)
    if not variantKey then
        GodSystem.notify(GodSystem.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
        return false
    end
    local data = GodSystem.getData()
    local ok, item = GodSystemShopVariants.deleteUnlocked(data, variantKey)
    if not ok or not item then
        GodSystem.notify(GodSystem.text("Notify_ShopItemMissing", "The player-listed item no longer exists."))
        return false
    end
    local label = item.label or GodSystem.getItemDisplayName(item.fullType or variantKey)
    gsAppendHistory(data, { kind = "shop", text = GodSystem.text("History_ShopItemDeleted", "Delisted shop item: ") .. tostring(label) })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_ShopItemDeleted", "Delisted shop item: ") .. tostring(label))
    return true
end

function GodSystem.getConfiguredShopFullTypeSet()
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

local function gsLotteryNormalizeCategory(categoryKey)
    categoryKey = tostring(categoryKey or "all"):lower():gsub("[^a-z0-9_]+", "_")
    if categoryKey == "" then
        categoryKey = "all"
    end
    return categoryKey
end

function GodSystem.getLotteryPrice(categoryKey)
    categoryKey = gsLotteryNormalizeCategory(categoryKey)
    if categoryKey == "all" then
        return math.max(1, math.floor(tonumber(GodSystemConfig.LotteryAllPrice) or 100))
    end
    local prices = GodSystemConfig.LotteryCategoryPrices or {}
    return math.max(1, math.floor(tonumber(prices[categoryKey] or prices.normal or 60) or 60))
end

local function gsLotteryAddCandidate(result, seen, fullType, label)
    fullType = tostring(fullType or "")
    if fullType == "" or seen[fullType] then
        return
    end
    if (GodSystemConfig.LotteryBlacklist or {})[fullType] then
        return
    end
    if not GodSystem.itemExists(fullType) then
        return
    end
    if not GodSystem.isEconomicItemAllowed(fullType, "lottery") then
        return
    end
    if GodSystemAdminConfig.isLotteryItemEnabled(fullType, true) == false then
        return
    end
    local info = GodSystem.getItemPriceInfo(fullType)
    local categoryKey = gsLotteryNormalizeCategory(info and info.category or GodSystem.getPricingCategoryKey(fullType) or "normal")
    if categoryKey == "all" then
        categoryKey = "normal"
    end
    seen[fullType] = true
    result[#result + 1] = {
        fullType = fullType,
        label = GodSystem.getItemDisplayName(fullType, label or fullType),
        categoryKey = categoryKey,
        categoryLabel = GodSystem.getShopCategoryLabel(categoryKey),
        buyPrice = info and info.buyPrice or GodSystem.getItemBuyPrice(fullType),
        sellPrice = info and info.sellPrice or GodSystem.getItemSellPrice(fullType),
        lotteryCost = GodSystem.getLotteryPrice(categoryKey),
    }
end

function GodSystem.getLotteryCandidates(categoryKey)
    categoryKey = gsLotteryNormalizeCategory(categoryKey)
    local result = {}
    local seen = {}

    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local shopItem = GodSystemConfig.ShopItems[i]
        for j = 1, #(shopItem and shopItem.items or {}) do
            local item = shopItem.items[j]
            gsLotteryAddCandidate(result, seen, item and item.fullType, shopItem and shopItem.label)
        end
    end

    local data = GodSystem.getData()
    for variantKey, item in pairs(data.unlockedShopItems or {}) do
        gsLotteryAddCandidate(result, seen, item and item.fullType or variantKey, item and item.label)
    end

    for fullType, _ in pairs(GodSystemConfig.VanillaItemBuyPrices or {}) do
        gsLotteryAddCandidate(result, seen, fullType, nil)
    end

    local filtered = {}
    for i = 1, #result do
        if categoryKey == "all" or result[i].categoryKey == categoryKey then
            filtered[#filtered + 1] = result[i]
        end
    end

    table.sort(filtered, function(a, b)
        if tostring(a.categoryKey) ~= tostring(b.categoryKey) then
            return tostring(a.categoryKey) < tostring(b.categoryKey)
        end
        return tostring(a.label or a.fullType) < tostring(b.label or b.fullType)
    end)
    return filtered
end

function GodSystem.getLotteryCategories()
    local candidates = GodSystem.getLotteryCandidates("all")
    local counts = {}
    for i = 1, #candidates do
        local key = candidates[i].categoryKey or "normal"
        counts[key] = (counts[key] or 0) + 1
    end
    local result = {}
    for key, count in pairs(counts) do
        result[#result + 1] = {
            key = key,
            label = GodSystem.getShopCategoryLabel(key),
            lotteryCount = count,
            price = GodSystem.getLotteryPrice(key),
        }
    end
    table.sort(result, function(a, b)
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)
    return result
end

function GodSystem.getLotteryPreview(categoryKey)
    categoryKey = gsLotteryNormalizeCategory(categoryKey)
    local candidates = GodSystem.getLotteryCandidates(categoryKey)
    return {
        categoryKey = categoryKey,
        categoryLabel = GodSystem.getShopCategoryLabel(categoryKey),
        count = #candidates,
        price = GodSystem.getLotteryPrice(categoryKey),
        maxCount = math.max(1, math.floor(tonumber(GodSystemConfig.LotteryCustomMaxCount) or 50)),
        candidates = candidates,
    }
end

local function gsGroupLotteryResults(items)
    local grouped = {}
    local order = {}
    for i = 1, #(items or {}) do
        local item = items[i]
        local key = tostring(item.fullType or item.label or i)
        if not grouped[key] then
            grouped[key] = {
                fullType = item.fullType,
                label = item.label or item.fullType,
                count = 0,
            }
            order[#order + 1] = key
        end
        grouped[key].count = grouped[key].count + math.max(1, math.floor(tonumber(item.count) or 1))
    end
    local result = {}
    for i = 1, #order do
        result[#result + 1] = grouped[order[i]]
    end
    table.sort(result, function(a, b)
        return tostring(a.label or a.fullType) < tostring(b.label or b.fullType)
    end)
    return result
end

function GodSystem.performLotteryDraw(mode, categoryKey, count)
    if GodSystem.isFeatureEnabled("EnableShopLottery") == false then
        GodSystem.notify(GodSystem.text("Notify_LotteryDisabled", "Lottery disabled"))
        return false
    end
    mode = tostring(mode or "all")
    categoryKey = gsLotteryNormalizeCategory(mode == "all" and "all" or categoryKey)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local maxCount = math.max(1, math.floor(tonumber(GodSystemConfig.LotteryCustomMaxCount) or 50))
    if count > maxCount then
        GodSystem.notify(GodSystem.text("Notify_LotteryCountTooHigh", "Draw count is too high"))
        return false
    end
    if categoryKey == "all" then
        mode = "all"
    else
        mode = "category"
    end

    local candidates = GodSystem.getLotteryCandidates(categoryKey)
    if #candidates <= 0 then
        GodSystem.notify(GodSystem.text("Notify_LotteryNoCandidate", "No lottery item in this pool"))
        return false
    end

    local unitPrice = GodSystem.getLotteryPrice(categoryKey)
    local totalCost = unitPrice * count
    if not GodSystem.canAfford(totalCost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local drawn = {}
    for i = 1, count do
        local picked = candidates[gsRandomIndex(#candidates)]
        if not picked or not picked.fullType then
            GodSystem.notify(GodSystem.text("Notify_LotteryNoCandidate", "No lottery item in this pool"))
            return false
        end
        drawn[#drawn + 1] = {
            fullType = picked.fullType,
            label = picked.label,
            categoryKey = picked.categoryKey,
            count = 1,
        }
    end

    local addedItems = {}
    for i = 1, #drawn do
        local okGive, added = GodSystem.giveItem(drawn[i].fullType, 1)
        if not okGive then
            GodSystem.removeAddedItems(addedItems)
            GodSystem.notify(GodSystem.text("Error_ItemGiveFailed", "Item grant failed: ") .. tostring(drawn[i].fullType))
            return false
        end
        for j = 1, #(added or {}) do
            addedItems[#addedItems + 1] = added[j]
        end
    end

    local paid = GodSystem.spendCurrency(totalCost)
    if not paid then
        GodSystem.removeAddedItems(addedItems)
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local data = GodSystem.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + totalCost
    data.stats.lotteryDraws = (data.stats.lotteryDraws or 0) + count
    local grouped = gsGroupLotteryResults(drawn)
    gsAppendHistory(data, { kind = "shop", text = GodSystem.text("History_LotteryDraw", "Lottery draw: ") .. tostring(count) .. " -" .. tostring(totalCost) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    local payload = {
        kind = "lotteryDraw",
        mode = mode,
        categoryKey = categoryKey,
        categoryLabel = GodSystem.getShopCategoryLabel(categoryKey),
        count = count,
        unitPrice = unitPrice,
        totalCost = totalCost,
        items = drawn,
        groupedItems = grouped,
    }
    GodSystem.notify(GodSystem.text("Notify_LotteryDrawComplete", "Lottery complete") .. " -" .. tostring(totalCost) .. GodSystem.text("Unit_CoinShort", "c"))
    return true, payload, totalCost
end

function GodSystem.getShopLotteryCost(fullType)
    local sellPrice = GodSystem.getItemSellPrice(fullType)
    local multiplier = tonumber(GodSystemConfig.ShopLotteryCostMultiplier) or 1
    local minCost = math.max(1, math.floor(tonumber(GodSystemConfig.ShopLotteryMinCost) or 1))
    return math.max(minCost, math.floor((sellPrice or 0) * multiplier))
end

function GodSystem.getShopLotteryCandidates(categoryKey)
    categoryKey = tostring(categoryKey or "all")
    if categoryKey == "" then
        categoryKey = "all"
    end
    local prices = GodSystemConfig.VanillaItemBuyPrices or {}
    local categories = GodSystemConfig.VanillaItemPriceCategories or {}
    local data = GodSystem.getData()
    local unlocked = data.unlockedShopItems or {}
    local unlockedTypes = {}
    for variantKey, row in pairs(unlocked) do unlockedTypes[row and row.fullType or variantKey] = true end
    local configured = GodSystem.getConfiguredShopFullTypeSet()
    local result = {}

    for fullType, _ in pairs(prices) do
        if not unlockedTypes[fullType] and not configured[fullType] and GodSystem.isAutoShopUnlockAllowed(fullType) and GodSystemAdminConfig.isLotteryItemEnabled(fullType, true) and GodSystem.itemExists(fullType) and GodSystem.isEconomicItemAllowed(fullType, "lottery") then
            local key = tostring(categories[fullType] or GodSystem.getPricingCategoryKey(fullType) or "normal")
            key = key:lower():gsub("[^a-z0-9_]+", "_")
            if key == "" then
                key = "normal"
            end
            if categoryKey == "all" or key == categoryKey then
                local label = GodSystem.getItemDisplayName(fullType)
                table.insert(result, {
                    fullType = fullType,
                    label = label,
                    categoryKey = key,
                    categoryLabel = GodSystem.getShopCategoryLabel(key),
                    sellPrice = GodSystem.getItemSellPrice(fullType),
                    buyPrice = GodSystem.getItemBuyPrice(fullType),
                    lotteryCost = GodSystem.getShopLotteryCost(fullType),
                })
            end
        end
    end

    table.sort(result, function(a, b)
        if a.categoryKey ~= b.categoryKey then
            return tostring(a.categoryKey) < tostring(b.categoryKey)
        end
        return tostring(a.label or a.fullType) < tostring(b.label or b.fullType)
    end)
    return result
end

local function gsCurrentPosition()
    local player = gsPlayer()
    if not player then
        return nil
    end
    return {
        x = tonumber(player:getX()) or 0,
        y = tonumber(player:getY()) or 0,
        z = tonumber(player:getZ()) or 0,
    }
end

local function gsCopyPosition(pos)
    if not pos then
        return nil
    end
    return {
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
        label = pos.label,
        source = pos.source,
    }
end

function GodSystem.formatPosition(pos)
    if not pos then
        return GodSystem.text("Home_NotSet", "Not set")
    end
    return "X:" .. tostring(math.floor(tonumber(pos.x) or 0)) ..
        " Y:" .. tostring(math.floor(tonumber(pos.y) or 0)) ..
        " Z:" .. tostring(math.floor(tonumber(pos.z) or 0))
end

local function gsSafeBoolCall(object, methodName)
    if not object or not methodName or not object[methodName] then
        return false
    end
    local ok, value = pcall(function() return object[methodName](object) end)
    return ok and value == true
end

local function gsTeleportBlockedReason(player)
    if not player then
        return GodSystem.text("Notify_HomeNoPlayer", "Player not found")
    end
    if player.getVehicle then
        local ok, vehicle = pcall(function() return player:getVehicle() end)
        if ok and vehicle then
            return GodSystem.text("Notify_HomeInVehicle", "Cannot teleport while in a vehicle")
        end
    end
    return nil
end

local function gsGridSquareAt(pos)
    if not pos or not getCell then
        return nil
    end
    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    local x = math.floor(tonumber(pos.x) or 0)
    local y = math.floor(tonumber(pos.y) or 0)
    local z = math.floor(tonumber(pos.z) or 0)
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    if ok then
        return square
    end
    return nil
end

local function gsSquareIsSafe(square)
    if not square then
        return nil
    end
    if gsSafeBoolCall(square, "isSolid") or gsSafeBoolCall(square, "isSolidTrans") then
        return false
    end
    if square.TreatAsSolidFloor then
        local ok, hasFloor = pcall(function() return square:TreatAsSolidFloor() end)
        if ok and hasFloor == false then
            return false
        end
    end
    return true
end

function GodSystem.findSafeTeleportPosition(pos)
    if not pos then
        return nil
    end
    local base = gsCopyPosition(pos)
    local square = gsGridSquareAt(base)
    local safe = gsSquareIsSafe(square)
    if safe == true or safe == nil then
        return base
    end
    local radiusLimit = 4
    for radius = 1, radiusLimit do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local candidate = {
                        x = math.floor(base.x) + dx + 0.5,
                        y = math.floor(base.y) + dy + 0.5,
                        z = base.z,
                    }
                    if gsSquareIsSafe(gsGridSquareAt(candidate)) == true then
                        return candidate
                    end
                end
            end
        end
    end
    return nil
end

function GodSystem.getHomeSystem()
    local data = GodSystem.getData()
    data.homeSystem = data.homeSystem or {}
    data.homeSystem.tempSlots = data.homeSystem.tempSlots or {}
    data.homeSystem.safeZone = data.homeSystem.safeZone or {}
    data.homeSystem.safeZone.level = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.level) or 0))
    data.homeSystem.safeZone.enabled = data.homeSystem.safeZone.enabled == true
    data.homeSystem.safeZone.lastScanHours = tonumber(data.homeSystem.safeZone.lastScanHours) or 0
    data.homeSystem.safeZone.lastNoticeHours = tonumber(data.homeSystem.safeZone.lastNoticeHours) or -999
    data.homeSystem.safeZone.lastCleared = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.lastCleared) or 0))
    data.homeSystem.safeZone.lastClearHour = tonumber(data.homeSystem.safeZone.lastClearHour) or 0
    local limit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, limit do
        data.homeSystem.tempSlots[i] = data.homeSystem.tempSlots[i] or { owned = false, point = nil }
    end
    return data.homeSystem
end

local function gsHomeSafeZoneLevels()
    return GodSystemConfig.HomeSafeZoneLevels or {}
end

local function gsHomeSafeZoneLevelConfig(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    local levels = gsHomeSafeZoneLevels()
    for i = 1, #levels do
        if math.floor(tonumber(levels[i].level) or 0) == level then
            return levels[i]
        end
    end
    return nil
end

local function gsHomeSafeZoneFirstLevel()
    local levels = gsHomeSafeZoneLevels()
    return levels[1]
end

local function gsHomeSafeZoneNextLevel(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    local levels = gsHomeSafeZoneLevels()
    for i = 1, #levels do
        local cfg = levels[i]
        if math.floor(tonumber(cfg.level) or 0) > level then
            return cfg
        end
    end
    return nil
end

local function gsHomeSafeZoneMaxLevel()
    local levels = gsHomeSafeZoneLevels()
    local maxLevel = 0
    for i = 1, #levels do
        maxLevel = math.max(maxLevel, math.floor(tonumber(levels[i].level) or 0))
    end
    return maxLevel
end

function GodSystem.getHomeSafeZoneInfo()
    local home = GodSystem.getHomeSystem()
    local safe = home.safeZone or {}
    local level = math.max(0, math.floor(tonumber(safe.level) or 0))
    local current = gsHomeSafeZoneLevelConfig(level)
    local nextLevel = gsHomeSafeZoneNextLevel(level)
    local firstLevel = gsHomeSafeZoneFirstLevel()
    local clearCost = current and current.clearCost or (firstLevel and firstLevel.clearCost) or 0
    return {
        homeSet = home.home ~= nil,
        center = home.home,
        level = level,
        maxLevel = gsHomeSafeZoneMaxLevel(),
        unlocked = level > 0 and current ~= nil,
        enabled = safe.enabled == true,
        radius = current and (current.radius or 0) or 0,
        clearCost = clearCost or 0,
        unlockCost = firstLevel and (firstLevel.unlockCost or firstLevel.upgradeCost or 0) or 0,
        nextLevel = nextLevel,
        intervalHours = GodSystemConfig.HomeSafeZoneScanIntervalHours or 0.5,
        lastCleared = safe.lastCleared or 0,
        lastClearHour = safe.lastClearHour or 0,
    }
end

function GodSystem.getHomeSafeZoneDetailText(info)
    info = info or GodSystem.getHomeSafeZoneInfo()
    if not info.homeSet then
        return GodSystem.text("HomeSafe_NeedHome", "Set a home first.")
    end
    local center = GodSystem.formatPosition(info.center)
    if not info.unlocked then
        return GodSystem.text("HomeSafe_Locked", "Locked") .. " | " ..
            GodSystem.text("HomeSafe_Center", "Center: ") .. center .. " | " ..
            GodSystem.text("HomeSafe_UnlockCost", "Unlock cost ") .. tostring(info.unlockCost or 0) .. GodSystem.text("Unit_CoinShort", "c")
    end
    local state = info.enabled and GodSystem.text("HomeSafe_Enabled", "Enabled") or GodSystem.text("HomeSafe_Disabled", "Paused")
    local nextText = GodSystem.text("Upgrade_Maxed", "Maxed")
    if info.nextLevel then
        nextText = "Lv." .. tostring(info.nextLevel.level) .. " " ..
            GodSystem.text("HomeSafe_Radius", "Radius ") .. tostring(info.nextLevel.radius or 0) .. " | " ..
            GodSystem.text("Upgrade_Cost", "Cost") .. " " .. tostring(info.nextLevel.upgradeCost or 0) .. GodSystem.text("Unit_CoinShort", "c")
    end
    return state .. " | Lv." .. tostring(info.level) .. "/" .. tostring(info.maxLevel) ..
        " | " .. GodSystem.text("HomeSafe_Center", "Center: ") .. center ..
        " | " .. GodSystem.text("HomeSafe_Radius", "Radius ") .. tostring(info.radius or 0) ..
        " | " .. GodSystem.text("HomeSafe_ClearCost", "Clear cost ") .. tostring(info.clearCost or 0) .. GodSystem.text("Unit_CoinShort", "c") ..
        " | " .. GodSystem.text("HomeSafe_Interval", "Interval ") .. tostring(info.intervalHours or 0.5) .. GodSystem.text("Unit_Hour", "h") ..
        " | " .. GodSystem.text("HomeSafe_LastClear", "Last clear ") .. tostring(info.lastCleared or 0) ..
        " | " .. GodSystem.text("Upgrade_Next", "Next") .. " " .. nextText
end

function GodSystem.getHomeEntries()
    local home = GodSystem.getHomeSystem()
    local entries = {}
    table.insert(entries, { kind = "home", label = GodSystem.text("Home_HomePoint", "Home"), point = home.home })
    local safeInfo = GodSystem.getHomeSafeZoneInfo()
    table.insert(entries, { kind = "safeZone", label = GodSystem.text("HomeSafe_Title", "Home safe zone"), safeZone = safeInfo })
    if home.returnPoint then
        table.insert(entries, { kind = "return", label = GodSystem.text("Home_ReturnPoint", "Return point"), point = home.returnPoint })
    end
    local limit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, limit do
        local slot = home.tempSlots[i] or { owned = false, point = nil }
        table.insert(entries, { kind = "temp", index = i, label = GodSystem.text("Home_TempPoint", "Temp point ") .. tostring(i), owned = slot.owned == true, point = slot.point })
    end
    return entries
end

function GodSystem.getHomeEntryDetail(entry)
    if not entry then
        return ""
    end
    if entry.kind == "home" then
        return GodSystem.formatPosition(entry.point) .. " | " .. GodSystem.text("Home_SetCost", "Set ") .. tostring(GodSystemConfig.HomeSetCost or 100) .. GodSystem.text("Unit_CoinShort", "c") .. " | " .. GodSystem.text("Home_TravelCost", "Travel ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystem.text("Unit_CoinShort", "c")
    end
    if entry.kind == "return" then
        return GodSystem.formatPosition(entry.point) .. " | " .. GodSystem.text("Home_ReturnCost", "Return ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystem.text("Unit_CoinShort", "c")
    end
    if entry.kind == "temp" then
        if not entry.owned then
            return GodSystem.text("Home_TempLocked", "Not purchased") .. " | " .. tostring(GodSystemConfig.TempTeleportSlotCost or 500) .. GodSystem.text("Unit_CoinShort", "c")
        end
        return GodSystem.formatPosition(entry.point) .. " | " .. GodSystem.text("Home_SetCost", "Set ") .. tostring(GodSystemConfig.TempTeleportSetCost or 100) .. GodSystem.text("Unit_CoinShort", "c") .. " | " .. GodSystem.text("Home_TravelCost", "Travel ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystem.text("Unit_CoinShort", "c")
    end
    if entry.kind == "safeZone" then
        return GodSystem.getHomeSafeZoneDetailText(entry.safeZone)
    end
    return ""
end

local function gsSpendTeleportCost(cost, historyText)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if cost > 0 and not GodSystem.canAfford(cost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    if cost > 0 and not GodSystem.addPoints(-cost) then
        return false
    end
    local data = GodSystem.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    if historyText then
        gsAppendHistory(data, { kind = "home", text = historyText .. " -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins") })
    end
    return true
end

function GodSystem.setHomePoint()
    if GodSystem.isFeatureEnabled("EnableTeleport") == false then
        GodSystem.notify("Teleport disabled")
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystem.notify(reason)
        return false
    end
    local pos = gsCurrentPosition()
    if not pos or not GodSystem.findSafeTeleportPosition(pos) then
        GodSystem.notify(GodSystem.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.HomeSetCost or 100
    if not gsSpendTeleportCost(cost, GodSystem.text("History_HomeSet", "Set home")) then
        return false
    end
    local home = GodSystem.getHomeSystem()
    home.home = gsCopyPosition(pos)
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeSet", "Home set: ") .. GodSystem.formatPosition(home.home))
    return true
end

function GodSystem.buyTempTeleportSlot(index)
    if GodSystem.isFeatureEnabled("EnableTeleport") == false then
        GodSystem.notify("Teleport disabled")
        return false
    end
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystem.getHomeSystem()
    if index > (GodSystemConfig.TempTeleportMaxSlots or 3) then
        return false
    end
    home.tempSlots[index] = home.tempSlots[index] or { owned = false, point = nil }
    if home.tempSlots[index].owned then
        GodSystem.notify(GodSystem.text("Notify_HomeTempOwned", "Temp point already purchased"))
        return false
    end
    local cost = GodSystemConfig.TempTeleportSlotCost or 500
    if not gsSpendTeleportCost(cost, GodSystem.text("History_HomeTempBought", "Bought temp teleport point ") .. tostring(index)) then
        return false
    end
    home.tempSlots[index].owned = true
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeTempBought", "Temp teleport point purchased: ") .. tostring(index))
    return true
end

function GodSystem.setTempTeleportPoint(index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystem.getHomeSystem()
    local slot = home.tempSlots[index]
    if not slot or slot.owned ~= true then
        GodSystem.notify(GodSystem.text("Notify_HomeTempLocked", "Temp point not purchased"))
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystem.notify(reason)
        return false
    end
    local pos = gsCurrentPosition()
    if not pos or not GodSystem.findSafeTeleportPosition(pos) then
        GodSystem.notify(GodSystem.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.TempTeleportSetCost or 100
    if not gsSpendTeleportCost(cost, GodSystem.text("History_HomeTempSet", "Set temp teleport point ") .. tostring(index)) then
        return false
    end
    slot.point = gsCopyPosition(pos)
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeTempSet", "Temp teleport point set: ") .. tostring(index))
    return true
end

local function gsTeleportToPosition(target, returnLabel, historyText)
    if GodSystem.isFeatureEnabled("EnableTeleport") == false then
        GodSystem.notify("Teleport disabled")
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystem.notify(reason)
        return false
    end
    local safe = GodSystem.findSafeTeleportPosition(target)
    if not safe then
        GodSystem.notify(GodSystem.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.HomeTravelCost or 10
    if not gsSpendTeleportCost(cost, historyText) then
        return false
    end
    local home = GodSystem.getHomeSystem()
    local current = gsCurrentPosition()
    if returnLabel and current then
        home.returnPoint = current
        home.returnPoint.source = returnLabel
    end
    GodSystem.applyApprovedTeleport(safe)
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeTeleported", "Teleported: ") .. GodSystem.formatPosition(safe))
    return true
end

function GodSystem.teleportHome()
    local home = GodSystem.getHomeSystem()
    if not home.home then
        GodSystem.notify(GodSystem.text("Notify_HomeNotSet", "Home is not set"))
        return false
    end
    return gsTeleportToPosition(home.home, GodSystem.text("Home_ReturnSourceHome", "before returning home"), GodSystem.text("History_HomeTeleport", "Teleport home"))
end

function GodSystem.teleportTemp(index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystem.getHomeSystem()
    local slot = home.tempSlots[index]
    if not slot or slot.owned ~= true then
        GodSystem.notify(GodSystem.text("Notify_HomeTempLocked", "Temp point not purchased"))
        return false
    end
    if not slot.point then
        GodSystem.notify(GodSystem.text("Notify_HomeTempNotSet", "Temp point is not set"))
        return false
    end
    return gsTeleportToPosition(slot.point, GodSystem.text("Home_TempPoint", "Temp point ") .. tostring(index), GodSystem.text("History_HomeTempTeleport", "Teleport temp point ") .. tostring(index))
end

function GodSystem.teleportReturn()
    local home = GodSystem.getHomeSystem()
    if not home.returnPoint then
        GodSystem.notify(GodSystem.text("Notify_HomeNoReturn", "No return point"))
        return false
    end
    local target = gsCopyPosition(home.returnPoint)
    local source = target.source
    local ok = gsTeleportToPosition(target, nil, GodSystem.text("History_HomeReturn", "Return to departure point"))
    if ok then
        home.returnPoint = nil
        GodSystem.save()
        if source then
            GodSystem.notify(GodSystem.text("Notify_HomeReturnedFrom", "Returned from: ") .. tostring(source))
        end
    end
    return ok
end

function GodSystem.applyApprovedTeleport(pos)
    local player = gsPlayer()
    if not player or not pos then
        return false
    end
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z) or 0
    if not x or not y then
        return false
    end
    if player.teleportTo then
        local ok = pcall(function() player:teleportTo(x, y, z) end)
        if ok then
            return true
        end
    end
    if player.setX and player.setY and player.setZ then
        player:setX(x)
        player:setY(y)
        player:setZ(z)
        if player.setLastX then player:setLastX(x) end
        if player.setLastY then player:setLastY(y) end
        if player.setLastZ then player:setLastZ(z) end
        return true
    end
    return false
end

function GodSystem.clearHomeReturnPoint()
    local home = GodSystem.getHomeSystem()
    if not home.returnPoint then
        GodSystem.notify(GodSystem.text("Notify_HomeNoReturn", "No return point"))
        return false
    end
    local data = GodSystem.getData()
    home.returnPoint = nil
    gsAppendHistory(data, { kind = "home", text = GodSystem.text("History_HomeReturnCleared", "Clear departure point") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeReturnCleared", "Departure point cleared"))
    return true
end

function GodSystem.unlockHomeSafeZone()
    local home = GodSystem.getHomeSystem()
    local info = GodSystem.getHomeSafeZoneInfo()
    if not info.homeSet then
        GodSystem.notify(GodSystem.text("HomeSafe_NeedHome", "Set a home first."))
        return false
    end
    if info.unlocked then
        GodSystem.notify(GodSystem.text("Notify_HomeSafeAlreadyUnlocked", "Home safe zone is already unlocked"))
        return false
    end
    local firstLevel = gsHomeSafeZoneFirstLevel()
    if not firstLevel then
        return false
    end
    local cost = firstLevel.unlockCost or firstLevel.upgradeCost or 0
    if not gsSpendTeleportCost(cost, GodSystem.text("History_HomeSafeUnlock", "Unlock home safe zone")) then
        return false
    end
    home.safeZone.level = math.floor(tonumber(firstLevel.level) or 1)
    home.safeZone.enabled = true
    home.safeZone.lastScanHours = gsNowHours()
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeSafeUnlocked", "Home safe zone unlocked"))
    return true
end

function GodSystem.upgradeHomeSafeZone()
    local home = GodSystem.getHomeSystem()
    local info = GodSystem.getHomeSafeZoneInfo()
    if not info.homeSet then
        GodSystem.notify(GodSystem.text("HomeSafe_NeedHome", "Set a home first."))
        return false
    end
    if not info.unlocked then
        return GodSystem.unlockHomeSafeZone()
    end
    local nextLevel = info.nextLevel
    if not nextLevel then
        GodSystem.notify(GodSystem.text("Notify_HomeSafeMaxLevel", "Home safe zone is already at max level"))
        return false
    end
    local cost = nextLevel.upgradeCost or 0
    if not gsSpendTeleportCost(cost, GodSystem.text("History_HomeSafeUpgrade", "Upgrade home safe zone") .. " Lv." .. tostring(nextLevel.level)) then
        return false
    end
    home.safeZone.level = math.floor(tonumber(nextLevel.level) or (info.level + 1))
    home.safeZone.enabled = true
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_HomeSafeUpgraded", "Home safe zone upgraded to Lv.") .. tostring(home.safeZone.level))
    return true
end

function GodSystem.toggleHomeSafeZone()
    local home = GodSystem.getHomeSystem()
    local info = GodSystem.getHomeSafeZoneInfo()
    if not info.unlocked then
        GodSystem.notify(GodSystem.text("HomeSafe_Locked", "Locked"))
        return false
    end
    home.safeZone.enabled = not home.safeZone.enabled
    GodSystem.save()
    if home.safeZone.enabled then
        GodSystem.notify(GodSystem.text("Notify_HomeSafeEnabled", "Home safe zone enabled"))
    else
        GodSystem.notify(GodSystem.text("Notify_HomeSafeDisabled", "Home safe zone paused"))
    end
    return true
end

local function gsCollectHomeSafeZoneZombies(center, radius)
    local result = {}
    if not center or not radius or radius <= 0 or not getCell then
        return result
    end
    local cell = getCell()
    if not cell or not cell.getZombieList then
        return result
    end
    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not okList or not zombies or not zombies.size or not zombies.get then
        return result
    end
    local okSize, size = pcall(function() return zombies:size() end)
    if not okSize or not size or size <= 0 then
        return result
    end
    local radiusSq = radius * radius
    for i = size - 1, 0, -1 do
        local okZombie, zombie = pcall(function() return zombies:get(i) end)
        if okZombie and zombie and zombie.getX and zombie.getY then
            local dead = false
            if zombie.isDead then
                local okDead, isDead = pcall(function() return zombie:isDead() end)
                dead = okDead and isDead == true
            end
            if not dead then
                local okPos, zx, zy = pcall(function() return zombie:getX(), zombie:getY() end)
                if okPos then
                    local dx = (tonumber(zx) or 0) - (tonumber(center.x) or 0)
                    local dy = (tonumber(zy) or 0) - (tonumber(center.y) or 0)
                    if (dx * dx) + (dy * dy) <= radiusSq then
                        table.insert(result, zombie)
                    end
                end
            end
        end
    end
    return result
end

local function gsRemoveZombieFromWorld(zombie)
    if not zombie then
        return false
    end
    local removed = false
    if zombie.removeFromWorld then
        local ok = pcall(function() zombie:removeFromWorld() end)
        removed = removed or ok
    end
    if zombie.removeFromSquare then
        local ok = pcall(function() zombie:removeFromSquare() end)
        removed = removed or ok
    end
    return removed
end

function GodSystem.clearHomeSafeZone(manual)
    local home = GodSystem.getHomeSystem()
    local info = GodSystem.getHomeSafeZoneInfo()
    local safe = home.safeZone
    local now = gsNowHours()
    safe.lastScanHours = now
    if not info.homeSet then
        if manual then
            GodSystem.notify(GodSystem.text("HomeSafe_NeedHome", "Set a home first."))
        end
        return 0
    end
    if not info.unlocked then
        if manual then
            GodSystem.notify(GodSystem.text("HomeSafe_Locked", "Locked"))
        end
        return 0
    end
    if not manual and not info.enabled then
        return 0
    end

    local targets = gsCollectHomeSafeZoneZombies(info.center, info.radius or 0)
    if #targets <= 0 then
        safe.lastCleared = 0
        GodSystem.save()
        if manual then
            GodSystem.notify(GodSystem.text("Notify_HomeSafeNoZombie", "No zombies in the safe zone"))
        end
        return 0
    end

    local cost = math.max(0, math.floor(tonumber(info.clearCost) or 0))
    if cost > 0 and not GodSystem.canAfford(cost) then
        if manual or (now - (safe.lastNoticeHours or -999)) >= (GodSystemConfig.HomeSafeZoneInsufficientNoticeHours or 1) then
            GodSystem.notify(GodSystem.text("Notify_HomeSafeNoMoney", "Not enough currency for safe zone cleanup"))
            safe.lastNoticeHours = now
            GodSystem.save()
        end
        return 0
    end

    local removed = 0
    for i = 1, #targets do
        if gsRemoveZombieFromWorld(targets[i]) then
            removed = removed + 1
        end
    end

    safe.lastCleared = removed
    safe.lastClearHour = now
    if removed > 0 then
        if cost > 0 then
            if not GodSystem.addPoints(-cost) then
                return removed
            end
            local data = GodSystem.getData()
            data.stats = data.stats or {}
            data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        end
        local data = GodSystem.getData()
        data.stats = data.stats or {}
        data.stats.homeSafeCleared = (data.stats.homeSafeCleared or 0) + removed
        gsAppendHistory(data, { kind = "home", text = GodSystem.text("History_HomeSafeClear", "Home safe zone cleared ") .. tostring(removed) .. GodSystem.text("HomeSafe_ZombieUnit", " zombies") .. " -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins") })
        GodSystem.save()
        if manual then
            GodSystem.notify(GodSystem.text("Notify_HomeSafeCleared", "Home safe zone cleared: ") .. tostring(removed))
        end
    end
    return removed
end

function GodSystem.updateHomeSafeZone()
    local home = GodSystem.getHomeSystem()
    local safe = home.safeZone
    local info = GodSystem.getHomeSafeZoneInfo()
    if not info.homeSet or not info.unlocked or not info.enabled then
        return
    end
    local now = gsNowHours()
    local interval = math.max(0.05, tonumber(info.intervalHours) or 0.5)
    if now - (safe.lastScanHours or 0) < interval then
        return
    end
    GodSystem.clearHomeSafeZone(false)
end

function GodSystem.performHomeAction(action, index)
    if action == "setHome" then
        return GodSystem.setHomePoint()
    elseif action == "buyTemp" then
        return GodSystem.buyTempTeleportSlot(index)
    elseif action == "setTemp" then
        return GodSystem.setTempTeleportPoint(index)
    elseif action == "teleportHome" then
        return GodSystem.teleportHome()
    elseif action == "teleportTemp" then
        return GodSystem.teleportTemp(index)
    elseif action == "return" then
        return GodSystem.teleportReturn()
    elseif action == "clearReturn" then
        return GodSystem.clearHomeReturnPoint()
    elseif action == "unlockSafeZone" then
        return GodSystem.unlockHomeSafeZone()
    elseif action == "upgradeSafeZone" then
        return GodSystem.upgradeHomeSafeZone()
    elseif action == "toggleSafeZone" then
        return GodSystem.toggleHomeSafeZone()
    elseif action == "clearSafeZone" then
        return GodSystem.clearHomeSafeZone(true)
    end
    return false
end

function GodSystem.buyShopItem(shopItem, quantity)
    if GodSystem.isFeatureEnabled("EnableShop") == false then
        GodSystem.notify("Shop disabled")
        return false
    end
    if not shopItem then
        return false
    end
    if shopItem.featureKey and GodSystemAdminConfig.isFeatureEnabled(shopItem.featureKey) == false then
        GodSystem.notify("Shop item disabled")
        return false
    end
    local data = GodSystem.getData()
    if shopItem.unlocked == true then
        local variantKey = shopItem.variantKey or GodSystemShopVariants.getKey(shopItem.fullType, shopItem.worldSprite)
        local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
        if not stored then
            GodSystem.notify(GodSystem.text("Notify_ShopItemMissing", "This player-listed item no longer exists."))
            return false
        elseif stored.hidden == true then
            GodSystem.notify(GodSystem.text("Notify_ShopHiddenAlreadyListed", "This item is hidden. Restore it from hidden management."))
            return false
        end
    end
    local primaryFullType = GodSystem.getShopPrimaryFullType(shopItem)
    if primaryFullType and GodSystemAdminConfig.isShopItemEnabled(primaryFullType, true) == false then
        GodSystem.notify("Shop item disabled")
        return false
    end
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local unitPrice = GodSystem.getShopItemUnitPrice(shopItem)
    local price = unitPrice * quantity
    if not GodSystem.canAfford(price) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local available, reason, availableItems, missingItems = GodSystem.shopItemIsAvailable(shopItem)
    if not available then
        GodSystem.notify(reason)
        return false
    end

    local expected = 0
    local grantItems = gsMultiplyItems(availableItems or shopItem.items, quantity)
    for i = 1, #(grantItems or {}) do
        expected = expected + math.max(1, math.floor(grantItems[i].count or 1))
    end
    local given, _, addedItems = GodSystem.giveItems(grantItems, true)
    if expected > 0 and given < expected then
        GodSystem.removeAddedItems(addedItems)
        GodSystem.notify(GodSystem.text("Notify_ItemGrantFailed", "Failed to give item, no currency spent"))
        return false
    end
    if not GodSystem.addPoints(-price) then
        GodSystem.removeAddedItems(addedItems)
        return false
    end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + price
    data.stats.boughtItems = (data.stats.boughtItems or 0) + quantity
    local quantityText = quantity > 1 and (" x" .. tostring(quantity)) or ""
    gsAppendHistory(data, { kind = "shop", text = GodSystem.text("History_Bought", "Bought: ") .. tostring(GodSystem.getShopLabel(shopItem)) .. quantityText .. " -" .. tostring(price) .. GodSystem.text("Unit_Coin", " coins") })
    if missingItems and #missingItems > 0 then
        GodSystem.notify(GodSystem.text("Notify_BoughtPartial", "Bought available items, skipped missing: ") .. tostring(#missingItems))
    else
        GodSystem.notify(GodSystem.text("Notify_Bought", "Bought: ") .. tostring(GodSystem.getShopLabel(shopItem)) .. quantityText)
    end
    GodSystem.save()
    return true
end

local function gsGetRecycleValue(item, allowContainers)
    if not item then
        return 0
    end
    local fullType = item:getFullType()
    if GodSystem.isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item) then
        return 0
    end
    if GodSystemConfig.RecycleBlacklist[fullType] then
        return 0
    end
    if GodSystemAdminConfig.isRecycleItemEnabled(fullType, true) == false then
        return 0
    end
    if allowContainers ~= true and GodSystemConfig.AllowRecycleContainers ~= true and gsItemHasInventory(item) then
        return 0
    end
    if GodSystem.isLooseAmmoRecycleItem(fullType, item) then
        return 1
    end
    local value = GodSystem.getItemSellPrice(fullType, item)
    if gsSafeIsBroken(item) then
        value = math.floor(value * 0.5)
    end
    local usedDelta = gsSafeUsedDelta(item)
    if usedDelta then
        value = math.floor(value * usedDelta)
    end
    return math.max(1, value)
end

function GodSystem.getRecycleValue(item)
    return gsGetRecycleValue(item, false)
end

function GodSystem.getContextRecycleValue(item)
    return gsGetRecycleValue(item, true)
end

local function gsIsKeyItem(item)
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

function GodSystem.canContextRecycleItem(item)
    if not item or not item.getFullType then return false, "invalid" end
    local fullType = item:getFullType()
    if GodSystem.isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item) then return false, "protected" end
    if (GodSystemConfig.RecycleBlacklist or {})[fullType] or gsIsKeyItem(item) then return false, "protected" end
    if GodSystem.isEconomicItemAllowed and GodSystem.isEconomicItemAllowed(fullType, "recycle") == false then
        return false, "invalid"
    end
    if GodSystem.getContextRecycleValue(item) <= 0 then return false, "invalid" end
    return true, nil
end

function GodSystem.canContextListItem(item)
    local allowed, reason = GodSystem.canContextRecycleItem(item)
    if not allowed then return false, reason end
    local fullType = item:getFullType()
    if not GodSystem.isAutoShopUnlockAllowed(fullType) then return false, "notListable" end
    local data = GodSystem.getData()
    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local known, source = GodSystemShopVariants.isListingKnown(data, GodSystem.getConfiguredShopKeySet(), variantKey)
    if known then
        if source == "configured" then return false, "configuredListed" end
        if data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then return false, "hiddenListed" end
        return false, "alreadyListed"
    end
    return true, nil
end

function GodSystem.isAutoRecyclerContainer(item)
    if not item or not item.getFullType then
        return false
    end
    if not GodSystem.isAutoRecyclerFullType(item:getFullType()) then
        return false
    end
    return true
end

function GodSystem.canAutoRecycleItem(item)
    if not item or not item.getFullType then
        return false
    end
    if GodSystemTerminalRelief.isReliefItem(item) then
        return false
    end
    local fullType = item:getFullType()
    if GodSystem.isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item) then
        return false
    end
    if GodSystemConfig.RecycleBlacklist[fullType] then
        return false
    end
    if gsItemHasInventory(item) then
        return false
    end
    return GodSystem.getRecycleValue(item) > 0
end

function GodSystem.processAutoRecyclerContainer(container)
    if not container or not container.getItems then
        return 0, 0, 0
    end

    local items = container:getItems()
    local groups = {}
    local order = {}
    local skipped = 0

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if GodSystem.canAutoRecycleItem(item) then
            local fullType = item:getFullType()
            if not groups[fullType] then
                groups[fullType] = { items = {}, raw = 0, count = 0 }
                table.insert(order, fullType)
            end
            table.insert(groups[fullType].items, item)
            groups[fullType].raw = groups[fullType].raw + GodSystem.getRecycleValue(item)
            groups[fullType].count = groups[fullType].count + 1
        elseif not GodSystemTerminalRelief.isReliefItem(item) then
            skipped = skipped + 1
        end
    end

    local removedItems = {}
    local removedCount = 0
    local rawValue = 0
    local diminishedUnits = 0
    for i = 1, #order do
        local fullType = order[i]
        local group = groups[fullType]
        local groupValue = GodSystem.calculateRecyclePayout(fullType, group.raw, group.count)
        if groupValue > 0 then
            rawValue = rawValue + groupValue
            if GodSystem.getRecycleUnitDivisor(fullType, group.items[1]) > 1 then
                diminishedUnits = diminishedUnits + groupValue
            else
                diminishedUnits = diminishedUnits + group.count
            end
            for j = 1, #group.items do
                table.insert(removedItems, group.items[j])
                removedCount = removedCount + 1
            end
        else
            skipped = skipped + group.count
        end
    end

    if removedCount <= 0 or rawValue <= 0 then
        return 0, 0, skipped
    end

    for i = 1, #removedItems do
        container:Remove(removedItems[i])
    end

    local payout = GodSystem.applyAutoRecyclerDailyPayout(rawValue, diminishedUnits)
    if payout <= 0 then
        return 0, 0, skipped
    end
    return removedCount, payout, skipped
end

function GodSystem.processAutoRecycler()
    local found = GodSystem.findAutoRecyclerCandidates()
    if #found <= 0 then
        return false
    end

    local totalRemoved = 0
    local totalPayout = 0
    local totalSkipped = 0
    for i = 1, #found do
        local ring = found[i].item
        if not GodSystem.isAutoRecyclerContainer(ring) then
            ring = nil
        end
        local inventory = nil
        if ring and ring.getInventory then
            GodSystem.applyAutoRecyclerContainerStats(ring)
            local ok, child = pcall(function() return ring:getInventory() end)
            if ok then
                inventory = child
            end
        end
        local removed, payout, skipped = GodSystem.processAutoRecyclerContainer(inventory)
        totalRemoved = totalRemoved + removed
        totalPayout = totalPayout + payout
        totalSkipped = totalSkipped + skipped
    end

    if totalRemoved <= 0 or totalPayout <= 0 then
        return false
    end

    local data = GodSystem.getData()
    data.stats.recycledItems = (data.stats.recycledItems or 0) + totalRemoved
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + totalPayout
    GodSystem.giveCurrency(totalPayout)
    gsAppendHistory(data, { kind = "recycle", text = GodSystem.text("History_AutoRecycler", "Auto recycler: ") .. tostring(totalRemoved) .. GodSystem.text("Unit_Item", " items, gained ") .. tostring(totalPayout) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    local skippedText = totalSkipped > 0 and (" | " .. GodSystem.text("AutoRecycler_Skipped", "skipped ") .. tostring(totalSkipped)) or ""
    GodSystem.notify(GodSystem.text("Notify_AutoRecycler", "Auto recycler: ") .. tostring(totalRemoved) .. GodSystem.text("Unit_Item", " items, gained ") .. tostring(totalPayout) .. GodSystem.text("Unit_Coin", " coins") .. skippedText)
    return true
end

function GodSystem.updateAutoRecycler()
    local data = GodSystem.getData()
    if data.waistAutoRecycleUnlocked ~= true or data.waistAutoRecycleEnabled ~= true then
        return
    end
    local interval = GodSystem.getWaistAutoRecycleIntervalHours()
    local nowHour = math.floor(gsNowHours())
    if nowHour < (data.lastWaistAutoRecycleHour or 0) then
        data.lastWaistAutoRecycleHour = nowHour
    end
    if nowHour - (data.lastWaistAutoRecycleHour or nowHour) < interval then
        return
    end
    data.lastWaistAutoRecycleHour = nowHour
    GodSystem.save()
    GodSystem.processWaistAutoRecycle()
end

function GodSystem.claimOrRecoverAutoRecycler()
    local data = GodSystem.getData()
    local existing = GodSystem.getAutoRecyclerContainer()
    if existing then
        GodSystem.notify(GodSystem.text("Notify_AutoRecyclerAlreadyOwned", "System space terminal already exists"))
        return true
    end

    local cost = data.autoRecyclerClaimed and GodSystem.getAutoRecyclerRecoverCost() or 0
    local fullType = GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal"
    if not GodSystem.itemExists(fullType) then
        GodSystem.notify(GodSystem.text("Error_ItemNotFound", "Item not found: ") .. tostring(fullType))
        return false
    end
    if cost > 0 and not GodSystem.canAfford(cost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local ok, addedItems = GodSystem.giveItem(fullType, 1)
    if not ok or not addedItems or not addedItems[1] then
        GodSystem.notify(GodSystem.text("Notify_ItemGrantFailed", "Failed to give item, no currency spent"))
        return false
    end
    if cost > 0 and not GodSystem.addPoints(-cost) then
        GodSystem.removeAddedItems(addedItems)
        return false
    end

    data.autoRecyclerClaimed = true
    GodSystem.markAutoRecyclerContainer(addedItems[1])
    local historyKey = cost > 0 and "History_AutoRecyclerRecovered" or "History_AutoRecyclerClaimed"
    local notifyKey = cost > 0 and "Notify_AutoRecyclerRecovered" or "Notify_AutoRecyclerClaimed"
    local suffix = cost > 0 and (" -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins")) or ""
    gsAppendHistory(data, { kind = "system", text = GodSystem.text(historyKey, "System space terminal ready") .. suffix })
    GodSystem.save()
    GodSystem.notify(GodSystem.text(notifyKey, "System space terminal ready"))
    return true
end

function GodSystem.upgradeTerminal(upgradeType)
    if upgradeType ~= "capacity" and upgradeType ~= "reduction" and upgradeType ~= "relief" then return false end
    return GodSystem.upgradeSystem("terminal" .. string.upper(string.sub(upgradeType, 1, 1)) .. string.sub(upgradeType, 2))
end

function GodSystem.upgradeAutoRecycler()
    return GodSystem.upgradeTerminal("capacity")
end

function GodSystem.getAutoRecyclerInventory()
    local entry = GodSystem.getAutoRecyclerContainer()
    if not entry or not entry.item or not entry.item.getInventory then
        return nil, entry
    end
    local ok, inventory = pcall(function() return entry.item:getInventory() end)
    if ok then
        return inventory, entry
    end
    return nil, entry
end

function GodSystem.getAutoRecyclerInfo()
    local data = GodSystem.getData()
    local capacityInfo = GodSystemTerminalUpgrades.getUpgradeInfo(data, "capacity")
    local reductionInfo = GodSystemTerminalUpgrades.getUpgradeInfo(data, "reduction")
    local reliefInfo = GodSystemTerminalUpgrades.getUpgradeInfo(data, "relief")
    local inventory, entry = GodSystem.getAutoRecyclerInventory()
    local appliedStatus = entry and entry.item and GodSystemTerminalUpgrades.getAppliedStatus(entry.item, data, gsPlayer()) or nil
    local count = 0
    local contentsWeight = nil
    if inventory and inventory.getItems then
        local ok, items = pcall(function() return inventory:getItems() end)
        if ok and items and items.size then
            for i = 0, items:size() - 1 do
                if not GodSystemTerminalRelief.isReliefItem(items:get(i)) then count = count + 1 end
            end
        end
    end
    if inventory and inventory.getContentsWeight then
        local ok, value = pcall(function() return inventory:getContentsWeight() end)
        if ok then contentsWeight = tonumber(value) end
    end
    local actualRelief = appliedStatus and tonumber(appliedStatus.actualRelief) or 0
    return {
        claimed = data.autoRecyclerClaimed == true,
        found = entry ~= nil,
        level = capacityInfo.level,
        maxLevel = capacityInfo.maxLevel,
        capacityLevel = capacityInfo.level,
        capacityMaxLevel = capacityInfo.maxLevel,
        reductionLevel = reductionInfo.level,
        reductionMaxLevel = reductionInfo.maxLevel,
        reliefLevel = reliefInfo.level,
        reliefMaxLevel = reliefInfo.maxLevel,
        capacity = capacityInfo.value or 0,
        weightReduction = reductionInfo.value or 0,
        reliefOffset = reliefInfo.offset or 0,
        reliefNextOffset = reliefInfo.nextOffset,
        effectiveCapacity = (capacityInfo.value or 0) + (reliefInfo.offset or 0),
        visibleContentsWeight = math.max(0, (tonumber(contentsWeight) or 0) + actualRelief),
        actualCapacity = appliedStatus and appliedStatus.outerCapacity or nil,
        actualInnerCapacity = appliedStatus and appliedStatus.innerCapacity or nil,
        actualWeightReduction = appliedStatus and appliedStatus.outerReduction or nil,
        actualInnerWeightReduction = appliedStatus and appliedStatus.innerReduction or nil,
        capacityApplied = appliedStatus and appliedStatus.capacityApplied == true,
        reductionApplied = appliedStatus and appliedStatus.reductionApplied == true,
        reliefApplied = appliedStatus and appliedStatus.reliefApplied == true,
        actualRelief = appliedStatus and appliedStatus.actualRelief or nil,
        capacityNextCost = capacityInfo.nextCost,
        reductionNextCost = reductionInfo.nextCost,
        reliefNextCost = reliefInfo.nextCost,
        nextCost = capacityInfo.nextCost,
        recoverCost = GodSystem.getAutoRecyclerRecoverCost(),
        itemCount = count,
        contentsWeight = contentsWeight,
        autoRecycleUnlocked = data.waistAutoRecycleUnlocked == true,
        autoRecycleEnabled = data.waistAutoRecycleEnabled == true,
        recycleUnlockMode = data.waistRecycleUnlockMode == true,
        autoRecycleUnlockCost = GodSystem.getWaistAutoRecycleUnlockCost(),
        autoRecycleIntervalHours = GodSystem.getWaistAutoRecycleIntervalHours(),
    }
end

function GodSystem.unlockWaistAutoRecycle()
    local info = GodSystem.getAutoRecyclerInfo()
    if not info.found then
        GodSystem.notify(GodSystem.text("Notify_AutoRecyclerMissing", "System space terminal not found"))
        return false
    end

    local data = GodSystem.getData()
    if data.waistAutoRecycleUnlocked == true then
        return true
    end

    local cost = GodSystem.getWaistAutoRecycleUnlockCost()
    if cost > 0 and not GodSystem.canAfford(cost) then
        GodSystem.notify(GodSystem.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    if cost > 0 and not GodSystem.addPoints(-cost) then
        return false
    end

    data.waistAutoRecycleUnlocked = true
    data.waistAutoRecycleEnabled = true
    data.lastWaistAutoRecycleHour = math.floor(gsNowHours())
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    gsAppendHistory(data, { kind = "system", text = GodSystem.text("History_WaistAutoRecycleUnlocked", "Terminal auto recycle unlocked") .. " -" .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_WaistAutoRecycleUnlocked", "Terminal auto recycle unlocked and enabled"))
    return true
end

function GodSystem.toggleWaistAutoRecycle()
    if GodSystem.isFeatureEnabled("EnableWaistAutoRecycle") == false then
        GodSystem.notify(GodSystem.text("NotifyMP_WaistAutoDisabled", "Terminal auto recycle disabled"))
        return false
    end
    local info = GodSystem.getAutoRecyclerInfo()
    if not info.found then
        GodSystem.notify(GodSystem.text("Notify_AutoRecyclerMissing", "System space terminal not found"))
        return false
    end

    local data = GodSystem.getData()
    if data.waistAutoRecycleUnlocked ~= true then
        return GodSystem.unlockWaistAutoRecycle()
    end

    data.waistAutoRecycleEnabled = data.waistAutoRecycleEnabled ~= true
    if data.waistAutoRecycleEnabled then
        data.lastWaistAutoRecycleHour = math.floor(gsNowHours())
        GodSystem.notify(GodSystem.text("Notify_WaistAutoRecycleEnabled", "Terminal auto recycle enabled"))
    else
        GodSystem.notify(GodSystem.text("Notify_WaistAutoRecycleDisabled", "Terminal auto recycle disabled"))
    end
    GodSystem.save()
    return true
end

function GodSystem.canRecycleWaistSpaceItem(item)
    if not item or not item.getFullType then
        return false
    end
    if GodSystemTerminalRelief.isReliefItem(item) then
        return false
    end
    local fullType = item:getFullType()
    if GodSystem.isAutoRecyclerContainer(item) then
        return false
    end
    if GodSystemConfig.RecycleBlacklist[fullType] then
        return false
    end
    if gsSafeIsFavorite(item) then
        return false
    end
    if gsItemHasInventory(item) then
        return false
    end
    return GodSystem.getRecycleValue(item) > 0
end

function GodSystem.getWaistSpaceRecycleGroups()
    local result = {}
    local order = {}
    local skipped = 0
    local inventory = GodSystem.getAutoRecyclerInventory()
    if not inventory or not inventory.getItems then
        return result, order, skipped
    end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and GodSystem.canRecycleWaistSpaceItem(item) then
            local fullType = item:getFullType()
            local value = GodSystem.getRecycleValue(item)
            if not result[fullType] then
                result[fullType] = {
                    fullType = fullType,
                    label = item:getDisplayName() or GodSystem.getItemDisplayName(fullType),
                    count = 0,
                    valueEach = value,
                    rawTotalValue = 0,
                    totalValue = 0,
                    unitDivisor = GodSystem.getRecycleUnitDivisor(fullType, item),
                    items = {},
                }
                table.insert(order, fullType)
            end
            table.insert(result[fullType].items, item)
            result[fullType].count = result[fullType].count + 1
            result[fullType].rawTotalValue = result[fullType].rawTotalValue + value
            result[fullType].totalValue = GodSystem.calculateRecyclePayout(fullType, result[fullType].rawTotalValue, result[fullType].count)
        elseif not GodSystemTerminalRelief.isReliefItem(item) then
            skipped = skipped + 1
        end
    end
    table.sort(order, function(a, b)
        return (result[a].label or a) < (result[b].label or b)
    end)
    return result, order, skipped
end

function GodSystem.recycleWaistSpaceItemsInternal(selectedFullTypes, unlockShop)
    if GodSystem.isFeatureEnabled("EnableRecycle") == false then
        GodSystem.notify("Recycle disabled")
        return false
    end
    local inventory = GodSystem.getAutoRecyclerInventory()
    if not inventory or not inventory.Remove then
        GodSystem.notify(GodSystem.text("Notify_AutoRecyclerMissing", "System space terminal not found"))
        return false
    end

    local groups, order = GodSystem.getWaistSpaceRecycleGroups()
    local removedItems = {}
    local removedCount = 0
    local totalPayout = 0
    local unlockDetails = {}
    for i = 1, #order do
        local fullType = order[i]
        local selected = selectedFullTypes == nil or selectedFullTypes[fullType] == true
        local group = groups[fullType]
        if selected and group and (group.totalValue or 0) > 0 then
            totalPayout = totalPayout + (group.totalValue or 0)
            if unlockShop == true then
                local variants = {}
                for j = 1, #(group.items or {}) do
                    local item = group.items[j]
                    local variantKey = GodSystemShopVariants.getKey(fullType, item)
                    if not variants[variantKey] then
                        variants[variantKey] = true
                        unlockDetails[#unlockDetails + 1] = { fullType = fullType, label = item:getDisplayName() or group.label, sellValue = group.valueEach or 1, worldSprite = GodSystemShopVariants.getWorldSprite(item) }
                    end
                end
            end
            for j = 1, #(group.items or {}) do
                table.insert(removedItems, group.items[j])
                removedCount = removedCount + 1
            end
        end
    end

    if removedCount <= 0 or totalPayout <= 0 then
        GodSystem.notify(GodSystem.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end

    for i = 1, #removedItems do
        inventory:Remove(removedItems[i])
    end

    local data = GodSystem.getData()
    data.stats.recycledItems = (data.stats.recycledItems or 0) + removedCount
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + totalPayout
    if unlockShop == true then
        for i = 1, #unlockDetails do
            GodSystem.unlockAutoShopItem(unlockDetails[i].fullType, unlockDetails[i].label, unlockDetails[i].sellValue, unlockDetails[i].worldSprite)
        end
    end
    GodSystem.giveCurrency(totalPayout)
    gsAppendHistory(data, { kind = "recycle", text = GodSystem.text("History_WaistSpaceRecycled", "Terminal recycled ") .. tostring(removedCount) .. GodSystem.text("Unit_Item", " items, gained ") .. tostring(totalPayout) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_WaistSpaceRecycled", "Terminal recycled ") .. tostring(removedCount) .. GodSystem.text("Unit_Item", " items, gained ") .. tostring(totalPayout) .. GodSystem.text("Unit_Coin", " coins"))
    return true
end

function GodSystem.recycleWaistSpaceItems(selectedFullTypes)
    return GodSystem.recycleWaistSpaceItemsInternal(selectedFullTypes, false)
end

function GodSystem.recycleWaistSpaceItemsAndUnlock(selectedFullTypes)
    return GodSystem.recycleWaistSpaceItemsInternal(selectedFullTypes, true)
end

function GodSystem.recycleWaistSpaceItemsByMode(selectedFullTypes)
    if GodSystem.isWaistRecycleUnlockMode() then
        return GodSystem.recycleWaistSpaceItemsAndUnlock(selectedFullTypes)
    end
    return GodSystem.recycleWaistSpaceItems(selectedFullTypes)
end

function GodSystem.processWaistAutoRecycle()
    local data = GodSystem.getData()
    if data.waistAutoRecycleUnlocked ~= true or data.waistAutoRecycleEnabled ~= true then
        return false
    end

    local inventory = GodSystem.getAutoRecyclerInventory()
    if not inventory then
        return false
    end

    local _, order = GodSystem.getWaistSpaceRecycleGroups()
    if not order or #order <= 0 then
        return false
    end

    return GodSystem.recycleWaistSpaceItemsByMode(nil)
end

function GodSystem.getInventoryRecycleGroups()
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
            local value = GodSystem.getRecycleValue(item)
            if value > 0 then
                if not result[fullType] then
                    result[fullType] = {
                        fullType = fullType,
                        label = item:getDisplayName() or GodSystem.getItemDisplayName(fullType),
                        count = 0,
                        valueEach = value,
                        rawTotalValue = 0,
                        totalValue = 0,
                        unitDivisor = GodSystem.getRecycleUnitDivisor(fullType, item),
                        itemIds = {},
                    }
                    table.insert(order, fullType)
                end
                if item.getID then result[fullType].itemIds[#result[fullType].itemIds + 1] = tostring(item:getID()) end
                if not result[fullType].listItemId then
                    local listable = GodSystem.canContextListItem(item)
                    if listable == true and item.getID then
                        result[fullType].listItemId = tostring(item:getID())
                        result[fullType].listVariantKey = GodSystemShopVariants.getKey(fullType, item)
                        result[fullType].listWorldSprite = GodSystemShopVariants.getWorldSprite(item)
                    end
                end
                result[fullType].count = result[fullType].count + 1
                result[fullType].rawTotalValue = result[fullType].rawTotalValue + value
                result[fullType].totalValue = GodSystem.calculateRecyclePayout(fullType, result[fullType].rawTotalValue, result[fullType].count)
            end
        end
    end

    table.sort(order, function(a, b)
        return (result[a].label or a) < (result[b].label or b)
    end)
    return result, order
end

function GodSystem.removeInventoryItems(fullType, count)
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
        local value = GodSystem.getRecycleValue(item)
        if value > 0 then
            local unlockValue = GodSystem.getItemSellPrice(item:getFullType(), item) or value
            totalValue = totalValue + value
            table.insert(removedDetails, {
                fullType = item:getFullType(),
                label = item:getDisplayName() or GodSystem.getItemDisplayName(item:getFullType()),
                sellValue = unlockValue,
                worldSprite = GodSystemShopVariants.getWorldSprite(item),
            })
            found[i].container:Remove(item)
            removed = removed + 1
        end
    end

    return removed, totalValue, removedDetails
end

function GodSystem.removeAnyInventoryItems(fullTypes, count)
    local removed = 0
    local totalValue = 0
    if not fullTypes then
        return removed, totalValue
    end
    for i = 1, #fullTypes do
        if removed >= count then
            break
        end
        local take, value = GodSystem.removeInventoryItems(fullTypes[i], count - removed)
        removed = removed + take
        totalValue = totalValue + value
    end
    return removed, totalValue
end

function GodSystem.recycleInventoryItems(fullType, count)
    if GodSystem.isFeatureEnabled("EnableRecycle") == false then
        GodSystem.notify("Recycle disabled")
        return false
    end
    local found = gsFindInventoryItems(fullType, false, false)
    if #found <= 0 then
        GodSystem.notify(GodSystem.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end
    count = math.max(1, math.floor(count or 1))
    count = math.min(count, #found)
    local divisor = GodSystem.getRecycleUnitDivisor(fullType, found[1].item)
    if divisor > 1 then
        local previewRaw = 0
        for i = 1, count do
            previewRaw = previewRaw + GodSystem.getRecycleValue(found[i].item)
        end
        if GodSystem.calculateRecyclePayout(fullType, previewRaw, count) <= 0 then
            GodSystem.notify(GodSystem.text("Notify_RecycleNeedMore", "Need more items for 1 coin: ") .. tostring(divisor))
            return false
        end
    end
    local removed, totalValue, removedDetails = GodSystem.removeInventoryItems(fullType, count)
    if removed <= 0 then
        GodSystem.notify(GodSystem.text("Notify_NoRecycleItem", "No recyclable item"))
        return false
    end
    local rawValue = GodSystem.calculateRecyclePayout(fullType, totalValue, removed)
    if rawValue <= 0 then
        GodSystem.notify(GodSystem.text("Notify_RecycleNeedMore", "Need more items for 1 coin: ") .. tostring(divisor))
        return false
    end
    local totalValue, diminished = GodSystem.applyRecycleDailyPayout(rawValue)

    local data = GodSystem.getData()
    data.stats.recycledItems = (data.stats.recycledItems or 0) + removed
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + totalValue
    GodSystem.addPoints(totalValue, GodSystem.text("Reason_Recycle", "Recycle"))
    if GodSystem.isRecycleUnlockMode() then
        for i = 1, #(removedDetails or {}) do
            local detail = removedDetails[i]
            GodSystem.unlockAutoShopItem(detail.fullType, detail.label, detail.sellValue, detail.worldSprite)
        end
    end
    local historyText = GodSystem.text("History_Recycled", "Recycled ") .. tostring(removed) .. GodSystem.text("Unit_Item", " items, gained ") .. tostring(totalValue) .. GodSystem.text("Unit_Coin", " coins")
    if diminished then
        historyText = historyText .. " (" .. GodSystem.text("History_RecycleDiminished", "daily limit diminished from ") .. tostring(rawValue) .. ")"
        GodSystem.notify(GodSystem.text("Notify_RecycleDiminished", "Daily recycle limit reached, payout: ") .. tostring(totalValue) .. GodSystem.text("Unit_CoinShort", "c"))
    end
    gsAppendHistory(data, { kind = "recycle", text = historyText })
    GodSystem.save()
    return true
end

local function gsContainerContainsItem(container, item)
    return GodSystem.containerContainsItem(container, item)
end

local function gsRestoreContextItems(player, removed)
    local inventory = player and player:getInventory() or nil
    if not inventory then return false end
    local restored = true
    for i = 1, #(removed or {}) do
        local row = removed[i]
        local ok = pcall(function() inventory:AddItem(row.item) end)
        restored = restored and ok
        if ok and row.worn and row.bodyLocation and player.setWornItem then
            pcall(function() player:setWornItem(row.bodyLocation, row.item) end)
        end
        if ok and row.primary then pcall(function() player:setPrimaryHandItem(row.item) end) end
        if ok and row.secondary then pcall(function() player:setSecondaryHandItem(row.item) end) end
    end
    return restored
end

local function gsRestoreContextUseState(player, row)
    if not player or not row or not row.item then return end
    if row.worn and row.bodyLocation and player.setWornItem then
        pcall(function() player:setWornItem(row.bodyLocation, row.item) end)
    end
    if row.primary then pcall(function() player:setPrimaryHandItem(row.item) end) end
    if row.secondary then pcall(function() player:setSecondaryHandItem(row.item) end) end
end

function GodSystem.recycleSelectedItems(mode, itemIds, allowDestroyContents, containerContentSignatures, clientSkipped)
    mode = tostring(mode or "")
    if mode ~= "recycle" and mode ~= "recycleAndList" and mode ~= "listOnly" then return false end
    if GodSystem.isFeatureEnabled("EnableRecycle") == false then
        GodSystem.notify(GodSystem.text("Notify_RecycleDisabled", "Recycle is disabled"))
        return false
    end
    local player = gsPlayer()
    if not player then return false end

    local selected = {}
    local seen = {}
    local types = {}
    local typeOrder = {}
    local skipped = math.min(10000, math.max(0, math.floor(tonumber(clientSkipped) or 0)))
    for i = 1, #(itemIds or {}) do
        local id = tostring(itemIds[i] or "")
        if id ~= "" and not seen[id] then
            seen[id] = true
            local item, container = gsInventoryItemById(id)
            if not item or not container then
                GodSystem.notify(GodSystem.text("Notify_RecycleSelectionChanged", "Selected items changed; action cancelled"))
                return false
            end
            local allowed = GodSystem.canContextRecycleItem(item)
            local fullType = item:getFullType()
            local eligible = allowed == true
            if eligible and mode ~= "recycle" then
                local listable, reason = GodSystem.canContextListItem(item)
                if not listable then
                    eligible = false
                end
            end
            if not eligible then
                skipped = skipped + 1
            elseif mode ~= "listOnly" then
                local expected = type(containerContentSignatures) == "table" and containerContentSignatures[id] or nil
                local hasContents = gsItemInventoryCount(item) > 0
                if (hasContents or expected) and (allowDestroyContents ~= true or not expected or GodSystem.getContextContainerSignature(item) ~= expected) then
                    GodSystem.notify(GodSystem.text("Notify_RecycleSelectionContainerChanged", "Container contents require confirmation"))
                    return false
                end
            end
            if eligible then
                local variantKey = GodSystemShopVariants.getKey(fullType, item)
                local groupKey = mode == "recycle" and fullType or variantKey
                selected[#selected + 1] = { item = item, container = container, fullType = fullType, variantKey = variantKey }
                if not types[groupKey] then
                    types[groupKey] = { item = item, fullType = fullType, raw = 0, count = 0 }
                    typeOrder[#typeOrder + 1] = groupKey
                end
                types[groupKey].raw = types[groupKey].raw + GodSystem.getContextRecycleValue(item)
                types[groupKey].count = types[groupKey].count + 1
            end
        end
    end
    if #selected <= 0 then
        GodSystem.notify(gsFormatText(GodSystem.text("Notify_RecycleSelectionEmptySkipped", "No eligible items; skipped {1}"), { skipped }))
        return false
    end

    local data = GodSystem.getData()
    if mode == "listOnly" then
        local totalCost = 0
        local listRows = {}
        for i = 1, #typeOrder do
            local variantKey = typeOrder[i]
            local row = types[variantKey]
            local fullType = row.fullType
            local sellValue = GodSystem.getItemSellPrice(fullType, row.item)
            local cost = GodSystem.getAutoShopListOnlyCost(fullType, sellValue)
            totalCost = totalCost + cost
            listRows[#listRows + 1] = { fullType = fullType, item = row.item, sellValue = sellValue }
        end
        local paid, fromBank, fromCash = GodSystem.spendCurrency(totalCost)
        if not paid then
            GodSystem.notify(GodSystem.text("Notify_ListOnlyInsufficient", "Not enough system coins"))
            return false
        end
        local unlocked = {}
        for i = 1, #listRows do
            local row = listRows[i]
            if not GodSystem.unlockAutoShopItem(row.fullType, row.item:getDisplayName(), row.sellValue, row.item) then
                for j = 1, #unlocked do data.unlockedShopItems[unlocked[j]] = nil end
                GodSystem.refundCurrencySources(fromBank, fromCash)
                GodSystem.save()
                GodSystem.notify(GodSystem.text("Notify_RecycleSelectionChanged", "Selected items changed; action cancelled"))
                return false
            end
            unlocked[#unlocked + 1] = GodSystemShopVariants.getKey(row.fullType, row.item)
        end
        local data = GodSystem.getData()
        gsAppendHistory(data, { kind = "shop", text = gsFormatText(GodSystem.text("History_RecycleSelectionListOnly", "Listed {1} item types for {2} coins"), { #listRows, totalCost }) })
        GodSystem.save()
        local notifyKey = skipped > 0 and "Notify_RecycleSelectionListOnlyPartial" or "Notify_RecycleSelectionListOnly"
        GodSystem.notify(gsFormatText(GodSystem.text(notifyKey, "Listed {1} item types for {2} coins; skipped {3}"), { #listRows, totalCost, skipped }))
        return true
    end

    local rawPayout = 0
    for i = 1, #typeOrder do
        local row = types[typeOrder[i]]
        rawPayout = rawPayout + GodSystem.calculateRecyclePayout(row.fullType, row.raw, row.count)
    end
    if rawPayout <= 0 then return false end

    local removed = {}
    local primary = player:getPrimaryHandItem()
    local secondary = player:getSecondaryHandItem()
    for i = 1, #selected do
        local row = selected[i]
        local item = row.item
        local worn = player.isEquipped and player:isEquipped(item) == true
        local bodyLocation = item.canBeEquipped and item:canBeEquipped() or (item.getBodyLocation and item:getBodyLocation() or nil)
        if item == primary then player:setPrimaryHandItem(nil) end
        if item == secondary then player:setSecondaryHandItem(nil) end
        if worn and player.removeWornItem then pcall(function() player:removeWornItem(item, false) end) end
        local ok = pcall(function() row.container:Remove(item) end)
        if not ok or gsContainerContainsItem(row.container, item) then
            local current = {
                item = item,
                primary = item == primary,
                secondary = item == secondary,
                worn = worn,
                bodyLocation = bodyLocation,
            }
            if gsContainerContainsItem(row.container, item) then
                gsRestoreContextUseState(player, current)
            else
                removed[#removed + 1] = current
            end
            gsRestoreContextItems(player, removed)
            GodSystem.notify(GodSystem.text("Notify_RecycleSelectionFailed", "Recycle failed; items restored"))
            return false
        end
        removed[#removed + 1] = {
            item = item,
            primary = item == primary,
            secondary = item == secondary,
            worn = worn,
            bodyLocation = bodyLocation,
        }
    end

    local oldLimitDay = data.recycleLimitDay
    local oldLimitUsed = data.recycleLimitUsed
    local payout = GodSystem.applyRecycleDailyPayout(rawPayout)
    if payout > 0 and not GodSystem.giveCurrency(payout) then
        data.recycleLimitDay = oldLimitDay
        data.recycleLimitUsed = oldLimitUsed
        gsRestoreContextItems(player, removed)
        GodSystem.notify(GodSystem.text("Notify_RecycleSelectionFailed", "Recycle failed; items restored"))
        return false
    end
    if mode == "recycleAndList" then
        for i = 1, #typeOrder do
            local row = types[typeOrder[i]]
            GodSystem.unlockAutoShopItem(row.fullType, row.item:getDisplayName(), GodSystem.getItemSellPrice(row.fullType, row.item), row.item)
        end
    end
    data.stats.recycledItems = (data.stats.recycledItems or 0) + #removed
    data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
    local key = mode == "recycleAndList" and "Notify_RecycleSelectionAndList" or "Notify_RecycleSelectionSuccess"
    if skipped > 0 then key = key .. "Partial" end
    gsAppendHistory(data, { kind = "recycle", text = gsFormatText(GodSystem.text("History_RecycleSelection", "Recycled {1} items for {2} coins"), { #removed, payout }) })
    GodSystem.save()
    GodSystem.notify(gsFormatText(GodSystem.text(key, "Recycled {1} items for {2} coins; skipped {3}"), { #removed, payout, skipped }))
    return true
end

function GodSystem.generateTaskFromTemplate(template)
    local now = gsNowHours()
    return {
        taskId = tostring(template.id) .. "_" .. tostring(math.floor(now * 100)) .. "_" .. tostring(gsRandomIndex(9999)),
        sourceId = template.id,
        title = template.title,
        kind = template.kind,
        target = template.target,
        item = template.item,
        items = gsCopyStringArray(template.items),
        limitHours = template.limitHours or GodSystemConfig.DefaultTaskLimitHours,
        rewardPoints = GodSystemAdminConfig.applyTaskReward(template.rewardPoints or 0),
        rewardItems = gsCopyItems(template.rewardItems),
        penaltyPoints = GodSystemAdminConfig.applyTaskPenalty(template.penaltyPoints or 0),
        description = template.description,
        status = "open",
        createdAt = now,
        createdDay = gsCurrentDay(),
    }
end

function GodSystem.getActiveTaskCount()
    local data = GodSystem.getData()
    local count = 0
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "active" then
            count = count + 1
        end
    end
    return count
end

function GodSystem.isTaskTemplateAvailable(template)
    if not template then
        return false
    end
    local blacklist = GodSystemConfig.TaskItemBlacklist or {}
    if template.kind == "turnInItem" then
        return not blacklist[template.item] and GodSystem.itemExists(template.item)
    end
    if template.kind == "turnInAnyItem" then
        local items = template.items or {}
        for i = 1, #items do
            if not blacklist[items[i]] and GodSystem.itemExists(items[i]) then
                return true
            end
        end
        return false
    end
    return true
end

function GodSystem.getAvailableTaskTemplates()
    local result = {}
    local templates = GodSystemConfig.TaskTemplates or {}
    for i = 1, #templates do
        if GodSystem.isTaskTemplateAvailable(templates[i]) then
            table.insert(result, templates[i])
        end
    end
    if #result == 0 then
        return templates
    end
    return result
end

function GodSystem.generateDailyTasks(force)
    local data = GodSystem.getData()
    local day = gsCurrentDay()
    if not force and data.lastGeneratedDay == day then
        return
    end

    local kept = {}
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" then
            table.insert(kept, task)
        elseif task.status == "claimed" or task.status == "failed" then
            gsAppendHistory(data, { kind = "task", text = GodSystem.getTaskStatusText(task) .. ": " .. tostring(GodSystem.getTaskTitle(task)) })
        end
    end

    local templates = GodSystem.getAvailableTaskTemplates()
    local used = {}
    local count = math.min(GodSystem.getDailyTaskCount(), #templates)
    for _ = 1, count do
        local index = gsRandomIndex(#templates)
        local guard = 0
        while used[index] and guard < 30 do
            index = gsRandomIndex(#templates)
            guard = guard + 1
        end
        used[index] = true
        table.insert(kept, GodSystem.generateTaskFromTemplate(templates[index]))
    end

    data.lastGeneratedDay = day
    data.tasks = kept
    gsAppendHistory(data, { kind = "system", text = GodSystem.text("History_DailyTasks", "Daily tasks published x") .. tostring(count) })
    GodSystem.save()
end

function GodSystem.refreshOpenTasks()
    if GodSystem.isFeatureEnabled("EnableTasks") == false then
        GodSystem.notify("Tasks disabled")
        return false
    end
    local data = GodSystem.getData()
    local cost = GodSystemConfig.RefreshTaskCost or 0
    if not GodSystem.canAfford(cost) then
        GodSystem.notify(GodSystem.text("Notify_CannotRefresh", "Not enough currency to refresh tasks"))
        return false
    end

    local openCount = 0
    local activeCount = 0
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "open" then
            openCount = openCount + 1
        elseif data.tasks[i].status == "active" then
            activeCount = activeCount + 1
        end
    end
    if openCount <= 0 then
        if activeCount >= GodSystem.getMaxActiveTasks() then
            GodSystem.notify(GodSystem.text("Notify_CannotRefreshActiveFull", "Active task slots are full. Complete or abandon a task first."))
            return false
        end
        GodSystem.notify(GodSystem.text("Notify_NoOpenTask", "No open task to refresh"))
        return false
    end

    if not GodSystem.addPoints(-cost) then
        return false
    end
    local templates = GodSystem.getAvailableTaskTemplates()
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "open" then
            data.tasks[i] = GodSystem.generateTaskFromTemplate(templates[gsRandomIndex(#templates)])
        end
    end
    gsAppendHistory(data, { kind = "task", text = GodSystem.text("History_RefreshTasks", "Refreshed open tasks -") .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins") })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_RefreshTasks", "Refreshed open tasks -") .. tostring(cost) .. GodSystem.text("Unit_Coin", " coins"))
    return true
end

function GodSystem.acceptTask(task)
    if GodSystem.isFeatureEnabled("EnableTasks") == false then
        GodSystem.notify("Tasks disabled")
        return false
    end
    if not task or task.status ~= "open" then
        return false
    end
    if GodSystem.getActiveTaskCount() >= GodSystem.getMaxActiveTasks() then
        GodSystem.notify(GodSystem.text("Notify_ActiveTaskLimit", "Active task limit reached"))
        return false
    end

    local data = GodSystem.getData()
    local player = gsPlayer()
    task.status = "active"
    task.acceptedAt = gsNowHours()
    task.deadline = task.acceptedAt + (task.limitHours or GodSystemConfig.DefaultTaskLimitHours)
    task.startKills = player and player:getZombieKills() or 0
    task.killProgress = task.kind == "kill" and 0 or nil
    task.startRecycledItems = data.stats.recycledItems or 0
    task.startRecycledPoints = data.stats.recycledPoints or 0
    task.startSpentPoints = data.stats.spentPoints or 0
    task.startBoughtItems = data.stats.boughtItems or 0
    task.startMoveDistance = data.stats.moveDistance or 0
    gsAppendHistory(data, { kind = "task", text = GodSystem.text("History_AcceptTask", "Accepted task: ") .. tostring(GodSystem.getTaskTitle(task)) })
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_AcceptTask", "Accepted task: ") .. tostring(GodSystem.getTaskTitle(task)))
    return true
end

function GodSystem.getInventoryItemCount(fullType)
    local player = gsPlayer()
    if not player then
        return 0
    end
    return #gsFindInventoryItems(fullType, false, false)
end

function GodSystem.getAnyInventoryItemCount(fullTypes)
    local total = 0
    if not fullTypes then
        return total
    end
    for i = 1, #fullTypes do
        total = total + GodSystem.getInventoryItemCount(fullTypes[i])
    end
    return total
end

function GodSystem.getTaskProgress(task)
    if not task then
        return 0
    end

    local data = GodSystem.getData()
    local player = gsPlayer()
    if task.kind == "kill" then
        local kills = player and player.getZombieKills and player:getZombieKills() or 0
        return gsEnsureKillTaskProgress(task, kills)
    elseif task.kind == "recycleItems" then
        return math.max(0, (data.stats.recycledItems or 0) - (task.startRecycledItems or 0))
    elseif task.kind == "recyclePoints" then
        return math.max(0, (data.stats.recycledPoints or 0) - (task.startRecycledPoints or 0))
    elseif task.kind == "surviveHours" then
        return math.max(0, math.floor(gsNowHours() - (task.acceptedAt or gsNowHours())))
    elseif task.kind == "turnInItem" then
        return GodSystem.getInventoryItemCount(task.item)
    elseif task.kind == "turnInAnyItem" then
        return GodSystem.getAnyInventoryItemCount(task.items)
    elseif task.kind == "spendPoints" then
        return math.max(0, (data.stats.spentPoints or 0) - (task.startSpentPoints or 0))
    elseif task.kind == "buyItems" then
        return math.max(0, (data.stats.boughtItems or 0) - (task.startBoughtItems or 0))
    elseif task.kind == "moveDistance" then
        return math.max(0, math.floor((data.stats.moveDistance or 0) - (task.startMoveDistance or 0)))
    end
    return 0
end

function GodSystem.isTaskComplete(task)
    return GodSystem.getTaskProgress(task) >= (task.target or 1)
end

function GodSystem.isTaskExpired(task)
    return task and task.status == "active" and task.deadline and gsNowHours() > task.deadline
end

function GodSystem.getRemainingHours(task)
    if not task or not task.deadline then
        return task and (task.limitHours or GodSystemConfig.DefaultTaskLimitHours) or 0
    end
    return math.max(0, math.ceil(task.deadline - gsNowHours()))
end

function GodSystem.failTask(task, silent, historyKey)
    if not task or task.status ~= "active" then
        return false
    end
    local data = GodSystem.getData()
    task.status = "failed"
    task.failedAt = gsNowHours()
    data.stats.failedTasks = (data.stats.failedTasks or 0) + 1
    local paid, fromBank, fromCash = GodSystem.payTaskFailurePenalty(task.penaltyPoints or 0)
    local prefix = GodSystem.text(historyKey or "History_FailTask", "Task failed: ")
    gsAppendHistory(data, { kind = "task", text = prefix .. tostring(GodSystem.getTaskTitle(task)) .. GodSystem.text("History_Penalty", ", penalty ") .. tostring(paid or 0) .. "/" .. tostring(task.penaltyPoints or 0) .. GodSystem.text("Unit_Coin", " coins") .. " (" .. GodSystem.text("Bank_Current", "Current account") .. " " .. tostring(fromBank or 0) .. ", " .. GodSystem.text("Task_CashPenalty", "cash") .. " " .. tostring(fromCash or 0) .. ")" })
    GodSystem.save()
    if not silent then
        GodSystem.notify(GodSystem.text("Notify_FailTask", "Task failed: ") .. tostring(GodSystem.getTaskTitle(task)))
    end
    return true
end

function GodSystem.abandonTask(task)
    if not task or task.status ~= "active" then
        GodSystem.notify(GodSystem.text("Notify_SelectTask", "Select a task first"))
        return false
    end
    return GodSystem.failTask(task, false, "History_AbandonTask")
end

function GodSystem.claimTask(task, silent)
    if GodSystem.isFeatureEnabled("EnableTasks") == false then
        GodSystem.notify("Tasks disabled")
        return false
    end
    if not task or task.status ~= "active" then
        return false
    end

    if GodSystem.isTaskExpired(task) and not GodSystem.isTaskComplete(task) then
        GodSystem.failTask(task, false, "History_TaskTimeout")
        return false
    end

    if not GodSystem.isTaskComplete(task) then
        GodSystem.notify(GodSystem.text("Notify_TaskIncomplete", "Task incomplete"))
        return false
    end

    if task.kind == "turnInItem" then
        local removed = select(1, GodSystem.removeInventoryItems(task.item, task.target or 1))
        if removed < (task.target or 1) then
            GodSystem.notify(GodSystem.text("Notify_TurnInNotEnough", "Not enough items"))
            return false
        end
    elseif task.kind == "turnInAnyItem" then
        local removed = select(1, GodSystem.removeAnyInventoryItems(task.items, task.target or 1))
        if removed < (task.target or 1) then
            GodSystem.notify(GodSystem.text("Notify_TurnInNotEnough", "Not enough items"))
            return false
        end
    end

    local data = GodSystem.getData()
    if (task.rewardPoints or 0) > 0 then
        GodSystem.addPoints(task.rewardPoints)
    end
    GodSystem.giveItems(task.rewardItems)
    task.status = "claimed"
    task.claimedAt = gsNowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    gsAppendHistory(data, { kind = "task", text = GodSystem.text("History_ClaimTask", "Task completed: ") .. tostring(GodSystem.getTaskTitle(task)) })
    GodSystem.save()
    if not silent then
        GodSystem.notify(GodSystem.text("Notify_ClaimTask", "Task completed: ") .. tostring(GodSystem.getTaskTitle(task)))
    end
    return true
end

function GodSystem.toggleAutoTaskClaim()
    local data = GodSystem.getData()
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled ~= true
    data.lastAutoTaskClaimHour = gsNowHours()
    GodSystem.save()
    GodSystem.notify(GodSystem.text(data.autoTaskClaimEnabled and "Notify_AutoTaskClaimEnabled" or "Notify_AutoTaskClaimDisabled", data.autoTaskClaimEnabled and "Auto task claim enabled" or "Auto task claim disabled"))
    return data.autoTaskClaimEnabled
end

function GodSystem.processAutoTaskClaim()
    local data = GodSystem.getData()
    if data.autoTaskClaimEnabled ~= true then return false end
    local nowHour = gsNowHours()
    if nowHour < (data.lastAutoTaskClaimHour or nowHour) then
        data.lastAutoTaskClaimHour = nowHour
    end
    if nowHour - (data.lastAutoTaskClaimHour or nowHour) < 1 then
        return false
    end
    data.lastAutoTaskClaimHour = nowHour
    local claimed = 0
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" and GodSystem.isTaskComplete(task) then
            if GodSystem.claimTask(task, true) then
                claimed = claimed + 1
            end
        end
    end
    GodSystem.save()
    if claimed > 0 then
        GodSystem.notify(gsFormatText(GodSystem.text("Notify_AutoTaskClaimed", "Automatically claimed {1} task(s)"), { claimed }))
        return true
    end
    return false
end

function GodSystem.getTaskStatusText(task)
    if not task then
        return ""
    end
    if task.status == "open" then
        return GodSystem.text("Status_Open", "Open")
    elseif task.status == "active" then
        if GodSystem.isTaskExpired(task) and not GodSystem.isTaskComplete(task) then
            return GodSystem.text("Status_Expired", "Expired")
        end
        return GodSystem.text("Status_Active", "Active")
    elseif task.status == "claimed" then
        return GodSystem.text("Status_Claimed", "Claimed")
    elseif task.status == "failed" then
        return GodSystem.text("Status_Failed", "Failed")
    end
    return task.status or ""
end

function GodSystem.getRewardText(points, items)
    local reward = {}
    if (points or 0) > 0 then
        table.insert(reward, tostring(points) .. GodSystem.text("Unit_Coin", " coins"))
    end
    if items then
        for i = 1, #items do
            local item = items[i]
            table.insert(reward, GodSystem.getItemDisplayName(item.fullType) .. " x" .. tostring(item.count or 1))
        end
    end
    if #reward == 0 then
        return GodSystem.text("None", "None")
    end
    return table.concat(reward, ", ")
end

function GodSystem.getTaskDetailLines(task)
    if not task then
        return {}
    end
    local progress = GodSystem.getTaskProgress(task)
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    local rewardText = GodSystem.getRewardText(task.rewardPoints, task.rewardItems)
    local limit = task.limitHours or GodSystemConfig.DefaultTaskLimitHours
    local lines = {
        GodSystem.getTaskListTitle(task),
        GodSystem.text("Task_Type", "Type") .. ": " .. GodSystem.getTaskKindLabel(task),
        GodSystem.text("Task_Difficulty", "Difficulty") .. ": " .. GodSystem.getTaskDifficulty(task),
        GodSystem.text("Task_Target", "Target") .. ": " .. tostring(task.target or 1),
        GodSystem.text("Task_Progress", "Progress") .. ": " .. tostring(math.min(progress, target)) .. "/" .. tostring(target),
        GodSystem.text("Task_Limit", "Limit") .. ": " .. tostring(limit) .. GodSystem.text("Unit_Hour", "h"),
    }
    if task.status == "active" then
        table.insert(lines, GodSystem.text("Task_Remaining", "Remaining") .. ": " .. tostring(GodSystem.getRemainingHours(task)) .. GodSystem.text("Unit_Hour", "h"))
    end
    local description = GodSystem.getTaskDescription(task)
    if description and description ~= "" then
        table.insert(lines, description)
    end
    table.insert(lines, "")
    table.insert(lines, GodSystem.text("TaskSection_Reward", "Reward"))
    table.insert(lines, rewardText)
    table.insert(lines, "")
    table.insert(lines, GodSystem.text("TaskSection_Penalty", "Failure penalty"))
    table.insert(lines, tostring(task.penaltyPoints or 0) .. GodSystem.text("Unit_Coin", " coins") .. " - " .. GodSystem.text("Task_PenaltyBankFirst", "deduct current account first, then cash"))
    return lines
end

function GodSystem.getTaskDetailText(task)
    return table.concat(GodSystem.getTaskDetailLines(task), "\n")
end

function GodSystem.updateKillRewards()
    local data = GodSystem.getData()
    local player = gsPlayer()
    if not player then
        return
    end
    local kills = player:getZombieKills()
    if data.lastKnownKills == nil then
        data.lastKnownKills = kills
        return
    end
    local delta = kills - data.lastKnownKills
    if delta > 0 then
        data.lastKnownKills = kills
        GodSystem.updateKillTaskProgress(delta, kills - delta)
        GodSystem.addPoints(delta * (GodSystemConfig.KillPointReward or 0), GodSystem.text("Reason_KillZombie", "Zombie kill"))
    elseif delta < 0 then
        GodSystem.normalizeActiveKillTasks(data.lastKnownKills)
        data.lastKnownKills = kills
        GodSystem.save()
    end
end

function GodSystem.updateTaskTimeouts()
    local data = GodSystem.getData()
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" and GodSystem.isTaskExpired(task) and not GodSystem.isTaskComplete(task) then
            GodSystem.failTask(task, false, "History_TaskTimeout")
        end
    end
end

function GodSystem.failActiveTasksOnDeath()
    local data = GodSystem.getData()
    local failed = 0
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" then
            if GodSystem.failTask(task, true, "History_TaskDeathFailed") then
                failed = failed + 1
            end
        end
    end
    return failed
end

function GodSystem.handlePlayerDeath()
    local data = GodSystem.getData()
    local changed = false
    if GodSystem.applyBankDeathPenalty() then
        changed = true
    end
    if GodSystem.failActiveTasksOnDeath() > 0 then
        changed = true
    end
    if changed then
        GodSystem.notify(GodSystem.text("Notify_DeathHandled", "Death settlement completed"))
        GodSystem.save()
    end
    return changed
end

function GodSystem.updateMoveDistance(player)
    player = player or gsPlayer()
    if not player or not player.getX or not player.getY then
        return
    end

    local data = GodSystem.getData()
    local x = player:getX()
    local y = player:getY()
    local z = player.getZ and player:getZ() or 0
    if not data.lastMoveX or not data.lastMoveY then
        data.lastMoveX = x
        data.lastMoveY = y
        data.lastMoveZ = z
        return
    end

    if z ~= data.lastMoveZ then
        data.lastMoveX = x
        data.lastMoveY = y
        data.lastMoveZ = z
        return
    end

    local dx = x - data.lastMoveX
    local dy = y - data.lastMoveY
    local distance = math.sqrt((dx * dx) + (dy * dy))
    data.lastMoveX = x
    data.lastMoveY = y
    data.lastMoveZ = z

    if distance > 0.05 and distance < 80 then
        data.stats = data.stats or {}
        data.stats.moveDistance = (data.stats.moveDistance or 0) + distance
    end
end

function GodSystem.onPlayerUpdate(player)
    if not player or player ~= gsPlayer() then
        return
    end
    GodSystem.updateTicks = (GodSystem.updateTicks or 0) + 1
    if GodSystem.updateTicks % 60 ~= 0 then
        return
    end
    GodSystem.updateMoveDistance(player)
    GodSystem.generateDailyTasks(false)
    GodSystem.updateKillRewards()
    GodSystem.updateTaskTimeouts()
    if GodSystem.updateTicks % 300 == 0 then
        GodSystem.refreshAutoRecyclerContainers(false)
    end
    GodSystem.updateAutoRecycler()
    GodSystem.processAutoTaskClaim()
    GodSystem.processBankAutoDeposit()
    GodSystem.updateBankInvestments()
    GodSystem.updateHomeSafeZone()
end

function GodSystem.onPlayerDeath(player)
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true then
        return
    end
    if player and type(player) ~= "number" and player ~= gsPlayer() then
        return
    end
    GodSystem.autoRecyclerCache = nil
    GodSystemCarryCapacity.clearRuntime(type(player) == "number" and nil or player)
    GodSystem.normalizeActiveKillTasks()
    GodSystem.handlePlayerDeath()
end

function GodSystem.onGameStart()
    local data = GodSystem.getData()
    GodSystem.applyCarryCapacity(gsPlayer(), data)
    GodSystem.ensureCurrencyInitialized()
    GodSystem.generateDailyTasks(false)
    GodSystem.refreshAutoRecyclerContainers(true)
end

function GodSystem.onCreatePlayer(_, player)
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true then return end
    GodSystemCarryCapacity.clearRuntime(player)
    GodSystem.applyCarryCapacity(player or gsPlayer(), GodSystem.getData())
end

function GodSystem.onInitGlobalModData()
    GodSystem.getData()
end

function GodSystem.onGameExit()
    GodSystem.autoRecyclerCache = nil
end

function GodSystem.debugAddPoints()
    if not GodSystemConfig.EnableDebugTools then
        return false
    end
    GodSystem.addPoints(500, GodSystem.text("Reason_Debug", "Debug"))
    return true
end

if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(GodSystem.onInitGlobalModData)
end
if Events.OnGameStart then
    Events.OnGameStart.Add(GodSystem.onGameStart)
end
if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(GodSystem.onCreatePlayer)
end
if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(GodSystem.onPlayerUpdate)
end
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(GodSystem.onPlayerDeath)
end
if Events.OnGameExit then
    Events.OnGameExit.Add(GodSystem.onGameExit)
end
