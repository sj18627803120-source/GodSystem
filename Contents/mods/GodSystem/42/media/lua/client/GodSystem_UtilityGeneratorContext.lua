require "GodSystem_UtilityGenerator"
require "GodSystem_Protocol"
require "GodSystem_B42JavaCalls"
require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISTextBox"
require "ISBaseObject"

if isServer and isServer() and not (isClient and isClient()) then return end

GodSystemUtilityGeneratorContext = GodSystemUtilityGeneratorContext or {}
local Context = GodSystemUtilityGeneratorContext
local Utility = GodSystemUtilityGenerator
local Protocol = GodSystemProtocol or {}
local function value(target, method, fallback, ...)
    return GodSystemB42JavaCalls.value(target, method, fallback, ...)
end

local function runtime()
    return GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime or nil
end

local function text(key, fallback)
    local service = runtime()
    return service and service.text and service.text(key, fallback) or fallback or key
end

local function notify(message)
    local service = runtime()
    if service and service.notify then service.notify(message) end
end

local function notifyCode(code)
    notify(text("Notify_" .. tostring(code or ""), tostring(code or "")))
end

local function findById(container, id)
    if not container or not container.getItems then return nil, nil end
    local items = value(container, "getItems", nil)
    local count = math.max(0, math.floor(tonumber(value(items, "size", 0)) or 0))
    for index = 0, count - 1 do
        local item = value(items, "get", nil, index)
        if item and Utility.itemId(item) == tostring(id or "") then return item, container end
        local child = item and value(item, "getInventory", nil) or nil
        local found, source = findById(child, id)
        if found then return found, source end
    end
    return nil, nil
end

local function playerInventory(player)
    return player and value(player, "getInventory", nil) or nil
end

local function findPlayerItem(player, id)
    return findById(playerInventory(player), id)
end

local function findByType(container, fullType)
    if not container or not container.getItems then return nil end
    local items = value(container, "getItems", nil)
    local count = math.max(0, math.floor(tonumber(value(items, "size", 0)) or 0))
    for index = 0, count - 1 do
        local item = value(items, "get", nil, index)
        if item and Utility.itemFullType(item) == fullType then return item end
        local child = item and value(item, "getInventory", nil) or nil
        local found = findByType(child, fullType)
        if found then return found end
    end
    return nil
end

local function generatorAt(square, id)
    if not square then return nil end
    local generator = value(square, "getGenerator", nil)
    if generator and Utility.deviceId(generator) == tostring(id or "") then return generator end
    for _, method in ipairs({ "getSpecialObjects", "getObjects" }) do
        local list = value(square, method, nil)
        local count = math.max(0, math.floor(tonumber(value(list, "size", 0)) or 0))
        for index = 0, count - 1 do
            local object = value(list, "get", nil, index)
            if object and Utility.deviceId(object) == tostring(id or "") then return object end
        end
    end
    return nil
end

local function findGenerator(id, x, y, z)
    local cell = getCell and getCell() or nil
    local square = cell and value(cell, "getGridSquare", nil, math.floor(tonumber(x) or -1),
        math.floor(tonumber(y) or -1), math.floor(tonumber(z) or 0)) or nil
    return generatorAt(square, id)
end

local function currentPlayerSquare(player)
    local square = player and value(player, "getSquare", nil) or nil
    if not square then return nil end
    return math.floor(tonumber(value(square, "getX", 0)) or 0),
        math.floor(tonumber(value(square, "getY", 0)) or 0),
        math.floor(tonumber(value(square, "getZ", 0)) or 0)
end

