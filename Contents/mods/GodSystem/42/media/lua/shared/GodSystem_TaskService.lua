require "GodSystem_Config"
require "GodSystem_AdminConfig"

GodSystemTaskService = GodSystemTaskService or {}

local TaskService = GodSystemTaskService

TaskService.moduleId = "tasks"
TaskService.PermitKind = "storagePermit"
TaskService.PermitSourceId = "storage_expansion_permit"
TaskService.PermitTarget = 50
TaskService.PermitFullType = "GodSystem.StorageExpansionPermit"

local KIND_ORDER = {
    storagePermit = 0,
    kill = 10,
    recycleItems = 20,
    recyclePoints = 30,
    surviveHours = 40,
    turnInItem = 50,
    turnInAnyItem = 60,
    spendPoints = 70,
    buyItems = 80,
    moveDistance = 90,
}

local function result(ok, code, data, operationId)
    return {
        ok = ok == true,
        code = tostring(code or ""),
        data = data,
        operationId = operationId and tostring(operationId) or nil,
        moduleId = TaskService.moduleId,
    }
end

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then value = fallback or 0 end
    return math.floor(value)
end

local function copyArray(source)
    local copy = {}
    for i = 1, #(source or {}) do copy[#copy + 1] = source[i] end
    return copy
end

