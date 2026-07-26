require "GodSystem_Config"

GodSystemStorage = GodSystemStorage or {}

local Storage = GodSystemStorage

Storage.SchemaVersion = 1
Storage.Module = "GodSystemStorage"
Storage.StoreKey = (GodSystemConfig.DataKey or "GodSystem_CN_Data") .. "_StorageNetworkV1"
Storage.ControllerFullType = "GodSystem.StorageController"
Storage.ControllerTokenKey = "GodSystemStorageControllerToken"
Storage.ControllerNetworkKey = "GodSystemStorageNetworkId"
Storage.ControllerInstalledKey = "GodSystemStorageControllerInstalled"
Storage.ControllerObjectIdKey = "GodSystemStorageControllerObjectId"
Storage.ObjectIdKey = "GodSystemStorageObjectId"
Storage.ObjectLinksKey = "GodSystemStorageLinks"
Storage.ControllerRecoveryCost = 2000
Storage.ControllerPlacementDistance = 4.5
Storage.DefaultRadius = 30
Storage.DefaultMaxLinks = 64
Storage.MinRadius = 1
Storage.MaxRadius = 60
Storage.MinLinks = 1
Storage.MaxLinks = 128
Storage.MaxDepth = 32
Storage.MaxIndexedItems = 20000
Storage.IndexBatchItems = 250
Storage.IndexBudgetMs = 2
Storage.SnapshotGroupChunk = 100
Storage.ControllerUseDistance = 3.5

Storage.Roles = {
    "auto", "general", "fridge", "freezer", "food", "medical", "weapon",
    "ammo", "tool", "material", "clothing", "book", "liquid", "noAuto",
}

Storage.Categories = {
    "food", "perishable", "drink", "medical", "weapon", "ammo", "tool",
    "material", "clothing", "book", "container", "furniture", "other",
}

Storage.ProtectedFullTypes = {
    ["GodSystem.SystemCoin1"] = true,
    ["GodSystem.SystemCoin10"] = true,
    ["GodSystem.SystemCoin100"] = true,
    ["GodSystem.SystemSpaceTerminal"] = true,
    ["GodSystem.SystemTerminalRelief"] = true,
    ["GodSystem.StorageController"] = true,
}

local function number(value, fallback)
    local result = tonumber(value)
    if result == nil or result ~= result or result == math.huge or result == -math.huge then
        return fallback or 0
    end
    return result
end

local function integer(value, fallback)
    return math.floor(number(value, fallback or 0))
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function safeCall(object, methodName, fallback, ...)
    if not object or not methodName or not object[methodName] then return fallback end
    local args = { ... }
    local unpackFn = unpack or (table and table.unpack)
    local ok, value = pcall(function()
        if unpackFn then return object[methodName](object, unpackFn(args)) end
        return object[methodName](object)
    end)
    if ok and value ~= nil then return value end
    return fallback
end

Storage.number = number
Storage.integer = integer
Storage.clamp = clamp
Storage.safeCall = safeCall

function Storage.nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Storage.newId(prefix, seed)
    local random = ZombRand and ZombRand(1000000000) or math.random(1, 999999999)
    local raw = tostring(seed or "") .. ":" .. tostring(Storage.nowMs()) .. ":" .. tostring(random)
    local hash = 5381
    for i = 1, #raw do hash = ((hash * 33) + string.byte(raw, i)) % 2147483647 end
    return tostring(prefix or "gs") .. "-" .. tostring(Storage.nowMs()) .. "-" .. tostring(hash)
end

function Storage.playerKey(player)
    local username = safeCall(player, "getUsername", nil)
    if username and tostring(username) ~= "" then return tostring(username) end
    return tostring(safeCall(player, "getOnlineID", "sp"))
end

function Storage.itemId(item)
    local value = safeCall(item, "getID", nil)
    if value == nil then return nil end
    return tostring(value)
end

function Storage.itemFullType(item)
    return tostring(safeCall(item, "getFullType", "") or "")
end

function Storage.isController(item)
    return Storage.itemFullType(item) == Storage.ControllerFullType
end

function Storage.isProtected(item)
    return Storage.ProtectedFullTypes[Storage.itemFullType(item)] == true
end

function Storage.getControllerIdentity(item)
    if not Storage.isController(item) then return nil, nil end
    local data = safeCall(item, "getModData", nil)
    if type(data) ~= "table" then return nil, nil end
    return tostring(data[Storage.ControllerNetworkKey] or ""), tostring(data[Storage.ControllerTokenKey] or "")
end

function Storage.setControllerIdentity(item, networkId, token)
    if not Storage.isController(item) then return false end
    local data = safeCall(item, "getModData", nil)
    if type(data) ~= "table" then return false end
    data[Storage.ControllerNetworkKey] = tostring(networkId or "")
    data[Storage.ControllerTokenKey] = tostring(token or "")
    if item.transmitModData then pcall(item.transmitModData, item) end
    return true
end

