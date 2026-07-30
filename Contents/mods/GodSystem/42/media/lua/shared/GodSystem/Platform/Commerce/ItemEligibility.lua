require "GodSystem/Platform/Commerce/Support"

GodSystemItemEligibilityPlatform = GodSystemItemEligibilityPlatform or {}

local Descriptor = GodSystemItemEligibilityPlatform
local Support = GodSystemCommercePlatformSupport

Descriptor.id = "item.eligibility"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local EXACT_BLACKLIST = {
    ["Base.TestHotDrink"] = true,
    ["Base.TestMug"] = true,
    ["Base.TestWaterMug"] = true,
    ["Base.Animal_Item_Dummy"] = true,
}

local function compact(value)
    return tostring(value or ""):lower():gsub("[^a-z0-9]+", "")
end

local function forbiddenName(fullType)
    if tostring(fullType):sub(1, 12) == "Base.ZedDmg_" then return true end
    local moduleName, itemName = tostring(fullType):match("^([^%.]+)%.(.+)$")
    if moduleName ~= "Base" or not itemName then return false end
    local name = itemName:lower()
    return name:find("_dummy", 1, true) ~= nil
        or name:find("debug", 1, true) ~= nil
        or name:find("hidden", 1, true) ~= nil
        or name:find("placeholder", 1, true) ~= nil
        or name:find("template", 1, true) ~= nil
        or name:find("unused", 1, true) ~= nil
end

local function scriptAllowed(fullType, usage)
    if fullType == "" or EXACT_BLACKLIST[fullType] or forbiddenName(fullType) then return false end
    local item = Support.scriptItem(fullType)
    if not item then return false end
    local obsolete = Support.safeCall(item, "getObsolete", nil)
    local hidden = Support.safeCall(item, "isHidden", nil)
    if obsolete == true or hidden == true then return false end
    if tostring(usage or "") == "lottery" and (obsolete == nil or hidden == nil) then return false end
    local displayCategory = compact(Support.safeCall(item, "getDisplayCategory", ""))
    if displayCategory == "zeddmg" or displayCategory == "wound" then return false end
    local bodyLocation = compact(Support.safeCall(item, "getBodyLocation", ""))
    if bodyLocation:find("zeddmg", 1, true)
        or bodyLocation:find("wound", 1, true)
        or bodyLocation:find("bandage", 1, true)
    then
        return false
    end
    return true
end

function Descriptor.create(_, context)
    local snapshot = type(context) == "table" and context.configSnapshot or {}
    local config = type(snapshot) == "table" and snapshot.eligibility or {}
    local recycleBlacklist = type(config.recycleBlacklist) == "table"
        and config.recycleBlacklist or {}
    local shopBlacklist = type(config.shopBlacklist) == "table" and config.shopBlacklist or {}
    local allowedModules = type(config.allowedModules) == "table" and config.allowedModules or {}
    local allowAnyModule = config.allowAnyModule ~= false
    local instance = { started = false, checked = 0, rejected = 0 }

    local function reject()
        instance.rejected = instance.rejected + 1
        return false
    end

    local function allowed(fullType, usage)
        instance.checked = instance.checked + 1
        fullType = tostring(fullType or "")
        if shopBlacklist[fullType] or recycleBlacklist[fullType] then
            return reject(), "itemNotEligible"
        end
        if not scriptAllowed(fullType, usage) then return reject(), "itemNotEligible" end
        return true
    end

    local function canRecycle(item)
        instance.checked = instance.checked + 1
        if type(item) ~= "table" or tostring(item.fullType or "") == "" then
            return reject(), "invalid"
        end
        if item.protected == true or item.key == true or recycleBlacklist[item.fullType] then
            return reject(), "protected"
        end
        if item.hasInventory == true and config.allowRecycleContainers ~= true then
            return reject(), "container"
        end
        if not scriptAllowed(item.fullType, "recycle") then return reject(), "invalid" end
        if tonumber(item.sellPrice or item.value or 0) <= 0 then return reject(), "invalid" end
        return true
    end

    instance.public = {
        allowed = allowed,
        canRecycle = canRecycle,
        canList = function(item)
            local ok, code = canRecycle(item)
            if not ok then return false, code end
            local moduleName = Support.moduleName(item.fullType)
            if shopBlacklist[item.fullType] then return reject(), "notListable" end
            if allowAnyModule then return moduleName ~= nil, moduleName and nil or "notListable" end
            return moduleName ~= nil and allowedModules[moduleName] == true,
                "notListable"
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { checked = self.checked, rejected = self.rejected },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
