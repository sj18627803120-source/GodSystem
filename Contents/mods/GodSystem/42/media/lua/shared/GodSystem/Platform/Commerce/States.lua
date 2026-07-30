require "GodSystem/Platform/Commerce/Support"

local Support = GodSystemCommercePlatformSupport

local function descriptor(moduleId, defaults)
    local value = {
        id = moduleId,
        dependencies = { "commerce.actor.identity" },
        stateVersion = 1,
    }

    function value.create(dependencies, context)
        local identity = assert(dependencies["commerce.actor.identity"],
            "commerce.actor.identity dependency missing")
        local root = assert(context and context.state, moduleId .. " context.state missing"):get()
        root.players = type(root.players) == "table" and root.players or {}
        local instance = { started = false, loads = 0, saves = 0 }

        local function key(actor) return identity.key(actor) end
        local function normalized(data)
            data = type(data) == "table" and data or Support.copy(defaults)
            data.stats = type(data.stats) == "table" and data.stats or {}
            if moduleId == "tasks.state" then
                data.tasks = type(data.tasks) == "table" and data.tasks or {}
            elseif moduleId == "shop.state" then
                data.unlockedShopItems = type(data.unlockedShopItems) == "table"
                    and data.unlockedShopItems or {}
            end
            return data
        end

        instance.public = {
            load = function(actor)
                instance.loads = instance.loads + 1
                local actorKey = key(actor)
                if type(root.players[actorKey]) ~= "table" then
                    root.players[actorKey] = normalized(nil)
                end
                return Support.copy(normalized(root.players[actorKey]))
            end,
            save = function(actor, data)
                if type(data) ~= "table" then return false, "stateInvalid" end
                root.players[key(actor)] = Support.copy(normalized(data))
                instance.saves = instance.saves + 1
                return true
            end,
        }
        function instance:start() self.started = true return true end
        function instance:stop() self.started = false return true end
        function instance:health()
            return {
                ok = self.started,
                code = self.started and "healthy" or "stopped",
                data = { loads = self.loads, saves = self.saves },
                moduleId = moduleId,
            }
        end
        return instance
    end
    return value
end

GodSystemTasksStatePlatform = GodSystemTasksStatePlatform
    or descriptor("tasks.state", { tasks = {}, stats = {} })
GodSystemShopStatePlatform = GodSystemShopStatePlatform
    or descriptor("shop.state", { unlockedShopItems = {}, stats = {} })
GodSystemRecycleStatePlatform = GodSystemRecycleStatePlatform
    or descriptor("recycle.state", { stats = {} })

return {
    tasks = GodSystemTasksStatePlatform,
    shop = GodSystemShopStatePlatform,
    recycle = GodSystemRecycleStatePlatform,
}
