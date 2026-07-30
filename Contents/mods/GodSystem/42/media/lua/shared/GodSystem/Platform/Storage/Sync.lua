require "GodSystem/Platform/Storage/Support"

GodSystemStorageSyncPlatform = GodSystemStorageSyncPlatform or {}

local Descriptor = GodSystemStorageSyncPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.sync"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local counters = { objects = 0, adds = 0, removes = 0, states = 0, failures = 0 }
    local public = {}

    local function callback(name)
        if type(binding[name]) == "function" then return binding[name] end
        return Support.api(binding, name)
    end

    local function invoke(name, ...)
        local target = callback(name)
        if type(target) ~= "function" then return true end
        local called, value = pcall(target, ...)
        if not called or value == false then
            counters.failures = counters.failures + 1
            return false
        end
        return true
    end

    function public.object(object, request)
        local raw = type(object) == "table" and object.raw or object
        if not raw or type(raw.transmitModData) ~= "function" then
            counters.failures = counters.failures + 1
            return false, "objectSyncMissing"
        end
        local called, value = pcall(raw.transmitModData, raw)
        if not called or value == false then
            counters.failures = counters.failures + 1
            return false, "objectSyncFailed"
        end
        counters.objects = counters.objects + 1
        return true
    end

    function public.add(container, item, request)
        if not invoke("sendAddItemToContainer", container, item, request) then
            return false, "itemAddSyncFailed"
        end
        Support.write(container, { "setDrawDirty" }, true)
        counters.adds = counters.adds + 1
        return true
    end

    function public.remove(container, item, request)
        if not invoke("sendRemoveItemFromContainer", container, item, request) then
            return false, "itemRemoveSyncFailed"
        end
        Support.write(container, { "setDrawDirty" }, true)
        counters.removes = counters.removes + 1
        return true
    end

    function public.state(network, request)
        if not invoke("transmitStorageState", Support.copy(network), request) then
            return false, "stateSyncFailed"
        end
        counters.states = counters.states + 1
        return true
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
