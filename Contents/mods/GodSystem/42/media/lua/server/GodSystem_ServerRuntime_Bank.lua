_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Bank"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Bank then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Bank = true
    setfenv(1, runtimeEnvironment)

function GodSystemServer.refundCurrencySources(player, data, fromBank, fromCash)
    local bank = getBank(data)
    local bankAmount = math.max(0, floor(fromBank, 0))
    local cashAmount = math.max(0, floor(fromCash, 0))
    bank.current = (bank.current or 0) + bankAmount
    if cashAmount <= 0 then return true end
    if giveCurrency(player, cashAmount) then return true end
    bank.current = (bank.current or 0) + cashAmount
    return false
end

function GodSystemServer.restoreRemovedCurrencyOrBank(player, removed)
    local ok, failedValue = restoreRemovedCurrency(player, removed)
    if failedValue > 0 then
        local bank = getBank(playerData(player))
        bank.current = (bank.current or 0) + failedValue
    end
    return ok, failedValue
end

function bankFixedEntry(bank, entryId)
    entryId = tostring(entryId or "")
    for i = 1, #(bank.fixed or {}) do
        if tostring(bank.fixed[i].id or "") == entryId then
            return bank.fixed[i], i
        end
    end
    return nil
end

function bankFixedInterest(entry)
    if not entry then return 0 end
    return math.max(0, math.floor((tonumber(entry.principal) or 0) * (tonumber(entry.rate) or 0)))
end

function bankFixedPayout(entry)
    if not entry then return 0, 0, false end
    local principal = math.max(0, floor(entry.principal, 0))
    if nowHours() >= n(entry.matureHour, 0) then
        local interest = bankFixedInterest(entry)
        return principal + interest, interest, true
    end
    local penalty = math.max(0, math.floor(principal * (GodSystemConfig.BankEarlyWithdrawPenaltyRatio or 0.05)))
    return math.max(0, principal - penalty), -penalty, false
end

function bankInvestmentProfiles()
    local profiles = GodSystemConfig.BankInvestmentProfiles or {}
    local result = {}
    for i = 1, #BANK_INVESTMENT_IDS do
        local tierId = BANK_INVESTMENT_IDS[i]
        local profile = profiles[tierId] or {}
        local gainChance = math.max(0, math.min(100, floor(profile.gainChance, 0)))
        result[#result + 1] = {
            id = tierId,
            gainChance = gainChance,
            lossChance = math.max(0, math.min(100 - gainChance, floor(profile.lossChance, 0))),
            gainPercent = math.max(0, n(profile.gainPercent, 0)),
            lossPercent = math.max(0, n(profile.lossPercent, 0)),
        }
    end
    return result
end

function bankInvestmentProfile(tierId)
    tierId = tostring(tierId or "")
    local profiles = bankInvestmentProfiles()
    for i = 1, #profiles do
        if profiles[i].id == tierId then return profiles[i] end
    end
    return nil
end

function bankInvestmentMinimum()
    return math.max(1, floor(GodSystemConfig.BankInvestmentMinAmount, 1))
end

function prepareBankInvestment(data, tierId, amount)
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableBankInvestments") == false then
        return nil, nil, nil, "BankInvestmentDisabled", {}
    end
    local profile = bankInvestmentProfile(tierId)
    amount = math.max(0, floor(amount, 0))
    local minimum = bankInvestmentMinimum()
    if not profile then return nil, nil, nil, "BankInvestmentSelect", {} end
    if amount < minimum then return nil, nil, nil, "BankInvestmentMinimum", { minimum } end
    local bank = getBank(data)
    return profile, bank.investments[profile.id], amount, nil, nil
end

function addBankInvestment(data, bank, profile, account, amount, source)
    if (account.balance or 0) <= 0 then
        account.balance = 0
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    account.balance = (account.balance or 0) + amount
    data.stats.bankInvestmentDeposited = (data.stats.bankInvestmentDeposited or 0) + amount
    appendHistory(data, historyEntry("bank", "BankInvestmentCreated", { profile.id, amount, source }))
    return true, "BankInvestmentCreated", { profile.id, amount }
