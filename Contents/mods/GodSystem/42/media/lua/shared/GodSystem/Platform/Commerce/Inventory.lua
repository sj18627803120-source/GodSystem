require "GodSystem/Platform/Commerce/Support"

local Support = GodSystemCommercePlatformSupport

GodSystemCommerceInventoryPlatform = GodSystemCommerceInventoryPlatform or {
    id = "commerce.inventory",
    dependencies = {},
    stateVersion = 1,
}

local function walk(actor, visitor, maximum)
    local root = Support.playerInventory(actor)
    if not root then return 0, false end
    maximum = Support.integer(maximum, 20000, 1)
    local seen, pending = {}, { { container = root, depth = 0 } }
    local count, limited = 0, false
    while #pending > 0 do
        local row = table.remove(pending, 1)
        if row.depth <= 32 and row.container and not seen[row.container] then
            seen[row.container] = true
            local values = Support.itemsArray(row.container)
            for index = 1, #values do
                count = count + 1
                if count > maximum then limited = true break end
                local item = values[index]
                if visitor(item, row.container, row.depth) == false then
                    return math.min(count, maximum), limited
                end
                local child = Support.childContainer(item)
                if child then pending[#pending + 1] = { container = child, depth = row.depth + 1 } end
            end
        end
        if limited then break end
    end
    return math.min(count, maximum), limited
end

local function isKey(item)
    if type(instanceof) == "function" then
        local ok, value = pcall(instanceof, item, "Key")
        if ok and value == true then return true end
    end
    if item and type(item.isItemType) == "function" and ItemType and ItemType.KEY_RING then
        local ok, value = pcall(item.isItemType, item, ItemType.KEY_RING)
        if ok and value == true then return true end
    end
    if item and type(item.hasTag) == "function" and ItemTag and ItemTag.KEY_RING then
        local ok, value = pcall(item.hasTag, item, ItemTag.KEY_RING)
        if ok and value == true then return true end
    end
    return false
end

local function categoryKey(item)
    local value = Support.safeCall(item, "getCategory", nil)
        or Support.safeCall(item, "getDisplayCategory", nil)
    value = tostring(value or "other"):lower()
    return value ~= "" and value or "other"
end

local function itemView(item, container)
    if not item then return nil end
    local fullType = Support.fullType(item)
    if not fullType then return nil end
    local child = Support.childContainer(item)
    local usedDelta = Support.safeCall(item, "getUsedDelta", nil)
    local modData = Support.safeCall(item, "getModData", nil)
    return {
        id = Support.itemId(item),
        fullType = fullType,
        worldSprite = Support.worldSprite(item),
        label = tostring(Support.safeCall(item, "getDisplayName", fullType)),
        categoryKey = categoryKey(item),
        sellPrice = 1,
        buyPrice = 4,
        value = 1,
        broken = Support.safeCall(item, "isBroken", false) == true,
        usedDelta = tonumber(usedDelta),
        hasInventory = child ~= nil,
        contentCount = child and #Support.itemsArray(child) or 0,
        contentSignature = child and Support.containerSignature(item) or nil,
        key = isKey(item),
        protected = type(modData) == "table" and modData.GodSystemProtected == true,
        _item = item,
        _container = container,
    }
end

local function createItem(fullType, worldSprite)
    if not InventoryItemFactory or type(InventoryItemFactory.CreateItem) ~= "function" then
        return nil, "factoryUnavailable"
    end
    local ok, item = pcall(InventoryItemFactory.CreateItem, tostring(fullType or ""))
    if not ok or not item then return nil, "createFailed" end
    worldSprite = Support.worldSprite(worldSprite)
    if worldSprite then
        if type(item.ReadFromWorldSprite) ~= "function" then return nil, "moveableUnsupported" end
        local restored = pcall(item.ReadFromWorldSprite, item, worldSprite)
        if not restored or Support.worldSprite(item) ~= worldSprite then
            return nil, "spriteRestoreFailed"
        end
    end
    return item
end

function GodSystemCommerceInventoryPlatform.create(_, context)
    context = type(context) == "table" and context or {}
    local config = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local terminalFullType = tostring(config.AutoRecyclerFullType
        or "GodSystem.SystemSpaceTerminal")
    local instance = {
        started = false,
        scans = 0,
        removed = 0,
        restored = 0,
        granted = 0,
        failures = 0,
    }

    local function resolve(actor, itemId)
        itemId = tostring(itemId or "")
        local found
        walk(actor, function(item, container)
            if Support.itemId(item) == itemId then found = itemView(item, container) return false end
            return true
        end, 20200)
        return found, found and nil or "itemMissing"
    end

    local function removeView(actor, view)
        local current = resolve(actor, view and view.id)
        if not current
            or current._item ~= view._item
            or current.fullType ~= tostring(view.fullType or "")
            or tostring(current.worldSprite or "") ~= tostring(view.worldSprite or "")
        then
            return false, "selectionChanged"
        end
        local container, item = current._container, current._item
        if not container or type(container.Remove) ~= "function" then return false, "selectionChanged" end
        local receipt = {
            item = item,
            itemId = current.id,
            fullType = current.fullType,
            worldSprite = current.worldSprite,
            container = container,
        }
        local ok = pcall(container.Remove, container, item)
        if not ok or Support.contains(container, item) then
            instance.failures = instance.failures + 1
            return false, "selectionFailed"
        end
        Support.markRemoved(container, item)
        instance.removed = instance.removed + 1
        return true, receipt
    end

    local function restore(actor, receipt)
        if type(receipt) ~= "table" or not receipt.item then return false end
        if resolve(actor, receipt.itemId) then return true end
        local container = receipt.container
        local added
        if container and type(container.AddItem) == "function" then
            local ok, value = pcall(container.AddItem, container, receipt.item)
            if ok then added = value end
        end
        if not added then
            container = Support.playerInventory(actor)
            if container and type(container.AddItem) == "function" then
                local ok, value = pcall(container.AddItem, container, receipt.item)
                if ok then added = value end
            end
        end
        if not added then instance.failures = instance.failures + 1 return false end
        Support.markAdded(container, added)
        instance.restored = instance.restored + 1
        return true
    end

    local function revoke(_, receipt)
        if type(receipt) ~= "table" or type(receipt.items) ~= "table" then return false end
        local complete = true
        for index = #receipt.items, 1, -1 do
            local row = receipt.items[index]
            local container = row.container
            if container and type(container.Remove) == "function" and Support.contains(container, row.item) then
                local ok = pcall(container.Remove, container, row.item)
                if ok and not Support.contains(container, row.item) then
                    Support.markRemoved(container, row.item)
                else
                    complete = false
                end
            else
                complete = false
            end
        end
        if not complete then instance.failures = instance.failures + 1 end
        return complete
    end

    instance.public = {
        resolve = resolve,
        count = function(actor, fullTypes)
            local wanted, count = {}, 0
            for index = 1, #(fullTypes or {}) do wanted[tostring(fullTypes[index])] = true end
            instance.scans = instance.scans + 1
            walk(actor, function(item)
                if wanted[Support.fullType(item)] then count = count + 1 end
                return true
            end, 20000)
            return count
        end,
        consume = function(actor, fullTypes, requested)
            local wanted, candidates = {}, {}
            for index = 1, #(fullTypes or {}) do wanted[tostring(fullTypes[index])] = true end
            requested = Support.integer(requested, 0, 0)
            walk(actor, function(item, container)
                if #candidates < requested and wanted[Support.fullType(item)] then
                    candidates[#candidates + 1] = itemView(item, container)
                end
                return #candidates < requested
            end, 20000)
            if #candidates < requested then return false, "turnInNotEnough" end
            local receipts = {}
            for index = 1, #candidates do
                local ok, receipt = removeView(actor, candidates[index])
                if not ok then
                    for rollback = #receipts, 1, -1 do restore(actor, receipts[rollback]) end
                    return false, receipt or "selectionChanged"
                end
                receipts[#receipts + 1] = receipt
            end
            return true, receipts
        end,
        restore = function(actor, receipt)
            local values = type(receipt) == "table" and receipt or {}
            if values.item then return restore(actor, values) end
            local complete = true
            for index = #values, 1, -1 do complete = restore(actor, values[index]) and complete end
            return complete
        end,
        grant = function(actor, entries)
            local container = Support.playerInventory(actor)
            if not container or type(container.AddItem) ~= "function" then return false, "inventoryUnavailable" end
            local receipt = { items = {} }
            for entryIndex = 1, #(entries or {}) do
                local entry = entries[entryIndex]
                for _ = 1, Support.integer(entry.count, 1, 1) do
                    local item, code = createItem(entry.fullType, entry.worldSprite)
                    if not item then revoke(actor, receipt) return false, code end
                    local ok, added = pcall(container.AddItem, container, item)
                    if not ok or not added then revoke(actor, receipt) return false, "addFailed" end
                    receipt.items[#receipt.items + 1] = { item = added, container = container }
                    Support.markAdded(container, added)
                    instance.granted = instance.granted + 1
                end
            end
            return true, receipt
        end,
        revoke = revoke,
        remove = removeView,
        autoRecycleIds = function(actor, maximum)
            maximum = Support.integer(maximum, 2000, 1)
            local result, seen = {}, {}
            walk(actor, function(item)
                if Support.fullType(item) == terminalFullType then
                    local child = Support.childContainer(item)
                    local values = Support.itemsArray(child)
                    for index = 1, #values do
                        local id = Support.itemId(values[index])
                        if id and not seen[id] and #result < maximum then
                            seen[id] = true
                            result[#result + 1] = id
                        end
                    end
                end
                return #result < maximum
            end, 20200)
            return result
        end,
    }

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "inventoryFailure"
                or (self.started and "healthy" or "stopped"),
            data = {
                scans = self.scans,
                removed = self.removed,
                restored = self.restored,
                granted = self.granted,
                failures = self.failures,
            },
            moduleId = GodSystemCommerceInventoryPlatform.id,
        }
    end
    return instance
end

local function wrapper(id, methods)
    local value = { id = id, dependencies = { "commerce.inventory" }, stateVersion = 1 }
    function value.create(dependencies)
        local inventory = assert(dependencies["commerce.inventory"], "commerce.inventory dependency missing")
        local instance = { started = false }
        instance.public = {}
        for index = 1, #methods do
            local methodName = methods[index]
            instance.public[methodName] = function(...) return inventory[methodName](...) end
        end
        function instance:start() self.started = true return true end
        function instance:stop() self.started = false return true end
        function instance:health()
            return {
                ok = self.started,
                code = self.started and "healthy" or "stopped",
                data = {},
                moduleId = id,
            }
        end
        return instance
    end
    return value
end

GodSystemTasksInventoryPlatform = GodSystemTasksInventoryPlatform
    or wrapper("tasks.inventory", { "count", "consume", "restore", "grant", "revoke" })
GodSystemShopInventoryPlatform = GodSystemShopInventoryPlatform
    or wrapper("shop.inventory", { "resolve", "grant", "revoke" })
GodSystemRecycleInventoryPlatform = GodSystemRecycleInventoryPlatform
    or wrapper("recycle.inventory",
        { "resolve", "remove", "restore", "autoRecycleIds" })

return {
    commerce = GodSystemCommerceInventoryPlatform,
    tasks = GodSystemTasksInventoryPlatform,
    shop = GodSystemShopInventoryPlatform,
    recycle = GodSystemRecycleInventoryPlatform,
}
