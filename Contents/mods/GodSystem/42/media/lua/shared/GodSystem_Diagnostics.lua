-- Bounded, context-only console diagnostics. Never log request payloads here.
GodSystemDiagnostics = GodSystemDiagnostics or {}
local D = GodSystemDiagnostics
local recent = {}
local order = {}
local unicodeStrings = #"\228\184\173" == 1 -- Kahlua uses Java UTF-16 strings; Lua 5.1 uses bytes.

local function safe(value)
    local result = tostring(value or "-"):gsub("[^%w%._:%-]", "_")
    return result:sub(1, 96)
end

local function milliseconds()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and type(value) == "number" then return value end
    end
    return math.floor((os and os.clock and os.clock() or 0) * 1000)
end

local function errorSummary(value)
    local result = tostring(value or "-"):gsub("[%c]", " ")
    if #result <= 256 then return result end
    local last = 256
    -- Keep the exception on one line without cutting either encoding.
    if unicodeStrings then
        local unit = result:byte(last)
        if unit >= 55296 and unit <= 56319 then last = last - 1 end
    else
        while last > 0 and result:byte(last + 1) >= 128 and result:byte(last + 1) < 192 do last = last - 1 end
    end
    return result:sub(1, last)
end

function D.issue(side, feature, phase, code, operationId, context)
    local hasOperation = operationId ~= nil and tostring(operationId) ~= ""
    local key = safe(side) .. ":" .. safe(feature) .. ":"
        .. (hasOperation and ("op:" .. safe(operationId) .. ":" .. safe(phase) .. ":" .. safe(code)) or (safe(phase) .. ":" .. safe(code)))
    if type(context) == "table" then key = key .. ":" .. safe(context.step) .. ":" .. safe(context.itemType) end
    local now = milliseconds()
    local row = recent[key]
    if row and (hasOperation or now - row.at < 30000) then
        row.suppressed = row.suppressed + 1
        return false
    end
    local repeated = row and row.suppressed or 0
    if not row then order[#order + 1] = key end
    recent[key] = { at = now, suppressed = 0 }
    while #order > 128 do recent[table.remove(order, 1)] = nil end
    local suffix = ""
    if type(context) == "table" then
        for _, field in ipairs({ "source", "itemType", "step", "mutation", "world", "square", "itemLink", "objectSquare", "transmit", "restored" }) do
            if context[field] ~= nil then suffix = suffix .. " " .. field .. "=" .. safe(context[field]) end
        end
        if context.error ~= nil then suffix = suffix .. " error=" .. errorSummary(context.error) end
    end
    print("[GodSystem][diag] version=" .. safe(GodSystemConfig and GodSystemConfig.Version)
        .. " side=" .. safe(side) .. " feature=" .. safe(feature)
        .. " phase=" .. safe(phase) .. " code=" .. safe(code)
        .. " op=" .. safe(operationId) .. " repeat=" .. tostring(repeated) .. suffix)
    return true
end

function D.isUnexpected(code)
    code = tostring(code or "")
    return code == "ServerCommandFailed" or code == "EquipmentUnknown"
        or code == "TransactionOperationUnknown" or code == "ItemGrantFailed"
        or code:find("RollbackFailed", 1, true) ~= nil
        or code:find("PersistFailed", 1, true) ~= nil
end

return D
