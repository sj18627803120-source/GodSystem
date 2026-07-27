require "GodSystem_StorageManager"

GodSystemStorageClient = GodSystemStorageClient or {}

local Client = GodSystemStorageClient
local Storage = GodSystemStorage
local Manager = GodSystemStorageManager
local MODULE = Storage.Module

Client.snapshot = Client.snapshot or nil
Client.snapshotBuilding = Client.snapshotBuilding or nil
Client.details = Client.details or {}
Client.core = Client.core or nil
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
    coreMissing = { "Storage_Error_CoreMissing", "Storage core is missing" },
    coreHostMissing = { "Storage_Error_CoreHostMissing", "Storage core host is missing" },
    coreInvalid = { "Storage_Error_CoreInvalid", "Storage core identity is invalid" },
    coreChanged = { "Storage_Error_CoreChanged", "Storage core host changed" },
    coreExpired = { "Storage_Error_CoreExpired", "This storage core has expired; recover it from the God System page" },
    coreOwned = { "Storage_Error_CoreOwned", "A valid storage core is already in your inventory" },
    coreInstalled = { "Storage_Error_CoreInstalled", "A storage core is already installed" },
    networkContainerRequired = { "Storage_Error_NetworkContainerRequired", "Mark this furniture as a network container first" },
    capacityRestoreFailed = { "Storage_Error_CapacityRestoreFailed", "The host capacity could not be restored" },
    coreConsumeFailed = { "Storage_Error_CoreConsumeFailed", "The storage core could not be consumed" },
    coreReturnFailed = { "Storage_Error_CoreReturnFailed", "The storage core could not be returned; the host was unlocked" },
    currencyNotEnough = { "Storage_Error_CurrencyNotEnough", "Not enough system coins" },
    economyUnavailable = { "Storage_Error_EconomyUnavailable", "The system coin service is unavailable" },
    tooFar = { "Storage_Error_TooFar", "Move closer to the storage core host" },
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

function Client.hasPendingOperation(command)
    for _, pending in pairs(Client.pending or {}) do
        if pending.command == command then return true end
    end
    return false
end

function Client.coreArgs()
    local current = Client.core or {}
    return {
        x = current.x,
        y = current.y,
        z = current.z,
        coreX = current.x,
        coreY = current.y,
        coreZ = current.z,
        coreItemId = current.itemId,
        coreToken = current.token,
        coreObjectId = current.objectId,
        networkId = current.networkId,
    }
end

local function mergeCoreArgs(args)
    local result = Client.coreArgs()
    for key, value in pairs(args or {}) do result[key] = value end
    return result
end