function Storage.getInstalledControllerIdentity(object)
    if not object then return nil, nil, nil, nil end
    local data = safeCall(object, "getModData", nil)
    if type(data) ~= "table" or data[Storage.ControllerInstalledKey] ~= true then
        return nil, nil, nil, nil
    end
    local item = safeCall(object, "getItem", nil)
    local networkId, token = Storage.getControllerIdentity(item)
    if not networkId or networkId == "" then networkId = tostring(data[Storage.ControllerNetworkKey] or "") end
    if not token or token == "" then token = tostring(data[Storage.ControllerTokenKey] or "") end
    return networkId, token, tostring(data[Storage.ControllerObjectIdKey] or ""), item
end

function Storage.markInstalledController(object, networkId, token, objectId)
    local data = safeCall(object, "getModData", nil)
    if type(data) ~= "table" then return false end
    data[Storage.ControllerInstalledKey] = true
    data[Storage.ControllerNetworkKey] = tostring(networkId or "")
    data[Storage.ControllerTokenKey] = tostring(token or "")
    data[Storage.ControllerObjectIdKey] = tostring(objectId or "")
    if object.transmitModData then pcall(object.transmitModData, object) end
    return true
end

function Storage.isInstalledController(object)
    local networkId, token = Storage.getInstalledControllerIdentity(object)
    return networkId ~= nil and networkId ~= "" and token ~= nil and token ~= ""
end

function Storage.getItemContainer(item)
    return safeCall(item, "getContainer", nil)
end

function Storage.containerContains(container, item)
    if not container or not item then return false end
    local items = safeCall(container, "getItems", nil)
    if not items then return false end
    if items.contains then
        local ok, value = pcall(function() return items:contains(item) end)
        if ok then return value == true end
    end
    local size = integer(safeCall(items, "size", 0), 0)
    for i = 0, size - 1 do
        if safeCall(items, "get", nil, i) == item then return true end
    end
    return false
end

function Storage.findItemRecursive(container, expectedId, maxDepth)
    expectedId = tostring(expectedId or "")
    if expectedId == "" or not container then return nil, nil end
    local seen = {}
    local function visit(current, depth)
        if not current or seen[current] or depth > (maxDepth or Storage.MaxDepth) then return nil, nil end
        seen[current] = true
        local items = safeCall(current, "getItems", nil)
        local size = integer(safeCall(items, "size", 0), 0)
        for i = 0, size - 1 do
            local item = safeCall(items, "get", nil, i)
            if Storage.itemId(item) == expectedId then return item, current end
            local child = safeCall(item, "getInventory", nil)
            local found, source = visit(child, depth + 1)
            if found then return found, source end
        end
        return nil, nil
    end
    return visit(container, 0)
end

function Storage.objectCoordinates(object)
    local square = safeCall(object, "getSquare", nil)
    if not square then return nil end
    return {
        x = integer(safeCall(square, "getX", 0), 0),
        y = integer(safeCall(square, "getY", 0), 0),
        z = integer(safeCall(square, "getZ", 0), 0),
    }
end

function Storage.objectSpriteName(object)
    local sprite = safeCall(object, "getSprite", nil)
    return tostring(safeCall(sprite, "getName", "") or "")
end

function Storage.getObjectId(object, create)
    local data = safeCall(object, "getModData", nil)
    if type(data) ~= "table" then return nil end
    local objectId = tostring(data[Storage.ObjectIdKey] or "")
    if objectId == "" and create == true then
        local pos = Storage.objectCoordinates(object) or {}
        objectId = Storage.newId("obj", tostring(pos.x) .. ":" .. tostring(pos.y) .. ":" .. tostring(pos.z))
        data[Storage.ObjectIdKey] = objectId
    end
    if objectId == "" then return nil end
    return objectId
end

function Storage.getObjectIndex(object)
    local square = safeCall(object, "getSquare", nil)
    local objects = safeCall(square, "getObjects", nil)
    local size = integer(safeCall(objects, "size", 0), 0)
    for i = 0, size - 1 do
        if safeCall(objects, "get", nil, i) == object then return i end
    end
    return -1
end

function Storage.getContainerSlots(object)
    local result = {}
    if not object then return result end
    local count = integer(safeCall(object, "getContainerCount", 0), 0)
    if count > 0 and object.getContainerByIndex then
        for index = 0, count - 1 do
            local container = safeCall(object, "getContainerByIndex", nil, index)
            if container then
                result[#result + 1] = {
                    index = index,
                    key = tostring(index),
                    container = container,
                    type = tostring(safeCall(container, "getType", "") or ""),
                }
            end
        end
    else
        local container = safeCall(object, "getContainer", nil)
        if container then
            result[1] = {
                index = 0,
                key = "0",
                container = container,
                type = tostring(safeCall(container, "getType", "") or ""),
            }
        end
    end
    return result
end

function Storage.getContainerSlot(object, slotIndex)
    slotIndex = integer(slotIndex, 0)
    local slots = Storage.getContainerSlots(object)
    for i = 1, #slots do
        if slots[i].index == slotIndex then return slots[i] end
    end
    return nil
