local luaRoot = assert(arg[1], "lua root argument required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/shared/?/init.lua;" .. package.path

local UpgradesConfig = require "GodSystem/Platform/Progression/UpgradesConfig"
local UpgradesState = require "GodSystem/Platform/Progression/UpgradesState"
local UpgradesAbilities = require "GodSystem/Platform/Progression/UpgradesAbilities"
local UpgradesTasks = require "GodSystem/Platform/Progression/UpgradesTasks"
local UpgradesWallet = require "GodSystem/Platform/Progression/UpgradesWallet"
local MedicalConfig = require "GodSystem/Platform/Progression/MedicalConfig"
local MedicalState = require "GodSystem/Platform/Progression/MedicalState"
local MedicalBody = require "GodSystem/Platform/Progression/MedicalBody"
local MedicalWallet = require "GodSystem/Platform/Progression/MedicalWallet"
local HomeConfig = require "GodSystem/Platform/Progression/HomeConfig"
local HomeState = require "GodSystem/Platform/Progression/HomeState"
local HomePosition = require "GodSystem/Platform/Progression/HomePosition"
local HomeWorld = require "GodSystem/Platform/Progression/HomeWorld"
local HomeWallet = require "GodSystem/Platform/Progression/HomeWallet"
local UpgradesFeature = require "GodSystem/Features/Upgrades/Module"
local MedicalFeature = require "GodSystem/Features/Medical/Module"
local HomeFeature = require "GodSystem/Features/Home/Module"

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual), 2)
    end
end

local function start(descriptor, dependencies, context)
    local instance = descriptor.create(dependencies or {}, context or {})
    expect(instance:start() == true, descriptor.id .. " did not start")
    return instance
end

local function scope()
    local root = {}
    return {
        root = root,
        get = function() return root end,
    }
end

local function list(values)
    return {
        values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
    }
end

local actor = {
    id = "alice",
    username = "alice",
    delta = 0,
    base = 14,
    maximum = 14,
    x = 10,
    y = 20,
    z = 0,
    health = 1,
    modData = {},
}
function actor:getUsername() return self.username end
function actor:getMaxWeightDelta() return self.delta end
function actor:setMaxWeightDelta(value) self.delta = value end
function actor:getMaxWeightBase() return self.base end
function actor:getMaxWeight() return self.maximum end
function actor:setMaxWeight(value) self.maximum = value end
function actor:getModData() return self.modData end
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:setX(value) self.x = value end
function actor:setY(value) self.y = value end
function actor:setZ(value) self.z = value end
function actor:setLastX(value) self.lastX = value end
function actor:setLastY(value) self.lastY = value end
function actor:setLastZ(value) self.lastZ = value end
function actor:getHealth() return self.health end
function actor:setHealth(value) self.health = value end
function actor:getInventory() error("progression adapters must not scan the player inventory") end

local function stateChecks()
    local upgradeScope = scope()
    local medicalScope = scope()
    local homeScope = scope()
    local upgrades = start(UpgradesState, {}, { state = upgradeScope })
    local medical = start(MedicalState, {}, { state = medicalScope })
    local home = start(HomeState, {}, { state = homeScope })
    local value = upgrades.public.load(actor)
    equal(value.upgrades.maxActiveTasks, 3, "upgrade defaults")
    value.upgrades.carryCapacityLevel = 4
    expect(upgrades.public.save(actor, value), "upgrade state save")
    equal(upgrades.public.load(actor).upgrades.carryCapacityLevel, 4, "upgrade state persistence")
    medical.public.save(actor, { stats = { spentPoints = 7 } })
    equal(medical.public.load(actor).stats.spentPoints, 7, "medical state persistence")
    local homeValue = home.public.load(actor)
    expect(type(homeValue.homeSystem.safeZone) == "table", "home state normalization")
    expect(upgradeScope.root.players ~= medicalScope.root.players, "feature states must be isolated")
end

