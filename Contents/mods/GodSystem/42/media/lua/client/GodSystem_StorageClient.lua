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
        networkId = current.networkId,
    }
end

local function mergeControllerArgs(args)
    local result = Client.controllerArgs()
    for key, value in pairs(args or {}) do result[key] = value end
    return result
end

function Client.setController(item, x, y, z)
    local networkId, token = Storage.getControllerIdentity(item)
    if not networkId or networkId == "" or not token or token == "" then return false end
    Client.controller = {
        x = Storage.integer(x, 0),
        y = Storage.integer(y, 0),
        z = Storage.integer(z, 0),
        itemId = Storage.itemId(item),
        token = token,
        networkId = networkId,
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

function Client.claimController()
    if isMultiplayer() then return send("claimController", {}) end
    local ok, reason, payload = Manager.claimController(player())
    if not ok then Client.notifyReason(reason); return false end
    if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_Notify_ControllerClaimed", "Storage controller received")) end
    return true, payload
end

function Client.open(item, x, y, z)
    if not Client.setController(item, x, y, z) then
        Client.notifyReason("controllerInvalid")
        return false
    end
    Client.snapshot = nil
    Client.snapshotBuilding = nil
    if GodSystemStorageUI and GodSystemStorageUI.open then GodSystemStorageUI.open() end
    if isMultiplayer() then return send("open", Client.controllerArgs()) end
    return startLocalIndex()
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
    if command == "networkState" then
        Client.networkState = args
        if GodSystemStorageUI and GodSystemStorageUI.onNetworkState then GodSystemStorageUI.onNetworkState(args) end
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
