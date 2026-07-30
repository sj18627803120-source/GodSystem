GodSystemBankFeaturesPlatform = GodSystemBankFeaturesPlatform or {}

local Descriptor = GodSystemBankFeaturesPlatform

Descriptor.id = "bank.features"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local snapshot = type(context.configSnapshot) == "table" and context.configSnapshot or {}
    local configured = type(snapshot.features) == "table" and snapshot.features or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local instance = { started = false, reads = 0 }
    instance.public = {}

    function instance.public:isEnabled(key)
        instance.reads = instance.reads + 1
        key = tostring(key or "")
        if type(binding.values) == "table" and binding.values[key] ~= nil then
            return binding.values[key] ~= false
        end
        if type(binding.read) == "function" then
            local value = binding.read(key)
            if value ~= nil then return value ~= false end
        end
        if configured[key] ~= nil then return configured[key] ~= false end
        local sandbox = type(SandboxVars) == "table" and SandboxVars.GodSystem or nil
        if type(sandbox) == "table" and sandbox[key] ~= nil then
            return sandbox[key] ~= false
        end
        return true
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