local function configChecks()
    local upgrades = start(UpgradesConfig)
    local carry = upgrades.public.quote(actor, "carryCapacity", 0)
    equal(carry.cost, 2000, "carry quote")
    equal(upgrades.public.quote(actor, "activeTasks", 3).cost, 100, "active quote")
    equal(upgrades.public.quote(actor, "dailyTasks", 5).cost, 50, "daily quote")
    equal(upgrades.public.quote(actor, "terminalCapacity", 1).cost, 60, "capacity quote")
    equal(upgrades.public.quote(actor, "terminalReduction", 1).cost, 100, "reduction quote")
    equal(upgrades.public.quote(actor, "terminalRelief", 1).cost, 2000, "relief quote")
    local overflow = start(UpgradesConfig, {}, {
        binding = { config = { CarryCapacityBaseCost = math.huge } },
    })
    expect(overflow.public.quote(actor, "carryCapacity", 0) == nil, "non-finite quote rejected")

    local medical = start(MedicalConfig)
    equal(medical.public.cost("checkInfection"), 50, "medical check quote")
    equal(medical.public.cost("healInjuries"), 5000, "medical heal quote")
    equal(medical.public.cost("cureInfection"), 2000, "medical cure quote")

    local home = start(HomeConfig)
    expect(home.public.isEnabled(), "home enabled")
    equal(home.public.cost("setHome"), 100, "home set quote")
    equal(home.public.cost("teleportHome"), 10, "home travel quote")
    equal(home.public.maxTempSlots(), 3, "home slots")
    equal(home.public.nextSafeLevel(0).radius, 12, "home safe level")
    equal(home.public.cost("clearSafeZone", actor,
        { homeSystem = { safeZone = { level = 2 } } }), 12, "home clear quote")
end

