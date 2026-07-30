GodSystemResult = GodSystemResult or {}

local Result = GodSystemResult

local function normalizeId(value)
    value = tostring(value or "")
    if value == "" then return nil end
    return value
end

function Result.ok(moduleId, code, data, operationId)
    return {
        ok = true,
        moduleId = normalizeId(moduleId),
        code = tostring(code or "ok"),
        data = data,
        operationId = normalizeId(operationId),
    }
end

function Result.fail(moduleId, code, data, operationId)
    return {
        ok = false,
        moduleId = normalizeId(moduleId),
        code = tostring(code or "unknownError"),
        data = data,
        operationId = normalizeId(operationId),
    }
end

function Result.normalize(value, moduleId, operationId)
    if type(value) == "table" and value.ok ~= nil then
        value.ok = value.ok == true
        value.moduleId = normalizeId(value.moduleId) or normalizeId(moduleId)
        value.code = tostring(value.code or (value.ok and "ok" or "unknownError"))
        value.operationId = normalizeId(value.operationId) or normalizeId(operationId)
        return value
    end
    if value == false or value == nil then
        return Result.fail(moduleId, "unknownError", value, operationId)
    end
    return Result.ok(moduleId, "ok", value, operationId)
end