local function localEnvironment(player)
    local root = Utility.worldData()
    return {
        root = root,
        square = function(x, y, z)
            local cell = getCell and getCell() or nil
            return cell and value(cell, "getGridSquare", nil, math.floor(tonumber(x) or -1),
                math.floor(tonumber(y) or -1), math.floor(tonumber(z) or 0)) or nil
        end,
        findItem = findPlayerItem,
        removeItem = function(target, item, container)
            local ok = pcall(function() container:Remove(item) end)
            if ok and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
            return ok
        end,
        createGenerator = function(sourceItem, id, square)
            if not IsoGenerator or not IsoGenerator.new or not instanceItem then return false, nil end
            local item = instanceItem(Utility.FullType)
            if not item then return false, nil end
            pcall(function() item:setCondition(value(sourceItem, "getCondition", 100)) end)
            local data = value(item, "getModData", nil)
            if type(data) ~= "table" then return false, nil end
            data[Utility.ItemMarker], data.fuel = tostring(id), 0
            local ok, generator = pcall(function() return IsoGenerator.new(item, getCell(), square) end)
            if not ok or not generator then return false, nil end
            local generatorData = value(generator, "getModData", nil)
            if type(generatorData) ~= "table" then
                pcall(function() generator:remove() end)
                return false, nil
            end
            generatorData[Utility.ObjectMarker] = tostring(id)
            local fueled = GodSystemB42JavaCalls.try(generator, "setFuel", 0)
            GodSystemB42JavaCalls.try(generator, "setConnected", true)
            GodSystemB42JavaCalls.try(generator, "setActivated", false)
            GodSystemB42JavaCalls.try(generator, "transmitModData")
            if fueled then GodSystemB42JavaCalls.try(generator, "transmitCompleteItemToClients") end
            if not fueled or Utility.deviceId(generator) ~= tostring(id) then
                pcall(function() generator:remove() end)
                return false, nil
            end
            return true, generator
        end,
        removeGenerator = function(generator)
            GodSystemB42JavaCalls.try(generator, "setActivated", false)
            GodSystemB42JavaCalls.try(generator, "setFuel", 0)
            return GodSystemB42JavaCalls.try(generator, "remove")
        end,
        findDevice = findGenerator,
        spendCurrency = function(_, amount)
            local service = runtime()
            local ok = service and service.spendCurrency and service.spendCurrency(amount)
            return ok == true
        end,
        repair = function(target, generator, scrap, container)
            if value(generator, "isActivated", false) == true then return false end
            local removed = pcall(function() container:Remove(scrap) end)
            if not removed then return false end
            local condition = tonumber(value(generator, "getCondition", 0)) or 0
            local level = tonumber(value(target, "getPerkLevel", 0, Perks and Perks.Electricity or "Electricity")) or 0
            if not GodSystemB42JavaCalls.try(generator, "setCondition", math.min(100, condition + 4 + level / 2)) then
                local inventory = playerInventory(target)
                if inventory then pcall(function() inventory:AddItem("Base.ElectronicsScrap") end) end
                return false
            end
            if addXp and Perks and Perks.Electricity then pcall(addXp, target, Perks.Electricity, 5) end
            GodSystemB42JavaCalls.try(generator, "sync")
            if triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
            return true
        end,
        pickup = function(target, generator, id)
            local inventory = playerInventory(target)
            if not inventory or not instanceItem then return false, nil end
            local item = instanceItem(Utility.FullType)
            if not item then return false, nil end
            local data = value(item, "getModData", nil)
            if type(data) ~= "table" then return false, nil end
            data[Utility.ItemMarker], data.fuel = tostring(id), 0
            pcall(function() item:setCondition(value(generator, "getCondition", 100)) end)
            local addedOk, added = pcall(function() return inventory:AddItem(item) end)
            if not addedOk or not added then return false, nil end
            local removed = GodSystemB42JavaCalls.try(generator, "remove")
            if not removed then pcall(function() inventory:Remove(item) end); return false, nil end
            if triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
            return true, item
        end,
        cleanupWater = function(id, _, row)
            local processed = 0
            for key, record in pairs(row.waterFixtures or {}) do
                if processed >= 32 then return false end
                processed = processed + 1
                local square = getCell and getCell() or nil
                square = square and value(square, "getGridSquare", nil, record.x, record.y, record.z) or nil
                if not square then return false end
                local list = value(square, "getObjects", nil)
                local count = math.max(0, math.floor(tonumber(value(list, "size", 0)) or 0))
                local fixture
                for index = 0, count - 1 do
                    local object = value(list, "get", nil, index)
                    local data = object and value(object, "getModData", nil) or nil
                    if type(data) == "table" and tostring(data[Utility.WaterMarker] or "") == tostring(id) then
                        fixture = object
                        break
                    end
                end
                if fixture then
                    if not Utility.releaseWaterFixture(root, row, fixture, key, value(fixture, "getModData", nil),
                        value(fixture, "getFluidContainer", nil)) then return false end
                else
                    -- A removed fixture may already have consumed its prepaid water.
                    row.waterReserveCents = math.max(0, row.waterReserveCents - math.max(0, math.floor(tonumber(record.paidCents) or 0)))
                    row.waterFixtures[key] = nil
                end
            end
            return Utility.tableCount(row.waterFixtures) == 0
        end,
        persist = function() return true end,
    }
