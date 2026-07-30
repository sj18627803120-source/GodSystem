GodSystemAttributesFeatureState = GodSystemAttributesFeatureState or {}

local State = GodSystemAttributesFeatureState

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function integer(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.floor(value))
end

local function normalize(value)
    value = type(value) == "table" and value or {}
    value.stats = type(value.stats) == "table" and value.stats or {}
    value.stats.spentPoints = integer(value.stats.spentPoints)
    value.stats.modifiedTraits = integer(value.stats.modifiedTraits)
    value.attributeSyncPending = value.attributeSyncPending == true
    return value
end

function State.new(scope)
    assert(type(scope) == "table" and type(scope.get) == "function"
        and type(scope.replace) == "function", "attributes state scope required")

    local function root()
        local value = scope:get()
        value.players = type(value.players) == "table" and value.players or {}
        return value
    end

    local public = {}

    function public.load(ownerKey)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" then return nil, "ownerRequired" end
        local value = root()
        value.players[ownerKey] = normalize(value.players[ownerKey])
        return copy(value.players[ownerKey])
    end

    function public.save(ownerKey, data)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" or type(data) ~= "table" then return false, "stateInvalid" end
        local value = root()
        value.players[ownerKey] = copy(normalize(data))
        scope:replace(value, 1)
        return true
    end

    function public.health()
        local count = 0
        for _ in pairs(root().players) do count = count + 1 end
        return { ok = true, code = "healthy", data = { players = count } }
    end

    return public
end

return State
