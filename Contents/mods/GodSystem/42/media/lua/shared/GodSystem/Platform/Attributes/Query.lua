require "GodSystem/Platform/Progression/Support"

GodSystemAttributesQueryPlatform = GodSystemAttributesQueryPlatform or {}

local Descriptor = GodSystemAttributesQueryPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "attributes.query"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local BLOCKED = {}
for _, value in ipairs({
    "Obese", "Overweight", "Underweight", "Very Underweight", "VeryUnderweight",
    "Emaciated", "Strong", "Stout", "Weak", "Feeble", "Fit", "Athletic", "Unfit",
    "Out of Shape", "OutOfShape", "BLACKSMITH2", "COOK2", "MECHANICS2", "NUTRITIONIST2",
}) do
    BLOCKED[tostring(value):gsub("[%s_%-]", ""):lower()] = true
end

local function safe(object, methodName, fallback, ...)
    local ok, value = Support.call(object, methodName, ...)
    if ok and value ~= nil then return value end
    return fallback
end

local function tokenText(value)
    if value == nil then return "" end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    return tostring(safe(value, "toString", value))
end

local function normalized(value)
    return tokenText(value):gsub("[%s_%-]", ""):lower()
end

local function same(left, right)
    return left ~= nil and right ~= nil and left == right
end

local function groupFor(perk, parent)
    if Perks then
        if same(perk, Perks.Strength) or same(perk, Perks.Fitness) or same(parent, Perks.Passiv) then
            return "body"
        end
        if same(parent, Perks.Combat) or same(parent, Perks.Agility)
            or same(parent, Perks.Firearm)
        then
            return "combat"
        end
        if same(parent, Perks.Survivalist) then return "survival" end
        if same(parent, Perks.Crafting) then return "crafting" end
    end
    return "mod"
