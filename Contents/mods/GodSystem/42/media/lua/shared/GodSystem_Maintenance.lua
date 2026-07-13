GodSystemMaintenance = GodSystemMaintenance or {}

GodSystemMaintenance.RepairItemType = "GodSystem.SystemRepairKit"
GodSystemMaintenance.ReinforceItemType = "GodSystem.DurabilityCore"
GodSystemMaintenance.VehicleRepairItemType = "GodSystem.SystemVehicleRepairModule"
GodSystemMaintenance.MaxSafeCondition = 2147483645

local utilityTypes = {
    [GodSystemMaintenance.RepairItemType] = true,
    [GodSystemMaintenance.ReinforceItemType] = true,
    [GodSystemMaintenance.VehicleRepairItemType] = true,
}

function GodSystemMaintenance.vehicleDamageSummary(vehicle)
    local result = { damaged = 0, missing = 0, total = 0 }
    if not vehicle or not vehicle.getPartCount or not vehicle.getPartByIndex then return result end
    local okCount, count = pcall(function() return vehicle:getPartCount() end)
    count = okCount and math.max(0, math.floor(tonumber(count) or 0)) or 0
    for index = 0, count - 1 do
        local okPart, part = pcall(function() return vehicle:getPartByIndex(index) end)
        if okPart and part then
            result.total = result.total + 1
            local missing = false
            if part.getItemType and part.getInventoryItem then
                local okTypes, itemTypes = pcall(function() return part:getItemType() end)
                local hasTypes = okTypes and itemTypes and itemTypes.isEmpty and itemTypes:isEmpty() == false
                if hasTypes then
                    local okItem, item = pcall(function() return part:getInventoryItem() end)
                    missing = okItem and item == nil
                end
            end
            local condition = 100
            if part.getCondition then
                local okCondition, value = pcall(function() return part:getCondition() end)
                if okCondition then condition = tonumber(value) or 100 end
            end
            if missing then
                result.missing = result.missing + 1
                result.damaged = result.damaged + 1
            elseif condition < 100 then
                result.damaged = result.damaged + 1
            end
        end
    end
    return result
end

local function call(object, methodName, ...)
    if not object then return false, nil end
    local okMethod, method = pcall(function() return object[methodName] end)
    if not okMethod or not method then return false, nil end
    local args = { ... }
    local unpackFn = unpack or (table and table.unpack)
    return pcall(function()
        return method(object, unpackFn(args))
    end)
end

local function syncVehiclePart(vehicle, part)
    if not vehicle or not part then return end
    local okItem, item = call(part, "getInventoryItem")
    if okItem and item then call(item, "syncItemFields") end
    call(vehicle, "transmitPartCondition", part)
    call(vehicle, "transmitPartItem", part)
    call(vehicle, "transmitPartModData", part)
end

function GodSystemMaintenance.repairVehicle(vehicle)
    local before = GodSystemMaintenance.vehicleDamageSummary(vehicle)
    if not vehicle then return false, "VehicleRepairInvalid", before, before end
    if before.damaged <= 0 then return false, "VehicleAlreadyFull", before, before end

    local repaired, repairError = call(vehicle, "repair")
    if not repaired then
        return false, "VehicleRepairFailed", before, GodSystemMaintenance.vehicleDamageSummary(vehicle), repairError
    end

    call(vehicle, "updatePartStats")
    call(vehicle, "updateBulletStats")
    call(vehicle, "updateDamageOverlay")

    local okCount, count = call(vehicle, "getPartCount")
    count = okCount and math.max(0, math.floor(tonumber(count) or 0)) or 0
    for index = 0, count - 1 do
        local okPart, part = call(vehicle, "getPartByIndex", index)
        if okPart and part then syncVehiclePart(vehicle, part) end
    end

    local after = GodSystemMaintenance.vehicleDamageSummary(vehicle)
    if after.damaged > 0 then
        return false, "VehicleRepairFailed", before, after
    end
    return true, "VehicleRepaired", before, after
end

