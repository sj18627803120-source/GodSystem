require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderAmmoCatalogPlatform = GodSystemAutoLoaderAmmoCatalogPlatform or {}

local Descriptor = GodSystemAutoLoaderAmmoCatalogPlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "ammo.catalog"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function scriptItem(fullType)
    if type(getScriptManager) ~= "function" then return nil end
    local okManager, manager = pcall(getScriptManager)
    if not okManager or not manager or type(manager.FindItem) ~= "function" then return nil end
    local okItem, item = pcall(manager.FindItem, manager, tostring(fullType or ""))
    return okItem and item or nil
end

function Descriptor.create()
    local instance = {
        started = false,
        queries = 0,
        failures = 0,
    }

    local function itemId(item)
        instance.queries = instance.queries + 1
        return Support.itemId(item)
    end

    local function fullType(item)
        instance.queries = instance.queries + 1
        return Support.fullType(item)
    end

    local function displayName(value, fallback)
        instance.queries = instance.queries + 1
        if value and type(value) ~= "string" then
            local direct = Support.safeCall(value, "getDisplayName", nil)
            if direct and tostring(direct) ~= "" then return tostring(direct) end
            value = Support.fullType(value)
        end
        local registered = scriptItem(value)
        local name = Support.safeCall(registered, "getDisplayName", nil)
        if name and tostring(name) ~= "" then return tostring(name) end
        return tostring(fallback or value or "")
    end

    local function isLooseAmmo(item)
        instance.queries = instance.queries + 1
        if not item or type(item.hasTag) ~= "function" or not ItemTag or not ItemTag.AMMO then
            return false
        end
        local ok, value = pcall(item.hasTag, item, ItemTag.AMMO)
        if not ok then instance.failures = instance.failures + 1 end
        return ok and value == true
    end

    local function isHandWeapon(item)
        if not item or type(instanceof) ~= "function" then return false end
        local ok, value = pcall(instanceof, item, "HandWeapon")
        if not ok then instance.failures = instance.failures + 1 end
        return ok and value == true
    end

    local function magazineAmmoType(item)
        instance.queries = instance.queries + 1
        if not item or isHandWeapon(item) then return nil end
        local ammoType = Support.safeCall(item, "getAmmoType", nil)
        local maximum = Support.integer(Support.safeCall(item, "getMaxAmmo", 0), 0, 0)
        if not ammoType or maximum <= 0 or type(ammoType.getItemKey) ~= "function" then return nil end
        local ok, key = pcall(ammoType.getItemKey, ammoType)
        if not ok then instance.failures = instance.failures + 1 return nil end
        key = tostring(key or "")
        return key ~= "" and key or nil
    end

    local function isProtected(item)
        instance.queries = instance.queries + 1
        local itemType = Support.fullType(item)
        if itemType == Support.FullType then return true end
        local blacklist = GodSystemConfig and GodSystemConfig.RecycleBlacklist or nil
        return type(blacklist) == "table" and blacklist[itemType] == true
    end

    instance.public = {
        itemId = itemId,
        fullType = fullType,
        displayName = displayName,
        isLooseAmmo = isLooseAmmo,
        isFavorite = function(item)
            instance.queries = instance.queries + 1
            return Support.safeCall(item, "isFavorite", false) == true
        end,
        isProtected = isProtected,
        isAvailable = function(value)
            instance.queries = instance.queries + 1
            return scriptItem(value) ~= nil
        end,
        magazineAmmoType = magazineAmmoType,
        magazineRounds = function(item)
            instance.queries = instance.queries + 1
            return Support.integer(Support.safeCall(item, "getCurrentAmmoCount", 0), 0, 0)
        end,
        magazineCapacity = function(item)
            instance.queries = instance.queries + 1
            return Support.integer(Support.safeCall(item, "getMaxAmmo", 0), 0, 0)
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "catalogFailure" or (self.started and "healthy" or "stopped"),
            data = { queries = self.queries, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
