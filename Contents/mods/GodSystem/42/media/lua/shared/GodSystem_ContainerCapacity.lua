-- B42.20 wearable containers clamp native capacity to 50. The wrapper keeps
-- the displayed effective capacity and the actual transfer check consistent.
GodSystemContainerCapacity = GodSystemContainerCapacity or {}

local CapacityPatch = GodSystemContainerCapacity
CapacityPatch.FullType = "GodSystem.StorageContainer"
CapacityPatch.ShortType = "StorageContainer"
CapacityPatch.Capacity = 500
CapacityPatch.Marker = "__godSystemStorageContainerCapacity_v1"
CapacityPatch.ContainerCache = CapacityPatch.ContainerCache
    or setmetatable({}, { __mode = "k" })

local function isTargetContainer(container)
    if not container then return false end

    local ok, item = pcall(function()
        return container:getContainingItem()
    end)
    if not ok then
        item = nil
    end

    local itemId = nil
    if item then
        local idOk, value = pcall(function()
            return item:getID()
        end)
        if idOk then
            itemId = value
        end
    end

    local cached = CapacityPatch.ContainerCache[container]
    if cached and cached.item == item and cached.itemId == itemId then
        return cached.target == true
    end

    local fullType = nil
    if item then
        local fullOk, value = pcall(function()
            return item:getFullType()
        end)
        if fullOk then
            fullType = value
        end
    end

    local typeOk, containerType = pcall(function()
        return container:getType()
    end)
    if not typeOk then
        containerType = nil
    end

    local target = fullType == CapacityPatch.FullType
        or (not item and containerType == CapacityPatch.ShortType)
    CapacityPatch.ContainerCache[container] = {
        item = item,
        itemId = itemId,
        fullType = fullType,
        containerType = containerType,
        target = target,
    }
    return target
end

local function adjustedCapacity(player)
    local capacity = CapacityPatch.Capacity
    if not player then return capacity end

    local organizedOk, organized = pcall(function()
        return player:hasTrait(CharacterTrait.ORGANIZED)
    end)
    if organizedOk and organized then
        return math.floor(math.max(capacity * 1.3, capacity + 1))
    end

    local disorganizedOk, disorganized = pcall(function()
        return player:hasTrait(CharacterTrait.DISORGANIZED)
    end)
    if disorganizedOk and disorganized then
        return math.floor(math.max(capacity * 0.7, 1))
    end

    return capacity
end

local function getItemWeight(item)
    if type(item) == "number" then
        return item
    end
    if item and instanceof and instanceof(item, "InventoryItem") then
        local ok, weight = pcall(function()
            return item:getUnequippedWeight()
        end)
        if ok and type(weight) == "number" then
            return weight
        end
    end
    return nil
end

local function wrapsGetCapacity(original)
    return function(self)
        if isTargetContainer(self) then
            return CapacityPatch.Capacity
        end
        return original(self)
    end
end

local function wrapsGetEffectiveCapacity(original)
    return function(self, player)
        if not player then
            return nil
        end
        if isTargetContainer(self) then
            return adjustedCapacity(player)
        end
        return original(self, player)
    end
end

local function callOriginal(original, self, ...)
    -- B42 exposes several hasRoomFor overloads. Preserve the exact argument
    -- count so a two-argument call is not routed to a three-argument Java
    -- overload with a nil float.
    return original(self, ...)
end

local function wrapsHasRoomFor(original)
    return function(self, ...)
        local argumentCount = select("#", ...)
        local first, second, third = ...
        if isTargetContainer(self) then
            local player = argumentCount >= 2 and first or nil
            local itemOrWeight = argumentCount >= 2 and second or first
            local extraWeight = argumentCount >= 3 and third or nil
            local weight = getItemWeight(itemOrWeight)
            if weight ~= nil then
                if itemOrWeight and type(itemOrWeight) ~= "number" and self.isItemAllowed then
                    local allowedOk, allowed = pcall(function()
                        return self:isItemAllowed(itemOrWeight)
                    end)
                    if allowedOk and not allowed then
                        return false
                    end
                end

                local contentsOk, contentsWeight = pcall(function()
                    return self:getContentsWeight()
                end)
                if contentsOk and type(contentsWeight) == "number" then
                    local addedWeight = type(extraWeight) == "number" and extraWeight or 0
                    return contentsWeight + weight + addedWeight <= adjustedCapacity(player)
                end
            end
        end
        return callOriginal(original, self, ...)
    end
end

function CapacityPatch.install()
    if not __classmetatables or not ItemContainer or not ItemContainer.class then
        return false
    end

    local classMeta = __classmetatables[ItemContainer.class]
    local index = classMeta and classMeta.__index
    if not index then return false end
    if rawget(index, CapacityPatch.Marker) then return true end

    local originals = {
        getCapacity = index.getCapacity,
        getEffectiveCapacity = index.getEffectiveCapacity,
        hasRoomFor = index.hasRoomFor,
    }
    if not originals.getCapacity or not originals.getEffectiveCapacity or not originals.hasRoomFor then
        return false
    end

    local wrappers = {
        getCapacity = wrapsGetCapacity(originals.getCapacity),
        getEffectiveCapacity = wrapsGetEffectiveCapacity(originals.getEffectiveCapacity),
        hasRoomFor = wrapsHasRoomFor(originals.hasRoomFor),
    }
    index.getCapacity = wrappers.getCapacity
    index.getEffectiveCapacity = wrappers.getEffectiveCapacity
    index.hasRoomFor = wrappers.hasRoomFor
    rawset(index, CapacityPatch.Marker, wrappers)
    return true
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(CapacityPatch.install)
end
if Events and Events.OnServerStarted then
    Events.OnServerStarted.Add(CapacityPatch.install)
end
