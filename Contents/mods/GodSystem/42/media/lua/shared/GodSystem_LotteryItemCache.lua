require "GodSystem_B42JavaCalls"
require "GodSystem_RuntimeConfig"
require "GodSystem_Scheduler"

GodSystemLotteryItemCache = GodSystemLotteryItemCache or {}

local Cache = GodSystemLotteryItemCache
local SCHEMA = 1
local FILE_PREFIX = "GodSystem_LotteryItemCache_"
local FILE_SUFFIX = ".txt"

local function safeCall(target, methodName, ...)
    if not target then return false, nil end
    if GodSystemB42JavaCalls and GodSystemB42JavaCalls.try then
        return GodSystemB42JavaCalls.try(target, methodName, ...)
    end
    local method = target[methodName]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

local function value(target, methodName, fallback, ...)
    if GodSystemB42JavaCalls and GodSystemB42JavaCalls.value then
        return GodSystemB42JavaCalls.value(target, methodName, fallback, ...)
    end
    local ok, result = safeCall(target, methodName, ...)
    return ok and result ~= nil and result or fallback
end

local function number(valueToConvert, fallback)
    local result = tonumber(valueToConvert)
    return result == nil and fallback or result
end

local function nowMs()
    if GodSystemScheduler and GodSystemScheduler.nowMs then return GodSystemScheduler.nowMs() end
    return 0
end

local function trim(valueToTrim)
    return tostring(valueToTrim or ""):match("^%s*(.-)%s*$") or ""
end

