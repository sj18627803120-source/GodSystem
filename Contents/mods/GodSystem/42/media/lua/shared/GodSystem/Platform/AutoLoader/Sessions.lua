require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderSessionsPlatform = GodSystemAutoLoaderSessionsPlatform or {}

local Descriptor = GodSystemAutoLoaderSessionsPlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "autoloader.sessions"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create()
    local values = {}
    local instance = {
        started = false,
        created = 0,
        removed = 0,
    }

    instance.public = {
        nowMs = Support.nowMs,
        get = function(sessionId)
            return values[tostring(sessionId or "")]
        end,
        put = function(session)
            if type(session) ~= "table" or tostring(session.sessionId or "") == "" then
                return false, "sessionInvalid"
            end
            if values[session.sessionId] == nil then instance.created = instance.created + 1 end
            values[session.sessionId] = session
            return true
        end,
        remove = function(sessionId)
            sessionId = tostring(sessionId or "")
            if values[sessionId] ~= nil then
                values[sessionId] = nil
                instance.removed = instance.removed + 1
            end
            return true
        end,
        cleanup = function(now)
            now = Support.integer(now, Support.nowMs(), 0)
            local count = 0
            for sessionId, session in pairs(values) do
                if now > Support.integer(session.expiresAt, 0, 0) then
                    values[sessionId] = nil
                    instance.removed = instance.removed + 1
                    count = count + 1
                end
            end
            return count
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        values = {}
        return true
    end

    function instance:health()
        local active = 0
        for _ in pairs(values) do active = active + 1 end
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { active = active, created = self.created, removed = self.removed },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
