GodSystemTaskOrder = GodSystemTaskOrder or {}

local TaskOrder = GodSystemTaskOrder

local CATEGORY_RANK = {
    kill = 1,
    recycleItems = 2,
    recyclePoints = 2,
    surviveHours = 3,
    turnInItem = 4,
    turnInAnyItem = 4,
    spendPoints = 5,
    buyItems = 6,
    moveDistance = 7,
}

local CATEGORY_KEY = {
    kill = "kill",
    recycleItems = "recycle",
    recyclePoints = "recycle",
    surviveHours = "survive",
    turnInItem = "turnIn",
    turnInAnyItem = "turnIn",
    spendPoints = "spend",
    buyItems = "buy",
    moveDistance = "move",
}

function TaskOrder.categoryRank(task)
    return CATEGORY_RANK[tostring(task and task.kind or "")] or 99
end

function TaskOrder.categoryKey(task)
    local kind = tostring(task and task.kind or "")
    return CATEGORY_KEY[kind] or ("unknown:" .. kind)
end

function TaskOrder.difficultyRank(task)
    local penalty = math.max(0, math.floor(tonumber(task and task.penaltyPoints) or 0))
    if penalty >= 150 then return 4 end
    if penalty >= 80 then return 3 end
    if penalty >= 30 then return 2 end
    return 1
end

function TaskOrder.difficultyLabel(task)
    return "D" .. tostring(TaskOrder.difficultyRank(task))
end

function TaskOrder.sortedCopy(tasks, status, titleProvider)
    local result = {}
    for i = 1, #(tasks or {}) do
        local task = tasks[i]
        if task and (status == nil or task.status == status) then
            result[#result + 1] = task
        end
    end
    table.sort(result, function(a, b)
        local aCategory = TaskOrder.categoryRank(a)
        local bCategory = TaskOrder.categoryRank(b)
        if aCategory ~= bCategory then return aCategory < bCategory end

        local aCategoryKey = TaskOrder.categoryKey(a)
        local bCategoryKey = TaskOrder.categoryKey(b)
        if aCategoryKey ~= bCategoryKey then return aCategoryKey < bCategoryKey end

        local aDifficulty = TaskOrder.difficultyRank(a)
        local bDifficulty = TaskOrder.difficultyRank(b)
        if aDifficulty ~= bDifficulty then return aDifficulty < bDifficulty end

        local aTitle = tostring(titleProvider and titleProvider(a) or a.title or a.sourceId or "")
        local bTitle = tostring(titleProvider and titleProvider(b) or b.title or b.sourceId or "")
        if aTitle ~= bTitle then return aTitle < bTitle end

        local aSource = tostring(a.sourceId or a.id or "")
        local bSource = tostring(b.sourceId or b.id or "")
        if aSource ~= bSource then return aSource < bSource end
        return tostring(a.taskId or "") < tostring(b.taskId or "")
    end)
    return result
end

return TaskOrder
