require "GodSystem_Config"

GodSystemAdminConfig = GodSystemAdminConfig or {}

local Config = GodSystemConfig or {}

local function investmentDefault(tierId, field, fallback)
    local profiles = Config.BankInvestmentProfiles or {}
    local profile = profiles[tierId] or {}
    local value = tonumber(profile[field])
    if value == nil then
        return fallback
    end
    return value
end

local SETTING_META = {
    { key = "StartingPoints", group = "base", type = "integer", default = Config.StartingPoints or 60, min = 0, max = 100000, target = "StartingPoints", labelKey = "AdminSetting_StartingPoints", descKey = "AdminSetting_StartingPoints_Desc" },
    { key = "KillPointReward", group = "base", type = "integer", default = Config.KillPointReward or 1, min = 0, max = 1000, target = "KillPointReward", labelKey = "AdminSetting_KillPointReward", descKey = "AdminSetting_KillPointReward_Desc" },
    { key = "DailyTaskCount", group = "base", type = "integer", default = Config.DailyTaskCount or 5, min = 0, max = Config.MaxDailyTaskLimit or 20, target = "DailyTaskCount", labelKey = "AdminSetting_DailyTaskCount", descKey = "AdminSetting_DailyTaskCount_Desc" },
    { key = "MaxActiveTasks", group = "base", type = "integer", default = Config.MaxActiveTasks or 3, min = 0, max = Config.MaxActiveTaskLimit or 10, target = "MaxActiveTasks", labelKey = "AdminSetting_MaxActiveTasks", descKey = "AdminSetting_MaxActiveTasks_Desc" },
    { key = "RefreshTaskCost", group = "base", type = "integer", default = Config.RefreshTaskCost or 30, min = 0, max = 100000, target = "RefreshTaskCost", labelKey = "AdminSetting_RefreshTaskCost", descKey = "AdminSetting_RefreshTaskCost_Desc" },
    { key = "DefaultTaskLimitHours", group = "base", type = "integer", default = Config.DefaultTaskLimitHours or 24, min = 1, max = 168, target = "DefaultTaskLimitHours", labelKey = "AdminSetting_DefaultTaskLimitHours", descKey = "AdminSetting_DefaultTaskLimitHours_Desc" },
    { key = "MedicalCheckInfectionCost", group = "base", type = "integer", default = Config.MedicalCheckInfectionCost or 50, min = 0, max = 1000000, target = "MedicalCheckInfectionCost", labelKey = "AdminSetting_MedicalCheckInfectionCost", descKey = "AdminSetting_MedicalCheckInfectionCost_Desc" },
    { key = "MedicalHealInjuriesCost", group = "base", type = "integer", default = Config.MedicalHealInjuriesCost or 5000, min = 0, max = 1000000, target = "MedicalHealInjuriesCost", labelKey = "AdminSetting_MedicalHealInjuriesCost", descKey = "AdminSetting_MedicalHealInjuriesCost_Desc" },
    { key = "MedicalCureInfectionCost", group = "base", type = "integer", default = Config.MedicalCureInfectionCost or 2000, min = 0, max = 1000000, target = "MedicalCureInfectionCost", labelKey = "AdminSetting_MedicalCureInfectionCost", descKey = "AdminSetting_MedicalCureInfectionCost_Desc" },
    { key = "HomeSetCost", group = "base", type = "integer", default = Config.HomeSetCost or 100, min = 0, max = 100000, target = "HomeSetCost", labelKey = "AdminSetting_HomeSetCost", descKey = "AdminSetting_HomeSetCost_Desc" },
    { key = "HomeTravelCost", group = "base", type = "integer", default = Config.HomeTravelCost or 10, min = 0, max = 100000, target = "HomeTravelCost", labelKey = "AdminSetting_HomeTravelCost", descKey = "AdminSetting_HomeTravelCost_Desc" },
    { key = "TempTeleportSlotCost", group = "base", type = "integer", default = Config.TempTeleportSlotCost or 500, min = 0, max = 100000, target = "TempTeleportSlotCost", labelKey = "AdminSetting_TempTeleportSlotCost", descKey = "AdminSetting_TempTeleportSlotCost_Desc" },
    { key = "TempTeleportSetCost", group = "base", type = "integer", default = Config.TempTeleportSetCost or 100, min = 0, max = 100000, target = "TempTeleportSetCost", labelKey = "AdminSetting_TempTeleportSetCost", descKey = "AdminSetting_TempTeleportSetCost_Desc" },
    { key = "WaistAutoRecycleUnlockCost", group = "base", type = "integer", default = Config.WaistAutoRecycleUnlockCost or 100, min = 0, max = 100000, target = "WaistAutoRecycleUnlockCost", labelKey = "AdminSetting_WaistAutoRecycleUnlockCost", descKey = "AdminSetting_WaistAutoRecycleUnlockCost_Desc" },
    { key = "WaistAutoRecycleIntervalHours", group = "base", type = "number", default = Config.WaistAutoRecycleIntervalHours or 1, min = 0.1, max = 168, target = "WaistAutoRecycleIntervalHours", labelKey = "AdminSetting_WaistAutoRecycleIntervalHours", descKey = "AdminSetting_WaistAutoRecycleIntervalHours_Desc" },
    { key = "PositiveTraitCostPerPoint", group = "base", type = "integer", default = Config.PositiveTraitCostPerPoint or 800, min = 0, max = 100000, target = "PositiveTraitCostPerPoint", labelKey = "AdminSetting_PositiveTraitCostPerPoint", descKey = "AdminSetting_PositiveTraitCostPerPoint_Desc" },
    { key = "NegativeTraitRemoveCostPerPoint", group = "base", type = "integer", default = Config.NegativeTraitRemoveCostPerPoint or 500, min = 0, max = 100000, target = "NegativeTraitRemoveCostPerPoint", labelKey = "AdminSetting_NegativeTraitRemoveCostPerPoint", descKey = "AdminSetting_NegativeTraitRemoveCostPerPoint_Desc" },
    { key = "AttributeXPPerCoin", group = "base", type = "integer", default = Config.AttributeXPPerCoin or 10, min = 1, max = 1000000, target = "AttributeXPPerCoin", labelKey = "AdminSetting_AttributeXPPerCoin", descKey = "AdminSetting_AttributeXPPerCoin_Desc" },
    { key = "TerminalReliefUpgradeCost", group = "base", type = "integer", default = Config.TerminalReliefUpgradeCost or 2000, min = 0, max = 100000000, target = "TerminalReliefUpgradeCost", labelKey = "AdminSetting_TerminalReliefUpgradeCost", descKey = "AdminSetting_TerminalReliefUpgradeCost_Desc" },
    { key = "TerminalReliefPerLevel", group = "base", type = "integer", default = Config.TerminalReliefPerLevel or 5, min = 1, max = 5000, target = "TerminalReliefPerLevel", labelKey = "AdminSetting_TerminalReliefPerLevel", descKey = "AdminSetting_TerminalReliefPerLevel_Desc" },
    { key = "TerminalReliefMaxOffset", group = "base", type = "integer", default = Config.TerminalReliefMaxOffset or 2000, min = 0, max = 5000, target = "TerminalReliefMaxOffset", labelKey = "AdminSetting_TerminalReliefMaxOffset", descKey = "AdminSetting_TerminalReliefMaxOffset_Desc" },

    { key = "ShopBuyPriceMultiplier", group = "economy", type = "number", default = 1, min = 0.01, max = 100, labelKey = "AdminSetting_ShopBuyPriceMultiplier", descKey = "AdminSetting_ShopBuyPriceMultiplier_Desc" },
    { key = "RecycleSellPriceMultiplier", group = "economy", type = "number", default = 1, min = 0, max = 100, labelKey = "AdminSetting_RecycleSellPriceMultiplier", descKey = "AdminSetting_RecycleSellPriceMultiplier_Desc" },
    { key = "TaskRewardMultiplier", group = "economy", type = "number", default = 1, min = 0, max = 100, labelKey = "AdminSetting_TaskRewardMultiplier", descKey = "AdminSetting_TaskRewardMultiplier_Desc" },
    { key = "TaskPenaltyMultiplier", group = "economy", type = "number", default = 1, min = 0, max = 100, labelKey = "AdminSetting_TaskPenaltyMultiplier", descKey = "AdminSetting_TaskPenaltyMultiplier_Desc" },
    { key = "MPBackgroundSyncMinutes", group = "economy", type = "number", default = 5, min = 1, max = 60, labelKey = "AdminSetting_MPBackgroundSyncMinutes", descKey = "AdminSetting_MPBackgroundSyncMinutes_Desc" },
    { key = "CompanionPriceMultiplier", group = "economy", type = "number", default = 1, min = 0.01, max = 100, singlePlayerOnly = true, labelKey = "AdminSetting_CompanionPriceMultiplier", descKey = "AdminSetting_CompanionPriceMultiplier_Desc" },
    { key = "LotteryAllPrice", group = "economy", type = "integer", default = Config.LotteryAllPrice or 100, min = 1, max = 100000, target = "LotteryAllPrice", labelKey = "AdminSetting_LotteryAllPrice", descKey = "AdminSetting_LotteryAllPrice_Desc" },
    { key = "LotteryCustomMaxCount", group = "economy", type = "integer", default = Config.LotteryCustomMaxCount or 50, min = 1, max = 500, target = "LotteryCustomMaxCount", labelKey = "AdminSetting_LotteryCustomMaxCount", descKey = "AdminSetting_LotteryCustomMaxCount_Desc" },
    { key = "LotteryPriceLow", group = "economy", type = "integer", default = 60, min = 1, max = 100000, labelKey = "AdminSetting_LotteryPriceLow", descKey = "AdminSetting_LotteryPriceLow_Desc" },
    { key = "LotteryPriceMid", group = "economy", type = "integer", default = 90, min = 1, max = 100000, labelKey = "AdminSetting_LotteryPriceMid", descKey = "AdminSetting_LotteryPriceMid_Desc" },
    { key = "LotteryPriceUtility", group = "economy", type = "integer", default = 150, min = 1, max = 100000, labelKey = "AdminSetting_LotteryPriceUtility", descKey = "AdminSetting_LotteryPriceUtility_Desc" },
    { key = "LotteryPriceVehicle", group = "economy", type = "integer", default = 200, min = 1, max = 100000, labelKey = "AdminSetting_LotteryPriceVehicle", descKey = "AdminSetting_LotteryPriceVehicle_Desc" },
    { key = "LotteryPriceWeapon", group = "economy", type = "integer", default = 400, min = 1, max = 100000, labelKey = "AdminSetting_LotteryPriceWeapon", descKey = "AdminSetting_LotteryPriceWeapon_Desc" },
    { key = "AutoShopListOnlyCostRatio", group = "economy", type = "number", default = Config.AutoShopListOnlyCostRatio or 0.5, min = 0, max = 100, target = "AutoShopListOnlyCostRatio", labelKey = "AdminSetting_AutoShopListOnlyCostRatio", descKey = "AdminSetting_AutoShopListOnlyCostRatio_Desc" },
    { key = "AutoShopListOnlyMinCost", group = "economy", type = "integer", default = Config.AutoShopListOnlyMinCost or 50, min = 0, max = 100000000, target = "AutoShopListOnlyMinCost", labelKey = "AdminSetting_AutoShopListOnlyMinCost", descKey = "AdminSetting_AutoShopListOnlyMinCost_Desc" },
    { key = "BankLoanBaseCredit", group = "economy", type = "integer", default = Config.BankLoanBaseCredit or 2000, min = 0, max = 100000000, target = "BankLoanBaseCredit", labelKey = "AdminSetting_BankLoanBaseCredit", descKey = "AdminSetting_BankLoanBaseCredit_Desc" },
    { key = "BankLoanCreditSpendStep", group = "economy", type = "integer", default = Config.BankLoanCreditSpendStep or 100, min = 1, max = 1000000, target = "BankLoanCreditSpendStep", labelKey = "AdminSetting_BankLoanCreditSpendStep", descKey = "AdminSetting_BankLoanCreditSpendStep_Desc" },
    { key = "BankLoanCreditPerStep", group = "economy", type = "integer", default = Config.BankLoanCreditPerStep or 5, min = 0, max = 1000000, target = "BankLoanCreditPerStep", labelKey = "AdminSetting_BankLoanCreditPerStep", descKey = "AdminSetting_BankLoanCreditPerStep_Desc" },
    { key = "BankLoanSingleInterestRate", group = "economy", type = "number", default = Config.BankLoanSingleInterestRate or 0.05, min = 0, max = 10, target = "BankLoanSingleInterestRate", labelKey = "AdminSetting_BankLoanSingleInterestRate", descKey = "AdminSetting_BankLoanSingleInterestRate_Desc" },
    { key = "BankLoanOverduePenaltyDailyRate", group = "economy", type = "number", default = Config.BankLoanOverduePenaltyDailyRate or 0.05, min = 0, max = 10, target = "BankLoanOverduePenaltyDailyRate", labelKey = "AdminSetting_BankLoanOverduePenaltyDailyRate", descKey = "AdminSetting_BankLoanOverduePenaltyDailyRate_Desc" },
    { key = "BankLoanOverduePenaltyMaxRate", group = "economy", type = "number", default = Config.BankLoanOverduePenaltyMaxRate or 0.5, min = 0, max = 10, target = "BankLoanOverduePenaltyMaxRate", labelKey = "AdminSetting_BankLoanOverduePenaltyMaxRate", descKey = "AdminSetting_BankLoanOverduePenaltyMaxRate_Desc" },
    { key = "BankLoanBankruptcyGraceHours", group = "economy", type = "integer", default = Config.BankLoanBankruptcyGraceHours or 240, min = 1, max = 10000, target = "BankLoanBankruptcyGraceHours", labelKey = "AdminSetting_BankLoanBankruptcyGraceHours", descKey = "AdminSetting_BankLoanBankruptcyGraceHours_Desc" },
    { key = "BankLoanFreezeHours", group = "economy", type = "integer", default = Config.BankLoanFreezeHours or 168, min = 0, max = 10000, target = "BankLoanFreezeHours", labelKey = "AdminSetting_BankLoanFreezeHours", descKey = "AdminSetting_BankLoanFreezeHours_Desc" },
    { key = "BankLoanZombieDebtPerZombie", group = "economy", type = "integer", default = Config.BankLoanZombieDebtPerZombie or 50, min = 1, max = 1000000, target = "BankLoanZombieDebtPerZombie", labelKey = "AdminSetting_BankLoanZombieDebtPerZombie", descKey = "AdminSetting_BankLoanZombieDebtPerZombie_Desc" },
    { key = "BankLoanZombieMaxCount", group = "economy", type = "integer", default = Config.BankLoanZombieMaxCount or 100, min = 0, max = 1000, target = "BankLoanZombieMaxCount", labelKey = "AdminSetting_BankLoanZombieMaxCount", descKey = "AdminSetting_BankLoanZombieMaxCount_Desc" },
    { key = "BankInvestmentMinAmount", group = "economy", type = "integer", default = Config.BankInvestmentMinAmount or 1, min = 1, max = 100000000, target = "BankInvestmentMinAmount", labelKey = "AdminSetting_BankInvestmentMinAmount", descKey = "AdminSetting_BankInvestmentMinAmount_Desc" },
    { key = "BankInvestmentStableGainChance", group = "economy", type = "integer", default = investmentDefault("stable", "gainChance", 70), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentStableGainChance", descKey = "AdminSetting_BankInvestmentStableGainChance_Desc" },
    { key = "BankInvestmentStableLossChance", group = "economy", type = "integer", default = investmentDefault("stable", "lossChance", 5), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentStableLossChance", descKey = "AdminSetting_BankInvestmentStableLossChance_Desc" },
    { key = "BankInvestmentStableGainPercent", group = "economy", type = "number", default = investmentDefault("stable", "gainPercent", 1), min = 0, max = 1000, labelKey = "AdminSetting_BankInvestmentStableGainPercent", descKey = "AdminSetting_BankInvestmentStableGainPercent_Desc" },
    { key = "BankInvestmentStableLossPercent", group = "economy", type = "number", default = investmentDefault("stable", "lossPercent", 1), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentStableLossPercent", descKey = "AdminSetting_BankInvestmentStableLossPercent_Desc" },
    { key = "BankInvestmentBalancedGainChance", group = "economy", type = "integer", default = investmentDefault("balanced", "gainChance", 55), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentBalancedGainChance", descKey = "AdminSetting_BankInvestmentBalancedGainChance_Desc" },
    { key = "BankInvestmentBalancedLossChance", group = "economy", type = "integer", default = investmentDefault("balanced", "lossChance", 30), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentBalancedLossChance", descKey = "AdminSetting_BankInvestmentBalancedLossChance_Desc" },
    { key = "BankInvestmentBalancedGainPercent", group = "economy", type = "number", default = investmentDefault("balanced", "gainPercent", 3), min = 0, max = 1000, labelKey = "AdminSetting_BankInvestmentBalancedGainPercent", descKey = "AdminSetting_BankInvestmentBalancedGainPercent_Desc" },
    { key = "BankInvestmentBalancedLossPercent", group = "economy", type = "number", default = investmentDefault("balanced", "lossPercent", 2), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentBalancedLossPercent", descKey = "AdminSetting_BankInvestmentBalancedLossPercent_Desc" },
    { key = "BankInvestmentAggressiveGainChance", group = "economy", type = "integer", default = investmentDefault("aggressive", "gainChance", 45), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentAggressiveGainChance", descKey = "AdminSetting_BankInvestmentAggressiveGainChance_Desc" },
    { key = "BankInvestmentAggressiveLossChance", group = "economy", type = "integer", default = investmentDefault("aggressive", "lossChance", 45), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentAggressiveLossChance", descKey = "AdminSetting_BankInvestmentAggressiveLossChance_Desc" },
    { key = "BankInvestmentAggressiveGainPercent", group = "economy", type = "number", default = investmentDefault("aggressive", "gainPercent", 8), min = 0, max = 1000, labelKey = "AdminSetting_BankInvestmentAggressiveGainPercent", descKey = "AdminSetting_BankInvestmentAggressiveGainPercent_Desc" },
    { key = "BankInvestmentAggressiveLossPercent", group = "economy", type = "number", default = investmentDefault("aggressive", "lossPercent", 5), min = 0, max = 100, labelKey = "AdminSetting_BankInvestmentAggressiveLossPercent", descKey = "AdminSetting_BankInvestmentAggressiveLossPercent_Desc" },

    { key = "EnableShop", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableShop", descKey = "AdminSetting_EnableShop_Desc" },
    { key = "EnableRecycle", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableRecycle", descKey = "AdminSetting_EnableRecycle_Desc" },
    { key = "EnableBank", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableBank", descKey = "AdminSetting_EnableBank_Desc" },
    { key = "EnableTeleport", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableTeleport", descKey = "AdminSetting_EnableTeleport_Desc" },
    { key = "EnableTraits", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableTraits", descKey = "AdminSetting_EnableTraits_Desc" },
    { key = "EnableWaistAutoRecycle", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableWaistAutoRecycle", descKey = "AdminSetting_EnableWaistAutoRecycle_Desc" },
    { key = "EnableShopLottery", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableShopLottery", descKey = "AdminSetting_EnableShopLottery_Desc" },
    { key = "EnableTasks", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableTasks", descKey = "AdminSetting_EnableTasks_Desc" },
    { key = "EnableBankLoan", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableBankLoan", descKey = "AdminSetting_EnableBankLoan_Desc" },
    { key = "EnableBankInvestments", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableBankInvestments", descKey = "AdminSetting_EnableBankInvestments_Desc" },
    { key = "EnableCompanion", group = "features", type = "boolean", default = true, singlePlayerOnly = true, labelKey = "AdminSetting_EnableCompanion", descKey = "AdminSetting_EnableCompanion_Desc" },
    { key = "EnableAttributes", group = "features", type = "boolean", default = true, labelKey = "AdminSetting_EnableAttributes", descKey = "AdminSetting_EnableAttributes_Desc" },
}

local META_BY_KEY = {}
local BASE_VALUES = {}

local function copyTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function clampNumber(value, fallback, minValue, maxValue, integer)
    local numberValue = tonumber(value)
    if numberValue == nil then
        numberValue = tonumber(fallback) or 0
    end
    if minValue ~= nil and numberValue < minValue then
        numberValue = minValue
    end
    if maxValue ~= nil and numberValue > maxValue then
        numberValue = maxValue
    end
    if integer then
        numberValue = math.floor(numberValue)
    end
    return numberValue
end

local function boolValue(value, fallback)
    if value == nil then
        return fallback == true
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    local text = tostring(value):lower()
    if text == "true" or text == "yes" or text == "on" then
        return true
    end
    return false
end

local function sanitizeText(value, maxLength)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if maxLength and string.len(text) > maxLength then
        text = string.sub(text, 1, maxLength)
    end
    return text
end

local function captureBaseValues()
    for i = 1, #SETTING_META do
        local meta = SETTING_META[i]
        META_BY_KEY[meta.key] = meta
        if meta.target and BASE_VALUES[meta.target] == nil then
            BASE_VALUES[meta.target] = Config[meta.target]
            if BASE_VALUES[meta.target] == nil then
                BASE_VALUES[meta.target] = meta.default
            end
        end
    end
end

captureBaseValues()

function GodSystemAdminConfig.getMeta()
    return copyTable(SETTING_META)
end

function GodSystemAdminConfig.getDefaults()
    local result = {}
    for i = 1, #SETTING_META do
        local meta = SETTING_META[i]
        result[meta.key] = meta.default
    end
    return result
end

function GodSystemAdminConfig.getSandboxDefaults()
    local result = GodSystemAdminConfig.getDefaults()
    local sandbox = SandboxVars and SandboxVars.GodSystem or nil
    if type(sandbox) == "table" then
        for i = 1, #SETTING_META do
            local key = SETTING_META[i].key
            if sandbox[key] ~= nil then
                result[key] = sandbox[key]
            end
        end
    end
    return GodSystemAdminConfig.sanitizeSettings(result)
end

function GodSystemAdminConfig.sanitizeSettings(input)
    local source = type(input) == "table" and input or {}
    local result = {}
    for i = 1, #SETTING_META do
        local meta = SETTING_META[i]
        local value = source[meta.key]
        if meta.type == "boolean" then
            result[meta.key] = boolValue(value, meta.default)
        elseif meta.type == "integer" then
            result[meta.key] = clampNumber(value, meta.default, meta.min, meta.max, true)
        else
            result[meta.key] = clampNumber(value, meta.default, meta.min, meta.max, false)
        end
    end
    local investmentPrefixes = { "BankInvestmentStable", "BankInvestmentBalanced", "BankInvestmentAggressive" }
    for i = 1, #investmentPrefixes do
        local gainKey = investmentPrefixes[i] .. "GainChance"
        local lossKey = investmentPrefixes[i] .. "LossChance"
        result[lossKey] = math.min(result[lossKey] or 0, 100 - (result[gainKey] or 0))
    end
    return result
end

function GodSystemAdminConfig.sanitizeItemOverride(input)
    if type(input) ~= "table" then
        return nil
    end
    local result = {}
    if input.buyPrice ~= nil and tostring(input.buyPrice) ~= "" then
        result.buyPrice = clampNumber(input.buyPrice, 0, 0, 10000000, true)
    end
    if input.sellPrice ~= nil and tostring(input.sellPrice) ~= "" then
        result.sellPrice = clampNumber(input.sellPrice, 0, 0, 10000000, true)
    end
    if input.category ~= nil and tostring(input.category) ~= "" then
        local category = sanitizeText(input.category, 32):lower():gsub("[^a-z0-9_]+", "_")
        if category ~= "" then
            result.category = category
        end
    end
    if input.shopEnabled ~= nil then
        result.shopEnabled = boolValue(input.shopEnabled, true)
    end
    if input.recycleEnabled ~= nil then
        result.recycleEnabled = boolValue(input.recycleEnabled, true)
    end
    if input.lotteryEnabled ~= nil then
        result.lotteryEnabled = boolValue(input.lotteryEnabled, true)
    end
    if input.note ~= nil and tostring(input.note) ~= "" then
        result.note = sanitizeText(input.note, 120)
    end
    if next(result) == nil then
        return nil
    end
    return result
end

local function sanitizeItemOverrides(input)
    local result = {}
    if type(input) ~= "table" then
        return result
    end
    for fullType, override in pairs(input) do
        local key = sanitizeText(fullType, 120)
        local clean = GodSystemAdminConfig.sanitizeItemOverride(override)
        if key ~= "" and clean then
            result[key] = clean
        end
    end
    return result
end

local function applyLotteryCategoryPrices(settings)
    Config.LotteryCategoryPrices = Config.LotteryCategoryPrices or {}
    local low = settings.LotteryPriceLow
    local mid = settings.LotteryPriceMid
    local utility = settings.LotteryPriceUtility
    local vehicle = settings.LotteryPriceVehicle
    local weapon = settings.LotteryPriceWeapon
    local lowCategories = { "food", "drink", "material", "normal", "other", "casing", "cooking", "drainable", "farming", "fire", "key", "literature" }
    local midCategories = { "medical", "clothing", "accessory" }
    local utilityCategories = { "tool", "electronics", "security", "ammo", "container" }
    for i = 1, #lowCategories do
        Config.LotteryCategoryPrices[lowCategories[i]] = low
    end
    for i = 1, #midCategories do
        Config.LotteryCategoryPrices[midCategories[i]] = mid
    end
    for i = 1, #utilityCategories do
        Config.LotteryCategoryPrices[utilityCategories[i]] = utility
    end
    Config.LotteryCategoryPrices.vehicle = vehicle
    Config.LotteryCategoryPrices.weapon = weapon
end

local function applyBankInvestmentSettings(settings)
    Config.BankInvestmentProfiles = Config.BankInvestmentProfiles or {}
    local tiers = {
        { id = "stable", prefix = "BankInvestmentStable", defaults = { 70, 5, 1, 1 } },
        { id = "balanced", prefix = "BankInvestmentBalanced", defaults = { 55, 30, 3, 2 } },
        { id = "aggressive", prefix = "BankInvestmentAggressive", defaults = { 45, 45, 8, 5 } },
    }
    for i = 1, #tiers do
        local tier = tiers[i]
        local gainChance = clampNumber(settings[tier.prefix .. "GainChance"], tier.defaults[1], 0, 100, true)
        local lossChance = clampNumber(settings[tier.prefix .. "LossChance"], tier.defaults[2], 0, 100 - gainChance, true)
        Config.BankInvestmentProfiles[tier.id] = {
            id = tier.id,
            gainChance = gainChance,
            lossChance = lossChance,
            gainPercent = clampNumber(settings[tier.prefix .. "GainPercent"], tier.defaults[3], 0, 1000, false),
            lossPercent = clampNumber(settings[tier.prefix .. "LossPercent"], tier.defaults[4], 0, 100, false),
        }
    end
end

function GodSystemAdminConfig.applyRuntime(settings, itemOverrides)
    local cleanSettings = GodSystemAdminConfig.sanitizeSettings(settings)
    local staticOverrides = sanitizeItemOverrides(Config.ItemOverrides or {})
    local runtimeOverrides = sanitizeItemOverrides(itemOverrides or {})
    for fullType, override in pairs(runtimeOverrides) do
        staticOverrides[fullType] = override
    end

    Config.AdminRuntimeSettings = cleanSettings
    Config.AdminRuntimeItemOverrides = staticOverrides

    for i = 1, #SETTING_META do
        local meta = SETTING_META[i]
        if meta.target then
            local base = BASE_VALUES[meta.target]
            local value = cleanSettings[meta.key]
            if value == nil then
                value = base
            end
            Config[meta.target] = value
        end
    end

    if GodSystemProtocol and cleanSettings.MPBackgroundSyncMinutes then
        GodSystemProtocol.BackgroundSyncMs = math.max(60000, math.floor(cleanSettings.MPBackgroundSyncMinutes * 60000))
    end
    applyLotteryCategoryPrices(cleanSettings)
    applyBankInvestmentSettings(cleanSettings)

    return cleanSettings, staticOverrides
end

function GodSystemAdminConfig.getSetting(key, fallback)
    local settings = Config.AdminRuntimeSettings or {}
    if settings[key] ~= nil then
        return settings[key]
    end
    local meta = META_BY_KEY[key]
    if meta then
        return meta.default
    end
    return fallback
end

function GodSystemAdminConfig.isFeatureEnabled(key)
    return GodSystemAdminConfig.getSetting(key, true) == true
end

function GodSystemAdminConfig.getItemOverride(fullType)
    if not fullType then
        return nil
    end
    local overrides = Config.AdminRuntimeItemOverrides or {}
    return overrides[tostring(fullType)]
end

function GodSystemAdminConfig.getItemOverrides()
    return copyTable(Config.AdminRuntimeItemOverrides or {})
end

function GodSystemAdminConfig.applyShopBuyPrice(fullType, price)
    price = math.max(0, math.floor(tonumber(price) or 0))
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.buyPrice ~= nil then
        return math.max(0, math.floor(tonumber(override.buyPrice) or 0))
    end
    local multiplier = tonumber(GodSystemAdminConfig.getSetting("ShopBuyPriceMultiplier", 1)) or 1
    return math.max(0, math.floor(price * multiplier))
end

function GodSystemAdminConfig.applySellPrice(fullType, price)
    price = math.max(0, math.floor(tonumber(price) or 0))
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.sellPrice ~= nil then
        return math.max(0, math.floor(tonumber(override.sellPrice) or 0))
    end
    local multiplier = tonumber(GodSystemAdminConfig.getSetting("RecycleSellPriceMultiplier", 1)) or 1
    return math.max(0, math.floor(price * multiplier))
end

function GodSystemAdminConfig.applyTaskReward(value)
    local multiplier = tonumber(GodSystemAdminConfig.getSetting("TaskRewardMultiplier", 1)) or 1
    return math.max(0, math.floor((tonumber(value) or 0) * multiplier))
end

function GodSystemAdminConfig.applyTaskPenalty(value)
    local multiplier = tonumber(GodSystemAdminConfig.getSetting("TaskPenaltyMultiplier", 1)) or 1
    return math.max(0, math.floor((tonumber(value) or 0) * multiplier))
end

function GodSystemAdminConfig.applyCategory(fullType, category)
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.category and override.category ~= "" then
        return override.category
    end
    return category
end

function GodSystemAdminConfig.isShopItemEnabled(fullType, fallback)
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.shopEnabled ~= nil then
        return override.shopEnabled == true
    end
    return fallback ~= false
end

function GodSystemAdminConfig.isRecycleItemEnabled(fullType, fallback)
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.recycleEnabled ~= nil then
        return override.recycleEnabled == true
    end
    return fallback ~= false
end

function GodSystemAdminConfig.isLotteryItemEnabled(fullType, fallback)
    local override = GodSystemAdminConfig.getItemOverride(fullType)
    if override and override.lotteryEnabled ~= nil then
        return override.lotteryEnabled == true
    end
    return fallback ~= false
end

function GodSystemAdminConfig.buildSnapshot()
    local settings = GodSystemAdminConfig.sanitizeSettings(Config.AdminRuntimeSettings or nil)
    local overrides = GodSystemAdminConfig.getItemOverrides()
    return {
        settings = settings,
        itemOverrides = overrides,
        meta = GodSystemAdminConfig.getMeta(),
    }
end

GodSystemAdminConfig.applyRuntime(Config.AdminRuntimeSettings or nil, Config.AdminRuntimeItemOverrides or nil)
