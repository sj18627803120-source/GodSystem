_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_HomeGrowth"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_HomeGrowth then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_HomeGrowth = true
    setfenv(1, runtimeEnvironment)

function currentPosition(player)
    return { x = n(player:getX()), y = n(player:getY()), z = n(player:getZ()) }
end

function gridSquareAt(pos)
    local cell = getCell and getCell() or nil
    if not cell or not pos then return nil end
    local ok, square = GodSystemB42JavaCalls.try(cell, "getGridSquare", math.floor(n(pos.x)), math.floor(n(pos.y)), math.floor(n(pos.z)))
    if ok then return square end
    return nil
end

function squareSafe(square)
    if not square then return nil end
    if square.isSolid and square:isSolid() then return false end
    if square.isSolidTrans and square:isSolidTrans() then return false end
    if square.TreatAsSolidFloor then
        local ok, hasFloor = GodSystemB42JavaCalls.try(square, "TreatAsSolidFloor")
        if ok and hasFloor == false then return false end
    end
    return true
end

function safeTeleportPosition(pos)
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

function safeZoneLevelConfig(level)
    local rows = GodSystemConfig.HomeSafeZoneLevels or {}
    for i = 1, #rows do
        if (rows[i].level or i) == level then return rows[i] end
    end
    return rows[level]
end

function collectSafeZoneZombies(center, radius, scanStart, scanBudget)
    local result = {}
    if not center or not radius or radius <= 0 or not getCell then return result, 0, 0 end
    local cell = getCell()
    if not cell or not cell.getZombieList then return result, 0, 0 end
    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not okList or not zombies or not zombies.size or not zombies.get then return result, 0, 0 end
    local okSize, size = pcall(function() return zombies:size() end)
    if not okSize or not size or size <= 0 then return result, 0, 0 end
    local radiusSq = radius * radius
    local budget = math.max(1, floor(scanBudget, 256))
    local index = math.max(0, floor(scanStart, 0))
    if index >= size then index = 0 end
    local inspected = 0
    while inspected < budget and inspected < size do
        local okZombie, zombie = pcall(function() return zombies:get(index) end)
        index = index + 1
        if index >= size then index = 0 end
        inspected = inspected + 1
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
    return result, index, inspected
end

function removeZombieFromWorld(zombie)
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

function clearHomeSafeZone(player, data, manual)
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
    local scanBudget = math.max(1, floor(GodSystemRuntimeConfig.get("HomeSafeZoneScanBudget", 256), 256))
    local clearLimit = math.max(1, floor(GodSystemRuntimeConfig.get("HomeSafeZoneClearLimit", 64), 64))
    local targets, nextZombieScanIndex = collectSafeZoneZombies(
        home.home,
        row.radius or 0,
        safe.nextZombieScanIndex,
        scanBudget
    )
    safe.nextZombieScanIndex = nextZombieScanIndex
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
    for i = 1, math.min(#targets, clearLimit) do
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

function spendHomeCostCode(player, data, cost, code, args)
    cost = math.max(0, floor(cost, 0))
    if cost > 0 and not addPoints(player, -cost, data) then return false end
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    local historyArgs = args or {}
    historyArgs[#historyArgs + 1] = cost
    appendHistory(data, historyEntry("home", code, historyArgs))
    return true
end

function sendTeleportRequest(player, data, action, index, safe, history, historyArgs)
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
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTeleport") == false then return finish(player, false, "Teleport disabled") end
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
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTeleport") == false then return finish(player, false, "Teleport disabled") end
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
    applyRuntimeStores()
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
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTraits") == false then return finish(player, false, "Traits disabled") end
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
        if traits.remove then ok = GodSystemB42JavaCalls.try(traits, "remove", token) end
    else
        if traits.add then ok = GodSystemB42JavaCalls.try(traits, "add", token) end
    end
    if not ok or playerHasTrait(player, traitType) ~= (action ~= "remove") then
        return finish(player, false, "天赋修改失败")
    end
    if not addPoints(player, -cost, data) then
        if action == "remove" then
            if traits.add then GodSystemB42JavaCalls.try(traits, "add", token) end
        else
            if traits.remove then GodSystemB42JavaCalls.try(traits, "remove", token) end
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

function Commands.setShopItemHidden(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local variantKey = tostring(args and (args.variantKey or args.fullType) or "")
        local hidden = args and args.hidden == true
        local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
        local fullType = stored and stored.fullType or variantKey
        if GodSystemItemConfig.getShopVariantMode(variantKey, fullType) == "forced" then
            return finishCode(player, false, "ShopItemForced")
        end
        local found, changed, item = GodSystemShopVariants.setHidden(data, variantKey, hidden)
        if not found then return finishCode(player, false, "ShopItemMissing") end
        local code = hidden and "ShopItemHidden" or "ShopItemVisible"
        local itemFullType = item and item.fullType or fullType
        if changed then appendHistory(data, historyEntry("shop", code, { itemFullType })) end
        return finishCode(player, true, code, { itemFullType })
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
            local stored = data.unlockedShopItems and data.unlockedShopItems[keys[i]] or nil
            local fullType = stored and stored.fullType or keys[i]
            local forced = GodSystemItemConfig.getShopVariantMode(keys[i], fullType) == "forced"
            local found, changed = false, false
            if not forced then found, changed = GodSystemShopVariants.setHidden(data, keys[i], targetHidden) end
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
        local errorPersisted, errorPersistError = storeCheckpoint()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        return errorMessage(player, tostring(err))
    end
end

function Commands.deleteShopItem(_, _, player, args)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local variantKey = tostring(args and args.variantKey or "")
        local stored = data.unlockedShopItems and data.unlockedShopItems[variantKey] or nil
        local fullType = stored and stored.fullType or variantKey
        if GodSystemItemConfig.getShopVariantMode(variantKey, fullType) == "forced" then
            return finishCode(player, false, "ShopItemForced")
        end
        local deleted, item = GodSystemShopVariants.deleteUnlocked(data, variantKey)
        if not deleted or not item then return finishCode(player, false, "ShopItemMissing") end
        local itemFullType = item.fullType or fullType
        appendHistory(data, historyEntry("shop", "ShopItemDeleted", { itemFullType }))
        return finishCode(player, true, "ShopItemDeleted", { itemFullType })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end
end
