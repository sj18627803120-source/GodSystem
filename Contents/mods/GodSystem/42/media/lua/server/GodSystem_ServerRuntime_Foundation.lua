_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Foundation"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Foundation then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Foundation = true
    setfenv(1, runtimeEnvironment)

function GodSystemServer.getConfiguredShopKeySet()
    local result = {}
    for key, value in pairs(GodSystemServer.configuredShopKeySet or {}) do result[key] = value end
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

Protocol = GodSystemProtocol or {}
MODULE = Protocol.Module or "GodSystem"
STORE_KEY = (GodSystemConfig.DataKey or "GodSystem_CN_Data") .. "_MP"
BAL_STORE_KEY = STORE_KEY .. "_Balance"
LEGACY_ADMIN_CONFIG_KEY = STORE_KEY .. "_AdminConfig"
ITEM_CONFIG_KEY = STORE_KEY .. "_ItemConfig"

pending = {}
diagnostics = {
    handledCommands = 0,
    failedCommands = 0,
    lastCommand = nil,
    lastError = nil,
    lastResultOk = nil,
    lastResultMessage = nil,
}

function nowHours()
    if GameTime and GameTime:getInstance() then
        return GameTime:getInstance():getWorldAgeHours()
    end
    return 0
end

function currentDay()
    return math.floor(nowHours() / 24)
end

function n(v, fallback)
    local value = tonumber(v)
    if value == nil then return fallback or 0 end
    return value
end

function floor(v, fallback)
    return math.floor(n(v, fallback or 0))
end

function safeCall(object, methodName, fallback, ...)
    return GodSystemB42JavaCalls.value(object, methodName, fallback, ...)
end

function userKey(player)
    if player and player.getUsername then
        local u = player:getUsername()
        if u and u ~= "" then return tostring(u) end
    end
    if player and player.getOnlineID then
        local id = player:getOnlineID()
        if id ~= nil then return "id:" .. tostring(id) end
    end
    return "unknown"
end

function store()
    if ModData and ModData.getOrCreate then
        local data = ModData.getOrCreate(STORE_KEY)
        data.players = data.players or {}
        return data
    end
    _G.__GodSystemServerStore = _G.__GodSystemServerStore or { players = {} }
    return _G.__GodSystemServerStore
end

function GodSystemServer.clearDisabledShopListings(fullType, variantKey)
    local root = store()
    local removed = 0
    for _, data in pairs(root.players or {}) do
        removed = removed + GodSystemShopVariants.removeMatchingUnlocked(data, fullType, variantKey)
    end
    return removed
end

function storeCheckpoint()
    -- ModData is persisted by the server save cycle. Broadcasting this private
    -- player store exposed every player's data and caused large bandwidth spikes.
    return true
end

function itemConfigStore()
    if ModData and ModData.getOrCreate then
        local data = ModData.getOrCreate(ITEM_CONFIG_KEY)
        local legacy = ModData.getOrCreate(LEGACY_ADMIN_CONFIG_KEY)
        return GodSystemItemConfig.migrate(data, legacy)
    end
    _G.__GodSystemItemConfigStore = GodSystemItemConfig.migrate(
        _G.__GodSystemItemConfigStore or {},
        _G.__GodSystemAdminConfigStore or {}
    )
    return _G.__GodSystemItemConfigStore
end

function applyRuntimeStores()
    GodSystemRuntimeConfig.readSandbox()
    local data = itemConfigStore()
    GodSystemItemConfig.applyRuntime(data.itemOverrides, data.shopVariantOverrides, data.economyRevision)
    return data
end

function isAdminPlayer(player)
    if not player then return false end
    if player.isAccessLevel then
        local levels = { "Admin", "Moderator", "Overseer", "GM" }
        for i = 1, #levels do
            local ok, allowed = GodSystemB42JavaCalls.try(player, "isAccessLevel", levels[i])
            if ok and allowed == true then return true end
        end
    end
    if player.getAccessLevel then
        local ok, level = GodSystemB42JavaCalls.try(player, "getAccessLevel")
        if ok and level then
            level = tostring(level):lower()
            return level == "admin" or level == "moderator" or level == "overseer" or level == "gm"
        end
    end
    return false
