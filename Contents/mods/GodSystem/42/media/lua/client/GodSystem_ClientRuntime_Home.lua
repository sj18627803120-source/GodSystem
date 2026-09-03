_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Home"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Home then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_Home = true
    setfenv(1, runtimeEnvironment)

function gsCurrentPosition()
    local player = gsPlayer()
    if not player then
        return nil
    end
    return {
        x = tonumber(player:getX()) or 0,
        y = tonumber(player:getY()) or 0,
        z = tonumber(player:getZ()) or 0,
    }
end

function gsCopyPosition(pos)
    if not pos then
        return nil
    end
    return {
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
        label = pos.label,
        source = pos.source,
    }
end

function GodSystemApp.services.runtime.formatPosition(pos)
    if not pos then
        return GodSystemApp.services.runtime.text("Home_NotSet", "Not set")
    end
    return "X:" .. tostring(math.floor(tonumber(pos.x) or 0)) ..
        " Y:" .. tostring(math.floor(tonumber(pos.y) or 0)) ..
        " Z:" .. tostring(math.floor(tonumber(pos.z) or 0))
end

function gsSafeBoolCall(object, methodName)
    local ok, value = GodSystemB42JavaCalls.try(object, methodName)
    return ok and value == true
end

function gsTeleportBlockedReason(player)
    if not player then
        return GodSystemApp.services.runtime.text("Notify_HomeNoPlayer", "Player not found")
    end
    if player.getVehicle then
        local ok, vehicle = pcall(function() return player:getVehicle() end)
        if ok and vehicle then
            return GodSystemApp.services.runtime.text("Notify_HomeInVehicle", "Cannot teleport while in a vehicle")
        end
    end
    return nil
end

function gsGridSquareAt(pos)
    if not pos or not getCell then
        return nil
    end
    local cell = getCell()
    if not cell or not cell.getGridSquare then
        return nil
    end
    local x = math.floor(tonumber(pos.x) or 0)
    local y = math.floor(tonumber(pos.y) or 0)
    local z = math.floor(tonumber(pos.z) or 0)
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    if ok then
        return square
    end
    return nil
end

function gsSquareIsSafe(square)
    if not square then
        return nil
    end
    if gsSafeBoolCall(square, "isSolid") or gsSafeBoolCall(square, "isSolidTrans") then
        return false
    end
    if square.TreatAsSolidFloor then
        local ok, hasFloor = pcall(function() return square:TreatAsSolidFloor() end)
        if ok and hasFloor == false then
            return false
        end
    end
    return true
end

function GodSystemApp.services.runtime.findSafeTeleportPosition(pos)
    if not pos then
        return nil
    end
    local base = gsCopyPosition(pos)
    local square = gsGridSquareAt(base)
    local safe = gsSquareIsSafe(square)
    if safe == true or safe == nil then
        return base
    end
    local radiusLimit = 4
    for radius = 1, radiusLimit do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local candidate = {
                        x = math.floor(base.x) + dx + 0.5,
                        y = math.floor(base.y) + dy + 0.5,
                        z = base.z,
                    }
                    if gsSquareIsSafe(gsGridSquareAt(candidate)) == true then
                        return candidate
                    end
                end
            end
        end
    end
    return nil
end

function GodSystemApp.services.runtime.getHomeSystem()
    local data = GodSystemApp.services.runtime.getData()
    data.homeSystem = data.homeSystem or {}
    data.homeSystem.tempSlots = data.homeSystem.tempSlots or {}
    data.homeSystem.safeZone = data.homeSystem.safeZone or {}
    data.homeSystem.safeZone.level = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.level) or 0))
    data.homeSystem.safeZone.enabled = data.homeSystem.safeZone.enabled == true
    data.homeSystem.safeZone.lastScanHours = tonumber(data.homeSystem.safeZone.lastScanHours) or 0
    data.homeSystem.safeZone.lastNoticeHours = tonumber(data.homeSystem.safeZone.lastNoticeHours) or -999
    data.homeSystem.safeZone.lastCleared = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.lastCleared) or 0))
    data.homeSystem.safeZone.lastClearHour = tonumber(data.homeSystem.safeZone.lastClearHour) or 0
    data.homeSystem.safeZone.nextZombieScanIndex = math.max(0, math.floor(tonumber(data.homeSystem.safeZone.nextZombieScanIndex) or 0))
    local limit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, limit do
        data.homeSystem.tempSlots[i] = data.homeSystem.tempSlots[i] or { owned = false, point = nil }
    end
    return data.homeSystem
