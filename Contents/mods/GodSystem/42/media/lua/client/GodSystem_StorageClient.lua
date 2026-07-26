require "GodSystem_StorageManager"

GodSystemStorageClient = GodSystemStorageClient or {}

local Client = GodSystemStorageClient
local Storage = GodSystemStorage
local Manager = GodSystemStorageManager
local MODULE = Storage.Module

Client.snapshot = Client.snapshot or nil
Client.snapshotBuilding = Client.snapshotBuilding or nil
Client.details = Client.details or {}
Client.controller = Client.controller or nil
Client.pending = Client.pending or {}
Client.lastError = Client.lastError or nil
Client.claimState = Client.claimState or nil
Client.statusRequestedAtMs = Client.statusRequestedAtMs or 0

local function player()
    return getPlayer and getPlayer() or nil
end

local function isMultiplayer()
    return isClient and isClient() == true
end

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local reasonText = {
    controllerMissing = { "Storage_Error_ControllerMissing", "Controller is missing" },
    controllerInvalid = { "Storage_Error_ControllerInvalid", "Controller identity is invalid" },
    controllerChanged = { "Storage_Error_ControllerChanged", "Controller changed" },
    controllerExpired = { "Storage_Error_ControllerExpired", "This controller has expired; recover it from the God System page" },
    controllerOwned = { "Storage_Error_ControllerOwned", "A valid controller kit is already in your inventory" },
    controllerInstalled = { "Storage_Error_ControllerInstalled", "The controller is already installed" },
    controllerNotInstalled = { "Storage_Error_ControllerNotInstalled", "This controller is not installed" },
    controllerOverlap = { "Storage_Error_ControllerOverlap", "A controller already occupies this square" },
    placementBlocked = { "Storage_Error_PlacementBlocked", "The controller cannot be installed on this square" },
    placementInvalid = { "Storage_Error_PlacementInvalid", "The selected installation square is invalid" },
    placementUnsupported = { "Storage_Error_PlacementUnsupported", "This game version cannot create the installed controller" },
    placementFailed = { "Storage_Error_PlacementFailed", "Controller installation failed" },
    reclaimFailed = { "Storage_Error_ReclaimFailed", "Controller reclaim failed" },
    currencyNotEnough = { "Storage_Error_CurrencyNotEnough", "Not enough system coins" },
    economyUnavailable = { "Storage_Error_EconomyUnavailable", "The system coin service is unavailable" },
    tooFar = { "Storage_Error_TooFar", "Move closer to the controller" },
    notAllowed = { "Storage_Error_NotAllowed", "You cannot use this storage network" },
    manageDenied = { "Storage_Error_ManageDenied", "You cannot manage this storage network" },
    safehouseHasNetwork = { "Storage_Error_SafehouseHasNetwork", "This safehouse already has a storage network" },
    linkLimit = { "Storage_Error_LinkLimit", "The container connection limit has been reached" },
    outOfRange = { "Storage_Error_OutOfRange", "The container is outside the network range" },
    targetTooFar = { "Storage_Error_TargetTooFar", "Move next to the target container" },
    targetInvalid = { "Storage_Error_TargetInvalid", "The withdrawal target is no longer a worn container" },
    targetChanged = { "Storage_Error_TargetChanged", "The target furniture changed" },
    containerMissing = { "Storage_Error_ContainerMissing", "The selected container is missing" },
    alreadyLinked = { "Storage_Error_AlreadyLinked", "This container is already linked" },
    portableContainer = { "Storage_Error_Portable", "Portable containers cannot be linked in this version" },
    snapshotExpired = { "Storage_Error_SnapshotExpired", "The storage snapshot expired; refresh and try again" },
    nothingMoved = { "Storage_Error_NothingMoved", "No item could be moved" },
    operationPending = { "Storage_Error_OperationPending", "The previous operation is still being processed" },
    operationMismatch = { "Storage_Error_OperationMismatch", "The operation identity does not match" },
    adminOnly = { "Storage_Error_AdminOnly", "Only an administrator can change this setting" },
    internalError = { "Storage_Error_Internal", "Storage operation failed" },
    markerFailed = { "Storage_Error_MarkerFailed", "The network container mark could not be changed" },
    nativePlacementRequired = { "Storage_Error_NativePlacement", "Use the game's Place Item action to install this controller" },
}

