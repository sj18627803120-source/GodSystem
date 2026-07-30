GodSystemMaintenanceRulesFeature = GodSystemMaintenanceRulesFeature or {}

local Descriptor = GodSystemMaintenanceRulesFeature

Descriptor.id = "maintenance.rules"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

Descriptor.RepairItemType = "GodSystem.SystemRepairKit"
Descriptor.ReinforceItemType = "GodSystem.DurabilityCore"
Descriptor.VehicleRepairItemType = "GodSystem.SystemVehicleRepairModule"
Descriptor.MaxSafeCondition = 2147483645

local function call(object, methodName, ...)
    if not object then return false, nil end
    local method = object[methodName]
    if type(method) ~= "function" then return false, nil end
    return true, method(object, ...)
end

local function number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function sameNumber(left, right)
    left, right = number(left), number(right)
    return left and right and math.abs(left - right) < 0.0001
end

local function itemFullType(item)
    local ok, value = call(item, "getFullType")
    return ok and tostring(value or "") or ""
end

local function itemSnapshot(item)
    if not item then return nil, "MaintenanceInvalidTarget" end
    local fullType = itemFullType(item)
    if fullType == Descriptor.RepairItemType
        or fullType == Descriptor.ReinforceItemType
        or fullType == Descriptor.VehicleRepairItemType then
        return nil, "MaintenanceInvalidTarget"
    end
    local okCondition, condition = call(item, "getCondition")
    local okMax, conditionMax = call(item, "getConditionMax")
    condition, conditionMax = number(condition), number(conditionMax)
    if not okCondition or not okMax or not condition or not conditionMax or conditionMax <= 0 then
        return nil, "MaintenanceInvalidTarget"
    end
    local snapshot = {
        kind = "item",
        condition = condition,
        conditionMax = conditionMax,
        hasHead = false,
        hasSharpness = false,
        broken = false,
    }
    local okHeadFlag, hasHead = call(item, "hasHeadCondition")
    if okHeadFlag and hasHead == true then
        local okHead, head = call(item, "getHeadCondition")
        local okHeadMax, headMax = call(item, "getHeadConditionMax")
        head, headMax = number(head), number(headMax)
        if okHead and okHeadMax and head and headMax and headMax > 0 then
            snapshot.hasHead = true
            snapshot.headCondition = head
            snapshot.headConditionMax = headMax
        end
    end
    local okSharpFlag, hasSharpness = call(item, "hasSharpness")
    if okSharpFlag and hasSharpness == true then
        local okSharp, sharpness = call(item, "getSharpness")
        sharpness = number(sharpness)
        if okSharp and sharpness then
            snapshot.hasSharpness = true
            snapshot.sharpness = sharpness
        end
    end
    local okBroken, broken = call(item, "isBroken")
    snapshot.broken = okBroken and broken == true
    return snapshot
end

local function fullyRepaired(snapshot)
    if snapshot.condition < snapshot.conditionMax then return false end
    if snapshot.hasHead and snapshot.headCondition < snapshot.headConditionMax then return false end
    if snapshot.hasSharpness and snapshot.sharpness < 0.9999 then return false end
    return snapshot.broken ~= true
end

local function vehicleSummary(vehicle)
    local result = { kind = "vehicle", damaged = 0, missing = 0, total = 0 }
    local okCount, count = call(vehicle, "getPartCount")
    count = okCount and math.max(0, math.floor(tonumber(count) or 0)) or 0
    for index = 0, count - 1 do
        local okPart, part = call(vehicle, "getPartByIndex", index)
        if okPart and part then
            result.total = result.total + 1
            local missing = false
            local okTypes, itemTypes = call(part, "getItemType")
            if okTypes and itemTypes and type(itemTypes.isEmpty) == "function" and itemTypes:isEmpty() == false then
                local okItem, inventoryItem = call(part, "getInventoryItem")
                missing = okItem and inventoryItem == nil
            end
            local okCondition, condition = call(part, "getCondition")
            condition = okCondition and tonumber(condition) or 100
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

local function inVehicleRange(actor, vehicle)
    if not actor or not vehicle then return false, "VehicleRepairInvalid" end
    if type(actor.getVehicle) == "function" and actor:getVehicle() == vehicle then return true end
    local az = math.floor(tonumber(actor:getZ()) or 0)
    local vz = math.floor(tonumber(vehicle:getZ()) or 0)
    if az ~= vz then return false, "VehicleRepairWrongFloor" end
    local dx = (tonumber(actor:getX()) or 0) - (tonumber(vehicle:getX()) or 0)
    local dy = (tonumber(actor:getY()) or 0) - (tonumber(vehicle:getY()) or 0)
    if dx * dx + dy * dy > 16 then return false, "VehicleRepairTooFar" end
    return true
end

local function rollbackItem(item, snapshot)
    if not item or not snapshot or snapshot.kind ~= "item" then return false end
    local ok = call(item, "setConditionMax", snapshot.conditionMax)
    local applied = call(item, "setCondition", snapshot.condition)
    ok = ok and applied
    if snapshot.hasHead then
        applied = call(item, "setHeadCondition", snapshot.headCondition)
        ok = ok and applied
    end
    if snapshot.hasSharpness then
        applied = call(item, "setSharpness", snapshot.sharpness)
        ok = ok and applied
    end
    if type(item.setBroken) == "function" then
        applied = call(item, "setBroken", snapshot.broken == true)
        ok = ok and applied
    end
    return ok