end

local function makeOpId()
    local root = Utility.worldData()
    root.localOperationSeq = math.max(0, math.floor(tonumber(root.localOperationSeq) or 0)) + 1
    return "gs-" .. tostring(math.floor(os.time())) .. "-" .. tostring(root.localOperationSeq) .. "-1"
end

function Context.submit(player, args)
    args = type(args) == "table" and args or {}
    if isClient and isClient() then
        local command = (Protocol.C2S and Protocol.C2S.UtilityGenerator) or "utilityGenerator"
        args.opId = args.opId or makeOpId()
        if not GodSystemNetwork or not GodSystemNetwork.send or GodSystemNetwork.send(command, args, player) ~= true then
            notifyCode("UtilityGeneratorRequestFailed")
        end
        return
    end
    local ok, code, payload = Utility.execute(player, args, localEnvironment(player))
    Context.lastLocalResult = { ok = ok == true, code = code, payload = payload }
    notifyCode(code)
    return ok, code, payload
end

function Context.requestStatus(generator, player, playerNum, purpose)
    local id = Utility.deviceId(generator)
    local square = value(generator, "getSquare", nil)
    if not id or not square then return end
    local x, y, z = value(square, "getX", nil), value(square, "getY", nil), value(square, "getZ", nil)
    local args = { deviceId = id, x = x, y = y, z = z }
    Context.pendingStatus = purpose and { purpose = purpose, generator = generator, playerNum = playerNum } or nil
    if isClient and isClient() then
        local command = (Protocol.C2S and Protocol.C2S.UtilityGeneratorStatus) or "utilityGeneratorStatus"
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send(command, args, player) end
        return
    end
    local row = Utility.ensureDevice(Utility.worldData(), id)
    if row then Context.receiveStatus({ ok = true, status = Utility.status(Utility.worldData(), row, generator) }) end
end