function Client.notifyReason(reason)
    local row = reasonText[tostring(reason or "")] or { "Storage_Error_Generic", "Storage operation failed: {1}" }
    local value = text(row[1], row[2])
    if row[1] == "Storage_Error_Generic" then value = value:gsub("{1}", tostring(reason or "unknown")) end
    if GodSystem and GodSystem.notify then GodSystem.notify(value) end
end

function Client.newOperationId(command)
    return Storage.newId("op-" .. tostring(command or "storage"), Storage.playerKey(player()))
end

function Client.controllerArgs()
    local current = Client.controller or {}
    return {
        controllerX = current.x,
        controllerY = current.y,
        controllerZ = current.z,
        controllerItemId = current.itemId,
        controllerToken = current.token,
        controllerObjectId = current.objectId,
        networkId = current.networkId,
    }
end

local function mergeControllerArgs(args)
    local result = Client.controllerArgs()
    for key, value in pairs(args or {}) do result[key] = value end
    return result
end

function Client.setController(item, x, y, z, object)
    local networkId, token = Storage.getControllerIdentity(item)
    if (not networkId or networkId == "") and object then networkId, token = Storage.getControllerIdentity(object) end
    if not networkId or networkId == "" or not token or token == "" then return false end
    local _, _, objectId = Storage.getInstalledControllerIdentity(object)
    local worldItem = object and Storage.safeCall(object, "getItem", nil) or nil
    local controllerItemId = Storage.itemId(worldItem)
    if not controllerItemId and item ~= object then controllerItemId = Storage.itemId(item) end
    if Client.controller and tostring(Client.controller.networkId or "") ~= tostring(networkId) then
        Client.networkState = nil
        Client.snapshot = nil
    end
    Client.controller = {
        x = Storage.integer(x, 0),
        y = Storage.integer(y, 0),
        z = Storage.integer(z, 0),
        itemId = controllerItemId,
        token = token,
        networkId = networkId,
        objectId = objectId ~= "" and objectId or nil,
        object = object,
    }
    return true
end

local function send(command, args)
    if not isMultiplayer() or not sendClientCommand then return false end
    sendClientCommand(player(), MODULE, command, args or {})
    return true
end

function Client.applySnapshot(snapshot)
    Client.snapshot = snapshot
    Client.snapshotBuilding = nil
    Client.details = {}
    if GodSystemStorageUI and GodSystemStorageUI.onSnapshot then
        GodSystemStorageUI.onSnapshot(snapshot)
    end
end

local function startLocalIndex(allowRemote)
    local p = player()
    local ok, reason, job = Manager.startIndex(p, {
        x = Client.controller.x, y = Client.controller.y, z = Client.controller.z,
        controllerItemId = Client.controller.itemId,
        controllerToken = Client.controller.token,
        networkId = Client.controller.networkId,
        allowRemote = allowRemote == true,
    }, function(_, snapshot)
        Client.applySnapshot(snapshot)
    end)
    if not ok then Client.notifyReason(reason); return false end
    Client.networkState = Manager.networkSummary(p, job.network)
    if GodSystemStorageUI and GodSystemStorageUI.onNetworkState then GodSystemStorageUI.onNetworkState(Client.networkState) end
    return true
end

local function refreshGodSystemStoragePage()
    if GodSystemUI and GodSystemUI.window and GodSystemUI.window.mode == "storage"
        and GodSystemUI.window.requestDeferredPopulate then
        GodSystemUI.window:requestDeferredPopulate(1)
    end
end

function Client.requestControllerStatus(force)
    local now = Storage.nowMs()
    if force ~= true and Client.claimState and now - (Client.statusRequestedAtMs or 0) < 1500 then
        return Client.claimState
    end
    Client.statusRequestedAtMs = now
    if isMultiplayer() then
        send("controllerStatus", {})
        return Client.claimState
    end
    local status, reason = Manager.controllerStatus(player())
    if not status then Client.notifyReason(reason); return nil end
    Client.claimState = status
    if status.state ~= "installed" and status.state ~= "legacyGround" then
        Client.controller = nil
        Client.networkState = nil
    end
    refreshGodSystemStoragePage()
    return status
end

local function beginStandalone(command, args)
    args = args or {}
    for _, pending in pairs(Client.pending) do
        if pending.command == command and type(pending.args) == "table" then
            pending.retriedAtMs = Storage.nowMs()
            return false, pending.args
        end
    end
    args.opId = args.opId or Client.newOperationId(command)
    Client.pending[args.opId] = { command = command, args = args, startedAtMs = Storage.nowMs() }
    return true, args