end

local function applyItem(action, item, before)
    if action == "repairItem" then
        if fullyRepaired(before) then return false, "MaintenanceAlreadyFull" end
        if not call(item, "setCondition", before.conditionMax) then return false, "MaintenanceFailed" end
        if before.hasHead and not call(item, "setHeadCondition", before.headConditionMax) then
            return false, "MaintenanceFailed"
        end
        if before.hasSharpness and not call(item, "setSharpness", 1.0) then
            return false, "MaintenanceFailed"
        end
        if before.broken and type(item.setBroken) == "function" and not call(item, "setBroken", false) then
            return false, "MaintenanceFailed"
        end
    elseif action == "enhanceDurability" then
        if before.conditionMax > Descriptor.MaxSafeCondition then return false, "MaintenanceOverflow" end
        local nextMax = before.conditionMax + 2
        local nextCondition = math.min(before.condition + 2, nextMax)
        if not call(item, "setConditionMax", nextMax) or not call(item, "setCondition", nextCondition) then
            return false, "MaintenanceFailed"
        end
    else
        return false, "MaintenanceInvalidTarget"
    end
    local after = itemSnapshot(item)
    if not after then return false, "MaintenanceFailed" end
    if action == "repairItem" then
        if not sameNumber(after.condition, before.conditionMax)
            or (before.hasHead and not sameNumber(after.headCondition, before.headConditionMax))
            or (before.hasSharpness and not sameNumber(after.sharpness, 1.0))
            or after.broken == true then
            return false, "MaintenanceFailed"
        end
    else
        if not sameNumber(after.conditionMax, before.conditionMax + 2)
            or not sameNumber(after.condition, math.min(before.condition + 2, before.conditionMax + 2)) then
            return false, "MaintenanceFailed"
        end
    end
    return true, after
end

local function applyVehicle(vehicle)
    local before = vehicleSummary(vehicle)
    if before.damaged <= 0 then return false, "VehicleAlreadyFull" end
    local repaired = call(vehicle, "repair")
    if not repaired then return false, "VehicleRepairFailed" end
    call(vehicle, "updatePartStats")
    call(vehicle, "updateBulletStats")
    call(vehicle, "updateDamageOverlay")
    local okCount, count = call(vehicle, "getPartCount")
    count = okCount and math.max(0, math.floor(tonumber(count) or 0)) or 0
    for index = 0, count - 1 do
        local okPart, part = call(vehicle, "getPartByIndex", index)
        if okPart and part then
            local okItem, item = call(part, "getInventoryItem")
            if okItem and item then call(item, "syncItemFields") end
            call(vehicle, "transmitPartCondition", part)
            call(vehicle, "transmitPartItem", part)
            call(vehicle, "transmitPartModData", part)
        end
    end
    local after = vehicleSummary(vehicle)
    if after.damaged >= before.damaged and after.damaged > 0 then
        return false, "VehicleRepairFailed"
    end
    return true, after
end

function Descriptor.create()
    local instance = { started = false, validations = 0, failures = 0 }

    instance.public = {
        validate = function(action, actor, target, consumable)
            instance.validations = instance.validations + 1
            local expected = action == "repairItem" and Descriptor.RepairItemType
                or action == "enhanceDurability" and Descriptor.ReinforceItemType
                or action == "repairVehicle" and Descriptor.VehicleRepairItemType
                or nil
            if not expected or itemFullType(consumable) ~= expected then
                return false, "MaintenanceConsumableMissing"
            end
            if action == "repairVehicle" then
                local inRange, code = inVehicleRange(actor, target)
                if not inRange then return false, code end
                if vehicleSummary(target).damaged <= 0 then return false, "VehicleAlreadyFull" end
            else
                local snapshot, code = itemSnapshot(target)
                if not snapshot then return false, code end
                if action == "repairItem" and fullyRepaired(snapshot) then
                    return false, "MaintenanceAlreadyFull"
                end
                if action == "enhanceDurability" and snapshot.conditionMax > Descriptor.MaxSafeCondition then
                    return false, "MaintenanceOverflow"
                end
            end
            return true, { cost = 0 }
        end,
        snapshot = function(action, target)
            if action == "repairVehicle" then return vehicleSummary(target) end
            return itemSnapshot(target)
        end,
        apply = function(action, target)
            local ok, valueOrCode = action == "repairVehicle"
                and applyVehicle(target)
                or applyItem(action, target, assert(itemSnapshot(target)))
            if not ok then
                instance.failures = instance.failures + 1
                return false, valueOrCode
            end
            return true, valueOrCode
        end,
        rollback = function(action, target, snapshot)
            if action == "repairVehicle" then return true end
            return rollbackItem(target, snapshot)
        end,
        vehicleSummary = vehicleSummary,
        itemSnapshot = itemSnapshot,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "ruleFailure" or (self.started and "healthy" or "stopped"),
            data = { validations = self.validations, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