local function escape(valueToEscape)
    return tostring(valueToEscape or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end

local function unescape(valueToUnescape)
    return tostring(valueToUnescape or ""):gsub("%%0A", "\n"):gsub("%%0D", "\r"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function splitRow(line)
    local fields = {}
    for field in tostring(line or ""):gmatch("([^|]*)|?") do
        fields[#fields + 1] = unescape(field)
        if #fields >= 8 then break end
    end
    return fields
end

local function fileName(role)
    return FILE_PREFIX .. (role == "server" and "server" or "sp") .. FILE_SUFFIX
end

local function collectionSize(collection)
    if type(collection) == "table" and type(collection.size) ~= "function" then return #collection end
    return math.max(0, math.floor(number(value(collection, "size", 0), 0)))
end

local function collectionAt(collection, index)
    if type(collection) == "table" and type(collection.get) ~= "function" then return collection[index + 1] end
    return value(collection, "get", nil, index)
end

local function activatedModsFingerprint()
    local ids = {}
    local activated = nil
    if getActivatedMods then
        local ok, result = pcall(getActivatedMods)
        if ok then activated = result end
    end
    local count = collectionSize(activated)
    for index = 0, count - 1 do
        local modId = trim(collectionAt(activated, index))
        if modId ~= "" then
            local version = ""
            if getModInfoByID then
                local okInfo, info = pcall(getModInfoByID, modId)
                if okInfo and info then
                    version = trim(value(info, "getModVersion", ""))
                    if version == "" then version = trim(value(info, "getVersion", "")) end
                end
            end
            ids[#ids + 1] = modId .. "=" .. version
        end
    end
    table.sort(ids)
    return table.concat(ids, ";")
end

local function fingerprint(scriptCount)
    return table.concat({
        "schema=" .. tostring(SCHEMA),
        "version=" .. tostring(GodSystemConfig and GodSystemConfig.Version or ""),
        "mods=" .. escape(activatedModsFingerprint()),
        "scripts=" .. tostring(scriptCount or 0),
    }, "|")
end

local function emptyState(role)
    return {
        role = role,
        status = "loading",
        rows = {},
        candidates = nil,
        scripts = nil,
        cursor = 0,
        total = 0,
        fingerprint = "",
        tickRegistered = false,
        nextStartAt = 0,
        error = nil,
    }
end

local function reset(role)
    local old = Cache.state
    if old and old.tickRegistered and Events and Events.OnTick then Events.OnTick.Remove(Cache.onTick) end
    Cache.state = emptyState(role)
    return Cache.state
end

local function readPersisted(role, expectedFingerprint, expectedCount)
    if not getFileReader then return nil end
    local ok, reader = pcall(getFileReader, fileName(role), true)
    if not ok or not reader then return nil end
    local header, rows, complete = {}, {}, false
    local success = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            line = trim(line)
            if line:sub(1, 1) ~= "#" and line ~= "" then
                local key, data = line:match("^([^=]+)=(.*)$")
                if key == "row" then
                    local fields = splitRow(data)
                    if fields[1] and fields[1] ~= "" then
                        rows[#rows + 1] = {
                            fullType = fields[1],
                            moduleName = fields[2] or "",
                            displayCategory = fields[3] or "",
                            itemType = fields[4] or "",
                            tags = fields[5] or "",
                            hidden = fields[6] == "1",
                            obsolete = fields[7] == "1",
                            eligible = fields[8] ~= "0",
                        }
                    end
                elseif key then
                    header[key] = data
                    if key == "complete" then complete = data == "1" end
                end
            end
        end
    end)
    pcall(function() reader:close() end)
    if not success or not complete then return nil end
    if tonumber(header.schema) ~= SCHEMA then return nil end
    if tostring(header.fingerprint or "") ~= tostring(expectedFingerprint or "") then return nil end
    if tonumber(header.scriptCount) ~= tonumber(expectedCount or -1) then return nil end
    if tonumber(header.rowCount) ~= #rows or #rows <= 0 then return nil end
    local seen = {}
    for index = 1, #rows do
        if seen[rows[index].fullType] then return nil end
        seen[rows[index].fullType] = true
    end
    return rows
end

local function writePersisted(state)
    if not getFileWriter then return false end
    local ok, writer = pcall(getFileWriter, fileName(state.role), true, false)
    if not ok or not writer then return false end
    local success = pcall(function()
        writer:write("# GodSystem lottery full item cache\r\n")
        writer:write("schema=" .. tostring(SCHEMA) .. "\r\n")
        writer:write("complete=1\r\n")
        writer:write("fingerprint=" .. escape(state.fingerprint) .. "\r\n")
        writer:write("scriptCount=" .. tostring(state.total) .. "\r\n")
        writer:write("rowCount=" .. tostring(#state.rows) .. "\r\n")
        for index = 1, #state.rows do
            local row = state.rows[index]
            writer:write("row=" .. table.concat({
                escape(row.fullType),
                escape(row.moduleName),
                escape(row.displayCategory),
                escape(row.itemType),
                escape(row.tags),
                row.hidden and "1" or "0",
                row.obsolete and "1" or "0",
                row.eligible == false and "0" or "1",
            }, "|") .. "\r\n")
        end
    end)
    pcall(function() writer:close() end)
    return success
end

local function scriptRow(scriptItem)
    local fullType = tostring(value(scriptItem, "getFullName", "") or "")
    if fullType == "" then fullType = tostring(value(scriptItem, "getFullType", "") or "") end
    if fullType == "" then return nil end
    local hidden = value(scriptItem, "isHidden", false) == true
    local obsolete = value(scriptItem, "getObsolete", false) == true
    return {
        fullType = fullType,
        moduleName = tostring(value(scriptItem, "getModuleName", "") or ""),
        displayCategory = tostring(value(scriptItem, "getDisplayCategory", "") or ""),
        itemType = tostring(value(scriptItem, "getItemType", "") or ""),
        tags = tostring(value(scriptItem, "getTags", "") or ""),
        hidden = hidden,
        obsolete = obsolete,
        eligible = not hidden and not obsolete,
    }
end

function Cache.buildStep(limit)
    local state = Cache.state
    if not state or state.status ~= "building" or not state.scripts then return 0 end
    local processed = 0
    while processed < limit and state.cursor < state.total do
        local row = scriptRow(collectionAt(state.scripts, state.cursor))
        if row then state.rows[#state.rows + 1] = row end
        state.cursor = state.cursor + 1
        processed = processed + 1
    end
    if state.cursor >= state.total then
        state.scripts = nil
        state.status = #state.rows > 0 and "ready" or "error"
        state.candidates = nil
        if state.status == "ready" then state.persisted = writePersisted(state) end
        if state.tickRegistered and Events and Events.OnTick then Events.OnTick.Remove(Cache.onTick) end
        state.tickRegistered = false
    end
    return processed
end

local function buildRate()
    local configured = GodSystemRuntimeConfig and GodSystemRuntimeConfig.get
        and GodSystemRuntimeConfig.get("LotteryItemCacheBuildRate", 100) or 100
    return math.max(1, math.min(10000, math.floor(number(configured, 100))))
end

function Cache.onTick()
    local state = Cache.state
    if not state then return end
    if state.status == "loading" and nowMs() >= (state.nextStartAt or 0) then
        Cache.ensureStarted(state.role)
        state = Cache.state
    end
    if not state or state.status ~= "building" then return end
    if not GodSystemScheduler or not GodSystemScheduler.due
        or not GodSystemScheduler.due("lottery.itemcache." .. tostring(state.role), 100, nowMs()) then return end
    local budget = math.max(1, math.floor(buildRate() / 10))
    local ok, err = pcall(Cache.buildStep, budget)
    if not ok then
        state.status = "error"
        state.error = tostring(err)
        state.scripts = nil
        if state.tickRegistered and Events and Events.OnTick then Events.OnTick.Remove(Cache.onTick) end
        state.tickRegistered = false
    end
end

function Cache.ensureStarted(role)
    role = role == "server" and "server" or "sp"
    local state = Cache.state
    if not state or state.role ~= role then state = reset(role) end
    if state.status == "ready" or state.status == "building" then return state.status == "ready", state.status end
    local manager = nil
    if getScriptManager then
        local ok, result = pcall(getScriptManager)
        if ok then manager = result end
    end
    local scripts = manager and value(manager, "getAllItems", nil) or nil
    local total = collectionSize(scripts)
    if not scripts or total <= 0 then
        state.status = "loading"
        state.nextStartAt = nowMs() + 1000
        state.error = "scriptManagerUnavailable"
        return false, "unavailable"
    end
    local currentFingerprint = fingerprint(total)
    local persistedRows = readPersisted(role, currentFingerprint, total)
    if persistedRows then
        state.status = "ready"
        state.rows = persistedRows
        state.total = total
        state.cursor = total
        state.fingerprint = currentFingerprint
        state.candidates = nil
        return true, "ready"
    end
    state.status = "building"
    state.scripts = scripts
    state.total = total
    state.cursor = 0
    state.rows = {}
    state.fingerprint = currentFingerprint
    state.candidates = nil
    state.error = nil
    return false, "preparing"
end

function Cache.install(role)
    role = role == "server" and "server" or "sp"
    local state = Cache.state
    if not state or state.role ~= role then state = reset(role) end
    state.nextStartAt = state.nextStartAt or 0
    if Events and Events.OnTick then
        Events.OnTick.Remove(Cache.onTick)
        Events.OnTick.Add(Cache.onTick)
        state.tickRegistered = true
    else
        Cache.ensureStarted(role)
    end
    return state
end

function Cache.status()
    local state = Cache.state or emptyState("sp")
    return {
        status = state.status,
        complete = state.status == "ready",
        building = state.status == "building",
        processed = state.cursor or 0,
        total = state.total or 0,
        cached = #(state.rows or {}),
        error = state.error,
    }
end

function Cache.rows()
    return (Cache.state and Cache.state.rows) or {}
end

function Cache.candidateRows(predicate)
    local state = Cache.state
    if not state or state.status ~= "ready" then return {} end
    if not state.candidates then
        state.candidates = {}
        for index = 1, #state.rows do
            local row = state.rows[index]
            if not predicate or predicate(row) then state.candidates[#state.candidates + 1] = row end
        end
    end
    return state.candidates
end

function Cache.evict(fullType)
    local state = Cache.state
    if not state or not state.candidates then return end
    for index = #state.candidates, 1, -1 do
        if state.candidates[index].fullType == fullType then table.remove(state.candidates, index) end
    end
end

return Cache
