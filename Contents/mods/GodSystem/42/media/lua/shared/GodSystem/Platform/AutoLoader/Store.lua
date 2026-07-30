require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderStorePlatform = GodSystemAutoLoaderStorePlatform or {}

local Descriptor = GodSystemAutoLoaderStorePlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "autoloader.store"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function configuredCapacity()
    local fallback = Support.integer(
        GodSystemConfig and GodSystemConfig.AutoLoaderAmmoCapacity,
        2000, 100, 10000)
    if GodSystemAdminConfig and type(GodSystemAdminConfig.getSetting) == "function" then
        local ok, value = pcall(
            GodSystemAdminConfig.getSetting, "AutoLoaderAmmoCapacity", fallback)
        if ok then return Support.integer(value, fallback, 100, 10000) end
    end
    return fallback
end

local function loaderStore(loader, create)
    if Support.fullType(loader) ~= Support.FullType then return nil end
    local modData = Support.safeCall(loader, "getModData", nil)
    if type(modData) ~= "table" then return nil end
    local value = modData[Support.DataKey]
    if type(value) ~= "table" and create then
        value = { version = 1, ammo = {}, names = {} }
        modData[Support.DataKey] = value
    end
    if type(value) ~= "table" then return nil end
    value.version = 1
    value.ammo = type(value.ammo) == "table" and value.ammo or {}
    value.names = type(value.names) == "table" and value.names or {}
    for fullType, count in pairs(value.ammo) do
        local key = tostring(fullType or "")
        local normalized = Support.integer(count, 0, 0)
        if key == "" or normalized <= 0 then
            value.ammo[fullType] = nil
        else
            value.ammo[fullType] = normalized
        end
    end
    return value
end

function Descriptor.create()
    local instance = {
        started = false,
        reads = 0,
        writes = 0,
        failures = 0,
    }

    instance.public = {
        capacity = function()
            instance.reads = instance.reads + 1
            return configuredCapacity()
        end,
        getBalance = function(loader, fullType)
            instance.reads = instance.reads + 1
            local value = loaderStore(loader, false)
            if not value then return 0 end
            return Support.integer(value.ammo[tostring(fullType or "")], 0, 0)
        end,
        setBalance = function(loader, fullType, count, name)
            local key = tostring(fullType or "")
            if key == "" then instance.failures = instance.failures + 1 return false, "ammoTypeRequired" end
            local value = loaderStore(loader, true)
            if not value then instance.failures = instance.failures + 1 return false, "loaderStoreMissing" end
            count = Support.integer(count, 0, 0)
            value.ammo[key] = count > 0 and count or nil
            if name and tostring(name) ~= "" then value.names[key] = tostring(name) end
            instance.writes = instance.writes + 1
            return true
        end,
        entries = function(loader)
            instance.reads = instance.reads + 1
            local value = loaderStore(loader, true)
            if not value then return {} end
            local rows = {}
            for fullType, count in pairs(value.ammo) do
                rows[#rows + 1] = {
                    fullType = tostring(fullType),
                    count = Support.integer(count, 0, 0),
                    name = value.names[fullType],
                }
            end
            return rows
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
            code = self.failures > 0 and "storeFailure" or (self.started and "healthy" or "stopped"),
            data = { reads = self.reads, writes = self.writes, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
