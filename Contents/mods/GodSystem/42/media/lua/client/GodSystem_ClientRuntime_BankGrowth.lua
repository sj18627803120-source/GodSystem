_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_BankGrowth"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_BankGrowth then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_BankGrowth = true
    setfenv(1, runtimeEnvironment)

function GodSystemApp.services.runtime.getSystemUpgradeInfo(upgradeType)
    local data = GodSystemApp.services.runtime.getData()
    data.upgrades = data.upgrades or {}
    if upgradeType == "activeTasks" then
        local current = GodSystemApp.services.runtime.getMaxActiveTasks()
        local maxValue = GodSystemConfig.MaxActiveTaskLimit or 10
        local nextValue = math.min(maxValue, current + 1)
        local cost = nil
        if current < maxValue then
            cost = (GodSystemConfig.ActiveTaskUpgradeCosts or {})[nextValue] or (nextValue * 120)
        end
        return {
            upgradeType = upgradeType,
            current = current,
            nextValue = nextValue,
            maxValue = maxValue,
            cost = cost,
            label = GodSystemApp.services.runtime.text("Upgrade_ActiveTasks", "Active task slots"),
            desc = GodSystemApp.services.runtime.text("Upgrade_ActiveTasksDesc", "Increase the maximum number of active tasks by 1."),
        }
    end
    if upgradeType == "dailyTasks" then
        local current = GodSystemApp.services.runtime.getDailyTaskCount()
        local maxValue = GodSystemConfig.MaxDailyTaskLimit or 20
        local nextValue = math.min(maxValue, current + 1)
        local cost = nil
        if current < maxValue then
            cost = (GodSystemConfig.DailyTaskUpgradeCosts or {})[nextValue] or (nextValue * 30)
        end
        return {
            upgradeType = upgradeType,
            current = current,
            nextValue = nextValue,
            maxValue = maxValue,
            cost = cost,
            label = GodSystemApp.services.runtime.text("Upgrade_DailyTasks", "Daily task display"),
            desc = GodSystemApp.services.runtime.text("Upgrade_DailyTasksDesc", "Increase the number of tasks generated each day by 1. Adds one open task immediately."),
        }
    end
    if upgradeType == "carryCapacity" then
        local level = GodSystemApp.services.runtime.getCarryCapacityLevel()
        local cost = GodSystemCarryCapacity.getNextCost(level)
        local status = GodSystemCarryCapacity.getStatus(gsPlayer(), level)
        return {
            upgradeType = upgradeType,
            current = level,
            nextValue = level + 1,
            maxValue = nil,
            cost = cost,
            label = GodSystemApp.services.runtime.text("Upgrade_CarryCapacity", "Carry capacity"),
            desc = GodSystemApp.services.runtime.text("Upgrade_CarryCapacityDesc", "Each level adds 2 to the protocol carry base. Use Carry restore after another MOD changes the base."),
            carryStatus = status,
        }
    end
    return nil
end

