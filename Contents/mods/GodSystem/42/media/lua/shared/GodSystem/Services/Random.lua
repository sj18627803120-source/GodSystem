GodSystemRandomService = GodSystemRandomService or {}

local Descriptor = GodSystemRandomService

Descriptor.id = "random"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create()
    local instance = { started = false, calls = 0 }
    local function nextInt(minimum, maximum)
        minimum = math.floor(tonumber(minimum) or 0)
        maximum = math.floor(tonumber(maximum) or minimum)
        if maximum < minimum then minimum, maximum = maximum, minimum end
        instance.calls = instance.calls + 1
        if type(ZombRand) == "function" then
            return minimum + ZombRand(maximum - minimum + 1)
        end
        return math.random(minimum, maximum)
    end
    instance.public = { nextInt = nextInt }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { calls = self.calls },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
