local shared = assert(arg and arg[1], "shared Lua directory argument is required")
shared = string.gsub(shared, "\\", "/")
if string.sub(shared, -1) ~= "/" then shared = shared .. "/" end

dofile(shared .. "GodSystem_Maintenance.lua")

local function itemTypes(hasItem)
    return { isEmpty = function() return hasItem ~= true end }
end

local function newPart(condition, missing)
    local part = { condition = condition, missing = missing == true }
    function part:getItemType() return itemTypes(true) end
    function part:getInventoryItem()
        if self.missing then return nil end
        return {}
    end
    function part:getCondition() return self.condition end
    return part
end

local function newVehicle(parts, repairFn)
    local vehicle = {}
    function vehicle:getPartCount() return #parts end
    function vehicle:getPartByIndex(index) return parts[index + 1] end
    function vehicle:repair() repairFn(parts) end
    return vehicle
end

local partialParts = {
    newPart(40, false),
    newPart(100, true),
}
local partialVehicle = newVehicle(partialParts, function(parts)
    parts[1].condition = 100
end)
local repaired, code, before, after = GodSystemMaintenance.repairVehicle(partialVehicle)
assert(repaired == true and code == "VehicleRepaired", "a real repair must succeed even if an invalid MOD part remains missing")
assert(before.damaged == 2 and after.damaged == 1 and after.missing == 1, "partial repair summary mismatch")

local stalledParts = { newPart(100, true) }
local stalledVehicle = newVehicle(stalledParts, function() end)
repaired, code, before, after = GodSystemMaintenance.repairVehicle(stalledVehicle)
assert(repaired == false and code == "VehicleRepairFailed", "a repair with no measurable progress must still fail and refund")
assert(before.damaged == 1 and after.damaged == 1, "stalled repair summary mismatch")

local completeParts = { newPart(25, false) }
local completeVehicle = newVehicle(completeParts, function(parts)
    parts[1].condition = 100
end)
repaired, code, before, after = GodSystemMaintenance.repairVehicle(completeVehicle)
assert(repaired == true and after.damaged == 0, "a complete vanilla repair must remain successful")

print("Test-GodSystemV11663VehicleRepairRuntime passed")
