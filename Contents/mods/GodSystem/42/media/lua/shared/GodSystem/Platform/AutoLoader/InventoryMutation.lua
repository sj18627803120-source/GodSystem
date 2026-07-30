require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderInventoryMutationPlatform = GodSystemAutoLoaderInventoryMutationPlatform or {}

local Descriptor = GodSystemAutoLoaderInventoryMutationPlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "autoloader.inventory.mutation"
Descriptor.dependencies = { "autoloader.inventory.query" }
Descriptor.stateVersion = 1

local function addExisting(container, item)
    if not container or type(container.AddItem) ~= "function" then return nil end
    local ok, added = pcall(container.AddItem, container, item)
    return ok and added or nil
end

function Descriptor.create(dependencies)
    local query = assert(dependencies["autoloader.inventory.query"],
        "autoloader.inventory.query dependency missing")
    local instance = {
        started = false,
        removed = 0,
        restored = 0,
        created = 0,
        failures = 0,
    }

    local function removeItem(actor, item)
        local itemId = Support.itemId(item)
        local carried, _, container = query.resolveItem(actor, itemId)
        if carried ~= item or not container or type(container.Remove) ~= "function" then
            return false, "itemOwnershipChanged"
        end
        local receipt = {
            item = item,
            itemId = itemId,
            fullType = Support.fullType(item),
            container = container,
        }
        local ok = pcall(container.Remove, container, item)
        if not ok or Support.containerContains(container, item) then
            instance.failures = instance.failures + 1
            return false, "itemRemovalFailed"
        end
        instance.removed = instance.removed + 1
        return true, receipt
    end

    local function restoreItem(actor, receipt)
        if type(receipt) ~= "table" or not receipt.item then return false end
        if query.resolveItem(actor, receipt.itemId) == receipt.item then return true end
        local destination = receipt.container
        local added = addExisting(destination, receipt.item)
        if not added then
            destination = Support.playerInventory(actor)
            added = addExisting(destination, receipt.item)
        end
        if not added and destination and receipt.fullType and type(destination.AddItem) == "function" then
            local ok, replacement = pcall(destination.AddItem, destination, receipt.fullType)
            added = ok and replacement or nil
        end
        if not added then instance.failures = instance.failures + 1 return false end
        receipt.restoredContainer = destination
        receipt.restoredItem = added
        instance.restored = instance.restored + 1
        return true
    end

    instance.public = {
        removeAmmo = removeItem,
        restoreAmmo = restoreItem,
        createAmmo = function(actor, fullType)
            local container = Support.playerInventory(actor)
            if not container or type(container.AddItem) ~= "function" then
                instance.failures = instance.failures + 1
                return false, "inventoryMissing"
            end
            local ok, item = pcall(container.AddItem, container, tostring(fullType or ""))
            if not ok or not item then
                instance.failures = instance.failures + 1
                return false, "createFailed"
            end
            instance.created = instance.created + 1
            return true, {
                item = item,
                itemId = Support.itemId(item),
                fullType = Support.fullType(item),
                container = container,
            }
        end,
        removeCreated = function(actor, receipt)
            if type(receipt) ~= "table" or not receipt.item then return false end
            local item, _, container = query.resolveItem(actor, receipt.itemId)
            container = container or receipt.container
            if item ~= receipt.item or not container or type(container.Remove) ~= "function" then
                return false
            end
            local ok = pcall(container.Remove, container, receipt.item)
            if not ok or query.resolveItem(actor, receipt.itemId) then
                instance.failures = instance.failures + 1
                return false
            end
            instance.removed = instance.removed + 1
            return true
        end,
        setMagazineRounds = function(_, magazine, rounds)
            if not magazine or type(magazine.setCurrentAmmoCount) ~= "function" then return false end
            local ok = pcall(magazine.setCurrentAmmoCount, magazine, Support.integer(rounds, 0, 0))
            if not ok then instance.failures = instance.failures + 1 end
            return ok
        end,
        restoreMagazineRounds = function(_, magazine, rounds)
            if not magazine or type(magazine.setCurrentAmmoCount) ~= "function" then return false end
            local ok = pcall(magazine.setCurrentAmmoCount, magazine, Support.integer(rounds, 0, 0))
            if not ok then instance.failures = instance.failures + 1 end
            return ok
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
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "mutationFailure" or (self.started and "healthy" or "stopped"),
            data = {
                removed = self.removed,
                restored = self.restored,
                created = self.created,
                failures = self.failures,
            },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
