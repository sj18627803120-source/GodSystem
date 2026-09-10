require "GodSystem_Equipment"
require "GodSystem_B42JavaCalls"

GodSystemEquipmentItems = GodSystemEquipmentItems or {}
local I, E, Bridge = GodSystemEquipmentItems, GodSystemEquipment, GodSystemB42JavaCalls
I.metrics=I.metrics or {applications=0,lastApplyMs=0}
-- Explicit colon calls are required for Kahlua Java userdata.
local callers = {
    getMinDamage = function(o) return o:getMinDamage() end,
    getMaxDamage = function(o) return o:getMaxDamage() end,
    getSharpnessMultiplier = function(o) return o:getSharpnessMultiplier() end,
    getMaxSharpness = function(o) return o:getMaxSharpness() end,
    getConditionLowerChance = function(o) return o:getConditionLowerChance() end,
    getBaseSpeed = function(o) return o:getBaseSpeed() end,
    getHitChance = function(o) return o:getHitChance() end,
    getRecoilDelay = function(o) return o:getRecoilDelay() end,
    getAllWeaponParts = function(o) return o:getAllWeaponParts() end,
    getDamage = function(o) return o:getDamage() end,
    isRanged = function(o) return o:isRanged() end,
    getOnBreak = function(o) return o:getOnBreak() end,
    setMinDamage = function(o,v) return o:setMinDamage(v) end,
    setMaxDamage = function(o,v) return o:setMaxDamage(v) end,
    setConditionLowerChance = function(o,v) return o:setConditionLowerChance(v) end,
    setBaseSpeed = function(o,v) return o:setBaseSpeed(v) end,
    setHitChance = function(o,v) return o:setHitChance(v) end,
    setRecoilDelay = function(o,v) return o:setRecoilDelay(v) end,
    clearAllWeaponParts = function(o) return o:clearAllWeaponParts() end,
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
local getters = { minDamage = "getMinDamage", maxDamage = "getMaxDamage", wear = "getConditionLowerChance",
    speed = "getBaseSpeed", accuracy = "getHitChance", recoil = "getRecoilDelay" }
local setters = { minDamage = "setMinDamage", maxDamage = "setMaxDamage", wear = "setConditionLowerChance",
    speed = "setBaseSpeed", accuracy = "setHitChance", recoil = "setRecoilDelay" }
local order = { "minDamage", "maxDamage", "wear", "speed", "accuracy", "recoil" }
function I.raw(item)
    local v = { ranged = I.value(item, "isRanged", false) == true }
    for key, getter in pairs(getters) do v[key] = E.number(I.value(item, getter)) end
    -- B42.20.4: effectiveMax = min + (rawMax-min)*sharpnessMultiplier.
    if I.value(item, "hasSharpness", false) and v.minDamage and v.maxDamage and v.maxDamage > v.minDamage then
        local multiplier = E.number(I.value(item, "getSharpnessMultiplier", 1))
        if not multiplier or multiplier <= 0 then return nil end
        v.maxDamage = v.minDamage + (v.maxDamage - v.minDamage) / multiplier
    end
    return v
end
function I.parts(item)
    local parts = { minDamage = 0, maxDamage = 0, accuracy = 0, recoil = 0 }
    local ok, list = I.call(item, "getAllWeaponParts")
    if not ok or not list then return nil end
    local count = E.integer(I.value(list, "size"), 0, 64)
    if not count then return nil end
    for index = 0, count - 1 do
        local part = I.value(list, "get", nil, index)
        if not part then return nil end
        local damage = E.number(I.value(part, "getDamage"))
        local accuracy = E.number(I.value(part, "getHitChance"))
        local recoil = E.number(I.value(part, "getRecoilDelay"))
        if not damage or not accuracy or not recoil then return nil end
        parts.minDamage, parts.maxDamage = parts.minDamage + damage, parts.maxDamage + damage
        parts.accuracy, parts.recoil = parts.accuracy + accuracy, parts.recoil + recoil
    end
    return parts
end
function I.base(item)
    if not I.isWeapon(item) then return nil, "EquipmentUnsupported" end
    local raw, parts = I.raw(item), I.parts(item)
    if not raw or not parts then return nil, "EquipmentUnsupported" end
    local base = E.copy(raw)
    for key, value in pairs(parts) do if base[key] then base[key] = base[key] - value end end
    if not base.minDamage or not base.maxDamage or base.minDamage < 0 or base.maxDamage < base.minDamage then
        return nil, "EquipmentUnsupported"
    end
    if not base.wear or base.wear <= 0 then base.wear = nil end
    if not base.speed or base.speed <= 0 then base.speed = nil end
    if not base.accuracy or base.accuracy <= 0 then base.accuracy = nil end
    if not base.recoil or base.recoil <= 0 then base.recoil = nil end
    if parts.recoil ~= math.floor(parts.recoil) then base.recoil = nil end -- Native integer truncation is not invertible.
    return base
end
function I.near(a,b)
    return E.number(a) and E.number(b) and math.abs(a-b) <= math.max(0.00001, math.abs(b)*0.00001)
end
function I.write(item, target, force)
    local before = I.raw(item)
    if not before then return false end
    for _, key in ipairs(order) do
        local value = target[key]
        if value ~= nil then
            if not E.number(value) or math.abs(value) > E.MaxMoney then return false end
            if force or not I.near(before[key], value) then
                if not I.call(item, setters[key], value) then return false end
            end
        end
    end
    local after = I.raw(item)
    if not after then return false end
    for _, key in ipairs(order) do if target[key] ~= nil and not I.near(after[key], target[key]) then return false end end
    return true
end
function I.target(item, base, levels, cfg)
    local parts, target = I.parts(item), E.values(base, levels, cfg)
    if not parts then return nil end
    for key, value in pairs(parts) do if target[key] ~= nil then target[key] = target[key] + value end end
    if target.accuracy then target.accuracy = math.floor(target.accuracy + 0.5) end
    if target.recoil then target.recoil = math.floor(target.recoil + 0.5) end
    if levels and (levels.accuracy or 0)>0 and target.accuracy then target.accuracy=math.min(100,target.accuracy) end
    if levels and (levels.recoil or 0)>0 and target.recoil then target.recoil=math.max(1,target.recoil) end
    return target
end
function I.apply(item, base, levels, cfg)
    local started=getTimestampMs and getTimestampMs() or 0
    I.metrics.applications=I.metrics.applications+1
    local target=I.target(item,base,levels,cfg)
    if not target then return false end
    local result=I.write(item, target)
    I.metrics.lastApplyMs=(getTimestampMs and getTimestampMs() or started)-started
    return result
end
function I.durability(item)
    local d = { condition = E.number(I.value(item, "getCondition")), conditionMax = E.number(I.value(item, "getConditionMax")),
        hasHead = I.value(item, "hasHeadCondition", false) == true,
        hasSharpness = I.value(item, "hasSharpness", false) == true }
    if not d.condition or not d.conditionMax or d.conditionMax < 1 then return nil end
    if d.hasHead then
        d.headCondition = E.number(I.value(item, "getHeadCondition"))
        d.headConditionMax = E.number(I.value(item, "getHeadConditionMax"))
        if not d.headCondition or not d.headConditionMax or d.headConditionMax < 1 then return nil end
    end
    if d.hasSharpness then
        d.sharpness = E.number(I.value(item, "getSharpness"))
        d.maxSharpness = E.number(I.value(item, "getMaxSharpness"))
        if not d.sharpness or not d.maxSharpness then return nil end
    end
    return d
end
function I.full(d)
    return d and d.condition >= d.conditionMax and (not d.hasHead or d.headCondition >= d.headConditionMax)
        and (not d.hasSharpness or d.sharpness >= 0.99999)
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
    if not current or current.hasHead ~= d.hasHead or current.hasSharpness ~= d.hasSharpness then return false end
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
function I.snapshot(item)
    local raw, d = I.raw(item), I.durability(item)
    if not raw or not d then return nil end
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
    return { raw = raw, durability = d, marker = marker,
        name = custom ~= nil and I.name(item) or nil, customName = custom == true }
end
function I.restore(item, snapshot)
    if not snapshot then return false end
    local attributes = I.write(item, snapshot.raw)
    local durability = I.setDurability(item, snapshot.durability, false, false)
    local md = I.value(item, "getModData")
    if md then md[E.ItemKey] = E.copy(snapshot.marker) end
    local named = type(snapshot.name) ~= "string" or I.setName(item, snapshot.name, snapshot.customName == true)
    return attributes and durability and named and md ~= nil
end
function I.mark(item, root, record)
    local md = I.value(item, "getModData")
    if not md then return false end
    md[E.ItemKey] = { schema = E.Schema, worldId = root.worldId, equipmentId = record.id,
        generation = record.generation, revision = record.revision, ownerKey = record.ownerKey,
        itemId = I.id(item), fullType = I.value(item, "getFullType"),
        base = E.copy(record.base), durability = E.copy(record.durability) }
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
