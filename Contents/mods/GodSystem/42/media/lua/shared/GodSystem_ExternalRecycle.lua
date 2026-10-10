-- Transaction-local external source adapter. No source reference survives a request.
GodSystemExternalRecycle = GodSystemExternalRecycle or {}
local E = GodSystemExternalRecycle

local Bridge = GodSystemB42JavaCalls or require "GodSystem_B42JavaCalls"

local function call(object, method, fallback, ...)
    local ok, value = Bridge.try(object, method, ...)
    if ok and value ~= nil then return value end
    return fallback
end

local function itemId(item)
    local value = call(item, "getID", nil)
    if value == nil then return nil end
    return tostring(value)
end

local function squareOf(object)
    return call(object, "getSquare", nil)
end

local function coordinates(square)
    if not square then return nil end
    local ok, x, y, z = pcall(function() return square:getX(), square:getY(), square:getZ() end)
    if not ok or not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function sourceOf(item)
    local container = call(item, "getContainer", nil)
    local directWorldObject = call(item, "getWorldItem", nil)
    if not container and not directWorldObject then return nil end
    local path = {}
    local rootItem
    for _ = 1, 16 do
        local containing = call(container, "getContainingItem", nil)
        if not containing then break end
        rootItem = containing
        table.insert(path, 1, itemId(containing) or "")
        container = call(containing, "getContainer", nil)
        if not container then break end
    end
    if container and call(container, "getContainingItem", nil) then return nil end
    local kind, parent, square, anchor, partId, vehicleId
    local parentItem = call(container, "getContainingItem", nil)
    if parentItem then return nil end
    if not container or call(container, "getType", "") == "floor" then
        local worldObject = call(rootItem or item, "getWorldItem", nil)
        if not worldObject then return nil end
        kind, square = rootItem and "worldBag" or "worldItem", squareOf(worldObject)
        anchor = itemId(rootItem or item)
    else
        parent = call(container, "getParent", nil)
        square = call(container, "getSourceGrid", nil) or squareOf(parent)
        if parent and instanceof and instanceof(parent, "BaseVehicle") then
            kind, vehicleId = "vehicle", tostring(call(parent, "getId", ""))
            local part = call(parent, "getPartById", nil, call(container, "getType", ""))
            if part and call(part, "getItemContainer", nil) == container then
                partId = tostring(call(part, "getId", ""))
            end
            if not partId or partId == "" then return nil end
            anchor = vehicleId
        elseif parent and instanceof and instanceof(parent, "IsoDeadBody") then
            kind, anchor = "corpse", tostring(call(parent, "getStaticMovingObjectIndex", -1))
        elseif parent and call(parent, "getObjectIndex", -1) >= 0 then
            kind, anchor = "worldContainer", tostring(call(parent, "getObjectIndex", -1))
        end
    end
    local coord = coordinates(square)
    if not kind or not coord or not anchor or anchor == "" or anchor == "-1" then return nil end
    local containerIndex = -1
    if kind == "worldContainer" and parent then
        local count = tonumber(call(parent, "getContainerCount", 0)) or 0
        for index = 0, math.min(count, 64) - 1 do
            if call(parent, "getContainerByIndex", nil, index) == container then containerIndex = index; break end
        end
        if containerIndex < 0 then return nil end
    end
    coord.kind, coord.itemId, coord.anchor = kind, itemId(item), anchor
    coord.containerType = (kind == "worldItem" or kind == "worldBag")
        and "floor" or tostring(call(container, "getType", ""))
    coord.containerIndex = containerIndex
    coord.path = table.concat(path, "/")
    coord.partId = partId or ""
    return coord.itemId and coord or nil, container, parent
end

function E.describe(item)
    local ok, descriptor = pcall(sourceOf, item)
    if ok then return descriptor end
    return nil
end

local function inWorld(square, worldObject)
    if not square then return nil end
    local ok, objects = Bridge.try(square, "getWorldObjects")
    if not ok or not objects then return nil end
    if not worldObject then return false end
    local read, present = Bridge.try(objects, "contains", worldObject)
    if not read or type(present) ~= "boolean" then return nil end
    return present
end

local function sameSource(left, right)
    for _, key in ipairs({ "kind", "itemId", "anchor", "containerType", "containerIndex", "path", "partId", "x", "y", "z" }) do
        if tostring(left[key] or "") ~= tostring(right[key] or "") then return false end
    end
    return true
