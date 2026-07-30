GodSystemBankRandomPlatform = GodSystemBankRandomPlatform or {}

local Descriptor = GodSystemBankRandomPlatform

Descriptor.id = "bank.random"
Descriptor.dependencies = { "random" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local random = assert(dependencies.random, "random dependency missing")
    local instance = { started = false, rolls = 0 }
    instance.public = {}
    function instance.public:nextInt(maximum)
        maximum = math.floor(tonumber(maximum) or 0)
        if maximum <= 0 then return nil end
        instance.rolls = instance.rolls + 1
        return random.nextInt(1, maximum)
    end
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { rolls = self.rolls },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
