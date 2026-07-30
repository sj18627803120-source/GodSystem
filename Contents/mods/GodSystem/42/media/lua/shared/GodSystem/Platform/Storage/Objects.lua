require "GodSystem/Platform/Storage/Support"

GodSystemStorageObjectsPlatform = GodSystemStorageObjectsPlatform or {}

local Descriptor = GodSystemStorageObjectsPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.objects"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local config = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local objectIdKey = tostring(config.StorageObjectIdKey
        or "GodSystemStorageObjectId")
    local markerKey = tostring(config.StorageNetworkContainerKey
        or "GodSystemStorageNetworkContainerV2")
    local settingsKey = tostring(config.StorageContainerSettingsKey
        or "GodSystemStorageContainerSettingsV1")
    local coreKey = tostring(config.StorageCoreHostKey
        or "GodSystemStorageCoreHostV1")
    local counters = {
        resolves = 0, markers = 0, settings = 0, coreChanges = 0,
        unloaded = 0, failures = 0,
    }
    local public = {}

    local function rawObject(value)
        if type(value) == "table" and value.raw then return value.raw end
        return value
    end

    local function objectName(object, marker)
        if type(marker) == "table" and tostring(marker.name or "") ~= "" then
            return tostring(marker.name):sub(1, 60)
        end
        local name = Support.read(object, { "getObjectName", "getName" }, nil)
        if name ~= nil and tostring(name) ~= "" then return tostring(name):sub(1, 60) end
        local container = Support.read(object, { "getContainer" }, nil)
        name = Support.read(container, { "getType" }, nil)
        if name ~= nil and tostring(name) ~= "" then return tostring(name):sub(1, 60) end
        local sprite = Support.spriteName(object)
        return sprite ~= "" and sprite:sub(1, 60) or "Container"
    end

    local function wrap(object)
        if not object then return nil end
        local data = Support.modData(object)
        local objectId = type(data) == "table" and tostring(data[objectIdKey] or "") or ""
        if objectId == "" then return nil end
        local position = Support.position(object)
        if not position then return nil end
        local marker = type(data[markerKey]) == "table" and data[markerKey] or nil
        return {
            raw = object,
            objectId = objectId,
            x = Support.integer(position.x, 0),
            y = Support.integer(position.y, 0),
            z = Support.integer(position.z, 0),
            sprite = Support.spriteName(object),
            name = objectName(object, marker),
        }
    end

    local function ensureObjectId(object)
        local data = Support.modData(object)
        if type(data) ~= "table" then return nil end
        local objectId = tostring(data[objectIdKey] or "")
        local created = false
        if objectId == "" then
            local position = Support.position(object) or {}
            local seed = table.concat({
                tostring(position.x or ""),
                tostring(position.y or ""),
                tostring(position.z or ""),
                Support.spriteName(object),
            }, ":")
            objectId = Support.newId(binding, "storage-object", seed)
            data[objectIdKey] = objectId
            created = true
        end
        return objectId, created
    end

    local function slotRows(object)
        local result = {}
        local count = Support.integer(
            Support.read(object, { "getContainerCount" }, 0), 0, 0)
        if count > 0 and type(object.getContainerByIndex) == "function" then
            for slotIndex = 0, count - 1 do
                local container = Support.read(object,
                    { "getContainerByIndex" }, nil, slotIndex)
                if container then
                    local typeName = tostring(
                        Support.read(container, { "getType" }, "") or "")
                    result[#result + 1] = {
                        slotIndex = slotIndex,
                        index = slotIndex,
                        container = container,
                        type = typeName,
                        name = typeName ~= "" and typeName or objectName(object),
                    }
                end
            end
        else
            local container = Support.read(object, { "getContainer" }, nil)
            if container then
                local typeName = tostring(
                    Support.read(container, { "getType" }, "") or "")
                result[1] = {
                    slotIndex = 0,
                    index = 0,
                    container = container,
                    type = typeName,
                    name = typeName ~= "" and typeName or objectName(object),
                }
            end
        end
        return result
    end

    local function normalizeSet(value)
        local result = {}
        if type(value) ~= "table" then return result end
        for key, child in pairs(value) do
            local name = type(key) == "number" and tostring(child or "")
                or tostring(key or "")
            local enabled = type(key) == "number" or child == true
            if enabled and name ~= "" then result[name] = true end
        end
        return result
    end

    local function normalizeSettings(value, assignedOrder)
        value = type(value) == "table" and value or {}
        local priority = tostring(value.priorityTier or value.priority or "normal")
        local validPriority = {
            lowest = true, low = true, normal = true, high = true, highest = true,
        }
        if not validPriority[priority] then
            local numeric = Support.integer(priority, 50, 0, 100)
            priority = numeric <= 20 and "lowest"
                or (numeric <= 40 and "low")
                or (numeric <= 60 and "normal")
                or (numeric <= 80 and "high")
                or "highest"
        end
        return {
            role = tostring(value.role or "general"),
            priorityTier = priority,
            assignedOrder = Support.number(value.assignedOrder,
                assignedOrder or 0) or 0,
            allowCategories = normalizeSet(
                value.allowCategories or value.allowedCategories),
            denyCategories = normalizeSet(
                value.denyCategories or value.deniedCategories),
        }
    end

    local function markerFor(object)
        local data = Support.modData(rawObject(object))
        local value = type(data) == "table" and data[markerKey] or nil
        if type(value) ~= "table" or value.enabled ~= true then return nil end
        return Support.copy(value)
    end

    function public.actorPosition(actor)
        return Support.position(actor)
    end

    function public.reference(object, create)
        object = rawObject(object)
        if not object then return nil, "objectMissing" end
        local data = Support.modData(object)
        if type(data) ~= "table" then return nil, "objectModDataMissing" end
        local objectId = tostring(data[objectIdKey] or "")
        local created = false
        if objectId == "" and create == true then
            objectId, created = ensureObjectId(object)
        end
        if objectId == "" then return nil, "objectIdentityMissing" end
        if created and type(object.transmitModData) == "function" then
            local called, value = pcall(object.transmitModData, object)
            if not called or value == false then
                data[objectIdKey] = nil
                counters.failures = counters.failures + 1
                return nil, "objectIdentitySyncFailed"
            end
        end
        local result = wrap(object)
        return result, result and nil or "objectInvalid"
    end

    function public.scope(actor, position)
        if type(binding.scope) == "function" then
            local called, value = pcall(binding.scope, actor, Support.copy(position))
            if called and type(value) == "table" then return Support.copy(value) end
        end
        local safehouse = Support.safehouseAt(binding, position.x, position.y)
        if safehouse then
            local key = Support.safehouseKey(safehouse)
            return {
                kind = "safehouse",
                key = key,
                owner = tostring(Support.read(safehouse, { "getOwner" },
                    Support.identity(actor, binding)) or Support.identity(actor, binding)),
            }
        end
        local identity = Support.identity(actor, binding)
        return { kind = "personal", key = "personal:" .. identity, owner = identity }
    end

    function public.resolve(reference)
        counters.resolves = counters.resolves + 1
        if type(reference) ~= "table" or tostring(reference.objectId or "") == "" then
            counters.failures = counters.failures + 1
            return nil, "invalidObjectReference"
        end
        local square = Support.square(binding, reference.x, reference.y, reference.z)
        if not square then
            counters.unloaded = counters.unloaded + 1
            return nil, "squareUnloaded"
        end
        local expectedId = tostring(reference.objectId)
        local rows = Support.squareObjects(square)
        for index = 1, #rows do
            local data = Support.modData(rows[index])
            if type(data) == "table"
                and tostring(data[objectIdKey] or "") == expectedId
            then
                local result = wrap(rows[index])
                if result then return result, nil end
                return nil, "objectInvalid"
            end
        end
        return nil, "objectMissing"
    end

    function public.adjacent(object, scopeKey)
        local source = type(object) == "table" and object or wrap(object)
        if not source then return {} end
        local result, seen = {}, {}
        local offsets = {
            { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        }
        for index = 1, #offsets do
            local square = Support.square(binding,
                source.x + offsets[index][1], source.y + offsets[index][2], source.z)
            local rows = Support.squareObjects(square)
            for rowIndex = 1, #rows do
                local candidate = wrap(rows[rowIndex])
                local marker = candidate and markerFor(candidate) or nil
                if candidate
                    and candidate.objectId ~= source.objectId
                    and not seen[candidate.objectId]
                    and type(marker) == "table"
                    and tostring(marker.scopeKey or "") == tostring(scopeKey or "")
                    and #slotRows(rows[rowIndex]) > 0
                then
                    seen[candidate.objectId] = true
                    result[#result + 1] = candidate
                end
            end
        end
        table.sort(result, function(left, right)
            return tostring(left.objectId) < tostring(right.objectId)
        end)
        return result
    end

    function public.slots(object)
        return slotRows(rawObject(object))
    end

    function public.marker(object)
        return markerFor(object)
    end

    function public.setMarker(object, marker)
        object = rawObject(object)
        local data = Support.modData(object)
        if type(data) ~= "table" or type(marker) ~= "table" then
            counters.failures = counters.failures + 1
            return false, "markerInvalid"
        end
        local objectId = ensureObjectId(object)
        if not objectId then
            counters.failures = counters.failures + 1
            return false, "objectIdentityFailed"
        end
        local row = {
            enabled = true,
            objectId = objectId,
            scopeKey = tostring(marker.scopeKey or ""),
            owner = tostring(marker.owner or ""),
            name = tostring(marker.name or objectName(object)):sub(1, 60),
            markedAtMs = Support.number(marker.markedAtMs,
                Support.nowMs(binding)) or Support.nowMs(binding),
        }
        data[markerKey] = row
        data[settingsKey] = type(data[settingsKey]) == "table"
            and data[settingsKey] or {}
        local slots = slotRows(object)
        for index = 1, #slots do
            local key = tostring(slots[index].slotIndex)
            if type(data[settingsKey][key]) ~= "table" then
                data[settingsKey][key] = normalizeSettings(marker,
                    row.markedAtMs * 100 + slots[index].slotIndex)
            end
        end
        counters.markers = counters.markers + 1
        return true, nil, Support.copy(row)
    end

    function public.clearMarker(object)
        object = rawObject(object)
        local data = Support.modData(object)
        if type(data) ~= "table" then
            counters.failures = counters.failures + 1
            return false, "objectModDataMissing"
        end
        data[markerKey] = nil
        data[settingsKey] = nil
        counters.markers = counters.markers + 1
        return true
    end

    function public.settings(object, slotIndex)
        object = rawObject(object)
        local data = Support.modData(object)
        if type(data) ~= "table" then return nil end
        local rows = type(data[settingsKey]) == "table" and data[settingsKey] or {}
        local marker = type(data[markerKey]) == "table" and data[markerKey] or {}
        local key = tostring(Support.integer(slotIndex, 0))
        return normalizeSettings(rows[key],
            (Support.number(marker.markedAtMs, Support.nowMs(binding))
                or Support.nowMs(binding)) * 100 + Support.integer(slotIndex, 0))
    end

    function public.setSettings(object, slotIndex, settings)
        object = rawObject(object)
        local data = Support.modData(object)
        if type(data) ~= "table" then
            counters.failures = counters.failures + 1
            return false, "objectModDataMissing"
        end
        data[settingsKey] = type(data[settingsKey]) == "table"
            and data[settingsKey] or {}
        local key = tostring(Support.integer(slotIndex, 0))
        data[settingsKey][key] = normalizeSettings(settings,
            Support.nowMs(binding) * 100 + Support.integer(slotIndex, 0))
        counters.settings = counters.settings + 1
        return true, nil, Support.copy(data[settingsKey][key])
    end

    function public.coreMarker(object)
        local data = Support.modData(rawObject(object))
        local row = type(data) == "table" and data[coreKey] or nil
        if type(row) ~= "table" or row.installed ~= true then return nil end
        return Support.copy(row)
    end

    function public.installCore(object, networkId, token)
        object = rawObject(object)
        local data = Support.modData(object)
        local marker = markerFor(object)
        if type(data) ~= "table" then return false, "objectModDataMissing" end
        if type(marker) ~= "table" then return false, "networkContainerRequired" end
        if #slotRows(object) == 0 then return false, "containerMissing" end
        local current = data[coreKey]
        if type(current) == "table" and current.installed == true then
            return false, "coreInstalled"
        end
        local networkText, tokenText = tostring(networkId or ""), tostring(token or "")
        if networkText == "" or tokenText == "" then return false, "coreIdentityMissing" end
        data[coreKey] = {
            installed = true,
            hostVersion = 2,
            capacityMode = "networkStorage",
            networkId = networkText,
            token = tokenText,
            objectId = tostring(marker.objectId or ""),
            installedAtMs = Support.nowMs(binding),
        }
        counters.coreChanges = counters.coreChanges + 1
        return true, nil, Support.copy(data[coreKey])
    end

    function public.removeCore(object, expectedToken)
        object = rawObject(object)
        local data = Support.modData(object)
        local current = type(data) == "table" and data[coreKey] or nil
        if type(current) ~= "table" or current.installed ~= true then
            return false, "coreHostMissing"
        end
        if tostring(expectedToken or "") ~= ""
            and tostring(current.token or "") ~= tostring(expectedToken)
        then
            return false, "coreExpired"
        end
        local receipt = Support.copy(current)
        data[coreKey] = nil
        counters.coreChanges = counters.coreChanges + 1
        return true, receipt
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
