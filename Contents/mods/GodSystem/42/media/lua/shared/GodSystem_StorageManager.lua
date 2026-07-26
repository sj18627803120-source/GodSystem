require "GodSystem_Storage"

GodSystemStorageManager = GodSystemStorageManager or {}

local Manager = GodSystemStorageManager
local Storage = GodSystemStorage

Manager.runtime = Manager.runtime or {
    jobs = {},
    latestJobs = {},
    snapshotJobs = {},
    listeners = {},
}
Manager.runtime.jobs = Manager.runtime.jobs or {}
Manager.runtime.latestJobs = Manager.runtime.latestJobs or {}
Manager.runtime.snapshotJobs = Manager.runtime.snapshotJobs or {}

local function safeCall(object, methodName, fallback, ...)
    return Storage.safeCall(object, methodName, fallback, ...)
end

local function transmitStore()
    if ModData and ModData.transmit then pcall(ModData.transmit, Storage.StoreKey) end
end

function Manager.save(network)
    if type(network) == "table" then network.updatedAtMs = Storage.nowMs() end
    transmitStore()
end

function Manager.getStore()
    local store
    if ModData and ModData.getOrCreate then
        store = ModData.getOrCreate(Storage.StoreKey)
    else
        Manager.fallbackStore = Manager.fallbackStore or {}
        store = Manager.fallbackStore
    end
    store.schemaVersion = Storage.SchemaVersion
    store.networks = type(store.networks) == "table" and store.networks or {}
    store.scopeIndex = type(store.scopeIndex) == "table" and store.scopeIndex or {}
    store.operations = type(store.operations) == "table" and store.operations or {}
    return store
end