end
E.sameSource = sameSource

function E.canFallbackSources(sources)
    if type(sources) ~= "table" or #sources == 0 then return false end
    for i = 1, #sources do
        if type(sources[i]) ~= "table" or sources[i].kind ~= "worldItem" then return false end
    end
    return true
end

local function indexContainer(container, result, visited, state, depth)
    if not container or visited[container] or depth > 16 or state.count > 20000 then return end
    visited[container] = true
    local items = call(container, "getItems", nil)
    if not items then state.failure = "nativeReadFailed"; return end
    for index = 0, items:size() - 1 do
        state.count = state.count + 1
        if state.count > 20000 then return end
        local item = items:get(index)
        local id = itemId(item)
        if id then
            if result[id] ~= nil then result[id] = false else result[id] = { item = item, container = container } end
        end
        indexContainer(call(item, "getInventory", nil), result, visited, state, depth + 1)
    end
end

-- The cache belongs to one synchronous transaction, never to a player/session.
local function locateRoot(square, descriptor, player, cache)
    local kind, anchor = descriptor.kind, tostring(descriptor.anchor or "")
    if kind == "worldItem" or kind == "worldBag" then
        cache.world = cache.world or {}
        local indexed = cache.world[square]
        if not indexed then
            local objects = call(square, "getWorldObjects", nil)
            if not objects then return nil, nil, nil, nil, "nativeReadFailed" end
            indexed = {}
            for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                local rootItem = call(object, "getItem", nil)
                local id = itemId(rootItem)
                if id and call(rootItem, "getWorldItem", nil) == object then
                    if indexed[id] ~= nil then indexed[id] = false
                    else indexed[id] = { item = rootItem, object = object } end
                end
            end
            cache.world[square] = indexed
        end
        local match = indexed[anchor]
        if match and call(match.item, "getWorldItem", nil) == match.object
            and squareOf(match.object) == square then
            if kind == "worldItem" then return nil, match.item, match.object end
            return call(match.item, "getInventory", nil), nil, match.object
        end
    elseif kind == "worldContainer" then
        local objects = call(square, "getObjects", nil)
        local index = tonumber(anchor)
        if not objects or not index or index < 0 or index >= objects:size() then return nil end
        local object = objects:get(index)
        if tonumber(call(object, "getObjectIndex", -1)) ~= index then return nil end
        return call(object, "getContainerByIndex", nil, tonumber(descriptor.containerIndex)), nil, object
    elseif kind == "corpse" then
        local objects = call(square, "getStaticMovingObjects", nil)
        local index = tonumber(anchor)
        if not objects or not index or index < 0 or index >= objects:size() then return nil end
        local object = objects:get(index)
        if not instanceof or not instanceof(object, "IsoDeadBody")
            or tonumber(call(object, "getStaticMovingObjectIndex", -1)) ~= index then return nil end
        return call(object, "getContainer", nil), nil, object
    elseif kind == "vehicle" then
        local vehicleId = tonumber(anchor)
        if not vehicleId or vehicleId ~= math.floor(vehicleId) then return nil end
        local vehicle = getVehicleById and getVehicleById(vehicleId) or nil
        if not vehicle then
            local nearby = call(square, "getVehicleContainer", nil)
            if nearby and tostring(call(nearby, "getId", "")) == anchor then vehicle = nearby end
        end
        if not vehicle or tostring(call(vehicle, "getId", "")) ~= anchor then return nil end
        local part = call(vehicle, "getPartById", nil, descriptor.partId)
        local partIndex = -1
        for index = 0, math.min(tonumber(call(vehicle, "getPartCount", 0)) or 0, 128) - 1 do
            if call(vehicle, "getPartByIndex", nil, index) == part then partIndex = index; break end
        end
        if partIndex < 0 then return nil end
        local access = call(vehicle, "canAccessContainer", nil, partIndex, player)
        if access == nil then return nil, nil, nil, nil, "nativeReadFailed" end
        if access ~= true then return nil, nil, nil, nil, "locked" end
        return call(part, "getItemContainer", nil), nil, vehicle, part
    end
    return nil
end

