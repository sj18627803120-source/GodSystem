require "GodSystem_StorageUI"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISWorldObjectContextMenu"

GodSystemStorageContext = GodSystemStorageContext or {}

local Context = GodSystemStorageContext
local Storage = GodSystemStorage
local Client = GodSystemStorageClient

Context.connectMode = Context.connectMode == true
Context.highlighted = Context.highlighted or {}

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

local function worldItem(object)
    return Storage.safeCall(object, "getItem", nil)
end

local function controllerPosition(object)
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
end

function Context.highlight(object, r, g, b)
    if not object then return end
    if object.setHighlightColor then object:setHighlightColor(r or 0.1, g or 0.65, b or 0.9, 1) end
    if object.setHighlighted then object:setHighlighted(true) end
    Context.highlighted[object] = true
end

function Context.refreshHighlights()
    Context.clearHighlights()
    if not Context.connectMode then return end
    local player = playerByNumber(0)
    local position = Storage.positionOfPlayer(player)
    if not position then return end
    local connected = type(Client.networkState) == "table" and Client.networkState.connectedObjectIds or {}
    local controller = Client.controller or (type(Client.claimState) == "table" and Client.claimState.controller or nil)
    local controllerObject = type(controller) == "table" and controller.object or nil
    if not controllerObject and type(controller) == "table" then
        controllerObject = Storage.findWorldController(
            controller.x, controller.y, controller.z,
            controller.itemId, controller.token, controller.objectId
        )
    end
    if controllerObject then
        local controllerPosition = Storage.objectCoordinates(controllerObject)
        local safehouse = controllerPosition and Storage.getSafehouseAt(controllerPosition.x, controllerPosition.y) or nil
        local scopeKey
        if safehouse and (Storage.playerAllowedSafehouse(player, safehouse) or Storage.isAdmin(player)) then
            scopeKey = Storage.safehouseKey(safehouse)
        else
            scopeKey = "personal:" .. Storage.playerKey(player)
        end
        connected = Storage.discoverNetwork({
            scopeKey = scopeKey,
            controller = controllerPosition,
        }, controllerObject).connectedObjectIds
    end
    for x = Storage.integer(position.x, 0) - Storage.HighlightRadius, Storage.integer(position.x, 0) + Storage.HighlightRadius do
        for y = Storage.integer(position.y, 0) - Storage.HighlightRadius, Storage.integer(position.y, 0) + Storage.HighlightRadius do
            local objects = Storage.squareObjects(Storage.getSquare(x, y, position.z))
            for i = 1, #objects do
                local marker = Storage.getNetworkContainerMarker(objects[i])
                if marker then
                    if connected and connected[tostring(marker.objectId or "")] == true then
                        Context.highlight(objects[i], 0.12, 0.82, 0.42)
                    else
                        Context.highlight(objects[i], 0.12, 0.48, 0.92)
                    end
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

function Context.openController(_, payload)
    if not payload or not payload.identity or not payload.position then return end
    Client.open(payload.identity, payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.reclaimController(_, payload)
    if not payload or not payload.identity or not payload.position then return end
    Client.reclaim(payload.identity, payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.setNetworkContainer(_, payload)
    if not payload then return end
    Client.setNetworkContainer(payload)
end

local function addControllerOption(context, object)
    local item = worldItem(object)
    local identity = Storage.isController(object) and object or item
    if not Storage.isController(identity) then return false end
    local position = controllerPosition(object)
    if not position then return false end
    context:addOption(text("Storage_Context_Open", "Open system storage"), Context, Context.openController, {
        identity = identity,
        position = position,
        object = object,
    })
    context:addOption(text("Storage_Context_Reclaim", "Reclaim storage controller"), Context, Context.reclaimController, {
        identity = identity,
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
    if Storage.isController(object) or Storage.isInstalledController(object) then return false end
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
    local label = marker
        and text("Storage_Context_UnmarkNetwork", "Remove network container mark")
        or text("Storage_Context_MarkNetwork", "Mark as network container")
    context:addOption(label, Context, Context.setNetworkContainer, payload)
    return true
end

function Context.fillWorldMenu(playerNum, context, worldObjects, test)
    if test then return end
    local objects = collectWorldObjects(worldObjects)
    for i = 1, #objects do
        addControllerOption(context, objects[i])
    end
    if not Context.connectMode then return end
    for i = 1, #objects do
        local object = objects[i]
        addNetworkContainerOption(context, object)
    end
end

local function controllerNearby(player)
    local controller = Client.controller
    if not player or not controller then return false end
    local position = Storage.positionOfPlayer(player)
    return position and Storage.integer(position.z, 0) == Storage.integer(controller.z, 0)
        and Storage.distance2D(position, controller) <= Storage.ControllerUseDistance
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
    if not controllerNearby(p) then return end
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

Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldMenu)
Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldMenu)
Events.OnFillInventoryObjectContextMenu.Remove(Context.fillInventoryMenu)
Events.OnFillInventoryObjectContextMenu.Add(Context.fillInventoryMenu)
if Events.OnDisconnect then
    Events.OnDisconnect.Remove(Context.reset)
    Events.OnDisconnect.Add(Context.reset)
end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Remove(Context.reset)
    Events.OnMainMenuEnter.Add(Context.reset)
end

return Context
