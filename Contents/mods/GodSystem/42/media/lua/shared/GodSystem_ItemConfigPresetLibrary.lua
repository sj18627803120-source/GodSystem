require "GodSystem_ItemConfig"

GodSystemItemConfigPresetLibrary = GodSystemItemConfigPresetLibrary or {}
local Library = GodSystemItemConfigPresetLibrary
Library.filename = "GodSystem_ItemConfigPresets.txt"
Library.header = "GodSystemItemConfigPresets:1"
Library.loaded = false

local usesUTF16 = #"\228\184\173" == 1

local function hex(value)
    value = tostring(value or "")
    local out, index = {}, 1
    while index <= #value do
        local code = string.byte(value, index)
        if usesUTF16 and code >= 55296 and code <= 56319 then
            local low = string.byte(value, index + 1)
            if low and low >= 56320 and low <= 57343 then
                code = 65536 + (code - 55296) * 1024 + low - 56320
                index = index + 1
            else code = 65533 end
        elseif usesUTF16 and code >= 56320 and code <= 57343 then
            code = 65533
        end
        if not usesUTF16 or code < 128 then
            out[#out + 1] = string.format("%02X", code)
        elseif code < 2048 then
            out[#out + 1] = string.format("%02X%02X", 192 + math.floor(code / 64), 128 + code % 64)
        elseif code < 65536 then
            out[#out + 1] = string.format("%02X%02X%02X", 224 + math.floor(code / 4096),
                128 + math.floor(code / 64) % 64, 128 + code % 64)
        else
            out[#out + 1] = string.format("%02X%02X%02X%02X", 240 + math.floor(code / 262144),
                128 + math.floor(code / 4096) % 64, 128 + math.floor(code / 64) % 64, 128 + code % 64)
        end
        index = index + 1
    end
    return table.concat(out)
end

local function unhex(value)
    if type(value) ~= "string" or #value % 2 ~= 0 or value:find("[^0-9A-F]") then return nil end
    local bytes = {}
    for index = 1, #value, 2 do bytes[#bytes + 1] = tonumber(value:sub(index, index + 1), 16) end
    if not usesUTF16 then
        local out = {}
        for _, byte in ipairs(bytes) do out[#out + 1] = string.char(byte) end
        return table.concat(out)
    end
    local out, index = {}, 1
    while index <= #bytes do
        local first = bytes[index]
        local code, extra
        if first < 128 then code, extra = first, 0
        elseif first >= 194 and first <= 223 then code, extra = first - 192, 1
        elseif first >= 224 and first <= 239 then code, extra = first - 224, 2
        elseif first >= 240 and first <= 244 then code, extra = first - 240, 3
        else return nil end
        for step = 1, extra do
            local byte = bytes[index + step]
            if not byte or byte < 128 or byte > 191 then return nil end
            code = code * 64 + byte - 128
        end
        if (extra == 1 and code < 128) or (extra == 2 and code < 2048)
            or (extra == 3 and code < 65536) or (code >= 55296 and code <= 57343)
            or code > 1114111 then return nil end
        if code < 65536 then
            out[#out + 1] = string.char(code)
        else
            code = code - 65536
            out[#out + 1] = string.char(55296 + math.floor(code / 1024), 56320 + code % 1024)
        end
        index = index + extra + 1
    end
    return table.concat(out)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
Library.copy = copy

local function empty()
    return { order = {}, presets = {}, remarks = {}, deleted = {} }
end

local function insertPath(snapshot, path, kind, encoded)
    if type(path) ~= "string" or #path > 1024 then return false end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        local marker, value = part:sub(1, 1), part:sub(2)
        if marker == "s" then value = unhex(value)
        elseif marker == "n" then value = tonumber(value)
        else return false end
        if value == nil then return false end
        parts[#parts + 1] = value
    end
    if #parts == 0 or #parts > 12 then return false end
    local node = snapshot
    for i = 1, #parts - 1 do
        local key = parts[i]
        if node[key] == nil then node[key] = {} end
        if type(node[key]) ~= "table" then return false end
        node = node[key]
    end
    local value
    if kind == "t" then value = {}
    elseif kind == "s" then value = unhex(encoded)
    elseif kind == "n" then value = tonumber(encoded)
    elseif kind == "b" and (encoded == "0" or encoded == "1") then value = encoded == "1"
    else return false end
    if value == nil then return false end
    node[parts[#parts]] = value
    return true
end

local function readLibrary()
    if not getFileReader then return nil, "Unavailable" end
    local opened, reader = pcall(getFileReader, Library.filename, true)
    if not opened then return nil, "ReadFailed" end
    if not reader then return empty() end
    local result, lineCount, valid = empty(), 0, true
    local readOk = pcall(function()
        local header = reader:readLine()
        -- On the first lookup the native reader may leave a zero-byte file.
        if header == nil then return end
        if type(header) ~= "string" or header:gsub("\r$", "") ~= Library.header then valid = false; return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            lineCount = lineCount + 1
            if lineCount > 150000 or #line > 4096 then valid = false; break end
            line = line:gsub("\r$", "")
            local code, rest = line:match("^(%u)\t(.+)$")
            if code == "P" then
                local name = unhex(rest)
                if not name or not GodSystemItemConfig.sanitizePresetName(name) or result.presets[name]
                    or #result.order >= 32 then valid = false; break end
                result.order[#result.order + 1] = name
                result.presets[name] = {}
            elseif code == "D" then
                local name = unhex(rest)
                if not name then valid = false; break end
                result.deleted[name] = true
            elseif code == "N" then
                local nameCode, remarkCode = rest:match("^([^\t]+)\t(.*)$")
                local name, remark = unhex(nameCode), unhex(remarkCode)
                if not name or not GodSystemItemConfig.isPresetSlot(name) or not remark then valid = false; break end
                result.remarks[name] = GodSystemItemConfig.sanitizePresetRemark(remark)
            elseif code == "E" then
                local nameCode, path, kind, value = rest:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
                local name = unhex(nameCode)
                if not name or not result.presets[name]
                    or not insertPath(result.presets[name], path, kind, value) then valid = false; break end
            else valid = false; break end
        end
    end)
    pcall(function() reader:close() end)
    if not readOk or not valid then return nil, "ReadFailed" end
    return result
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

local function serialize(name, value, path, lines, depth)
    if depth > 12 or #lines > 150000 then return false end
    if type(value) == "table" then
        local keys = sortedKeys(value)
        if #keys == 0 then lines[#lines + 1] = "E\t" .. hex(name) .. "\t" .. path .. "\tt\t"; return true end
        for _, key in ipairs(keys) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then return false end
            local segment = keyType == "string" and ("s" .. hex(key)) or ("n" .. tostring(key))
            if not serialize(name, value[key], path .. "/" .. segment, lines, depth + 1) then return false end
        end
        return true
    end
    local kind, encoded = type(value), nil
    if kind == "string" then kind, encoded = "s", hex(value)
    elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        kind, encoded = "n", tostring(value)
    elseif kind == "boolean" then kind, encoded = "b", value and "1" or "0"
    else return false end
    lines[#lines + 1] = "E\t" .. hex(name) .. "\t" .. path .. "\t" .. kind .. "\t" .. encoded
    return true
end

local function writeLibrary(library)
    if not getFileWriter then return false end
    local lines = { Library.header }
    for _, name in ipairs(library.order) do
        lines[#lines + 1] = "P\t" .. hex(name)
        for _, key in ipairs(sortedKeys(library.presets[name] or {})) do
            if type(key) ~= "string" or not serialize(name, library.presets[name][key], "s" .. hex(key), lines, 1) then
                return false
            end
        end
    end
    for _, name in ipairs(GodSystemItemConfig.PRESET_SLOTS) do
        local remark = library.remarks[name]
        if remark and remark ~= "" then lines[#lines + 1] = "N\t" .. hex(name) .. "\t" .. hex(remark) end
    end
    for _, name in ipairs(sortedKeys(library.deleted)) do
        if library.deleted[name] then lines[#lines + 1] = "D\t" .. hex(name) end
    end
    local opened, writer = pcall(getFileWriter, Library.filename, true, false)
    if not opened or not writer then return false end
    local wrote = pcall(function()
        for _, line in ipairs(lines) do writer:write(line .. "\n") end
    end)
    local closed = pcall(function() writer:close() end)
    return wrote and closed
end

function Library.load(data)
    if not Library.loaded then
        local value, err = readLibrary()
        if not value then return false, err end
        Library.store, Library.loaded = value, true
    end
    local localStore = GodSystemItemConfig.ensurePresets(data)
    if not localStore then return false, "Invalid" end
    local global = Library.store
    local slots = { order = {}, presets = {}, remarks = {} }
    for _, name in ipairs(GodSystemItemConfig.PRESET_SLOTS) do
        if type(global.presets[name]) == "table" then
            slots.order[#slots.order + 1] = name
            slots.presets[name] = copy(global.presets[name])
        end
        slots.remarks[name] = global.remarks[name] or ""
    end
    local active = localStore.active
    data.itemConfigPresets = { order = slots.order, presets = slots.presets, remarks = slots.remarks,
        active = active ~= GodSystemItemConfig.PRESET_DEFAULT and slots.presets[active] and active
            or GodSystemItemConfig.PRESET_DEFAULT }
    GodSystemItemConfig.ensurePresets(data)
    return true
end

function Library.commit(data, deletedName)
    local store = GodSystemItemConfig.ensurePresets(data)
    if not store or not Library.loaded then return false end
    local proposed = { order = copy(store.order), presets = copy(store.presets),
        remarks = copy(store.remarks), deleted = copy(Library.store.deleted) }
    if deletedName then proposed.deleted[deletedName] = true
    elseif store.active ~= GodSystemItemConfig.PRESET_DEFAULT then proposed.deleted[store.active] = nil end
    if not writeLibrary(proposed) then return false end
    Library.store = proposed
    return true
end

function Library.resetForTests()
    Library.loaded, Library.store = false, nil
end

return Library