function Context.receiveStatus(args)
    local pending = Context.pendingStatus
    Context.pendingStatus = nil
    if not args or args.ok ~= true or type(args.status) ~= "table" then
        notifyCode(args and args.code or "UtilityGeneratorUnavailable")
        return
    end
    local status = args.status
    if pending and pending.purpose == "targets" then
        local menu = ISContextMenu.get(pending.playerNum, getMouseX(), getMouseY())
        local targets = status.waterTargets or {}
        if #targets == 0 then
            local option = menu:addOption(text("Context_UtilityGenerator_NoTargets", "No bound water targets"), nil, nil)
            option.notAvailable = true
        end
        for _, target in ipairs(targets) do
            local label = tostring(target.label or target.kind) .. " (" .. tostring(target.x) .. ", " .. tostring(target.y) .. ", " .. tostring(target.z) .. ")"
            menu:addOption(label, pending.playerNum, function(num)
                local id = Utility.deviceId(pending.generator)
                local square = value(pending.generator, "getSquare", nil)
                if id and square then
                    local player = getSpecificPlayer(num)
                    Context.submit(player, { action = "unbindWaterTarget", deviceId = id,
                        x = value(square, "getX", nil), y = value(square, "getY", nil), z = value(square, "getZ", nil),
                        targetId = target.id })
                end
            end)
        end
        return
    end
    if pending and pending.purpose == "amount" then
        local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
        local box = ISTextBox:new(math.max(12, (screenW - 420) / 2), math.max(12, (screenH - 180) / 2),
            420, 180, text("Context_UtilityGenerator_TargetAmountPrompt", "Target water level (1-1000 L)"),
            tostring(status.waterTargetLiters or 10), Context, Context.onAmountResult, pending.playerNum)
        box.maxChars = 4
        box:initialise()
        Context.amountDialog = { box = box, generator = pending.generator, playerNum = pending.playerNum }
        box:addToUIManager()
        return
    end
    local message = text("UtilityGenerator_Status",
        "Water {1} (reserved {2}) | Power {3} (reserved {4})")
    local waterText = text("UtilityGenerator_Reason_" .. tostring(status.waterReason or "unknown"), tostring(status.waterReason or "unknown"))
    local electricText = text("UtilityGenerator_Reason_" .. tostring(status.electricityReason or "unknown"), tostring(status.electricityReason or "unknown"))
    message = message:gsub("{1}", string.format("%.2f", (tonumber(status.waterBalanceCents or status.balanceCents) or 0) / 100))
        :gsub("{2}", string.format("%.2f", (tonumber(status.waterReserveCents) or 0) / 100))
        :gsub("{3}", string.format("%.2f", (tonumber(status.powerBalanceCents) or 0) / 100))
        :gsub("{4}", string.format("%.2f", (tonumber(status.powerReserveCents) or 0) / 100))
    notify(message)
    local supply = text("UtilityGenerator_SupplyStatus", "Water: {1} | Power: {2}")
    notify(supply:gsub("{1}", waterText):gsub("{2}", electricText))
end

function Context.onAmountResult(_, button)
    local state = Context.amountDialog
    Context.amountDialog = nil
    if not state or not button or button.internal ~= "OK" then return end
    local input = state.box and state.box.entry and state.box.entry:getInternalText() or ""
    local amount = tonumber(input)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 1000 then
        return notifyCode("UtilityGeneratorTargetAmountInvalid")
    end
    local generator, playerNum = state.generator, state.playerNum
    local square = value(generator, "getSquare", nil)
    if not square then return end
    Context.submit(getSpecificPlayer(playerNum), { action = "setWaterTargetLiters", deviceId = Utility.deviceId(generator),
        x = value(square, "getX", nil), y = value(square, "getY", nil), z = value(square, "getZ", nil), liters = amount })
end

local function optionLabel(key, fallback)
    return text("Context_UtilityGenerator_" .. key, fallback)
end

local function sendForGenerator(playerNum, generator, action, extra)
    local id = Utility.deviceId(generator)
    local square = value(generator, "getSquare", nil)
    if not id or not square then return end
    local x, y, z = value(square, "getX", nil), value(square, "getY", nil), value(square, "getZ", nil)
    local args = { action = action, deviceId = id, x = x, y = y, z = z }
    for key, entry in pairs(extra or {}) do args[key] = entry end
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer and getPlayer() or nil
    Context.submit(player, args)
end

-- The vanilla building cursor lives in the server Lua tree and is not
-- requireable while client autorun files load. A selection cursor only needs
-- the drag callbacks, so keep it in the shared base class available here.
local WaterTargetCursor = ISBaseObject:derive("GodSystemWaterTargetCursor")

function WaterTargetCursor:getFloorCursorSprite()
    if not WaterTargetCursor.floorCursorSprite then
        local spriteName = (Core.getTileScale() == 2)
            and "media/ui/FloorTileCursor2x.png" or "media/ui/FloorTileCursor.png"
        local sprite = IsoSprite.new()
        sprite:LoadSingleTexture(spriteName)
        WaterTargetCursor.floorCursorSprite = sprite
    end
    return WaterTargetCursor.floorCursorSprite
end

function WaterTargetCursor:update()
end

function WaterTargetCursor:isValid(square)
    return square ~= nil
end

function WaterTargetCursor:render(x, y, z)
    local color = getCore():getGoodHighlitedColor()
    self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, color:getR(), color:getG(), color:getB(), 0.8)
