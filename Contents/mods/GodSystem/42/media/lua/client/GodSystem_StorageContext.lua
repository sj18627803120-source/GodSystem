require "GodSystem_StorageUI"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISWorldObjectContextMenu"

GodSystemStorageContext = GodSystemStorageContext or {}

local Context = GodSystemStorageContext
local UI = GodSystemStorageUI
local Storage = GodSystemStorage
local Client = GodSystemStorageClient

Context.connectMode = Context.connectMode == true
Context.highlighted = Context.highlighted or {}
Context.markers = Context.markers or {}
Context.markerCount = Context.markerCount or 0
Context.lineTexture = Context.lineTexture or nil
Context.RefreshIntervalMs = 5000
Context.lastRefreshMs = Context.lastRefreshMs or 0

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

function Context.clearTemporaryHighlights()
    for object, playerNum in pairs(Context.highlighted) do
        if object and object.setHighlighted then
            pcall(function() object:setHighlighted(Storage.integer(playerNum, 0), false) end)
        end
    end
    Context.highlighted = {}
end

function Context.clearHighlights()
    Context.clearTemporaryHighlights()
    Context.markers = {}
    Context.markerCount = 0
end

local function connectedObjectIds()
    return type(Client.networkState) == "table" and type(Client.networkState.connectedObjectIds) == "table"
        and Client.networkState.connectedObjectIds or {}
end

