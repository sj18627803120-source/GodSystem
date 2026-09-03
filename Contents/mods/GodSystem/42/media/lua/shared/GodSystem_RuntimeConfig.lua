GodSystemRuntimeConfig = GodSystemRuntimeConfig or {}

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

function GodSystemRuntimeConfig.readSandbox()
    local source = SandboxVars and SandboxVars.GodSystem or {}
    GodSystemRuntimeConfig.Current = GodSystemRuntimeConfig.fromSandbox(source)
    applyDirectConfigValues(GodSystemRuntimeConfig.Current)
    return GodSystemRuntimeConfig.Current
end

function GodSystemRuntimeConfig.applySnapshot(snapshot)
    GodSystemRuntimeConfig.Current = GodSystemRuntimeConfig.fromSandbox(snapshot)
    applyDirectConfigValues(GodSystemRuntimeConfig.Current)
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
