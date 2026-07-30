require "GodSystem/Platform/Storage/Support"

GodSystemStorageClockPlatform = GodSystemStorageClockPlatform or {}

local Descriptor = GodSystemStorageClockPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.clock"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local binding = Support.binding(context)
    local counters = { reads = 0, failures = 0 }
    local public = {}
    function public.nowMs()
        counters.reads = counters.reads + 1
        return Support.nowMs(binding)
    end
    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
