if not (isServer and isServer()) then return end

GodSystemTransactionOps = GodSystemTransactionOps or {}
GodSystemTransactionOps.normalized = GodSystemTransactionOps.normalized or {}

local MAX_RESULTS = 64

local function validOpId(args)
    local opId = args and tostring(args.opId or "") or ""
    if #opId > 96 or not string.match(opId, "^gs%-%d+%-%d+%-%d+$") then return nil end
    return opId
end

local function sortedValues(values)
    local result = {}
    for i = 1, #(values or {}) do result[#result + 1] = tostring(values[i] or "") end
    table.sort(result)
    return result
end

local function sortedUniqueNonEmptyValues(values)
    local result, seen = {}, {}
    for i = 1, #(values or {}) do
        local value = tostring(values[i] or "")
        if value ~= "" and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    table.sort(result)
    return result
end

function GodSystemTransactionOps.fingerprint(kind, args)
    args = type(args) == "table" and args or {}
    if kind == "upgradeSystem" then
        return "upgrade|" .. tostring(args.upgradeType or "")
    end
    if kind == "terminalFreshnessService" then
        return "freshnessService|d:" .. tostring(math.max(0, math.floor(tonumber(args.days) or 0)))
    end
    if kind == "recycleSelectedItems" then
        local parts = {
            "recycle",
            tostring(args.mode or ""),
            args.allowDestroyContents == true and "1" or "0",
        }
        local ids = sortedValues(args.itemIds)
        for i = 1, #ids do parts[#parts + 1] = "i:" .. ids[i] end
        local signatures = type(args.containerContentSignatures) == "table" and args.containerContentSignatures or {}
        local signatureIds = {}
        for id in pairs(signatures) do signatureIds[#signatureIds + 1] = tostring(id) end
        table.sort(signatureIds)
        for i = 1, #signatureIds do
            local id = signatureIds[i]
            parts[#parts + 1] = "s:" .. id .. "=" .. tostring(signatures[id] or "")
        end
        return table.concat(parts, "|")
    end
    if kind == "setShopItemsHidden" then
        local parts = { "shopHidden", args.hidden == true and "1" or "0" }
        local keys = sortedUniqueNonEmptyValues(args.variantKeys)
        for i = 1, #keys do parts[#parts + 1] = "k:" .. keys[i] end
        return table.concat(parts, "|")
    end
    return ""
end

function GodSystemTransactionOps.bucket(root, owner, kind, create)
    if type(root) ~= "table" then return nil end
    owner = tostring(owner or "")
    if owner == "" then return nil end
    root.transactionOperations = type(root.transactionOperations) == "table" and root.transactionOperations or {}
    root.transactionOperations[owner] = type(root.transactionOperations[owner]) == "table" and root.transactionOperations[owner] or {}
    local ownerBuckets = root.transactionOperations[owner]
    local bucket = ownerBuckets[kind]
    if not bucket and create == true then
        bucket = { results = {}, order = {} }
        ownerBuckets[kind] = bucket
    end
    if bucket then
        bucket.results = type(bucket.results) == "table" and bucket.results or {}
        bucket.order = type(bucket.order) == "table" and bucket.order or {}
        if GodSystemTransactionOps.normalized[bucket] ~= true then
            for _, result in pairs(bucket.results) do
                if type(result) == "table" and result.status == "processing" then
                    result.status = "unknown"
                    result.ok = false
                    result.code = "TransactionOperationUnknown"
                    result.args = {}
                end
            end
            GodSystemTransactionOps.normalized[bucket] = true
        end
    end
    return bucket
end

function GodSystemTransactionOps.get(root, owner, kind, args)
    local opId = validOpId(args)
    if not opId then return { status = "invalid" } end
    local bucket = GodSystemTransactionOps.bucket(root, owner, kind, false)
    local result = bucket and bucket.results[opId] or nil
    if result and result.fingerprint ~= GodSystemTransactionOps.fingerprint(kind, args) then
        return { status = "mismatch" }
    end
    return result
end

function GodSystemTransactionOps.trim(bucket)
    while bucket and #bucket.order > MAX_RESULTS do
        local removeAt = 1
        for i = 1, #bucket.order do
            local candidate = bucket.results[bucket.order[i]]
            if candidate and candidate.status == "done" then removeAt = i break end
        end
        local opId = table.remove(bucket.order, removeAt)
        bucket.results[opId] = nil
    end
end

function GodSystemTransactionOps.begin(root, owner, kind, args)
    local opId = validOpId(args)
    if not opId then return false end
    local bucket = GodSystemTransactionOps.bucket(root, owner, kind, true)
    if bucket.results[opId] ~= nil then return false end
    bucket.order[#bucket.order + 1] = opId
    bucket.results[opId] = {
        status = "processing",
        fingerprint = GodSystemTransactionOps.fingerprint(kind, args),
    }
    GodSystemTransactionOps.trim(bucket)
    return true
end

function GodSystemTransactionOps.remember(root, owner, kind, args, ok, code, codeArgs, payload)
    local opId = validOpId(args)
    if not opId then return end
    local bucket = GodSystemTransactionOps.bucket(root, owner, kind, true)
    local current = bucket.results[opId]
    bucket.results[opId] = {
        status = "done",
        fingerprint = current and current.fingerprint or GodSystemTransactionOps.fingerprint(kind, args),
        ok = ok == true,
        code = tostring(code or ""),
        args = codeArgs or {},
        payload = payload,
    }
    GodSystemTransactionOps.trim(bucket)
end

function GodSystemTransactionOps.markUnknown(root, owner, kind, args)
    local opId = validOpId(args)
    if not opId then return end
    local bucket = GodSystemTransactionOps.bucket(root, owner, kind, true)
    local current = bucket.results[opId]
    if current and current.status == "processing" then
        bucket.results[opId] = {
            status = "unknown",
            fingerprint = current.fingerprint,
            ok = false,
            code = "TransactionOperationUnknown",
            args = {},
            payload = { opId = opId },
        }
    end
end
