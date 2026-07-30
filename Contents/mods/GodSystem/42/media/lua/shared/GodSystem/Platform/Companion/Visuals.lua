GodSystemCompanionVisualsPlatform = GodSystemCompanionVisualsPlatform or {}

local Descriptor = GodSystemCompanionVisualsPlatform

Descriptor.id = "companion.visuals"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local instance = { started = false, emitted = 0, rendered = 0, failures = 0 }

    local function invoke(name, ...)
        local callback = binding[name]
        if type(callback) ~= "function" then return true end
        local ok, value = pcall(callback, ...)
        if not ok then instance.failures = instance.failures + 1 return false, value end
        return value ~= false, value
    end

    instance.public = {
        emit = function(kind, runtime, data, actor, target)
            instance.emitted = instance.emitted + 1
            return invoke("emit", kind, runtime, data, actor, target)
        end,
        reset = function(runtime)
            return invoke("reset", runtime)
        end,
        render = function(runtime, data, actor)
            instance.rendered = instance.rendered + 1
            return invoke("render", runtime, data, actor)
        end,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "visualFailed" or (self.started and "healthy" or "stopped"),
            data = { emitted = self.emitted, rendered = self.rendered, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
