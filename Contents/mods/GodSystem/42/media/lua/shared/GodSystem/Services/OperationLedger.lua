require "GodSystem/Core/Result"

GodSystemOperationLedger = GodSystemOperationLedger or {}

local Ledger = GodSystemOperationLedger

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

local function normalizeId(value)
    value = tostring(value or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function scalarToken(value)
    local valueType = type(value)
    if valueType == "nil" then return "n:" end
    if valueType == "boolean" then return value and "b:1" or "b:0" end
    if valueType == "number" then return "d:" .. tostring(value) end
    return "s:" .. tostring(value)
end

function Ledger.fingerprint(command, payload, keys)
    local tokens = { tostring(command or "") }
    for i = 1, #(keys or {}) do
        local key = tostring(keys[i])
        tokens[#tokens + 1] = key .. "=" .. scalarToken(type(payload) == "table" and payload[key] or nil)
    end
    return table.concat(tokens, "|")
end

function Ledger.new(bucket, options)
    options = options or {}
    bucket = type(bucket) == "table" and bucket or {}
    bucket.results = type(bucket.results) == "table" and bucket.results or {}
    bucket.order = type(bucket.order) == "table" and bucket.order or {}
    local instance = {
        bucket = bucket,
        maxEntries = math.max(20, math.floor(tonumber(options.maxEntries) or 200)),
    }

    function instance:recoverProcessing()
        for _, row in pairs(self.bucket.results) do
            if type(row) == "table" and row.status == "processing" then
                row.status = "unknown"
                row.ok = false
                row.code = "operationOutcomeUnknown"
                row.finishedAt = tonumber(row.finishedAt) or nowMs()
            end
        end
    end

    function instance:prune()
        while #self.bucket.order > self.maxEntries do
            local operationId = table.remove(self.bucket.order, 1)
            self.bucket.results[operationId] = nil
        end
    end

    function instance:get(operationId)
        operationId = normalizeId(operationId)
        return operationId and self.bucket.results[operationId] or nil
    end

    function instance:begin(operationId, fingerprint)
        operationId = normalizeId(operationId)
        fingerprint = tostring(fingerprint or "")
        if not operationId or fingerprint == "" then
            return nil, GodSystemResult.fail("operations", "operationInvalid", nil, operationId)
        end
        local existing = self.bucket.results[operationId]
        if existing then
            if tostring(existing.fingerprint or "") ~= fingerprint then
                return nil, GodSystemResult.fail("operations", "operationMismatch", nil, operationId)
            end
            return existing, GodSystemResult.ok("operations", "operationReplay", existing.result, operationId)
        end
        local row = {
            status = "processing",
            fingerprint = fingerprint,
            startedAt = nowMs(),
        }
        self.bucket.results[operationId] = row
        self.bucket.order[#self.bucket.order + 1] = operationId
        self:prune()
        return row, nil
    end

    function instance:finish(operationId, result)
        operationId = normalizeId(operationId)
        local row = operationId and self.bucket.results[operationId] or nil
        if not row then return GodSystemResult.fail("operations", "operationMissing", nil, operationId) end
        result = GodSystemResult.normalize(result, result and result.moduleId or "operations", operationId)
        row.status = "done"
        row.ok = result.ok
        row.code = result.code
        row.result = result
        row.finishedAt = nowMs()
        return result
    end

    function instance:markUnknown(operationId, code)
        operationId = normalizeId(operationId)
        local row = operationId and self.bucket.results[operationId] or nil
        if not row then return false end
        row.status = "unknown"
        row.ok = false
        row.code = tostring(code or "operationOutcomeUnknown")
        row.finishedAt = nowMs()
        return true
    end

    instance:recoverProcessing()
    return instance
end

