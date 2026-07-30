require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderInventoryQueryPlatform = GodSystemAutoLoaderInventoryQueryPlatform or {}

local Descriptor = GodSystemAutoLoaderInventoryQueryPlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "autoloader.inventory.query"
Descriptor.dependencies = { "ammo.catalog" }
Descriptor.stateVersion = 1

local function sortItemsById(items)
    table.sort(items, function(left, right)
        local leftId, rightId = Support.itemId(left) or "", Support.itemId(right) or ""
        local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
        if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
        return leftId < rightId
    end)
    return items
end

local function walk(actor, visitor, maximum)
    local root = Support.playerInventory(actor)
    if not root then return 0, false end
    maximum = Support.integer(maximum, 20000, 1)
    local count, limited = 0, false
    local pending, seen = {}, {}

    local function visitContainer(container, depth, sortValues)
        if not container or seen[container] then return true end
        seen[container] = true
        local values = Support.itemsArray(container)
        if sortValues then sortItemsById(values) end
        for index = 1, #values do
            count = count + 1
            if count > maximum then limited = true return false end
            local item = values[index]
            if visitor(item, container, depth, count) == false then return false end
            local child = Support.childContainer(item)
            if child then pending[#pending + 1] = { item = item, container = child, depth = depth + 1 } end
        end
        return true
    end

    if not visitContainer(root, 0, false) then return math.min(count, maximum), limited end
    while #pending > 0 do
        table.sort(pending, function(left, right)
            local leftId, rightId = Support.itemId(left.item) or "", Support.itemId(right.item) or ""
            local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
            if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
            return leftId < rightId
        end)
        local row = table.remove(pending, 1)
        if not visitContainer(row.container, row.depth, true) then break end
    end
    return math.min(count, maximum), limited
end

function Descriptor.create(dependencies)
    local catalog = assert(dependencies["ammo.catalog"], "ammo.catalog dependency missing")
    local instance = {
        started = false,
        scans = 0,
        resolved = 0,
        missed = 0,
    }

    local function resolveItem(actor, wantedId)
        wantedId = tostring(wantedId or "")
        if wantedId == "" then instance.missed = instance.missed + 1 return nil, "itemIdRequired" end
        local found, source
        walk(actor, function(item, container)
            if catalog.itemId(item) == wantedId then
                found, source = item, container
                return false
            end
            return true
        end, 20200)
        if not found then instance.missed = instance.missed + 1 return nil, "itemMissing" end
        instance.resolved = instance.resolved + 1
        return found, nil, source
    end

    local function isCarried(actor, item)
        local wantedId = catalog.itemId(item)
        if not wantedId then return false end
        local found = resolveItem(actor, wantedId)
        return found == item
    end

    instance.public = {
        resolveItem = resolveItem,
        resolveLoader = function(actor, wantedId)
            local item, code, source = resolveItem(actor, wantedId)
            if not item or catalog.fullType(item) ~= Support.FullType then
                return nil, code or "NotCarried"
            end
            return item, nil, source
        end,
        scanCarried = function(actor, maximum)
            instance.scans = instance.scans + 1
            local values = {}
            local _, limited = walk(actor, function(item)
                values[#values + 1] = item
                return true
            end, maximum)
            return values, { limitSkipped = limited and 1 or 0 }
        end,
        scanLoaders = function(actor, maximum)
            instance.scans = instance.scans + 1
            maximum = Support.integer(maximum, 64, 1, 64)
            local values, limited = {}, false
            walk(actor, function(item)
                if catalog.fullType(item) == Support.FullType then
                    if #values < maximum then values[#values + 1] = item else limited = true end
                end
                return true
            end, 20320)
            sortItemsById(values)
            return values, limited
        end,
        scanMagazines = function(actor, maximum)
            instance.scans = instance.scans + 1
            maximum = Support.integer(maximum, 256, 1, 256)
            local values, limited = {}, false
            walk(actor, function(item)
                if catalog.magazineAmmoType(item) then
                    if #values < maximum then values[#values + 1] = item else limited = true end
                end
                return true
            end, 20320)
            return values, limited
        end,
        isCarried = isCarried,
        ownerKey = function(actor)
            local username = Support.safeCall(actor, "getUsername", nil)
            if username and tostring(username) ~= "" then return tostring(username) end
            return tostring(Support.safeCall(actor, "getOnlineID", "player"))
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
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { scans = self.scans, resolved = self.resolved, missed = self.missed },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
