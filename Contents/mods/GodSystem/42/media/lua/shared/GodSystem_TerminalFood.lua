require "GodSystem_Config"

GodSystemTerminalFood = GodSystemTerminalFood or {}

local TerminalFood = GodSystemTerminalFood
local EPSILON = 0.0001

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function integer(value, fallback)
    value = tonumber(value)
    if not finite(value) then return fallback or 0 end
    return math.floor(value)
end

local function itemModData(item)
    if not item or not item.getModData then return nil end
    local ok, data = pcall(function() return item:getModData() end)
    return ok and type(data) == "table" and data or nil
end

local function terminalInventory(terminal)
    if not terminal or not terminal.getInventory then return nil end
    local ok, inventory = pcall(function() return terminal:getInventory() end)
    return ok and inventory or nil
end

local function getNumber(target, method)
    if not target or not target[method] then return nil end
    local ok, value = pcall(function() return target[method](target) end)
    value = ok and tonumber(value) or nil
    return finite(value) and value or nil
end

local function setNumber(target, setter, getter, value)
    if not target or not target[setter] or not target[getter] then return false, false, "unsupported" end
    local before = getNumber(target, getter)
    if before == nil then return false, false, "readFailed" end
    if math.abs(before - value) <= EPSILON then return true, false end
    local ok = pcall(function() target[setter](target, value) end)
    if not ok then return false, false, "writeException" end
    local after = getNumber(target, getter)
    if after == nil or math.abs(after - value) > EPSILON then return false, false, "verificationFailed" end
    return true, true
end

