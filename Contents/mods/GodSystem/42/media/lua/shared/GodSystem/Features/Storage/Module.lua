require "GodSystem/Core/Result"
require "GodSystem/Features/Storage/Rules"

GodSystemStorageFeatureModule = GodSystemStorageFeatureModule or {}

local Descriptor = GodSystemStorageFeatureModule
local Rules = GodSystemStorageFeatureRules

Descriptor.id = "feature.storage"
Descriptor.dependencies = {
    "storage.config",
    "storage.state",
    "storage.objects",
    "storage.containers",
    "storage.items",
    "storage.core",
    "storage.permissions",
    "storage.clock",
    "storage.sync",
    "wallet",
    "operations",
    "storage.audit",
}
Descriptor.stateVersion = Rules.stateVersion

local MUTATIONS = {
    claimCore = true,
    installCore = true,
    retrieveCore = true,
    setNetworkContainer = true,
    updateContainer = true,
    deposit = true,
    withdraw = true,
    startOrganizer = true,
    stopOrganizer = true,
}

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function call(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function method(port, name, ...)
    local callback = port and port[name]
    if type(callback) ~= "function" then return false, "missing method " .. tostring(name) end
    return call(callback, ...)
end

local function requiredPort(dependencies, dependencyId, methods)
    local port = dependencies[dependencyId]
    assert(type(port) == "table", "missing dependency: " .. dependencyId)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. dependencyId .. " is missing method " .. methods[index])
    end
    return port
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function childRequest(request, suffix)
    local result = {}
    for key, value in pairs(type(request) == "table" and request or {}) do result[key] = value end
    local parentId = operationId(request)
    result.operationId = parentId and (parentId .. ":" .. tostring(suffix)) or nil
    return result
end