end

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local counters = { perkReads = 0, traitReads = 0, failures = 0 }
    local traitCache = nil

    local function ownerKey(actor)
        return Support.identity(actor, binding)
    end

    local function resolvePerk(index)
        if type(binding.resolvePerk) == "function" then return binding.resolvePerk(index) end
        if not Perks or type(Perks.getMaxIndex) ~= "function"
            or type(Perks.fromIndex) ~= "function"
            or not PerkFactory or type(PerkFactory.getPerk) ~= "function"
        then
            return nil, "apiMissing"
        end
        index = Support.integer(index, -1)
        local maxIndex = Support.integer(Perks.getMaxIndex(), 0, 0)
        if not index or index < 0 or index >= maxIndex then return nil, "invalidIndex" end
        local okPerk, perk = pcall(Perks.fromIndex, index)
        if not okPerk or not perk or (Perks.None and perk == Perks.None) then
            return nil, "invalidPerk"
        end
        local okFactory, factoryPerk = pcall(PerkFactory.getPerk, perk)
        if not okFactory or not factoryPerk then return nil, "factoryMissing" end
        local parent = safe(factoryPerk, "getParent", nil) or safe(perk, "getParent", nil)
        if not parent or (Perks.None and parent == Perks.None) then return nil, "category" end
        local maxXp = tonumber(safe(factoryPerk, "getTotalXpForLevel", nil, 10)
            or safe(perk, "getTotalXpForLevel", nil, 10))
        if not maxXp or maxXp <= 0 then return nil, "curveMissing" end
        local levelXp = {}
        for level = 1, 10 do
            levelXp[level] = tonumber(safe(factoryPerk, "getTotalXpForLevel", nil, level)
                or safe(perk, "getTotalXpForLevel", nil, level))
        end
        return {
            index = index,
            perk = perk,
            factoryPerk = factoryPerk,
            parent = parent,
            label = tostring(safe(factoryPerk, "getName", nil)
                or safe(perk, "getName", nil) or ("Perk " .. tostring(index))),
            parentLabel = tostring(safe(parent, "getName", "")),
            group = groupFor(perk, parent),
            maxLevel = 10,
            maxXp = maxXp,
            levelXp = levelXp,
        }
    end

    local function perkState(actor, info)
        if type(binding.perkState) == "function" then return binding.perkState(actor, info) end
        local xp = actor and type(actor.getXp) == "function" and actor:getXp() or nil
        if not xp or type(info) ~= "table" or info.perk == nil then return nil, "stateMissing" end
        local currentXp = tonumber(safe(xp, "getXP", nil, info.perk))
        local currentLevel = tonumber(safe(actor, "getPerkLevel", nil, info.perk))
        if currentXp == nil or currentLevel == nil then return nil, "stateMissing" end
        return {
            currentXp = math.max(0, currentXp),
            currentLevel = math.max(0, math.floor(currentLevel)),
            maxLevel = info.maxLevel,
            maxXp = info.maxXp,
        }
    end

    local function listPerks(actor)
        if type(binding.listPerks) == "function" then return binding.listPerks(actor) end
        local result = {}
        local maximum = Perks and type(Perks.getMaxIndex) == "function"
            and Support.integer(Perks.getMaxIndex(), 0, 0) or 0
        for index = 0, maximum - 1 do
            local info = resolvePerk(index)
            local state = info and perkState(actor, info) or nil
            if info and state then
                local row = Support.copy(info)
                row.currentXp = state.currentXp
                row.currentLevel = state.currentLevel
                row.maxed = state.currentXp >= info.maxXp or state.currentLevel >= info.maxLevel
                result[#result + 1] = row
            end
        end
        table.sort(result, function(left, right)
            if left.group ~= right.group then return tostring(left.group) < tostring(right.group) end
            if left.label ~= right.label then return tostring(left.label) < tostring(right.label) end
            return left.index < right.index
        end)
        counters.perkReads = counters.perkReads + 1
        return result
    end

    local function traitDefinitions()
        if traitCache then return traitCache end
        local result = {}
        local raw = nil
        if type(binding.traits) == "table" then
            raw = binding.traits
        end
        if not raw and CharacterTraitDefinition and type(CharacterTraitDefinition.getTraits) == "function" then
            local ok, value = pcall(CharacterTraitDefinition.getTraits)
            if ok then raw = value end
        end
        if not raw and TraitFactory and type(TraitFactory.getTraits) == "function" then
            local ok, value = pcall(TraitFactory.getTraits)
            if ok then raw = value end
        end
        if not raw and BaseGameCharacterDetails then
            raw = BaseGameCharacterDetails.traits
        end
        for _, definition in ipairs(Support.values(raw)) do
            local tableType = type(definition) == "table"
                and (definition.type or definition.traitType) or nil
            local traitType = tokenText(tableType or safe(definition, "getType", ""))
            if traitType ~= "" then
                result[normalized(traitType)] = {
                    definition = definition,
                    traitType = traitType,
                    token = (type(definition) == "table"
                        and (definition.token or definition.type)) or safe(definition, "getType", traitType),
                }
            end
        end
        traitCache = result
        return result
    end

    local function knownTraits(actor)
        if type(binding.knownTraits) == "function" then return binding.knownTraits(actor) end
        local traits = actor and ((type(actor.getCharacterTraits) == "function"
            and actor:getCharacterTraits()) or (type(actor.getTraits) == "function" and actor:getTraits())) or nil
        return Support.values(safe(traits, "getKnownTraits", traits))
    end

    local function hasTrait(actor, traitType)
        if type(binding.hasTrait) == "function" then return binding.hasTrait(actor, traitType) == true end
        local entry = traitDefinitions()[normalized(traitType)]
        local token = entry and entry.token or traitType
        if actor and type(actor.hasTrait) == "function" and token and type(token) ~= "string" then
            local ok, value = pcall(actor.hasTrait, actor, token)
            if ok then return value == true end
        end
        local target = normalized(traitType)
        for _, owned in ipairs(knownTraits(actor)) do
            if normalized(owned) == target then return true end
        end
        return false
    end

    local function resolveTrait(actor, traitType)
        if type(binding.resolveTrait) == "function" then return binding.resolveTrait(actor, traitType) end
        local entry = traitDefinitions()[normalized(traitType)]
        if not entry then return nil, "traitMissing" end
        local definition = entry.definition
        local cost = type(definition) == "table"
            and tonumber(definition.cost or definition.costPoints) or nil
        if cost == nil then cost = tonumber(safe(definition, "getCost", 0)) end
        local mutualSource = type(definition) == "table"
            and (definition.mutual or definition.mutualTypes) or nil
        if mutualSource == nil then
            mutualSource = safe(definition, "getMutuallyExclusiveTraits", nil)
        end
        local mutual = Support.values(mutualSource)
        local conflictTypes, ownedConflicts = {}, {}
        for _, token in ipairs(mutual) do
            local value = tokenText(token)
            if value ~= "" then
                conflictTypes[#conflictTypes + 1] = value
                if hasTrait(actor, value) then ownedConflicts[#ownedConflicts + 1] = value end
            end
        end
        local free = (type(definition) == "table" and definition.free == true)
            or safe(definition, "isFree", false) == true
        local profession = type(definition) == "table"
            and (definition.prof == true or definition.profession == true) or false
        return {
            definition = definition,
            traitType = entry.traitType,
            token = entry.token,
            label = tostring((type(definition) == "table" and definition.label)
                or safe(definition, "getLabel", entry.traitType)),
            description = tostring((type(definition) == "table" and definition.description)
                or safe(definition, "getDescription", "")),
            costPoints = math.floor(cost or 0),
            conflictTypes = conflictTypes,
            ownedConflicts = ownedConflicts,
            blocked = BLOCKED[normalized(entry.traitType)] == true,
            free = free,
            profession = profession,
        }
    end

    local function listTraits(actor, action)
        if type(binding.listTraits) == "function" then return binding.listTraits(actor, action) end
        local result = {}
        for _, entry in pairs(traitDefinitions()) do
            local info = resolveTrait(actor, entry.traitType)
            local owned = info and hasTrait(actor, info.traitType) or false
            if info and not info.blocked and not info.free and not info.profession
                and ((action == "remove" and info.costPoints < 0 and owned)
                    or (action ~= "remove" and info.costPoints > 0))
            then
                info.owned = owned
                result[#result + 1] = info
            end
        end
        table.sort(result, function(left, right)
            local leftCost, rightCost = math.abs(left.costPoints), math.abs(right.costPoints)
            if leftCost ~= rightCost then return leftCost < rightCost end
            return tostring(left.label) < tostring(right.label)
        end)
        counters.traitReads = counters.traitReads + 1
        return result
    end

    local public = {
        ownerKey = ownerKey,
        listPerks = listPerks,
        resolvePerk = resolvePerk,
        perkState = perkState,
        listTraits = listTraits,
        resolveTrait = resolveTrait,
        hasTrait = hasTrait,
    }
    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
