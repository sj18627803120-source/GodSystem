require "GodSystem/Platform/Storage/Support"

GodSystemStorageStatePlatform = GodSystemStorageStatePlatform or {}

local Descriptor = GodSystemStorageStatePlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.state"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local scopedState = assert(
        context.state and type(context.state.get) == "function"
            and context.state or nil,
        "storage.state context.state missing")
    local root = scopedState:get()
    root.networks = type(root.networks) == "table" and root.networks or {}
    root.revisions = type(root.revisions) == "table" and root.revisions or {}
    root.scopeIndex = type(root.scopeIndex) == "table" and root.scopeIndex or {}
    root.actorIndex = type(root.actorIndex) == "table" and root.actorIndex or {}
    local counters = { loads = 0, creates = 0, commits = 0, conflicts = 0, failures = 0 }
    local public = {}

    local function findCurrent(actor)
        local actorKey = Support.identity(actor, binding)
        if type(binding.scopeKey) == "function" then
            local called, scopeKey = pcall(binding.scopeKey, actor)
            if called and scopeKey and root.scopeIndex[tostring(scopeKey)] then
                return root.scopeIndex[tostring(scopeKey)]
            end
        end
        return root.actorIndex[actorKey]
    end

    function public.load(actor, selector)
        counters.loads = counters.loads + 1
        selector = type(selector) == "table" and selector or {}
        local networkId = tostring(selector.networkId or "")
        if networkId == "" then networkId = tostring(findCurrent(actor) or "") end
        local value = networkId ~= "" and root.networks[networkId] or nil
        if type(value) ~= "table" then return nil, 0 end
        return Support.copy(value), Support.integer(root.revisions[networkId], 0, 0)
    end

    function public.create(actor, value)
        if type(value) ~= "table" or tostring(value.networkId or "") == "" then
            counters.failures = counters.failures + 1
            return nil, "stateInvalid"
        end
        local scopeKey = tostring(value.scopeKey or "")
        local existingId = scopeKey ~= "" and root.scopeIndex[scopeKey] or nil
        if existingId and type(root.networks[existingId]) == "table" then
            root.actorIndex[Support.identity(actor, binding)] = existingId
            return Support.copy(root.networks[existingId]),
                Support.integer(root.revisions[existingId], 0, 0)
        end
        local networkId = tostring(value.networkId)
        root.networks[networkId] = Support.copy(value)
        root.revisions[networkId] = 0
        if scopeKey ~= "" then root.scopeIndex[scopeKey] = networkId end
        root.actorIndex[Support.identity(actor, binding)] = networkId
        counters.creates = counters.creates + 1
        return Support.copy(root.networks[networkId]), 0
    end

    function public.commit(actor, value, expectedRevision)
        if type(value) ~= "table" or tostring(value.networkId or "") == "" then
            counters.failures = counters.failures + 1
            return false, "stateInvalid"
        end
        local networkId = tostring(value.networkId)
        local current = Support.integer(root.revisions[networkId], 0, 0)
        if Support.integer(expectedRevision, -1) ~= current then
            counters.conflicts = counters.conflicts + 1
            return false, "revisionConflict"
        end
        root.networks[networkId] = Support.copy(value)
        root.revisions[networkId] = current + 1
        local scopeKey = tostring(value.scopeKey or "")
        if scopeKey ~= "" then root.scopeIndex[scopeKey] = networkId end
        root.actorIndex[Support.identity(actor, binding)] = networkId
        counters.commits = counters.commits + 1
        return true, nil, current + 1
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