local function number(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return value
end

local function sameNumber(a, b)
    a = number(a)
    b = number(b)
    if not a or not b then return false end
    return math.abs(a - b) < 0.0001
end

function GodSystemMaintenance.itemId(item)
    local ok, value = call(item, "getID")
    if not ok or value == nil then return nil end
    return tostring(value)
end

function GodSystemMaintenance.isUtilityItem(item)
    local ok, fullType = call(item, "getFullType")
    return ok and utilityTypes[tostring(fullType or "")] == true
end

function GodSystemMaintenance.snapshot(item)
    if not item or GodSystemMaintenance.isUtilityItem(item) then
        return nil, "MaintenanceInvalidTarget"
    end

    local okCondition, condition = call(item, "getCondition")
    local okMax, conditionMax = call(item, "getConditionMax")
    condition = number(condition)
    conditionMax = number(conditionMax)
    if not okCondition or not okMax or not condition or not conditionMax or conditionMax <= 0 then
        return nil, "MaintenanceInvalidTarget"
    end

    local snapshot = {
        condition = condition,
        conditionMax = conditionMax,
        hasHead = false,
        hasSharpness = false,
        broken = false,
    }

    local okHasHead, hasHead = call(item, "hasHeadCondition")
    if okHasHead and hasHead == true then
        local okHead, headCondition = call(item, "getHeadCondition")
        local okHeadMax, headConditionMax = call(item, "getHeadConditionMax")
        headCondition = number(headCondition)
        headConditionMax = number(headConditionMax)
        if okHead and okHeadMax and headCondition and headConditionMax and headConditionMax > 0 then
            snapshot.hasHead = true
            snapshot.headCondition = headCondition
            snapshot.headConditionMax = headConditionMax
        end
    end

    local okHasSharpness, hasSharpness = call(item, "hasSharpness")
    if okHasSharpness and hasSharpness == true then
        local okSharpness, sharpness = call(item, "getSharpness")
        sharpness = number(sharpness)
        if okSharpness and sharpness then
            snapshot.hasSharpness = true
            snapshot.sharpness = sharpness
        end
    end

    local okBroken, broken = call(item, "isBroken")
    snapshot.broken = okBroken and broken == true
    return snapshot, nil
end

function GodSystemMaintenance.isFullyRepaired(snapshot)
    if not snapshot then return false end
    if snapshot.condition < snapshot.conditionMax then return false end
    if snapshot.hasHead and snapshot.headCondition < snapshot.headConditionMax then return false end
    if snapshot.hasSharpness and snapshot.sharpness < 0.9999 then return false end
    return snapshot.broken ~= true
end

function GodSystemMaintenance.rollback(item, snapshot)
    if not item or not snapshot then return false end
    local ok = true
    local applied = call(item, "setConditionMax", snapshot.conditionMax)
    ok = applied and ok
    applied = call(item, "setCondition", snapshot.condition)
    ok = applied and ok
    if snapshot.hasHead then
        applied = call(item, "setHeadCondition", snapshot.headCondition)
        ok = applied and ok
    end
    if snapshot.hasSharpness then
        applied = call(item, "setSharpness", snapshot.sharpness)
        ok = applied and ok
    end
    if snapshot.broken ~= nil and item.setBroken then
        applied = call(item, "setBroken", snapshot.broken == true)
        ok = applied and ok
    end
    return ok
end

local function verifyRepair(item, before)
    local after = GodSystemMaintenance.snapshot(item)
    if not after then return nil end
    if not sameNumber(after.condition, before.conditionMax) then return nil end
    if before.hasHead and not sameNumber(after.headCondition, before.headConditionMax) then return nil end
    if before.hasSharpness and not sameNumber(after.sharpness, 1.0) then return nil end
    if after.broken == true then return nil end
    return after
end

local function applyRepair(item, before)
    if GodSystemMaintenance.isFullyRepaired(before) then
        return false, "MaintenanceAlreadyFull"
    end
    local ok = call(item, "setCondition", before.conditionMax)
    if not ok then return false, "MaintenanceFailed" end
    if before.hasHead then
        ok = call(item, "setHeadCondition", before.headConditionMax)
        if not ok then return false, "MaintenanceFailed" end
    end
    if before.hasSharpness then
        ok = call(item, "setSharpness", 1.0)
        if not ok then return false, "MaintenanceFailed" end
    end
    if before.broken and item.setBroken then
        ok = call(item, "setBroken", false)
        if not ok then return false, "MaintenanceFailed" end
    end
    local after = verifyRepair(item, before)
    if not after then return false, "MaintenanceFailed" end
    return true, "MaintenanceRepairSuccess", after
end

local function applyReinforce(item, before)
    local oldCondition = before.condition
    local oldMax = before.conditionMax
    if oldMax > GodSystemMaintenance.MaxSafeCondition then
        return false, "MaintenanceOverflow"
    end
    local newMax = oldMax + 2
    local newCondition = math.min(oldCondition + 2, newMax)
    local ok = call(item, "setConditionMax", newMax)
    if not ok then return false, "MaintenanceFailed" end
    ok = call(item, "setCondition", newCondition)
    if not ok then return false, "MaintenanceFailed" end
    local after = GodSystemMaintenance.snapshot(item)
    if not after or not sameNumber(after.conditionMax, newMax) or not sameNumber(after.condition, newCondition) then
        return false, "MaintenanceFailed"
    end
    return true, "MaintenanceReinforceSuccess", after
end

function GodSystemMaintenance.apply(item, action)
    local before, snapshotError = GodSystemMaintenance.snapshot(item)
    if not before then return false, snapshotError or "MaintenanceInvalidTarget" end

    local ok, code, after
    local callOk, callError = pcall(function()
        if action == "repairHeld" then
            ok, code, after = applyRepair(item, before)
        elseif action == "reinforceHeld" then
            ok, code, after = applyReinforce(item, before)
        else
            ok, code = false, "MaintenanceInvalidTarget"
        end
    end)
    if not callOk then
        GodSystemMaintenance.rollback(item, before)
        return false, "MaintenanceFailed", { error = tostring(callError) }, before
    end
    if not ok then
        GodSystemMaintenance.rollback(item, before)
        return false, code or "MaintenanceFailed", nil, before
    end
    return true, code, { before = before, after = after }, before
end