end

function investBankCurrent(data, tierId, amount)
    local profile, account, cleanAmount, code, args = prepareBankInvestment(data, tierId, amount)
    if not profile then return false, code, args end
    local bank = getBank(data)
    if (bank.current or 0) < cleanAmount then return false, "BankCurrentNotEnough", {} end
    bank.current = (bank.current or 0) - cleanAmount
    return addBankInvestment(data, bank, profile, account, cleanAmount, "current")
end

function investBankCash(player, data, tierId, amount)
    local profile, account, cleanAmount, code, args = prepareBankInvestment(data, tierId, amount)
    if not profile then return false, code, args end
    if not removeCurrency(player, cleanAmount) then return false, "CurrencyNotEnough", {} end
    return addBankInvestment(data, getBank(data), profile, account, cleanAmount, "cash")
end

function redeemBankInvestment(data, tierId, amount)
    local profile = bankInvestmentProfile(tierId)
    local bank = getBank(data)
    local account = profile and bank.investments[profile.id] or nil
    amount = math.max(1, floor(amount, 0))
    if not profile or not account or (account.balance or 0) <= 0 then return false, "BankInvestmentSelect", {} end
    if account.redeemUnlocked ~= true then return false, "BankInvestmentLocked", {} end
    if amount > (account.balance or 0) then return false, "BankInvestmentBalanceLow", {} end
    account.balance = math.max(0, (account.balance or 0) - amount)
    bank.current = (bank.current or 0) + amount
    data.stats.bankInvestmentRedeemed = (data.stats.bankInvestmentRedeemed or 0) + amount
    appendHistory(data, historyEntry("bank", "BankInvestmentRedeemed", { profile.id, amount }))
    if account.balance <= 0 then
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    return true, "BankInvestmentRedeemed", { profile.id, amount }
end

function settleBankInvestmentAccount(account, profile, nowHour)
    local before = math.max(0, floor(account.balance, 0))
    if before <= 0 then return 0, "flat", before end
    local roll = randomIndex(100)
    local delta = 0
    local outcome = "flat"
    if roll <= (profile.gainChance or 0) then
        local percent = math.max(0, n(profile.gainPercent, 0))
        if percent > 0 then
            delta = math.max(1, math.floor(before * percent / 100))
            account.balance = before + delta
            outcome = "gain"
        end
    elseif roll > 100 - (profile.lossChance or 0) then
        local percent = math.max(0, n(profile.lossPercent, 0))
        if percent > 0 then
            local loss = math.max(1, math.floor(before * percent / 100))
            loss = math.min(before, loss)
            delta = -loss
            account.balance = before - loss
            outcome = "loss"
        end
    end
    account.redeemUnlocked = true
    account.settlementCount = (account.settlementCount or 0) + 1
    account.lastDelta = delta
    account.lastOutcome = outcome
    account.lastSettledHour = nowHour
    return delta, outcome, before
end

function applyBankInvestmentElapsed(data, elapsedHours)
    elapsedHours = math.max(0, floor(elapsedHours, 0))
    if elapsedHours <= 0 or GodSystemRuntimeConfig.isFeatureEnabled("EnableBankInvestments") == false then
        return 0, 0
    end
    local bank = getBank(data)
    local profiles = bankInvestmentProfiles()
    local settlementHours = math.max(1, n(GodSystemConfig.BankInvestmentSettlementHours, 24))
    local settledCount = 0
    local totalDelta = 0
    local nowHour = nowHours()
    for i = 1, #profiles do
        local profile = profiles[i]
        local account = bank.investments[profile.id]
        if account and (account.balance or 0) > 0 then
            account.onlineHours = math.max(0, n(account.onlineHours, 0)) + elapsedHours
            while account.onlineHours >= settlementHours and (account.balance or 0) > 0 do
                account.onlineHours = account.onlineHours - settlementHours
                local delta, _, before = settleBankInvestmentAccount(account, profile, nowHour)
                totalDelta = totalDelta + delta
                settledCount = settledCount + 1
                if delta > 0 then
                    data.stats.bankInvestmentProfit = (data.stats.bankInvestmentProfit or 0) + delta
                elseif delta < 0 then
                    data.stats.bankInvestmentLoss = (data.stats.bankInvestmentLoss or 0) + math.abs(delta)
                end
                appendHistory(data, historyEntry("bank", "BankInvestmentSettled", { profile.id, before, delta, account.balance }))
            end
        end
    end
    return settledCount, totalDelta
