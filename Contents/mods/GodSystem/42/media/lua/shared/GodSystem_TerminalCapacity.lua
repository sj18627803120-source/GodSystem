require "GodSystem_Config"

GodSystemTerminalCapacity = GodSystemTerminalCapacity or {}

local TERMINAL_FULL_TYPE = GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal"
local TARGET_KEY = GodSystemConfig.AutoRecyclerTargetCapacityKey or "GodSystemTerminalTargetCapacity"
local MAX_CAPACITY = math.max(1, math.floor(tonumber(GodSystemConfig.TerminalCapacityHardLimit) or 2000))
local EPSILON = 0.0001
local registered = GodSystemTerminalCapacity.registered or setmetatable({}, { __mode = "k" })
GodSystemTerminalCapacity.registered = registered

local originalEffectiveCapacity = GodSystemTerminalCapacity.originalEffectiveCapacity
local originalHasRoomFor = GodSystemTerminalCapacity.originalHasRoomFor

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeCall(target, method, fallback, ...)
    if not target or not target[method] then return fallback end
    local args = { ... }
    local ok, value = pcall(function() return target[method](target, unpack(args)) end)
    return ok and value or fallback
end

local function terminalItem(container)
    local cached = registered[container]
    if cached and cached.terminal then return cached.terminal end
    local item = safeCall(container, "getContainingItem", nil)
    if not item then return nil end
    local fullType = tostring(safeCall(item, "getFullType", "") or "")
    return fullType == TERMINAL_FULL_TYPE and item or nil
end

local function storedCapacity(container)
    local cached = registered[container]
    local value = cached and cached.capacity or nil
    if not finite(value) then
        local item = terminalItem(container)
        local modData = item and safeCall(item, "getModData", nil) or nil
        value = type(modData) == "table" and modData[TARGET_KEY] or nil
    end
    value = tonumber(value)
    if not finite(value) or value < 1 or value > MAX_CAPACITY then return nil end
    return math.floor(value + EPSILON)
end

local function effectiveCapacity(container)
    local target = storedCapacity(container)
    if not target then return nil end
    -- The target is deliberately exact.  Applying vanilla trait multipliers
    -- here could push the 1999 safety target above the researched 2000 bound.
    return target
end

local function requestedWeight(itemOrWeight)
    if type(itemOrWeight) == "number" then return itemOrWeight end
    if not itemOrWeight then return nil end
    local value = safeCall(itemOrWeight, "getUnequippedWeight", nil)
    if not finite(value) then value = safeCall(itemOrWeight, "getActualWeight", nil) end
    value = tonumber(value)
    return finite(value) and value >= 0 and value or nil
end

local function roomFor(container, player, itemOrWeight, fallback)
    local contents = tonumber(safeCall(container, "getContentsWeight", nil))
    local incoming = requestedWeight(itemOrWeight)
    if not finite(contents) or contents < 0 or not finite(incoming) then
        return fallback(container, player, itemOrWeight)
    end
    return contents + incoming <= effectiveCapacity(container) + EPSILON
end

function GodSystemTerminalCapacity.register(terminal, capacity)
    capacity = tonumber(capacity)
    if not terminal or not finite(capacity) or capacity < 1 or capacity >= MAX_CAPACITY then return false end
    local fullType = tostring(safeCall(terminal, "getFullType", "") or "")
    if fullType ~= TERMINAL_FULL_TYPE then return false end
    local container = safeCall(terminal, "getInventory", nil)
    if not container then return false end
    capacity = math.floor(capacity + EPSILON)
    local modData = safeCall(terminal, "getModData", nil)
    if type(modData) == "table" then modData[TARGET_KEY] = capacity end
    registered[container] = { terminal = terminal, capacity = capacity }
    return true
end

function GodSystemTerminalCapacity.unregister(terminal)
    local container = terminal and safeCall(terminal, "getInventory", nil) or nil
    if container then registered[container] = nil end
end

function GodSystemTerminalCapacity.getRegisteredCapacity(container)
    return storedCapacity(container)
end

function GodSystemTerminalCapacity.getEffectiveCapacity(container, player)
    local target = effectiveCapacity(container)
    if target then return target end
    return originalEffectiveCapacity and originalEffectiveCapacity(container, player) or nil
end

function GodSystemTerminalCapacity.isInstalled()
    local classMeta = ItemContainer and ItemContainer.__classmetatables
        and ItemContainer.__classmetatables[ItemContainer.class] or nil
    local index = classMeta and classMeta.__index or nil
    return type(index) == "table"
        and index.getEffectiveCapacity == GodSystemTerminalCapacity.effectiveWrapper
        and index.hasRoomFor == GodSystemTerminalCapacity.roomWrapper
end

function GodSystemTerminalCapacity.install()
    local classMeta = ItemContainer and ItemContainer.__classmetatables
        and ItemContainer.__classmetatables[ItemContainer.class] or nil
    local index = classMeta and classMeta.__index or nil
    if type(index) ~= "table" then return false end
    if type(index.getEffectiveCapacity) ~= "function" or type(index.hasRoomFor) ~= "function" then return false end
    if GodSystemTerminalCapacity.isInstalled() then return true end

    local capturedEffectiveCapacity = index.getEffectiveCapacity
    local capturedHasRoomFor = index.hasRoomFor
    originalEffectiveCapacity = capturedEffectiveCapacity
    originalHasRoomFor = capturedHasRoomFor
    GodSystemTerminalCapacity.originalEffectiveCapacity = originalEffectiveCapacity
    GodSystemTerminalCapacity.originalHasRoomFor = originalHasRoomFor
    local effectiveWrapper = function(self, player)
        local target = effectiveCapacity(self)
        if not target then return capturedEffectiveCapacity(self, player) end
        return target
    end
    local roomWrapper = function(self, player, itemOrWeight)
        if not storedCapacity(self) then return capturedHasRoomFor(self, player, itemOrWeight) end
        return roomFor(self, player, itemOrWeight, capturedHasRoomFor)
    end
    index.getEffectiveCapacity = effectiveWrapper
    index.hasRoomFor = roomWrapper
    GodSystemTerminalCapacity.installedIndex = index
    GodSystemTerminalCapacity.effectiveWrapper = effectiveWrapper
    GodSystemTerminalCapacity.roomWrapper = roomWrapper
    return true
end

GodSystemTerminalCapacity.install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(GodSystemTerminalCapacity.install) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(GodSystemTerminalCapacity.install) end

return GodSystemTerminalCapacity
