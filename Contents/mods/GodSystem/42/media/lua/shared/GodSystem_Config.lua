GodSystemConfig = GodSystemConfig or {}

GodSystemConfig.ModName = "神级系统"
GodSystemConfig.DataKey = "GodSystem_CN_Data"
GodSystemConfig.Version = "42.20.2.1"

GodSystemConfig.StartingPoints = 60
GodSystemConfig.CurrencyName = "系统币"
GodSystemConfig.CurrencyItems = {
    { fullType = "GodSystem.SystemCoin100", value = 100, label = "系统币（100）" },
    { fullType = "GodSystem.SystemCoin10", value = 10, label = "系统币（10）" },
    { fullType = "GodSystem.SystemCoin1", value = 1, label = "系统币（1）" },
}
GodSystemConfig.KillPointReward = 1
GodSystemConfig.DailyTaskCount = 5
GodSystemConfig.MaxActiveTasks = 3
GodSystemConfig.MaxDailyTaskLimit = 20
GodSystemConfig.MaxActiveTaskLimit = 10
GodSystemConfig.DailyTaskUpgradeCosts = {
    [6] = 50,
    [7] = 60,
    [8] = 70,
    [9] = 85,
    [10] = 100,
    [11] = 120,
    [12] = 145,
    [13] = 170,
    [14] = 200,
    [15] = 230,
    [16] = 260,
    [17] = 300,
    [18] = 340,
    [19] = 380,
    [20] = 420,
}
GodSystemConfig.ActiveTaskUpgradeCosts = {
    [4] = 100,
    [5] = 150,
    [6] = 220,
    [7] = 300,
    [8] = 420,
    [9] = 560,
    [10] = 750,
}
GodSystemConfig.CarryCapacityPerLevel = 2
GodSystemConfig.CarryCapacityBaseCost = 2000
GodSystemConfig.CarryCapacityCostMultiplier = 1.5
GodSystemConfig.RefreshTaskCost = 30
GodSystemConfig.DefaultTaskLimitHours = 24
GodSystemConfig.MedicalCheckInfectionCost = 50
GodSystemConfig.MedicalHealInjuriesCost = 5000
GodSystemConfig.MedicalCureInfectionCost = 2000
GodSystemConfig.HistoryLimit = 40
GodSystemConfig.EnableDebugTools = false
GodSystemConfig.HomeSetCost = 100
GodSystemConfig.HomeTravelCost = 10
GodSystemConfig.TempTeleportSlotCost = 500
GodSystemConfig.TempTeleportSetCost = 100
GodSystemConfig.TempTeleportMaxSlots = 3
GodSystemConfig.HomeSafeZoneScanIntervalHours = 0.5
GodSystemConfig.HomeSafeZoneInsufficientNoticeHours = 1
GodSystemConfig.HomeSafeZoneLevels = {
    { level = 1, radius = 12, unlockCost = 500, clearCost = 8 },
    { level = 2, radius = 20, upgradeCost = 1000, clearCost = 12 },
    { level = 3, radius = 30, upgradeCost = 2000, clearCost = 18 },
    { level = 4, radius = 45, upgradeCost = 3500, clearCost = 28 },
    { level = 5, radius = 60, upgradeCost = 5500, clearCost = 40 },
}
GodSystemConfig.BankDeathDemandPenaltyRatio = 0.3
GodSystemConfig.BankEarlyWithdrawPenaltyRatio = 0.05
GodSystemConfig.BankFixedTerms = {
    { id = "d1", days = 1, hours = 24, interestRate = 0.02 },
    { id = "d3", days = 3, hours = 72, interestRate = 0.07 },
    { id = "d7", days = 7, hours = 168, interestRate = 0.18 },
}
GodSystemConfig.BankInvestmentSettlementHours = 24
GodSystemConfig.BankInvestmentMinAmount = 1
GodSystemConfig.BankInvestmentProfiles = {
    stable = { id = "stable", gainChance = 70, lossChance = 5, gainPercent = 1, lossPercent = 1 },
    balanced = { id = "balanced", gainChance = 55, lossChance = 30, gainPercent = 3, lossPercent = 2 },
    aggressive = { id = "aggressive", gainChance = 45, lossChance = 45, gainPercent = 8, lossPercent = 5 },
}
GodSystemConfig.BankLoanBaseCredit = 2000
GodSystemConfig.BankLoanCreditSpendStep = 100
GodSystemConfig.BankLoanCreditPerStep = 5
GodSystemConfig.BankLoanSingleDueHours = 72
GodSystemConfig.BankLoanSingleInterestRate = 0.05
GodSystemConfig.BankLoanPeriodHours = 72
GodSystemConfig.BankLoanInstallmentPlans = {
    { id = "i3", periods = 3, totalInterestRate = 0.10 },
    { id = "i5", periods = 5, totalInterestRate = 0.18 },
    { id = "i10", periods = 10, totalInterestRate = 0.30 },
}
GodSystemConfig.BankLoanOverduePenaltyDailyRate = 0.05
GodSystemConfig.BankLoanOverduePenaltyMaxRate = 0.50
GodSystemConfig.BankLoanBankruptcyGraceHours = 240
GodSystemConfig.BankLoanFreezeHours = 168
GodSystemConfig.BankLoanZombieDebtPerZombie = 50
GodSystemConfig.BankLoanZombieMaxCount = 100
GodSystemConfig.BankLoanZombieMinDistance = 20
GodSystemConfig.BankLoanZombieMaxDistance = 45
GodSystemConfig.BatchRecycleCount = 5
GodSystemConfig.AllowRecycleContainers = false
GodSystemConfig.AutoRecyclerFullType = "GodSystem.SystemSpaceTerminal"
GodSystemConfig.AutoRecyclerFullTypes = {
    ["GodSystem.SystemSpaceTerminal"] = true,
}
GodSystemConfig.AutoLoaderFullType = "GodSystem.SystemAutoLoader"
GodSystemConfig.AutoLoaderAmmoCapacity = 2000
GodSystemConfig.TaskItemBlacklist = {
    ["GodSystem.StorageController"] = true,
}
GodSystemConfig.AutoRecyclerMarkerKey = "GodSystemAutoRecycler"
GodSystemConfig.AutoRecyclerLevelKey = "GodSystemAutoRecyclerLevel"
GodSystemConfig.AutoRecyclerCapacityLevelKey = "GodSystemTerminalCapacityLevel"
GodSystemConfig.AutoRecyclerReductionLevelKey = "GodSystemTerminalReductionLevel"
GodSystemConfig.TerminalReliefFullType = "GodSystem.SystemTerminalRelief"
GodSystemConfig.TerminalReliefLevelKey = "GodSystemTerminalReliefLevel"
GodSystemConfig.TerminalReliefItemMarkerKey = "GodSystemTerminalRelief"
GodSystemConfig.TerminalReliefOwnerKey = "GodSystemTerminalReliefOwner"
GodSystemConfig.TerminalReliefOffsetKey = "GodSystemTerminalReliefOffset"
GodSystemConfig.TerminalReliefVersionKey = "GodSystemTerminalReliefVersion"
GodSystemConfig.TerminalReliefUpgradeCost = 2000
GodSystemConfig.TerminalReliefPerLevel = 5
GodSystemConfig.TerminalReliefMaxOffset = 2000
GodSystemConfig.AutoRecyclerCapacity = 10
GodSystemConfig.AutoRecyclerWeightReduction = 50
GodSystemConfig.AutoRecyclerIntervalHours = 0
GodSystemConfig.WaistAutoRecycleUnlockCost = 100
GodSystemConfig.WaistAutoRecycleIntervalHours = 1
GodSystemConfig.AutoRecyclerLevels = {
    { level = 1, capacity = 10, weightReduction = 50, upgradeCost = 0 },
    { level = 2, capacity = 15, weightReduction = 55, upgradeCost = 60 },
    { level = 3, capacity = 20, weightReduction = 60, upgradeCost = 120 },
    { level = 4, capacity = 25, weightReduction = 65, upgradeCost = 220 },
    { level = 5, capacity = 30, weightReduction = 70, upgradeCost = 350 },
    { level = 6, capacity = 35, weightReduction = 80, upgradeCost = 550 },
    { level = 7, capacity = 42, weightReduction = 90, upgradeCost = 800 },
    { level = 8, capacity = 49, weightReduction = 99, upgradeCost = 1100 },
}
GodSystemConfig.TerminalCapacityLevels = {
    { level = 1, value = 10, upgradeCost = 0 },
    { level = 2, value = 15, upgradeCost = 60 },
    { level = 3, value = 20, upgradeCost = 120 },
    { level = 4, value = 25, upgradeCost = 220 },
    { level = 5, value = 30, upgradeCost = 350 },
    { level = 6, value = 35, upgradeCost = 550 },
    { level = 7, value = 42, upgradeCost = 800 },
    { level = 8, value = 49, upgradeCost = 1100 },
}
GodSystemConfig.TerminalCapacityMaxLevel = #GodSystemConfig.TerminalCapacityLevels
GodSystemConfig.TerminalReductionLevels = {
    { level = 1, value = 50, upgradeCost = 0 },
    { level = 2, value = 55, upgradeCost = 100 },
    { level = 3, value = 60, upgradeCost = 200 },
    { level = 4, value = 65, upgradeCost = 400 },
    { level = 5, value = 70, upgradeCost = 700 },
    { level = 6, value = 80, upgradeCost = 1100 },
    { level = 7, value = 90, upgradeCost = 1700 },
    { level = 8, value = 99, upgradeCost = 2500 },
}
GodSystemConfig.TerminalFreshnessLevels = {
    { level = 1, restorePerDay = 0.25, upgradeCost = 1250 },
    { level = 2, restorePerDay = 0.5, upgradeCost = 3250 },
    { level = 3, restorePerDay = 1.0, upgradeCost = 7000 },
}
GodSystemConfig.TerminalFreshnessMaxDays = 365
GodSystemConfig.TerminalFreshnessPackages = {
    [1] = 100,
    [10] = 900,
    [20] = 1600,
    [30] = 2100,
}
GodSystemConfig.AutoRecyclerRecoverCosts = {
    { maxLevel = 3, cost = 10 },
    { maxLevel = 6, cost = 35 },
    { maxLevel = GodSystemConfig.TerminalCapacityMaxLevel, cost = 80 },
}
GodSystemConfig.AutoUnlockShopFromRecycle = true
GodSystemConfig.AutoShopAllowAnyModule = true
GodSystemConfig.AutoShopModMinBuy = 200
GodSystemConfig.AutoShopModWeaponMinBuy = 600
GodSystemConfig.AutoShopModAmmoMinBuy = 250
GodSystemConfig.AutoShopModClothingMinBuy = 180
GodSystemConfig.AutoShopListOnlyCostRatio = 0.5
GodSystemConfig.AutoShopListOnlyMinCost = 50
GodSystemConfig.RecycleSellRatio = 0.05
GodSystemConfig.ShopLotteryMinCost = 30
GodSystemConfig.ShopLotteryCostMultiplier = 1
GodSystemConfig.LotteryAllPrice = 100
GodSystemConfig.LotteryCustomMaxCount = 50
GodSystemConfig.LotteryCategoryPrices = {
    accessory = 90,
    ammo = 150,
    casing = 60,
    clothing = 90,
    container = 150,
    cooking = 60,
    drainable = 60,
    drink = 60,
    electronics = 150,
    farming = 60,
    fire = 60,
    food = 60,
    key = 60,
    literature = 60,
    material = 60,
    medical = 90,
    normal = 60,
    other = 60,
    security = 150,
    tool = 150,
    vehicle = 200,
    weapon = 400,
}
GodSystemConfig.LotteryBlacklist = {
    ["GodSystem.SystemRepairKit"] = true,
    ["GodSystem.DurabilityCore"] = true,
    ["GodSystem.SystemVehicleRepairModule"] = true,
    ["GodSystem.SystemTerminalRelief"] = true,
    ["GodSystem.SystemSpaceTerminal"] = true,
    ["GodSystem.StorageController"] = true,
    ["GodSystem.SystemAutoLoader"] = true,
}
GodSystemConfig.ModCategoryBuyPrices = {
    accessory = 180,
    ammo = 250,
    casing = 120,
    clothing = 180,
    container = 260,
    cooking = 120,
    drainable = 140,
    drink = 80,
    electronics = 220,
    farming = 120,
    fire = 120,
    food = 80,
    key = 120,
    literature = 160,
    material = 90,
    medical = 160,
    normal = 120,
    other = 120,
    security = 220,
    tool = 220,
    vehicle = 320,
    weapon = 600,
}
GodSystemConfig.UnknownModItemRecycleValue = 1
GodSystemConfig.EconomyConversionSafetyMargin = 0.10
GodSystemConfig.EconomyUnknownDynamicOutputCount = 500
GodSystemConfig.EconomyPolicyVersion = "42.20.2.1"
GodSystemConfig.DailyRecycleSoftCap = 0
GodSystemConfig.DiminishedRecyclePayout = 1
GodSystemConfig.PositiveTraitCostPerPoint = 800
GodSystemConfig.NegativeTraitRemoveCostPerPoint = 500
GodSystemConfig.AttributeXPPerCoin = 10
GodSystemConfig.TraitBlockedTypes = {
    ["Obese"] = true,
    ["Overweight"] = true,
    ["Underweight"] = true,
    ["Very Underweight"] = true,
    ["VeryUnderweight"] = true,
    ["Emaciated"] = true,
    ["Strong"] = true,
    ["Stout"] = true,
    ["Weak"] = true,
    ["Feeble"] = true,
    ["Fit"] = true,
    ["Athletic"] = true,
    ["Unfit"] = true,
    ["Out of Shape"] = true,
    ["OutOfShape"] = true,
    ["EMACIATED"] = true,
    ["VERY_UNDERWEIGHT"] = true,
    ["UNDERWEIGHT"] = true,
    ["OVERWEIGHT"] = true,
    ["OBESE"] = true,
    ["FIT"] = true,
    ["ATHLETIC"] = true,
    ["STOUT"] = true,
    ["STRONG"] = true,
    ["BLACKSMITH2"] = true,
    ["COOK2"] = true,
    ["MECHANICS2"] = true,
    ["NUTRITIONIST2"] = true,
}
GodSystemConfig.TraitStableTypes = {
    ["SpeedDemon"] = true,
    ["SundayDriver"] = true,
    ["CatEyes"] = true,
    ["NightVision"] = true,
    ["Outdoorsman"] = true,
    ["Wakeful"] = true,
    ["Sleepyhead"] = true,
    ["Dextrous"] = true,
    ["AllThumbs"] = true,
    ["FastReader"] = true,
    ["SlowReader"] = true,
    ["Brave"] = true,
    ["Cowardly"] = true,
    ["Lucky"] = true,
    ["Unlucky"] = true,
    ["FastLearner"] = true,
    ["SlowLearner"] = true,
    ["FastHealer"] = true,
    ["SlowHealer"] = true,
    ["LowThirst"] = true,
    ["HighThirst"] = true,
    ["LightEater"] = true,
    ["HeartyAppitite"] = true,
    ["HeartyAppetite"] = true,
    ["Organized"] = true,
    ["Disorganized"] = true,
    ["ThickSkinned"] = true,
    ["ThinSkinned"] = true,
    ["Inconspicuous"] = true,
    ["Conspicuous"] = true,
    ["Graceful"] = true,
    ["Clumsy"] = true,
    ["KeenHearing"] = true,
    ["HardOfHearing"] = true,
    ["Deaf"] = true,
    ["Smoker"] = true,
    ["ProneToIllness"] = true,
    ["Resilient"] = true,
    ["WeakStomach"] = true,
    ["IronGut"] = true,
    ["Pacifist"] = true,
    ["Agoraphobic"] = true,
    ["Claustophobic"] = true,
    ["Claustrophobic"] = true,
    ["Hemophobic"] = true,
}
GodSystemConfig.TraitFallbackCatalog = {
    { type = "SpeedDemon", cost = 1, labelKey = "UI_trait_speedDemon", mutual = { "SundayDriver" } },
    { type = "NightVision", cost = 2, labelKey = "UI_trait_nightvision" },
    { type = "Outdoorsman", cost = 2, labelKey = "UI_trait_outdoorsman" },
    { type = "Wakeful", cost = 2, labelKey = "UI_trait_wakeful", mutual = { "Sleepyhead" } },
    { type = "Dextrous", cost = 2, labelKey = "UI_trait_dextrous", mutual = { "AllThumbs" } },
    { type = "FastReader", cost = 2, labelKey = "UI_trait_fastReader", mutual = { "SlowReader" } },
    { type = "Brave", cost = 4, labelKey = "UI_trait_brave", mutual = { "Cowardly" } },
    { type = "Lucky", cost = 4, labelKey = "UI_trait_lucky", mutual = { "Unlucky" } },
    { type = "FastLearner", cost = 6, labelKey = "UI_trait_fastLearner", mutual = { "SlowLearner" } },
    { type = "FastHealer", cost = 6, labelKey = "UI_trait_fastHealer", mutual = { "SlowHealer" } },
    { type = "LowThirst", cost = 6, labelKey = "UI_trait_lowThirst", mutual = { "HighThirst" } },
    { type = "LightEater", cost = 4, labelKey = "UI_trait_lightEater", mutual = { "HeartyAppitite", "HeartyAppetite" } },
    { type = "Organized", cost = 6, labelKey = "UI_trait_organized", mutual = { "Disorganized" } },
    { type = "ThickSkinned", cost = 8, labelKey = "UI_trait_thickSkinned", mutual = { "ThinSkinned" } },
    { type = "Inconspicuous", cost = 4, labelKey = "UI_trait_inconspicuous", mutual = { "Conspicuous" } },
    { type = "Graceful", cost = 4, labelKey = "UI_trait_graceful", mutual = { "Clumsy" } },
    { type = "KeenHearing", cost = 6, labelKey = "UI_trait_keenHearing", mutual = { "HardOfHearing", "Deaf" } },
    { type = "Resilient", cost = 4, labelKey = "UI_trait_resilient", mutual = { "ProneToIllness" } },
    { type = "IronGut", cost = 3, labelKey = "UI_trait_irongut", mutual = { "WeakStomach" } },
    { type = "EagleEyed", cost = 6, labelKey = "UI_trait_eagleEyed", mutual = { "ShortSighted" } },

    { type = "SundayDriver", cost = -1, labelKey = "UI_trait_sundayDriver", mutual = { "SpeedDemon" } },
    { type = "Sleepyhead", cost = -4, labelKey = "UI_trait_sleepyhead", mutual = { "Wakeful" } },
    { type = "AllThumbs", cost = -2, labelKey = "UI_trait_allThumbs", mutual = { "Dextrous" } },
    { type = "SlowReader", cost = -2, labelKey = "UI_trait_slowReader", mutual = { "FastReader" } },
    { type = "Cowardly", cost = -2, labelKey = "UI_trait_cowardly", mutual = { "Brave" } },
    { type = "Unlucky", cost = -4, labelKey = "UI_trait_unlucky", mutual = { "Lucky" } },
    { type = "SlowLearner", cost = -6, labelKey = "UI_trait_slowLearner", mutual = { "FastLearner" } },
    { type = "SlowHealer", cost = -6, labelKey = "UI_trait_slowHealer", mutual = { "FastHealer" } },
    { type = "HighThirst", cost = -6, labelKey = "UI_trait_highThirst", mutual = { "LowThirst" } },
    { type = "HeartyAppitite", cost = -4, labelKey = "UI_trait_heartyAppetite", mutual = { "LightEater" } },
    { type = "HeartyAppetite", cost = -4, labelKey = "UI_trait_heartyAppetite", mutual = { "LightEater" } },
    { type = "Disorganized", cost = -4, labelKey = "UI_trait_disorganized", mutual = { "Organized" } },
    { type = "ThinSkinned", cost = -8, labelKey = "UI_trait_thinSkinned", mutual = { "ThickSkinned" } },
    { type = "Conspicuous", cost = -4, labelKey = "UI_trait_conspicuous", mutual = { "Inconspicuous" } },
    { type = "Clumsy", cost = -2, labelKey = "UI_trait_clumsy", mutual = { "Graceful" } },
    { type = "HardOfHearing", cost = -4, labelKey = "UI_trait_hardOfHearing", mutual = { "KeenHearing" } },
    { type = "Deaf", cost = -12, labelKey = "UI_trait_deaf", mutual = { "KeenHearing" } },
    { type = "ProneToIllness", cost = -4, labelKey = "UI_trait_proneToIllness", mutual = { "Resilient" } },
    { type = "WeakStomach", cost = -3, labelKey = "UI_trait_weakStomach", mutual = { "IronGut" } },
    { type = "Smoker", cost = -4, labelKey = "UI_trait_smoker" },
    { type = "Pacifist", cost = -4, labelKey = "UI_trait_pacifist" },
    { type = "Agoraphobic", cost = -4, labelKey = "UI_trait_agoraphobic" },
    { type = "Claustophobic", cost = -4, labelKey = "UI_trait_claustrophobic" },
    { type = "Claustrophobic", cost = -4, labelKey = "UI_trait_claustrophobic" },
    { type = "Hemophobic", cost = -5, labelKey = "UI_trait_hemophobic" },
    { type = "ShortSighted", cost = -2, labelKey = "UI_trait_shortSighted", mutual = { "EagleEyed" } },
}
GodSystemConfig.RecycleDefaultAllowedModules = {
    Base = true,
    farming = true,
}
GodSystemConfig.AutoShopAllowedModules = {
    Base = true,
    farming = true,
}
GodSystemConfig.AutoShopBlacklist = {
    ["Base.KeyRing"] = true,
    ["Base.Key"] = true,
    ["GodSystem.SystemCoin1"] = true,
    ["GodSystem.SystemCoin10"] = true,
    ["GodSystem.SystemCoin100"] = true,
    ["GodSystem.SystemRepairKit"] = true,
    ["GodSystem.DurabilityCore"] = true,
    ["GodSystem.SystemVehicleRepairModule"] = true,
    ["GodSystem.SystemSpaceTerminal"] = true,
    ["GodSystem.SystemTerminalRelief"] = true,
    ["GodSystem.StorageController"] = true,
    ["GodSystem.SystemAutoLoader"] = true,
}

