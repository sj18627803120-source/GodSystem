GodSystemBankClockPlatform = GodSystemBankClockPlatform or {}

local Descriptor = GodSystemBankClockPlatform

Descriptor.id = "bank.clock"
Descriptor.dependencies = { "clock" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local clock = assert(dependencies.clock, "clock dependency missing")
    local instance = { started = false, reads = 0 }
    instance.public = {}
    function instance.public:nowHours()
        instance.reads = instance.reads + 1
        return clock.nowHours()
    end
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { reads = self.reads },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
