require "GodSystem/Platform/Progression/Support"

GodSystemAdminRuntimePlatform = GodSystemAdminRuntimePlatform or {}

local Descriptor = GodSystemAdminRuntimePlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "admin.runtime"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local counters = { applies = 0, failures = 0 }
    local current = { settings = {}, itemOverrides = {}, revision = 0 }

    local function apply(settings, overrides, revision)
        local cleanSettings = Support.copy(type(settings) == "table" and settings or {})
        local cleanOverrides = Support.copy(type(overrides) == "table" and overrides or {})
        if type(binding.apply) == "function" then
            local ok, applied, code = pcall(binding.apply,
                Support.copy(cleanSettings), Support.copy(cleanOverrides), revision)
            if not ok or applied ~= true then
                counters.failures = counters.failures + 1
                return false, ok and (code or "runtimeApplyFailed") or "runtimePortError"
            end
        end
        current = {
            settings = Support.copy(cleanSettings),
            itemOverrides = Support.copy(cleanOverrides),
            revision = math.max(0, math.floor(tonumber(revision) or 0)),
        }
        counters.applies = counters.applies + 1
        return true
    end

    local function health()
        return counters.failures == 0, {
            revision = current.revision,
            applies = counters.applies,
            failures = counters.failures,
        }
    end

    local instance = Support.lifecycle(Descriptor.id, {
        apply = apply,
        snapshot = function() return Support.copy(current) end,
        health = health,
    }, counters)
    return instance
end

return Descriptor
