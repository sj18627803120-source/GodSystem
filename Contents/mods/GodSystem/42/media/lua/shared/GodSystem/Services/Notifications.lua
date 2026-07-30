GodSystemNotificationsService = GodSystemNotificationsService or {}

local Descriptor = GodSystemNotificationsService

Descriptor.id = "notifications"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local state = context.state:get()
    local instance = {
        started = false,
        listeners = {},
    }

    state.published = math.max(0, math.floor(tonumber(state.published) or 0))

    local function publish(result, request)
        state.published = state.published + 1
        state.last = {
            ok = result and result.ok == true,
            code = tostring(result and result.code or ""),
            moduleId = tostring(result and result.moduleId or ""),
            operationId = result and result.operationId or nil,
        }
        for index = 1, #instance.listeners do
            instance.listeners[index](result, request)
        end
        return true
    end

    instance.public = {
        publish = publish,
        subscribe = function(listener)
            if type(listener) ~= "function" then return false end
            instance.listeners[#instance.listeners + 1] = listener
            return true
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        self.listeners = {}
        return true
    end

    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { published = state.published, listeners = #self.listeners },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
