GodSystemBankFeatureRules = GodSystemBankFeatureRules or {}

local Rules = GodSystemBankFeatureRules

local INVESTMENT_IDS = { "stable", "balanced", "aggressive" }

local DEFAULTS = {
    deathPenaltyRatio = 0.30,
    earlyWithdrawPenaltyRatio = 0.05,
    investmentSettlementHours = 24,
    investmentMinimum = 1,
    investmentProfiles = {
        stable = { gainChance = 70, lossChance = 5, gainPercent = 1, lossPercent = 1 },
        balanced = { gainChance = 55, lossChance = 30, gainPercent = 3, lossPercent = 2 },
        aggressive = { gainChance = 45, lossChance = 45, gainPercent = 8, lossPercent = 5 },
    },
    loanBaseCredit = 2000,
    loanCreditSpendStep = 100,
    loanCreditPerStep = 5,
    loanSingleDueHours = 72,
    loanSingleInterestRate = 0.05,
    loanPeriodHours = 72,
    loanInstallmentPlans = {
        { id = "i3", periods = 3, totalInterestRate = 0.10 },
        { id = "i5", periods = 5, totalInterestRate = 0.18 },
        { id = "i10", periods = 10, totalInterestRate = 0.30 },
    },
    loanOverduePenaltyDailyRate = 0.05,
    loanOverduePenaltyMaxRate = 0.50,
    loanBankruptcyGraceHours = 240,
    loanFreezeHours = 168,
    loanZombieDebtPerZombie = 50,
    loanZombieMaxCount = 100,
}

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function number(value, fallback)
    value = tonumber(value)
    if not finite(value) then return fallback end
    return value
end

local function integer(value, fallback)
    return math.floor(number(value, fallback or 0))
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function validNumber(value)
    return value == nil or finite(tonumber(value))
end

local function normalizedInvestment(account, tierId)
    account = type(account) == "table" and clone(account) or {}
    if not validNumber(account.balance)
        or not validNumber(account.onlineHours)
        or not validNumber(account.settlementCount)
        or not validNumber(account.lastDelta)
        or not validNumber(account.lastSettledHour)
    then
        return nil, "investmentDataInvalid:" .. tierId
    end
    account.tierId = tierId
    account.balance = math.max(0, integer(account.balance, 0))
    account.onlineHours = math.max(0, number(account.onlineHours, 0))
    account.settlementCount = math.max(0, integer(account.settlementCount, 0))
    account.redeemUnlocked = account.redeemUnlocked == true
    account.lastDelta = integer(account.lastDelta, 0)
    account.lastOutcome = tostring(account.lastOutcome or "flat")
    account.lastSettledHour = tonumber(account.lastSettledHour)
    return account
end

