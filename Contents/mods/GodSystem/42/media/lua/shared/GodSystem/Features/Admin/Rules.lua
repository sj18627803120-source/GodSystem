GodSystemAdminFeatureRules = GodSystemAdminFeatureRules or {}

local Rules = GodSystemAdminFeatureRules

Rules.stateVersion = 1

local function meta(key, group, kind, default, minimum, maximum, singlePlayerOnly)
    return {
        key = key,
        group = group,
        type = kind,
        default = default,
        min = minimum,
        max = maximum,
        singlePlayerOnly = singlePlayerOnly == true,
        labelKey = "AdminSetting_" .. key,
        descKey = "AdminSetting_" .. key .. "_Desc",
    }
end

Rules.meta = {
    meta("StartingPoints", "base", "integer", 60, 0, 100000),
    meta("KillPointReward", "base", "integer", 1, 0, 1000),
    meta("DailyTaskCount", "base", "integer", 5, 0, 20),
    meta("MaxActiveTasks", "base", "integer", 3, 0, 10),
    meta("RefreshTaskCost", "base", "integer", 30, 0, 100000),
    meta("DefaultTaskLimitHours", "base", "integer", 24, 1, 168),
    meta("MedicalCheckInfectionCost", "base", "integer", 50, 0, 1000000),
    meta("MedicalHealInjuriesCost", "base", "integer", 5000, 0, 1000000),
    meta("MedicalCureInfectionCost", "base", "integer", 2000, 0, 1000000),
    meta("HomeSetCost", "base", "integer", 100, 0, 100000),
    meta("HomeTravelCost", "base", "integer", 10, 0, 100000),
    meta("TempTeleportSlotCost", "base", "integer", 500, 0, 100000),
    meta("TempTeleportSetCost", "base", "integer", 100, 0, 100000),
    meta("WaistAutoRecycleUnlockCost", "base", "integer", 100, 0, 100000),
    meta("WaistAutoRecycleIntervalHours", "base", "number", 1, 0.1, 168),
    meta("PositiveTraitCostPerPoint", "base", "integer", 800, 0, 100000),
    meta("NegativeTraitRemoveCostPerPoint", "base", "integer", 500, 0, 100000),
    meta("AttributeXPPerCoin", "base", "integer", 10, 1, 1000000),
    meta("TerminalReliefUpgradeCost", "base", "integer", 2000, 0, 100000000),
    meta("TerminalReliefPerLevel", "base", "integer", 5, 1, 5000),
    meta("TerminalReliefMaxOffset", "base", "integer", 2000, 0, 5000),
    meta("AutoLoaderAmmoCapacity", "base", "integer", 2000, 100, 10000),

    meta("ShopBuyPriceMultiplier", "economy", "number", 1, 0.01, 100),
    meta("RecycleSellPriceMultiplier", "economy", "number", 1, 0, 100),
    meta("TaskRewardMultiplier", "economy", "number", 1, 0, 100),
    meta("TaskPenaltyMultiplier", "economy", "number", 1, 0, 100),
    meta("MPBackgroundSyncMinutes", "economy", "number", 5, 1, 60),
    meta("CompanionPriceMultiplier", "economy", "number", 1, 0.01, 100, true),
    meta("LotteryAllPrice", "economy", "integer", 100, 1, 100000),
    meta("LotteryCustomMaxCount", "economy", "integer", 50, 1, 500),
    meta("LotteryPriceLow", "economy", "integer", 60, 1, 100000),
    meta("LotteryPriceMid", "economy", "integer", 90, 1, 100000),
    meta("LotteryPriceUtility", "economy", "integer", 150, 1, 100000),
    meta("LotteryPriceVehicle", "economy", "integer", 200, 1, 100000),
    meta("LotteryPriceWeapon", "economy", "integer", 400, 1, 100000),
    meta("AutoShopListOnlyCostRatio", "economy", "number", 0.5, 0, 100),
    meta("AutoShopListOnlyMinCost", "economy", "integer", 50, 0, 100000000),
    meta("BankLoanBaseCredit", "economy", "integer", 2000, 0, 100000000),
    meta("BankLoanCreditSpendStep", "economy", "integer", 100, 1, 1000000),
    meta("BankLoanCreditPerStep", "economy", "integer", 5, 0, 1000000),
    meta("BankLoanSingleInterestRate", "economy", "number", 0.05, 0, 10),
    meta("BankLoanOverduePenaltyDailyRate", "economy", "number", 0.05, 0, 10),
    meta("BankLoanOverduePenaltyMaxRate", "economy", "number", 0.5, 0, 10),
    meta("BankLoanBankruptcyGraceHours", "economy", "integer", 240, 1, 10000),
    meta("BankLoanFreezeHours", "economy", "integer", 168, 0, 10000),
    meta("BankLoanZombieDebtPerZombie", "economy", "integer", 50, 1, 1000000),
    meta("BankLoanZombieMaxCount", "economy", "integer", 100, 0, 1000),
    meta("BankInvestmentMinAmount", "economy", "integer", 1, 1, 100000000),
    meta("BankInvestmentStableGainChance", "economy", "integer", 70, 0, 100),
    meta("BankInvestmentStableLossChance", "economy", "integer", 5, 0, 100),
    meta("BankInvestmentStableGainPercent", "economy", "number", 1, 0, 1000),
    meta("BankInvestmentStableLossPercent", "economy", "number", 1, 0, 100),
    meta("BankInvestmentBalancedGainChance", "economy", "integer", 55, 0, 100),
    meta("BankInvestmentBalancedLossChance", "economy", "integer", 30, 0, 100),
    meta("BankInvestmentBalancedGainPercent", "economy", "number", 3, 0, 1000),
    meta("BankInvestmentBalancedLossPercent", "economy", "number", 2, 0, 100),
    meta("BankInvestmentAggressiveGainChance", "economy", "integer", 45, 0, 100),
    meta("BankInvestmentAggressiveLossChance", "economy", "integer", 45, 0, 100),
    meta("BankInvestmentAggressiveGainPercent", "economy", "number", 8, 0, 1000),
    meta("BankInvestmentAggressiveLossPercent", "economy", "number", 5, 0, 100),

    meta("EnableShop", "features", "boolean", true),
    meta("EnableRecycle", "features", "boolean", true),
    meta("EnableBank", "features", "boolean", true),
    meta("EnableTeleport", "features", "boolean", true),
    meta("EnableTraits", "features", "boolean", true),
    meta("EnableWaistAutoRecycle", "features", "boolean", true),
    meta("EnableShopLottery", "features", "boolean", true),
    meta("EnableTasks", "features", "boolean", true),
    meta("EnableBankLoan", "features", "boolean", true),
    meta("EnableBankInvestments", "features", "boolean", true),
    meta("EnableCompanion", "features", "boolean", true, nil, nil, true),
    meta("EnableAttributes", "features", "boolean", true),
    meta("EnableAutoLoaderShop", "features", "boolean", true),
}

