-- Deterministic, bounded replay fingerprints for large recycle selections.
-- The digest is deliberately Lua 5.1/Kahlua-safe: no bit operations or Java APIs.
GodSystemRecycleFingerprint = GodSystemRecycleFingerprint or {}
local F = GodSystemRecycleFingerprint

F.FullFingerprintItemLimit = 2000

local MOD_A = 2147483647
local MOD_B = 2147483629
local MUL_A = 131
local MUL_B = 137

local function sortedValues(values)
    local result = {}
    for i = 1, #(values or {}) do result[#result + 1] = tostring(values[i] or "") end
    table.sort(result)
    return result
end

local function sortedSignatureIds(signatures)
    local result = {}
    for id in pairs(signatures or {}) do result[#result + 1] = tostring(id) end
    table.sort(result)
    return result
end

local function newHash()
    return { a = 5381, b = 7919 }
end

local function writeHash(hash, value)
    value = tostring(value or "")
    for i = 1, #value do
        local byte = string.byte(value, i)
        hash.a = (hash.a * MUL_A + byte) % MOD_A
        hash.b = (hash.b * MUL_B + byte) % MOD_B
    end
end

local function digest(count, hash)
    return "h:" .. tostring(count) .. ":" .. tostring(hash.a) .. "-" .. tostring(hash.b)
end

local function writeNormalized(hash, args, ids, signatures, signatureIds)
    writeHash(hash, "recycle")
    writeHash(hash, "|")
    writeHash(hash, tostring(args.mode or ""))
    writeHash(hash, "|")
    writeHash(hash, args.allowDestroyContents == true and "1" or "0")
    for i = 1, #ids do
        writeHash(hash, "|i:")
        writeHash(hash, ids[i])
    end
    for i = 1, #signatureIds do
        local id = signatureIds[i]
        writeHash(hash, "|s:")
        writeHash(hash, id)
        writeHash(hash, "=")
        writeHash(hash, tostring(signatures[id] or ""))
    end
end

function F.fingerprint(args)
    args = type(args) == "table" and args or {}
    local ids = sortedValues(args.itemIds)
    local signatures = type(args.containerContentSignatures) == "table" and args.containerContentSignatures or {}
    local signatureIds = sortedSignatureIds(signatures)
    if #ids > F.FullFingerprintItemLimit then
        local hash = newHash()
        writeNormalized(hash, args, ids, signatures, signatureIds)
        return digest(#ids, hash)
    end
    local parts = {
        "recycle",
        tostring(args.mode or ""),
        args.allowDestroyContents == true and "1" or "0",
    }
    for i = 1, #ids do parts[#parts + 1] = "i:" .. ids[i] end
    for i = 1, #signatureIds do
        local id = signatureIds[i]
        parts[#parts + 1] = "s:" .. id .. "=" .. tostring(signatures[id] or "")
    end
    return table.concat(parts, "|")
end

local function legacyItemCount(value)
    if string.sub(value, 1, 8) ~= "recycle|" then return nil end
    local count, cursor = 0, 1
    while true do
        local itemAt = string.find(value, "|i:", cursor, true)
        local signatureAt = string.find(value, "|s:", cursor, true)
        if not itemAt or (signatureAt and signatureAt < itemAt) then break end
        count = count + 1
        cursor = itemAt + 3
    end
    return count
end

-- Converts a legacy persisted fingerprint without reconstructing its item list.
-- New large fingerprints hash the exact same normalized byte stream, so retries keep
-- their idempotency guarantee across the format upgrade.
function F.compactLegacy(value)
    value = tostring(value or "")
    if string.sub(value, 1, 2) == "h:" then return value end
    local count = legacyItemCount(value)
    if not count or count <= F.FullFingerprintItemLimit then return value end
    local hash = newHash()
    writeHash(hash, value)
    return digest(count, hash)
end

return F
