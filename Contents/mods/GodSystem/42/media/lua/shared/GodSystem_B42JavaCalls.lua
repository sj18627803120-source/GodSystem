-- B42 Java userdata rejects an extracted method called as a plain Lua function.
-- Keep every supported userdata call explicit here; normal Lua tables retain their
-- existing dynamic dispatch in the narrow fallback below.
GodSystemB42JavaCalls = GodSystemB42JavaCalls or {}

local Bridge = GodSystemB42JavaCalls

local CALLERS = {
    AddItem = function(target, ...) return target:AddItem(...) end,
    FindItem = function(target, ...) return target:FindItem(...) end,
    TreatAsSolidFloor = function(target, ...) return target:TreatAsSolidFloor(...) end,
    add = function(target, ...) return target:add(...) end,
    get = function(target, ...) return target:get(...) end,
    getAccessLevel = function(target, ...) return target:getAccessLevel(...) end,
    getActualWeight = function(target, ...) return target:getActualWeight(...) end,
    getAge = function(target, ...) return target:getAge(...) end,
    getAllItems = function(target, ...) return target:getAllItems(...) end,
    getAllRecipes = function(target, ...) return target:getAllRecipes(...) end,
    getAmmoType = function(target, ...) return target:getAmmoType(...) end,
    getAttachedItems = function(target, ...) return target:getAttachedItems(...) end,
    getAttachedToModel = function(target, ...) return target:getAttachedToModel(...) end,
    getAttachmentType = function(target, ...) return target:getAttachmentType(...) end,
    getBodyDamage = function(target, ...) return target:getBodyDamage(...) end,
    getBodyLocation = function(target, ...) return target:getBodyLocation(...) end,
    getBodyParts = function(target, ...) return target:getBodyParts(...) end,
    getCapacity = function(target, ...) return target:getCapacity(...) end,
    getEffectiveCapacity = function(target, ...) return target:getEffectiveCapacity(...) end,
    getCategory = function(target, ...) return target:getCategory(...) end,
    getCondition = function(target, ...) return target:getCondition(...) end,
    getConditionMax = function(target, ...) return target:getConditionMax(...) end,
    getContainer = function(target, ...) return target:getContainer(...) end,
    getContainerByIndex = function(target, ...) return target:getContainerByIndex(...) end,
    getContainerCount = function(target, ...) return target:getContainerCount(...) end,
    getContainingItem = function(target, ...) return target:getContainingItem(...) end,
    getContentsWeight = function(target, ...) return target:getContentsWeight(...) end,
    getCount = function(target, ...) return target:getCount(...) end,
    getCurrentAmmoCount = function(target, ...) return target:getCurrentAmmoCount(...) end,
    getDisplayCategory = function(target, ...) return target:getDisplayCategory(...) end,
    getDisplayName = function(target, ...) return target:getDisplayName(...) end,
    getFullName = function(target, ...) return target:getFullName(...) end,
    getFullType = function(target, ...) return target:getFullType(...) end,
    getGridSquare = function(target, ...) return target:getGridSquare(...) end,
    getH = function(target, ...) return target:getH(...) end,
    getHealth = function(target, ...) return target:getHealth(...) end,
    getHeight = function(target, ...) return target:getHeight(...) end,
    getID = function(target, ...) return target:getID(...) end,
    getInfectionLevel = function(target, ...) return target:getInfectionLevel(...) end,
    getInfectionMortalityDuration = function(target, ...) return target:getInfectionMortalityDuration(...) end,
    getInfectionTime = function(target, ...) return target:getInfectionTime(...) end,
    getInventory = function(target, ...) return target:getInventory(...) end,
    getInventoryItem = function(target, ...) return target:getInventoryItem(...) end,
    getItemKey = function(target, ...) return target:getItemKey(...) end,
    getItem = function(target, ...) return target:getItem(...) end,
    getItems = function(target, ...) return target:getItems(...) end,
    getLocation = function(target, ...) return target:getLocation(...) end,
    getLuaCreate = function(target, ...) return target:getLuaCreate(...) end,
    getMaxAmmo = function(target, ...) return target:getMaxAmmo(...) end,
    getModData = function(target, ...) return target:getModData(...) end,
    getModule = function(target, ...) return target:getModule(...) end,
    getModuleName = function(target, ...) return target:getModuleName(...) end,
    getName = function(target, ...) return target:getName(...) end,
    getObjects = function(target, ...) return target:getObjects(...) end,
    getOffAge = function(target, ...) return target:getOffAge(...) end,
    getOnlineID = function(target, ...) return target:getOnlineID(...) end,
    getOverallBodyHealth = function(target, ...) return target:getOverallBodyHealth(...) end,
    getOwner = function(target, ...) return target:getOwner(...) end,
    getParent = function(target, ...) return target:getParent(...) end,
    getPerkLevel = function(target, ...) return target:getPerkLevel(...) end,
    getPlayerNum = function(target, ...) return target:getPlayerNum(...) end,
    getPlayers = function(target, ...) return target:getPlayers(...) end,
    getPrimaryHandItem = function(target, ...) return target:getPrimaryHandItem(...) end,
    getResult = function(target, ...) return target:getResult(...) end,
    getScriptItem = function(target, ...) return target:getScriptItem(...) end,
    getSecondaryHandItem = function(target, ...) return target:getSecondaryHandItem(...) end,
    getSource = function(target, ...) return target:getSource(...) end,
    getSourceGrid = function(target, ...) return target:getSourceGrid(...) end,
    getSpecialObjects = function(target, ...) return target:getSpecialObjects(...) end,
    getSprite = function(target, ...) return target:getSprite(...) end,
    getSquare = function(target, ...) return target:getSquare(...) end,
    getStats = function(target, ...) return target:getStats(...) end,
    getTags = function(target, ...) return target:getTags(...) end,
    getTemprature = function(target, ...) return target:getTemprature(...) end,
    getTex = function(target, ...) return target:getTex(...) end,
    getTexture = function(target, ...) return target:getTexture(...) end,
    getTotalXpForLevel = function(target, ...) return target:getTotalXpForLevel(...) end,
    getType = function(target, ...) return target:getType(...) end,
    getTypeString = function(target, ...) return target:getTypeString(...) end,
    getUsedDelta = function(target, ...) return target:getUsedDelta(...) end,
    getUsername = function(target, ...) return target:getUsername(...) end,
    getW = function(target, ...) return target:getW(...) end,
    getWeight = function(target, ...) return target:getWeight(...) end,
    getWeightReduction = function(target, ...) return target:getWeightReduction(...) end,
    getWorldObjects = function(target, ...) return target:getWorldObjects(...) end,
    getWorldSprite = function(target, ...) return target:getWorldSprite(...) end,
    getWornItem = function(target, ...) return target:getWornItem(...) end,
    getWornItems = function(target, ...) return target:getWornItems(...) end,
    getWoundInfectionLevel = function(target, ...) return target:getWoundInfectionLevel(...) end,
    getX = function(target, ...) return target:getX(...) end,
    getXP = function(target, ...) return target:getXP(...) end,
    getY = function(target, ...) return target:getY(...) end,
    getYScroll = function(target, ...) return target:getYScroll(...) end,
    getZ = function(target, ...) return target:getZ(...) end,
    haveElectricity = function(target, ...) return target:haveElectricity(...) end,
    haveBullet = function(target, ...) return target:haveBullet(...) end,
    haveGlass = function(target, ...) return target:haveGlass(...) end,
    hasInjury = function(target, ...) return target:hasInjury(...) end,
    isAimedFirearm = function(target, ...) return target:isAimedFirearm(...) end,
    isAccessLevel = function(target, ...) return target:isAccessLevel(...) end,
    isBleeding = function(target, ...) return target:isBleeding(...) end,
    isBroken = function(target, ...) return target:isBroken(...) end,
    isCooked = function(target, ...) return target:isCooked(...) end,
    isCooking = function(target, ...) return target:isCooking(...) end,
    isDestroy = function(target, ...) return target:isDestroy(...) end,
    isEquipped = function(target, ...) return target:isEquipped(...) end,
    isFavorite = function(target, ...) return target:isFavorite(...) end,
    isFrozen = function(target, ...) return target:isFrozen(...) end,
    isInfected = function(target, ...) return target:isInfected(...) end,
    isItemInBothHands = function(target, ...) return target:isItemInBothHands(...) end,
    isItemType = function(target, ...) return target:isItemType(...) end,
    isKeep = function(target, ...) return target:isKeep(...) end,
    isOwner = function(target, ...) return target:isOwner(...) end,
    isRotten = function(target, ...) return target:isRotten(...) end,
    isStale = function(target, ...) return target:isStale(...) end,
    playerAllowed = function(target, ...) return target:playerAllowed(...) end,
    hasTag = function(target, ...) return target:hasTag(...) end,
    repair = function(target, ...) return target:repair(...) end,
    remove = function(target, ...) return target:remove(...) end,
    Remove = function(target, ...) return target:Remove(...) end,
    setAdditionalPain = function(target, ...) return target:setAdditionalPain(...) end,
    setAge = function(target, ...) return target:setAge(...) end,
    setBiteTime = function(target, ...) return target:setBiteTime(...) end,
    setBleedingTime = function(target, ...) return target:setBleedingTime(...) end,
    setBurnTime = function(target, ...) return target:setBurnTime(...) end,
    setCapacity = function(target, ...) return target:setCapacity(...) end,
    setCurrentAmmoCount = function(target, ...) return target:setCurrentAmmoCount(...) end,
    setCustomName = function(target, ...) return target:setCustomName(...) end,
    setCutTime = function(target, ...) return target:setCutTime(...) end,
    setDeepWoundTime = function(target, ...) return target:setDeepWoundTime(...) end,
    setFavorite = function(target, ...) return target:setFavorite(...) end,
    setFractureTime = function(target, ...) return target:setFractureTime(...) end,
    setHaveBullet = function(target, ...) return target:setHaveBullet(...) end,
    setHaveGlass = function(target, ...) return target:setHaveGlass(...) end,
    setHealth = function(target, ...) return target:setHealth(...) end,
    setHungChange = function(target, ...) return target:setHungChange(...) end,
    setJobDelta = function(target, ...) return target:setJobDelta(...) end,
    setJobType = function(target, ...) return target:setJobType(...) end,
    setInfected = function(target, ...) return target:setInfected(...) end,
    setInfectedWound = function(target, ...) return target:setInfectedWound(...) end,
    setInfectionLevel = function(target, ...) return target:setInfectionLevel(...) end,
    setInfectionMortalityDuration = function(target, ...) return target:setInfectionMortalityDuration(...) end,
    setInfectionTime = function(target, ...) return target:setInfectionTime(...) end,
    setIsFakeInfected = function(target, ...) return target:setIsFakeInfected(...) end,
    setScratchTime = function(target, ...) return target:setScratchTime(...) end,
    setName = function(target, ...) return target:setName(...) end,
    setSplint = function(target, ...) return target:setSplint(...) end,
    setStitched = function(target, ...) return target:setStitched(...) end,
    setUnwanted = function(target, ...) return target:setUnwanted(...) end,
    setWeightReduction = function(target, ...) return target:setWeightReduction(...) end,
    setWoundInfectionLevel = function(target, ...) return target:setWoundInfectionLevel(...) end,
    size = function(target, ...) return target:size(...) end,
    syncItemFields = function(target, ...) return target:syncItemFields(...) end,
    transmitModData = function(target, ...) return target:transmitModData(...) end,
    transmitPartCondition = function(target, ...) return target:transmitPartCondition(...) end,
    transmitPartItem = function(target, ...) return target:transmitPartItem(...) end,
    transmitPartModData = function(target, ...) return target:transmitPartModData(...) end,
    updateBulletStats = function(target, ...) return target:updateBulletStats(...) end,
    updateDamageOverlay = function(target, ...) return target:updateDamageOverlay(...) end,
    updatePartStats = function(target, ...) return target:updatePartStats(...) end,
    getAdditionalPain = function(target, ...) return target:getAdditionalPain(...) end,
    getBiteTime = function(target, ...) return target:getBiteTime(...) end,
    getBleedingTime = function(target, ...) return target:getBleedingTime(...) end,
    getBurnTime = function(target, ...) return target:getBurnTime(...) end,
    getCutTime = function(target, ...) return target:getCutTime(...) end,
    getDeepWoundTime = function(target, ...) return target:getDeepWoundTime(...) end,
    getFractureTime = function(target, ...) return target:getFractureTime(...) end,
    getHeadCondition = function(target, ...) return target:getHeadCondition(...) end,
    getHeadConditionMax = function(target, ...) return target:getHeadConditionMax(...) end,
    getHungChange = function(target, ...) return target:getHungChange(...) end,
    getId = function(target, ...) return target:getId(...) end,
    getKills = function(target, ...) return target:getKills(...) end,
    getNumKills = function(target, ...) return target:getNumKills(...) end,
    getPartByIndex = function(target, ...) return target:getPartByIndex(...) end,
    getPartCount = function(target, ...) return target:getPartCount(...) end,
    getScratchTime = function(target, ...) return target:getScratchTime(...) end,
    getSharpness = function(target, ...) return target:getSharpness(...) end,
    getReplaceOnDeplete = function(target, ...) return target:getReplaceOnDeplete(...) end,
    getReplaceOnUse = function(target, ...) return target:getReplaceOnUse(...) end,
    getZombieKills = function(target, ...) return target:getZombieKills(...) end,
    getZombieKillsTotal = function(target, ...) return target:getZombieKillsTotal(...) end,
    HasInjury = function(target, ...) return target:HasInjury(...) end,
    hasHeadCondition = function(target, ...) return target:hasHeadCondition(...) end,
    hasSharpness = function(target, ...) return target:hasSharpness(...) end,
    IsBleeding = function(target, ...) return target:IsBleeding(...) end,
    bleeding = function(target, ...) return target:bleeding(...) end,
    isBurnt = function(target, ...) return target:isBurnt(...) end,
    isDeepWounded = function(target, ...) return target:isDeepWounded(...) end,
    deepWounded = function(target, ...) return target:deepWounded(...) end,
    IsFakeInfected = function(target, ...) return target:IsFakeInfected(...) end,
    isFakeInfected = function(target, ...) return target:isFakeInfected(...) end,
    IsInfected = function(target, ...) return target:IsInfected(...) end,
    isSolid = function(target, ...) return target:isSolid(...) end,
    isSolidTrans = function(target, ...) return target:isSolidTrans(...) end,
    stitched = function(target, ...) return target:stitched(...) end,
    setBroken = function(target, ...) return target:setBroken(...) end,
    setCondition = function(target, ...) return target:setCondition(...) end,
    setConditionMax = function(target, ...) return target:setConditionMax(...) end,
    SetFakeInfected = function(target, ...) return target:SetFakeInfected(...) end,
    setHeadCondition = function(target, ...) return target:setHeadCondition(...) end,
    SetHealth = function(target, ...) return target:SetHealth(...) end,
    SetInfected = function(target, ...) return target:SetInfected(...) end,
    setOverallBodyHealth = function(target, ...) return target:setOverallBodyHealth(...) end,
    setSharpness = function(target, ...) return target:setSharpness(...) end,
}

