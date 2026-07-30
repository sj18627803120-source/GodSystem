require "GodSystem/Core/Result"
require "GodSystem/Features/Bank/Rules"

GodSystemBankFeatureModule = GodSystemBankFeatureModule or {}

local Descriptor = GodSystemBankFeatureModule
local Rules = GodSystemBankFeatureRules

Descriptor.id = "feature.bank"
Descriptor.dependencies = {
    "wallet",
    "bank.state",
    "bank.clock",
    "bank.random",
    "bank.features",
    "bank.audit",
    "bank.debt",
    "operations",
}
Descriptor.stateVersion = 1

local ACTIONS = {
    deposit = true,
    depositAllCash = true,
    withdraw = true,
    toggleAutoDeposit = true,
    withdrawFixed = true,
    investFromCurrent = true,
    investFromCash = true,
    redeemInvestment = true,
    syncInvestmentHours = true,
    borrowLoan = true,
    repayLoanDue = true,
    payoffLoan = true,
    updateLoan = true,
    deathPenalty = true,
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function call(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function method(port, name, ...)
    local callback = port and port[name]
    if type(callback) ~= "function" then return false, "missing method " .. tostring(name) end
    return call(callback, port, ...)
end

local function callback(port, name, ...)
    local fn = port and port[name]
    if type(fn) ~= "function" then return false, "missing method " .. tostring(name) end
    return call(fn, ...)
end

local function requiredPort(dependencies, dependencyId, methods)
    local port = dependencies[dependencyId]
    assert(type(port) == "table", "missing dependency: " .. dependencyId)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. dependencyId .. " is missing method " .. methods[index])
    end
    return port
end

local function positiveAmount(value)
    value = tonumber(value)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
        or value <= 0
    then
        return nil
    end
    value = math.floor(value)
    if value <= 0 then return nil end
    return value
end

local function nonNegativeAmount(value)
    value = tonumber(value)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
        or value < 0
    then
        return nil
    end
    return math.floor(value)
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 120 then return nil end
    return value
end

local function childRequest(request, suffix, values)
    local copy = {}
    for key, value in pairs(type(request) == "table" and request or {}) do copy[key] = value end
    local parentId = operationId(request)
    copy.operationId = parentId and (parentId .. ":" .. tostring(suffix)) or nil
    for key, value in pairs(type(values) == "table" and values or {}) do copy[key] = value end
    return copy
end

local function fingerprint(request)
    return table.concat({
        tostring(request.action or ""),
        tostring(request.amount or ""),
        tostring(request.termId or ""),
        tostring(request.entryId or ""),
        tostring(request.hours or ""),
    }, "|")
end

local function removeAt(list, index)
    for cursor = index, #list - 1 do list[cursor] = list[cursor + 1] end
    list[#list] = nil
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = Rules.config(context.config)
    local wallet = requiredPort(dependencies, "wallet",
        { "getBalance", "grant", "charge", "refund" })
    local state = requiredPort(dependencies, "bank.state", { "load", "commit" })
    local clock = requiredPort(dependencies, "bank.clock", { "nowHours" })
    local random = requiredPort(dependencies, "bank.random", { "nextInt" })
    local features = requiredPort(dependencies, "bank.features", { "isEnabled" })
    local audit = requiredPort(dependencies, "bank.audit", { "record", "increment", "counter" })
    local debt = requiredPort(dependencies, "bank.debt", { "spawn" })
    local operations = requiredPort(dependencies, "operations",
        { "begin", "finish", "markUnknown" })

    local instance = {
        started = false,
        completed = 0,
        failed = 0,
        lastIssue = nil,
        healthActor = context.healthActor,
    }

    local function result(ok, code, data, request)
        if ok then instance.completed = instance.completed + 1
        else instance.failed = instance.failed + 1 end
        if ok then return GodSystemResult.ok(moduleId, code, data, operationId(request)) end
        return GodSystemResult.fail(moduleId, code, data, operationId(request))
    end

    local function portFailure(stage, message, request)
        instance.lastIssue = {
            stage = stage,
            code = "portError",
            message = tostring(message),
        }
        return result(false, "portError", {
            stage = stage,
            message = tostring(message),
        }, request)
    end

    local function nowHours(request)
        local called, value = method(clock, "nowHours")
        if not called then return nil, portFailure("clock", value, request) end
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            return nil, result(false, "clockInvalid", nil, request)
        end
        return value
    end

    local function enabled(key, request)
        local called, value = method(features, "isEnabled", key)
        if not called then return nil, portFailure("features", value, request) end
        return value ~= false
    end

    local function loadBank(actor, request)
        local called, raw = method(state, "load", actor)
        if not called then return nil, nil, portFailure("stateLoad", raw, request) end
        local now, timeError = nowHours(request)
        if not now then return nil, nil, timeError end
        local bank, reason = Rules.normalize(raw, now)
        if not bank then return nil, nil, result(false, reason or "bankStateInvalid", nil, request) end
        return bank, now
    end

    local function commitBank(actor, bank, request)
        local called, committed, code, data = method(state, "commit", actor, bank, request)
        if not called then return false, portFailure("stateCommit", committed, request) end
        if committed ~= true then
            return false, result(false, code or "stateCommitFailed", data, request)
        end
        return true
    end

    local function auditEvent(actor, code, data, counters, request)
        for name, amount in pairs(type(counters) == "table" and counters or {}) do
            local called, ok = method(audit, "increment", actor, name, amount, request)
            if not called or ok == false then
                instance.lastIssue = {
                    stage = "auditIncrement",
                    code = "auditFailed",
                    message = tostring(name),
                }
            end
        end
        local called, ok = method(audit, "record", actor, code, data or {}, request)
        if not called or ok == false then
            instance.lastIssue = {
                stage = "auditRecord",
                code = "auditFailed",
                message = tostring(code),
            }
        end
    end

    local function spentPoints(actor)
        local called, value = method(audit, "counter", actor, "spentPoints")
        if not called then return 0 end
        return math.max(0, math.floor(tonumber(value) or 0))
    end

    local function begin(request)
        local id = operationId(request)
        if not id then return nil, result(false, "operationIdRequired", nil, request) end
        local called, status, ledgerResult = call(operations.begin, moduleId, id,
            fingerprint(request), request)
        if not called then return nil, portFailure("operationBegin", status, request) end
        if status == "replay" then return nil, ledgerResult end
        if status ~= "new" then
            local code = type(ledgerResult) == "table" and ledgerResult.code or "operationInvalid"
            return nil, result(false, code,
                type(ledgerResult) == "table" and ledgerResult.data or nil, request)
        end
        return ledgerResult
    end

    local function finish(request, value)
        local id = operationId(request)
        local called, finished = call(operations.finish, moduleId, id, value, request)
        if called and type(finished) == "table" then return finished end
        call(operations.markUnknown, moduleId, id, "operationOutcomeUnknown", request)
        instance.lastIssue = {
            stage = "operationFinish",
            code = "operationOutcomeUnknown",
            message = tostring(finished),
        }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = value and value.ok == true,
        }, id)
    end

    local function walletCharge(actor, amount, suffix, request)
        local called, paid, receiptOrCode, data = callback(wallet, "charge", actor, amount,
            childRequest(request, suffix, { scope = "cash" }))
        if not called then return false, nil, portFailure("walletCharge", paid, request) end
        if paid ~= true then return false, nil, result(false, receiptOrCode or "currencyInsufficient", data, request) end
        if type(receiptOrCode) ~= "table" then
            return false, nil, result(false, "receiptMissing", { stage = "walletCharge" }, request)
        end
        return true, receiptOrCode
    end

    local function walletRefund(actor, receipt, suffix, request)
        local called, refunded, code, data = callback(wallet, "refund", actor, receipt,
            childRequest(request, suffix))
        if not called then return false, tostring(refunded) end
        if refunded ~= true then return false, tostring(code or data or "refundFailed") end
        return true
    end

    local function walletGrant(actor, amount, suffix, request)
        local called, granted, receiptOrCode, data = callback(wallet, "grant", actor, amount,
            childRequest(request, suffix, { scope = "cash" }))
        if not called then return false, portFailure("walletGrant", granted, request) end
        if granted ~= true then
            return false, result(false, receiptOrCode or "withdrawFailed", data, request)
        end
        return true, receiptOrCode
    end

    local function rollbackState(actor, previous, request)
        local called, committed = method(state, "commit", actor, previous,
            childRequest(request, "stateRollback"))
        return called and committed == true
    end

    local function deposit(actor, bank, amount, request)
        amount = positiveAmount(amount)
        if not amount then return result(false, "amountInvalid", nil, request) end
        local paid, receipt, paymentError = walletCharge(actor, amount, "depositCharge", request)
        if not paid then return paymentError end
        bank.current = bank.current + amount
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then
            local restored = walletRefund(actor, receipt, "depositRefund", request)
            if not restored then
                return result(false, "rollbackIncomplete", {
                    cause = commitError,
                    wallet = false,
                }, request)
            end
            return commitError
        end
        auditEvent(actor, "BankDeposit", { amount = amount }, { bankDeposited = amount }, request)
        return result(true, "BankDeposit", { amount = amount, current = bank.current }, request)
    end

    local function depositAll(actor, bank, request)
        local called, amount, balanceCode = callback(wallet, "getBalance", actor, "cash")
        if not called then return portFailure("walletBalance", amount, request) end
        amount = nonNegativeAmount(amount)
        if not amount then return result(false, balanceCode or "balanceInvalid", nil, request) end
        if amount <= 0 then return result(false, "BankDepositAllEmpty", { amount = 0 }, request) end
        return deposit(actor, bank, amount, request)
    end

    local function withdraw(actor, bank, previous, amount, request)
        amount = positiveAmount(amount)
        if not amount then return result(false, "amountInvalid", nil, request) end
        if bank.current < amount then
            return result(false, "BankCurrentNotEnough", {
                available = bank.current,
                required = amount,
            }, request)
        end
        bank.current = bank.current - amount
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        local granted, grantOrError = walletGrant(actor, amount, "withdrawGrant", request)
        if not granted then
            if not rollbackState(actor, previous, request) then
                return result(false, "rollbackIncomplete", {
                    cause = grantOrError,
                    bank = false,
                }, request)
            end
            return grantOrError
        end
        auditEvent(actor, "BankWithdraw", { amount = amount }, { bankWithdrawn = amount }, request)
        return result(true, "BankWithdraw", { amount = amount, current = bank.current }, request)
    end

    local function toggleAutoDeposit(actor, bank, now, request)
        bank.autoDepositEnabled = bank.autoDepositEnabled ~= true
        bank.lastAutoDepositHour = now
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        return result(true, bank.autoDepositEnabled and "AutoDepositEnabled" or "AutoDepositDisabled", {
            enabled = bank.autoDepositEnabled,
        }, request)
    end

    local function withdrawFixed(actor, bank, now, request)
        local entryId = tostring(request.entryId or "")
        local entry, entryIndex
        for index = 1, #bank.fixed do
            if tostring(bank.fixed[index].id or "") == entryId then
                entry, entryIndex = bank.fixed[index], index
                break
            end
        end
        if not entry then return result(false, "BankFixedSelect", nil, request) end
        local payout, interestOrPenalty, mature = Rules.fixedPayout(entry, now, config)
        bank.current = bank.current + payout
        removeAt(bank.fixed, entryIndex)
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        local counters = mature
            and { bankInterest = math.max(0, interestOrPenalty) }
            or { bankPenalty = math.abs(math.min(0, interestOrPenalty)) }
        auditEvent(actor, mature and "BankFixedWithdraw" or "BankFixedEarlyWithdraw", {
            payout = payout,
            interestOrPenalty = interestOrPenalty,
        }, counters, request)
        return result(true, mature and "BankFixedWithdraw" or "BankFixedEarlyWithdraw", {
            payout = payout,
            interestOrPenalty = interestOrPenalty,
            mature = mature,
        }, request)
    end

    local function prepareInvestment(bank, request)
        local enabledValue, featureError = enabled("EnableBankInvestments", request)
        if enabledValue == nil then return nil, nil, featureError end
        if not enabledValue then return nil, nil, result(false, "BankInvestmentDisabled", nil, request) end
        local profile = Rules.investmentProfile(config, request.termId)
        local amount = positiveAmount(request.amount)
        if not profile then return nil, nil, result(false, "BankInvestmentSelect", nil, request) end
        if not amount or amount < math.max(1, math.floor(config.investmentMinimum)) then
            return nil, nil, result(false, "BankInvestmentMinimum", {
                minimum = math.max(1, math.floor(config.investmentMinimum)),
            }, request)
        end
        return profile, amount
    end

    local function addInvestment(account, amount)
        if account.balance <= 0 then
            account.balance = 0
            account.onlineHours = 0
            account.settlementCount = 0
            account.redeemUnlocked = false
            account.lastDelta = 0
            account.lastOutcome = "flat"
            account.lastSettledHour = nil
        end
        account.balance = account.balance + amount
    end

    local function investCurrent(actor, bank, request)
        local profile, amount, preparationError = prepareInvestment(bank, request)
        if not profile then return preparationError end
        if bank.current < amount then return result(false, "BankCurrentNotEnough", nil, request) end
        bank.current = bank.current - amount
        addInvestment(bank.investments[profile.id], amount)
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        auditEvent(actor, "BankInvestmentCreated", {
            tierId = profile.id, amount = amount, source = "current",
        }, { bankInvestmentDeposited = amount }, request)
        return result(true, "BankInvestmentCreated", {
            tierId = profile.id, amount = amount,
        }, request)
    end

    local function investCash(actor, bank, request)
        local profile, amount, preparationError = prepareInvestment(bank, request)
        if not profile then return preparationError end
        local paid, receipt, paymentError = walletCharge(actor, amount, "investmentCharge", request)
        if not paid then return paymentError end
        addInvestment(bank.investments[profile.id], amount)
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then
            local restored = walletRefund(actor, receipt, "investmentRefund", request)
            if not restored then
                return result(false, "rollbackIncomplete", {
                    cause = commitError,
                    wallet = false,
                }, request)
            end
            return commitError
        end
        auditEvent(actor, "BankInvestmentCreated", {
            tierId = profile.id, amount = amount, source = "cash",
        }, { bankInvestmentDeposited = amount }, request)
        return result(true, "BankInvestmentCreated", {
            tierId = profile.id, amount = amount,
        }, request)
    end

    local function redeemInvestment(actor, bank, request)
        local profile = Rules.investmentProfile(config, request.termId)
        local amount = positiveAmount(request.amount)
        local account = profile and bank.investments[profile.id] or nil
        if not profile or not account or account.balance <= 0 or not amount then
            return result(false, "BankInvestmentSelect", nil, request)
        end
        if account.redeemUnlocked ~= true then
            return result(false, "BankInvestmentLocked", nil, request)
        end
        if amount > account.balance then
            return result(false, "BankInvestmentBalanceLow", nil, request)
        end
        account.balance = account.balance - amount
        bank.current = bank.current + amount
        if account.balance <= 0 then
            account.onlineHours = 0
            account.settlementCount = 0
            account.redeemUnlocked = false
            account.lastDelta = 0
            account.lastOutcome = "flat"
            account.lastSettledHour = nil
        end
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        auditEvent(actor, "BankInvestmentRedeemed", {
            tierId = profile.id, amount = amount,
        }, { bankInvestmentRedeemed = amount }, request)
        return result(true, "BankInvestmentRedeemed", {
            tierId = profile.id, amount = amount,
        }, request)
    end

    local function settleInvestments(actor, bank, now, request)
        local hours = nonNegativeAmount(request.hours)
        if not hours then return result(false, "hoursInvalid", nil, request) end
        local enabledValue, featureError = enabled("EnableBankInvestments", request)
        if enabledValue == nil then return featureError end
        if not enabledValue or hours <= 0 then
            return result(true, "BankInvestmentProgress", { hours = hours, settledCount = 0 }, request)
        end
        local randomFailure = nil
        local function nextInt(maximum)
            local called, value = method(random, "nextInt", maximum)
            if not called then randomFailure = tostring(value); return 1 end
            return value
        end
        local events, totalDelta = Rules.settleInvestments(bank, hours, now, config, nextInt)
        if randomFailure then return portFailure("random", randomFailure, request) end
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        local counters = { bankInvestmentProfit = 0, bankInvestmentLoss = 0 }
        for index = 1, #events do
            local event = events[index]
            if event.delta > 0 then counters.bankInvestmentProfit = counters.bankInvestmentProfit + event.delta
            elseif event.delta < 0 then counters.bankInvestmentLoss = counters.bankInvestmentLoss + math.abs(event.delta) end
            auditEvent(actor, "BankInvestmentSettled", event, nil, request)
        end
        if counters.bankInvestmentProfit > 0 then
            method(audit, "increment", actor, "bankInvestmentProfit",
                counters.bankInvestmentProfit, request)
        end
        if counters.bankInvestmentLoss > 0 then
            method(audit, "increment", actor, "bankInvestmentLoss",
                counters.bankInvestmentLoss, request)
        end
        return result(true, #events > 0 and "BankInvestmentSettled" or "BankInvestmentProgress", {
            hours = hours,
            settledCount = #events,
            totalDelta = totalDelta,
        }, request)
    end

    local function bankruptcyDue(bank, now)
        if not bank.loan then return false end
        local amounts = Rules.loanAmounts(bank.loan, now)
        if not amounts.overdueStartHour then return false end
        return now - amounts.overdueStartHour >= math.max(1,
            math.floor(config.loanBankruptcyGraceHours))
    end

    local function applyBankruptcy(actor, bank, now, request)
        local amounts = Rules.loanAmounts(bank.loan, now)
        local penalty = Rules.loanPenalty(bank.loan, now, amounts, config)
        local totalDebt = amounts.unpaidTotal + penalty
        local called, cash = callback(wallet, "getBalance", actor, "cash")
        if not called then return portFailure("walletBalance", cash, request) end
        cash = math.max(0, math.floor(tonumber(cash) or 0))
        local cashReceipt = nil
        if cash > 0 then
            local paid, receipt, paymentError = walletCharge(actor, cash, "bankruptcyCash", request)
            if not paid then return paymentError end
            cashReceipt = receipt
        end
        bank.loan = nil
        bank.current = 0
        bank.loanFrozenUntilHour = now + math.max(0, math.floor(config.loanFreezeHours))
        bank.loanCreditSpentOffset = spentPoints(actor)
        bank.loanBankruptcyCount = bank.loanBankruptcyCount + 1
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then
            if cashReceipt and not walletRefund(actor, cashReceipt, "bankruptcyRefund", request) then
                return result(false, "rollbackIncomplete", { wallet = false }, request)
            end
            return commitError
        end
        local perZombie = math.max(1, math.floor(config.loanZombieDebtPerZombie))
        local count = math.min(math.max(0, math.floor(config.loanZombieMaxCount)),
            math.max(1, math.floor(totalDebt / perZombie)))
        local spawnCalled, spawned = method(debt, "spawn", actor, count, request)
        if not spawnCalled then
            instance.lastIssue = {
                stage = "debtSpawn",
                code = "debtSpawnFailed",
                message = tostring(spawned),
            }
            spawned = 0
        end
        auditEvent(actor, "BankLoanBankruptcy", {
            debt = totalDebt, spawned = spawned,
        }, { bankPenalty = totalDebt }, request)
        return result(true, "BankLoanBankruptcy", {
            debt = totalDebt, spawned = spawned,
        }, request)
    end

    local function borrowLoan(actor, bank, now, request)
        local enabledValue, featureError = enabled("EnableBankLoan", request)
        if enabledValue == nil then return featureError end
        if not enabledValue then return result(false, "BankLoanDisabled", nil, request) end
        if bankruptcyDue(bank, now) then
            local bankruptcy = applyBankruptcy(actor, bank, now, request)
            if bankruptcy.ok then return result(false, "BankLoanFrozen", bankruptcy.data, request) end
            return bankruptcy
        end
        if bank.loan then return result(false, "BankLoanActive", nil, request) end
        if bank.loanFrozenUntilHour > now then return result(false, "BankLoanFrozen", nil, request) end
        local amount = positiveAmount(request.amount)
        local plan = Rules.loanPlan(config, request.termId)
        if not amount then return result(false, "amountInvalid", nil, request) end
        if not plan then return result(false, "BankLoanPlanMissing", nil, request) end
        local _, available = Rules.loanCredit(spentPoints(actor), bank, config)
        if amount > available then
            return result(false, "BankLoanCreditInsufficient", { available = available }, request)
        end
        local id = "L" .. tostring(bank.nextLoanId)
        bank.nextLoanId = bank.nextLoanId + 1
        bank.loan = Rules.createLoan(plan, amount, now, id)
        bank.current = bank.current + amount
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        auditEvent(actor, "BankLoanBorrowed", { amount = amount, planId = plan.id }, nil, request)
        return result(true, "BankLoanBorrowed", {
            amount = amount, planId = plan.id, loanId = id,
        }, request)
    end

    local function repayDue(actor, bank, now, request)
        if not bank.loan then return result(false, "BankLoanMissing", nil, request) end
        if bankruptcyDue(bank, now) then return applyBankruptcy(actor, bank, now, request) end
        local amounts = Rules.loanAmounts(bank.loan, now)
        local penalty = Rules.loanPenalty(bank.loan, now, amounts, config)
        local due = amounts.due + penalty
        if due <= 0 then return result(false, "BankLoanNothingDue", nil, request) end
        if bank.current < due then return result(false, "BankCurrentNotEnough", nil, request) end
        bank.current = bank.current - due
        Rules.applyLoanPayment(bank.loan, amounts.due, now, false)
        if bank.loan.paid >= bank.loan.totalDue then bank.loan = nil
        else Rules.loanAmounts(bank.loan, now) end
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        auditEvent(actor, "BankLoanRepaid", { amount = due }, {
            bankPenalty = penalty,
        }, request)
        return result(true, "BankLoanRepaid", { amount = due, penalty = penalty }, request)
    end

    local function payoffLoan(actor, bank, now, request)
        if not bank.loan then return result(false, "BankLoanMissing", nil, request) end
        if bankruptcyDue(bank, now) then return applyBankruptcy(actor, bank, now, request) end
        local amounts = Rules.loanAmounts(bank.loan, now)
        local penalty = Rules.loanPenalty(bank.loan, now, amounts, config)
        local payoff = math.max(0, math.floor(amounts.due + penalty
            + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5)))
        if payoff > bank.current then return result(false, "BankCurrentNotEnough", nil, request) end
        bank.current = bank.current - payoff
        bank.loan = nil
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        auditEvent(actor, "BankLoanPayoff", { amount = payoff }, {
            bankPenalty = penalty,
        }, request)
        return result(true, "BankLoanPayoff", { amount = payoff, penalty = penalty }, request)
    end

    local function deathPenalty(actor, bank, now, request)
        if now - bank.lastDeathPenaltyHour < 0.1 then
            return result(true, "BankDeathPenaltySkipped", { amount = 0 }, request)
        end
        bank.lastDeathPenaltyHour = now
        local penalty = math.floor(bank.current * config.deathPenaltyRatio)
        if penalty > 0 then bank.current = math.max(0, bank.current - penalty) end
        local committed, commitError = commitBank(actor, bank, request)
        if not committed then return commitError end
        if penalty > 0 then
            auditEvent(actor, "BankDeathPenalty", { amount = penalty }, {
                bankPenalty = penalty,
            }, request)
        end
        return result(true, "BankDeathPenalty", { amount = penalty }, request)
    end

    local function executeAction(request)
        local actor = request.actor
        local bank, now, loadError = loadBank(actor, request)
        if not bank then return loadError end
        local previous = Rules.normalize(bank, now)
        local action = request.action
        if action == "deposit" then return deposit(actor, bank, request.amount, request) end
        if action == "depositAllCash" then return depositAll(actor, bank, request) end
        if action == "withdraw" then return withdraw(actor, bank, previous, request.amount, request) end
        if action == "toggleAutoDeposit" then return toggleAutoDeposit(actor, bank, now, request) end
        if action == "withdrawFixed" then return withdrawFixed(actor, bank, now, request) end
        if action == "investFromCurrent" then return investCurrent(actor, bank, request) end
        if action == "investFromCash" then return investCash(actor, bank, request) end
        if action == "redeemInvestment" then return redeemInvestment(actor, bank, request) end
        if action == "syncInvestmentHours" then return settleInvestments(actor, bank, now, request) end
        if action == "borrowLoan" then return borrowLoan(actor, bank, now, request) end
        if action == "repayLoanDue" then return repayDue(actor, bank, now, request) end
        if action == "payoffLoan" then return payoffLoan(actor, bank, now, request) end
        if action == "deathPenalty" then return deathPenalty(actor, bank, now, request) end
        if action == "updateLoan" then
            if bankruptcyDue(bank, now) then return applyBankruptcy(actor, bank, now, request) end
            return result(true, "BankLoanCurrent", Rules.summary(bank, now, spentPoints(actor), config), request)
        end
        return result(false, "actionInvalid", { action = action }, request)
    end

    local function execute(request)
        request = type(request) == "table" and request or {}
        request.action = tostring(request.action or "")
        if not instance.started then return result(false, "moduleStopped", nil, request) end
        if not ACTIONS[request.action] then
            return result(false, "actionInvalid", { action = request.action }, request)
        end
        if request.actor == nil then return result(false, "actorRequired", nil, request) end
        local bankEnabled, featureError = enabled("EnableBank", request)
        if bankEnabled == nil then return featureError end
        if not bankEnabled then return result(false, "BankDisabled", nil, request) end
        local row, replay = begin(request)
        if not row then return replay end
        local called, value = call(executeAction, request)
        if not called then
            call(operations.markUnknown, moduleId, operationId(request), "portError", request)
            return portFailure("execute", value, request)
        end
        return finish(request, value)
    end

    local function summary(actor)
        local request = { actor = actor }
        local bank, now, loadError = loadBank(actor, request)
        if not bank then return loadError end
        local value = Rules.summary(bank, now, spentPoints(actor), config)
        value.state = copy(bank)
        local called, cash = callback(wallet, "getBalance", actor, "cash")
        value.cash = called and math.max(0, math.floor(tonumber(cash) or 0)) or 0
        return GodSystemResult.ok(moduleId, "BankSummary", value)
    end

    local function requestSummary(request)
        request = type(request) == "table" and request or {}
        if request.actor == nil then
            return result(false, "actorRequired", nil, request)
        end
        return summary(request.actor)
    end

    instance.public = {
        execute = execute,
        summary = summary,
        requestSummary = requestSummary,
        deposit = function(request)
            request = childRequest(request, "depositPublic", { action = "deposit" })
            return execute(request)
        end,
        withdraw = function(request)
            request = childRequest(request, "withdrawPublic", { action = "withdraw" })
            return execute(request)
        end,
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
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            lastIssue = self.lastIssue,
        }
        if self.healthActor ~= nil then
            local request = { actor = self.healthActor }
            local bank, _, loadError = loadBank(self.healthActor, request)
            if not bank then
                data.state = loadError and loadError.code or "bankStateInvalid"
                return GodSystemResult.fail(moduleId, data.state, data)
            end
        end
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
