require "GodSystem/Platform/Progression/Support"

GodSystemHomePositionPlatform = GodSystemHomePositionPlatform or {}

local Descriptor = GodSystemHomePositionPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "home.position"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function position(value)
    if type(value) ~= "table" then return nil end
    local x = Support.number(value.x, nil)
    local y = Support.number(value.y, nil)
    local z = Support.number(value.z, 0)
    if x == nil or y == nil or z == nil then return nil end
    return { x = x, y = y, z = z, source = value.source }
end

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local counters = { validations = 0, teleports = 0, restores = 0, failures = 0 }
    local public = {}

    local function squareAt(target)
        if type(binding.squareAt) == "function" then
            local ok, square = pcall(binding.squareAt, target)
            return ok and square or nil
        end
        if type(getCell) ~= "function" then return nil end
        local okCell, cell = pcall(getCell)
        if not okCell or not cell or type(cell.getGridSquare) ~= "function" then return nil end
        local ok, square = pcall(cell.getGridSquare, cell,
            math.floor(target.x), math.floor(target.y), math.floor(target.z))
        return ok and square or nil
    end

    local function squareSafe(square)
        if not square then return nil end
        if Support.read(square, { "isSolid" }, false) == true then return false end
        if Support.read(square, { "isSolidTrans" }, false) == true then return false end
        local floor = Support.read(square, { "TreatAsSolidFloor" }, nil)
        if floor == false then return false end
        return true
    end

    function public.blockedReason(actor, request)
        if type(binding.blockedReason) == "function" then return binding.blockedReason(actor, request) end
        if not actor then return "playerMissing" end
        if Support.read(actor, { "getVehicle" }, nil) ~= nil then return "insideVehicle" end
        if Support.read(actor, { "isDead" }, false) == true then return "playerDead" end
        return nil
    end

    function public.current(actor)
        if type(binding.current) == "function" then return position(binding.current(actor)) end
        return position({
            x = Support.read(actor, { "getX" }, nil),
            y = Support.read(actor, { "getY" }, nil),
            z = Support.read(actor, { "getZ" }, 0),
        })
    end

    function public.validate(actor, target, request)
        counters.validations = counters.validations + 1
        target = position(target)
        if not target then return nil, "positionInvalid" end
        if type(binding.validate) == "function" then
            local safe, code = binding.validate(actor, target, request)
            return position(safe), code
        end
        local safe = squareSafe(squareAt(target))
        if safe == true or safe == nil then return target end
        for radius = 1, 4 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if math.abs(dx) == radius or math.abs(dy) == radius then
                        local candidate = {
                            x = math.floor(target.x) + dx + 0.5,
                            y = math.floor(target.y) + dy + 0.5,
                            z = target.z,
                        }
                        if squareSafe(squareAt(candidate)) == true then return candidate end
                    end
                end
            end
        end
        return nil, "positionUnsafe"
    end

    local function nativeMove(actor, target)
        if not actor or not Support.write(actor, { "setX" }, target.x)
            or not Support.write(actor, { "setY" }, target.y)
            or not Support.write(actor, { "setZ" }, target.z) then return false end
        if type(actor.setLastX) == "function" then Support.write(actor, { "setLastX" }, target.x) end
        if type(actor.setLastY) == "function" then Support.write(actor, { "setLastY" }, target.y) end
        if type(actor.setLastZ) == "function" then Support.write(actor, { "setLastZ" }, target.z) end
        return true
    end

    function public.teleport(actor, target, request)
        target = position(target)
        local before = public.current(actor)
        if not target or not before then return false, "positionInvalid" end
        local moved
        if type(binding.teleport) == "function" then
            moved = binding.teleport(actor, target, request)
        else
            moved = nativeMove(actor, target)
        end
        if moved ~= true then
            counters.failures = counters.failures + 1
            return false, "teleportFailed"
        end
        local after = public.current(actor)
        if not after or math.abs(after.x - target.x) > 0.01 or math.abs(after.y - target.y) > 0.01
            or math.abs(after.z - target.z) > 0.01 then
            counters.failures = counters.failures + 1
            return false, "teleportVerificationFailed"
        end
        counters.teleports = counters.teleports + 1
        return true, { actor = actor, before = before, after = after }
    end

    function public.restore(actor, receipt, request)
        local before = type(receipt) == "table" and position(receipt.before) or nil
        if not before then return false, "receiptInvalid" end
        local restored
        if type(binding.restore) == "function" then
            restored = binding.restore(actor, receipt, request)
        else
            restored = nativeMove(actor, before)
        end
        if restored == true then
            counters.restores = counters.restores + 1
            return true
        end
        counters.failures = counters.failures + 1
        return false, "restoreFailed"
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