local META = {}
for index = 1, #Rules.meta do META[Rules.meta[index].key] = Rules.meta[index] end

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

function Rules.copy(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then return seen[source] end
    local target = {}
    seen[source] = target
    for key, value in pairs(source) do target[Rules.copy(key, seen)] = Rules.copy(value, seen) end
    return target
end

function Rules.boolean(value, fallback)
    if value == nil then return fallback == true end
    if value == true or value == 1 or value == "1" then return true end
    local text = tostring(value):lower()
    return text == "true" or text == "yes" or text == "on"
end

function Rules.text(value, maximum)
    local result = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if maximum and #result > maximum then result = result:sub(1, maximum) end
    return result
end

function Rules.sanitizeSettings(input, base)
    input, base = type(input) == "table" and input or {}, type(base) == "table" and base or {}
    local result = {}
    for index = 1, #Rules.meta do
        local row = Rules.meta[index]
        local fallback = base[row.key]
        if fallback == nil then fallback = row.default end
        local value = input[row.key]
        if row.type == "boolean" then
            result[row.key] = Rules.boolean(value, fallback)
        else
            value = finite(value) and tonumber(value) or tonumber(fallback) or 0
            if row.min ~= nil and value < row.min then value = row.min end
            if row.max ~= nil and value > row.max then value = row.max end
            if row.type == "integer" then value = math.floor(value) end
            result[row.key] = value
        end
    end
    for _, prefix in ipairs({
        "BankInvestmentStable", "BankInvestmentBalanced", "BankInvestmentAggressive",
    }) do
        local gainKey, lossKey = prefix .. "GainChance", prefix .. "LossChance"
        result[lossKey] = math.min(result[lossKey] or 0, 100 - (result[gainKey] or 0))
    end
    return result
end

function Rules.sanitizeOverride(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for _, field in ipairs({ "buyPrice", "sellPrice" }) do
        if value[field] ~= nil and tostring(value[field]) ~= "" then
            local number = finite(value[field]) and tonumber(value[field]) or 0
            result[field] = math.max(0, math.min(10000000, math.floor(number)))
        end
    end
    if value.category ~= nil and tostring(value.category) ~= "" then
        local category = Rules.text(value.category, 32):lower():gsub("[^a-z0-9_]+", "_")
        if category ~= "" then result.category = category end
    end
    for _, field in ipairs({ "shopEnabled", "recycleEnabled", "lotteryEnabled" }) do
        if value[field] ~= nil then result[field] = Rules.boolean(value[field], true) end
    end
    if value.note ~= nil and tostring(value.note) ~= "" then result.note = Rules.text(value.note, 120) end
    return next(result) and result or nil
end

function Rules.sanitizeOverrides(input)
    local result = {}
    for fullType, value in pairs(type(input) == "table" and input or {}) do
        local key, override = Rules.text(fullType, 120), Rules.sanitizeOverride(value)
        if key ~= "" and override then result[key] = override end
    end
    return result
end

function Rules.snapshot(data, baseSettings, staticOverrides)
    data = type(data) == "table" and data or {}
    local settings = Rules.sanitizeSettings(data.settings, baseSettings)
    local overrides = Rules.sanitizeOverrides(staticOverrides)
    for fullType, value in pairs(Rules.sanitizeOverrides(data.itemOverrides)) do overrides[fullType] = value end
    return {
        settings = settings,
        itemOverrides = overrides,
        meta = Rules.copy(Rules.meta),
        revision = math.max(0, math.floor(tonumber(data.revision) or 0)),
    }
end

function Rules.getMeta(key)
    return META[tostring(key or "")]
end

return Rules