local function candidateRows(square)
    local rows = {}
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local object = objects[i]
        if #Storage.getContainerSlots(object) > 0 and Storage.getObjectIndex(object) >= 0 then
            rows[#rows + 1] = object
        end
    end
    table.sort(rows, function(a, b)
        local ai, bi = Storage.getObjectIndex(a), Storage.getObjectIndex(b)
        if ai ~= bi then return ai < bi end
        local as, bs = Storage.objectSpriteName(a), Storage.objectSpriteName(b)
        if as ~= bs then return as < bs end
        return tostring(a) < tostring(b)
    end)
    return rows
end

local function candidateNumber(object)
    local square = Storage.safeCall(object, "getSquare", nil)
    local rows = candidateRows(square)
    for i = 1, #rows do if rows[i] == object then return i end end
    return 1
end

local function markerHorizontalSlot(number)
    number = math.max(1, Storage.integer(number, 1))
    if number == 1 then return 0 end
    local distance = math.floor(number / 2)
    return number % 2 == 0 and -distance or distance
end

local function markerChevronCount(number)
    return math.min(3, math.max(1, Storage.integer(number, 1)))
end

local function candidateLevelLabel(number, total)
    number = math.max(1, Storage.integer(number, 1))
    total = math.max(1, Storage.integer(total, 1))
    if total == 2 then
        return number == 1 and text("Storage_Level_Low", "Low") or text("Storage_Level_High", "High")
    end
    if total == 3 then
        if number == 1 then return text("Storage_Level_Low", "Low") end
        if number == 2 then return text("Storage_Level_Middle", "Middle") end
        return text("Storage_Level_High", "High")
    end
    return "#" .. tostring(number)
end

Context.candidateRows = candidateRows
Context.candidateNumber = candidateNumber
Context.markerHorizontalSlot = markerHorizontalSlot
Context.markerChevronCount = markerChevronCount
Context.candidateLevelLabel = candidateLevelLabel

local function cacheMarker(object, marker, number, total)
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
        number = number or candidateNumber(object),
        total = total or 1,
        coreHost = Storage.isCoreHost(object),
        connected = connectedObjectIds()[objectId] == true,
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
        Context.lineTexture = getTexture and getTexture("media/textures/GodSystem_WhitePixel.png") or nil
    end
    if not Context.lineTexture then return end
    for _, marker in pairs(Context.markers) do
        local sx, sy, zoom = screenPoint(marker.x + 0.5, marker.y + 0.5, marker.z)
        if sx and sy and zoom then
            local size = math.max(4, 7 / zoom)
            local step = math.max(5, 8 / zoom)
            local spacing = math.max(12, 18 / zoom)
            local stem = math.max(3, 5 / zoom)
            sx = sx + (markerHorizontalSlot(marker.number) * spacing)
            local baseY = sy - math.max(30, 46 / zoom)
            local red, green, blue = 0.86, 0.26, 0.28
            if marker.connected then red, green, blue = 0.12, 0.48, 0.92 end
            if marker.coreHost then red, green, blue = 0.12, 0.82, 0.42 end
            local count = markerChevronCount(marker.number)
            for level = 1, count do
                local cy = baseY - ((level - 1) * step)
                drawLine(renderer, Context.lineTexture, sx - size, cy + size, sx, cy, red, green, blue)
                drawLine(renderer, Context.lineTexture, sx, cy, sx + size, cy + size, red, green, blue)
            end
            drawLine(renderer, Context.lineTexture, sx, baseY + size, sx, baseY + size + stem, red, green, blue)
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
            local objects = candidateRows(Storage.getSquare(x, y, position.z))
            for i = 1, #objects do
                local marker = Storage.getNetworkContainerMarker(objects[i])
                if marker then
                    cacheMarker(objects[i], marker, i, #objects)
                end
            end
        end
    end
end

local function colorForObject(object)
    if Storage.isCoreHost(object) then return 0.12, 0.82, 0.42 end
    local marker = Storage.getNetworkContainerMarker(object)
    if marker then
        local objectId = tostring(marker.objectId or "")
        if connectedObjectIds()[objectId] == true then return 0.12, 0.48, 0.92 end
        return 0.86, 0.26, 0.28
    end
    return 0.80, 0.74, 0.30
end


Context.colorForObject = colorForObject

function Context.onOptionHighlight(_, menu, highlighted, object)
    if not object or not object.setHighlighted then return end
    local playerNum = Storage.integer(menu and menu.player, 0)
    if not highlighted then
        pcall(function() object:setHighlighted(playerNum, false) end)
        Context.highlighted[object] = nil
        return
    end
    Context.clearTemporaryHighlights()
    local red, green, blue = colorForObject(object)
    pcall(function()
        object:setHighlightColor(playerNum, ColorInfo.new(red, green, blue, 1))
        object:setHighlighted(playerNum, true, false)
    end)
    Context.highlighted[object] = playerNum
end

local function configureOption(option, object)
    if option then
        option.onHighlightParams = { object }
        option.onHighlight = Context.onOptionHighlight
    end
    return option
end

local function numberedLabel(number, total, label)
    return "[" .. candidateLevelLabel(number, total) .. "] " .. tostring(label or "")
end

function Context.setConnectMode(enabled)
    local nextValue = enabled == true
    local changed = Context.connectMode ~= nextValue
    Context.connectMode = nextValue
    if Context.connectMode then
        Context.lastRefreshMs = 0
        Context.refreshConnectionState(true)
    else
        Context.lastRefreshMs = 0
        Context.clearHighlights()
    end
    if changed and GodSystem and GodSystem.notify then
        GodSystem.notify(Context.connectMode
            and text("Storage_Notify_ConnectModeOn", "Connection mode enabled. Right-click a nearby fixed container.")
            or text("Storage_Notify_ConnectModeOff", "Connection mode disabled."))
    end
end

function Context.toggleConnectMode()
    Context.setConnectMode(not Context.connectMode)
    return Context.connectMode
end

function Context.refreshConnectionState(force)
    if not Context.connectMode then return false end
    local now = Storage.nowMs()
    if force ~= true and now - (Context.lastRefreshMs or 0) < Context.RefreshIntervalMs then return false end
    Context.lastRefreshMs = now
    local requested = Client.refreshNetworkState and Client.refreshNetworkState() or false
    if requested == false or (isClient and isClient()) then Context.refreshHighlights() end
    return requested ~= false
end

function Context.onTick()
    if Context.connectMode then Context.refreshConnectionState(false) end
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

local function addCoreHostOptions(context, object, number, total)
    if not Storage.isCoreHost(object) then return false end
    local position = objectPosition(object)
    if not position then return false end
    configureOption(context:addOption(numberedLabel(number, total, text("Storage_Context_Open", "Open system storage")), Context, Context.openCoreHost, {
        position = position,
        object = object,
    }), object)
    configureOption(context:addOption(numberedLabel(number, total, text("Storage_Context_RetrieveCore", "Retrieve storage core")), Context, Context.retrieveCore, {
        position = position,
        object = object,
    }), object)
    return true
end

local function addNetworkContainerOption(context, object, number, total)
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
    configureOption(context:addOption(numberedLabel(number, total, label), Context, Context.setNetworkContainer, payload), object)
    return true
end

local function addInstallCoreOption(context, object, number, total)
    if not Client.findCarriedCore or not Client.findCarriedCore() then return false end
    local marker = Storage.getNetworkContainerMarker(object)
    if not marker or Storage.isCoreHost(object) then return false end
    local position = Storage.objectCoordinates(object)
    local objectIndex = Storage.getObjectIndex(object)
    if not position or objectIndex < 0 then return false end
    configureOption(context:addOption(numberedLabel(number, total, text("Storage_Context_InstallCore", "Install storage core")), Context, Context.installCore, {
        x = position.x, y = position.y, z = position.z,
        objectIndex = objectIndex,
        sprite = Storage.objectSpriteName(object),
    }), object)
    return true
end

function Context.fillWorldMenu(playerNum, context, worldObjects, test)
    if test then return end
    Context.clearTemporaryHighlights()
    local clicked = collectWorldObjects(worldObjects)
    local squares, seenSquares = {}, {}
    for i = 1, #clicked do
        local square = Storage.safeCall(clicked[i], "getSquare", nil)
        if square and not seenSquares[square] then seenSquares[square] = true; squares[#squares + 1] = square end
    end
    for s = 1, #squares do
        local objects = candidateRows(squares[s])
        for i = 1, #objects do
            addCoreHostOptions(context, objects[i], i, #objects)
            addInstallCoreOption(context, objects[i], i, #objects)
            if Context.connectMode then addNetworkContainerOption(context, objects[i], i, #objects) end
        end
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
    if #itemIds > 0 then
        if not UI.window then UI.open() end
        UI.depositExternalSelection(payload.items, payload.sourceItemId)
    end
end

local function sourceItemIdForSelection(player, items)
    local root = Storage.safeCall(player, "getInventory", nil)
    local source = items[1] and Storage.getItemContainer(items[1]) or nil
    if not root or not source then return nil, false end
    for i = 2, #items do if Storage.getItemContainer(items[i]) ~= source then return nil, false end end
    if source == root then return nil, true end
    local roots = Storage.safeCall(root, "getItems", nil)
    local size = Storage.integer(Storage.safeCall(roots, "size", 0), 0)
    for i = 0, size - 1 do
        local item = Storage.safeCall(roots, "get", nil, i)
        if Storage.safeCall(item, "getInventory", nil) == source and Storage.isPlayerSourceItem(player, item) then
            return Storage.itemId(item), true
        end
    end
    return nil, false
end

function Context.fillInventoryMenu(playerNum, context, items)
    local p = playerByNumber(playerNum)
    local selected = collectInventoryItems(items)
    if not coreNearby(p) then return end
    local sourceItemId, sourceValid = sourceItemIdForSelection(p, selected)
    if not sourceValid then return end
    local eligible = {}
    for i = 1, #selected do
        local allowed = Storage.isManualDepositItem(p, selected[i])
        if allowed and isInPlayerInventory(p, selected[i]) then eligible[#eligible + 1] = selected[i] end
    end
    if #eligible <= 0 then return end
    local label = text("Storage_Context_DepositSelected", "Deposit selected into system storage")
        .. " (" .. tostring(#eligible) .. ")"
    context:addOption(label, Context, Context.depositSelected, { items = eligible, sourceItemId = sourceItemId })
end

function Context.reset()
    Context.connectMode = false
    Context.lastRefreshMs = 0
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
if Events.OnTick then
    Events.OnTick.Remove(Context.onTick)
    Events.OnTick.Add(Context.onTick)
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
