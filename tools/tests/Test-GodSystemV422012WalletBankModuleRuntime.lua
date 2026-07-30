local luaRoot = assert(arg and arg[1], "Lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/init.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Services/OperationLedger"
require "GodSystem/Features/Wallet/Module"
require "GodSystem/Features/Bank/Rules"
require "GodSystem/Features/Bank/Module"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function fundsPort(initial)
    local port = {
        balances = clone(initial or {}),
        nextReceipt = 1,
        debitReceipts = {},
        failCredit = false,
        failDebit = false,
        failRestore = false,
    }

    local function account(self, actor)
        local key = tostring(actor)
        self.balances[key] = self.balances[key] or { cash = 0, vault = 0 }
        return self.balances[key]
    end

    function port:balance(actor, scope)
        local row = account(self, actor)
        if scope == "spendable" then return row.cash + (row.current or 0) end
        return row[scope] or 0
    end

    function port:debit(actor, amount, scope)
        if self.failDebit then return false, "debitFailed" end
        local row = account(self, actor)
        local available = scope == "spendable"
            and (row.cash + (row.current or 0))
            or (row[scope] or 0)
        if available < amount then return false, "balanceInsufficient" end
        local sources = {}
        if scope == "spendable" then
            local fromCurrent = math.min(row.current or 0, amount)
            row.current = (row.current or 0) - fromCurrent
            local fromCash = amount - fromCurrent
            row.cash = row.cash - fromCash
            sources.current = fromCurrent
            sources.cash = fromCash
        else
            row[scope] = (row[scope] or 0) - amount
            sources[scope] = amount
        end
        local receipt = {
            id = "D" .. tostring(self.nextReceipt),
            actor = tostring(actor),
            amount = amount,
            scope = scope,
            sources = sources,
            restored = false,
        }
        self.nextReceipt = self.nextReceipt + 1
        self.debitReceipts[receipt.id] = receipt
        return true, receipt
    end

    function port:credit(actor, amount, scope)
        if self.failCredit then return false, "creditFailed" end
        local row = account(self, actor)
        row[scope] = (row[scope] or 0) + amount
        local receipt = {
            id = "C" .. tostring(self.nextReceipt),
            actor = tostring(actor),
            amount = amount,
            scope = scope,
        }
        self.nextReceipt = self.nextReceipt + 1
        return true, receipt
    end

    function port:restore(actor, receipt)
        if self.failRestore then return false, "restoreFailed" end
        if type(receipt) ~= "table"
            or tostring(actor) ~= receipt.actor
            or receipt.restored == true
        then
            return false, "receiptInvalid"
        end
        local row = account(self, actor)
        for source, amount in pairs(receipt.sources or {}) do
            row[source] = (row[source] or 0) + amount
        end
        receipt.restored = true
        return true
    end

    function port:health() return true, { balances = true } end
    return port
end

local function ledger()
    local buckets = {}
    local function scoped(moduleId, request)
        local actor = type(request) == "table" and request.actor or "local"
        local key = tostring(moduleId or "default") .. "@" .. tostring(actor or "local")
        if not buckets[key] then
            buckets[key] = GodSystemOperationLedger.new(
                { results = {}, order = {} },
                { maxEntries = 500 }
            )
        end
        return buckets[key]
    end
    return {
        begin = function(moduleId, operationId, fingerprint, request)
            local row, replay = scoped(moduleId, request):begin(operationId, fingerprint)
            if not row then return false, replay end
            if replay then return "replay", row.result or replay end
            return "new", row
        end,
        finish = function(moduleId, operationId, result, request)
            return scoped(moduleId, request):finish(operationId, result)
        end,
        markUnknown = function(moduleId, operationId, code, request)
            return scoped(moduleId, request):markUnknown(operationId, code)
        end,
    }
end

local function walletEnvironment(initial, sharedLedger)
    local funds = fundsPort(initial)
    local module = GodSystemWalletFeatureModule.create({
        ["wallet.funds"] = funds,
        operations = sharedLedger or ledger(),
    })
    return module, funds
end

do
    local wallet, funds = walletEnvironment({
        alice = { cash = 1000, current = 300, vault = 0 },
    })
    local stopped = wallet.public.execute({
        action = "charge", actor = "alice", amount = 1, operationId = "wallet-stopped",
    })
    expect(stopped.ok == false and stopped.code == "moduleStopped", "wallet stopped guard")
    wallet:start()

    expect(wallet.public.getBalance("alice", "spendable") == 1300, "wallet aggregate balance")

    local charged, receipt, _, chargeResult = wallet.public.charge("alice", 400, {
        operationId = "wallet-charge-1",
        scope = "spendable",
    })
    expect(charged == true and receipt.kind == "charge", "wallet charge receipt")
    expect(chargeResult.moduleId == "feature.wallet", "wallet result envelope")
    expect(funds.balances.alice.current == 0 and funds.balances.alice.cash == 900,
        "wallet keeps current-first spend rule in funds port")

    local replayed, replayReceipt = wallet.public.charge("alice", 400, {
        operationId = "wallet-charge-1",
        scope = "spendable",
    })
    expect(replayed == true and replayReceipt.sourceReceipt.id == receipt.sourceReceipt.id,
        "wallet duplicate operation replay")
    expect(funds.balances.alice.cash == 900, "wallet replay must not debit twice")

    local insufficient, code = wallet.public.charge("alice", 5000, {
        operationId = "wallet-charge-insufficient",
        scope = "spendable",
    })
    expect(insufficient == false and code == "balanceInsufficient", "wallet insufficient balance")
    expect(funds.balances.alice.cash == 900, "insufficient charge leaves balance")

    local refunded = wallet.public.refund("alice", receipt, {
        operationId = "wallet-refund-1",
    })
    expect(refunded == true, "wallet refund")
    expect(funds.balances.alice.current == 300 and funds.balances.alice.cash == 1000,
        "wallet refund restores exact sources")
    local replayRefund = wallet.public.refund("alice", receipt, {
        operationId = "wallet-refund-1",
    })
    expect(replayRefund == true, "wallet refund replay")
    expect(funds.balances.alice.cash == 1000, "refund replay must not duplicate")

    local granted = wallet.public.grant("alice", 50, {
        operationId = "wallet-grant-1",
        scope = "cash",
    })
    expect(granted == true and funds.balances.alice.cash == 1050, "wallet grant")
    wallet.public.grant("alice", 50, {
        operationId = "wallet-grant-1",
        scope = "cash",
    })
    expect(funds.balances.alice.cash == 1050, "grant replay must not duplicate")

    local transferred, transferReceipt = wallet.public.transfer("alice", 100, {
        operationId = "wallet-transfer-1",
        fromScope = "cash",
        toScope = "vault",
    })
    expect(transferred == true and transferReceipt.kind == "transfer", "wallet transfer receipt")
    expect(funds.balances.alice.cash == 950 and funds.balances.alice.vault == 100,
        "wallet transfer balances")

    funds.failCredit = true
    local transferFailed = wallet.public.transfer("alice", 200, {
        operationId = "wallet-transfer-rollback",
        fromScope = "cash",
        toScope = "vault",
    })
    expect(transferFailed == false, "wallet transfer failure")
    expect(funds.balances.alice.cash == 950 and funds.balances.alice.vault == 100,
        "wallet transfer rollback")
    funds.failCredit = false

    local nan = 0 / 0
    local invalid = wallet.public.charge("alice", nan, {
        operationId = "wallet-invalid",
    })
    expect(invalid == false, "wallet rejects NaN")

    local beforeHealth = clone(funds.balances)
    local health = wallet:health()
    expect(health.ok == true and health.code == "healthy", "wallet health")
    expect(equal(beforeHealth, funds.balances), "wallet health is read-only")
end

local function statePort(initial)
    local port = {
        rows = clone(initial or {}),
        failNextCommit = false,
        commits = 0,
    }
    function port:load(actor)
        return self.rows[tostring(actor)] or {}
    end
    function port:commit(actor, value)
        if self.failNextCommit then
            self.failNextCommit = false
            return false, "stateCommitFailed"
        end
        self.rows[tostring(actor)] = clone(value)
        self.commits = self.commits + 1
        return true
    end
    return port
end

local function auditPort()
    local port = { counters = {}, events = {} }
    local function actorCounters(self, actor)
        local key = tostring(actor)
        self.counters[key] = self.counters[key] or {}
        return self.counters[key]
    end
    function port:increment(actor, name, amount)
        local row = actorCounters(self, actor)
        row[name] = (row[name] or 0) + (tonumber(amount) or 0)
        return true
    end
    function port:record(actor, code, data)
        self.events[#self.events + 1] = {
            actor = tostring(actor), code = code, data = clone(data),
        }
        return true
    end
    function port:counter(actor, name)
        return actorCounters(self, actor)[name] or 0
    end
    return port
end

local function bankEnvironment(mode, options)
    options = options or {}
    local sharedLedger = ledger()
    local walletModule, funds = walletEnvironment(options.funds or {
        alice = { cash = 3000, vault = 0 },
    }, sharedLedger)
    walletModule:start()
    local bankState = statePort(options.bank or {
        alice = {
            current = 1000,
            fixed = {},
            investments = {},
            nextId = 1,
            nextLoanId = 1,
        },
    })
    local clock = { value = options.now or 0 }
    function clock:nowHours() return self.value end
    local random = { rolls = clone(options.rolls or { 1 }), index = 1 }
    function random:nextInt()
        local value = self.rolls[self.index] or self.rolls[#self.rolls] or 1
        self.index = self.index + 1
        return value
    end
    local features = { values = options.features or {} }
    function features:isEnabled(key)
        if self.values[key] == nil then return true end
        return self.values[key]
    end
    local audit = auditPort()
    audit.counters.alice = { spentPoints = options.spentPoints or 0 }
    local debt = { spawned = 0 }
    function debt:spawn(_, count) self.spawned = self.spawned + count; return count end
    local module = GodSystemBankFeatureModule.create({
        wallet = walletModule.public,
        ["bank.state"] = bankState,
        ["bank.clock"] = clock,
        ["bank.random"] = random,
        ["bank.features"] = features,
        ["bank.audit"] = audit,
        ["bank.debt"] = debt,
        operations = sharedLedger,
    }, {
        healthActor = "alice",
        mode = mode,
    })
    module:start()
    return {
        module = module,
        wallet = walletModule,
        funds = funds,
        state = bankState,
        clock = clock,
        random = random,
        audit = audit,
        debt = debt,
    }
end

local function execute(env, action, operationId, values)
    local request = {
        actor = "alice",
        action = action,
        operationId = operationId,
    }
    for key, value in pairs(values or {}) do request[key] = value end
    return env.module.public.execute(request)
end

do
    local env = bankEnvironment("sp")

    local deposit = execute(env, "deposit", "bank-deposit-1", { amount = 200 })
    expect(deposit.ok == true and env.state.rows.alice.current == 1200, "bank deposit")
    expect(env.funds.balances.alice.cash == 2800, "bank deposit charges carried cash")
    execute(env, "deposit", "bank-deposit-1", { amount = 200 })
    expect(env.state.rows.alice.current == 1200 and env.funds.balances.alice.cash == 2800,
        "bank deposit replay")

    local insufficient = execute(env, "deposit", "bank-deposit-low", { amount = 9000 })
    expect(insufficient.ok == false and env.state.rows.alice.current == 1200,
        "bank deposit insufficient")

    env.state.failNextCommit = true
    local beforeCash = env.funds.balances.alice.cash
    local failedDeposit = execute(env, "deposit", "bank-deposit-rollback", { amount = 100 })
    expect(failedDeposit.ok == false, "bank deposit commit failure")
    expect(env.funds.balances.alice.cash == beforeCash, "bank deposit refunds on commit failure")
    expect(env.state.rows.alice.current == 1200, "bank deposit state rollback")

    local withdraw = execute(env, "withdraw", "bank-withdraw-1", { amount = 150 })
    expect(withdraw.ok == true and env.state.rows.alice.current == 1050, "bank withdraw")
    expect(env.funds.balances.alice.cash == beforeCash + 150, "bank withdraw grants cash")
    execute(env, "withdraw", "bank-withdraw-1", { amount = 150 })
    expect(env.state.rows.alice.current == 1050, "bank withdraw replay")

    env.funds.failCredit = true
    local previousBank = clone(env.state.rows.alice)
    local failedWithdraw = execute(env, "withdraw", "bank-withdraw-rollback", { amount = 100 })
    expect(failedWithdraw.ok == false, "bank withdraw grant failure")
    expect(equal(previousBank, env.state.rows.alice), "bank withdraw restores state")
    env.funds.failCredit = false

    env.state.rows.alice.fixed = {
        { id = "mature", principal = 1000, startHour = 0, matureHour = 24, rate = 0.02, days = 1 },
        { id = "early", principal = 1000, startHour = 0, matureHour = 100, rate = 0.18, days = 7 },
    }
    env.clock.value = 24
    local mature = execute(env, "withdrawFixed", "bank-fixed-mature", { entryId = "mature" })
    expect(mature.ok == true and mature.data.payout == 1020, "fixed maturity payout")
    local early = execute(env, "withdrawFixed", "bank-fixed-early", { entryId = "early" })
    expect(early.ok == true and early.data.payout == 950, "fixed early 5 percent penalty")

    local currentBeforeInvestment = env.state.rows.alice.current
    local invest = execute(env, "investFromCurrent", "bank-invest-current", {
        termId = "stable", amount = 1000,
    })
    expect(invest.ok == true, "investment from current")
    expect(env.state.rows.alice.investments.stable.balance == 1000, "investment balance")
    expect(env.state.rows.alice.current == currentBeforeInvestment - 1000,
        "investment current debit")

    env.state.failNextCommit = true
    beforeCash = env.funds.balances.alice.cash
    local investFailed = execute(env, "investFromCash", "bank-invest-rollback", {
        termId = "balanced", amount = 200,
    })
    expect(investFailed.ok == false, "investment cash commit failure")
    expect(env.funds.balances.alice.cash == beforeCash, "investment cash rollback")

    env.clock.value = 48
    local settlement = execute(env, "syncInvestmentHours", "bank-invest-settle", { hours = 24 })
    expect(settlement.ok == true and settlement.data.settledCount == 1, "investment settlement")
    expect(env.state.rows.alice.investments.stable.balance == 1010,
        "stable investment gain 1 percent")
    expect(env.state.rows.alice.investments.stable.redeemUnlocked == true,
        "investment unlock after first settlement")
    local redeem = execute(env, "redeemInvestment", "bank-invest-redeem", {
        termId = "stable", amount = 10,
    })
    expect(redeem.ok == true and env.state.rows.alice.investments.stable.balance == 1000,
        "investment redeem")

    env.audit.counters.alice.spentPoints = 0
    local currentBeforeLoan = env.state.rows.alice.current
    local borrowed = execute(env, "borrowLoan", "bank-loan-borrow", {
        termId = "single", amount = 1000,
    })
    expect(borrowed.ok == true, "loan borrow")
    expect(env.state.rows.alice.current == currentBeforeLoan + 1000, "loan credits current")
    expect(env.state.rows.alice.loan.totalInterest == 50, "single loan interest remains 5 percent")
    expect(env.state.rows.alice.loan.schedule[1].dueHour == 120, "single loan due after 72 hours")

    env.clock.value = 120
    local repaid = execute(env, "repayLoanDue", "bank-loan-repay")
    expect(repaid.ok == true and repaid.data.amount == 1050, "loan due repayment")
    expect(env.state.rows.alice.loan == nil, "loan closes after full repayment")

    local beforeHealth = clone(env.state.rows)
    local health = env.module:health()
    expect(health.ok == true, "bank health")
    expect(equal(beforeHealth, env.state.rows), "bank health is read-only")
end

do
    local sp = bankEnvironment("sp")
    local mp = bankEnvironment("mp")
    local requests = {
        { "deposit", "parity-deposit", { amount = 100 } },
        { "investFromCurrent", "parity-invest", { termId = "balanced", amount = 200 } },
        { "borrowLoan", "parity-loan", { termId = "i3", amount = 500 } },
    }
    for index = 1, #requests do
        local row = requests[index]
        local spResult = execute(sp, row[1], row[2], row[3])
        local mpResult = execute(mp, row[1], row[2], row[3])
        expect(spResult.ok == mpResult.ok and spResult.code == mpResult.code,
            "SP/MP result parity: " .. row[1])
    end
    expect(equal(sp.state.rows, mp.state.rows), "SP/MP bank state parity")
    expect(equal(sp.funds.balances, mp.funds.balances), "SP/MP wallet state parity")
end

do
    local invalid = bankEnvironment("sp", {
        bank = {
            alice = {
                current = 0 / 0,
                fixed = {},
                investments = {},
            },
        },
    })
    local beforeCash = invalid.funds.balances.alice.cash
    local health = invalid.module:health()
    expect(health.ok == false and health.code == "bankStateInvalid:current",
        "bank health detects NaN state")
    local result = execute(invalid, "deposit", "invalid-state-deposit", { amount = 100 })
    expect(result.ok == false and result.code == "bankStateInvalid:current",
        "bank rejects invalid state")
    expect(invalid.funds.balances.alice.cash == beforeCash,
        "invalid bank state cannot charge wallet")
end

print("Test-GodSystemV422012WalletBankModuleRuntime passed")
