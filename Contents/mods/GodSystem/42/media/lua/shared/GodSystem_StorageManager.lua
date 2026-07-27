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

function Manager.calibrateLoadedSquare(square)
    local changed = false
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local object = objects[i]
        local host = Storage.getCoreHostMarker(object)
        if host then
            local network = Manager.getNetwork(host.networkId)
            local position = Storage.objectCoordinates(object)
            local recorded = network and (network.coreHost or network.controller) or nil
            local active = network
                and tostring(network.coreToken or network.controllerToken or "") == tostring(host.token or "")
                and type(recorded) == "table"
                and position
                and Storage.integer(recorded.x, -1) == Storage.integer(position.x, 0)
                and Storage.integer(recorded.y, -1) == Storage.integer(position.y, 0)
                and Storage.integer(recorded.z, -1) == Storage.integer(position.z, 0)
                and tostring(recorded.objectId or "") == tostring(host.objectId or "")
            if active then
                Storage.enforceCoreHostLock(object, host.networkId, host.token)
            else
                local unlocked = Storage.unlockCoreHost(object, host.token)
                if unlocked and network and tostring(network.coreToken or "") == tostring(host.token or "") then
                    network.coreState = "missing"
                    network.coreHost = nil
                    network.coreItemId = nil
                    network.revision = Storage.integer(network.revision, 0) + 1
                    changed = true
                end
                if unlocked and network and type(network.pendingCoreUnlock) == "table"
                    and tostring(network.pendingCoreUnlock.token or "") == tostring(host.token or "") then
                    network.pendingCoreUnlock = nil
                    changed = true
                end
            end
        end
    end
    if changed then transmitStore() end
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
        coreToken = "",
        coreClaimedOnce = false,
        coreState = "unclaimed",
        coreItemId = nil,
        coreHost = nil,
        pendingCoreUnlock = nil,
        coreMigrationVersion = 1,
        radius = Storage.DefaultRadius,
        maxLinks = Storage.MaxLinks,
        links = {},
        topologyVersion = Storage.TopologyVersion,
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
        local coreHost = network.coreHost or network.controller or {}
        local safehouse = Storage.getSafehouseAt(coreHost.x or 0, coreHost.y or 0)
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
    local coreHost = network.coreHost or network.controller or {}
    local safehouse = Storage.getSafehouseAt(coreHost.x or 0, coreHost.y or 0)
    local username = Storage.playerKey(player)
    if Storage.safehouseKey(safehouse) ~= tostring(network.safehouse or "") then
        return username == tostring(network.creator or "")
    end
    return safeCall(safehouse, "isOwner", false, player) == true
        or tostring(safeCall(safehouse, "getOwner", "") or "") == username
        or username == tostring(network.creator or "")
end

local function inventoryAddCore(player, network, token)
    local inventory = safeCall(player, "getInventory", nil)
    if not inventory then return nil, "inventoryMissing" end
    local item
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, created = pcall(InventoryItemFactory.CreateItem, Storage.CoreFullType)
        if ok then item = created end
    end
    if item then
        local ok = pcall(function() inventory:AddItem(item) end)
        if not ok or not Storage.containerContains(inventory, item) then item = nil end
    end
    if not item then
        item = safeCall(inventory, "AddItem", nil, Storage.CoreFullType)
    end
    if not item then return nil, "createFailed" end
    if not Storage.setCoreIdentity(item, network.networkId, token) then
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

