require "GodSystem_Storage"

GodSystemItemSnapshot = GodSystemItemSnapshot or {}

local Snapshot = GodSystemItemSnapshot
local Storage = GodSystemStorage

Snapshot.SchemaVersion = 1
Snapshot.MaxDepth = 32
Snapshot.moduleId = "itemSnapshot"

local function result(ok, code, data)
    return { ok = ok == true, code = tostring(code or ""), data = data, moduleId = Snapshot.moduleId }
end

local function call(object, method, fallback, ...)
    if not object or not object[method] then return fallback, false end
    local args = { ... }
    local unpackFn = unpack or table.unpack
    local ok, value = pcall(function() return object[method](object, unpackFn(args)) end)
    if not ok then return fallback, false end
    return value, true
end

local function finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function safePrimitive(value, depth, seen, report)
    local kind = type(value)
    if kind == "nil" or kind == "string" or kind == "boolean" then return value, true end
    if kind == "number" then
        local number = finite(value)
        if number ~= nil then return number, true end
        report.omitted = report.omitted + 1
        report.reasons.nonFinite = (report.reasons.nonFinite or 0) + 1
        return nil, false
    end
    if kind ~= "table" then
        report.omitted = report.omitted + 1
        report.reasons[kind] = (report.reasons[kind] or 0) + 1
        return nil, false
    end
    if depth > Snapshot.MaxDepth or seen[value] then
        report.omitted = report.omitted + 1
        local reason = depth > Snapshot.MaxDepth and "depth" or "cycle"
        report.reasons[reason] = (report.reasons[reason] or 0) + 1
        return nil, false
    end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local safeChild, kept = safePrimitive(child, depth + 1, seen, report)
            if kept then copy[key] = safeChild end
        else
            report.omitted = report.omitted + 1
            report.reasons.keyType = (report.reasons.keyType or 0) + 1
        end
    end
    seen[value] = nil
    return copy, true
end

local FIELD_ADAPTERS = {
    { "condition", "getCondition", "setCondition" },
    { "conditionMax", "getConditionMax", "setConditionMax" },
    { "haveBeenRepaired", "getHaveBeenRepaired", "setHaveBeenRepaired" },
    { "actualWeight", "getActualWeight", "setActualWeight" },
    { "customWeight", "isCustomWeight", "setCustomWeight" },
    { "favorite", "isFavorite", "setFavorite" },
    { "activated", "isActivated", "setActivated" },
    { "wet", "isWet", "setWet" },
    { "wetCooldown", "getWetCooldown", "setWetCooldown" },
    { "bloodLevel", "getBloodLevel", "setBloodLevel" },
    { "dirtyness", "getDirtiness", "setDirtiness" },
    { "wetness", "getWetness", "setWetness" },
    { "keyId", "getKeyId", "setKeyId" },
    { "spriteName", "getSpriteName", "setSpriteName" },
    { "worldSprite", "getWorldSprite", "setWorldSprite" },
    { "usesFloat", "getCurrentUsesFloat", "setCurrentUsesFloat" },
    { "usedDelta", "getUsedDelta", "setUsedDelta" },
    { "currentUses", "getCurrentUses", "setCurrentUses" },
    { "uses", "getUses", "setUses" },
    { "count", "getCount", "setCount" },
    { "age", "getAge", "setAge" },
    { "offAge", "getOffAge", "setOffAge" },
    { "offAgeMax", "getOffAgeMax", "setOffAgeMax" },
    { "cookingTime", "getCookingTime", "setCookingTime" },
    { "lastAged", "getLastAged", "setLastAged" },
    { "cooked", "isCooked", "setCooked" },
    { "burnt", "isBurnt", "setBurnt" },
    { "tainted", "isTainted", "setTainted" },
    { "taintedWater", "isTaintedWater", "setTaintedWater" },
    { "poison", "isPoison", "setPoison" },
    { "poisonPower", "getPoisonPower", "setPoisonPower" },
    { "alcoholPower", "getAlcoholPower", "setAlcoholPower" },
    { "hunger", "getHungChange", "setHungChange" },
    { "thirst", "getThirstChange", "setThirstChange" },
    { "unhappy", "getUnhappyChange", "setUnhappyChange" },
    { "boredom", "getBoredomChange", "setBoredomChange" },
    { "stress", "getStressChange", "setStressChange" },
    { "sickness", "getFoodSicknessChange", "setFoodSicknessChange" },
    { "calories", "getCalories", "setCalories" },
    { "carbohydrates", "getCarbohydrates", "setCarbohydrates" },
    { "lipids", "getLipids", "setLipids" },
    { "proteins", "getProteins", "setProteins" },
    { "temperature", "getTemperature", "setTemperature" },
    { "freezingTime", "getFreezingTime", "setFreezingTime" },
    { "frozen", "isFrozen", "setFrozen" },
    { "sharpness", "getSharpness", "setSharpness" },
    { "headCondition", "getHeadCondition", "setHeadCondition" },
    { "quality", "getQuality", "setQuality" },
    { "currentAmmoCount", "getCurrentAmmoCount", "setCurrentAmmoCount" },
    { "roundChambered", "isRoundChambered", "setRoundChambered" },
    { "spentRoundChambered", "isSpentRoundChambered", "setSpentRoundChambered" },
    { "spentRoundCount", "getSpentRoundCount", "setSpentRoundCount" },
    { "jammed", "isJammed", "setJammed" },
    { "fireMode", "getFireMode", "setFireMode" },
    { "containsClip", "isContainsClip", "setContainsClip" },
    { "magazineType", "getMagazineType", "setMagazineType" },
}

