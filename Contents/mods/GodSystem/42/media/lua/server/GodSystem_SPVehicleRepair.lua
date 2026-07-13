require "GodSystem_Protocol"
require "GodSystem_Maintenance"

if (isClient and isClient()) or (isServer and isServer()) then return end

GodSystemSPVehicleRepair = GodSystemSPVehicleRepair or {}

local Bridge = GodSystemSPVehicleRepair
local Protocol = GodSystemProtocol or {}
local MODULE = Protocol.Module or "GodSystem"
local COMMAND = (Protocol.C2S and Protocol.C2S.UseMaintenanceItem) or "useMaintenanceItem"
local RESULT = (Protocol.S2C and Protocol.S2C.Result) or "result"

local function itemId(item)
    return GodSystemMaintenance.itemId(item)
end

local function inventoryItemById(container, wantedId)
    if not container or not container.getItems then return nil, nil end
    local items = container:getItems()
    if not items or not items.size then return nil, nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item and tostring(itemId(item) or "") == wantedId then return item, container end
        if item and item.getInventory then
            local ok, child = pcall(function() return item:getInventory() end)
            if ok and child then
                local found, owner = inventoryItemById(child, wantedId)
                if found then return found, owner end
            end
        end
    end
    return nil, nil
end

local function vehicleInRange(player, vehicle)
    if not player or not vehicle then return false, "VehicleRepairInvalid" end
    if player:getVehicle() == vehicle then return true end
    if math.floor(tonumber(player:getZ()) or 0) ~= math.floor(tonumber(vehicle:getZ()) or 0) then
        return false, "VehicleRepairWrongFloor"
    end
    local dx = (tonumber(player:getX()) or 0) - (tonumber(vehicle:getX()) or 0)
    local dy = (tonumber(player:getY()) or 0) - (tonumber(vehicle:getY()) or 0)
    if (dx * dx + dy * dy) > 16 then return false, "VehicleRepairTooFar" end
    return true
end

local function sendResult(player, ok, code, resultArgs, payload)
    local packet = {
        ok = ok == true,
        code = tostring(code or ""),
        args = resultArgs or {},
        message = "",
        payload = payload,
    }
    local delivered = sendServerCommand and pcall(sendServerCommand, player, MODULE, RESULT, packet) or false
    if not delivered and triggerEvent then
        delivered = pcall(triggerEvent, "OnServerCommand", MODULE, RESULT, packet)
    end
    return delivered == true
end

local function maintenancePayload(vehicleId)
    return {
        kind = "maintenanceItem",
        action = "repairVehicle",
        vehicleId = vehicleId,
    }
end

local function refundModule(player)
    local inventory = player and player:getInventory() or nil
    local replacement = inventory and inventory:AddItem(GodSystemMaintenance.VehicleRepairItemType) or nil
    if replacement and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
    return replacement ~= nil
end

function Bridge.onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= ((Protocol.C2S and Protocol.C2S.UseMaintenanceItem) or "useMaintenanceItem") then return end
    if tostring(args and args.action or "") ~= "repairVehicle" then return end

    local vehicleId = math.floor(tonumber(args and args.vehicleId) or -1)
    local payload = maintenancePayload(vehicleId)
    if not player or vehicleId < 0 then
        sendResult(player, false, "VehicleRepairInvalid", nil, payload)
        return
    end

    local consumableId = tostring(args and args.consumableItemId or "")
    local consumable, container = inventoryItemById(player:getInventory(), consumableId)
    if not consumable or not container or consumable:getFullType() ~= GodSystemMaintenance.VehicleRepairItemType then
        sendResult(player, false, "MaintenanceConsumableMissing", nil, payload)
        return
    end

    local vehicle = getVehicleById and getVehicleById(vehicleId) or nil
    local inRange, rangeCode = vehicleInRange(player, vehicle)
    if not inRange then
        sendResult(player, false, rangeCode, nil, payload)
        return
    end

    local before = GodSystemMaintenance.vehicleDamageSummary(vehicle)
    if before.damaged <= 0 then
        sendResult(player, false, "VehicleAlreadyFull", nil, payload)
        return
    end

    local removed = pcall(function() container:Remove(consumable) end)
    local stillOwned = inventoryItemById(player:getInventory(), consumableId) ~= nil
    if not removed or stillOwned then
        sendResult(player, false, "MaintenanceFailed", nil, payload)
        return
    end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    if triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end

    local repaired = GodSystemMaintenance.repairVehicle(vehicle)
    if not repaired then
        local refunded = refundModule(player)
        sendResult(player, false, refunded and "VehicleRepairFailedRefunded" or "VehicleRepairFailed", nil, payload)
        return
    end

    sendResult(player, true, "VehicleRepaired", { before.damaged, before.missing }, payload)
end

if Events.OnClientCommand then
    Events.OnClientCommand.Remove(Bridge.onClientCommand)
    Events.OnClientCommand.Add(Bridge.onClientCommand)
end