function GodSystemApp.services.runtime.getSystemUpgradeDetailText(upgradeType)
    local info = GodSystemApp.services.runtime.getSystemUpgradeInfo(upgradeType)
    if not info then
        return ""
    end
    if upgradeType == "carryCapacity" then
        local status = info.carryStatus or {}
        local externalBase = status.externalBase ~= nil and tostring(status.externalBase) or "?"
        local writtenBase = status.currentBase ~= nil and tostring(status.currentBase) or "?"
        local finalCarry = status.finalCarry ~= nil and tostring(status.finalCarry) or "?"
        local bonus = tonumber(status.bonus) or 0
        local bonusText = bonus >= 0 and ("+" .. tostring(bonus)) or tostring(bonus)
        local costText = info.cost and (tostring(info.cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")) or GodSystemApp.services.runtime.text("Upgrade_CostOverflow", "Unavailable")
        return tostring(info.desc or "")
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryProtocolBonus", "Protocol base bonus") .. " " .. bonusText
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryExternalBase", "External base") .. " " .. externalBase
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryWrittenBase", "Written base") .. " " .. writtenBase
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryGameFinal", "Game final carry") .. " " .. finalCarry
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Level", "Level") .. " " .. tostring(info.current)
            .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Cost", "Cost") .. " " .. costText
    end
    local nextText = info.cost and (tostring(info.current) .. " -> " .. tostring(info.nextValue)) or tostring(info.current)
    local costText = info.cost and (tostring(info.cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")) or GodSystemApp.services.runtime.text("Upgrade_Maxed", "Maxed")
    local detail = tostring(info.desc or "") .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Current", "Current") .. " " .. tostring(info.current) .. "/" .. tostring(info.maxValue) .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Next", "Next") .. " " .. nextText .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Cost", "Cost") .. " " .. costText
    return detail
end

function GodSystemApp.services.runtime.upgradeSystem(upgradeType)
    local info = GodSystemApp.services.runtime.getSystemUpgradeInfo(upgradeType)
    if not info then
        return false
    end
    if not info.cost then
        if upgradeType == "carryCapacity" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CarryCapacityCostOverflow", "The next cost exceeds the safe numeric range"))
        else
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_UpgradeMaxed", "Already at max level"))
        end
        return false
    end
    if not GodSystemApp.services.runtime.canAfford(info.cost) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    if upgradeType == "carryCapacity" then
        local player = gsPlayer()
        local data = GodSystemApp.services.runtime.getData()
        local previousLevel = GodSystemApp.services.runtime.getCarryCapacityLevel()
        local nextLevel = previousLevel + 1
        local applied, applyResult = GodSystemCarryCapacity.restore(player, nextLevel)
        if not applied then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CarryCapacityApplyFailed", "Carry capacity upgrade could not be applied") .. " (" .. tostring(applyResult or "unknown") .. ")")
            return false
        end
        if not GodSystemApp.services.runtime.addPoints(-info.cost) then
            GodSystemCarryCapacity.restore(player, previousLevel)
            return false
        end
        data.upgrades = data.upgrades or {}
        data.upgrades.carryCapacityLevel = nextLevel
        data.stats = data.stats or {}
        data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
        local protocolBonus = tonumber(applyResult and applyResult.bonus) or 0
        local writtenBase = applyResult and applyResult.currentBase or "?"
        gsAppendHistory(data, {
            kind = "upgrade",
            text = gsFormatText(GodSystemApp.services.runtime.text("History_CarryCapacityUpgrade", "Carry capacity upgraded to Lv.{1}; protocol base bonus {2}; written base {3}; cost {4}"), {
                nextLevel,
                protocolBonus,
                writtenBase,
                info.cost,
            }),
        })
        GodSystemApp.services.runtime.save()
        GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_CarryCapacityUpgraded", "Carry capacity upgraded to Lv.{1}; protocol base bonus {2}; written base {3}"), {
            nextLevel,
            protocolBonus,
            writtenBase,
        }))
        return true
    end
    if not GodSystemApp.services.runtime.addPoints(-info.cost) then
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    data.upgrades = data.upgrades or {}
    if upgradeType == "activeTasks" then
        data.upgrades.maxActiveTasks = info.nextValue
    elseif upgradeType == "dailyTasks" then
        data.upgrades.dailyTaskCount = info.nextValue
        local templates = GodSystemApp.services.runtime.getAvailableTaskTemplates()
        if #templates > 0 then
            data.tasks = data.tasks or {}
            table.insert(data.tasks, GodSystemApp.services.runtime.generateTaskFromTemplate(templates[gsRandomIndex(#templates)]))
        end
    end
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + info.cost
    gsAppendHistory(data, { kind = "upgrade", text = GodSystemApp.services.runtime.text("History_SystemUpgrade", "System upgrade: ") .. tostring(info.label) .. " " .. tostring(info.current) .. " -> " .. tostring(info.nextValue) .. " -" .. tostring(info.cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SystemUpgrade", "System upgraded: ") .. tostring(info.label) .. " " .. tostring(info.nextValue))
    return true
end

function GodSystemApp.services.runtime.getBank()
    local data = GodSystemApp.services.runtime.getData()
    data.bank = data.bank or {}
    data.bank.current = math.max(0, math.floor(tonumber(data.bank.current) or 0))
    data.bank.fixed = data.bank.fixed or {}
    data.bank.nextId = math.max(1, math.floor(tonumber(data.bank.nextId) or 1))
    data.bank.lastDeathPenaltyHour = tonumber(data.bank.lastDeathPenaltyHour) or -999
    data.bank.nextLoanId = math.max(1, math.floor(tonumber(data.bank.nextLoanId) or 1))
    data.bank.loanFrozenUntilHour = tonumber(data.bank.loanFrozenUntilHour) or 0
    data.bank.loanCreditSpentOffset = math.max(0, math.floor(tonumber(data.bank.loanCreditSpentOffset) or 0))
    data.bank.loanBankruptcyCount = math.max(0, math.floor(tonumber(data.bank.loanBankruptcyCount) or 0))
    data.bank.autoDepositEnabled = data.bank.autoDepositEnabled == true
    data.bank.lastAutoDepositHour = tonumber(data.bank.lastAutoDepositHour) or gsNowHours()
    gsNormalizeBankInvestments(data.bank)
    local now = gsNowHours()
    for i = #data.bank.fixed, 1, -1 do
        local entry = data.bank.fixed[i]
        if not entry or math.max(0, math.floor(tonumber(entry.principal) or 0)) <= 0 then
            table.remove(data.bank.fixed, i)
        else
            entry.id = tostring(entry.id or ("F" .. tostring(i)))
            entry.termId = tostring(entry.termId or "")
            entry.principal = math.max(0, math.floor(tonumber(entry.principal) or 0))
            entry.startHour = tonumber(entry.startHour) or now
            entry.matureHour = tonumber(entry.matureHour) or entry.startHour
            entry.rate = tonumber(entry.rate) or 0
            entry.days = math.max(1, math.floor(tonumber(entry.days) or math.max(1, math.ceil((entry.matureHour - entry.startHour) / 24))))
        end
    end
    if type(data.bank.loan) == "table" then
        local loan = data.bank.loan
        loan.id = tostring(loan.id or ("L" .. tostring(data.bank.nextLoanId or 1)))
        loan.kind = tostring(loan.kind or "single")
        loan.planId = tostring(loan.planId or loan.kind or "single")
        loan.principal = math.max(0, math.floor(tonumber(loan.principal) or 0))
        loan.createdHour = tonumber(loan.createdHour) or now
        loan.totalInterest = math.max(0, math.floor(tonumber(loan.totalInterest) or 0))
        loan.totalDue = math.max(loan.principal + loan.totalInterest, math.floor(tonumber(loan.totalDue) or 0))
        loan.paid = math.max(0, math.floor(tonumber(loan.paid) or 0))
        loan.schedule = type(loan.schedule) == "table" and loan.schedule or {}
        loan.overdueStartHour = tonumber(loan.overdueStartHour)
        for i = #loan.schedule, 1, -1 do
            local bill = loan.schedule[i]
            if type(bill) ~= "table" then
                table.remove(loan.schedule, i)
            else
                bill.index = math.max(1, math.floor(tonumber(bill.index) or i))
                bill.dueHour = tonumber(bill.dueHour) or loan.createdHour
                bill.principalPart = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
                bill.interestPart = math.max(0, math.floor(tonumber(bill.interestPart) or 0))
                bill.paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
            end
        end
        if loan.principal <= 0 or loan.totalDue <= 0 or loan.paid >= loan.totalDue then
            data.bank.loan = nil
        end
    else
        data.bank.loan = nil
    end
    return data.bank
end

function GodSystemApp.services.runtime.getSpendableBalance()
    local bank = GodSystemApp.services.runtime.getBank()
    return math.max(0, math.floor(tonumber(bank.current) or 0)) + math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0))
end

function GodSystemApp.services.runtime.spendCurrency(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return true, 0, 0
    end
    local bank = GodSystemApp.services.runtime.getBank()
    local cash = math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0))
    local current = math.max(0, math.floor(tonumber(bank.current) or 0))
    if current + cash < amount then
        return false, 0, 0
    end
    local fromBank = math.min(current, amount)
    if fromBank > 0 then
        bank.current = math.max(0, current - fromBank)
    end
    local fromCash = amount - fromBank
    if fromCash > 0 and not GodSystemApp.services.runtime.removeCurrency(fromCash) then
        if fromBank > 0 then
            bank.current = (bank.current or 0) + fromBank
        end
        return false, 0, 0
    end
    return true, fromBank, fromCash
end

function GodSystemApp.services.runtime.refundCurrencySources(fromBank, fromCash)
    local bank = GodSystemApp.services.runtime.getBank()
    local bankAmount = math.max(0, math.floor(tonumber(fromBank) or 0))
    local cashAmount = math.max(0, math.floor(tonumber(fromCash) or 0))
    bank.current = (bank.current or 0) + bankAmount
    if cashAmount <= 0 then return true end
    if GodSystemApp.services.runtime.giveCurrency(cashAmount) then return true end
    bank.current = (bank.current or 0) + cashAmount
    return false
end

function GodSystemApp.services.runtime.restoreRemovedCurrencyOrBank(removed)
    local ok, failedValue = gsRestoreRemovedCurrency(removed)
    if failedValue > 0 then
        local bank = GodSystemApp.services.runtime.getBank()
        bank.current = (bank.current or 0) + failedValue
    end
    return ok, failedValue
end

function GodSystemApp.services.runtime.getCompanionData()
    local data = GodSystemApp.services.runtime.getData()
    data.companion = GodSystemCompanionConfig.ensureData(data.companion)
    return data.companion
end

function gsCompanionPurchaseFailed(key, fallback)
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(key, fallback))
    return false
end

function GodSystemApp.services.runtime.purchaseCompanionNode(nodeId)
    if (isClient and isClient()) or (isServer and isServer()) then return false end
    if not GodSystemCompanionConfig.isEnabled() then
        return gsCompanionPurchaseFailed("Notify_CompanionDisabled", "Companion system is disabled")
    end

    nodeId = tostring(nodeId or "")
    local data = GodSystemApp.services.runtime.getData()
    local companion = GodSystemApp.services.runtime.getCompanionData()
    local cost = nil
    local apply = nil

    local unlock = GodSystemCompanionConfig.Unlocks[nodeId]
    if unlock then
        if GodSystemCompanionConfig.isUnlocked(companion, nodeId) then
            return gsCompanionPurchaseFailed("Notify_CompanionAlreadyUnlocked", "Already unlocked")
        end
        if unlock.requires and not GodSystemCompanionConfig.isUnlocked(companion, unlock.requires) then
            return gsCompanionPurchaseFailed("Notify_CompanionRequiresProjection", "Unlock the projection first")
        end
        cost = GodSystemCompanionConfig.scaleCost(unlock.cost)
        apply = function()
            if nodeId == "projection" then companion.unlocked = true else companion.unlocks[nodeId] = true end
        end
    elseif GodSystemCompanionConfig.Stats[nodeId] then
        local definition = GodSystemCompanionConfig.Stats[nodeId]
        if not GodSystemCompanionConfig.isUnlocked(companion, definition.requires) then
            return gsCompanionPurchaseFailed("Notify_CompanionAbilityLocked", "Required ability is locked")
        end
        cost = GodSystemCompanionConfig.getUpgradeCost(companion, nodeId)
        if not cost then
            return gsCompanionPurchaseFailed("Notify_CompanionMaxLevel", "Already at maximum level")
        end
        apply = function() companion.levels[nodeId] = companion.levels[nodeId] + 1 end
    elseif GodSystemCompanionConfig.Effects[nodeId] then
        if not companion.unlocks.attack then
            return gsCompanionPurchaseFailed("Notify_CompanionAbilityLocked", "Required ability is locked")
        end
        if GodSystemCompanionConfig.isEffectUnlocked(companion, nodeId) then
            return gsCompanionPurchaseFailed("Notify_CompanionAlreadyUnlocked", "Already unlocked")
        end
        cost = GodSystemCompanionConfig.getEffectCost(companion, nodeId)
        if not cost then
            return gsCompanionPurchaseFailed("Notify_CompanionEffectOrder", "Unlock the previous attack effect first")
        end
        apply = function() companion.effects[nodeId] = true end
    elseif nodeId == "resonance" then
        if not GodSystemCompanionConfig.canPurchaseResonance(companion) then
            return gsCompanionPurchaseFailed("Notify_CompanionResonanceLocked", "Max all functional upgrades and unlock every attack effect first")
        end
        cost = GodSystemCompanionConfig.getResonanceCost(companion)
        apply = function() companion.resonance = companion.resonance + 1 end
    else
        return false
    end

    local paid = GodSystemApp.services.runtime.spendCurrency(cost)
    if not paid then
        return gsCompanionPurchaseFailed("Notify_CurrencyNotEnough", "Not enough currency")
    end
    apply()
    data.stats.spentPoints = (data.stats.spentPoints or 0) + cost
    gsAppendHistory(data, {
        kind = "system",
        text = GodSystemApp.services.runtime.text("History_CompanionUpgrade", "Companion upgrade") .. " " .. nodeId .. " -" .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"),
    })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CompanionUpgradeSuccess", "Companion upgraded"))
    return true
end

function GodSystemApp.services.runtime.getBankFixedEntry(entryId)
    entryId = tostring(entryId or "")
    local bank = GodSystemApp.services.runtime.getBank()
    for i = 1, #(bank.fixed or {}) do
        if tostring(bank.fixed[i].id or "") == entryId then
            return bank.fixed[i], i
        end
    end
    return nil
end

function GodSystemApp.services.runtime.getBankFixedInterest(entry)
    if not entry then return 0 end
    return math.max(0, math.floor((tonumber(entry.principal) or 0) * (tonumber(entry.rate) or 0)))
end

function GodSystemApp.services.runtime.isBankFixedMature(entry)
    if not entry then return false end
    return gsNowHours() >= (tonumber(entry.matureHour) or 0)
end

function GodSystemApp.services.runtime.getBankFixedPayout(entry)
    if not entry then return 0, 0, false end
    local principal = math.max(0, math.floor(tonumber(entry.principal) or 0))
    if GodSystemApp.services.runtime.isBankFixedMature(entry) then
        local interest = GodSystemApp.services.runtime.getBankFixedInterest(entry)
        return principal + interest, interest, true
    end
    local penalty = math.max(0, math.floor(principal * (GodSystemConfig.BankEarlyWithdrawPenaltyRatio or 0.05)))
    return math.max(0, principal - penalty), -penalty, false
end

function GodSystemApp.services.runtime.getBankInvestmentProfiles()
    local profiles = GodSystemConfig.BankInvestmentProfiles or {}
    local result = {}
    for i = 1, #BANK_INVESTMENT_IDS do
        local tierId = BANK_INVESTMENT_IDS[i]
        local profile = profiles[tierId] or {}
        local gainChance = math.max(0, math.min(100, math.floor(tonumber(profile.gainChance) or 0)))
        result[#result + 1] = {
            id = tierId,
            gainChance = gainChance,
            lossChance = math.max(0, math.min(100 - gainChance, math.floor(tonumber(profile.lossChance) or 0))),
            gainPercent = math.max(0, tonumber(profile.gainPercent) or 0),
            lossPercent = math.max(0, tonumber(profile.lossPercent) or 0),
        }
    end
    return result
end

function GodSystemApp.services.runtime.getBankInvestmentProfile(tierId)
    tierId = tostring(tierId or "")
    local profiles = GodSystemApp.services.runtime.getBankInvestmentProfiles()
    for i = 1, #profiles do
        if profiles[i].id == tierId then
            return profiles[i]
        end
    end
    return nil
end

function GodSystemApp.services.runtime.getBankInvestmentAccount(tierId)
    local profile = GodSystemApp.services.runtime.getBankInvestmentProfile(tierId)
    if not profile then
        return nil
    end
    local bank = GodSystemApp.services.runtime.getBank()
    return bank.investments and bank.investments[profile.id] or nil
end

function GodSystemApp.services.runtime.getBankInvestmentLabel(tierId)
    local keys = {
        stable = "Bank_InvestmentStable",
        balanced = "Bank_InvestmentBalanced",
        aggressive = "Bank_InvestmentAggressive",
    }
    tierId = tostring(tierId or "")
    local key = keys[tierId]
    if not key then return tierId end
    return GodSystemApp.services.runtime.text(key, tierId)
end

function GodSystemApp.services.runtime.getBankInvestmentMinimum()
    return math.max(1, math.floor(tonumber(GodSystemConfig.BankInvestmentMinAmount) or 1))
end

function gsPrepareInvestmentDeposit(tierId, amount)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableBankInvestments") == false then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentDisabled", "Investment feature is disabled"))
        return nil, nil, nil
    end
    local profile = GodSystemApp.services.runtime.getBankInvestmentProfile(tierId)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local minimum = GodSystemApp.services.runtime.getBankInvestmentMinimum()
    if not profile then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentSelect", "Select an investment account"))
        return nil, nil, nil
    end
    if amount < minimum then
        GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankInvestmentMinimum", "Minimum investment is {1}"), { minimum }))
        return nil, nil, nil
    end
    local bank = GodSystemApp.services.runtime.getBank()
    local account = bank.investments[profile.id]
    return profile, account, amount
end

function gsAddBankInvestment(profile, account, amount, source)
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
    local data = GodSystemApp.services.runtime.getData()
    data.stats.bankInvestmentDeposited = (data.stats.bankInvestmentDeposited or 0) + amount
    local label = GodSystemApp.services.runtime.getBankInvestmentLabel(profile.id)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankInvestmentCreated", "Invested {2} coins in {1}"), { label, amount, source }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankInvestmentCreated", "Invested {2} coins in {1}"), { label, amount }))
    return true
