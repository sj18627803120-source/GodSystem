GodSystemCompanionFeatureRules = GodSystemCompanionFeatureRules or {}

local Rules = GodSystemCompanionFeatureRules

Rules.stateVersion = 1

Rules.constants = {
    sightDurationSeconds = 10,
    sightTargetCap = 50,
    guardianScanSeconds = 0.25,
    guardianTriggerRadius = 3,
    guardianTriggerCount = 1,
    shockInternalCooldownSeconds = 2,
    corrosionDurationSeconds = 3,
    corrosionTickSeconds = 1,
    corrosionDamageRatio = 0.10,
    markDurationSeconds = 6,
    markDamageMultiplier = 1.20,
    chainRadius = 3,
    chainDamageRatio = 0.50,
    blastRadius = 2,
    blastTargetCap = 4,
    blastDamageRatio = 0.25,
    projectileTravelSeconds = 0.35,
    attackSearchSeconds = 0.20,
    robotChargeSeconds = 0.20,
    robotRecoverySeconds = 0.15,
    robotCombatGraceSeconds = 3,
    robotOrbitRetargetMinSeconds = 2.5,
    robotOrbitRetargetMaxSeconds = 4.5,
    robotGuardDriftRadius = 1.5,
    robotRecallDistance = 24,
    robotCatchupMargin = 2,
    robotNormalSpeed = 1.2,
    robotCatchupSpeed = 4.5,
    robotTrailSeconds = 0.12,
    robotIdleMinSeconds = 2,
    robotIdleMaxSeconds = 5,
    robotLookMinSeconds = 0.8,
    robotLookMaxSeconds = 1.4,
    robotCombatStrafeMinSeconds = 1.2,
    robotCombatStrafeMaxSeconds = 2.0,
    robotNearPatrolChance = 0.25,
}

Rules.unlockOrder = { "projection", "attack", "sight", "guardian" }
Rules.unlocks = {
    projection = { cost = 100 },
    attack = { cost = 200, requires = "projection" },
    sight = { cost = 800, requires = "projection" },
    guardian = { cost = 1200, requires = "projection" },
}

Rules.effectOrder = { "shock", "corrosion", "mark", "chain", "blast" }
Rules.effects = {
    shock = { cost = 1000 },
    corrosion = { cost = 2000 },
    mark = { cost = 4000 },
    chain = { cost = 8000 },
    blast = { cost = 16000 },
}

Rules.statOrder = {
    "light", "attackDamage", "attackCooldown", "attackRange",
    "sightRange", "sightCooldown", "guardianRange", "guardianCount",
    "guardianCooldown",
}
Rules.stats = {
    light = { values = { 6, 8, 10, 12, 15 }, costs = { 100, 200, 400, 800 }, requires = "projection" },
    attackDamage = {
        values = { 0.40, 0.52, 0.66, 0.82, 1.00, 1.20 },
        costs = { 100, 200, 400, 800, 1600 },
        requires = "attack",
    },
    attackCooldown = {
        values = { 4.0, 3.2, 2.6, 2.0, 1.5, 1.0 },
        costs = { 150, 300, 600, 1200, 2400 },
        requires = "attack",
    },
    attackRange = { values = { 6, 8, 10, 12, 15 }, costs = { 100, 250, 500, 1000 }, requires = "attack" },
    sightRange = { values = { 20, 30, 40, 50 }, costs = { 300, 700, 1500 }, requires = "sight" },
    sightCooldown = { values = { 120, 90, 60, 30 }, costs = { 400, 900, 1800 }, requires = "sight" },
    guardianRange = { values = { 4, 5, 6, 8 }, costs = { 400, 800, 1600 }, requires = "guardian" },
    guardianCount = { values = { 4, 6, 9, 12 }, costs = { 300, 700, 1400 }, requires = "guardian" },
    guardianCooldown = { values = { 90, 60, 40, 25 }, costs = { 500, 1000, 2000 }, requires = "guardian" },
}