end

function getBankLoanPlans()
    local plans = {
        {
            id = "single",
            kind = "single",
            periods = 1,
            dueHours = math.max(1, floor(GodSystemConfig.BankLoanSingleDueHours, 72)),
            totalInterestRate = n(GodSystemConfig.BankLoanSingleInterestRate, 0.05),
        },
    }
    local periodHours = math.max(1, floor(GodSystemConfig.BankLoanPeriodHours, 72))
    for i = 1, #(GodSystemConfig.BankLoanInstallmentPlans or {}) do
        local row = GodSystemConfig.BankLoanInstallmentPlans[i]
        local periods = math.max(1, floor(row.periods, 1))
        plans[#plans + 1] = {
            id = tostring(row.id or ("i" .. tostring(periods))),
            kind = "installment",
            periods = periods,
            dueHours = periodHours,
            totalInterestRate = n(row.totalInterestRate, 0),
        }
    end
    return plans
end

function bankLoanPlan(planId)
    planId = tostring(planId or "single")
    local plans = getBankLoanPlans()
    for i = 1, #plans do
        if tostring(plans[i].id or "") == planId then return plans[i] end
    end
    return nil
end

function bankLoanUnpaidPrincipal(loan)
    local total = 0
    if not loan or type(loan.schedule) ~= "table" then return 0 end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local partTotal = math.max(0, floor((bill.principalPart or 0) + (bill.interestPart or 0), 0))
        local paid = math.max(0, floor(bill.paid, 0))
        local principal = math.max(0, floor(bill.principalPart, 0))
        if partTotal > 0 and paid < partTotal then
            local principalPaid = math.min(principal, paid)
            total = total + math.max(0, principal - principalPaid)
        end
    end
    return total
end

function bankLoanAmounts(loan, now)
    now = n(now, nowHours())
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
    if not loan or type(loan.schedule) ~= "table" then return result end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local principal = math.max(0, floor(bill.principalPart, 0))
        local interest = math.max(0, floor(bill.interestPart, 0))
        local total = principal + interest
        local paid = math.max(0, floor(bill.paid, 0))
        if total > paid then
            local remaining = total - paid
            local principalPaid = math.min(principal, paid)
            local interestPaid = math.max(0, paid - principal)
            local principalLeft = math.max(0, principal - principalPaid)
            local interestLeft = math.max(0, interest - interestPaid)
            result.unpaidPrincipal = result.unpaidPrincipal + principalLeft
            result.unpaidInterest = result.unpaidInterest + interestLeft
            result.unpaidTotal = result.unpaidTotal + remaining
            local dueHour = n(bill.dueHour, now)
            if now >= dueHour then
                result.due = result.due + remaining
                if not result.overdueStartHour or dueHour < result.overdueStartHour then
                    result.overdueStartHour = dueHour
                end
            else
                result.futurePrincipal = result.futurePrincipal + principalLeft
                result.futureInterest = result.futureInterest + interestLeft
                if not result.nextDueHour or dueHour < result.nextDueHour then
                    result.nextDueHour = dueHour
                end
            end
        end
    end
    return result
end

function refreshBankLoanStatus(loan, now)
    if not loan then return bankLoanAmounts(nil, now) end
    local amounts = bankLoanAmounts(loan, now)
    loan.overdueStartHour = amounts.overdueStartHour
    return amounts
end