end

function GodSystemApp.services.runtime.investBankCurrent(tierId, amount)
    local profile, account, cleanAmount = gsPrepareInvestmentDeposit(tierId, amount)
    if not profile then return false end
    local bank = GodSystemApp.services.runtime.getBank()
    if (bank.current or 0) < cleanAmount then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - cleanAmount
    return gsAddBankInvestment(profile, account, cleanAmount, "current")
end

function GodSystemApp.services.runtime.investBankCash(tierId, amount)
    local profile, account, cleanAmount = gsPrepareInvestmentDeposit(tierId, amount)
    if not profile then return false end
    if not GodSystemApp.services.runtime.removeCurrency(cleanAmount) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    return gsAddBankInvestment(profile, account, cleanAmount, "cash")
end

function GodSystemApp.services.runtime.redeemBankInvestment(tierId, amount)
    local profile = GodSystemApp.services.runtime.getBankInvestmentProfile(tierId)
    local account = profile and GodSystemApp.services.runtime.getBankInvestmentAccount(profile.id) or nil
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    if not profile or not account or (account.balance or 0) <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentSelect", "Select an investment account"))
        return false
    end
    if account.redeemUnlocked ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentLocked", "Investment can be redeemed after its first settlement"))
        return false
    end
    if amount > (account.balance or 0) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentBalanceLow", "Investment balance is not enough"))
        return false
    end
    account.balance = math.max(0, (account.balance or 0) - amount)
    local bank = GodSystemApp.services.runtime.getBank()
    bank.current = (bank.current or 0) + amount
    local data = GodSystemApp.services.runtime.getData()
    data.stats.bankInvestmentRedeemed = (data.stats.bankInvestmentRedeemed or 0) + amount
    local label = GodSystemApp.services.runtime.getBankInvestmentLabel(profile.id)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankInvestmentRedeemed", "Redeemed {2} coins from {1}"), { label, amount }) })
    if account.balance <= 0 then
        account.onlineHours = 0
        account.settlementCount = 0
        account.redeemUnlocked = false
        account.lastDelta = 0
        account.lastOutcome = "flat"
        account.lastSettledHour = nil
    end
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankInvestmentRedeemed", "Redeemed {2} coins from {1}"), { label, amount }))
    return true