end

function WaterTargetCursor:tryBuild(x, y, z)
    self:create(x, y, z)
end

function WaterTargetCursor:create(x, y, z)
    getCell():setDrag(nil, self.player)
    local square = value(getCell(), "getGridSquare", nil, x, y, z)
    local objects = square and value(square, "getObjects", nil) or nil
    local count = math.max(0, math.floor(tonumber(value(objects, "size", 0)) or 0))
    local menu = ISContextMenu.get(self.player, getMouseX(), getMouseY())
    local choices = 0
    for index = 0, count - 1 do
        local object = value(objects, "get", nil, index)
        local kind, reason = Utility.waterTargetKind(object)
        if kind or reason == "UtilityGeneratorTargetNotPlumbed" then
            choices = choices + 1
            local sprite = value(object, "getSpriteName", nil)
            if sprite == nil then
                local spriteObject = value(object, "getSprite", nil)
                sprite = spriteObject and value(spriteObject, "getName", nil) or nil
            end
            local label = tostring(value(object, "getName", nil) or sprite or kind or "Water target")
                .. " [" .. tostring(index + 1) .. "]"
            if kind then
                menu:addOption(label, self.player, function(num)
                    sendForGenerator(num, self.generator, "bindWaterTarget",
                        { targetX = x, targetY = y, targetZ = z, targetIndex = index,
                            targetSprite = tostring(sprite or "") })
                end)
            else
                local option = menu:addOption(label .. " — " .. text("Notify_" .. reason, "Plumb this sink first"), nil, nil)
                option.notAvailable = true
            end
        end
    end
    if choices == 0 then notifyCode("UtilityGeneratorTargetNone") end
end

function WaterTargetCursor:new(playerNum, generator)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:initialise()
    if o.init then o:init() end
    o.player = playerNum
    o.generator = generator
    o.noNeedHammer = true
    o.skipBuildAction = true
    return o
end

