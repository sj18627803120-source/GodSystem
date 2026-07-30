require "GodSystem/Core/Result"

GodSystemTasksFeatureModule = GodSystemTasksFeatureModule or {}

local Descriptor = GodSystemTasksFeatureModule

Descriptor.id = "feature.tasks"
Descriptor.dependencies = {
    "tasks.config",
    "tasks.state",
    "tasks.inventory",
    "tasks.wallet",
    "clock",
    "random",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function callPort(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function requiredPort(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. id)
    for i = 1, #methods do
        assert(type(port[methods[i]]) == "function", "dependency " .. id .. " is missing method " .. methods[i])
    end
    return port
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return fallback or 0 end
    return math.floor(value)
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    return value ~= "" and value or nil
end

local function findTask(data, taskId)
    for i = 1, #(data.tasks or {}) do
        if tostring(data.tasks[i].taskId or "") == tostring(taskId or "") then return data.tasks[i] end
    end
    return nil
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "tasks.config",
        { "getTemplates", "getDailyCount", "getMaxActive", "getDefaultLimitHours" })
    local state = requiredPort(dependencies, "tasks.state", { "load", "save" })
    local inventory = requiredPort(dependencies, "tasks.inventory",
        { "count", "consume", "restore", "grant", "revoke" })
    local wallet = requiredPort(dependencies, "tasks.wallet",
        { "credit", "revokeCredit", "chargePenalty", "refundPenalty" })
    local clock = requiredPort(dependencies, "clock", { "nowHours", "currentDay" })
    local random = requiredPort(dependencies, "random", { "index" })
    local operations = requiredPort(dependencies, "operations", { "begin", "finish" })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })

    local instance = { started = false, completed = 0, failed = 0, lastIssue = nil }

    local function makeResult(ok, code, data, request)
        local result
        if ok then
            instance.completed = instance.completed + 1
            result = GodSystemResult.ok(moduleId, code, data, operationId(request))
        else
            instance.failed = instance.failed + 1
            result = GodSystemResult.fail(moduleId, code, data, operationId(request))
        end
        local notified, notifyResult = callPort(notifications.publish, result, request)
        if not notified or notifyResult == false then
            instance.lastIssue = { stage = "notify", code = "notificationFailed" }
        end
        return result
    end

    local function begin(action, fingerprint, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = callPort(operations.begin, moduleId, id, action .. "|" .. fingerprint, request)
        if not called then
            instance.lastIssue = { stage = "operationBegin", code = "portError", message = tostring(status) }
            return nil, makeResult(false, "portError", { stage = "operationBegin" }, request)
        end
        if status == "replay" then return nil, value end
        if status ~= "new" then return nil, makeResult(false, value or "operationPending", nil, request) end
        return id, nil
    end

    local function finish(id, result, request)
        local called, stored = callPort(operations.finish, moduleId, id, result, request)
        if not called or stored == false then
            instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
            return makeResult(false, "operationOutcomeUnknown", { original = result }, request)
        end
        return result
    end

    local function load(actor, request)
        local called, data, code = callPort(state.load, actor, request)
        if not called then return nil, makeResult(false, "portError", { stage = "stateLoad" }, request) end
        if type(data) ~= "table" then return nil, makeResult(false, code or "stateUnavailable", nil, request) end
        data.tasks = type(data.tasks) == "table" and data.tasks or {}
        data.stats = type(data.stats) == "table" and data.stats or {}
        return data, nil
    end

    local function save(actor, data, request)
        local called, saved, code = callPort(state.save, actor, data, request)
        if not called then return false, "portError" end
        return saved == true, code or "stateSaveFailed"
    end

    local function nowHours(request)
        local called, value = callPort(clock.nowHours, request)
        return called and tonumber(value) or nil
    end

    local function currentDay(request)
        local called, value = callPort(clock.currentDay, request)
        return called and integer(value, nil) or nil
    end

    local function createTask(template, request)
        local now = assert(nowHours(request), "clock.nowHours failed")
        local maxRandom = 9999
        local called, suffix = callPort(random.index, maxRandom, request)
        if not called then error(suffix) end
        suffix = math.max(1, math.min(maxRandom, integer(suffix, 1)))
        local defaultLimit = integer(config.getDefaultLimitHours(request), 24)
        return {
            taskId = tostring(template.id) .. "_" .. tostring(math.floor(now * 100)) .. "_" .. tostring(suffix),
            sourceId = template.id,
            title = template.title,
            kind = template.kind,
            target = template.target,
            item = template.item,
            items = copy(template.items or {}),
            limitHours = tonumber(template.limitHours) or defaultLimit,
            rewardPoints = math.max(0, integer(template.rewardPoints, 0)),
            rewardItems = copy(template.rewardItems or {}),
            penaltyPoints = math.max(0, integer(template.penaltyPoints, 0)),
            description = template.description,
            status = "open",
            createdAt = now,
            createdDay = currentDay(request),
        }
    end

    local function progressOf(actor, data, task, request)
        if not task then return 0 end
        if task.kind == "kill" then
            return math.max(0, integer(request and request.killProgress, task.killProgress or 0))
        elseif task.kind == "recycleItems" then
            return math.max(0, integer(data.stats.recycledItems, 0) - integer(task.startRecycledItems, 0))
        elseif task.kind == "recyclePoints" then
            return math.max(0, integer(data.stats.recycledPoints, 0) - integer(task.startRecycledPoints, 0))
        elseif task.kind == "surviveHours" then
            return math.max(0, math.floor((nowHours(request) or 0) - (tonumber(task.acceptedAt) or 0)))
        elseif task.kind == "turnInItem" then
            local called, count = callPort(inventory.count, actor, { task.item }, request)
            return called and math.max(0, integer(count, 0)) or 0
        elseif task.kind == "turnInAnyItem" then
            local called, count = callPort(inventory.count, actor, task.items or {}, request)
            return called and math.max(0, integer(count, 0)) or 0
        elseif task.kind == "spendPoints" then
            return math.max(0, integer(data.stats.spentPoints, 0) - integer(task.startSpentPoints, 0))
        elseif task.kind == "buyItems" then
            return math.max(0, integer(data.stats.boughtItems, 0) - integer(task.startBoughtItems, 0))
        elseif task.kind == "moveDistance" then
            return math.max(0, math.floor((tonumber(data.stats.moveDistance) or 0) - (tonumber(task.startMoveDistance) or 0)))
        end
        return 0
    end

    local function generate(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("generate", tostring(request.force == true) .. "|" .. tostring(currentDay(request)), request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local day = currentDay(request)
        if day == nil then return finish(id, makeResult(false, "clockUnavailable", nil, request), request) end
        if request.force ~= true and integer(data.lastGeneratedDay, -1) == day then
            return finish(id, makeResult(true, "alreadyGenerated", { count = 0, day = day }, request), request)
        end
        local called, templates = callPort(config.getTemplates, request.actor, request)
        if not called or type(templates) ~= "table" or #templates == 0 then
            return finish(id, makeResult(false, "taskTemplatesUnavailable", nil, request), request)
        end
        local before = copy(data)
        local kept = {}
        for i = 1, #data.tasks do
            if data.tasks[i].status == "active" then kept[#kept + 1] = data.tasks[i] end
        end
        local count = math.min(#templates, math.max(0, integer(config.getDailyCount(request.actor, data, request), 0)))
        local available = {}
        for i = 1, #templates do available[i] = templates[i] end
        for _ = 1, count do
            local pickCalled, index = callPort(random.index, #available, request)
            if not pickCalled then
                save(request.actor, before, request)
                return finish(id, makeResult(false, "portError", { stage = "random" }, request), request)
            end
            index = math.max(1, math.min(#available, integer(index, 1)))
            local okTask, taskOrError = pcall(createTask, table.remove(available, index), request)
            if not okTask then
                save(request.actor, before, request)
                return finish(id, makeResult(false, "portError", { stage = "createTask", message = tostring(taskOrError) }, request), request)
            end
            kept[#kept + 1] = taskOrError
        end
        data.tasks = kept
        data.lastGeneratedDay = day
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            save(request.actor, before, request)
            return finish(id, makeResult(false, saveCode, nil, request), request)
        end
        return finish(id, makeResult(true, "generated", { count = count, day = day }, request), request)
    end

    local function accept(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("accept", tostring(request.taskId or ""), request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local task = findTask(data, request.taskId)
        if not task or task.status ~= "open" then
            return finish(id, makeResult(false, "taskStateInvalid", nil, request), request)
        end
        local active = 0
        for i = 1, #data.tasks do if data.tasks[i].status == "active" then active = active + 1 end end
        if active >= math.max(0, integer(config.getMaxActive(request.actor, data, request), 0)) then
            return finish(id, makeResult(false, "activeTaskLimit", nil, request), request)
        end
        local before = copy(data)
        local now = nowHours(request)
        if not now then return finish(id, makeResult(false, "clockUnavailable", nil, request), request) end
        task.status = "active"
        task.acceptedAt = now
        task.deadline = now + (tonumber(task.limitHours) or tonumber(config.getDefaultLimitHours(request)) or 24)
        task.killProgress = task.kind == "kill" and 0 or nil
        task.startRecycledItems = integer(data.stats.recycledItems, 0)
        task.startRecycledPoints = integer(data.stats.recycledPoints, 0)
        task.startSpentPoints = integer(data.stats.spentPoints, 0)
        task.startBoughtItems = integer(data.stats.boughtItems, 0)
        task.startMoveDistance = tonumber(data.stats.moveDistance) or 0
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            save(request.actor, before, request)
            return finish(id, makeResult(false, saveCode, nil, request), request)
        end
        return finish(id, makeResult(true, "accepted", { taskId = task.taskId }, request), request)
    end

    local function progress(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local data, failure = load(request.actor, request)
        if not data then return failure end
        local task = findTask(data, request.taskId)
        if not task then return makeResult(false, "taskMissing", nil, request) end
        local value = progressOf(request.actor, data, task, request)
        return makeResult(true, "progress", {
            taskId = task.taskId,
            value = value,
            target = math.max(1, integer(task.target, 1)),
            complete = value >= math.max(1, integer(task.target, 1)),
        }, request)
    end

    local function rollbackClaim(actor, before, turnInReceipt, pointReceipt, itemReceipt, request)
        local restored = true
        if itemReceipt then
            local called, value = callPort(inventory.revoke, actor, itemReceipt, request)
            restored = restored and called and value ~= false
        end
        if pointReceipt then
            local called, value = callPort(wallet.revokeCredit, actor, pointReceipt, request)
            restored = restored and called and value ~= false
        end
        if turnInReceipt then
            local called, value = callPort(inventory.restore, actor, turnInReceipt, request)
            restored = restored and called and value ~= false
        end
        local stateRestored = save(actor, before, request)
        return restored and stateRestored == true
    end

    local function claim(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("claim", tostring(request.taskId or ""), request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local task = findTask(data, request.taskId)
        if not task or task.status ~= "active" then
            return finish(id, makeResult(false, "taskStateInvalid", nil, request), request)
        end
        local target = math.max(1, integer(task.target, 1))
        local value = progressOf(request.actor, data, task, request)
        if value < target then
            local now = nowHours(request)
            if tonumber(task.deadline) and now and now > tonumber(task.deadline) then
                local before = copy(data)
                local penaltyReceipt, paid = nil, 0
                if integer(task.penaltyPoints, 0) > 0 then
                    local called, charged, receiptOrCode, paidValue = callPort(
                        wallet.chargePenalty, request.actor, integer(task.penaltyPoints, 0), request)
                    if not called or charged ~= true or receiptOrCode == nil then
                        return finish(id, makeResult(false,
                            called and (receiptOrCode or "penaltyFailed") or "portError", nil, request), request)
                    end
                    penaltyReceipt = receiptOrCode
                    paid = math.max(0, integer(paidValue, task.penaltyPoints))
                end
                task.status = "failed"
                task.failedAt = now
                data.stats.failedTasks = integer(data.stats.failedTasks, 0) + 1
                local saved, saveCode = save(request.actor, data, request)
                if not saved then
                    local restored = true
                    if penaltyReceipt then
                        local called, refundValue = callPort(
                            wallet.refundPenalty, request.actor, penaltyReceipt, request)
                        restored = called and refundValue ~= false
                    end
                    local stateRestored = save(request.actor, before, request)
                    return finish(id, makeResult(false,
                        restored and stateRestored and saveCode or "rollbackIncomplete", nil, request), request)
                end
                return finish(id, makeResult(false, "taskFailed", {
                    taskId = task.taskId,
                    expired = true,
                    penaltyRequested = integer(task.penaltyPoints, 0),
                    penaltyPaid = paid,
                }, request), request)
            end
            return finish(id, makeResult(false, "taskIncomplete", { progress = value, target = target }, request), request)
        end
        local before = copy(data)
        local turnInReceipt, pointReceipt, itemReceipt
        if task.kind == "turnInItem" or task.kind == "turnInAnyItem" then
            local selector = task.kind == "turnInItem" and { task.item } or (task.items or {})
            local called, consumed, receiptOrCode = callPort(inventory.consume, request.actor, selector, target, request)
            if not called or consumed ~= true or receiptOrCode == nil then
                return finish(id, makeResult(false, called and (receiptOrCode or "turnInNotEnough") or "portError", nil, request), request)
            end
            turnInReceipt = receiptOrCode
        end
        if integer(task.rewardPoints, 0) > 0 then
            local called, credited, receiptOrCode = callPort(wallet.credit, request.actor, integer(task.rewardPoints, 0), request)
            if not called or credited ~= true or receiptOrCode == nil then
                rollbackClaim(request.actor, before, turnInReceipt, nil, nil, request)
                return finish(id, makeResult(false, called and (receiptOrCode or "rewardFailed") or "portError", nil, request), request)
            end
            pointReceipt = receiptOrCode
        end
        if #(task.rewardItems or {}) > 0 then
            local called, granted, receiptOrCode = callPort(inventory.grant, request.actor, copy(task.rewardItems), request)
            if not called or granted ~= true or receiptOrCode == nil then
                rollbackClaim(request.actor, before, turnInReceipt, pointReceipt, nil, request)
                return finish(id, makeResult(false, called and (receiptOrCode or "rewardFailed") or "portError", nil, request), request)
            end
            itemReceipt = receiptOrCode
        end
        task.status = "claimed"
        task.claimedAt = nowHours(request)
        data.stats.completedTasks = integer(data.stats.completedTasks, 0) + 1
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restored = rollbackClaim(request.actor, before, turnInReceipt, pointReceipt, itemReceipt, request)
            return finish(id, makeResult(false, restored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "claimed", {
            taskId = task.taskId,
            rewardPoints = integer(task.rewardPoints, 0),
            rewardItems = copy(task.rewardItems or {}),
        }, request), request)
    end

    local function failTask(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("fail", tostring(request.taskId or ""), request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local task = findTask(data, request.taskId)
        if not task or task.status ~= "active" then
            return finish(id, makeResult(false, "taskStateInvalid", nil, request), request)
        end
        local before = copy(data)
        local penaltyReceipt, paid = nil, 0
        if integer(task.penaltyPoints, 0) > 0 then
            local called, charged, receiptOrCode, paidValue = callPort(
                wallet.chargePenalty, request.actor, integer(task.penaltyPoints, 0), request)
            if not called or charged ~= true or receiptOrCode == nil then
                return finish(id, makeResult(false, called and (receiptOrCode or "penaltyFailed") or "portError", nil, request), request)
            end
            penaltyReceipt = receiptOrCode
            paid = math.max(0, integer(paidValue, task.penaltyPoints))
        end
        task.status = "failed"
        task.failedAt = nowHours(request)
        data.stats.failedTasks = integer(data.stats.failedTasks, 0) + 1
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restored = true
            if penaltyReceipt then
                local called, value = callPort(wallet.refundPenalty, request.actor, penaltyReceipt, request)
                restored = called and value ~= false
            end
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false, restored and stateRestored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "failed", {
            taskId = task.taskId,
            penaltyRequested = integer(task.penaltyPoints, 0),
            penaltyPaid = paid,
        }, request), request)
    end

    instance.public = {
        generate = generate,
        accept = accept,
        progress = progress,
        claim = claim,
        fail = failTask,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        local data = { started = self.started, completed = self.completed, failed = self.failed, lastIssue = self.lastIssue }
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
