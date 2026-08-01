require "GodSystem_Config"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_Localization"
require "GodSystem_Localization_Override"
require "GodSystem_Protocol"
require "GodSystem_AdminConfig"
require "GodSystem_Maintenance"
require "GodSystem_Attributes"
require "GodSystem_CarryCapacity"
require "GodSystem_TransactionOps"
require "GodSystem_TerminalUpgrades"
require "GodSystem_TerminalFood"
require "GodSystem_ShopVariants"
require "GodSystem_Storage"

if not (isServer and isServer()) then return end

GodSystemServer = GodSystemServer or {}
GodSystemServer.terminalCache = GodSystemServer.terminalCache or {}
GodSystemServer.configuredShopKeySet = GodSystemShopVariants.getConfiguredKeySet(GodSystemConfig.ShopItems or {})

local Protocol = GodSystemProtocol or {}
local MODULE = Protocol.Module or "GodSystem"
local STORE_KEY = (GodSystemConfig.DataKey or "GodSystem_CN_Data") .. "_MP"
local BAL_STORE_KEY = STORE_KEY .. "_Balance"
local ADMIN_CONFIG_KEY = STORE_KEY .. "_AdminConfig"

local pending = {}
local diagnostics = {
    handledCommands = 0,
    failedCommands = 0,
    lastCommand = nil,
    lastError = nil,
    lastResultOk = nil,
    lastResultMessage = nil,
}

local function nowHours()
    if GameTime and GameTime:getInstance() then
        return GameTime:getInstance():getWorldAgeHours()
    end
    return 0
end

local function currentDay()
    return math.floor(nowHours() / 24)
end

local function n(v, fallback)
    local value = tonumber(v)
    if value == nil then return fallback or 0 end
    return value
end

local function floor(v, fallback)
    return math.floor(n(v, fallback or 0))
end

local function safeCall(object, methodName, fallback, ...)
    if not object or not methodName then
        return fallback
    end
    local args = { ... }
    local unpackFn = unpack or (table and table.unpack)
    local ok, value = pcall(function()
        local method = object[methodName]
        if unpackFn then
            return method(object, unpackFn(args))
        end
        return method(object)
    end)
    if ok and value ~= nil then
        return value
    end
    ok, value = pcall(function()
        local method = object[methodName]
        if unpackFn then
            return method(unpackFn(args))
        end
        return method()
    end)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

local function userKey(player)
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

local function store()
    if ModData and ModData.getOrCreate then
        local data = ModData.getOrCreate(STORE_KEY)
        data.players = data.players or {}
        return data
    end
    _G.__GodSystemServerStore = _G.__GodSystemServerStore or { players = {} }
    return _G.__GodSystemServerStore
end

local function transmitStore()
    if ModData and ModData.transmit then
        return pcall(ModData.transmit, STORE_KEY)
    end
    return true
end

local function adminConfigStore()
    if ModData and ModData.getOrCreate then
        local data = ModData.getOrCreate(ADMIN_CONFIG_KEY)
        if data.settings == nil then
            data.settings = GodSystemAdminConfig.getSandboxDefaults()
        end
        data.itemOverrides = data.itemOverrides or {}
        return data
    end
    _G.__GodSystemAdminConfigStore = _G.__GodSystemAdminConfigStore or {
        settings = GodSystemAdminConfig.getSandboxDefaults(),
        itemOverrides = {},
    }
    return _G.__GodSystemAdminConfigStore
end

local function transmitAdminConfig()
    if ModData and ModData.transmit then
        pcall(ModData.transmit, ADMIN_CONFIG_KEY)
    end
end

local function applyAdminConfigStore()
    local data = adminConfigStore()
    data.settings, data.itemOverrides = GodSystemAdminConfig.applyRuntime(data.settings, data.itemOverrides)
    return data
end

local function isAdminPlayer(player)
    if not player then return false end
    if player.isAccessLevel then
        local levels = { "Admin", "Moderator", "Overseer", "GM" }
        for i = 1, #levels do
            local ok, allowed = pcall(player.isAccessLevel, player, levels[i])
            if ok and allowed == true then return true end
        end
    end
    if player.getAccessLevel then
        local ok, level = pcall(player.getAccessLevel, player)
        if ok and level then
            level = tostring(level):lower()
            return level == "admin" or level == "moderator" or level == "overseer" or level == "gm"
        end
    end
    return false
end

local function markInventoryDirty(player, container)
    container = container or (player and player.getInventory and player:getInventory() or nil)
    if container and container.setDrawDirty then
        pcall(function() container:setDrawDirty(true) end)
    end
    if player and sendServerCommand then
        pcall(function() sendServerCommand(player, "ui", "DirtyUI", {}) end)
    end
end

local function copyStringArray(items)
    local result = {}
    if not items then return result end
    for i = 1, #items do result[i] = items[i] end
    return result
end

local function copyItems(items)
    local result = {}
    if not items then return result end
    for i = 1, #items do
        result[i] = { fullType = items[i].fullType, count = items[i].count or 1 }
    end
    return result
end

local function copyPosition(pos)
    if not pos then return nil end
    return {
        x = n(pos.x),
        y = n(pos.y),
        z = n(pos.z),
        label = pos.label,
        source = pos.source,
    }
end

local function appendHistory(data, entry)
    data.history = data.history or {}
    entry.time = nowHours()
    table.insert(data.history, 1, entry)
    local limit = GodSystemConfig.HistoryLimit or 40
    while #data.history > limit do
        table.remove(data.history)
    end
end

local function randomIndex(max)
    max = floor(max, 1)
    if max <= 1 then return 1 end
    if ZombRand then return ZombRand(max) + 1 end
    return math.random(max)
end

local BANK_INVESTMENT_IDS = { "stable", "balanced", "aggressive" }

local function normalizeBankInvestments(bank)
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

local function playerData(player)
    local root = store()
    local key = userKey(player)
    root.players[key] = root.players[key] or {}
    local data = root.players[key]
    data.version = GodSystemConfig.Version
    data.lastGeneratedDay = data.lastGeneratedDay or -1
    data.tasks = data.tasks or {}
    data.history = data.history or {}
    data.unlockedShopItems = data.unlockedShopItems or {}
    GodSystemShopVariants.normalizeUnlocked(data, GodSystemServer.configuredShopKeySet)
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
    data.upgrades.carryCapacityLevel = GodSystemCarryCapacity.normalizeLevel(data.upgrades.carryCapacityLevel)
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
    data.autoRecyclerClaimed = data.autoRecyclerClaimed == true
    GodSystemTerminalUpgrades.normalizeData(data)
    data.lastAutoRecyclerHour = data.lastAutoRecyclerHour or math.floor(nowHours())
    data.waistAutoRecycleUnlocked = data.waistAutoRecycleUnlocked == true
    data.waistAutoRecycleEnabled = data.waistAutoRecycleEnabled == true
    data.waistRecycleUnlockMode = data.waistRecycleUnlockMode == true
    data.lastWaistAutoRecycleHour = data.lastWaistAutoRecycleHour or math.floor(nowHours())
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled == true
    data.lastAutoTaskClaimHour = tonumber(data.lastAutoTaskClaimHour) or nowHours()
    data.ui = data.ui or {}
    return data
end

local function notify(player, text)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Notify) or "notify", { text = tostring(text or "") })
end

local function notifyCode(player, code, args)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Notify) or "notify", { code = tostring(code or ""), args = args or {} })
end

local function errorMessage(player, text)
    diagnostics.lastError = tostring(text or "")
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Error) or "error", { text = tostring(text or "") })
end

local function errorCode(player, code, args)
    diagnostics.lastError = tostring(code or "")
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Error) or "error", { code = tostring(code or ""), args = args or {} })
end

local function historyEntry(kind, code, args)
    return { kind = tostring(kind or "system"), code = tostring(code or ""), args = args or {} }
end

local function taskHistoryEntry(code, task, args)
    return {
        kind = "task",
        code = tostring(code or ""),
        taskId = task and task.sourceId or nil,
        args = args or {},
    }
end

local function shopHistoryEntry(code, row, args)
    return {
        kind = "shop",
        code = tostring(code or ""),
        shopId = row and row.id or nil,
        shopItems = row and row.items or nil,
        args = args or {},
    }
end

local function getBalanceStore()
    if ModData and ModData.getOrCreate then
        return ModData.getOrCreate(BAL_STORE_KEY)
    end
    _G.__GodSystemServerBalanceStore = _G.__GodSystemServerBalanceStore or {}
    return _G.__GodSystemServerBalanceStore
end

local function countContainerItems(container, fullType)
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
                local ok, child = pcall(item.getInventory, item)
                if ok and child then
                    total = total + countContainerItems(child, fullType)
                end
            end
        end
    end
    return total
end

local function getBalance(player)
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

local function itemExists(fullType)
    if not fullType then return false end
    if getScriptManager and getScriptManager() then
        return getScriptManager():FindItem(fullType) ~= nil
    end
    return true
end

local function findInventoryItems(container, result, fullType, includeFavorite, includeEquipped, player)
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
                local ok, value = pcall(item.isFavorite, item)
                favorite = ok and value == true
            end
            if matches and (includeEquipped or not equipped) and (includeFavorite or not favorite) then
                result[#result + 1] = { item = item, container = container }
            end
            if item.getInventory then
                local ok, child = pcall(item.getInventory, item)
                if ok and child then
                    findInventoryItems(child, result, fullType, includeFavorite, includeEquipped, player)
                end
            end
        end
    end
end

local function inventoryItems(player, fullType, includeFavorite, includeEquipped)
    local result = {}
    if player and player.getInventory then
        findInventoryItems(player:getInventory(), result, fullType, includeFavorite, includeEquipped, player)
    end
    return result
end

local function inventoryItemById(player, itemId)
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

local function giveItem(player, fullType, count)
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

local function removeItemFromContainer(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:Remove(item) end)
    if not ok or GodSystemServerContainerContainsItem(container, item) then return false end
    if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, item) end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    return true
end

local function restoreRemovedCurrency(player, removed)
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

local function giveCurrency(player, amount)
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

local function consolidateCurrency(player)
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

local function removeCurrency(player, amount)
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

local getBank
local spendCurrency
local spendableBalance

local function canAfford(player, cost, data)
    data = data or playerData(player)
    return spendableBalance(player, data) >= math.max(0, floor(cost, 0))
end

local function addPoints(player, amount, data)
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

function GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
    local bank = getBank(data)
    local bankAmount = math.max(0, floor(fromBank, 0))
    local cashAmount = math.max(0, floor(fromCash, 0))
    bank.current = (bank.current or 0) + bankAmount
    if cashAmount <= 0 then return true end
    if giveCurrency(player, cashAmount) then return true end
    bank.current = (bank.current or 0) + cashAmount
    return false
end

function GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
    local ok, failedValue = restoreRemovedCurrency(player, removed)
    if failedValue > 0 then
        local bank = getBank(playerData(player))
        bank.current = (bank.current or 0) + failedValue
    end
    return ok, failedValue
end

local function bankFixedEntry(bank, entryId)
    entryId = tostring(entryId or "")
    for i = 1, #(bank.fixed or {}) do
        if tostring(bank.fixed[i].id or "") == entryId then
            return bank.fixed[i], i
        end
    end
    return nil
end

local function bankFixedInterest(entry)
    if not entry then return 0 end
    return math.max(0, math.floor((tonumber(entry.principal) or 0) * (tonumber(entry.rate) or 0)))
end

local function bankFixedPayout(entry)
    if not entry then return 0, 0, false end
    local principal = math.max(0, floor(entry.principal, 0))
    if nowHours() >= n(entry.matureHour, 0) then
        local interest = bankFixedInterest(entry)
        return principal + interest, interest, true
    end
    local penalty = math.max(0, math.floor(principal * (GodSystemConfig.BankEarlyWithdrawPenaltyRatio or 0.05)))
    return math.max(0, principal - penalty), -penalty, false
end

local function bankInvestmentProfiles()
    local profiles = GodSystemConfig.BankInvestmentProfiles or {}
    local result = {}
    for i = 1, #BANK_INVESTMENT_IDS do
        local tierId = BANK_INVESTMENT_IDS[i]
        local profile = profiles[tierId] or {}
        local gainChance = math.max(0, math.min(100, floor(profile.gainChance, 0)))
        result[#result + 1] = {
            id = tierId,
            gainChance = gainChance,
            lossChance = math.max(0, math.min(100 - gainChance, floor(profile.lossChance, 0))),
            gainPercent = math.max(0, n(profile.gainPercent, 0)),
            lossPercent = math.max(0, n(profile.lossPercent, 0)),
        }
    end
    return result
end

local function bankInvestmentProfile(tierId)
    tierId = tostring(tierId or "")
    local profiles = bankInvestmentProfiles()
    for i = 1, #profiles do
        if profiles[i].id == tierId then return profiles[i] end
    end
    return nil
end

local function bankInvestmentMinimum()
    return math.max(1, floor(GodSystemConfig.BankInvestmentMinAmount, 1))
end

local function prepareBankInvestment(data, tierId, amount)
    if GodSystemAdminConfig.isFeatureEnabled("EnableBankInvestments") == false then
        return nil, nil, nil, "BankInvestmentDisabled", {}
    end
    local profile = bankInvestmentProfile(tierId)
    amount = math.max(0, floor(amount, 0))
    local minimum = bankInvestmentMinimum()
    if not profile then return nil, nil, nil, "BankInvestmentSelect", {} end
    if amount < minimum then return nil, nil, nil, "BankInvestmentMinimum", { minimum } end
    local bank = getBank(data)
    return profile, bank.investments[profile.id], amount, nil, nil
end

local function addBankInvestment(data, bank, profile, account, amount, source)
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
    data.stats.bankInvestmentDeposited = (data.stats.bankInvestmentDeposited or 0) + amount
    appendHistory(data, historyEntry("bank", "BankInvestmentCreated", { profile.id, amount, source }))
    return true, "BankInvestmentCreated", { profile.id, amount }
end

local function investBankCurrent(data, tierId, amount)
    local profile, account, cleanAmount, code, args = prepareBankInvestment(data, tierId, amount)
    if not profile then return false, code, args end
    local bank = getBank(data)
    if (bank.current or 0) < cleanAmount then return false, "BankCurrentNotEnough", {} end
    bank.current = (bank.current or 0) - cleanAmount
    return addBankInvestment(data, bank, profile, account, cleanAmount, "current")
end

local function investBankCash(player, data, tierId, amount)
    local profile, account, cleanAmount, code, args = prepareBankInvestment(data, tierId, amount)
    if not profile then return false, code, args end
    if not removeCurrency(player, cleanAmount) then return false, "CurrencyNotEnough", {} end
    return addBankInvestment(data, getBank(data), profile, account, cleanAmount, "cash")
end

local function redeemBankInvestment(data, tierId, amount)
    local profile = bankInvestmentProfile(tierId)
    local bank = getBank(data)
    local account = profile and bank.investments[profile.id] or nil
    amount = math.max(1, floor(amount, 0))
    if not profile or not account or (account.balance or 0) <= 0 then return false, "BankInvestmentSelect", {} end
    if account.redeemUnlocked ~= true then return false, "BankInvestmentLocked", {} end
    if amount > (account.balance or 0) then return false, "BankInvestmentBalanceLow", {} end
    account.balance = math.max(0, (account.balance or 0) - amount)
    bank.current = (bank.current or 0) + amount
    data.stats.bankInvestmentRedeemed = (data.stats.bankInvestmentRedeemed or 0) + amount
    appendHistory(data, historyEntry("bank", "BankInvestmentRedeemed", { profile.id, amount }))
    if account.balance <= 0 then
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    return true, "BankInvestmentRedeemed", { profile.id, amount }
end

local function settleBankInvestmentAccount(account, profile, nowHour)
    local before = math.max(0, floor(account.balance, 0))
    if before <= 0 then return 0, "flat", before end
    local roll = randomIndex(100)
    local delta = 0
    local outcome = "flat"
    if roll <= (profile.gainChance or 0) then
        local percent = math.max(0, n(profile.gainPercent, 0))
        if percent > 0 then
            delta = math.max(1, math.floor(before * percent / 100))
            account.balance = before + delta
            outcome = "gain"
        end
    elseif roll > 100 - (profile.lossChance or 0) then
        local percent = math.max(0, n(profile.lossPercent, 0))
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
    return delta, outcome, before
end

local function applyBankInvestmentElapsed(data, elapsedHours)
    elapsedHours = math.max(0, floor(elapsedHours, 0))
    if elapsedHours <= 0 or GodSystemAdminConfig.isFeatureEnabled("EnableBankInvestments") == false then
        return 0, 0
    end
    local bank = getBank(data)
    local profiles = bankInvestmentProfiles()
    local settlementHours = math.max(1, n(GodSystemConfig.BankInvestmentSettlementHours, 24))
    local settledCount = 0
    local totalDelta = 0
    local nowHour = nowHours()
    for i = 1, #profiles do
        local profile = profiles[i]
        local account = bank.investments[profile.id]
        if account and (account.balance or 0) > 0 then
            account.onlineHours = math.max(0, n(account.onlineHours, 0)) + elapsedHours
            while account.onlineHours >= settlementHours and (account.balance or 0) > 0 do
                account.onlineHours = account.onlineHours - settlementHours
                local delta, _, before = settleBankInvestmentAccount(account, profile, nowHour)
                totalDelta = totalDelta + delta
                settledCount = settledCount + 1
                if delta > 0 then
                    data.stats.bankInvestmentProfit = (data.stats.bankInvestmentProfit or 0) + delta
                elseif delta < 0 then
                    data.stats.bankInvestmentLoss = (data.stats.bankInvestmentLoss or 0) + math.abs(delta)
                end
                appendHistory(data, historyEntry("bank", "BankInvestmentSettled", { profile.id, before, delta, account.balance }))
            end
        end
    end
    return settledCount, totalDelta
end

local function getBankLoanPlans()
    local plans = {
        {
            id = "single",
            kind = "single",
            periods = 1,
            dueHours = math.max(1, floor(GodSystemConfig.BankLoanSingleDueHours, 72)),
            totalInterestRate = n(GodSystemConfig.BankLoanSingleInterestRate, 0.05),
        },
    }
    local periodHours = math.max(1, floor(GodSystemConfig.BankLoanPeriodHours, 72))
    for i = 1, #(GodSystemConfig.BankLoanInstallmentPlans or {}) do
        local row = GodSystemConfig.BankLoanInstallmentPlans[i]
        local periods = math.max(1, floor(row.periods, 1))
        plans[#plans + 1] = {
            id = tostring(row.id or ("i" .. tostring(periods))),
            kind = "installment",
            periods = periods,
            dueHours = periodHours,
            totalInterestRate = n(row.totalInterestRate, 0),
        }
    end
    return plans
end

local function bankLoanPlan(planId)
    planId = tostring(planId or "single")
    local plans = getBankLoanPlans()
    for i = 1, #plans do
        if tostring(plans[i].id or "") == planId then return plans[i] end
    end
    return nil
end

local function bankLoanUnpaidPrincipal(loan)
    local total = 0
    if not loan or type(loan.schedule) ~= "table" then return 0 end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local partTotal = math.max(0, floor((bill.principalPart or 0) + (bill.interestPart or 0), 0))
        local paid = math.max(0, floor(bill.paid, 0))
        local principal = math.max(0, floor(bill.principalPart, 0))
        if partTotal > 0 and paid < partTotal then
            local principalPaid = math.min(principal, paid)
            total = total + math.max(0, principal - principalPaid)
        end
    end
    return total
end

local function bankLoanAmounts(loan, now)
    now = n(now, nowHours())
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
    if not loan or type(loan.schedule) ~= "table" then return result end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local principal = math.max(0, floor(bill.principalPart, 0))
        local interest = math.max(0, floor(bill.interestPart, 0))
        local total = principal + interest
        local paid = math.max(0, floor(bill.paid, 0))
        if total > paid then
            local remaining = total - paid
            local principalPaid = math.min(principal, paid)
            local interestPaid = math.max(0, paid - principal)
            local principalLeft = math.max(0, principal - principalPaid)
            local interestLeft = math.max(0, interest - interestPaid)
            result.unpaidPrincipal = result.unpaidPrincipal + principalLeft
            result.unpaidInterest = result.unpaidInterest + interestLeft
            result.unpaidTotal = result.unpaidTotal + remaining
            local dueHour = n(bill.dueHour, now)
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

