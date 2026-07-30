require "GodSystem_Storage"

GodSystemStorageClient = GodSystemStorageClient or {}

local Client = GodSystemStorageClient
local Storage = GodSystemStorage

Client.snapshot = Client.snapshot or nil
Client.snapshotBuilding = Client.snapshotBuilding or nil
Client.details = Client.details or {}
Client.core = Client.core or nil
Client.pending = Client.pending or {}
Client.lastError = Client.lastError or nil
Client.claimState = Client.claimState or nil
Client.organizer = Client.organizer or { state = "idle" }
Client.statusRequestedAtMs = Client.statusRequestedAtMs or 0
Client.networkState = Client.networkState or nil
Client.indexing = Client.indexing == true

local function player()
    return getPlayer and getPlayer() or nil
end

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local reasonKeys = {
    coreMissing = "Storage_Error_CoreMissing",
    coreHostMissing = "Storage_Error_CoreHostMissing",
    coreInvalid = "Storage_Error_CoreInvalid",
    coreChanged = "Storage_Error_CoreChanged",
    coreExpired = "Storage_Error_CoreExpired",
    coreOwned = "Storage_Error_CoreOwned",
    coreInstalled = "Storage_Error_CoreInstalled",
    networkContainerRequired = "Storage_Error_NetworkContainerRequired",
    currencyNotEnough = "Storage_Error_CurrencyNotEnough",
    tooFar = "Storage_Error_TooFar",
    notAllowed = "Storage_Error_NotAllowed",
    manageDenied = "Storage_Error_ManageDenied",
    linkLimit = "Storage_Error_LinkLimit",
    outOfRange = "Storage_Error_OutOfRange",
    targetTooFar = "Storage_Error_TargetTooFar",
    targetInvalid = "Storage_Error_TargetInvalid",
    targetChanged = "Storage_Error_TargetChanged",
    containerMissing = "Storage_Error_ContainerMissing",
    alreadyLinked = "Storage_Error_AlreadyLinked",
    portableContainer = "Storage_Error_Portable",
    snapshotExpired = "Storage_Error_SnapshotExpired",
    nothingMoved = "Storage_Error_NothingMoved",
    operationPending = "Storage_Error_OperationPending",
    operationMismatch = "Storage_Error_OperationMismatch",
    adminOnly = "Storage_Error_AdminOnly",
    markerFailed = "Storage_Error_MarkerFailed",
    organizerRunning = "Storage_Error_OrganizerRunning",
}

function Client.notifyReason(reason)
    reason = tostring(reason or "unknown")
    local key = reasonKeys[reason] or "Storage_Error_Generic"
    local message = text(key, "Storage operation failed: {1}")
        :gsub("{1}", reason)
    if GodSystem and GodSystem.notify then GodSystem.notify(message) end
end

function Client.newOperationId(command)
    return Storage.newId("op-" .. tostring(command or "storage"),
        Storage.playerKey(player()))
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

function Client.setCoreHost(x, y, z, object)
    local marker = object and Storage.getCoreHostMarker(object) or nil
    local networkId = marker and tostring(marker.networkId or "") or ""
    local token = marker and tostring(marker.token or "") or ""
    if networkId == "" or token == "" then return false end
    if Client.core and tostring(Client.core.networkId or "") ~= networkId then
        Client.networkState = nil
        Client.snapshot = nil
    end
    local objectId = tostring(marker.objectId or "")
    Client.core = {
        x = Storage.integer(x, 0),
        y = Storage.integer(y, 0),
        z = Storage.integer(z, 0),
        token = token,
        networkId = networkId,
        objectId = objectId ~= "" and objectId or nil,
        object = object,
    }
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

function Client.findCarriedCore()
    local inventory = Storage.safeCall(player(), "getInventory", nil)
    if not inventory then return nil end
    local status = Client.claimState or {}
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
        for index = 0, size - 1 do
            local item = Storage.safeCall(items, "get", nil, index)
            local networkId, token = Storage.getCoreIdentity(item)
            if Storage.isCore(item) and tostring(networkId or "") ~= ""
                and tostring(token or "") ~= ""
            then
                return item
            end
            local nested = visit(Storage.safeCall(item, "getInventory", nil),
                depth + 1)
            if nested then return nested end
        end
        return nil
    end
    return visit(inventory, 0)
end

function Client.reset()
    Client.snapshot = nil
    Client.snapshotBuilding = nil
    Client.details = {}
    Client.core = nil
    Client.pending = {}
    Client.networkState = nil
    Client.claimState = nil
    Client.organizer = { state = "idle" }
    Client.statusRequestedAtMs = 0
    Client.indexing = false
    if GodSystemStorageUI and GodSystemStorageUI.close then
        GodSystemStorageUI.close()
    end
end

local adapterMethods = {
    "requestCoreStatus", "claimCore", "installCore", "retrieveCore", "open",
    "refresh", "refreshNetworkState", "requestDetails",
    "setNetworkContainer", "link", "unlink", "updateLink", "updateLimits",
    "startOrganizer", "stopOrganizer", "requestOrganizerStatus", "takeOver",
    "depositItems", "depositAll", "withdrawRequests", "withdraw",
    "withdrawExact",
}

local function adapterMissing()
    error("modular storage adapter is not installed")
end

for index = 1, #adapterMethods do
    Client[adapterMethods[index]] = adapterMissing
end

return Client
