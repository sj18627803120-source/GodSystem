GodSystemRangeFilter = GodSystemRangeFilter or {}

local Filter = GodSystemRangeFilter
local MAX_FULL_TYPE_LENGTH = 120
Filter.MAX_ACTIVE_ITEMS = 20000

function Filter.cleanMode(value)
    value = tostring(value or "")
    if value == "allowlist" or value == "denylist" then return value end
    return nil
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function Filter.cleanFullType(value)
    if type(value) ~= "string" then return nil end
    local fullType = trim(value)
    if fullType == "" or #fullType > MAX_FULL_TYPE_LENGTH then return nil end
    local moduleName, itemName = fullType:match("^([^%.]+)%.(.+)$")
    if not moduleName or not itemName or fullType:find("[%c%s]") then return nil end
    return fullType
end

function Filter.cleanBatch(values, maximum)
    if type(values) ~= "table" then return nil end
    maximum = math.max(1, math.floor(tonumber(maximum) or Filter.MAX_ACTIVE_ITEMS))
    local result, seen = {}, {}
    for _, raw in pairs(values) do
        local fullType = Filter.cleanFullType(raw)
        if not fullType then return nil end
        if not seen[fullType] then
            seen[fullType] = true
            result[#result + 1] = fullType
            if #result > maximum then return nil end
        end
    end
    table.sort(result)
    return result
end

local function sourceValues(input)
    if type(input.activeFullTypes) == "table" then return input.activeFullTypes end
    if type(input.allowedFullTypes) == "table" then return input.allowedFullTypes end
    -- A former blacklist must never become a new allowlist. Its values are
    -- deliberately ignored so players opt in again under the safer rule.
    if input.mode == "blacklist" then return {} end
    return type(input.fullTypes) == "table" and input.fullTypes or {}
end

function Filter.normalize(input)
    input = type(input) == "table" and input or {}
    local mode = Filter.cleanMode(input.mode)
    -- The old blacklist format is intentionally fail-closed.  Only the old
    -- allowedFullTypes format is migrated into the new safe mode.
    if not mode then mode = "allowlist" end
    local activeFullTypes = Filter.cleanBatch(sourceValues(input)) or {}
    return {
        mode = mode,
        revision = math.max(1, math.floor(tonumber(input.revision) or 1)),
        activeFullTypes = activeFullTypes,
        -- Keep the legacy field in snapshots and old UI callers while all new
        -- logic reads activeFullTypes.
        allowedFullTypes = activeFullTypes,
    }
end

function Filter.compile(input)
    local state = Filter.normalize(input)
    local set = {}
    for i = 1, #state.activeFullTypes do
        set[state.activeFullTypes[i]] = true
    end
    return {
        mode = state.mode,
        revision = state.revision,
        activeFullTypes = state.activeFullTypes,
        allowedFullTypes = state.activeFullTypes,
        set = set,
    }
end

function Filter.canStart(compiled)
    compiled = compiled or Filter.compile(nil)
    if compiled.mode == "denylist" then return true end
    return #(compiled.activeFullTypes or {}) > 0
end

function Filter.allows(compiled, fullType)
    compiled = compiled or Filter.compile(nil)
    local member = compiled.set and compiled.set[tostring(fullType or "")] == true
    if compiled.mode == "denylist" then member = not member end
    return member
end

function Filter.applyDelta(input, delta)
    local state = Filter.normalize(input)
    delta = type(delta) == "table" and delta or {}
    local baseRevision = math.floor(tonumber(delta.baseRevision) or -1)
    if baseRevision ~= state.revision then
        return { ok = false, code = "RangeFilterRevisionConflict", state = state }
    end

    local nextState = Filter.normalize(state)
    local members = {}
    for i = 1, #nextState.activeFullTypes do members[nextState.activeFullTypes[i]] = true end
    local operation = tostring(delta.op or "")
    if operation == "setMode" then
        local mode = Filter.cleanMode(delta.mode)
        if not mode then return { ok = false, code = "RangeFilterInvalidMode", state = state } end
        if mode == state.mode then
            return { ok = true, code = "RangeFilterUnchanged", state = state }
        end
        nextState.mode = mode
        nextState.revision = state.revision + 1
        return { ok = true, code = "RangeFilterModeChanged", state = nextState }
    end
    local values
    if operation == "add" or operation == "remove" then
        local one = Filter.cleanFullType(delta.fullType)
        values = one and { one } or nil
    elseif operation == "addMany" or operation == "removeMany" then
        values = Filter.cleanBatch(delta.fullTypes, 256)
    else
        return { ok = false, code = "RangeFilterInvalidOperation", state = state }
    end
    if not values then return { ok = false, code = "RangeFilterInvalidItem", state = state } end

    local changed = false
    if operation == "add" or operation == "addMany" then
        for i = 1, #values do
            local fullType = values[i]
            if not members[fullType] then
                members[fullType] = true
                changed = true
            end
        end
    else
        for i = 1, #values do
            local fullType = values[i]
            if members[fullType] then
                members[fullType] = nil
                changed = true
            end
        end
    end

    if changed then
        nextState.activeFullTypes = {}
        for fullType in pairs(members) do nextState.activeFullTypes[#nextState.activeFullTypes + 1] = fullType end
        table.sort(nextState.activeFullTypes)
        if #nextState.activeFullTypes > Filter.MAX_ACTIVE_ITEMS then
            return { ok = false, code = "RangeFilterTooManyItems", state = state }
        end
        nextState.allowedFullTypes = nextState.activeFullTypes
        nextState.revision = state.revision + 1
    end
    return {
        ok = true,
        code = changed and "RangeFilterUpdated" or "RangeFilterUnchanged",
        state = nextState,
    }
end