end

function Client.claimController(forceRecovery)
    local fresh, args = beginStandalone("claimController", { forceRecovery = forceRecovery == true })
    if not fresh then
        if isMultiplayer() then return send("claimController", args) end
        return false
    end
    if isMultiplayer() then return send("claimController", args) end
    local ok, reason, payload = Manager.claimController(player(), {
        forceRecovery = forceRecovery == true,
        charge = function(cost)
            if not GodSystem or not GodSystem.spendCurrency then return false, nil end
            local paid, fromBank, fromCash = GodSystem.spendCurrency(cost)
            return paid, { fromBank = fromBank, fromCash = fromCash }
        end,
        refund = function(receipt)
            if not GodSystem or not GodSystem.refundCurrencySources then return false end
            receipt = type(receipt) == "table" and receipt or {}
            return GodSystem.refundCurrencySources(receipt.fromBank or 0, receipt.fromCash or 0)
        end,
        onCommit = function(cost, recovered)
            if GodSystem and GodSystem.recordStorageControllerClaim then
                GodSystem.recordStorageControllerClaim(cost, recovered)
            end
        end,
    })
    Client.pending[args.opId] = nil
    if not ok then Client.notifyReason(reason); return false end
    Client.requestControllerStatus(true)
    if GodSystem and GodSystem.notify then
        GodSystem.notify(text(payload and payload.recovered and "Storage_Notify_ControllerRecovered" or "Storage_Notify_ControllerClaimed", "Storage controller received"))
    end
    return true, payload
end

function Client.installController()
    Client.notifyReason("nativePlacementRequired")
    return false
end

function Client.open(item, x, y, z, object)
    if not Client.setController(item, x, y, z, object) then
        Client.notifyReason("controllerInvalid")
        return false
    end
    Client.snapshot = nil
    Client.snapshotBuilding = nil
    if GodSystemStorageUI and GodSystemStorageUI.open then GodSystemStorageUI.open() end
    if isMultiplayer() then return send("open", Client.controllerArgs()) end
    return startLocalIndex()
end

function Client.reclaim(item, x, y, z, object)
    if not Client.setController(item, x, y, z, object) then
        Client.notifyReason("controllerInvalid")
        return false
    end
    local args = Client.controllerArgs()
    local fresh
    fresh, args = beginStandalone("reclaimController", args)
    if not fresh then
        if isMultiplayer() then return send("reclaimController", args) end
        return false
    end
    if isMultiplayer() then return send("reclaimController", args) end
    local ok, reason, payload = Manager.reclaimController(player(), args)
    Client.pending[args.opId] = nil
    if not ok then Client.notifyReason(reason); return false end
    Client.controller = nil
    Client.requestControllerStatus(true)
    if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_Notify_ControllerReclaimed", "Storage controller reclaimed")) end
    return true, payload
end

function Client.refresh()
    if not Client.controller then return false end
    if isMultiplayer() then return send("refresh", Client.controllerArgs()) end
    return startLocalIndex()
end

function Client.requestDetails(groupKey)
    if not Client.snapshot then return false end
    groupKey = tostring(groupKey or "")
    Client.details[groupKey] = {}
    if isMultiplayer() then
        return send("details", mergeControllerArgs({
            snapshotId = Client.snapshot.snapshotId,
            groupKey = groupKey,
        }))
    end
    local job = Manager.latestJob(Client.controller.networkId, Client.snapshot.snapshotId)
    if not job then Client.notifyReason("snapshotExpired"); return false end
    Client.details[groupKey] = Storage.copyInstanceDetails(job, groupKey)
    if GodSystemStorageUI and GodSystemStorageUI.onDetails then
        GodSystemStorageUI.onDetails(groupKey, Client.details[groupKey], true)
    end
    return true
end

