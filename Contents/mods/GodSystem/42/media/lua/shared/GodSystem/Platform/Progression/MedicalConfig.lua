require "GodSystem/Platform/Progression/Support"

GodSystemMedicalConfigPlatform = GodSystemMedicalConfigPlatform or {}

local Descriptor = GodSystemMedicalConfigPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "medical.config"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local DEFAULTS = {
    MedicalCheckInfectionCost = 50,
    MedicalHealInjuriesCost = 5000,
    MedicalCureInfectionCost = 2000,
}

function Descriptor.create(_, context)
    local config = Support.config(context, DEFAULTS)
    local counters = { quotes = 0, rejected = 0 }
    local mapping = {
        checkInfection = "MedicalCheckInfectionCost",
        healInjuries = "MedicalHealInjuriesCost",
        cureInfection = "MedicalCureInfectionCost",
    }
    local public = {}
    function public.cost(action)
        counters.quotes = counters.quotes + 1
        local key = mapping[tostring(action or "")]
        local value = key and Support.integer(config[key], nil, 0) or nil
        if value == nil then counters.rejected = counters.rejected + 1 end
        return value
    end
    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