end

function markInventoryDirty(player, container)
    container = container or (player and player.getInventory and player:getInventory() or nil)
    if container and container.setDrawDirty then
        pcall(function() container:setDrawDirty(true) end)
    end
    if player and sendServerCommand then
        pcall(function() sendServerCommand(player, "ui", "DirtyUI", {}) end)
    end
end

function copyStringArray(items)
    local result = {}
    if not items then return result end
    for i = 1, #items do result[i] = items[i] end
    return result
end

function copyItems(items)
    local result = {}
    if not items then return result end
    for i = 1, #items do
        result[i] = { fullType = items[i].fullType, count = items[i].count or 1 }
    end
    return result
end

function copyPosition(pos)
    if not pos then return nil end
    return {
        x = n(pos.x),
        y = n(pos.y),
        z = n(pos.z),
        label = pos.label,
        source = pos.source,
    }
end

function appendHistory(data, entry)
    data.history = data.history or {}
    entry.time = nowHours()
    table.insert(data.history, 1, entry)
    local limit = GodSystemConfig.HistoryLimit or 40
    while #data.history > limit do
        table.remove(data.history)
    end
end

function randomIndex(max)
    max = floor(max, 1)
    if max <= 1 then return 1 end
    if ZombRand then return ZombRand(max) + 1 end
    return math.random(max)
end

BANK_INVESTMENT_IDS = { "stable", "balanced", "aggressive" }

function normalizeBankInvestments(bank)
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
        account.balance = math.max(0, floor(account.balance, 0))
        account.onlineHours = math.max(0, n(account.onlineHours, 0))
        account.settlementCount = math.max(0, floor(account.settlementCount, 0))
        account.redeemUnlocked = account.redeemUnlocked == true
        account.lastDelta = floor(account.lastDelta, 0)
        account.lastOutcome = tostring(account.lastOutcome or "flat")
        account.lastSettledHour = tonumber(account.lastSettledHour)
    end
    return bank.investments
end

