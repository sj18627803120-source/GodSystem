require "GodSystem_Equipment"
GodSystemRuntimeConfig = GodSystemRuntimeConfig or {}
GodSystemRuntimeConfig.PricingRevision = math.max(1, tonumber(GodSystemRuntimeConfig.PricingRevision) or 1)
GodSystemRuntimeConfig._pricingSignature = GodSystemRuntimeConfig._pricingSignature or ""

local RANGE_DEFAULTS = {
    EnableRangeRecycle = true,
    RangeRecycleRadius = 5,
    RangeRecycleBatchIntervalSeconds = 0.25,
}

local PERFORMANCE_DEFAULTS = {
    CompanionAttackSearchSeconds = 0.5,
    CompanionAttackSearchCandidateLimit = 8,
    HomeSafeZoneScanIntervalHours = 1,
    HomeSafeZoneScanBudget = 256,
    HomeSafeZoneClearLimit = 64,
    LotteryItemCacheBuildRate = 100,
}

local TASK_UPGRADE_SCHEMA = 2
local TASK_TEMPLATE_BASELINE_HOURS = 24
local TASK_LIMITS = {
    activeTasks = {
        baseKey = "MaxActiveTasks",
        defaultBase = 3,
        maximumKey = "MaxActiveTaskLimit",
        defaultMaximum = 10,
        bonusKey = "maxActiveTaskBonus",
        legacyKey = "maxActiveTasks",
    },
    dailyTasks = {
        baseKey = "DailyTaskCount",
        defaultBase = 5,
        maximumKey = "MaxDailyTaskLimit",
        defaultMaximum = 20,
        bonusKey = "dailyTaskBonus",
        legacyKey = "dailyTaskCount",
    },
}

local function boolValue(value, fallback)
    if value == nil then return fallback == true end
    if value == true or value == 1 or value == "1" then return true end
    if value == false or value == 0 or value == "0" then return false end
    local text = tostring(value):lower()
    if text == "true" then return true end
    if text == "false" then return false end
    return fallback == true
end

