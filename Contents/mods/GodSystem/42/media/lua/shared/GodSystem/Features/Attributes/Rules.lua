GodSystemAttributesFeatureRules = GodSystemAttributesFeatureRules or {}

local Rules = GodSystemAttributesFeatureRules

Rules.stateVersion = 1
Rules.maxLevel = 10
Rules.defaultXpPerCoin = 10
Rules.defaultPositiveCostPerPoint = 800
Rules.defaultNegativeRemoveCostPerPoint = 500

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

function Rules.integer(value, fallback, minimum, maximum)
    value = finite(value) and tonumber(value) or tonumber(fallback) or 0
    value = math.floor(value)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Rules.attributeQuote(info, state, mode, value, xpPerCoin)
    if type(info) ~= "table" or type(state) ~= "table" then return nil, "stateMissing" end
    local currentXp = math.max(0, tonumber(state.currentXp) or 0)
    local currentLevel = Rules.integer(state.currentLevel, 0, 0, Rules.maxLevel)
    local maxXp = tonumber(info.maxXp)
    local maxLevel = Rules.integer(info.maxLevel, Rules.maxLevel, 1, Rules.maxLevel)
    if not maxXp or maxXp <= 0 then return nil, "curveMissing" end
    if currentXp >= maxXp or currentLevel >= maxLevel then return nil, "maxed" end
    xpPerCoin = Rules.integer(xpPerCoin, Rules.defaultXpPerCoin, 1, 1000000)
    mode, value = tostring(mode or "amount"), Rules.integer(value, 0)
    local requestedXp, targetLevel = 0, nil
    if mode == "amount" then
        if value <= 0 then return nil, "invalidAmount" end
        requestedXp = value * xpPerCoin
    elseif mode == "targetLevel" then
        targetLevel = math.max(1, math.min(maxLevel, value))
        if targetLevel <= currentLevel then return nil, "invalidLevel" end
        local targetXp = info.levelXp and tonumber(info.levelXp[targetLevel])
        if not targetXp or targetXp <= currentXp then return nil, "curveMissing" end
        requestedXp = targetXp - currentXp
    else
        return nil, "invalidMode"
    end
    local actualXp = math.max(0, math.min(requestedXp, maxXp - currentXp))
    if actualXp <= 0 then return nil, "maxed" end
    return {
        info = info,
        mode = mode,
        input = value,
        targetLevel = targetLevel,
        currentXp = currentXp,
        currentLevel = currentLevel,
        actualXp = actualXp,
        cost = math.max(1, math.ceil(actualXp / xpPerCoin)),
        xpPerCoin = xpPerCoin,
    }
end

function Rules.traitQuote(info, owned, action, positiveCost, negativeCost)
    if type(info) ~= "table" or tostring(info.traitType or "") == "" then
        return nil, "traitMissing"
    end
    action = tostring(action or "")
    local points = Rules.integer(info.costPoints, 0)
    if info.blocked or info.free or info.profession or points == 0 then return nil, "traitBlocked" end
    if action == "buy" then
        if points <= 0 then return nil, "traitActionInvalid" end
        if owned then return nil, "traitOwned" end
        if type(info.ownedConflicts) == "table" and #info.ownedConflicts > 0 then return nil, "traitConflict" end
        return {
            info = info,
            action = action,
            traitType = info.traitType,
            token = info.token,
            costPoints = points,
            cost = points * Rules.integer(positiveCost, Rules.defaultPositiveCostPerPoint, 0, 100000),
        }
    elseif action == "remove" then
        if points >= 0 then return nil, "traitActionInvalid" end
        if not owned then return nil, "traitNotOwned" end
        return {
            info = info,
            action = action,
            traitType = info.traitType,
            token = info.token,
            costPoints = points,
            cost = math.abs(points) * Rules.integer(
                negativeCost, Rules.defaultNegativeRemoveCostPerPoint, 0, 100000),
        }
    end
    return nil, "traitActionInvalid"
end

function Rules.finalAttributeCost(quote, appliedXp)
    appliedXp = math.max(0, tonumber(appliedXp) or 0)
    if appliedXp <= 0 then return 0 end
    return math.max(1, math.min(quote.cost, math.ceil(appliedXp / quote.xpPerCoin)))
end

return Rules
