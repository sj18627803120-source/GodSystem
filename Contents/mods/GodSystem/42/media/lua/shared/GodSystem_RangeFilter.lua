GodSystemRangeFilter = GodSystemRangeFilter or {}

local Filter = GodSystemRangeFilter
local MAX_FULL_TYPE_LENGTH = 120
Filter.MAX_ACTIVE_ITEMS = 20000
-- Private marker stamped only on states this module has validated itself.
-- Tables arriving over the network never inherit this trust: callers pass
-- allowTrusted=false so the full per-entry validation runs.
local TRUSTED_MARKER = "__godSystemFilterTrusted"

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

local function buildState(mode, revision, activeFullTypes)
    return {
        mode = mode,
        revision = revision,
        activeFullTypes = activeFullTypes,
        -- Keep the legacy field in snapshots and old UI callers while all new
        -- logic reads activeFullTypes.
        allowedFullTypes = activeFullTypes,
        [TRUSTED_MARKER] = true,
    }
end

function Filter.normalize(input, allowTrusted)
    input = type(input) == "table" and input or {}
    if allowTrusted ~= false and input[TRUSTED_MARKER] == true
        and (input.mode == "allowlist" or input.mode == "denylist") then
        -- Entries already passed cleanFullType when they first entered the
        -- filter; copy the array defensively without re-validating every item.
        local active = {}
        for i = 1, #(input.activeFullTypes or {}) do active[i] = input.activeFullTypes[i] end
        return buildState(input.mode, math.max(1, math.floor(tonumber(input.revision) or 1)), active)
    end
    local mode = Filter.cleanMode(input.mode)
    -- The old blacklist format is intentionally fail-closed.  Only the old
    -- allowedFullTypes format is migrated into the new safe mode.
    if not mode then mode = "allowlist" end
    local activeFullTypes = Filter.cleanBatch(sourceValues(input)) or {}
    return buildState(mode, math.max(1, math.floor(tonumber(input.revision) or 1)), activeFullTypes)
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

    -- Shallow working copy: its activeFullTypes are replaced wholesale below,
    -- never mutated in place, so sharing the validated array is safe.
    local nextState = {
        mode = state.mode,
        revision = state.revision,
        activeFullTypes = state.activeFullTypes,
        allowedFullTypes = state.activeFullTypes,
        [TRUSTED_MARKER] = true,
    }
    local members = {}
    for i = 1, #state.activeFullTypes do members[state.activeFullTypes[i]] = true end
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
        -- Rebuild the sorted array in a single linear pass instead of
        -- re-collecting via pairs() and re-sorting the whole list.
        local merged = {}
        if operation == "add" or operation == "addMany" then
            local current = state.activeFullTypes
            local i, j = 1, 1
            while i <= #current or j <= #values do
                local a, b = current[i], values[j]
                if a and (not b or a < b) then
                    merged[#merged + 1] = a; i = i + 1
                elseif b and (not a or b < a) then
                    merged[#merged + 1] = b; j = j + 1
                else
                    merged[#merged + 1] = a; i = i + 1; j = j + 1
                end
            end
        else
            local removed = {}
            for i = 1, #values do removed[values[i]] = true end
            for i = 1, #state.activeFullTypes do
                local fullType = state.activeFullTypes[i]
                if not removed[fullType] then merged[#merged + 1] = fullType end
            end
        end
        if #merged > Filter.MAX_ACTIVE_ITEMS then
            return { ok = false, code = "RangeFilterTooManyItems", state = state }
        end
        nextState.activeFullTypes = merged
        nextState.allowedFullTypes = merged
        nextState.revision = state.revision + 1
    end
    return {
        ok = true,
        code = changed and "RangeFilterUpdated" or "RangeFilterUnchanged",
        state = nextState,
    }
end
