require "GodSystem/Platform/Progression/Support"

GodSystemAdminSourcePlatform = GodSystemAdminSourcePlatform or {}

local Descriptor = GodSystemAdminSourcePlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "admin.source"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local counters = { reads = 0, failures = 0 }

    local function defaults()
        counters.reads = counters.reads + 1
        local result = {}
        local sandbox = type(binding.sandbox) == "table" and binding.sandbox
            or (SandboxVars and SandboxVars.GodSystem or nil)
        if type(sandbox) == "table" then
            for key, value in pairs(sandbox) do result[key] = Support.copy(value) end
        end
        if type(binding.defaults) == "table" then
            for key, value in pairs(binding.defaults) do result[key] = Support.copy(value) end
        end
        return result
    end

    local function staticOverrides()
        counters.reads = counters.reads + 1
        return Support.copy(type(binding.staticOverrides) == "table" and binding.staticOverrides or {})
    end

    return Support.lifecycle(Descriptor.id, {
        defaults = defaults,
        staticOverrides = staticOverrides,
    }, counters)
end

return Descriptor