local function refreshBankLoanStatus(loan, now)
    if not loan then return bankLoanAmounts(nil, now) end
    local amounts = bankLoanAmounts(loan, now)
    loan.overdueStartHour = amounts.overdueStartHour
    return amounts
end

local function bankLoanOverduePenalty(loan, now, amounts)
    amounts = amounts or refreshBankLoanStatus(loan, now)
    if not loan or not amounts.overdueStartHour then return 0 end
    now = n(now, nowHours())
    local overdueDays = math.max(0, math.floor((now - amounts.overdueStartHour) / 24))
    if overdueDays <= 0 then return 0 end
    local principal = math.max(0, floor(loan.principal, 0))
    local dailyRate = n(GodSystemConfig.BankLoanOverduePenaltyDailyRate, 0.05)
    local maxRate = n(GodSystemConfig.BankLoanOverduePenaltyMaxRate, 0.5)
    return math.max(0, math.floor(math.min(principal * maxRate, principal * dailyRate * overdueDays)))
end

local function bankLoanCredit(data, bank)
    bank = bank or getBank(data)
    local base = math.max(0, floor(GodSystemConfig.BankLoanBaseCredit, 2000))
    local step = math.max(1, floor(GodSystemConfig.BankLoanCreditSpendStep, 100))
    local perStep = math.max(0, floor(GodSystemConfig.BankLoanCreditPerStep, 5))
    local spent = math.max(0, floor(data.stats and data.stats.spentPoints, 0))
    local offset = math.max(0, floor(bank.loanCreditSpentOffset, 0))
    local growth = math.floor(math.max(0, spent - offset) / step) * perStep
    local total = base + growth
    local used = bankLoanUnpaidPrincipal(bank.loan)
    return total, math.max(0, total - used), growth, used
end

local function createBankLoanSchedule(plan, amount, now)
    local schedule = {}
    local periods = math.max(1, floor(plan.periods, 1))
    local totalInterest = math.max(0, math.floor(amount * n(plan.totalInterestRate, 0)))
    local principalLeft = amount
    local interestLeft = totalInterest
    for i = 1, periods do
        local principalPart = (i == periods) and principalLeft or math.floor(amount / periods)
        local interestPart = (i == periods) and interestLeft or math.floor(totalInterest / periods)
        principalLeft = principalLeft - principalPart
        interestLeft = interestLeft - interestPart
        schedule[#schedule + 1] = {
            index = i,
            dueHour = now + math.max(1, floor(plan.dueHours, 72)) * i,
            principalPart = principalPart,
            interestPart = interestPart,
            paid = 0,
        }
    end
    return schedule, totalInterest
end

local function applyBankLoanPayment(loan, amount, now, includeFuture)
    amount = math.max(0, floor(amount, 0))
    local paid = 0
    if not loan or amount <= 0 then return 0 end
    now = n(now, nowHours())
    for i = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[i]
        local total = math.max(0, floor((bill.principalPart or 0) + (bill.interestPart or 0), 0))
        local billPaid = math.max(0, floor(bill.paid, 0))
        if total > billPaid and (includeFuture or now >= n(bill.dueHour, now)) then
            local add = math.min(amount, total - billPaid)
            bill.paid = billPaid + add
            loan.paid = math.max(0, floor(loan.paid, 0)) + add
            amount = amount - add
            paid = paid + add
            if amount <= 0 then break end
        end
    end
    return paid
end

local function spawnBankLoanDebtZombies(player, count)
    count = math.max(0, floor(count, 0))
    if count <= 0 or not addZombiesInOutfit then return 0 end
    if not player or not player.getX then return 0 end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local minDist = math.max(1, floor(GodSystemConfig.BankLoanZombieMinDistance, 20))
    local maxDist = math.max(minDist, floor(GodSystemConfig.BankLoanZombieMaxDistance, 45))
    local spawned = 0
    local tries = 0
    while spawned < count and tries < count * 8 do
        tries = tries + 1
        local dist = minDist + randomIndex(math.max(1, maxDist - minDist + 1)) - 1
        local dx = randomIndex(dist * 2 + 1) - dist - 1
        local dySign = randomIndex(2) == 1 and -1 or 1
        local dy = dySign * math.max(minDist, dist - math.abs(dx))
        local batch = math.min(10, count - spawned)
        local ok = pcall(addZombiesInOutfit, math.floor(px + dx), math.floor(py + dy), pz, batch, nil, nil)
        if ok then spawned = spawned + batch end
    end
    return spawned
end

local function applyBankLoanBankruptcy(player, data, bank, loan, debt)
    bank = bank or getBank(data)
    loan = loan or bank.loan
    if not loan then return false, 0 end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    debt = math.max(0, floor(debt or (amounts.unpaidTotal + bankLoanOverduePenalty(loan, now, amounts)), 0))
    local perZombie = math.max(1, floor(GodSystemConfig.BankLoanZombieDebtPerZombie, 50))
    local maxZombies = math.max(0, floor(GodSystemConfig.BankLoanZombieMaxCount, 100))
    local zombieCount = math.min(maxZombies, math.max(1, math.floor(debt / perZombie)))
    local cash = math.max(0, getBalance(player))
    if cash > 0 then removeCurrency(player, cash) end
    bank.loan = nil
    bank.current = 0
    bank.loanFrozenUntilHour = now + math.max(0, floor(GodSystemConfig.BankLoanFreezeHours, 168))
    bank.loanCreditSpentOffset = math.max(0, floor(data.stats and data.stats.spentPoints, 0))
    bank.loanBankruptcyCount = math.max(0, floor(bank.loanBankruptcyCount, 0)) + 1
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + debt
    local spawned = spawnBankLoanDebtZombies(player, zombieCount)
    appendHistory(data, historyEntry("bank", "BankLoanBankruptcy", { debt, spawned }))
    notifyCode(player, "BankLoanBankruptcy", { spawned })
    return true, spawned
end

local function getBankLoanSummary(data)
    local bank = getBank(data)
    local now = nowHours()
    local loan = bank.loan
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local total, available, growth, used = bankLoanCredit(data, bank)
    local graceHours = math.max(1, floor(GodSystemConfig.BankLoanBankruptcyGraceHours, 240))
    return {
        creditTotal = total,
        creditAvailable = available,
        creditGrowth = growth,
        creditUsed = used,
        loan = loan,
        dueNow = amounts.due + penalty,
        dueBase = amounts.due,
        overduePenalty = penalty,
        payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5),
        unpaidTotal = amounts.unpaidTotal + penalty,
        nextDueHour = amounts.nextDueHour,
        overdueStartHour = amounts.overdueStartHour,
        freezeLeftHours = math.max(0, math.ceil((bank.loanFrozenUntilHour or 0) - now)),
        bankruptcyInHours = amounts.overdueStartHour and math.max(0, math.ceil(graceHours - (now - amounts.overdueStartHour))) or nil,
    }
end

local function updateBankLoanForData(player, data)
    local bank = getBank(data)
    local loan = bank.loan
    if not loan then return false end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local graceHours = math.max(1, floor(GodSystemConfig.BankLoanBankruptcyGraceHours, 240))
    if amounts.overdueStartHour and now - amounts.overdueStartHour >= graceHours then
        local penalty = bankLoanOverduePenalty(loan, now, amounts)
        applyBankLoanBankruptcy(player, data, bank, loan, amounts.unpaidTotal + penalty)
        return true
    end
    return false
end

local function borrowBankLoan(player, data, bank, planId, amount)
    if GodSystemAdminConfig.isFeatureEnabled("EnableBankLoan") == false then return false, "Loan disabled" end
    amount = math.max(1, floor(amount, 0))
    local plan = bankLoanPlan(planId)
    if not plan then return false, "Loan plan missing" end
    updateBankLoanForData(player, data)
    bank = getBank(data)
    if bank.loan then return false, "已有未结清贷款" end
    local now = nowHours()
    if n(bank.loanFrozenUntilHour, 0) > now then return false, "贷款功能冻结中" end
    local _, available = bankLoanCredit(data, bank)
    if amount > available then return false, "可借额度不足" end
    local schedule, totalInterest = createBankLoanSchedule(plan, amount, now)
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
    appendHistory(data, historyEntry("bank", "BankLoanBorrowed", { amount }))
    notifyCode(player, "BankLoanBorrowed", { amount })
    return true, "借款已到账活期"
end

local function repayBankLoanDue(player, data, bank)
    updateBankLoanForData(player, data)
    bank = getBank(data)
    local loan = bank.loan
    if not loan then return false, "没有未结清贷款" end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local due = amounts.due + penalty
    if due <= 0 then return false, "当前没有到期账单" end
    if (bank.current or 0) < due then return false, "活期余额不足" end
    bank.current = (bank.current or 0) - due
    applyBankLoanPayment(loan, amounts.due, now, false)
    if penalty > 0 then data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty end
    if (loan.paid or 0) >= (loan.totalDue or 0) then
        bank.loan = nil
    else
        refreshBankLoanStatus(loan, now)
    end
    appendHistory(data, historyEntry("bank", "BankLoanRepaid", { due }))
    notifyCode(player, "BankLoanRepaid", { due })
    return true, "贷款已还款"
end

local function payoffBankLoan(player, data, bank)
    updateBankLoanForData(player, data)
    bank = getBank(data)
    local loan = bank.loan
    if not loan then return false, "没有未结清贷款" end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local payoff = math.max(0, floor(amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5), 0))
    if payoff <= 0 then
        bank.loan = nil
        return true, "贷款已提前结清"
    end
    if (bank.current or 0) < payoff then return false, "活期余额不足" end
    bank.current = (bank.current or 0) - payoff
    bank.loan = nil
    if penalty > 0 then data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty end
    appendHistory(data, historyEntry("bank", "BankLoanPayoff", { payoff }))
    notifyCode(player, "BankLoanPayoff", { payoff })
    return true, "贷款已提前结清"
end

local function applyBankDeathPenalty(data)
    local bank = getBank(data)
    local now = nowHours()
    if now - (bank.lastDeathPenaltyHour or -999) < 0.1 then
        return 0
    end
    bank.lastDeathPenaltyHour = now
    local penalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    if penalty <= 0 then return 0 end
    bank.current = math.max(0, (bank.current or 0) - penalty)
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    appendHistory(data, historyEntry("bank", "BankDeathPenalty", { penalty }))
    return penalty
end

local function payTaskFailurePenalty(player, data, amount)
    amount = math.max(0, floor(amount, 0))
    if amount <= 0 then return 0, 0, 0 end
    local bank = getBank(data)
    local fromBank = math.min(bank.current or 0, amount)
    if fromBank > 0 then
        bank.current = math.max(0, (bank.current or 0) - fromBank)
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + fromBank
    end
    local remaining = amount - fromBank
    local fromCash = 0
    if remaining > 0 then
        fromCash = math.min(getBalance(player), remaining)
        if fromCash > 0 and not removeCurrency(player, fromCash) then
            fromCash = 0
        end
    end
    return fromBank + fromCash, fromBank, fromCash
end

local function failTask(player, data, task, historyCode)
    if not task or task.status ~= "active" then return false end
    task.status = "failed"
    task.failedAt = nowHours()
    data.stats.failedTasks = (data.stats.failedTasks or 0) + 1
    local paid, fromBank, fromCash = payTaskFailurePenalty(player, data, task.penaltyPoints or 0)
    appendHistory(data, taskHistoryEntry(historyCode or "TaskFailed", task, { paid, task.penaltyPoints or 0, fromBank, fromCash }))
    return true
end

local function failActiveTasksOnDeath(player, data)
    local failed = 0
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" then
            failTask(player, data, task, "TaskDeathFailed")
            failed = failed + 1
        end
    end
    return failed
end

local function normalizeTraitType(traitType)
    return tostring(traitType or ""):gsub("[%s_%-]", ""):lower()
end

local function traitTokenString(token)
    if token == nil then return "" end
    local tokenType = type(token)
    if tokenType == "string" or tokenType == "number" or tokenType == "boolean" then return tostring(token) end
    if token.toString then return tostring(token:toString()) end
    return tostring(token)
end

local function arrayFromList(list)
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

local function characterTraitDefinitionByType(traitType)
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

local function traitCostPoints(traitType)
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

local function traitTokenForType(traitType)
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

local function playerHasTrait(player, traitType)
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

local function traitBoostCount(value)
    if value and value.intValue then
        local ok, result = pcall(function() return value:intValue() end)
        if ok and tonumber(result) then return math.floor(tonumber(result)) end
    end
    return math.floor(tonumber(tostring(value)) or 0)
end

local function applyTraitBenefits(player, traitType)
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

local function scriptItemValue(fullType, methods)
    local scriptItem = getScriptManager and getScriptManager() and getScriptManager():FindItem(fullType) or nil
    if not scriptItem then return "" end
    for i = 1, #methods do
        local fn = scriptItem[methods[i]]
        if fn then
            local ok, value = pcall(fn, scriptItem)
            if ok and value and tostring(value) ~= "" then return tostring(value) end
        end
    end
    return ""
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function moduleName(fullType)
    return fullType and string.match(fullType, "^([^%.]+)%.") or nil
end

local function categoryFromRaw(raw)
    raw = trim(raw)
    local compact = string.lower(raw):gsub("[%s_%-%./\\|>]+", "")
    if compact == "" then return "normal" end
    if string.find(compact, "accessory", 1, true) or string.find(compact, "jewelry", 1, true) then return "accessory" end
    if string.find(compact, "casing", 1, true) then return "casing" end
    if string.find(compact, "security", 1, true) then return "security" end
    if string.find(compact, "firstaid", 1, true) or string.find(compact, "medical", 1, true) then return "medical" end
    if string.find(compact, "beverage", 1, true) or string.find(compact, "water", 1, true) or string.find(compact, "drink", 1, true) then return "drink" end
    if string.find(compact, "food", 1, true) or string.find(compact, "canned", 1, true) then return "food" end
    if string.find(compact, "container", 1, true) then return "container" end
    if string.find(compact, "cooking", 1, true) or string.find(compact, "utensil", 1, true) then return "cooking" end
    if string.find(compact, "fire", 1, true) then return "fire" end
    if string.find(compact, "tool", 1, true) or string.find(compact, "maintenance", 1, true) then return "tool" end
    if string.find(compact, "material", 1, true) then return "material" end
    if string.find(compact, "ammo", 1, true) or string.find(compact, "bullet", 1, true) or string.find(compact, "shell", 1, true) then return "ammo" end
    if string.find(compact, "weapon", 1, true) then return "weapon" end
    if string.find(compact, "cloth", 1, true) or string.find(compact, "clothing", 1, true) then return "clothing" end
    if string.find(compact, "literature", 1, true) or string.find(compact, "book", 1, true) or string.find(compact, "map", 1, true) then return "literature" end
    if string.find(compact, "drainable", 1, true) then return "drainable" end
    if string.find(compact, "elect", 1, true) or string.find(compact, "radio", 1, true) then return "electronics" end
    if string.find(compact, "farm", 1, true) or string.find(compact, "seed", 1, true) then return "farming" end
    if string.find(compact, "vehicle", 1, true) or string.find(compact, "mechanic", 1, true) then return "vehicle" end
    if string.find(compact, "key", 1, true) then return "key" end
    if compact == "survival" then return "survival" end
    return "normal"
end

local function pricingCategory(fullType, item)
    if fullType and GodSystemConfig.VanillaItemPriceCategories and GodSystemConfig.VanillaItemPriceCategories[fullType] then
        return GodSystemAdminConfig.applyCategory(fullType, GodSystemConfig.VanillaItemPriceCategories[fullType])
    end
    local raw = fullType and scriptItemValue(fullType, { "getDisplayCategory", "getTypeString", "getType", "getCategory" }) or ""
    if raw == "" and item and item.getCategory then
        local ok, value = pcall(item.getCategory, item)
        if ok and value then raw = tostring(value) end
    end
    return GodSystemAdminConfig.applyCategory(fullType, categoryFromRaw(raw))
end

local function categoryFallbackBuyPrice(categoryKey, fullType)
    local prices = GodSystemConfig.ModCategoryBuyPrices or {}
    local key = tostring(categoryKey or "normal")
    local price = prices[key] or prices.normal or 120
    local mod = moduleName(fullType)
    if mod and not (GodSystemConfig.RecycleDefaultAllowedModules or {})[mod] then
        if key == "weapon" then price = math.max(price, GodSystemConfig.AutoShopModWeaponMinBuy or price)
        elseif key == "ammo" then price = math.max(price, GodSystemConfig.AutoShopModAmmoMinBuy or price)
        elseif key == "clothing" then price = math.max(price, GodSystemConfig.AutoShopModClothingMinBuy or price)
        else price = math.max(price, GodSystemConfig.AutoShopModMinBuy or price) end
    end
    return math.max(1, floor(price, 1))
end

local function itemPriceInfo(fullType, item)
    if not fullType then return { buyPrice = 0, sellPrice = 0, category = "normal" } end
    local categoryKey = pricingCategory(fullType, item)
    local buyPrice = GodSystemConfig.VanillaItemBuyPrices and GodSystemConfig.VanillaItemBuyPrices[fullType] or nil
    if not buyPrice then buyPrice = categoryFallbackBuyPrice(categoryKey, fullType) end
    buyPrice = math.max(1, floor(buyPrice, 1))
    local baseBuyPrice = buyPrice
    local ratio = GodSystemConfig.RecycleSellRatio or 0.05
    local mod = moduleName(fullType)
    if mod and not (GodSystemConfig.RecycleDefaultAllowedModules or {})[mod] then
        ratio = GodSystemConfig.ModItemSellRatio or ratio
    end
    buyPrice = GodSystemAdminConfig.applyShopBuyPrice(fullType, baseBuyPrice)
    local sellPrice = GodSystemAdminConfig.applySellPrice(fullType, math.max(1, math.floor(baseBuyPrice * ratio)))
    return { buyPrice = buyPrice, sellPrice = sellPrice, category = categoryKey }
end

local function itemBuyPrice(fullType)
    return itemPriceInfo(fullType).buyPrice or 0
end

local function itemSellPrice(fullType, item)
    return itemPriceInfo(fullType, item).sellPrice or 0
end

local function configuredShopPriceForFullType(fullType)
    local best = nil
    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local row = GodSystemConfig.ShopItems[i]
        local items = row.items or {}
        for j = 1, #items do
            if items[j].fullType == fullType then
                local total = 0
                for k = 1, #items do
                    total = total + itemBuyPrice(items[k].fullType) * math.max(1, floor(items[k].count, 1))
                end
                local price = total > 0 and total or floor(row.price, 0)
                if price > 0 and (not best or price < best) then best = price end
            end
        end
    end
    return best
end

local function autoShopBuyPriceForItem(fullType, sellValue)
    local info = itemPriceInfo(fullType)
    if info and (info.buyPrice or 0) > 0 then return info.buyPrice end
    local price = math.max((sellValue or 1) * (GodSystemConfig.AutoShopBuyMultiplier or 3), (sellValue or 1) + (GodSystemConfig.AutoShopMinMarkup or 10))
    local configured = configuredShopPriceForFullType(fullType)
    if configured then price = math.max(price, configured) end
    return GodSystemAdminConfig.applyShopBuyPrice(fullType, math.max(1, floor(price, 1)))
end

local function autoShopListOnlyCost(fullType, sellValue)
    local baseSell = math.max(1, floor(sellValue, 1))
    local buyPrice = math.max(1, floor(autoShopBuyPriceForItem(fullType, baseSell), 1))
    local ratio = math.max(0, n(GodSystemConfig.AutoShopListOnlyCostRatio, 0.5))
    local minCost = math.max(0, floor(GodSystemConfig.AutoShopListOnlyMinCost, 50))
    return math.max(minCost, math.ceil(buyPrice * ratio)), buyPrice
end

