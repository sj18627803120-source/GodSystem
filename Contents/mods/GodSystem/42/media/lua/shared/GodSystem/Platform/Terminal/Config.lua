require "GodSystem/Platform/Terminal/Support"

GodSystemTerminalConfigPlatform = GodSystemTerminalConfigPlatform or {}

local Descriptor = GodSystemTerminalConfigPlatform
local Support = GodSystemTerminalPlatformSupport

Descriptor.id = "terminal.config"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local source = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local counters = { snapshots = 0, failures = 0 }
    local public = {}

    function public.snapshot()
        counters.snapshots = counters.snapshots + 1
        return {
            enabled = source.EnableAutoRecycler ~= false
                and source.EnableSystemTerminal ~= false,
            terminalFullType = tostring(source.AutoRecyclerFullType
                or "GodSystem.SystemSpaceTerminal"),
            reliefFullType = tostring(source.TerminalReliefFullType
                or "GodSystem.SystemTerminalRelief"),
            markerKey = tostring(source.AutoRecyclerMarkerKey
                or "GodSystemAutoRecycler"),
            capacityLevelKey = tostring(source.AutoRecyclerCapacityLevelKey
                or "GodSystemTerminalCapacityLevel"),
            reductionLevelKey = tostring(source.AutoRecyclerReductionLevelKey
                or "GodSystemTerminalReductionLevel"),
            reliefLevelKey = tostring(source.TerminalReliefLevelKey
                or "GodSystemTerminalReliefLevel"),
        }
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
