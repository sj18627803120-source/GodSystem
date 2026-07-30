require "GodSystem/Platform/Terminal/Support"

GodSystemTerminalStatePlatform = GodSystemTerminalStatePlatform or {}

local Descriptor = GodSystemTerminalStatePlatform
local Support = GodSystemTerminalPlatformSupport

Descriptor.id = "terminal.state"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local scopedState = assert(
        context.state and type(context.state.get) == "function"
            and context.state or nil,
        "terminal.state context.state missing")
    local root = scopedState:get()
    root.players = type(root.players) == "table" and root.players or {}
    local counters = { loads = 0, commits = 0, conflicts = 0, failures = 0 }
    local public = {}

    local function row(actor)
        local key = Support.identity(actor, binding)
        local value = root.players[key]
        if type(value) ~= "table" then
            value = {
                revision = 0,
                data = {
                    version = 1,
                    claimedOnce = false,
                    capacityLevel = 1,
                    reductionLevel = 1,
                    reliefLevel = 0,
                },
            }
            root.players[key] = value
        end
        value.revision = Support.integer(value.revision, 0, 0)
        value.data = type(value.data) == "table" and value.data or {}
        return value
    end

    function public.load(actor)
        counters.loads = counters.loads + 1
        local value = row(actor)
        return Support.copy(value.data), value.revision
    end

    function public.commit(actor, data, expectedRevision)
        if type(data) ~= "table" then
            counters.failures = counters.failures + 1
            return false, "stateInvalid"
        end
        local value = row(actor)
        if Support.integer(expectedRevision, -1) ~= value.revision then
            counters.conflicts = counters.conflicts + 1
            return false, "revisionConflict"
        end
        value.data = Support.copy(data)
        value.revision = value.revision + 1
        counters.commits = counters.commits + 1
        return true, nil, value.revision
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
