_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Commerce"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Commerce then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Commerce = true
    setfenv(1, runtimeEnvironment)

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
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableBank") == false then return finish(player, false, "Bank disabled") end
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
    storeCheckpoint()
    sendState(player)
end

function Commands.buyShop(_, _, player, args)
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableShop") == false then return finish(player, false, "Shop disabled") end
    local txKind = "buyShop"
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
    local persisted, persistError = storeCheckpoint()
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
        local data = playerData(player)
        local row, lookupReason = shopById(data, args and args.id)
        if not row then
            if lookupReason == "hidden" then return complete(false, "ShopItemHiddenStale") end
            return complete(false, "ShopItemNotFound")
        end
        local quantity = math.max(1, floor(args and args.quantity, 1))
        local price = shopUnitPrice(row) * quantity
        if not canAfford(player, price, data) then return complete(false, "CurrencyNotEnough") end
        local grant = {}
        for i = 1, #(row.items or {}) do
            if not itemExists(row.items[i].fullType) then return complete(false, "ShopItemNotFound", { row.items[i].fullType }) end
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
                return complete(false, "ItemGrantFailed")
            end
            for j = 1, #added do addedAll[#addedAll + 1] = added[j] end
        end
        if not addPoints(player, -price, data) then
            local inv = player:getInventory()
            for j = 1, #addedAll do removeItemFromContainer(inv, addedAll[j]) end
            return complete(false, "CurrencyNotEnough")
        end
        data.stats.spentPoints = (data.stats.spentPoints or 0) + price
        data.stats.boughtItems = (data.stats.boughtItems or 0) + quantity
        appendHistory(data, shopHistoryEntry("BuyShop", row, { quantity, price }))
        if GodSystemLottery and GodSystemLottery.isTicketShopId and GodSystemLottery.isTicketShopId(row.id)
            and _G.GodSystemServerLottery and _G.GodSystemServerLottery.ensureStarted then
            _G.GodSystemServerLottery.ensureStarted()
        end
        return complete(true, "ShopBuySuccess", { quantity, price }, { quantity = quantity, price = price })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local errorPersisted, errorPersistError = storeCheckpoint()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        errorMessage(player, tostring(err))
    end
end

function restoreRecycleSelection(player, removed)
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
        if ok and row.equipment then
            GodSystemManualRecycle.restoreEquipped(player, row.item, row.equipment, GodSystemManualRecycle.defaultBridge())
        end
    end
    markInventoryDirty(player, inventory)
    return restored
end

function recycleSelectedInternal(player, args)
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
    local persisted, persistError = storeCheckpoint()
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
        local listingSkipped = 0
        for i = 1, #(args and args.itemIds or {}) do
            local id = tostring(args.itemIds[i] or "")
            if id ~= "" and not seen[id] then
                seen[id] = true
                local item, container = inventoryItemById(player, id)
                if not item or not container then return complete(false, "RecycleSelectionChanged") end
                local allowed = canContextRecycleItem(item)
                local fullType = item:getFullType()
                local eligible = allowed == true
                local listable = true
                if eligible and mode ~= "recycle" then
                    listable = canContextListItem(data, item) == true
                    if not listable and mode == "listOnly" then eligible = false end
                    if not listable and mode == "recycleAndList" then listingSkipped = listingSkipped + 1 end
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
                        types[groupKey] = { item = item, fullType = fullType, raw = 0, count = 0, listable = listable }
                        typeOrder[#typeOrder + 1] = groupKey
                    end
                    types[groupKey].raw = types[groupKey].raw + recycleValue(item, true)
                    types[groupKey].count = types[groupKey].count + 1
                end
            end
        end
        skipped = math.max(skipped, listingSkipped)
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
        local removed = {}
        local equipmentBridge = GodSystemManualRecycle.defaultBridge()
        for i = 1, #selected do
            local row = selected[i]
            local item = row.item
            local equipment = GodSystemManualRecycle.captureEquipped(player, item, equipmentBridge)
            if not GodSystemManualRecycle.detachEquipped(player, item, equipmentBridge) then
                GodSystemManualRecycle.restoreEquipped(player, item, equipment, equipmentBridge)
                restoreRecycleSelection(player, removed)
                return complete(false, "RecycleSelectionFailed")
            end
            local removedOk = removeItemFromContainer(row.container, item)
            if not removedOk then
                local current = {
                    item = item,
                    equipment = equipment,
                }
                if GodSystemServerContainerContainsItem(row.container, item) then
                    GodSystemManualRecycle.restoreEquipped(player, item, equipment, equipmentBridge)
                else
                    removed[#removed + 1] = current
                end
                restoreRecycleSelection(player, removed)
                return complete(false, "RecycleSelectionFailed")
            end
            removed[#removed + 1] = {
                item = item,
                equipment = equipment,
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
                if row.listable then
                    unlockAutoShopItem(data, row.fullType, row.item:getDisplayName(), itemSellPrice(row.fullType, row.item), row.item)
                end
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
        local persisted, persistError = storeCheckpoint()
        if not persisted then
            GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
            return errorMessage(player, tostring(persistError))
        end
        errorMessage(player, tostring(err))
    end
end

function Commands.recycle(_, _, player, args)
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableRecycle") == false then return finish(player, false, "Recycle disabled") end
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
    applyRuntimeStores()
    local txKind = "listOnlyAutoShop"
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
    local persisted, persistError = storeCheckpoint()
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
        local data = playerData(player)
        local fullType = tostring(args and args.fullType or "")
        local itemId = tostring(args and args.itemId or "")
        if fullType == "" or itemId == "" then return complete(false, "RecycleSelectionChanged") end
        if not isAutoShopListOnlyAllowed(fullType) then return complete(false, "ListOnlyDisabled") end
        local item, container = inventoryItemById(player, itemId)
        if not item or not container or item:getFullType() ~= fullType then
            return complete(false, "RecycleSelectionChanged")
        end
        local listable, reason = canContextListItem(data, item)
        if not listable then
            if reason == "configuredListed" then return complete(true, "ShopConfiguredAlreadyListed") end
            if reason == "hiddenListed" then return complete(true, "ShopHiddenAlreadyListed") end
            if reason == "alreadyListed" then return complete(true, "ListOnlyAlreadyUnlocked") end
            return complete(false, "ListOnlyDisabled")
        end
        local label = item and item.getDisplayName and item:getDisplayName() or fullType
        local sellValue = itemSellPrice(fullType, item)
        local cost, buyPrice = autoShopListOnlyCost(fullType, sellValue)
        local paid, fromBank, fromCash = spendCurrency(player, data, cost)
        if not paid then return complete(false, "ListOnlyInsufficient") end
        local unlocked = unlockAutoShopItem(data, fullType, label, sellValue, item)
        if not unlocked then
            GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
            return complete(false, "RecycleSelectionChanged")
        end
        appendHistory(data, historyEntry("shop", "ListOnlyAutoShop", { fullType, cost, buyPrice }))
        return complete(true, "ListOnlySuccess", { fullType, cost, buyPrice }, { cost = cost, buyPrice = buyPrice })
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        local errorPersisted, errorPersistError = storeCheckpoint()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        errorMessage(player, tostring(err))
    end
end

end
