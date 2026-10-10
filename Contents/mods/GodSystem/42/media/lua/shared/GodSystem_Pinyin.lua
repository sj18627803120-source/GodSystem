-- Read-only search keys; never use them as item identity or transaction input.
GodSystemPinyin = GodSystemPinyin or {}
local P = GodSystemPinyin
local readings

local function data()
    if not readings then
        require "GodSystem_PinyinData"
        readings = GodSystemPinyinData or {}
    end
    return readings or {}
end

local function codepoint(value, index)
    local first = string.byte(value, index)
    if not first then return nil, index end
    -- Kahlua stores Java text as UTF-16 chars; stock Lua 5.1 exposes UTF-8 bytes.
    if first > 255 then return first, index + 1 end
    if first < 128 then return first, index + 1 end
    local length = first >= 240 and first <= 244 and 4
        or first >= 224 and first <= 239 and 3
        or first >= 194 and first <= 223 and 2 or nil
    if not length then return nil, index + 1 end
    local point = first % (2 ^ (7 - length))
    for offset = 1, length - 1 do
        local byte = string.byte(value, index + offset)
        if not byte or byte < 128 or byte > 191 then return nil, index + 1 end
        point = point * 64 + byte - 128
    end
    return point, index + length
end

local function fieldIndex(value)
    local raw = tostring(value or ""):lower()
    local phonetic, initials = {}, {}
    local lookup = data()
    local index = 1
    while index <= #raw do
        local point, following = codepoint(raw, index)
        local source = string.sub(raw, index, following - 1)
        local reading = point and lookup[point] or nil
        if reading then
            phonetic[#phonetic + 1] = reading
            initials[#initials + 1] = string.sub(reading, 1, 1)
        else
            phonetic[#phonetic + 1] = source
            initials[#initials + 1] = source
        end
        index = following
    end
    return { raw = raw, phonetic = table.concat(phonetic), initials = table.concat(initials) }
end

function P.buildIndex(fields)
    if type(fields) ~= "table" then fields = { fields } end
    local result = {}
    for index = 1, #fields do result[index] = fieldIndex(fields[index]) end
    return result
end

function P.normalizeQuery(query)
    return tostring(query or ""):lower():gsub("%s+", "")
end

local lastQuery, preparedQuery
function P.prepareQuery(query)
    if type(query) == "table" then return query end
    query = tostring(query or "")
    if query ~= lastQuery then
        lastQuery = query
        preparedQuery = { raw = query:lower(), compact = P.normalizeQuery(query) }
    end
    return preparedQuery
end

function P.matches(index, query)
    local prepared = P.prepareQuery(query)
    query = prepared.raw
    if query == "" then return true end
    local compact = prepared.compact
    for i = 1, #(index or {}) do
        local field = index[i]
        if field.raw:find(query, 1, true)
            or field.phonetic:find(compact, 1, true)
            or field.initials:find(compact, 1, true) then return true end
    end
    return false
end

function P.matchFields(fields, query)
    if query == nil or query == "" then return true end
    return P.matches(P.buildIndex(fields), query)
end

-- Per-display/compiled-relation domains, strictly bounded and never persisted.
local domains = {}
local domainNames = { manual=true, recycle=true, shopLegacy=true, hidden=true,
    attributes=true, relationsClient=true, relationsServer=true }
local domainLimits = {manual=512, attributes=512, relationsClient=1024, relationsServer=1024,
    recycle=20000, hidden=20000, shopLegacy=20000}
function P.clearCaches(domain)
    if domain then domains[domain] = nil else domains = {}; lastQuery = nil; preparedQuery = nil end
end
function P.matchCached(domain, key, fields, query)
    local prepared = P.prepareQuery(query)
    if prepared.raw == "" then return true end
    if not domainNames[domain] then return P.matches(P.buildIndex(fields), prepared) end
    local cache = domains[domain]
    if not cache then cache = { entries={}, count=0, bytes=0 }; domains[domain]=cache end
    key = tostring(key or "")
    local entry = cache.entries[key]
    local unchanged = entry and #entry.fields == #fields
    if unchanged then
        for i=1,#fields do
            if entry.fields[i] ~= tostring(fields[i] or "") then unchanged=false; break end
        end
    end
    if not unchanged then
        local normalized, bytes = {}, 0
        for i=1,#fields do normalized[i]=tostring(fields[i] or ""); bytes=bytes+#normalized[i] end
        local index = P.buildIndex(normalized)
        -- At capacity release the old display snapshot; no unbounded text history.
        if cache.count >= domainLimits[domain] or cache.bytes + bytes > 2097152 then
            cache = { entries={}, count=0, bytes=0 }; domains[domain]=cache; entry=nil
        end
        if bytes <= 2097152 then
            cache.count=cache.count+(entry and 0 or 1)
            cache.bytes=cache.bytes-(entry and entry.bytes or 0)+bytes
            cache.entries[key]={ fields=normalized, index=index, bytes=bytes }
        end
        return P.matches(index, prepared)
    end
    return P.matches(entry.index, prepared)
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(P.clearCaches) end
return P
