require "GodSystem/Platform/Companion/Support"

GodSystemCompanionMutationPlatform = GodSystemCompanionMutationPlatform or {}

local Descriptor = GodSystemCompanionMutationPlatform
local Support = GodSystemCompanionPlatformSupport

Descriptor.id = "companion.mutation"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local instance = { started = false, damageCalls = 0, guardianCalls = 0, failures = 0 }

    local function damage(actor, target, amount)
        if type(binding.damage) == "function" then return binding.damage(actor, target, amount) end
        if not actor or not target or Support.dead(target) then return false, "targetInvalid" end
        amount = math.max(0, Support.number(amount, 0))
        local health = Support.number(Support.safeCall(target, "getHealth", nil), 0)
        if amount <= 0 or health <= 0 then return false, "damageInvalid" end
        local oldKills = Support.number(Support.safeCall(actor, "getZombieKills", 0), 0)
        pcall(function() target:setAttackedBy(actor) end)
        local applied = pcall(function() target:setHealth(math.max(0, health - amount)) end)
        if not applied then instance.failures = instance.failures + 1 return false, "damageFailed" end
        instance.damageCalls = instance.damageCalls + 1
        if Support.number(Support.safeCall(target, "getHealth", health), health) <= 0 then
            pcall(function() target:Kill(actor) end)
            if Support.number(Support.safeCall(actor, "getZombieKills", oldKills), oldKills) < oldKills + 1 then
                pcall(function() actor:setZombieKills(oldKills + 1) end)
            end
        end
        return true
    end

    local function knockDown(target)
        if type(binding.knockDown) == "function" then return binding.knockDown(target) end
        if not target or Support.dead(target) then return false, "targetInvalid" end
        local ok = pcall(function()
            target:setStaggerBack(true)
            target:setKnockedDown(true)
        end)
        if not ok then instance.failures = instance.failures + 1 return false, "guardianFailed" end
        instance.guardianCalls = instance.guardianCalls + 1
        return true
    end

    local function shock(target)
        if type(binding.shock) == "function" then return binding.shock(target) end
        if not target or Support.dead(target) then return false, "targetInvalid" end
        local onFloor = Support.safeCall(target, "isOnFloor", false) == true
        if onFloor then return true end
        local ok = pcall(function() target:setHitReaction("ShotBelly") end)
        if not ok then instance.failures = instance.failures + 1 return false, "shockFailed" end
        return true
    end

    local function setLight(handle, position, radius)
        if type(binding.setLight) == "function" then return binding.setLight(handle, position, radius) end
        if handle and handle.cell and handle.light then
            pcall(handle.cell.removeLamppost, handle.cell, handle.light)
        end
        local cell = type(getCell) == "function" and getCell() or nil
        if not cell or type(IsoLightSource) ~= "table" or type(IsoLightSource.new) ~= "function" then
            return nil, "lightUnavailable"
        end
        local light = IsoLightSource.new(
            math.floor(Support.number(position and position.x, 0)),
            math.floor(Support.number(position and position.y, 0)),
            math.floor(Support.number(position and position.z, 0) + 0.1),
            0.38, 0.68, 1.0, math.max(1, math.floor(Support.number(radius, 6))))
        cell:addLamppost(light)
        return { cell = cell, light = light }
    end

    local function removeLight(handle)
        if type(binding.removeLight) == "function" then return binding.removeLight(handle) end
        if handle and handle.cell and handle.light then
            local ok = pcall(handle.cell.removeLamppost, handle.cell, handle.light)
            return ok
        end
        return true
    end

    instance.public = {
        damage = damage,
        shock = shock,
        knockDown = knockDown,
        setLight = setLight,
        removeLight = removeLight,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "mutationFailed" or (self.started and "healthy" or "stopped"),
            data = {
                damageCalls = self.damageCalls,
                guardianCalls = self.guardianCalls,
                failures = self.failures,
            },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
