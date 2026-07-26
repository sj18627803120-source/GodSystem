require "GodSystem_StorageUI"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISWorldObjectContextMenu"

GodSystemStorageContext = GodSystemStorageContext or {}

local Context = GodSystemStorageContext
local Storage = GodSystemStorage
local Client = GodSystemStorageClient

Context.connectMode = Context.connectMode == true
Context.highlighted = Context.highlighted or {}
Context.markers = Context.markers or {}
Context.markerCount = Context.markerCount or 0
Context.lineTexture = Context.lineTexture or nil

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function playerByNumber(playerNum)
    return getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
end

local function isInventoryItem(value)
    if not value then return false end
    if instanceof then
        local ok, result = pcall(instanceof, value, "InventoryItem")
        if ok then return result == true end
    end
    return value.getFullType ~= nil and value.getID ~= nil
end

local function appendItem(result, seen, item)
    if not isInventoryItem(item) then return end
    local id = Storage.itemId(item)
    if not id or seen[id] then return end
    seen[id] = true
    result[#result + 1] = item
end

local function collectInventoryItems(values)
    local result, seen = {}, {}
    for _, value in ipairs(values or {}) do
        if isInventoryItem(value) then
            appendItem(result, seen, value)
        elseif value and value.items then
            for _, item in ipairs(value.items) do appendItem(result, seen, item) end
        end
    end
    return result
end

local function collectWorldObjects(values)
    local result, seen = {}, {}
    for _, value in ipairs(values or {}) do
        local object = value
        if type(value) == "table" and value.object then object = value.object end
        if object and not seen[object] then seen[object] = true; result[#result + 1] = object end
    end
    return result
end

local function objectPosition(object)
    local square = Storage.safeCall(object, "getSquare", nil)
    if not square then return nil end
    return {
        x = Storage.integer(Storage.safeCall(square, "getX", 0), 0),
        y = Storage.integer(Storage.safeCall(square, "getY", 0), 0),
        z = Storage.integer(Storage.safeCall(square, "getZ", 0), 0),
    }
end

function Context.clearHighlights()
    for object in pairs(Context.highlighted) do
        if object and object.setHighlighted then object:setHighlighted(false) end
    end
    Context.highlighted = {}
    Context.markers = {}
    Context.markerCount = 0
end

local function cacheMarker(object, marker)
    local position = Storage.objectCoordinates(object)
    local objectId = marker and tostring(marker.objectId or "") or ""
    if not position or objectId == "" then return end
    if Context.markers[objectId] == nil then
        Context.markerCount = Context.markerCount + 1
    end
    Context.markers[objectId] = {
        x = position.x,
        y = position.y,
        z = position.z,
        coreHost = Storage.isCoreHost(object),
    }
end

local function screenPoint(x, y, z)
    if not ISCoordConversion or not ISCoordConversion.ToScreen then return nil, nil, nil end
    local sx, sy = ISCoordConversion.ToScreen(x, y, z)
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom, zoom
end

local function drawLine(renderer, texture, x1, y1, x2, y2, red, green, blue)
    if math.floor(x1) == math.floor(x2) then x2 = x2 + 1 end
    renderer:renderline(texture, math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2),
        red, green, blue, 0.95)
end

function Context.renderMarkers()
    if not Context.connectMode or Context.markerCount <= 0 then return end
    if not isIngameState or not isIngameState() then return end
    local renderer = getRenderer and getRenderer() or nil
    if not renderer then return end
    if not Context.lineTexture then
        Context.lineTexture = getTexture and getTexture("media/textures/mask_white.png") or nil
    end
    if not Context.lineTexture then return end
    for _, marker in pairs(Context.markers) do
        local sx, sy, zoom = screenPoint(marker.x + 0.5, marker.y + 0.5, marker.z)
        if sx and sy and zoom then
            local size = math.max(6, 10 / zoom)
            local stem = math.max(4, 7 / zoom)
            local cy = sy - math.max(20, 34 / zoom)
            local red, green, blue = 0.12, 0.48, 0.92
            if marker.coreHost then red, green, blue = 0.12, 0.82, 0.42 end
            drawLine(renderer, Context.lineTexture, sx, cy - size, sx + size, cy, red, green, blue)
            drawLine(renderer, Context.lineTexture, sx + size, cy, sx, cy + size, red, green, blue)
            drawLine(renderer, Context.lineTexture, sx, cy + size, sx - size, cy, red, green, blue)
            drawLine(renderer, Context.lineTexture, sx - size, cy, sx, cy - size, red, green, blue)
            drawLine(renderer, Context.lineTexture, sx, cy + size, sx, cy + size + stem, red, green, blue)
        end
    end
end

function Context.refreshHighlights()
    Context.clearHighlights()
    if not Context.connectMode then return end
    local player = playerByNumber(0)
    local position = Storage.positionOfPlayer(player)
    if not position then return end
    for x = Storage.integer(position.x, 0) - Storage.HighlightRadius, Storage.integer(position.x, 0) + Storage.HighlightRadius do
        for y = Storage.integer(position.y, 0) - Storage.HighlightRadius, Storage.integer(position.y, 0) + Storage.HighlightRadius do
            local objects = Storage.squareObjects(Storage.getSquare(x, y, position.z))
            for i = 1, #objects do
                local marker = Storage.getNetworkContainerMarker(objects[i])
                if marker then
                    cacheMarker(objects[i], marker)
                end
            end
        end
    end
end

function Context.setConnectMode(enabled)
    local nextValue = enabled == true
    local changed = Context.connectMode ~= nextValue
    Context.connectMode = nextValue
    if Context.connectMode then Context.refreshHighlights() else Context.clearHighlights() end
    if changed and GodSystem and GodSystem.notify then
        GodSystem.notify(Context.connectMode
            and text("Storage_Notify_ConnectModeOn", "Connection mode enabled. Right-click a nearby fixed container.")
            or text("Storage_Notify_ConnectModeOff", "Connection mode disabled."))
    end
end

function Context.toggleConnectMode()
    Context.setConnectMode(not Context.connectMode)
end

function Context.openCoreHost(_, payload)
    if not payload or not payload.position then return end
    Client.open(payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.retrieveCore(_, payload)
    if not payload or not payload.position then return end
    Client.retrieveCore(payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.installCore(_, payload)
    if payload then Client.installCore(payload) end
end

function Context.setNetworkContainer(_, payload)
    if not payload then return end
    Client.setNetworkContainer(payload)
end

local function addCoreHostOptions(context, object)
    if not Storage.isCoreHost(object) then return false end
    local position = objectPosition(object)
    if not position then return false end
    context:addOption(text("Storage_Context_Open", "Open system storage"), Context, Context.openCoreHost, {
        position = position,
        object = object,
    })
    context:addOption(text("Storage_Context_RetrieveCore", "Retrieve storage core"), Context, Context.retrieveCore, {
        position = position,
        object = object,
    })
    return true
end

local function addNetworkContainerOption(context, object)
    local position = Storage.objectCoordinates(object)
    if not position then return false end
    local slots = Storage.getContainerSlots(object)
    if #slots <= 0 then return false end
    local objectIndex = Storage.getObjectIndex(object)
    if objectIndex < 0 then return false end
    local marker = Storage.getNetworkContainerMarker(object)
    local payload = {
        x = position.x, y = position.y, z = position.z,
        objectIndex = objectIndex,
        sprite = Storage.objectSpriteName(object),
        enabled = marker == nil,
        name = marker and marker.name or (slots[1].type ~= "" and slots[1].type or text("Storage_Container", "Container")),
    }
    if marker and Storage.isCoreHost(object) then return false end
    local label = marker
        and text("Storage_Context_UnmarkNetwork", "Remove network container mark")
        or text("Storage_Context_MarkNetwork", "Mark as network container")
    context:addOption(label, Context, Context.setNetworkContainer, payload)
    return true
end

local function addInstallCoreOption(context, object)
    if not Client.findCarriedCore or not Client.findCarriedCore() then return false end
    local marker = Storage.getNetworkContainerMarker(object)
    if not marker or Storage.isCoreHost(object) then return false end
    if not Storage.coreHostIsEmpty(object) then return false end
    local position = Storage.objectCoordinates(object)
    local objectIndex = Storage.getObjectIndex(object)
    if not position or objectIndex < 0 then return false end
    context:addOption(text("Storage_Context_InstallCore", "Install storage core"), Context, Context.installCore, {
        x = position.x, y = position.y, z = position.z,
        objectIndex = objectIndex,
        sprite = Storage.objectSpriteName(object),
    })
    return true
end

function Context.fillWorldMenu(playerNum, context, worldObjects, test)
    if test then return end
    local objects = collectWorldObjects(worldObjects)
    for i = 1, #objects do
        addCoreHostOptions(context, objects[i])
        addInstallCoreOption(context, objects[i])
    end
    if not Context.connectMode then return end
    for i = 1, #objects do
        local object = objects[i]
        addNetworkContainerOption(context, object)
    end
end

local function coreNearby(player)
    local core = Client.core
    if not player or not core then return false end
    local position = Storage.positionOfPlayer(player)
    return position and Storage.integer(position.z, 0) == Storage.integer(core.z, 0)
        and Storage.distance2D(position, core) <= Storage.CoreUseDistance
end

local function isInPlayerInventory(player, item)
    local container = Storage.getItemContainer(item)
    if not player or not container then return false end
    if container == Storage.safeCall(player, "getInventory", nil) then return true end
    if container.isInCharacterInventory then
        local ok, result = pcall(function() return container:isInCharacterInventory(player) end)
        if ok then return result == true end
    end
    return false
end

function Context.depositSelected(_, payload)
    local itemIds = {}
    for i = 1, #(payload.items or {}) do
        local id = Storage.itemId(payload.items[i])
        if id then itemIds[#itemIds + 1] = id end
    end
    if #itemIds > 0 then Client.depositItems(itemIds) end
end

function Context.fillInventoryMenu(playerNum, context, items)
    local p = playerByNumber(playerNum)
    local selected = collectInventoryItems(items)
    if not coreNearby(p) then return end
    local eligible = {}
    for i = 1, #selected do
        local allowed = Storage.isSafeDepositItem(p, selected[i])
        if allowed and isInPlayerInventory(p, selected[i]) then eligible[#eligible + 1] = selected[i] end
    end
    if #eligible <= 0 then return end
    local label = text("Storage_Context_DepositSelected", "Deposit selected into system storage")
        .. " (" .. tostring(#eligible) .. ")"
    context:addOption(label, Context, Context.depositSelected, { items = eligible })
end

function Context.reset()
    Context.connectMode = false
    Context.clearHighlights()
end

function Context.onLoadGridSquare(square)
    if not (isClient and isClient()) then
        GodSystemStorageManager.calibrateLoadedSquare(square)
    end
end

Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldMenu)
Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldMenu)
Events.OnFillInventoryObjectContextMenu.Remove(Context.fillInventoryMenu)
Events.OnFillInventoryObjectContextMenu.Add(Context.fillInventoryMenu)
if Events.OnPreUIDraw then
    Events.OnPreUIDraw.Remove(Context.renderMarkers)
    Events.OnPreUIDraw.Add(Context.renderMarkers)
end
if Events.OnDisconnect then
    Events.OnDisconnect.Remove(Context.reset)
    Events.OnDisconnect.Add(Context.reset)
end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Remove(Context.reset)
    Events.OnMainMenuEnter.Add(Context.reset)
end
if Events.LoadGridsquare then
    Events.LoadGridsquare.Remove(Context.onLoadGridSquare)
    Events.LoadGridsquare.Add(Context.onLoadGridSquare)
end

return Context
