GodSystemResult = GodSystemResult or {}

local function tableOrEmpty(value)
    if type(value) == "table" then return value end
    return {}
end

function GodSystemResult.success(code, data, args, operationId)
    return {
        ok = true,
        code = tostring(code or "OK"),
        args = tableOrEmpty(args),
        data = tableOrEmpty(data),
        operationId = operationId and tostring(operationId) or nil,
    }
end

function GodSystemResult.failure(code, args, operationId, data)
    return {
        ok = false,
        code = tostring(code or "UnknownError"),
        args = tableOrEmpty(args),
        data = tableOrEmpty(data),
        operationId = operationId and tostring(operationId) or nil,
    }
end
