GodSystemCompanionConfig = GodSystemCompanionConfig or {}

local Config = GodSystemCompanionConfig

Config.UnlockCost = 100
Config.AttackUnlockCost = 200
Config.SightUnlockCost = 800
Config.GuardianUnlockCost = 1200
Config.SightDurationSeconds = 10
Config.SightTargetCap = 50
Config.GuardianScanSeconds = 0.25
Config.GuardianTriggerRadius = 3
Config.GuardianTriggerCount = 1
Config.ResonanceBaseCost = 2500
Config.ResonanceCostStep = 500
Config.ResonanceDamagePerLevel = 0.01
Config.EffectOrder = { "shock", "corrosion", "mark", "chain", "blast" }
Config.Effects = {
    shock = { cost = 1000, labelKey = "Companion_EffectShock", detailKey = "Companion_EffectShockDetail" },
    corrosion = { cost = 2000, labelKey = "Companion_EffectCorrosion", detailKey = "Companion_EffectCorrosionDetail" },
    mark = { cost = 4000, labelKey = "Companion_EffectMark", detailKey = "Companion_EffectMarkDetail" },
    chain = { cost = 8000, labelKey = "Companion_EffectChain", detailKey = "Companion_EffectChainDetail" },
    blast = { cost = 16000, labelKey = "Companion_EffectBlast", detailKey = "Companion_EffectBlastDetail" },
}
Config.ShockInternalCooldownSeconds = 2
Config.CorrosionDurationSeconds = 3
Config.CorrosionTickSeconds = 1
Config.CorrosionDamageRatio = 0.10
Config.MarkDurationSeconds = 6
Config.MarkDamageMultiplier = 1.20
Config.ChainRadius = 3
Config.ChainDamageRatio = 0.50
Config.BlastRadius = 2
Config.BlastTargetCap = 4
Config.BlastDamageRatio = 0.25
Config.ProjectileTravelSeconds = 0.35
Config.AttackSearchSeconds = 0.5
Config.AttackSearchCandidateLimit = 8
Config.ProjectionRebuildDistance = 24
Config.RobotFrameSeconds = 0.18
Config.RobotOrbitRetargetMinSeconds = 2.5
Config.RobotOrbitRetargetMaxSeconds = 4.5
Config.RobotIdleMinSeconds = 2
Config.RobotIdleMaxSeconds = 5
Config.RobotCombatGraceSeconds = 3
Config.RobotGuardDriftRadius = 1.5
Config.RobotRecallDistance = 24
Config.RobotCatchupMargin = 2
Config.RobotNormalSpeed = 1.2
Config.RobotCatchupSpeed = 4.5
Config.RobotBobPixels = 3
Config.RobotDrawHalfWidth = 16
Config.RobotDrawHalfHeight = 13
Config.RobotSensorOffset = 3
Config.RobotChargeSeconds = 0.20
Config.RobotRecoverySeconds = 0.15
Config.RobotLookMinSeconds = 0.8
Config.RobotLookMaxSeconds = 1.4
Config.RobotNearPatrolChance = 0.25
Config.RobotCombatStrafeMinSeconds = 1.2
Config.RobotCombatStrafeMaxSeconds = 2.0
Config.RobotTrailSeconds = 0.12
Config.RobotDirections = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
Config.RobotFollowBands = {
    follow3 = { minimum = 1.5, maximum = 3 },
    follow5 = { minimum = 2, maximum = 5 },
    follow10 = { minimum = 4, maximum = 10 },
}

Config.Unlocks = {
    projection = { cost = Config.UnlockCost, labelKey = "Companion_Unlock" },
    attack = { cost = Config.AttackUnlockCost, requires = "projection", labelKey = "Companion_Attack" },
    sight = { cost = Config.SightUnlockCost, requires = "projection", labelKey = "Companion_Sight" },
    guardian = { cost = Config.GuardianUnlockCost, requires = "projection", labelKey = "Companion_Guardian" },
}