local function resolve(player, descriptor, cache)
    cache = cache or {}
    if type(descriptor) ~= "table" then return nil, "unsupported" end
    if descriptor.kind ~= "worldItem" and descriptor.kind ~= "worldBag"
        and descriptor.kind ~= "worldContainer" and descriptor.kind ~= "corpse"
        and descriptor.kind ~= "vehicle" then return nil, "unsupported" end
    local x, y, z = tonumber(descriptor.x), tonumber(descriptor.y), tonumber(descriptor.z)
    if not x or not y or not z or x ~= math.floor(x) or y ~= math.floor(y) or z ~= math.floor(z)
        or math.abs(x) > 300000 or math.abs(y) > 300000 or z < -10 or z > 32 then return nil, "coordinates" end
    local id, anchor = tostring(descriptor.itemId or ""), tostring(descriptor.anchor or "")
    if id == "" or #id > 64 or anchor == "" or #anchor > 64 or not player then return nil, "identity" end
    local okPosition, px, py, pz = pcall(function() return player:getX(), player:getY(), player:getZ() end)
    if not okPosition or type(px) ~= "number" or type(py) ~= "number" or type(pz) ~= "number" then return nil, "nativeReadFailed" end
    if math.floor(pz) ~= z or math.abs(math.floor(px) - x) > 1
        or math.abs(math.floor(py) - y) > 1 then return nil, "distance" end
    if not getCell then return nil, "unloaded" end
    local okSquare, square = pcall(function() return getCell():getGridSquare(x, y, z) end)
    if not okSquare then return nil, "nativeReadFailed" end
    if not square then return nil, "unloaded" end
    local okReach, blocked = pcall(function()
        local current = player:getCurrentSquare()
        return not current or (current ~= square and current:isBlockedTo(square))
    end)
    if not okReach then return nil, "nativeReadFailed" end
    if blocked then return nil, "blocked" end
    if isServer and isServer() and (not SafeHouse or not SafeHouse.isSafeHouse) then return nil, "nativeReadFailed" end
    if SafeHouse and SafeHouse.isSafeHouse then
        local okAccess, denied = pcall(function()
            return SafeHouse.isSafeHouse(square, player:getUsername(), true)
        end)
        if not okAccess then return nil, "nativeReadFailed" end
        if denied then return nil, "protected" end
    end
    local root, worldItem, object, part, rootFailure = locateRoot(square, descriptor, player, cache)
    if rootFailure then return nil, rootFailure end
    local found
    if descriptor.kind == "worldItem" then
        -- A loose world item is owned by its world object. The loot UI may give
        -- it a transient "floor" container, which need not contain the item on
        -- the authority side. Vanilla ISGrabItemAction uses the world object.
        found = worldItem and { item = worldItem } or nil
    elseif root then
        cache = cache or {}
        local cacheKey = table.concat({ descriptor.kind, anchor, tostring(descriptor.containerIndex or ""),
            tostring(descriptor.partId or ""), tostring(x), tostring(y), tostring(z) }, ":")
        local indexed = cache[cacheKey]
        if not indexed then
            indexed = {}
            local state = { count = 0 }
            indexContainer(root, indexed, {}, state, 0)
            if state.failure then return nil, state.failure end
            cache[cacheKey] = indexed
        end
        found = indexed[id]
    end
    local item, container = found and found.item, found and found.container
    local validContainer = descriptor.kind == "worldItem" and object ~= nil
    if item and container then
        local present = call(container, "contains", nil, item)
        local exists = call(container, "isExistYet", nil)
        local allowed = call(container, "isRemoveItemAllowed", nil, item)
        if present == nil or exists == nil or allowed == nil then return nil, "nativeReadFailed" end
        if present ~= true or exists ~= true then return nil, "changed" end
        if allowed ~= true then return nil, "removeDenied" end
        validContainer = true
    end
    if item and validContainer then
        local actual = E.describe(item)
        if actual and sameSource(actual, descriptor) then
            if object and instanceof and instanceof(object, "IsoThumpable") then
                local locked = call(object, "isLockedToCharacter", nil, player)
                if locked == nil then return nil, "nativeReadFailed" end
                if locked ~= false then return nil, "locked" end
                local padlock = call(object, "isLockedByPadlock", nil)
                if padlock == nil then return nil, "nativeReadFailed" end
                if padlock then
                    local inventory = call(player, "getInventory", nil)
                    local keyId = call(object, "getKeyId", nil)
                    if not inventory or keyId == nil then return nil, "nativeReadFailed" end
                    local keyRead, key = Bridge.try(inventory, "haveThisKeyId", keyId)
                    if not keyRead then return nil, "nativeReadFailed" end
                    if not key then return nil, "locked" end
                end
            end
            return { item = item, worldObject = descriptor.kind == "worldItem" and object or nil,
                square = square, container = container, kind = descriptor.kind, vehiclePart = part,
                player = player, descriptor = descriptor, cache = cache }
        end
    end
    return nil, "changed"
