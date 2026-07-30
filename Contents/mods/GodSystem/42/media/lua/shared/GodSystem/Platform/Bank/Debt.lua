require "GodSystem/Platform/Bank/Support"

GodSystemBankDebtPlatform = GodSystemBankDebtPlatform or {}

local Descriptor = GodSystemBankDebtPlatform
local Support = GodSystemBankPlatformSupport

Descriptor.id = "bank.debt"
Descriptor.dependencies = { "bank.random" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies, context)
    context = context or {}
    local random = assert(dependencies["bank.random"], "bank.random dependency missing")
    local snapshot = type(context.configSnapshot) == "table" and context.configSnapshot or {}
    local config = type(snapshot.bank) == "table" and snapshot.bank or {}
    local minimum = Support.integer(config.loanZombieMinDistance, 20, 1)
    local maximum = Support.integer(config.loanZombieMaxDistance, 45, minimum)
    local instance = { started = false, requested = 0, spawned = 0 }
    instance.public = {}

    function instance.public:spawn(actor, count)
        count = Support.integer(count, 0, 0)
        if count <= 0 then return 0 end
        assert(type(addZombiesInOutfit) == "function", "addZombiesInOutfit unavailable")
        assert(actor and type(actor.getX) == "function"
            and type(actor.getY) == "function"
            and type(actor.getZ) == "function", "debt actor position unavailable")
        local x, y, z = actor:getX(), actor:getY(), actor:getZ()
        local spawned, tries = 0, 0
        instance.requested = instance.requested + count
        while spawned < count and tries < count * 8 do
            tries = tries + 1
            local distance = minimum + random:nextInt(maximum - minimum + 1) - 1
            local dx = random:nextInt(distance * 2 + 1) - distance - 1
            local sign = random:nextInt(2) == 1 and -1 or 1
            local dy = sign * math.max(minimum, distance - math.abs(dx))
            local batch = math.min(10, count - spawned)
            addZombiesInOutfit(math.floor(x + dx), math.floor(y + dy), z,
                batch, nil, nil)
            spawned = spawned + batch
        end
        instance.spawned = instance.spawned + spawned
        return spawned
    end

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { requested = self.requested, spawned = self.spawned },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
