GodSystemInventoryMutationPlatform = GodSystemInventoryMutationPlatform or {}

local Descriptor = GodSystemInventoryMutationPlatform

Descriptor.id = "inventory.mutation"
Descriptor.dependencies = { "inventory.query" }
Descriptor.stateVersion = 1

local function fullType(item)
    if not item or type(item.getFullType) ~= "function" then return nil end
    local value = item:getFullType()
    return value and tostring(value) or nil
end

local function markDirty(container)
    if container and type(container.setDrawDirty) == "function" then container:setDrawDirty(true) end
    if type(triggerEvent) == "function" then triggerEvent("OnContainerUpdate") end
end

function Descriptor.create(dependencies)
    local query = assert(dependencies["inventory.query"], "inventory.query dependency missing")
    local instance = {
        started = false,
        consumed = 0,
        restored = 0,
        failures = 0,
    }

    local function consume(actor, item)
        if not actor or not item then return false, "itemMissing" end
        local id = query.itemId(item)
        local carried, _, container = query.resolveItem(actor, id, "consumable")
        if carried ~= item or not container or type(container.Remove) ~= "function" then
            return false, "itemOwnershipChanged"
        end
        local receipt = {
            item = item,
            itemId = id,
            fullType = fullType(item),
            container = container,
        }
        container:Remove(item)
        local stillOwned = query.resolveItem(actor, id, "consumable")
        if stillOwned then
            instance.failures = instance.failures + 1
            return false, "itemRemovalFailed"
        end
        instance.consumed = instance.consumed + 1
        markDirty(container)
        return true, receipt
    end

    local function addExisting(container, item)
        if not container or type(container.AddItem) ~= "function" then return nil end
        return container:AddItem(item)
    end

    local function restore(actor, receipt)
        if type(receipt) ~= "table" or not receipt.item then return false end
        if query.resolveItem(actor, receipt.itemId, "consumable") then return true end
        local added = addExisting(receipt.container, receipt.item)
        if not added then
            local inventory = actor and type(actor.getInventory) == "function" and actor:getInventory() or nil
            added = addExisting(inventory, receipt.item)
            if not added and inventory and receipt.fullType then
                added = inventory:AddItem(receipt.fullType)
            end
        end
        if not added then
            instance.failures = instance.failures + 1
            return false
        end
        instance.restored = instance.restored + 1
        markDirty(receipt.container)
        return true
    end

    instance.public = {
        consume = consume,
        restore = restore,
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
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "mutationFailure" or (self.started and "healthy" or "stopped"),
            data = {
                consumed = self.consumed,
                restored = self.restored,
                failures = self.failures,
            },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
