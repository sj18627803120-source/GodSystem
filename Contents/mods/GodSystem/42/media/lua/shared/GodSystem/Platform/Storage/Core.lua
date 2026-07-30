require "GodSystem/Platform/Storage/Support"

GodSystemStorageCorePlatform = GodSystemStorageCorePlatform or {}

local Descriptor = GodSystemStorageCorePlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.core"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local config = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local tokenKey = tostring(config.StorageCoreTokenKey
        or "GodSystemStorageCoreToken")
    local networkKey = tostring(config.StorageCoreNetworkKey
        or "GodSystemStorageCoreNetworkId")
    local counters = {
        searches = 0, creates = 0, removes = 0, restores = 0,
        duplicatesRemoved = 0, failures = 0,
    }
    local public = {}

    local function rootInventory(actor)
        return Support.read(actor, { "getInventory" }, nil)
    end

    local function identity(item)
        local data = Support.modData(item)
        if type(data) ~= "table" then return nil, nil end
        return tostring(data[networkKey] or ""), tostring(data[tokenKey] or "")
    end

    local function assign(item, networkId, token)
        local data = Support.modData(item)
        if type(data) ~= "table" then return false end
        data[networkKey] = tostring(networkId or "")
        data[tokenKey] = tostring(token or "")
        if type(item.transmitModData) == "function" then
            local called = pcall(item.transmitModData, item)
            if not called then return false end
        end
        local actualNetwork, actualToken = identity(item)
        return actualNetwork == tostring(networkId or "")
            and actualToken == tostring(token or "")
    end

    local function sync(kind, container, item)
        local name = kind == "add" and "sendAddItemToContainer"
            or "sendRemoveItemFromContainer"
        local callback = type(binding[name]) == "function"
            and binding[name] or Support.api(binding, name)
        if type(callback) == "function" then
            local called, result = pcall(callback, container, item)
            if not called or result == false then return false end
        end
        Support.write(container, { "setDrawDirty" }, true)
        return true
    end

    local function candidates(actor)
        local result = {}
        local root = rootInventory(actor)
        local seenContainers = {}
        local function visit(container, depth)
            if not container or seenContainers[container] or depth > 32 then return end
            seenContainers[container] = true
            local rows = Support.items(container)
            for index = 1, #rows do
                result[#result + 1] = { item = rows[index], container = container }
                visit(Support.child(rows[index]), depth + 1)
            end
        end
        visit(root, 0)
        return result
    end

    function public.find(actor, networkId, token, expectedId)
        counters.searches = counters.searches + 1
        local expectedNetwork, expectedToken = tostring(networkId or ""),
            tostring(token or "")
        local expectedItemId = tostring(expectedId or "")
        local rows = candidates(actor)
        for index = 1, #rows do
            local item = rows[index].item
            local itemNetwork, itemToken = identity(item)
            if itemNetwork == expectedNetwork and itemToken == expectedToken
                and (expectedItemId == ""
                    or Support.itemId(item) == expectedItemId)
            then
                return item, rows[index].container
            end
        end
        return nil, "coreMissing"
    end

    function public.create(actor, networkId, token, fullType)
        local inventory = rootInventory(actor)
        if not inventory then return nil, "inventoryMissing" end
        local item
        local factory = type(binding.createItem) == "function"
            and binding.createItem or nil
        if not factory then
            local inventoryItemFactory = type(binding.InventoryItemFactory) == "table"
                and binding.InventoryItemFactory
                or (type(_G) == "table" and _G.InventoryItemFactory or nil)
            if inventoryItemFactory
                and type(inventoryItemFactory.CreateItem) == "function"
            then
                factory = inventoryItemFactory.CreateItem
            end
        end
        if factory then
            local called, created = pcall(factory, fullType)
            if called then item = created end
            if item then
                local addCalled = type(inventory.AddItem) == "function"
                    and pcall(inventory.AddItem, inventory, item) or false
                if not addCalled or not Support.contains(inventory, item) then
                    counters.failures = counters.failures + 1
                    return nil, "coreAddFailed"
                end
            end
        else
            local called, created = Support.call(inventory, "AddItem", fullType)
            if called then item = created end
        end
        if not item or Support.fullType(item) ~= tostring(fullType or "")
            or not Support.contains(inventory, item)
        then
            counters.failures = counters.failures + 1
            return nil, "coreCreateFailed"
        end
        if not assign(item, networkId, token) or not sync("add", inventory, item) then
            if Support.contains(inventory, item) then
                Support.remove(inventory, item)
            end
            counters.failures = counters.failures + 1
            return nil, "coreSyncFailed"
        end
        counters.creates = counters.creates + 1
        return item
    end

    function public.remove(actor, item)
        if not item then return false, "coreMissing" end
        local inventory = rootInventory(actor)
        local itemId = Support.itemId(item)
        local found, container = Support.findRecursive(inventory, itemId, 32)
        if found ~= item and Support.itemId(found) ~= itemId then
            return false, "coreNotOwned"
        end
        if not container then
            container = Support.read(item, { "getContainer" }, nil)
        end
        if not container or not Support.contains(container, item) then
            return false, "coreNotOwned"
        end
        local receipt = { container = container }
        if not Support.remove(container, item) then
            counters.failures = counters.failures + 1
            return false, "coreRemoveFailed"
        end
        if not sync("remove", container, item) then
            Support.add(container, item)
            counters.failures = counters.failures + 1
            return false, "coreSyncFailed"
        end
        counters.removes = counters.removes + 1
        return true, receipt
    end

    function public.restore(actor, item, receipt)
        local target = type(receipt) == "table" and receipt.container or nil
        target = target or rootInventory(actor)
        if not target or not item then return false, "restoreMissing" end
        local added = Support.add(target, item)
        if not added or not sync("add", target, item) then
            if added then Support.remove(target, item) end
            counters.failures = counters.failures + 1
            return false, "restoreFailed"
        end
        counters.restores = counters.restores + 1
        return true
    end

    function public.cleanupDuplicates(actor, networkId, keep)
        local rows = candidates(actor)
        local removed = 0
        for index = 1, #rows do
            local item, container = rows[index].item, rows[index].container
            local itemNetwork = identity(item)
            if item ~= keep and itemNetwork == tostring(networkId or "")
                and Support.remove(container, item)
            then
                if sync("remove", container, item) then
                    removed = removed + 1
                else
                    Support.add(container, item)
                end
            end
        end
        counters.duplicatesRemoved = counters.duplicatesRemoved + removed
        return removed
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
