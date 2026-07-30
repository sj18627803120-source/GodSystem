local luaRoot = assert(arg and arg[1], "Lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/init.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

require "GodSystem/Runtime/ConfigSnapshot"

local source = assert(GodSystemConfig, "published config missing")
local originalVersion = source.Version
local originalShopCount = #source.ShopItems
local originalTaskCount = #source.TaskTemplates
local originalShopCategory = source.ShopItems[1].group
local originalShopType = source.ShopItems[1].items[1].fullType
local originalBankChance = source.BankInvestmentProfiles.stable.gainChance
local originalTerminalCapacity = source.TerminalCapacityLevels[1].value

local snapshot = GodSystemRuntimeConfigSnapshot.build()
expect(snapshot ~= source, "snapshot aliases published config")
expect(snapshot.Version == "42.20.1.1", "published version mapping changed")
expect(snapshot.StartingPoints == 60, "starting points mapping changed")
expect(snapshot.KillPointReward == 1, "kill reward mapping changed")
expect(#snapshot.shop.products == 17 and originalShopCount == 17,
    "published shop item count changed")
expect(#snapshot.tasks.templates == 25 and originalTaskCount == 25,
    "published task template count changed")
expect(snapshot.shop.products[1].categoryKey == snapshot.shop.products[1].group,
    "ShopItems.group was not mapped to categoryKey")
expect(snapshot.tasks.dailyCount == 5
    and snapshot.tasks.maxActive == 3
    and snapshot.tasks.maxDailyCount == 20
    and snapshot.tasks.maxActiveLimit == 10,
    "task limit mapping changed")
expect(snapshot.tasks.refreshCost == 30
    and snapshot.tasks.defaultLimitHours == 24,
    "task timing/cost mapping changed")

expect(snapshot.upgrades.CarryCapacityPerLevel == 2
    and snapshot.upgrades.CarryCapacityBaseCost == 2000
    and snapshot.upgrades.CarryCapacityCostMultiplier == 1.5,
    "carry upgrade mapping changed")
expect(snapshot.upgrades.TerminalCapacityLevels[2].value == 15
    and snapshot.upgrades.TerminalCapacityLevels[2].upgradeCost == 60,
    "terminal capacity mapping changed")
expect(snapshot.upgrades.TerminalReductionLevels[8].value == 99
    and snapshot.upgrades.TerminalReductionLevels[8].upgradeCost == 2500,
    "terminal reduction mapping changed")
expect(snapshot.medical.MedicalCheckInfectionCost == 50
    and snapshot.medical.MedicalHealInjuriesCost == 5000
    and snapshot.medical.MedicalCureInfectionCost == 2000,
    "medical cost mapping changed")
expect(snapshot.home.HomeSetCost == 100
    and snapshot.home.HomeTravelCost == 10
    and snapshot.home.TempTeleportSlotCost == 500
    and snapshot.home.TempTeleportSetCost == 100,
    "home cost mapping changed")

expect(snapshot.AutoRecyclerFullType == "GodSystem.SystemSpaceTerminal",
    "terminal fullType mapping changed")
expect(snapshot.TerminalReliefFullType == "GodSystem.SystemTerminalRelief",
    "terminal relief fullType mapping changed")
expect(snapshot.TerminalReliefMarkerKey == source.TerminalReliefItemMarkerKey,
    "terminal relief marker alias missing")
expect(snapshot.AutoLoaderFullType == "GodSystem.SystemAutoLoader"
    and snapshot.AutoLoaderAmmoCapacity == 2000,
    "autoloader root mapping changed")
expect(snapshot.autoLoader.fullType == snapshot.AutoLoaderFullType
    and snapshot.autoLoader.ammoCapacity == snapshot.AutoLoaderAmmoCapacity,
    "autoloader section/root mismatch")

expect(snapshot.bank.deathPenaltyRatio == 0.3
    and snapshot.bank.earlyWithdrawPenaltyRatio == 0.05,
    "bank penalty mapping changed")
expect(#snapshot.bank.fixedTerms == 3
    and snapshot.bank.fixedTerms[3].hours == 168
    and snapshot.bank.fixedTerms[3].interestRate == 0.18,
    "bank fixed-term mapping changed")
expect(snapshot.bank.investmentSettlementHours == 24
    and snapshot.bank.investmentMinimum == 1
    and snapshot.bank.investmentProfiles.stable.gainChance == 70,
    "bank investment mapping changed")
expect(snapshot.bank.loanBaseCredit == 2000
    and snapshot.bank.loanSingleDueHours == 72
    and snapshot.bank.loanZombieMinDistance == 20
    and snapshot.bank.loanZombieMaxDistance == 45,
    "bank loan mapping changed")

require "GodSystem/Features/Bank/Rules"
local bankRules = GodSystemBankFeatureRules.config(snapshot.bank)
expect(bankRules.deathPenaltyRatio == snapshot.bank.deathPenaltyRatio
    and bankRules.loanBaseCredit == snapshot.bank.loanBaseCredit
    and bankRules.loanInstallmentPlans[3].periods == 10,
    "bank rules did not consume mapped config")

require "GodSystem/Platform/Terminal/Config"
local terminal = GodSystemTerminalConfigPlatform.create({}, {
    configSnapshot = snapshot,
})
terminal:start()
local terminalConfig = terminal.public.snapshot()
expect(terminalConfig.terminalFullType == snapshot.AutoRecyclerFullType
    and terminalConfig.reliefFullType == snapshot.TerminalReliefFullType
    and terminalConfig.capacityLevelKey == snapshot.AutoRecyclerCapacityLevelKey,
    "terminal strict adapter/config mismatch")

require "GodSystem/Platform/Storage/Config"
local storage = GodSystemStorageConfigPlatform.create({}, {
    configSnapshot = snapshot,
})
storage:start()
local storageConfig = storage.public.snapshot()
expect(storageConfig.maxNodes == 128
    and storageConfig.maxDepth == 32
    and storageConfig.maxIndexedItems == 20000
    and storageConfig.indexBatchItems == 250
    and storageConfig.coreRecoveryCost == 2000,
    "storage strict defaults changed for absent published fields")

require "GodSystem/Platform/Progression/UpgradesConfig"
local upgrades = GodSystemUpgradesConfigPlatform.create({}, {
    binding = { config = snapshot.upgrades },
})
upgrades:start()
local carryQuote = upgrades.public.quote(nil, "carryCapacity", 0)
local terminalQuote = upgrades.public.quote(nil, "terminalCapacity", 1)
expect(carryQuote and carryQuote.cost == 2000 and carryQuote.nextValue == 1,
    "carry upgrade adapter/config mismatch")
expect(terminalQuote and terminalQuote.cost == 60
    and terminalQuote.value == 15 and terminalQuote.nextValue == 2,
    "terminal upgrade adapter/config mismatch")

local overridden = GodSystemRuntimeConfigSnapshot.build({
    adminSnapshot = {
        settings = {
            EnableShop = false,
            EnableCompanion = false,
            EnableAutoLoaderShop = true,
            ShopBuyPriceMultiplier = 2.5,
            RecycleSellPriceMultiplier = 3,
            CompanionPriceMultiplier = 4,
            AutoLoaderAmmoCapacity = 3456,
            TaskRewardMultiplier = 2,
            TaskPenaltyMultiplier = 0.5,
        },
        itemOverrides = {
            ["ThirdParty.Sample"] = {
                buyPrice = 321,
                sellPrice = 17,
                category = "material",
                shopEnabled = false,
                recycleEnabled = true,
                lotteryEnabled = false,
            },
        },
    },
})
expect(overridden.features.EnableShop == false
    and overridden.shop.enabled == false,
    "admin feature override entry was not preserved")
expect(overridden.companion.enabled == false
    and overridden.companion.priceMultiplier == 4,
    "companion admin override mapping changed")
expect(overridden.AutoLoaderAmmoCapacity == 3456
    and overridden.autoLoader.ammoCapacity == 3456,
    "autoloader admin override mapping changed")
expect(overridden.shop.buyPriceMultiplier == 2.5
    and overridden.recycle.sellPriceMultiplier == 3,
    "economy admin override entry was not preserved")
expect(overridden.tasks.rewardMultiplier == 2
    and overridden.tasks.penaltyMultiplier == 0.5,
    "task multiplier override entry was not preserved")
expect(overridden.itemOverrides["ThirdParty.Sample"].buyPrice == 321
    and overridden.eligibility.itemOverrides["ThirdParty.Sample"].shopEnabled == false,
    "third-party item override entry was not preserved")

snapshot.Version = "mutated"
snapshot.ShopItems[1].group = "mutated"
snapshot.shop.products[1].categoryKey = "mutated"
snapshot.shop.products[1].items[1].fullType = "Mutated.Item"
snapshot.tasks.templates[1].target = -1
snapshot.bank.investmentProfiles.stable.gainChance = -1
snapshot.upgrades.TerminalCapacityLevels[1].value = -1
snapshot.admin.settings.StartingPoints = -1

expect(source.Version == originalVersion, "snapshot version mutation contaminated source")
expect(source.ShopItems[1].group == originalShopCategory,
    "snapshot root mutation contaminated source shop row")
expect(source.ShopItems[1].items[1].fullType == originalShopType,
    "snapshot product mutation contaminated source item")
expect(source.TaskTemplates[1].target ~= -1,
    "snapshot task mutation contaminated source")
expect(source.BankInvestmentProfiles.stable.gainChance == originalBankChance,
    "snapshot bank mutation contaminated source")
expect(source.TerminalCapacityLevels[1].value == originalTerminalCapacity,
    "snapshot terminal mutation contaminated source")

local rebuilt = GodSystemRuntimeConfigSnapshot.build()
expect(rebuilt.Version == originalVersion
    and rebuilt.shop.products[1].categoryKey == originalShopCategory
    and rebuilt.shop.products[1].items[1].fullType == originalShopType,
    "new snapshot inherited mutations from previous snapshot")

print("Test-GodSystemV422012ConfigSnapshotRuntime passed")
