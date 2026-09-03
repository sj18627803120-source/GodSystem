_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Services"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Services then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Services = true
    setfenv(1, runtimeEnvironment)

function medicalBody(player)
    if not player then return nil end
    return safeCall(player, "getBodyDamage", nil)
end

function medicalBool(object, methods)
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

function medicalNumber(object, methods, fallback)
    for i = 1, #(methods or {}) do
        local value = tonumber(safeCall(object, methods[i], nil))
        if value ~= nil then return value end
    end
    return fallback
end

function medicalList(list)
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

function medicalBodyParts(body)
    return medicalList(safeCall(body, "getBodyParts", nil))
end

function medicalCaptureInfection(body)
    return {
        infected = medicalBool(body, { "IsInfected", "isInfected" }),
        fakeInfected = medicalBool(body, { "IsFakeInfected", "isFakeInfected" }),
        infectionTime = medicalNumber(body, { "getInfectionTime" }, nil),
        mortalityDuration = medicalNumber(body, { "getInfectionMortalityDuration" }, nil),
        infectionLevel = medicalNumber(body, { "getInfectionLevel" }, nil),
    }
end

function medicalRestoreInfection(body, snapshot)
    if not body or not snapshot or snapshot.infected ~= true then return end
    safeCall(body, "setInfected", nil, true)
    safeCall(body, "setIsFakeInfected", nil, snapshot.fakeInfected == true)
    if snapshot.infectionTime ~= nil then safeCall(body, "setInfectionTime", nil, snapshot.infectionTime) end
    if snapshot.mortalityDuration ~= nil then safeCall(body, "setInfectionMortalityDuration", nil, snapshot.mortalityDuration) end
    if snapshot.infectionLevel ~= nil then safeCall(body, "setInfectionLevel", nil, snapshot.infectionLevel) end
end

function medicalIsInfected(body)
    if not body then return false end
    if medicalBool(body, { "IsInfected", "isInfected" }) then return true end
    local level = medicalNumber(body, { "getInfectionLevel" }, 0) or 0
    if level > 0 then return true end
    local time = medicalNumber(body, { "getInfectionTime" }, -1) or -1
    return time > 0
end

function medicalHasInjury(body)
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

function medicalClearBodyPartInfection(part)
    if not part then return end
    safeCall(part, "SetInfected", nil, false)
    safeCall(part, "SetFakeInfected", nil, false)
    safeCall(part, "setInfectedWound", nil, false)
    safeCall(part, "setWoundInfectionLevel", nil, -1)
end

function medicalClearInfection(body, player)
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

function medicalHealPart(part)
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
end

function medicalHealInjuries(player, body)
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

function medicalServiceInfo(action)
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

function medicalApply(player, action, body)
    if action == "checkInfection" then
        return true, medicalIsInfected(body) and "infected" or "clean"
    elseif action == "healInjuries" then
        return medicalHealInjuries(player, body), "healed"
    elseif action == "cureInfection" then
        return medicalClearInfection(body, player), "cured"
    end
    return false, "unknown"
end

function medicalNotifyMessage(action, result)
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

function maintenanceExpectedType(action)
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

function rollbackMaintenanceTarget(target, snapshot)
    return GodSystemMaintenance.rollback(target, snapshot)
end

function syncMaintenanceTarget(player, target)
    if not target then return end
    if sendItemStats then pcall(sendItemStats, target) end
    if syncItemFields and player then pcall(syncItemFields, player, target) end
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
            syncMaintenanceTarget(player, target)
            return finishCode(player, false, "MaintenanceFailed")
        end

        if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, consumable) end
        if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
        syncMaintenanceTarget(player, target)
        local fullType = tostring(target:getFullType())
        local state = result and result.after and GodSystemMaintenance.snapshotPayload(result.after) or nil
        return finishCode(player, true, code, {
            fullType,
            result and result.after and result.after.condition or 0,
            result and result.after and result.after.conditionMax or 0,
        }, {
            kind = "maintenanceItem",
            action = action,
            targetItemId = targetItemId,
            state = state,
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
        if t == "carryCapacity" then
            local currentLevel = GodSystemCarryCapacity.getLevel(data, player)
            local nextLevel = currentLevel + 1
            local cost = GodSystemCarryCapacity.getNextCost(currentLevel)
            if not cost then return complete(false, "CarryCapacityCostOverflow") end
            local applied, reason = GodSystemCarryCapacity.restore(player, nextLevel)
            if not applied then return complete(false, "CarryCapacityApplyFailed", { tostring(reason or "unknown") }) end
            if not addPoints(player, -cost, data) then
                GodSystemCarryCapacity.restore(player, currentLevel)
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
        local errorPersisted, errorPersistError = storeCheckpoint()
        if not errorPersisted then return errorMessage(player, tostring(errorPersistError)) end
        return errorMessage(player, tostring(err))
    end
end

function Commands.refreshCarryCapacity(_, _, player)
    if not guard(player) then return end
    local ok, err = pcall(function()
        local data = playerData(player)
        local level = GodSystemCarryCapacity.getLevel(data, player)
        local applied, reason = GodSystemCarryCapacity.restore(player, level)
        if not applied then
            return finishCode(player, false, "CarryCapacityRestoreFailed", { tostring(reason or "unknown") })
        end
        finishCode(player, true, "CarryCapacityRestored", {
            level,
            GodSystemCarryCapacity.getBonus(level) or 0,
        }, {
            kind = "carryCapacityRestore",
            level = level,
        })
    end)
    unguard(player)
    if not ok then errorMessage(player, tostring(err)) end
end

function Commands.task(_, _, player, args)
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTasks") == false then return finish(player, false, "Tasks disabled") end
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
            if autoTask and autoTask.status == "active" and not isTurnInTask(autoTask) then
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
    elseif action == "submitTurnIn" then
        local claimed, code = submitTurnInTaskForPlayer(player, data, task, args)
        return finishCode(player, claimed, code)
    elseif action == "abandon" then
        if task.status ~= "active" then return finish(player, false, "任务状态不正确") end
        failTask(player, data, task, "TaskAbandoned")
        return finish(player, true, "任务已放弃")
    end
    finish(player, false, "未知任务操作")
end

function Commands.refreshTasks(_, _, player)
    applyRuntimeStores()
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTasks") == false then return finish(player, false, "Tasks disabled") end
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
end