local function copyItems(source)
    local copy = {}
    for i = 1, #(source or {}) do
        copy[#copy + 1] = { fullType = source[i].fullType, count = integer(source[i].count, 1) }
    end
    return copy
end

local function removeTask(data, task)
    for i = #(data.tasks or {}), 1, -1 do
        if data.tasks[i] == task then table.remove(data.tasks, i); return true end
    end
    return false
end

function TaskService.difficultyFromPenalty(penalty)
    penalty = math.max(0, integer(penalty, 0))
    if penalty < 30 then return 1 end
    if penalty < 80 then return 2 end
    if penalty < 150 then return 3 end
    return 4
end

function TaskService.normalizeTask(task)
    if type(task) ~= "table" then return nil end
    task.difficulty = math.max(1, math.min(4, integer(task.difficulty, TaskService.difficultyFromPenalty(task.penaltyPoints))))
    if task.kind == TaskService.PermitKind or task.sourceId == TaskService.PermitSourceId then
        task.kind = TaskService.PermitKind
        task.sourceId = TaskService.PermitSourceId
        task.isLongTerm = true
        task.target = TaskService.PermitTarget
        task.limitHours = nil
        task.deadline = nil
        task.penaltyPoints = 0
        task.rewardPoints = 0
        task.rewardItems = { { fullType = TaskService.PermitFullType, count = 1 } }
        task.permitProgress = math.max(0, integer(task.permitProgress, 0))
        task.difficulty = 4
    end
    return task
end

function TaskService.createPermitTask(now, randomIndex)
    local random = randomIndex and randomIndex(9999) or math.random(1, 9999)
    return {
        taskId = TaskService.PermitSourceId .. "_" .. tostring(math.floor((now or 0) * 100)) .. "_" .. tostring(random),
        sourceId = TaskService.PermitSourceId,
        title = "Task_StoragePermit_Title",
        description = "Task_StoragePermit_Desc",
        kind = TaskService.PermitKind,
        target = TaskService.PermitTarget,
        permitProgress = 0,
        rewardPoints = 0,
        rewardItems = { { fullType = TaskService.PermitFullType, count = 1 } },
        penaltyPoints = 0,
        status = "open",
        createdAt = now or 0,
        isLongTerm = true,
        difficulty = 4,
    }
end

function TaskService.isPermit(task)
    return type(task) == "table" and (task.kind == TaskService.PermitKind or task.sourceId == TaskService.PermitSourceId)
end

function TaskService.ensurePermitTask(data, now, randomIndex, enabled)
    data.tasks = type(data.tasks) == "table" and data.tasks or {}
    if enabled == false then return nil, false end
    local keep, changed = nil, false
    for i = #data.tasks, 1, -1 do
        local task = TaskService.normalizeTask(data.tasks[i])
        if TaskService.isPermit(task) and (task.status == "open" or task.status == "active") then
            if not keep then keep = task else table.remove(data.tasks, i); changed = true end
        end
    end
    if not keep then
        keep = TaskService.createPermitTask(now, randomIndex)
        data.tasks[#data.tasks + 1] = keep
        changed = true
    end
    return keep, changed
end

function TaskService.sortTasks(tasks)
    table.sort(tasks, function(a, b)
        local ap, bp = TaskService.isPermit(a), TaskService.isPermit(b)
        if ap ~= bp then return ap end
        local ak, bk = KIND_ORDER[a.kind] or 999, KIND_ORDER[b.kind] or 999
        if ak ~= bk then return ak < bk end
        local ad, bd = integer(a.difficulty, TaskService.difficultyFromPenalty(a.penaltyPoints)), integer(b.difficulty, TaskService.difficultyFromPenalty(b.penaltyPoints))
        if ad ~= bd then return ad < bd end
        local at, bt = tostring(a.title or a.sourceId or ""), tostring(b.title or b.sourceId or "")
        if at ~= bt then return at < bt end
        return tostring(a.taskId or "") < tostring(b.taskId or "")
    end)
    return tasks
end

function TaskService.create(dependencies)
    local deps = dependencies or {}
    local service = { moduleId = TaskService.moduleId, dependencies = deps, lastError = nil }

    local function now() return deps.nowHours and deps.nowHours() or 0 end
    local function day() return deps.currentDay and deps.currentDay() or math.floor(now() / 24) end
    local function randomIndex(maximum)
        maximum = math.max(1, integer(maximum, 1))
        return deps.randomIndex and deps.randomIndex(maximum) or math.random(1, maximum)
    end
    local function featureEnabled()
        return not deps.featureEnabled or deps.featureEnabled("EnableTasks") ~= false
    end
    local function permitEnabled()
        return featureEnabled() and (not deps.featureEnabled or deps.featureEnabled("EnablePersonalStorage") ~= false)
    end
    local function appendHistory(data, code, task, extra)
        if deps.appendHistory then deps.appendHistory(data, code, task, extra) end
    end
    local function notify(code, values)
        if deps.notify then deps.notify(code, values) end
    end
    local function save(data)
        if deps.save then deps.save(data) end
    end
    local function availableTemplates()
        local rows = {}
        for i = 1, #(GodSystemConfig.TaskTemplates or {}) do
            local template = GodSystemConfig.TaskTemplates[i]
            local available = true
            if deps.templateAvailable then available = deps.templateAvailable(template) end
            if available then rows[#rows + 1] = template end
        end
        if #rows == 0 then return GodSystemConfig.TaskTemplates or {} end
        return rows
    end

    function service:availableTemplates()
        return availableTemplates()
    end
    local function maxActive(data)
        if deps.maxActiveTasks then return deps.maxActiveTasks(data) end
        return GodSystemConfig.MaxActiveTasks or 3
    end
    local function dailyCount(data)
        if deps.dailyTaskCount then return deps.dailyTaskCount(data) end
        return GodSystemConfig.DailyTaskCount or 5
    end

    function service:generateTask(template)
        local created = now()
        return TaskService.normalizeTask({
            taskId = tostring(template.id) .. "_" .. tostring(math.floor(created * 100)) .. "_" .. tostring(randomIndex(9999)),
            sourceId = template.id,
            title = template.title,
            kind = template.kind,
            target = template.target,
            item = template.item,
            items = copyArray(template.items),
            limitHours = template.limitHours or GodSystemConfig.DefaultTaskLimitHours,
            rewardPoints = GodSystemAdminConfig.applyTaskReward(template.rewardPoints or 0),
            rewardItems = copyItems(template.rewardItems),
            penaltyPoints = GodSystemAdminConfig.applyTaskPenalty(template.penaltyPoints or 0),
            description = template.description,
            status = "open",
            createdAt = created,
            createdDay = day(),
        })
    end

    function service:normalize(data)
        data.tasks = type(data.tasks) == "table" and data.tasks or {}
        data.stats = type(data.stats) == "table" and data.stats or {}
        for i = 1, #data.tasks do TaskService.normalizeTask(data.tasks[i]) end
        TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        return data
    end

    function service:find(data, taskId)
        self:normalize(data)
        for i = 1, #data.tasks do
            if tostring(data.tasks[i].taskId or "") == tostring(taskId or "") then return data.tasks[i] end
        end
        return nil
    end

    function service:activeCount(data)
        local count = 0
        self:normalize(data)
        for i = 1, #data.tasks do if data.tasks[i].status == "active" then count = count + 1 end end
        return count
    end

    function service:generateDaily(data, force)
        self:normalize(data)
        local currentDay = day()
        if not force and data.lastGeneratedDay == currentDay then return result(true, "unchanged", { count = 0 }) end
        local kept = {}
        for i = 1, #data.tasks do
            local task = data.tasks[i]
            if task.status == "active" or (TaskService.isPermit(task) and task.status == "open") then
                kept[#kept + 1] = task
            elseif task.status == "claimed" then
                appendHistory(data, "TaskStatusClaimed", task)
            elseif task.status == "failed" then
                appendHistory(data, "TaskStatusFailed", task)
            end
        end
        local templates = availableTemplates()
        local count = math.min(dailyCount(data), #templates)
        local used = {}
        for _ = 1, count do
            local index = randomIndex(#templates)
            local guard = 0
            while used[index] and guard < 30 do index = randomIndex(#templates); guard = guard + 1 end
            used[index] = true
            kept[#kept + 1] = self:generateTask(templates[index])
        end
        data.tasks = kept
        data.lastGeneratedDay = currentDay
        TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        appendHistory(data, "DailyTasks", nil, { count })
        save(data)
        return result(true, "generated", { count = count })
    end

    function service:refresh(data, charge)
        self:normalize(data)
        local open = {}
        for i = 1, #data.tasks do
            if data.tasks[i].status == "open" and not TaskService.isPermit(data.tasks[i]) then open[#open + 1] = i end
        end
        if #open == 0 then return result(false, "noOpenTask") end
        local cost = math.max(0, integer(GodSystemConfig.RefreshTaskCost, 0))
        if cost > 0 and charge and charge(cost) ~= true then return result(false, "insufficientFunds") end
        local templates = availableTemplates()
        for i = 1, #open do data.tasks[open[i]] = self:generateTask(templates[randomIndex(#templates)]) end
        data.stats.spentPoints = integer(data.stats.spentPoints, 0) + cost
        appendHistory(data, "RefreshTasks", nil, { cost })
        save(data)
        return result(true, "refreshed", { cost = cost, count = #open })
    end

    function service:accept(data, task, context)
        self:normalize(data)
        if not task or task.status ~= "open" then return result(false, "stateInvalid") end
        if self:activeCount(data) >= maxActive(data) then return result(false, "activeLimit") end
        context = context or {}
        task.status = "active"
        task.acceptedAt = now()
        task.deadline = TaskService.isPermit(task) and nil or task.acceptedAt + (task.limitHours or GodSystemConfig.DefaultTaskLimitHours)
        task.startKills = integer(context.kills, 0)
        task.killProgress = task.kind == "kill" and 0 or nil
        task.startRecycledItems = integer(data.stats.recycledItems, 0)
        task.startRecycledPoints = integer(data.stats.recycledPoints, 0)
        task.startSpentPoints = integer(data.stats.spentPoints, 0)
        task.startBoughtItems = integer(data.stats.boughtItems, 0)
        task.startMoveDistance = tonumber(data.stats.moveDistance) or 0
        if TaskService.isPermit(task) then task.permitProgress = 0 end
        appendHistory(data, "AcceptTask", task)
        save(data)
        return result(true, "accepted", { taskId = task.taskId })
    end

    function service:ensureKillProgress(task, kills)
        if not task or task.kind ~= "kill" then return 0 end
        kills = math.max(0, integer(kills, 0))
        if task.killProgress == nil then
            task.killProgress = math.max(0, kills - math.max(0, integer(task.startKills, kills)))
        end
        task.killProgress = math.max(0, integer(task.killProgress, 0))
        return task.killProgress
    end

    function service:applyKillDelta(data, delta, baseline)
        local changed = false
        delta = math.max(0, integer(delta, 0))
        if delta == 0 then return false end
        for i = 1, #(data.tasks or {}) do
            local task = data.tasks[i]
            if task.status == "active" and task.kind == "kill" then
                task.killProgress = self:ensureKillProgress(task, baseline) + delta
                changed = true
            end
        end
        return changed
    end

    function service:progress(data, task, context)
        if not task then return 0 end
        context = context or {}
        if TaskService.isPermit(task) then return math.max(0, integer(task.permitProgress, 0)) end
        if task.kind == "kill" then return self:ensureKillProgress(task, context.kills)
        elseif task.kind == "recycleItems" then return math.max(0, integer(data.stats.recycledItems, 0) - integer(task.startRecycledItems, 0))
        elseif task.kind == "recyclePoints" then return math.max(0, integer(data.stats.recycledPoints, 0) - integer(task.startRecycledPoints, 0))
        elseif task.kind == "surviveHours" then return math.max(0, math.floor(now() - (task.acceptedAt or now())))
        elseif task.kind == "turnInItem" then return deps.itemCount and deps.itemCount(task.item) or 0
        elseif task.kind == "turnInAnyItem" then return deps.anyItemCount and deps.anyItemCount(task.items) or 0
        elseif task.kind == "spendPoints" then return math.max(0, integer(data.stats.spentPoints, 0) - integer(task.startSpentPoints, 0))
        elseif task.kind == "buyItems" then return math.max(0, integer(data.stats.boughtItems, 0) - integer(task.startBoughtItems, 0))
        elseif task.kind == "moveDistance" then return math.max(0, math.floor((data.stats.moveDistance or 0) - (task.startMoveDistance or 0))) end
        return 0
    end

    function service:isComplete(data, task, context)
        return self:progress(data, task, context) >= (task.target or 1)
    end

    function service:isExpired(task)
        return task and task.status == "active" and not TaskService.isPermit(task) and task.deadline and now() > task.deadline or false
    end

    function service:remainingHours(task)
        if TaskService.isPermit(task) then return nil end
        if not task or not task.deadline then return task and (task.limitHours or GodSystemConfig.DefaultTaskLimitHours) or 0 end
        return math.max(0, math.ceil(task.deadline - now()))
    end

    function service:fail(data, task, reasonCode, silent, prepaidPenalty)
        if not task or task.status ~= "active" then return result(false, "stateInvalid") end
        local permitTask = TaskService.isPermit(task)
        local penalty = prepaidPenalty
        if penalty == nil then
            penalty = 0
            if deps.payTaskPenalty then penalty = deps.payTaskPenalty(data, task, permitTask) or 0 end
        end
        task.status = "failed"
        task.failedAt = now()
        data.stats.failedTasks = integer(data.stats.failedTasks, 0) + 1
        appendHistory(data, reasonCode or "TaskFailed", task, { penalty })
        if permitTask then removeTask(data, task) end
        TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        save(data)
        if not silent then notify("TaskFailed", { task, penalty }) end
        return result(true, "failed", { penalty = penalty, permit = permitTask })
    end

    function service:incrementPermit(data)
        local permit = TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        if permit and permit.status == "active" then
            permit.permitProgress = math.min(TaskService.PermitTarget, integer(permit.permitProgress, 0) + 1)
            return true, permit.permitProgress
        end
        return false, 0
    end

    function service:claim(data, task, context)
        context = context or {}
        if not task or task.status ~= "active" then return result(false, "stateInvalid") end
        local progress = math.max(self:progress(data, task, context), integer(context.clientProgress, 0))
        if self:isExpired(task) and progress < (task.target or 1) then return self:fail(data, task, "TaskTimeout", false) end
        if progress < (task.target or 1) then return result(false, "incomplete") end
        if task.kind == "turnInItem" and deps.removeItems and deps.removeItems(task.item, task.target or 1) < (task.target or 1) then
            return result(false, "turnInNotEnough")
        elseif task.kind == "turnInAnyItem" and deps.removeAnyItems and deps.removeAnyItems(task.items, task.target or 1) < (task.target or 1) then
            return result(false, "turnInNotEnough")
        end
        if deps.addPoints and (task.rewardPoints or 0) > 0 then deps.addPoints(task.rewardPoints) end
        if deps.giveItems then deps.giveItems(task.rewardItems or {}) end
        local permitTask = TaskService.isPermit(task)
        task.status = "claimed"
        task.claimedAt = now()
        data.stats.completedTasks = integer(data.stats.completedTasks, 0) + 1
        appendHistory(data, "ClaimTask", task)
        local permitProgress
        if not permitTask then
            local changed
            changed, permitProgress = self:incrementPermit(data)
        end
        if permitTask then removeTask(data, task) end
        TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        save(data)
        if not context.silent then notify("TaskClaimed", { task }) end
        return result(true, "claimed", { permitProgress = permitProgress, permit = permitTask })
    end

    function service:settleDeath(data, deathToken)
        self:normalize(data)
        data.taskSettlement = type(data.taskSettlement) == "table" and data.taskSettlement or {}
        deathToken = tostring(deathToken or "")
        if deathToken ~= "" and tostring(data.taskSettlement.lastDeathToken or "") == deathToken then
            return result(true, "duplicateDeath", { failed = 0, penalty = 0 })
        end
        data.taskSettlement.lastDeathToken = deathToken
        local activePermit = nil
        for i = 1, #data.tasks do
            if data.tasks[i].status == "active" and TaskService.isPermit(data.tasks[i]) then activePermit = data.tasks[i]; break end
        end
        local hasActivePermit = activePermit ~= nil
        local basePenalty = 0
        if not hasActivePermit and deps.applyDefaultDeathPenalty then basePenalty = deps.applyDefaultDeathPenalty(data) or 0 end
        local permitPenalty = 0
        if activePermit and deps.payTaskPenalty then permitPenalty = deps.payTaskPenalty(data, activePermit, true) or 0 end
        local failed, penalty = 0, basePenalty + permitPenalty
        local active = {}
        for i = 1, #data.tasks do if data.tasks[i].status == "active" then active[#active + 1] = data.tasks[i] end end
        for i = 1, #active do
            local prepaid = active[i] == activePermit and permitPenalty or nil
            local outcome = self:fail(data, active[i], "DeathTaskFailed", true, prepaid)
            if outcome.ok then
                failed = failed + 1
                if active[i] ~= activePermit then penalty = penalty + integer(outcome.data and outcome.data.penalty, 0) end
            end
        end
        TaskService.ensurePermitTask(data, now(), randomIndex, permitEnabled())
        save(data)
        return result(true, "deathSettled", { failed = failed, penalty = penalty, permitPenalty = hasActivePermit })
    end

    function service:sort(data)
        self:normalize(data)
        TaskService.sortTasks(data.tasks)
        return data.tasks
    end

    function service:health(data)
        if type(data) ~= "table" or type(data.tasks) ~= "table" then
            return result(false, "stateMissing", { tasks = 0, active = 0, permitCount = 0 })
        end
        local permitCount, active = 0, 0
        for i = 1, #data.tasks do
            if TaskService.isPermit(data.tasks[i]) and (data.tasks[i].status == "open" or data.tasks[i].status == "active") then permitCount = permitCount + 1 end
            if data.tasks[i].status == "active" then active = active + 1 end
        end
        return result(permitCount <= 1, permitCount <= 1 and "ok" or "permitDuplicate", {
            tasks = #data.tasks,
            active = active,
            permitCount = permitCount,
        })
    end

    return service
end

return TaskService
