require "GodSystem/Platform/Progression/Support"

GodSystemHomeWorldPlatform = GodSystemHomeWorldPlatform or {}

local Descriptor = GodSystemHomeWorldPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "home.world"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function zombiePosition(zombie)
    local x = Support.number(Support.read(zombie, { "getX" }, nil), nil)
    local y = Support.number(Support.read(zombie, { "getY" }, nil), nil)
    local z = Support.number(Support.read(zombie, { "getZ" }, 0), 0)
    return x and y and z and { x = x, y = y, z = z } or nil
end

local function inside(value, center, radius)
    local pos = zombiePosition(value)
    if not pos then return false end
    local dx, dy = pos.x - center.x, pos.y - center.y
    return pos.z == center.z and (dx * dx) + (dy * dy) <= radius * radius
end

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local counters = { plans = 0, executed = 0, removed = 0, failures = 0 }
    local public = {}

    local function loadedZombies()
        if type(binding.loadedZombies) == "function" then
            local ok, values = pcall(binding.loadedZombies)
            return ok and Support.values(values) or {}
        end
        if type(getCell) ~= "function" then return {} end
        local ok, cell = pcall(getCell)
        if not ok or not cell then return {} end
        return Support.values(Support.read(cell, { "getZombieList" }, nil))
    end

    function public.planClear(actor, center, radius, request)
        counters.plans = counters.plans + 1
        radius = Support.number(radius, nil, 0)
        center = type(center) == "table" and {
            x = Support.number(center.x, nil),
            y = Support.number(center.y, nil),
            z = Support.number(center.z, 0),
        } or nil
        if not center or center.x == nil or center.y == nil or radius == nil then
            return nil, "clearPositionInvalid"
        end
        if type(binding.planClear) == "function" then
            return binding.planClear(actor, center, radius, request)
        end
        local result = {}
        local values = loadedZombies()
        for index = 1, #values do
            local zombie = values[index]
            if Support.read(zombie, { "isDead" }, false) ~= true and inside(zombie, center, radius) then
                result[#result + 1] = zombie
            end
        end
        return { actor = actor, center = center, radius = radius, targets = result, count = #result }
    end

    function public.executeClear(actor, plan, request)
        if type(binding.executeClear) == "function" then
            return binding.executeClear(actor, plan, request)
        end
        if type(plan) ~= "table" or type(plan.targets) ~= "table"
            or type(plan.center) ~= "table" or not Support.finite(plan.radius) then
            return false, "clearPlanInvalid"
        end
        local targets = plan.targets
        if Support.integer(plan.count, nil, 0) ~= #targets then return false, "clearPlanChanged" end
        for index = 1, #targets do
            local zombie = targets[index]
            if not zombie or Support.read(zombie, { "isDead" }, false) == true
                or not inside(zombie, plan.center, plan.radius)
                or (type(zombie.removeFromWorld) ~= "function"
                    and type(zombie.removeFromSquare) ~= "function") then
                return false, "clearTargetChanged"
            end
        end
        local removed = 0
        for index = 1, #targets do
            local zombie, changed = targets[index], false
            if type(zombie.removeFromWorld) == "function" then
                changed = pcall(zombie.removeFromWorld, zombie) or changed
            end
            if type(zombie.removeFromSquare) == "function" then
                changed = pcall(zombie.removeFromSquare, zombie) or changed
            end
            if changed then removed = removed + 1 end
        end
        counters.executed = counters.executed + 1
        counters.removed = counters.removed + removed
        if removed ~= #targets then
            counters.failures = counters.failures + 1
            return false, removed
        end
        return true, removed
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