local function fingerprint(request)
    local itemIds = {}
    for index = 1, #(request.itemIds or {}) do
        itemIds[#itemIds + 1] = tostring(request.itemIds[index] or "")
    end
    table.sort(itemIds)
    return table.concat({
        tostring(request.action or ""),
        tostring(request.networkId or ""),
        tostring(request.objectId or ""),
        tostring(request.slotIndex or ""),
        tostring(request.role or ""),
        tostring(request.priorityTier or request.priority or ""),
        tostring(request.enabled == true),
        tostring(request.mode or ""),
        table.concat(itemIds, ","),
        tostring(request.snapshotId or ""),
    }, "|")
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "storage.config",
        { "snapshot", "health" })
    local state = requiredPort(dependencies, "storage.state",
        { "load", "create", "commit", "health" })
    local objects = requiredPort(dependencies, "storage.objects", {
        "actorPosition", "scope", "resolve", "adjacent", "slots", "marker",
        "setMarker", "clearMarker", "settings", "setSettings", "coreMarker",
        "installCore", "removeCore", "health",
    })
    local containers = requiredPort(dependencies, "storage.containers", {
        "list", "child", "contains", "accepts", "remove", "add",
        "playerContainer", "ground", "capacity", "used", "cold", "powered",
        "health",
    })
    local items = requiredPort(dependencies, "storage.items", {
        "id", "describe", "category", "isProtected", "canDeposit", "health",
    })
    local core = requiredPort(dependencies, "storage.core",
        { "find", "create", "remove", "restore", "cleanupDuplicates", "health" })
    local permissions = requiredPort(dependencies, "storage.permissions",
        { "canUse", "canManage", "withinRange", "health" })
    local clock = requiredPort(dependencies, "storage.clock", { "nowMs" })
    local sync = requiredPort(dependencies, "storage.sync",
        { "object", "add", "remove", "state", "health" })
    local wallet = requiredPort(dependencies, "wallet",
        { "getBalance", "charge", "refund" })
    local operations = requiredPort(dependencies, "operations",
        { "begin", "finish", "markUnknown" })
    local audit = requiredPort(dependencies, "storage.audit",
        { "record", "health" })
    local configCalled, configSnapshot = method(config, "snapshot")
    assert(configCalled and type(configSnapshot) == "table",
        "storage.config snapshot failed")
    local limits = {
        enabled = configSnapshot.enabled ~= false,
        maxNodes = math.max(1, math.min(Rules.maxNodes,
            Rules.integer(configSnapshot.maxNodes, Rules.maxNodes))),
        maxDepth = math.max(1, math.min(Rules.maxDepth,
            Rules.integer(configSnapshot.maxDepth, Rules.maxDepth))),
        maxIndexedItems = math.max(1, math.min(Rules.maxIndexedItems,
            Rules.integer(configSnapshot.maxIndexedItems, Rules.maxIndexedItems))),
        indexBatchItems = math.max(1, math.min(Rules.indexBatchItems,
            Rules.integer(configSnapshot.indexBatchItems, Rules.indexBatchItems))),
        indexBudgetMs = math.max(0.25, math.min(Rules.indexBudgetMs,
            tonumber(configSnapshot.indexBudgetMs) or Rules.indexBudgetMs)),
        coreRecoveryCost = math.max(0, Rules.integer(
            configSnapshot.coreRecoveryCost, Rules.coreRecoveryCost)),
        coreUseDistance = math.max(0.5, tonumber(
            configSnapshot.coreUseDistance) or Rules.coreUseDistance),
        manageDistance = math.max(0.5, tonumber(
            configSnapshot.manageDistance) or Rules.manageDistance),
    }

    local instance = {
        started = false,
        completed = 0,
        failed = 0,
        lastIssue = nil,
        sequence = 0,
        jobs = {},
        latestJobs = {},
        snapshotJobs = {},
        organizerByNetwork = {},
    }

    local function nowMs()
        local called, value = method(clock, "nowMs")
        value = called and tonumber(value) or nil
        if not value or value ~= value or value == math.huge or value == -math.huge then
            return 0
        end
        return math.floor(value)
    end

    local function newId(prefix, seed)
        instance.sequence = instance.sequence + 1
        return table.concat({
            tostring(prefix or "storage"),
            tostring(nowMs()),
            tostring(seed or ""),
            tostring(instance.sequence),
        }, "-")
    end

    local function result(ok, code, data, request)
        if ok then instance.completed = instance.completed + 1
        else instance.failed = instance.failed + 1 end
        if ok then return GodSystemResult.ok(moduleId, code, data, operationId(request)) end
        return GodSystemResult.fail(moduleId, code, data, operationId(request))
    end

    local function portFailure(stage, message, request)
        instance.lastIssue = {
            stage = stage,
            code = "portError",
            message = tostring(message),
        }
        return result(false, "portError", {
            stage = stage,
            message = tostring(message),
        }, request)
    end

    local function begin(request)
        local id = operationId(request)
        if not id then return nil, result(false, "operationIdRequired", nil, request) end
        local called, status, ledgerResult = call(operations.begin,
            moduleId, id, fingerprint(request), request)
        if not called then return nil, portFailure("operationBegin", status, request) end
        if status == "replay" then return nil, ledgerResult end
        if status ~= "new" then
            local code = type(ledgerResult) == "table"
                and ledgerResult.code or "operationInvalid"
            return nil, result(false, code,
                type(ledgerResult) == "table" and ledgerResult.data or nil, request)
        end
        return ledgerResult
    end

    local function finish(request, value)
        local id = operationId(request)
        local called, finished = call(operations.finish,
            moduleId, id, value, request)
        if called and type(finished) == "table" then return finished end
        call(operations.markUnknown, moduleId, id,
            "operationOutcomeUnknown", request)
        instance.lastIssue = {
            stage = "operationFinish",
            code = "operationOutcomeUnknown",
            message = tostring(finished),
        }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = value and value.ok == true,
        }, id)
    end

    local function loadNetwork(actor, selector, request)
        local called, value, revision = method(state, "load", actor, selector)
        if not called then return nil, nil, portFailure("stateLoad", value, request) end
        if value == nil then return nil, revision end
        if type(value) ~= "table" then
            return nil, revision, result(false, "stateInvalid", nil, request)
        end
        return Rules.normalizeState(value), revision
    end

    local function createNetwork(actor, request)
        local positionCalled, position = method(objects, "actorPosition", actor)
        if not positionCalled then return nil, nil, portFailure("actorPosition", position, request) end
        if type(position) ~= "table" then
            return nil, nil, result(false, "actorPositionMissing", nil, request)
        end
        local scopeCalled, scope = method(objects, "scope", actor, position)
        if not scopeCalled then return nil, nil, portFailure("scope", scope, request) end
        if type(scope) ~= "table" or tostring(scope.key or "") == "" then
            return nil, nil, result(false, "scopeInvalid", nil, request)
        end
        local called, value, revision = method(state, "create", actor, {
            version = Rules.stateVersion,
            schemaVersion = Rules.schemaVersion,
            networkId = newId("storage-network", scope.key),
            scopeKey = tostring(scope.key),
            scope = tostring(scope.kind or "personal"),
            owner = tostring(scope.owner or actor),
            coreClaimedOnce = false,
            coreToken = "",
            coreState = "unclaimed",
            revision = 0,
            knownObjects = {},
        })
        if not called then return nil, nil, portFailure("stateCreate", value, request) end
        if type(value) ~= "table" then
            return nil, nil, result(false, "stateCreateFailed", nil, request)
        end
        return Rules.normalizeState(value), revision
    end

    local function currentNetwork(actor, request, allowCreate)
        local selector = {
            networkId = request and request.networkId,
            current = not request or not request.networkId,
        }
        local network, revision, loadError = loadNetwork(actor, selector, request)
        if loadError then return nil, nil, loadError end
        if not network and allowCreate then return createNetwork(actor, request) end
        if not network then
            return nil, revision, result(false, "networkMissing", nil, request)
        end
        return network, revision
    end

    local function commitNetwork(actor, network, revision, request)
        network = Rules.normalizeState(network)
        network.revision = network.revision + 1
        local called, ok, code, nextRevision = method(state, "commit",
            actor, network, revision, request)
        if not called then return false, portFailure("stateCommit", ok, request) end
        if ok ~= true then return false, result(false, code or "stateCommitFailed", nil, request) end
        method(sync, "state", network, request)
        return true, nextRevision
    end

    local function auditRecord(actor, action, data, request)
        local called, value = method(audit, "record", actor, action, data, request)
        if not called then
            instance.lastIssue = {
                stage = "audit",
                code = "auditFailed",
                message = tostring(value),
            }
        end
    end

    local function walletCharge(actor, amount, request)
        local called, balance = method(wallet, "getBalance", actor, "spendable")
        if not called then return nil, portFailure("walletBalance", balance, request) end
        balance = tonumber(balance)
        if not balance or balance < amount then
            return nil, result(false, "balanceInsufficient", {
                available = math.max(0, math.floor(balance or 0)),
                required = amount,
            }, request)
        end
        local paidCalled, paid, receipt, data = method(wallet, "charge",
            actor, amount, childRequest(request, "charge"))
        if not paidCalled then return nil, portFailure("walletCharge", paid, request) end
        if paid ~= true then return nil, result(false, receipt or "chargeFailed", data, request) end
        return receipt
    end

    local function walletRefund(actor, receipt, request)
        if not receipt then return true end
        local called, refunded = method(wallet, "refund",
            actor, receipt, childRequest(request, "refund"))
        return called and refunded == true
    end

    local function permission(portName, actor, network, object, request)
        local called, allowed, code = method(permissions, portName,
            actor, network, object)
        if not called then return false, portFailure("permission." .. portName, allowed, request) end
        if allowed ~= true then return false, result(false, code or "notAllowed", nil, request) end
        return true
    end

    local function closeEnough(actor, object, distance, request)
        local called, allowed, code = method(permissions, "withinRange",
            actor, object, distance)
        if not called then return false, portFailure("permission.withinRange", allowed, request) end
        if allowed ~= true then return false, result(false, code or "tooFar", nil, request) end
        return true
    end

    local function resolveObject(reference, request, stage)
        local called, object, code = method(objects, "resolve", reference)
        if not called then return nil, portFailure(stage or "objectResolve", object, request) end
        if not object then return nil, result(false, code or "objectMissing", nil, request) end
        if tostring(object.objectId or "") ~= tostring(reference.objectId or "") then
            return nil, result(false, "objectChanged", nil, request)
        end
        return object
    end

    local function recordObject(network, object, slots)
        local reference = Rules.objectRef(object)
        if not reference then return false end
        reference.slots = {}
        for index = 1, #(slots or {}) do
            reference.slots[#reference.slots + 1] = {
                slotIndex = Rules.integer(slots[index].slotIndex, 0),
                name = tostring(slots[index].name or slots[index].type or reference.name),
                type = tostring(slots[index].type or ""),
            }
        end
        network.knownObjects[reference.objectId] = reference
        return true
    end

    local function topology(actor, network, request)
        local view = {
            networkId = network.networkId,
            scopeKey = network.scopeKey,
            revision = network.revision,
            links = {},
            orderedLinks = {},
            connectedObjectIds = {},
            onlineObjects = 0,
            offlineObjects = 0,
            truncated = false,
        }
        if type(network.coreHost) ~= "table" then
            return nil, result(false, "coreHostMissing", nil, request)
        end
        local host, hostError = resolveObject(network.coreHost, request, "coreResolve")
        if not host then return nil, hostError end
        view.host = host
        local coreMarkerCalled, coreMarker = method(objects, "coreMarker", host)
        if not coreMarkerCalled then return nil, portFailure("coreMarker", coreMarker, request) end
        if type(coreMarker) ~= "table"
            or tostring(coreMarker.networkId or "") ~= tostring(network.networkId)
            or tostring(coreMarker.token or "") ~= tostring(network.coreToken)
        then
            return nil, result(false, "coreExpired", nil, request)
        end
        local allowed, permissionError = permission("canUse",
            actor, network, host, request)
        if not allowed then return nil, permissionError end
        if request and request.allowRemote ~= true then
            local near, nearError = closeEnough(actor, host,
                limits.coreUseDistance, request)
            if not near then return nil, nearError end
        end

        local queue, cursor, visited = { host }, 1, {}
        while cursor <= #queue do
            local object = queue[cursor]
            cursor = cursor + 1
            local objectId = tostring(object.objectId or "")
            if objectId ~= "" and not visited[objectId] then
                if view.onlineObjects >= limits.maxNodes then
                    view.truncated = true
                    break
                end
                local markerCalled, marker = method(objects, "marker", object)
                if not markerCalled then return nil, portFailure("marker", marker, request) end
                if type(marker) == "table"
                    and marker.enabled == true
                    and tostring(marker.scopeKey or "") == tostring(network.scopeKey)
                then
                    visited[objectId] = true
                    view.connectedObjectIds[objectId] = true
                    view.onlineObjects = view.onlineObjects + 1
                    local slotsCalled, slots = method(objects, "slots", object)
                    if not slotsCalled then return nil, portFailure("slots", slots, request) end
                    slots = type(slots) == "table" and slots or {}
                    recordObject(network, object, slots)
                    local hostObject = objectId == tostring(network.coreHost.objectId or "")
                    if not hostObject then
                        for index = 1, #slots do
                            local slot = slots[index]
                            local settingsCalled, settings = method(objects,
                                "settings", object, slot.slotIndex)
                            if not settingsCalled then
                                return nil, portFailure("settings", settings, request)
                            end
                            settings = Rules.normalizeSettings(settings,
                                marker.markedAtMs and marker.markedAtMs * 100
                                    + Rules.integer(slot.slotIndex, 0) or 0)
                            local link = {
                                linkId = Rules.linkId(objectId, slot.slotIndex),
                                objectId = objectId,
                                objectRef = Rules.objectRef(object),
                                slotIndex = Rules.integer(slot.slotIndex, 0),
                                name = tostring(slot.name or marker.name or object.name or "Container"),
                                baseName = tostring(marker.name or object.name or "Container"),
                                type = tostring(slot.type or ""),
                                container = slot.container,
                                role = settings.role,
                                priorityTier = settings.priorityTier,
                                assignedOrder = settings.assignedOrder,
                                allowCategories = settings.allowCategories,
                                denyCategories = settings.denyCategories,
                                online = true,
                            }
                            view.links[link.linkId] = link
                            view.orderedLinks[#view.orderedLinks + 1] = link
                        end
                    end
                    local adjacentCalled, adjacent = method(objects,
                        "adjacent", object, network.scopeKey)
                    if not adjacentCalled then
                        return nil, portFailure("adjacent", adjacent, request)
                    end
                    for index = 1, #(adjacent or {}) do
                        local neighbor = adjacent[index]
                        local neighborId = tostring(neighbor and neighbor.objectId or "")
                        if neighborId ~= "" and not visited[neighborId]
                            and Rules.isAdjacent(object, neighbor)
                        then
                            queue[#queue + 1] = neighbor
                        end
                    end
                end
            end
        end
        for objectId, reference in pairs(network.knownObjects or {}) do
            if not visited[objectId] then
                local called, object, reason = method(objects, "resolve", reference)
                if not called then return nil, portFailure("offlineResolve", object, request) end
                view.offlineObjects = view.offlineObjects + 1
                for index = 1, #(reference.slots or {}) do
                    local slot = reference.slots[index]
                    local link = {
                        linkId = Rules.linkId(objectId, slot.slotIndex),
                        objectId = objectId,
                        objectRef = Rules.copy(reference),
                        slotIndex = slot.slotIndex,
                        name = slot.name,
                        type = slot.type,
                        online = false,
                        reason = object and "disconnected" or (reason or "objectMissing"),
                    }
                    view.links[link.linkId] = link
                    view.orderedLinks[#view.orderedLinks + 1] = link
                end
            end
        end
        table.sort(view.orderedLinks, function(left, right)
            return tostring(left.linkId) < tostring(right.linkId)
        end)
        return view
    end

    local function resolveLiveLink(link)
        if type(link) ~= "table" or link.online ~= true then return nil, nil, "offline" end
        local called, object, reason = method(objects, "resolve", link.objectRef)
        if not called or not object then return nil, nil, called and reason or object end
        if tostring(object.objectId or "") ~= tostring(link.objectId or "") then
            return nil, nil, "objectChanged"
        end
        local slotsCalled, slots = method(objects, "slots", object)
        if not slotsCalled then return nil, nil, slots end
        for index = 1, #(slots or {}) do
            if Rules.integer(slots[index].slotIndex, 0) == Rules.integer(link.slotIndex, 0) then
                return object, slots[index].container, nil
            end
        end
        return object, nil, "containerMissing"
    end

    local function routeCandidates(actor, view, item, includeFull)
        local categoryCalled, category = method(items, "category", item)
        if not categoryCalled then return nil, nil, "categoryPortError" end
        local routes = {}
        for index = 1, #view.orderedLinks do
            local link = view.orderedLinks[index]
            if link.online then
                local object, container = resolveLiveLink(link)
                if object and container then
                    local acceptedCalled, accepted, reason = method(containers,
                        "accepts", container, actor, item)
                    if not acceptedCalled then return nil, nil, "acceptsPortError" end
                    local coldCalled, cold = method(containers, "cold", container, link)
                    local poweredCalled, powered = method(containers, "powered", container, link)
                    if not coldCalled or not poweredCalled then
                        return nil, nil, "coldPortError"
                    end
                    local row = Rules.copy(link)
                    row.container = container
                    row.available = accepted == true
                    row.reason = accepted == true and nil or reason
                    row.coldContainer = cold == true
                    row.powered = powered == true
                    routes[#routes + 1] = row
                end
            end
        end
        return Rules.routeCandidates(routes, category, includeFull), category
    end

    local function transfer(actor, item, source, target, fallbackObject,
        sourceValidator, targetValidator, request)
        local function valid(callback)
            if type(callback) ~= "function" then return true end
            local called, value = call(callback)
            return called and value == true
        end
        if source == target then return false, "invalid" end
        if not valid(sourceValidator) then return false, "sourceChanged" end
        local containedCalled, contained = method(containers, "contains", source, item)
        if not containedCalled or contained ~= true then return false, "sourceChanged" end
        if not valid(targetValidator) then return false, "targetChanged" end
        local acceptsCalled, accepted, acceptCode = method(containers,
            "accepts", target, actor, item)
        if not acceptsCalled then return false, "acceptsPortError" end
        if accepted ~= true then return false, acceptCode or "notAllowed" end

        local removedCalled, removed = method(containers, "remove", source, item)
        if not removedCalled or removed ~= true then return false, "removeFailed" end
        method(sync, "remove", source, item, request)

        local function restore(originalReason)
            local addCalled, restored = method(containers, "add", source, item)
            if addCalled and restored == true then
                method(sync, "add", source, item, request)
                return false, originalReason
            end
            local playerCalled, playerContainer = method(containers,
                "playerContainer", actor, nil)
            if playerCalled and playerContainer then
                local inventoryCalled, inventoryRestored = method(containers,
                    "add", playerContainer, item)
                if inventoryCalled and inventoryRestored == true then
                    method(sync, "add", playerContainer, item, request)
                    return false, "restoredToPlayer"
                end
            end
            local groundCalled, grounded = method(containers, "ground",
                fallbackObject, actor, item)
            if groundCalled and grounded == true then return false, "restoredToGround" end
            return false, "criticalRestoreFailed"
        end

        if not valid(targetValidator) then return restore("targetChanged") end
        local addCalled, added = method(containers, "add", target, item)
        if addCalled and added == true then
            method(sync, "add", target, item, request)
            if valid(targetValidator) then return true, nil end
            local rollbackCalled, rollbackRemoved = method(containers,
                "remove", target, item)
            if not rollbackCalled or rollbackRemoved ~= true then
                return false, "criticalRestoreFailed"
            end
            method(sync, "remove", target, item, request)
            return restore("targetChanged")
        end
        return restore("targetAddFailed")
    end

    local function claimCore(actor, network, revision, request)
        local foundCalled, found = method(core, "find", actor,
            network.networkId, network.coreToken, request.coreItemId)
        if not foundCalled then return portFailure("coreFind", found, request) end
        if found then return result(false, "coreOwned", nil, request) end
        if network.coreState == "installed" and request.forceRecovery ~= true then
            return result(false, "coreInstalled", nil, request)
        end
        local recovered = network.coreClaimedOnce == true
        local cost = recovered and limits.coreRecoveryCost or 0
        local receipt, paymentError
        if cost > 0 then
            receipt, paymentError = walletCharge(actor, cost, request)
            if not receipt then return paymentError end
        end
        local token = newId("storage-core", network.networkId)
        local createCalled, item, createCode = method(core, "create",
            actor, network.networkId, token, Rules.coreFullType, request)
        if not createCalled or not item then
            local refunded = walletRefund(actor, receipt, request)
            if not refunded then
                return result(false, "rollbackIncomplete", {
                    cause = createCalled and createCode or item,
                    wallet = false,
                }, request)
            end
            if not createCalled then return portFailure("coreCreate", item, request) end
            return result(false, createCode or "coreCreateFailed", nil, request)
        end

        local oldHost = network.coreHost
        local oldToken = network.coreToken
        local unlockedOldObject = nil
        if type(oldHost) == "table" and oldToken ~= "" then
            local resolveCalled, oldObject, reason = method(objects, "resolve", oldHost)
            if not resolveCalled then
                method(core, "remove", actor, item, request)
                walletRefund(actor, receipt, request)
                return portFailure("oldCoreResolve", oldObject, request)
            end
            if oldObject then
                local removedCalled, removed = method(objects, "removeCore",
                    oldObject, oldToken, request)
                if not removedCalled or removed ~= true then
                    method(core, "remove", actor, item, request)
                    walletRefund(actor, receipt, request)
                    return result(false, removedCalled and reason or "portError", nil, request)
                end
                unlockedOldObject = oldObject
                method(sync, "object", oldObject, request)
            elseif reason == "squareUnloaded" then
                network.pendingCoreUnlock = Rules.copy(oldHost)
                network.pendingCoreUnlock.token = oldToken
            end
        end
        network.coreClaimedOnce = true
        network.coreToken = token
        network.coreState = "kit"
        network.coreHost = nil
        local committed, commitValue = commitNetwork(actor, network, revision, request)
        if not committed then
            local removeCalled, removed = method(core, "remove", actor, item, request)
            local refunded = walletRefund(actor, receipt, request)
            local hostRestored = true
            if unlockedOldObject then
                local hostCalled, hostValue = method(objects, "installCore",
                    unlockedOldObject, network.networkId, oldToken, request)
                hostRestored = hostCalled and hostValue == true
            end
            if not removeCalled or removed ~= true or not refunded or not hostRestored then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    core = removeCalled and removed == true,
                    wallet = refunded,
                    host = hostRestored,
                }, request)
            end
            return commitValue
        end
        local cleanupCalled, duplicates = method(core, "cleanupDuplicates",
            actor, network.networkId, item)
        if not cleanupCalled then duplicates = 0 end
        auditRecord(actor, recovered and "StorageCoreRecovered" or "StorageCoreClaimed", {
            networkId = network.networkId,
            cost = cost,
        }, request)
        return result(true, recovered and "StorageCoreRecovered" or "StorageCoreClaimed", {
            networkId = network.networkId,
            coreItem = item,
            token = token,
            cost = cost,
            recovered = recovered,
            removedDuplicates = tonumber(duplicates) or 0,
        }, request)
    end

    local function installCore(actor, network, revision, request)
        if network.coreState == "installed" or type(network.coreHost) == "table" then
            return result(false, "coreInstalled", nil, request)
        end
        local foundCalled, item = method(core, "find", actor,
            network.networkId, network.coreToken, request.coreItemId)
        if not foundCalled then return portFailure("coreFind", item, request) end
        if not item then return result(false, "coreMissing", nil, request) end
        local targetRef = request.object or request
        local object, objectError = resolveObject(targetRef, request, "targetResolve")
        if not object then return objectError end
        local markerCalled, marker = method(objects, "marker", object)
        if not markerCalled then return portFailure("marker", marker, request) end
        if type(marker) ~= "table" or marker.enabled ~= true then
            return result(false, "networkContainerRequired", nil, request)
        end
        if tostring(marker.scopeKey or "") ~= tostring(network.scopeKey) then
            return result(false, "scopeMismatch", nil, request)
        end
        local manageable, manageError = permission("canManage", actor, network, object, request)
        if not manageable then return manageError end
        local near, nearError = closeEnough(actor, object, limits.manageDistance, request)
        if not near then return nearError end
        local installCalled, installed, installCode = method(objects, "installCore",
            object, network.networkId, network.coreToken, request)
        if not installCalled then return portFailure("coreInstall", installed, request) end
        if installed ~= true then return result(false, installCode or "coreInstallFailed", nil, request) end
        local removeCalled, removed, removeReceipt = method(core, "remove",
            actor, item, request)
        if not removeCalled or removed ~= true then
            method(objects, "removeCore", object, network.coreToken, request)
            if not removeCalled then return portFailure("coreConsume", removed, request) end
            return result(false, removeReceipt or "coreConsumeFailed", nil, request)
        end
        network.coreHost = Rules.objectRef(object)
        network.coreState = "installed"
        local committed, commitValue = commitNetwork(actor, network, revision, request)
        if not committed then
            local hostRemovedCalled, hostRemoved = method(objects, "removeCore",
                object, network.coreToken, request)
            local restoredCalled, restored = method(core, "restore",
                actor, item, removeReceipt, request)
            if not hostRemovedCalled or hostRemoved ~= true
                or not restoredCalled or restored ~= true
            then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    host = hostRemovedCalled and hostRemoved == true,
                    core = restoredCalled and restored == true,
                }, request)
            end
            return commitValue
        end
        method(sync, "object", object, request)
        auditRecord(actor, "StorageCoreInstalled", {
            networkId = network.networkId,
            objectId = object.objectId,
        }, request)
        return result(true, "StorageCoreInstalled", {
            networkId = network.networkId,
            coreHost = network.coreHost,
        }, request)
    end

    local function retrieveCore(actor, network, revision, request)
        if type(network.coreHost) ~= "table" or network.coreState ~= "installed" then
            return result(false, "coreHostMissing", nil, request)
        end
        local object, objectError = resolveObject(network.coreHost, request, "coreResolve")
        if not object then return objectError end
        local manageable, manageError = permission("canManage", actor, network, object, request)
        if not manageable then return manageError end
        local near, nearError = closeEnough(actor, object, limits.manageDistance, request)
        if not near then return nearError end
        local removeCalled, removed, marker = method(objects, "removeCore",
            object, network.coreToken, request)
        if not removeCalled then return portFailure("coreRemove", removed, request) end
        if removed ~= true then return result(false, marker or "coreRemoveFailed", nil, request) end
        local createCalled, item, createCode = method(core, "create",
            actor, network.networkId, network.coreToken, Rules.coreFullType, request)
        if not createCalled or not item then
            method(objects, "installCore", object,
                network.networkId, network.coreToken, request)
            if not createCalled then return portFailure("coreReturn", item, request) end
            return result(false, createCode or "coreReturnFailed", nil, request)
        end
        network.coreState = "kit"
        network.coreHost = nil
        local committed, commitValue = commitNetwork(actor, network, revision, request)
        if not committed then
            local coreRemovedCalled, coreRemoved = method(core, "remove",
                actor, item, request)
            local hostRestoredCalled, hostRestored = method(objects,
                "installCore", object, network.networkId, network.coreToken, request)
            if not coreRemovedCalled or coreRemoved ~= true
                or not hostRestoredCalled or hostRestored ~= true
            then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    core = coreRemovedCalled and coreRemoved == true,
                    host = hostRestoredCalled and hostRestored == true,
                }, request)
            end
            return commitValue
        end
        method(sync, "object", object, request)
        auditRecord(actor, "StorageCoreRetrieved", {
            networkId = network.networkId,
            objectId = object.objectId,
        }, request)
        return result(true, "StorageCoreRetrieved", {
            networkId = network.networkId,
            coreItem = item,
        }, request)
    end

    local function setNetworkContainer(actor, network, revision, request)
        local object, objectError = resolveObject(request.object or request,
            request, "targetResolve")
        if not object then return objectError end
        local near, nearError = closeEnough(actor, object, limits.manageDistance, request)
        if not near then return nearError end
        local manageable, manageError = permission("canManage", actor, network, object, request)
        if not manageable then return manageError end
        local markerCalled, current = method(objects, "marker", object)
        if not markerCalled then return portFailure("marker", current, request) end
        local previousMarker = Rules.copy(current)
        local previousSettings = {}
        local previousSlotsCalled, previousSlots = method(objects, "slots", object)
        if not previousSlotsCalled then return portFailure("slots", previousSlots, request) end
        for index = 1, #(previousSlots or {}) do
            local slot = previousSlots[index]
            local settingsCalled, settings = method(objects, "settings",
                object, slot.slotIndex)
            if not settingsCalled then return portFailure("settings", settings, request) end
            previousSettings[tostring(slot.slotIndex)] = Rules.copy(settings)
        end
        local enabled = request.enabled == true
        if not enabled then
            local coreCalled, hostMarker = method(objects, "coreMarker", object)
            if not coreCalled then return portFailure("coreMarker", hostMarker, request) end
            if type(hostMarker) == "table" then return result(false, "coreInstalled", nil, request) end
            local clearCalled, cleared, clearCode = method(objects, "clearMarker",
                object, request)
            if not clearCalled then return portFailure("markerClear", cleared, request) end
            if cleared ~= true then return result(false, clearCode or "markerFailed", nil, request) end
            network.knownObjects[tostring(object.objectId)] = nil
        else
            if type(current) == "table"
                and tostring(current.scopeKey or "") ~= tostring(network.scopeKey)
            then
                return result(false, "alreadyLinked", nil, request)
            end
            local slotsCalled, slots = method(objects, "slots", object)
            if not slotsCalled then return portFailure("slots", slots, request) end
            if type(slots) ~= "table" or #slots == 0 then
                return result(false, "containerMissing", nil, request)
            end
            local marker = {
                enabled = true,
                objectId = tostring(object.objectId or ""),
                scopeKey = network.scopeKey,
                owner = network.owner,
                name = tostring(request.name or object.name or "Container"):sub(1, 60),
                markedAtMs = nowMs(),
            }
            local setCalled, set, setCode = method(objects, "setMarker",
                object, marker, request)
            if not setCalled then return portFailure("markerSet", set, request) end
            if set ~= true then return result(false, setCode or "markerFailed", nil, request) end
            recordObject(network, object, slots)
        end
        local committed, commitValue = commitNetwork(actor, network, revision, request)
        if not committed then
            local markerRestored = false
            if type(previousMarker) == "table" then
                local restoreCalled, restored = method(objects, "setMarker",
                    object, previousMarker, request)
                markerRestored = restoreCalled and restored == true
            else
                local restoreCalled, restored = method(objects, "clearMarker",
                    object, request)
                markerRestored = restoreCalled and restored == true
            end
            local settingsRestored = true
            for key, settings in pairs(previousSettings) do
                local restoreCalled, restored = method(objects, "setSettings",
                    object, tonumber(key), settings, request)
                if not restoreCalled or restored ~= true then settingsRestored = false end
            end
            if not markerRestored or not settingsRestored then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    marker = markerRestored,
                    settings = settingsRestored,
                }, request)
            end
            return commitValue
        end
        method(sync, "object", object, request)
        return result(true, "StorageContainerUpdated", {
            enabled = enabled,
            objectId = object.objectId,
        }, request)
    end

    local function updateContainer(actor, network, revision, request)
        local view, viewError = topology(actor, network, request)
        if not view then return viewError end
        local link = view.links[tostring(request.linkId or "")]
        if not link or not link.online then return result(false, "linkMissing", nil, request) end
        local object, objectError = resolveObject(link.objectRef, request, "linkResolve")
        if not object then return objectError end
        local manageable, manageError = permission("canManage", actor, network, object, request)
        if not manageable then return manageError end
        local currentCalled, current = method(objects, "settings",
            object, link.slotIndex)
        if not currentCalled then return portFailure("settings", current, request) end
        local previousSettings = Rules.copy(current)
        local next = Rules.normalizeSettings(current, nowMs() * 100 + link.slotIndex)
        if request.role ~= nil then
            if not Rules.isRole(request.role) then
                return result(false, "invalidRole", nil, request)
            end
            next.role = Rules.normalizeRole(request.role)
        end
        if request.priorityTier ~= nil or request.priority ~= nil then
            next.priorityTier = Rules.normalizePriority(
                request.priorityTier or request.priority)
        end
        if request.allowCategories ~= nil then
            next.allowCategories = Rules.normalizeSettings({
                allowCategories = request.allowCategories,
            }).allowCategories
        end
        if request.denyCategories ~= nil then
            next.denyCategories = Rules.normalizeSettings({
                denyCategories = request.denyCategories,
            }).denyCategories
        end
        network.routingSequence = math.max(network.routingSequence + 1, nowMs() * 100)
        next.assignedOrder = network.routingSequence
        local setCalled, set, setCode = method(objects, "setSettings",
            object, link.slotIndex, next, request)
        if not setCalled then return portFailure("settingsSet", set, request) end
        if set ~= true then return result(false, setCode or "settingsFailed", nil, request) end
        local committed, commitValue = commitNetwork(actor, network, revision, request)
        if not committed then
            local restoreCalled, restored = method(objects, "setSettings",
                object, link.slotIndex, previousSettings, request)
            if not restoreCalled or restored ~= true then
                return result(false, "rollbackIncomplete", {
                    cause = commitValue,
                    settings = false,
                }, request)
            end
            return commitValue
        end
        method(sync, "object", object, request)
        return result(true, "StorageContainerSettingsUpdated", {
            linkId = link.linkId,
            settings = next,
        }, request)
    end

    local function findDirect(container, expectedId)
        local listed, rows = method(containers, "list", container)
        if not listed then return nil end
        for index = 1, #(rows or {}) do
            local idCalled, id = method(items, "id", rows[index])
            if idCalled and tostring(id or "") == tostring(expectedId or "") then
                return rows[index]
            end
        end
        return nil
    end

    local function deposit(actor, network, _, request)
        local view, viewError = topology(actor, network, request)
        if not view then return viewError end
        local sourceCalled, source, sourceItem = method(containers,
            "playerContainer", actor, request.sourceItemId)
        if not sourceCalled then return portFailure("playerContainer", source, request) end
        if not source then return result(false, sourceItem or "sourceMissing", nil, request) end
        local mode = tostring(request.mode or "")
        if mode ~= "selected" and mode ~= "sourceAll" then
            return result(false, "invalidMode", nil, request)
        end
        local candidates, seen = {}, {}
        if mode == "sourceAll" then
            local listed, rows = method(containers, "list", source)
            if not listed then return portFailure("sourceList", rows, request) end
            for index = 1, math.min(#(rows or {}), limits.maxIndexedItems) do
                local idCalled, id = method(items, "id", rows[index])
                id = idCalled and tostring(id or "") or ""
                if id ~= "" and not seen[id] then
                    seen[id] = true
                    candidates[#candidates + 1] = { id = id, item = rows[index] }
                end
            end
        else
            for index = 1, math.min(#(request.itemIds or {}), limits.maxIndexedItems) do
                local id = tostring(request.itemIds[index] or "")
                if id ~= "" and not seen[id] then
                    seen[id] = true
                    candidates[#candidates + 1] = {
                        id = id,
                        item = findDirect(source, id),
                    }
                end
            end
        end
        local stats = {
            requested = #candidates,
            success = 0,
            skipped = 0,
            failed = 0,
            coldDowngrade = 0,
            offline = view.offlineObjects,
            successItemIds = {},
            skippedItemIds = {},
            failedItems = {},
        }
        for index = 1, #candidates do
            local row = candidates[index]
            if not row.item then
                stats.failed = stats.failed + 1
                stats.failedItems[#stats.failedItems + 1] = {
                    itemId = row.id, reason = "sourceChanged",
                }
            else
                local allowedCalled, allowed, allowedCode = method(items,
                    "canDeposit", actor, row.item, mode)
                if not allowedCalled then
                    return portFailure("canDeposit", allowed, request)
                elseif allowed ~= true then
                    stats.skipped = stats.skipped + 1
                    stats.skippedItemIds[#stats.skippedItemIds + 1] = row.id
                else
                    local routes, category, routeCode = routeCandidates(
                        actor, view, row.item, false)
                    if not routes then return result(false, routeCode, nil, request) end
                    local moved, reason, used
                    for routeIndex = 1, #routes do
                        local route = routes[routeIndex]
                        local function sourceValidator()
                            local currentCalled, current = method(containers,
                                "playerContainer", actor, request.sourceItemId)
                            return currentCalled and current == source
                                and findDirect(source, row.id) == row.item
                        end
                        local function targetValidator()
                            local _, live = resolveLiveLink(route)
                            return live == route.container
                        end
                        moved, reason = transfer(actor, row.item, source,
                            route.container, view.host, sourceValidator,
                            targetValidator, request)
                        if moved then used = route; break end
                        local stillCalled, still = method(containers,
                            "contains", source, row.item)
                        if not stillCalled or still ~= true then break end
                    end
                    if moved then
                        stats.success = stats.success + 1
                        stats.successItemIds[#stats.successItemIds + 1] = row.id
                        if category == "perishable"
                            and (not used or used.powered ~= true)
                        then
                            stats.coldDowngrade = stats.coldDowngrade + 1
                        end
                    else
                        stats.failed = stats.failed + 1
                        stats.failedItems[#stats.failedItems + 1] = {
                            itemId = row.id,
                            reason = #routes == 0 and "noRoute" or (reason or "targetAddFailed"),
                        }
                    end
                end
            end
        end
        if stats.success > 0 then
            network.revision = network.revision + 1
            method(sync, "state", network, request)
        end
        return result(stats.success > 0,
            stats.success > 0 and "StorageDeposited" or "nothingMoved",
            stats, request)
    end

    local function newIndexJob(actor, network, view, request, kind)
        local job = {
            jobId = newId(kind or "storage-index", network.networkId),
            kind = kind or "index",
            actor = actor,
            request = Rules.copy(request or {}),
            network = Rules.copy(network),
            view = view,
            stack = {},
            seenContainers = {},
            groups = {},
            groupOrder = {},
            instances = {},
            itemRows = {},
            processed = 0,
            indexed = 0,
            incomplete = false,
            phase = "index",
            cursor = 1,
            snapshot = Rules.emptySnapshot(network, nowMs()),
            stats = {
                moved = 0, unchanged = 0, skipped = 0, failed = 0, noRoute = 0,
            },
        }
        job.snapshot.snapshotId = newId("storage-snapshot", network.networkId)
        job.snapshot.offlineLinks = view.offlineObjects
        for index = 1, #view.orderedLinks do
            local link = view.orderedLinks[index]
            local summary = {
                linkId = link.linkId,
                objectId = link.objectId,
                name = link.name,
                role = link.role,
                priorityTier = link.priorityTier,
                online = link.online == true,
                reason = link.reason,
                capacity = 0,
                used = 0,
            }
            if link.online then
                local capacityCalled, capacity = method(containers,
                    "capacity", link.container)
                local usedCalled, used = method(containers, "used", link.container)
                if capacityCalled then summary.capacity = tonumber(capacity) or 0 end
                if usedCalled then summary.used = tonumber(used) or 0 end
                job.snapshot.totalCapacity = job.snapshot.totalCapacity + summary.capacity
                job.snapshot.usedCapacity = job.snapshot.usedCapacity + summary.used
                job.snapshot.onlineLinks = job.snapshot.onlineLinks + 1
                local listed, rows = method(containers, "list", link.container)
                if listed then
                    job.stack[#job.stack + 1] = {
                        container = link.container,
                        link = link,
                        rows = rows or {},
                        cursor = 1,
                        depth = 0,
                    }
                end
            end
            job.snapshot.containers[#job.snapshot.containers + 1] = summary
        end
        instance.jobs[job.jobId] = job
        return job
    end

    local function stepIndex(job)
        local started = nowMs()
        local handled = 0
        while #job.stack > 0
            and handled < limits.indexBatchItems
            and nowMs() - started <= limits.indexBudgetMs
        do
            if job.processed >= limits.maxIndexedItems then
                job.incomplete = true
                job.stack = {}
                break
            end
            local frame = job.stack[#job.stack]
            if job.seenContainers[frame.container] and frame.cursor == 1 then
                table.remove(job.stack)
            else
                job.seenContainers[frame.container] = true
                if frame.cursor > #(frame.rows or {}) then
                    table.remove(job.stack)
                else
                    local item = frame.rows[frame.cursor]
                    frame.cursor = frame.cursor + 1
                    handled = handled + 1
                    job.processed = job.processed + 1
                    local protectedCalled, protected = method(items,
                        "isProtected", item)
                    if not protectedCalled then
                        job.incomplete = true
                    elseif protected ~= true then
                        local described, description = method(items,
                            "describe", item, frame.link, frame.container)
                        if described and type(description) == "table" then
                            Rules.mergeSummary(job.groups, job.groupOrder,
                                job.instances, description)
                            job.indexed = job.indexed + 1
                            job.itemRows[#job.itemRows + 1] = {
                                item = item,
                                source = frame.container,
                                link = frame.link,
                                description = description,
                            }
                        end
                    end
                    local childCalled, child = method(containers, "child", item)
                    if childCalled and child and frame.depth < limits.maxDepth
                        and not job.seenContainers[child]
                    then
                        local listed, rows = method(containers, "list", child)
                        if listed then
                            job.stack[#job.stack + 1] = {
                                container = child,
                                link = frame.link,
                                rows = rows or {},
                                cursor = 1,
                                depth = frame.depth + 1,
                            }
                        end
                    end
                end
            end
        end
        if #job.stack == 0 then
            job.snapshot.itemCount = job.indexed
            job.snapshot.incomplete = job.incomplete
            Rules.finalizeSnapshot(job.snapshot, job.groups,
                job.groupOrder, job.instances, nowMs())
            if job.kind == "organizer" then job.phase = "organize"
            else job.phase = "completed" end
            instance.latestJobs[job.network.networkId] = job
            instance.snapshotJobs[job.snapshot.snapshotId] = job
        end
        return job.phase ~= "index"
    end

    local function startIndex(actor, network, request)
        local view, viewError = topology(actor, network, request)
        if not view then return viewError end
        local job = newIndexJob(actor, network, view, request, "index")
        return result(true, "StorageIndexStarted", {
            jobId = job.jobId,
            snapshotId = job.snapshot.snapshotId,
            maxItems = limits.maxIndexedItems,
            batchItems = limits.indexBatchItems,
            budgetMs = limits.indexBudgetMs,
        }, request)
    end

    local function selectedInstances(job, requests)
        local selected, seen = {}, {}
        for index = 1, #(requests or {}) do
            local request = requests[index]
            local groupKey = tostring(request.groupKey or "")
            local rows = job.instances[groupKey] or {}
            local byId = {}
            for rowIndex = 1, #rows do
                byId[tostring(rows[rowIndex].id or "")] = rows[rowIndex]
            end
            if type(request.itemIds) == "table" and #request.itemIds > 0 then
                for itemIndex = 1, #request.itemIds do
                    local id = tostring(request.itemIds[itemIndex] or "")
                    if id ~= "" and byId[id] and not seen[id] then
                        seen[id] = true
                        selected[#selected + 1] = byId[id]
                    end
                end
            else
                local wanted = math.max(1, math.min(limits.maxIndexedItems,
                    Rules.integer(request.count, 1)))
                for rowIndex = 1, math.min(wanted, #rows) do
                    local id = tostring(rows[rowIndex].id or "")
                    if id ~= "" and not seen[id] then
                        seen[id] = true
                        selected[#selected + 1] = rows[rowIndex]
                    end
                end
            end
        end
        return selected
    end

    local function liveItem(view, expectedId)
        local scanned, seenContainers = 0, {}
        local function visit(container, link, depth)
            if not container or seenContainers[container]
                or depth > limits.maxDepth
                or scanned >= limits.maxIndexedItems
            then
                return nil
            end
            seenContainers[container] = true
            local listed, rows = method(containers, "list", container)
            if not listed then return nil end
            for index = 1, #(rows or {}) do
                if scanned >= limits.maxIndexedItems then break end
                local item = rows[index]
                scanned = scanned + 1
                local idCalled, id = method(items, "id", item)
                if idCalled and tostring(id or "") == tostring(expectedId or "") then
                    return { item = item, source = container, link = link }
                end
                local childCalled, child = method(containers, "child", item)
                if childCalled and child then
                    local found = visit(child, link, depth + 1)
                    if found then return found end
                end
            end
            return nil
        end
        for index = 1, #view.orderedLinks do
            local link = view.orderedLinks[index]
            if link.online then
                local found = visit(link.container, link, 0)
                if found then return found end
            end
        end
        return nil
    end

    local function withdraw(actor, network, _, request)
        local view, viewError = topology(actor, network, request)
        if not view then return viewError end
        local job = instance.snapshotJobs[tostring(request.snapshotId or "")]
        if not job or tostring(job.network.networkId) ~= tostring(network.networkId) then
            return result(false, "snapshotExpired", nil, request)
        end
        local targetCalled, target, targetItem = method(containers,
            "playerContainer", actor, request.targetItemId)
        if not targetCalled then return portFailure("playerContainer", target, request) end
        if not target then return result(false, targetItem or "targetMissing", nil, request) end
        local selected = selectedInstances(job, request.requests)
        local stats = {
            requested = #selected, success = 0, skipped = 0, failed = 0,
            offline = view.offlineObjects, successItemIds = {},
            skippedItemIds = {}, failedItems = {},
        }
        for index = 1, #selected do
            local expected = selected[index]
            local live = liveItem(view, expected.id)
            if not live then
                stats.skipped = stats.skipped + 1
                stats.skippedItemIds[#stats.skippedItemIds + 1] = expected.id
            else
                local function sourceValidator()
                    local containedCalled, contained = method(containers,
                        "contains", live.source, live.item)
                    return containedCalled and contained == true
                end
                local function targetValidator()
                    local called, current = method(containers,
                        "playerContainer", actor, request.targetItemId)
                    return called and current == target
                end
                local ok, code = transfer(actor, live.item, live.source,
                    target, view.host, sourceValidator, targetValidator, request)
                if ok then
                    stats.success = stats.success + 1
                    stats.successItemIds[#stats.successItemIds + 1] = expected.id
                else
                    stats.failed = stats.failed + 1
                    stats.failedItems[#stats.failedItems + 1] = {
                        itemId = expected.id, reason = code,
                    }
                end
            end
        end
        if stats.success > 0 then
            network.revision = network.revision + 1
            method(sync, "state", network, request)
        end
        return result(stats.success > 0,
            stats.success > 0 and "StorageWithdrawn" or "nothingMoved",
            stats, request)
    end

    local function startOrganizer(actor, network, request)
        if instance.organizerByNetwork[network.networkId] then
            return result(false, "organizerRunning", nil, request)
        end
        local view, viewError = topology(actor, network, request)
        if not view then return viewError end
        local manageable, manageError = permission("canManage",
            actor, network, view.host, request)
        if not manageable then return manageError end
        local job = newIndexJob(actor, network, view, request, "organizer")
        instance.organizerByNetwork[network.networkId] = job.jobId
        return result(true, "StorageOrganizerStarted", {
            jobId = job.jobId,
            phase = job.phase,
        }, request), true
    end

    local function stepOrganizer(job)
        local started = nowMs()
        local handled = 0
        while job.cursor <= #job.itemRows
            and handled < 20
            and nowMs() - started <= limits.indexBudgetMs
        do
            local row = job.itemRows[job.cursor]
            job.cursor = job.cursor + 1
            handled = handled + 1
            local containedCalled, contained = method(containers,
                "contains", row.source, row.item)
            if not containedCalled or contained ~= true then
                job.stats.skipped = job.stats.skipped + 1
            else
                local routes = routeCandidates(job.actor, job.view, row.item, false)
                local desired = routes and routes[1] or nil
                if not desired then
                    job.stats.noRoute = job.stats.noRoute + 1
                    job.stats.skipped = job.stats.skipped + 1
                elseif desired.container == row.source then
                    job.stats.unchanged = job.stats.unchanged + 1
                else
                    local function sourceValidator()
                        local called, value = method(containers,
                            "contains", row.source, row.item)
                        return called and value == true
                    end
                    local function targetValidator()
                        local _, live = resolveLiveLink(desired)
                        return live == desired.container
                    end
                    local moved = transfer(job.actor, row.item, row.source,
                        desired.container, nil, sourceValidator,
                        targetValidator, job.request)
                    if moved then job.stats.moved = job.stats.moved + 1
                    else job.stats.failed = job.stats.failed + 1 end
                end
            end
        end
        if job.cursor > #job.itemRows then
            job.phase = "completed"
            instance.organizerByNetwork[job.network.networkId] = nil
            local final = GodSystemResult.ok(moduleId, "StorageOrganizerCompleted", {
                jobId = job.jobId,
                stats = job.stats,
                incomplete = job.incomplete,
            }, operationId(job.request))
            finish(job.request, final)
            return true
        end
        return false
    end

    local function stopOrganizer(actor, network, request)
        local jobId = instance.organizerByNetwork[network.networkId]
        local job = jobId and instance.jobs[jobId] or nil
        if not job then return result(true, "StorageOrganizerStopped", nil, request) end
        local manageable, manageError = permission("canManage",
            actor, network, job.view and job.view.host or nil, request)
        if not manageable then return manageError end
        job.phase = "stopped"
        instance.organizerByNetwork[network.networkId] = nil
        if job.request and operationId(job.request) then
            finish(job.request, GodSystemResult.fail(moduleId,
                "StorageOrganizerStopped", { jobId = job.jobId },
                operationId(job.request)))
        end
        return result(true, "StorageOrganizerStopped", {
            jobId = job.jobId,
        }, request)
    end

    local function processJobs()
        local indexCount, organizerCount = 0, 0
        for jobId, job in pairs(instance.jobs) do
            if job.phase == "index" and indexCount < 2 then
                indexCount = indexCount + 1
                stepIndex(job)
            end
            if job.phase == "organize" and organizerCount < 1 then
                organizerCount = organizerCount + 1
                stepOrganizer(job)
            end
            if job.phase == "completed" and job.kind == "index" then
                instance.jobs[jobId] = nil
            elseif job.phase == "completed" and job.kind == "organizer" then
                instance.jobs[jobId] = nil
            end
        end
        return {
            indexJobs = indexCount,
            organizerJobs = organizerCount,
        }
    end

    local function executeAction(request, network, revision)
        if request.action == "claimCore" then
            return claimCore(request.actor, network, revision, request)
        end
        if request.action == "installCore" then
            return installCore(request.actor, network, revision, request)
        end
        if request.action == "retrieveCore" then
            return retrieveCore(request.actor, network, revision, request)
        end
        if request.action == "setNetworkContainer" then
            return setNetworkContainer(request.actor, network, revision, request)
        end
        if request.action == "updateContainer" then
            return updateContainer(request.actor, network, revision, request)
        end
        if request.action == "deposit" then
            return deposit(request.actor, network, revision, request)
        end
        if request.action == "withdraw" then
            return withdraw(request.actor, network, revision, request)
        end
        if request.action == "startOrganizer" then
            return startOrganizer(request.actor, network, request)
        end
        if request.action == "stopOrganizer" then
            return stopOrganizer(request.actor, network, request)
        end
        return result(false, "actionInvalid", { action = request.action }, request)
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        request.action = tostring(request.action or "")
        if not instance.started then return result(false, "moduleStopped", nil, request) end
        if request.actor == nil then return result(false, "actorRequired", nil, request) end
        if not limits.enabled then return result(false, "StorageDisabled", nil, request) end
        if not MUTATIONS[request.action] then
            return result(false, "actionInvalid", { action = request.action }, request)
        end
        local row, replay = begin(request)
        if not row then return replay end
        local allowCreate = request.action == "claimCore"
            or request.action == "setNetworkContainer"
        local network, revision, loadError = currentNetwork(
            request.actor, request, allowCreate)
        if not network then
            local value = loadError or result(false, "networkMissing", nil, request)
            return finish(request, value)
        end
        local called, value, asynchronous = call(executeAction,
            request, network, revision)
        if not called then
            call(operations.markUnknown, moduleId,
                operationId(request), "portError", request)
            return portFailure("execute", value, request)
        end
        if request.action == "startOrganizer" and asynchronous == true
            and value.ok == true
        then
            return value
        end
        return finish(request, value)
    end

    local function status(actor, request)
        request = type(request) == "table" and request or {}
        request.actor = actor or request.actor
        if not limits.enabled then return result(false, "StorageDisabled", nil, request) end
        local network, _, loadError = currentNetwork(request.actor, request, false)
        if not network then
            if loadError and loadError.code ~= "networkMissing" then return loadError end
            return result(true, "StorageUnclaimed", {
                state = "unclaimed",
                nextCost = 0,
            }, request)
        end
        local foundCalled, found = method(core, "find", request.actor,
            network.networkId, network.coreToken, request.coreItemId)
        if not foundCalled then return portFailure("coreFind", found, request) end
        local stateName = found and "kit" or network.coreState
        return result(true, "StorageStatus", {
            networkId = network.networkId,
            state = stateName,
            claimedOnce = network.coreClaimedOnce,
            nextCost = network.coreClaimedOnce and limits.coreRecoveryCost or 0,
            coreHost = network.coreHost,
            revision = network.revision,
            organizing = instance.organizerByNetwork[network.networkId] ~= nil,
        }, request)
    end

    local function requestStatus(request)
        request = type(request) == "table" and request or {}
        return status(request.actor, request)
    end

    local function startIndexPublic(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return result(false, "moduleStopped", nil, request) end
        if request.actor == nil then return result(false, "actorRequired", nil, request) end
        if not limits.enabled then return result(false, "StorageDisabled", nil, request) end
        local network, _, loadError = currentNetwork(request.actor, request, false)
        if not network then return loadError end
        return startIndex(request.actor, network, request)
    end

    local function snapshot(snapshotId)
        local job = instance.snapshotJobs[tostring(snapshotId or "")]
        if not job then return nil end
        return Rules.copy(job.snapshot)
    end

    local function instanceDetails(snapshotId, groupKey)
        local job = instance.snapshotJobs[tostring(snapshotId or "")]
        if not job then return nil end
        return Rules.copy(job.instances[tostring(groupKey or "")] or {})
    end

    local function requestSnapshot(request)
        request = type(request) == "table" and request or {}
        local value = snapshot(request.snapshotId)
        if not value then return result(false, "snapshotMissing", nil, request) end
        return result(true, "StorageSnapshot", value, request)
    end

    local function requestInstanceDetails(request)
        request = type(request) == "table" and request or {}
        local job = instance.snapshotJobs[tostring(request.snapshotId or "")]
        if not job then return result(false, "snapshotMissing", nil, request) end
        return result(true, "StorageDetails", {
            snapshotId = tostring(request.snapshotId or ""),
            groupKey = tostring(request.groupKey or ""),
            instances = Rules.copy(
                job.instances[tostring(request.groupKey or "")] or {}),
        }, request)
    end

    instance.public = {
        execute = execute,
        status = status,
        requestStatus = requestStatus,
        startIndex = startIndexPublic,
        processJobs = processJobs,
        snapshot = snapshot,
        requestSnapshot = requestSnapshot,
        instanceDetails = instanceDetails,
        requestInstanceDetails = requestInstanceDetails,
        claimCore = function(request)
            request = type(request) == "table" and request or {}
            request.action = "claimCore"
            return execute(request)
        end,
        installCore = function(request)
            request = type(request) == "table" and request or {}
            request.action = "installCore"
            return execute(request)
        end,
        retrieveCore = function(request)
            request = type(request) == "table" and request or {}
            request.action = "retrieveCore"
            return execute(request)
        end,
        deposit = function(request)
            request = type(request) == "table" and request or {}
            request.action = "deposit"
            return execute(request)
        end,
        withdraw = function(request)
            request = type(request) == "table" and request or {}
            request.action = "withdraw"
            return execute(request)
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop(reason)
        self.started = false
        for _, job in pairs(self.jobs) do
            if job.kind == "organizer" and job.phase ~= "completed" then
                job.phase = "stopped"
                if job.request and operationId(job.request) then
                    finish(job.request, GodSystemResult.fail(moduleId,
                        "moduleStopped", { reason = reason },
                        operationId(job.request)))
                end
            end
        end
        self.jobs = {}
        self.organizerByNetwork = {}
        return true
    end

    function instance:health()
        local checks, healthy = {}, true
        for _, row in ipairs({
            { id = "config", port = config },
            { id = "state", port = state },
            { id = "objects", port = objects },
            { id = "containers", port = containers },
            { id = "items", port = items },
            { id = "core", port = core },
            { id = "permissions", port = permissions },
            { id = "sync", port = sync },
            { id = "audit", port = audit },
        }) do
            local called, ok, data = method(row.port, "health")
            checks[row.id] = {
                ok = called and ok ~= false,
                data = called and data or tostring(ok),
            }
            if not checks[row.id].ok then healthy = false end
        end
        local runningJobs = 0
        for _ in pairs(self.jobs) do runningJobs = runningJobs + 1 end
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
            runningJobs = runningJobs,
            checks = checks,
        }
        if self.lastIssue or not healthy then
            return GodSystemResult.fail(moduleId,
                self.lastIssue and self.lastIssue.code or "dependencyUnhealthy", data)
        end
        return GodSystemResult.ok(moduleId,
            self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
