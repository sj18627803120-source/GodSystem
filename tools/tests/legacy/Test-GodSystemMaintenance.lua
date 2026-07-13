local maintenancePath = [[C:\Users\Admin\Zomboid\Workshop\GodSystem\Contents\mods\GodSystem\42\media\lua\shared\GodSystem_Maintenance.lua]]
dofile(maintenancePath)

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEqual failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function fakeItem(options)
    options = options or {}
    local item = {
        fullType = options.fullType or "Base.TestWeapon",
        condition = options.condition or 3,
        conditionMax = options.conditionMax or 10,
        headCondition = options.headCondition,
        headConditionMax = options.headConditionMax,
        sharpness = options.sharpness,
        broken = options.broken == true,
    }
    function item:getFullType() return self.fullType end
    function item:getCondition() return self.condition end
    function item:getConditionMax() return self.conditionMax end
    function item:setCondition(value) self.condition = value end
    function item:setConditionMax(value) self.conditionMax = value end
    function item:hasHeadCondition() return self.headCondition ~= nil end
    function item:getHeadCondition() return self.headCondition end
    function item:getHeadConditionMax() return self.headConditionMax end
    function item:setHeadCondition(value) self.headCondition = value end
    function item:hasSharpness() return self.sharpness ~= nil end
    function item:getSharpness() return self.sharpness end
    function item:setSharpness(value) self.sharpness = value end
    function item:isBroken() return self.broken end
    function item:setBroken(value) self.broken = value end
    return item
end

local damaged = fakeItem({ condition = 3, conditionMax = 10, headCondition = 2, headConditionMax = 8, sharpness = 0.4, broken = true })
local okRepair, repairCode, repairResult, repairBefore = GodSystemMaintenance.apply(damaged, "repairHeld")
assertEqual(okRepair, true, "repair should succeed")
assertEqual(repairCode, "MaintenanceRepairSuccess", "repair code")
assertEqual(damaged.condition, 10, "main condition repaired")
assertEqual(damaged.headCondition, 8, "head condition repaired")
assertEqual(damaged.sharpness, 1.0, "sharpness repaired")
assertEqual(damaged.broken, false, "broken flag cleared")
assertEqual(repairResult.after.condition, 10, "repair result snapshot")

assertEqual(GodSystemMaintenance.rollback(damaged, repairBefore), true, "repair rollback")
assertEqual(damaged.condition, 3, "rollback main condition")
assertEqual(damaged.headCondition, 2, "rollback head condition")
assertEqual(damaged.sharpness, 0.4, "rollback sharpness")
assertEqual(damaged.broken, true, "rollback broken flag")

local reinforced = fakeItem({ condition = 3, conditionMax = 10, headCondition = 2, headConditionMax = 8, sharpness = 0.4 })
local okCore, coreCode, coreResult = GodSystemMaintenance.apply(reinforced, "reinforceHeld")
assertEqual(okCore, true, "reinforce should succeed")
assertEqual(coreCode, "MaintenanceReinforceSuccess", "reinforce code")
assertEqual(reinforced.condition, 5, "reinforce current condition")
assertEqual(reinforced.conditionMax, 12, "reinforce maximum condition")
assertEqual(reinforced.headCondition, 2, "reinforce must not repair head")
assertEqual(reinforced.sharpness, 0.4, "reinforce must not repair sharpness")
assertEqual(coreResult.after.conditionMax, 12, "reinforce result snapshot")

local full = fakeItem({ condition = 10, conditionMax = 10, headCondition = 8, headConditionMax = 8, sharpness = 1.0 })
local okFull, fullCode = GodSystemMaintenance.apply(full, "repairHeld")
assertEqual(okFull, false, "full item repair must fail")
assertEqual(fullCode, "MaintenanceAlreadyFull", "full item code")

local utility = fakeItem({ fullType = "GodSystem.SystemRepairKit", condition = 1, conditionMax = 1 })
local okUtility, utilityCode = GodSystemMaintenance.apply(utility, "reinforceHeld")
assertEqual(okUtility, false, "utility item must be rejected")
assertEqual(utilityCode, "MaintenanceInvalidTarget", "utility item code")

local overflow = fakeItem({ condition = 20, conditionMax = 2147483646 })
local okOverflow, overflowCode = GodSystemMaintenance.apply(overflow, "reinforceHeld")
assertEqual(okOverflow, false, "overflow must be rejected")
assertEqual(overflowCode, "MaintenanceOverflow", "overflow code")

print("Test-GodSystemMaintenance passed")