local function normalizedFixed(entries, now)
    if entries ~= nil and type(entries) ~= "table" then return nil, "fixedDataInvalid" end
    local result = {}
    for index = 1, #(entries or {}) do
        local entry = entries[index]
        if type(entry) ~= "table"
            or not validNumber(entry.principal)
            or not validNumber(entry.startHour)
            or not validNumber(entry.matureHour)
            or not validNumber(entry.rate)
            or not validNumber(entry.days)
        then
            return nil, "fixedEntryInvalid:" .. tostring(index)
        end
        local principal = math.max(0, integer(entry.principal, 0))
        if principal > 0 then
            local row = clone(entry)
            row.id = tostring(row.id or ("F" .. tostring(index)))
            row.termId = tostring(row.termId or "")
            row.principal = principal
            row.startHour = number(row.startHour, now)
            row.matureHour = number(row.matureHour, row.startHour)
            row.rate = number(row.rate, 0)
            row.days = math.max(1, integer(row.days,
                math.max(1, math.ceil((row.matureHour - row.startHour) / 24))))
            result[#result + 1] = row
        end
    end
    return result
end

local function normalizedLoan(source, nextLoanId, now)
    if source == nil then return nil end
    if type(source) ~= "table" then return nil, "loanDataInvalid" end
    local numeric = {
        "principal", "createdHour", "totalInterest", "totalDue", "paid", "overdueStartHour",
    }
    for index = 1, #numeric do
        if not validNumber(source[numeric[index]]) then
            return nil, "loanDataInvalid:" .. numeric[index]
        end
    end
    if source.schedule ~= nil and type(source.schedule) ~= "table" then
        return nil, "loanScheduleInvalid"
    end
    local loan = clone(source)
    loan.id = tostring(loan.id or ("L" .. tostring(nextLoanId)))
    loan.kind = tostring(loan.kind or "single")
    loan.planId = tostring(loan.planId or loan.kind)
    loan.principal = math.max(0, integer(loan.principal, 0))
    loan.createdHour = number(loan.createdHour, now)
    loan.totalInterest = math.max(0, integer(loan.totalInterest, 0))
    loan.totalDue = math.max(loan.principal + loan.totalInterest, integer(loan.totalDue, 0))
    loan.paid = math.max(0, integer(loan.paid, 0))
    loan.overdueStartHour = tonumber(loan.overdueStartHour)
    local schedule = {}
    for index = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[index]
        if type(bill) ~= "table"
            or not validNumber(bill.index)
            or not validNumber(bill.dueHour)
            or not validNumber(bill.principalPart)
            or not validNumber(bill.interestPart)
            or not validNumber(bill.paid)
        then
            return nil, "loanBillInvalid:" .. tostring(index)
        end
        schedule[#schedule + 1] = {
            index = math.max(1, integer(bill.index, index)),
            dueHour = number(bill.dueHour, loan.createdHour),
            principalPart = math.max(0, integer(bill.principalPart, 0)),
            interestPart = math.max(0, integer(bill.interestPart, 0)),
            paid = math.max(0, integer(bill.paid, 0)),
        }
    end
    loan.schedule = schedule
    if loan.principal <= 0 or loan.totalDue <= 0 or loan.paid >= loan.totalDue then return nil end
    return loan
end

function Rules.config(source)
    source = type(source) == "table" and source or {}
    local config = clone(DEFAULTS)
    for key, value in pairs(source) do config[key] = clone(value) end
    return config
end

function Rules.normalize(source, now)
    if source ~= nil and type(source) ~= "table" then return nil, "bankStateInvalid" end
    source = type(source) == "table" and source or {}
    local numeric = {
        "current", "nextId", "lastDeathPenaltyHour", "lastAutoDepositHour",
        "nextLoanId", "loanFrozenUntilHour", "loanCreditSpentOffset", "loanBankruptcyCount",
    }
    for index = 1, #numeric do
        if not validNumber(source[numeric[index]]) then
            return nil, "bankStateInvalid:" .. numeric[index]
        end
    end
    now = number(now, 0)
    local bank = clone(source)
    bank.current = math.max(0, integer(bank.current, 0))
    bank.nextId = math.max(1, integer(bank.nextId, 1))
    bank.lastDeathPenaltyHour = number(bank.lastDeathPenaltyHour, -999)
    bank.autoDepositEnabled = bank.autoDepositEnabled == true
    bank.lastAutoDepositHour = number(bank.lastAutoDepositHour, now)
    bank.nextLoanId = math.max(1, integer(bank.nextLoanId, 1))
    bank.loanFrozenUntilHour = number(bank.loanFrozenUntilHour, 0)
    bank.loanCreditSpentOffset = math.max(0, integer(bank.loanCreditSpentOffset, 0))
    bank.loanBankruptcyCount = math.max(0, integer(bank.loanBankruptcyCount, 0))

    local fixed, reason = normalizedFixed(bank.fixed, now)
    if not fixed then return nil, reason end
    bank.fixed = fixed

    if bank.investments ~= nil and type(bank.investments) ~= "table" then
        return nil, "investmentDataInvalid"
    end
    local investments = {}
    for index = 1, #INVESTMENT_IDS do
        local tierId = INVESTMENT_IDS[index]
        local account
        account, reason = normalizedInvestment(bank.investments and bank.investments[tierId], tierId)
        if not account then return nil, reason end
        investments[tierId] = account
    end
    bank.investments = investments

    bank.loan, reason = normalizedLoan(bank.loan, bank.nextLoanId, now)
    if reason then return nil, reason end
    return bank
end

function Rules.investmentProfile(config, tierId)
    config = Rules.config(config)
    tierId = tostring(tierId or "")
    local source = config.investmentProfiles[tierId]
    if not source then return nil end
    local gainChance = math.max(0, math.min(100, integer(source.gainChance, 0)))
    return {
        id = tierId,
        gainChance = gainChance,
        lossChance = math.max(0, math.min(100 - gainChance, integer(source.lossChance, 0))),
        gainPercent = math.max(0, number(source.gainPercent, 0)),
        lossPercent = math.max(0, number(source.lossPercent, 0)),
    }
end

function Rules.fixedPayout(entry, now, config)
    if type(entry) ~= "table" then return 0, 0, false end
    config = Rules.config(config)
    local principal = math.max(0, integer(entry.principal, 0))
    if number(now, 0) >= number(entry.matureHour, 0) then
        local interest = math.max(0, math.floor(principal * number(entry.rate, 0)))
        return principal + interest, interest, true
    end
    local penalty = math.max(0,
        math.floor(principal * number(config.earlyWithdrawPenaltyRatio, 0.05)))
    return math.max(0, principal - penalty), -penalty, false
end

function Rules.settleInvestments(bank, elapsedHours, now, config, nextInt)
    config = Rules.config(config)
    elapsedHours = math.max(0, integer(elapsedHours, 0))
    local settlementHours = math.max(1, number(config.investmentSettlementHours, 24))
    local events = {}
    local totalDelta = 0
    for index = 1, #INVESTMENT_IDS do
        local tierId = INVESTMENT_IDS[index]
        local account = bank.investments[tierId]
        local profile = Rules.investmentProfile(config, tierId)
        if account.balance > 0 then
            account.onlineHours = math.max(0, number(account.onlineHours, 0)) + elapsedHours
            while account.onlineHours >= settlementHours and account.balance > 0 do
                account.onlineHours = account.onlineHours - settlementHours
                local before = account.balance
                local roll = math.max(1, math.min(100, integer(nextInt(100), 1)))
                local delta = 0
                local outcome = "flat"
                if roll <= profile.gainChance and profile.gainPercent > 0 then
                    delta = math.max(1, math.floor(before * profile.gainPercent / 100))
                    account.balance = before + delta
                    outcome = "gain"
                elseif roll > 100 - profile.lossChance and profile.lossPercent > 0 then
                    local loss = math.min(before,
                        math.max(1, math.floor(before * profile.lossPercent / 100)))
                    delta = -loss
                    account.balance = before - loss
                    outcome = "loss"
                end
                account.redeemUnlocked = true
                account.settlementCount = account.settlementCount + 1
                account.lastDelta = delta
                account.lastOutcome = outcome
                account.lastSettledHour = now
                totalDelta = totalDelta + delta
                events[#events + 1] = {
                    tierId = tierId,
                    before = before,
                    delta = delta,
                    balance = account.balance,
                    outcome = outcome,
                }
            end
        end
    end
    return events, totalDelta
end

function Rules.loanPlans(config)
    config = Rules.config(config)
    local plans = {
        {
            id = "single",
            kind = "single",
            periods = 1,
            dueHours = math.max(1, integer(config.loanSingleDueHours, 72)),
            totalInterestRate = number(config.loanSingleInterestRate, 0.05),
        },
    }
    local periodHours = math.max(1, integer(config.loanPeriodHours, 72))
    for index = 1, #(config.loanInstallmentPlans or {}) do
        local row = config.loanInstallmentPlans[index]
        local periods = math.max(1, integer(row.periods, 1))
        plans[#plans + 1] = {
            id = tostring(row.id or ("i" .. tostring(periods))),
            kind = "installment",
            periods = periods,
            dueHours = periodHours,
            totalInterestRate = number(row.totalInterestRate, 0),
        }
    end
    return plans
end

function Rules.loanPlan(config, planId)
    planId = tostring(planId or "single")
    local plans = Rules.loanPlans(config)
    for index = 1, #plans do
        if plans[index].id == planId then return plans[index] end
    end
    return nil
end

function Rules.createLoan(plan, amount, now, id)
    amount = math.max(1, integer(amount, 1))
    local periods = math.max(1, integer(plan.periods, 1))
    local totalInterest = math.max(0,
        math.floor(amount * number(plan.totalInterestRate, 0)))
    local principalLeft = amount
    local interestLeft = totalInterest
    local schedule = {}
    for index = 1, periods do
        local principalPart = index == periods and principalLeft or math.floor(amount / periods)
        local interestPart = index == periods and interestLeft or math.floor(totalInterest / periods)
        principalLeft = principalLeft - principalPart
        interestLeft = interestLeft - interestPart
        schedule[#schedule + 1] = {
            index = index,
            dueHour = now + math.max(1, integer(plan.dueHours, 72)) * index,
            principalPart = principalPart,
            interestPart = interestPart,
            paid = 0,
        }
    end
    return {
        id = tostring(id),
        kind = plan.kind,
        planId = plan.id,
        principal = amount,
        createdHour = now,
        totalInterest = totalInterest,
        totalDue = amount + totalInterest,
        paid = 0,
        schedule = schedule,
    }
end

function Rules.loanAmounts(loan, now)
    local result = {
        due = 0,
        futurePrincipal = 0,
        futureInterest = 0,
        unpaidPrincipal = 0,
        unpaidInterest = 0,
        unpaidTotal = 0,
        overdueStartHour = nil,
        nextDueHour = nil,
    }
    if type(loan) ~= "table" then return result end
    for index = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[index]
        local principal = math.max(0, integer(bill.principalPart, 0))
        local interest = math.max(0, integer(bill.interestPart, 0))
        local paid = math.max(0, integer(bill.paid, 0))
        local remaining = math.max(0, principal + interest - paid)
        if remaining > 0 then
            local principalPaid = math.min(principal, paid)
            local interestPaid = math.max(0, paid - principal)
            local principalLeft = math.max(0, principal - principalPaid)
            local interestLeft = math.max(0, interest - interestPaid)
            result.unpaidPrincipal = result.unpaidPrincipal + principalLeft
            result.unpaidInterest = result.unpaidInterest + interestLeft
            result.unpaidTotal = result.unpaidTotal + remaining
            if now >= bill.dueHour then
                result.due = result.due + remaining
                if not result.overdueStartHour or bill.dueHour < result.overdueStartHour then
                    result.overdueStartHour = bill.dueHour
                end
            else
                result.futurePrincipal = result.futurePrincipal + principalLeft
                result.futureInterest = result.futureInterest + interestLeft
                if not result.nextDueHour or bill.dueHour < result.nextDueHour then
                    result.nextDueHour = bill.dueHour
                end
            end
        end
    end
    loan.overdueStartHour = result.overdueStartHour
    return result
end

function Rules.loanPenalty(loan, now, amounts, config)
    config = Rules.config(config)
    amounts = amounts or Rules.loanAmounts(loan, now)
    if not loan or not amounts.overdueStartHour then return 0 end
    local overdueDays = math.max(0, math.floor((now - amounts.overdueStartHour) / 24))
    if overdueDays <= 0 then return 0 end
    local principal = math.max(0, integer(loan.principal, 0))
    local daily = number(config.loanOverduePenaltyDailyRate, 0.05)
    local maximum = number(config.loanOverduePenaltyMaxRate, 0.50)
    return math.max(0, math.floor(math.min(principal * maximum,
        principal * daily * overdueDays)))
end

function Rules.loanCredit(spentPoints, bank, config)
    config = Rules.config(config)
    local base = math.max(0, integer(config.loanBaseCredit, 2000))
    local step = math.max(1, integer(config.loanCreditSpendStep, 100))
    local perStep = math.max(0, integer(config.loanCreditPerStep, 5))
    local offset = math.max(0, integer(bank.loanCreditSpentOffset, 0))
    local growth = math.floor(math.max(0, integer(spentPoints, 0) - offset) / step) * perStep
    local used = Rules.loanAmounts(bank.loan, 0).unpaidPrincipal
    return base + growth, math.max(0, base + growth - used), growth, used
end

function Rules.applyLoanPayment(loan, amount, now, includeFuture)
    amount = math.max(0, integer(amount, 0))
    local paid = 0
    for index = 1, #(loan and loan.schedule or {}) do
        local bill = loan.schedule[index]
        local total = math.max(0, integer(bill.principalPart, 0)
            + integer(bill.interestPart, 0))
        local billPaid = math.max(0, integer(bill.paid, 0))
        if total > billPaid and (includeFuture or now >= bill.dueHour) then
            local add = math.min(amount, total - billPaid)
            bill.paid = billPaid + add
            loan.paid = math.max(0, integer(loan.paid, 0)) + add
            amount = amount - add
            paid = paid + add
            if amount <= 0 then break end
        end
    end
    return paid
end

function Rules.summary(bank, now, spentPoints, config)
    config = Rules.config(config)
    local amounts = Rules.loanAmounts(bank.loan, now)
    local penalty = Rules.loanPenalty(bank.loan, now, amounts, config)
    local total, available, growth, used = Rules.loanCredit(spentPoints, bank, config)
    local investmentTotal = 0
    for index = 1, #INVESTMENT_IDS do
        investmentTotal = investmentTotal + bank.investments[INVESTMENT_IDS[index]].balance
    end
    return {
        current = bank.current,
        investmentTotal = investmentTotal,
        fixedCount = #bank.fixed,
        creditTotal = total,
        creditAvailable = available,
        creditGrowth = growth,
        creditUsed = used,
        loan = bank.loan,
        dueNow = amounts.due + penalty,
        dueBase = amounts.due,
        overduePenalty = penalty,
        payoff = amounts.due + penalty + amounts.futurePrincipal
            + math.floor(amounts.futureInterest * 0.5),
        unpaidTotal = amounts.unpaidTotal + penalty,
        nextDueHour = amounts.nextDueHour,
        overdueStartHour = amounts.overdueStartHour,
        freezeLeftHours = math.max(0, math.ceil(bank.loanFrozenUntilHour - now)),
        bankruptcyInHours = amounts.overdueStartHour and math.max(0,
            math.ceil(math.max(1, integer(config.loanBankruptcyGraceHours, 240))
                - (now - amounts.overdueStartHour))) or nil,
    }
end

return Rules