function Manager.scopeForPosition(player, position)
    local safehouse = Storage.getSafehouseAt(position.x, position.y)
    if safehouse and (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
        local key = Storage.safehouseKey(safehouse)
        if key then return "safehouse", key, safehouse end
    end
    local owner = Storage.playerKey(player)
    return "personal", "personal:" .. owner, nil
end

function Manager.getNetwork(networkId)
    return Manager.getStore().networks[tostring(networkId or "")]
end

function Manager.getNetworkByScope(scopeKey)
    local store = Manager.getStore()
    local networkId = store.scopeIndex[tostring(scopeKey or "")]
    return networkId and store.networks[networkId] or nil
end

function Manager.createNetwork(player, scope, scopeKey)
    local store = Manager.getStore()
    local owner = Storage.playerKey(player)
    local networkId = Storage.newId("network", scopeKey .. ":" .. owner)
    local network = {
        schemaVersion = Storage.SchemaVersion,
        networkId = networkId,
        scope = scope,
        scopeKey = scopeKey,
        safehouse = scope == "safehouse" and scopeKey or nil,
        owner = owner,
        creator = owner,
        controllerToken = "",
        controller = nil,
        radius = Storage.DefaultRadius,
        maxLinks = Storage.DefaultMaxLinks,
        links = {},
        revision = 1,
        createdAtMs = Storage.nowMs(),
        updatedAtMs = Storage.nowMs(),
    }
    store.networks[networkId] = network
    store.scopeIndex[scopeKey] = networkId
    transmitStore()
    return network
end

function Manager.getOrCreateNetwork(player)
    local position = Storage.positionOfPlayer(player)
    if not position then return nil, "playerMissing" end
    local scope, scopeKey = Manager.scopeForPosition(player, position)
    local network = Manager.getNetworkByScope(scopeKey)
    local created = false
    if not network then network = Manager.createNetwork(player, scope, scopeKey); created = true end
    return network, nil, created
end

function Manager.canUse(player, network)
    if not player or type(network) ~= "table" then return false end
    if Storage.isAdmin(player) then return true end
    if network.scope == "personal" then return Storage.playerKey(player) == tostring(network.owner or "") end
    if network.scope == "safehouse" then
        local controller = network.controller or {}
        local safehouse = Storage.getSafehouseAt(controller.x or 0, controller.y or 0)
        if Storage.safehouseKey(safehouse) == tostring(network.safehouse or "") then
            return Storage.playerAllowedSafehouse(player, safehouse)
        end
        return Storage.playerKey(player) == tostring(network.creator or "")
    end
    return false
end

function Manager.canManage(player, network)
    if Storage.isAdmin(player) then return true end
    if not Manager.canUse(player, network) then return false end
    if network.scope == "personal" then return Storage.playerKey(player) == tostring(network.owner or "") end
    local controller = network.controller or {}
    local safehouse = Storage.getSafehouseAt(controller.x or 0, controller.y or 0)
    local username = Storage.playerKey(player)
    if Storage.safehouseKey(safehouse) ~= tostring(network.safehouse or "") then
        return username == tostring(network.creator or "")
    end
    return safeCall(safehouse, "isOwner", false, player) == true
        or tostring(safeCall(safehouse, "getOwner", "") or "") == username
        or username == tostring(network.creator or "")
end

local function inventoryAddController(player, network, token)
    local inventory = safeCall(player, "getInventory", nil)
    if not inventory then return nil, "inventoryMissing" end
    local item
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, created = pcall(InventoryItemFactory.CreateItem, Storage.ControllerFullType)
        if ok then item = created end
    end
    if item then
        local ok = pcall(function() inventory:AddItem(item) end)
        if not ok or not Storage.containerContains(inventory, item) then item = nil end
    end
    if not item then
        item = safeCall(inventory, "AddItem", nil, Storage.ControllerFullType)
    end
    if not item then return nil, "createFailed" end
    if not Storage.setControllerIdentity(item, network.networkId, token) then
        pcall(function() inventory:Remove(item) end)
        return nil, "identityFailed"
    end
    Storage.syncAdd(inventory, item)
    return item, nil
end

local function removeInventoryItem(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:Remove(item) end)
    if not ok or Storage.containerContains(container, item) then return false end
    Storage.syncRemove(container, item)
    return true
end

local function collectControllerItems(player)
    local root = safeCall(player, "getInventory", nil)
    local result, seenContainers = {}, {}
    local function visit(container, depth)
        if not container or seenContainers[container] or depth > Storage.MaxDepth then return end
        seenContainers[container] = true
        local items = safeCall(container, "getItems", nil)
        local size = Storage.integer(safeCall(items, "size", 0), 0)
        for i = 0, size - 1 do
            local item = safeCall(items, "get", nil, i)
            if Storage.isController(item) then
                result[#result + 1] = { item = item, container = container }
            end
            visit(safeCall(item, "getInventory", nil), depth + 1)
        end
    end
    visit(root, 0)
    return result
end

local function findInventoryController(player, networkId, token)
    local rows = collectControllerItems(player)
    for i = 1, #rows do
        local itemNetworkId, itemToken = Storage.getControllerIdentity(rows[i].item)
        if tostring(itemNetworkId or "") == tostring(networkId or "")
            and tostring(itemToken or "") == tostring(token or "") then
            return rows[i].item, rows[i].container
        end
    end
    return nil, nil
end

local function cleanupInventoryControllers(player, networkId, keepItem)
    local removed = 0
    local rows = collectControllerItems(player)
    for i = 1, #rows do
        local itemNetworkId = Storage.getControllerIdentity(rows[i].item)
        if rows[i].item ~= keepItem and tostring(itemNetworkId or "") == tostring(networkId or "")
            and removeInventoryItem(rows[i].container, rows[i].item) then
            removed = removed + 1
        end
    end
    return removed
end

local function removeWorldController(object)
    local square = safeCall(object, "getSquare", nil)
    if not square or not object then return false end
    if square.transmitRemoveItemFromSquare then
        local ok = pcall(function() square:transmitRemoveItemFromSquare(object) end)
        if not ok then return false end
    else
        if object.removeFromWorld then pcall(function() object:removeFromWorld() end) end
        if object.removeFromSquare then pcall(function() object:removeFromSquare() end) end
    end
    return Storage.integer(safeCall(object, "getObjectIndex", -1), -1) < 0
end

local function normalizeControllerFields(network)
    local changed = false
    local token = tostring(network.controllerToken or "")
    if network.controllerClaimedOnce == nil then
        network.controllerClaimedOnce = token ~= ""
        changed = true
    end
    if token == "" and tostring(network.controllerState or "") ~= "unclaimed" then
        network.controllerState = "unclaimed"
        network.controllerItemId = nil
        changed = true
    elseif token ~= "" and tostring(network.controllerState or "") == "" then
        network.controllerState = "missing"
        changed = true
    end
    return changed
end

local function setControllerState(network, state, itemId, controller)
    local changed = tostring(network.controllerState or "") ~= tostring(state or "")
        or tostring(network.controllerItemId or "") ~= tostring(itemId or "")
        or network.controller ~= controller
    network.controllerState = tostring(state or "missing")
    network.controllerItemId = itemId and tostring(itemId) or nil
    network.controller = controller
    if changed then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
    end
    return changed
end

function Manager.controllerStatus(player)
    local position = Storage.positionOfPlayer(player)
    if not position then return nil, "playerMissing" end
    local _, scopeKey = Manager.scopeForPosition(player, position)
    local network = Manager.getNetworkByScope(scopeKey)
    if not network then
        return {
            state = "unclaimed",
            claimedOnce = false,
            recoveryCost = Storage.ControllerRecoveryCost,
            nextCost = 0,
            canClaim = true,
        }
    end
    if not Manager.canUse(player, network) then return nil, "notAllowed" end

    local changed = normalizeControllerFields(network)
    local token = tostring(network.controllerToken or "")
    local state = tostring(network.controllerState or "missing")
    local itemId = network.controllerItemId
    local controller = network.controller
    if token ~= "" then
        local item = findInventoryController(player, network.networkId, token)
        if item then
            itemId = Storage.itemId(item)
            controller = nil
            state = "kit"
        elseif type(controller) == "table" then
            local square = Storage.getSquare(controller.x, controller.y, controller.z)
            local object, worldItem = Storage.findWorldController(
                controller.x, controller.y, controller.z,
                controller.itemId, token, controller.objectId
            )
            if object and worldItem then
                state = Storage.isInstalledController(object) and "installed" or "legacyGround"
                itemId = Storage.itemId(worldItem)
            elseif square then
                state = "missing"
                controller = nil
                itemId = nil
            elseif state ~= "installed" then
                state = "missing"
                controller = nil
                itemId = nil
            end
        else
            state = "missing"
            itemId = nil
        end
    else
        state = "unclaimed"
        itemId = nil
        controller = nil
    end
    if setControllerState(network, state, itemId, controller) then changed = true end
    if changed then transmitStore() end

    local claimedOnce = network.controllerClaimedOnce == true
    return {
        networkId = network.networkId,
        state = state,
        claimedOnce = claimedOnce,
        recoveryCost = Storage.ControllerRecoveryCost,
        nextCost = claimedOnce and Storage.ControllerRecoveryCost or 0,
        canClaim = state == "unclaimed" or state == "missing",
        canForceRecover = state == "installed" or state == "legacyGround",
        controllerItemId = itemId,
        controller = controller,
        revision = Storage.integer(network.revision, 0),
    }
end

local function removeRecordedController(network, expectedToken, recordedController)
    local controller = type(recordedController) == "table" and recordedController
        or (type(network.controller) == "table" and network.controller or nil)
    if not controller then return false end
    local object = Storage.findWorldController(
        controller.x, controller.y, controller.z,
        controller.itemId, expectedToken, controller.objectId
    )
    if not object then return false end
    return removeWorldController(object)
end

function Manager.claimController(player, options)
    options = type(options) == "table" and options or {}
    local network, reason, created = Manager.getOrCreateNetwork(player)
    if not network then return false, reason end
    if not Manager.canUse(player, network) then return false, "notAllowed" end
    if not created and not Manager.canManage(player, network) then return false, "manageDenied" end
    normalizeControllerFields(network)

    local status, statusReason = Manager.controllerStatus(player)
    if not status then return false, statusReason end
    local state = tostring(status.state or "missing")
    local forceRecovery = options.forceRecovery == true
    if state == "kit" then return false, "controllerOwned" end
    if (state == "installed" or state == "legacyGround") and not forceRecovery then
        return false, "controllerInstalled"
    end

    local recovered = network.controllerClaimedOnce == true
    local cost = recovered and Storage.ControllerRecoveryCost or 0
    local oldToken = tostring(network.controllerToken or "")
    local oldController = network.controller
    local token = Storage.newId("controller", network.networkId)

    local receipt
    if cost > 0 then
        if type(options.charge) ~= "function" then
            return false, "economyUnavailable"
        end
        local paid
        paid, receipt = options.charge(cost)
        if paid ~= true then
            return false, "currencyNotEnough"
        end
    end
    local item, createReason = inventoryAddController(player, network, token)
    if not item then
        if cost > 0 and type(options.refund) == "function" then
            pcall(options.refund, receipt)
        end
        return false, createReason
    end

    network.controllerToken = token
    network.controllerClaimedOnce = true
    setControllerState(network, "kit", Storage.itemId(item), nil)
    local removedDuplicates = cleanupInventoryControllers(player, network.networkId, item)
    if oldToken ~= "" then removeRecordedController(network, oldToken, oldController) end
    transmitStore()
    if type(options.onCommit) == "function" then
        pcall(options.onCommit, cost, recovered, receipt)
    end
    return true, nil, {
        networkId = network.networkId,
        controllerItemId = Storage.itemId(item),
        token = token,
        recovered = recovered,
        cost = cost,
        removedDuplicates = removedDuplicates,
        state = "kit",
    }
end

local function controllerPlacementAllowed(player, network, square)
    if not player or not network or not square then return false, "placementInvalid" end
    local playerPosition = Storage.positionOfPlayer(player)
    local position = Storage.objectCoordinates(square) or {
        x = safeCall(square, "getX", nil),
        y = safeCall(square, "getY", nil),
        z = safeCall(square, "getZ", nil),
    }
    if not playerPosition or position.x == nil or position.y == nil or position.z == nil then
        return false, "placementInvalid"
    end
    if Storage.integer(playerPosition.z, -1) ~= Storage.integer(position.z, -2)
        or Storage.distance2D(playerPosition, position) > Storage.ControllerPlacementDistance then
        return false, "targetTooFar"
    end
    if safeCall(square, "isVehicleIntersecting", false) == true then return false, "placementBlocked" end
    if not safeCall(square, "getFloor", nil) then return false, "placementBlocked" end
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local object = objects[i]
        local item = safeCall(object, "getItem", nil)
        if Storage.isController(item) or Storage.isInstalledController(object) then
            return false, "controllerOverlap"
        end
    end

    local scope, scopeKey, safehouse = Manager.scopeForPosition(player, position)
    if network.scope == "safehouse" then
        if scope ~= "safehouse" or scopeKey ~= tostring(network.safehouse or "") then
            if Storage.playerKey(player) ~= tostring(network.creator or "") and not Storage.isAdmin(player) then
                return false, "notAllowed"
            end
        elseif not (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
            return false, "notAllowed"
        end
    elseif scope == "safehouse" then
        local existing = Manager.getNetworkByScope(scopeKey)
        if existing and existing ~= network then return false, "safehouseHasNetwork" end
        if not (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
            return false, "notAllowed"
        end
    end
    return true, nil, position, scope, scopeKey
end

local function updateNetworkScopeForPlacement(network, scope, scopeKey)
    if network.scope ~= "personal" or scope ~= "safehouse" then return false end
    local store = Manager.getStore()
    if store.scopeIndex[network.scopeKey] == network.networkId then
        store.scopeIndex[network.scopeKey] = nil
    end
    network.scope = "safehouse"
    network.scopeKey = scopeKey
    network.safehouse = scopeKey
    store.scopeIndex[scopeKey] = network.networkId
    return true
end

function Manager.installController(player, args)
    args = type(args) == "table" and args or {}
    local itemId = tostring(args.controllerItemId or "")
    local inventory = safeCall(player, "getInventory", nil)
    local item, source = Storage.findItemRecursive(inventory, itemId, Storage.MaxDepth)
    if not item or not source or not Storage.isController(item) then return false, "controllerMissing" end
    local networkId, token = Storage.getControllerIdentity(item)
    if networkId == "" or token == "" then return false, "controllerInvalid" end
    if tostring(args.networkId or networkId) ~= networkId or tostring(args.controllerToken or token) ~= token then
        return false, "controllerChanged"
    end
    local network = Manager.getNetwork(networkId)
    if not network or tostring(network.controllerToken or "") ~= token then return false, "controllerExpired" end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local status = Manager.controllerStatus(player)
    if not status or status.state ~= "kit" or tostring(status.controllerItemId or "") ~= itemId then
        return false, "controllerChanged"
    end

    local square = Storage.getSquare(args.x, args.y, args.z)
    local allowed, reason, position, scope, scopeKey = controllerPlacementAllowed(player, network, square)
    if not allowed then return false, reason end
    if not IsoCarBatteryCharger or not IsoCarBatteryCharger.new then return false, "placementUnsupported" end

    local okCreate, object = pcall(function()
        return IsoCarBatteryCharger.new(item, getCell(), square)
    end)
    if not okCreate or not object then return false, "placementFailed" end
    local objectId = Storage.newId("controller-object", network.networkId)
    if not Storage.markInstalledController(object, network.networkId, token, objectId) then
        return false, "placementFailed"
    end
    local okAdd = pcall(function() square:AddSpecialObject(object) end)
    if not okAdd or Storage.integer(safeCall(object, "getObjectIndex", -1), -1) < 0 then
        if okAdd then removeWorldController(object) end
        return false, "placementFailed"
    end
    if not removeInventoryItem(source, item) then
        removeWorldController(object)
        return false, "controllerChanged"
    end
    local removedDuplicates = cleanupInventoryControllers(player, network.networkId, nil)
    if object.transmitCompleteItemToClients then
        pcall(function() object:transmitCompleteItemToClients() end)
    elseif object.transmitCompleteItemToServer then
        pcall(function() object:transmitCompleteItemToServer() end)
    end

    updateNetworkScopeForPlacement(network, scope, scopeKey)
    local controller = {
        x = Storage.integer(position.x, 0),
        y = Storage.integer(position.y, 0),
        z = Storage.integer(position.z, 0),
        itemId = Storage.itemId(item),
        objectId = objectId,
    }
    setControllerState(network, "installed", Storage.itemId(item), controller)
    transmitStore()
    return true, nil, {
        networkId = network.networkId,
        controllerItemId = Storage.itemId(item),
        controllerToken = token,
        controller = controller,
        state = "installed",
        removedDuplicates = removedDuplicates,
    }
end

function Manager.reclaimController(player, args)
    local network, worldObject, item, reason = Manager.resolveController(player, args)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    if not Storage.isInstalledController(worldObject) then return false, "controllerNotInstalled" end
    local inventory = safeCall(player, "getInventory", nil)
    if not inventory or not item then return false, "inventoryMissing" end

    local okAdd = pcall(function() inventory:AddItem(item) end)
    if not okAdd or not Storage.containerContains(inventory, item) then return false, "createFailed" end
    Storage.syncAdd(inventory, item)
    if not removeWorldController(worldObject) then
        removeInventoryItem(inventory, item)
        return false, "reclaimFailed"
    end
    local removedDuplicates = cleanupInventoryControllers(player, network.networkId, item)
    setControllerState(network, "kit", Storage.itemId(item), nil)
    transmitStore()
    return true, nil, {
        networkId = network.networkId,
        controllerItemId = Storage.itemId(item),
        token = tostring(network.controllerToken or ""),
        state = "kit",
        removedDuplicates = removedDuplicates,
    }
end

function Manager.resolveController(player, args)
    args = type(args) == "table" and args or {}
    local worldObject, item = Storage.findWorldController(
        args.x, args.y, args.z, args.controllerItemId, args.controllerToken, args.controllerObjectId
    )
    if not item then return nil, nil, nil, "controllerMissing" end
    local networkId, token = Storage.getControllerIdentity(item)
    if networkId == "" or token == "" then return nil, nil, nil, "controllerInvalid" end
    if args.networkId and tostring(args.networkId) ~= "" and tostring(args.networkId) ~= networkId then
        return nil, nil, nil, "controllerChanged"
    end
    local network = Manager.getNetwork(networkId)
    if not network or tostring(network.controllerToken or "") ~= token then
        return nil, nil, nil, "controllerExpired"
    end
    local playerPosition = Storage.positionOfPlayer(player)
    local controllerPosition = { x = Storage.number(args.x, 0), y = Storage.number(args.y, 0), z = Storage.integer(args.z, 0) }
    if args.allowRemote ~= true and (not playerPosition or Storage.distance2D(playerPosition, controllerPosition) > Storage.ControllerUseDistance
        or Storage.integer(playerPosition.z, 0) ~= Storage.integer(controllerPosition.z, 0)) then
        return nil, nil, nil, "tooFar"
    end

    local scope, scopeKey, safehouse = Manager.scopeForPosition(player, controllerPosition)
    if network.scope == "personal" and scope == "safehouse" then
        local existing = Manager.getNetworkByScope(scopeKey)
        if existing and existing ~= network then return nil, nil, nil, "safehouseHasNetwork" end
        local store = Manager.getStore()
        if store.scopeIndex[network.scopeKey] == network.networkId then store.scopeIndex[network.scopeKey] = nil end
        network.scope = "safehouse"
        network.scopeKey = scopeKey
        network.safehouse = scopeKey
        store.scopeIndex[scopeKey] = network.networkId
    end
    local allowedAtCurrentPosition
    if network.scope == "safehouse" then
        if scope == "safehouse" and scopeKey == tostring(network.safehouse or "") then
            allowedAtCurrentPosition = Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)
        else
            allowedAtCurrentPosition = Storage.playerKey(player) == tostring(network.creator or "") or Storage.isAdmin(player)
        end
    else
        allowedAtCurrentPosition = Manager.canUse(player, network)
    end
    if not allowedAtCurrentPosition then return nil, nil, nil, "notAllowed" end
    local _, _, objectId = Storage.getInstalledControllerIdentity(worldObject)
    local resolvedState = Storage.isInstalledController(worldObject) and "installed" or "legacyGround"
    local changed = type(network.controller) ~= "table"
        or Storage.integer(network.controller.x, -1) ~= Storage.integer(controllerPosition.x, 0)
        or Storage.integer(network.controller.y, -1) ~= Storage.integer(controllerPosition.y, 0)
        or Storage.integer(network.controller.z, -1) ~= Storage.integer(controllerPosition.z, 0)
        or tostring(network.controller.itemId or "") ~= tostring(Storage.itemId(item) or "")
        or tostring(network.controller.objectId or "") ~= tostring(objectId or "")
        or tostring(network.controllerState or "") ~= resolvedState
    network.controller = {
        x = Storage.integer(controllerPosition.x, 0),
        y = Storage.integer(controllerPosition.y, 0),
        z = Storage.integer(controllerPosition.z, 0),
        itemId = Storage.itemId(item),
        objectId = objectId ~= "" and objectId or nil,
    }
    network.controllerState = resolvedState
    network.controllerItemId = Storage.itemId(item)
    if changed then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
        transmitStore()
    end
    return network, worldObject, item, nil
end

function Manager.networkSummary(player, network)
    return {
        networkId = network.networkId,
        scope = network.scope,
        owner = network.owner,
        creator = network.creator,
        radius = Storage.clamp(Storage.integer(network.radius, Storage.DefaultRadius), Storage.MinRadius, Storage.MaxRadius),
        maxLinks = Storage.clamp(Storage.integer(network.maxLinks, Storage.DefaultMaxLinks), Storage.MinLinks, Storage.MaxLinks),
        linkCount = Manager.linkCount(network),
        revision = Storage.integer(network.revision, 0),
        canUse = Manager.canUse(player, network),
        canManage = Manager.canManage(player, network),
        isAdmin = Storage.isAdmin(player),
        controller = network.controller,
    }
end

function Manager.linkCount(network)
    local count = 0
    for _ in pairs((network and network.links) or {}) do count = count + 1 end
    return count
end

function Manager.linkContainer(player, controllerArgs, targetArgs)
    local remoteControllerArgs = {}
    for key, value in pairs(controllerArgs or {}) do remoteControllerArgs[key] = value end
    remoteControllerArgs.allowRemote = true
    local network, _, _, reason = Manager.resolveController(player, remoteControllerArgs)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    if Manager.linkCount(network) >= Storage.clamp(Storage.integer(network.maxLinks, Storage.DefaultMaxLinks), Storage.MinLinks, Storage.MaxLinks) then
        return false, "linkLimit"
    end
    local targetPosition = {
        x = Storage.integer(targetArgs.x, 0),
        y = Storage.integer(targetArgs.y, 0),
        z = Storage.integer(targetArgs.z, 0),
    }
    local playerPosition = Storage.positionOfPlayer(player)
    if not playerPosition or Storage.distance2D(playerPosition, targetPosition) > 2.5
        or Storage.integer(playerPosition.z, 0) ~= targetPosition.z then return false, "targetTooFar" end
    if not Storage.isWithinNetworkRange(network, targetPosition) then return false, "outOfRange" end
    local object = Storage.resolveObjectCandidate(targetPosition.x, targetPosition.y, targetPosition.z, targetArgs.objectIndex, targetArgs.sprite)
    if not object then return false, "targetChanged" end
    local slot = Storage.getContainerSlot(object, targetArgs.slotIndex)
    if not slot or not slot.container then return false, "containerMissing" end
    local existingMarker = Storage.getLinkMarker(object, slot.index)
    if existingMarker then
        local markerNetworkId = type(existingMarker) == "table" and existingMarker.networkId or nil
        local markerLinkId = type(existingMarker) == "table" and existingMarker.linkId or nil
        local existingNetwork = Manager.getNetwork(markerNetworkId)
        local existingLink = existingNetwork and existingNetwork.links
            and existingNetwork.links[tostring(markerLinkId or "")] or nil
        if existingLink then return false, "alreadyLinked" end
        Storage.clearLinkMarker(object, slot.index, markerLinkId)
    end
    local parent = safeCall(slot.container, "getParent", nil)
    if parent and parent ~= object then return false, "portableContainer" end
    local objectId = Storage.getObjectId(object, true)
    if not objectId then return false, "objectIdentityFailed" end
    local linkId = Storage.newId("link", network.networkId .. ":" .. objectId .. ":" .. tostring(slot.index))
    local link = {
        linkId = linkId,
        networkId = network.networkId,
        objectId = objectId,
        x = targetPosition.x, y = targetPosition.y, z = targetPosition.z,
        slotIndex = slot.index,
        sprite = Storage.objectSpriteName(object),
        containerType = slot.type,
        name = tostring(targetArgs.name or slot.type or "Container"):sub(1, 60),
        role = tostring(targetArgs.role or "auto"),
        priority = Storage.clamp(Storage.integer(targetArgs.priority, 50), 0, 100),
        allowCategories = {},
        denyCategories = {},
        createdAtMs = Storage.nowMs(),
    }
    local marker = { networkId = network.networkId, linkId = linkId, objectId = objectId, slotIndex = slot.index }
    if not Storage.setLinkMarker(object, slot.index, marker) then return false, "markerFailed" end
    network.links[linkId] = link
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil, link
end

function Manager.unlinkContainer(player, controllerArgs, linkId)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local link = network.links[tostring(linkId or "")]
    if not link then return false, "linkMissing" end
    local object = Storage.resolveLink(link)
    if object then Storage.clearLinkMarker(object, link.slotIndex, link.linkId) end
    network.links[link.linkId] = nil
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil
end

local roleSet
local function validRole(role)
    if not roleSet then
        roleSet = {}
        for i = 1, #Storage.Roles do roleSet[Storage.Roles[i]] = true end
    end
    return roleSet[tostring(role or "")] == true
end

local function normalizeCategoryRules(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for i = 1, #Storage.Categories do
        local category = Storage.Categories[i]
        if source[category] == true then result[category] = true end
    end
    return result
end

function Manager.updateLink(player, controllerArgs, args)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local link = network.links[tostring(args.linkId or "")]
    if not link then return false, "linkMissing" end
    if args.name ~= nil then link.name = tostring(args.name):sub(1, 60) end
    if args.role ~= nil then
        if not validRole(args.role) then return false, "invalidRole" end
        link.role = tostring(args.role)
    end
    if args.priority ~= nil then link.priority = Storage.clamp(Storage.integer(args.priority, 50), 0, 100) end
    if type(args.allowCategories) == "table" then link.allowCategories = normalizeCategoryRules(args.allowCategories) end
    if type(args.denyCategories) == "table" then link.denyCategories = normalizeCategoryRules(args.denyCategories) end
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil, link
end

function Manager.updateLimits(player, controllerArgs, radius, maxLinks)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    if not Storage.isAdmin(player) then return false, "adminOnly" end
    network.radius = Storage.clamp(Storage.integer(radius, network.radius), Storage.MinRadius, Storage.MaxRadius)
    network.maxLinks = Storage.clamp(Storage.integer(maxLinks, network.maxLinks), Storage.MinLinks, Storage.MaxLinks)
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil
end

function Manager.startIndex(player, controllerArgs, callback)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    local job = Storage.newIndexJob(network)
    local jobId = Storage.newId("index", network.networkId)
    job.jobId = jobId
    job.player = player
    job.callback = callback
    Manager.runtime.jobs[jobId] = job
    return true, nil, job
end

function Manager.processJobs()
    local completed = {}
    local processedJobs = 0
    for jobId, job in pairs(Manager.runtime.jobs) do
        if processedJobs >= 2 then break end
        processedJobs = processedJobs + 1
        if Storage.stepIndexJob(job, Storage.IndexBatchItems, Storage.IndexBudgetMs) then
            completed[#completed + 1] = jobId
            local network = job.network
            local snapshot = Storage.buildSnapshot(job, network)
            job.snapshot = snapshot
            Manager.runtime.latestJobs[network.networkId] = job
            Manager.runtime.snapshotJobs[snapshot.snapshotId] = job
            if job.callback then
                local ok, err = pcall(job.callback, job, snapshot)
                if not ok then print("[GodSystemStorage] index callback failed: " .. tostring(err)) end
            end
        end
    end
    for i = 1, #completed do Manager.runtime.jobs[completed[i]] = nil end
    local cutoff = Storage.nowMs() - 300000
    for snapshotId, job in pairs(Manager.runtime.snapshotJobs) do
        if Storage.number(job and job.finishedAtMs, 0) < cutoff then Manager.runtime.snapshotJobs[snapshotId] = nil end
    end
end

function Manager.latestJob(networkId, snapshotId)
    local job
    if snapshotId and tostring(snapshotId) ~= "" then
        job = Manager.runtime.snapshotJobs[tostring(snapshotId)]
    else
        job = Manager.runtime.latestJobs[tostring(networkId or "")]
    end
    if not job then return nil end
    if tostring(job.network and job.network.networkId or "") ~= tostring(networkId or "") then return nil end
    if snapshotId and tostring(snapshotId) ~= "" and tostring(job.snapshot and job.snapshot.snapshotId or "") ~= tostring(snapshotId) then
        return nil
    end
    return job
end

local function countOfflineLinks(network)
    local offline = 0
    for _, link in pairs((network and network.links) or {}) do
        local object, container = Storage.resolveLink(link)
        if not object or not container or not Storage.isWithinNetworkRange(network, { x = link.x, y = link.y, z = link.z }) then
            offline = offline + 1
        end
    end
    return offline
end

local function collectSafeDepositItems(player)
    local result = {}
    local inventory = safeCall(player, "getInventory", nil)
    local items = safeCall(inventory, "getItems", nil)
    local size = Storage.integer(safeCall(items, "size", 0), 0)
    local seen = {}
    local function append(item)
        local id = Storage.itemId(item)
        if id and not seen[id] then seen[id] = true; result[#result + 1] = { item = item, container = Storage.getItemContainer(item) } end
    end
    local function visitWornContents(item, depth)
        if depth > Storage.MaxDepth then return end
        local child = safeCall(item, "getInventory", nil)
        local children = safeCall(child, "getItems", nil)
        local childCount = Storage.integer(safeCall(children, "size", 0), 0)
        for j = 0, childCount - 1 do
            local nested = safeCall(children, "get", nil, j)
            local allowed = Storage.isSafeDepositItem(player, nested)
            if allowed then append(nested) else visitWornContents(nested, depth + 1) end
        end
    end
    for i = 0, size - 1 do
        local item = safeCall(items, "get", nil, i)
        local allowed, reason = Storage.isSafeDepositItem(player, item)
        if allowed then
            append(item)
        elseif reason == "worn" then
            visitWornContents(item, 0)
        end
    end
    return result
end

function Manager.deposit(player, controllerArgs, args)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    local candidates = {}
    if args.safeAll == true then
        candidates = collectSafeDepositItems(player)
    else
        local inventory = safeCall(player, "getInventory", nil)
        local seen = {}
        for i = 1, #((args and args.itemIds) or {}) do
            local id = tostring(args.itemIds[i] or "")
            if id ~= "" and not seen[id] then
                seen[id] = true
                local item, source = Storage.findItemRecursive(inventory, id)
                if item and source then candidates[#candidates + 1] = { item = item, container = source } end
            end
        end
    end
    local stats = { requested = #candidates, success = 0, skipped = 0, failed = 0, coldDowngrade = 0, offline = countOfflineLinks(network) }
    local fallbackSquare = Storage.getSquare(network.controller.x, network.controller.y, network.controller.z)
    for i = 1, #candidates do
        local row = candidates[i]
        local allowed = Storage.isSafeDepositItem(player, row.item)
        if not allowed then
            stats.skipped = stats.skipped + 1
        else
            local routes, downgraded = Storage.routeCandidates(network, player, row.item)
            if #routes == 0 then
                stats.skipped = stats.skipped + 1
            else
                local moved = false
                for j = 1, #routes do
                    local route = routes[j]
                    local function targetValidator()
                        local object, current = Storage.resolveLink(route.link)
                        return object ~= nil and current == route.container
                            and Storage.isWithinNetworkRange(network, { x = route.link.x, y = route.link.y, z = route.link.z })
                    end
                    local ok = Storage.transferItem(player, row.item, row.container, route.container, fallbackSquare, nil, targetValidator)
                    if ok then moved = true; break end
                    if not Storage.containerContains(row.container, row.item) then break end
                end
                if moved then
                    stats.success = stats.success + 1
                    if downgraded then stats.coldDowngrade = stats.coldDowngrade + 1 end
                else
                    stats.failed = stats.failed + 1
                end
            end
        end
    end
    if stats.success > 0 then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
        transmitStore()
    end
    return stats.success > 0, stats.success > 0 and nil or "nothingMoved", stats
end

local function playerWearsItem(player, expectedItem)
    local worn = safeCall(player, "getWornItems", nil)
    local size = Storage.integer(safeCall(worn, "size", 0), 0)
    for i = 0, size - 1 do
        local entry = safeCall(worn, "get", nil, i)
        local wornItem = safeCall(entry, "getItem", entry)
        if wornItem == expectedItem then return true end
    end
    return false
end

function Manager.withdraw(player, controllerArgs, args)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs)
    if not network then return false, reason end
    local job = Manager.latestJob(network.networkId, args.snapshotId)
    if not job then return false, "snapshotExpired" end
    local instances = job.instances[tostring(args.groupKey or "")] or {}
    local wanted = Storage.clamp(Storage.integer(args.count, 1), 1, 20000)
    if args.itemId and tostring(args.itemId) ~= "" then
        local exact = {}
        for i = 1, #instances do
            if tostring(instances[i].id or "") == tostring(args.itemId) then exact[1] = instances[i]; break end
        end
        instances = exact
        wanted = 1
    end
    local target = safeCall(player, "getInventory", nil)
    local targetItem
    if args.targetItemId and tostring(args.targetItemId) ~= "" then
        targetItem = Storage.findItemRecursive(target, tostring(args.targetItemId))
        if not targetItem or not playerWearsItem(player, targetItem) then return false, "targetInvalid" end
        local nested = targetItem and safeCall(targetItem, "getInventory", nil) or nil
        if not nested then return false, "targetInvalid" end
        target = nested
    end
    if not target then return false, "targetMissing" end
    local stats = { requested = wanted, success = 0, skipped = 0, failed = 0, coldDowngrade = 0, offline = countOfflineLinks(network) }
    local fallbackSquare = Storage.getSquare(network.controller.x, network.controller.y, network.controller.z)
    local selected, expectedIds = {}, {}
    for i = 1, math.min(wanted, #instances) do
        selected[#selected + 1] = instances[i]
        expectedIds[tostring(instances[i].id or "")] = true
    end
    local liveItems = Storage.findNetworkItems(network, expectedIds)
    for i = 1, #selected do
        local expected = selected[i]
        local live = liveItems[tostring(expected.id or "")]
        local item, source = live and live.item or nil, live and live.source or nil
        if not item or not source then
            stats.skipped = stats.skipped + 1
        else
            local function sourceValidator()
                local object, current = Storage.resolveLink(live.link)
                return object ~= nil and current ~= nil
                    and Storage.isWithinNetworkRange(network, { x = live.link.x, y = live.link.y, z = live.link.z })
            end
            local function targetValidator()
                if not targetItem then return target == safeCall(player, "getInventory", nil) end
                return playerWearsItem(player, targetItem) and safeCall(targetItem, "getInventory", nil) == target
            end
            local ok = Storage.transferItem(player, item, source, target, fallbackSquare, sourceValidator, targetValidator)
            if ok then stats.success = stats.success + 1 else stats.failed = stats.failed + 1 end
        end
    end
    if stats.success > 0 then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
        transmitStore()
    end
    return stats.success > 0, stats.success > 0 and nil or "nothingMoved", stats
end

function Manager.getOperation(player, opId, fingerprint)
    opId = tostring(opId or "")
    if opId == "" then return nil, "missingOperation" end
    local store = Manager.getStore()
    local key = Storage.playerKey(player) .. ":" .. opId
    local row = store.operations[key]
    if row and tostring(row.fingerprint or "") ~= tostring(fingerprint or "") then return nil, "operationMismatch" end
    return row, nil, key
end

function Manager.beginOperation(player, opId, fingerprint)
    Manager.runtime.operationCount = Storage.integer(Manager.runtime.operationCount, 0) + 1
    if Manager.runtime.operationCount % 100 == 0 then Manager.pruneOperations() end
    local existing, reason, key = Manager.getOperation(player, opId, fingerprint)
    if reason then return nil, reason end
    if existing then return existing, existing.done == true and "done" or "pending" end
    local row = { fingerprint = tostring(fingerprint or ""), startedAtMs = Storage.nowMs(), done = false }
    Manager.getStore().operations[key] = row
    return row, nil
end

function Manager.finishOperation(row, ok, reason, payload)
    row.done = true
    row.ok = ok == true
    row.reason = reason
    row.payload = payload
    row.finishedAtMs = Storage.nowMs()
    transmitStore()
end

function Manager.pruneOperations()
    local store = Manager.getStore()
    local cutoff = Storage.nowMs() - 3600000
    for key, row in pairs(store.operations) do
        if Storage.number(row.finishedAtMs or row.startedAtMs, 0) < cutoff then store.operations[key] = nil end
    end
end

return Manager
