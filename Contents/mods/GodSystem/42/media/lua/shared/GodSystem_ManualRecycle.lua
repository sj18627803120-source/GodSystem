GodSystemManualRecycle = GodSystemManualRecycle or {}

function GodSystemManualRecycle.canRecycle(item)
    if not item or type(item.getFullType) ~= "function" then return false, "invalid" end
    local ok, fullType = pcall(function() return item:getFullType() end)
    if not ok or tostring(fullType or "") == "" then return false, "invalid" end
    return true, nil
end

function GodSystemManualRecycle.detachEquipped(player, item, bridge)
    if not player or not item or type(bridge) ~= "table" then return false end
    local ok = true
    if bridge:getPrimary(player) == item then ok = bridge:clearPrimary(player) == true and ok end
    if bridge:getSecondary(player) == item then ok = bridge:clearSecondary(player) == true and ok end
    if not bridge.hasWorn or bridge:hasWorn(player, item) then
        ok = bridge:removeWorn(player, item) == true and ok
    end
    if not bridge.hasAttached or bridge:hasAttached(player, item) then
        ok = bridge:removeAttached(player, item) == true and ok
    end
    return ok
end

function GodSystemManualRecycle.captureEquipped(player, item, bridge)
    return {
        primary = bridge:getPrimary(player) == item,
        secondary = bridge:getSecondary(player) == item,
        worn = bridge.hasWorn and bridge:hasWorn(player, item) == true or false,
        bodyLocation = bridge.wornLocation and bridge:wornLocation(item) or nil,
        attached = bridge.hasAttached and bridge:hasAttached(player, item) == true or false,
        attachedLocation = bridge.attachedLocation and bridge:attachedLocation(player, item) or nil,
    }
end

function GodSystemManualRecycle.restoreEquipped(player, item, state, bridge)
    state = type(state) == "table" and state or {}
    local ok = true
    if state.worn and state.bodyLocation and bridge.setWorn then
        ok = bridge:setWorn(player, state.bodyLocation, item) == true and ok
    end
    if state.attached and state.attachedLocation and bridge.setAttached then
        ok = bridge:setAttached(player, state.attachedLocation, item) == true and ok
    end
    if state.primary then ok = bridge:setPrimary(player, item) == true and ok end
    if state.secondary then ok = bridge:setSecondary(player, item) == true and ok end
    return ok
end

function GodSystemManualRecycle.defaultBridge()
    local bridge = {}
    function bridge:getPrimary(player)
        return GodSystemB42JavaCalls.value(player, "getPrimaryHandItem", nil)
    end
    function bridge:getSecondary(player)
        return GodSystemB42JavaCalls.value(player, "getSecondaryHandItem", nil)
    end
    function bridge:clearPrimary(player)
        return GodSystemB42JavaCalls.try(player, "setPrimaryHandItem", nil)
    end
    function bridge:clearSecondary(player)
        return GodSystemB42JavaCalls.try(player, "setSecondaryHandItem", nil)
    end
    function bridge:setPrimary(player, item)
        return GodSystemB42JavaCalls.try(player, "setPrimaryHandItem", item)
    end
    function bridge:setSecondary(player, item)
        return GodSystemB42JavaCalls.try(player, "setSecondaryHandItem", item)
    end
    function bridge:hasWorn(player, item)
        local worn = GodSystemB42JavaCalls.value(player, "getWornItems", nil)
        return GodSystemB42JavaCalls.value(worn, "contains", false, item) == true
    end
    function bridge:removeWorn(player, item)
        return GodSystemB42JavaCalls.try(player, "removeWornItem", item)
    end
    function bridge:wornLocation(item)
        return GodSystemB42JavaCalls.value(item, "getBodyLocation", nil)
    end
    function bridge:setWorn(player, location, item)
        return GodSystemB42JavaCalls.try(player, "setWornItem", location, item)
    end
    function bridge:hasAttached(player, item)
        local attached = GodSystemB42JavaCalls.value(player, "getAttachedItems", nil)
        return GodSystemB42JavaCalls.value(attached, "contains", false, item) == true
    end
    function bridge:removeAttached(player, item)
        return GodSystemB42JavaCalls.try(player, "removeAttachedItem", item)
    end
    function bridge:attachedLocation(player, item)
        local attached = GodSystemB42JavaCalls.value(player, "getAttachedItems", nil)
        return GodSystemB42JavaCalls.value(attached, "getLocation", nil, item)
    end
    function bridge:setAttached(player, location, item)
        return GodSystemB42JavaCalls.try(player, "setAttachedItem", location, item)
    end
    return bridge
end

return GodSystemManualRecycle
