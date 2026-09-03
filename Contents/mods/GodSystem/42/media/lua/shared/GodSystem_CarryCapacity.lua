require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}

local Carry = GodSystemCarryCapacity
local MARKER_LEVEL = "GodSystemCarryCapacityLevel"
local MARKER_EXTERNAL_BASE = "GodSystemCarryExternalBase"
local MARKER_APPLIED_BASE = "GodSystemCarryAppliedBase"
local LEGACY_MARKERS = {
    "GodSystemCarryAppliedBonus",
    "GodSystemCarryAppliedDelta",
    "GodSystemCarryAppliedFactor",
    "GodSystemCarryBaseline",
    "GodSystemCarryNativeDelta",
}
local MAX_LEVEL = 1073741823
local MAX_BASE = 2147483647
local BONUS_PER_LEVEL = 2

local function finite(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function asInteger(value)
    value = tonumber(value)
    if not finite(value) then return nil end
    return math.floor(value)
end

local function playerModData(player)
    if not player or not player.getModData then return nil end
    local ok, data = pcall(function() return player:getModData() end)
    return ok and type(data) == "table" and data or nil
end

local function readBase(player)
    if not player or not player.getMaxWeightBase then return nil end
    local ok, value = pcall(function() return player:getMaxWeightBase() end)
    value = ok and asInteger(value) or nil
    if value == nil or value < 0 or value > MAX_BASE then return nil end
    return value
end

local function writeBase(player, value)
    value = asInteger(value)
    if not player or not player.setMaxWeightBase or value == nil or value < 0 or value > MAX_BASE then
        return false, "unsupported"
    end
    local ok = pcall(function() player:setMaxWeightBase(value) end)
    if not ok then return false, "writeFailed" end
    if readBase(player) ~= value then return false, "verificationFailed" end
    return true, "ok"
end

local function readFinal(player)
    if not player or not player.getMaxWeight then return nil end
    local ok, value = pcall(function() return player:getMaxWeight() end)
    value = ok and asInteger(value) or nil
    return value
end

function Carry.normalizeLevel(value)
    value = asInteger(value)
    if value == nil then return 0 end
    return math.max(0, math.min(MAX_LEVEL, value))
end

function Carry.getBonus(level)
    local value = Carry.normalizeLevel(level) * BONUS_PER_LEVEL
    if value > MAX_BASE then return nil end
    return value
end

function Carry.getNextCost()
    return 2000
end

function Carry.getPersistedLevel(player)
    local data = playerModData(player)
    return Carry.normalizeLevel(data and data[MARKER_LEVEL])
end

function Carry.getLevel(data, player)
    local upgrades = data and data.upgrades or nil
    return math.max(
        Carry.normalizeLevel(upgrades and upgrades.carryCapacityLevel),
        Carry.getPersistedLevel(player)
    )
end

local function markerContext(player, currentBase)
    local data = playerModData(player)
    local externalBase = data and asInteger(data[MARKER_EXTERNAL_BASE]) or nil
    local appliedBase = data and asInteger(data[MARKER_APPLIED_BASE]) or nil
    if externalBase ~= nil and externalBase >= 0 and appliedBase == currentBase then
        return externalBase, appliedBase, true
    end
    return currentBase, appliedBase, false
end

function Carry.getStatus(player, level)
    level = Carry.normalizeLevel(level)
    local currentBase = readBase(player)
    local bonus = Carry.getBonus(level) or 0
    local externalBase, appliedBase, managed = markerContext(player, currentBase)
    local targetBase = externalBase and externalBase + bonus or nil
    return {
        level = level,
        bonus = bonus,
        currentBase = currentBase,
        externalBase = externalBase,
        appliedBase = appliedBase,
        targetBase = targetBase,
        finalCarry = readFinal(player),
        restored = managed and currentBase == targetBase,
        requiresRestore = level > 0 and not (managed and currentBase == targetBase),
    }
end

local function clearLegacyMarkers(data)
    if not data then return end
    for i = 1, #LEGACY_MARKERS do data[LEGACY_MARKERS[i]] = nil end
end

-- This is deliberately invoked only for a purchase or the player's explicit
-- "restore carry" action. No lifecycle or background path may call it.
function Carry.restore(player, level)
    level = Carry.normalizeLevel(level)
    local currentBase = readBase(player)
    local bonus = Carry.getBonus(level)
    if currentBase == nil then return false, "unsupported" end
    if bonus == nil or currentBase + bonus > MAX_BASE then return false, "overflow" end

    local externalBase = markerContext(player, currentBase)
    local targetBase = externalBase + bonus
    if currentBase ~= targetBase then
        local written, reason = writeBase(player, targetBase)
        if not written then
            -- A setter can fail after partially changing the base. Restore the
            -- exact pre-operation value before the caller decides not to charge.
            writeBase(player, currentBase)
            return false, reason
        end
    end

    local data = playerModData(player)
    if data then
        data[MARKER_LEVEL] = level
        data[MARKER_EXTERNAL_BASE] = externalBase
        data[MARKER_APPLIED_BASE] = targetBase
        clearLegacyMarkers(data)
    end
    return true, Carry.getStatus(player, level)
end
