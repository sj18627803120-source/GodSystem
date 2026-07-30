require "GodSystem/Platform/Progression/Support"

GodSystemAttributesMutationPlatform = GodSystemAttributesMutationPlatform or {}

local Descriptor = GodSystemAttributesMutationPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "attributes.mutation"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local counters = { xpChanges = 0, traitChanges = 0, benefits = 0, failures = 0 }

    local function addXp(actor, info, amount, request)
        if type(binding.addXp) == "function" then return binding.addXp(actor, info, amount, request) end
        local xp = actor and type(actor.getXp) == "function" and actor:getXp() or nil
        if not xp or type(xp.AddXP) ~= "function" or type(info) ~= "table" or info.perk == nil then
            counters.failures = counters.failures + 1
            return false, "attributeApiMissing"
        end
        local ok = pcall(xp.AddXP, xp, info.perk, amount, false, false, false, false)
        if not ok then
            counters.failures = counters.failures + 1
            return false, "attributeApplyFailed"
        end
        counters.xpChanges = counters.xpChanges + 1
        return true
    end

    local function syncXp(actor, request)
        if type(binding.syncXp) == "function" then return binding.syncXp(actor, request) end
        if type(SyncXp) ~= "function" then return false, "syncUnavailable" end
        local ok = pcall(SyncXp, actor)
        return ok, ok and nil or "syncFailed"
    end

    local function traits(actor)
        if not actor then return nil end
        if type(actor.getCharacterTraits) == "function" then return actor:getCharacterTraits() end
        if type(actor.getTraits) == "function" then return actor:getTraits() end
        return nil
    end

    local function setTrait(actor, info, enabled, request)
        if type(binding.setTrait) == "function" then
            return binding.setTrait(actor, info, enabled, request)
        end
        local collection = traits(actor)
        local token = type(info) == "table" and info.token or nil
        if not collection or token == nil or type(token) == "string" then
            counters.failures = counters.failures + 1
            return false, "traitApiMissing"
        end
        local method = enabled and collection.add or collection.remove
        if type(method) ~= "function" then
            counters.failures = counters.failures + 1
            return false, "traitApiMissing"
        end
        local ok = pcall(method, collection, token)
        if not ok then
            counters.failures = counters.failures + 1
            return false, "traitApplyFailed"
        end
        counters.traitChanges = counters.traitChanges + 1
        return true
    end

    local function applyTraitBenefits(actor, info, request)
        if type(binding.applyTraitBenefits) == "function" then
            return binding.applyTraitBenefits(actor, info, request)
        end
        local definition = type(info) == "table" and info.definition or nil
        if not actor or not definition then return true, 0 end
        local applied = 0
        local boosts = nil
        if type(definition) == "table" then boosts = definition.xpBoosts
        elseif type(definition.getXpBoosts) == "function" then boosts = definition:getXpBoosts() end
        if boosts and transformIntoKahluaTable then
            local ok, value = pcall(transformIntoKahluaTable, boosts)
            if ok then boosts = value end
        end
        if type(boosts) == "table" then
            for perk, value in pairs(boosts) do
                local count = math.max(0, math.floor(tonumber(tostring(value)) or 0))
                for _ = 1, count do
                    local level = tonumber(Support.read(actor, { "getPerkLevel" }, 0, perk)) or 0
                    if level >= 10 then break end
                    if type(actor.LevelPerk) == "function" then
                        local ok = pcall(actor.LevelPerk, actor, perk)
                        if ok then
                            applied = applied + 1
                            if luautils and type(luautils.updatePerksXp) == "function" then
                                pcall(luautils.updatePerksXp, perk, actor)
                            end
                        end
                    end
                end
            end
        end
        local recipes = nil
        local hasRecipes = type(definition) == "table" and definition.grantedRecipes ~= nil
            or Support.read(definition, { "hasGrantedRecipes" }, false) == true
        if hasRecipes then
            recipes = type(definition) == "table" and definition.grantedRecipes
                or Support.read(definition, { "getGrantedRecipes" }, nil)
        end
        for _, recipe in ipairs(Support.values(recipes)) do
            if type(actor.learnRecipe) == "function" then
                local ok = pcall(actor.learnRecipe, actor, recipe)
                if ok then applied = applied + 1 end
            end
        end
        counters.benefits = counters.benefits + applied
        return true, applied
    end

    local public = {
        addXp = addXp,
        syncXp = syncXp,
        setTrait = setTrait,
        applyTraitBenefits = applyTraitBenefits,
    }
    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
