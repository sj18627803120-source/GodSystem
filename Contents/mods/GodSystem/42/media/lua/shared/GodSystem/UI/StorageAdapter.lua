GodSystemUIStorageAdapter = GodSystemUIStorageAdapter or {}

local StorageAdapter = GodSystemUIStorageAdapter

local MUTATION_NAMES = {
    "claimCore", "installCore", "retrieveCore", "link",
    "setNetworkContainer", "unlink", "updateLink", "updateLimits",
    "startOrganizer", "stopOrganizer", "takeOver",
    "depositItems", "depositAll", "withdrawRequests", "withdraw",
    "withdrawExact",
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

function StorageAdapter.new(options)
    options = type(options) == "table" and options or {}
    local facade = assert(options.facade, "storage facade required")
    local target = assert(options.target, "storage client target required")
    local storage = assert(options.storage, "storage helpers required")
    local ui = options.ui
    local context = options.context
    local now = type(options.now) == "function"
        and options.now or function() return storage.nowMs() end
    local originals = {}
    local instance = {
        installed = false,
        snapshotId = nil,
        nextSnapshotPollAt = 0,
        nextOrganizerPollAt = 0,
        indexing = false,
    }

    local function notify(code)
        target.lastError = tostring(code or "")
        target.notifyReason(code)
        if ui and ui.onError then ui.onError({ reason = code }) end
    end

    local function publishNetworkState(value)
        target.networkState = type(value) == "table"
            and value or { connectedObjectIds = {} }
        if ui and ui.onNetworkState then ui.onNetworkState(target.networkState) end
        if context and context.refreshHighlights then context.refreshHighlights() end
        return true
    end

    local function publishOrganizer(value)
        target.organizer = type(value) == "table" and value or { state = "idle" }
        if ui and ui.onOrganizerStatus then
            ui.onOrganizerStatus(target.organizer)
        end
        return true
    end

    local function objectReference(args)
        local source = type(args) == "table" and args or {}
        local object = source.object
        args = copy(source)
        if object then
            local position = storage.objectCoordinates(object)
            local objectId = storage.getObjectId(object, true)
            if position and objectId then
                args.objectId = tostring(objectId)
                args.x, args.y, args.z = position.x, position.y, position.z
                args.sprite = storage.objectSpriteName(object)
                args.object = {
                    objectId = tostring(objectId),
                    x = position.x,
                    y = position.y,
                    z = position.z,
                    sprite = args.sprite,
                    name = tostring(args.name or ""),
                }
                return args
            end
        end
        if tostring(args.objectId or "") ~= "" then
            args.object = {
                objectId = tostring(args.objectId),
                x = args.x,
                y = args.y,
                z = args.z,
                sprite = args.sprite,
                name = tostring(args.name or ""),
            }
        end
        return args
    end

    local function coreArgs(args)
        local result = copy(target.coreArgs and target.coreArgs() or {})
        for key, value in pairs(type(args) == "table" and args or {}) do
            result[key] = value
        end
        return result
    end

    local function request(route, args, callback, operationId)
        local primary, secondary = facade:request(route, args, {
            operationId = operationId,
            callback = callback,
        })
        local value = type(primary) == "table" and primary or secondary
        return type(value) == "table"
            and (value.ok == true or value.code == "requestPending")
    end

    local function requestNetworkState()
        return request("storage.networkState", coreArgs(), function(result)
            if result.ok then publishNetworkState(result.data)
            elseif result.code ~= "networkMissing"
                and result.code ~= "coreHostMissing"
            then
                notify(result.code)
            end
        end)
    end

    local function requestCoreStatus(force)
        local timestamp = now()
        if force ~= true and target.claimState
            and timestamp - (target.statusRequestedAtMs or 0) < 1500
        then
            return target.claimState
        end
        target.statusRequestedAtMs = timestamp
        request("storage.status", {}, function(result)
            if not result.ok then
                if result.code ~= "networkMissing" then notify(result.code) end
                return
            end
            local data = copy(result.data or {})
            data.recoveryCost = data.nextCost
            target.claimState = data
            target.statusRequestedAtMs = now()
            if data.state ~= "installed" then
                target.core = nil
                target.networkState = nil
            end
            if GodSystemUI and GodSystemUI.window
                and GodSystemUI.window.mode == "storage"
                and GodSystemUI.window.requestDeferredPopulate
            then
                GodSystemUI.window:requestDeferredPopulate(1)
            end
        end)
        return target.claimState
    end

    local function pollSnapshot()
        if not instance.snapshotId then return false end
        if facade.gateway:isPending("storage.snapshot") then return false end
        return request("storage.snapshot", {
            snapshotId = instance.snapshotId,
        }, function(result)
            if not result.ok then
                instance.snapshotId = nil
                instance.indexing = false
                target.indexing = false
                notify(result.code)
                return
            end
            if result.data and result.data.pending == true then
                instance.nextSnapshotPollAt = now() + 100
                return
            end
            instance.snapshotId = nil
            instance.indexing = false
            target.indexing = false
            target.applySnapshot(result.data)
            requestNetworkState()
        end)
    end

    local function startIndex()
        if not target.core then return false end
        target.snapshot = nil
        target.snapshotBuilding = nil
        target.indexing = true
        instance.indexing = true
        return request("storage.index", coreArgs(), function(result)
            if not result.ok then
                target.indexing = false
                instance.indexing = false
                notify(result.code)
                return
            end
            instance.snapshotId = result.data and result.data.snapshotId or nil
            instance.nextSnapshotPollAt = 0
            if ui and ui.onIndexStarted then ui.onIndexStarted(result.data or {}) end
        end)
    end

    local function completeMutation(command, operationId, result, after)
        target.pending[operationId] = nil
        if not result.ok then notify(result.code) end
        if ui and ui.onOperationResult then
            ui.onOperationResult(command, result.ok == true,
                result.code, result.data)
        end
        if result.ok and type(after) == "function" then after(result.data or {}) end
    end

    local function mutation(command, action, args, after)
        if target.hasPendingOperation
            and target.hasPendingOperation(command)
        then
            target.notifyReason("operationPending")
            return false
        end
        local operationId = target.newOperationId(command)
        args = coreArgs(args)
        args.action = action
        target.pending[operationId] = {
            command = command,
            args = copy(args),
            startedAtMs = now(),
        }
        return request("storage.execute", args, function(result)
            completeMutation(command, operationId, result, after)
        end, operationId)
    end

    local function refreshAfterContainerChange()
        requestNetworkState()
        if target.core then startIndex() end
    end

    local replacements = {}

    replacements.requestCoreStatus = requestCoreStatus

    replacements.claimCore = function(forceRecovery)
        return mutation("claimCore", "claimCore", {
            forceRecovery = forceRecovery == true,
        }, function()
            requestCoreStatus(true)
        end)
    end

    replacements.installCore = function(args)
        args = objectReference(args)
        local carried = target.findCarriedCore and target.findCarriedCore() or nil
        if not carried then notify("coreMissing"); return false end
        args.coreItemId = storage.itemId(carried)
        return mutation("installCore", "installCore", args, function(data)
            requestCoreStatus(true)
            if data.coreHost then
                target.core = {
                    x = data.coreHost.x,
                    y = data.coreHost.y,
                    z = data.coreHost.z,
                    token = args.coreToken,
                    networkId = data.networkId or args.networkId,
                    objectId = data.coreHost.objectId,
                }
            end
            requestNetworkState()
        end)
    end

    replacements.retrieveCore = function(x, y, z, object)
        if not target.setCoreHost(x, y, z, object) then
            notify("coreInvalid")
            return false
        end
        return mutation("retrieveCore", "retrieveCore", {}, function()
            target.core = nil
            requestCoreStatus(true)
        end)
    end

    replacements.open = function(x, y, z, object)
        if not target.setCoreHost(x, y, z, object) then
            notify("coreInvalid")
            return false
        end
        target.snapshot = nil
        target.snapshotBuilding = nil
        if ui and ui.open then ui.open() end
        requestNetworkState()
        return startIndex()
    end

    replacements.refresh = startIndex
    replacements.refreshNetworkState = requestNetworkState

    replacements.requestDetails = function(groupKey)
        if not target.snapshot then return false end
        groupKey = tostring(groupKey or "")
        target.details[groupKey] = {}
        return request("storage.details", {
            snapshotId = target.snapshot.snapshotId,
            groupKey = groupKey,
        }, function(result)
            if not result.ok then notify(result.code); return end
            target.details[groupKey] = copy(
                result.data and result.data.instances or {})
            if ui and ui.onDetails then
                ui.onDetails(groupKey, target.details[groupKey], true)
            end
        end)
    end

    replacements.setNetworkContainer = function(args)
        args = objectReference(args)
        return mutation("setNetworkContainer", "setNetworkContainer", args,
            refreshAfterContainerChange)
    end

    replacements.link = function(args)
        args = objectReference(args)
        args.enabled = true
        return mutation("setNetworkContainer", "setNetworkContainer", args,
            refreshAfterContainerChange)
    end

    replacements.unlink = function(linkId)
        return mutation("unlink", "removeNetworkContainer", {
            linkId = linkId,
        }, refreshAfterContainerChange)
    end

    replacements.updateLink = function(args)
        return mutation("updateLink", "updateContainer", args, function()
            startIndex()
        end)
    end

    replacements.updateLimits = function()
        notify("actionInvalid")
        return false
    end

    replacements.startOrganizer = function()
        return mutation("organizerStart", "startOrganizer", {}, function()
            publishOrganizer({ state = "running" })
            instance.nextOrganizerPollAt = 0
        end)
    end

    replacements.stopOrganizer = function()
        return mutation("organizerStop", "stopOrganizer", {}, function(data)
            publishOrganizer(data and data.state and data or { state = "idle" })
            startIndex()
        end)
    end

    replacements.requestOrganizerStatus = function()
        if not target.core then return false end
        return request("storage.organizerStatus", coreArgs(), function(result)
            if result.ok then
                local previous = target.organizer and target.organizer.state
                publishOrganizer(result.data)
                if previous == "running"
                    and target.organizer.state ~= "running"
                then
                    startIndex()
                end
            else
                notify(result.code)
            end
        end)
    end

    replacements.takeOver = function()
        return mutation("takeOver", "takeOver", {}, function()
            requestNetworkState()
            startIndex()
        end)
    end

    replacements.depositItems = function(itemIds, sourceItemId)
        return mutation("deposit", "deposit", {
            mode = "selected",
            sourceItemId = sourceItemId,
            itemIds = itemIds or {},
        }, startIndex)
    end

    replacements.depositAll = function(sourceItemId)
        return mutation("deposit", "deposit", {
            mode = "sourceAll",
            sourceItemId = sourceItemId,
        }, startIndex)
    end

    replacements.withdrawRequests = function(requests, targetItemId)
        return mutation("withdraw", "withdraw", {
            snapshotId = target.snapshot and target.snapshot.snapshotId,
            requests = requests or {},
            targetItemId = targetItemId,
        }, startIndex)
    end

    replacements.withdraw = function(groupKey, count, targetItemId)
        return replacements.withdrawRequests({
            { groupKey = groupKey, count = count },
        }, targetItemId)
    end

    replacements.withdrawExact = function(groupKey, itemId, targetItemId)
        return replacements.withdrawRequests({
            { groupKey = groupKey, itemIds = { itemId } },
        }, targetItemId)
    end

    function instance:install()
        if self.installed then return true end
        for index = 1, #MUTATION_NAMES do
            local name = MUTATION_NAMES[index]
            originals[name] = target[name]
        end
        for name, callback in pairs(replacements) do
            if originals[name] == nil then originals[name] = target[name] end
            target[name] = callback
        end
        self.installed = true
        return true
    end

    function instance:poll()
        if not self.installed then return false end
        local timestamp = now()
        if instance.snapshotId and timestamp >= instance.nextSnapshotPollAt then
            instance.nextSnapshotPollAt = timestamp + 100
            if options.multiplayer ~= true
                and not facade.gateway:isPending("storage.process")
            then
                request("storage.process", {})
            end
            pollSnapshot()
        end
        if target.organizer and target.organizer.state == "running"
            and timestamp >= instance.nextOrganizerPollAt
            and not facade.gateway:isPending("storage.organizerStatus")
        then
            instance.nextOrganizerPollAt = timestamp + 250
            replacements.requestOrganizerStatus()
        end
        return true
    end

    function instance:stop()
        if not self.installed then return true end
        for name, callback in pairs(replacements) do
            if target[name] == callback then target[name] = originals[name] end
        end
        self.snapshotId = nil
        self.indexing = false
        self.installed = false
        return true
    end

    return instance
end

return StorageAdapter
