require "GodSystem_Equipment"
require "GodSystem_B42JavaCalls"

GodSystemEquipmentItems = GodSystemEquipmentItems or {}
local I, E, Bridge = GodSystemEquipmentItems, GodSystemEquipment, GodSystemB42JavaCalls
I.metrics=I.metrics or {}
-- Explicit colon calls are required for Kahlua Java userdata.
local callers = {
    isRanged = function(o) return o:isRanged() end,
    getOnBreak = function(o) return o:getOnBreak() end,
    setContainsClip = function(o,v) return o:setContainsClip(v) end,
    setRoundChambered = function(o,v) return o:setRoundChambered(v) end,
    setSpentRoundCount = function(o,v) return o:setSpentRoundCount(v) end,
    setSpentRoundChambered = function(o,v) return o:setSpentRoundChambered(v) end,
    isContainsClip = function(o) return o:isContainsClip() end,
    isRoundChambered = function(o) return o:isRoundChambered() end,
    getSpentRoundCount = function(o) return o:getSpentRoundCount() end,
    isSpentRoundChambered = function(o) return o:isSpentRoundChambered() end,
}
function I.call(object, name, ...)
    if not object then return false end
    if callers[name] then return pcall(callers[name], object, ...) end
    return Bridge.try(object, name, ...)
end
function I.value(object, name, fallback, ...)
    local ok, v = I.call(object, name, ...)
    if ok and v ~= nil then return v end
    return fallback
end
function I.id(item)
    local id = I.value(item, "getID")
    return id ~= nil and tostring(id) or nil
end
function I.name(item)
    return I.value(item, "getName", I.value(item, "getDisplayName", I.value(item, "getFullType", "")))
end
function I.customName(item)
    return I.value(item, "isCustomName", false) == true
end
function I.defaultName(item)
    local script = I.value(item, "getScriptItem")
    local key = script and I.value(script, "getDisplayName") or nil
    if type(key) == "string" and key ~= "" and Translator and Translator.getText then
        local ok, value = pcall(Translator.getText, key)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return I.value(item, "getDisplayName", I.value(item, "getFullType", ""))
end
function I.setName(item, name, custom)
    local setName = I.call(item, "setName", name)
    local setCustom = I.call(item, "setCustomName", custom == true)
    return setName and setCustom and I.name(item) == name and I.customName(item) == (custom == true)
end
function I.marker(item)
    local md = I.value(item, "getModData")
    return md and type(md[E.ItemKey]) == "table" and md[E.ItemKey] or nil
end
function I.isWeapon(item)
    if not item or not instanceof or not instanceof(item, "HandWeapon") then return false end
    return I.value(item, "getFullType", "") ~= "Base.BareHands"
end
function I.held(player, item)
    return item and (I.value(player, "getPrimaryHandItem") == item or I.value(player, "getSecondaryHandItem") == item)
end
function I.owned(player, item)
    local root, container, seen = I.value(player, "getInventory"), I.value(item, "getContainer"), {}
    while container and not seen[container] do
        if container == root then return true end
        seen[container] = true
        local bag = I.value(container, "getContainingItem")
        container = bag and I.value(bag, "getContainer") or nil
    end
    return false
end
-- 42.20_3.6 deliberately has no per-instance combat-stat helpers here.
-- Equipment effects must not read, derive or overwrite weapon damage, speed,
-- wear chance, accuracy or recoil values owned by vanilla/other mods.
function I.near(a,b)
    return E.number(a) and E.number(b) and math.abs(a-b)<=math.max(0.00001,math.abs(b)*0.00001)
end
function I.durability(item)
    local d = { condition = E.number(I.value(item, "getCondition")), conditionMax = E.number(I.value(item, "getConditionMax")),
        hasHead = I.value(item, "hasHeadCondition", false) == true,
        hasSharpness = I.value(item, "hasSharpness", false) == true }
    -- Binding records only the identity and recovery fields used by this
    -- system. Combat statistics remain deliberately outside this check.
    if not E.integer(d.conditionMax,1,127) or not E.integer(d.condition,0,d.conditionMax) then return nil, "EquipmentBindMissingBody" end
    if d.hasHead then
        d.headCondition = E.number(I.value(item, "getHeadCondition"))
        d.headConditionMax = E.number(I.value(item, "getHeadConditionMax"))
        if not E.integer(d.headConditionMax,1,E.MaxMoney) or not E.integer(d.headCondition,0,d.headConditionMax) then return nil, "EquipmentBindMissingHead" end
    end
    if d.hasSharpness then
        d.sharpness = E.number(I.value(item, "getSharpness"))
        d.maxSharpness = E.number(I.value(item, "getMaxSharpness"))
        if not d.sharpness or d.sharpness < 0 or d.sharpness > 1 or not d.maxSharpness then return nil, "EquipmentBindMissingSharpness" end
    end
    return d
