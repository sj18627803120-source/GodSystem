require "GodSystem/Platform/Storage/Support"

GodSystemStorageContainersPlatform = GodSystemStorageContainersPlatform or {}

local Descriptor = GodSystemStorageContainersPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.containers"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local counters = {
        lists = 0, accepts = 0, adds = 0, removes = 0, grounds = 0,
        failures = 0,
    }
    local public = {}

    local function directItem(container, expectedId)
        expectedId = tostring(expectedId or "")
        local rows = Support.items(container)
        for index = 1, #rows do
            if Support.itemId(rows[index]) == expectedId then return rows[index] end
        end
        return nil
    end

    local function entryItem(entry)
        local value = Support.read(entry, { "getItem" }, nil)
        return value or entry
    end

    local function isEquipped(actor, item)
        if Support.read(actor, { "getPrimaryHandItem" }, nil) == item
            or Support.read(actor, { "getSecondaryHandItem" }, nil) == item
            or Support.read(actor, { "isItemInBothHands" }, false, item) == true
            or Support.read(actor, { "isEquipped" }, false, item) == true
        then
            return true
        end
        for _, methodName in ipairs({ "getAttachedItems", "getWornItems" }) do
            local rows = Support.values(Support.read(actor, { methodName }, nil))
            for index = 1, #rows do
                if entryItem(rows[index]) == item then return true end
            end
        end
        return false
    end

    function public.list(container)
        counters.lists = counters.lists + 1
        return Support.items(container)
    end

    function public.child(item)
        return Support.child(item)
    end

    function public.contains(container, item)
        return Support.contains(container, item)
    end

    function public.accepts(container, actor, item)
        counters.accepts = counters.accepts + 1
        if not container or not item then return false, "invalid" end
        if type(container.isItemAllowed) == "function" then
            local called, allowed = pcall(container.isItemAllowed, container, item)
            if called and allowed == false then return false, "notAllowed" end
        end
        if type(container.hasRoomFor) == "function" then
            local called, room = pcall(container.hasRoomFor, container, actor, item)
            if not called then
                called, room = pcall(container.hasRoomFor, container, item)
            end
            if called and room == false then return false, "full" end
        end
        return true
    end

    function public.remove(container, item)
        if not container or not item or not Support.contains(container, item) then
            return false
        end
        local called = type(container.Remove) == "function"
            and pcall(container.Remove, container, item) or false
        if not called or Support.contains(container, item) then
            counters.failures = counters.failures + 1
            return false
        end
        counters.removes = counters.removes + 1
        return true
    end

    function public.add(container, item)
        if not container or not item then return false end
        local called = type(container.AddItem) == "function"
            and pcall(container.AddItem, container, item) or false
        if not called or not Support.contains(container, item) then
            counters.failures = counters.failures + 1
            return false
        end
        counters.adds = counters.adds + 1
        return true
    end

    function public.playerContainer(actor, itemId)
        local root = Support.read(actor, { "getInventory" }, nil)
        if not root then return nil, "targetMissing" end
        if itemId == nil or tostring(itemId) == "" then return root end
        local item = directItem(root, itemId)
        if not item then return nil, "targetMissing" end
        local child = Support.child(item)
        if not child then return nil, "targetInvalid" end
        local fullType = string.lower(Support.fullType(item))
        local keyRing = string.find(fullType, "keyring", 1, true) ~= nil
            or string.find(fullType, "key_ring", 1, true) ~= nil
        if not isEquipped(actor, item) and not keyRing then
            return nil, "targetInvalid"
        end
        return child, item
    end

    function public.ground(fallbackObject, actor, item)
        if not item then return false end
        local raw = type(fallbackObject) == "table" and fallbackObject.raw
            or fallbackObject
        local square = Support.read(raw, { "getSquare" }, nil)
            or Support.read(actor, { "getSquare" }, nil)
        if not square or type(square.AddWorldInventoryItem) ~= "function" then
            counters.failures = counters.failures + 1
            return false
        end
        local called, worldItem = pcall(square.AddWorldInventoryItem,
            square, item, 0.5, 0.5, 0)
        if not called or worldItem == false then
            counters.failures = counters.failures + 1
            return false
        end
        counters.grounds = counters.grounds + 1
        return true
    end

    function public.capacity(container)
        return math.max(0, Support.number(
            Support.read(container, { "getCapacity" }, 0), 0) or 0)
    end

    function public.used(container)
        return math.max(0, Support.number(
            Support.read(container, { "getContentsWeight" }, 0), 0) or 0)
    end

    function public.cold(container, link)
        local role = type(link) == "table" and tostring(link.role or "") or ""
        local containerType = string.lower(tostring(
            Support.read(container, { "getType" }, "") or ""))
        return role == "fridge" or role == "freezer"
            or string.find(containerType, "fridge", 1, true) ~= nil
            or string.find(containerType, "freezer", 1, true) ~= nil
    end

    function public.powered(container, link)
        if not public.cold(container, link) then return false end
        if type(container.isPowered) == "function" then
            local called, value = pcall(container.isPowered, container)
            if called then return value == true end
        end
        local sourceGrid = Support.read(container, { "getSourceGrid" }, nil)
        return Support.read(sourceGrid, { "haveElectricity" }, false) == true
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