end

bankInvestmentRuntimeHour = nil

function gsSettleBankInvestmentAccount(account, profile, nowHour)
    local before = math.max(0, math.floor(tonumber(account.balance) or 0))
    if before <= 0 then return 0, "flat" end
    local roll = gsRandomIndex(100)
    local delta = 0
    local outcome = "flat"
    if roll <= (profile.gainChance or 0) then
        local percent = math.max(0, tonumber(profile.gainPercent) or 0)
        if percent > 0 then
            delta = math.max(1, math.floor(before * percent / 100))
            account.balance = before + delta
            outcome = "gain"
        end
    elseif roll > 100 - (profile.lossChance or 0) then
        local percent = math.max(0, tonumber(profile.lossPercent) or 0)
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
    return delta, outcome
end

function GodSystemApp.services.runtime.updateBankInvestments()
    local nowHour = gsNowHours()
    if bankInvestmentRuntimeHour == nil then
        bankInvestmentRuntimeHour = nowHour
        return false
    end
    local elapsed = nowHour - bankInvestmentRuntimeHour
    bankInvestmentRuntimeHour = nowHour
    if elapsed <= 0 then
        return false
    end
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableBankInvestments") == false then
        return false
    end
    local bank = GodSystemApp.services.runtime.getBank()
    local profiles = GodSystemApp.services.runtime.getBankInvestmentProfiles()
    local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
    local settledCount = 0
    local totalDelta = 0
    local data = GodSystemApp.services.runtime.getData()
    for i = 1, #profiles do
        local profile = profiles[i]
        local account = bank.investments[profile.id]
        if account and (account.balance or 0) > 0 then
            account.onlineHours = math.max(0, tonumber(account.onlineHours) or 0) + elapsed
            while account.onlineHours >= settlementHours and (account.balance or 0) > 0 do
                account.onlineHours = account.onlineHours - settlementHours
                local before = account.balance
                local delta = gsSettleBankInvestmentAccount(account, profile, nowHour)
                totalDelta = totalDelta + delta
                settledCount = settledCount + 1
                if delta > 0 then
                    data.stats.bankInvestmentProfit = (data.stats.bankInvestmentProfit or 0) + delta
                elseif delta < 0 then
                    data.stats.bankInvestmentLoss = (data.stats.bankInvestmentLoss or 0) + math.abs(delta)
                end
                local label = GodSystemApp.services.runtime.getBankInvestmentLabel(profile.id)
                gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankInvestmentSettled", "Investment settled: {1} {2} -> {4} ({3})"), { label, before, delta, account.balance }) })
            end
        end
    end
    if settledCount <= 0 then
        return false
    end
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankInvestmentSettled", "Investment settlement: {1} account(s), total change {2}"), { settledCount, totalDelta }))
    return true