local function callLuaTable(target, methodName, ...)
    if type(target) ~= "table" then return false, nil end
    local method = target[methodName]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

function Bridge.try(target, methodName, ...)
    if not target or not methodName then return false, nil end
    local caller = CALLERS[methodName]
    if caller then
        -- Java userdata exposes only methods implemented by the concrete item
        -- class. Probe the member before invoking the explicit wrapper so an
        -- optional method such as getUsedDelta falls back cleanly on ordinary
        -- InventoryItem instances.
        local available, method = pcall(function() return target[methodName] end)
        if not available or method == nil then return false, nil end
        return pcall(caller, target, ...)
    end
    return callLuaTable(target, methodName, ...)
end

function Bridge.value(target, methodName, fallback, ...)
    local ok, value = Bridge.try(target, methodName, ...)
    if ok and value ~= nil then return value end
    return fallback
end

function Bridge.getContainingItem(container)
    return Bridge.value(container, "getContainingItem", nil)
end

function Bridge.getCapacity(target)
    return Bridge.value(target, "getCapacity", nil)
end

function Bridge.getEffectiveCapacity(target)
    return Bridge.value(target, "getEffectiveCapacity", nil)
end

function Bridge.setCapacity(target, value)
    return Bridge.try(target, "setCapacity", value)
end

function Bridge.getWeightReduction(target)
    return Bridge.value(target, "getWeightReduction", nil)
end

function Bridge.setWeightReduction(target, value)
    return Bridge.try(target, "setWeightReduction", value)
end

function Bridge.getAge(target)
    return Bridge.value(target, "getAge", nil)
end

function Bridge.setAge(target, value)
    return Bridge.try(target, "setAge", value)
end

function Bridge.getOffAge(target)
    return Bridge.value(target, "getOffAge", nil)
end

return Bridge