local function clampNumber(value, fallback, minimum, maximum)
    local number = tonumber(value)
    if number == nil then number = fallback end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function copyScalars(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        local valueType = type(value)
        if valueType == "boolean" or valueType == "number" or valueType == "string" then
            result[tostring(key)] = value
        end
    end
    return result
end

function GodSystemRuntimeConfig.fromSandbox(source)
    local result = copyScalars(source)
    result.EnableTeleportFallback = boolValue(result.EnableTeleportFallback, true)
    result.DeathProtectionCost = math.floor(clampNumber(result.DeathProtectionCost, 20000, 0, 1000000))
    result.EnableEquipment = boolValue(result.EnableEquipment, true)
    result.EnableEquipmentFreeze = boolValue(result.EnableEquipmentFreeze, true)
    result.EnableEquipmentSplash = boolValue(result.EnableEquipmentSplash, true)
    result.EquipmentFreezeVisuals = boolValue(result.EquipmentFreezeVisuals, true)
    result.EnableTasks = boolValue(result.EnableTasks, true)
    result.EnableRecycleListing = boolValue(result.EnableRecycleListing, true)
    result.DailyTaskCount = math.floor(clampNumber(result.DailyTaskCount, 5, 0, 20))
    result.MaxActiveTasks = math.floor(clampNumber(result.MaxActiveTasks, 3, 0, 10))
    result.RefreshTaskCost = math.floor(clampNumber(result.RefreshTaskCost, 30, 0, 100000))
    result.DefaultTaskLimitHours = math.floor(clampNumber(result.DefaultTaskLimitHours, 24, 1, 168))
    result.TaskRewardMultiplier = clampNumber(result.TaskRewardMultiplier, 1, 0, 100)
    result.TaskPenaltyMultiplier = clampNumber(result.TaskPenaltyMultiplier, 1, 0, 100)
    result.EnableShopDynamicInflation = boolValue(result.EnableShopDynamicInflation, true)
    result.ShopDynamicInflationPercent = clampNumber(result.ShopDynamicInflationPercent, 10, 0, 100)
    result.ShopDynamicInflationHours = math.floor(clampNumber(result.ShopDynamicInflationHours, 24, 1, 720))
    result.EnableUtilityGenerator = boolValue(result.EnableUtilityGenerator, true)
    result.EnableUtilityGeneratorWater = boolValue(result.EnableUtilityGeneratorWater, true)
    result.EnableUtilityGeneratorElectricity = boolValue(result.EnableUtilityGeneratorElectricity, true)
    result.UtilityGeneratorWaterPricePer100L = clampNumber(result.UtilityGeneratorWaterPricePer100L, 20, 0, 1000000)
    result.UtilityGeneratorElectricityPricePerFuelUnit = clampNumber(result.UtilityGeneratorElectricityPricePerFuelUnit, 5, 0, 1000000)
    for key, rule in pairs(GodSystemEquipment.Settings) do
        if result[key] == nil then result[key] = rule[1] end
    end
    result.EnableRangeRecycle = boolValue(result.EnableRangeRecycle, RANGE_DEFAULTS.EnableRangeRecycle)
    result.RangeRecycleRadius = math.floor(clampNumber(
        result.RangeRecycleRadius,
        RANGE_DEFAULTS.RangeRecycleRadius,
        1,
        10
    ))
    result.RangeRecycleBatchIntervalSeconds = clampNumber(
        result.RangeRecycleBatchIntervalSeconds,
        RANGE_DEFAULTS.RangeRecycleBatchIntervalSeconds,
        0.10,
        2.00
    )
    result.CompanionAttackSearchSeconds = clampNumber(
        result.CompanionAttackSearchSeconds,
        PERFORMANCE_DEFAULTS.CompanionAttackSearchSeconds,
        0.10,
        10.00
    )
    result.CompanionAttackSearchCandidateLimit = math.floor(clampNumber(
        result.CompanionAttackSearchCandidateLimit,
        PERFORMANCE_DEFAULTS.CompanionAttackSearchCandidateLimit,
        1,
        64
    ))
    result.HomeSafeZoneScanIntervalHours = clampNumber(
        result.HomeSafeZoneScanIntervalHours,
        PERFORMANCE_DEFAULTS.HomeSafeZoneScanIntervalHours,
        0.25,
        24
    )
    result.HomeSafeZoneScanBudget = math.floor(clampNumber(
        result.HomeSafeZoneScanBudget,
        PERFORMANCE_DEFAULTS.HomeSafeZoneScanBudget,
        1,
        4096
    ))
    result.HomeSafeZoneClearLimit = math.floor(clampNumber(
        result.HomeSafeZoneClearLimit,
        PERFORMANCE_DEFAULTS.HomeSafeZoneClearLimit,
        1,
        1024
    ))
    result.LotteryItemCacheBuildRate = math.floor(clampNumber(
        result.LotteryItemCacheBuildRate,
        PERFORMANCE_DEFAULTS.LotteryItemCacheBuildRate,
        1,
        10000
    ))
    return result
end

local function applyBankInvestmentProfiles(snapshot)
    if not GodSystemConfig then return end
    GodSystemConfig.BankInvestmentProfiles = GodSystemConfig.BankInvestmentProfiles or {}
    local tiers = {
        { id = "stable", prefix = "BankInvestmentStable" },
        { id = "balanced", prefix = "BankInvestmentBalanced" },
        { id = "aggressive", prefix = "BankInvestmentAggressive" },
    }
    for i = 1, #tiers do
        local tier = tiers[i]
        local current = GodSystemConfig.BankInvestmentProfiles[tier.id] or {}
        local gainChance = tonumber(snapshot[tier.prefix .. "GainChance"])
        local lossChance = tonumber(snapshot[tier.prefix .. "LossChance"])
        GodSystemConfig.BankInvestmentProfiles[tier.id] = {
            id = current.id or tier.id,
            labelKey = current.labelKey,
            gainChance = gainChance or current.gainChance,
            lossChance = math.min(lossChance or current.lossChance or 0, 100 - (gainChance or current.gainChance or 0)),
            gainPercent = tonumber(snapshot[tier.prefix .. "GainPercent"]) or current.gainPercent,
            lossPercent = tonumber(snapshot[tier.prefix .. "LossPercent"]) or current.lossPercent,
        }
    end
end

local function applyDirectConfigValues(snapshot)
    if not GodSystemConfig then return end
    for key, value in pairs(snapshot) do
        if GodSystemConfig[key] ~= nil then GodSystemConfig[key] = value end
    end
    applyBankInvestmentProfiles(snapshot)
end

local function refreshPricingRevision(snapshot)
    local signature = table.concat({
        tostring(snapshot and snapshot.ShopBuyPriceMultiplier or GodSystemConfig and GodSystemConfig.ShopBuyPriceMultiplier or 1),
        tostring(snapshot and snapshot.RecycleSellPriceMultiplier or GodSystemConfig and GodSystemConfig.RecycleSellPriceMultiplier or 1),
        tostring(snapshot and snapshot.RecycleSellRatio or GodSystemConfig and GodSystemConfig.RecycleSellRatio or 0.05),
        tostring(snapshot and snapshot.EconomyConversionSafetyMargin or GodSystemConfig and GodSystemConfig.EconomyConversionSafetyMargin or 0.10),
    }, "|")
    if GodSystemRuntimeConfig._pricingSignature ~= signature then
        GodSystemRuntimeConfig._pricingSignature = signature
        GodSystemRuntimeConfig.PricingRevision = GodSystemRuntimeConfig.PricingRevision + 1
        if GodSystemEconomyPolicy and GodSystemEconomyPolicy.invalidate then GodSystemEconomyPolicy.invalidate("runtimePricing") end
        if GodSystemEconomyPolicy and GodSystemEconomyPolicy.rebuildConversionFloors then GodSystemEconomyPolicy.rebuildConversionFloors() end
    end
end

function GodSystemRuntimeConfig.readSandbox()
    if GodSystemRuntimeConfig.Source == "server" and isClient and isClient() then
        return GodSystemRuntimeConfig.Current
    end
    local source = SandboxVars and SandboxVars.GodSystem or {}
    GodSystemRuntimeConfig.Current = GodSystemRuntimeConfig.fromSandbox(source)
    if GodSystemShopInflation and ModData and ModData.getOrCreate then
        GodSystemShopInflation.observeConfig(ModData.getOrCreate("GodSystem_CN_ShopEconomyConfig"), GodSystemRuntimeConfig.Current)
    end
    GodSystemRuntimeConfig.Source = "sandbox"
    applyDirectConfigValues(GodSystemRuntimeConfig.Current)
    refreshPricingRevision(GodSystemRuntimeConfig.Current)
    return GodSystemRuntimeConfig.Current
end

function GodSystemRuntimeConfig.applySnapshot(snapshot)
    GodSystemRuntimeConfig.Current = GodSystemRuntimeConfig.fromSandbox(snapshot)
    GodSystemRuntimeConfig.Current.ShopInflationGeneration = snapshot and snapshot.ShopInflationGeneration or 0
    GodSystemRuntimeConfig.Source = "server"
    applyDirectConfigValues(GodSystemRuntimeConfig.Current)
    refreshPricingRevision(GodSystemRuntimeConfig.Current)
    return GodSystemRuntimeConfig.Current
end

function GodSystemRuntimeConfig.snapshot()
    local current = GodSystemRuntimeConfig.Current or GodSystemRuntimeConfig.readSandbox()
    return copyScalars(current)
end

function GodSystemRuntimeConfig.get(key, fallback)
    local current = GodSystemRuntimeConfig.Current or GodSystemRuntimeConfig.readSandbox()
    local value = current[tostring(key or "")]
    if value == nil and GodSystemConfig then value = GodSystemConfig[tostring(key or "")] end
    if value == nil then return fallback end
    return value
end

function GodSystemRuntimeConfig.isFeatureEnabled(key, fallback)
    return boolValue(GodSystemRuntimeConfig.get(key, fallback ~= false), fallback ~= false)
end

function GodSystemRuntimeConfig.applyTaskReward(value)
    local multiplier = tonumber(GodSystemRuntimeConfig.get("TaskRewardMultiplier", 1)) or 1
    return math.max(0, math.floor((tonumber(value) or 0) * multiplier))
end

function GodSystemRuntimeConfig.applyTaskPenalty(value)
    local multiplier = tonumber(GodSystemRuntimeConfig.get("TaskPenaltyMultiplier", 1)) or 1
    return math.max(0, math.floor((tonumber(value) or 0) * multiplier))
end

local function taskLimitRule(upgradeType)
    return TASK_LIMITS[tostring(upgradeType or "")]
end

local function taskLimitBase(rule)
    return math.max(0, math.floor(tonumber(GodSystemRuntimeConfig.get(rule.baseKey, rule.defaultBase)) or rule.defaultBase))
end

local function taskLimitMaximum(rule)
    local value = rule.defaultMaximum
    if GodSystemConfig then value = GodSystemConfig[rule.maximumKey] or value end
    return math.max(0, math.floor(tonumber(value) or rule.defaultMaximum))
end

function GodSystemRuntimeConfig.normalizeTaskUpgrades(upgrades)
    upgrades = type(upgrades) == "table" and upgrades or {}
    local schema = math.floor(tonumber(upgrades.taskLimitSchema) or 0)
    if schema < TASK_UPGRADE_SCHEMA then
        -- The previous fields stored absolute limits and allowed old values to
        -- override a lower sandbox base.  v3.1 intentionally starts the new
        -- additive model clean instead of guessing which values were bought.
        upgrades.maxActiveTaskBonus = 0
        upgrades.dailyTaskBonus = 0
    end
    upgrades.taskLimitSchema = TASK_UPGRADE_SCHEMA
    for _, rule in pairs(TASK_LIMITS) do
        local maximum = taskLimitMaximum(rule)
        local bonus = math.max(0, math.floor(tonumber(upgrades[rule.bonusKey]) or 0))
        upgrades[rule.bonusKey] = math.min(maximum, bonus)
        upgrades[rule.legacyKey] = math.min(maximum, taskLimitBase(rule) + upgrades[rule.bonusKey])
    end
    return upgrades
end

function GodSystemRuntimeConfig.getTaskLimit(upgrades, upgradeType)
    local rule = taskLimitRule(upgradeType)
    if not rule then return 0 end
    upgrades = GodSystemRuntimeConfig.normalizeTaskUpgrades(upgrades)
    return math.min(taskLimitMaximum(rule), taskLimitBase(rule) + upgrades[rule.bonusKey])
end

function GodSystemRuntimeConfig.increaseTaskLimitUpgrade(upgrades, upgradeType)
    local rule = taskLimitRule(upgradeType)
    if not rule then return false, 0 end
    upgrades = GodSystemRuntimeConfig.normalizeTaskUpgrades(upgrades)
    local current = GodSystemRuntimeConfig.getTaskLimit(upgrades, upgradeType)
    local maximum = taskLimitMaximum(rule)
    if current >= maximum then return false, current end
    upgrades[rule.bonusKey] = upgrades[rule.bonusKey] + 1
    GodSystemRuntimeConfig.normalizeTaskUpgrades(upgrades)
    return true, GodSystemRuntimeConfig.getTaskLimit(upgrades, upgradeType)
end

function GodSystemRuntimeConfig.effectiveTaskLimitHours(template)
    template = type(template) == "table" and template or {}
    local configured = math.max(1, math.floor(tonumber(GodSystemRuntimeConfig.get(
        "DefaultTaskLimitHours",
        TASK_TEMPLATE_BASELINE_HOURS
    )) or TASK_TEMPLATE_BASELINE_HOURS))
    local templateHours = math.max(1, math.floor(tonumber(template.limitHours) or TASK_TEMPLATE_BASELINE_HOURS))
    local adjusted = math.max(1, templateHours + configured - TASK_TEMPLATE_BASELINE_HOURS)
    if tostring(template.kind or "") == "surviveHours" then
        adjusted = math.max(adjusted, math.floor(tonumber(template.target) or 1))
    end
    return adjusted
end

function GodSystemRuntimeConfig.taskGenerationToken()
    local enabled = GodSystemRuntimeConfig.isFeatureEnabled("EnableTasks", true) and "1" or "0"
    return table.concat({
        "task-v2",
        enabled,
        tostring(math.floor(tonumber(GodSystemRuntimeConfig.get("DailyTaskCount", 5)) or 5)),
        tostring(math.floor(tonumber(GodSystemRuntimeConfig.get("DefaultTaskLimitHours", 24)) or 24)),
        tostring(tonumber(GodSystemRuntimeConfig.get("TaskRewardMultiplier", 1)) or 1),
        tostring(tonumber(GodSystemRuntimeConfig.get("TaskPenaltyMultiplier", 1)) or 1),
    }, "|")
end
