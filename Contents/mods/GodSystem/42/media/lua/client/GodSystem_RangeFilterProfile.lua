require "GodSystem_RangeFilter"

GodSystemRangeFilterProfile = GodSystemRangeFilterProfile or {}
local Profile = GodSystemRangeFilterProfile
local FILE_PREFIX = "GodSystem_RangeRecycleAllowlist_"
local FILE_SUFFIX = ".txt"
local SHARED_FILENAME = "GodSystem_RangeRecycleFilter.txt"

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function safeIdentity(value)
    value = tostring(value or ""):gsub("[^%w_%-]", "_")
    if value == "" then value = "local_0" end
    return value:sub(1, 96)
end

function Profile.identity(player)
    if player and player.getSteamID then
        local ok, steamId = pcall(function() return tostring(player:getSteamID() or "") end)
        steamId = ok and trim(steamId) or ""
        if steamId ~= "" and steamId ~= "0" then return "steam_" .. safeIdentity(steamId) end
    end
    if player and player.getUsername then
        local ok, username = pcall(function() return player:getUsername() end)
        if ok and tostring(username or "") ~= "" then return "user_" .. safeIdentity(username) end
    end
    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    return "local_" .. tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

function Profile.legacyFilename(player)
    return FILE_PREFIX .. safeIdentity(Profile.identity(player)) .. FILE_SUFFIX
end

function Profile.filename(_)
    return SHARED_FILENAME
end

local function loadFilename(filename)
    if not getFileReader then return GodSystemRangeFilter.normalize(nil), false, false end
    local ok, reader = pcall(getFileReader, filename, true)
    if not ok then return GodSystemRangeFilter.normalize(nil), false, false end
    if not reader then return GodSystemRangeFilter.normalize(nil), true, false end
    local values = {}
    local mode = "allowlist"
    local success = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            line = trim(line)
            if line:sub(1, 1) ~= "#" and line ~= "" then
                local storedMode = line:match("^mode=(.+)$")
                if storedMode then
                    mode = storedMode
                else
                    values[#values + 1] = line
                end
            end
        end
    end)
    pcall(function() reader:close() end)
    if not success then return GodSystemRangeFilter.normalize(nil), false, true end
    return GodSystemRangeFilter.normalize({ mode = mode, activeFullTypes = values }), true, true
end

function Profile.load(player)
    local shared, sharedOk, sharedFound = loadFilename(SHARED_FILENAME)
    if not sharedOk then return shared, false end
    if sharedFound then return shared, true end

    local legacy, legacyOk, legacyFound = loadFilename(Profile.legacyFilename(player))
    if not legacyOk then return legacy, false end
    if legacyFound then
        Profile.save(player, legacy)
        return legacy, true
    end
    return shared, true
end

function Profile.save(player, state)
    if not getFileWriter then return false end
    local normalized = GodSystemRangeFilter.normalize(state)
    local ok, writer = pcall(getFileWriter, Profile.filename(player), true, false)
    if not ok or not writer then return false end
    local success = pcall(function()
        writer:write("# GodSystem Range Recycle filter v2\r\n")
        writer:write("mode=" .. normalized.mode .. "\r\n")
        for i = 1, #normalized.activeFullTypes do
            writer:write(normalized.activeFullTypes[i] .. "\r\n")
        end
    end)
    local closeOk = pcall(function() writer:close() end)
    return success and closeOk
end

return Profile
