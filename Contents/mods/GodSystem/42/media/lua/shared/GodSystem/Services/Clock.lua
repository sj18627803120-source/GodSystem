GodSystemClockService = GodSystemClockService or {}

local Descriptor = GodSystemClockService

Descriptor.id = "clock"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function nowHours()
    if GameTime and type(GameTime.getInstance) == "function" then
        local gameTime = GameTime:getInstance()
        if gameTime and type(gameTime.getWorldAgeHours) == "function" then
            return tonumber(gameTime:getWorldAgeHours()) or 0
        end
    end
    return 0
end

function Descriptor.create()
    local instance = { started = false }
    instance.public = {
        nowHours = nowHours,
        currentDay = function() return math.floor(nowHours() / 24) end,
        nowMs = function()
            if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
            return math.floor((os and os.time and os.time() or 0) * 1000)
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { nowHours = nowHours() },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