end

function gsHomeSafeZoneLevels()
    return GodSystemConfig.HomeSafeZoneLevels or {}
end

function gsHomeSafeZoneLevelConfig(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    local levels = gsHomeSafeZoneLevels()
    for i = 1, #levels do
        if math.floor(tonumber(levels[i].level) or 0) == level then
            return levels[i]
        end
    end
    return nil
end

function gsHomeSafeZoneFirstLevel()
    local levels = gsHomeSafeZoneLevels()
    return levels[1]
end

function gsHomeSafeZoneNextLevel(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    local levels = gsHomeSafeZoneLevels()
    for i = 1, #levels do
        local cfg = levels[i]
        if math.floor(tonumber(cfg.level) or 0) > level then
            return cfg
        end
    end
    return nil
end

function gsHomeSafeZoneMaxLevel()
    local levels = gsHomeSafeZoneLevels()
    local maxLevel = 0
    for i = 1, #levels do
        maxLevel = math.max(maxLevel, math.floor(tonumber(levels[i].level) or 0))
    end
    return maxLevel
end

function GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local safe = home.safeZone or {}
    local level = math.max(0, math.floor(tonumber(safe.level) or 0))
    local current = gsHomeSafeZoneLevelConfig(level)
    local nextLevel = gsHomeSafeZoneNextLevel(level)
    local firstLevel = gsHomeSafeZoneFirstLevel()
    local clearCost = current and current.clearCost or (firstLevel and firstLevel.clearCost) or 0
    return {
        homeSet = home.home ~= nil,
        center = home.home,
        level = level,
        maxLevel = gsHomeSafeZoneMaxLevel(),
        unlocked = level > 0 and current ~= nil,
        enabled = safe.enabled == true,
        radius = current and (current.radius or 0) or 0,
        clearCost = clearCost or 0,
        unlockCost = firstLevel and (firstLevel.unlockCost or firstLevel.upgradeCost or 0) or 0,
        nextLevel = nextLevel,
        intervalHours = GodSystemRuntimeConfig.get("HomeSafeZoneScanIntervalHours", 1),
        lastCleared = safe.lastCleared or 0,
        lastClearHour = safe.lastClearHour or 0,
    }
end

function GodSystemApp.services.runtime.getHomeSafeZoneDetailText(info)
    info = info or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    if not info.homeSet then
        return GodSystemApp.services.runtime.text("HomeSafe_NeedHome", "Set a home first.")
    end
    local center = GodSystemApp.services.runtime.formatPosition(info.center)
    if not info.unlocked then
        return GodSystemApp.services.runtime.text("HomeSafe_Locked", "Locked") .. " | " ..
            GodSystemApp.services.runtime.text("HomeSafe_Center", "Center: ") .. center .. " | " ..
            GodSystemApp.services.runtime.text("HomeSafe_UnlockCost", "Unlock cost ") .. tostring(info.unlockCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    local state = info.enabled and GodSystemApp.services.runtime.text("HomeSafe_Enabled", "Enabled") or GodSystemApp.services.runtime.text("HomeSafe_Disabled", "Paused")
    local nextText = GodSystemApp.services.runtime.text("Upgrade_Maxed", "Maxed")
    if info.nextLevel then
        nextText = "Lv." .. tostring(info.nextLevel.level) .. " " ..
            GodSystemApp.services.runtime.text("HomeSafe_Radius", "Radius ") .. tostring(info.nextLevel.radius or 0) .. " | " ..
            GodSystemApp.services.runtime.text("Upgrade_Cost", "Cost") .. " " .. tostring(info.nextLevel.upgradeCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    return state .. " | Lv." .. tostring(info.level) .. "/" .. tostring(info.maxLevel) ..
        " | " .. GodSystemApp.services.runtime.text("HomeSafe_Center", "Center: ") .. center ..
        " | " .. GodSystemApp.services.runtime.text("HomeSafe_Radius", "Radius ") .. tostring(info.radius or 0) ..
        " | " .. GodSystemApp.services.runtime.text("HomeSafe_ClearCost", "Clear cost ") .. tostring(info.clearCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") ..
        " | " .. GodSystemApp.services.runtime.text("HomeSafe_Interval", "Interval ") .. tostring(info.intervalHours or 0.5) .. GodSystemApp.services.runtime.text("Unit_Hour", "h") ..
        " | " .. GodSystemApp.services.runtime.text("HomeSafe_LastClear", "Last clear ") .. tostring(info.lastCleared or 0) ..
        " | " .. GodSystemApp.services.runtime.text("Upgrade_Next", "Next") .. " " .. nextText
end

function GodSystemApp.services.runtime.getHomeEntries()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local entries = {}
    table.insert(entries, { kind = "home", label = GodSystemApp.services.runtime.text("Home_HomePoint", "Home"), point = home.home })
    local safeInfo = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    table.insert(entries, { kind = "safeZone", label = GodSystemApp.services.runtime.text("HomeSafe_Title", "Home safe zone"), safeZone = safeInfo })
    if home.returnPoint then
        table.insert(entries, { kind = "return", label = GodSystemApp.services.runtime.text("Home_ReturnPoint", "Return point"), point = home.returnPoint })
    end
    local limit = GodSystemConfig.TempTeleportMaxSlots or 3
    for i = 1, limit do
        local slot = home.tempSlots[i] or { owned = false, point = nil }
        table.insert(entries, { kind = "temp", index = i, label = GodSystemApp.services.runtime.text("Home_TempPoint", "Temp point ") .. tostring(i), owned = slot.owned == true, point = slot.point })
    end
    return entries
end

function GodSystemApp.services.runtime.getHomeEntryDetail(entry)
    if not entry then
        return ""
    end
    if entry.kind == "home" then
        return GodSystemApp.services.runtime.formatPosition(entry.point) .. " | " .. GodSystemApp.services.runtime.text("Home_SetCost", "Set ") .. tostring(GodSystemConfig.HomeSetCost or 100) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") .. " | " .. GodSystemApp.services.runtime.text("Home_TravelCost", "Travel ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    if entry.kind == "return" then
        return GodSystemApp.services.runtime.formatPosition(entry.point) .. " | " .. GodSystemApp.services.runtime.text("Home_ReturnCost", "Return ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    if entry.kind == "temp" then
        if not entry.owned then
            return GodSystemApp.services.runtime.text("Home_TempLocked", "Not purchased") .. " | " .. tostring(GodSystemConfig.TempTeleportSlotCost or 500) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        end
        return GodSystemApp.services.runtime.formatPosition(entry.point) .. " | " .. GodSystemApp.services.runtime.text("Home_SetCost", "Set ") .. tostring(GodSystemConfig.TempTeleportSetCost or 100) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") .. " | " .. GodSystemApp.services.runtime.text("Home_TravelCost", "Travel ") .. tostring(GodSystemConfig.HomeTravelCost or 10) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    if entry.kind == "safeZone" then
        return GodSystemApp.services.runtime.getHomeSafeZoneDetailText(entry.safeZone)
    end
    return ""
end

function gsSpendTeleportCost(cost, historyText)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if cost > 0 and not GodSystemApp.services.runtime.canAfford(cost) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    if cost > 0 and not GodSystemApp.services.runtime.addPoints(-cost) then
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    if historyText then
        gsAppendHistory(data, { kind = "home", text = historyText .. " -" .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    end
    return true
end

function GodSystemApp.services.runtime.setHomePoint()
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTeleport") == false then
        GodSystemApp.services.runtime.notify("Teleport disabled")
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystemApp.services.runtime.notify(reason)
        return false
    end
    local pos = gsCurrentPosition()
    if not pos or not GodSystemApp.services.runtime.findSafeTeleportPosition(pos) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.HomeSetCost or 100
    if not gsSpendTeleportCost(cost, GodSystemApp.services.runtime.text("History_HomeSet", "Set home")) then
        return false
    end
    local home = GodSystemApp.services.runtime.getHomeSystem()
    home.home = gsCopyPosition(pos)
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSet", "Home set: ") .. GodSystemApp.services.runtime.formatPosition(home.home))
    return true
end

function GodSystemApp.services.runtime.buyTempTeleportSlot(index)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTeleport") == false then
        GodSystemApp.services.runtime.notify("Teleport disabled")
        return false
    end
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystemApp.services.runtime.getHomeSystem()
    if index > (GodSystemConfig.TempTeleportMaxSlots or 3) then
        return false
    end
    home.tempSlots[index] = home.tempSlots[index] or { owned = false, point = nil }
    if home.tempSlots[index].owned then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempOwned", "Temp point already purchased"))
        return false
    end
    local cost = GodSystemConfig.TempTeleportSlotCost or 500
    if not gsSpendTeleportCost(cost, GodSystemApp.services.runtime.text("History_HomeTempBought", "Bought temp teleport point ") .. tostring(index)) then
        return false
    end
    home.tempSlots[index].owned = true
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempBought", "Temp teleport point purchased: ") .. tostring(index))
    return true
end

function GodSystemApp.services.runtime.setTempTeleportPoint(index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local slot = home.tempSlots[index]
    if not slot or slot.owned ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempLocked", "Temp point not purchased"))
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystemApp.services.runtime.notify(reason)
        return false
    end
    local pos = gsCurrentPosition()
    if not pos or not GodSystemApp.services.runtime.findSafeTeleportPosition(pos) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.TempTeleportSetCost or 100
    if not gsSpendTeleportCost(cost, GodSystemApp.services.runtime.text("History_HomeTempSet", "Set temp teleport point ") .. tostring(index)) then
        return false
    end
    slot.point = gsCopyPosition(pos)
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempSet", "Temp teleport point set: ") .. tostring(index))
    return true
end

function gsTeleportToPosition(target, returnLabel, historyText)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTeleport") == false then
        GodSystemApp.services.runtime.notify("Teleport disabled")
        return false
    end
    local player = gsPlayer()
    local reason = gsTeleportBlockedReason(player)
    if reason then
        GodSystemApp.services.runtime.notify(reason)
        return false
    end
    local safe = GodSystemApp.services.runtime.findSafeTeleportPosition(target)
    if not safe then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeUnsafe", "No safe position found"))
        return false
    end
    local cost = GodSystemConfig.HomeTravelCost or 10
    if not gsSpendTeleportCost(cost, historyText) then
        return false
    end
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local current = gsCurrentPosition()
    if returnLabel and current then
        home.returnPoint = current
        home.returnPoint.source = returnLabel
    end
    GodSystemApp.services.runtime.applyApprovedTeleport(safe)
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTeleported", "Teleported: ") .. GodSystemApp.services.runtime.formatPosition(safe))
    return true
end

function GodSystemApp.services.runtime.teleportHome()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    if not home.home then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNotSet", "Home is not set"))
        return false
    end
    return gsTeleportToPosition(home.home, GodSystemApp.services.runtime.text("Home_ReturnSourceHome", "before returning home"), GodSystemApp.services.runtime.text("History_HomeTeleport", "Teleport home"))
end

function GodSystemApp.services.runtime.teleportTemp(index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local slot = home.tempSlots[index]
    if not slot or slot.owned ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempLocked", "Temp point not purchased"))
        return false
    end
    if not slot.point then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTempNotSet", "Temp point is not set"))
        return false
    end
    return gsTeleportToPosition(slot.point, GodSystemApp.services.runtime.text("Home_TempPoint", "Temp point ") .. tostring(index), GodSystemApp.services.runtime.text("History_HomeTempTeleport", "Teleport temp point ") .. tostring(index))
end

function GodSystemApp.services.runtime.teleportReturn()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    if not home.returnPoint then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNoReturn", "No return point"))
        return false
    end
    local target = gsCopyPosition(home.returnPoint)
    local source = target.source
    local ok = gsTeleportToPosition(target, nil, GodSystemApp.services.runtime.text("History_HomeReturn", "Return to departure point"))
    if ok then
        home.returnPoint = nil
        GodSystemApp.services.runtime.save()
        if source then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeReturnedFrom", "Returned from: ") .. tostring(source))
        end
    end
    return ok
end

function GodSystemApp.services.runtime.applyApprovedTeleport(pos)
    local player = gsPlayer()
    if not player or not pos then
        return false
    end
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z) or 0
    if not x or not y then
        return false
    end
    if player.teleportTo then
        local ok = pcall(function() player:teleportTo(x, y, z) end)
        if ok then
            return true
        end
    end
    if player.setX and player.setY and player.setZ then
        player:setX(x)
        player:setY(y)
        player:setZ(z)
        if player.setLastX then player:setLastX(x) end
        if player.setLastY then player:setLastY(y) end
        if player.setLastZ then player:setLastZ(z) end
        return true
    end
    return false
end

function GodSystemApp.services.runtime.clearHomeReturnPoint()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    if not home.returnPoint then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNoReturn", "No return point"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    home.returnPoint = nil
    gsAppendHistory(data, { kind = "home", text = GodSystemApp.services.runtime.text("History_HomeReturnCleared", "Clear departure point") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeReturnCleared", "Departure point cleared"))
    return true
end

function GodSystemApp.services.runtime.unlockHomeSafeZone()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    if not info.homeSet then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_NeedHome", "Set a home first."))
        return false
    end
    if info.unlocked then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeAlreadyUnlocked", "Home safe zone is already unlocked"))
        return false
    end
    local firstLevel = gsHomeSafeZoneFirstLevel()
    if not firstLevel then
        return false
    end
    local cost = firstLevel.unlockCost or firstLevel.upgradeCost or 0
    if not gsSpendTeleportCost(cost, GodSystemApp.services.runtime.text("History_HomeSafeUnlock", "Unlock home safe zone")) then
        return false
    end
    home.safeZone.level = math.floor(tonumber(firstLevel.level) or 1)
    home.safeZone.enabled = true
    home.safeZone.lastScanHours = gsNowHours()
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeUnlocked", "Home safe zone unlocked"))
    return true
end

function GodSystemApp.services.runtime.upgradeHomeSafeZone()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    if not info.homeSet then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_NeedHome", "Set a home first."))
        return false
    end
    if not info.unlocked then
        return GodSystemApp.services.runtime.unlockHomeSafeZone()
    end
    local nextLevel = info.nextLevel
    if not nextLevel then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeMaxLevel", "Home safe zone is already at max level"))
        return false
    end
    local cost = nextLevel.upgradeCost or 0
    if not gsSpendTeleportCost(cost, GodSystemApp.services.runtime.text("History_HomeSafeUpgrade", "Upgrade home safe zone") .. " Lv." .. tostring(nextLevel.level)) then
        return false
    end
    home.safeZone.level = math.floor(tonumber(nextLevel.level) or (info.level + 1))
    home.safeZone.enabled = true
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeUpgraded", "Home safe zone upgraded to Lv.") .. tostring(home.safeZone.level))
    return true
end

function GodSystemApp.services.runtime.toggleHomeSafeZone()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    if not info.unlocked then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_Locked", "Locked"))
        return false
    end
    home.safeZone.enabled = not home.safeZone.enabled
    GodSystemApp.services.runtime.save()
    if home.safeZone.enabled then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeEnabled", "Home safe zone enabled"))
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeDisabled", "Home safe zone paused"))
    end
    return true
end

function gsCollectHomeSafeZoneZombies(center, radius, scanStart, scanBudget)
    local result = {}
    if not center or not radius or radius <= 0 or not getCell then
        return result, 0, 0
    end
    local cell = getCell()
    if not cell or not cell.getZombieList then
        return result, 0, 0
    end
    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not okList or not zombies or not zombies.size or not zombies.get then
        return result, 0, 0
    end
    local okSize, size = pcall(function() return zombies:size() end)
    if not okSize or not size or size <= 0 then
        return result, 0, 0
    end
    local radiusSq = radius * radius
    local budget = math.max(1, math.floor(tonumber(scanBudget) or 256))
    local index = math.max(0, math.floor(tonumber(scanStart) or 0))
    if index >= size then index = 0 end
    local inspected = 0
    while inspected < budget and inspected < size do
        local okZombie, zombie = pcall(function() return zombies:get(index) end)
        index = index + 1
        if index >= size then index = 0 end
        inspected = inspected + 1
        if okZombie and zombie and zombie.getX and zombie.getY then
            local dead = false
            if zombie.isDead then
                local okDead, isDead = pcall(function() return zombie:isDead() end)
                dead = okDead and isDead == true
            end
            if not dead then
                local okPos, zx, zy = pcall(function() return zombie:getX(), zombie:getY() end)
                if okPos then
                    local dx = (tonumber(zx) or 0) - (tonumber(center.x) or 0)
                    local dy = (tonumber(zy) or 0) - (tonumber(center.y) or 0)
                    if (dx * dx) + (dy * dy) <= radiusSq then
                        result[#result + 1] = zombie
                    end
                end
            end
        end
    end
    return result, index, inspected
end

function gsRemoveZombieFromWorld(zombie)
    if not zombie then
        return false
    end
    local removed = false
    if zombie.removeFromWorld then
        local ok = pcall(function() zombie:removeFromWorld() end)
        removed = removed or ok
    end
    if zombie.removeFromSquare then
        local ok = pcall(function() zombie:removeFromSquare() end)
        removed = removed or ok
    end
    return removed
end

function GodSystemApp.services.runtime.clearHomeSafeZone(manual)
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    local safe = home.safeZone
    local now = gsNowHours()
    safe.lastScanHours = now
    if not info.homeSet then
        if manual then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_NeedHome", "Set a home first."))
        end
        return 0
    end
    if not info.unlocked then
        if manual then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_Locked", "Locked"))
        end
        return 0
    end
    if not manual and not info.enabled then
        return 0
    end

    local scanBudget = math.max(1, math.floor(tonumber(GodSystemRuntimeConfig.get("HomeSafeZoneScanBudget", 256)) or 256))
    local clearLimit = math.max(1, math.floor(tonumber(GodSystemRuntimeConfig.get("HomeSafeZoneClearLimit", 64)) or 64))
    local targets, nextZombieScanIndex = gsCollectHomeSafeZoneZombies(
        info.center,
        info.radius or 0,
        safe.nextZombieScanIndex,
        scanBudget
    )
    safe.nextZombieScanIndex = nextZombieScanIndex
    if #targets <= 0 then
        safe.lastCleared = 0
        GodSystemApp.services.runtime.save()
        if manual then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeNoZombie", "No zombies in the safe zone"))
        end
        return 0
    end

    local cost = math.max(0, math.floor(tonumber(info.clearCost) or 0))
    if cost > 0 and not GodSystemApp.services.runtime.canAfford(cost) then
        if manual or (now - (safe.lastNoticeHours or -999)) >= (GodSystemConfig.HomeSafeZoneInsufficientNoticeHours or 1) then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeNoMoney", "Not enough currency for safe zone cleanup"))
            safe.lastNoticeHours = now
            GodSystemApp.services.runtime.save()
        end
        return 0
    end

    local removed = 0
    for i = 1, math.min(#targets, clearLimit) do
        if gsRemoveZombieFromWorld(targets[i]) then
            removed = removed + 1
        end
    end

    safe.lastCleared = removed
    safe.lastClearHour = now
    if removed > 0 then
        if cost > 0 then
            if not GodSystemApp.services.runtime.addPoints(-cost) then
                return removed
            end
            local data = GodSystemApp.services.runtime.getData()
            data.stats = data.stats or {}
            data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
        end
        local data = GodSystemApp.services.runtime.getData()
        data.stats = data.stats or {}
        data.stats.homeSafeCleared = (data.stats.homeSafeCleared or 0) + removed
        gsAppendHistory(data, { kind = "home", text = GodSystemApp.services.runtime.text("History_HomeSafeClear", "Home safe zone cleared ") .. tostring(removed) .. GodSystemApp.services.runtime.text("HomeSafe_ZombieUnit", " zombies") .. " -" .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
        GodSystemApp.services.runtime.save()
        if manual then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeCleared", "Home safe zone cleared: ") .. tostring(removed))
        end
    end
    return removed
end

function GodSystemApp.services.runtime.updateHomeSafeZone()
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local safe = home.safeZone
    local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
    if not info.homeSet or not info.unlocked or not info.enabled then
        return
    end
    local now = gsNowHours()
    local interval = math.max(0.05, tonumber(info.intervalHours) or 0.5)
    if now - (safe.lastScanHours or 0) < interval then
        return
    end
    GodSystemApp.services.runtime.clearHomeSafeZone(false)
end

function GodSystemApp.services.runtime.performHomeAction(action, index)
    if action == "setHome" then
        return GodSystemApp.services.runtime.setHomePoint()
    elseif action == "buyTemp" then
        return GodSystemApp.services.runtime.buyTempTeleportSlot(index)
    elseif action == "setTemp" then
        return GodSystemApp.services.runtime.setTempTeleportPoint(index)
    elseif action == "teleportHome" then
        return GodSystemApp.services.runtime.teleportHome()
    elseif action == "teleportTemp" then
        return GodSystemApp.services.runtime.teleportTemp(index)
    elseif action == "return" then
        return GodSystemApp.services.runtime.teleportReturn()
    elseif action == "clearReturn" then
        return GodSystemApp.services.runtime.clearHomeReturnPoint()
    elseif action == "unlockSafeZone" then
        return GodSystemApp.services.runtime.unlockHomeSafeZone()
    elseif action == "upgradeSafeZone" then
        return GodSystemApp.services.runtime.upgradeHomeSafeZone()
    elseif action == "toggleSafeZone" then
        return GodSystemApp.services.runtime.toggleHomeSafeZone()
    elseif action == "clearSafeZone" then
        return GodSystemApp.services.runtime.clearHomeSafeZone(true)
    end
    return false
end
end