local function addGeneratorOptions(playerNum, context, generator)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player or not Utility.deviceId(generator) then return end
    local parent = context:addOption(optionLabel("Title", "Utility Generator"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, menu)
    menu:addOption(optionLabel("Status", "View Status"), playerNum, function(num) Context.requestStatus(generator, player, num) end)
    menu:addOption(optionLabel("Start", "Start"), playerNum, function(num) sendForGenerator(num, generator, "active", { active = true }) end)
    menu:addOption(optionLabel("Stop", "Stop"), playerNum, function(num) sendForGenerator(num, generator, "active", { active = false }) end)
    menu:addOption(optionLabel("Fill", "Fill Water"), playerNum, function(num)
        local target = getSpecificPlayer and getSpecificPlayer(num) or nil
        local item = Utility.findFillableContainer(target)
        if not item then return notifyCode("UtilityGeneratorNoContainer") end
        sendForGenerator(num, generator, "fill", { itemId = Utility.itemId(item) })
    end)
    menu:addOption(optionLabel("Drink", "Drink"), playerNum, function(num)
        sendForGenerator(num, generator, "drink")
    end)
    menu:addOption(optionLabel("SelectWaterTarget", "Select water target"), playerNum, function(num)
        if type(ISBuildingObject) == "table" and getmetatable(WaterTargetCursor) ~= ISBuildingObject then
            -- Vanilla may load this class after our client autorun. Use its
            -- complete drag behavior when present without requiring it at boot.
            setmetatable(WaterTargetCursor, ISBuildingObject)
            ISBuildingObject.__index = ISBuildingObject
            WaterTargetCursor.SuperType = ISBuildingObject
        end
        getCell():setDrag(WaterTargetCursor:new(num, generator), num)
    end)
    menu:addOption(optionLabel("ManageWaterTargets", "View / unbind water targets"), playerNum, function(num)
        Context.requestStatus(generator, getSpecificPlayer(num), num, "targets")
    end)
    menu:addOption(optionLabel("SetWaterTargetAmount", "Set target water level"), playerNum, function(num)
        Context.requestStatus(generator, getSpecificPlayer(num), num, "amount")
    end)
    local chargeParent = menu:addOption(optionLabel("Charge", "Charge Accounts"), nil, nil)
    local chargeMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(chargeParent, chargeMenu)
    for _, account in ipairs({ { kind = "water", label = "ChargeWater", fallback = "Water Account" },
        { kind = "power", label = "ChargePower", fallback = "Power Account" } }) do
        local utility = account.kind
        local accountParent = chargeMenu:addOption(optionLabel(account.label, account.fallback), nil, nil)
        local accountMenu = ISContextMenu:getNew(chargeMenu)
        chargeMenu:addSubMenu(accountParent, accountMenu)
        for _, amount in ipairs({ 100, 500, 1000 }) do
            accountMenu:addOption(optionLabel("ChargeAmount", "Charge {1}"):gsub("{1}", tostring(amount)), playerNum,
                function(num) sendForGenerator(num, generator, "charge", { amount = amount, utility = utility }) end)
        end
    end
    menu:addOption(optionLabel("Repair", "Repair (uses scrap)"), playerNum, function(num)
        local target = getSpecificPlayer and getSpecificPlayer(num) or nil
        local inventory = playerInventory(target)
        local scrap = findByType(inventory, "Base.ElectronicsScrap")
        if not scrap then return notifyCode("UtilityGeneratorRepairMaterialMissing") end
        sendForGenerator(num, generator, "repair", { itemId = Utility.itemId(scrap) })
    end)
    menu:addOption(optionLabel("Pickup", "Pick Up"), playerNum, function(num) sendForGenerator(num, generator, "pickup") end)
end

local function removeVanillaGeneratorOptions(context)
    if not context or not context.removeOptionByName then return end
    for _, key in ipairs({
        "ContextMenu_Generator", "ContextMenu_GeneratorInfo",
        "ContextMenu_GeneratorPlug", "ContextMenu_GeneratorUnplug",
        "ContextMenu_GeneratorAddFuel", "ContextMenu_GeneratorFix",
        "ContextMenu_TakeGenerator", "ContextMenu_GeneratorTake",
    }) do
        local label = getText and getText(key) or key
        if label and label ~= "" then context:removeOptionByName(label) end
    end
end

function Context.fillWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    if not Utility or type(Utility.deviceId) ~= "function" then return end
    local hasGodSystemGenerator = false
    local seen = {}
    for index = 1, #(worldobjects or {}) do
        local object = worldobjects[index]
        local id = Utility.deviceId(object)
        if id and not seen[id] then
            seen[id] = true
            hasGodSystemGenerator = true
            addGeneratorOptions(playerNum, context, object)
        end
        local square = value(object, "getSquare", nil)
        local generator = square and value(square, "getGenerator", nil) or nil
        id = generator and Utility.deviceId(generator) or nil
        if id and not seen[id] then
            seen[id] = true
            hasGodSystemGenerator = true
            addGeneratorOptions(playerNum, context, generator)
        end
    end
    if hasGodSystemGenerator then
        removeVanillaGeneratorOptions(context)
    end
end

function Context.fillInventoryMenu(_, context, snapshot)
    if not Utility or type(Utility.itemFullType) ~= "function" then return end
    for index = 1, #(snapshot.items or {}) do
        local item = snapshot.items[index]
        if Utility.itemFullType(item) == Utility.FullType then
            local player = getSpecificPlayer and getSpecificPlayer(snapshot.playerNum) or nil
            local x, y, z = currentPlayerSquare(player)
            if x then
                context:addOption(optionLabel("Place", "Place Utility Generator"), player, function(target)
                    Context.submit(target, { action = "place", itemId = Utility.itemId(item), x = x, y = y, z = z })
                end)
            end
            break
        end
    end
end

local function installVanillaGeneratorGuards()
    local menu = ISWorldObjectContextMenu
    if not menu or Context._vanillaGuardsInstalled then return end
    Context._vanillaGuardsInstalled = true
    local callbacks = {
        onInfoGenerator = { 2, function(worldobjects, generator, player) Context.requestStatus(generator, getSpecificPlayer(player), player) end },
        onPlugGenerator = { 2, function(_, generator, player) notify(text("UtilityGenerator_AlwaysConnected", "Utility Generator stays connected.")) end },
        onActivateGenerator = { 3, function(_, enabled, generator, player) sendForGenerator(player, generator, "active", { active = enabled == true }) end },
        onFixGenerator = { 2, function(_, generator, player)
            local target = getSpecificPlayer and getSpecificPlayer(player) or nil
            local inventory = playerInventory(target)
            local scrap = findByType(inventory, "Base.ElectronicsScrap")
            if scrap then sendForGenerator(player, generator, "repair", { itemId = Utility.itemId(scrap) }) else notifyCode("UtilityGeneratorRepairMaterialMissing") end
        end },
        onAddFuelGenerator = { 3, function(_, _, generator) notify(text("UtilityGenerator_UseCoinCharge", "Use the device menu to charge with system coins.")) end },
        doAddFuelGenerator = { 2, function(_, generator) notify(text("UtilityGenerator_UseCoinCharge", "Use the device menu to charge with system coins.")) end },
        onTakeGenerator = { 2, function(_, generator, player) sendForGenerator(player, generator, "pickup") end },
    }
    for name, rule in pairs(callbacks) do
        local original = menu[name]
        if type(original) == "function" then
            menu[name] = function(...)
                local args = { ... }
                local generator = args[rule[1]]
                if generator and Utility.deviceId(generator) then return rule[2](...) end
                return original(...)
            end
        end
    end
end

if GodSystemInventoryContext and GodSystemInventoryContext.register then
    GodSystemInventoryContext.register("utilityGenerator", Context.fillInventoryMenu)
end
if Events and Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldMenu)
    Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldMenu)