function playerData(player)
    local root = store()
    local key = userKey(player)
    root.players[key] = root.players[key] or {}
    local data = root.players[key]
    data.version = GodSystemConfig.Version
    data.lastGeneratedDay = data.lastGeneratedDay or -1
    data.tasks = data.tasks or {}
    data.history = data.history or {}
    data.unlockedShopItems = data.unlockedShopItems or {}
    GodSystemShopVariants.normalizeUnlocked(data, GodSystemServer.getConfiguredShopKeySet())
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
    data.recycleLimitDay = data.recycleLimitDay or currentDay()
    data.recycleLimitUsed = data.recycleLimitUsed or 0
    if data.recycleUnlockMode == nil then data.recycleUnlockMode = true end
    data.upgrades = data.upgrades or {}
    data.upgrades.maxActiveTasks = math.max(GodSystemConfig.MaxActiveTasks or 3, floor(data.upgrades.maxActiveTasks, GodSystemConfig.MaxActiveTasks or 3))
    data.upgrades.maxActiveTasks = math.min(data.upgrades.maxActiveTasks, GodSystemConfig.MaxActiveTaskLimit or 10)
    data.upgrades.dailyTaskCount = math.max(GodSystemConfig.DailyTaskCount or 5, floor(data.upgrades.dailyTaskCount, GodSystemConfig.DailyTaskCount or 5))
    data.upgrades.dailyTaskCount = math.min(data.upgrades.dailyTaskCount, GodSystemConfig.MaxDailyTaskLimit or 20)
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.getLevel(data, player)
    data.homeSystem = data.homeSystem or {}
    data.homeSystem.tempSlots = data.homeSystem.tempSlots or {}
    data.homeSystem.returnPoint = data.homeSystem.returnPoint or nil
    data.homeSystem.safeZone = data.homeSystem.safeZone or {}
    data.homeSystem.safeZone.level = math.max(0, floor(data.homeSystem.safeZone.level, 0))
    data.homeSystem.safeZone.enabled = data.homeSystem.safeZone.enabled == true
    data.homeSystem.safeZone.lastScanHours = n(data.homeSystem.safeZone.lastScanHours, 0)
    data.homeSystem.safeZone.lastNoticeHours = n(data.homeSystem.safeZone.lastNoticeHours, -999)
    data.homeSystem.safeZone.lastCleared = math.max(0, floor(data.homeSystem.safeZone.lastCleared, 0))
    data.homeSystem.safeZone.lastClearHour = n(data.homeSystem.safeZone.lastClearHour, 0)
    data.homeSystem.safeZone.nextZombieScanIndex = math.max(0, floor(data.homeSystem.safeZone.nextZombieScanIndex, 0))
    data.bank = data.bank or {}
    data.bank.current = math.max(0, floor(data.bank.current, 0))
    data.bank.fixed = data.bank.fixed or {}
    data.bank.nextId = math.max(1, floor(data.bank.nextId, 1))
    data.bank.lastDeathPenaltyHour = n(data.bank.lastDeathPenaltyHour, -999)
    data.bank.autoDepositEnabled = data.bank.autoDepositEnabled == true
    data.bank.lastAutoDepositHour = tonumber(data.bank.lastAutoDepositHour) or nowHours()
    normalizeBankInvestments(data.bank)
    data.bank.nextLoanId = math.max(1, floor(data.bank.nextLoanId, 1))
    data.bank.loanFrozenUntilHour = n(data.bank.loanFrozenUntilHour, 0)
    data.bank.loanCreditSpentOffset = math.max(0, floor(data.bank.loanCreditSpentOffset, 0))
    data.bank.loanBankruptcyCount = math.max(0, floor(data.bank.loanBankruptcyCount, 0))
    local tempLimit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, tempLimit do
        data.homeSystem.tempSlots[i] = data.homeSystem.tempSlots[i] or { owned = false, point = nil }
        data.homeSystem.tempSlots[i].owned = data.homeSystem.tempSlots[i].owned == true
    end
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled == true
    data.lastAutoTaskClaimHour = tonumber(data.lastAutoTaskClaimHour) or nowHours()
    data.ui = data.ui or {}
    return data
end

function notify(player, text)
    local code = tostring(text or "")
    if code == "Not enough currency for safe zone cleanup" then
        code = "CurrencyNotEnough"
    elseif code == "" then
        code = "OperationSucceeded"
    else
        code = "OperationSucceeded"
    end
    notifyCode(player, code, {})
end

function notifyCode(player, code, args)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Notify) or "notify", { code = tostring(code or ""), args = args or {} })
end

function errorMessage(player, text)
    diagnostics.lastError = tostring(text or "")
    errorCode(player, "ServerCommandFailed", {})
end

function errorCode(player, code, args)
    diagnostics.lastError = tostring(code or "")
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Error) or "error", { code = tostring(code or ""), args = args or {} })
end

function historyEntry(kind, code, args)
    return { kind = tostring(kind or "system"), code = tostring(code or ""), args = args or {} }
end

function taskHistoryEntry(code, task, args)
    return {
        kind = "task",
        code = tostring(code or ""),
        taskId = task and task.sourceId or nil,
        args = args or {},
    }
end

function shopHistoryEntry(code, row, args)
    return {
        kind = "shop",
        code = tostring(code or ""),
        shopId = row and row.id or nil,
        shopItems = row and row.items or nil,
        args = args or {},
    }
end

function getBalanceStore()
    if ModData and ModData.getOrCreate then
        return ModData.getOrCreate(BAL_STORE_KEY)
    end
    _G.__GodSystemServerBalanceStore = _G.__GodSystemServerBalanceStore or {}
    return _G.__GodSystemServerBalanceStore
end

function countContainerItems(container, fullType)
    if not container or not container.getItems then return 0 end
    local total = 0
    local items = container:getItems()
    if not items or not items.size then return 0 end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if item.getFullType and item:getFullType() == fullType then
                total = total + 1
            end
            if item.getInventory then
                local ok, child = GodSystemB42JavaCalls.try(item, "getInventory")
                if ok and child then
                    total = total + countContainerItems(child, fullType)
                end
            end
        end
    end
    return total