GodSystemConfig.FloatingButton = {
    x = 40,
    y = 220,
    width = 48,
    height = 48,
}

GodSystemConfig.RecycleBlacklist = {
    ["Base.KeyRing"] = true,
    ["Base.Key"] = true,
    ["GodSystem.SystemCoin1"] = true,
    ["GodSystem.SystemCoin10"] = true,
    ["GodSystem.SystemCoin100"] = true,
    ["GodSystem.SystemSpaceTerminal"] = true,
    ["GodSystem.SystemTerminalRelief"] = true,
    ["GodSystem.StorageController"] = true,
    ["GodSystem.SystemAutoLoader"] = true,
}

GodSystemConfig.ShopItems = {
    {
        id = "bandage_single",
        group = "medical",
        price = 20,
        items = { { fullType = "Base.Bandage", count = 1 } }
    },
    {
        id = "bandaid_single",
        group = "medical",
        price = 12,
        items = { { fullType = "Base.Bandaid", count = 1 } }
    },
    {
        id = "alcohol_wipes_single",
        group = "medical",
        price = 25,
        items = { { fullType = "Base.AlcoholWipes", count = 1 } }
    },
    {
        id = "vitamins_single",
        group = "medical",
        price = 70,
        items = { { fullType = "Base.PillsVitamins", count = 1 } }
    },
    {
        id = "hammer_single",
        group = "tool",
        price = 120,
        items = { { fullType = "Base.Hammer", count = 1 } }
    },
    {
        id = "saw_single",
        group = "tool",
        price = 140,
        items = { { fullType = "Base.Saw", count = 1 } }
    },
    {
        id = "screwdriver_single",
        group = "tool",
        price = 80,
        items = { { fullType = "Base.Screwdriver", count = 1 } }
    },
    {
        id = "nails_box_single",
        group = "material",
        price = 120,
        items = { { fullType = "Base.NailsBox", count = 1 } }
    },
    {
        id = "plank_single",
        group = "material",
        price = 20,
        items = { { fullType = "Base.Plank", count = 1 } }
    },
    {
        id = "duct_tape_single",
        group = "material",
        price = 55,
        items = { { fullType = "Base.DuctTape", count = 1 } }
    },
    {
        id = "garbage_bag_single",
        group = "material",
        price = 25,
        items = { { fullType = "Base.Garbagebag", count = 1 } }
    },
    {
        id = "tin_opener_single",
        group = "tool",
        price = 60,
        items = { { fullType = "Base.TinOpener", count = 1 } }
    },
    {
        id = "water_bottle_single",
        group = "survival",
        price = 35,
        items = { { fullType = "Base.WaterBottle", count = 1 } }
    },
    {
        id = "system_repair_kit",
        group = "tool",
        price = 300,
        items = { { fullType = "GodSystem.SystemRepairKit", count = 1 } }
    },
    {
        id = "durability_core",
        group = "tool",
        price = 1200,
        items = { { fullType = "GodSystem.DurabilityCore", count = 1 } }
    },
    {
        id = "system_vehicle_repair_module",
        group = "vehicle",
        price = 5000,
        items = { { fullType = "GodSystem.SystemVehicleRepairModule", count = 1 } }
    },
    {
        id = "system_auto_loader",
        group = "tool",
        price = 1000,
        featureKey = "EnableAutoLoaderShop",
        items = { { fullType = "GodSystem.SystemAutoLoader", count = 1 } }
    },
}

