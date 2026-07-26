require "GodSystem_StorageManager"

if not (isServer and isServer()) then return end

GodSystemStorageServer = GodSystemStorageServer or {}

local Server = GodSystemStorageServer
local Storage = GodSystemStorage
local Manager = GodSystemStorageManager
local MODULE = Storage.Module

local function send(player, command, args)
    if player and sendServerCommand then
        sendServerCommand(player, MODULE, command, args or {})
    end
end

local function notify(player, code, args)
    send(player, "notify", { code = tostring(code or ""), args = args or {} })
end

local function fail(player, command, reason, payload)
    send(player, "error", {
        command = tostring(command or ""),
        reason = tostring(reason or "unknown"),
        payload = payload,
    })
end

local function controllerArgs(args)
    return {
        x = args and args.controllerX,
        y = args and args.controllerY,
        z = args and args.controllerZ,
        controllerItemId = args and args.controllerItemId,
        controllerToken = args and args.controllerToken,
        networkId = args and args.networkId,
    }
end

local function sendNetworkState(player, network)
    if not network then return end
    send(player, "networkState", Manager.networkSummary(player, network))
end

local function sendSnapshot(player, job, snapshot)
    send(player, "snapshotBegin", {
        snapshotId = snapshot.snapshotId,
        networkId = snapshot.networkId,
        revision = snapshot.revision,
    })
    local chunk = {}
    for i = 1, #(snapshot.groups or {}) do
        chunk[#chunk + 1] = snapshot.groups[i]
        if #chunk >= Storage.SnapshotGroupChunk then
            send(player, "snapshotChunk", {
                snapshotId = snapshot.snapshotId,
                groups = chunk,
            })
            chunk = {}
        end
    end
    if #chunk > 0 then
        send(player, "snapshotChunk", {
            snapshotId = snapshot.snapshotId,
            groups = chunk,
        })
    end
    local finish = {}
    for key, value in pairs(snapshot) do
        if key ~= "groups" then finish[key] = value end
    end
    send(player, "snapshotEnd", finish)
end

local function startIndex(player, args, allowRemote)
    local resolvedController = controllerArgs(args)
    resolvedController.allowRemote = allowRemote == true
    local ok, reason, job = Manager.startIndex(player, resolvedController, function(completed, snapshot)
        sendSnapshot(player, completed, snapshot)
    end)
    if not ok then fail(player, "refresh", reason); return false end
    sendNetworkState(player, job.network)
    send(player, "indexStarted", {
        jobId = job.jobId,
        networkId = job.network.networkId,
        revision = job.network.revision,
    })
    return true
end

local function fingerprint(command, args)
    local parts = {
        tostring(command or ""),
        tostring(args and args.networkId or ""),
        tostring(args and args.controllerItemId or ""),
        tostring(args and args.controllerToken or ""),
        tostring(args and args.controllerX or ""),
        tostring(args and args.controllerY or ""),
        tostring(args and args.controllerZ or ""),
        tostring(args and args.snapshotId or ""),
        tostring(args and args.groupKey or ""),
        tostring(args and args.count or ""),
        tostring(args and args.linkId or ""),
        tostring(args and args.safeAll == true),
        tostring(args and args.x or ""),
        tostring(args and args.y or ""),
        tostring(args and args.z or ""),
        tostring(args and args.objectIndex or ""),
        tostring(args and args.slotIndex or ""),
        tostring(args and args.sprite or ""),
        tostring(args and args.name or ""),
        tostring(args and args.role or ""),
        tostring(args and args.priority or ""),
        tostring(args and args.targetItemId or ""),
        tostring(args and args.itemId or ""),
        tostring(args and args.radius or ""),
        tostring(args and args.maxLinks or ""),
    }
    for i = 1, #((args and args.itemIds) or {}) do parts[#parts + 1] = tostring(args.itemIds[i]) end
    for i = 1, #Storage.Categories do
        local category = Storage.Categories[i]
        parts[#parts + 1] = "a:" .. category .. ":" .. tostring(type(args and args.allowCategories) == "table" and args.allowCategories[category] == true)
        parts[#parts + 1] = "d:" .. category .. ":" .. tostring(type(args and args.denyCategories) == "table" and args.denyCategories[category] == true)
    end
    return table.concat(parts, "|")
end

local function operation(player, command, args, fn)
    local opId = tostring(args and args.opId or "")
    local fp = fingerprint(command, args)
    local row, status = Manager.beginOperation(player, opId, fp)
    if not row then fail(player, command, status); return end
    if status == "done" then
        send(player, "operationResult", {
            command = command,
            opId = opId,
            ok = row.ok == true,
            reason = row.reason,
            payload = row.payload,
            replay = true,
        })
        return
    end
    if status == "pending" then fail(player, command, "operationPending", { opId = opId }); return end
    local okCall, ok, reason, payload = pcall(fn)
    if not okCall then
        ok, reason, payload = false, "internalError", { detail = tostring(ok) }
    end
    Manager.finishOperation(row, ok, reason, payload)
    send(player, "operationResult", {
        command = command,
        opId = opId,
        ok = ok == true,
        reason = reason,
        payload = payload,
    })
    if ok then startIndex(player, args, command == "link") end
end

local Commands = {}

function Commands.claimController(player)
    local ok, reason, payload = Manager.claimController(player)
    if not ok then fail(player, "claimController", reason); return end
    send(player, "claimResult", payload)
    if sendServerCommand then pcall(sendServerCommand, player, "ui", "DirtyUI", {}) end
    notify(player, "controllerClaimed")
end

function Commands.open(player, args)
    startIndex(player, args)
end

function Commands.refresh(player, args)
    startIndex(player, args)
end

function Commands.details(player, args)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs(args))
    if not network then fail(player, "details", reason); return end
    local job = Manager.latestJob(network.networkId, args.snapshotId)
    if not job then fail(player, "details", "snapshotExpired"); return end
    local instances = Storage.copyInstanceDetails(job, args.groupKey)
    local chunkSize = 100
    for i = 1, math.max(1, math.ceil(#instances / chunkSize)) do
        local chunk = {}
        local first = ((i - 1) * chunkSize) + 1
        for j = first, math.min(#instances, first + chunkSize - 1) do chunk[#chunk + 1] = instances[j] end
        send(player, "details", {
            snapshotId = job.snapshot.snapshotId,
            groupKey = tostring(args.groupKey or ""),
            instances = chunk,
            complete = first + chunkSize - 1 >= #instances,
        })
    end
end

function Commands.link(player, args)
    operation(player, "link", args, function()
        return Manager.linkContainer(player, controllerArgs(args), {
            x = args.x, y = args.y, z = args.z,
            objectIndex = args.objectIndex,
            slotIndex = args.slotIndex,
            sprite = args.sprite,
            name = args.name,
            role = args.role,
            priority = args.priority,
        })
    end)
end

function Commands.unlink(player, args)
    operation(player, "unlink", args, function()
        return Manager.unlinkContainer(player, controllerArgs(args), args.linkId)
    end)
end

function Commands.updateLink(player, args)
    operation(player, "updateLink", args, function()
        return Manager.updateLink(player, controllerArgs(args), args)
    end)
end

function Commands.updateLimits(player, args)
    operation(player, "updateLimits", args, function()
        return Manager.updateLimits(player, controllerArgs(args), args.radius, args.maxLinks)
    end)
end

function Commands.deposit(player, args)
    operation(player, "deposit", args, function()
        return Manager.deposit(player, controllerArgs(args), args)
    end)
end

function Commands.withdraw(player, args)
    operation(player, "withdraw", args, function()
        return Manager.withdraw(player, controllerArgs(args), args)
    end)
end

function Commands.takeOver(player, args)
    local network, _, _, reason = Manager.resolveController(player, controllerArgs(args))
    if not network then fail(player, "takeOver", reason); return end
    if not Storage.isAdmin(player) then fail(player, "takeOver", "adminOnly"); return end
    network.owner = Storage.playerKey(player)
    network.creator = network.owner
    network.revision = Storage.integer(network.revision, 0) + 1
    Manager.save(network)
    sendNetworkState(player, network)
    notify(player, "networkTakenOver")
end

function Server.onClientCommand(module, command, player, args)
    if module ~= MODULE or not player then return end
    local fn = Commands[tostring(command or "")]
    if not fn then fail(player, command, "unknownCommand"); return end
    local ok, err = pcall(fn, player, args or {})
    if not ok then
        print("[GodSystemStorage] command '" .. tostring(command) .. "' failed: " .. tostring(err))
        fail(player, command, "internalError", { detail = tostring(err) })
    end
end

function Server.onTick()
    Manager.processJobs()
end

function Server.onInitGlobalModData()
    Manager.getStore()
    Manager.pruneOperations()
end

Events.OnClientCommand.Remove(Server.onClientCommand)
Events.OnClientCommand.Add(Server.onClientCommand)
Events.OnTick.Remove(Server.onTick)
Events.OnTick.Add(Server.onTick)
if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Remove(Server.onInitGlobalModData)
    Events.OnInitGlobalModData.Add(Server.onInitGlobalModData)
end

return Server