local function collectCoreItems(player)
    local root = safeCall(player, "getInventory", nil)
    local result, seenContainers = {}, {}
    local function visit(container, depth)
        if not container or seenContainers[container] or depth > Storage.MaxDepth then return end
        seenContainers[container] = true
        local items = safeCall(container, "getItems", nil)
        local size = Storage.integer(safeCall(items, "size", 0), 0)
        for i = 0, size - 1 do
            local item = safeCall(items, "get", nil, i)
            if Storage.isCore(item) then
                result[#result + 1] = { item = item, container = container }
            end
            visit(safeCall(item, "getInventory", nil), depth + 1)
        end
    end
    visit(root, 0)
    return result
end

local function findInventoryCore(player, networkId, token, expectedItemId)
    local rows = collectCoreItems(player)
    for i = 1, #rows do
        local itemNetworkId, itemToken = Storage.getCoreIdentity(rows[i].item)
        if tostring(itemNetworkId or "") == tostring(networkId or "")
            and tostring(itemToken or "") == tostring(token or "")
            and (not expectedItemId or tostring(expectedItemId) == ""
                or tostring(Storage.itemId(rows[i].item) or "") == tostring(expectedItemId)) then
            return rows[i].item, rows[i].container
        end
    end
    return nil, nil
end

local function cleanupInventoryCores(player, networkId, keepItem)
    local removed = 0
    local rows = collectCoreItems(player)
    for i = 1, #rows do
        local itemNetworkId = Storage.getCoreIdentity(rows[i].item)
        if rows[i].item ~= keepItem and tostring(itemNetworkId or "") == tostring(networkId or "")
            and removeInventoryItem(rows[i].container, rows[i].item) then
            removed = removed + 1
        end
    end
    return removed
end

local function removeLegacyWorldObject(object)
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

local function normalizeCoreFields(network)
    local changed = false
    if Storage.integer(network.coreMigrationVersion, 0) < 1 then
        local legacyToken = tostring(network.controllerToken or "")
        if tostring(network.coreToken or "") == "" then network.coreToken = legacyToken end
        if network.coreClaimedOnce == nil then
            network.coreClaimedOnce = network.controllerClaimedOnce == true or legacyToken ~= ""
        end
        local legacyState = tostring(network.controllerState or "")
        if type(network.controller) == "table"
            and (legacyState == "installed" or legacyState == "legacyGround") then
            network.legacyControllerCleanup = network.controller
            network.legacyControllerCleanup.token = legacyToken
            network.coreState = "migrationPending"
        elseif legacyState == "kit" then
            network.coreState = "kit"
            network.coreItemId = network.controllerItemId
        elseif tostring(network.coreToken or "") == "" then
            network.coreState = "unclaimed"
        else
            network.coreState = "missing"
        end
        network.coreMigrationVersion = 1
        network.controller = nil
        network.controllerToken = nil
        network.controllerState = nil
        network.controllerItemId = nil
        network.controllerClaimedOnce = nil
        changed = true
    end
    local token = tostring(network.coreToken or "")
    if network.coreClaimedOnce == nil then
        network.coreClaimedOnce = token ~= ""
        changed = true
    end
    if token == "" and tostring(network.coreState or "") ~= "unclaimed" then
        network.coreState = "unclaimed"
        network.coreItemId = nil
        changed = true
    elseif token ~= "" and tostring(network.coreState or "") == "" then
        network.coreState = "missing"
        changed = true
    end
    return changed
end

local function setCoreState(network, state, itemId, coreHost)
    local changed = tostring(network.coreState or "") ~= tostring(state or "")
        or tostring(network.coreItemId or "") ~= tostring(itemId or "")
        or network.coreHost ~= coreHost
    network.coreState = tostring(state or "missing")
    network.coreItemId = itemId and tostring(itemId) or nil
    network.coreHost = coreHost
    if changed then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
    end
    return changed
end

local function findRecordedCoreHost(network, expectedToken)
    local host = type(network.coreHost) == "table" and network.coreHost or nil
    if not host then return nil, nil, false end
    local square = Storage.getSquare(host.x, host.y, host.z)
    if not square then return nil, nil, false end
    local object, marker = Storage.findCoreHost(host.x, host.y, host.z, host.objectId,
        network.networkId, expectedToken)
    return object, marker, true
end

local function processPendingUnlock(network)
    local pending = type(network.pendingCoreUnlock) == "table" and network.pendingCoreUnlock or nil
    if not pending then return false end
    local square = Storage.getSquare(pending.x, pending.y, pending.z)
    if not square then return false end
    local object = Storage.findCoreHost(pending.x, pending.y, pending.z,
        pending.objectId, network.networkId, pending.token)
    if object then
        local unlocked = Storage.unlockCoreHost(object, pending.token)
        if not unlocked then return false end
    end
    network.pendingCoreUnlock = nil
    return true
end

local function cleanupLegacyController(network)
    local legacy = type(network.legacyControllerCleanup) == "table" and network.legacyControllerCleanup or nil
    if not legacy then return false end
    local square = Storage.getSquare(legacy.x, legacy.y, legacy.z)
    if not square then return false end
    local object = Storage.findLegacyWorldController(
        legacy.x, legacy.y, legacy.z, legacy.itemId,
        tostring(legacy.token or network.coreToken or ""), legacy.objectId)
    if object and not removeLegacyWorldObject(object) then return false end
    network.legacyControllerCleanup = nil
    return true
end

local function migrateInventoryCore(player, network, item, container)
    if not item or not Storage.hasLegacyControllerIdentity(item) then
        if item then Storage.setCoreIdentity(item, network.networkId, network.coreToken) end
        return item, container
    end
    local replacement, reason = inventoryAddCore(player, network, network.coreToken)
    if not replacement then return item, container, reason end
    if not removeInventoryItem(container, item) then
        removeInventoryItem(safeCall(player, "getInventory", nil), replacement)
        return item, container, "migrationRemoveFailed"
    end
    return replacement, safeCall(replacement, "getContainer", nil)
end

function Manager.coreStatus(player)
    local position = Storage.positionOfPlayer(player)
    if not position then return nil, "playerMissing" end
    local network
    local coreRows = collectCoreItems(player)
    for i = 1, #coreRows do
        local networkId, token = Storage.getCoreIdentity(coreRows[i].item)
        local candidate = Manager.getNetwork(networkId)
        if candidate then normalizeCoreFields(candidate) end
        if candidate and tostring(candidate.coreToken or "") == tostring(token or "") then
            network = candidate
            break
        end
    end
    local scopeNetwork
    if not network then
        local _, scopeKey = Manager.scopeForPosition(player, position)
        scopeNetwork = Manager.getNetworkByScope(scopeKey)
        if scopeNetwork then
            normalizeCoreFields(scopeNetwork)
            if tostring(scopeNetwork.coreToken or "") ~= "" then network = scopeNetwork end
        end
    end
    if not network then
        local username = Storage.playerKey(player)
        local newestAt = -1
        for _, candidate in pairs(Manager.getStore().networks) do
            if tostring(candidate.owner or candidate.creator or "") == username
                and tostring(candidate.coreToken or candidate.controllerToken or "") ~= ""
                and Storage.number(candidate.updatedAtMs, 0) > newestAt then
                network = candidate
                newestAt = Storage.number(candidate.updatedAtMs, 0)
            end
        end
    end
    if not network then network = scopeNetwork end
    if not network then
        return {
            state = "unclaimed",
            claimedOnce = false,
            recoveryCost = Storage.CoreRecoveryCost,
            nextCost = 0,
            canClaim = true,
        }
    end
    if not Manager.canUse(player, network) then return nil, "notAllowed" end

    local changed = normalizeCoreFields(network)
    if processPendingUnlock(network) then changed = true end
    if cleanupLegacyController(network) then changed = true end
    local token = tostring(network.coreToken or "")
    local state = tostring(network.coreState or "missing")
    local itemId = network.coreItemId
    local coreHost = network.coreHost
    local activeCoreItem
    if token ~= "" then
        local item, container = findInventoryCore(player, network.networkId, token)
        if item then
            item, container = migrateInventoryCore(player, network, item, container)
            activeCoreItem = item
            itemId = Storage.itemId(item)
            if type(coreHost) == "table" then
                local staleHost, _, loaded = findRecordedCoreHost(network, token)
                if staleHost then
                    local unlocked = Storage.unlockCoreHost(staleHost, token)
                    if not unlocked then return nil, "capacityRestoreFailed" end
                elseif not loaded then
                    network.pendingCoreUnlock = {
                        x = coreHost.x, y = coreHost.y, z = coreHost.z,
                        objectId = coreHost.objectId, token = token,
                    }
                end
            end
            coreHost = nil
            state = "kit"
        elseif state == "migrationPending" then
            local migrated, migrateReason = inventoryAddCore(player, network, token)
            if not migrated then return nil, migrateReason end
            activeCoreItem = migrated
            itemId = Storage.itemId(migrated)
            coreHost = nil
            state = "kit"
            cleanupLegacyController(network)
        elseif type(coreHost) == "table" then
            local object, _, loaded = findRecordedCoreHost(network, token)
            if object then
                local locked, lockReason = Storage.enforceCoreHostLock(object, network.networkId, token)
                if not locked then return nil, lockReason end
                state = "installed"
                itemId = nil
            elseif loaded then
                state = "missing"
                coreHost = nil
                itemId = nil
            end
        else
            state = "missing"
            itemId = nil
        end
    else
        state = "unclaimed"
        itemId = nil
        coreHost = nil
    end
    if setCoreState(network, state, itemId, coreHost) then changed = true end
    if token ~= "" and cleanupInventoryCores(player, network.networkId, activeCoreItem) > 0 then changed = true end
    if changed then transmitStore() end

    local claimedOnce = network.coreClaimedOnce == true
    return {
        networkId = network.networkId,
        state = state,
        claimedOnce = claimedOnce,
        recoveryCost = Storage.CoreRecoveryCost,
        nextCost = claimedOnce and Storage.CoreRecoveryCost or 0,
        canClaim = state == "unclaimed" or state == "missing",
        canForceRecover = state == "installed",
        coreItemId = itemId,
        coreHost = coreHost,
        revision = Storage.integer(network.revision, 0),
    }
end

function Manager.claimCore(player, options)
    options = type(options) == "table" and options or {}
    local status, statusReason = Manager.coreStatus(player)
    if not status then return false, statusReason end
    local network = status.networkId and Manager.getNetwork(status.networkId) or nil
    local reason, created
    if not network then network, reason, created = Manager.getOrCreateNetwork(player) end
    if not network then return false, reason end
    if not Manager.canUse(player, network) then return false, "notAllowed" end
    if not created and not Manager.canManage(player, network) then return false, "manageDenied" end
    normalizeCoreFields(network)
    local state = tostring(status.state or "missing")
    local forceRecovery = options.forceRecovery == true
    if state == "kit" then return false, "coreOwned" end
    if state == "installed" and not forceRecovery then
        return false, "coreInstalled"
    end

    local recovered = network.coreClaimedOnce == true
    local cost = recovered and Storage.CoreRecoveryCost or 0
    local oldToken = tostring(network.coreToken or "")
    local oldHost = network.coreHost
    local token = Storage.newId("storage-core", network.networkId)

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
    local item, createReason = inventoryAddCore(player, network, token)
    if not item then
        if cost > 0 and type(options.refund) == "function" then
            pcall(options.refund, receipt)
        end
        return false, createReason
    end

    if type(oldHost) == "table" and oldToken ~= "" then
        local oldObject, _, loaded = findRecordedCoreHost(network, oldToken)
        if oldObject then
            local unlocked, unlockReason = Storage.unlockCoreHost(oldObject, oldToken)
            if not unlocked then
                removeInventoryItem(safeCall(player, "getInventory", nil), item)
                if cost > 0 and type(options.refund) == "function" then pcall(options.refund, receipt) end
                return false, unlockReason
            end
        elseif not loaded then
            network.pendingCoreUnlock = {
                x = oldHost.x, y = oldHost.y, z = oldHost.z,
                objectId = oldHost.objectId, token = oldToken,
            }
        end
    end
    network.coreToken = token
    network.coreClaimedOnce = true
    setCoreState(network, "kit", Storage.itemId(item), nil)
    local removedDuplicates = cleanupInventoryCores(player, network.networkId, item)
    transmitStore()
    if type(options.onCommit) == "function" then
        pcall(options.onCommit, cost, recovered, receipt)
    end
    return true, nil, {
        networkId = network.networkId,
        coreItemId = Storage.itemId(item),
        token = token,
        recovered = recovered,
        cost = cost,
        removedDuplicates = removedDuplicates,
        state = "kit",
    }
end

local function installTarget(player, args)
    local position = {
        x = Storage.integer(args.x, 0),
        y = Storage.integer(args.y, 0),
        z = Storage.integer(args.z, 0),
    }
    local playerPosition = Storage.positionOfPlayer(player)
    if not playerPosition or Storage.distance2D(playerPosition, position) > 2.5
        or Storage.integer(playerPosition.z, 0) ~= position.z then
        return nil, nil, "targetTooFar"
    end
    local object = Storage.resolveObjectCandidate(position.x, position.y, position.z,
        args.objectIndex, args.sprite)
    if not object then return nil, nil, "targetChanged" end
    local marker = Storage.getNetworkContainerMarker(object)
    if not marker then return nil, nil, "networkContainerRequired" end
    if Storage.isCoreHost(object) then return nil, nil, "coreInstalled" end
    return object, position, nil
end

local function bindNetworkScope(player, network, position)
    local scope, scopeKey, safehouse = Manager.scopeForPosition(player, position)
    if scope == "safehouse" and not (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
        return false, "notAllowed"
    end
    if tostring(network.scopeKey or "") == tostring(scopeKey or "") then return true end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local existing = Manager.getNetworkByScope(scopeKey)
    if existing and existing ~= network then return false, "safehouseHasNetwork" end
    local store = Manager.getStore()
    if store.scopeIndex[network.scopeKey] == network.networkId then store.scopeIndex[network.scopeKey] = nil end
    network.scope = scope
    network.scopeKey = scopeKey
    network.safehouse = scope == "safehouse" and scopeKey or nil
    store.scopeIndex[scopeKey] = network.networkId
    return true
end

function Manager.installCore(player, args)
    args = type(args) == "table" and args or {}
    local network = Manager.getNetwork(args.networkId)
    if not network then return false, "coreInvalid" end
    normalizeCoreFields(network)
    local token = tostring(args.coreToken or "")
    if token == "" or token ~= tostring(network.coreToken or "") then return false, "coreExpired" end
    if type(network.coreHost) == "table" or tostring(network.coreState or "") == "installed" then
        return false, "coreInstalled"
    end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local core, coreContainer = findInventoryCore(player, network.networkId, token, args.coreItemId)
    if not core or not coreContainer then return false, "coreMissing" end
    local object, position, targetReason = installTarget(player, args)
    if not object then return false, targetReason end
    local scoped, scopeReason = bindNetworkScope(player, network, position)
    if not scoped then return false, scopeReason end
    local marker = Storage.getNetworkContainerMarker(object)
    if tostring(marker.scopeKey or "") ~= tostring(network.scopeKey or "") then return false, "scopeMismatch" end
    local locked, lockReason, hostMarker = Storage.lockCoreHost(object, network.networkId, token)
    if not locked then return false, lockReason end
    if not removeInventoryItem(coreContainer, core) then
        Storage.unlockCoreHost(object, token)
        return false, "coreConsumeFailed"
    end
    local host = {
        x = position.x, y = position.y, z = position.z,
        objectId = tostring(hostMarker.objectId or ""),
        sprite = Storage.objectSpriteName(object),
    }
    setCoreState(network, "installed", nil, host)
    Manager.save(network)
    return true, nil, {
        networkId = network.networkId,
        token = token,
        coreHost = host,
        state = "installed",
    }
end

function Manager.retrieveCore(player, args)
    local network, object, _, reason = Manager.resolveCoreHost(player, args)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local token = tostring(network.coreToken or "")
    local unlocked, unlockReason = Storage.unlockCoreHost(object, token)
    if not unlocked then return false, unlockReason end
    local item, createReason = inventoryAddCore(player, network, token)
    if not item then
        local relocked = Storage.lockCoreHost(object, network.networkId, token)
        if not relocked then
            setCoreState(network, "missing", nil, nil)
            Manager.save(network)
            return false, "coreReturnFailed"
        end
        return false, createReason
    end
    local removedDuplicates = cleanupInventoryCores(player, network.networkId, item)
    setCoreState(network, "kit", Storage.itemId(item), nil)
    Manager.save(network)
    return true, nil, {
        networkId = network.networkId,
        coreItemId = Storage.itemId(item),
        token = token,
        state = "kit",
        removedDuplicates = removedDuplicates,
    }
end

function Manager.resolveCoreHost(player, args)
    args = type(args) == "table" and args or {}
    local coreX = args.x ~= nil and args.x or args.coreX
    local coreY = args.y ~= nil and args.y or args.coreY
    local coreZ = args.z ~= nil and args.z or args.coreZ
    local worldObject, hostMarker = Storage.findCoreHost(
        coreX, coreY, coreZ, args.coreObjectId, args.networkId, args.coreToken)
    if not worldObject then return nil, nil, nil, "coreHostMissing" end
    local networkId = tostring(hostMarker.networkId or "")
    local token = tostring(hostMarker.token or "")
    if networkId == "" or token == "" then return nil, nil, nil, "coreInvalid" end
    if args.networkId and tostring(args.networkId) ~= "" and tostring(args.networkId) ~= networkId then
        return nil, nil, nil, "coreChanged"
    end
    local network = Manager.getNetwork(networkId)
    if not network then
        Storage.unlockCoreHost(worldObject, token)
        return nil, nil, nil, "coreExpired"
    end
    normalizeCoreFields(network)
    if tostring(network.coreToken or "") ~= token then
        local unlocked = Storage.unlockCoreHost(worldObject, token)
        if network and type(network.pendingCoreUnlock) == "table"
            and tostring(network.pendingCoreUnlock.token or "") == token and unlocked then
            network.pendingCoreUnlock = nil
            Manager.save(network)
        end
        return nil, nil, nil, "coreExpired"
    end
    local playerPosition = Storage.positionOfPlayer(player)
    local corePosition = {
        x = Storage.number(coreX, 0),
        y = Storage.number(coreY, 0),
        z = Storage.integer(coreZ, 0),
    }
    if args.allowRemote ~= true and (not playerPosition or Storage.distance2D(playerPosition, corePosition) > Storage.CoreUseDistance
        or Storage.integer(playerPosition.z, 0) ~= Storage.integer(corePosition.z, 0)) then
        return nil, nil, nil, "tooFar"
    end
    if not Manager.canUse(player, network) then return nil, nil, nil, "notAllowed" end
    local objectId = tostring(hostMarker.objectId or "")
    local locked, lockReason = Storage.enforceCoreHostLock(worldObject, networkId, token)
    if not locked then return nil, nil, nil, lockReason end
    local resolvedState = "installed"
    local changed = type(network.coreHost) ~= "table"
        or Storage.integer(network.coreHost.x, -1) ~= Storage.integer(corePosition.x, 0)
        or Storage.integer(network.coreHost.y, -1) ~= Storage.integer(corePosition.y, 0)
        or Storage.integer(network.coreHost.z, -1) ~= Storage.integer(corePosition.z, 0)
        or tostring(network.coreHost.objectId or "") ~= tostring(objectId or "")
        or tostring(network.coreState or "") ~= resolvedState
    network.coreHost = {
        x = Storage.integer(corePosition.x, 0),
        y = Storage.integer(corePosition.y, 0),
        z = Storage.integer(corePosition.z, 0),
        objectId = objectId ~= "" and objectId or nil,
    }
    network.coreState = resolvedState
    network.coreItemId = nil
    if changed then
        network.revision = Storage.integer(network.revision, 0) + 1
        network.updatedAtMs = Storage.nowMs()
        transmitStore()
    end
    return network, worldObject, hostMarker, nil
end

function Manager.connectedNetwork(network, coreObject)
    if type(network) ~= "table" then return nil end
    if processPendingUnlock(network) then Manager.save(network) end
    if Storage.integer(network.topologyVersion, 0) < Storage.TopologyVersion then
        local migrated = {}
        for _, legacyLink in pairs(type(network.links) == "table" and network.links or {}) do
            local object = Storage.resolveLink(legacyLink)
            if object then
                local objectId = Storage.getObjectId(object, true)
                if objectId and not migrated[objectId] then
                    Storage.setNetworkContainerMarker(object, {
                        scopeKey = network.scopeKey,
                        owner = network.owner,
                        name = legacyLink.name,
                        role = legacyLink.role,
                        priority = legacyLink.priority,
                        allowCategories = legacyLink.allowCategories,
                        denyCategories = legacyLink.denyCategories,
                    })
                    migrated[objectId] = true
                end
                Storage.clearLinkMarker(object, legacyLink.slotIndex, legacyLink.linkId)
            end
        end
        network.links = {}
        network.topologyVersion = Storage.TopologyVersion
        network.maxLinks = Storage.MaxLinks
        network.radius = nil
        network.revision = Storage.integer(network.revision, 0) + 1
        transmitStore()
    end
    return Storage.discoverNetwork(network, coreObject)
end

function Manager.networkSummary(player, network)
    return {
        networkId = network.networkId,
        scope = network.scope,
        scopeKey = network.scopeKey,
        owner = network.owner,
        creator = network.creator,
        topologyMode = network.topologyMode or "physical",
        maxLinks = Storage.MaxLinks,
        linkCount = Manager.linkCount(network),
        nodeCount = Storage.integer(network.nodeCount, 0),
        truncated = network.truncated == true,
        connectedObjectIds = network.connectedObjectIds or {},
        revision = Storage.integer(network.revision, 0),
        canUse = Manager.canUse(player, network),
        canManage = Manager.canManage(player, network),
        isAdmin = Storage.isAdmin(player),
        coreHost = network.coreHost,
    }
end

function Manager.linkCount(network)
    local count = 0
    for _ in pairs((network and network.links) or {}) do count = count + 1 end
    return count
end

local function targetObject(player, targetArgs)
    local targetPosition = {
        x = Storage.integer(targetArgs.x, 0),
        y = Storage.integer(targetArgs.y, 0),
        z = Storage.integer(targetArgs.z, 0),
    }
    local playerPosition = Storage.positionOfPlayer(player)
    if not playerPosition or Storage.distance2D(playerPosition, targetPosition) > 2.5
        or Storage.integer(playerPosition.z, 0) ~= targetPosition.z then return nil, nil, "targetTooFar" end
    local object = Storage.resolveObjectCandidate(targetPosition.x, targetPosition.y, targetPosition.z, targetArgs.objectIndex, targetArgs.sprite)
    if not object then return nil, nil, "targetChanged" end
    if Storage.isCoreHost(object) then return nil, nil, "coreInstalled" end
    local slots = Storage.getContainerSlots(object)
    if #slots <= 0 then return nil, nil, "containerMissing" end
    for i = 1, #slots do
        local parent = safeCall(slots[i].container, "getParent", nil)
        if parent and parent ~= object then return nil, nil, "portableContainer" end
    end
    return object, targetPosition, nil
end

local function markerManageAllowed(player, marker, position)
    if Storage.isAdmin(player) then return true end
    local safehouse = Storage.getSafehouseAt(position.x, position.y)
    if safehouse then
        return tostring(marker.scopeKey or "") == tostring(Storage.safehouseKey(safehouse) or "")
            and Storage.playerAllowedSafehouse(player, safehouse)
    end
    return tostring(marker.owner or "") == Storage.playerKey(player)
end

function Manager.setNetworkContainer(player, targetArgs)
    targetArgs = type(targetArgs) == "table" and targetArgs or {}
    local object, position, reason = targetObject(player, targetArgs)
    if not object then return false, reason end
    local existing = Storage.getNetworkContainerMarker(object)
    local enabled = targetArgs.enabled == true
    if existing and not markerManageAllowed(player, existing, position) then return false, "manageDenied" end
    if not enabled then
        if not existing then return true, nil, { enabled = false } end
        if Storage.isCoreHost(object) then return false, "coreInstalled" end
        if not Storage.clearNetworkContainerMarker(object) then return false, "markerFailed" end
        return true, nil, { enabled = false, objectId = existing.objectId }
    end
    local scope, scopeKey, safehouse = Manager.scopeForPosition(player, position)
    if scope == "safehouse" and not (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
        return false, "notAllowed"
    end
    if existing and tostring(existing.scopeKey or "") ~= tostring(scopeKey or "") then return false, "alreadyLinked" end
    local slots = Storage.getContainerSlots(object)
    local defaultName = tostring(targetArgs.name or "")
    if defaultName == "" then defaultName = slots[1] and slots[1].type or "Container" end
    if not Storage.setNetworkContainerMarker(object, {
        scopeKey = scopeKey,
        owner = Storage.playerKey(player),
        name = existing and existing.name or defaultName,
        role = existing and existing.role or "auto",
        priority = existing and existing.priority or 50,
        allowCategories = existing and existing.allowCategories or {},
        denyCategories = existing and existing.denyCategories or {},
        markedAtMs = existing and existing.markedAtMs or Storage.nowMs(),
    }) then return false, "markerFailed" end
    return true, nil, Storage.getNetworkContainerMarker(object)
end

function Manager.linkContainer(player, _, targetArgs)
    targetArgs = type(targetArgs) == "table" and targetArgs or {}
    targetArgs.enabled = true
    return Manager.setNetworkContainer(player, targetArgs)
end

function Manager.unlinkContainer(player, coreArgs, linkId)
    local network, coreObject, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local view = Manager.connectedNetwork(network, coreObject)
    local link = view.links[tostring(linkId or "")]
    if not link then return false, "linkMissing" end
    local object = Storage.resolveLink(link)
    if not object then return false, "targetChanged" end
    if Storage.isCoreHost(object) then return false, "coreInstalled" end
    if not Storage.clearNetworkContainerMarker(object) then return false, "markerFailed" end
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

function Manager.updateLink(player, coreArgs, args)
    local network, coreObject, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    if not Manager.canManage(player, network) then return false, "manageDenied" end
    local view = Manager.connectedNetwork(network, coreObject)
    local link = view.links[tostring(args.linkId or "")]
    if not link then return false, "linkMissing" end
    local object = Storage.resolveLink(link)
    if not object then return false, "targetChanged" end
    local marker = Storage.getNetworkContainerMarker(object)
    if not marker then return false, "linkMissing" end
    if args.name ~= nil then marker.name = tostring(args.name):sub(1, 60) end
    if args.role ~= nil then
        if not validRole(args.role) then return false, "invalidRole" end
        marker.role = tostring(args.role)
    end
    if args.priority ~= nil then marker.priority = Storage.clamp(Storage.integer(args.priority, 50), 0, 100) end
    if type(args.allowCategories) == "table" then marker.allowCategories = normalizeCategoryRules(args.allowCategories) end
    if type(args.denyCategories) == "table" then marker.denyCategories = normalizeCategoryRules(args.denyCategories) end
    if not Storage.setNetworkContainerMarker(object, marker) then return false, "markerFailed" end
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil, marker
end

function Manager.updateLimits(player, coreArgs)
    local network, _, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    if not Storage.isAdmin(player) then return false, "adminOnly" end
    network.radius = nil
    network.maxLinks = Storage.MaxLinks
    network.revision = Storage.integer(network.revision, 0) + 1
    network.updatedAtMs = Storage.nowMs()
    transmitStore()
    return true, nil
end

function Manager.startIndex(player, coreArgs, callback)
    local network, coreObject, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    local connected = Manager.connectedNetwork(network, coreObject)
    local job = Storage.newIndexJob(connected)
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

function Manager.deposit(player, coreArgs, args)
    args = type(args) == "table" and args or {}
    local network, coreObject, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    local connected = Manager.connectedNetwork(network, coreObject)
    local mode = tostring(args.mode or "")
    if mode ~= "selected" and mode ~= "sourceAll" then return false, "invalidMode" end
    local source, sourceItem, sourceReason = Storage.resolvePlayerContainer(player, args.sourceItemId)
    if not source then return false, sourceReason end
    local stats = {
        requested = 0, success = 0, skipped = 0, failed = 0, coldDowngrade = 0, offline = 0,
        successItemIds = {}, failedItems = {}, skippedItemIds = {},
    }
    local candidates, seen = {}, {}
    local function failItem(id, itemReason)
        stats.failed = stats.failed + 1
        stats.failedItems[#stats.failedItems + 1] = { itemId = tostring(id or ""), reason = tostring(itemReason or "unknown") }
    end
    local function append(item, id)
        id = tostring(id or Storage.itemId(item) or "")
        if id ~= "" and not seen[id] then
            seen[id] = true
            stats.requested = stats.requested + 1
            if item then candidates[#candidates + 1] = { item = item, itemId = id, container = source }
            else failItem(id, "sourceChanged") end
        end
    end
    if mode == "sourceAll" then
        local items = safeCall(source, "getItems", nil)
        local size = Storage.integer(safeCall(items, "size", 0), 0)
        for i = 0, math.min(size - 1, Storage.MaxIndexedItems - 1) do
            local item = safeCall(items, "get", nil, i)
            append(item, Storage.itemId(item))
        end
    else
        for i = 1, math.min(#(args.itemIds or {}), Storage.MaxIndexedItems) do
            local id = tostring(args.itemIds[i] or "")
            if id ~= "" and not seen[id] then append(Storage.findDirectItem(source, id), id) end
        end
    end
    local fallbackSquare = Storage.getSquare(network.coreHost.x, network.coreHost.y, network.coreHost.z)
    for i = 1, #candidates do
        local row = candidates[i]
        local allowed, itemReason
        if mode == "sourceAll" then
            allowed, itemReason = Storage.isBulkDepositItem(player, row.item)
        else
            allowed, itemReason = Storage.isManualDepositItem(player, row.item)
        end
        if not allowed then
            if mode == "sourceAll" then
                stats.skipped = stats.skipped + 1
                stats.skippedItemIds[#stats.skippedItemIds + 1] = row.itemId
            else
                failItem(row.itemId, itemReason)
            end
        else
            local routes, downgraded = Storage.routeCandidates(connected, player, row.item)
            if #routes == 0 then
                failItem(row.itemId, "noRoute")
            else
                local moved = false
                local transferReason = "targetAddFailed"
                for j = 1, #routes do
                    local route = routes[j]
                    local function sourceValidator()
                        local current, currentItem = Storage.resolvePlayerContainer(player, args.sourceItemId)
                        return current == source and currentItem == sourceItem
                            and Storage.findDirectItem(source, row.itemId) == row.item
                    end
                    local function targetValidator()
                        local object, current = Storage.resolveLink(route.link)
                        return object ~= nil and current == route.container
                            and Storage.isWithinNetworkRange(connected, { x = route.link.x, y = route.link.y, z = route.link.z })
                    end
                    local ok, moveReason = Storage.transferItem(player, row.item, row.container, route.container,
                        fallbackSquare, sourceValidator, targetValidator)
                    transferReason = moveReason or transferReason
                    if ok then moved = true; break end
                    if not Storage.containerContains(row.container, row.item) then break end
                end
                if moved then
                    stats.success = stats.success + 1
                    stats.successItemIds[#stats.successItemIds + 1] = row.itemId
                    if downgraded then stats.coldDowngrade = stats.coldDowngrade + 1 end
                else
                    failItem(row.itemId, transferReason)
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

function Manager.withdraw(player, coreArgs, args)
    args = type(args) == "table" and args or {}
    local network, coreObject, _, reason = Manager.resolveCoreHost(player, coreArgs)
    if not network then return false, reason end
    local connected = Manager.connectedNetwork(network, coreObject)
    local job = Manager.latestJob(network.networkId, args.snapshotId)
    if not job then return false, "snapshotExpired" end
    local target, targetItem, targetReason = Storage.resolvePlayerContainer(player, args.targetItemId)
    if not target then return false, targetReason end
    local stats = {
        requested = 0, success = 0, skipped = 0, failed = 0, coldDowngrade = 0, offline = 0,
        successItemIds = {}, failedItems = {}, skippedItemIds = {},
    }
    local fallbackSquare = Storage.getSquare(network.coreHost.x, network.coreHost.y, network.coreHost.z)
    local selected, expectedIds, selectedIds = {}, {}, {}
    local requests = type(args.requests) == "table" and args.requests or {}
    local function selectInstance(instance, groupKey)
        local id = tostring(instance and instance.id or "")
        if id == "" or selectedIds[id] or #selected >= Storage.MaxIndexedItems then return end
        selectedIds[id] = true
        expectedIds[id] = true
        selected[#selected + 1] = { id = id, groupKey = tostring(groupKey or "") }
    end
    for i = 1, #requests do
        if #selected >= Storage.MaxIndexedItems then break end
        local request = type(requests[i]) == "table" and requests[i] or {}
        local groupKey = tostring(request.groupKey or "")
        local instances = job.instances[groupKey] or {}
        if type(request.itemIds) == "table" and #request.itemIds > 0 then
            local byId = {}
            for j = 1, #instances do byId[tostring(instances[j].id or "")] = instances[j] end
            for j = 1, #request.itemIds do
                local id = tostring(request.itemIds[j] or "")
                if byId[id] then selectInstance(byId[id], groupKey) end
            end
        else
            local wanted = Storage.clamp(Storage.integer(request.count, 1), 1, Storage.MaxIndexedItems)
            for j = 1, math.min(wanted, #instances) do selectInstance(instances[j], groupKey) end
        end
    end
    stats.requested = #selected
    if stats.requested == 0 then return false, "nothingMoved", stats end
    local liveItems = Storage.findNetworkItems(connected, expectedIds)
    for i = 1, #selected do
        local expected = selected[i]
        local live = liveItems[expected.id]
        local item, source = live and live.item or nil, live and live.source or nil
        if not item or not source or Storage.itemGroupKey(item) ~= expected.groupKey then
            stats.skipped = stats.skipped + 1
            stats.skippedItemIds[#stats.skippedItemIds + 1] = expected.id
        else
            local function sourceValidator()
                local object, current = Storage.resolveLink(live.link)
                return object ~= nil and current == source and Storage.containerContains(source, item)
                    and Storage.isWithinNetworkRange(connected, { x = live.link.x, y = live.link.y, z = live.link.z })
            end
            local function targetValidator()
                local current, currentItem = Storage.resolvePlayerContainer(player, args.targetItemId)
                return current == target and currentItem == targetItem
            end
            local ok, moveReason = Storage.transferItem(player, item, source, target, fallbackSquare,
                sourceValidator, targetValidator)
            if ok then
                stats.success = stats.success + 1
                stats.successItemIds[#stats.successItemIds + 1] = expected.id
            else
                stats.failed = stats.failed + 1
                stats.failedItems[#stats.failedItems + 1] = { itemId = expected.id, reason = tostring(moveReason or "unknown") }
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