end
installVanillaGeneratorGuards()
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        if not Context._vanillaGuardsInstalled then
            installVanillaGeneratorGuards()
        end
    end)
end

if not (isClient and isClient()) and Events and Events.OnTick then
    local lastTick = 0
    Events.OnTick.Add(function()
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        if not Utility or type(Utility.worldData) ~= "function" then return end
        if now - lastTick < 1000 and not (Utility.hasPendingWork and Utility.hasPendingWork(now)) then return end
        if now - lastTick >= 1000 then lastTick = now end
        local root = Utility.worldData()
        Utility.tick(root, {
            square = function(x, y, z)
                local cell = getCell and getCell() or nil
                return cell and value(cell, "getGridSquare", nil, x, y, z) or nil
            end,
            findDevice = findGenerator,
            fixture = function(record, id)
                local cell = getCell and getCell() or nil
                local square = cell and value(cell, "getGridSquare", nil, record.x, record.y, record.z) or nil
                local list = square and value(square, "getObjects", nil) or nil
                local count = math.max(0, math.floor(tonumber(value(list, "size", 0)) or 0))
                for index = 0, count - 1 do
                    local object = value(list, "get", nil, index)
                    if object and tostring((value(object, "getModData", {}) or {})[Utility.WaterMarker] or "") == tostring(id) then return object end
                end
                return nil
            end,
        }, now)
    end)
    local function squareAt(x, y, z)
        local cell = getCell and getCell() or nil
        return cell and value(cell, "getGridSquare", nil, x, y, z) or nil
    end
    if Events.OnObjectAdded then
        Events.OnObjectAdded.Add(function(object)
            Utility.onObjectAdded(Utility.worldData(), object, { square = squareAt })
        end)
    end
    if Events.OnLoadGridsquare then
        Events.OnLoadGridsquare.Add(function(square)
            Utility.onSquareLoaded(Utility.worldData(), square)
        end)
    end
    if Events.OnWaterAmountChange then
        Events.OnWaterAmountChange.Add(function(object)
            local data = value(object, "getModData", nil)
            local id = type(data) == "table" and tostring(data[Utility.GhostMarker] or data[Utility.TargetMarker] or "") or ""
            if id ~= "" then Utility.markWaterTargetDirty(Utility.worldData(), id) end
        end)
    end
end

return Context