Config.StatOrder = {
    "light", "attackDamage", "attackCooldown", "attackRange",
    "sightRange", "sightCooldown", "guardianRange", "guardianCount", "guardianCooldown",
}

Config.Stats = {
    light = {
        values = { 6, 8, 10, 12, 15 },
        costs = { 100, 200, 400, 800 },
        requires = "projection",
        labelKey = "Companion_Light",
    },
    attackDamage = {
        values = { 0.40, 0.52, 0.66, 0.82, 1.00, 1.20 },
        costs = { 100, 200, 400, 800, 1600 },
        requires = "attack",
        labelKey = "Companion_AttackDamage",
    },
    attackCooldown = {
        values = { 4.0, 3.2, 2.6, 2.0, 1.5, 1.0 },
        costs = { 150, 300, 600, 1200, 2400 },
        requires = "attack",
        labelKey = "Companion_AttackCooldown",
    },
    attackRange = {
        values = { 6, 8, 10, 12, 15 },
        costs = { 100, 250, 500, 1000 },
        requires = "attack",
        labelKey = "Companion_AttackRange",
    },
    sightRange = {
        values = { 20, 30, 40, 50 },
        costs = { 300, 700, 1500 },
        requires = "sight",
        labelKey = "Companion_SightRange",
    },
    sightCooldown = {
        values = { 120, 90, 60, 30 },
        costs = { 400, 900, 1800 },
        requires = "sight",
        labelKey = "Companion_SightCooldown",
    },
    guardianRange = {
        values = { 4, 5, 6, 8 },
        costs = { 400, 800, 1600 },
        requires = "guardian",
        labelKey = "Companion_GuardianRange",
    },
    guardianCount = {
        values = { 4, 6, 9, 12 },
        costs = { 300, 700, 1400 },
        requires = "guardian",
        labelKey = "Companion_GuardianCount",
    },
    guardianCooldown = {
        values = { 90, 60, 40, 25 },
        costs = { 500, 1000, 2000 },
        requires = "guardian",
        labelKey = "Companion_GuardianCooldown",
    },
}

local function clampInteger(value, minimum, maximum)
    value = math.floor(tonumber(value) or minimum)
    return math.max(minimum, math.min(maximum, value))
end

