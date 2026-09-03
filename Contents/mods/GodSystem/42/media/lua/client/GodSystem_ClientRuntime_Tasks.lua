_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Tasks"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Tasks then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Tasks = true
    setfenv(1, runtimeEnvironment)

local TurnInCandidateLimit = function(task)
    return math.max(1, math.floor(tonumber(task and task.target) or 1))
end

-- Rendering may run every frame. Cache the single recursive inventory walk used
-- by task display, while transactions continue to use getTaskProgress() exactly.
local TaskDisplayProgressCacheTtlMs = 750
local taskDisplayProgressCache = { refreshedAtMs = -1, itemCounts = {} }

local function taskDisplayNowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return math.floor(tonumber(value)) end
    end
    return math.floor((os.time and os.time() or 0) * 1000)
end

local function isTurnInTask(task)
    return task and (task.kind == "turnInItem" or task.kind == "turnInAnyItem")
end

local function turnInAllowedTypes(task)
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

function GodSystemApp.services.runtime.generateTaskFromTemplate(template)
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
        rewardPoints = GodSystemRuntimeConfig.applyTaskReward(template.rewardPoints or 0),
        rewardItems = gsCopyItems(template.rewardItems),
        penaltyPoints = GodSystemRuntimeConfig.applyTaskPenalty(template.penaltyPoints or 0),
        description = template.description,
        status = "open",
        createdAt = now,
        createdDay = gsCurrentDay(),
    }
end

function GodSystemApp.services.runtime.getActiveTaskCount()
    local data = GodSystemApp.services.runtime.getData()
    local count = 0
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "active" then
            count = count + 1
        end
    end
    return count
end

function GodSystemApp.services.runtime.isTaskTemplateAvailable(template)
    if not template then
        return false
    end
    local blacklist = GodSystemConfig.TaskItemBlacklist or {}
    if template.kind == "turnInItem" then
        return not blacklist[template.item] and GodSystemApp.services.runtime.itemExists(template.item)
    end
    if template.kind == "turnInAnyItem" then
        local items = template.items or {}
        for i = 1, #items do
            if not blacklist[items[i]] and GodSystemApp.services.runtime.itemExists(items[i]) then
                return true
            end
        end
        return false
    end
    return true
end

function GodSystemApp.services.runtime.getAvailableTaskTemplates()
    local result = {}
    local templates = GodSystemConfig.TaskTemplates or {}
    for i = 1, #templates do
        if GodSystemApp.services.runtime.isTaskTemplateAvailable(templates[i]) then
            table.insert(result, templates[i])
        end
    end
    if #result == 0 then
        return templates
    end
    return result
end

