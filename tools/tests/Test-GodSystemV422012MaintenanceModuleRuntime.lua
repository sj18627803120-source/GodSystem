local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Features/Maintenance/Module"

local Descriptor = assert(GodSystemMaintenanceFeatureModule)
assert(Descriptor.id == "feature.maintenance", "maintenance module id changed")

local function newFixture(environment)
    local actor = { id = "player-1" }
    local items = {
        kit = { id = "kit", kind = "consumable" },
        weapon = { id = "weapon", condition = 4, conditionMax = 10 },
    }
    local vehicles = {
        car = { id = "car", condition = 30, conditionMax = 100 },
    }
    local state = {
        environment = environment,
        balance = 100,
        consumed = false,
        notifications = {},
        calls = {},
        failApply = false,
        failConsume = false,
        failRestore = false,
        failRefund = false,
    }

    local function record(value)
        state.calls[#state.calls + 1] = environment .. ":" .. value
    end

    local query = {
        resolveItem = function(owner, itemId)
            record("resolveItem")
            assert(owner == actor, "query received the wrong actor")
            return items[tostring(itemId or "")], "itemMissing"
        end,
        resolveVehicle = function(owner, vehicleId)
            record("resolveVehicle")
            assert(owner == actor, "vehicle query received the wrong actor")
            return vehicles[tostring(vehicleId or "")], "vehicleMissing"
        end,
    }

    local mutation = {
        consume = function(owner, item)
            record("consume")
            assert(owner == actor and item == items.kit, "wrong consumable")
            if state.failConsume then return false, "consumeRejected" end
            state.consumed = true
            return true, { item = item }
        end,
        restore = function(owner, receipt)
            record("restore")
            assert(owner == actor and receipt.item == items.kit, "wrong restore receipt")
            if state.failRestore then return false end
            state.consumed = false
            return true
        end,
    }

    local wallet = {
        charge = function(owner, cost)
            record("charge")
            assert(owner == actor, "wallet received the wrong actor")
            if state.balance < cost then return false, "insufficientFunds" end
            state.balance = state.balance - cost
            return true, { amount = cost }
        end,
        refund = function(owner, receipt)
            record("refund")
            assert(owner == actor, "wallet refund received the wrong actor")
            if state.failRefund then return false end
            state.balance = state.balance + receipt.amount
            return true
        end,
    }

    local rules = {
        validate = function(action, owner, target, consumable)
            record("validate:" .. action)
            assert(owner == actor and target and consumable == items.kit, "invalid rule arguments")
            return true, { cost = action == "repairVehicle" and 5 or 0 }
        end,
        snapshot = function(action, target)
            record("snapshot:" .. action)
            return {
                condition = target.condition,
                conditionMax = target.conditionMax,
            }
        end,
        apply = function(action, target)
            record("apply:" .. action)
            if action == "repairItem" then
                target.condition = target.conditionMax
            elseif action == "enhanceDurability" then
                target.conditionMax = target.conditionMax + 5
                target.condition = target.conditionMax
            elseif action == "repairVehicle" then
                target.condition = target.conditionMax
            end
            if state.failApply then return false, "applyRejected", { reason = "fixture" } end
            return true, { condition = target.condition, conditionMax = target.conditionMax }
        end,
        rollback = function(action, target, snapshot)
            record("rollback:" .. action)
            target.condition = snapshot.condition
            target.conditionMax = snapshot.conditionMax
            return true
        end,
    }

    local notifications = {
        publish = function(value)
            record("notify")
            state.notifications[#state.notifications + 1] = value
            return true
        end,
    }

    local instance = Descriptor.create({
        ["inventory.query"] = query,
        ["inventory.mutation"] = mutation,
        wallet = wallet,
        ["maintenance.rules"] = rules,
        notifications = notifications,
    }, {
        moduleId = Descriptor.id,
        environment = environment,
    })
    assert(instance:start())

    return {
        actor = actor,
        items = items,
        vehicles = vehicles,
        state = state,
        instance = instance,
    }
end

local function successSignature(environment)
    local fixture = newFixture(environment)
    local repair = fixture.instance.public.repairItem({
        actor = fixture.actor,
        targetId = "weapon",
        consumableId = "kit",
        operationId = environment .. "-repair",
    })
    assert(repair.ok and repair.code == "completed", "repairItem failed")
    assert(fixture.items.weapon.condition == 10, "repairItem did not repair the item")

    fixture.items.weapon.condition = 4
    fixture.state.consumed = false
    local enhance = fixture.instance.public.enhanceDurability({
        actor = fixture.actor,
        targetId = "weapon",
        consumableId = "kit",
        operationId = environment .. "-enhance",
    })
    assert(enhance.ok and enhance.code == "completed", "enhanceDurability failed")
    assert(fixture.items.weapon.conditionMax == 15 and fixture.items.weapon.condition == 15,
        "enhanceDurability did not use the shared rule")

    fixture.state.consumed = false
    local vehicle = fixture.instance.public.repairVehicle({
        actor = fixture.actor,
        vehicleId = "car",
        consumableId = "kit",
        operationId = environment .. "-vehicle",
    })
    assert(vehicle.ok and vehicle.code == "completed", "repairVehicle failed")
    assert(fixture.vehicles.car.condition == 100, "repairVehicle did not repair the vehicle")
    assert(fixture.state.balance == 95, "wallet cost was not settled")
    assert(#fixture.state.notifications == 3, "results were not published")

    local health = fixture.instance:health()
    assert(health.ok and health.data.completed == 3 and health.data.failed == 0,
        "health counters are incorrect")

    return table.concat({
        repair.code,
        enhance.code,
        vehicle.code,
        tostring(fixture.items.weapon.conditionMax),
        tostring(fixture.vehicles.car.condition),
        tostring(fixture.state.balance),
    }, "|")
end

local spSignature = successSignature("sp")
local mpSignature = successSignature("mp")
assert(spSignature == mpSignature, "SP and MP adapters changed maintenance business results")

do
    local fixture = newFixture("rollback")
    fixture.state.failApply = true
    local beforeBalance = fixture.state.balance
    local value = fixture.instance.public.repairVehicle({
        actor = fixture.actor,
        vehicleId = "car",
        consumableId = "kit",
        operationId = "rollback-1",
    })
    assert(not value.ok and value.code == "applyRejected", "apply failure code was lost")
    assert(fixture.vehicles.car.condition == 30, "target snapshot was not restored")
    assert(fixture.state.consumed == false, "consumable was not restored")
    assert(fixture.state.balance == beforeBalance, "wallet payment was not restored")
    assert(value.data.rollback.complete == true, "complete rollback was not reported")
end

do
    local fixture = newFixture("consume-failure")
    fixture.state.failConsume = true
    local beforeBalance = fixture.state.balance
    local value = fixture.instance.public.repairVehicle({
        actor = fixture.actor,
        vehicleId = "car",
        consumableId = "kit",
        operationId = "consume-1",
    })
    assert(not value.ok and value.code == "consumeRejected", "consume failure code was lost")
    assert(fixture.vehicles.car.condition == 30, "target changed before successful consumption")
    assert(fixture.state.balance == beforeBalance, "payment was not refunded after consume failure")
end

do
    local fixture = newFixture("degraded-rollback")
    fixture.state.failApply = true
    fixture.state.failRestore = true
    local value = fixture.instance.public.repairItem({
        actor = fixture.actor,
        targetId = "weapon",
        consumableId = "kit",
        operationId = "rollback-2",
    })
    assert(not value.ok and value.code == "rollbackIncomplete", "degraded rollback was hidden")
    assert(value.data.rollback.inventory == false, "failed inventory restore was not reported")
    local health = fixture.instance:health()
    assert(not health.ok and health.code == "rollbackIncomplete", "health did not retain rollback issue")
end

do
    local fixture = newFixture("lifecycle")
    fixture.instance:stop("test")
    local value = fixture.instance.public.repairItem({
        actor = fixture.actor,
        targetId = "weapon",
        consumableId = "kit",
    })
    assert(not value.ok and value.code == "moduleStopped", "stopped module still executed")
end

print("Test-GodSystemV422012MaintenanceModuleRuntime passed")
