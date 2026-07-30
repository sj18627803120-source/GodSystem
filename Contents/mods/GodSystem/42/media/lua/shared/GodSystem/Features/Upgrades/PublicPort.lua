GodSystemUpgradesPublicPort = GodSystemUpgradesPublicPort or {}

local Descriptor = GodSystemUpgradesPublicPort

Descriptor.id = "upgrades.read"
Descriptor.dependencies = { "feature.upgrades" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local upgrades = assert(dependencies["feature.upgrades"], "feature.upgrades dependency missing")
    assert(type(upgrades.summary) == "function", "feature.upgrades summary missing")
    local instance = { started = false, reads = 0, public = {} }

    function instance.public.limits(actor, request)
        instance.reads = instance.reads + 1
        local result = upgrades.summary(actor, request)
        if type(result) ~= "table" or result.ok ~= true then
            return nil, type(result) == "table" and result.code or "upgradeStateUnavailable"
        end
        return {
            maxActiveTasks = result.data.maxActiveTasks,
            dailyTaskCount = result.data.dailyTaskCount,
        }
    end

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { reads = self.reads },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
