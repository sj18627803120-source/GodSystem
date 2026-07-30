require "GodSystem/Platform/Progression/Support"

GodSystemHomeConfigPlatform = GodSystemHomeConfigPlatform or {}

local Descriptor = GodSystemHomeConfigPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "home.config"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local DEFAULTS = {
    EnableTeleport = true,
    HomeSetCost = 100,
    HomeTravelCost = 10,
    TempTeleportSlotCost = 500,
    TempTeleportSetCost = 100,
    TempTeleportMaxSlots = 3,
    HomeSafeZoneLevels = {
        { level = 1, radius = 12, unlockCost = 500, clearCost = 8 },
        { level = 2, radius = 20, upgradeCost = 1000, clearCost = 12 },
        { level = 3, radius = 30, upgradeCost = 2000, clearCost = 18 },
        { level = 4, radius = 45, upgradeCost = 3500, clearCost = 28 },
        { level = 5, radius = 60, upgradeCost = 5500, clearCost = 40 },
    },
}

function Descriptor.create(_, context)
    local config = Support.config(context, DEFAULTS)
    local counters = { reads = 0, rejected = 0 }
    local public = {}

    local function levelInfo(level)
        level = Support.integer(level, nil, 1)
        local rows = type(config.HomeSafeZoneLevels) == "table" and config.HomeSafeZoneLevels or {}
        if not level then return nil end
        for index = 1, #rows do
            if Support.integer(rows[index].level, index, 1) == level then
                return Support.copy(rows[index])
            end
        end
        return nil
    end

    function public.isEnabled()
        counters.reads = counters.reads + 1
        return config.EnableTeleport ~= false
    end
    function public.maxTempSlots()
        counters.reads = counters.reads + 1
        return Support.integer(config.TempTeleportMaxSlots, 3, 0)
    end
    function public.safeLevel(level)
        counters.reads = counters.reads + 1
        return levelInfo(level)
    end
    function public.nextSafeLevel(level)
        counters.reads = counters.reads + 1
        return levelInfo((Support.integer(level, 0, 0) or 0) + 1)
    end
    function public.cost(action, _, data)
        counters.reads = counters.reads + 1
        action = tostring(action or "")
        local keyByAction = {
            setHome = "HomeSetCost",
            teleportHome = "HomeTravelCost",
            teleportTemp = "HomeTravelCost",
            ["return"] = "HomeTravelCost",
            buyTemp = "TempTeleportSlotCost",
            setTemp = "TempTeleportSetCost",
        }
        local key = keyByAction[action]
        if key then return Support.integer(config[key], nil, 0) end
        if action == "clearSafeZone" then
            local level = data and data.homeSystem and data.homeSystem.safeZone
                and data.homeSystem.safeZone.level or 0
            local row = levelInfo(level)
            return row and Support.integer(row.clearCost, nil, 0) or nil
        end
        counters.rejected = counters.rejected + 1
        return nil
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
