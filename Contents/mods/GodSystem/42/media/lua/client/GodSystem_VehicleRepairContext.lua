require "GodSystem_Core"
require "GodSystem_Maintenance"
require "ISUI/ISModalDialog"
require "ISUI/ISToolTip"

GodSystemVehicleRepairContext = GodSystemVehicleRepairContext or {}

local Context = GodSystemVehicleRepairContext
local ModuleType = "GodSystem.SystemVehicleRepairModule"

local function text(key, fallback)
    return GodSystem and GodSystem.text and GodSystem.text(key, fallback) or fallback or key
end

local function findModule(player)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory or not inventory.getFirstTypeRecurse then return nil end
    local ok, item = pcall(function() return inventory:getFirstTypeRecurse(ModuleType) end)
    return ok and item or nil
end

local function selectedVehicle(player)
    if not player then return nil end
    local vehicle = player.getVehicle and player:getVehicle() or nil
    if vehicle then return vehicle end
    if IsoObjectPicker and IsoObjectPicker.Instance and IsoObjectPicker.Instance.PickVehicle then
        local ok, picked = pcall(function()
            return IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
        end)
        if ok then return picked end
    end
    return nil
end

local function vehicleName(vehicle)
    if not vehicle or not vehicle.getScript then return text("VehicleRepair_UnknownVehicle", "Vehicle") end
    local ok, script = pcall(function() return vehicle:getScript() end)
    if not ok or not script then return text("VehicleRepair_UnknownVehicle", "Vehicle") end
    local okModel, model = pcall(function() return script:getCarModelName() end)
    if okModel and model and tostring(model) ~= "" then return tostring(model) end
    local okName, name = pcall(function() return script:getName() end)
    return okName and tostring(name) or text("VehicleRepair_UnknownVehicle", "Vehicle")
end

function Context.onConfirm(button, payload)
    if not button or button.internal ~= "YES" or not payload then return end
    local player = getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
    local module = findModule(player)
    if not module then
        if GodSystem and GodSystem.notify then GodSystem.notify(text("Notify_MaintenanceConsumableMissing", "Repair module is missing")) end
        return
    end
    GodSystem.useMaintenanceItem("repairVehicle", module, payload.vehicleId)
end

function Context.confirm(playerNum, vehicle)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
    local module = findModule(player)
    if not player or not vehicle or not module then return end
    local summary = GodSystemMaintenance.vehicleDamageSummary(vehicle)
    if summary.damaged <= 0 then
        if GodSystem and GodSystem.notify then GodSystem.notify(text("Notify_VehicleAlreadyFull", "This vehicle is already fully repaired")) end
        return
    end
    local message = text("Confirm_RepairVehicle", "Consume one vehicle repair module to fully repair this vehicle?") .. "\n" ..
        vehicleName(vehicle) .. "\n\n" ..
        text("VehicleRepair_DamagedParts", "Damaged or missing parts") .. ": " .. tostring(summary.damaged) .. "\n" ..
        text("VehicleRepair_MissingParts", "Missing standard parts") .. ": " .. tostring(summary.missing) .. "\n\n" ..
        text("VehicleRepair_NoFuel", "Fuel and vehicle inventory will not be changed.")
    local x = math.max(40, (getCore():getScreenWidth() - 560) / 2)
    local y = math.max(40, (getCore():getScreenHeight() - 300) / 2)
    local modal = ISModalDialog:new(x, y, 560, 300, message, true, Context, Context.onConfirm, playerNum, {
        playerNum = playerNum,
        vehicleId = vehicle:getId(),
    })
    modal:initialise()
    modal:addToUIManager()
end

function Context.fillWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    local module = findModule(player)
    if not module then return end
    local vehicle = selectedVehicle(player)
    if not vehicle then return end
    local summary = GodSystemMaintenance.vehicleDamageSummary(vehicle)
    local option = context:addOption(text("Context_RepairVehicle", "Use system vehicle repair module"), playerNum, Context.confirm, vehicle)
    if summary.damaged <= 0 then
        option.notAvailable = true
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(text("Context_RepairVehicle", "Use system vehicle repair module"))
        tooltip.description = text("Notify_VehicleAlreadyFull", "This vehicle is already fully repaired")
        option.toolTip = tooltip
    end
end

Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldMenu)