end

function GodSystemApp.services.runtime.getBankSummary()
    local bank = GodSystemApp.services.runtime.getBank()
    local fixedPrincipal = 0
    local fixedMatureValue = 0
    local investmentTotal = 0
    for i = 1, #(bank.fixed or {}) do
        local entry = bank.fixed[i]
        fixedPrincipal = fixedPrincipal + math.max(0, math.floor(tonumber(entry.principal) or 0))
        fixedMatureValue = fixedMatureValue + math.max(0, math.floor((tonumber(entry.principal) or 0) + GodSystemApp.services.runtime.getBankFixedInterest(entry)))
    end
    for _, account in pairs(bank.investments or {}) do
        investmentTotal = investmentTotal + math.max(0, math.floor(tonumber(account.balance) or 0))
    end
    local deathPenalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    return {
        cash = GodSystemApp.services.runtime.getCurrencyTotal(),
        current = bank.current or 0,
        fixedPrincipal = fixedPrincipal,
        fixedMatureValue = fixedMatureValue,
        fixedCount = #(bank.fixed or {}),
        investmentTotal = investmentTotal,
        deathPenalty = deathPenalty,
    }
end

function GodSystemApp.services.runtime.getBankLoanPlans()
    local plans = {
        {
            id = "single",
            kind = "single",
            periods = 1,
            dueHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanSingleDueHours) or 72)),
            totalInterestRate = tonumber(GodSystemConfig.BankLoanSingleInterestRate) or 0.05,
        },
    }
    local periodHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanPeriodHours) or 72))
    for i = 1, #(GodSystemConfig.BankLoanInstallmentPlans or {}) do
        local row = GodSystemConfig.BankLoanInstallmentPlans[i]
        local periods = math.max(1, math.floor(tonumber(row.periods) or 1))
        plans[#plans + 1] = {
            id = tostring(row.id or ("i" .. tostring(periods))),
            kind = "installment",
            periods = periods,
            dueHours = periodHours,
            totalInterestRate = tonumber(row.totalInterestRate) or 0,
        }
    end
    return plans
end

function gsGetBankLoanPlan(planId)
    planId = tostring(planId or "single")
    local plans = GodSystemApp.services.runtime.getBankLoanPlans()
    for i = 1, #plans do
        if tostring(plans[i].id or "") == planId then
            return plans[i]
        end
    end
    return nil
end

function gsBankLoanUnpaidPrincipal(loan)
    local total = 0
    if not loan or type(loan.schedule) ~= "table" then
        return 0
    end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local partTotal = math.max(0, math.floor((tonumber(bill.principalPart) or 0) + (tonumber(bill.interestPart) or 0)))
        local paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        local principal = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
        if partTotal > 0 and paid < partTotal then
            local principalPaid = math.min(principal, paid)
            total = total + math.max(0, principal - principalPaid)
        end
    end
    return total
end

function gsBankLoanAmounts(loan, now)
    now = tonumber(now) or gsNowHours()
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
    if not loan or type(loan.schedule) ~= "table" then
        return result
    end
    for i = 1, #loan.schedule do
        local bill = loan.schedule[i]
        local principal = math.max(0, math.floor(tonumber(bill.principalPart) or 0))
        local interest = math.max(0, math.floor(tonumber(bill.interestPart) or 0))
        local total = principal + interest
        local paid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        if total > paid then
            local remaining = total - paid
            local principalPaid = math.min(principal, paid)
            local interestPaid = math.max(0, paid - principal)
            local principalLeft = math.max(0, principal - principalPaid)
            local interestLeft = math.max(0, interest - interestPaid)
            result.unpaidPrincipal = result.unpaidPrincipal + principalLeft
            result.unpaidInterest = result.unpaidInterest + interestLeft
            result.unpaidTotal = result.unpaidTotal + remaining
            local dueHour = tonumber(bill.dueHour) or now
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

