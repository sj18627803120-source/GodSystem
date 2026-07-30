local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/init.lua",
    package.path,
}, ";")

local function equal(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function truthy(value, label)
    if not value then error(label or "expected truthy", 2) end
end

local function scope(seed)
    local value = seed or {}
    return {
        get = function() return value end,
        replace = function(_, nextValue) value = nextValue return true end,
        inspect = function() return value end,
    }
end

local function operations()
    local rows = {}
    return {
        begin = function(moduleId, operationId, fingerprint, request)
            local actor = request and request.actor and request.actor.id or "local"
            local key = tostring(moduleId) .. "|" .. tostring(actor) .. "|" .. tostring(operationId)
            if rows[key] then return "replay", rows[key].result end
            rows[key] = { fingerprint = fingerprint }
            return "new", rows[key]
        end,
        finish = function(moduleId, operationId, result, request)
            local actor = request and request.actor and request.actor.id or "local"
            local key = tostring(moduleId) .. "|" .. tostring(actor) .. "|" .. tostring(operationId)
            rows[key] = rows[key] or {}
            rows[key].result = result
            return result
        end,
        markUnknown = function() return true end,
    }
end

local notifications = { rows = {} }
function notifications.publish(result)
    notifications.rows[#notifications.rows + 1] = result
    return true
end

require "GodSystem/Features/Admin/Rules"
require "GodSystem/Features/Admin/Module"
require "GodSystem/Features/Admin/PublicPort"
require "GodSystem/Features/Attributes/Module"
require "GodSystem/Features/Attributes/PublicPort"
require "GodSystem/Platform/Admin/Source"
require "GodSystem/Platform/Admin/Permissions"
require "GodSystem/Platform/Admin/Runtime"
require "GodSystem/Platform/Attributes/Query"
require "GodSystem/Platform/Attributes/Mutation"

local perkToken = {}
local parentToken = {}
Perks = {
    None = {},
    Combat = parentToken,
    getMaxIndex = function() return 1 end,
    fromIndex = function(index) return index == 0 and perkToken or nil end,
}
local factoryPerk = {
    getParent = function() return parentToken end,
    getName = function() return "Aiming" end,
    getTotalXpForLevel = function(_, level) return level * 100 end,
}
PerkFactory = { getPerk = function() return factoryPerk end }
local traitToken = { toString = function() return "Positive" end }
local traitDefinition = {
    getType = function() return traitToken end,
    getCost = function() return 2 end,
    getLabel = function() return "Positive" end,
    getDescription = function() return "Test trait" end,
    getMutuallyExclusiveTraits = function() return {} end,
    isFree = function() return false end,
}
CharacterTraitDefinition = { getTraits = function() return { traitDefinition } end }
local platformActor = {
    id = "platform",
    xp = 0,
    level = 0,
    owned = {},
}
local xpObject = {
    getXP = function() return platformActor.xp end,
    AddXP = function(_, _, amount) platformActor.xp = platformActor.xp + amount return true end,
}
local traitCollection = {
    getKnownTraits = function() return platformActor.owned end,
    add = function(_, token) platformActor.owned[#platformActor.owned + 1] = token end,
    remove = function(_, token)
        for index = #platformActor.owned, 1, -1 do
            if platformActor.owned[index] == token then table.remove(platformActor.owned, index) end
        end
    end,
}
function platformActor:getXp() return xpObject end
function platformActor:getPerkLevel() return self.level end
function platformActor:getCharacterTraits() return traitCollection end
SyncXp = function() return true end

local queryAdapter = GodSystemAttributesQueryPlatform.create({}, {})
local mutationAdapter = GodSystemAttributesMutationPlatform.create({}, {})
queryAdapter:start()
mutationAdapter:start()
local platformPerk = assert(queryAdapter.public.resolvePerk(0))
equal(platformPerk.group, "combat", "PZ perk parent classification")
equal(queryAdapter.public.perkState(platformActor, platformPerk).currentXp, 0, "PZ perk state")
truthy(mutationAdapter.public.addXp(platformActor, platformPerk, 25), "PZ AddXP adapter")
equal(queryAdapter.public.perkState(platformActor, platformPerk).currentXp, 25, "PZ XP mutation")
local platformTrait = assert(queryAdapter.public.resolveTrait(platformActor, "Positive"))
truthy(mutationAdapter.public.setTrait(platformActor, platformTrait, true), "PZ trait add adapter")
equal(queryAdapter.public.hasTrait(platformActor, "Positive"), true, "PZ trait verification")
truthy(mutationAdapter.public.setTrait(platformActor, platformTrait, false), "PZ trait remove adapter")
equal(queryAdapter.public.hasTrait(platformActor, "Positive"), false, "PZ trait rollback")

local adminScope = scope()
local runtimeSnapshot = nil
local sourceInstance = GodSystemAdminSourcePlatform.create({}, {
    binding = {
        defaults = {
            AttributeXPPerCoin = 10,
            PositiveTraitCostPerPoint = 800,
            NegativeTraitRemoveCostPerPoint = 500,
        },
        staticOverrides = {
            ["Base.Static"] = { buyPrice = 77, category = "material" },
        },
    },
})
local permissionInstance = GodSystemAdminPermissionsPlatform.create({}, {
    binding = { multiplayer = true, canConfigure = function(actor) return actor and actor.admin == true end },
})
local runtimeInstance = GodSystemAdminRuntimePlatform.create({}, {
    binding = {
        apply = function(settings, overrides, revision)
            runtimeSnapshot = { settings = settings, overrides = overrides, revision = revision }
            return true
        end,
    },
})
sourceInstance:start()
permissionInstance:start()
runtimeInstance:start()

local ops = operations()
local adminInstance = GodSystemAdminFeatureModule.create({
    ["admin.source"] = sourceInstance.public,
    ["admin.permissions"] = permissionInstance.public,
    ["admin.runtime"] = runtimeInstance.public,
    operations = ops,
    notifications = notifications,
}, { state = adminScope })
truthy(adminInstance:start(), "admin start")
equal(runtimeSnapshot.settings.AttributeXPPerCoin, 10, "admin initial setting")
equal(runtimeSnapshot.overrides["Base.Static"].buyPrice, 77, "admin static override")

local administrator = { id = "admin", admin = true }
local ordinary = { id = "ordinary", admin = false }
local denied = adminInstance.public.setSettings({
    actor = ordinary,
    operationId = "admin-denied",
    settings = { AttributeXPPerCoin = 99 },
})
equal(denied.ok, false, "ordinary player denied")
equal(denied.code, "adminPermissionDenied", "ordinary player denial code")
equal(adminInstance.public.getSetting("AttributeXPPerCoin"), 10, "denied update not applied")

local settingsResult = adminInstance.public.setSettings({
    actor = administrator,
    operationId = "admin-settings",
    settings = {
        AttributeXPPerCoin = 12,
        PositiveTraitCostPerPoint = 700,
        BankInvestmentStableGainChance = 80,
        BankInvestmentStableLossChance = 80,
        EnableAttributes = true,
        EnableTraits = true,
    },
})
equal(settingsResult.ok, true, "admin settings update")
equal(adminInstance.public.getSetting("AttributeXPPerCoin"), 12, "admin setting visible")
equal(adminInstance.public.getSetting("BankInvestmentStableLossChance"), 20, "investment loss clamped")

local overrideResult = adminInstance.public.setItemOverride({
    actor = administrator,
    operationId = "admin-override",
    fullType = "Base.TestItem",
    override = {
        buyPrice = 123.9,
        sellPrice = -2,
        category = "Medical Stuff!",
        shopEnabled = false,
        note = string.rep("x", 140),
    },
})
equal(overrideResult.ok, true, "admin item override")
equal(adminInstance.public.applyShopBuyPrice("Base.TestItem", 999), 123, "override buy price")
equal(adminInstance.public.applyRecycleSellPrice("Base.TestItem", 999), 0, "override sell price")
equal(adminInstance.public.getCategory("Base.TestItem", "other"), "medical_stuff_", "override category")
equal(adminInstance.public.isItemEnabled("Base.TestItem", "shopEnabled", true), false, "override feature flag")
equal(#adminInstance.public.getItemOverride("Base.TestItem").note, 120, "override note clamp")

local replay = adminInstance.public.setItemOverride({
    actor = administrator,
    operationId = "admin-override",
    fullType = "Base.TestItem",
    override = { buyPrice = 9999 },
})
equal(replay.data.itemOverrides["Base.TestItem"].buyPrice, 123, "operation replay is idempotent")

local clearResult = adminInstance.public.clearItemOverride({
    actor = administrator,
    operationId = "admin-clear",
    fullType = "Base.TestItem",
})
equal(clearResult.ok, true, "admin override clear")
equal(adminInstance.public.getItemOverride("Base.TestItem"), nil, "runtime override removed")
equal(adminInstance.public.getItemOverride("Base.Static").buyPrice, 77, "static override retained")

local adminPort = GodSystemAdminPublicPort.create({ ["feature.admin"] = adminInstance.public })
adminPort:start()

local actors = {
    one = { id = "one", xp = 0, level = 0, traits = {}, balance = 10000 },
    two = { id = "two", xp = 0, level = 0, traits = {}, balance = 10 },
}
local perk = {
    index = 1, perk = "perk-token", label = "Aiming", parentLabel = "Combat",
    group = "combat", maxLevel = 10, maxXp = 1000,
    levelXp = { [1] = 100, [2] = 200, [3] = 300, [4] = 400, [5] = 500,
        [6] = 600, [7] = 700, [8] = 800, [9] = 900, [10] = 1000 },
}
local traits = {
    Positive = {
        traitType = "Positive", token = {}, label = "Positive", costPoints = 2,
        ownedConflicts = {}, blocked = false, free = false, profession = false,
    },
    Negative = {
        traitType = "Negative", token = {}, label = "Negative", costPoints = -2,
        ownedConflicts = {}, blocked = false, free = false, profession = false,
    },
}

local query = {
    ownerKey = function(actor) return actor.id end,
    listPerks = function(actor)
        local row = {}
        for key, value in pairs(perk) do row[key] = value end
        row.currentXp, row.currentLevel = actor.xp, actor.level
        return { row }
    end,
    resolvePerk = function(index)
        if tonumber(index) == 1 then return perk end
        return nil, "invalidIndex"
    end,
    perkState = function(actor)
        return { currentXp = actor.xp, currentLevel = actor.level, maxXp = 1000, maxLevel = 10 }
    end,
    listTraits = function(actor, action)
        if action == "remove" then return actor.traits.Negative and { traits.Negative } or {} end
        return { traits.Positive }
    end,
    resolveTrait = function(actor, traitType)
        local info = traits[tostring(traitType)]
        if not info then return nil, "traitMissing" end
        local copy = {}
        for key, value in pairs(info) do copy[key] = value end
        return copy
    end,
    hasTrait = function(actor, traitType) return actor.traits[tostring(traitType)] == true end,
}

local mutation = {
    addXp = function(actor, info, amount)
        if actor.rejectXp then return false, "attributeApplyFailed" end
        local applied = actor.partialXp or amount
        actor.xp = actor.xp + applied
        actor.level = math.floor(actor.xp / 100)
        return true
    end,
    syncXp = function(actor)
        return actor.syncFails ~= true
    end,
    setTrait = function(actor, info, enabled)
        actor.traits[info.traitType] = enabled == true or nil
        return true
    end,
    applyTraitBenefits = function() return true, 2 end,
}

local wallet = {
    charge = function(actor, amount, request)
        if actor.balance < amount then return false, "balanceInsufficient" end
        actor.balance = actor.balance - amount
        return true, { amount = amount, id = request.operationId }
    end,
    refund = function(actor, receipt)
        actor.balance = actor.balance + receipt.amount
        return true
    end,
}

local metricRows = {}
local metrics = {
    increment = function(actor, changes)
        local actorKey = actor.id
        local row = metricRows[actorKey] or {}
        metricRows[actorKey] = row
        local before, after = {}, {}
        for name, amount in pairs(changes) do
            before[name] = row[name] or 0
            after[name] = before[name] + amount
            if after[name] < 0 then return false, "metricRangeInvalid" end
        end
        for name, value in pairs(after) do row[name] = value end
        return true, {
            actorKey = actorKey,
            before = before,
            after = after,
        }
    end,
    restore = function(actor, receipt)
        if receipt.actorKey ~= actor.id then return false, "metricReceiptInvalid" end
        local row = metricRows[actor.id] or {}
        for name, expected in pairs(receipt.after or {}) do
            if (row[name] or 0) ~= expected then return false, "metricStateChanged" end
        end
        for name, value in pairs(receipt.before or {}) do row[name] = value end
        metricRows[actor.id] = row
        return true
    end,
}

local attributesScope = scope()
local attributes = GodSystemAttributesFeatureModule.create({
    ["attributes.query"] = query,
    ["attributes.mutation"] = mutation,
    ["admin.config"] = adminPort.public,
    wallet = wallet,
    metrics = metrics,
    operations = ops,
    notifications = notifications,
}, { state = attributesScope })
truthy(attributes:start(), "attributes start")

local perksResult = attributes.public.requestListPerks({
    actor = actors.one,
    search = "Aim",
})
equal(perksResult.ok, true, "attribute perk request envelope")
equal(perksResult.code, "perks", "attribute perk request code")
equal(#perksResult.data.perks, 1, "attribute perk request data")
local attributeQuoteResult = attributes.public.requestAttributeQuote({
    actor = actors.one,
    perkIndex = 1,
    mode = "amount",
    value = 2,
})
equal(attributeQuoteResult.ok, true, "attribute quote request envelope")
equal(attributeQuoteResult.data.quote.cost, 2, "attribute quote request data")
local traitsResult = attributes.public.requestListTraits({
    actor = actors.one,
    action = "buy",
})
equal(traitsResult.ok, true, "trait list request envelope")
truthy(#traitsResult.data.traits >= 1, "trait list request data")
local traitQuoteResult = attributes.public.requestTraitQuote({
    actor = actors.one,
    action = "buy",
    traitType = "Positive",
})
equal(traitQuoteResult.ok, true, "trait quote request envelope")
equal(traitQuoteResult.data.quote.cost, 1400, "trait quote request data")

local bought = attributes.public.purchaseAttribute({
    actor = actors.one, operationId = "xp-one", perkIndex = 1, mode = "amount", value = 2,
})
equal(bought.ok, true, "attribute purchase")
equal(bought.data.appliedXp, 24, "attribute admin rate")
equal(bought.data.chargedCost, 2, "attribute charged cost")
equal(actors.one.balance, 9998, "attribute balance")
equal(metricRows.one.spentPoints, 2, "attribute spend metric")
equal(actors.two.xp, 0, "second player xp isolated")

local boughtReplay = attributes.public.purchaseAttribute({
    actor = actors.one, operationId = "xp-one", perkIndex = 1, mode = "amount", value = 99,
})
equal(boughtReplay.data.appliedXp, 24, "attribute replay result")
equal(actors.one.xp, 24, "attribute replay no duplicate xp")

actors.one.partialXp = 5
local partial = attributes.public.purchaseAttribute({
    actor = actors.one, operationId = "xp-partial", perkIndex = 1, mode = "amount", value = 2,
})
equal(partial.ok, true, "partial attribute purchase")
equal(partial.data.chargedCost, 1, "partial attribute cost")
equal(actors.one.balance, 9997, "partial refund and recharge")
equal(metricRows.one.spentPoints, 3, "partial attribute metric settlement")
actors.one.partialXp = nil

actors.two.rejectXp = true
local failedXp = attributes.public.purchaseAttribute({
    actor = actors.two, operationId = "xp-failed", perkIndex = 1, mode = "amount", value = 1,
})
equal(failedXp.ok, false, "attribute mutation failure")
equal(actors.two.balance, 10, "attribute failure payment rollback")

local traitBought = attributes.public.modifyTrait({
    actor = actors.one, operationId = "trait-buy", action = "buy", traitType = "Positive",
})
equal(traitBought.ok, true, "positive trait purchase")
equal(actors.one.traits.Positive, true, "positive trait applied")
equal(traitBought.data.chargedCost, 1400, "admin trait price")
equal(metricRows.one.spentPoints, 1403, "trait spend metric")
equal(metricRows.one.modifiedTraits, 1, "trait count metric")

local traitFailed = attributes.public.modifyTrait({
    actor = actors.two, operationId = "trait-failed", action = "buy", traitType = "Positive",
})
equal(traitFailed.ok, false, "trait insufficient funds")
equal(actors.two.traits.Positive, nil, "trait rolled back after payment failure")

local stateData = attributesScope.inspect()
truthy(stateData.players.one.stats == nil, "attribute state retained shared metrics")
truthy(stateData.players.two == nil or stateData.players.two.stats == nil,
    "second player state retained shared metrics")
truthy(metricRows.two == nil or (metricRows.two.modifiedTraits or 0) == 0,
    "second player metrics are not isolated")

local badRuntime = GodSystemAdminRuntimePlatform.create({}, {
    binding = { apply = function(_, _, revision) return revision == 0 end },
})
badRuntime:start()
local isolatedAdmin = GodSystemAdminFeatureModule.create({
    ["admin.source"] = sourceInstance.public,
    ["admin.permissions"] = permissionInstance.public,
    ["admin.runtime"] = badRuntime.public,
    operations = operations(),
    notifications = notifications,
}, { state = scope() })
truthy(isolatedAdmin:start(), "isolated admin start")
local isolatedFailure = isolatedAdmin.public.setSettings({
    actor = administrator, operationId = "isolated-failure", settings = { AttributeXPPerCoin = 20 },
})
equal(isolatedFailure.ok, false, "admin runtime failure contained")
local attributesHealth = attributes:health()
if attributesHealth.ok ~= true then
    error("admin failure does not poison attributes: "
        .. tostring(attributesHealth.code) .. " / "
        .. tostring(attributesHealth.data and attributesHealth.data.lastIssue
            and attributesHealth.data.lastIssue.stage), 2)
end
equal(isolatedAdmin:health().ok, false, "failing admin health is local")

print("Test-GodSystemV422012AttributesAdminModuleRuntime passed")
