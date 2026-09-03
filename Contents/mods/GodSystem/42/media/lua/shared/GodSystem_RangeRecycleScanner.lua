GodSystemRangeRecycleScanner = GodSystemRangeRecycleScanner or {}

local Scanner = {}
Scanner.__index = Scanner

local function cursorState(cursor)
    if type(cursor) == "table" and type(cursor.seen) == "table" then return cursor end
    return { seen = {} }
end

-- The domain budget used to count only square requests.  A single square can
-- contain a large nested container, so keep a per-call work counter here and
-- yield with the existing cursor when that counter is exhausted.
local function beginWorkSlice(cursor, budget)
    budget = tonumber(budget)
    cursor.workBudget = budget and math.max(1, math.floor(budget)) or nil
    cursor.workUsed = 0
    cursor.workYielded = false
end

local function consumeWork(cursor)
    if cursor.workBudget and cursor.workUsed >= cursor.workBudget then
        cursor.workYielded = true
        return false
    end
    cursor.workUsed = cursor.workUsed + 1
    return true
end

local function clearActive(frame)
    frame.candidateActive = false
    frame.entry = nil
    frame.pendingItem = nil
end

local function finishFrame(frame, removed)
    if removed ~= true then frame.index = frame.index + 1 end
    local onDone = frame.onDone
    clearActive(frame)
    if onDone then onDone(frame, removed) end
end

function GodSystemRangeRecycleScanner.new(hooks)
    assert(type(hooks) == "table", "range scanner hooks are required")
    return setmetatable({ hooks = hooks }, Scanner)
end

function Scanner:listSize(list)
    return math.max(0, math.floor(tonumber(self.hooks:listSize(list)) or 0))
end

function Scanner:listGet(list, index)
    index = math.floor(tonumber(index) or -1)
    if not list or index < 0 or index >= self:listSize(list) then return nil end
    return self.hooks:listGet(list, index)
end

function Scanner:key(value)
    if self.hooks.identity then return self.hooks:identity(value) end
    return value
end

function Scanner:isSeen(cursor, value)
    local key = self:key(value)
    return key ~= nil and cursor.seen[key] == true
end

function Scanner:markCandidate(cursor, candidate, frame, identity)
    local key = self:key(identity or candidate.item or candidate.corpse or candidate.worldObject)
    if key ~= nil then cursor.seen[key] = true end
    frame.candidateActive = true
    candidate._rangeScanFrame = frame
    return candidate
end

function Scanner:afterCandidate(candidate, removed)
    local frame = candidate and candidate._rangeScanFrame or nil
    if not frame or frame.candidateActive ~= true then return end
    finishFrame(frame, removed)
    candidate._rangeScanFrame = nil
end

function Scanner:resolveActive(frame)
    if frame.candidateActive ~= true then return end
    local current = self:listGet(frame.list, frame.index)
    finishFrame(frame, current == frame.entry and false or true)
end

function Scanner:newContainerFrame(container, owner, depth)
    return {
        container = container,
        owner = owner,
        depth = depth,
        list = nil,
        index = 0,
        pendingItem = nil,
        childActive = false,
        candidateActive = false,
    }
end