Rules.followBands = {
    follow3 = { minimum = 1.5, maximum = 3 },
    follow5 = { minimum = 2, maximum = 5 },
    follow10 = { minimum = 4, maximum = 10 },
}

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

function Rules.number(value, fallback, minimum, maximum)
    value = finite(value) and tonumber(value) or tonumber(fallback) or 0
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Rules.integer(value, fallback, minimum, maximum)
    return math.floor(Rules.number(value, fallback, minimum, maximum))
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

function Rules.normalizePersistent(value)
    local data = type(value) == "table" and Rules.copy(value) or {}
    data.unlocked = data.unlocked == true
    data.unlocks = type(data.unlocks) == "table" and data.unlocks or {}
    data.levels = type(data.levels) == "table" and data.levels or {}
    data.effects = type(data.effects) == "table" and data.effects or {}
    data.cooldowns = type(data.cooldowns) == "table" and data.cooldowns or {}
    for _, id in ipairs({ "attack", "sight", "guardian" }) do
        data.unlocks[id] = data.unlocks[id] == true
        data.cooldowns[id] = Rules.number(data.cooldowns[id], 0, 0)
    end
    for id, definition in pairs(Rules.stats) do
        data.levels[id] = Rules.integer(data.levels[id], 1, 1, #definition.values)
    end
    for _, id in ipairs(Rules.effectOrder) do data.effects[id] = data.effects[id] == true end
    data.resonance = Rules.integer(data.resonance, 0, 0)
    if data.combatMode ~= "active" and data.combatMode ~= "ceasefire" then
        data.combatMode = "defensive"
    end
    if data.followMode ~= "follow3" and data.followMode ~= "follow10" and data.followMode ~= "guard" then
        data.followMode = "follow5"
    end
    if data.visible == nil then data.visible = true else data.visible = data.visible == true end
    if data.guardianEnabled == nil then
        data.guardianEnabled = true
    else
        data.guardianEnabled = data.guardianEnabled == true
    end
    data.guardPoint = type(data.guardPoint) == "table" and {
        x = Rules.number(data.guardPoint.x, 0),
        y = Rules.number(data.guardPoint.y, 0),
        z = Rules.number(data.guardPoint.z, 0),
    } or nil
    data.ui = type(data.ui) == "table" and data.ui or {}
    data.ui.shortcutVisible = data.ui.shortcutVisible == true
    data.ui.shortcutX = finite(data.ui.shortcutX) and tonumber(data.ui.shortcutX) or nil
    data.ui.shortcutY = finite(data.ui.shortcutY) and tonumber(data.ui.shortcutY) or nil
    return data
end

function Rules.isUnlocked(data, id)
    data = Rules.normalizePersistent(data)
    if id == "projection" then return data.unlocked end
    return data.unlocks[id] == true
end

function Rules.statValue(data, id)
    data = Rules.normalizePersistent(data)
    local definition = Rules.stats[id]
    return definition and definition.values[data.levels[id]] or nil
end

function Rules.scaleCost(value, multiplier)
    multiplier = Rules.number(multiplier, 1, 0.01)
    return math.max(1, math.floor(Rules.number(value, 0, 0) * multiplier + 0.5))
end

function Rules.functionalMax(data)
    data = Rules.normalizePersistent(data)
    if not data.unlocked or not data.unlocks.attack or not data.unlocks.sight
            or not data.unlocks.guardian then return false end
    for id, definition in pairs(Rules.stats) do
        if data.levels[id] < #definition.values then return false end
    end
    return true
end

function Rules.allEffectsUnlocked(data)
    data = Rules.normalizePersistent(data)
    for _, id in ipairs(Rules.effectOrder) do
        if not data.effects[id] then return false end
    end
    return true
end

function Rules.purchaseQuote(data, nodeId, multiplier)
    data = Rules.normalizePersistent(data)
    local unlock = Rules.unlocks[nodeId]
    if unlock then
        if Rules.isUnlocked(data, nodeId) then return nil, "alreadyUnlocked" end
        if unlock.requires and not Rules.isUnlocked(data, unlock.requires) then return nil, "requirementLocked" end
        return { kind = "unlock", nodeId = nodeId, cost = Rules.scaleCost(unlock.cost, multiplier) }
    end
    local stat = Rules.stats[nodeId]
    if stat then
        if not Rules.isUnlocked(data, stat.requires) then return nil, "requirementLocked" end
        local level = data.levels[nodeId]
        local cost = stat.costs[level]
        if not cost then return nil, "maxLevel" end
        return { kind = "stat", nodeId = nodeId, level = level + 1, cost = Rules.scaleCost(cost, multiplier) }
    end
    local effect = Rules.effects[nodeId]
    if effect then
        if not data.unlocks.attack then return nil, "requirementLocked" end
        if data.effects[nodeId] then return nil, "alreadyUnlocked" end
        for index, id in ipairs(Rules.effectOrder) do
            if id == nodeId and index > 1 and not data.effects[Rules.effectOrder[index - 1]] then
                return nil, "effectOrder"
            end
        end
        return { kind = "effect", nodeId = nodeId, cost = Rules.scaleCost(effect.cost, multiplier) }
    end
    if nodeId == "resonance" then
        if not Rules.functionalMax(data) or not Rules.allEffectsUnlocked(data) then
            return nil, "resonanceLocked"
        end
        return {
            kind = "resonance",
            nodeId = nodeId,
            level = data.resonance + 1,
            cost = Rules.scaleCost(2500 + data.resonance * 500, multiplier),
        }
    end
    return nil, "nodeUnknown"
end

function Rules.applyPurchase(data, quote)
    data = Rules.normalizePersistent(data)
    if quote.kind == "unlock" then
        if quote.nodeId == "projection" then data.unlocked = true else data.unlocks[quote.nodeId] = true end
    elseif quote.kind == "stat" then
        data.levels[quote.nodeId] = Rules.integer(quote.level, data.levels[quote.nodeId], 1,
            #Rules.stats[quote.nodeId].values)
    elseif quote.kind == "effect" then
        data.effects[quote.nodeId] = true
    elseif quote.kind == "resonance" then
        data.resonance = Rules.integer(quote.level, data.resonance + 1, 0)
    else
        return nil, "quoteInvalid"
    end
    return data
end

function Rules.finalDamage(data)
    return (Rules.statValue(data, "attackDamage") or 0)
        * (1 + Rules.integer(data and data.resonance, 0, 0) * 0.01)
end

function Rules.attackRadius(data)
    data = Rules.normalizePersistent(data)
    return data.combatMode == "defensive" and 5 or (Rules.statValue(data, "attackRange") or 6)
end

function Rules.distanceSquared(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return math.huge end
    local dx = Rules.number(left.x, 0) - Rules.number(right.x, 0)
    local dy = Rules.number(left.y, 0) - Rules.number(right.y, 0)
    return dx * dx + dy * dy
end

function Rules.targetAllowed(data, actor, target, sightMarked)
    data = Rules.normalizePersistent(data)
    if data.combatMode == "ceasefire" or type(actor) ~= "table" or type(target) ~= "table" then return false end
    if target.dead == true or math.floor(Rules.number(target.z, -99) + 0.1)
            ~= math.floor(Rules.number(actor.z, 0) + 0.1) then return false end
    local radius = Rules.attackRadius(data)
    if Rules.distanceSquared(actor, target) > radius * radius then return false end
    return sightMarked == true or target.visible == true
end

function Rules.decrementCooldowns(data, delta)
    data = Rules.normalizePersistent(data)
    delta = Rules.number(delta, 0, 0, 0.25)
    for _, id in ipairs({ "attack", "sight", "guardian" }) do
        data.cooldowns[id] = math.max(0, data.cooldowns[id] - delta)
    end
    return data
end

return Rules