local function localMutation(command, args)
    local p = player()
    local controller = {
        x = Client.controller.x, y = Client.controller.y, z = Client.controller.z,
        controllerItemId = Client.controller.itemId,
        controllerToken = Client.controller.token,
        networkId = Client.controller.networkId,
    }
    local ok, reason, payload
    if command == "link" then
        ok, reason, payload = Manager.linkContainer(p, controller, args)
    elseif command == "unlink" then
        ok, reason, payload = Manager.unlinkContainer(p, controller, args.linkId)
    elseif command == "updateLink" then
        ok, reason, payload = Manager.updateLink(p, controller, args)
    elseif command == "updateLimits" then
        ok, reason, payload = Manager.updateLimits(p, controller, args.radius, args.maxLinks)
    elseif command == "deposit" then
        ok, reason, payload = Manager.deposit(p, controller, args)
    elseif command == "withdraw" then
        ok, reason, payload = Manager.withdraw(p, controller, args)
    end
    if not ok then Client.notifyReason(reason) end
    if payload and GodSystemStorageUI and GodSystemStorageUI.onOperationResult then
        GodSystemStorageUI.onOperationResult(command, ok, reason, payload)
    end
    if command == "link" then
        startLocalIndex(true)
    else
        Client.refresh()
    end
    return ok, reason, payload
end

function Client.mutate(command, args)
    if not Client.controller then return false end
    if isMultiplayer() then
        for _, pending in pairs(Client.pending) do
            if pending.command == command and type(pending.args) == "table" then
                pending.retriedAtMs = Storage.nowMs()
                return send(command, pending.args)
            end
        end
    end
    args = mergeControllerArgs(args or {})
    args.opId = args.opId or Client.newOperationId(command)
    Client.pending[args.opId] = { command = command, args = args, startedAtMs = Storage.nowMs() }
    if isMultiplayer() then return send(command, args) end
    Client.pending[args.opId] = nil
    return localMutation(command, args)
end

function Client.link(target)
    return Client.mutate("link", target)
end

function Client.setNetworkContainer(target)
    target = type(target) == "table" and target or {}
    local fresh, args = beginStandalone("setNetworkContainer", target)
    if not fresh then
        if isMultiplayer() then return send("setNetworkContainer", args) end
        return false
    end
    if isMultiplayer() then return send("setNetworkContainer", args) end
    local ok, reason, payload = Manager.setNetworkContainer(player(), args)
    Client.pending[args.opId] = nil
    if not ok then Client.notifyReason(reason) end
    if GodSystemStorageContext and GodSystemStorageContext.refreshHighlights then
        GodSystemStorageContext.refreshHighlights()
    end
    if Client.controller then Client.refresh() end
    return ok, reason, payload
end

function Client.unlink(linkId)
    return Client.mutate("unlink", { linkId = linkId })
end

function Client.updateLink(args)
    return Client.mutate("updateLink", args)
end

function Client.updateLimits(radius, maxLinks)
    return Client.mutate("updateLimits", { radius = radius, maxLinks = maxLinks })
end

function Client.takeOver()
    if not Client.controller then return false end
    if isMultiplayer() then return send("takeOver", Client.controllerArgs()) end
    local network = Manager.getNetwork(Client.controller.networkId)
    if not network or not Storage.isAdmin(player()) then Client.notifyReason("adminOnly"); return false end
    network.owner = Storage.playerKey(player())
    network.creator = network.owner
    network.revision = Storage.integer(network.revision, 0) + 1
    Manager.save(network)
    Client.refresh()
    return true
end

function Client.depositItems(itemIds)
    return Client.mutate("deposit", { itemIds = itemIds or {}, safeAll = false })
end

function Client.depositAll()
    return Client.mutate("deposit", { safeAll = true })
end

function Client.withdraw(groupKey, count, targetItemId)
    return Client.mutate("withdraw", {
        snapshotId = Client.snapshot and Client.snapshot.snapshotId,
        groupKey = groupKey,
        count = count,
        targetItemId = targetItemId,
    })
end

function Client.withdrawExact(groupKey, itemId, targetItemId)
    return Client.mutate("withdraw", {
        snapshotId = Client.snapshot and Client.snapshot.snapshotId,
        groupKey = groupKey,
        itemId = itemId,
        count = 1,
        targetItemId = targetItemId,
    })
end