local function isAutoShopListOnlyAllowed(fullType)
    if not fullType or fullType == "" then return false end
    if GodSystemAdminConfig.isFeatureEnabled("EnableShop") == false then return false end
    if GodSystemAdminConfig.isFeatureEnabled("EnableRecycle") == false then return false end
    if not GodSystemConfig.AutoUnlockShopFromRecycle then return false end
    if (GodSystemConfig.AutoShopBlacklist or {})[fullType] or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return false end
    if GodSystemAdminConfig.isShopItemEnabled(fullType, true) == false then return false end
    if GodSystemAdminConfig.isRecycleItemEnabled(fullType, true) == false then return false end
    if GodSystem.isEconomicItemAllowed and GodSystem.isEconomicItemAllowed(fullType, "shop") == false then return false end
    local mod = moduleName(fullType)
    if GodSystemConfig.AutoShopAllowAnyModule == true then return mod ~= nil end
    return mod ~= nil and (GodSystemConfig.AutoShopAllowedModules or {})[mod] == true
end

local function shopUnitPrice(shopItem)
    if not shopItem then return 0 end
    local total = 0
    for i = 1, #(shopItem.items or {}) do
        total = total + itemBuyPrice(shopItem.items[i].fullType) * math.max(1, floor(shopItem.items[i].count, 1))
    end
    if total > 0 then return total end
    return math.max(0, floor(shopItem.price, 0))
end

local function shopById(data, id)
    id = tostring(id or "")
    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local row = GodSystemConfig.ShopItems[i]
        if tostring(row.id or "") == id then
            if row.featureKey and GodSystemAdminConfig.isFeatureEnabled(row.featureKey) == false then
                return nil, "disabled"
            end
            local items = row.items or {}
            for j = 1, #items do
                if items[j].fullType and GodSystemAdminConfig.isShopItemEnabled(items[j].fullType, true) == false then
                    return nil, "disabled"
                end
            end
            return row
        end
    end
    for variantKey, item in pairs(data.unlockedShopItems or {}) do
        local fullType = item.fullType or variantKey
        local unlockedId = "unlocked_" .. tostring(variantKey)
        if unlockedId == id or tostring(variantKey) == id then
            if item.hidden == true then return nil, "hidden" end
            if GodSystemAdminConfig.isShopItemEnabled(fullType, true) == false then return nil, "disabled" end
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

local function itemHasInventory(item)
    if not item or not item.getInventory then return false end
    local ok, child = pcall(item.getInventory, item)
    return ok and child ~= nil
end

local function isAutoRecyclerFullType(fullType)
    return fullType == (GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal")
end

local function isAutoRecyclerContainer(item)
    if not item or not item.getFullType then return false end
    return isAutoRecyclerFullType(item:getFullType())
end

local function isLooseAmmoRecycleItem(fullType, item)
    if not fullType then return false end
    if string.find(fullType, "Box", 1, true)
        or string.find(fullType, "Carton", 1, true)
        or string.find(fullType, "Clip", 1, true)
        or string.find(fullType, "Magazine", 1, true)
        or string.find(fullType, "AmmoBox", 1, true)
        or string.find(fullType, "Strap", 1, true)
        or string.find(fullType, "Case", 1, true)
        or string.find(fullType, "Bag_", 1, true) then
        return false
    end
    local lowerType = string.lower(fullType)
    local looksLikeLooseAmmoName = string.find(lowerType, "bullet", 1, true)
        or string.find(lowerType, "shell", 1, true)
        or string.find(lowerType, "ammo", 1, true)
        or string.find(lowerType, "round", 1, true)
        or string.find(lowerType, "cartridge", 1, true)
        or string.find(lowerType, "caliber", 1, true)
        or string.find(lowerType, "9mm", 1, true)
        or string.find(lowerType, "308", 1, true)
        or string.find(lowerType, "556", 1, true)
        or string.find(lowerType, "3030", 1, true)
    if not looksLikeLooseAmmoName then return false end
    if item and item.getCategory then
        local ok, category = pcall(item.getCategory, item)
        if ok and category == "Ammo" then return true end
    end
    local configuredCategory = GodSystemConfig.VanillaItemPriceCategories and GodSystemConfig.VanillaItemPriceCategories[fullType] or nil
    if configuredCategory == "ammo" then return true end
    if pricingCategory(fullType, item) == "ammo" then return true end
    if string.find(fullType, "Bullets", 1, true) or string.find(fullType, "ShotgunShells", 1, true) then return true end
    return false
end

local function recycleUnitDivisor(fullType)
    if not fullType then return 1 end
    if isLooseAmmoRecycleItem(fullType) then return 1 end
    if string.find(fullType, "ShotgunShells", 1, true) and not string.find(fullType, "Box", 1, true) then return GodSystemConfig.LooseShellRecycleDivisor or 5 end
    if string.find(fullType, "Bullets", 1, true) and not string.find(fullType, "Box", 1, true) then return GodSystemConfig.LooseAmmoRecycleDivisor or 10 end
    if string.find(fullType, "Nails", 1, true) and not string.find(fullType, "Box", 1, true) then return GodSystemConfig.SmallUnitRecycleDivisor or 10 end
    return 1
end

local function calculateRecyclePayout(fullType, rawValue, count)
    rawValue = floor(rawValue, 0)
    if rawValue <= 0 then return 0 end
    local divisor = recycleUnitDivisor(fullType)
    if divisor <= 1 then return math.max(1, rawValue) end
    return math.floor((count or 1) / divisor)
end

local function recycleValue(item, allowContainers)
    if not item or not item.getFullType then return 0 end
    local fullType = item:getFullType()
    if isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item)
        or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return 0 end
    if GodSystemAdminConfig.isRecycleItemEnabled(fullType, true) == false then return 0 end
    if allowContainers ~= true and GodSystemConfig.AllowRecycleContainers ~= true and itemHasInventory(item) then return 0 end
    if isLooseAmmoRecycleItem(fullType, item) then return 1 end
    local value = itemSellPrice(fullType, item)
    if item.isBroken then
        local ok, broken = pcall(item.isBroken, item)
        if ok and broken then value = math.floor(value * 0.5) end
    end
    if item.getUsedDelta then
        local ok, used = pcall(item.getUsedDelta, item)
        if ok and used and used > 0 and used < 1 then value = math.floor(value * used) end
    end
    return math.max(1, value)
end

local function itemInventoryCount(item)
    if not itemHasInventory(item) then return 0 end
    local okInventory, inventory = pcall(item.getInventory, item)
    if not okInventory or not inventory or not inventory.getItems then return 0 end
    local okItems, items = pcall(inventory.getItems, inventory)
    if not okItems or not items or not items.size then return 0 end
    return items:size()
end

local function isKeyItem(item)
    if not item then return false end
    if instanceof and instanceof(item, "Key") then return true end
    if item.isItemType and ItemType and ItemType.KEY_RING then
        local ok, value = pcall(item.isItemType, item, ItemType.KEY_RING)
        if ok and value == true then return true end
    end
    if item.hasTag and ItemTag and ItemTag.KEY_RING then
        local ok, value = pcall(item.hasTag, item, ItemTag.KEY_RING)
        if ok and value == true then return true end
    end
    return false
end

local function canContextRecycleItem(item)
    if not item or not item.getFullType then return false, "invalid" end
    local fullType = item:getFullType()
    if isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item) then return false, "protected" end
    if (GodSystemConfig.RecycleBlacklist or {})[fullType] or isKeyItem(item) then return false, "protected" end
    if GodSystem.isEconomicItemAllowed and GodSystem.isEconomicItemAllowed(fullType, "recycle") == false then
        return false, "invalid"
    end
    if recycleValue(item, true) <= 0 then return false, "invalid" end
    return true, nil
end

local function canContextListItem(data, item)
    local allowed, reason = canContextRecycleItem(item)
    if not allowed then return false, reason end
    local fullType = item:getFullType()
    if not isAutoShopListOnlyAllowed(fullType) then return false, "notListable" end
    local variantKey = GodSystemShopVariants.getKey(fullType, item)
    local listed, source = GodSystemShopVariants.isListingKnown(data, GodSystemServer.configuredShopKeySet, variantKey)
    if listed then
        if source == "configured" then return false, "configuredListed" end
        if data.unlockedShopItems and data.unlockedShopItems[variantKey] and data.unlockedShopItems[variantKey].hidden == true then
            return false, "hiddenListed"
        end
        return false, "alreadyListed"
    end
    return true, nil
end

local function canRecycleItem(item, waistOnly)
    if not item or not item.getFullType then return false end
    local fullType = item:getFullType()
    if isAutoRecyclerContainer(item) or GodSystemStorage.isProtected(item)
        or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return false end
    if item.isFavorite then
        local ok, favorite = pcall(item.isFavorite, item)
        if ok and favorite then return false end
    end
    if waistOnly and itemHasInventory(item) then return false end
    if not waistOnly and GodSystemConfig.AllowRecycleContainers ~= true and itemHasInventory(item) then return false end
    return recycleValue(item) > 0
end

local function applyRecycleDailyPayout(data, rawValue)
    rawValue = floor(rawValue, 0)
    if rawValue <= 0 then return 0, false end
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then return rawValue, false end
    if data.recycleLimitDay ~= currentDay() then
        data.recycleLimitDay = currentDay()
        data.recycleLimitUsed = 0
    end
    local remaining = math.max(0, cap - (data.recycleLimitUsed or 0))
    if remaining > 0 then
        local payout = math.min(rawValue, remaining)
        data.recycleLimitUsed = math.min(cap, (data.recycleLimitUsed or 0) + payout)
        return payout, payout < rawValue
    end
    return math.max(1, GodSystemConfig.DiminishedRecyclePayout or 1), true
end

local function unlockAutoShopItem(data, fullType, label, sellValue, itemOrSprite)
    if not fullType or not GodSystemConfig.AutoUnlockShopFromRecycle then return nil end
    if (GodSystemConfig.AutoShopBlacklist or {})[fullType] or (GodSystemConfig.RecycleBlacklist or {})[fullType] then return nil end
    local mod = moduleName(fullType)
    if GodSystemConfig.AutoShopAllowAnyModule ~= true and not ((GodSystemConfig.AutoShopAllowedModules or {})[mod]) then return nil end
    data.unlockedShopItems = data.unlockedShopItems or {}
    local baseSell = math.max(1, floor(sellValue, 1))
    local buyPrice = autoShopBuyPriceForItem(fullType, baseSell)
    local worldSprite = GodSystemShopVariants.getWorldSprite(itemOrSprite)
    local variantKey = GodSystemShopVariants.getKey(fullType, worldSprite)
    local listed, source = GodSystemShopVariants.isListingKnown(data, GodSystemServer.configuredShopKeySet, variantKey)
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

local function lotteryNormalizeCategory(categoryKey)
    categoryKey = tostring(categoryKey or "all"):lower():gsub("[^a-z0-9_]+", "_")
    if categoryKey == "" then categoryKey = "all" end
    return categoryKey
end

local function lotteryPrice(categoryKey)
    categoryKey = lotteryNormalizeCategory(categoryKey)
    if categoryKey == "all" then return math.max(1, floor(GodSystemConfig.LotteryAllPrice or 100, 100)) end
    local prices = GodSystemConfig.LotteryCategoryPrices or {}
    return math.max(1, floor(prices[categoryKey] or prices.normal or 60, 60))
end

local function lotteryAddCandidate(result, seen, fullType, label)
    fullType = tostring(fullType or "")
    if fullType == "" or seen[fullType] then return end
    if (GodSystemConfig.LotteryBlacklist or {})[fullType] then return end
    if not itemExists(fullType) then return end
    if not GodSystem.isEconomicItemAllowed(fullType, "lottery") then return end
    if GodSystemAdminConfig.isLotteryItemEnabled(fullType, true) == false then return end
    local info = itemPriceInfo(fullType)
    local categoryKey = lotteryNormalizeCategory(info and info.category or pricingCategory(fullType) or "normal")
    if categoryKey == "all" then categoryKey = "normal" end
    seen[fullType] = true
    result[#result + 1] = {
        fullType = fullType,
        label = label or fullType,
        categoryKey = categoryKey,
        buyPrice = info and info.buyPrice or itemBuyPrice(fullType),
        sellPrice = info and info.sellPrice or itemSellPrice(fullType),
    }
end

local function lotteryCandidates(data, categoryKey)
    categoryKey = lotteryNormalizeCategory(categoryKey)
    local result = {}
    local seen = {}
    for i = 1, #(GodSystemConfig.ShopItems or {}) do
        local row = GodSystemConfig.ShopItems[i]
        for j = 1, #(row and row.items or {}) do
            local item = row.items[j]
            lotteryAddCandidate(result, seen, item and item.fullType, row and row.label)
        end
    end
    for variantKey, item in pairs((data and data.unlockedShopItems) or {}) do
        lotteryAddCandidate(result, seen, item and item.fullType or variantKey, item and item.label)
    end
    for fullType, _ in pairs(GodSystemConfig.VanillaItemBuyPrices or {}) do
        lotteryAddCandidate(result, seen, fullType, nil)
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

