local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Features/System/Module"

local root = {}
local balances = {}
local operationResults = {}
local notifications = {}
local accounts = {
    key = function(actor) return actor.key end,
}
local wallet = {
    grant = function(actor, amount)
        balances[actor.key] = (balances[actor.key] or 0) + amount
        return true, { actorKey = actor.key, amount = amount }
    end,
    refund = function(actor, receipt)
        balances[actor.key] = balances[actor.key] - receipt.amount
        return true
    end,
}
local operations = {
    begin = function(_, operationId, fingerprint)
        local row = operationResults[operationId]
        if row then return "replay", row end
        operationResults[operationId] = { fingerprint = fingerprint }
        return "new"
    end,
    finish = function(_, operationId, value)
        operationResults[operationId] = value
        return value
    end,
    markUnknown = function() return true end,
}
local instance = GodSystemSystemFeatureModule.create({
    ["wallet.accounts"] = accounts,
    wallet = wallet,
    operations = operations,
    notifications = {
        publish = function(value) notifications[#notifications + 1] = value return true end,
    },
}, {
    version = "42.20.1.2",
    configSnapshot = { StartingPoints = 60, HistoryLimit = 20 },
    state = { get = function() return root end },
})
assert(instance:start() == true, "system module did not start")

local alice, bob = { key = "alice" }, { key = "bob" }
local initialized = instance.public.ensureInitialized({
    actor = alice,
    operationId = "alice-init",
})
assert(initialized.ok and initialized.data.granted == 60 and balances.alice == 60,
    "initial currency drifted")
local replay = instance.public.ensureInitialized({
    actor = alice,
    operationId = "alice-init-repeat",
})
assert(replay.ok and replay.code == "alreadyInitialized" and balances.alice == 60,
    "repeat initialization duplicated currency")

root.players.bob = {
    started = false,
    currencyInitialized = false,
    pendingCurrencyGrant = 35,
    history = {},
    ui = {},
}
local migrated = instance.public.ensureInitialized({
    actor = bob,
    operationId = "bob-init",
})
assert(migrated.ok and migrated.data.granted == 35 and balances.bob == 35,
    "migrated pending grant was not preserved")

local changed = instance.public.setPreference({
    actor = alice,
    key = "window.mode",
    value = "tasks",
})
assert(changed.ok, "preference update failed")
local snapshot = instance.public.snapshot({ actor = alice })
assert(snapshot.ok and snapshot.data.ui["window.mode"] == "tasks",
    "preference snapshot failed")
assert(#snapshot.data.history == 1 and snapshot.data.history[1].amount == 60,
    "initialization history missing")
snapshot.data.ui["window.mode"] = "mutated"
assert(instance.public.snapshot({ actor = alice }).data.ui["window.mode"] == "tasks",
    "snapshot leaked mutable state")
assert(instance:health().ok and #notifications >= 5, "system health or notification drifted")

print("Test-GodSystemV422012SystemModuleRuntime passed")
