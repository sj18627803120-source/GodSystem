GodSystemCompanionEventsPlatform = GodSystemCompanionEventsPlatform or {}

local Descriptor = GodSystemCompanionEventsPlatform

Descriptor.id = "companion.events"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local instance = { started = false, bound = false, handlers = 0, failures = 0 }

    local function subscribe(name, handler)
        if type(handler) ~= "function" then return true end
        if not context.events or type(context.events.subscribe) ~= "function" then
            instance.failures = instance.failures + 1
            return false, "eventGatewayMissing"
        end
        local ok, code = context.events:subscribe(name, handler)
        if not ok then instance.failures = instance.failures + 1 return false, code end
        instance.handlers = instance.handlers + 1
        return true
    end

    instance.public = {
        bind = function(handlers)
            if instance.bound then return true end
            handlers = type(handlers) == "table" and handlers or {}
            local rows = {
                { "OnGameStart", handlers.gameStart },
                { "OnPlayerUpdate", handlers.playerUpdate },
                { "OnPlayerDeath", handlers.playerDeath },
                { "OnPreUIDraw", handlers.render },
            }
            for index = 1, #rows do
                local ok, code = subscribe(rows[index][1], rows[index][2])
                if not ok then return false, code end
            end
            instance.bound = true
            return true
        end,
        unbind = function()
            if context.events and type(context.events.unsubscribe) == "function" then
                context.events:unsubscribe()
            end
            instance.bound = false
            return true
        end,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false self.bound = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "eventBindingFailed" or (self.started and "healthy" or "stopped"),
            data = { bound = self.bound, handlers = self.handlers, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