local function groupLotteryItems(items)
    local grouped = {}
    local order = {}
    for i = 1, #(items or {}) do
        local item = items[i]
        local key = tostring(item.fullType or item.label or i)
        if not grouped[key] then
            grouped[key] = { fullType = item.fullType, label = item.label or item.fullType, count = 0 }
            order[#order + 1] = key
        end
        grouped[key].count = grouped[key].count + math.max(1, floor(item.count or 1, 1))
    end
    local result = {}
    for i = 1, #order do result[#result + 1] = grouped[order[i]] end
    table.sort(result, function(a, b) return tostring(a.label or a.fullType) < tostring(b.label or b.fullType) end)
    return result
end

local function autoRecyclerLevels()
    return GodSystemTerminalUpgrades.getLevels("capacity")
end

local function autoRecyclerMaxLevel()
    return math.max(1, #autoRecyclerLevels())
end

local function autoRecyclerLevelData(level)
    local capacity = GodSystemConfig.TerminalCapacityLevels or {}
    local reduction = GodSystemConfig.TerminalReductionLevels or {}
    level = math.max(1, math.min(floor(level, 1), math.max(1, #capacity)))
    local reductionLevel = math.max(1, math.min(level, math.max(1, #reduction)))
    return {
        level = level,
        capacity = (capacity[level] and capacity[level].value) or GodSystemConfig.AutoRecyclerCapacity or 10,
        weightReduction = (reduction[reductionLevel] and reduction[reductionLevel].value) or GodSystemConfig.AutoRecyclerWeightReduction or 50,
        upgradeCost = (capacity[level] and capacity[level].upgradeCost) or 0,
    }
end

local function autoRecyclerLevel(data)
    return GodSystemTerminalUpgrades.getLevel(data, "capacity")
end

local function autoRecyclerDisplayName(level)
    return "System Space Terminal Lv." .. tostring(level)
end

function GodSystemServer.syncTerminalApplyReport(item, report, forceSync)
    report = type(report) == "table" and report or {}
    local inventory = report.inventory
    if not inventory and item and item.getInventory then
        local okInventory, value = pcall(function() return item:getInventory() end)
        if okInventory then inventory = value end
    end
    local seen = {}
    for i = 1, #((report.removedItems) or {}) do
        local removedItem = report.removedItems[i]
        if inventory and removedItem and sendRemoveItemFromContainer then
            pcall(sendRemoveItemFromContainer, inventory, removedItem)
        end
    end
    for i = 1, #((report.addedItems) or {}) do
        local addedItem = report.addedItems[i]
        if inventory and addedItem and sendAddItemToContainer then
            pcall(sendAddItemToContainer, inventory, addedItem)
        end
        if addedItem then seen[addedItem] = true end
    end
    for i = 1, #((report.items) or {}) do
        local changedItem = report.items[i]
        if changedItem then seen[changedItem] = true end
    end
    for i = 1, #((report.changedItems) or {}) do
        local changedItem = report.changedItems[i]
        if changedItem then seen[changedItem] = true end
    end
    if forceSync == true and inventory and inventory.getItems then
        local okItems, items = pcall(function() return inventory:getItems() end)
        if okItems and items and items.size and items.get then
            for i = 0, items:size() - 1 do
                local changedItem = items:get(i)
                if GodSystemTerminalRelief.isReliefItem(changedItem) then seen[changedItem] = true end
            end
        end
    end
    for changedItem in pairs(seen) do
        if changedItem.syncItemFields then pcall(function() changedItem:syncItemFields() end) end
        if sendItemStats then pcall(sendItemStats, changedItem) end
        if changedItem.transmitModData then pcall(changedItem.transmitModData, changedItem) end
    end
    if report.terminalChanged == true or forceSync == true then
        if item and item.syncItemFields then pcall(function() item:syncItemFields() end) end
        if item and item.transmitModData then pcall(item.transmitModData, item) end
        if item and sendItemStats then pcall(sendItemStats, item) end
    end
end

function GodSystemServer.buildTerminalSyncPayload(item, player)
    if not item or not item.getID or not item.getInventory then return nil end
    if not isAutoRecyclerContainer(item) then return nil end

    local okId, itemId = pcall(function() return item:getID() end)
    local okInventory, inventory = pcall(function() return item:getInventory() end)
    if not okId or itemId == nil or not okInventory or not inventory then return nil end

    local function readNumber(target, method)
        if not target or not target[method] then return nil end
        local ok, value = pcall(function() return target[method](target) end)
        value = ok and tonumber(value) or nil
        if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end

    local outerCapacity = readNumber(item, "getCapacity")
    local innerCapacity = readNumber(inventory, "getCapacity")
    local outerReduction = readNumber(item, "getWeightReduction")
    local innerReduction = readNumber(inventory, "getWeightReduction")
    if outerCapacity == nil or innerCapacity == nil or outerReduction == nil or innerReduction == nil then return nil end

    local terminalData = item.getModData and item:getModData() or nil
    local reliefLevelKey = GodSystemConfig.TerminalReliefLevelKey or "GodSystemTerminalReliefLevel"
    local reliefOffsetKey = GodSystemConfig.TerminalReliefOffsetKey or "GodSystemTerminalReliefOffset"
    local reliefLevel = math.max(0, math.floor(tonumber(terminalData and terminalData[reliefLevelKey]) or 0))
    local reliefOffset = 0
    local reliefSnapshot = GodSystemTerminalRelief.snapshot(item, player)
    local reliefState = reliefSnapshot and reliefSnapshot.items and reliefSnapshot.items[1] or nil
    if reliefState then
        reliefLevel = math.max(0, math.floor(tonumber(reliefState.modData and reliefState.modData[reliefLevelKey]) or reliefLevel))
        reliefOffset = math.max(0, tonumber(reliefState.modData and reliefState.modData[reliefOffsetKey])
            or -(tonumber(reliefState.actualWeight) or 0))
    end

    return {
        kind = "terminalSync",
        itemId = itemId,
        outerCapacity = outerCapacity,
        innerCapacity = innerCapacity,
        outerReduction = outerReduction,
        innerReduction = innerReduction,
        reliefLevel = reliefLevel,
        reliefOffset = reliefOffset,
    }
end

function GodSystemServer.syncEscapedReliefRemovals(entries)
    for i = 1, #(entries or {}) do
        local entry = entries[i]
        if entry and entry.container and entry.item and sendRemoveItemFromContainer then
            pcall(sendRemoveItemFromContainer, entry.container, entry.item)
        end
    end
end

function GodSystemServer.cleanupEscapedRelief(player, terminal)
    local removed, entries = GodSystemTerminalRelief.removeEscapedFromPlayer(player, terminal)
    if removed > 0 then GodSystemServer.syncEscapedReliefRemovals(entries) end
    return removed
end

local function markAutoRecycler(data, item, player, preappliedReport, deferSync)
    if not item or not item.getFullType or not isAutoRecyclerFullType(item:getFullType()) then return false end
    local level = GodSystemTerminalUpgrades.getLevel(data, "capacity")
    local applied, report = true, preappliedReport
    if not report then applied, report = GodSystemTerminalUpgrades.applyTerminal(item, data, player) end
    report = type(report) == "table" and report or {}
    if applied ~= true then return false, report end

    local terminalChanged = report.terminalChanged == true
    local md = item.getModData and item:getModData() or nil
    if md then
        local markerKey = GodSystemConfig.AutoRecyclerMarkerKey or "GodSystemAutoRecycler"
        local levelKey = GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"
        if md[markerKey] ~= true then
            md[markerKey] = true
            terminalChanged = true
        end
        if md[levelKey] ~= level then
            md[levelKey] = level
            terminalChanged = true
        end
    end
    local expectedName = autoRecyclerDisplayName(level)
    if item.setName and item.getName and tostring(item:getName() or "") ~= expectedName then
        local nameOk = pcall(item.setName, item, expectedName)
        terminalChanged = nameOk or terminalChanged
        if nameOk and item.setCustomName then pcall(item.setCustomName, item, true) end
    end
    report.terminalChanged = terminalChanged
    if deferSync ~= true then GodSystemServer.syncTerminalApplyReport(item, report) end
    return true, report
end

function GodSystemServer.giveConfiguredTerminal(player, data)
    if not player or not player.getInventory then return false, nil end
    local inventory = player:getInventory()
    local fullType = GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal"
    local item = inventory and inventory.AddItem and inventory:AddItem(fullType) or nil
    if not item then return false, nil end
    local applied, report = markAutoRecycler(data, item, player, nil, true)
    if applied ~= true then
        if inventory.Remove then pcall(inventory.Remove, inventory, item) end
        return false, nil
    end
    local synced = sendAddItemToContainer and pcall(sendAddItemToContainer, inventory, item)
    if not synced then
        if inventory.Remove then pcall(inventory.Remove, inventory, item) end
        return false, nil
    end
    GodSystemServer.syncTerminalApplyReport(item, report, true)
    markInventoryDirty(player, inventory)
    print("[GodSystem][TerminalWear] grant item=" .. tostring(item.getID and item:getID() or "?") .. " slot=GodSystem:SystemSpaceTerminal")
    return true, item, report
end

function GodSystemServer.isTerminalOwnedByPlayer(player, item)
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
        local parent = container.getContainingItem and safeCall(container, "getContainingItem", nil) or nil
        current = parent
    end
    return false
end

local function findAutoRecycler(data, player)
    local key = userKey(player)
    local cached = GodSystemServer.terminalCache[key]
    if cached and cached.item and isAutoRecyclerContainer(cached.item) and GodSystemServer.isTerminalOwnedByPlayer(player, cached.item) then
        GodSystemServer.cleanupEscapedRelief(player, cached.item)
        markAutoRecycler(data, cached.item, player)
        return cached.item, cached.item.getContainer and cached.item:getContainer() or nil
    end
    GodSystemServer.terminalCache[key] = nil
    local aliases = GodSystemConfig.AutoRecyclerFullTypes or { [GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal"] = true }
    for fullType, enabled in pairs(aliases) do
        if enabled == true then
            local candidates = inventoryItems(player, fullType, true, true)
            for i = 1, #candidates do
                if isAutoRecyclerContainer(candidates[i].item) then
                    GodSystemServer.cleanupEscapedRelief(player, candidates[i].item)
                    markAutoRecycler(data, candidates[i].item, player)
                    GodSystemServer.terminalCache[key] = { player = player, item = candidates[i].item }
                    return candidates[i].item, candidates[i].container
                end
            end
        end
    end
    GodSystemServer.cleanupEscapedRelief(player, nil)
    return nil
end

local function autoRecyclerInventory(data, player)
    local item = findAutoRecycler(data, player)
    if item and item.getInventory then
        local ok, inv = pcall(item.getInventory, item)
        if ok then return inv, item end
    end
    return nil, item
end

local function maxActiveTasks(data)
    return math.min(GodSystemConfig.MaxActiveTaskLimit or 10, math.max(GodSystemConfig.MaxActiveTasks or 3, floor(data.upgrades.maxActiveTasks, GodSystemConfig.MaxActiveTasks or 3)))
end

local function dailyTaskCount(data)
    return math.min(GodSystemConfig.MaxDailyTaskLimit or 20, math.max(GodSystemConfig.DailyTaskCount or 5, floor(data.upgrades.dailyTaskCount, GodSystemConfig.DailyTaskCount or 5)))
end

local function isTaskTemplateAvailable(template)
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

local function availableTaskTemplates()
    local result = {}
    for i = 1, #(GodSystemConfig.TaskTemplates or {}) do
        local t = GodSystemConfig.TaskTemplates[i]
        if isTaskTemplateAvailable(t) then result[#result + 1] = t end
    end
    if #result == 0 then return GodSystemConfig.TaskTemplates or {} end
    return result
end

local function generateTask(template)
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
        rewardPoints = GodSystemAdminConfig.applyTaskReward(template.rewardPoints or 0),
        rewardItems = copyItems(template.rewardItems),
        penaltyPoints = GodSystemAdminConfig.applyTaskPenalty(template.penaltyPoints or 0),
        description = template.description,
        status = "open",
        createdAt = now,
        createdDay = currentDay(),
    }
end

local function generateDailyTasks(data, force)
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

local function findTask(data, taskId)
    for i = 1, #(data.tasks or {}) do
        if tostring(data.tasks[i].taskId or "") == tostring(taskId or "") then return data.tasks[i] end
    end
    return nil
end

local function ensureKillTaskProgress(task, baselineKills)
    if not task or task.kind ~= "kill" then return 0 end
    if task.killProgress == nil then
        baselineKills = math.max(0, floor(baselineKills, 0))
        task.killProgress = math.max(0, baselineKills - math.max(0, floor(task.startKills, baselineKills)))
    end
    task.killProgress = math.max(0, floor(task.killProgress, 0))
    return task.killProgress
end

local function applyKillTaskDelta(data, delta, baselineKills)
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

local function taskProgress(data, player, task)
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

local function removeInventoryItems(player, fullType, count)
    local found = inventoryItems(player, fullType, false, false)
    count = math.max(1, floor(count, 1))
    local removed = 0
    for i = 1, #found do
        if removed >= count then break end
        removeItemFromContainer(found[i].container, found[i].item)
        removed = removed + 1
    end
    return removed
end

local function removeAnyInventoryItems(player, fullTypes, count)
    local removed = 0
    for i = 1, #(fullTypes or {}) do
        if removed >= count then break end
        removed = removed + removeInventoryItems(player, fullTypes[i], count - removed)
    end
    return removed
end

local function claimTaskForPlayer(player, data, task, claimArgs)
    claimArgs = claimArgs or {}
    if not task or task.status ~= "active" then return false, "TaskStateInvalid" end
    local progress = taskProgress(data, player, task)
    if task.kind ~= "turnInItem" and task.kind ~= "turnInAnyItem" then
        progress = math.max(0, floor(claimArgs.clientProgress, progress))
    end
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
    if task.kind == "turnInItem" then
        if removeInventoryItems(player, task.item, task.target or 1) < (task.target or 1) then return false, "TaskTurnInNotEnough" end
    elseif task.kind == "turnInAnyItem" then
        if removeAnyInventoryItems(player, task.items, task.target or 1) < (task.target or 1) then return false, "TaskTurnInNotEnough" end
    end
    if (task.rewardPoints or 0) > 0 then addPoints(player, task.rewardPoints) end
    for i = 1, #(task.rewardItems or {}) do giveItem(player, task.rewardItems[i].fullType, task.rewardItems[i].count or 1) end
    task.status = "claimed"
    task.claimedAt = nowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    appendHistory(data, taskHistoryEntry("ClaimTask", task))
    return true, "TaskClaimed"
end

local function sendState(player, terminalSync)
    applyAdminConfigStore()
    local data = playerData(player)
    generateDailyTasks(data, false)
    updateBankLoanForData(player, data)
    data.balance = getBalance(player)
    data.serverDiagnostics = {
        handledCommands = diagnostics.handledCommands or 0,
        failedCommands = diagnostics.failedCommands or 0,
        lastCommand = diagnostics.lastCommand,
        lastError = diagnostics.lastError,
        lastResultOk = diagnostics.lastResultOk,
        lastResultMessage = diagnostics.lastResultMessage,
        lastTraitBenefitsOk = diagnostics.lastTraitBenefitsOk,
        lastTraitBenefitsApplied = diagnostics.lastTraitBenefitsApplied,
        lastTraitBenefitsType = diagnostics.lastTraitBenefitsType,
    }
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.State) or "state", {
        data = data,
        balance = data.balance,
        version = GodSystemConfig.Version,
        admin = isAdminPlayer(player),
        adminConfig = GodSystemAdminConfig.buildSnapshot(),
        terminalSync = terminalSync,
    })
end

local function finish(player, ok, message, payload)
    diagnostics.lastResultOk = ok == true
    diagnostics.lastResultMessage = tostring(message or "")
    transmitStore()
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Result) or "result", { ok = ok == true, message = tostring(message or ""), payload = payload })
    sendState(player)
    if message and message ~= "" then notify(player, message) end
end

local function finishCode(player, ok, code, args, payload)
    diagnostics.lastResultOk = ok == true
    diagnostics.lastResultMessage = tostring(code or "")
    transmitStore()
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Result) or "result", {
        ok = ok == true,
        code = tostring(code or ""),
        args = args or {},
        message = "",
        payload = payload,
    })
    sendState(player)
    if code and code ~= "" then notifyCode(player, code, args or {}) end
end

local function guard(player)
    local key = userKey(player)
    if pending[key] then
        errorCode(player, "CommandPending")
        return false
    end
    pending[key] = true
    return true
end

local function unguard(player)
    pending[userKey(player)] = nil
end

GodSystemServer.attributeOps = GodSystemServer.attributeOps or {}
GodSystemServer.attributeOpsNormalized = GodSystemServer.attributeOpsNormalized or {}

function GodSystemServer.attributeOpId(args)
    local opId = args and tostring(args.opId or "") or ""
    if #opId > 96 or not string.match(opId, "^gs%-%d+%-%d+%-%d+$") then return nil end
    return opId
end

function GodSystemServer.attributeOpFingerprint(args)
    if type(args) ~= "table" then return "" end
    return table.concat({
        tostring(args.perkIndex or ""),
        tostring(args.mode or ""),
        tostring(args.value or ""),
    }, "|")
end

function GodSystemServer.attributeOpBucket(player, create)
    local root = store()
    root.attributeOperations = root.attributeOperations or {}
    local key = userKey(player)
    local bucket = root.attributeOperations[key]
    if not bucket and create == true then
        bucket = { results = {}, order = {} }
        root.attributeOperations[key] = bucket
    end
    if bucket then
        bucket.results = type(bucket.results) == "table" and bucket.results or {}
        bucket.order = type(bucket.order) == "table" and bucket.order or {}
        if GodSystemServer.attributeOpsNormalized[key] ~= bucket then
            for _, result in pairs(bucket.results) do
                if type(result) == "table" and result.status == "processing" then
                    result.status = "unknown"
                    result.ok = false
                    result.code = "AttributeOperationUnknown"
                    result.args = {}
                end
            end
            GodSystemServer.attributeOpsNormalized[key] = bucket
        end
    end
    return bucket
end

function GodSystemServer.getAttributeOpResult(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return nil end
    local bucket = GodSystemServer.attributeOpBucket(player, false)
    local result = bucket and bucket.results[opId] or nil
    if result and result.fingerprint and result.fingerprint ~= GodSystemServer.attributeOpFingerprint(args) then
        return { status = "mismatch" }
    end
    return result
end

function GodSystemServer.trimAttributeOps(bucket)
    while bucket and #bucket.order > 64 do
        local removeAt = 1
        for i = 1, #bucket.order do
            local candidate = bucket.results[bucket.order[i]]
            if candidate and candidate.status == "done" then
                removeAt = i
                break
            end
        end
        local expired = table.remove(bucket.order, removeAt)
        bucket.results[expired] = nil
    end
end

function GodSystemServer.beginAttributeOp(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return false end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    if bucket.results[opId] ~= nil then return false end
    bucket.order[#bucket.order + 1] = opId
    bucket.results[opId] = { status = "processing", fingerprint = GodSystemServer.attributeOpFingerprint(args) }
    GodSystemServer.trimAttributeOps(bucket)
    return true
end

function GodSystemServer.rememberAttributeOpResult(player, args, ok, code, codeArgs, payload)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    if bucket.results[opId] == nil then
        bucket.order[#bucket.order + 1] = opId
    end
    local current = bucket.results[opId]
    bucket.results[opId] = {
        status = "done",
        fingerprint = current and current.fingerprint or GodSystemServer.attributeOpFingerprint(args),
        ok = ok == true,
        code = tostring(code or ""),
        args = codeArgs or {},
        payload = payload,
    }
    GodSystemServer.trimAttributeOps(bucket)
end

function GodSystemServer.markAttributeOpUnknown(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    local current = bucket.results[opId]
    if current and current.status == "processing" then
        bucket.results[opId] = {
            status = "unknown",
            fingerprint = current.fingerprint or GodSystemServer.attributeOpFingerprint(args),
            ok = false,
            code = "AttributeOperationUnknown",
            args = {},
            payload = { opId = opId },
        }
    end
end

local Commands = {}

function Commands.hello(_, _, player)
    local data = playerData(player)
    if not data.currencyInitialized then
        local grant = 0
        if data.points and data.points > 0 then grant = floor(data.points, 0)
        elseif not data.started then grant = GodSystemConfig.StartingPoints or 0 end
        if grant > 0 and not giveCurrency(player, grant) then
            return finish(player, false, "初始系统币发放失败，将在下次进入时重试")
        end
        data.started = true
        data.currencyInitialized = true
        data.points = 0
        if grant > 0 then appendHistory(data, historyEntry("system", "InitialCurrency", { grant })) end
    end
    if data.attributeSyncPending == true and type(SyncXp) == "function" then
        local okSync = pcall(function() SyncXp(player) end)
        if okSync then data.attributeSyncPending = nil end
    end
    generateDailyTasks(data, false)
    GodSystemCarryCapacity.apply(player, GodSystemCarryCapacity.getLevel(data))
    findAutoRecycler(data, player)
    sendState(player)
end

function Commands.syncClientData(_, _, player, args)
    local item = findAutoRecycler(playerData(player), player)
    local terminalSync = nil
    if args and args.terminalSync == true and item then
        GodSystemServer.syncTerminalApplyReport(item, {}, true)
        terminalSync = GodSystemServer.buildTerminalSyncPayload(item, player)
    end
    sendState(player, terminalSync)
end

function Commands.refresh(_, _, player, args)
    local data = playerData(player)
    data.stats.moveDistance = math.max(data.stats.moveDistance or 0, n(args and args.clientMoveDistance, data.stats.moveDistance or 0))
    findAutoRecycler(data, player)
    sendState(player)
end

function Commands.diagnostics(_, _, player)
    sendState(player)
end

function Commands.adminConfigGet(_, _, player)
    if not isAdminPlayer(player) then
        return finish(player, false, "Admin only")
    end
    applyAdminConfigStore()
    sendState(player)
end

function Commands.adminConfigSet(_, _, player, args)
    if not isAdminPlayer(player) then
        return finish(player, false, "Admin only")
    end
    local data = adminConfigStore()
    data.settings = GodSystemAdminConfig.sanitizeSettings(args and args.settings or {})
    applyAdminConfigStore()
    findAutoRecycler(playerData(player), player)
    transmitAdminConfig()
    finish(player, true, "Admin config saved")
end

function Commands.adminItemOverrideSet(_, _, player, args)
    if not isAdminPlayer(player) then
        return finish(player, false, "Admin only")
    end
    local fullType = tostring(args and args.fullType or "")
    fullType = fullType:gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then
        return finish(player, false, "Item fullType required")
    end
    local override = GodSystemAdminConfig.sanitizeItemOverride(args and args.override or {})
    if not override then
        return finish(player, false, "No override value")
    end
    local data = adminConfigStore()
    data.itemOverrides = data.itemOverrides or {}
    data.itemOverrides[fullType] = override
    applyAdminConfigStore()
    transmitAdminConfig()
    finish(player, true, "Item override saved")
end

function Commands.adminItemOverrideClear(_, _, player, args)
    if not isAdminPlayer(player) then
        return finish(player, false, "Admin only")
    end
    local fullType = tostring(args and args.fullType or "")
    fullType = fullType:gsub("^%s+", ""):gsub("%s+$", "")
    if fullType == "" then
        return finish(player, false, "Item fullType required")
    end
    local data = adminConfigStore()
    data.itemOverrides = data.itemOverrides or {}
    data.itemOverrides[fullType] = nil
    applyAdminConfigStore()
    transmitAdminConfig()
    finish(player, true, "Item override cleared")
end

function Commands.syncKills(_, _, player, args)
    applyAdminConfigStore()
    local data = playerData(player)
    local kills = math.max(0, floor(args and args.clientKills, 0))
    if data.lastKnownKills == nil or kills < data.lastKnownKills then
        if data.lastKnownKills ~= nil and kills < data.lastKnownKills then
            for i = 1, #(data.tasks or {}) do
                local task = data.tasks[i]
                if task and task.status == "active" and task.kind == "kill" then
                    ensureKillTaskProgress(task, data.lastKnownKills)
                end
            end
        end
        data.lastKnownKills = kills
        return
    end
    local delta = kills - data.lastKnownKills
    if delta <= 0 then return end
    data.lastKnownKills = kills
    applyKillTaskDelta(data, delta, kills - delta)
    local reward = math.max(0, floor(GodSystemConfig.KillPointReward, 0))
    if reward <= 0 then return end
    local amount = delta * reward
    if giveCurrency(player, amount) then
        appendHistory(data, historyEntry("points", "KillReward", { amount }))
        notifyCode(player, "KillReward", { amount })
        sendState(player)
    end
end

function Commands.debugGrant(_, _, player, args)
    local code = tostring(args and args.code or "")
    if code ~= "12130" then
        return finish(player, false, "测试码错误")
    end
    local data = playerData(player)
    local amount = 10000
    if not giveCurrency(player, amount) then
        return finish(player, false, "测试点数发放失败")
    end
    appendHistory(data, historyEntry("points", "DebugGrant", { amount }))
    finish(player, true, "测试点数 +" .. tostring(amount))
end

function Commands.bank(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableBank") == false then return finish(player, false, "Bank disabled") end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local bank = getBank(data)
        local action = tostring(args and args.action or "")
        local amount = math.max(1, floor(args and args.amount, 0))
        if action == "toggleAutoDeposit" then
            bank.autoDepositEnabled = bank.autoDepositEnabled ~= true
            bank.lastAutoDepositHour = nowHours()
            return finishCode(player, true, bank.autoDepositEnabled and "AutoDepositEnabled" or "AutoDepositDisabled")
        elseif action == "deposit" then
            if not removeCurrency(player, amount) then return finish(player, false, "系统币不足") end
            bank.current = (bank.current or 0) + amount
            data.stats.bankDeposited = (data.stats.bankDeposited or 0) + amount
            appendHistory(data, historyEntry("bank", "BankDeposit", { amount }))
            return finish(player, true, "活期存入成功")
        elseif action == "depositAllCash" then
            local isAuto = args and args.auto == true
            if isAuto then bank.lastAutoDepositHour = nowHours() end
            local total = math.max(0, getBalance(player))
            if total <= 0 then
                if isAuto then return finishCode(player, true, "", {}, { kind = "autoDeposit", amount = 0 }) end
                notifyCode(player, "BankDepositAllEmpty")
                return finish(player, false, "")
            end
            if not removeCurrency(player, total) then return finish(player, false, "") end
            bank.current = (bank.current or 0) + total
            data.stats.bankDeposited = (data.stats.bankDeposited or 0) + total
            appendHistory(data, historyEntry("bank", "BankDepositAll", { total }))
            return finishCode(player, true, "BankDepositAll", { total }, { kind = isAuto and "autoDeposit" or "depositAll", amount = total })
        elseif action == "withdraw" then
            if (bank.current or 0) < amount then return finish(player, false, "活期余额不足") end
            if not giveCurrency(player, amount) then return finish(player, false, "取款失败") end
            bank.current = (bank.current or 0) - amount
            data.stats.bankWithdrawn = (data.stats.bankWithdrawn or 0) + amount
            appendHistory(data, historyEntry("bank", "BankWithdraw", { amount }))
            return finish(player, true, "活期取出成功")
        elseif action == "borrowLoan" then
            local okLoan, msg = borrowBankLoan(player, data, bank, args and args.termId, amount)
            return finish(player, okLoan, msg or "")
        elseif action == "repayLoanDue" then
            local okLoan, msg = repayBankLoanDue(player, data, bank)
            return finish(player, okLoan, msg or "")
        elseif action == "payoffLoan" then
            local okLoan, msg = payoffBankLoan(player, data, bank)
            return finish(player, okLoan, msg or "")
        elseif action == "withdrawFixed" then
            local entry, index = bankFixedEntry(bank, args and args.entryId)
            if not entry or not index then return finish(player, false, "请选择死期存款") end
            local payout, interestOrPenalty, mature = bankFixedPayout(entry)
            bank.current = (bank.current or 0) + payout
            table.remove(bank.fixed, index)
            if mature then
                data.stats.bankInterest = (data.stats.bankInterest or 0) + math.max(0, interestOrPenalty)
                appendHistory(data, historyEntry("bank", "BankFixedWithdraw", { payout, math.max(0, interestOrPenalty) }))
                return finish(player, true, "死期到期支取成功")
            end
            data.stats.bankPenalty = (data.stats.bankPenalty or 0) + math.abs(math.min(0, interestOrPenalty))
            appendHistory(data, historyEntry("bank", "BankFixedEarlyWithdraw", { payout, math.abs(math.min(0, interestOrPenalty)) }))
            return finish(player, true, "死期提前支取成功")
        elseif action == "investFromCurrent" then
            local okInvestment, code, codeArgs = investBankCurrent(data, args and args.termId, amount)
            return finishCode(player, okInvestment, code, codeArgs)
        elseif action == "investFromCash" then
            local okInvestment, code, codeArgs = investBankCash(player, data, args and args.termId, amount)
            return finishCode(player, okInvestment, code, codeArgs)
        elseif action == "redeemInvestment" then
            local okInvestment, code, codeArgs = redeemBankInvestment(data, args and args.termId, amount)
            return finishCode(player, okInvestment, code, codeArgs)
        elseif action == "syncInvestmentHours" then
            local elapsedHours = math.max(0, floor(args and args.hours, 0))
            if elapsedHours <= 0 then
                return finishCode(player, true, "", {}, { kind = "investmentProgress", hours = 0 })
            end
            local settledCount, totalDelta = applyBankInvestmentElapsed(data, elapsedHours)
            if settledCount > 0 then
                return finishCode(player, true, "BankInvestmentSettled", { settledCount, totalDelta }, {
                    kind = "investmentProgress",
                    hours = elapsedHours,
                    settledCount = settledCount,
                    totalDelta = totalDelta,
                })
            end
            return finishCode(player, true, "", {}, { kind = "investmentProgress", hours = elapsedHours })
        end
        finish(player, false, "未知银行操作")
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.consolidateCurrency(_, _, player)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local success, total, originalCount, newCount = consolidateCurrency(player)
        if not success then
            if (total or 0) <= 0 then
                notifyCode(player, "CurrencyConsolidateNone")
                return finish(player, false, "")
            end
            notifyCode(player, "CurrencyConsolidateFailed")
            return finish(player, false, "")
        end
        appendHistory(data, historyEntry("bank", "CurrencyConsolidated", { total, originalCount, newCount }))
        notifyCode(player, "CurrencyConsolidated", { total, originalCount, newCount })
        return finish(player, true, "")
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.death(_, _, player)
    local data = playerData(player)
    local terminalState = GodSystemServer.terminalCache[userKey(player)]
    GodSystemServer.terminalCache[userKey(player)] = nil
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" and task.kind == "kill" then
            ensureKillTaskProgress(task, data.lastKnownKills or 0)
        end
    end
    local penalty = applyBankDeathPenalty(data)
    local failed = failActiveTasksOnDeath(player, data)
    if penalty > 0 then notifyCode(player, "BankDeathPenalty", { penalty }) end
    if failed > 0 then notifyCode(player, "DeathTasksFailed", { failed }) end
    transmitStore()
    sendState(player)
end

function Commands.buyShop(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableShop") == false then return finish(player, false, "Shop disabled") end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local row, lookupReason = shopById(data, args and args.id)
        if not row then
            if lookupReason == "hidden" then return finishCode(player, false, "ShopItemHiddenStale") end
            return finish(player, false, "商品不存在")
        end
        local quantity = math.max(1, floor(args and args.quantity, 1))
        local price = shopUnitPrice(row) * quantity
        if not canAfford(player, price, data) then return finish(player, false, "系统币不足") end
        local grant = {}
        for i = 1, #(row.items or {}) do
            if not itemExists(row.items[i].fullType) then return finish(player, false, "物品不存在: " .. tostring(row.items[i].fullType)) end
            grant[#grant + 1] = { fullType = row.items[i].fullType, worldSprite = row.items[i].worldSprite, count = math.max(1, floor(row.items[i].count, 1)) * quantity }
        end
        local addedAll = {}
        for i = 1, #grant do
            local okGive, added = nil, nil
            if grant[i].worldSprite then
                okGive, added = GodSystemShopVariants.addItems(player:getInventory(), grant[i].fullType, grant[i].worldSprite, grant[i].count)
                if okGive and sendAddItemToContainer then
                    local synced = true
                    for j = 1, #added do
                        local spriteOk = GodSystemShopVariants.getWorldSprite(added[j]) == grant[i].worldSprite
                        local sendOk = spriteOk and pcall(sendAddItemToContainer, player:getInventory(), added[j])
                        synced = synced and sendOk
                    end
                    if synced then
                        markInventoryDirty(player, player:getInventory())
                    else
                        for j = 1, #added do removeItemFromContainer(player:getInventory(), added[j]) end
                        okGive, added = false, {}
                    end
                end
            else
                okGive, added = giveItem(player, grant[i].fullType, grant[i].count)
            end
            if not okGive then
                local inv = player:getInventory()
                for j = 1, #addedAll do removeItemFromContainer(inv, addedAll[j]) end
                return finish(player, false, "发放物品失败，不扣币")
            end
            for j = 1, #added do addedAll[#addedAll + 1] = added[j] end
        end
        if not addPoints(player, -price, data) then
            local inv = player:getInventory()
            for j = 1, #addedAll do removeItemFromContainer(inv, addedAll[j]) end
            return finish(player, false, "系统币不足")
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + price
        data.stats.boughtItems = (data.stats.boughtItems or 0) + quantity
        appendHistory(data, shopHistoryEntry("BuyShop", row, { quantity, price }))
        finish(player, true, "购买成功")
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

local function restoreRecycleSelection(player, removed)
    local inventory = player and player:getInventory() or nil
    if not inventory then return false end
    local restored = true
    for i = 1, #(removed or {}) do
        local row = removed[i]
        local ok = pcall(function()
            inventory:AddItem(row.item)
            if sendAddItemToContainer then sendAddItemToContainer(inventory, row.item) end
        end)
        restored = restored and ok
        if ok and row.worn and row.bodyLocation and player.setWornItem then
            pcall(function() player:setWornItem(row.bodyLocation, row.item) end)
        end
        if ok and row.primary then pcall(function() player:setPrimaryHandItem(row.item) end) end
        if ok and row.secondary then pcall(function() player:setSecondaryHandItem(row.item) end) end
    end
    markInventoryDirty(player, inventory)
    return restored
end

local function recycleSelectedInternal(player, args)
    local data = playerData(player)
    local txKind = "recycleSelectedItems"
    local txRoot = store()
    local txOwner = userKey(player)
    local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
    if cached then
        local status = tostring(cached.status or "")
        if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
        if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId }) end
        if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args and args.opId }) end
        if status == "done" then
            local payload = type(cached.payload) == "table" and cached.payload or {}
            payload.opId = args and args.opId
            return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
        end
    end
    if not guard(player) then return end
    if not GodSystemTransactionOps.begin(txRoot, txOwner, txKind, args) then
        unguard(player)
        return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId })
    end
    local persisted, persistError = transmitStore()
    if not persisted then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        unguard(player)
        return errorMessage(player, tostring(persistError))
    end
    local ok, err = pcall(function()
        local function complete(okValue, code, codeArgs, payload)
            payload = type(payload) == "table" and payload or {}
            payload.opId = args and args.opId
            GodSystemTransactionOps.remember(txRoot, txOwner, txKind, args, okValue, code, codeArgs, payload)
            return finishCode(player, okValue, code, codeArgs, payload)
        end
        local mode = tostring(args and args.mode or "")
        if mode ~= "recycle" and mode ~= "recycleAndList" and mode ~= "listOnly" then
            return complete(false, "RecycleSelectionInvalid")
        end
        local selected = {}
        local seen = {}
        local types = {}
        local typeOrder = {}
        local skipped = math.min(10000, math.max(0, floor(args and args.clientSkipped, 0)))
        for i = 1, #(args and args.itemIds or {}) do
            local id = tostring(args.itemIds[i] or "")
            if id ~= "" and not seen[id] then
                seen[id] = true
                local item, container = inventoryItemById(player, id)
                if not item or not container then return complete(false, "RecycleSelectionChanged") end
                local allowed = canContextRecycleItem(item)
                local fullType = item:getFullType()
                local eligible = allowed == true
                if eligible and mode ~= "recycle" then
                    local listable, reason = canContextListItem(data, item)
                    if not listable then
                        eligible = false
                    end
                end
                if not eligible then
                    skipped = skipped + 1
                elseif mode ~= "listOnly" then
                    local signatures = type(args.containerContentSignatures) == "table" and args.containerContentSignatures or {}
                    local expected = signatures[id]
                    local hasContents = itemInventoryCount(item) > 0
                    if (hasContents or expected) and (args.allowDestroyContents ~= true or not expected or GodSystemServerContainerContentSignature(item) ~= expected) then
                        return complete(false, "RecycleSelectionContainerChanged")
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
                    types[groupKey].raw = types[groupKey].raw + recycleValue(item, true)
                    types[groupKey].count = types[groupKey].count + 1
                end
            end
        end
        if #selected <= 0 then return complete(false, "RecycleSelectionEmptySkipped", { skipped }, { processedCount = 0, skippedCount = skipped }) end

        if mode == "listOnly" then
            local totalCost = 0
            local rows = {}
            for i = 1, #typeOrder do
                local variantKey = typeOrder[i]
                local row = types[variantKey]
                local fullType = row.fullType
                local sellValue = itemSellPrice(fullType, row.item)
                local cost, buyPrice = autoShopListOnlyCost(fullType, sellValue)
                totalCost = totalCost + cost
                rows[#rows + 1] = { fullType = fullType, item = row.item, sellValue = sellValue, buyPrice = buyPrice }
            end
            local paid, fromBank, fromCash = spendCurrency(player, data, totalCost)
            if not paid then
                return complete(false, "ListOnlyInsufficient")
            end
            local unlocked = {}
            for i = 1, #rows do
                local row = rows[i]
                if not unlockAutoShopItem(data, row.fullType, row.item:getDisplayName(), row.sellValue, row.item) then
                    for j = 1, #unlocked do data.unlockedShopItems[unlocked[j]] = nil end
                    GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
                    return complete(false, "RecycleSelectionChanged")
                end
                unlocked[#unlocked + 1] = GodSystemShopVariants.getKey(row.fullType, row.item)
            end
            appendHistory(data, historyEntry("shop", "RecycleSelectionListOnly", { #rows, totalCost }))
            local resultCode = skipped > 0 and "RecycleSelectionListOnlyPartial" or "RecycleSelectionListOnly"
            return complete(true, resultCode, { #rows, totalCost, skipped }, { processedCount = #rows, skippedCount = skipped, cost = totalCost })
        end

        local rawPayout = 0
        for i = 1, #typeOrder do
            local row = types[typeOrder[i]]
            rawPayout = rawPayout + calculateRecyclePayout(row.fullType, row.raw, row.count)
        end
        if rawPayout <= 0 then return complete(false, "RecycleSelectionEmpty") end

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
            local removedOk = removeItemFromContainer(row.container, item)
            if not removedOk then
                local current = {
                    item = item,
                    primary = item == primary,
                    secondary = item == secondary,
                    worn = worn,
                    bodyLocation = bodyLocation,
                }
                if GodSystemServerContainerContainsItem(row.container, item) then
                    if current.worn and current.bodyLocation and player.setWornItem then
                        pcall(function() player:setWornItem(current.bodyLocation, current.item) end)
                    end
                    if current.primary then pcall(function() player:setPrimaryHandItem(current.item) end) end
                    if current.secondary then pcall(function() player:setSecondaryHandItem(current.item) end) end
                else
                    removed[#removed + 1] = current
                end
                restoreRecycleSelection(player, removed)
                return complete(false, "RecycleSelectionFailed")
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
        local payout = applyRecycleDailyPayout(data, rawPayout)
        if payout > 0 and not giveCurrency(player, payout) then
            data.recycleLimitDay = oldLimitDay
            data.recycleLimitUsed = oldLimitUsed
            restoreRecycleSelection(player, removed)
            return complete(false, "RecycleSelectionFailed")
        end
        if mode == "recycleAndList" then
            for i = 1, #typeOrder do
                local row = types[typeOrder[i]]
                unlockAutoShopItem(data, row.fullType, row.item:getDisplayName(), itemSellPrice(row.fullType, row.item), row.item)
            end
        end
        data.stats.recycledItems = (data.stats.recycledItems or 0) + #removed
        data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
        local historyCode = mode == "recycleAndList" and "RecycleSelectionAndList" or "RecycleSelectionSuccess"
        local code = skipped > 0 and (historyCode .. "Partial") or historyCode
        appendHistory(data, historyEntry("recycle", historyCode, { #removed, payout }))
        return complete(true, code, { #removed, payout, skipped }, { processedCount = #removed, skippedCount = skipped, payout = payout })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local persisted, persistError = transmitStore()
        if not persisted then
            GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
            return errorMessage(player, tostring(persistError))
        end
        errorMessage(player, tostring(err))
    end
end

function Commands.recycle(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableRecycle") == false then return finish(player, false, "Recycle disabled") end
    if args and args.itemIds then
        return recycleSelectedInternal(player, args)
    end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local fullType = args and args.fullType
        local count = math.max(1, floor(args and args.count, 1))
        local found = inventoryItems(player, fullType, false, false)
        if #found <= 0 then return finish(player, false, "没有可回收物品") end
        count = math.min(count, #found)
        local raw = 0
        local removed = {}
        local details = {}
        for i = 1, count do
            local item = found[i].item
            if canRecycleItem(item, false) then
                local value = recycleValue(item)
                raw = raw + value
                removed[#removed + 1] = found[i]
                details[#details + 1] = { fullType = item:getFullType(), label = item:getDisplayName() or item:getFullType(), sellValue = itemSellPrice(item:getFullType(), item), worldSprite = GodSystemShopVariants.getWorldSprite(item) }
            end
        end
        local payoutRaw = calculateRecyclePayout(fullType, raw, #removed)
        if #removed <= 0 or payoutRaw <= 0 then return finish(player, false, "数量不足，无法回收为 1 币") end
        for i = 1, #removed do removeItemFromContainer(removed[i].container, removed[i].item) end
        local payout = applyRecycleDailyPayout(data, payoutRaw)
        if payout > 0 then giveCurrency(player, payout) end
        data.stats.recycledItems = (data.stats.recycledItems or 0) + #removed
        data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
        if data.recycleUnlockMode == true then
            for i = 1, #details do unlockAutoShopItem(data, details[i].fullType, details[i].label, details[i].sellValue, details[i].worldSprite) end
        end
        appendHistory(data, historyEntry("recycle", "Recycle", { #removed, payout }))
        finish(player, true, "回收成功 +" .. tostring(payout))
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.listOnlyAutoShop(_, _, player, args)
    applyAdminConfigStore()
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local fullType = tostring(args and args.fullType or "")
        local itemId = tostring(args and args.itemId or "")
        if fullType == "" or itemId == "" then return finishCode(player, false, "RecycleSelectionChanged") end
        if not isAutoShopListOnlyAllowed(fullType) then return finish(player, false, "该物品无法上架") end
        local item, container = inventoryItemById(player, itemId)
        if not item or not container or item:getFullType() ~= fullType then
            return finishCode(player, false, "RecycleSelectionChanged")
        end
        local listable, reason = canContextListItem(data, item)
        if not listable then
            if reason == "configuredListed" then return finishCode(player, true, "ShopConfiguredAlreadyListed") end
            if reason == "hiddenListed" then return finishCode(player, true, "ShopHiddenAlreadyListed") end
            if reason == "alreadyListed" then return finishCode(player, true, "ListOnlyAlreadyUnlocked") end
            return finish(player, false, "该物品无法上架")
        end
        local label = item and item.getDisplayName and item:getDisplayName() or fullType
        local sellValue = itemSellPrice(fullType, item)
        local cost, buyPrice = autoShopListOnlyCost(fullType, sellValue)
        local paid, fromBank, fromCash = spendCurrency(player, data, cost)
        if not paid then return finishCode(player, false, "ListOnlyInsufficient") end
        local unlocked = unlockAutoShopItem(data, fullType, label, sellValue, item)
        if not unlocked then
            GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
            return finishCode(player, false, "RecycleSelectionChanged")
        end
        appendHistory(data, historyEntry("shop", "ListOnlyAutoShop", { label, cost, buyPrice }))
        finish(player, true, "上架成功 -" .. tostring(cost))
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

local function recycleWaistInternal(player, args, unlockShop)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableRecycle") == false then
        return finishCode(player, false, "RecycleDisabled")
    end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local inv = autoRecyclerInventory(data, player)
        if not inv then return finishCode(player, false, "RecycleWaistMissing") end
        local selected = args and args.selected or nil
        local items = inv:getItems()
        local groups = {}
        local removed = {}
        local rawByType = {}
        local unlockDetails = {}
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if canRecycleItem(item, true) then
                local fullType = item:getFullType()
                if selected == nil or selected[fullType] == true then
                    groups[fullType] = (groups[fullType] or 0) + 1
                    rawByType[fullType] = (rawByType[fullType] or 0) + recycleValue(item)
                    removed[#removed + 1] = item
                    local variantKey = GodSystemShopVariants.getKey(fullType, item)
                    if unlockShop == true and not unlockDetails[variantKey] then
                        unlockDetails[variantKey] = { fullType = fullType, label = item:getDisplayName() or fullType, sellValue = itemSellPrice(fullType, item), worldSprite = GodSystemShopVariants.getWorldSprite(item) }
                    end
                end
            end
        end
        local payoutRaw = 0
        for fullType, count in pairs(groups) do
            payoutRaw = payoutRaw + calculateRecyclePayout(fullType, rawByType[fullType] or 0, count)
        end
        if #removed <= 0 or payoutRaw <= 0 then
            if args and args.auto == true then
                return finishCode(player, true, "", {}, { kind = "autoWaistRecycle", count = 0 })
            end
            return finishCode(player, false, "RecycleWaistEmpty")
        end
        for i = 1, #removed do removeItemFromContainer(inv, removed[i]) end
        local payout = applyRecycleDailyPayout(data, payoutRaw)
        if payout > 0 then giveCurrency(player, payout) end
        if unlockShop == true then
            for _, detail in pairs(unlockDetails) do unlockAutoShopItem(data, detail.fullType, detail.label, detail.sellValue, detail.worldSprite) end
        end
        data.stats.recycledItems = (data.stats.recycledItems or 0) + #removed
        data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
        local code = unlockShop and "RecycleWaistAndUnlock" or "RecycleWaist"
        appendHistory(data, historyEntry("recycle", code, { #removed, payout }))
        finishCode(player, true, code, { #removed, payout })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end
function Commands.recycleWaist(_, _, player, args)
    recycleWaistInternal(player, args, false)
end

function Commands.recycleWaistAndUnlock(_, _, player, args)
    recycleWaistInternal(player, args, true)
end
function Commands.claimWaist(_, _, player)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        if findAutoRecycler(data, player) then return finishCode(player, true, "ClaimWaistOwned") end
        local cost = 0
        if data.autoRecyclerClaimed then
            local level = GodSystemTerminalUpgrades.getRecoveryLevel(data)
            for i = 1, #(GodSystemConfig.AutoRecyclerRecoverCosts or {}) do
                local row = GodSystemConfig.AutoRecyclerRecoverCosts[i]
                if level <= (row.maxLevel or level) then cost = row.cost or 0 break end
            end
        end
        if cost > 0 and not canAfford(player, cost, data) then return finishCode(player, false, "CurrencyNotEnough") end
        if cost > 0 and not addPoints(player, -cost, data) then return finishCode(player, false, "CurrencyNotEnough") end
        local okGive, added = GodSystemServer.giveConfiguredTerminal(player, data)
        if not okGive or not added then
            if cost > 0 then giveCurrency(player, cost) end
            return finishCode(player, false, "ItemGrantFailed")
        end
        data.autoRecyclerClaimed = true
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        GodSystemServer.terminalCache[userKey(player)] = { player = player, item = added }
        local code = cost > 0 and "ClaimWaistPaid" or "ClaimWaist"
        appendHistory(data, historyEntry("system", code, { cost }))
        finishCode(player, true, code, { cost }, {
            terminalSync = GodSystemServer.buildTerminalSyncPayload(added, player),
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.upgradeWaist(_, _, player)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local item = findAutoRecycler(data, player)
        if not item then return finishCode(player, false, "RecycleWaistMissing") end
        local info = GodSystemTerminalUpgrades.getUpgradeInfo(data, "capacity")
        local level = info.level
        if not info.nextCost then return finishCode(player, false, "UpgradeWaistMax") end
        local cost = info.nextCost
        if cost > 0 and not canAfford(player, cost, data) then return finishCode(player, false, "UpgradeWaistNoMoney") end
        local snapshot = GodSystemTerminalUpgrades.snapshotTerminal(item, player)
        GodSystemTerminalUpgrades.setLevel(data, "capacity", level + 1)
        local applied, report = GodSystemTerminalUpgrades.applyTerminal(item, data, player)
        if not applied then
            GodSystemTerminalUpgrades.setLevel(data, "capacity", level)
            local _, restoreReport = GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
            GodSystemServer.syncTerminalApplyReport(item, restoreReport)
            markAutoRecycler(data, item, player)
            return finishCode(player, false, "TerminalUpgradeApplyFailed")
        end
        if cost > 0 and not addPoints(player, -cost, data) then
            GodSystemTerminalUpgrades.setLevel(data, "capacity", level)
            local _, restoreReport = GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
            GodSystemServer.syncTerminalApplyReport(item, restoreReport)
            markAutoRecycler(data, item, player)
            return finishCode(player, false, "UpgradeWaistNoMoney")
        end
        markAutoRecycler(data, item, player, report)
        data.autoRecyclerClaimed = true
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        appendHistory(data, historyEntry("system", "UpgradeWaist", { level + 1, cost }))
        finishCode(player, true, "UpgradeWaist", { level + 1, cost }, {
            terminalSync = GodSystemServer.buildTerminalSyncPayload(item, player),
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.toggleWaistAuto(_, _, player)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableWaistAutoRecycle") == false then return finishCode(player, false, "WaistAutoDisabled") end
    local data = playerData(player)
    if not findAutoRecycler(data, player) then return finishCode(player, false, "RecycleWaistMissing") end
    if data.waistAutoRecycleUnlocked ~= true then
        local cost = math.max(0, floor(GodSystemConfig.WaistAutoRecycleUnlockCost, 100))
        if cost > 0 and not canAfford(player, cost, data) then return finishCode(player, false, "CurrencyNotEnough") end
        if cost > 0 and not addPoints(player, -cost, data) then return finishCode(player, false, "CurrencyNotEnough") end
        data.waistAutoRecycleUnlocked = true
        data.waistAutoRecycleEnabled = true
        data.lastWaistAutoRecycleHour = math.floor(nowHours())
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        appendHistory(data, historyEntry("system", "UnlockWaistAuto", { cost }))
        return finishCode(player, true, "WaistAutoUnlocked", { cost })
    end
    data.waistAutoRecycleEnabled = data.waistAutoRecycleEnabled ~= true
    if data.waistAutoRecycleEnabled then data.lastWaistAutoRecycleHour = math.floor(nowHours()) end
    finishCode(player, true, data.waistAutoRecycleEnabled and "WaistAutoRecycleEnabled" or "WaistAutoRecycleDisabled")
end
local function medicalBody(player)
    if not player then return nil end
    return safeCall(player, "getBodyDamage", nil)
end

local function medicalBool(object, methods)
    for i = 1, #(methods or {}) do
        local value = safeCall(object, methods[i], nil)
        if value == true then
            return true
        elseif value == false then
            return false
        end
    end
    return false
end

local function medicalNumber(object, methods, fallback)
    for i = 1, #(methods or {}) do
        local value = tonumber(safeCall(object, methods[i], nil))
        if value ~= nil then return value end
    end
    return fallback
end

local function medicalList(list)
    local result = {}
    if not list then return result end
    if type(list) == "table" then
        for _, value in pairs(list) do result[#result + 1] = value end
        return result
    end
    if not list.size or not list.get then return result end
    local size = tonumber(list:size()) or 0
    for i = 0, size - 1 do
        local value = list:get(i)
        if value ~= nil then result[#result + 1] = value end
    end
    return result
end

local function medicalBodyParts(body)
    return medicalList(safeCall(body, "getBodyParts", nil))
end

local function medicalCaptureInfection(body)
    return {
        infected = medicalBool(body, { "IsInfected", "isInfected" }),
        fakeInfected = medicalBool(body, { "IsFakeInfected", "isFakeInfected" }),
        infectionTime = medicalNumber(body, { "getInfectionTime" }, nil),
        mortalityDuration = medicalNumber(body, { "getInfectionMortalityDuration" }, nil),
        infectionLevel = medicalNumber(body, { "getInfectionLevel" }, nil),
    }
end

local function medicalRestoreInfection(body, snapshot)
    if not body or not snapshot or snapshot.infected ~= true then return end
    safeCall(body, "setInfected", nil, true)
    safeCall(body, "setIsFakeInfected", nil, snapshot.fakeInfected == true)
    if snapshot.infectionTime ~= nil then safeCall(body, "setInfectionTime", nil, snapshot.infectionTime) end
    if snapshot.mortalityDuration ~= nil then safeCall(body, "setInfectionMortalityDuration", nil, snapshot.mortalityDuration) end
    if snapshot.infectionLevel ~= nil then safeCall(body, "setInfectionLevel", nil, snapshot.infectionLevel) end
end

local function medicalIsInfected(body)
    if not body then return false end
    if medicalBool(body, { "IsInfected", "isInfected" }) then return true end
    local level = medicalNumber(body, { "getInfectionLevel" }, 0) or 0
    if level > 0 then return true end
    local time = medicalNumber(body, { "getInfectionTime" }, -1) or -1
    return time > 0
end

local function medicalHasInjury(body)
    if not body then return false end
    local overall = medicalNumber(body, { "getOverallBodyHealth", "getHealth" }, nil)
    if overall and overall < 99.5 then return true end
    local boolMethods = {
        "HasInjury", "hasInjury", "isBleeding", "IsBleeding", "bleeding",
        "isDeepWounded", "deepWounded", "haveBullet", "haveGlass", "isBurnt", "stitched",
    }
    local timeMethods = {
        "getBleedingTime", "getDeepWoundTime", "getScratchTime", "getCutTime",
        "getBiteTime", "getBurnTime", "getFractureTime", "getWoundInfectionLevel", "getAdditionalPain",
    }
    local parts = medicalBodyParts(body)
    for i = 1, #parts do
        local part = parts[i]
        local health = medicalNumber(part, { "getHealth" }, nil)
        if health and health < 99.5 then return true end
        for j = 1, #boolMethods do
            if safeCall(part, boolMethods[j], false) == true then return true end
        end
        for j = 1, #timeMethods do
            if (tonumber(safeCall(part, timeMethods[j], 0)) or 0) > 0 then return true end
        end
    end
    return false
end

local function medicalClearBodyPartInfection(part)
    if not part then return end
    safeCall(part, "SetInfected", nil, false)
    safeCall(part, "SetFakeInfected", nil, false)
    safeCall(part, "setInfectedWound", nil, false)
    safeCall(part, "setWoundInfectionLevel", nil, -1)
end

local function medicalClearInfection(body, player)
    if not body then return false end
    if player and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil then
        local stats = safeCall(player, "getStats", nil)
        if stats then
            pcall(function()
                stats:set(CharacterStat.ZOMBIE_INFECTION, 0)
            end)
        end
    end
    safeCall(body, "setInfectionTime", nil, -1.0)
    safeCall(body, "setInfectionLevel", nil, 0)
    safeCall(body, "setInfected", nil, false)
    safeCall(body, "setIsFakeInfected", nil, false)
    safeCall(body, "setInfectionMortalityDuration", nil, -1.0)
    local parts = medicalBodyParts(body)
    for i = 1, #parts do
        medicalClearBodyPartInfection(parts[i])
    end
    return medicalIsInfected(body) ~= true
end

local function medicalHealPart(part)
    if not part then return end
    safeCall(part, "SetHealth", nil, 100)
    safeCall(part, "setHealth", nil, 100)
    safeCall(part, "setBleedingTime", nil, 0)
    safeCall(part, "setDeepWoundTime", nil, 0)
    safeCall(part, "setScratchTime", nil, 0)
    safeCall(part, "setCutTime", nil, 0)
    safeCall(part, "setBiteTime", nil, 0)
    safeCall(part, "setBurnTime", nil, 0)
    safeCall(part, "setFractureTime", nil, 0)
    safeCall(part, "setAdditionalPain", nil, 0)
    safeCall(part, "setWoundInfectionLevel", nil, 0)
    safeCall(part, "setHaveBullet", nil, false, 0)
    safeCall(part, "setHaveGlass", nil, false)
    safeCall(part, "setStitched", nil, false)
    safeCall(part, "setSplint", nil, false, 0)
    safeCall(part, "setBandaged", nil, false, 0, false, "", nil)
end

local function medicalHealInjuries(player, body)
    body = body or medicalBody(player)
    if not body then return false end
    local snapshot = medicalCaptureInfection(body)
    local parts = medicalBodyParts(body)
    for i = 1, #parts do medicalHealPart(parts[i]) end
    safeCall(body, "setOverallBodyHealth", nil, 100)
    safeCall(player, "setHealth", nil, 1.0)
    medicalRestoreInfection(body, snapshot)
    return true
end

local function medicalServiceInfo(action)
    action = tostring(action or "")
    if action == "checkInfection" then
        return { action = action, cost = math.max(0, floor(GodSystemConfig.MedicalCheckInfectionCost, 50)) }
    elseif action == "healInjuries" then
        return { action = action, cost = math.max(0, floor(GodSystemConfig.MedicalHealInjuriesCost, 5000)) }
    elseif action == "cureInfection" then
        return { action = action, cost = math.max(0, floor(GodSystemConfig.MedicalCureInfectionCost, 2000)) }
    end
    return nil
end

local function medicalApply(player, action, body)
    if action == "checkInfection" then
        return true, medicalIsInfected(body) and "infected" or "clean"
    elseif action == "healInjuries" then
        return medicalHealInjuries(player, body), "healed"
    elseif action == "cureInfection" then
        return medicalClearInfection(body, player), "cured"
    end
    return false, "unknown"
end

local function medicalNotifyMessage(action, result)
    if action == "checkInfection" then
        return result == "infected" and "检查结果：已感染僵尸病毒" or "检查结果：未感染僵尸病毒"
    elseif action == "healInjuries" then
        return "伤势已治疗"
    elseif action == "cureInfection" then
        return "僵尸病毒已治愈"
    end
    return "医疗服务完成"
end

function Commands.medicalService(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local action = tostring(args and args.action or "")
        local info = medicalServiceInfo(action)
        if not info then return finish(player, false, "未知医疗服务") end
        local body = medicalBody(player)
        if not body then return finish(player, false, "医疗接口不可用") end
        local infected = medicalIsInfected(body)
        local injured = medicalHasInjury(body)
        if action == "cureInfection" and infected ~= true then
            return finish(player, false, "未检测到僵尸病毒")
        end
        if action == "healInjuries" and injured ~= true then
            return finish(player, false, "没有需要治疗的伤势")
        end
        if not canAfford(player, info.cost, data) then
            return finish(player, false, "系统币不足")
        end
        if info.cost > 0 and not addPoints(player, -info.cost, data) then
            return finish(player, false, "系统币不足")
        end
        local applied, result = medicalApply(player, action, body)
        if not applied then
            if info.cost > 0 then addPoints(player, info.cost, data) end
            return finish(player, false, "医疗服务失败")
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
        appendHistory(data, historyEntry("medical", "MedicalService", { action, info.cost }))
        return finish(player, true, medicalNotifyMessage(action, result), {
            kind = "medicalService",
            action = action,
            result = result,
            cost = info.cost,
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

local function maintenanceExpectedType(action)
    if action == "repairHeld" then return GodSystemMaintenance.RepairItemType end
    if action == "reinforceHeld" then return GodSystemMaintenance.ReinforceItemType end
    if action == "repairVehicle" then return GodSystemMaintenance.VehicleRepairItemType end
    return nil
end

function GodSystemServer.maintenanceVehicleInRange(player, vehicle)
    if not player or not vehicle then return false, "VehicleRepairInvalid" end
    if player:getVehicle() == vehicle then return true end
    if math.floor(tonumber(player:getZ()) or 0) ~= math.floor(tonumber(vehicle:getZ()) or 0) then
        return false, "VehicleRepairWrongFloor"
    end
    local dx = (tonumber(player:getX()) or 0) - (tonumber(vehicle:getX()) or 0)
    local dy = (tonumber(player:getY()) or 0) - (tonumber(vehicle:getY()) or 0)
    if (dx * dx + dy * dy) > 16 then return false, "VehicleRepairTooFar" end
    return true
end

local function rollbackMaintenanceTarget(target, snapshot)
    return GodSystemMaintenance.rollback(target, snapshot)
end

local function syncMaintenanceTarget(target)
    if not target then return end
    if sendItemStats then pcall(sendItemStats, target) end
    if target.syncItemFields then pcall(function() target:syncItemFields() end) end
    local container = target.getContainer and target:getContainer() or nil
    if container and container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
end

function Commands.useMaintenanceItem(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local action = tostring(args and args.action or "")
        local expectedType = maintenanceExpectedType(action)
        if not expectedType then return finishCode(player, false, "MaintenanceInvalidTarget") end

        local consumableItemId = tostring(args and args.consumableItemId or "")
        local targetItemId = tostring(args and args.targetItemId or "")
        local consumable, container = inventoryItemById(player, consumableItemId)
        if not consumable or not container or consumable:getFullType() ~= expectedType then
            return finishCode(player, false, "MaintenanceConsumableMissing")
        end

        if action == "repairVehicle" then
            local vehicleId = math.floor(tonumber(args and args.vehicleId) or -1)
            local vehicle = vehicleId >= 0 and getVehicleById and getVehicleById(vehicleId) or nil
            local inRange, rangeCode = GodSystemServer.maintenanceVehicleInRange(player, vehicle)
            if not inRange then return finishCode(player, false, rangeCode) end
            local before = GodSystemMaintenance.vehicleDamageSummary(vehicle)
            if before.damaged <= 0 then return finishCode(player, false, "VehicleAlreadyFull") end

            local removed = pcall(function() container:Remove(consumable) end)
            local stillOwned = inventoryItemById(player, consumableItemId) ~= nil
            if not removed or stillOwned then return finishCode(player, false, "MaintenanceFailed") end
            if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, consumable) end
            if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end

            local repaired = GodSystemMaintenance.repairVehicle(vehicle)
            if not repaired then
                local refunded = giveItem(player, expectedType, 1)
                return finishCode(player, false, refunded and "VehicleRepairFailedRefunded" or "VehicleRepairFailed")
            end
            return finishCode(player, true, "VehicleRepaired", { before.damaged, before.missing }, {
                kind = "maintenanceItem",
                action = action,
                vehicleId = vehicleId,
            })
        end

        local target = player:getPrimaryHandItem()
        if not target or tostring(GodSystemMaintenance.itemId(target) or "") ~= targetItemId then
            return finishCode(player, false, "MaintenanceTargetChanged")
        end

        local applied, code, result, before = GodSystemMaintenance.apply(target, action)
        if not applied then return finishCode(player, false, code or "MaintenanceFailed") end

        local removed = pcall(function() container:Remove(consumable) end)
        local stillOwned = inventoryItemById(player, consumableItemId) ~= nil
        if not removed or stillOwned then
            rollbackMaintenanceTarget(target, before)
            syncMaintenanceTarget(target)
            return finishCode(player, false, "MaintenanceFailed")
        end

        if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, consumable) end
        if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
        syncMaintenanceTarget(target)
        local label = target.getDisplayName and tostring(target:getDisplayName()) or tostring(target:getFullType())
        return finishCode(player, true, code, {
            label,
            result and result.after and result.after.condition or 0,
            result and result.after and result.after.conditionMax or 0,
        }, {
            kind = "maintenanceItem",
            action = action,
            targetItemId = targetItemId,
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.upgradeSystem(_, _, player, args)
    local data = playerData(player)
    local t = args and args.upgradeType
    local txKind = "upgradeSystem"
    local txRoot = store()
    local txOwner = userKey(player)
    local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
    if cached then
        local status = tostring(cached.status or "")
        if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
        if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId }) end
        if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args and args.opId }) end
        if status == "done" then
            local payload = type(cached.payload) == "table" and cached.payload or {}
            payload.opId = args and args.opId
            return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
        end
    end
    if not guard(player) then return end
    if not GodSystemTransactionOps.begin(txRoot, txOwner, txKind, args) then
        unguard(player)
        return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId })
    end
    local persisted, persistError = transmitStore()
    if not persisted then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        unguard(player)
        return errorMessage(player, tostring(persistError))
    end
    local ok, err = pcall(function()
        local function complete(okValue, code, codeArgs, payload)
            payload = type(payload) == "table" and payload or {}
            payload.opId = args and args.opId
            GodSystemTransactionOps.remember(txRoot, txOwner, txKind, args, okValue, code, codeArgs, payload)
            return finishCode(player, okValue, code, codeArgs, payload)
        end
        if t == "carryCapacity" then
            local currentLevel = GodSystemCarryCapacity.getLevel(data)
            local nextLevel = currentLevel + 1
            local cost = GodSystemCarryCapacity.getNextCost(currentLevel)
            if not cost then return complete(false, "CarryCapacityCostOverflow") end
            local applied, reason = GodSystemCarryCapacity.apply(player, nextLevel)
            if not applied then return complete(false, "CarryCapacityApplyFailed", { tostring(reason or "unknown") }) end
            if not addPoints(player, -cost, data) then
                GodSystemCarryCapacity.apply(player, currentLevel)
                return complete(false, "CurrencyNotEnough")
            end
            data.upgrades.carryCapacityLevel = nextLevel
            data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
            appendHistory(data, historyEntry("upgrade", "CarryCapacityUpgrade", {
                nextLevel,
                GodSystemCarryCapacity.getBonus(nextLevel) or 0,
                cost,
            }))
            return complete(true, "CarryCapacityUpgraded", {
                nextLevel,
                GodSystemCarryCapacity.getBonus(nextLevel) or 0,
                cost,
            }, {
                kind = "carryCapacity",
                level = nextLevel,
            })
        end
        local terminalTypes = {
            terminalCapacity = "capacity",
            terminalReduction = "reduction",
            terminalRelief = "relief",
            terminalFreshness = "freshness",
        }
        local terminalType = terminalTypes[t]
        if terminalType then
            local item = findAutoRecycler(data, player)
            if not item then return complete(false, "RecycleWaistMissing") end
            local info = GodSystemTerminalUpgrades.getUpgradeInfo(data, terminalType)
            if not info or not info.nextCost then return complete(false, "SystemUpgradeMaxed") end
            local cost = info.nextCost
            if not canAfford(player, cost, data) then return complete(false, "CurrencyNotEnough") end
            local snapshot = GodSystemTerminalUpgrades.snapshotTerminal(item, player)
            local previousLevel = info.level
            GodSystemTerminalUpgrades.setLevel(data, terminalType, previousLevel + 1)
            local applied, report = GodSystemTerminalUpgrades.applyTerminal(item, data, player)
            if not applied then
                GodSystemTerminalUpgrades.setLevel(data, terminalType, previousLevel)
                local _, restoreReport = GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
                GodSystemServer.syncTerminalApplyReport(item, restoreReport)
                markAutoRecycler(data, item, player)
                return complete(false, terminalType == "relief" and "TerminalReliefApplyFailed" or "TerminalUpgradeApplyFailed")
            end
            if not addPoints(player, -cost, data) then
                GodSystemTerminalUpgrades.setLevel(data, terminalType, previousLevel)
                local _, restoreReport = GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
                GodSystemServer.syncTerminalApplyReport(item, restoreReport)
                markAutoRecycler(data, item, player)
                return complete(false, "CurrencyNotEnough")
            end
            markAutoRecycler(data, item, player, report)
            data.autoRecyclerClaimed = true
            data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
            appendHistory(data, historyEntry("upgrade", "TerminalUpgrade", { terminalType, previousLevel + 1, cost }))
            return complete(true, "TerminalUpgradeSuccess", {
                terminalType,
                previousLevel + 1,
                cost,
                report and report.skipped or 0,
            }, {
                kind = "terminalUpgrade",
                upgradeType = terminalType,
                level = previousLevel + 1,
                skipped = report and report.skipped or 0,
                terminalSync = GodSystemServer.buildTerminalSyncPayload(item, player),
            })
        end
        local current, maxValue, nextValue, cost
        if t == "activeTasks" then
            current = maxActiveTasks(data)
            maxValue = GodSystemConfig.MaxActiveTaskLimit or 10
            nextValue = math.min(maxValue, current + 1)
            cost = current < maxValue and ((GodSystemConfig.ActiveTaskUpgradeCosts or {})[nextValue] or nextValue * 120) or nil
        elseif t == "dailyTasks" then
            current = dailyTaskCount(data)
            maxValue = GodSystemConfig.MaxDailyTaskLimit or 20
            nextValue = math.min(maxValue, current + 1)
            cost = current < maxValue and ((GodSystemConfig.DailyTaskUpgradeCosts or {})[nextValue] or nextValue * 30) or nil
        end
        if not cost then return complete(false, "SystemUpgradeMaxed") end
        if not addPoints(player, -cost, data) then return complete(false, "CurrencyNotEnough") end
        if t == "activeTasks" then
            data.upgrades.maxActiveTasks = nextValue
        elseif t == "dailyTasks" then
            data.upgrades.dailyTaskCount = nextValue
            local templates = availableTaskTemplates()
            if #templates > 0 then data.tasks[#data.tasks + 1] = generateTask(templates[randomIndex(#templates)]) end
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        appendHistory(data, historyEntry("upgrade", "UpgradeSystem", { t, current, nextValue, cost }))
        return complete(true, "SystemUpgradeSuccess", { t, current, nextValue, cost }, {
            kind = "systemUpgrade",
            upgradeType = t,
            level = nextValue,
        })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local errorPersisted, errorPersistError = transmitStore()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        return errorMessage(player, tostring(err))
    end
end

function Commands.terminalFreshnessService(_, _, player, args)
    local data = playerData(player)
    local txKind = "terminalFreshnessService"
    local txRoot = store()
    local txOwner = userKey(player)
    local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
    if cached then
        local status = tostring(cached.status or "")
        if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
        if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId }) end
        if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args and args.opId }) end
        if status == "done" then
            local payload = type(cached.payload) == "table" and cached.payload or {}
            payload.opId = args and args.opId
            return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
        end
    end
    if not guard(player) then return end
    if not GodSystemTransactionOps.begin(txRoot, txOwner, txKind, args) then
        unguard(player)
        return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId })
    end
    local persisted, persistError = transmitStore()
    if not persisted then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        unguard(player)
        return errorMessage(player, tostring(persistError))
    end
    local ok, err = pcall(function()
        local function complete(okValue, code, codeArgs, payload)
            payload = type(payload) == "table" and payload or {}
            payload.opId = args and args.opId
            GodSystemTransactionOps.remember(txRoot, txOwner, txKind, args, okValue, code, codeArgs, payload)
            return finishCode(player, okValue, code, codeArgs, payload)
        end
        local terminal = findAutoRecycler(data, player)
        if not terminal then return complete(false, "RecycleWaistMissing") end
        local days = math.max(0, floor(args and args.days, 0))
        local allowed, reason = GodSystemTerminalFood.canPurchaseService(data, days)
        if not allowed then
            local code = reason == "freshnessRequired" and "TerminalFreshnessRequired"
                or reason == "serviceCap" and "TerminalFreshnessServiceCap"
                or "TerminalFreshnessInvalidPackage"
            return complete(false, code)
        end
        local cost = GodSystemTerminalFood.getServiceCost(days)
        if not canAfford(player, cost, data) then return complete(false, "CurrencyNotEnough") end
        GodSystemTerminalFood.normalizeData(data)
        local state = data.terminalFood
        local beforeRemaining = state.remainingHours
        local beforeSettledHour = state.lastSettledHour
        local beforeExpiryNotified = state.expiryNotified
        local purchased = GodSystemTerminalFood.purchaseService(data, days, nowHours())
        if not purchased then return complete(false, "TerminalFreshnessInvalidPackage") end
        if not addPoints(player, -cost, data) then
            state.remainingHours = beforeRemaining
            state.lastSettledHour = beforeSettledHour
            state.expiryNotified = beforeExpiryNotified
            return complete(false, "CurrencyNotEnough")
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        appendHistory(data, historyEntry("terminal", "TerminalFreshnessService", { days, cost }))
        return complete(true, "TerminalFreshnessPurchased", { days, cost, state.remainingHours }, {
            kind = "terminalFreshnessService",
            days = days,
            cost = cost,
            remainingHours = state.remainingHours,
            terminalSync = GodSystemServer.buildTerminalSyncPayload(terminal, player),
        })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local errorPersisted, errorPersistError = transmitStore()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        return errorMessage(player, tostring(err))
    end
end

function Commands.refreshCarryCapacity(_, _, player)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local level = GodSystemCarryCapacity.getLevel(data)
        local applied, reason = GodSystemCarryCapacity.apply(player, level)
        if not applied then
            return finishCode(player, false, "CarryCapacityRefreshFailed", { tostring(reason or "unknown") })
        end
        finishCode(player, true, "CarryCapacityRefreshed", {
            level,
            GodSystemCarryCapacity.getBonus(level) or 0,
        }, {
            kind = "carryCapacityRefresh",
            level = level,
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.task(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableTasks") == false then return finish(player, false, "Tasks disabled") end
    local data = playerData(player)
    generateDailyTasks(data, false)
    local action = args and args.action
    if action == "toggleAutoClaim" then
        data.autoTaskClaimEnabled = data.autoTaskClaimEnabled ~= true
        data.lastAutoTaskClaimHour = nowHours()
        return finishCode(player, true, data.autoTaskClaimEnabled and "AutoTaskClaimEnabled" or "AutoTaskClaimDisabled")
    elseif action == "autoClaim" then
        data.lastAutoTaskClaimHour = nowHours()
        local claims = type(args and args.claims) == "table" and args.claims or {}
        local claimed = 0
        for i = 1, #claims do
            local claim = claims[i] or {}
            local autoTask = findTask(data, claim.taskId)
            if autoTask and autoTask.status == "active" then
                local claimedOne = claimTaskForPlayer(player, data, autoTask, claim)
                if claimedOne then claimed = claimed + 1 end
            end
        end
        if claimed > 0 then
            return finishCode(player, true, "AutoTaskClaimed", { claimed }, { kind = "autoTaskClaim", count = claimed })
        end
        return finishCode(player, true, "", {}, { kind = "autoTaskClaim", count = 0 })
    end
    local task = findTask(data, args and args.taskId)
    if not task then return finish(player, false, "任务不存在") end
    if action == "accept" then
        if task.status ~= "open" then return finish(player, false, "任务状态不正确") end
        local active = 0
        for i = 1, #data.tasks do if data.tasks[i].status == "active" then active = active + 1 end end
        if active >= maxActiveTasks(data) then return finish(player, false, "进行中任务已达上限") end
        task.status = "active"
        task.acceptedAt = nowHours()
        task.deadline = task.acceptedAt + (task.limitHours or GodSystemConfig.DefaultTaskLimitHours)
        task.startKills = math.max(0, floor(args and args.clientKills, player.getZombieKills and player:getZombieKills() or 0))
        task.killProgress = task.kind == "kill" and 0 or nil
        task.startRecycledItems = data.stats.recycledItems or 0
        task.startRecycledPoints = data.stats.recycledPoints or 0
        task.startSpentPoints = data.stats.spentPoints or 0
        task.startBoughtItems = data.stats.boughtItems or 0
        data.stats.moveDistance = math.max(data.stats.moveDistance or 0, n(args and args.clientMoveDistance, data.stats.moveDistance or 0))
        task.startMoveDistance = data.stats.moveDistance or 0
        appendHistory(data, taskHistoryEntry("AcceptTask", task))
        return finish(player, true, "任务已接取")
    elseif action == "claim" then
        local claimed, code = claimTaskForPlayer(player, data, task, args)
        return finishCode(player, claimed, code)
    elseif action == "abandon" then
        if task.status ~= "active" then return finish(player, false, "任务状态不正确") end
        failTask(player, data, task, "TaskAbandoned")
        return finish(player, true, "任务已放弃")
    end
    finish(player, false, "未知任务操作")
end

function Commands.refreshTasks(_, _, player)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableTasks") == false then return finish(player, false, "Tasks disabled") end
    local data = playerData(player)
    local cost = GodSystemConfig.RefreshTaskCost or 0
    if cost > 0 and not addPoints(player, -cost, data) then return finish(player, false, "系统币不足") end
    local templates = availableTaskTemplates()
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "open" and #templates > 0 then
            data.tasks[i] = generateTask(templates[randomIndex(#templates)])
        end
    end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    appendHistory(data, historyEntry("task", "RefreshTasks", { cost }))
    finish(player, true, "任务已刷新")
end

local function currentPosition(player)
    return { x = n(player:getX()), y = n(player:getY()), z = n(player:getZ()) }
end

local function gridSquareAt(pos)
    local cell = getCell and getCell() or nil
    if not cell or not pos then return nil end
    local ok, square = pcall(cell.getGridSquare, cell, math.floor(n(pos.x)), math.floor(n(pos.y)), math.floor(n(pos.z)))
    if ok then return square end
    return nil
end

local function squareSafe(square)
    if not square then return nil end
    if square.isSolid and square:isSolid() then return false end
    if square.isSolidTrans and square:isSolidTrans() then return false end
    if square.TreatAsSolidFloor then
        local ok, hasFloor = pcall(square.TreatAsSolidFloor, square)
        if ok and hasFloor == false then return false end
    end
    return true
end

local function safeTeleportPosition(pos)
    if not pos then return nil end
    local base = copyPosition(pos)
    local safe = squareSafe(gridSquareAt(base))
    if safe == true or safe == nil then return base end
    for radius = 1, 4 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local c = { x = math.floor(base.x) + dx + 0.5, y = math.floor(base.y) + dy + 0.5, z = base.z }
                    if squareSafe(gridSquareAt(c)) == true then return c end
                end
            end
        end
    end
    return nil
end

local function safeZoneLevelConfig(level)
    local rows = GodSystemConfig.HomeSafeZoneLevels or {}
    for i = 1, #rows do
        if (rows[i].level or i) == level then return rows[i] end
    end
    return rows[level]
end

local function collectSafeZoneZombies(center, radius)
    local result = {}
    if not center or not radius or radius <= 0 or not getCell then return result end
    local cell = getCell()
    if not cell or not cell.getZombieList then return result end
    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not okList or not zombies or not zombies.size or not zombies.get then return result end
    local okSize, size = pcall(function() return zombies:size() end)
    if not okSize or not size or size <= 0 then return result end
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
                        result[#result + 1] = zombie
                    end
                end
            end
        end
    end
    return result
end

local function removeZombieFromWorld(zombie)
    if not zombie then return false end
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

local function clearHomeSafeZone(player, data, manual)
    local home = data.homeSystem or {}
    local safe = home.safeZone or {}
    home.safeZone = safe
    safe.lastScanHours = nowHours()
    if not home.home then
        if manual then return finish(player, false, "Home is not set") end
        return 0
    end
    local level = floor(safe.level, 0)
    if level <= 0 then
        if manual then return finish(player, false, "Safe zone is locked") end
        return 0
    end
    if not manual and safe.enabled ~= true then return 0 end
    local row = safeZoneLevelConfig(level)
    if not row then return 0 end
    local targets = collectSafeZoneZombies(home.home, row.radius or 0)
    if #targets <= 0 then
        safe.lastCleared = 0
        if manual then return finish(player, true, "No zombies in safe zone") end
        return 0
    end
    local cost = math.max(0, floor(row.clearCost, 0))
    if cost > 0 and not canAfford(player, cost, data) then
        if manual or nowHours() - (safe.lastNoticeHours or -999) >= (GodSystemConfig.HomeSafeZoneInsufficientNoticeHours or 1) then
            safe.lastNoticeHours = nowHours()
            if manual then return finish(player, false, "Not enough currency for safe zone cleanup") end
            notify(player, "Not enough currency for safe zone cleanup")
        end
        return 0
    end
    local removed = 0
    for i = 1, #targets do
        if removeZombieFromWorld(targets[i]) then removed = removed + 1 end
    end
    safe.lastCleared = removed
    safe.lastClearHour = nowHours()
    if removed > 0 then
        if cost > 0 then
            addPoints(player, -cost, data)
            data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        end
        data.stats.homeSafeCleared = (data.stats.homeSafeCleared or 0) + removed
        appendHistory(data, historyEntry("home", "HomeSafeClear", { removed, cost }))
    end
    if manual then
        return finish(player, true, "Home safe zone cleared: " .. tostring(removed))
    end
    return removed
end

local function spendHomeCostCode(player, data, cost, code, args)
    cost = math.max(0, floor(cost, 0))
    if cost > 0 and not addPoints(player, -cost, data) then return false end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    local historyArgs = args or {}
    historyArgs[#historyArgs + 1] = cost
    appendHistory(data, historyEntry("home", code, historyArgs))
    return true
end

local function sendTeleportRequest(player, data, action, index, safe, history, historyArgs)
    local home = data.homeSystem or {}
    local cost = math.max(0, floor(GodSystemConfig.HomeTravelCost, 10))
    if cost > 0 and not canAfford(player, cost, data) then return finish(player, false, "系统币不足") end
    local requestId = tostring(math.floor(nowHours() * 1000)) .. "_" .. tostring(randomIndex(999999))
    home.pendingTeleport = {
        id = requestId,
        action = tostring(action or ""),
        index = index,
        safe = copyPosition(safe),
        cost = cost,
        history = tostring(history or "Teleport"),
        historyArgs = historyArgs or {},
        returnPoint = action ~= "return" and currentPosition(player) or nil,
        createdHour = nowHours(),
    }
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Teleport) or "teleport", {
        id = requestId,
        pos = copyPosition(safe),
    })
end

function Commands.teleportConfirm(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableTeleport") == false then return finish(player, false, "Teleport disabled") end
    local data = playerData(player)
    local home = data.homeSystem or {}
    local pendingTeleport = home.pendingTeleport
    if not pendingTeleport or tostring(pendingTeleport.id or "") ~= tostring(args and args.id or "") then
        return finish(player, false, "传送请求已失效")
    end
    home.pendingTeleport = nil
    if not args or args.ok ~= true then
        return finish(player, false, "传送未完成，未扣费")
    end
    local cost = math.max(0, floor(pendingTeleport.cost, 0))
    if cost > 0 and not addPoints(player, -cost, data) then
        return finish(player, false, "系统币不足")
    end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    local finalArgs = pendingTeleport.historyArgs or {}
    finalArgs[#finalArgs + 1] = cost
    appendHistory(data, historyEntry("home", pendingTeleport.history or "Teleport", finalArgs))
    if pendingTeleport.action ~= "return" and pendingTeleport.returnPoint then
        home.returnPoint = copyPosition(pendingTeleport.returnPoint)
        home.returnPoint.source = pendingTeleport.history
    elseif pendingTeleport.action == "return" then
        home.returnPoint = nil
    end
    return finish(player, true, "传送完成")
end

function Commands.home(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableTeleport") == false then return finish(player, false, "Teleport disabled") end
    local data = playerData(player)
    local home = data.homeSystem
    local action = args and args.action
    local index = math.max(1, floor(args and args.index, 1))
    if player.getVehicle and player:getVehicle() then return finish(player, false, "车内无法传送") end
    if action == "setHome" then
        local pos = currentPosition(player)
        if not safeTeleportPosition(pos) then return finish(player, false, "当前位置不安全") end
        if not spendHomeCostCode(player, data, GodSystemConfig.HomeSetCost or 100, "SetHome") then return finish(player, false, "系统币不足") end
        home.home = copyPosition(pos)
        return finish(player, true, "家园已设置")
    elseif action == "buyTemp" then
        if index > (GodSystemConfig.TempTeleportMaxSlots or 3) then return finish(player, false, "临时点不存在") end
        home.tempSlots[index] = home.tempSlots[index] or { owned = false, point = nil }
        if home.tempSlots[index].owned then return finish(player, false, "临时点已购买") end
        if not spendHomeCostCode(player, data, GodSystemConfig.TempTeleportSlotCost or 500, "BuyTemp", { index }) then return finish(player, false, "系统币不足") end
        home.tempSlots[index].owned = true
        return finish(player, true, "临时点已购买")
    elseif action == "setTemp" then
        local slot = home.tempSlots[index]
        if not slot or slot.owned ~= true then return finish(player, false, "临时点未购买") end
        local pos = currentPosition(player)
        if not safeTeleportPosition(pos) then return finish(player, false, "当前位置不安全") end
        if not spendHomeCostCode(player, data, GodSystemConfig.TempTeleportSetCost or 100, "SetTemp", { index }) then return finish(player, false, "系统币不足") end
        slot.point = copyPosition(pos)
        return finish(player, true, "临时点已设置")
    elseif action == "clearReturn" then
        home.returnPoint = nil
        appendHistory(data, historyEntry("home", "ClearReturn"))
        return finish(player, true, "出发点已删除")
    elseif action == "teleportHome" or action == "teleportTemp" or action == "return" then
        local target = nil
        local history = "传送"
        if action == "teleportHome" then
            target = home.home
            history = "TeleportHome"
        elseif action == "teleportTemp" then
            local slot = home.tempSlots[index]
            target = slot and slot.point
            history = "TeleportTemp"
        else
            target = home.returnPoint
            history = "Return"
        end
        if not target then return finish(player, false, "目标未设置") end
        local safe = safeTeleportPosition(target)
        if not safe then return finish(player, false, "目标附近没有安全落点") end
        local historyArgs = action == "teleportTemp" and { index } or {}
        do
            return sendTeleportRequest(player, data, action, index, safe, history, historyArgs)
        end
        if not spendHomeCostCode(player, data, GodSystemConfig.HomeTravelCost or 10, history, historyArgs) then return finish(player, false, "系统币不足") end
        if action ~= "return" then
            home.returnPoint = currentPosition(player)
            home.returnPoint.source = history
        end
        player:setX(safe.x); player:setY(safe.y); player:setZ(safe.z)
        if player.setLastX then player:setLastX(safe.x) end
        if player.setLastY then player:setLastY(safe.y) end
        if player.setLastZ then player:setLastZ(safe.z) end
        if action == "return" then home.returnPoint = nil end
        return finish(player, true, "传送完成")
    elseif action == "toggleSafeZone" then
        home.safeZone.enabled = home.safeZone.enabled ~= true
        return finish(player, true, home.safeZone.enabled and "安全区已开启" or "安全区已关闭")
    elseif action == "unlockSafeZone" or action == "upgradeSafeZone" then
        local level = floor(home.safeZone.level, 0)
        local nextLevel = action == "unlockSafeZone" and 1 or (level + 1)
        local row = (GodSystemConfig.HomeSafeZoneLevels or {})[nextLevel]
        if not row then return finish(player, false, "安全区已满级") end
        local cost = row.unlockCost or row.upgradeCost or 0
        if not spendHomeCostCode(player, data, cost, action == "unlockSafeZone" and "HomeSafeUnlock" or "HomeSafeUpgrade") then return finish(player, false, "系统币不足") end
        home.safeZone.level = nextLevel
        home.safeZone.enabled = true
        return finish(player, true, "家园安全区已升级")
    elseif action == "clearSafeZone" then
        return clearHomeSafeZone(player, data, true)
    end
    finish(player, false, "未知家园操作")
end

function Commands.attribute(_, _, player, args)
    applyAdminConfigStore()
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return finishCode(player, false, "AttributeOperationInvalid") end
    local cached = GodSystemServer.getAttributeOpResult(player, args)
    if cached then
        if cached.status == "mismatch" then return finishCode(player, false, "AttributeOperationInvalid", {}, { opId = opId }) end
        if cached.status == "processing" then return finishCode(player, false, "AttributeOperationPending", {}, { opId = opId }) end
        if cached.status == "unknown" then return finishCode(player, false, "AttributeOperationUnknown", {}, { opId = opId }) end
        return finishCode(player, cached.ok, cached.code, cached.args, cached.payload)
    end
    local opStarted = false
    local function respond(ok, code, codeArgs, payload)
        local responsePayload = payload or {}
        if args and args.opId ~= nil then responsePayload.opId = args.opId end
        GodSystemServer.rememberAttributeOpResult(player, args, ok, code, codeArgs, responsePayload)
        return finishCode(player, ok, code, codeArgs, responsePayload)
    end
    if GodSystemAttributes.isEnabled() ~= true then return respond(false, "AttributesDisabled") end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local quote, reason = GodSystemAttributes.quote(
            player,
            args and args.perkIndex,
            args and args.mode,
            args and args.value,
            GodSystemAttributes.getXpPerCoin()
        )
        if not quote then
            local code = reason == "maxed" and "AttributeMaxed" or "AttributeInvalid"
            return respond(false, code)
        end
        if not canAfford(player, quote.cost, data) then return respond(false, "CurrencyNotEnough") end
        if not GodSystemServer.beginAttributeOp(player, args) then
            return finishCode(player, false, "AttributeOperationPending", {}, { opId = opId })
        end
        opStarted = true
        local paid, fromBank, fromCash = spendCurrency(player, data, quote.cost)
        if not paid then return respond(false, "CurrencyNotEnough") end

        local before = quote.currentXp
        local xp = player and player.getXp and player:getXp() or nil
        if xp and xp.AddXP then
            pcall(function() xp:AddXP(quote.info.perk, quote.actualXp, false, false, false, false) end)
        end
        local state = GodSystemAttributes.getPlayerState(player, quote.info)
        local appliedXp = state and math.max(0, state.currentXp - before) or 0
        if appliedXp <= 0 then
            local originalSourcesRestored = GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
            return respond(false, originalSourcesRestored and "AttributeApplyFailed" or "AttributeApplyFailedBankRefund")
        end

        local chargedCost = quote.cost
        if appliedXp + 0.0001 < quote.actualXp then
            chargedCost = math.max(1, math.min(quote.cost, math.ceil(appliedXp / GodSystemAttributes.getXpPerCoin())))
            local refund = quote.cost - chargedCost
            local refundCash = math.min(math.max(0, floor(fromCash, 0)), refund)
            GodSystemServer.refundCurrencySources(player, data, refund - refundCash, refundCash)
        end

        local okSync = type(SyncXp) == "function" and pcall(function() SyncXp(player) end)
        if okSync then data.attributeSyncPending = nil else data.attributeSyncPending = true end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + chargedCost
        appendHistory(data, historyEntry("attribute", "AttributePurchased", {
            quote.info.label,
            math.floor(appliedXp),
            chargedCost,
            state.currentLevel,
        }))
        local resultCode = okSync and "AttributePurchased" or "AttributePurchasedSyncPending"
        respond(true, resultCode, {
            quote.info.label,
            math.floor(appliedXp),
            chargedCost,
            state.currentLevel,
        }, { kind = "attribute", perkIndex = quote.info.index, syncPending = not okSync })
    end)
    unguard(player)
    if not ok then
        if opStarted then GodSystemServer.markAttributeOpUnknown(player, args) end
        local outcome = GodSystemServer.getAttributeOpResult(player, args)
        if outcome and outcome.status == "unknown" then
            finishCode(player, false, "AttributeOperationUnknown", {}, { opId = opId })
        else
            errorMessage(player, tostring(err))
        end
    end
end

function Commands.trait(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableTraits") == false then return finish(player, false, "Traits disabled") end
    local data = playerData(player)
    local action = args and args.action
    local traitType = args and args.traitType
    if not traitType or traitType == "" then return finish(player, false, "天赋不存在") end
    if not player.getCharacterTraits then return finish(player, false, "角色天赋接口不可用") end
    local costPoints = traitCostPoints(traitType)
    local cost = action == "remove"
        and (math.abs(math.min(0, costPoints)) * (GodSystemConfig.NegativeTraitRemoveCostPerPoint or 500))
        or (math.max(0, costPoints) * (GodSystemConfig.PositiveTraitCostPerPoint or 800))
    if cost <= 0 then return finish(player, false, "天赋不可修改") end
    if action == "remove" and not playerHasTrait(player, traitType) then return finish(player, false, "角色没有该天赋") end
    if action ~= "remove" and playerHasTrait(player, traitType) then return finish(player, false, "角色已拥有该天赋") end
    local traits = player:getCharacterTraits()
    local token = traitTokenForType(traitType)
    local ok = false
    if action == "remove" then
        if traits.remove then ok = pcall(traits.remove, traits, token) end
    else
        if traits.add then ok = pcall(traits.add, traits, token) end
    end
    if not ok or playerHasTrait(player, traitType) ~= (action ~= "remove") then
        return finish(player, false, "天赋修改失败")
    end
    if not addPoints(player, -cost, data) then
        if action == "remove" then
            if traits.add then pcall(traits.add, traits, token) end
        else
            if traits.remove then pcall(traits.remove, traits, token) end
        end
        return finish(player, false, "系统币不足")
    end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    data.stats.modifiedTraits = (data.stats.modifiedTraits or 0) + 1
    if action ~= "remove" then
        local benefitsOk, benefitsApplied = applyTraitBenefits(player, traitType)
        diagnostics.lastTraitBenefitsOk = benefitsOk == true
        diagnostics.lastTraitBenefitsApplied = benefitsApplied or 0
        diagnostics.lastTraitBenefitsType = tostring(traitType or "")
    end
    appendHistory(data, historyEntry("trait", "Trait", { traitType, cost }))
    return finish(player, true, "天赋修改完成")
end

function Commands.toggleRecycleMode(_, _, player)
    local data = playerData(player)
    data.recycleUnlockMode = data.recycleUnlockMode ~= true
    finishCode(player, true, data.recycleUnlockMode and "RecycleModeUnlock" or "RecycleModeOnly")
end

function Commands.toggleWaistRecycleMode(_, _, player)
    local data = playerData(player)
    data.waistRecycleUnlockMode = data.waistRecycleUnlockMode ~= true
    finishCode(player, true, data.waistRecycleUnlockMode and "WaistRecycleModeUnlock" or "WaistRecycleModeOnly")
end
function Commands.setShopItemHidden(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local variantKey = tostring(args and (args.variantKey or args.fullType) or "")
        local hidden = args and args.hidden == true
        local found, changed, item = GodSystemShopVariants.setHidden(data, variantKey, hidden)
        if not found then return finishCode(player, false, "ShopItemMissing") end
        local code = hidden and "ShopItemHidden" or "ShopItemVisible"
        local label = item and (item.label or item.fullType) or variantKey
        if changed then appendHistory(data, historyEntry("shop", code, { label })) end
        return finishCode(player, true, code, { label })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.setShopItemsHidden(_, _, player, args)
    local txKind = "setShopItemsHidden"
    local txRoot = store()
    local txOwner = userKey(player)
    local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
    if cached then
        local status = tostring(cached.status or "")
        if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
        if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId }) end
        if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args and args.opId }) end
        if status == "done" then
            local payload = type(cached.payload) == "table" and cached.payload or {}
            payload.opId = args and args.opId
            return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
        end
    end
    if not guard(player) then return end
    if not GodSystemTransactionOps.begin(txRoot, txOwner, txKind, args) then
        unguard(player)
        return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId })
    end
    local persisted, persistError = transmitStore()
    if not persisted then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        unguard(player)
        return errorMessage(player, tostring(persistError))
    end
    local ok, err = pcall(function()
        local function complete(okValue, code, codeArgs, payload)
            payload = type(payload) == "table" and payload or {}
            payload.opId = args and args.opId
            GodSystemTransactionOps.remember(txRoot, txOwner, txKind, args, okValue, code, codeArgs, payload)
            return finishCode(player, okValue, code, codeArgs, payload)
        end
        if type(args) ~= "table" or type(args.variantKeys) ~= "table" then
            return complete(false, "ShopItemBatchInvalid")
        end
        if #args.variantKeys > 500 then return complete(false, "ShopItemBatchTooLarge") end
        local keys, seen = {}, {}
        for i = 1, #args.variantKeys do
            local key = tostring(args.variantKeys[i] or "")
            if key ~= "" and not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        if #keys == 0 then return complete(false, "ShopItemBatchInvalid") end
        local targetHidden = args.hidden == true
        local data = playerData(player)
        local changedKeys, skippedKeys = {}, {}
        for i = 1, #keys do
            local found, changed = GodSystemShopVariants.setHidden(data, keys[i], targetHidden)
            if found and changed then changedKeys[#changedKeys + 1] = keys[i]
            else skippedKeys[#skippedKeys + 1] = keys[i] end
        end
        local code = targetHidden and "ShopItemsHidden" or "ShopItemsVisible"
        if #changedKeys > 0 then appendHistory(data, historyEntry("shop", code, { #changedKeys, #skippedKeys })) end
        return complete(true, code, { #changedKeys, #skippedKeys }, {
            requested = #keys,
            changed = #changedKeys,
            skipped = #skippedKeys,
            changedKeys = changedKeys,
            skippedKeys = skippedKeys,
        })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local errorPersisted, errorPersistError = transmitStore()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        return errorMessage(player, tostring(err))
    end
end

function Commands.deleteShopItem(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local variantKey = tostring(args and args.variantKey or "")
        local deleted, item = GodSystemShopVariants.deleteUnlocked(data, variantKey)
        if not deleted or not item then return finishCode(player, false, "ShopItemMissing") end
        local label = item.label or item.fullType or variantKey
        appendHistory(data, historyEntry("shop", "ShopItemDeleted", { label }))
        return finishCode(player, true, "ShopItemDeleted", { label })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.lotteryDraw(_, _, player, args)
    applyAdminConfigStore()
    if GodSystemAdminConfig.isFeatureEnabled("EnableShopLottery") == false then return finish(player, false, "Shop lottery disabled") end
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local mode = tostring(args and args.mode or "all")
        local categoryKey = lotteryNormalizeCategory(mode == "all" and "all" or (args and args.categoryKey))
        if categoryKey == "all" then mode = "all" else mode = "category" end
        local count = math.max(1, floor(args and args.count, 1))
        local maxCount = math.max(1, floor(GodSystemConfig.LotteryCustomMaxCount or 50, 50))
        if count > maxCount then return finish(player, false, "抽奖次数超过上限") end
        local candidates = lotteryCandidates(data, categoryKey)
        if #candidates <= 0 then return finish(player, false, "没有可抽取物品") end
        local unitPrice = lotteryPrice(categoryKey)
        local totalCost = unitPrice * count
        if not canAfford(player, totalCost, data) then return finish(player, false, "系统币不足") end

        local drawn = {}
        for i = 1, count do
            local picked = candidates[randomIndex(#candidates)]
            if not picked or not picked.fullType then return finish(player, false, "没有可抽取物品") end
            drawn[#drawn + 1] = {
                fullType = picked.fullType,
                label = picked.label,
                categoryKey = picked.categoryKey,
                count = 1,
            }
        end

        local addedAll = {}
        for i = 1, #drawn do
            local okGive, added = giveItem(player, drawn[i].fullType, 1)
            if not okGive then
                local inv = player:getInventory()
                for j = 1, #addedAll do removeItemFromContainer(inv, addedAll[j]) end
                return finish(player, false, "发放物品失败，不扣币")
            end
            for j = 1, #(added or {}) do addedAll[#addedAll + 1] = added[j] end
        end

        if not addPoints(player, -totalCost, data) then
            local inv = player:getInventory()
            for j = 1, #addedAll do removeItemFromContainer(inv, addedAll[j]) end
            return finish(player, false, "系统币不足")
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + totalCost
        data.stats.lotteryDraws = (data.stats.lotteryDraws or 0) + count
        appendHistory(data, historyEntry("shop", "LotteryDraw", { count, totalCost }))
        finish(player, true, "抽奖完成", {
            kind = "lotteryDraw",
            mode = mode,
            categoryKey = categoryKey,
            count = count,
            unitPrice = unitPrice,
            totalCost = totalCost,
            items = drawn,
            groupedItems = groupLotteryItems(drawn),
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.shopLottery(_, _, player, args)
    args = args or {}
    args.mode = "category"
    args.count = 1
    return Commands.lotteryDraw(nil, nil, player, args)
end

local function sendStateSoon(player, data)
    data = data or playerData(player)
    local nowHour = nowHours()
    if nowHour - (data.lastServerPushHour or -999) < 0.02 then return end
    data.lastServerPushHour = nowHour
    sendState(player)
end

local function hasWaistRecycleItems(player, data)
    local inv = autoRecyclerInventory(data, player)
    if not inv or not inv.getItems then return false end
    local items = inv:getItems()
    if not items or not items.size then return false end
    for i = 0, items:size() - 1 do
        if canRecycleItem(items:get(i), true) then return true end
    end
    return false
end

local function updateKillRewards(player)
    if player and player.getZombieKills then
        Commands.syncKills(nil, nil, player, { clientKills = player:getZombieKills() })
    end
end

local function updateTaskTimeouts(player)
    local data = playerData(player)
    local changed = false
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" and task.deadline and nowHours() > task.deadline and taskProgress(data, player, task) < (task.target or 1) then
            failTask(player, data, task, "TaskFailed")
            changed = true
        end
    end
    if changed then sendStateSoon(player, data) end
end

local function updateWaistAutoRecycle(player)
    local data = playerData(player)
    if data.waistAutoRecycleUnlocked ~= true or data.waistAutoRecycleEnabled ~= true then return end
    local nowHour = math.floor(nowHours())
    local interval = math.max(1, floor(GodSystemConfig.WaistAutoRecycleIntervalHours, 1))
    if nowHour - (data.lastWaistAutoRecycleHour or nowHour) < interval then return end
    data.lastWaistAutoRecycleHour = nowHour
    if not hasWaistRecycleItems(player, data) then return end
    if data.waistRecycleUnlockMode == true then
        Commands.recycleWaistAndUnlock(nil, nil, player, { selected = nil })
    else
        Commands.recycleWaist(nil, nil, player, { selected = nil })
    end
end

local function updateHomeSafeZone(player)
    local data = playerData(player)
    local home = data.homeSystem or {}
    local safe = home.safeZone or {}
    if not home.home or safe.enabled ~= true or floor(safe.level, 0) <= 0 then return end
    local row = safeZoneLevelConfig(floor(safe.level, 0))
    if not row then return end
    local interval = math.max(0.05, n(GodSystemConfig.HomeSafeZoneScanIntervalHours, 0.5))
    if nowHours() - (safe.lastScanHours or 0) < interval then return end
    local removed = clearHomeSafeZone(player, data, false)
    if removed and removed > 0 then sendStateSoon(player, data) end
end

local function settleTerminalFreshnessService(player, data)
    local terminal = findAutoRecycler(data, player)
    local report = GodSystemTerminalFood.settleOnline(data, terminal, nowHours())
    if report.restored and report.restored > 0 and terminal then
        GodSystemServer.syncTerminalApplyReport(terminal, report)
    end
    if report.expired == true then
        notifyCode(player, "TerminalFreshnessExpired")
    end
    if (report.hoursConsumed or 0) > 0 or report.expired == true then
        sendStateSoon(player, data)
    end
    return report
end

local FRESHNESS_SESSION_GAP_HOURS = 1

local function observeTerminalFreshnessSession(state, nowHour)
    local previousHour = tonumber(state.terminalFreshnessLastObservedHour)
    state.terminalFreshnessLastObservedHour = nowHour
    if previousHour == nil or nowHour < previousHour or nowHour - previousHour > FRESHNESS_SESSION_GAP_HOURS then
        state.terminalFreshnessNeedsSessionReset = true
    end
end

local playerUpdateTicks = {}
local function onPlayerUpdate(player)
    if not player then return end
    local key = userKey(player)
    local state = playerUpdateTicks[key]
    if not state or state.player ~= player then
        state = { player = player, ticks = 0 }
        playerUpdateTicks[key] = state
    end
    state.ticks = state.ticks + 1
    observeTerminalFreshnessSession(state, nowHours())
    if state.ticks % 60 ~= 0 then return end
    local data = playerData(player)
    generateDailyTasks(data, false)
    updateHomeSafeZone(player)
    if state.terminalFreshnessNeedsSessionReset then
        -- Never charge persisted elapsed time before this active player session is observed.
        GodSystemTerminalFood.beginOnlineSession(data, nowHours())
        state.terminalFreshnessNeedsSessionReset = false
    else
        settleTerminalFreshnessService(player, data)
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= MODULE then return end
    if not player then return end
    diagnostics.handledCommands = (diagnostics.handledCommands or 0) + 1
    diagnostics.lastCommand = tostring(command or "")
    local fn = Commands[command]
    if fn then
        local ok, err = pcall(fn, module, command, player, args or {})
        if not ok then
            diagnostics.failedCommands = (diagnostics.failedCommands or 0) + 1
            diagnostics.lastError = tostring(err)
            print("[GodSystem] command '" .. tostring(command) .. "' failed: " .. tostring(err))
            errorMessage(player, tostring(err))
            sendState(player)
        end
    else
        diagnostics.failedCommands = (diagnostics.failedCommands or 0) + 1
        errorCode(player, "UnknownCommand", { tostring(command or "") })
        sendState(player)
    end
end)

function GodSystemServer.storageControllerCharge(player, cost)
    local data = playerData(player)
    local paid, fromBank, fromCash = spendCurrency(player, data, cost)
    if not paid then return false, nil end
    return true, {
        data = data,
        fromBank = fromBank,
        fromCash = fromCash,
    }
end

function GodSystemServer.storageControllerRefund(player, receipt)
    receipt = type(receipt) == "table" and receipt or {}
    return GodSystemServer.refundCurrencySources(
        player,
        receipt.data or playerData(player),
        receipt.fromBank or 0,
        receipt.fromCash or 0
    )
end

function GodSystemServer.storageControllerCommit(player, cost, recovered, receipt)
    local data = type(receipt) == "table" and receipt.data or playerData(player)
    cost = math.max(0, floor(cost, 0))
    if cost > 0 then
        data.stats = data.stats or {}
        data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    end
    appendHistory(data, historyEntry("storage", recovered and "StorageControllerRecovered" or "StorageControllerClaimed", { cost }))
    sendState(player)
end

require "GodSystem_StorageServer"

return Commands