GodSystemConfig.TaskTemplates = {
    {
        id = "kill_10",
        title = "清理街区",
        kind = "kill",
        target = 10,
        limitHours = 24,
        rewardPoints = 35,
        rewardItems = {},
        penaltyPoints = 15,
        description = "击杀 10 只僵尸。"
    },
    {
        id = "kill_30",
        title = "尸潮压制",
        kind = "kill",
        target = 30,
        limitHours = 24,
        rewardPoints = 95,
        rewardItems = { { fullType = "Base.Bandage", count = 2 } },
        penaltyPoints = 35,
        description = "击杀 30 只僵尸。"
    },
    {
        id = "kill_75",
        title = "死亡清算",
        kind = "kill",
        target = 75,
        limitHours = 36,
        rewardPoints = 240,
        rewardItems = { { fullType = "Base.ShotgunShellsBox", count = 1 } },
        penaltyPoints = 90,
        description = "击杀 75 只僵尸。"
    },
    {
        id = "recycle_12_items",
        title = "废土回收",
        kind = "recycleItems",
        target = 12,
        limitHours = 24,
        rewardPoints = 45,
        rewardItems = {},
        penaltyPoints = 15,
        description = "通过系统回收 12 件物品。"
    },
    {
        id = "recycle_100_points",
        title = "资源归拢",
        kind = "recyclePoints",
        target = 100,
        limitHours = 24,
        rewardPoints = 70,
        rewardItems = { { fullType = "Base.NailsBox", count = 1 } },
        penaltyPoints = 30,
        description = "通过回收累计获得 100 枚系统币。"
    },
    {
        id = "survive_12h",
        title = "保持低调",
        kind = "surviveHours",
        target = 12,
        limitHours = 18,
        rewardPoints = 55,
        rewardItems = { { fullType = "Base.TinnedBeans", count = 1 } },
        penaltyPoints = 15,
        description = "领取后存活 12 小时。"
    },
    {
        id = "survive_24h",
        title = "熬过今天",
        kind = "surviveHours",
        target = 24,
        limitHours = 30,
        rewardPoints = 110,
        rewardItems = { { fullType = "Base.PillsVitamins", count = 1 } },
        penaltyPoints = 35,
        description = "领取后存活 24 小时。"
    },
    {
        id = "turn_in_bandage",
        title = "医疗储备",
        kind = "turnInItem",
        target = 4,
        item = "Base.Bandage",
        limitHours = 24,
        rewardPoints = 45,
        rewardItems = { { fullType = "Base.AlcoholWipes", count = 2 } },
        penaltyPoints = 20,
        description = "提交 4 个绷带。"
    },
    {
        id = "turn_in_plank",
        title = "加固据点",
        kind = "turnInItem",
        target = 8,
        item = "Base.Plank",
        limitHours = 24,
        rewardPoints = 45,
        rewardItems = { { fullType = "Base.NailsBox", count = 1 } },
        penaltyPoints = 20,
        description = "提交 8 块木板。"
    },
    {
        id = "turn_in_canned_food",
        title = "罐头征集",
        kind = "turnInAnyItem",
        target = 5,
        items = { "Base.TinnedBeans", "Base.TinnedSoup" },
        limitHours = 24,
        rewardPoints = 55,
        rewardItems = { { fullType = "Base.WaterBottle", count = 2 } },
        penaltyPoints = 25,
        description = "提交任意 5 个指定罐头。"
    },
    {
        id = "spend_150",
        title = "系统交易认证",
        kind = "spendPoints",
        target = 150,
        limitHours = 24,
        rewardPoints = 40,
        rewardItems = { { fullType = "Base.DuctTape", count = 1 } },
        penaltyPoints = 20,
        description = "在商城累计消费 150 枚系统币。"
    },
    {
        id = "buy_3",
        title = "物资采购",
        kind = "buyItems",
        target = 3,
        limitHours = 24,
        rewardPoints = 45,
        rewardItems = {},
        penaltyPoints = 20,
        description = "在商城完成 3 次购买。"
    },
    {
        id = "kill_120",
        title = "尸群清剿",
        kind = "kill",
        target = 120,
        limitHours = 48,
        rewardPoints = 380,
        rewardItems = { { fullType = "Base.ShotgunShellsBox", count = 1 } },
        penaltyPoints = 140,
        description = "击杀 120 只僵尸。"
    },
    {
        id = "kill_200",
        title = "清空危险区",
        kind = "kill",
        target = 200,
        limitHours = 72,
        rewardPoints = 600,
        rewardItems = { { fullType = "Base.PillsVitamins", count = 2 } },
        penaltyPoints = 220,
        description = "击杀 200 只僵尸。"
    },
    {
        id = "recycle_30_items",
        title = "废料整备",
        kind = "recycleItems",
        target = 30,
        limitHours = 36,
        rewardPoints = 100,
        rewardItems = { { fullType = "Base.Garbagebag", count = 2 } },
        penaltyPoints = 35,
        description = "通过系统回收 30 件物品。"
    },
    {
        id = "recycle_60_items",
        title = "大批量回收",
        kind = "recycleItems",
        target = 60,
        limitHours = 48,
        rewardPoints = 200,
        rewardItems = { { fullType = "Base.DuctTape", count = 2 } },
        penaltyPoints = 70,
        description = "通过系统回收 60 件物品。"
    },
    {
        id = "recycle_250_points",
        title = "资源变现",
        kind = "recyclePoints",
        target = 250,
        limitHours = 36,
        rewardPoints = 170,
        rewardItems = { { fullType = "Base.NailsBox", count = 2 } },
        penaltyPoints = 65,
        description = "通过回收累计获得 250 枚系统币。"
    },
    {
        id = "recycle_500_points",
        title = "仓库清理",
        kind = "recyclePoints",
        target = 500,
        limitHours = 48,
        rewardPoints = 330,
        rewardItems = { { fullType = "Base.Bandage", count = 4 } },
        penaltyPoints = 120,
        description = "通过回收累计获得 500 枚系统币。"
    },
    {
        id = "survive_48h",
        title = "稳住两天",
        kind = "surviveHours",
        target = 48,
        limitHours = 54,
        rewardPoints = 260,
        rewardItems = { { fullType = "Base.TinnedSoup", count = 2 } },
        penaltyPoints = 85,
        description = "领取后存活 48 小时。"
    },
    {
        id = "spend_500",
        title = "中额交易认证",
        kind = "spendPoints",
        target = 500,
        limitHours = 48,
        rewardPoints = 110,
        rewardItems = { { fullType = "Base.NailsBox", count = 1 } },
        penaltyPoints = 60,
        description = "在商城累计消费 500 枚系统币。"
    },
    {
        id = "buy_10",
        title = "连续采购",
        kind = "buyItems",
        target = 10,
        limitHours = 36,
        rewardPoints = 110,
        rewardItems = { { fullType = "Base.AlcoholWipes", count = 2 } },
        penaltyPoints = 45,
        description = "在商城完成 10 次购买。"
    },
    {
        id = "move_500",
        title = "短途巡逻",
        kind = "moveDistance",
        target = 500,
        limitHours = 24,
        rewardPoints = 55,
        rewardItems = {},
        penaltyPoints = 15,
        description = "领取后移动 500 米。"
    },
    {
        id = "move_1500",
        title = "区域调查",
        kind = "moveDistance",
        target = 1500,
        limitHours = 36,
        rewardPoints = 150,
        rewardItems = { { fullType = "Base.WaterBottle", count = 1 } },
        penaltyPoints = 50,
        description = "领取后移动 1500 米。"
    },
    {
        id = "turn_in_tools",
        title = "工具调拨",
        kind = "turnInAnyItem",
        target = 2,
        items = { "Base.Hammer", "Base.Saw", "Base.Screwdriver" },
        limitHours = 36,
        rewardPoints = 100,
        rewardItems = { { fullType = "Base.NailsBox", count = 1 } },
        penaltyPoints = 45,
        description = "提交任意 2 个常用工具。"
    },
    {
        id = "turn_in_water",
        title = "饮水储备",
        kind = "turnInItem",
        target = 3,
        item = "Base.WaterBottle",
        limitHours = 36,
        rewardPoints = 45,
        rewardItems = { { fullType = "Base.TinnedBeans", count = 2 } },
        penaltyPoints = 25,
        description = "提交 3 个装满水的水瓶。"
    },
}
