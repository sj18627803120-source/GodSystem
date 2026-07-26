require "GodSystem_StorageUI"
require "BuildingObjects/ISBuildingObject"
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

local ControllerPlacement = ISBuildingObject:derive("GodSystemStorageControllerPlacement")

function ControllerPlacement:isValid(square)
    local player = playerByNumber(self.player)
    if not square or not player or not self.item then return false end
    if Storage.itemId(self.item) ~= tostring(self.itemId or "") then return false end
    local networkId, token = Storage.getControllerIdentity(self.item)
    if networkId == "" or token == "" then return false end
    local position = {
        x = Storage.integer(Storage.safeCall(square, "getX", 0), 0),
        y = Storage.integer(Storage.safeCall(square, "getY", 0), 0),
        z = Storage.integer(Storage.safeCall(square, "getZ", 0), 0),
    }
    local playerPosition = Storage.positionOfPlayer(player)
    if not playerPosition
        or Storage.integer(playerPosition.z, -1) ~= position.z
        or Storage.distance2D(playerPosition, position) > Storage.ControllerPlacementDistance then
        return false
    end
    if Storage.safeCall(square, "isVehicleIntersecting", false) == true then return false end
    if not Storage.safeCall(square, "getFloor", nil) then return false end
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local object = objects[i]
        if Storage.isInstalledController(object)
            or Storage.isController(Storage.safeCall(object, "getItem", nil)) then
            return false
        end
    end
    return true
end

function ControllerPlacement:render(x, y, z, square)
    local cursor = self:getFloorCursorSprite()
    if self:isValid(square) then
        cursor:RenderGhostTileColor(x, y, z, 0, 0, 0.12, 0.72, 0.95, 0.75)
    else
        cursor:RenderGhostTileColor(x, y, z, 0, 0, 0.85, 0.12, 0.12, 0.75)
    end
end

function ControllerPlacement:create(x, y, z)
    getCell():setDrag(nil, self.player)
    Client.installController(self.item, x, y, z)
end

function ControllerPlacement:tryBuild(x, y, z)
    local square = getCell():getGridSquare(x, y, z)
    if not self:isValid(square) then return nil end
    self:create(x, y, z)
    return nil
end

function ControllerPlacement:new(playerNum, item)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    o.player = playerNum or 0
    o.character = playerByNumber(o.player)
    o.item = item
    o.itemId = Storage.itemId(item)
    o.name = "GodSystem Storage Controller"
    o.noNeedHammer = true
    o.skipBuildAction = true
    o.dragNilAfterPlace = true
    o.canBeAlwaysPlaced = true
    o.blockAllTheSquare = false
    o.canPassThrough = true
    o:setSprite("carpentry_02_56")
    o:setNorthSprite("carpentry_02_56")
    return o
end

function ControllerPlacement.start(playerNum, item)
    local cursor = ControllerPlacement:new(playerNum, item)
    getCell():setDrag(cursor, playerNum or 0)
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
        if object and object.setHighlighted then pcall(function() object:setHighlighted(false) end) end
    end
    Context.highlighted = {}
end

function Context.highlight(object, r, g, b)
    if not object then return end
    if object.setHighlightColor then pcall(function() object:setHighlightColor(r or 0.1, g or 0.65, b or 0.9, 1) end) end
    if object.setHighlighted then pcall(function() object:setHighlighted(true) end) end
    Context.highlighted[object] = true
end

function Context.setConnectMode(enabled)
    Context.connectMode = enabled == true
    if not Context.connectMode then Context.clearHighlights() end
    if GodSystem and GodSystem.notify then
        GodSystem.notify(Context.connectMode
            and text("Storage_Notify_ConnectModeOn", "Connection mode enabled. Right-click a nearby fixed container.")
            or text("Storage_Notify_ConnectModeOff", "Connection mode disabled."))
    end
end

function Context.toggleConnectMode()
    Context.setConnectMode(not Context.connectMode)
end