function bankLoanOverduePenalty(loan, now, amounts)
    amounts = amounts or refreshBankLoanStatus(loan, now)
    if not loan or not amounts.overdueStartHour then return 0 end
    now = n(now, nowHours())
    local overdueDays = math.max(0, math.floor((now - amounts.overdueStartHour) / 24))
    if overdueDays <= 0 then return 0 end
    local principal = math.max(0, floor(loan.principal, 0))
    local dailyRate = n(GodSystemConfig.BankLoanOverduePenaltyDailyRate, 0.05)
    local maxRate = n(GodSystemConfig.BankLoanOverduePenaltyMaxRate, 0.5)
    return math.max(0, math.floor(math.min(principal * maxRate, principal * dailyRate * overdueDays)))
end

function bankLoanCredit(data, bank)
    bank = bank or getBank(data)
    local base = math.max(0, floor(GodSystemConfig.BankLoanBaseCredit, 2000))
    local step = math.max(1, floor(GodSystemConfig.BankLoanCreditSpendStep, 100))
    local perStep = math.max(0, floor(GodSystemConfig.BankLoanCreditPerStep, 5))
    local spent = math.max(0, floor(data.stats and data.stats.spentPoints, 0))
    local offset = math.max(0, floor(bank.loanCreditSpentOffset, 0))
    local growth = math.floor(math.max(0, spent - offset) / step) * perStep
    local total = base + growth
    local used = bankLoanUnpaidPrincipal(bank.loan)
    return total, math.max(0, total - used), growth, used
end

function createBankLoanSchedule(plan, amount, now)
    local schedule = {}
    local periods = math.max(1, floor(plan.periods, 1))
    local totalInterest = math.max(0, math.floor(amount * n(plan.totalInterestRate, 0)))
    local principalLeft = amount
    local interestLeft = totalInterest
    for i = 1, periods do
        local principalPart = (i == periods) and principalLeft or math.floor(amount / periods)
        local interestPart = (i == periods) and interestLeft or math.floor(totalInterest / periods)
        principalLeft = principalLeft - principalPart
        interestLeft = interestLeft - interestPart
        schedule[#schedule + 1] = {
            index = i,
            dueHour = now + math.max(1, floor(plan.dueHours, 72)) * i,
            principalPart = principalPart,
            interestPart = interestPart,
            paid = 0,
        }
    end
    return schedule, totalInterest
end

function applyBankLoanPayment(loan, amount, now, includeFuture)
    amount = math.max(0, floor(amount, 0))
    local paid = 0
    if not loan or amount <= 0 then return 0 end
    now = n(now, nowHours())
    for i = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[i]
        local total = math.max(0, floor((bill.principalPart or 0) + (bill.interestPart or 0), 0))
        local billPaid = math.max(0, floor(bill.paid, 0))
        if total > billPaid and (includeFuture or now >= n(bill.dueHour, now)) then
            local add = math.min(amount, total - billPaid)
            bill.paid = billPaid + add
            loan.paid = math.max(0, floor(loan.paid, 0)) + add
            amount = amount - add
            paid = paid + add
            if amount <= 0 then break end
        end
    end
    return paid
end

function spawnBankLoanDebtZombies(player, count)
    count = math.max(0, floor(count, 0))
    if count <= 0 or not addZombiesInOutfit then return 0 end
    if not player or not player.getX then return 0 end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local minDist = math.max(1, floor(GodSystemConfig.BankLoanZombieMinDistance, 20))
    local maxDist = math.max(minDist, floor(GodSystemConfig.BankLoanZombieMaxDistance, 45))
    local spawned = 0
    local tries = 0
    while spawned < count and tries < count * 8 do
        tries = tries + 1
        local dist = minDist + randomIndex(math.max(1, maxDist - minDist + 1)) - 1
        local dx = randomIndex(dist * 2 + 1) - dist - 1
        local dySign = randomIndex(2) == 1 and -1 or 1
        local dy = dySign * math.max(minDist, dist - math.abs(dx))
        local batch = math.min(10, count - spawned)
        local ok = pcall(addZombiesInOutfit, math.floor(px + dx), math.floor(py + dy), pz, batch, nil, nil)
        if ok then spawned = spawned + batch end
    end
    return spawned
