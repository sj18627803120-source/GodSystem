_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Lottery"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Lottery then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Lottery = true
    setfenv(1, runtimeEnvironment)

    local Lottery = GodSystemLottery
    local Cache = GodSystemLotteryItemCache
    local ServerLottery = _G.GodSystemServerLottery or {}
    _G.GodSystemServerLottery = ServerLottery
    ServerLottery.state = ServerLottery.state or { installed = true }
    Cache.install("server")

    local function preparedReward(fullType)
        if not GodSystemShopVariants or not GodSystemShopVariants.createItem then return nil end
        local item = GodSystemShopVariants.createItem(fullType, nil)
        return item
    end

    local function addPreparedReward(player, item)
        local inventory = player and player.getInventory and player:getInventory() or nil
        if not inventory or not item then return false end
        local ok, added = pcall(function() return inventory:AddItem(item) end)
        if not ok or not added then return false end
        if sendAddItemToContainer then
            local synced = pcall(sendAddItemToContainer, inventory, item)
            if not synced then
                removeItemFromContainer(inventory, item)
                return false
            end
        end
        markInventoryDirty(player, inventory)
        return true
    end

    local function restoreTicket(player, fullType)
        local ok, restored = giveItem(player, fullType, 1)
        return ok == true and #(restored or {}) == 1
    end

    local function sendLotteryResult(player, payload)
        sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.LotteryResult) or "lotteryResult", payload)
    end

    local function replayCachedLottery(player, cached, args)
        local payload = type(cached.payload) == "table" and cached.payload or {}
        payload.opId = args and args.opId
        if payload.lottery == true then sendLotteryResult(player, payload) end
        return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
    end

    local function prepareRewards(drawCount)
        local rewards, types = {}, {}
        for draw = 1, drawCount do
            local prepared, fullType = nil, nil
            for _ = 1, 8 do
                fullType = Lottery and Lottery.drawCandidate and Lottery.drawCandidate() or nil
                if not fullType then break end
                prepared = preparedReward(fullType)
                if prepared then break end
                if Lottery.evict then Lottery.evict(fullType) end
                prepared, fullType = nil, nil
            end
            if not prepared or not fullType then return nil, nil end
            rewards[#rewards + 1] = prepared
            types[#types + 1] = fullType
        end
        return rewards, types
    end

    local function rollbackRewards(player, rewards)
        local inventory = player and player.getInventory and player:getInventory() or nil
        for index = #rewards, 1, -1 do
            if inventory then removeItemFromContainer(inventory, rewards[index]) end
        end
    end

    function ServerLottery.status()
        local status = Cache and Cache.status and Cache.status() or {}
        status.complete = status.complete == true
        status.building = status.building == true
        return status
    end

    function ServerLottery.ensureStarted()
        if not Cache then return false, "unavailable" end
        local ready, status = Cache.ensureStarted("server")
        return ready, status
    end

    function Commands.useLotteryTicket(_, _, player, args)
        applyRuntimeStores()
        local txKind = "useLotteryTicket"
        local txRoot = store()
        local txOwner = userKey(player)
        local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
        if cached then
            local status = tostring(cached.status or "")
            if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
            if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args and args.opId }) end
            if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args and args.opId }) end
            if status == "done" then return replayCachedLottery(player, cached, args) end
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
                if payload.lottery == true then sendLotteryResult(player, payload) end
                return finishCode(player, okValue, code, codeArgs, payload)
            end

            local item, container = inventoryItemById(player, args and args.itemId)
            local ticket = item and Lottery and Lottery.ticketForFullType(item:getFullType()) or nil
            if not item or not container or not ticket then return complete(false, "LotteryTicketInvalid") end

            local ready, state = ServerLottery.ensureStarted()
            if not ready then
                local status = ServerLottery.status()
                return complete(false, state == "unavailable" and "LotteryPoolUnavailable" or "LotteryPoolPreparing", {
                    status.processed or 0, status.total or 0,
                })
            end

            local drawCount = math.max(1, math.min(10, math.floor(tonumber(ticket.draws) or 1)))
            local rewards, rewardTypes = prepareRewards(drawCount)
            if not rewards or #rewards ~= drawCount then return complete(false, "LotteryPoolEmpty") end
            if not removeItemFromContainer(container, item) then return complete(false, "LotteryTicketInvalid") end

            local added = {}
            for index = 1, #rewards do
                if not addPreparedReward(player, rewards[index]) then
                    rollbackRewards(player, added)
                    if not restoreTicket(player, ticket.fullType) then return complete(false, "LotteryRestoreFailed") end
                    return complete(false, "LotteryRewardUnavailable")
                end
                added[#added + 1] = rewards[index]
            end

            return complete(true, "LotteryDrawSuccess", {}, {
                lottery = true,
                ticketFullType = ticket.fullType,
                ticketKind = ticket.kind,
                drawCount = drawCount,
                rewards = rewardTypes,
                rewardFullType = rewardTypes[1],
            })
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

return _G.GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Lottery"]