function Client.setCoreHost(x, y, z, object)
    local marker = object and Storage.getCoreHostMarker(object) or nil
    local networkId = marker and tostring(marker.networkId or "") or ""
    local token = marker and tostring(marker.token or "") or ""
    if not networkId or networkId == "" or not token or token == "" then return false end
    local objectId = tostring(marker.objectId or "")
    if Client.core and tostring(Client.core.networkId or "") ~= tostring(networkId) then
        Client.networkState = nil
        Client.snapshot = nil
    end
    Client.core = {
        x = Storage.integer(x, 0),
        y = Storage.integer(y, 0),
        z = Storage.integer(z, 0),
        itemId = nil,
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
        x = Client.core.x, y = Client.core.y, z = Client.core.z,
        coreToken = Client.core.token,
        coreObjectId = Client.core.objectId,
        networkId = Client.core.networkId,
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

function Client.requestCoreStatus(force)
    local now = Storage.nowMs()
    if force ~= true and Client.claimState and now - (Client.statusRequestedAtMs or 0) < 1500 then
        return Client.claimState
    end
    Client.statusRequestedAtMs = now
    if isMultiplayer() then
        send("coreStatus", {})
        return Client.claimState
    end
    local status, reason = Manager.coreStatus(player())
    if not status then Client.notifyReason(reason); return nil end
    Client.claimState = status
    if status.state ~= "installed" then
        Client.core = nil
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

function Client.claimCore(forceRecovery)
    local fresh, args = beginStandalone("claimCore", { forceRecovery = forceRecovery == true })
    if not fresh then
        if isMultiplayer() then return send("claimCore", args) end
        return false
    end
    if isMultiplayer() then return send("claimCore", args) end
    local ok, reason, payload = Manager.claimCore(player(), {
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
    Client.requestCoreStatus(true)
    if GodSystem and GodSystem.notify then
        GodSystem.notify(text(payload and payload.recovered and "Storage_Notify_CoreRecovered" or "Storage_Notify_CoreClaimed", "Storage core received"))
    end
    return true, payload
end

local function findCarriedCore()
    local status = Client.claimState or {}
    local inventory = Storage.safeCall(player(), "getInventory", nil)
    if not inventory then return nil end
    local expectedId = tostring(status.coreItemId or "")
    if expectedId ~= "" then
        local item = Storage.findItemRecursive(inventory, expectedId)
        if item and Storage.isCore(item) then return item end
    end
    local seen = {}
    local function visit(container, depth)
        if not container or seen[container] or depth > Storage.MaxDepth then return nil end
        seen[container] = true
        local items = Storage.safeCall(container, "getItems", nil)
        local size = Storage.integer(Storage.safeCall(items, "size", 0), 0)
        for i = 0, size - 1 do
            local item = Storage.safeCall(items, "get", nil, i)
            local networkId, token = Storage.getCoreIdentity(item)
            if Storage.isCore(item) and tostring(networkId or "") ~= "" and tostring(token or "") ~= "" then
                return item
            end
            local nested = visit(Storage.safeCall(item, "getInventory", nil), depth + 1)
            if nested then return nested end
        end
        return nil
    end
    return visit(inventory, 0)
end

Client.findCarriedCore = findCarriedCore

function Client.installCore(target)
    target = type(target) == "table" and target or {}
    local item = findCarriedCore()
    if not item then Client.notifyReason("coreMissing"); return false end
    local networkId, token = Storage.getCoreIdentity(item)
    target.networkId = networkId
    target.coreToken = token
    target.coreItemId = Storage.itemId(item)
    local fresh, args = beginStandalone("installCore", target)
    if not fresh then
        if isMultiplayer() then return send("installCore", args) end
        return false
    end
    if isMultiplayer() then return send("installCore", args) end
    local ok, reason, payload = Manager.installCore(player(), args)
    Client.pending[args.opId] = nil
    if not ok then Client.notifyReason(reason); return false end
    Client.requestCoreStatus(true)
    if GodSystem and GodSystem.notify then
        GodSystem.notify(text("Storage_Notify_CoreInstalled", "Storage core installed"))
    end
    return true, payload
end

function Client.open(x, y, z, object)
    if not Client.setCoreHost(x, y, z, object) then
        Client.notifyReason("coreInvalid")
        return false
    end
    Client.snapshot = nil
    Client.snapshotBuilding = nil
    if GodSystemStorageUI and GodSystemStorageUI.open then GodSystemStorageUI.open() end
    if isMultiplayer() then return send("open", Client.coreArgs()) end
    return startLocalIndex()
end

function Client.retrieveCore(x, y, z, object)
    if not Client.setCoreHost(x, y, z, object) then
        Client.notifyReason("coreInvalid")
        return false
    end
    local args = Client.coreArgs()
    local fresh
    fresh, args = beginStandalone("retrieveCore", args)
    if not fresh then
        if isMultiplayer() then return send("retrieveCore", args) end
        return false
    end
    if isMultiplayer() then return send("retrieveCore", args) end
    local ok, reason, payload = Manager.retrieveCore(player(), args)
    Client.pending[args.opId] = nil
    if not ok then Client.notifyReason(reason); return false end
    Client.core = nil
    Client.requestCoreStatus(true)
    if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_Notify_CoreRetrieved", "Storage core retrieved")) end
    return true, payload
end

function Client.refresh()
    if not Client.core then return false end
    if isMultiplayer() then return send("refresh", Client.coreArgs()) end
    return startLocalIndex()
end

function Client.requestDetails(groupKey)
    if not Client.snapshot then return false end
    groupKey = tostring(groupKey or "")
    Client.details[groupKey] = {}
    if isMultiplayer() then
        return send("details", mergeCoreArgs({
            snapshotId = Client.snapshot.snapshotId,
            groupKey = groupKey,
        }))
    end
    local job = Manager.latestJob(Client.core.networkId, Client.snapshot.snapshotId)
    if not job then Client.notifyReason("snapshotExpired"); return false end
    Client.details[groupKey] = Storage.copyInstanceDetails(job, groupKey)
    if GodSystemStorageUI and GodSystemStorageUI.onDetails then
        GodSystemStorageUI.onDetails(groupKey, Client.details[groupKey], true)
    end
    return true
end

local function localMutation(command, args)
    local p = player()
    local core = {
        x = Client.core.x, y = Client.core.y, z = Client.core.z,
        coreObjectId = Client.core.objectId,
        coreToken = Client.core.token,
        networkId = Client.core.networkId,
    }
    local ok, reason, payload
    if command == "link" then
        ok, reason, payload = Manager.linkContainer(p, core, args)
    elseif command == "unlink" then
        ok, reason, payload = Manager.unlinkContainer(p, core, args.linkId)
    elseif command == "updateLink" then
        ok, reason, payload = Manager.updateLink(p, core, args)
    elseif command == "updateLimits" then
        ok, reason, payload = Manager.updateLimits(p, core, args.radius, args.maxLinks)
    elseif command == "deposit" then
        ok, reason, payload = Manager.deposit(p, core, args)
    elseif command == "withdraw" then
        ok, reason, payload = Manager.withdraw(p, core, args)
    end
    if not ok then Client.notifyReason(reason) end
    if GodSystemStorageUI and GodSystemStorageUI.onOperationResult then
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
    if not Client.core then return false end
    if isMultiplayer() then
        for _, pending in pairs(Client.pending) do
            if pending.command == command and type(pending.args) == "table" then
                pending.retriedAtMs = Storage.nowMs()
                return send(command, pending.args)
            end
        end
    end
    args = mergeCoreArgs(args or {})
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
    if Client.core then Client.refresh() end
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
    if not Client.core then return false end
    if isMultiplayer() then return send("takeOver", Client.coreArgs()) end
    local network = Manager.getNetwork(Client.core.networkId)
    if not network or not Storage.isAdmin(player()) then Client.notifyReason("adminOnly"); return false end
    network.owner = Storage.playerKey(player())
    network.creator = network.owner
    network.revision = Storage.integer(network.revision, 0) + 1
    Manager.save(network)
    Client.refresh()
    return true
end

function Client.depositItems(itemIds, sourceItemId)
    return Client.mutate("deposit", {
        mode = "selected",
        sourceItemId = sourceItemId,
        itemIds = itemIds or {},
    })
end

function Client.depositAll(sourceItemId)
    return Client.mutate("deposit", {
        mode = "sourceAll",
        sourceItemId = sourceItemId,
    })
end

function Client.withdrawRequests(requests, targetItemId)
    return Client.mutate("withdraw", {
        snapshotId = Client.snapshot and Client.snapshot.snapshotId,
        requests = requests or {},
        targetItemId = targetItemId,
    })
end

function Client.withdraw(groupKey, count, targetItemId)
    return Client.withdrawRequests({ { groupKey = groupKey, count = count } }, targetItemId)
end

function Client.withdrawExact(groupKey, itemId, targetItemId)
    return Client.withdrawRequests({ { groupKey = groupKey, itemIds = { itemId } } }, targetItemId)
end

function Client.onServerCommand(module, command, args)
    if module ~= MODULE then return end
    args = args or {}
    if command == "coreStatus" then
        Client.claimState = args
        if args.state ~= "installed" then
            Client.core = nil
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
        if args.command == "claimCore" or args.command == "installCore" or args.command == "retrieveCore" then
            if args.ok == true and type(args.payload) == "table" and args.payload.state then
                local nextState = Client.claimState or {}
                nextState.state = tostring(args.payload.state)
                nextState.networkId = args.payload.networkId or nextState.networkId
                nextState.coreItemId = args.payload.coreItemId
                nextState.claimedOnce = true
                nextState.recoveryCost = Storage.CoreRecoveryCost
                nextState.nextCost = Storage.CoreRecoveryCost
                nextState.coreHost = args.payload.coreHost
                Client.claimState = nextState
            end
            if args.command == "retrieveCore" and args.ok == true then Client.core = nil end
            Client.requestCoreStatus(true)
            refreshGodSystemStoragePage()
        end
        if args.command == "setNetworkContainer" then
            if GodSystemStorageContext and GodSystemStorageContext.refreshHighlights then
                GodSystemStorageContext.refreshHighlights()
            end
            if args.ok == true and Client.core then Client.refresh() end
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
    Client.core = nil
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