end

function getBalance(player)
    local inv = player and player.getInventory and player:getInventory() or nil
    local total = 0
    for i = 1, #(GodSystemConfig.CurrencyItems or {}) do
        local denom = GodSystemConfig.CurrencyItems[i]
        local count = inv and countContainerItems(inv, denom.fullType) or 0
        total = total + count * (denom.value or 0)
    end
    local bs = getBalanceStore()
    bs[userKey(player)] = total
    return total
end

function itemExists(fullType)
    if not fullType then return false end
    if getScriptManager and getScriptManager() then
        return getScriptManager():FindItem(fullType) ~= nil
    end
    return true
end

function findInventoryItems(container, result, fullType, includeFavorite, includeEquipped, player)
    if not container or not container.getItems then return end
    local primary = player and player.getPrimaryHandItem and player:getPrimaryHandItem() or nil
    local secondary = player and player.getSecondaryHandItem and player:getSecondaryHandItem() or nil
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local matches = (not fullType) or item:getFullType() == fullType
            local equipped = item == primary or item == secondary
            local favorite = false
            if item.isFavorite then
                local ok, value = GodSystemB42JavaCalls.try(item, "isFavorite")
                favorite = ok and value == true
            end
            if matches and (includeEquipped or not equipped) and (includeFavorite or not favorite) then
                result[#result + 1] = { item = item, container = container }
            end
            if item.getInventory then
                local ok, child = GodSystemB42JavaCalls.try(item, "getInventory")
                if ok and child then
                    findInventoryItems(child, result, fullType, includeFavorite, includeEquipped, player)
                end
            end
        end
    end
end

function inventoryItems(player, fullType, includeFavorite, includeEquipped)
    local result = {}
    if player and player.getInventory then
        findInventoryItems(player:getInventory(), result, fullType, includeFavorite, includeEquipped, player)
    end
    return result
end

function inventoryItemById(player, itemId)
    itemId = tostring(itemId or "")
    if itemId == "" then return nil, nil end
    local found = inventoryItems(player, nil, true, true)
    for i = 1, #found do
        local item = found[i].item
        if tostring(GodSystemMaintenance.itemId(item) or "") == itemId then
            return item, found[i].container
        end
    end
    return nil, nil
end

function giveItem(player, fullType, count)
    if not player or not fullType or not itemExists(fullType) then return false, {} end
    count = math.max(1, floor(count, 1))
    local inv = player:getInventory()
    local added = {}
    for _ = 1, count do
        local item = inv:AddItem(fullType)
        if not item then
            for i = 1, #added do
                inv:Remove(added[i])
                if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, inv, added[i]) end
            end
            return false, {}
        end
        added[#added + 1] = item
        if sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
    end
    markInventoryDirty(player, inv)
    return true, added
end

function GodSystemServerContainerContainsItem(container, item)
    if not container or not item or not container.getItems then return false end
    local ok, contains = pcall(function()
        local items = container:getItems()
        return items and items.contains and items:contains(item) == true
    end)
    return ok and contains == true
end

function GodSystemServerContainerContentSignature(item)
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

function removeItemFromContainer(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:Remove(item) end)
    if not ok or GodSystemServerContainerContainsItem(container, item) then return false end
    if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, item) end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    return true
end

function restoreRemovedCurrency(player, removed)
    local okAll = true
    local byType = {}
    for i = 1, #(removed or {}) do
        local fullType = removed[i].fullType
        if fullType then
            byType[fullType] = byType[fullType] or { count = 0, value = math.max(1, floor(removed[i].value, 1)) }
            byType[fullType].count = byType[fullType].count + 1
        end
    end
    local failedValue = 0
    for fullType, row in pairs(byType) do
        local ok, added = giveItem(player, fullType, row.count)
        if not ok or #added < row.count then
            okAll = false
            failedValue = failedValue + row.count * row.value
        end
    end
    return okAll, failedValue
end