function Scanner:walkContainer(cursor, stack)
    while #stack > 0 do
        if not consumeWork(cursor) then return nil end
        local frame = stack[#stack]
        frame.list = self.hooks:containerItems(frame.container)
        self:resolveActive(frame)

        if frame.pendingItem then
            local current = self:listGet(frame.list, frame.index)
            if current ~= frame.pendingItem then
                frame.pendingItem = nil
                frame.childActive = false
            elseif frame.childActive then
                frame.childActive = false
            else
                local item = frame.pendingItem
                return self:markCandidate(cursor, {
                    kind = "containerItem",
                    item = item,
                    container = frame.container,
                    owner = frame.owner,
                    fullType = self.hooks:fullType(item),
                }, frame, item)
            end
        end

        if not frame.pendingItem then
            local item = self:listGet(frame.list, frame.index)
            if not item then
                table.remove(stack)
            else
                frame.pendingItem = item
                local nested = self.hooks:itemContainer(item)
                if nested and frame.depth < 32 then
                    frame.childActive = true
                    stack[#stack + 1] = self:newContainerFrame(nested, item, frame.depth + 1)
                end
            end
        end
    end
    return nil
end

function Scanner:groundCandidate(square, cursor)
    local state = cursor.ground
    if not state then
        state = { list = self.hooks:worldObjects(square), index = 0, candidateActive = false }
        cursor.ground = state
    else
        state.list = self.hooks:worldObjects(square)
    end
    self:resolveActive(state)

    while state.index < self:listSize(state.list) do
        if not consumeWork(cursor) then return nil end
        local worldObject = self:listGet(state.list, state.index)
        local item = worldObject and self.hooks:worldItem(worldObject) or nil
        if item and not self.hooks:itemContainer(item) and not self:isSeen(cursor, item) then
            state.entry = worldObject
            return self:markCandidate(cursor, {
                kind = "worldItem",
                item = item,
                worldObject = worldObject,
                fullType = self.hooks:fullType(item),
            }, state, item)
        end
        state.index = state.index + 1
    end
    return nil
end

function Scanner:containerCandidate(square, cursor)
    local state = cursor.container
    if not state then
        state = {
            phase = "objects",
            objects = self.hooks:objects(square),
            objectIndex = 0,
            object = nil,
            containers = nil,
            containerIndex = 0,
            stack = {},
            worldObjects = nil,
            worldIndex = 0,
            worldPending = nil,
        }
        cursor.container = state
    else
        state.objects = self.hooks:objects(square)
    end

    while true do
        local candidate = self:walkContainer(cursor, state.stack)
        if candidate then return candidate end
        if cursor.workYielded then return nil end

        if state.phase == "objects" then
            if not consumeWork(cursor) then return nil end
            if state.containers and state.containerIndex < self:listSize(state.containers) then
                local container = self:listGet(state.containers, state.containerIndex)
                state.containerIndex = state.containerIndex + 1
                if container then state.stack[#state.stack + 1] = self:newContainerFrame(container, state.object, 1) end
            elseif state.objectIndex < self:listSize(state.objects) then
                local object = self:listGet(state.objects, state.objectIndex)
                state.objectIndex = state.objectIndex + 1
                if object and not self.hooks:isVehicle(object) then
                    state.object = object
                    state.containers = self.hooks:objectContainers(object)
                    state.containerIndex = 0
                end
            else
                state.phase = "world"
                state.worldObjects = self.hooks:worldObjects(square)
                state.worldIndex = 0
            end
        else
            if not consumeWork(cursor) then return nil end
            state.worldObjects = self.hooks:worldObjects(square)
            local pending = state.worldPending
            if pending then
                local current = self:listGet(pending.list, pending.index)
                if current ~= pending.entry then
                    state.worldPending = nil
                else
                    self:resolveActive(pending)
                    if pending.candidateActive then
                        return nil
                    end
                    if state.worldPending == pending then
                        return self:markCandidate(cursor, {
                            kind = "worldItem",
                            item = pending.item,
                            worldObject = pending.worldObject,
                            portableShell = true,
                            fullType = self.hooks:fullType(pending.item),
                        }, pending, pending.item)
                    end
                end
            elseif state.worldIndex < self:listSize(state.worldObjects) then
                local worldObject = self:listGet(state.worldObjects, state.worldIndex)
                local item = worldObject and self.hooks:worldItem(worldObject) or nil
                local nested = item and self.hooks:itemContainer(item) or nil
                if nested then
                    state.worldPending = {
                        list = state.worldObjects,
                        index = state.worldIndex,
                        entry = worldObject,
                        item = item,
                        worldObject = worldObject,
                        candidateActive = false,
                        onDone = function(frame) state.worldIndex = frame.index; state.worldPending = nil end,
                    }
                    state.stack[#state.stack + 1] = self:newContainerFrame(nested, item, 1)
                else
                    state.worldIndex = state.worldIndex + 1
                end
            else
                return nil
            end
        end
    end
end

function Scanner:corpseItemCandidate(square, cursor)
    local state = cursor.corpseItems
    if not state then
        state = { corpses = self.hooks:corpses(square), corpseIndex = 0, currentCorpse = nil, stack = {} }
        cursor.corpseItems = state
    else
        state.corpses = self.hooks:corpses(square)
    end

    while true do
        local candidate = self:walkContainer(cursor, state.stack)
        if candidate then
            candidate.corpse = state.currentCorpse
            return candidate
        end
        if cursor.workYielded then return nil end
        if not consumeWork(cursor) then return nil end
        if state.corpseIndex >= self:listSize(state.corpses) then return nil end
        local corpse = self:listGet(state.corpses, state.corpseIndex)
        state.corpseIndex = state.corpseIndex + 1
        local container = corpse and self.hooks:corpseContainer(corpse) or nil
        if container then
            state.currentCorpse = corpse
            state.stack[#state.stack + 1] = self:newContainerFrame(container, corpse, 1)
        end
    end
end

function Scanner:corpseCandidate(square, cursor)
    local state = cursor.corpses
    if not state then
        state = { list = self.hooks:corpses(square), index = 0, candidateActive = false }
        cursor.corpses = state
    else
        state.list = self.hooks:corpses(square)
    end
    self:resolveActive(state)

    while state.index < self:listSize(state.list) do
        if not consumeWork(cursor) then return nil end
        local corpse = self:listGet(state.list, state.index)
        local container = corpse and self.hooks:corpseContainer(corpse) or nil
        local items = container and self.hooks:containerItems(container) or nil
        if corpse and self:listSize(items) == 0 and not self:isSeen(cursor, corpse) then
            state.entry = corpse
            return self:markCandidate(cursor, {
                kind = "corpse",
                corpse = corpse,
                filterable = false,
                fullType = "GodSystem.Corpse",
            }, state, corpse)
        end
        state.index = state.index + 1
    end
    return nil
end

function Scanner:nextCandidate(stage, square, cursor, budget)
    cursor = cursorState(cursor)
    beginWorkSlice(cursor, budget)
    local candidate = nil
    if stage == "ground" then
        candidate = self:groundCandidate(square, cursor)
    elseif stage == "container" then
        candidate = self:containerCandidate(square, cursor)
    elseif stage == "corpseItems" then
        candidate = self:corpseItemCandidate(square, cursor)
    elseif stage == "corpses" then
        candidate = self:corpseCandidate(square, cursor)
    end
    if candidate then return candidate, cursor, false, false, cursor.workUsed end
    if cursor.workYielded then return nil, cursor, false, true, cursor.workUsed end
    return nil, cursor, true, false, cursor.workUsed
end

return GodSystemRangeRecycleScanner
