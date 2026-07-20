GodSystemShopVariants = GodSystemShopVariants or {}

local SEPARATOR = "@worldSprite="

function GodSystemShopVariants.getWorldSprite(value)
    if type(value) == "string" then return value ~= "" and value or nil end
    if not value or not value.getWorldSprite then return nil end
    local ok, sprite = pcall(function() return value:getWorldSprite() end)
    sprite = ok and tostring(sprite or "") or ""
    return sprite ~= "" and sprite or nil
end

function GodSystemShopVariants.getKey(fullType, itemOrSprite)
    fullType = tostring(fullType or "")
    local sprite = GodSystemShopVariants.getWorldSprite(itemOrSprite)
    if sprite then return fullType .. SEPARATOR .. sprite end
    return fullType
end

function GodSystemShopVariants.getConfiguredKeySet(shopItems)
    local result = {}
    for i = 1, #(shopItems or {}) do
        local items = shopItems[i] and shopItems[i].items or {}
        if #items == 1 then
            local definition = items[1]
            local fullType = definition and tostring(definition.fullType or "") or ""
            local count = definition and math.max(1, math.floor(tonumber(definition.count) or 1)) or 0
            if fullType ~= "" and count == 1 then
                result[GodSystemShopVariants.getKey(fullType, definition.worldSprite)] = true
            end
        end
    end
    return result
end

function GodSystemShopVariants.normalizeUnlocked(data, configuredKeys)
    if type(data) ~= "table" then return {} end
    data.unlockedShopItems = type(data.unlockedShopItems) == "table" and data.unlockedShopItems or {}
    local migrated = {}
    local removedConfigured = 0
    local mergedDuplicates = 0
    for oldKey, row in pairs(data.unlockedShopItems) do
        if type(row) == "table" then
            local fullType = tostring(row.fullType or oldKey or "")
            local key = GodSystemShopVariants.getKey(fullType, row.worldSprite)
            row.fullType = fullType
            row.variantKey = key
            row.hidden = row.hidden == true
            if configuredKeys and configuredKeys[key] == true then
                removedConfigured = removedConfigured + 1
            elseif migrated[key] then
                local existing = migrated[key]
                existing.hidden = existing.hidden == true or row.hidden == true
                existing.label = existing.label or row.label
                existing.sellPrice = existing.sellPrice or row.sellPrice
                existing.buyPrice = existing.buyPrice or row.buyPrice
                existing.unlockedAt = existing.unlockedAt or row.unlockedAt
                mergedDuplicates = mergedDuplicates + 1
            else
                migrated[key] = row
            end
        end
    end
    data.unlockedShopItems = migrated
    return migrated, removedConfigured, mergedDuplicates
end

function GodSystemShopVariants.isListingKnown(data, configuredKeys, fullTypeOrKey, itemOrSprite)
    local key = itemOrSprite ~= nil and GodSystemShopVariants.getKey(fullTypeOrKey, itemOrSprite)
        or tostring(fullTypeOrKey or "")
    if configuredKeys and configuredKeys[key] == true then return true, "configured", key end
    local unlocked = type(data) == "table" and data.unlockedShopItems or nil
    if type(unlocked) == "table" and unlocked[key] then return true, "unlocked", key end
    return false, nil, key
end

function GodSystemShopVariants.setHidden(data, variantKey, hidden)
    local unlocked = type(data) == "table" and data.unlockedShopItems or nil
    local key = tostring(variantKey or "")
    local row = type(unlocked) == "table" and unlocked[key] or nil
    if type(row) ~= "table" then return false, false, nil end
    local target = hidden == true
    local changed = row.hidden ~= target
    row.hidden = target
    row.variantKey = key
    return true, changed, row
end

function GodSystemShopVariants.getUnlockedRows(data, includeHidden)
    local result = {}
    for variantKey, row in pairs((type(data) == "table" and data.unlockedShopItems) or {}) do
        if type(row) == "table" and (includeHidden == true or row.hidden ~= true) then
            row.variantKey = tostring(row.variantKey or variantKey)
            result[#result + 1] = row
        end
    end
    return result
end

function GodSystemShopVariants.createItem(fullType, worldSprite)
    if not InventoryItemFactory or not InventoryItemFactory.CreateItem then return nil, "factoryUnavailable" end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    if not ok or not item then return nil, "createFailed" end
    worldSprite = GodSystemShopVariants.getWorldSprite(worldSprite)
    if worldSprite then
        if not item.ReadFromWorldSprite then return nil, "moveableUnsupported" end
        local readOk = pcall(function() item:ReadFromWorldSprite(worldSprite) end)
        if not readOk or GodSystemShopVariants.getWorldSprite(item) ~= worldSprite then return nil, "spriteRestoreFailed" end
    end
    return item
end

function GodSystemShopVariants.addItems(inventory, fullType, worldSprite, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if not inventory or not inventory.AddItem then return false, {}, "inventoryUnavailable" end
    local added = {}
    for _ = 1, count do
        local item, reason = GodSystemShopVariants.createItem(fullType, worldSprite)
        if not item then
            for i = 1, #added do pcall(function() inventory:Remove(added[i]) end) end
            return false, {}, reason
        end
        local ok, result = pcall(function() return inventory:AddItem(item) end)
        if not ok or not result then
            for i = 1, #added do pcall(function() inventory:Remove(added[i]) end) end
            return false, {}, "addFailed"
        end
        added[#added + 1] = item
    end
    return true, added
end

return GodSystemShopVariants