function gsRefreshBankLoanStatus(loan, now)
    if not loan then
        return gsBankLoanAmounts(nil, now)
    end
    local amounts = gsBankLoanAmounts(loan, now)
    loan.overdueStartHour = amounts.overdueStartHour
    return amounts
end

function gsBankLoanOverduePenalty(loan, now, amounts)
    amounts = amounts or gsRefreshBankLoanStatus(loan, now)
    if not loan or not amounts.overdueStartHour then
        return 0
    end
    now = tonumber(now) or gsNowHours()
    local overdueDays = math.max(0, math.floor((now - amounts.overdueStartHour) / 24))
    if overdueDays <= 0 then
        return 0
    end
    local principal = math.max(0, math.floor(tonumber(loan.principal) or 0))
    local dailyRate = tonumber(GodSystemConfig.BankLoanOverduePenaltyDailyRate) or 0.05
    local maxRate = tonumber(GodSystemConfig.BankLoanOverduePenaltyMaxRate) or 0.5
    return math.max(0, math.floor(math.min(principal * maxRate, principal * dailyRate * overdueDays)))
end

function gsBankLoanCredit(data, bank)
    data = data or GodSystemApp.services.runtime.getData()
    bank = bank or GodSystemApp.services.runtime.getBank()
    local base = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanBaseCredit) or 2000))
    local step = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanCreditSpendStep) or 100))
    local perStep = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanCreditPerStep) or 5))
    local spent = math.max(0, math.floor(tonumber(data.stats and data.stats.spentPoints) or 0))
    local offset = math.max(0, math.floor(tonumber(bank.loanCreditSpentOffset) or 0))
    local growth = math.floor(math.max(0, spent - offset) / step) * perStep
    local total = base + growth
    local used = gsBankLoanUnpaidPrincipal(bank.loan)
    return total, math.max(0, total - used), growth, used
end

function gsCreateBankLoanSchedule(plan, amount, now)
    local schedule = {}
    local periods = math.max(1, math.floor(tonumber(plan.periods) or 1))
    local totalInterest = math.max(0, math.floor(amount * (tonumber(plan.totalInterestRate) or 0)))
    local principalLeft = amount
    local interestLeft = totalInterest
    for i = 1, periods do
        local principalPart = (i == periods) and principalLeft or math.floor(amount / periods)
        local interestPart = (i == periods) and interestLeft or math.floor(totalInterest / periods)
        principalLeft = principalLeft - principalPart
        interestLeft = interestLeft - interestPart
        schedule[#schedule + 1] = {
            index = i,
            dueHour = now + math.max(1, math.floor(tonumber(plan.dueHours) or 72)) * i,
            principalPart = principalPart,
            interestPart = interestPart,
            paid = 0,
        }
    end
    return schedule, totalInterest
end

function gsApplyBankLoanPayment(loan, amount, now, includeFuture)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local paid = 0
    if not loan or amount <= 0 then
        return 0
    end
    now = tonumber(now) or gsNowHours()
    for i = 1, #(loan.schedule or {}) do
        local bill = loan.schedule[i]
        local total = math.max(0, math.floor((tonumber(bill.principalPart) or 0) + (tonumber(bill.interestPart) or 0)))
        local billPaid = math.max(0, math.floor(tonumber(bill.paid) or 0))
        if total > billPaid and (includeFuture or now >= (tonumber(bill.dueHour) or now)) then
            local add = math.min(amount, total - billPaid)
            bill.paid = billPaid + add
            loan.paid = math.max(0, math.floor(tonumber(loan.paid) or 0)) + add
            amount = amount - add
            paid = paid + add
            if amount <= 0 then
                break
            end
        end
    end
    return paid
end

function GodSystemApp.services.runtime.spawnBankLoanDebtZombies(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 or not addZombiesInOutfit then
        return 0
    end
    local player = gsPlayer()
    if not player or not player.getX then
        return 0
    end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local minDist = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanZombieMinDistance) or 20))
    local maxDist = math.max(minDist, math.floor(tonumber(GodSystemConfig.BankLoanZombieMaxDistance) or 45))
    local spawned = 0
    local tries = 0
    while spawned < count and tries < count * 8 do
        tries = tries + 1
        local dist = minDist + gsRandomIndex(math.max(1, maxDist - minDist + 1)) - 1
        local dx = gsRandomIndex(dist * 2 + 1) - dist - 1
        local dySign = gsRandomIndex(2) == 1 and -1 or 1
        local dy = dySign * math.max(minDist, dist - math.abs(dx))
        local x = math.floor(px + dx)
        local y = math.floor(py + dy)
        local batch = math.min(10, count - spawned)
        local ok = pcall(addZombiesInOutfit, x, y, pz, batch, nil, nil)
        if ok then
            spawned = spawned + batch
        end
    end
    return spawned
end

function GodSystemApp.services.runtime.applyBankLoanBankruptcy(bank, loan, debt)
    local data = GodSystemApp.services.runtime.getData()
    bank = bank or GodSystemApp.services.runtime.getBank()
    loan = loan or bank.loan
    if not loan then
        return false, 0
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    debt = math.max(0, math.floor(tonumber(debt) or (amounts.unpaidTotal + gsBankLoanOverduePenalty(loan, now, amounts))))
    local perZombie = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanZombieDebtPerZombie) or 50))
    local maxZombies = math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanZombieMaxCount) or 100))
    local zombieCount = math.min(maxZombies, math.max(1, math.floor(debt / perZombie)))
    local cash = math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0))
    if cash > 0 then
        GodSystemApp.services.runtime.removeCurrency(cash)
    end
    bank.loan = nil
    bank.current = 0
    bank.loanFrozenUntilHour = now + math.max(0, math.floor(tonumber(GodSystemConfig.BankLoanFreezeHours) or 168))
    bank.loanCreditSpentOffset = math.max(0, math.floor(tonumber(data.stats and data.stats.spentPoints) or 0))
    bank.loanBankruptcyCount = math.max(0, math.floor(tonumber(bank.loanBankruptcyCount) or 0)) + 1
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + debt
    local spawned = GodSystemApp.services.runtime.spawnBankLoanDebtZombies(zombieCount)
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankLoanBankruptcy", "Loan bankruptcy cleared debt {1}, spawned debt zombies {2}"), { debt, spawned }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankLoanBankruptcy", "Loan bankruptcy! Debt cleared, current account and carried cash removed, debt zombies spawned: {1}"), { spawned }))
    return true, spawned