function Config.ensureData(value)
    local data = type(value) == "table" and value or {}
    data.unlocked = data.unlocked == true
    data.unlocks = type(data.unlocks) == "table" and data.unlocks or {}
    data.unlocks.attack = data.unlocks.attack == true
    data.unlocks.sight = data.unlocks.sight == true
    data.unlocks.guardian = data.unlocks.guardian == true
    data.levels = type(data.levels) == "table" and data.levels or {}
    for id, definition in pairs(Config.Stats) do
        data.levels[id] = clampInteger(data.levels[id], 1, #definition.values)
    end
    data.resonance = math.max(0, math.floor(tonumber(data.resonance) or 0))
    data.effects = type(data.effects) == "table" and data.effects or {}
    for _, id in ipairs(Config.EffectOrder) do
        data.effects[id] = data.effects[id] == true
    end
    if data.combatMode ~= "active" and data.combatMode ~= "ceasefire" then
        data.combatMode = "defensive"
    end
    if data.followMode ~= "follow3" and data.followMode ~= "follow10" and data.followMode ~= "guard" then
        data.followMode = "follow5"
    end
    data.visualMode = nil
    if data.visible == nil then data.visible = true else data.visible = data.visible == true end
    if data.guardianEnabled == nil then data.guardianEnabled = true else data.guardianEnabled = data.guardianEnabled == true end
    data.guardPoint = type(data.guardPoint) == "table" and data.guardPoint or nil
    data.appearance = nil
    data.cooldowns = type(data.cooldowns) == "table" and data.cooldowns or {}
    data.cooldowns.attack = math.max(0, tonumber(data.cooldowns.attack) or 0)
    data.cooldowns.sight = math.max(0, tonumber(data.cooldowns.sight) or 0)
    data.cooldowns.guardian = math.max(0, tonumber(data.cooldowns.guardian) or 0)
    data.ui = type(data.ui) == "table" and data.ui or {}
    data.ui.shortcutVisible = data.ui.shortcutVisible == true
    data.ui.shortcutX = tonumber(data.ui.shortcutX)
    data.ui.shortcutY = tonumber(data.ui.shortcutY)
    return data
end

function Config.isEnabled()
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        return GodSystemRuntimeConfig.get("EnableCompanion", true) == true
    end
    return true
end

function Config.getPriceMultiplier()
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        return math.max(0.01, tonumber(GodSystemRuntimeConfig.get("CompanionPriceMultiplier", 1)) or 1)
    end
    return 1
end

function Config.getAttackSearchSeconds()
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        return math.max(0.10, tonumber(GodSystemRuntimeConfig.get("CompanionAttackSearchSeconds", Config.AttackSearchSeconds)) or Config.AttackSearchSeconds)
    end
    return Config.AttackSearchSeconds
end

function Config.getAttackSearchCandidateLimit()
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        return math.max(1, math.floor(tonumber(GodSystemRuntimeConfig.get("CompanionAttackSearchCandidateLimit", Config.AttackSearchCandidateLimit)) or Config.AttackSearchCandidateLimit))
    end
    return Config.AttackSearchCandidateLimit
end

function Config.scaleCost(cost)
    return math.max(1, math.floor((tonumber(cost) or 0) * Config.getPriceMultiplier() + 0.5))
end

function Config.isUnlocked(data, unlockId)
    data = Config.ensureData(data)
    if unlockId == "projection" then return data.unlocked end
    return data.unlocks[unlockId] == true
end

function Config.getStatValue(data, statId)
    data = Config.ensureData(data)
    local definition = Config.Stats[statId]
    if not definition then return nil end
    return definition.values[data.levels[statId] or 1]
end

function Config.getUpgradeCost(data, statId)
    data = Config.ensureData(data)
    local definition = Config.Stats[statId]
    if not definition then return nil end
    local level = data.levels[statId] or 1
    local cost = definition.costs[level]
    return cost and Config.scaleCost(cost) or nil
end

function Config.isFunctionalMax(data)
    data = Config.ensureData(data)
    if not data.unlocked or not data.unlocks.attack or not data.unlocks.sight or not data.unlocks.guardian then
        return false
    end
    for id, definition in pairs(Config.Stats) do
        if (data.levels[id] or 1) < #definition.values then return false end
    end
    return true
end

function Config.isEffectUnlocked(data, effectId)
    data = Config.ensureData(data)
    return data.effects[effectId] == true
end

function Config.canUnlockEffect(data, effectId)
    data = Config.ensureData(data)
    if not data.unlocked or not data.unlocks.attack or data.effects[effectId] == true then return false end
    for index, id in ipairs(Config.EffectOrder) do
        if id == effectId then
            return index == 1 or data.effects[Config.EffectOrder[index - 1]] == true
        end
    end
    return false
end

function Config.getEffectCost(data, effectId)
    local definition = Config.Effects[effectId]
    if not definition or not Config.canUnlockEffect(data, effectId) then return nil end
    return Config.scaleCost(definition.cost)
end

function Config.areAllEffectsUnlocked(data)
    data = Config.ensureData(data)
    for _, id in ipairs(Config.EffectOrder) do
        if data.effects[id] ~= true then return false end
    end
    return true
end

function Config.canPurchaseResonance(data)
    return Config.isFunctionalMax(data) and Config.areAllEffectsUnlocked(data)
end

function Config.getResonanceCost(data)
    data = Config.ensureData(data)
    if not Config.canPurchaseResonance(data) then return nil end
    return Config.scaleCost(Config.ResonanceBaseCost + data.resonance * Config.ResonanceCostStep)
end

function Config.getFinalDamage(data)
    local base = Config.getStatValue(data, "attackDamage") or 0
    return base * (1 + math.max(0, tonumber(data and data.resonance) or 0) * Config.ResonanceDamagePerLevel)
end

return GodSystemCompanionConfig