function giveCurrency(player, amount)
    amount = floor(amount, 0)
    if amount <= 0 then return true end
    local granted = {}
    for i = 1, #(GodSystemConfig.CurrencyItems or {}) do
        local denom = GodSystemConfig.CurrencyItems[i]
        local value = denom.value or 1
        local count = math.floor(amount / value)
        if count > 0 then
            local ok, added = giveItem(player, denom.fullType, count)
            if not ok or #added < count then
                local inv = player:getInventory()
                for j = 1, #granted do removeItemFromContainer(inv, granted[j]) end
                return false
            end
            for j = 1, #added do granted[#granted + 1] = added[j] end
            amount = amount - count * value
        end
    end
    return true
end

function consolidateCurrency(player)
    local total = 0
    local removed = {}
    local originalCount = 0
    for i = 1, #(GodSystemConfig.CurrencyItems or {}) do
        local denom = GodSystemConfig.CurrencyItems[i]
        local value = math.max(1, floor(denom.value, 1))
        local found = inventoryItems(player, denom.fullType, true, true)
        for j = 1, #found do
            if not removeItemFromContainer(found[j].container, found[j].item) then
                GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
                return false, total, originalCount, 0
            end
            removed[#removed + 1] = { fullType = denom.fullType, value = value }
            total = total + value
            originalCount = originalCount + 1
        end
    end
    if total <= 0 then
        return false, 0, 0, 0
    end
    if not giveCurrency(player, total) then
        GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
        return false, total, originalCount, 0
    end
    local newCount = 0
    local remaining = total
    for i = 1, #(GodSystemConfig.CurrencyItems or {}) do
        local value = math.max(1, floor(GodSystemConfig.CurrencyItems[i].value, 1))
        local count = math.floor(remaining / value)
        newCount = newCount + count
        remaining = remaining - (count * value)
    end
    return true, total, originalCount, newCount
end

function removeCurrency(player, amount)
    amount = floor(amount, 0)
    if amount <= 0 then return true end
    local total = getBalance(player)
    if total < amount then return false end
    local remaining = amount
    local removedValue = 0
    local removed = {}
    for i = 1, #(GodSystemConfig.CurrencyItems or {}) do
        if remaining <= 0 then break end
        local denom = GodSystemConfig.CurrencyItems[i]
        local value = math.max(1, floor(denom.value, 1))
        local need = math.floor(remaining / value)
        if need > 0 then
            local found = inventoryItems(player, denom.fullType, true, true)
            for j = 1, #found do
                if need <= 0 then break end
                if not removeItemFromContainer(found[j].container, found[j].item) then
                    GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
                    return false
                end
                removed[#removed + 1] = { fullType = denom.fullType, value = value }
                removedValue = removedValue + value
                remaining = remaining - value
                need = need - 1
            end
        end
    end
    if remaining > 0 then
        for i = #(GodSystemConfig.CurrencyItems or {}), 1, -1 do
            if remaining <= 0 then break end
            local denom = GodSystemConfig.CurrencyItems[i]
            local value = math.max(1, floor(denom.value, 1))
            local found = inventoryItems(player, denom.fullType, true, true)
            for j = 1, #found do
                if not removeItemFromContainer(found[j].container, found[j].item) then
                    GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
                    return false
                end
                removed[#removed + 1] = { fullType = denom.fullType, value = value }
                removedValue = removedValue + value
                remaining = remaining - value
                break
            end
        end
    end
    if removedValue < amount then
        GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
        return false
    end
    local change = removedValue - amount
    if change > 0 and not giveCurrency(player, change) then
        GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
        return false
    end
    return true
end

function canAfford(player, cost, data)
    data = data or playerData(player)
    return spendableBalance(player, data) >= math.max(0, floor(cost, 0))
end

function addPoints(player, amount, data)
    amount = floor(amount, 0)
    if amount == 0 then return true end
    if amount > 0 then return giveCurrency(player, amount) end
    data = data or playerData(player)
    return spendCurrency(player, data, math.abs(amount))
end

function getBank(data)
    data.bank = data.bank or {}
    local bank = data.bank
    bank.current = math.max(0, floor(bank.current, 0))
    bank.fixed = bank.fixed or {}
    bank.nextId = math.max(1, floor(bank.nextId, 1))
    bank.lastDeathPenaltyHour = n(bank.lastDeathPenaltyHour, -999)
    bank.nextLoanId = math.max(1, floor(bank.nextLoanId, 1))
    bank.loanFrozenUntilHour = n(bank.loanFrozenUntilHour, 0)
    bank.loanCreditSpentOffset = math.max(0, floor(bank.loanCreditSpentOffset, 0))
    bank.loanBankruptcyCount = math.max(0, floor(bank.loanBankruptcyCount, 0))
    bank.autoDepositEnabled = bank.autoDepositEnabled == true
    bank.lastAutoDepositHour = tonumber(bank.lastAutoDepositHour) or nowHours()
    normalizeBankInvestments(bank)
    local now = nowHours()
    for i = #bank.fixed, 1, -1 do
        local entry = bank.fixed[i]
        if not entry or math.max(0, floor(entry.principal, 0)) <= 0 then
            table.remove(bank.fixed, i)
        else
            entry.id = tostring(entry.id or ("F" .. tostring(i)))
            entry.termId = tostring(entry.termId or "")
            entry.principal = math.max(0, floor(entry.principal, 0))
            entry.startHour = n(entry.startHour, now)
            entry.matureHour = n(entry.matureHour, entry.startHour)
            entry.rate = n(entry.rate, 0)
            entry.days = math.max(1, floor(entry.days, math.max(1, math.ceil((entry.matureHour - entry.startHour) / 24))))
        end
    end
    if type(bank.loan) == "table" then
        local loan = bank.loan
        loan.id = tostring(loan.id or ("L" .. tostring(bank.nextLoanId or 1)))
        loan.kind = tostring(loan.kind or "single")
        loan.planId = tostring(loan.planId or loan.kind or "single")
        loan.principal = math.max(0, floor(loan.principal, 0))
        loan.createdHour = n(loan.createdHour, now)
        loan.totalInterest = math.max(0, floor(loan.totalInterest, 0))
        loan.totalDue = math.max(loan.principal + loan.totalInterest, floor(loan.totalDue, 0))
        loan.paid = math.max(0, floor(loan.paid, 0))
        loan.schedule = type(loan.schedule) == "table" and loan.schedule or {}
        loan.overdueStartHour = tonumber(loan.overdueStartHour)
        for i = #loan.schedule, 1, -1 do
            local bill = loan.schedule[i]
            if type(bill) ~= "table" then
                table.remove(loan.schedule, i)
            else
                bill.index = math.max(1, floor(bill.index, i))
                bill.dueHour = n(bill.dueHour, loan.createdHour)
                bill.principalPart = math.max(0, floor(bill.principalPart, 0))
                bill.interestPart = math.max(0, floor(bill.interestPart, 0))
                bill.paid = math.max(0, floor(bill.paid, 0))
            end
        end
        if loan.principal <= 0 or loan.totalDue <= 0 or loan.paid >= loan.totalDue then
            bank.loan = nil
        end
    else
        bank.loan = nil
    end
    return bank
end

function spendableBalance(player, data)
    local bank = getBank(data)
    return math.max(0, floor(bank.current, 0)) + math.max(0, getBalance(player))
end

function spendCurrency(player, data, amount)
    amount = math.max(0, floor(amount, 0))
    if amount <= 0 then return true, 0, 0 end
    local bank = getBank(data)
    local current = math.max(0, floor(bank.current, 0))
    local cash = math.max(0, getBalance(player))
    if current + cash < amount then
        return false, 0, 0
    end
    local fromBank = math.min(current, amount)
    if fromBank > 0 then
        bank.current = math.max(0, current - fromBank)
    end
    local fromCash = amount - fromBank
    if fromCash > 0 and not removeCurrency(player, fromCash) then
        if fromBank > 0 then
            bank.current = (bank.current or 0) + fromBank
        end
        return false, 0, 0
    end
    return true, fromBank, fromCash
end
end