end

function GodSystemApp.services.runtime.getBankLoanSummary()
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local now = gsNowHours()
    local loan = bank.loan
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local creditTotal, creditAvailable, creditGrowth, creditUsed = gsBankLoanCredit(data, bank)
    local freezeLeft = math.max(0, math.ceil((tonumber(bank.loanFrozenUntilHour) or 0) - now))
    local graceHours = math.max(1, math.floor(tonumber(GodSystemConfig.BankLoanBankruptcyGraceHours) or 240))
    if loan and not (GodSystemNetwork and GodSystemNetwork.isMultiplayer == true) and amounts.overdueStartHour and now - amounts.overdueStartHour >= graceHours then
        GodSystemApp.services.runtime.applyBankLoanBankruptcy(bank, loan, amounts.unpaidTotal + penalty)
        return GodSystemApp.services.runtime.getBankLoanSummary()
    end
    return {
        creditTotal = creditTotal,
        creditAvailable = creditAvailable,
        creditGrowth = creditGrowth,
        creditUsed = creditUsed,
        loan = bank.loan,
        dueNow = amounts.due + penalty,
        dueBase = amounts.due,
        overduePenalty = penalty,
        payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5),
        unpaidTotal = amounts.unpaidTotal + penalty,
        nextDueHour = amounts.nextDueHour,
        overdueStartHour = amounts.overdueStartHour,
        freezeLeftHours = freezeLeft,
        frozen = freezeLeft > 0,
        bankruptcyInHours = amounts.overdueStartHour and math.max(0, math.ceil(graceHours - (now - amounts.overdueStartHour))) or nil,
    }
end

function GodSystemApp.services.runtime.borrowBankLoan(planId, amount)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableBankLoan") == false then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanFrozen", "Loan feature is disabled"))
        return false
    end
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    local plan = gsGetBankLoanPlan(planId)
    if not plan then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankSelectTerm", "Select a fixed term first"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local summary = GodSystemApp.services.runtime.getBankLoanSummary()
    if bank.loan then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanActive", "There is already an active loan"))
        return false
    end
    if summary.frozen then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanFrozen", "Loan feature is frozen"))
        return false
    end
    if amount > (summary.creditAvailable or 0) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanCreditLow", "Available credit is not enough"))
        return false
    end
    local now = gsNowHours()
    local schedule, totalInterest = gsCreateBankLoanSchedule(plan, amount, now)
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
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankLoanBorrowed", "Bank loan received {1} coins"), { amount }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankLoanBorrowed", "Loan paid to current account: {1}"), { amount }))
    return true
end

function GodSystemApp.services.runtime.repayBankLoanDue()
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local loan = bank.loan
    if not loan then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanNoActive", "No active loan"))
        return false
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local due = amounts.due + penalty
    if due <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanNoDue", "No due bill now"))
        return false
    end
    if (bank.current or 0) < due then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - due
    gsApplyBankLoanPayment(loan, amounts.due, now, false)
    if penalty > 0 then
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    end
    if (loan.paid or 0) >= (loan.totalDue or 0) then
        bank.loan = nil
    else
        gsRefreshBankLoanStatus(loan, now)
    end
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankLoanRepaid", "Loan repaid {1} coins"), { due }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankLoanRepaid", "Loan repaid: {1}"), { due }))
    return true
end

function GodSystemApp.services.runtime.payoffBankLoan()
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local loan = bank.loan
    if not loan then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankLoanNoActive", "No active loan"))
        return false
    end
    local now = gsNowHours()
    local amounts = gsRefreshBankLoanStatus(loan, now)
    local penalty = gsBankLoanOverduePenalty(loan, now, amounts)
    local payoff = amounts.due + penalty + amounts.futurePrincipal + math.floor(amounts.futureInterest * 0.5)
    payoff = math.max(0, math.floor(payoff))
    if payoff <= 0 then
        bank.loan = nil
        GodSystemApp.services.runtime.save()
        return true
    end
    if (bank.current or 0) < payoff then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    bank.current = (bank.current or 0) - payoff
    bank.loan = nil
    if penalty > 0 then
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    end
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankLoanPayoff", "Loan paid off early {1} coins"), { payoff }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankLoanPayoff", "Loan paid off early: {1}"), { payoff }))
    return true
end

function GodSystemApp.services.runtime.depositBankCurrent(amount)
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    if not GodSystemApp.services.runtime.removeCurrency(amount) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    bank.current = (bank.current or 0) + amount
    data.stats.bankDeposited = (data.stats.bankDeposited or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = GodSystemApp.services.runtime.text("History_BankDeposit", "Bank deposit ") .. tostring(amount) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankDeposit", "Deposited to current account: ") .. tostring(amount))
    return true
end

function GodSystemApp.services.runtime.depositAllCashToBankCurrent(silent)
    local amount = math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0))
    if amount <= 0 then
        if not silent then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankDepositAllEmpty", "No carried system currency to deposit"))
        end
        return false
    end
    if not GodSystemApp.services.runtime.removeCurrency(amount) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    bank.current = (bank.current or 0) + amount
    data.stats.bankDeposited = (data.stats.bankDeposited or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = gsFormatText(GodSystemApp.services.runtime.text("History_BankDepositAll", "Deposited all carried cash into current account: {1} coins"), { amount }) })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(gsFormatText(GodSystemApp.services.runtime.text("Notify_BankDepositAll", "Deposited all carried cash into current account: {1}"), { amount }))
    return true
end

function GodSystemApp.services.runtime.toggleBankAutoDeposit()
    local bank = GodSystemApp.services.runtime.getBank()
    bank.autoDepositEnabled = bank.autoDepositEnabled ~= true
    bank.lastAutoDepositHour = gsNowHours()
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(bank.autoDepositEnabled and "Notify_AutoDepositEnabled" or "Notify_AutoDepositDisabled", bank.autoDepositEnabled and "Auto deposit enabled" or "Auto deposit disabled"))
    return bank.autoDepositEnabled
