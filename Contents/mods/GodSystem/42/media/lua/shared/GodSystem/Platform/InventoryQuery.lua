GodSystemInventoryQueryPlatform = GodSystemInventoryQueryPlatform or {}

local Descriptor = GodSystemInventoryQueryPlatform

Descriptor.id = "inventory.query"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function itemId(item)
    if not item or type(item.getID) ~= "function" then return nil end
    local value = item:getID()
    return value ~= nil and tostring(value) or nil
end

local function childContainer(item)
    if not item or type(item.getInventory) ~= "function" then return nil end
    return item:getInventory()
end

local function findIn(container, wantedId, visited, depth)
    if not container or type(container.getItems) ~= "function" then return nil, nil end
    if depth > 32 or visited[container] then return nil, nil end
    visited[container] = true
    local items = container:getItems()
    if not items or type(items.size) ~= "function" or type(items.get) ~= "function" then
        return nil, nil
    end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item and itemId(item) == wantedId then return item, container end
        local child = childContainer(item)
        if child then
            local found, owner = findIn(child, wantedId, visited, depth + 1)
            if found then return found, owner end
        end
    end
    return nil, nil
end

local function actorInventory(actor)
    return actor and type(actor.getInventory) == "function" and actor:getInventory() or nil
end

function Descriptor.create()
    local instance = {
        started = false,
        resolved = 0,
        missed = 0,
    }

    local function resolveItem(actor, wantedId, role)
        wantedId = tostring(wantedId or "")
        if wantedId == "" then
            instance.missed = instance.missed + 1
            return nil, "itemIdRequired"
        end
        if role == "target" and actor and type(actor.getPrimaryHandItem) == "function" then
            local target = actor:getPrimaryHandItem()
            if target and itemId(target) == wantedId then
                instance.resolved = instance.resolved + 1
                return target, nil
            end
            instance.missed = instance.missed + 1
            return nil, "targetChanged"
        end
        local item, container = findIn(actorInventory(actor), wantedId, {}, 0)
        if not item then
            instance.missed = instance.missed + 1
            return nil, "itemMissing"
        end
        instance.resolved = instance.resolved + 1
        return item, nil, container
    end

    local function resolveVehicle(actor, wantedId)
        local numericId = math.floor(tonumber(wantedId) or -1)
        if numericId < 0 or type(getVehicleById) ~= "function" then
            instance.missed = instance.missed + 1
            return nil, "vehicleMissing"
        end
        local vehicle = getVehicleById(numericId)
        if not vehicle then
            instance.missed = instance.missed + 1
            return nil, "vehicleMissing"
        end
        instance.resolved = instance.resolved + 1
        return vehicle, nil
    end

    instance.public = {
        itemId = itemId,
        findIn = function(container, wantedId)
            return findIn(container, tostring(wantedId or ""), {}, 0)
        end,
        resolveItem = resolveItem,
        resolveVehicle = resolveVehicle,
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
            data = { resolved = self.resolved, missed = self.missed },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