end

function Storage.getLinkMarker(object, slotIndex)
    local data = safeCall(object, "getModData", nil)
    local links = type(data) == "table" and data[Storage.ObjectLinksKey] or nil
    if type(links) ~= "table" then return nil end
    return links[tostring(integer(slotIndex, 0))]
end

function Storage.setLinkMarker(object, slotIndex, marker)
    local data = safeCall(object, "getModData", nil)
    if type(data) ~= "table" then return false end
    local links = data[Storage.ObjectLinksKey]
    if type(links) ~= "table" then
        links = {}
        data[Storage.ObjectLinksKey] = links
    end
    links[tostring(integer(slotIndex, 0))] = marker
    if object.transmitModData then pcall(object.transmitModData, object) end
    return true
end

function Storage.clearLinkMarker(object, slotIndex, expectedLinkId)
    local data = safeCall(object, "getModData", nil)
    local links = type(data) == "table" and data[Storage.ObjectLinksKey] or nil
    if type(links) ~= "table" then return false end
    local key = tostring(integer(slotIndex, 0))
    local marker = links[key]
    if expectedLinkId and type(marker) == "table" and tostring(marker.linkId or "") ~= tostring(expectedLinkId) then
        return false
    end
    links[key] = nil
    if object.transmitModData then pcall(object.transmitModData, object) end
    return true
end