end

function E.resolve(player, descriptor, cache)
    local ok, row, reason = pcall(resolve, player, descriptor, cache)
    if ok then return row, reason end
    return nil, "nativeReadFailed"
end

-- The batch is request-local. Native void calls succeed when pcall succeeds.
function E.newBatch()
    return { containers = {}, order = {}, vehicles = {}, dirty = {} }
end

function E.queueRemoved(batch, container, item, part)
    if container then
        local rows = batch.containers[container]
        if not rows then rows = {}; batch.containers[container] = rows; batch.order[#batch.order + 1] = container end
        rows[#rows + 1] = item
        batch.dirty[container] = true
    end
    if part then
        local vehicleContainer = call(part, "getItemContainer", nil)
        if not vehicleContainer then batch.invalid = true else batch.vehicles[part] = vehicleContainer end
    end
end

function E.flushUpdates(batch)
    local ok = batch.invalid ~= true
    for container in pairs(batch.dirty) do
        -- Dirty is optional for native containers which do not expose a UI flag.
        local read, fn = pcall(function() return container.setDrawDirty end)
        if read and fn then ok = pcall(function() container:setDrawDirty(true) end) and ok end
    end
    for part, container in pairs(batch.vehicles) do
        ok = pcall(function() part:setContainerContentAmount(container:getCapacityWeight()) end) and ok
    end
    return ok
end

function E.flushBatch(batch)
    local ok, err = pcall(function()
        if isServer and isServer() then
            for _, container in ipairs(batch.order) do
                local rows = batch.containers[container]
                for first = 1, #rows, 200 do
                    if ArrayList and ArrayList.new and sendRemoveItemsFromContainer then
                        local nativeItems = ArrayList.new()
                        for i = first, math.min(first + 199, #rows) do nativeItems:add(rows[i]) end
                        sendRemoveItemsFromContainer(container, nativeItems)
                    elseif sendRemoveItemFromContainer then
                        for i = first, math.min(first + 199, #rows) do sendRemoveItemFromContainer(container, rows[i]) end
                    else
                        error("native container synchronization unavailable")
                    end
                end
            end
        end
    end)
    if not ok then return false, "syncFailed", err end
    if not E.flushUpdates(batch) then return false, "syncFailed" end
    return true
end

function E.remove(row, batch)
    if not row or not row.item or (not row.container and row.kind ~= "worldItem") then return false end
    if row.player then
        local current, reason = E.resolve(row.player, row.descriptor, row.cache)
        if not current or current.item ~= row.item or current.container ~= row.container then return false, reason or "changed" end
    end
    if row.kind == "worldItem" then
        local present = inWorld(row.square, row.worldObject)
        if present ~= true then return false, present == nil and "nativeReadFailed" or "changed" end
    end
    if row.container and call(row.container, "contains", false, row.item) ~= true then return false end
    local step, transmitResult, readError = "containerRemove", nil, nil
    local expectedId = row.descriptor and tostring(row.descriptor.itemId) or itemId(row.item)
    local serverWorld = row.kind == "worldItem" and isServer and isServer() == true
    local worldState, finishWorldLinks
    if row.kind == "worldItem" then
        worldState = function()
            local state = {}
            local function readMember(name, target, method, ...)
                local read, value = Bridge.try(target, method, ...)
                if not read then state.error = state.error or (name .. ": " .. tostring(value or "native method unavailable")) end
                return read, value
            end
            local read, objects = readMember("worldList", row.square, "getWorldObjects")
            if read and objects then
                local presentOk, present = readMember("worldContains", objects, "contains", row.worldObject)
                if presentOk and type(present) == "boolean" then state.world = present end
            end
            read, objects = readMember("squareList", row.square, "getObjects")
            if read and objects then
                local presentOk, present = readMember("squareContains", objects, "contains", row.worldObject)
                if presentOk and type(present) == "boolean" then state.square = present end
            end
            state.itemRead, state.itemWorld = readMember("itemWorld", row.item, "getWorldItem")
            state.objectRead, state.objectSquare = readMember("objectSquare", row.worldObject, "getSquare")
            local idRead, id = readMember("itemId", row.item, "getID")
            local objectItemRead, objectItem = readMember("objectItem", row.worldObject, "getItem")
            state.identity = idRead and id ~= nil and expectedId ~= nil and tostring(id) == expectedId
                and objectItemRead and objectItem == row.item
            if state.world == nil or state.square == nil then
                state.error = state.error or "native membership result unavailable"
            end
            readError = readError or state.error
            state.absent = state.world == false and state.square == false
            state.complete = state.absent and state.identity and state.itemRead and state.itemWorld == nil
                and state.objectRead and state.objectSquare == nil
            return state
        end
        finishWorldLinks = function(state)
            -- Only clear references to this exact, already removed object. Never
            -- detach an item moved to another world object by an event handler.
            if not state.absent or not state.identity or not state.itemRead or not state.objectRead
                or (state.itemWorld ~= nil and state.itemWorld ~= row.worldObject)
                or (state.objectSquare ~= nil and state.objectSquare ~= row.square) then return false end
            if state.objectSquare ~= nil then
                step = "clearObjectSquare"
                row.worldObject:setSquare(nil)
            end
            if state.itemWorld ~= nil then
                step = "clearItemWorld"
                row.item:setWorldItem(nil)
            end
            return true
        end
    end
    local ok, err = pcall(function()
        if row.container then
            row.container:DoRemoveItem(row.item)
            if not batch and isServer and isServer() and sendRemoveItemFromContainer then
                step = "containerSync"
                sendRemoveItemFromContainer(row.container, row.item)
            end
        end
        if row.kind == "worldItem" then
            step = "worldTransmit"
            transmitResult = row.square:transmitRemoveItemFromSquare(row.worldObject)
            if serverWorld and (type(transmitResult) ~= "number" or transmitResult < 0) then return end
            -- B42.21's native transmit removes the object itself in SP/server.
            -- Avoid calling its removal lifecycle twice when both lists agree.
            step = "afterTransmit"
            local state = worldState()
            if state.world == true or state.square == true then
                step = "removeFromWorld"
                row.worldObject:removeFromWorld()
                step = "removeFromSquare"
                row.worldObject:removeFromSquare()
                state = worldState()
            end
            finishWorldLinks(state)
        end
        if not batch and row.vehiclePart and call(row.vehiclePart, "getItemContainer", nil) == row.container then
            step = "vehicleWeight"
            row.vehiclePart:setContainerContentAmount(row.container:getCapacityWeight())
        end
    end)
    local failedStep = not ok and step or nil
    local state, detail
    if row.kind == "worldItem" then
        state = worldState()
        if not state.complete then
            -- One bounded recheck covers a transient verification failure or a
            -- post-removal exception. It never retries destructive removal.
            local priorError = state.error
            local completed, completeError = pcall(function() finishWorldLinks(state) end)
            if not completed then
                failedStep = failedStep or step
                err = err or completeError
            end
            state = worldState()
            if priorError then err = err or priorError end
        end
        err = err or readError
        if not ok or err or not state.complete then
            local function membership(value)
                if value == nil then return "unknown" end
                return value and "present" or "absent"
            end
            detail = { source = row.kind, itemType = call(row.item, "getFullType", "-"),
                step = failedStep or "worldVerify", error = err or state.error,
                transmit = transmitResult, world = membership(state.world), square = membership(state.square),
                itemLink = state.itemRead and (state.itemWorld == nil and "clear" or "linked") or "unknown",
                objectSquare = state.objectRead and (state.objectSquare == nil and "clear" or "linked") or "unknown",
                mutation = state.complete and "complete" or "unverified" }
        end
    end
    local containerOk, contains = true, false
    if row.container then containerOk, contains = pcall(function() return row.container:contains(row.item) end) end
    local removed = containerOk and contains == false
        and (row.kind == "worldItem" and state.complete or row.kind ~= "worldItem" and ok)
    if serverWorld and (type(transmitResult) ~= "number" or transmitResult < 0) then
        removed = false -- Local absence cannot prove that a failed server remove was synchronized.
        detail = detail or { source = row.kind, itemType = call(row.item, "getFullType", "-"), step = "worldTransmit" }
        detail.step = failedStep or "worldTransmit"
        detail.mutation = "unverified"
        detail.error = detail.error or "server native remove/sync was not confirmed"
    end
    if not removed and not detail then
        detail = { source = row.kind, itemType = call(row.item, "getFullType", "-"),
            step = failedStep or "containerVerify", error = err or (not containerOk and contains or nil),
            mutation = "unverified" }
    end
    if removed and batch then E.queueRemoved(batch, row.container, row.item, row.vehiclePart) end
    if removed and row.cache and row.cache.world and row.cache.world[row.square] then
        row.cache.world[row.square][itemId(row.item)] = nil
    end
    if removed then return true, nil, detail end
    return false, "deleteFailed", detail
end

function E.restore(row, batch)
    if not row or not row.square or not row.item or (not row.container and row.kind ~= "worldItem") then return false end
    if row.kind == "worldItem" then
        -- An object-removal callback can move the same item elsewhere. Do not
        -- create a second world object or detach it from its new owner.
        local read, container = Bridge.try(row.item, "getContainer")
        if not read then return false end
        if container then
            local typeRead, containerType = Bridge.try(container, "getType")
            if not typeRead or containerType ~= "floor" then return false end
        end
        local worldRead, object = Bridge.try(row.item, "getWorldItem")
        local idRead, id = Bridge.try(row.item, "getID")
        if not worldRead or not idRead or id == nil or (row.descriptor and tostring(id) ~= tostring(row.descriptor.itemId)) then return false end
        object = object or row.worldObject
        if not object then return false end
        local squareRead, square = Bridge.try(object, "getSquare")
        local itemRead, item = Bridge.try(object, "getItem")
        if not squareRead or (square ~= nil and square ~= row.square) or not itemRead or item ~= row.item then return false end
        local present = inWorld(row.square, object)
        local objectsRead, objects = Bridge.try(row.square, "getObjects")
        if not objectsRead or not objects then return false end
        local memberRead, member = Bridge.try(objects, "contains", object)
        if present == nil or not memberRead or type(member) ~= "boolean" or present ~= member then return false end
    end
    local ok = pcall(function()
        if row.container and not row.container:contains(row.item) then
            if row.kind == "worldItem" then row.container:DoAddItemBlind(row.item)
            else row.container:AddItem(row.item) end
            if isServer and isServer() and sendAddItemToContainer then
                sendAddItemToContainer(row.container, row.item)
            end
        end
        if row.kind == "worldItem" then
            local present = inWorld(row.square, row.item:getWorldItem())
            if present == nil then error("native world membership unavailable") end
            if not present then
                local restored = row.square:AddWorldInventoryItem(row.item, 0.5, 0.5, 0)
                if not restored then return end
            end
            -- A remove packet may have reached clients before a later step failed.
            if isServer and isServer() and row.item:getWorldItem() then
                row.item:getWorldItem():transmitCompleteItemToClients()
            end
        end
        if batch then
            if row.container then batch.dirty[row.container] = true end
            if row.vehiclePart then batch.vehicles[row.vehiclePart] = call(row.vehiclePart, "getItemContainer", nil) end
        elseif row.vehiclePart and call(row.vehiclePart, "getItemContainer", nil) == row.container then
            row.vehiclePart:setContainerContentAmount(row.container:getCapacityWeight())
        end
    end)
    if row.cache then
        -- Restore can replace native object identities. Discard request indices.
        for key in pairs(row.cache) do row.cache[key] = nil end
    end
    local verified, result = pcall(function()
        local described = ok and E.describe(row.item) or nil
        return described ~= nil and described.itemId == itemId(row.item)
            and described.x == row.square:getX() and described.y == row.square:getY() and described.z == row.square:getZ()
            and (row.kind ~= "worldItem" or inWorld(row.square, row.item:getWorldItem()) == true)
            and (not row.container or row.container:contains(row.item))
    end)
    return verified and result == true
end

return E
