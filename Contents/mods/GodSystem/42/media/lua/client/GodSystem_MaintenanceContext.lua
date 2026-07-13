require "GodSystem_Core"
require "GodSystem_Maintenance"
require "ISUI/ISModalDialog"

GodSystemMaintenanceContext = GodSystemMaintenanceContext or {}

local Context = GodSystemMaintenanceContext

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function formatText(template, args)
    local value = tostring(template or "")
    for i = 1, #(args or {}) do
        value = value:gsub("{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return value
end

local function notifyCode(code, args)
    if not GodSystem or not GodSystem.notify then return end
    local value = text("Notify_" .. tostring(code or "MaintenanceFailed"), text("Notify_MaintenanceFailed", "Maintenance failed"))
    GodSystem.notify(formatText(value, args or {}))
end

local function displayName(item)
    if item and item.getDisplayName then
        local ok, value = pcall(function() return item:getDisplayName() end)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    if item and item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then return tostring(value) end
    end
    return text("Maintenance_UnknownItem", "Unknown item")
end

local function numberText(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.0001 then return tostring(math.floor(value)) end
    return string.format("%.2f", value)
end

local function containsItem(container, target)
    if not container or not container.getItems then return false end
    local items = container:getItems()
    if not items or not items.size then return false end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item == target then return true end
        if item and item.getInventory then
            local ok, child = pcall(function() return item:getInventory() end)
            if ok and child and containsItem(child, target) then return true end
        end
    end
    return false
end

local function selectedUtility(items)
    local selected = nil
    for _, value in ipairs(items or {}) do
        local item = value
        if not instanceof(item, "InventoryItem") then
            item = value and value.items and value.items[1] or nil
        end
        if item and GodSystemMaintenance.isUtilityItem(item) then
            if selected and selected ~= item then return nil end
            selected = item
        end
    end
    return selected
end

local function actionForItem(item)
    if not item or not item.getFullType then return nil end
    local ok, fullType = pcall(function() return item:getFullType() end)
    if not ok then return nil end
    if fullType == GodSystemMaintenance.RepairItemType then return "repairHeld" end
    if fullType == GodSystemMaintenance.ReinforceItemType then return "reinforceHeld" end
    return nil
end

local function buildConfirmMessage(action, target, before)
    local lines = {
        text(action == "repairHeld" and "Confirm_RepairHeld" or "Confirm_ReinforceHeld", "Confirm maintenance item use"),
        displayName(target),
        "",
    }
    if action == "repairHeld" then
        lines[#lines + 1] = text("Maintenance_MainCondition", "Main condition") .. ": " ..
            numberText(before.condition) .. "/" .. numberText(before.conditionMax) .. " -> " ..
            numberText(before.conditionMax) .. "/" .. numberText(before.conditionMax)
        if before.hasHead then
            lines[#lines + 1] = text("Maintenance_HeadCondition", "Head condition") .. ": " ..
                numberText(before.headCondition) .. "/" .. numberText(before.headConditionMax) .. " -> " ..
                numberText(before.headConditionMax) .. "/" .. numberText(before.headConditionMax)
        end
        if before.hasSharpness then
            lines[#lines + 1] = text("Maintenance_Sharpness", "Sharpness") .. ": " ..
                tostring(math.floor(before.sharpness * 100 + 0.5)) .. "% -> 100%"
        end
    else
        lines[#lines + 1] = text("Maintenance_MainCondition", "Main condition") .. ": " ..
            numberText(before.condition) .. "/" .. numberText(before.conditionMax) .. " -> " ..
            numberText(math.min(before.condition + 2, before.conditionMax + 2)) .. "/" .. numberText(before.conditionMax + 2)
        lines[#lines + 1] = ""
        lines[#lines + 1] = text("Maintenance_HeadMaxUnchanged", "Head-condition maximum will not increase")
    end
    return table.concat(lines, "\n")
end

local function removeConsumable(player, consumable)
    if not player or not consumable or not containsItem(player:getInventory(), consumable) then return false end
    local container = consumable:getContainer()
    if not container then return false end
    local ok = pcall(function() container:Remove(consumable) end)
    if not ok or containsItem(player:getInventory(), consumable) then return false end
    if container.setDrawDirty then pcall(function() container:setDrawDirty(true) end) end
    if triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
    return true
end

function GodSystem.useMaintenanceItem(action, consumable, targetItemId)
    if isClient and isClient() then
        notifyCode("MaintenanceFailed")
        return false
    end
    local player = getPlayer and getPlayer() or nil
    if action == "repairVehicle" then
        local vehicleId = math.floor(tonumber(targetItemId) or -1)
        local vehicle = vehicleId >= 0 and getVehicleById and getVehicleById(vehicleId) or nil
        if not player or not vehicle then
            notifyCode("VehicleRepairInvalid")
            return false
        end
        if not consumable or not containsItem(player:getInventory(), consumable) or consumable:getFullType() ~= GodSystemMaintenance.VehicleRepairItemType then
            notifyCode("MaintenanceConsumableMissing")
            return false
        end
        if player:getVehicle() ~= vehicle then
            if math.floor(tonumber(player:getZ()) or 0) ~= math.floor(tonumber(vehicle:getZ()) or 0) then
                notifyCode("VehicleRepairWrongFloor")
                return false
            end
            local dx = (tonumber(player:getX()) or 0) - (tonumber(vehicle:getX()) or 0)
            local dy = (tonumber(player:getY()) or 0) - (tonumber(vehicle:getY()) or 0)
            if (dx * dx + dy * dy) > 16 then
                notifyCode("VehicleRepairTooFar")
                return false
            end
        end
        local before = GodSystemMaintenance.vehicleDamageSummary(vehicle)
        if before.damaged <= 0 then
            notifyCode("VehicleAlreadyFull")
            return false
        end
        if not removeConsumable(player, consumable) then
            notifyCode("MaintenanceFailed")
            return false
        end
        local repaired = pcall(function() vehicle:repair() end)
        local after = GodSystemMaintenance.vehicleDamageSummary(vehicle)
        if not repaired or after.damaged > 0 then
            local replacement = player:getInventory():AddItem(GodSystemMaintenance.VehicleRepairItemType)
            if replacement and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
            notifyCode(replacement and "VehicleRepairFailedRefunded" or "VehicleRepairFailed")
            return false
        end
        notifyCode("VehicleRepaired", { before.damaged, before.missing })
        return true
    end
    local target = player and player:getPrimaryHandItem() or nil
    if not target then
        notifyCode("MaintenanceNoHeldItem")
        return false
    end
    if tostring(GodSystemMaintenance.itemId(target) or "") ~= tostring(targetItemId or "") then
        notifyCode("MaintenanceTargetChanged")
        return false
    end
    if not consumable or not containsItem(player:getInventory(), consumable) then
        notifyCode("MaintenanceConsumableMissing")
        return false
    end
    local expectedAction = actionForItem(consumable)
    if expectedAction ~= action then
        notifyCode("MaintenanceInvalidTarget")
        return false
    end

    local applied, code, result, before = GodSystemMaintenance.apply(target, action)
    if not applied then
        notifyCode(code)
        return false
    end
    if not removeConsumable(player, consumable) then
        GodSystemMaintenance.rollback(target, before)
        notifyCode("MaintenanceFailed")
        return false
    end
    notifyCode(code, { displayName(target), numberText(result.after.condition), numberText(result.after.conditionMax) })
    return true
end

function Context:onConfirm(button, payload)
    if not button or button.internal ~= "YES" or not payload then return end
    GodSystem.useMaintenanceItem(payload.action, payload.consumable, payload.targetItemId)
end

function Context.confirmUse(consumable, playerNum, action)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
    local target = player and player:getPrimaryHandItem() or nil
    if not target then
        notifyCode("MaintenanceNoHeldItem")
        return
    end
    local before, code = GodSystemMaintenance.snapshot(target)
    if not before then
        notifyCode(code or "MaintenanceInvalidTarget")
        return
    end
    if action == "repairHeld" and GodSystemMaintenance.isFullyRepaired(before) then
        notifyCode("MaintenanceAlreadyFull")
        return
    end
    if action == "reinforceHeld" and before.conditionMax > GodSystemMaintenance.MaxSafeCondition then
        notifyCode("MaintenanceOverflow")
        return
    end
    local targetItemId = GodSystemMaintenance.itemId(target)
    if not targetItemId then
        notifyCode("MaintenanceInvalidTarget")
        return
    end
    local message = buildConfirmMessage(action, target, before)
    local x = math.max(40, (getCore():getScreenWidth() - 560) / 2)
    local y = math.max(40, (getCore():getScreenHeight() - 300) / 2)
    local modal = ISModalDialog:new(x, y, 560, 300, message, true, Context, Context.onConfirm, playerNum, {
        action = action,
        consumable = consumable,
        consumableItemId = GodSystemMaintenance.itemId(consumable),
        targetItemId = targetItemId,
    })
    modal:initialise()
    modal:addToUIManager()
end

function Context.fillInventoryMenu(playerNum, context, items)
    local consumable = selectedUtility(items)
    local action = actionForItem(consumable)
    if not action then return end
    local key = action == "repairHeld" and "Context_RepairHeld" or "Context_ReinforceHeld"
    local fallback = action == "repairHeld" and "Repair held item" or "Reinforce held item"
    context:addOption(text(key, fallback), consumable, Context.confirmUse, playerNum, action)
end

Events.OnFillInventoryObjectContextMenu.Add(Context.fillInventoryMenu)
