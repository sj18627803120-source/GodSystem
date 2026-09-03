require "GodSystem_Config"

GodSystemItemEligibility = GodSystemItemEligibility or {}

local EXACT_BLACKLIST = {
    ["Base.TestHotDrink"] = true,
    ["Base.TestMug"] = true,
    ["Base.TestWaterMug"] = true,
    ["Base.Animal_Item_Dummy"] = true,
}

local ZED_DMG_PREFIX = "Base.ZedDmg_"

local function compactText(value)
    return tostring(value or ""):lower():gsub("[^a-z0-9]+", "")
end

local function findScriptItem(fullType)
    if not fullType or fullType == "" then
        return nil
    end
    if not getScriptManager then
        return nil
    end
    local okManager, manager = pcall(function()
        return getScriptManager()
    end)
    if not okManager or not manager then
        return nil
    end
    local okItem, scriptItem = pcall(function()
        return manager:FindItem(fullType)
    end)
    if okItem then
        return scriptItem
    end
    return nil
end

local function safeObsolete(scriptItem)
    local ok, value = pcall(function()
        return scriptItem:getObsolete()
    end)
    if not ok then
        return nil
    end
    return value == true
end

local function safeHidden(scriptItem)
    local ok, value = pcall(function()
        return scriptItem:isHidden()
    end)
    if not ok then
        return nil
    end
    return value == true
end

local function hasBodyLocation(scriptItem, bodyLocation)
    if bodyLocation == nil then
        return false
    end
    local ok, value = pcall(function()
        return scriptItem:isBodyLocation(bodyLocation)
    end)
    return ok and value == true
end

local function hasForbiddenBodyLocation(scriptItem)
    if ItemBodyLocation then
        if hasBodyLocation(scriptItem, ItemBodyLocation.ZED_DMG) then
            return true
        end
        if hasBodyLocation(scriptItem, ItemBodyLocation.WOUND) then
            return true
        end
        if hasBodyLocation(scriptItem, ItemBodyLocation.BANDAGE) then
            return true
        end
    end

    local ok, bodyLocation = pcall(function()
        return scriptItem:getBodyLocation()
    end)
    if ok and bodyLocation then
        local location = compactText(bodyLocation)
        if location:find("zeddmg", 1, true) or location:find("wound", 1, true) or location:find("bandage", 1, true) then
            return true
        end
    end
    return false
end

local function hasForbiddenDisplayCategory(scriptItem)
    local ok, displayCategory = pcall(function()
        return scriptItem:getDisplayCategory()
    end)
    if not ok or not displayCategory then
        return false
    end
    local category = compactText(displayCategory)
    return category == "zeddmg" or category == "wound"
end

local function hasForbiddenBaseName(fullType)
    if fullType:sub(1, #ZED_DMG_PREFIX) == ZED_DMG_PREFIX then
        return true
    end

    local moduleName, itemName = fullType:match("^([^%.]+)%.(.+)$")
    if moduleName ~= "Base" or not itemName then
        return false
    end

    local name = itemName:lower()
    if name:find("_dummy", 1, true) then return true end
    if name:find("debug", 1, true) then return true end
    if name:find("hidden", 1, true) then return true end
    if name:find("placeholder", 1, true) then return true end
    if name:find("template", 1, true) then return true end
    if name:find("unused", 1, true) then return true end
    return false
end

function GodSystemItemEligibility.isEconomicItemAllowed(fullType, context)
    fullType = tostring(fullType or "")
    if fullType == "" then
        return false
    end

    if EXACT_BLACKLIST[fullType] or hasForbiddenBaseName(fullType) then
        return false
    end

    local scriptItem = findScriptItem(fullType)
    if not scriptItem then
        return false
    end

    local obsolete = safeObsolete(scriptItem)
    if obsolete == true then
        return false
    end

    local hidden = safeHidden(scriptItem)
    if hidden == true then
        return false
    end

    if hasForbiddenDisplayCategory(scriptItem) then
        return false
    end

    if hasForbiddenBodyLocation(scriptItem) then
        return false
    end

    return true
end
