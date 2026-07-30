GodSystemCompanionPlatformSupport = GodSystemCompanionPlatformSupport or {}

local Support = GodSystemCompanionPlatformSupport

function Support.safeCall(target, methodName, fallback, ...)
    if not target or type(target[methodName]) ~= "function" then return fallback end
    local ok, value = pcall(target[methodName], target, ...)
    if ok then return value end
    return fallback
end

function Support.number(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return tonumber(fallback) or 0
    end
    return value
end

function Support.position(value)
    if not value then return nil end
    return {
        x = Support.number(Support.safeCall(value, "getX", nil), 0),
        y = Support.number(Support.safeCall(value, "getY", nil), 0),
        z = Support.number(Support.safeCall(value, "getZ", nil), 0),
    }
end

function Support.dead(value)
    if not value then return true end
    if Support.safeCall(value, "isDead", false) == true then return true end
    local alive = Support.safeCall(value, "isAlive", nil)
    return alive == false
end

function Support.ownerKey(actor)
    local username = Support.safeCall(actor, "getUsername", nil)
    if username ~= nil and tostring(username) ~= "" then return tostring(username) end
    local onlineId = Support.safeCall(actor, "getOnlineID", nil)
    if onlineId ~= nil then return tostring(onlineId) end
    local playerNum = Support.safeCall(actor, "getPlayerNum", 0)
    return "player:" .. tostring(playerNum)
end

function Support.nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return math.floor(tonumber(value)) end
    end
    return math.floor((os and os.time and os.time() or 0) * 1000)
end

return Support