end

function applyBankLoanBankruptcy(player, data, bank, loan, debt)
    bank = bank or getBank(data)
    loan = loan or bank.loan
    if not loan then return false, 0 end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    debt = math.max(0, floor(debt or (amounts.unpaidTotal + bankLoanOverduePenalty(loan, now, amounts)), 0))
    local perZombie = math.max(1, floor(GodSystemConfig.BankLoanZombieDebtPerZombie, 50))
    local maxZombies = math.max(0, floor(GodSystemConfig.BankLoanZombieMaxCount, 100))
    local zombieCount = math.min(maxZombies, math.max(1, math.floor(debt / perZombie)))
    local cash = math.max(0, getBalance(player))
    if cash > 0 then removeCurrency(player, cash) end
    bank.loan = nil
    bank.current = 0
    bank.loanFrozenUntilHour = now + math.max(0, floor(GodSystemConfig.BankLoanFreezeHours, 168))
    bank.loanCreditSpentOffset = math.max(0, floor(data.stats and data.stats.spentPoints, 0))
    bank.loanBankruptcyCount = math.max(0, floor(bank.loanBankruptcyCount, 0)) + 1
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + debt
    local spawned = spawnBankLoanDebtZombies(player, zombieCount)
    appendHistory(data, historyEntry("bank", "BankLoanBankruptcy", { debt, spawned }))
    notifyCode(player, "BankLoanBankruptcy", { spawned })
    return true, spawned
end

function getBankLoanSummary(data)
    local bank = getBank(data)
    local now = nowHours()
    local loan = bank.loan
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local total, available, growth, used = bankLoanCredit(data, bank)
    local graceHours = math.max(1, floor(GodSystemConfig.BankLoanBankruptcyGraceHours, 240))
    return {
        creditTotal = total,
        creditAvailable = available,
        creditGrowth = growth,
        creditUsed = used,
        loan = loan,
        dueNow = amounts.due + penalty,
        dueBase = amounts.due,
        overduePenalty = penalty,
        payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5),
        unpaidTotal = amounts.unpaidTotal + penalty,
        nextDueHour = amounts.nextDueHour,
        overdueStartHour = amounts.overdueStartHour,
        freezeLeftHours = math.max(0, math.ceil((bank.loanFrozenUntilHour or 0) - now)),
        bankruptcyInHours = amounts.overdueStartHour and math.max(0, math.ceil(graceHours - (now - amounts.overdueStartHour))) or nil,
    }
end

function updateBankLoanForData(player, data)
    local bank = getBank(data)
    local loan = bank.loan
    if not loan then return false end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local graceHours = math.max(1, floor(GodSystemConfig.BankLoanBankruptcyGraceHours, 240))
    if amounts.overdueStartHour and now - amounts.overdueStartHour >= graceHours then
        local penalty = bankLoanOverduePenalty(loan, now, amounts)
        applyBankLoanBankruptcy(player, data, bank, loan, amounts.unpaidTotal + penalty)
        return true
    end
    return false
end

function borrowBankLoan(player, data, bank, planId, amount)
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableBankLoan") == false then return false, "Loan disabled" end
    amount = math.max(1, floor(amount, 0))
    local plan = bankLoanPlan(planId)
    if not plan then return false, "Loan plan missing" end
    updateBankLoanForData(player, data)
    bank = getBank(data)
    if bank.loan then return false, "已有未结清贷款" end
    local now = nowHours()
    if n(bank.loanFrozenUntilHour, 0) > now then return false, "贷款功能冻结中" end
    local _, available = bankLoanCredit(data, bank)
    if amount > available then return false, "可借额度不足" end
    local schedule, totalInterest = createBankLoanSchedule(plan, amount, now)
    local id = "L" .. tostring(bank.nextLoanId or 1)
    bank.nextLoanId = (bank.nextLoanId or 1) + 1
    bank.loan = {
        id = id,
        kind = plan.kind,
        planId = plan.id,
        principal = amount,
        createdHour = now,
        totalInterest = totalInterest,
        totalDue = amount + totalInterest,
        paid = 0,
        schedule = schedule,
    }
    bank.current = (bank.current or 0) + amount
    appendHistory(data, historyEntry("bank", "BankLoanBorrowed", { amount }))
    return true, "借款已到账活期"
