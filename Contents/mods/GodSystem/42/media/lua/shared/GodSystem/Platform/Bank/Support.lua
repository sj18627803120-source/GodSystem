GodSystemBankPlatformSupport = GodSystemBankPlatformSupport or {}

local Support = GodSystemBankPlatformSupport

function Support.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[Support.copy(key, seen)] = Support.copy(item, seen)
    end
    return result
end

function Support.integer(value, fallback, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    value = math.floor(tonumber(value) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Support.number(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return tonumber(fallback) or 0
    end
    return value
end

return Support