end
function I.full(d)
    return d and E.number(d.condition) and E.number(d.conditionMax) and d.condition >= d.conditionMax and (not d.hasHead or (E.number(d.headCondition) and E.number(d.headConditionMax) and d.headCondition >= d.headConditionMax))
        and (not d.hasSharpness or (E.number(d.sharpness) and d.sharpness >= 0.99999))
end
function I.canRepair(item,d)
    d=d or I.durability(item)
    if not d then return false end
    if d.condition<=0 or (d.hasHead and d.headCondition<=0) then
        local ok,onBreak=I.call(item,"getOnBreak")
        -- Reverting a failed repair must not run a destructive OnBreak callback a second time.
        return ok and (onBreak==nil or onBreak=="")
    end
    return true
end
function I.setDurability(item, d, recover, repair)
    local current = I.durability(item)
    if not d or not current or current.hasHead ~= d.hasHead or current.hasSharpness ~= d.hasSharpness then return false end
    -- Never restore an obsolete ConditionMax or manufacture a zero-condition composite.
    local condition = repair and current.conditionMax or math.min(current.conditionMax, d.condition)
    if recover then condition = math.max(1, condition) end
    if not I.near(current.condition, condition) and not I.call(item, "setCondition", condition) then return false end
    local head
    if current.hasHead then
        head = repair and current.headConditionMax or math.min(current.headConditionMax, d.headCondition)
        if recover then head = math.max(1, head) end
        if not I.near(current.headCondition, head) and not I.call(item, "setHeadCondition", head) then return false end
    end
    local sharpness
    if current.hasSharpness then
        local maximum = E.number(I.value(item, "getMaxSharpness"))
        if not maximum then return false end
        sharpness = repair and maximum or math.min(maximum, d.sharpness)
        if not I.call(item, "setSharpness", sharpness) then return false end
    end
    local after = I.durability(item)
    return after and I.near(after.condition, condition) and (not head or I.near(after.headCondition, head))
        and (not sharpness or I.near(after.sharpness, sharpness)) or false
end
function I.snapshot(item, restoreDurability)
    local d = I.durability(item)
    if restoreDurability and not d then return nil end
    local source,marker=I.marker(item),nil
    if source then
        marker={}
        -- Item ModData is not authority. Never recursively copy client-supplied auxiliary tables.
        for _,key in ipairs({"schema","worldId","equipmentId","generation","revision","ownerKey"}) do
            local value=source[key]
            if type(value)=="string" or (type(value)=="number" and E.number(value)) then marker[key]=value end
        end
    end
    local custom = I.value(item, "isCustomName", nil)
    return { durability = d, marker = marker, restoreDurability = restoreDurability == true,
        name = custom ~= nil and I.name(item) or nil, customName = custom == true }
end
function I.restore(item, snapshot)
    if not snapshot then return false end
    local durability = not snapshot.restoreDurability or I.setDurability(item, snapshot.durability, false, false)
    local md = I.value(item, "getModData")
    if md then md[E.ItemKey] = E.copy(snapshot.marker) end
    local named = type(snapshot.name) ~= "string" or I.setName(item, snapshot.name, snapshot.customName == true)
    return durability and named and md ~= nil
end
function I.mark(item, root, record)
    local md = I.value(item, "getModData")
    if not md then return false end
    md[E.ItemKey] = { schema = E.Schema, worldId = root.worldId, equipmentId = record.id,
        generation = record.generation, revision = record.revision, ownerKey = record.ownerKey,
        itemId = I.id(item), fullType = I.value(item, "getFullType"),
        durability = E.copy(record.durability) }
    return true
end
function I.matches(item, root, record)
    local m = I.marker(item)
    return m and record and record.state == "active" and m.schema == E.Schema and m.worldId == root.worldId
        and m.equipmentId == record.id and m.generation == record.generation and m.ownerKey == record.ownerKey
        and I.id(item) == record.itemId and I.value(item, "getFullType") == record.fullType or false
end
function I.emptyRecovery(item)
    if not I.call(item, "clearAllWeaponParts") then return false end
    local parts=I.value(item,"getAllWeaponParts")
    if not parts or I.value(parts,"size",-1) ~= 0 then return false end
    if I.value(item, "isRanged", false) then
        for name, value in pairs({ setCurrentAmmoCount = 0, setContainsClip = false, setRoundChambered = false,
            setSpentRoundCount = 0, setSpentRoundChambered = false }) do
            if not I.call(item, name, value) then return false end
        end
        if I.value(item,"getCurrentAmmoCount",-1)~=0 or I.value(item,"isContainsClip",true)
            or I.value(item,"isRoundChambered",true) or I.value(item,"getSpentRoundCount",-1)~=0
            or I.value(item,"isSpentRoundChambered",true) then return false end
    end
    return true
end
return I