local function captureFields(item, target)
    for i = 1, #FIELD_ADAPTERS do
        local row = FIELD_ADAPTERS[i]
        local value, ok = call(item, row[2], nil)
        if ok and (type(value) == "string" or type(value) == "boolean" or finite(value) ~= nil) then
            target[row[1]] = value
        end
    end
    local customName = call(item, "isCustomName", false)
    if customName == true then
        target.customName = true
        target.name = tostring(call(item, "getName", target.fullType) or target.fullType)
    end
    local customColor = call(item, "isCustomColor", false)
    if customColor == true then
        target.color = {
            r = finite(call(item, "getColorRed", 1)) or 1,
            g = finite(call(item, "getColorGreen", 1)) or 1,
            b = finite(call(item, "getColorBlue", 1)) or 1,
        }
    end
end

local function captureFluid(item, target)
    local fluid = call(item, "getFluidContainer", nil)
    if not fluid then return end
    local amount = finite(call(fluid, "getAmount", nil))
    local primary = call(fluid, "getPrimaryFluid", nil)
    if amount and amount > 0 and primary then
        local fluidType = call(primary, "getFluidTypeString", nil)
        target.fluid = { amount = amount, primary = tostring(fluidType or primary) }
    end
end

local function captureClothing(item, target)
    if call(item, "IsClothing", false) ~= true or not BloodBodyPartType or not BloodBodyPartType.MAX then return end
    local visual = call(item, "getVisual", nil)
    local max = BloodBodyPartType.MAX:index()
    local holes, patches = {}, {}
    for index = 0, max - 1 do
        local part = BloodBodyPartType.FromIndex(index)
        local patch = call(item, "getPatchType", nil, part)
        if patch then
            patches[#patches + 1] = {
                partIndex = index,
                tailorLvl = finite(patch.tailorLvl) or 0,
                fabricType = finite(patch.fabricType) or 0,
                hasHole = patch.hasHole == true,
            }
        end
        local hole = visual and finite(call(visual, "getHole", nil, part)) or nil
        if hole and hole > 0 then holes[#holes + 1] = { partIndex = index } end
    end
    if #holes > 0 then target.holes = holes end
    if #patches > 0 then target.patches = patches end
end

local function captureItem(item, depth, seenItems, report)
    if not item then return nil, "missingItem" end
    if depth > Snapshot.MaxDepth then return nil, "depth" end
    if seenItems[item] then return nil, "cycle" end
    local fullType = Storage.itemFullType(item)
    if fullType == "" then return nil, "missingFullType" end
    seenItems[item] = true
    local target = {
        schemaVersion = Snapshot.SchemaVersion,
        fullType = fullType,
        category = Storage.categoryOf(item),
        displayName = tostring(call(item, "getName", fullType) or fullType),
        modName = Storage.itemModName(item),
        states = Storage.statesOf(item, Storage.getItemContainer(item)),
        children = {},
        weaponParts = {},
    }
    captureFields(item, target)
    local mediaIndex = call(item, "getRecordedMediaIndexInteger", nil)
    if mediaIndex == nil then mediaIndex = call(item, "getRecordedMediaIndex", nil) end
    if finite(mediaIndex) ~= nil then target.recordedMediaIndex = math.floor(mediaIndex) end
    captureFluid(item, target)
    captureClothing(item, target)

    local modData = call(item, "getModData", nil)
    if type(modData) == "table" then
        local safeData = safePrimitive(modData, 1, {}, report)
        target.modData = safeData
    elseif modData ~= nil then
        report.omitted = report.omitted + 1
        report.reasons.modData = (report.reasons.modData or 0) + 1
    end

    local childContainer = call(item, "getInventory", nil)
    local childItems = childContainer and call(childContainer, "getItems", nil) or nil
    local childSize = childItems and math.max(0, math.floor(tonumber((call(childItems, "size", 0))) or 0)) or 0
    for index = 0, childSize - 1 do
        local child = call(childItems, "get", nil, index)
        local childSnapshot, reason = captureItem(child, depth + 1, seenItems, report)
        if not childSnapshot then seenItems[item] = nil; return nil, reason end
        target.children[#target.children + 1] = childSnapshot
    end

    local parts = call(item, "getAllWeaponParts", nil)
    local partSize = parts and math.max(0, math.floor(tonumber((call(parts, "size", 0))) or 0)) or 0
    for index = 0, partSize - 1 do
        local part = call(parts, "get", nil, index)
        local partSnapshot, reason = captureItem(part, depth + 1, seenItems, report)
        if not partSnapshot then seenItems[item] = nil; return nil, reason end
        target.weaponParts[#target.weaponParts + 1] = partSnapshot
    end

    seenItems[item] = nil
    target.itemCount = math.max(1, math.floor(finite(target.count) or 1))
    for i = 1, #target.children do target.itemCount = target.itemCount + (target.children[i].itemCount or 1) end
    for i = 1, #target.weaponParts do target.itemCount = target.itemCount + (target.weaponParts[i].itemCount or 1) end
    return target
end

function Snapshot.capture(item)
    local report = { simplified = false, omitted = 0, reasons = {} }
    local data, reason = captureItem(item, 1, {}, report)
    report.simplified = report.omitted > 0
    if not data then return result(false, reason, { report = report }) end
    return result(true, report.simplified and "simplified" or "complete", { snapshot = data, report = report })
end

local function applyFields(item, data)
    for i = 1, #FIELD_ADAPTERS do
        local row = FIELD_ADAPTERS[i]
        local drainableDuplicate = data.usedDelta ~= nil
            and (row[1] == "usesFloat" or row[1] == "currentUses" or row[1] == "uses")
        if not drainableDuplicate and data[row[1]] ~= nil and item[row[3]] then
            call(item, row[3], nil, data[row[1]])
        end
    end
    if data.customName == true and data.name then
        call(item, "setName", nil, data.name)
        call(item, "setCustomName", nil, true)
    end
    if type(data.color) == "table" then
        call(item, "setColorRed", nil, data.color.r)
        call(item, "setColorGreen", nil, data.color.g)
        call(item, "setColorBlue", nil, data.color.b)
        call(item, "setCustomColor", nil, true)
    end
end

local function applyFluid(item, data)
    if type(data.fluid) ~= "table" then return end
    local fluid = call(item, "getFluidContainer", nil)
    if not fluid then return end
    if fluid.removeFluid then call(fluid, "removeFluid", nil) else call(fluid, "Empty", nil) end
    if data.fluid.primary and finite(data.fluid.amount) then
        local fluidType = nil
        if Fluid and Fluid[data.fluid.primary] then fluidType = Fluid[data.fluid.primary] end
        if not fluidType and FluidType and FluidType.FromNameLower then
            local ok, resolved = pcall(FluidType.FromNameLower, string.lower(tostring(data.fluid.primary)))
            if ok then fluidType = resolved end
        end
        call(fluid, "addFluid", nil, fluidType or data.fluid.primary, data.fluid.amount)
    end
end

local function applyClothing(item, data)
    local visual = call(item, "getVisual", nil)
    if visual and type(data.holes) == "table" and BloodBodyPartType then
        for i = 1, #data.holes do
            local part = BloodBodyPartType.FromIndex(data.holes[i].partIndex)
            call(visual, "setHole", nil, part)
        end
    end
    if visual and type(data.patches) == "table" and BloodBodyPartType then
        for i = 1, #data.patches do
            local row = data.patches[i]
            call(item, "addPatchForSync", nil, row.partIndex, row.tailorLvl, row.fabricType, row.hasHole)
            local part = BloodBodyPartType.FromIndex(row.partIndex)
            if row.fabricType == 1 then call(visual, "setBasicPatch", nil, part)
            elseif row.fabricType == 2 then call(visual, "setDenimPatch", nil, part)
            elseif row.fabricType == 3 then call(visual, "setLeatherPatch", nil, part) end
        end
    end
end

local function restoreItem(data, depth, report)
    if type(data) ~= "table" or tostring(data.fullType or "") == "" then return nil, "invalidSnapshot" end
    if depth > Snapshot.MaxDepth then return nil, "depth" end
    if not instanceItem then return nil, "factoryUnavailable" end
    local ok, item = pcall(instanceItem, data.fullType)
    if not ok or not item then return nil, "missingDefinition" end
    applyFields(item, data)
    if data.recordedMediaIndex ~= nil then
        if item.setRecordedMediaIndexInteger then call(item, "setRecordedMediaIndexInteger", nil, data.recordedMediaIndex)
        else call(item, "setRecordedMediaIndex", nil, data.recordedMediaIndex) end
    end
    applyFluid(item, data)
    applyClothing(item, data)
    if type(data.modData) == "table" then
        local modData = call(item, "getModData", nil)
        if type(modData) == "table" then
            for key in pairs(modData) do modData[key] = nil end
            local copied = safePrimitive(data.modData, 1, {}, report)
            for key, value in pairs(copied or {}) do modData[key] = value end
        end
    end
    call(item, "synchWithVisual", nil)

    local childContainer = call(item, "getInventory", nil)
    if #(data.children or {}) > 0 and not childContainer then return nil, "childContainerMissing" end
    for i = 1, #(data.children or {}) do
        local child, reason = restoreItem(data.children[i], depth + 1, report)
        if not child then return nil, reason end
        call(childContainer, "AddItem", nil, child)
        if not Storage.containerContains(childContainer, child) then return nil, "childAddFailed" end
    end
    for i = 1, #(data.weaponParts or {}) do
        local part, reason = restoreItem(data.weaponParts[i], depth + 1, report)
        if not part then return nil, reason end
        local _, attached = call(item, "attachWeaponPart", nil, part)
        if not attached and not item.attachWeaponPart then return nil, "weaponPartUnsupported" end
    end
    return item
end

function Snapshot.restore(data)
    local report = { simplified = false, omitted = 0, reasons = {} }
    local item, reason = restoreItem(data, 1, report)
    if not item then return result(false, reason, { report = report }) end
    return result(true, "restored", { item = item, report = report })
end

function Snapshot.count(data)
    if type(data) ~= "table" then return 0 end
    local stackCount = finite(data.count)
    local count = math.max(1, math.floor(stackCount or 1))
    for i = 1, #(data.children or {}) do count = count + Snapshot.count(data.children[i]) end
    for i = 1, #(data.weaponParts or {}) do count = count + Snapshot.count(data.weaponParts[i]) end
    return count
end

function Snapshot.health()
    return result(instanceItem ~= nil, instanceItem and "ok" or "factoryUnavailable", {
        schemaVersion = Snapshot.SchemaVersion,
        maxDepth = Snapshot.MaxDepth,
        adapterCount = #FIELD_ADAPTERS,
    })
end

return Snapshot