function Context.openController(_, payload)
    if not payload or not payload.item or not payload.position then return end
    Client.open(payload.item, payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.reclaimController(_, payload)
    if not payload or not payload.item or not payload.position then return end
    Client.reclaim(payload.item, payload.position.x, payload.position.y, payload.position.z, payload.object)
end

function Context.installController(_, payload)
    if not payload or not payload.item then return end
    ControllerPlacement.start(payload.playerNum or 0, payload.item)
end

function Context.linkContainer(_, payload)
    if not payload then return end
    Client.link(payload)
end

local function addControllerOption(context, object)
    local item = worldItem(object)
    if not Storage.isController(item) then return false end
    local position = controllerPosition(object)
    if not position then return false end
    Context.highlight(object, 0.08, 0.65, 0.92)
    context:addOption(text("Storage_Context_Open", "Open system storage"), Context, Context.openController, {
        item = item,
        position = position,
        object = object,
    })
    if Storage.isInstalledController(object) then
        context:addOption(text("Storage_Context_Reclaim", "Reclaim storage controller"), Context, Context.reclaimController, {
            item = item,
            position = position,
            object = object,
        })
    end
    return true
end

local function removeNativeChargerOption(context, object)
    if not context or not object or not Storage.isInstalledController(object) then return end
    if not instanceof then return end
    local ok, isCharger = pcall(instanceof, object, "IsoCarBatteryCharger")
    if not ok or not isCharger then return end
    local fetched = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
        and ISWorldObjectContextMenu.fetchVars.carBatteryCharger or nil
    if fetched and fetched ~= object then return end
    if context.removeOptionByName and getText then
        pcall(function() context:removeOptionByName(getText("ContextMenu_CarBatteryCharger")) end)
    end
end

local function addLinkOptions(context, object)
    local position = Storage.objectCoordinates(object)
    if not position then return false end
    local slots = Storage.getContainerSlots(object)
    if #slots <= 0 then return false end
    Context.highlight(object, 0.15, 0.85, 0.55)
    local objectIndex = Storage.getObjectIndex(object)
    if objectIndex < 0 then return false end
    local base = {
        x = position.x, y = position.y, z = position.z,
        objectIndex = objectIndex,
        sprite = Storage.objectSpriteName(object),
        priority = 50,
        role = "auto",
    }
    if #slots == 1 then
        local slot = slots[1]
        local payload = {}
        for key, value in pairs(base) do payload[key] = value end
        payload.slotIndex = slot.index
        payload.name = slot.type ~= "" and slot.type or text("Storage_Container", "Container")
        context:addOption(text("Storage_Context_Link", "Connect to system storage"), Context, Context.linkContainer, payload)
        return true
    end
    local root = context:addOption(text("Storage_Context_Link", "Connect to system storage"), nil, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(root, submenu)
    for i = 1, #slots do
        local slot = slots[i]
        local payload = {}
        for key, value in pairs(base) do payload[key] = value end
        payload.slotIndex = slot.index
        payload.name = slot.type ~= "" and slot.type or (text("Storage_Container", "Container") .. " " .. tostring(i))
        submenu:addOption(payload.name, Context, Context.linkContainer, payload)
    end
    return true
end

function Context.fillWorldMenu(playerNum, context, worldObjects, test)
    if test then return end
    local objects = collectWorldObjects(worldObjects)
    local sawController = false
    for i = 1, #objects do
        removeNativeChargerOption(context, objects[i])
        if addControllerOption(context, objects[i]) then sawController = true end
    end
    if not Context.connectMode or not Client.controller then return end
    for i = 1, #objects do
        local object = objects[i]
        if not Storage.isController(worldItem(object)) then addLinkOptions(context, object) end
    end
    if sawController and GodSystemStorageUI and GodSystemStorageUI.window then
        Context.highlighted = Context.highlighted or {}
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
    for i = 1, #selected do
        if Storage.isController(selected[i]) then
            context:addOption(text("Storage_Context_Install", "Install storage controller"), Context, Context.installController, {
                playerNum = playerNum,
                item = selected[i],
            })
            break
        end
    end
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