local function coolingLevel(level)
    return math.max(0, math.min(#(GodSystemConfig.TerminalCoolingLevels or {}), integer(level, 0)))
end

local function terminalFoodData(data)
    data.terminalFood = type(data.terminalFood) == "table" and data.terminalFood or {}
    return data.terminalFood
end

function TerminalFood.normalizeData(data)
    if type(data) ~= "table" then return data end
    local state = terminalFoodData(data)
    state.coolingLevel = coolingLevel(state.coolingLevel)
    state.remainingHours = math.max(0, integer(state.remainingHours, 0))
    state.lastSettledHour = finite(state.lastSettledHour) and tonumber(state.lastSettledHour) or nil
    state.expiryNotified = state.expiryNotified == true
    return data
end

function TerminalFood.getCoolingLevel(data)
    TerminalFood.normalizeData(data)
    return type(data) == "table" and coolingLevel(data.terminalFood and data.terminalFood.coolingLevel) or 0
end

function TerminalFood.setCoolingLevel(data, level)
    if type(data) ~= "table" then return false end
    TerminalFood.normalizeData(data)
    data.terminalFood.coolingLevel = coolingLevel(level)
    return true
end

function TerminalFood.getCoolingInfo(data)
    local levels = GodSystemConfig.TerminalCoolingLevels or {}
    local level = TerminalFood.getCoolingLevel(data)
    local current = levels[level]
    local nextRow = levels[level + 1]
    return {
        level = level,
        maxLevel = #levels,
        multiplier = current and tonumber(current.multiplier) or 1,
        ageFactor = current and tonumber(current.ageFactor) or 1,
        nextMultiplier = nextRow and tonumber(nextRow.multiplier) or nil,
        nextCost = nextRow and math.max(0, integer(nextRow.upgradeCost, 0)) or nil,
    }
end

function TerminalFood.getRemainingHours(data)
    TerminalFood.normalizeData(data)
    return type(data) == "table" and math.max(0, integer(data.terminalFood and data.terminalFood.remainingHours, 0)) or 0
end

function TerminalFood.getServiceInfo(data)
    local hours = TerminalFood.getRemainingHours(data)
    return {
        remainingHours = hours,
        remainingDays = hours / 24,
        maxHours = math.max(24, integer(GodSystemConfig.TerminalFreshnessMaxDays, 365) * 24),
        active = hours > 0,
        expired = type(data) == "table" and data.terminalFood and data.terminalFood.expiryNotified == true or false,
    }
end

function TerminalFood.getServiceCost(days)
    days = integer(days, 0)
    return math.max(0, integer((GodSystemConfig.TerminalFreshnessPackages or {})[days], 0))
end

function TerminalFood.canPurchaseService(data, days)
    local hours = math.max(0, integer(days, 0)) * 24
    if TerminalFood.getCoolingLevel(data) < 1 then return false, "coolingRequired" end
    if hours <= 0 or TerminalFood.getServiceCost(days) <= 0 then return false, "invalidPackage" end
    if TerminalFood.getRemainingHours(data) + hours > TerminalFood.getServiceInfo(data).maxHours then return false, "serviceCap" end
    return true
end

function TerminalFood.purchaseService(data, days, startedAtHour)
    local allowed, reason = TerminalFood.canPurchaseService(data, days)
    if not allowed then return false, reason end
    TerminalFood.normalizeData(data)
    local state = data.terminalFood
    state.remainingHours = TerminalFood.getRemainingHours(data) + integer(days, 0) * 24
    state.expiryNotified = false
    if finite(startedAtHour) then state.lastSettledHour = tonumber(startedAtHour) end
    return true, TerminalFood.getServiceCost(days)
end

function TerminalFood.beginOnlineSession(data, nowHour)
    if type(data) ~= "table" or not finite(nowHour) then return false end
    TerminalFood.normalizeData(data)
    data.terminalFood.lastSettledHour = tonumber(nowHour)
    return true
end

function TerminalFood.snapshotCooling(terminal)
    local inventory = terminalInventory(terminal)
    return {
        inventory = inventory,
        ageFactor = getNumber(inventory, "getAgeFactor"),
    }
end

function TerminalFood.restoreCooling(snapshot)
    if type(snapshot) ~= "table" or not snapshot.inventory or not finite(snapshot.ageFactor) then return true, false end
    return setNumber(snapshot.inventory, "setAgeFactor", "getAgeFactor", snapshot.ageFactor)
end

function TerminalFood.applyCooling(terminal, data)
    local inventory = terminalInventory(terminal)
    if not inventory then return false, { reason = "missingInventory" } end
    local info = TerminalFood.getCoolingInfo(data)
    if info.level <= 0 then
        return true, { level = 0, ageFactor = getNumber(inventory, "getAgeFactor"), changed = false }
    end
    local applied, changed, reason = setNumber(inventory, "setAgeFactor", "getAgeFactor", info.ageFactor)
    if not applied then return false, { reason = reason or "ageFactorUnsupported" } end
    local md = itemModData(terminal)
    if md then md[GodSystemConfig.TerminalCoolingLevelKey or "GodSystemTerminalCoolingLevel"] = info.level end
    return true, { level = info.level, ageFactor = info.ageFactor, multiplier = info.multiplier, changed = changed == true }
end

function TerminalFood.isEligibleFood(item)
    if not item or (instanceof and not instanceof(item, "Food")) then return false end
    if item.getFullType and tostring(item:getFullType() or "") == (GodSystemConfig.TerminalReliefFullType or "GodSystem.SystemTerminalRelief") then return false end
    if not item.getAge or not item.setAge or not item.getOffAge or not item.isRotten then return false end
    local ok, rotten = pcall(function() return item:isRotten() end)
    return ok and rotten ~= true
end

local function iterateDirectItems(inventory, callback)
    if not inventory or not inventory.getItems then return end
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items or not items.size or not items.get then return end
    for index = 0, items:size() - 1 do callback(items:get(index)) end
end

function TerminalFood.settle(data, terminal, elapsedHours)
    TerminalFood.normalizeData(data)
    elapsedHours = math.max(0, integer(elapsedHours, 0))
    local state = data.terminalFood
    local available = TerminalFood.getRemainingHours(data)
    local consumed = math.min(available, elapsedHours)
    local report = { hoursConsumed = consumed, restored = 0, skipped = 0, expired = false, changedItems = {} }
    if consumed <= 0 then return report end

    state.remainingHours = available - consumed
    local cooling = TerminalFood.getCoolingInfo(data)
    local restorePerDay = cooling.level > 0 and (GodSystemConfig.TerminalFreshnessRestorePerDay or {})[cooling.level] or 0
    local inventory = terminalInventory(terminal)
    if inventory and restorePerDay > 0 then
        iterateDirectItems(inventory, function(item)
            if not TerminalFood.isEligibleFood(item) then
                report.skipped = report.skipped + 1
                return
            end
            local age = getNumber(item, "getAge")
            local freshWindow = getNumber(item, "getOffAge")
            if age == nil or freshWindow == nil or freshWindow <= 0 then
                report.skipped = report.skipped + 1
                return
            end
            local restore = freshWindow * tonumber(restorePerDay) * consumed / 24
            if restore <= 0 then return end
            local nextAge = math.max(0, age - restore)
            if nextAge >= age - EPSILON then return end
            local ok = pcall(function() item:setAge(nextAge) end)
            if ok then
                report.restored = report.restored + 1
                report.changedItems[#report.changedItems + 1] = item
            else
                report.skipped = report.skipped + 1
            end
        end)
    end
    if state.remainingHours <= 0 and state.expiryNotified ~= true then
        state.expiryNotified = true
        report.expired = true
    end
    return report
end

function TerminalFood.settleOnline(data, terminal, nowHour)
    TerminalFood.normalizeData(data)
    nowHour = finite(nowHour) and tonumber(nowHour) or nil
    if not nowHour then return { hoursConsumed = 0, restored = 0, skipped = 0, expired = false, changedItems = {} } end
    local state = data.terminalFood
    if state.lastSettledHour == nil or nowHour < state.lastSettledHour then
        state.lastSettledHour = nowHour
        return { hoursConsumed = 0, restored = 0, skipped = 0, expired = false, changedItems = {} }
    end
    local elapsed = math.floor(nowHour - state.lastSettledHour)
    if elapsed <= 0 then return { hoursConsumed = 0, restored = 0, skipped = 0, expired = false, changedItems = {} } end
    state.lastSettledHour = state.lastSettledHour + elapsed
    return TerminalFood.settle(data, terminal, elapsed)
end

return TerminalFood