function GodSystemApp.services.runtime.generateDailyTasks(force)
    local data = GodSystemApp.services.runtime.getData()
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
            gsAppendHistory(data, { kind = "task", text = GodSystemApp.services.runtime.getTaskStatusText(task) .. ": " .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)) })
        end
    end

    local templates = GodSystemApp.services.runtime.getAvailableTaskTemplates()
    local used = {}
    local count = math.min(GodSystemApp.services.runtime.getDailyTaskCount(), #templates)
    for _ = 1, count do
        local index = gsRandomIndex(#templates)
        local guard = 0
        while used[index] and guard < 30 do
            index = gsRandomIndex(#templates)
            guard = guard + 1
        end
        used[index] = true
        table.insert(kept, GodSystemApp.services.runtime.generateTaskFromTemplate(templates[index]))
    end

    data.lastGeneratedDay = day
    data.tasks = kept
    gsAppendHistory(data, { kind = "system", text = GodSystemApp.services.runtime.text("History_DailyTasks", "Daily tasks published x") .. tostring(count) })
    GodSystemApp.services.runtime.save()
end

function GodSystemApp.services.runtime.refreshOpenTasks()
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTasks") == false then
        GodSystemApp.services.runtime.notify("Tasks disabled")
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local cost = GodSystemConfig.RefreshTaskCost or 0
    if not GodSystemApp.services.runtime.canAfford(cost) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CannotRefresh", "Not enough currency to refresh tasks"))
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
        if activeCount >= GodSystemApp.services.runtime.getMaxActiveTasks() then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CannotRefreshActiveFull", "Active task slots are full. Complete or abandon a task first."))
            return false
        end
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_NoOpenTask", "No open task to refresh"))
        return false
    end

    if not GodSystemApp.services.runtime.addPoints(-cost) then
        return false
    end
    local templates = GodSystemApp.services.runtime.getAvailableTaskTemplates()
    for i = 1, #(data.tasks or {}) do
        if data.tasks[i].status == "open" then
            data.tasks[i] = GodSystemApp.services.runtime.generateTaskFromTemplate(templates[gsRandomIndex(#templates)])
        end
    end
    gsAppendHistory(data, { kind = "task", text = GodSystemApp.services.runtime.text("History_RefreshTasks", "Refreshed open tasks -") .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RefreshTasks", "Refreshed open tasks -") .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"))
    return true
end

function GodSystemApp.services.runtime.acceptTask(task)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTasks") == false then
        GodSystemApp.services.runtime.notify("Tasks disabled")
        return false
    end
    if not task or task.status ~= "open" then
        return false
    end
    if GodSystemApp.services.runtime.getActiveTaskCount() >= GodSystemApp.services.runtime.getMaxActiveTasks() then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ActiveTaskLimit", "Active task limit reached"))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
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
    gsAppendHistory(data, { kind = "task", text = GodSystemApp.services.runtime.text("History_AcceptTask", "Accepted task: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_AcceptTask", "Accepted task: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)))
    return true
end

function GodSystemApp.services.runtime.getInventoryItemCount(fullType)
    local player = gsPlayer()
    if not player then
        return 0
    end
    return #gsFindInventoryItems(fullType, false, false)
end

function GodSystemApp.services.runtime.getAnyInventoryItemCount(fullTypes)
    local total = 0
    if not fullTypes then
        return total
    end
    for i = 1, #fullTypes do
        total = total + GodSystemApp.services.runtime.getInventoryItemCount(fullTypes[i])
    end
    return total
end

function GodSystemApp.services.runtime.isTurnInTask(task)
    return isTurnInTask(task)
end

function GodSystemApp.services.runtime.getTurnInCandidates(task)
    if not isTurnInTask(task) then return {} end
    local allowed = turnInAllowedTypes(task)
    local perTypeLimit = TurnInCandidateLimit(task)
    local perTypeCount = {}
    local candidates = {}
    local found = gsFindInventoryItems(nil, false, false)
    for i = 1, #found do
        local entry = found[i]
        local item = entry and entry.item or nil
        local fullType = item and item.getFullType and tostring(item:getFullType() or "") or ""
        local itemId = item and item.getID and tostring(item:getID() or "") or ""
        if allowed[fullType] and itemId ~= "" and (perTypeCount[fullType] or 0) < perTypeLimit then
            local label = fullType
            if item.getDisplayName then
                local ok, value = pcall(function() return item:getDisplayName() end)
                if ok and value and tostring(value) ~= "" then label = tostring(value) end
            end
            candidates[#candidates + 1] = {
                itemId = itemId,
                fullType = fullType,
                label = label,
            }
            perTypeCount[fullType] = (perTypeCount[fullType] or 0) + 1
        end
    end
    return candidates
end

function GodSystemApp.services.runtime.getTaskProgress(task)
    if not task then
        return 0
    end

    local data = GodSystemApp.services.runtime.getData()
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
        return GodSystemApp.services.runtime.getInventoryItemCount(task.item)
    elseif task.kind == "turnInAnyItem" then
        return GodSystemApp.services.runtime.getAnyInventoryItemCount(task.items)
    elseif task.kind == "spendPoints" then
        return math.max(0, (data.stats.spentPoints or 0) - (task.startSpentPoints or 0))
    elseif task.kind == "buyItems" then
        return math.max(0, (data.stats.boughtItems or 0) - (task.startBoughtItems or 0))
    elseif task.kind == "moveDistance" then
        return math.max(0, math.floor((data.stats.moveDistance or 0) - (task.startMoveDistance or 0)))
    end
    return 0
end

local function taskDisplayItemCounts()
    local nowMs = taskDisplayNowMs()
    local cache = taskDisplayProgressCache
    if cache.refreshedAtMs >= 0 and nowMs >= cache.refreshedAtMs
        and nowMs - cache.refreshedAtMs < TaskDisplayProgressCacheTtlMs then
        return cache.itemCounts
    end

    local itemCounts = {}
    local found = gsFindInventoryItems(nil, false, false)
    for i = 1, #found do
        local entry = found[i]
        local item = entry and entry.item or nil
        local fullType = item and item.getFullType and tostring(item:getFullType() or "") or ""
        if fullType ~= "" then
            itemCounts[fullType] = (itemCounts[fullType] or 0) + 1
        end
    end
    cache.refreshedAtMs = nowMs
    cache.itemCounts = itemCounts
    return itemCounts
end

function GodSystemApp.services.runtime.getTaskDisplayProgress(task)
    if not isTurnInTask(task) then
        return GodSystemApp.services.runtime.getTaskProgress(task)
    end

    local itemCounts = taskDisplayItemCounts()
    if task.kind == "turnInItem" then
        return itemCounts[tostring(task.item or "")] or 0
    end

    local total = 0
    for i = 1, #(task.items or {}) do
        total = total + (itemCounts[tostring(task.items[i] or "")] or 0)
    end
    return total
end

function GodSystemApp.services.runtime.invalidateTaskDisplayProgressCache()
    taskDisplayProgressCache.refreshedAtMs = -1
    taskDisplayProgressCache.itemCounts = {}
end

function GodSystemApp.services.runtime.isTaskComplete(task)
    return GodSystemApp.services.runtime.getTaskProgress(task) >= (task.target or 1)
end

function GodSystemApp.services.runtime.isTaskExpired(task)
    return task and task.status == "active" and task.deadline and gsNowHours() > task.deadline
end

function GodSystemApp.services.runtime.getRemainingHours(task)
    if not task or not task.deadline then
        return task and (task.limitHours or GodSystemConfig.DefaultTaskLimitHours) or 0
    end
    return math.max(0, math.ceil(task.deadline - gsNowHours()))
end

function GodSystemApp.services.runtime.failTask(task, silent, historyKey)
    if not task or task.status ~= "active" then
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    task.status = "failed"
    task.failedAt = gsNowHours()
    data.stats.failedTasks = (data.stats.failedTasks or 0) + 1
    local paid, fromBank, fromCash = GodSystemApp.services.runtime.payTaskFailurePenalty(task.penaltyPoints or 0)
    local prefix = GodSystemApp.services.runtime.text(historyKey or "History_FailTask", "Task failed: ")
    gsAppendHistory(data, { kind = "task", text = prefix .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)) .. GodSystemApp.services.runtime.text("History_Penalty", ", penalty ") .. tostring(paid or 0) .. "/" .. tostring(task.penaltyPoints or 0) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") .. " (" .. GodSystemApp.services.runtime.text("Bank_Current", "Current account") .. " " .. tostring(fromBank or 0) .. ", " .. GodSystemApp.services.runtime.text("Task_CashPenalty", "cash") .. " " .. tostring(fromCash or 0) .. ")" })
    GodSystemApp.services.runtime.save()
    if not silent then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_FailTask", "Task failed: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)))
    end
    return true
end

function GodSystemApp.services.runtime.abandonTask(task)
    if not task or task.status ~= "active" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectTask", "Select a task first"))
        return false
    end
    return GodSystemApp.services.runtime.failTask(task, false, "History_AbandonTask")
end

function GodSystemApp.services.runtime.claimTask(task, silent)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTasks") == false then
        GodSystemApp.services.runtime.notify("Tasks disabled")
        return false
    end
    if not task or task.status ~= "active" then
        return false
    end

    if isTurnInTask(task) then
        if not silent then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTurnInManualRequired", "This task requires manual item selection"))
        end
        return false
    end

    if GodSystemApp.services.runtime.isTaskExpired(task) and not GodSystemApp.services.runtime.isTaskComplete(task) then
        GodSystemApp.services.runtime.failTask(task, false, "History_TaskTimeout")
        return false
    end

    if not GodSystemApp.services.runtime.isTaskComplete(task) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskIncomplete", "Task incomplete"))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    if (task.rewardPoints or 0) > 0 then
        GodSystemApp.services.runtime.addPoints(task.rewardPoints)
    end
    GodSystemApp.services.runtime.giveItems(task.rewardItems)
    task.status = "claimed"
    task.claimedAt = gsNowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    gsAppendHistory(data, { kind = "task", text = GodSystemApp.services.runtime.text("History_ClaimTask", "Task completed: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)) })
    GodSystemApp.services.runtime.save()
    if not silent then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ClaimTask", "Task completed: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)))
    end
    return true
end

function GodSystemApp.services.runtime.submitTurnInTask(task, itemIds)
    if not isTurnInTask(task) or not task or task.status ~= "active" then
        return false
    end
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    if type(itemIds) ~= "table" or #itemIds ~= target then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTurnInSelectionInvalid", "Select exactly {1} matching items"):gsub("{1}", tostring(target)))
        return false
    end
    local selectedItemIds = {}
    for i = 1, #itemIds do
        local itemId = tostring(itemIds[i] or "")
        if itemId == "" or selectedItemIds[itemId] then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTurnInSelectionInvalid", "Select exactly {1} matching items"):gsub("{1}", tostring(target)))
            return false
        end
        selectedItemIds[itemId] = true
    end
    local allowed = turnInAllowedTypes(task)
    local selected = {}
    local found = gsFindInventoryItems(nil, false, false)
    for i = 1, #found do
        local entry = found[i]
        local item = entry and entry.item or nil
        local itemId = item and item.getID and tostring(item:getID() or "") or ""
        local fullType = item and item.getFullType and tostring(item:getFullType() or "") or ""
        if selectedItemIds[itemId] and allowed[fullType] then
            selected[itemId] = entry
        end
    end
    local rows = {}
    for i = 1, #itemIds do
        local row = selected[tostring(itemIds[i])]
        if not row then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TurnInNotEnough", "Not enough items"))
            return false
        end
        rows[#rows + 1] = row
    end
    local removed = {}
    for i = 1, #rows do
        local row = rows[i]
        local ok = pcall(function() row.container:Remove(row.item) end)
        if not ok or GodSystemApp.services.runtime.containerContainsItem(row.container, row.item) then
            local inventory = gsPlayer() and gsPlayer():getInventory() or nil
            if inventory then
                for j = 1, #removed do pcall(function() inventory:AddItem(removed[j].item) end) end
            end
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTurnInFailed", "Submission failed because the inventory changed"))
            return false
        end
        removed[#removed + 1] = row
    end
    local data = GodSystemApp.services.runtime.getData()
    if (task.rewardPoints or 0) > 0 then GodSystemApp.services.runtime.addPoints(task.rewardPoints) end
    GodSystemApp.services.runtime.giveItems(task.rewardItems)
    task.status = "claimed"
    task.claimedAt = gsNowHours()
    data.stats.completedTasks = (data.stats.completedTasks or 0) + 1
    gsAppendHistory(data, { kind = "task", text = GodSystemApp.services.runtime.text("History_ClaimTask", "Task completed: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ClaimTask", "Task completed: ") .. tostring(GodSystemApp.services.runtime.getTaskTitle(task)))
    return true
end

function GodSystemApp.services.runtime.toggleAutoTaskClaim()
    local data = GodSystemApp.services.runtime.getData()
    data.autoTaskClaimEnabled = data.autoTaskClaimEnabled ~= true
    data.lastAutoTaskClaimHour = gsNowHours()
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(data.autoTaskClaimEnabled and "Notify_AutoTaskClaimEnabled" or "Notify_AutoTaskClaimDisabled", data.autoTaskClaimEnabled and "Auto task claim enabled" or "Auto task claim disabled"))
    return data.autoTaskClaimEnabled
end

function GodSystemApp.services.runtime.processAutoTaskClaim()
    local data = GodSystemApp.services.runtime.getData()
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
        if task and task.status == "active" and not isTurnInTask(task) and GodSystemApp.services.runtime.isTaskComplete(task) then
            if GodSystemApp.services.runtime.claimTask(task, true) then
                claimed = claimed + 1
            end
        end
    end
    GodSystemApp.services.runtime.save()
    if claimed > 0 then
        GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_AutoTaskClaimed", "Automatically claimed {1} task(s)"), { claimed }))
        return true
    end
    return false
end

function GodSystemApp.services.runtime.getTaskStatusText(task)
    if not task then
        return ""
    end
    if task.status == "open" then
        return GodSystemApp.services.runtime.text("Status_Open", "Open")
    elseif task.status == "active" then
        if GodSystemApp.services.runtime.isTaskExpired(task) and not GodSystemApp.services.runtime.isTaskComplete(task) then
            return GodSystemApp.services.runtime.text("Status_Expired", "Expired")
        end
        return GodSystemApp.services.runtime.text("Status_Active", "Active")
    elseif task.status == "claimed" then
        return GodSystemApp.services.runtime.text("Status_Claimed", "Claimed")
    elseif task.status == "failed" then
        return GodSystemApp.services.runtime.text("Status_Failed", "Failed")
    end
    return task.status or ""
end

function GodSystemApp.services.runtime.getRewardText(points, items)
    local reward = {}
    if (points or 0) > 0 then
        table.insert(reward, tostring(points) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"))
    end
    if items then
        for i = 1, #items do
            local item = items[i]
            table.insert(reward, GodSystemApp.services.runtime.getItemDisplayName(item.fullType) .. " x" .. tostring(item.count or 1))
        end
    end
    if #reward == 0 then
        return GodSystemApp.services.runtime.text("None", "None")
    end
    return table.concat(reward, ", ")
end

function GodSystemApp.services.runtime.getTaskDetailLines(task)
    if not task then
        return {}
    end
    local progress = GodSystemApp.services.runtime.getTaskDisplayProgress(task)
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    local rewardText = GodSystemApp.services.runtime.getRewardText(task.rewardPoints, task.rewardItems)
    local limit = task.limitHours or GodSystemConfig.DefaultTaskLimitHours
    local lines = {
        GodSystemApp.services.runtime.getTaskListTitle(task),
        GodSystemApp.services.runtime.text("Task_Type", "Type") .. ": " .. GodSystemApp.services.runtime.getTaskKindLabel(task),
        GodSystemApp.services.runtime.text("Task_Difficulty", "Difficulty") .. ": " .. GodSystemApp.services.runtime.getTaskDifficulty(task),
        GodSystemApp.services.runtime.text("Task_Target", "Target") .. ": " .. tostring(task.target or 1),
        GodSystemApp.services.runtime.text("Task_Progress", "Progress") .. ": " .. tostring(math.min(progress, target)) .. "/" .. tostring(target),
        GodSystemApp.services.runtime.text("Task_Limit", "Limit") .. ": " .. tostring(limit) .. GodSystemApp.services.runtime.text("Unit_Hour", "h"),
    }
    if task.status == "active" then
        table.insert(lines, GodSystemApp.services.runtime.text("Task_Remaining", "Remaining") .. ": " .. tostring(GodSystemApp.services.runtime.getRemainingHours(task)) .. GodSystemApp.services.runtime.text("Unit_Hour", "h"))
    end
    local description = GodSystemApp.services.runtime.getTaskDescription(task)
    if description and description ~= "" then
        table.insert(lines, description)
    end
    table.insert(lines, "")
    table.insert(lines, GodSystemApp.services.runtime.text("TaskSection_Reward", "Reward"))
    table.insert(lines, rewardText)
    table.insert(lines, "")
    table.insert(lines, GodSystemApp.services.runtime.text("TaskSection_Penalty", "Failure penalty"))
    table.insert(lines, tostring(task.penaltyPoints or 0) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") .. " - " .. GodSystemApp.services.runtime.text("Task_PenaltyBankFirst", "deduct current account first, then cash"))
    return lines
end

function GodSystemApp.services.runtime.getTaskDetailText(task)
    return table.concat(GodSystemApp.services.runtime.getTaskDetailLines(task), "\n")
end

function GodSystemApp.services.runtime.updateKillRewards()
    local data = GodSystemApp.services.runtime.getData()
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
        GodSystemApp.services.runtime.updateKillTaskProgress(delta, kills - delta)
        GodSystemApp.services.runtime.addPoints(delta * (GodSystemConfig.KillPointReward or 0), GodSystemApp.services.runtime.text("Reason_KillZombie", "Zombie kill"))
    elseif delta < 0 then
        GodSystemApp.services.runtime.normalizeActiveKillTasks(data.lastKnownKills)
        data.lastKnownKills = kills
        GodSystemApp.services.runtime.save()
    end
end

function GodSystemApp.services.runtime.updateTaskTimeouts()
    local data = GodSystemApp.services.runtime.getData()
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" and GodSystemApp.services.runtime.isTaskExpired(task) and not GodSystemApp.services.runtime.isTaskComplete(task) then
            GodSystemApp.services.runtime.failTask(task, false, "History_TaskTimeout")
        end
    end
end

function GodSystemApp.services.runtime.failActiveTasksOnDeath()
    local data = GodSystemApp.services.runtime.getData()
    local failed = 0
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" then
            if GodSystemApp.services.runtime.failTask(task, true, "History_TaskDeathFailed") then
                failed = failed + 1
            end
        end
    end
    return failed
end

function GodSystemApp.services.runtime.handlePlayerDeath()
    local data = GodSystemApp.services.runtime.getData()
    local changed = false
    if GodSystemApp.services.runtime.applyBankDeathPenalty() then
        changed = true
    end
    if GodSystemApp.services.runtime.failActiveTasksOnDeath() > 0 then
        changed = true
    end
    if changed then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_DeathHandled", "Death settlement completed"))
        GodSystemApp.services.runtime.save()
    end
    return changed
end

function GodSystemApp.services.runtime.updateMoveDistance(player)
    player = player or gsPlayer()
    if not player or not player.getX or not player.getY then
        return
    end

    local data = GodSystemApp.services.runtime.getData()
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

function GodSystemApp.services.runtime.onPlayerUpdate(player)
    if not player or player ~= gsPlayer() then
        return
    end
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true then return end
    local now = GodSystemScheduler.nowMs()
    if not GodSystemScheduler.due("client.sp.core.fast", 1000, now) then return end
    GodSystemApp.services.runtime.updateMoveDistance(player)
    GodSystemApp.services.runtime.generateDailyTasks(false)
    GodSystemApp.services.runtime.updateKillRewards()
    GodSystemApp.services.runtime.updateTaskTimeouts()
    if GodSystemScheduler.due("client.sp.core.slow", 5000, now) then
        GodSystemApp.services.runtime.processAutoTaskClaim()
        GodSystemApp.services.runtime.processBankAutoDeposit()
        GodSystemApp.services.runtime.updateBankInvestments()
        GodSystemApp.services.runtime.updateHomeSafeZone()
    end
end

function GodSystemApp.services.runtime.onPlayerDeath(player)
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true then
        return
    end
    if player and type(player) ~= "number" and player ~= gsPlayer() then
        return
    end
    GodSystemApp.services.runtime.normalizeActiveKillTasks()
    GodSystemApp.services.runtime.handlePlayerDeath()
end

function GodSystemApp.services.runtime.onGameStart()
    GodSystemScheduler.reset("client.sp.")
    GodSystemApp.services.runtime.ensureCurrencyInitialized()
    GodSystemApp.services.runtime.generateDailyTasks(false)
end

function GodSystemApp.services.runtime.onCreatePlayer(_, player)
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true then return end
end

function GodSystemApp.services.runtime.onInitGlobalModData()
    GodSystemApp.services.runtime.getData()
end

function GodSystemApp.services.runtime.onGameExit()
end

function GodSystemApp.services.runtime.debugAddPoints()
    if not GodSystemConfig.EnableDebugTools then
        return false
    end
    GodSystemApp.services.runtime.addPoints(500, GodSystemApp.services.runtime.text("Reason_Debug", "Debug"))
    return true
end

if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(GodSystemApp.services.runtime.onInitGlobalModData)
end
if Events.OnGameStart then
    Events.OnGameStart.Add(GodSystemApp.services.runtime.onGameStart)
end
if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(GodSystemApp.services.runtime.onCreatePlayer)
end
if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(GodSystemApp.services.runtime.onPlayerUpdate)
end
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(GodSystemApp.services.runtime.onPlayerDeath)
end
if Events.OnGameExit then
    Events.OnGameExit.Add(GodSystemApp.services.runtime.onGameExit)
end
end