end

function repayBankLoanDue(player, data, bank)
    updateBankLoanForData(player, data)
    bank = getBank(data)
    local loan = bank.loan
    if not loan then return false, "没有未结清贷款" end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local due = amounts.due + penalty
    if due <= 0 then return false, "当前没有到期账单" end
    if (bank.current or 0) < due then return false, "活期余额不足" end
    bank.current = (bank.current or 0) - due
    applyBankLoanPayment(loan, amounts.due, now, false)
    if penalty > 0 then data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty end
    if (loan.paid or 0) >= (loan.totalDue or 0) then
        bank.loan = nil
    else
        refreshBankLoanStatus(loan, now)
    end
    appendHistory(data, historyEntry("bank", "BankLoanRepaid", { due }))
    return true, "贷款已还款"
end

function payoffBankLoan(player, data, bank)
    updateBankLoanForData(player, data)
    bank = getBank(data)
    local loan = bank.loan
    if not loan then return false, "没有未结清贷款" end
    local now = nowHours()
    local amounts = refreshBankLoanStatus(loan, now)
    local penalty = bankLoanOverduePenalty(loan, now, amounts)
    local payoff = math.max(0, floor(amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5), 0))
    if payoff <= 0 then
        bank.loan = nil
        return true, "贷款已提前结清"
    end
    if (bank.current or 0) < payoff then return false, "活期余额不足" end
    bank.current = (bank.current or 0) - payoff
    bank.loan = nil
    if penalty > 0 then data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty end
    appendHistory(data, historyEntry("bank", "BankLoanPayoff", { payoff }))
    return true, "贷款已提前结清"
end

function applyBankDeathPenalty(data)
    local bank = getBank(data)
    local now = nowHours()
    if now - (bank.lastDeathPenaltyHour or -999) < 0.1 then
        return 0
    end
    bank.lastDeathPenaltyHour = now
    local penalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    if penalty <= 0 then return 0 end
    bank.current = math.max(0, (bank.current or 0) - penalty)
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    appendHistory(data, historyEntry("bank", "BankDeathPenalty", { penalty }))
    return penalty
end

function payTaskFailurePenalty(player, data, amount)
    amount = math.max(0, floor(amount, 0))
    if amount <= 0 then return 0, 0, 0 end
    local bank = getBank(data)
    local fromBank = math.min(bank.current or 0, amount)
    if fromBank > 0 then
        bank.current = math.max(0, (bank.current or 0) - fromBank)
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + fromBank
    end
    local remaining = amount - fromBank
    local fromCash = 0
    if remaining > 0 then
        fromCash = math.min(getBalance(player), remaining)
        if fromCash > 0 and not removeCurrency(player, fromCash) then
            fromCash = 0
        end
    end
    return fromBank + fromCash, fromBank, fromCash
end

function failTask(player, data, task, historyCode)
    if not task or task.status ~= "active" then return false end
    task.status = "failed"
    task.failedAt = nowHours()
    data.stats.failedTasks = (data.stats.failedTasks or 0) + 1
    local paid, fromBank, fromCash = payTaskFailurePenalty(player, data, task.penaltyPoints or 0)
    appendHistory(data, taskHistoryEntry(historyCode or "TaskFailed", task, { paid, task.penaltyPoints or 0, fromBank, fromCash }))
    return true
end

function failActiveTasksOnDeath(player, data)
    local failed = 0
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task and task.status == "active" then
            failTask(player, data, task, "TaskDeathFailed")
            failed = failed + 1
        end
    end
    return failed
end
end
