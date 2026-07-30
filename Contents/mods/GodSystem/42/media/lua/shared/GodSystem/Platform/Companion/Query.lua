require "GodSystem/Platform/Companion/Support"

GodSystemCompanionQueryPlatform = GodSystemCompanionQueryPlatform or {}

local Descriptor = GodSystemCompanionQueryPlatform
local Support = GodSystemCompanionPlatformSupport

Descriptor.id = "companion.query"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function distanceSquared(left, right)
    local dx = Support.number(left.x, 0) - Support.number(right.x, 0)
    local dy = Support.number(left.y, 0) - Support.number(right.y, 0)
    return dx * dx + dy * dy
end

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local instance = { started = false, scans = 0, snapshots = 0, failures = 0 }

    local function currentActor()
        if type(binding.currentActor) == "function" then return binding.currentActor() end
        if type(getSpecificPlayer) == "function" then return getSpecificPlayer(0) end
        if type(getPlayer) == "function" then return getPlayer() end
        return nil
    end

    local function actorSnapshot(actor)
        if not actor then return nil, "actorMissing" end
        instance.snapshots = instance.snapshots + 1
        local position = Support.position(actor)
        position.dead = Support.dead(actor)
        position.inVehicle = Support.safeCall(actor, "getVehicle", nil) ~= nil
        position.paused = type(isGamePaused) == "function" and isGamePaused() == true or false
        return position
    end

    local function targetSnapshot(actor, target)
        if not actor or not target then return nil, "targetMissing" end
        instance.snapshots = instance.snapshots + 1
        local position = Support.position(target)
        position.dead = Support.dead(target)
        local visible = false
        if type(actor.CanSee) == "function" then
            local ok, value = pcall(actor.CanSee, actor, target)
            visible = ok and value == true
        end
        position.visible = visible
        return position
    end

    local function scanTargets(actor, radius, maximum)
        instance.scans = instance.scans + 1
        if type(binding.scanTargets) == "function" then
            return binding.scanTargets(actor, radius, maximum)
        end
        local result, seen = {}, {}
        local actorPosition = Support.position(actor)
        local cell = type(getCell) == "function" and getCell() or nil
        if not actorPosition or not cell then return result end
        radius = math.max(0, Support.number(radius, 0))
        maximum = maximum and math.max(1, math.floor(Support.number(maximum, 1))) or nil
        local z = math.floor(actorPosition.z + 0.1)
        local radiusSquared = radius * radius
        for x = math.floor(actorPosition.x - radius), math.floor(actorPosition.x + radius) do
            for y = math.floor(actorPosition.y - radius), math.floor(actorPosition.y + radius) do
                local square = cell:getGridSquare(x, y, z)
                local objects = square and Support.safeCall(square, "getMovingObjects", nil) or nil
                if objects and type(objects.size) == "function" and type(objects.get) == "function" then
                    for index = 0, objects:size() - 1 do
                        local target = objects:get(index)
                        local zombie = type(instanceof) == "function" and instanceof(target, "IsoZombie")
                        if zombie and not seen[target] and not Support.dead(target) then
                            seen[target] = true
                            local targetPosition = Support.position(target)
                            if math.floor(targetPosition.z + 0.1) == z
                                    and distanceSquared(actorPosition, targetPosition) <= radiusSquared then
                                result[#result + 1] = {
                                    target = target,
                                    distanceSquared = distanceSquared(actorPosition, targetPosition),
                                }
                                if maximum and #result >= maximum then return result end
                            end
                        end
                    end
                end
            end
        end
        table.sort(result, function(left, right) return left.distanceSquared < right.distanceSquared end)
        return result
    end

    instance.public = {
        currentActor = currentActor,
        ownerKey = Support.ownerKey,
        nowMs = Support.nowMs,
        actorSnapshot = actorSnapshot,
        targetSnapshot = targetSnapshot,
        scanTargets = scanTargets,
        randomBetween = function(minimum, maximum)
            minimum, maximum = Support.number(minimum, 0), Support.number(maximum, minimum)
            if type(binding.randomBetween) == "function" then
                return binding.randomBetween(minimum, maximum)
            end
            if type(ZombRandFloat) == "function" then return ZombRandFloat(minimum, maximum) end
            return minimum
        end,
        pointAvailable = function(actor, position, requireVisible)
            if type(binding.pointAvailable) == "function" then
                return binding.pointAvailable(actor, position, requireVisible)
            end
            local cell = type(getCell) == "function" and getCell() or nil
            if not actor or not cell or type(position) ~= "table" then return false end
            local actorPosition = Support.position(actor)
            if math.floor(Support.number(position.z, -99) + 0.1)
                    ~= math.floor(actorPosition.z + 0.1) then return false end
            local square = cell:getGridSquare(
                math.floor(Support.number(position.x, 0)),
                math.floor(Support.number(position.y, 0)),
                math.floor(Support.number(position.z, 0) + 0.1))
            if not square or Support.safeCall(square, "isSolid", false) == true
                    or Support.safeCall(square, "isSolidTrans", false) == true then return false end
            if not requireVisible then return true end
            local playerNum = Support.safeCall(actor, "getPlayerNum", 0)
            local value = Support.safeCall(square, "isCouldSee", nil, playerNum)
            if value == nil then value = Support.safeCall(square, "isSeen", false, playerNum) end
            return value == true
        end,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "queryFailed" or (self.started and "healthy" or "stopped"),
            data = { scans = self.scans, snapshots = self.snapshots, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