end

function GodSystemApp.services.runtime.processBankAutoDeposit()
    local bank = GodSystemApp.services.runtime.getBank()
    if bank.autoDepositEnabled ~= true then return false end
    local nowHour = gsNowHours()
    if nowHour < (bank.lastAutoDepositHour or nowHour) then
        bank.lastAutoDepositHour = nowHour
    end
    if nowHour - (bank.lastAutoDepositHour or nowHour) < 1 then
        return false
    end
    bank.lastAutoDepositHour = nowHour
    if math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0)) <= 0 then
        GodSystemApp.services.runtime.save()
        return false
    end
    return GodSystemApp.services.runtime.depositAllCashToBankCurrent(true)
end

function GodSystemApp.services.runtime.withdrawBankCurrent(amount)
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    if (bank.current or 0) < amount then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankCurrentNotEnough", "Current account balance is not enough"))
        return false
    end
    if not GodSystemApp.services.runtime.giveCurrency(amount) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankWithdrawFailed", "Withdrawal failed"))
        return false
    end
    bank.current = (bank.current or 0) - amount
    data.stats.bankWithdrawn = (data.stats.bankWithdrawn or 0) + amount
    gsAppendHistory(data, { kind = "bank", text = GodSystemApp.services.runtime.text("History_BankWithdraw", "Bank withdraw ") .. tostring(amount) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankWithdraw", "Withdrawn from current account: ") .. tostring(amount))
    return true
end

function GodSystemApp.services.runtime.withdrawBankFixed(entryId)
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local entry, index = GodSystemApp.services.runtime.getBankFixedEntry(entryId)
    if not entry or not index then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankSelectFixed", "Select a fixed deposit first"))
        return false
    end
    local payout, interestOrPenalty, mature = GodSystemApp.services.runtime.getBankFixedPayout(entry)
    bank.current = (bank.current or 0) + payout
    table.remove(bank.fixed, index)
    if mature then
        data.stats.bankInterest = (data.stats.bankInterest or 0) + math.max(0, interestOrPenalty)
        gsAppendHistory(data, { kind = "bank", text = GodSystemApp.services.runtime.text("History_BankFixedWithdraw", "Fixed deposit matured ") .. "+" .. tostring(payout) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankFixedWithdraw", "Fixed deposit paid to current account: ") .. tostring(payout))
    else
        data.stats.bankPenalty = (data.stats.bankPenalty or 0) + math.abs(math.min(0, interestOrPenalty))
        gsAppendHistory(data, { kind = "bank", text = GodSystemApp.services.runtime.text("History_BankFixedEarlyWithdraw", "Fixed deposit withdrawn early ") .. "+" .. tostring(payout) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankFixedEarlyWithdraw", "Early withdrawal paid to current account: ") .. tostring(payout))
    end
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.performBankAction(action, amount, termId, entryId)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableBank") == false then
        GodSystemApp.services.runtime.notify("Bank disabled")
        return false
    end
    if action == "deposit" then
        return GodSystemApp.services.runtime.depositBankCurrent(amount)
    elseif action == "depositAllCash" then
        return GodSystemApp.services.runtime.depositAllCashToBankCurrent()
    elseif action == "toggleAutoDeposit" then
        return GodSystemApp.services.runtime.toggleBankAutoDeposit()
    elseif action == "withdraw" then
        return GodSystemApp.services.runtime.withdrawBankCurrent(amount)
    elseif action == "withdrawFixed" then
        return GodSystemApp.services.runtime.withdrawBankFixed(entryId)
    elseif action == "investFromCurrent" then
        return GodSystemApp.services.runtime.investBankCurrent(termId, amount)
    elseif action == "investFromCash" then
        return GodSystemApp.services.runtime.investBankCash(termId, amount)
    elseif action == "redeemInvestment" then
        return GodSystemApp.services.runtime.redeemBankInvestment(termId, amount)
    elseif action == "borrowLoan" then
        return GodSystemApp.services.runtime.borrowBankLoan(termId, amount)
    elseif action == "repayLoanDue" then
        return GodSystemApp.services.runtime.repayBankLoanDue()
    elseif action == "payoffLoan" then
        return GodSystemApp.services.runtime.payoffBankLoan()
    end
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankUnknownAction", "Unknown bank operation"))
    return false
end

function GodSystemApp.services.runtime.applyBankDeathPenalty()
    local data = GodSystemApp.services.runtime.getData()
    local bank = GodSystemApp.services.runtime.getBank()
    local now = gsNowHours()
    if now - (bank.lastDeathPenaltyHour or -999) < 0.1 then
        return false
    end
    bank.lastDeathPenaltyHour = now
    local penalty = math.floor((bank.current or 0) * (GodSystemConfig.BankDeathDemandPenaltyRatio or 0.3))
    if penalty <= 0 then
        GodSystemApp.services.runtime.save()
        return false
    end
    bank.current = math.max(0, (bank.current or 0) - penalty)
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + penalty
    gsAppendHistory(data, { kind = "bank", text = GodSystemApp.services.runtime.text("History_BankDeathPenalty", "Death penalty deducted from current account ") .. tostring(penalty) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankDeathPenalty", "Death penalty deducted from current account: ") .. tostring(penalty))
    return true
end

function GodSystemApp.services.runtime.payTaskFailurePenalty(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return 0, 0, 0
    end
    local bank = GodSystemApp.services.runtime.getBank()
    local fromBank = math.min(bank.current or 0, amount)
    if fromBank > 0 then
        bank.current = math.max(0, (bank.current or 0) - fromBank)
    end
    local remaining = amount - fromBank
    local fromCash = 0
    if remaining > 0 then
        local cash = math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0))
        fromCash = math.min(cash, remaining)
        if fromCash > 0 and not GodSystemApp.services.runtime.removeCurrency(fromCash) then
            fromCash = 0
        end
    end
    local paid = fromBank + fromCash
    local data = GodSystemApp.services.runtime.getData()
    data.stats.bankPenalty = (data.stats.bankPenalty or 0) + fromBank
    return paid, fromBank, fromCash
end
end
