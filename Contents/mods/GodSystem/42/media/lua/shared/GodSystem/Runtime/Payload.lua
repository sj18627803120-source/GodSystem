GodSystemRuntimePayload = GodSystemRuntimePayload or {}

local Payload = GodSystemRuntimePayload

function Payload.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[Payload.copy(key, seen)] = Payload.copy(child, seen)
    end
    return result
end

function Payload.identifier(value)
    value = tostring(value or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function encode(value, visiting)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then
        if not finite(value) then return nil, "numberInvalid" end
        return "d" .. string.format("%.17g", value)
    end
    if kind == "string" then return "s" .. string.format("%q", value) end
    if kind ~= "table" then return nil, "payloadTypeInvalid:" .. kind end
    visiting = visiting or {}
    if visiting[value] then return nil, "payloadCycle" end
    visiting[value] = true
    local rows = {}
    for key, child in pairs(value) do
        local encodedKey, keyError = encode(key, visiting)
        if not encodedKey then
            visiting[value] = nil
            return nil, keyError
        end
        local encodedChild, childError = encode(child, visiting)
        if not encodedChild then
            visiting[value] = nil
            return nil, childError
        end
        rows[#rows + 1] = encodedKey .. "=" .. encodedChild
    end
    visiting[value] = nil
    table.sort(rows)
    return "t{" .. table.concat(rows, ",") .. "}"
end

function Payload.fingerprint(action, args)
    local encoded, reason = encode({
        action = tostring(action or ""),
        args = type(args) == "table" and args or {},
    })
    return encoded, reason
end

return Payload
