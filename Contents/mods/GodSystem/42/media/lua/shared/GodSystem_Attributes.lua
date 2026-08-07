require "GodSystem_Config"
require "GodSystem_AdminConfig"
require "GodSystem_B42JavaCalls"

GodSystemAttributes = GodSystemAttributes or {}

local Attributes = GodSystemAttributes

local function safeCall(object, methodName, fallback, ...)
    return GodSystemB42JavaCalls.value(object, methodName, fallback, ...)
end

local function samePerk(left, right)
    return left ~= nil and right ~= nil and left == right
end

local function groupFor(perk, parent)
    if Perks then
        if samePerk(perk, Perks.Strength) or samePerk(perk, Perks.Fitness) or samePerk(parent, Perks.Passiv) then return "body" end
        if samePerk(parent, Perks.Combat) or samePerk(parent, Perks.Agility) or samePerk(parent, Perks.Firearm) then return "combat" end
        if samePerk(parent, Perks.Survivalist) then return "survival" end
        if samePerk(parent, Perks.Crafting) then return "crafting" end
    end
    return "mod"
end

function Attributes.isEnabled()
    return GodSystemAdminConfig.getSetting("EnableAttributes", true) == true
end

function Attributes.getXpPerCoin()
    return math.max(1, math.floor(tonumber(GodSystemAdminConfig.getSetting("AttributeXPPerCoin", GodSystemConfig.AttributeXPPerCoin or 10)) or 10))
end

function Attributes.resolve(perkIndex)
    if not Perks or not Perks.getMaxIndex or not Perks.fromIndex or not PerkFactory or not PerkFactory.getPerk then return nil, "apiMissing" end
    perkIndex = math.floor(tonumber(perkIndex) or -1)
    local maxIndex = math.floor(tonumber(Perks.getMaxIndex()) or 0)
    if perkIndex < 0 or perkIndex >= maxIndex then return nil, "invalidIndex" end
    local okPerk, perk = pcall(function() return Perks.fromIndex(perkIndex) end)
    if not okPerk or not perk or (Perks.None and perk == Perks.None) then return nil, "invalidPerk" end
    local okFactory, factoryPerk = pcall(function() return PerkFactory.getPerk(perk) end)
    if not okFactory or not factoryPerk then return nil, "factoryMissing" end
    local parent = safeCall(factoryPerk, "getParent", nil) or safeCall(perk, "getParent", nil)
    if not parent or (Perks.None and parent == Perks.None) then return nil, "category" end
    local maxLevel = 10
    local maxXp = tonumber(safeCall(factoryPerk, "getTotalXpForLevel", nil, maxLevel)
        or safeCall(perk, "getTotalXpForLevel", nil, maxLevel))
    if not maxXp or maxXp <= 0 then return nil, "curveMissing" end
    local label = tostring(safeCall(factoryPerk, "getName", nil) or safeCall(perk, "getName", nil) or ("Perk " .. tostring(perkIndex)))
    local parentLabel = tostring(safeCall(parent, "getName", nil) or "")
    return {
        index = perkIndex,
        perk = perk,
        factoryPerk = factoryPerk,
        parent = parent,
        label = label,
        parentLabel = parentLabel,
        group = groupFor(perk, parent),
        maxLevel = maxLevel,
        maxXp = maxXp,
    }
end

function Attributes.getPlayerState(player, info)
    if not player or not info or not info.perk then return nil end
    local xpObject = player.getXp and player:getXp() or nil
    if not xpObject then return nil end
    local currentXp = tonumber(safeCall(xpObject, "getXP", nil, info.perk))
    local currentLevel = tonumber(safeCall(player, "getPerkLevel", nil, info.perk))
    if currentXp == nil or currentLevel == nil then return nil end
    return {
        currentXp = math.max(0, currentXp),
        currentLevel = math.max(0, math.floor(currentLevel)),
        maxXp = info.maxXp,
        maxLevel = info.maxLevel,
    }
end

function Attributes.enumerate(player)
    local result = {}
    if not Perks or not Perks.getMaxIndex then return result end
    local maxIndex = math.floor(tonumber(Perks.getMaxIndex()) or 0)
    for index = 0, maxIndex - 1 do
        local info = Attributes.resolve(index)
        local state = info and Attributes.getPlayerState(player, info) or nil
        if info and state then
            info.currentXp = state.currentXp
            info.currentLevel = state.currentLevel
            info.maxed = state.currentXp >= info.maxXp or state.currentLevel >= info.maxLevel
            result[#result + 1] = info
        end
    end
    table.sort(result, function(a, b)
        if a.group ~= b.group then return tostring(a.group) < tostring(b.group) end
        if a.label ~= b.label then return tostring(a.label) < tostring(b.label) end
        return a.index < b.index
    end)
    return result
end

function Attributes.quote(player, perkIndex, mode, value, xpPerCoin)
    local info, reason = Attributes.resolve(perkIndex)
    if not info then return nil, reason end
    local state = Attributes.getPlayerState(player, info)
    if not state then return nil, "stateMissing" end
    if state.currentXp >= state.maxXp or state.currentLevel >= state.maxLevel then return nil, "maxed" end
    xpPerCoin = math.max(1, math.floor(tonumber(xpPerCoin) or Attributes.getXpPerCoin()))
    mode = tostring(mode or "amount")
    value = math.floor(tonumber(value) or 0)
    local requestedXp = 0
    local targetLevel = nil
    if mode == "amount" then
        if value <= 0 then return nil, "invalidAmount" end
        requestedXp = value * xpPerCoin
    elseif mode == "targetLevel" then
        targetLevel = math.max(1, math.min(state.maxLevel, value))
        if targetLevel <= state.currentLevel then return nil, "invalidLevel" end
        local targetXp = tonumber(safeCall(info.factoryPerk, "getTotalXpForLevel", nil, targetLevel)
            or safeCall(info.perk, "getTotalXpForLevel", nil, targetLevel))
        if not targetXp or targetXp <= state.currentXp then return nil, "curveMissing" end
        requestedXp = targetXp - state.currentXp
    else
        return nil, "invalidMode"
    end
    local actualXp = math.max(0, math.min(requestedXp, state.maxXp - state.currentXp))
    if actualXp <= 0 then return nil, "maxed" end
    local cost = math.max(1, math.ceil(actualXp / xpPerCoin))
    return {
        info = info,
        mode = mode,
        input = value,
        targetLevel = targetLevel,
        currentXp = state.currentXp,
        currentLevel = state.currentLevel,
        actualXp = actualXp,
        cost = cost,
        xpPerCoin = xpPerCoin,
    }
end

return GodSystemAttributes
