require "GodSystem/Platform/Storage/Support"

GodSystemStoragePermissionsPlatform = GodSystemStoragePermissionsPlatform or {}

local Descriptor = GodSystemStoragePermissionsPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.permissions"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local counters = { checks = 0, denied = 0, failures = 0 }
    local public = {}

    local function objectPosition(object)
        if type(object) == "table"
            and object.x ~= nil and object.y ~= nil and object.z ~= nil
        then
            return {
                x = Support.number(object.x, nil),
                y = Support.number(object.y, nil),
                z = Support.integer(object.z, nil),
            }
        end
        local raw = type(object) == "table" and object.raw or object
        return Support.position(raw)
    end

    local function safehouseFor(network, object)
        local position = objectPosition(object)
        if not position then return nil end
        local safehouse = Support.safehouseAt(binding, position.x, position.y)
        if not safehouse then return nil end
        if tostring(Support.safehouseKey(safehouse) or "")
            ~= tostring(network and network.scopeKey or "")
        then
            return nil
        end
        return safehouse
    end

    function public.identity(actor)
        return Support.identity(actor, binding)
    end

    function public.isAdmin(actor)
        return Support.isAdmin(actor, binding)
    end

    function public.canUse(actor, network, object)
        counters.checks = counters.checks + 1
        if Support.isAdmin(actor, binding) then return true end
        if type(network) ~= "table" then
            counters.denied = counters.denied + 1
            return false, "networkMissing"
        end
        local identity = Support.identity(actor, binding)
        if tostring(network.scope or "") == "personal" then
            local allowed = tostring(network.owner or "") == identity
            if not allowed then counters.denied = counters.denied + 1 end
            return allowed, allowed and nil or "notAllowed"
        end
        local safehouse = safehouseFor(network, object)
        local allowed = safehouse
            and Support.safehouseAllowed(actor, safehouse, binding) or false
        if not allowed then counters.denied = counters.denied + 1 end
        return allowed, allowed and nil or "safehouseDenied"
    end

    function public.canManage(actor, network, object)
        counters.checks = counters.checks + 1
        if Support.isAdmin(actor, binding) then return true end
        if type(network) ~= "table" then
            counters.denied = counters.denied + 1
            return false, "networkMissing"
        end
        local identity = Support.identity(actor, binding)
        if tostring(network.scope or "") == "personal" then
            local allowed = tostring(network.owner or "") == identity
            if not allowed then counters.denied = counters.denied + 1 end
            return allowed, allowed and nil or "notAllowed"
        end
        local safehouse = safehouseFor(network, object)
        local owner = safehouse and tostring(
            Support.read(safehouse, { "getOwner" }, "") or "") or ""
        local allowed = safehouse ~= nil
            and (identity == owner
                or identity == tostring(network.owner or "")
                or Support.read(safehouse, { "isOwner" }, false, actor) == true)
        if not allowed then counters.denied = counters.denied + 1 end
        return allowed, allowed and nil or "manageDenied"
    end

    function public.withinRange(actor, object, maximumDistance)
        counters.checks = counters.checks + 1
        local actorPosition = Support.position(actor)
        local targetPosition = objectPosition(object)
        if not actorPosition or not targetPosition then
            counters.denied = counters.denied + 1
            return false, "positionMissing"
        end
        if Support.integer(actorPosition.z, -999)
            ~= Support.integer(targetPosition.z, -998)
        then
            counters.denied = counters.denied + 1
            return false, "differentFloor"
        end
        local dx = actorPosition.x - targetPosition.x
        local dy = actorPosition.y - targetPosition.y
        local limit = math.max(0, Support.number(maximumDistance, 0) or 0)
        local allowed = dx * dx + dy * dy <= limit * limit
        if not allowed then counters.denied = counters.denied + 1 end
        return allowed, allowed and nil or "tooFar"
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