function Client.onServerCommand(module, command, args)
    if module ~= MODULE then return end
    args = args or {}
    if command == "claimResult" then
        if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_Notify_ControllerClaimed", "Storage controller received")) end
        return
    end
    if command == "controllerStatus" then
        Client.claimState = args
        if args.state ~= "installed" and args.state ~= "legacyGround" then
            Client.controller = nil
            Client.networkState = nil
        end
        Client.statusRequestedAtMs = Storage.nowMs()
        refreshGodSystemStoragePage()
        return
    end
    if command == "networkState" then
        Client.networkState = args
        if GodSystemStorageUI and GodSystemStorageUI.onNetworkState then GodSystemStorageUI.onNetworkState(args) end
        if GodSystemStorageContext and GodSystemStorageContext.refreshHighlights then
            GodSystemStorageContext.refreshHighlights()
        end
        return
    end
    if command == "indexStarted" then
        Client.indexing = true
        if GodSystemStorageUI and GodSystemStorageUI.onIndexStarted then GodSystemStorageUI.onIndexStarted(args) end
        return
    end
    if command == "snapshotBegin" then
        Client.snapshotBuilding = {
            kind = "storageSnapshot",
            snapshotId = args.snapshotId,
            networkId = args.networkId,
            revision = args.revision,
            groups = {},
        }
        return
    end
    if command == "snapshotChunk" then
        local building = Client.snapshotBuilding
        if building and tostring(building.snapshotId) == tostring(args.snapshotId) then
            for i = 1, #((args.groups) or {}) do building.groups[#building.groups + 1] = args.groups[i] end
        end
        return
    end
    if command == "snapshotEnd" then
        local building = Client.snapshotBuilding
        if building and tostring(building.snapshotId) == tostring(args.snapshotId) then
            for key, value in pairs(args) do if key ~= "groups" then building[key] = value end end
            Client.indexing = false
            Client.applySnapshot(building)
        end
        return
    end
    if command == "details" then
        local key = tostring(args.groupKey or "")
        Client.details[key] = Client.details[key] or {}
        for i = 1, #((args.instances) or {}) do Client.details[key][#Client.details[key] + 1] = args.instances[i] end
        if GodSystemStorageUI and GodSystemStorageUI.onDetails then
            GodSystemStorageUI.onDetails(key, Client.details[key], args.complete == true)
        end
        return
    end
    if command == "operationResult" then
        local opId = tostring(args.opId or "")
        Client.pending[opId] = nil
        if args.ok ~= true then Client.notifyReason(args.reason) end
        if args.command == "claimController" or args.command == "installController" or args.command == "reclaimController" then
            if args.ok == true and type(args.payload) == "table" and args.payload.state then
                local nextState = Client.claimState or {}
                nextState.state = tostring(args.payload.state)
                nextState.networkId = args.payload.networkId or nextState.networkId
                nextState.controllerItemId = args.payload.controllerItemId
                nextState.claimedOnce = true
                nextState.recoveryCost = Storage.ControllerRecoveryCost
                nextState.nextCost = Storage.ControllerRecoveryCost
                nextState.controller = args.payload.controller
                Client.claimState = nextState
            end
            if args.command == "reclaimController" and args.ok == true then Client.controller = nil end
            Client.requestControllerStatus(true)
            refreshGodSystemStoragePage()
        end
        if args.command == "setNetworkContainer" then
            if GodSystemStorageContext and GodSystemStorageContext.refreshHighlights then
                GodSystemStorageContext.refreshHighlights()
            end
            if args.ok == true and Client.controller then Client.refresh() end
        end
        if GodSystemStorageUI and GodSystemStorageUI.onOperationResult then
            GodSystemStorageUI.onOperationResult(args.command, args.ok == true, args.reason, args.payload)
        end
        return
    end
    if command == "notify" then
        if GodSystem and GodSystem.notify then
            local key = "Storage_Notify_" .. tostring(args.code or "")
            GodSystem.notify(text(key, tostring(args.code or "")))
        end
        return
    end
    if command == "error" then
        Client.lastError = args.reason
        Client.notifyReason(args.reason)
        if GodSystemStorageUI and GodSystemStorageUI.onError then GodSystemStorageUI.onError(args) end
    end
end

function Client.onTick()
    if not isMultiplayer() then Manager.processJobs() end
end

function Client.reset()
    Client.snapshot = nil
    Client.snapshotBuilding = nil
    Client.details = {}
    Client.controller = nil
    Client.pending = {}
    Client.networkState = nil
    Client.claimState = nil
    Client.statusRequestedAtMs = 0
    if GodSystemStorageUI and GodSystemStorageUI.close then GodSystemStorageUI.close() end
end

Events.OnServerCommand.Remove(Client.onServerCommand)
Events.OnServerCommand.Add(Client.onServerCommand)
Events.OnTick.Remove(Client.onTick)
Events.OnTick.Add(Client.onTick)
if Events.OnDisconnect then
    Events.OnDisconnect.Remove(Client.reset)
    Events.OnDisconnect.Add(Client.reset)
end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Remove(Client.reset)
    Events.OnMainMenuEnter.Add(Client.reset)
end

return Client
