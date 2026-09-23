require "GodSystem_UtilityGenerator"
require "GodSystem_Protocol"
require "GodSystem_B42JavaCalls"
require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISUI/ISWorldObjectContextMenu"

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
                    Utility.releaseWaterFixture(root, row, fixture, key, value(fixture, "getModData", nil),
                        value(fixture, "getFluidContainer", nil))
                else
                    row.balanceCents = row.balanceCents + math.max(0, math.floor(tonumber(record.paidCents) or 0))
                    row.waterReserveCents = math.max(0, row.waterReserveCents - math.max(0, math.floor(tonumber(record.paidCents) or 0)))
                    row.waterFixtures[key] = nil
                end
            end
            return Utility.tableCount(row.waterFixtures) == 0
        end,
        scheduleScan = function(id) return Utility.scheduleScan(root, id) end,
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

function Context.requestStatus(generator, player, playerNum)
    local id = Utility.deviceId(generator)
    local square = value(generator, "getSquare", nil)
    if not id or not square then return end
    local x, y, z = value(square, "getX", nil), value(square, "getY", nil), value(square, "getZ", nil)
    local args = { deviceId = id, x = x, y = y, z = z }
    if isClient and isClient() then
        local command = (Protocol.C2S and Protocol.C2S.UtilityGeneratorStatus) or "utilityGeneratorStatus"
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send(command, args, player) end
        return
    end
    local row = Utility.ensureDevice(Utility.worldData(), id)
    if row then Context.receiveStatus({ ok = true, status = Utility.status(Utility.worldData(), row, generator) }) end
end

function Context.receiveStatus(args)
    if not args or args.ok ~= true or type(args.status) ~= "table" then
        notifyCode(args and args.code or "UtilityGeneratorUnavailable")
        return
    end
    local status = args.status
    local message = text("UtilityGenerator_Status", "Balance: {1} | Water: {2} | Electricity: {3}")
    local waterText = text("UtilityGenerator_Reason_" .. tostring(status.waterReason or "unknown"), tostring(status.waterReason or "unknown"))
    local electricText = text("UtilityGenerator_Reason_" .. tostring(status.electricityReason or "unknown"), tostring(status.electricityReason or "unknown"))
    message = message:gsub("{1}", string.format("%.2f", (tonumber(status.balanceCents) or 0) / 100))
        :gsub("{2}", waterText):gsub("{3}", electricText)
    notify(message)
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

local function addGeneratorOptions(playerNum, context, generator)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player or not Utility.deviceId(generator) then return end
    local parent = context:addOption(optionLabel("Title", "水电一体机"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, menu)
    menu:addOption(optionLabel("Status", "查看状态"), playerNum, function(num) Context.requestStatus(generator, player, num) end)
    menu:addOption(optionLabel("Start", "启动"), playerNum, function(num) sendForGenerator(num, generator, "active", { active = true }) end)
    menu:addOption(optionLabel("Stop", "停止"), playerNum, function(num) sendForGenerator(num, generator, "active", { active = false }) end)
    local chargeParent = menu:addOption(optionLabel("Charge", "充值系统币"), nil, nil)
    local chargeMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(chargeParent, chargeMenu)
    for _, amount in ipairs({ 100, 500, 1000 }) do
        chargeMenu:addOption(optionLabel("ChargeAmount", "充值 {1}"):gsub("{1}", tostring(amount)), playerNum,
            function(num) sendForGenerator(num, generator, "charge", { amount = amount }) end)
    end
    menu:addOption(optionLabel("Repair", "维修（消耗电子废料）"), playerNum, function(num)
        local target = getSpecificPlayer and getSpecificPlayer(num) or nil
        local inventory = playerInventory(target)
        local scrap = findByType(inventory, "Base.ElectronicsScrap")
        if not scrap then return notifyCode("UtilityGeneratorRepairMaterialMissing") end
        sendForGenerator(num, generator, "repair", { itemId = Utility.itemId(scrap) })
    end)
    menu:addOption(optionLabel("Pickup", "搬走"), playerNum, function(num) sendForGenerator(num, generator, "pickup") end)
end

function Context.fillWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local seen = {}
    for index = 1, #(worldobjects or {}) do
        local object = worldobjects[index]
        local id = Utility.deviceId(object)
        if id and not seen[id] then
            seen[id] = true
            addGeneratorOptions(playerNum, context, object)
        end
        local square = value(object, "getSquare", nil)
        local generator = square and value(square, "getGenerator", nil) or nil
        id = generator and Utility.deviceId(generator) or nil
        if id and not seen[id] then
            seen[id] = true
            addGeneratorOptions(playerNum, context, generator)
        end
    end
end

function Context.fillInventoryMenu(_, context, snapshot)
    for index = 1, #(snapshot.items or {}) do
        local item = snapshot.items[index]
        if Utility.itemFullType(item) == Utility.FullType then
            local player = getSpecificPlayer and getSpecificPlayer(snapshot.playerNum) or nil
            local x, y, z = currentPlayerSquare(player)
            if x then
                context:addOption(optionLabel("Place", "放置水电一体机"), player, function(target)
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
        onPlugGenerator = { 2, function(_, generator, player) notify(text("UtilityGenerator_AlwaysConnected", "水电一体机始终保持连接。")) end },
        onActivateGenerator = { 3, function(_, enabled, generator, player) sendForGenerator(player, generator, "active", { active = enabled == true }) end },
        onFixGenerator = { 2, function(_, generator, player)
            local target = getSpecificPlayer and getSpecificPlayer(player) or nil
            local inventory = playerInventory(target)
            local scrap = findByType(inventory, "Base.ElectronicsScrap")
            if scrap then sendForGenerator(player, generator, "repair", { itemId = Utility.itemId(scrap) }) else notifyCode("UtilityGeneratorRepairMaterialMissing") end
        end },
        onAddFuelGenerator = { 3, function(_, _, generator) notify(text("UtilityGenerator_UseCoinCharge", "请使用设备菜单以系统币充值。")) end },
        doAddFuelGenerator = { 2, function(_, generator) notify(text("UtilityGenerator_UseCoinCharge", "请使用设备菜单以系统币充值。")) end },
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

if not (isClient and isClient()) and Events and Events.OnTick then
    local lastTick = 0
    Events.OnTick.Add(function()
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        if now - lastTick < 1000 then return end
        lastTick = now
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
            local x, y, z = value(square, "getX", nil), value(square, "getY", nil), value(square, "getZ", nil)
            if x == nil or y == nil or z == nil then return end
            local root = Utility.worldData()
            for id in pairs(root.devices or {}) do
                local row = Utility.ensureDevice(root, id)
                if row and row.active and row.placed then
                    Utility.scanSquare(root, id, { square = squareAt }, x, y, z)
                end
            end
        end)
    end
end

return Context
