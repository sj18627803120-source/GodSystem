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

function GodSystemShopVariants.normalizeUnlocked(data)
    if type(data) ~= "table" then return {} end
    data.unlockedShopItems = type(data.unlockedShopItems) == "table" and data.unlockedShopItems or {}
    local migrated = {}
    for oldKey, row in pairs(data.unlockedShopItems) do
        if type(row) == "table" then
            local fullType = tostring(row.fullType or oldKey or "")
            local key = GodSystemShopVariants.getKey(fullType, row.worldSprite)
            row.fullType = fullType
            row.variantKey = key
            migrated[key] = migrated[key] or row
        end
    end
    data.unlockedShopItems = migrated
    return migrated
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
