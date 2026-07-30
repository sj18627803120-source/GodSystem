local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Features/Upgrades/Module"
require "GodSystem/Features/Medical/Module"
require "GodSystem/Features/Home/Module"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
    return result
end

local function operations()
    local rows = {}
    return {
        begin = function(moduleId, operationId, fingerprint)
            local key = tostring(moduleId) .. "|" .. tostring(operationId)
            local row = rows[key]
            if row then
                if row.fingerprint ~= fingerprint then return "blocked", "operationMismatch" end
                if row.result then return "replay", row.result end
                return "blocked", "operationPending"
            end
            rows[key] = { fingerprint = fingerprint }
            return "new"
        end,
        finish = function(moduleId, operationId, result)
            local key = tostring(moduleId) .. "|" .. tostring(operationId)
            assert(rows[key], "operation was not begun")
            rows[key].result = result
            return true
        end,
    }
end

local function notifications()
    local port = { values = {}, fail = false }
    function port.publish(value)
        port.values[#port.values + 1] = value
        return port.fail ~= true
    end
    return port
end

local function upgradeFixture(environment)
    local fixture = {
        actor = { id = environment .. "-player" },
        data = {
            upgrades = { carryCapacityLevel = 0, maxActiveTasks = 3, dailyTaskCount = 5 },
            autoRecyclerCapacityLevel = 1,
            autoRecyclerReductionLevel = 1,
            autoRecyclerReliefLevel = 1,
            tasks = {},
        },
        metrics = {},
        balance = 20000,
        applied = {},
        sequence = {},
        failAbility = nil,
        failMetric = false,
        failSave = false,
        taskAdds = 0,
        infiniteType = nil,
    }
    local notices = notifications()
    local costs = {
        activeTasks = { [3] = 100 },
        dailyTasks = { [5] = 50 },
        terminalCapacity = { [1] = 60 },
        terminalReduction = { [1] = 100 },
        terminalRelief = { [1] = 2000 },
    }
    local dependencies = {
        ["upgrades.config"] = {
            quote = function(_, upgradeType, current)
                if fixture.infiniteType == upgradeType then
                    return { nextValue = current + 1, cost = math.huge }
                end
                if upgradeType == "carryCapacity" then
                    return { nextValue = current + 1, cost = math.ceil(2000 * (1.5 ^ current)) }
                end
                local cost = costs[upgradeType] and costs[upgradeType][current] or nil
                if not cost then return nil, "upgradeMaxed" end
                return { nextValue = current + 1, cost = cost }
            end,
        },
        ["upgrades.state"] = {
            load = function() return fixture.data end,
            save = function(_, data)
                if fixture.failSave then
                    fixture.failSave = false
                    return false, "stateSaveFailed"
                end
                fixture.data = clone(data)
                return true
            end,
        },
        ["upgrades.abilities"] = {
            snapshot = function(_, upgradeType)
                fixture.sequence[#fixture.sequence + 1] = "snapshot:" .. upgradeType
                return { value = fixture.applied[upgradeType] }
            end,
            apply = function(_, upgradeType, level)
                fixture.sequence[#fixture.sequence + 1] = "apply:" .. upgradeType
                if fixture.failAbility == upgradeType then return false, "abilityApplyFailed" end
                fixture.applied[upgradeType] = level
                return true, { level = level, skipped = 0 }
            end,
            restore = function(_, upgradeType, snapshot)
                fixture.sequence[#fixture.sequence + 1] = "restore:" .. upgradeType
                fixture.applied[upgradeType] = snapshot.value
                return true
            end,
        },
        ["upgrades.tasks"] = {
            addOpen = function(_, data)
                fixture.taskAdds = fixture.taskAdds + 1
                local task = { id = "immediate-" .. fixture.taskAdds, status = "open" }
                data.tasks[#data.tasks + 1] = task
                return true, { id = task.id }
            end,
            rollback = function(_, receipt)
                for i = #fixture.data.tasks, 1, -1 do
                    if fixture.data.tasks[i].id == receipt.id then table.remove(fixture.data.tasks, i) end
                end
                return true
            end,
        },
        ["upgrades.wallet"] = {
            charge = function(_, amount)
                fixture.sequence[#fixture.sequence + 1] = "charge:" .. amount
                if fixture.balance < amount then return false, "insufficientFunds" end
                fixture.balance = fixture.balance - amount
                return true, { amount = amount }
            end,
            refund = function(_, receipt)
                fixture.sequence[#fixture.sequence + 1] = "refund:" .. receipt.amount
                fixture.balance = fixture.balance + receipt.amount
                return true
            end,
        },
        metrics = {
            snapshot = function() return clone(fixture.metrics) end,
            get = function(_, name) return fixture.metrics[name] or 0 end,
            increment = function(_, changes)
                if fixture.failMetric then return false, "metricUpdateFailed" end
                local before, after = {}, {}
                for name, amount in pairs(changes) do
                    before[name] = fixture.metrics[name] or 0
                    after[name] = before[name] + amount
                end
                for name, value in pairs(after) do fixture.metrics[name] = value end
                return true, { before = before, after = after }
            end,
            restore = function(_, receipt)
                for name, value in pairs(receipt.before or {}) do fixture.metrics[name] = value end
                return true
            end,
        },
        operations = operations(),
        notifications = notices,
    }
    fixture.notices = notices
    fixture.instance = GodSystemUpgradesFeatureModule.create(dependencies, {
        moduleId = "feature.upgrades",
        environment = environment,
    })
    assert(fixture.instance:start())
    return fixture
end

local function runUpgradeSuccess(environment)
    local f = upgradeFixture(environment)
    local types = {
        "carryCapacity", "activeTasks", "dailyTasks",
        "terminalCapacity", "terminalReduction", "terminalRelief",
    }
    local spent = 0
    for i = 1, #types do
        local result = f.instance.public.upgrade({
            actor = f.actor,
            upgradeType = types[i],
            operationId = environment .. "-" .. types[i],
        })
        assert(result.ok and result.code == "upgraded", "upgrade failed: " .. types[i])
        spent = spent + result.data.cost
    end
    assert(f.data.upgrades.carryCapacityLevel == 1 and f.data.upgrades.maxActiveTasks == 4 and
        f.data.upgrades.dailyTaskCount == 6, "character/task upgrade levels are wrong")
    assert(f.data.autoRecyclerCapacityLevel == 2 and f.data.autoRecyclerReductionLevel == 2 and
        f.data.autoRecyclerReliefLevel == 2, "terminal upgrade levels are wrong")
    assert(spent == 4310 and f.balance == 15690 and f.metrics.spentPoints == 4310,
        "upgrade prices changed")
    assert(#f.data.tasks == 1, "daily task upgrade did not add one open task")
    assert(f.sequence[1] == "snapshot:carryCapacity" and f.sequence[2] == "apply:carryCapacity" and
        f.sequence[3] == "charge:2000", "carry ability was not applied before charging")
    local before = f.balance
    local replay = f.instance.public.upgrade({
        actor = f.actor,
        upgradeType = "carryCapacity",
        operationId = environment .. "-carryCapacity",
    })
    assert(replay.ok and f.balance == before and f.data.upgrades.carryCapacityLevel == 1,
        "upgrade replay charged or upgraded twice")
    local refreshed = f.instance.public.refresh({
        actor = f.actor,
        upgradeType = "carryCapacity",
        operationId = environment .. "-refresh",
    })
    assert(refreshed.ok and refreshed.code == "refreshed" and f.balance == before,
        "carry refresh charged currency or failed")
    return table.concat({ spent, f.balance, f.data.upgrades.dailyTaskCount, #f.data.tasks }, "|")
end

assert(runUpgradeSuccess("sp") == runUpgradeSuccess("mp"), "SP/MP upgrade behavior diverged")

do
    local f = upgradeFixture("upgrade-rollback")
    f.failSave = true
    local result = f.instance.public.upgrade({
        actor = f.actor,
        upgradeType = "terminalCapacity",
        operationId = "upgrade-save-fail",
    })
    assert(not result.ok and result.code == "stateSaveFailed", "upgrade save failure code was lost")
    assert(f.data.autoRecyclerCapacityLevel == 1 and f.applied.terminalCapacity == nil and f.balance == 20000,
        "upgrade ability/wallet/state rollback failed")
end

do
    local f = upgradeFixture("upgrade-metric-rollback")
    f.failMetric = true
    local result = f.instance.public.upgrade({
        actor = f.actor,
        upgradeType = "terminalCapacity",
        operationId = "upgrade-metric-fail",
    })
    assert(not result.ok and result.code == "metricUpdateFailed",
        "upgrade metric failure code was lost")
    assert(f.data.autoRecyclerCapacityLevel == 1
        and f.applied.terminalCapacity == nil and f.balance == 20000,
        "upgrade metric failure did not roll back ability, wallet, and state")
end

do
    local f = upgradeFixture("upgrade-infinite")
    f.infiniteType = "carryCapacity"
    local result = f.instance.public.upgrade({
        actor = f.actor,
        upgradeType = "carryCapacity",
        operationId = "upgrade-infinite-1",
    })
    assert(not result.ok and result.code == "quoteInvalid" and f.balance == 20000,
        "non-finite upgrade quote was accepted")
end

local function medicalFixture(environment)
    local fixture = {
        actor = { id = environment .. "-player" },
        data = { stats = {} },
        balance = 10000,
        body = { infected = true, injured = true },
        now = 77,
        failApply = nil,
        failSave = false,
        infiniteAction = nil,
    }
    local notices = notifications()
    local prices = { checkInfection = 50, healInjuries = 5000, cureInfection = 2000 }
    local dependencies = {
        ["medical.config"] = {
            cost = function(action)
                if fixture.infiniteAction == action then return 0 / 0 end
                return prices[action]
            end,
        },
        ["medical.state"] = {
            load = function() return fixture.data end,
            save = function(_, data)
                if fixture.failSave then fixture.failSave = false return false, "stateSaveFailed" end
                fixture.data = clone(data)
                return true
            end,
        },
        ["medical.body"] = {
            inspect = function() return clone(fixture.body) end,
            snapshot = function() return clone(fixture.body) end,
            apply = function(_, action)
                if fixture.failApply == action then return false, "medicalApplyFailed" end
                if action == "checkInfection" then
                    return true, fixture.body.infected and "infected" or "clean"
                elseif action == "healInjuries" then
                    fixture.body.injured = false
                    return true, "healed"
                elseif action == "cureInfection" then
                    fixture.body.infected = false
                    return true, "cured"
                end
            end,
            restore = function(_, snapshot) fixture.body = clone(snapshot) return true end,
        },
        ["medical.wallet"] = {
            charge = function(_, amount)
                if fixture.balance < amount then return false, "insufficientFunds" end
                fixture.balance = fixture.balance - amount
                return true, { amount = amount }
            end,
            refund = function(_, receipt) fixture.balance = fixture.balance + receipt.amount return true end,
        },
        clock = { nowHours = function() return fixture.now end },
        operations = operations(),
        notifications = notices,
    }
    fixture.notices = notices
    fixture.instance = GodSystemMedicalFeatureModule.create(dependencies, {
        moduleId = "feature.medical",
        environment = environment,
    })
    assert(fixture.instance:start())
    return fixture
end

local function runMedicalSuccess(environment)
    local f = medicalFixture(environment)
    local check = f.instance.public.checkInfection({ actor = f.actor, operationId = environment .. "-check" })
    local heal = f.instance.public.healInjuries({ actor = f.actor, operationId = environment .. "-heal" })
    local cure = f.instance.public.cureInfection({ actor = f.actor, operationId = environment .. "-cure" })
    assert(check.ok and check.data.result == "infected", "infection check changed")
    assert(heal.ok and not f.body.injured, "injury treatment failed")
    assert(cure.ok and not f.body.infected, "infection cure failed")
    assert(f.balance == 2950 and f.data.stats.spentPoints == 7050, "medical prices changed")
    local before = f.balance
    local replay = f.instance.public.cureInfection({ actor = f.actor, operationId = environment .. "-cure" })
    assert(replay == cure and f.balance == before, "medical service was not idempotent")
    return table.concat({ check.data.result, heal.data.result, cure.data.result, f.balance }, "|")
end

assert(runMedicalSuccess("sp") == runMedicalSuccess("mp"), "SP/MP medical behavior diverged")

do
    local f = medicalFixture("medical-rollback")
    f.failApply = "healInjuries"
    local result = f.instance.public.healInjuries({ actor = f.actor, operationId = "medical-fail" })
    assert(not result.ok and result.code == "medicalApplyFailed", "medical failure code was lost")
    assert(f.body.injured and f.balance == 10000, "medical body/wallet rollback failed")
end

do
    local f = medicalFixture("medical-infinite")
    f.infiniteAction = "checkInfection"
    local result = f.instance.public.checkInfection({ actor = f.actor, operationId = "medical-nan" })
    assert(not result.ok and result.code == "quoteInvalid" and f.balance == 10000,
        "non-finite medical quote was accepted")
end

local function homeFixture(environment)
    local fixture = {
        actor = { id = environment .. "-player" },
        data = { homeSystem = { tempSlots = {}, safeZone = {} }, stats = {} },
        balance = 5000,
        current = { x = 10, y = 20, z = 0 },
        now = 100,
        threats = 2,
        failSave = false,
        failTeleport = false,
        failClear = false,
    }
    local notices = notifications()
    local levels = {
        { level = 1, radius = 12, unlockCost = 500, clearCost = 8 },
        { level = 2, radius = 20, upgradeCost = 1000, clearCost = 12 },
    }
    local function level(value)
        for i = 1, #levels do if levels[i].level == value then return clone(levels[i]) end end
        return nil
    end
    local dependencies = {
        ["home.config"] = {
            isEnabled = function() return true end,
            cost = function(action, _, data)
                if action == "setHome" then return 100 end
                if action == "buyTemp" then return 500 end
                if action == "setTemp" then return 100 end
                if action == "teleportHome" or action == "teleportTemp" or action == "return" then return 10 end
                if action == "clearSafeZone" then
                    local row = level(data.homeSystem.safeZone.level)
                    return row and row.clearCost or 0
                end
                return 0
            end,
            maxTempSlots = function() return 3 end,
            safeLevel = function(value) return level(value) end,
            nextSafeLevel = function(value) return level(value + 1), "safeZoneMaxed" end,
        },
        ["home.state"] = {
            load = function() return fixture.data end,
            save = function(_, data)
                if fixture.failSave then fixture.failSave = false return false, "stateSaveFailed" end
                fixture.data = clone(data)
                return true
            end,
        },
        ["home.position"] = {
            blockedReason = function() return nil end,
            current = function() return clone(fixture.current) end,
            validate = function(_, target)
                if target.x == 999 then return nil, "targetInvalid" end
                return clone(target)
            end,
            teleport = function(_, target)
                if fixture.failTeleport then return false, "teleportFailed" end
                local receipt = { previous = clone(fixture.current) }
                fixture.current = clone(target)
                return true, receipt
            end,
            restore = function(_, receipt) fixture.current = clone(receipt.previous) return true end,
        },
        ["home.world"] = {
            planClear = function(_, center, radius)
                assert(center and radius > 0, "safe-zone plan did not receive center/radius")
                return { count = fixture.threats }
            end,
            executeClear = function(_, plan)
                if fixture.failClear then return false, "clearFailed" end
                fixture.threats = math.max(0, fixture.threats - plan.count)
                return true, plan.count
            end,
        },
        ["home.wallet"] = {
            charge = function(_, amount)
                if fixture.balance < amount then return false, "insufficientFunds" end
                fixture.balance = fixture.balance - amount
                return true, { amount = amount }
            end,
            refund = function(_, receipt) fixture.balance = fixture.balance + receipt.amount return true end,
        },
        clock = { nowHours = function() return fixture.now end },
        operations = operations(),
        notifications = notices,
    }
    fixture.notices = notices
    fixture.instance = GodSystemHomeFeatureModule.create(dependencies, {
        moduleId = "feature.home",
        environment = environment,
    })
    assert(fixture.instance:start())
    return fixture
end

local function runHomeSuccess(environment)
    local f = homeFixture(environment)
    assert(f.instance.public.setHome({ actor = f.actor, operationId = environment .. "-home" }).ok)
    assert(f.data.homeSystem.home.x == 10 and f.balance == 4900, "set-home cost or position changed")
    assert(f.instance.public.buyTemp({
        actor = f.actor, index = 1, operationId = environment .. "-buy-temp",
    }).ok)
    f.current = { x = 30, y = 40, z = 0 }
    assert(f.instance.public.setTemp({
        actor = f.actor, index = 1, operationId = environment .. "-set-temp",
    }).ok)
    local homeTravel = f.instance.public.teleportHome({
        actor = f.actor, operationId = environment .. "-teleport-home",
    })
    assert(homeTravel.ok and f.current.x == 10 and f.data.homeSystem.returnPoint.x == 30,
        "home teleport or departure point failed")
    local replay = f.instance.public.teleportHome({
        actor = f.actor, operationId = environment .. "-teleport-home",
    })
    assert(replay == homeTravel and f.balance == 4290, "home teleport replay charged twice")
    assert(f.instance.public.returnToDeparture({
        actor = f.actor, operationId = environment .. "-return",
    }).ok)
    assert(f.current.x == 30 and f.data.homeSystem.returnPoint == nil, "return teleport failed")
    local safe = f.instance.public.upgradeSafeZone({
        actor = f.actor, operationId = environment .. "-safe-upgrade",
    })
    assert(safe.ok and safe.data.level == 1 and f.data.homeSystem.safeZone.enabled, "safe-zone unlock failed")
    assert(f.instance.public.toggleSafeZone({
        actor = f.actor, operationId = environment .. "-safe-off",
    }).code == "safeZoneDisabled")
    assert(f.instance.public.toggleSafeZone({
        actor = f.actor, operationId = environment .. "-safe-on",
    }).code == "safeZoneEnabled")
    local cleared = f.instance.public.clearSafeZone({
        actor = f.actor, manual = true, operationId = environment .. "-clear",
    })
    assert(cleared.ok and cleared.data.removed == 2 and f.threats == 0, "safe-zone clear failed")
    assert(f.balance == 3772 and f.data.stats.spentPoints == 1228,
        "home costs changed")
    return table.concat({ f.current.x, f.data.homeSystem.safeZone.level, cleared.data.removed, f.balance }, "|")
end

assert(runHomeSuccess("sp") == runHomeSuccess("mp"), "SP/MP home behavior diverged")

do
    local f = homeFixture("home-invalid")
    f.data.homeSystem.home = { x = 999, y = 1, z = 0 }
    local result = f.instance.public.teleportHome({ actor = f.actor, operationId = "home-invalid-target" })
    assert(not result.ok and result.code == "targetInvalid" and f.balance == 5000,
        "invalid home position was charged or accepted")
end

do
    local f = homeFixture("home-rollback")
    assert(f.instance.public.setHome({ actor = f.actor, operationId = "home-r-set" }).ok)
    f.current = { x = 30, y = 40, z = 0 }
    local beforeBalance = f.balance
    f.failSave = true
    local result = f.instance.public.teleportHome({ actor = f.actor, operationId = "home-r-travel" })
    assert(not result.ok and result.code == "stateSaveFailed", "home save failure code was lost")
    assert(f.current.x == 30 and f.balance == beforeBalance and f.data.homeSystem.returnPoint == nil,
        "teleport position/wallet/state rollback failed")
end

do
    local up = upgradeFixture("health-upgrade")
    local med = medicalFixture("health-medical")
    local home = homeFixture("health-home")
    med.notices.fail = true
    assert(med.instance.public.checkInfection({ actor = med.actor, operationId = "health-med" }).ok)
    assert(not med.instance:health().ok, "failing medical notification was not isolated in health")
    assert(up.instance:health().ok and home.instance:health().ok,
        "one module health failure contaminated independent modules")
end

print("Test-GodSystemV422012UpgradeMedicalHomeModuleRuntime passed")