function Storage.getSquare(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return safeCall(cell, "getGridSquare", nil, integer(x, 0), integer(y, 0), integer(z, 0))
end

function Storage.resolveObjectCandidate(x, y, z, objectIndex, expectedSprite)
    local square = Storage.getSquare(x, y, z)
    local objects = safeCall(square, "getObjects", nil)
    local object = safeCall(objects, "get", nil, integer(objectIndex, -1))
    if not object then return nil end
    if expectedSprite and tostring(expectedSprite) ~= "" and Storage.objectSpriteName(object) ~= tostring(expectedSprite) then
        return nil
    end
    return object
end

function Storage.resolveLink(link)
    if type(link) ~= "table" then return nil, nil, "invalidLink" end
    local square = Storage.getSquare(link.x, link.y, link.z)
    if not square then return nil, nil, "squareUnloaded" end
    local objects = safeCall(square, "getObjects", nil)
    local size = integer(safeCall(objects, "size", 0), 0)
    for i = 0, size - 1 do
        local object = safeCall(objects, "get", nil, i)
        local marker = Storage.getLinkMarker(object, link.slotIndex)
        if type(marker) == "table"
            and tostring(marker.linkId or "") == tostring(link.linkId or "")
            and tostring(marker.objectId or "") == tostring(link.objectId or "") then
            local slot = Storage.getContainerSlot(object, link.slotIndex)
            if slot and slot.container then return object, slot.container, nil end
            return object, nil, "containerMissing"
        end
    end
    return nil, nil, "objectMissing"
end

local function appendSquareObjects(result, seen, list)
    local size = integer(safeCall(list, "size", 0), 0)
    for i = 0, size - 1 do
        local object = safeCall(list, "get", nil, i)
        if object and not seen[object] then
            seen[object] = true
            result[#result + 1] = object
        end
    end
end

function Storage.squareObjects(square)
    local result, seen = {}, {}
    if not square then return result end
    appendSquareObjects(result, seen, safeCall(square, "getSpecialObjects", nil))
    appendSquareObjects(result, seen, safeCall(square, "getWorldObjects", nil))
    appendSquareObjects(result, seen, safeCall(square, "getObjects", nil))
    return result
end

function Storage.findWorldController(x, y, z, itemId, token, objectId)
    local square = Storage.getSquare(x, y, z)
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local worldObject = objects[i]
        local item = safeCall(worldObject, "getItem", nil)
        local networkId, itemToken = Storage.getControllerIdentity(item)
        local installedNetworkId, installedToken, installedObjectId, installedItem = Storage.getInstalledControllerIdentity(worldObject)
        if installedItem then
            item = installedItem
            networkId = installedNetworkId
            itemToken = installedToken
        end
        if Storage.isController(item)
            and (not itemId or tostring(itemId) == "" or Storage.itemId(item) == tostring(itemId))
            and (not token or tostring(token) == "" or itemToken == tostring(token))
            and (not objectId or tostring(objectId) == "" or installedObjectId == tostring(objectId)) then
            return worldObject, item
        end
    end
    return nil, nil
end

function Storage.distance2D(a, b)
    if not a or not b then return math.huge end
    local dx = number(a.x, 0) - number(b.x, 0)
    local dy = number(a.y, 0) - number(b.y, 0)
    return math.sqrt((dx * dx) + (dy * dy))
end

function Storage.positionOfPlayer(player)
    if not player then return nil end
    return {
        x = number(safeCall(player, "getX", 0), 0),
        y = number(safeCall(player, "getY", 0), 0),
        z = integer(safeCall(player, "getZ", 0), 0),
    }
end

local function javaListContains(list, text)
    if not list then return false end
    local size = integer(safeCall(list, "size", 0), 0)
    for i = 0, size - 1 do
        if tostring(safeCall(list, "get", "", i) or "") == tostring(text or "") then return true end
    end
    return false
end

function Storage.getSafehouseAt(x, y)
    if not SafeHouse or not SafeHouse.getSafehouseList then return nil end
    local list = SafeHouse.getSafehouseList()
    local size = integer(safeCall(list, "size", 0), 0)
    x, y = number(x, 0), number(y, 0)
    for i = 0, size - 1 do
        local safehouse = safeCall(list, "get", nil, i)
        local sx = number(safeCall(safehouse, "getX", 0), 0)
        local sy = number(safeCall(safehouse, "getY", 0), 0)
        local sw = number(safeCall(safehouse, "getW", 0), 0)
        local sh = number(safeCall(safehouse, "getH", 0), 0)
        if x >= sx and x < sx + sw and y >= sy and y < sy + sh then return safehouse end
    end
    return nil
end

function Storage.safehouseKey(safehouse)
    if not safehouse then return nil end
    local id = safeCall(safehouse, "getId", nil)
    if id ~= nil and tostring(id) ~= "" then return "safehouse:" .. tostring(id) end
    return table.concat({
        "safehouse",
        integer(safeCall(safehouse, "getX", 0), 0),
        integer(safeCall(safehouse, "getY", 0), 0),
        integer(safeCall(safehouse, "getW", 0), 0),
        integer(safeCall(safehouse, "getH", 0), 0),
    }, ":")
end

function Storage.playerAllowedSafehouse(player, safehouse)
    if not safehouse or not player then return false end
    local username = Storage.playerKey(player)
    if safeCall(safehouse, "isOwner", false, player) == true then return true end
    if safeCall(safehouse, "playerAllowed", false, username) == true then return true end
    if tostring(safeCall(safehouse, "getOwner", "") or "") == username then return true end
    return javaListContains(safeCall(safehouse, "getPlayers", nil), username)
end

function Storage.isAdmin(player)
    local level = tostring(safeCall(player, "getAccessLevel", "") or "")
    return level ~= "" and level ~= "None" and level ~= "none"
end

function Storage.isWithinNetworkRange(network, position)
    if type(network) ~= "table" or not position then return false end
    local controller = network.controller
    if type(controller) ~= "table" then return false end
    if network.scope == "safehouse" and network.safehouse then
        local controllerSafehouse = Storage.getSafehouseAt(controller.x, controller.y)
        if Storage.safehouseKey(controllerSafehouse) == tostring(network.safehouse) then
            local targetSafehouse = Storage.getSafehouseAt(position.x, position.y)
            if Storage.safehouseKey(targetSafehouse) == tostring(network.safehouse) then return true end
        end
    end
    if integer(position.z, 0) ~= integer(controller.z, 0) then return false end
    return Storage.distance2D(controller, position) <= clamp(number(network.radius, Storage.DefaultRadius), Storage.MinRadius, Storage.MaxRadius)
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function hasText(value, pattern)
    return string.find(lower(value), lower(pattern), 1, true) ~= nil
end

function Storage.categoryOf(item)
    local fullType = Storage.itemFullType(item)
    local category = lower(safeCall(item, "getDisplayCategory", ""))
    local itemType = lower(safeCall(item, "getType", ""))
    local container = safeCall(item, "getInventory", nil)
    local food = false
    if instanceof then
        local ok, value = pcall(instanceof, item, "Food")
        food = ok and value == true
    end
    if food or hasText(category, "food") then
        local age = number(safeCall(item, "getAge", 0), 0)
        local offAge = number(safeCall(item, "getOffAge", 1000000), 1000000)
        if offAge < 1000000 or age > 0 then return "perishable" end
        return "food"
    end
    if hasText(category, "drink") or hasText(itemType, "water") then return "drink" end
    if hasText(category, "medical") or hasText(fullType, "Bandage") or hasText(fullType, "Pills") then return "medical" end
    if hasText(category, "ammo") or hasText(category, "ammunition") then return "ammo" end
    if hasText(category, "weapon") or safeCall(item, "isAimedFirearm", false) == true then return "weapon" end
    if hasText(category, "tool") then return "tool" end
    if hasText(category, "clothing") or safeCall(item, "getBodyLocation", nil) then return "clothing" end
    if hasText(category, "literature") or hasText(category, "book") then return "book" end
    if hasText(category, "material") or hasText(category, "craft") then return "material" end
    if hasText(category, "furniture") or hasText(fullType, "Moveable") then return "furniture" end
    if container then return "container" end
    return "other"
end

function Storage.statesOf(item, sourceContainer)
    local result, seen = {}, {}
    local function add(value)
        if value and not seen[value] then seen[value] = true; result[#result + 1] = value end
    end
    if safeCall(item, "isFavorite", false) == true then add("favorite") end
    local condition = number(safeCall(item, "getCondition", 100), 100)
    local maxCondition = math.max(1, number(safeCall(item, "getConditionMax", 100), 100))
    if condition < maxCondition then add("damaged") end
    if condition / maxCondition <= 0.25 then add("lowCondition") end
    if safeCall(item, "isCooked", false) == true or safeCall(item, "isCooking", false) == true then add("cooking") end
    if safeCall(item, "isFrozen", false) == true then add("frozen") end
    if safeCall(item, "isRotten", false) == true then
        add("rotten")
    elseif safeCall(item, "isStale", false) == true then
        add("stale")
    elseif Storage.categoryOf(item) == "perishable" then
        add("fresh")
    end
    local temperature = number(safeCall(sourceContainer, "getTemprature", 1), 1)
    local containerType = lower(safeCall(sourceContainer, "getType", ""))
    if hasText(containerType, "freezer") or temperature <= 0.25 then
        add("frozen")
    elseif hasText(containerType, "fridge") or temperature < 1 then
        add("chilled")
    end
    return result
end

function Storage.itemModName(item)
    local scriptItem = safeCall(item, "getScriptItem", nil)
    local module = safeCall(scriptItem, "getModule", nil)
    local moduleName = safeCall(module, "getName", nil)
    if moduleName and tostring(moduleName) ~= "" then return tostring(moduleName) end
    local fullType = Storage.itemFullType(item)
    return fullType:match("^([^%.]+)%.") or "Base"
end

function Storage.itemGroupKey(item)
    local fullType = Storage.itemFullType(item)
    local worldSprite = tostring(safeCall(item, "getWorldSprite", "") or "")
    if worldSprite == "" then worldSprite = tostring(safeCall(item, "getName", "") or ""):match("%((%d+)%)$") or "" end
    return worldSprite ~= "" and (fullType .. "|" .. worldSprite) or fullType
end

function Storage.describeItem(item, sourceLink, sourceContainer)
    local condition = number(safeCall(item, "getCondition", 100), 100)
    local maxCondition = math.max(1, number(safeCall(item, "getConditionMax", 100), 100))
    local weight = number(safeCall(item, "getActualWeight", safeCall(item, "getWeight", 0)), 0)
    local usedDelta = number(safeCall(item, "getUsedDelta", 1), 1)
    local offAge = number(safeCall(item, "getOffAge", -1), -1)
    local age = number(safeCall(item, "getAge", 0), 0)
    local tags = {}
    local scriptItem = safeCall(item, "getScriptItem", nil)
    local tagList = safeCall(scriptItem, "getTags", nil)
    local tagCount = integer(safeCall(tagList, "size", 0), 0)
    for i = 0, math.min(tagCount - 1, 15) do tags[#tags + 1] = tostring(safeCall(tagList, "get", "", i) or "") end
    return {
        id = Storage.itemId(item),
        groupKey = Storage.itemGroupKey(item),
        fullType = Storage.itemFullType(item),
        name = tostring(safeCall(item, "getDisplayName", safeCall(item, "getName", Storage.itemFullType(item))) or ""),
        modName = Storage.itemModName(item),
        category = Storage.categoryOf(item),
        weight = math.max(0, weight),
        condition = condition,
        maxCondition = maxCondition,
        conditionRatio = condition / maxCondition,
        usedDelta = usedDelta,
        age = age,
        offAge = offAge,
        spoilageRemaining = offAge >= 0 and (offAge - age) or 1000000000,
        states = Storage.statesOf(item, sourceContainer),
        tags = tags,
        sourceLinkId = sourceLink and sourceLink.linkId or nil,
        sourceName = sourceLink and sourceLink.name or "",
    }
end

function Storage.isSafeDepositItem(player, item)
    if not item or Storage.isProtected(item) then return false, "protected" end
    if safeCall(item, "isFavorite", false) == true then return false, "favorite" end
    if safeCall(item, "getCategory", "") == "Key" or hasText(Storage.itemFullType(item), "Key") then return false, "key" end
    if safeCall(player, "getPrimaryHandItem", nil) == item or safeCall(player, "getSecondaryHandItem", nil) == item then
        return false, "hand"
    end
    if safeCall(player, "isItemInBothHands", false, item) == true then return false, "hand" end
    local hotbar = safeCall(player, "getAttachedItems", nil)
    local size = integer(safeCall(hotbar, "size", 0), 0)
    for i = 0, size - 1 do
        local entry = safeCall(hotbar, "get", nil, i)
        if safeCall(entry, "getItem", entry) == item then return false, "hotbar" end
    end
    local worn = safeCall(player, "getWornItems", nil)
    size = integer(safeCall(worn, "size", 0), 0)
    for i = 0, size - 1 do
        local entry = safeCall(worn, "get", nil, i)
        if safeCall(entry, "getItem", entry) == item then return false, "worn" end
    end
    return true, nil
end

function Storage.containerAccepts(container, player, item)
    if not container or not item then return false, "invalid" end
    if container.isItemAllowed then
        local ok, allowed = pcall(function() return container:isItemAllowed(item) end)
        if ok and allowed == false then return false, "notAllowed" end
    end
    if container.hasRoomFor then
        local ok, room = pcall(function() return container:hasRoomFor(player, item) end)
        if not ok then ok, room = pcall(function() return container:hasRoomFor(item) end) end
        if ok and room == false then return false, "full" end
    end
    return true, nil
end

function Storage.linkRoleAccepts(link, category)
    if type(link) ~= "table" or link.role == "noAuto" then return false end
    local denied = type(link.denyCategories) == "table" and link.denyCategories[category] == true
    if denied then return false end
    local allow = link.allowCategories
    if type(allow) == "table" and next(allow) ~= nil and allow[category] ~= true then return false end
    local role = tostring(link.role or "auto")
    if role == "auto" or role == "general" then return true end
    if role == "fridge" or role == "freezer" then return category == "food" or category == "perishable" or category == "drink" end
    if role == "food" then return category == "food" or category == "perishable" or category == "drink" end
    if role == "liquid" then return category == "drink" end
    return role == category
end

function Storage.isColdContainer(link, container)
    local role = type(link) == "table" and tostring(link.role or "") or ""
    local ctype = lower(safeCall(container, "getType", ""))
    return role == "fridge" or role == "freezer" or hasText(ctype, "fridge") or hasText(ctype, "freezer")
end

function Storage.isPoweredColdContainer(link, container)
    if not Storage.isColdContainer(link, container) then return false end
    if container.isPowered then
        local ok, powered = pcall(function() return container:isPowered() end)
        if ok then return powered == true end
    end
    local sourceGrid = safeCall(container, "getSourceGrid", nil)
    return safeCall(sourceGrid, "haveElectricity", false) == true
end

function Storage.routeCandidates(network, player, item)
    local category = Storage.categoryOf(item)
    local rows = {}
    for _, link in pairs((network and network.links) or {}) do
        local object, container = Storage.resolveLink(link)
        local online = object and container and Storage.isWithinNetworkRange(network, {
            x = link.x, y = link.y, z = link.z,
        })
        if online and Storage.linkRoleAccepts(link, category) then
            local accepted, reason = Storage.containerAccepts(container, player, item)
            if accepted then
                local cold = Storage.isPoweredColdContainer(link, container)
                local unusableCold = category == "perishable" and Storage.isColdContainer(link, container) and not cold
                if not unusableCold then
                    local coldScore = (category == "perishable" and cold) and 1 or 0
                    rows[#rows + 1] = {
                        link = link,
                        container = container,
                        cold = cold,
                        coldScore = coldScore,
                        priority = clamp(integer(link.priority, 50), 0, 100),
                    }
                end
            elseif reason ~= "full" then
                link.lastError = reason
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.coldScore ~= b.coldScore then return a.coldScore > b.coldScore end
        if a.priority ~= b.priority then return a.priority > b.priority end
        return tostring(a.link.linkId) < tostring(b.link.linkId)
    end)
    return rows, category == "perishable" and (#rows == 0 or rows[1].cold ~= true)
end

local function addToContainer(container, item)
    local ok = pcall(function() container:AddItem(item) end)
    return ok and Storage.containerContains(container, item)
end

local function removeFromContainer(container, item)
    local ok = pcall(function() container:Remove(item) end)
    return ok and not Storage.containerContains(container, item)
end

function Storage.syncRemove(container, item)
    if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, item) end
    if container and container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
end

function Storage.syncAdd(container, item)
    if sendAddItemToContainer then pcall(sendAddItemToContainer, container, item) end
    if container and container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
end

function Storage.transferItem(player, item, source, target, fallbackSquare, sourceValidator, targetValidator)
    if not item or not source or not target or source == target then return false, "invalid" end
    local function valid(validator)
        if not validator then return true end
        local ok, result = pcall(validator)
        return ok and result == true
    end
    local function restore(originalReason)
        if addToContainer(source, item) then
            Storage.syncAdd(source, item)
            return false, originalReason
        end
        local inventory = safeCall(player, "getInventory", nil)
        if inventory and addToContainer(inventory, item) then
            Storage.syncAdd(inventory, item)
            return false, "restoredToPlayer"
        end
        local square = fallbackSquare or safeCall(player, "getSquare", nil)
        if square and square.AddWorldInventoryItem then
            local ok = pcall(function() square:AddWorldInventoryItem(item, 0.5, 0.5, 0) end)
            if ok then return false, "restoredToGround" end
        end
        return false, "criticalRestoreFailed"
    end
    if not valid(sourceValidator) then return false, "sourceChanged" end
    if not Storage.containerContains(source, item) then return false, "sourceChanged" end
    if not valid(targetValidator) then return false, "targetChanged" end
    local accepted, reason = Storage.containerAccepts(target, player, item)
    if not accepted then return false, reason end
    if not removeFromContainer(source, item) then return false, "removeFailed" end
    Storage.syncRemove(source, item)
    if not valid(targetValidator) then return restore("targetChanged") end
    if addToContainer(target, item) then
        Storage.syncAdd(target, item)
        if valid(targetValidator) then return true, nil end
        if not removeFromContainer(target, item) then return false, "criticalRestoreFailed" end
        Storage.syncRemove(target, item)
        return restore("targetChanged")
    end
    return restore("targetAddFailed")
end

function Storage.newIndexJob(network)
    local job = {
        network = network,
        stack = {},
        seenContainers = {},
        groups = {},
        groupOrder = {},
        instances = {},
        links = {},
        processed = 0,
        onlineLinks = 0,
        offlineLinks = 0,
        totalCapacity = 0,
        usedCapacity = 0,
        incomplete = false,
        indexed = 0,
        done = false,
        startedAtMs = Storage.nowMs(),
    }
    local ordered = {}
    for _, link in pairs((network and network.links) or {}) do ordered[#ordered + 1] = link end
    table.sort(ordered, function(a, b) return tostring(a.linkId) < tostring(b.linkId) end)
    for i = 1, #ordered do
        local link = ordered[i]
        local object, container, reason = Storage.resolveLink(link)
        local online = object and container and Storage.isWithinNetworkRange(network, { x = link.x, y = link.y, z = link.z })
        link.online = online == true
        link.lastError = online and nil or (reason or "outOfRange")
        local summary = {
            linkId = link.linkId,
            name = link.name,
            role = link.role,
            priority = link.priority,
            x = link.x, y = link.y, z = link.z,
            online = online == true,
            reason = link.lastError,
            capacity = online and number(safeCall(container, "getCapacity", 0), 0) or 0,
            used = online and number(safeCall(container, "getContentsWeight", 0), 0) or 0,
            powered = online and Storage.isPoweredColdContainer(link, container) or false,
            allowCategories = link.allowCategories or {},
            denyCategories = link.denyCategories or {},
        }
        job.links[#job.links + 1] = summary
        if online then
            job.onlineLinks = job.onlineLinks + 1
            job.totalCapacity = job.totalCapacity + summary.capacity
            job.usedCapacity = job.usedCapacity + summary.used
            job.stack[#job.stack + 1] = { container = container, link = link, index = 0, depth = 0 }
        else
            job.offlineLinks = job.offlineLinks + 1
        end
    end
    return job
end

local function mergeItem(job, item, link, container)
    local row = Storage.describeItem(item, link, container)
    local key = row.groupKey
    local group = job.groups[key]
    if not group then
        group = {
            key = key,
            fullType = row.fullType,
            name = row.name,
            modName = row.modName,
            category = row.category,
            count = 0,
            totalWeight = 0,
            bestCondition = 0,
            earliestSpoilage = 1000000000,
            states = {},
            tags = {},
            sources = {},
            sourceNames = {},
        }
        job.groups[key] = group
        job.groupOrder[#job.groupOrder + 1] = key
        job.instances[key] = {}
    end
    group.count = group.count + 1
    group.totalWeight = group.totalWeight + row.weight
    group.bestCondition = math.max(group.bestCondition, row.conditionRatio)
    group.earliestSpoilage = math.min(group.earliestSpoilage, row.spoilageRemaining)
    for i = 1, #row.states do group.states[row.states[i]] = true end
    for i = 1, #row.tags do group.tags[row.tags[i]] = true end
    group.sources[tostring(row.sourceLinkId or "")] = true
    if tostring(row.sourceName or "") ~= "" then group.sourceNames[tostring(row.sourceName)] = true end
    job.instances[key][#job.instances[key] + 1] = row
end

function Storage.stepIndexJob(job, maxItems, budgetMs)
    if not job or job.done then return true end
    maxItems = clamp(integer(maxItems, Storage.IndexBatchItems), 1, Storage.IndexBatchItems)
    budgetMs = math.max(0.25, math.min(number(budgetMs, Storage.IndexBudgetMs), Storage.IndexBudgetMs))
    local started = Storage.nowMs()
    local handled = 0
    while #job.stack > 0 and handled < maxItems and Storage.nowMs() - started <= budgetMs do
        if job.processed >= Storage.MaxIndexedItems then
            job.incomplete = true
            job.stack = {}
            break
        end
        local frame = job.stack[#job.stack]
        if job.seenContainers[frame.container] and frame.index == 0 then
            table.remove(job.stack)
        else
            job.seenContainers[frame.container] = true
            local items = safeCall(frame.container, "getItems", nil)
            local size = integer(safeCall(items, "size", 0), 0)
            if frame.index >= size then
                table.remove(job.stack)
            else
                local item = safeCall(items, "get", nil, frame.index)
                frame.index = frame.index + 1
                handled = handled + 1
                job.processed = job.processed + 1
                if item and not Storage.isProtected(item) then
                    mergeItem(job, item, frame.link, frame.container)
                    job.indexed = job.indexed + 1
                end
                local child = item and safeCall(item, "getInventory", nil) or nil
                if child and frame.depth < Storage.MaxDepth and not job.seenContainers[child] then
                    job.stack[#job.stack + 1] = {
                        container = child,
                        link = frame.link,
                        index = 0,
                        depth = frame.depth + 1,
                    }
                end
            end
        end
    end
    if #job.stack == 0 then
        table.sort(job.groupOrder, function(a, b)
            return lower(job.groups[a].name) < lower(job.groups[b].name)
        end)
        for _, instances in pairs(job.instances) do
            table.sort(instances, function(a, b)
                if a.category == "perishable" and b.category == "perishable" and a.spoilageRemaining ~= b.spoilageRemaining then
                    return a.spoilageRemaining < b.spoilageRemaining
                end
                if a.conditionRatio ~= b.conditionRatio then return a.conditionRatio > b.conditionRatio end
                if a.usedDelta ~= b.usedDelta then return a.usedDelta > b.usedDelta end
                return tostring(a.id) < tostring(b.id)
            end)
        end
        job.done = true
        job.finishedAtMs = Storage.nowMs()
    end
    return job.done
end

function Storage.buildSnapshot(job, network)
    local groups = {}
    for i = 1, #(job and job.groupOrder or {}) do
        local group = job.groups[job.groupOrder[i]]
        local copy = {}
        for key, value in pairs(group) do copy[key] = value end
        local states, tags, sources, sourceNames = {}, {}, {}, {}
        for key in pairs(group.states or {}) do states[#states + 1] = key end
        for key in pairs(group.tags or {}) do tags[#tags + 1] = key end
        for key in pairs(group.sources or {}) do sources[#sources + 1] = key end
        for key in pairs(group.sourceNames or {}) do sourceNames[#sourceNames + 1] = key end
        table.sort(states); table.sort(tags); table.sort(sources); table.sort(sourceNames)
        copy.states, copy.tags, copy.sources = states, tags, sources
        copy.sourceNames = sourceNames
        groups[#groups + 1] = copy
    end
    return {
        kind = "storageSnapshot",
        networkId = network and network.networkId or nil,
        revision = network and integer(network.revision, 0) or 0,
        snapshotId = Storage.newId("snapshot", network and network.networkId or ""),
        groups = groups,
        containers = job and job.links or {},
        itemCount = job and job.indexed or 0,
        groupCount = #groups,
        onlineLinks = job and job.onlineLinks or 0,
        offlineLinks = job and job.offlineLinks or 0,
        totalCapacity = job and job.totalCapacity or 0,
        usedCapacity = job and job.usedCapacity or 0,
        incomplete = job and job.incomplete == true,
        indexedAtMs = Storage.nowMs(),
    }
end

function Storage.copyInstanceDetails(job, groupKey)
    local result = {}
    for i = 1, #((job and job.instances and job.instances[tostring(groupKey or "")]) or {}) do
        local source = job.instances[tostring(groupKey or "")][i]
        local row = {}
        for key, value in pairs(source) do row[key] = value end
        result[#result + 1] = row
    end
    return result
end

function Storage.findNetworkItems(network, expectedIds)
    local wanted, remaining = {}, 0
    for key, value in pairs(type(expectedIds) == "table" and expectedIds or {}) do
        local id = type(key) == "number" and tostring(value or "") or tostring(key or "")
        if id ~= "" and not wanted[id] then wanted[id] = true; remaining = remaining + 1 end
    end
    local found = {}
    if remaining == 0 then return found end
    local seenContainers = {}
    local scanned = 0
    local function visit(container, link, depth)
        if not container or seenContainers[container] or depth > Storage.MaxDepth
            or remaining <= 0 or scanned >= Storage.MaxIndexedItems then return end
        seenContainers[container] = true
        local items = safeCall(container, "getItems", nil)
        local size = integer(safeCall(items, "size", 0), 0)
        for i = 0, size - 1 do
            if remaining <= 0 or scanned >= Storage.MaxIndexedItems then break end
            local item = safeCall(items, "get", nil, i)
            scanned = scanned + 1
            local id = Storage.itemId(item)
            if id and wanted[id] and not found[id] and not Storage.isProtected(item) then
                found[id] = { item = item, source = container, link = link }
                remaining = remaining - 1
            end
            visit(item and safeCall(item, "getInventory", nil) or nil, link, depth + 1)
        end
    end
    local ordered = {}
    for _, link in pairs((network and network.links) or {}) do ordered[#ordered + 1] = link end
    table.sort(ordered, function(a, b) return tostring(a.linkId) < tostring(b.linkId) end)
    for i = 1, #ordered do
        local link = ordered[i]
        local _, container = Storage.resolveLink(link)
        if container and Storage.isWithinNetworkRange(network, { x = link.x, y = link.y, z = link.z }) then
            visit(container, link, 0)
        end
        if remaining <= 0 or scanned >= Storage.MaxIndexedItems then break end
    end
    return found
end

return Storage
