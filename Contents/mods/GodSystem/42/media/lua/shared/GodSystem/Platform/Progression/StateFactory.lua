require "GodSystem/Platform/Progression/Support"

GodSystemProgressionStateFactory = GodSystemProgressionStateFactory or {}

local Factory = GodSystemProgressionStateFactory
local Support = GodSystemProgressionPlatformSupport

function Factory.descriptor(moduleId, defaults)
    local Descriptor = {
        id = moduleId,
        dependencies = {},
        stateVersion = 1,
    }

    function Descriptor.create(_, context)
        context = context or {}
        local binding = type(context.binding) == "table" and context.binding or {}
        local stateScope = assert(context.state, moduleId .. " context.state missing")
        assert(type(stateScope.get) == "function", moduleId .. " context.state.get missing")
        local root = stateScope:get()
        root.players = type(root.players) == "table" and root.players or {}
        local counters = { loads = 0, saves = 0, failures = 0 }

        local function normalize(value)
            value = type(value) == "table" and value or Support.copy(defaults)
            if moduleId == "upgrades.state" then
                value.stats = nil
                value.upgrades = type(value.upgrades) == "table" and value.upgrades or {}
                value.tasks = type(value.tasks) == "table" and value.tasks or {}
                if value.autoRecyclerCapacityLevel == nil then value.autoRecyclerCapacityLevel = 1 end
                if value.autoRecyclerReductionLevel == nil then value.autoRecyclerReductionLevel = 1 end
                if value.autoRecyclerReliefLevel == nil then value.autoRecyclerReliefLevel = 1 end
            elseif moduleId == "home.state" then
                value.stats = type(value.stats) == "table" and value.stats or {}
                value.homeSystem = type(value.homeSystem) == "table" and value.homeSystem or {}
                value.homeSystem.tempSlots = type(value.homeSystem.tempSlots) == "table"
                    and value.homeSystem.tempSlots or {}
                value.homeSystem.safeZone = type(value.homeSystem.safeZone) == "table"
                    and value.homeSystem.safeZone or { level = 0, enabled = false }
            else
                value.stats = type(value.stats) == "table" and value.stats or {}
            end
            return value
        end

        local public = {}
        function public.load(actor)
            counters.loads = counters.loads + 1
            local key = Support.identity(actor, binding)
            if type(root.players[key]) ~= "table" then root.players[key] = normalize(nil) end
            return Support.copy(normalize(root.players[key]))
        end
        function public.save(actor, data)
            if type(data) ~= "table" then
                counters.failures = counters.failures + 1
                return false, "stateInvalid"
            end
            root.players[Support.identity(actor, binding)] = Support.copy(normalize(data))
            counters.saves = counters.saves + 1
            return true
        end
        return Support.lifecycle(moduleId, public, counters)
    end

    return Descriptor
end

return Factory
