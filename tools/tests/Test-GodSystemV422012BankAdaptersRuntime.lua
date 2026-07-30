local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local nextItemId = 1000
local worldHours = 0
local spawnFailure = false
local spawnedZombies = 0
local sync = { added = 0, removed = 0 }

GameTime = {
    getInstance = function()
        return { getWorldAgeHours = function() return worldHours end }
    end,
}
function ZombRand(maximum)
    assert(maximum > 0)
    return 0
end
function addZombiesInOutfit(_, _, _, count)
    if spawnFailure then error("expected debt spawn failure") end
    spawnedZombies = spawnedZombies + count
end
function sendAddItemToContainer() sync.added = sync.added + 1 end
function sendRemoveItemFromContainer() sync.removed = sync.removed + 1 end
function triggerEvent() end

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(fullType)
    nextItemId = nextItemId + 1
    local value = { id = nextItemId, fullType = fullType }
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getInventory() return nil end
    return value
end

local function container()
    local value = { rows = {} }
    function value:getItems() return javaList(self.rows) end
    function value:AddItem(source)
        local added = type(source) == "string" and item(source) or source
        self.rows[#self.rows + 1] = added
        return added
    end
    function value:Remove(target)
        for index = 1, #self.rows do
            if self.rows[index] == target then
                table.remove(self.rows, index)
                return
            end
        end
    end
    function value:setDrawDirty() end
    return value
end

local function addCash(inventory, amount)
    local denominations = {
        { fullType = "GodSystem.SystemCoin100", value = 100 },
        { fullType = "GodSystem.SystemCoin10", value = 10 },
        { fullType = "GodSystem.SystemCoin1", value = 1 },
    }
    for index = 1, #denominations do
        local row = denominations[index]
        local count = math.floor(amount / row.value)
        for _ = 1, count do inventory:AddItem(row.fullType) end
        amount = amount - count * row.value
    end
    assert(amount == 0)
end

local function player(username, onlineId, cash)
    local inventory = container()
    addCash(inventory, cash)
    local value = {
        username = username,
        onlineId = onlineId,
        inventory = inventory,
        x = 100,
        y = 100,
        z = 0,
    }
    function value:getUsername() return self.username end
    function value:getOnlineID() return self.onlineId end
    function value:getInventory() return self.inventory end
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    return value
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, itemValue in pairs(value) do copy[clone(key, seen)] = clone(itemValue, seen) end
    return copy
end

local function equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local snapshot = {
    features = {
        EnableBank = true,
        EnableBankLoan = true,
        EnableBankInvestments = true,
    },
    bank = {
        loanZombieMinDistance = 20,
        loanZombieMaxDistance = 45,
    },
}

local function context(moduleId, state, binding, environment)
    return {
        moduleId = moduleId,
        environment = environment,
        configSnapshot = snapshot,
        state = { get = function() return state end },
        binding = binding or {},
    }
end

require "GodSystem/Core/Result"
require "GodSystem/Services/OperationLedger"
require "GodSystem/Services/Clock"
require "GodSystem/Services/Random"
require "GodSystem/Services/Operations"
require "GodSystem/Platform/WalletAccounts"
require "GodSystem/Platform/WalletFunds"
require "GodSystem/Features/Wallet/Module"
require "GodSystem/Features/Wallet/PublicPort"
require "GodSystem/Platform/Bank/Descriptors"
require "GodSystem/Features/Bank/Rules"
require "GodSystem/Features/Bank/Module"

local function environment(mode)
    local alice = player("alice-" .. mode, mode == "sp" and 1 or 2, 3000)
    local bob = player("bob-" .. mode, mode == "sp" and 3 or 4, 800)
    local aliceKey = alice.username
    local bobKey = bob.username
    local accountState = {}
    local bankStateRoot = {
        players = {
            [aliceKey] = {
                current = 1000,
                fixed = {},
                investments = {},
                nextId = 1,
                nextLoanId = 1,
            },
            [bobKey] = {
                current = 400,
                fixed = {},
                investments = {},
                nextId = 1,
                nextLoanId = 1,
            },
        },
    }
    local commitBinding = { failNext = false }
    commitBinding.commit = function()
        if commitBinding.failNext then
            commitBinding.failNext = false
            return false, "stateCommitFailed"
        end
        return true
    end
    local spent = { [aliceKey] = 0, [bobKey] = 0 }

    local clock = GodSystemClockService.create()
    local random = GodSystemRandomService.create()
    local operations = GodSystemOperationsService.create({}, context(
        "operations", {}, nil, mode))
    local accounts = GodSystemWalletAccountsPlatform.create({}, context(
        "wallet.accounts", accountState, nil, mode))
    local funds = GodSystemWalletFundsPlatform.create({
        ["wallet.accounts"] = accounts.public,
    }, context("wallet.funds", {}, nil, mode))
    local walletFeature = GodSystemWalletFeatureModule.create({
        ["wallet.funds"] = funds.public,
        operations = operations.public,
    }, context("feature.wallet", {}, nil, mode))
    local wallet = GodSystemWalletPublicPort.create({
        ["feature.wallet"] = walletFeature.public,
    }, context("wallet", {}, nil, mode))
    local bankState = GodSystemBankStatePlatform.create({
        ["wallet.accounts"] = accounts.public,
    }, context("bank.state", bankStateRoot, commitBinding, mode))
    local bankClock = GodSystemBankClockPlatform.create({
        clock = clock.public,
    }, context("bank.clock", {}, nil, mode))
    local bankRandom = GodSystemBankRandomPlatform.create({
        random = random.public,
    }, context("bank.random", {}, nil, mode))
    local bankFeatures = GodSystemBankFeaturesPlatform.create({}, context(
        "bank.features", {}, nil, mode))
    local bankAudit = GodSystemBankAuditPlatform.create({
        ["wallet.accounts"] = accounts.public,
    }, context("bank.audit", {}, {
        counterSource = function(actor, name)
            if name == "spentPoints" then return spent[accounts.public.key(actor)] or 0 end
        end,
    }, mode))
    local bankDebt = GodSystemBankDebtPlatform.create({
        ["bank.random"] = bankRandom.public,
    }, context("bank.debt", {}, nil, mode))
    local bank = GodSystemBankFeatureModule.create({
        wallet = wallet.public,
        ["bank.state"] = bankState.public,
        ["bank.clock"] = bankClock.public,
        ["bank.random"] = bankRandom.public,
        ["bank.features"] = bankFeatures.public,
        ["bank.audit"] = bankAudit.public,
        ["bank.debt"] = bankDebt.public,
        operations = operations.public,
    }, {
        moduleId = "feature.bank",
        environment = mode,
        healthActor = alice,
    })

    local instances = {
        clock, random, operations, accounts, funds, walletFeature, wallet,
        bankState, bankClock, bankRandom, bankFeatures, bankAudit, bankDebt, bank,
    }
    for index = 1, #instances do assert(instances[index]:start()) end
    assert(bankState.public.load(alice).current == 1000)
    assert(bankStateRoot.players[aliceKey].current == nil,
        "bank current migration left a second account truth")
    return {
        mode = mode,
        alice = alice,
        bob = bob,
        aliceKey = aliceKey,
        bobKey = bobKey,
        accounts = accounts.public,
        funds = funds.public,
        wallet = wallet.public,
        state = bankState.public,
        stateRoot = bankStateRoot,
        bank = bank,
        audit = bankAudit.public,
        debt = bankDebt,
        commit = commitBinding,
        spent = spent,
        instances = instances,
    }
end

local function execute(env, actor, action, operationId, values)
    local request = {
        actor = actor,
        action = action,
        operationId = operationId,
    }
    for key, value in pairs(values or {}) do request[key] = value end
    return env.bank.public.execute(request)
end

local function runCore(mode)
    worldHours = 0
    local env = environment(mode)
    local alice = env.alice
    local bob = env.bob

    assert(env.wallet.getBalance(alice, "current") == 1000,
        "wallet current did not use bank account truth")
    assert(env.wallet.getBalance(alice, "spendable") == 4000,
        "wallet spendable did not combine bank current and PZ cash")

    local deposit = execute(env, alice, "deposit", "same-operation", { amount = 200 })
    assert(deposit.ok and env.state.load(alice).current == 1200,
        "bank deposit failed")
    assert(env.wallet.getBalance(alice, "current") == 1200
        and env.wallet.getBalance(alice, "spendable") == 4000,
        "deposit did not update shared current immediately")
    local replay = execute(env, alice, "deposit", "same-operation", { amount = 200 })
    assert(replay == deposit and env.state.load(alice).current == 1200,
        "bank operation replay duplicated a deposit")

    local bobDeposit = execute(env, bob, "deposit", "same-operation", { amount = 100 })
    assert(bobDeposit.ok and env.state.load(bob).current == 500,
        "same operation ID was not isolated by player")
    assert(env.state.load(alice).current == 1200,
        "second player modified first player bank state")

    local beforeCash = env.wallet.getBalance(alice, "cash")
    local beforeCurrent = env.wallet.getBalance(alice, "current")
    env.commit.failNext = true
    local failed = execute(env, alice, "deposit", "rollback-deposit", { amount = 100 })
    assert(not failed.ok and env.wallet.getBalance(alice, "cash") == beforeCash,
        "failed state commit did not refund PZ cash")
    assert(env.wallet.getBalance(alice, "current") == beforeCurrent
        and env.state.load(alice).current == beforeCurrent,
        "failed state commit split wallet and bank current")

    local withdraw = execute(env, alice, "withdraw", "withdraw-1", { amount = 150 })
    assert(withdraw.ok and env.wallet.getBalance(alice, "current") == beforeCurrent - 150,
        "withdraw did not debit shared current")
    assert(env.wallet.getBalance(alice, "cash") == beforeCash + 150,
        "withdraw did not grant PZ currency")

    local bankValue = env.state.load(alice)
    bankValue.fixed = {
        {
            id = "mature",
            principal = 1000,
            startHour = 0,
            matureHour = 24,
            rate = 0.02,
            days = 1,
        },
    }
    assert(env.state.commit(alice, bankValue, { operationId = "fixture-fixed" }))
    worldHours = 24
    local mature = execute(env, alice, "withdrawFixed", "fixed-mature", {
        entryId = "mature",
    })
    assert(mature.ok and mature.data.payout == 1020,
        "published fixed-deposit interest changed")

    local investment = execute(env, alice, "investFromCurrent", "invest-1", {
        termId = "stable",
        amount = 100,
    })
    assert(investment.ok, "PZ bank adapter rejected investment")
    worldHours = 48
    local settlement = execute(env, alice, "syncInvestmentHours", "settle-1", {
        hours = 24,
    })
    assert(settlement.ok and settlement.data.settledCount == 1,
        "investment settlement did not use shared clock/random adapters")
    assert(env.state.load(alice).investments.stable.balance == 101,
        "published stable investment gain changed")

    return env
end

local sp = runCore("sp")
local spState = clone({
    alice = sp.state.load(sp.alice),
    bob = sp.state.load(sp.bob),
})
local spBalances = {
    aliceCash = sp.wallet.getBalance(sp.alice, "cash"),
    aliceCurrent = sp.wallet.getBalance(sp.alice, "current"),
    bobCash = sp.wallet.getBalance(sp.bob, "cash"),
    bobCurrent = sp.wallet.getBalance(sp.bob, "current"),
}
local mp = runCore("mp")
local mpState = {
    alice = mp.state.load(mp.alice),
    bob = mp.state.load(mp.bob),
}
local mpBalances = {
    aliceCash = mp.wallet.getBalance(mp.alice, "cash"),
    aliceCurrent = mp.wallet.getBalance(mp.alice, "current"),
    bobCash = mp.wallet.getBalance(mp.bob, "cash"),
    bobCurrent = mp.wallet.getBalance(mp.bob, "current"),
}
assert(equal(spState, mpState) and equal(spBalances, mpBalances),
    "SP and MP adapters did not reuse the same bank rules")

worldHours = 0
local debtEnv = environment("debt")
local borrowed = execute(debtEnv, debtEnv.alice, "borrowLoan", "loan-1", {
    termId = "single",
    amount = 1000,
})
assert(borrowed.ok and debtEnv.state.load(debtEnv.alice).loan.totalInterest == 50,
    "published loan interest changed")
worldHours = 312
spawnFailure = true
local bankruptcy = execute(debtEnv, debtEnv.alice, "updateLoan", "loan-overdue")
spawnFailure = false
assert(bankruptcy.ok and bankruptcy.code == "BankLoanBankruptcy",
    "debt spawn failure escaped the bank module boundary")
assert(debtEnv.state.load(debtEnv.alice).loan == nil
    and debtEnv.wallet.getBalance(debtEnv.alice, "current") == 0,
    "debt spawn failure rolled back committed bankruptcy state")
assert(debtEnv.bank:health().code == "debtSpawnFailed",
    "debt spawn failure was not observable in module health")

assert(sync.added > 0 and sync.removed > 0,
    "PZ inventory synchronization was not exercised")
assert(spawnedZombies == 0, "failed debt fixture unexpectedly spawned zombies")

print("Test-GodSystemV422012BankAdaptersRuntime passed")