local function walletChecks()
    local funds = { balance = 10000, receipts = {}, restored = 0 }
    function funds.debit(_, amount)
        if funds.balance < amount then return false, "balanceInsufficient" end
        funds.balance = funds.balance - amount
        local receipt = { amount = amount }
        funds.receipts[#funds.receipts + 1] = receipt
        return true, receipt
    end
    function funds.restore(_, receipt)
        funds.balance = funds.balance + receipt.amount
        funds.restored = funds.restored + 1
        return true
    end
    for _, descriptor in ipairs({ UpgradesWallet, MedicalWallet, HomeWallet }) do
        local wallet = start(descriptor, { ["wallet.funds"] = funds })
        local paid, receipt = wallet.public.charge(actor, 10)
        expect(paid and receipt, descriptor.id .. " charge")
        expect(wallet.public.refund(actor, receipt), descriptor.id .. " refund")
    end
    equal(funds.balance, 10000, "wallet round trip")
    equal(funds.restored, 3, "wallet refunds")
end

local function reliefItem()
    local item = {
        fullType = "GodSystem.SystemTerminalRelief",
        id = 900,
        hung = -0.01,
        actual = 1,
        favorite = false,
        unwanted = {},
        modData = {},
    }
    function item:getFullType() return self.fullType end
    function item:getID() return self.id end
    function item:getHungChange() return self.hung end
    function item:setHungChange(value) self.hung = value self.actual = -value * 100 end
    function item:getActualWeight() return self.actual end
    function item:isFavorite() return self.favorite end
    function item:setFavorite(value) self.favorite = value end
    function item:isUnwanted(player) return self.unwanted[player] == true end
    function item:setUnwanted(player, value) self.unwanted[player] = value end
    function item:getModData() return self.modData end
    return item
end

local function terminalFixture()
    local inventory = { capacity = 10, reduction = 50, items = {} }
    function inventory:getItems() return list(self.items) end
    function inventory:getCapacity() return self.capacity end
    function inventory:setCapacity(value) self.capacity = value end
    function inventory:getWeightReduction() return self.reduction end
    function inventory:setWeightReduction(value) self.reduction = value end
    function inventory:AddItem(value)
        local item = type(value) == "table" and value or reliefItem()
        self.items[#self.items + 1] = item
        return item
    end
    function inventory:Remove(wanted)
        for index = #self.items, 1, -1 do
            if self.items[index] == wanted then table.remove(self.items, index) return end
        end
    end
    local terminal = { id = 42, capacity = 10, reduction = 50, inventory = inventory, modData = {} }
    function terminal:getID() return self.id end
    function terminal:getInventory() return self.inventory end
    function terminal:getCapacity() return self.capacity end
    function terminal:setCapacity(value) self.capacity = value end
    function terminal:getWeightReduction() return self.reduction end
    function terminal:setWeightReduction(value) self.reduction = value end
    function terminal:getModData() return self.modData end
    return terminal, inventory
end

local function abilityChecks()
    local abilities = start(UpgradesAbilities)
    local carry = abilities.public.snapshot(actor, "carryCapacity", 0, {}, {})
    local applied, report = abilities.public.apply(actor, "carryCapacity", 1, {}, {})
    expect(applied, "carry apply")
    equal(report.bonus, 2, "carry bonus")
    equal(actor.maximum, 16, "carry final")
    expect(abilities.public.restore(actor, "carryCapacity", carry, {}), "carry restore")
    equal(actor.maximum, 14, "carry restored final")
    equal(actor.delta, 0, "carry restored delta")

    local terminal, inventory = terminalFixture()
    local request = { terminal = terminal }
    local beforeCapacity = abilities.public.snapshot(actor, "terminalCapacity", 1, {}, request)
    expect(abilities.public.apply(actor, "terminalCapacity", 2, {}, request), "capacity apply")
    equal(terminal.capacity, 15, "outer capacity")
    equal(inventory.capacity, 15, "inner capacity")
    expect(abilities.public.restore(actor, "terminalCapacity", beforeCapacity, request), "capacity restore")
    equal(inventory.capacity, 10, "capacity restored")

    local beforeReduction = abilities.public.snapshot(actor, "terminalReduction", 1, {}, request)
    expect(abilities.public.apply(actor, "terminalReduction", 2, {}, request), "reduction apply")
    equal(terminal.reduction, 55, "outer reduction")
    equal(inventory.reduction, 55, "inner reduction")
    expect(abilities.public.restore(actor, "terminalReduction", beforeReduction, request), "reduction restore")

    local beforeRelief = abilities.public.snapshot(actor, "terminalRelief", 1, {}, request)
    expect(abilities.public.apply(actor, "terminalRelief", 2, {}, request), "relief apply")
    equal(#inventory.items, 1, "one relief item")
    equal(inventory.items[1].actual, -10, "relief weight")
    expect(abilities.public.restore(actor, "terminalRelief", beforeRelief, request), "relief restore")
    equal(#inventory.items, 0, "relief rollback removes created item")
    expect(abilities.public.snapshot(actor, "terminalCapacity", 1, {}, {}) == nil,
        "terminal must be supplied explicitly")
end

local function taskChecks()
    local sequence = 0
    local tasks = start(UpgradesTasks, {}, {
        binding = {
            createOpenTask = function()
                sequence = sequence + 1
                return { id = "task-" .. tostring(sequence), status = "open" }
            end,
        },
    })
    local data = { tasks = {} }
    local added, receipt = tasks.public.addOpen(actor, data, {})
    expect(added and receipt, "task add")
    equal(#data.tasks, 1, "task appended")
    expect(tasks.public.rollback(actor, receipt, {}), "task rollback")
    equal(#data.tasks, 0, "task removed")
end

local part = {
    health = 50, bleeding = 3, deepWound = 0, scratch = 1, cut = 0, bite = 0,
    burn = 0, fracture = 0, pain = 2, woundInfection = 0,
    bullet = false, glass = false, stitched = false, splint = false,
    bandaged = false, infectedWound = false, fakeInfected = false,
}
function part:getHealth() return self.health end
function part:setHealth(value) self.health = value end
part.SetHealth = part.setHealth
function part:getBleedingTime() return self.bleeding end
function part:setBleedingTime(value) self.bleeding = value end
function part:getDeepWoundTime() return self.deepWound end
function part:setDeepWoundTime(value) self.deepWound = value end
function part:getScratchTime() return self.scratch end
function part:setScratchTime(value) self.scratch = value end
function part:getCutTime() return self.cut end
function part:setCutTime(value) self.cut = value end
function part:getBiteTime() return self.bite end
function part:setBiteTime(value) self.bite = value end
function part:getBurnTime() return self.burn end
function part:setBurnTime(value) self.burn = value end
function part:getFractureTime() return self.fracture end
function part:setFractureTime(value) self.fracture = value end
function part:getAdditionalPain() return self.pain end
function part:setAdditionalPain(value) self.pain = value end
function part:getWoundInfectionLevel() return self.woundInfection end
function part:setWoundInfectionLevel(value) self.woundInfection = value end
function part:haveBullet() return self.bullet end
function part:setHaveBullet(value) self.bullet = value end
function part:haveGlass() return self.glass end
function part:setHaveGlass(value) self.glass = value end
function part:stitched() return self.stitched end
function part:setStitched(value) self.stitched = value end
function part:isSplint() return self.splint end
function part:setSplint(value) self.splint = value end
function part:bandaged() return self.bandaged end
function part:setBandaged(value) self.bandaged = value end
function part:isInfectedWound() return self.infectedWound end
function part:setInfectedWound(value) self.infectedWound = value end
function part:isFakeInfected() return self.fakeInfected end
function part:SetFakeInfected(value) self.fakeInfected = value end

local body = {
    overall = 80,
    infected = true,
    fakeInfected = false,
    infectionTime = 12,
    mortality = 72,
    infectionLevel = 25,
    parts = { part },
}
function body:getBodyParts() return list(self.parts) end
function body:getOverallBodyHealth() return self.overall end
function body:setOverallBodyHealth(value) self.overall = value end
function body:IsInfected() return self.infected end
function body:setInfected(value) self.infected = value end
function body:IsFakeInfected() return self.fakeInfected end
function body:setIsFakeInfected(value) self.fakeInfected = value end
function body:getInfectionTime() return self.infectionTime end
function body:setInfectionTime(value) self.infectionTime = value end
function body:getInfectionMortalityDuration() return self.mortality end
function body:setInfectionMortalityDuration(value) self.mortality = value end
function body:getInfectionLevel() return self.infectionLevel end
function body:setInfectionLevel(value) self.infectionLevel = value end
function actor:getBodyDamage() return body end

CharacterStat = { ZOMBIE_INFECTION = "zombie" }
actor.stats = { zombie = 1 }
function actor.stats:get(key) return self[key] end
function actor.stats:set(key, value) self[key] = value end
function actor:getStats() return self.stats end

local function medicalChecks()
    local adapter = start(MedicalBody)
    local status = adapter.public.inspect(actor, {})
    expect(status.infected and status.injured, "medical inspection")
    local snapshot = adapter.public.snapshot(actor, "healInjuries", {})
    local healed = adapter.public.apply(actor, "healInjuries", snapshot, {})
    expect(healed, "medical heal")
    equal(part.health, 100, "part healed")
    expect(body.infected, "healing preserves infection")
    expect(adapter.public.restore(actor, snapshot, {}), "medical rollback")
    equal(part.health, 50, "part health restored")
    local cureSnapshot = adapter.public.snapshot(actor, "cureInfection", {})
    expect(adapter.public.apply(actor, "cureInfection", cureSnapshot, {}), "medical cure")
    expect(not body.infected, "infection cleared")
    equal(actor.stats.zombie, 0, "infection stat cleared")
    expect(adapter.public.restore(actor, cureSnapshot, {}), "cure rollback")
    expect(body.infected, "infection restored")
end

local safeSquare = {}
function safeSquare:isSolid() return false end
function safeSquare:isSolidTrans() return false end
function safeSquare:TreatAsSolidFloor() return true end
local solidSquare = {}
function solidSquare:isSolid() return true end

local zombies = {}
local cell = {}
function cell:getGridSquare(x)
    return x >= 900 and solidSquare or safeSquare
end
function cell:getZombieList() return list(zombies) end
function getCell() return cell end

local function zombie(x, y)
    local value = { x = x, y = y, z = 0, dead = false, removed = false }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:isDead() return self.dead end
    function value:removeFromWorld() self.removed = true end
    function value:removeFromSquare() self.removed = true end
    return value
end

local function homeChecks()
    local positions = start(HomePosition)
    local current = positions.public.current(actor)
    equal(current.x, 10, "current position")
    expect(positions.public.validate(actor, current, {}), "current position valid")
    expect(positions.public.validate(actor, { x = 999, y = 999, z = 0 }, {}) == nil,
        "unsafe position rejected")
    local moved, receipt = positions.public.teleport(actor, { x = 30, y = 40, z = 0 }, {})
    expect(moved and receipt, "native teleport")
    equal(actor.x, 30, "teleport x")
    expect(positions.public.restore(actor, receipt, {}), "teleport rollback")
    equal(actor.x, 10, "position restored")

    zombies = { zombie(11, 20), zombie(12, 20), zombie(100, 100) }
    local world = start(HomeWorld)
    local plan = world.public.planClear(actor, { x = 10, y = 20, z = 0 }, 5, {})
    equal(plan.count, 2, "safe zone plan")
    local executed, removed = world.public.executeClear(actor, plan, {})
    expect(executed, "safe zone execution")
    equal(removed, 2, "safe zone removed count")
    expect(zombies[1].removed and zombies[2].removed and not zombies[3].removed,
        "only planned zombies removed")

    local changed = zombie(11, 20)
    zombies = { changed, zombie(12, 20) }
    local changedPlan = world.public.planClear(actor, { x = 10, y = 20, z = 0 }, 5, {})
    changed.dead = true
    expect(world.public.executeClear(actor, changedPlan, {}) == false, "changed plan rejected")
    expect(not zombies[2].removed, "prevalidation prevents partial removal")

    local badActor = {
        x = 1, y = 1, z = 0,
        getX = actor.getX, getY = actor.getY, getZ = actor.getZ,
        setX = function() error("write failed") end,
        setY = actor.setY, setZ = actor.setZ,
    }
    expect(positions.public.teleport(badActor, { x = 2, y = 2, z = 0 }, {}) == false,
        "failed native teleport reported")
    expect(positions:health().ok == false, "position health records its own failure")
    expect(world:health().ok == true, "world health remains isolated")
end

local function integrationChecks()
    actor.delta, actor.maximum = 0, 14
    actor.modData = {}
    actor.x, actor.y, actor.z = 10, 20, 0
    body.infected, body.infectionTime, body.infectionLevel = true, 12, 25
    actor.stats.zombie = 1

    local funds = { balance = 10000 }
    function funds.debit(_, amount)
        if funds.balance < amount then return false, "balanceInsufficient" end
        funds.balance = funds.balance - amount
        return true, { amount = amount }
    end
    function funds.restore(_, receipt)
        funds.balance = funds.balance + receipt.amount
        return true
    end
    local ledger = {}
    local operations = {}
    function operations.begin(moduleId, operationId, fingerprint)
        local key = moduleId .. "|" .. operationId
        local row = ledger[key]
        if row then
            if row.fingerprint ~= fingerprint then return "mismatch", "operationMismatch" end
            return row.result and "replay" or "pending", row.result
        end
        ledger[key] = { fingerprint = fingerprint }
        return "new"
    end
    function operations.finish(moduleId, operationId, result)
        ledger[moduleId .. "|" .. operationId].result = result
        return true
    end
    local notifications = { publish = function() return true end }
    local clock = { nowHours = function() return 100 end }

    local upgradeState = start(UpgradesState, {}, { state = scope() }).public
    local upgradeWallet = start(UpgradesWallet, { ["wallet.funds"] = funds }).public
    local upgradeTasks = start(UpgradesTasks, {}, {
        binding = {
            createOpenTask = function() return { id = "integration-task", status = "open" } end,
        },
    }).public
    local upgrades = start(UpgradesFeature, {
        ["upgrades.config"] = start(UpgradesConfig).public,
        ["upgrades.state"] = upgradeState,
        ["upgrades.abilities"] = start(UpgradesAbilities).public,
        ["upgrades.tasks"] = upgradeTasks,
        ["upgrades.wallet"] = upgradeWallet,
        operations = operations,
        notifications = notifications,
    })
    local carry = upgrades.public.upgrade({
        actor = actor, upgradeType = "carryCapacity", operationId = "integration-carry",
    })
    expect(carry.ok, "feature plus carry adapter integration")
    equal(actor.maximum, 16, "integrated carry result")
    local daily = upgrades.public.upgrade({
        actor = actor, upgradeType = "dailyTasks", operationId = "integration-daily",
    })
    expect(daily.ok, "feature plus task adapter integration")
    equal(#upgradeState.load(actor).tasks, 1, "integrated daily task")
    local replayBalance = funds.balance
    expect(upgrades.public.upgrade({
        actor = actor, upgradeType = "dailyTasks", operationId = "integration-daily",
    }).ok, "integrated idempotent replay")
    equal(funds.balance, replayBalance, "replay does not charge")

    local medical = start(MedicalFeature, {
        ["medical.config"] = start(MedicalConfig).public,
        ["medical.state"] = start(MedicalState, {}, { state = scope() }).public,
        ["medical.body"] = start(MedicalBody).public,
        ["medical.wallet"] = start(MedicalWallet, { ["wallet.funds"] = funds }).public,
        clock = clock,
        operations = operations,
        notifications = notifications,
    })
    expect(medical.public.cureInfection({
        actor = actor, operationId = "integration-cure",
    }).ok, "feature plus body adapter integration")
    expect(not body.infected, "integrated cure result")

    local home = start(HomeFeature, {
        ["home.config"] = start(HomeConfig).public,
        ["home.state"] = start(HomeState, {}, { state = scope() }).public,
        ["home.position"] = start(HomePosition).public,
        ["home.world"] = start(HomeWorld).public,
        ["home.wallet"] = start(HomeWallet, { ["wallet.funds"] = funds }).public,
        clock = clock,
        operations = operations,
        notifications = notifications,
    })
    expect(home.public.setHome({
        actor = actor, operationId = "integration-home",
    }).ok, "feature plus home adapter integration")
    equal(funds.balance, 5850, "integrated transaction total")
end

stateChecks()
configChecks()
walletChecks()
abilityChecks()
taskChecks()
medicalChecks()
homeChecks()
integrationChecks()

print("Test-GodSystemV422012ProgressionPlatformRuntime passed")
