require "GodSystem_Config"
require "GodSystem_AdminConfig"

GodSystemRuntimeConfigSnapshot = GodSystemRuntimeConfigSnapshot or {}

local ConfigSnapshot = GodSystemRuntimeConfigSnapshot

local FEATURE_KEYS = {
    "EnableShop",
    "EnableRecycle",
    "EnableBank",
    "EnableTeleport",
    "EnableTraits",
    "EnableWaistAutoRecycle",
    "EnableShopLottery",
    "EnableTasks",
    "EnableBankLoan",
    "EnableBankInvestments",
    "EnableCompanion",
    "EnableAttributes",
    "EnableAutoLoaderShop",
}

local ROOT_OPTIONAL_KEYS = {
    "EnableAutoRecycler",
    "EnableSystemTerminal",
    "EnableStorageNetwork",
    "StorageMaxLinks",
    "StorageMaxDepth",
    "StorageMaxIndexedItems",
    "StorageIndexBatchItems",
    "StorageIndexBudgetMs",
    "StorageCoreRecoveryCost",
    "StorageCoreUseDistance",
    "StorageManageDistance",
    "StorageCoreTokenKey",
    "StorageCoreNetworkKey",
    "StorageObjectIdKey",
    "StorageNetworkContainerKey",
    "StorageContainerSettingsKey",
    "StorageCoreHostKey",
    "StorageProtectedFullTypes",
    "TerminalDisplayName",
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function sanitizeOverrides(admin, source)
    local result = {}
    if type(source) ~= "table" then return result end
    for fullType, override in pairs(source) do
        local clean = nil
        if admin and type(admin.sanitizeItemOverride) == "function" then
            local ok, value = pcall(admin.sanitizeItemOverride, override)
            if ok then clean = value end
        elseif type(override) == "table" then
            clean = copy(override)
        end
        if clean then result[tostring(fullType)] = copy(clean) end
    end
    return result
end

local function adminSnapshot(options, source)
    local admin = options.adminConfig or GodSystemAdminConfig
    local supplied = options.adminSnapshot or options.adminState
    local raw = type(supplied) == "table" and supplied or nil
    if not raw and admin and type(admin.buildSnapshot) == "function" then
        local ok, value = pcall(admin.buildSnapshot)
        if ok and type(value) == "table" then raw = value end
    end
    raw = type(raw) == "table" and raw or {}

    local settingsSource = options.adminSettings
        or raw.settings
        or source.AdminRuntimeSettings
        or {}
    local settings
    if admin and type(admin.sanitizeSettings) == "function" then
        local ok, value = pcall(admin.sanitizeSettings, settingsSource)
        settings = ok and type(value) == "table" and value or {}
    else
        settings = copy(settingsSource)
    end

    local overridesSource = options.itemOverrides
        or raw.itemOverrides
        or source.AdminRuntimeItemOverrides
        or source.ItemOverrides
        or {}
    local overrides = sanitizeOverrides(admin, overridesSource)
    local meta = raw.meta
    if type(meta) ~= "table" and admin and type(admin.getMeta) == "function" then
        local ok, value = pcall(admin.getMeta)
        if ok then meta = value end
    end
    return {
        settings = copy(settings),
        itemOverrides = overrides,
        meta = copy(type(meta) == "table" and meta or {}),
    }
end

local function configured(settings, source, key)
    if type(settings) == "table" and settings[key] ~= nil then
        return settings[key]
    end
    return source[key]
end

local function investmentProfiles(source, settings)
    local result = copy(source.BankInvestmentProfiles or {})
    local rows = {
        { id = "stable", prefix = "BankInvestmentStable" },
        { id = "balanced", prefix = "BankInvestmentBalanced" },
        { id = "aggressive", prefix = "BankInvestmentAggressive" },
    }
    for index = 1, #rows do
        local row = rows[index]
        local profile = result[row.id] or { id = row.id }
        local mappings = {
            GainChance = "gainChance",
            LossChance = "lossChance",
            GainPercent = "gainPercent",
            LossPercent = "lossPercent",
        }
        for suffix, target in pairs(mappings) do
            local value = settings[row.prefix .. suffix]
            if value ~= nil then profile[target] = value end
        end
        profile.id = tostring(profile.id or row.id)
        result[row.id] = profile
    end
    return result
end

local function lotteryPrices(source, settings)
    local result = copy(source.LotteryCategoryPrices or {})
    local groups = {
        LotteryPriceLow = {
            "food", "drink", "material", "normal", "other", "casing",
            "cooking", "drainable", "farming", "fire", "key", "literature",
        },
        LotteryPriceMid = { "medical", "clothing", "accessory" },
        LotteryPriceUtility = { "tool", "electronics", "security", "ammo", "container" },
        LotteryPriceVehicle = { "vehicle" },
        LotteryPriceWeapon = { "weapon" },
    }
    for settingKey, categories in pairs(groups) do
        local value = settings[settingKey]
        if value ~= nil then
            for index = 1, #categories do result[categories[index]] = value end
        end
    end
    result.all = configured(settings, source, "LotteryAllPrice")
        or source.LotteryAllPrice
    return result
end

local function shopProducts(source)
    local products = copy(source.ShopItems or {})
    for index = 1, #products do
        local row = products[index]
        if type(row) == "table" and row.categoryKey == nil then
            row.categoryKey = row.group
        end
    end
    return products
end

local function copyOptionalRoot(snapshot, source)
    for index = 1, #ROOT_OPTIONAL_KEYS do
        local key = ROOT_OPTIONAL_KEYS[index]
        if source[key] ~= nil then snapshot[key] = copy(source[key]) end
    end
end

function ConfigSnapshot.build(options)
    options = type(options) == "table" and options or {}
    local source = options.config or options.source or GodSystemConfig or {}
    local snapshot = copy(source)
    local admin = adminSnapshot(options, source)
    local settings = admin.settings

    snapshot.admin = admin
    snapshot.itemOverrides = copy(admin.itemOverrides)
    snapshot.features = {}
    for index = 1, #FEATURE_KEYS do
        local key = FEATURE_KEYS[index]
        snapshot.features[key] = settings[key] ~= false
    end

    snapshot.progression = {
        killPointReward = configured(settings, source, "KillPointReward"),
    }

    snapshot.tasks = {
        enabled = snapshot.features.EnableTasks,
        templates = copy(source.TaskTemplates or {}),
        dailyCount = configured(settings, source, "DailyTaskCount"),
        maxDailyCount = source.MaxDailyTaskLimit,
        maxActive = configured(settings, source, "MaxActiveTasks"),
        maxActiveLimit = source.MaxActiveTaskLimit,
        defaultLimitHours = configured(settings, source, "DefaultTaskLimitHours"),
        refreshCost = configured(settings, source, "RefreshTaskCost"),
        rewardMultiplier = settings.TaskRewardMultiplier,
        penaltyMultiplier = settings.TaskPenaltyMultiplier,
        itemBlacklist = copy(source.TaskItemBlacklist or {}),
    }

    snapshot.shop = {
        enabled = snapshot.features.EnableShop,
        lotteryEnabled = snapshot.features.EnableShopLottery,
        products = shopProducts(source),
        listingCostByFullType = copy(source.AutoShopListingCosts or {}),
        defaultListingCost = configured(settings, source, "AutoShopListOnlyMinCost"),
        listingCostRatio = configured(settings, source, "AutoShopListOnlyCostRatio"),
        lotteryPrices = lotteryPrices(source, settings),
        defaultLotteryPrice = configured(settings, source, "LotteryAllPrice"),
        lotteryCustomMaxCount = configured(settings, source, "LotteryCustomMaxCount"),
        buyPriceMultiplier = settings.ShopBuyPriceMultiplier,
        itemOverrides = copy(admin.itemOverrides),
    }

    snapshot.recycle = {
        enabled = snapshot.features.EnableRecycle,
        sellPrices = copy(source.RecycleValues or {}),
        categoryValues = copy(source.RecycleCategoryValues or {}),
        defaultValue = type(source.RecycleCategoryValues) == "table"
            and source.RecycleCategoryValues.Normal or nil,
        divisors = copy(source.RecycleDivisors or {}),
        looseAmmoDivisor = source.LooseAmmoRecycleDivisor,
        looseShellDivisor = source.LooseShellRecycleDivisor,
        smallUnitDivisor = source.SmallUnitRecycleDivisor,
        dailyLimit = source.DailyRecycleSoftCap,
        diminishedPayout = source.DiminishedRecyclePayout,
        listingCostByFullType = copy(source.AutoShopListingCosts or {}),
        defaultListingCost = configured(settings, source, "AutoShopListOnlyMinCost"),
        listingCostRatio = configured(settings, source, "AutoShopListOnlyCostRatio"),
        buyMultiplier = source.AutoShopBuyMultiplier,
        sellPriceMultiplier = settings.RecycleSellPriceMultiplier,
        autoRecycleEnabled = snapshot.features.EnableWaistAutoRecycle,
        autoRecycleUnlockCost = source.WaistAutoRecycleUnlockCost,
        autoRecycleIntervalHours = source.WaistAutoRecycleIntervalHours,
        itemOverrides = copy(admin.itemOverrides),
    }

    snapshot.eligibility = {
        recycleBlacklist = copy(source.RecycleBlacklist or {}),
        shopBlacklist = copy(source.AutoShopBlacklist or {}),
        lotteryBlacklist = copy(source.LotteryBlacklist or {}),
        allowedModules = copy(source.AutoShopAllowedModules
            or source.RecycleDefaultAllowedModules or {}),
        allowAnyModule = source.AutoShopAllowAnyModule == true,
        allowRecycleContainers = source.AllowRecycleContainers == true,
        itemOverrides = copy(admin.itemOverrides),
    }

    snapshot.upgrades = {
        MaxActiveTaskLimit = source.MaxActiveTaskLimit,
        MaxDailyTaskLimit = source.MaxDailyTaskLimit,
        ActiveTaskUpgradeCosts = copy(source.ActiveTaskUpgradeCosts or {}),
        DailyTaskUpgradeCosts = copy(source.DailyTaskUpgradeCosts or {}),
        CarryCapacityBaseCost = source.CarryCapacityBaseCost,
        CarryCapacityCostMultiplier = source.CarryCapacityCostMultiplier,
        CarryCapacityPerLevel = source.CarryCapacityPerLevel,
        TerminalCapacityLevels = copy(source.TerminalCapacityLevels or {}),
        TerminalReductionLevels = copy(source.TerminalReductionLevels or {}),
        TerminalReliefFullType = source.TerminalReliefFullType,
        TerminalReliefUpgradeCost = configured(
            settings, source, "TerminalReliefUpgradeCost"),
        TerminalReliefPerLevel = configured(
            settings, source, "TerminalReliefPerLevel"),
        TerminalReliefMaxOffset = configured(
            settings, source, "TerminalReliefMaxOffset"),
        TerminalReliefItemMarkerKey = source.TerminalReliefItemMarkerKey,
        TerminalReliefOwnerKey = source.TerminalReliefOwnerKey,
        TerminalReliefLevelKey = source.TerminalReliefLevelKey,
        TerminalReliefOffsetKey = source.TerminalReliefOffsetKey,
        TerminalReliefVersionKey = source.TerminalReliefVersionKey,
    }

    snapshot.medical = {
        MedicalCheckInfectionCost = configured(
            settings, source, "MedicalCheckInfectionCost"),
        MedicalHealInjuriesCost = configured(
            settings, source, "MedicalHealInjuriesCost"),
        MedicalCureInfectionCost = configured(
            settings, source, "MedicalCureInfectionCost"),
    }

    snapshot.home = {
        EnableTeleport = snapshot.features.EnableTeleport,
        HomeSetCost = configured(settings, source, "HomeSetCost"),
        HomeTravelCost = configured(settings, source, "HomeTravelCost"),
        TempTeleportSlotCost = configured(settings, source, "TempTeleportSlotCost"),
        TempTeleportSetCost = configured(settings, source, "TempTeleportSetCost"),
        TempTeleportMaxSlots = source.TempTeleportMaxSlots,
        HomeSafeZoneScanIntervalHours = source.HomeSafeZoneScanIntervalHours,
        HomeSafeZoneInsufficientNoticeHours = source.HomeSafeZoneInsufficientNoticeHours,
        HomeSafeZoneLevels = copy(source.HomeSafeZoneLevels or {}),
    }

    snapshot.bank = {
        enabled = snapshot.features.EnableBank,
        loansEnabled = snapshot.features.EnableBankLoan,
        investmentsEnabled = snapshot.features.EnableBankInvestments,
        deathPenaltyRatio = source.BankDeathDemandPenaltyRatio,
        earlyWithdrawPenaltyRatio = source.BankEarlyWithdrawPenaltyRatio,
        fixedTerms = copy(source.BankFixedTerms or {}),
        investmentSettlementHours = source.BankInvestmentSettlementHours,
        investmentMinimum = configured(settings, source, "BankInvestmentMinAmount"),
        investmentProfiles = investmentProfiles(source, settings),
        loanBaseCredit = configured(settings, source, "BankLoanBaseCredit"),
        loanCreditSpendStep = configured(settings, source, "BankLoanCreditSpendStep"),
        loanCreditPerStep = configured(settings, source, "BankLoanCreditPerStep"),
        loanSingleDueHours = source.BankLoanSingleDueHours,
        loanSingleInterestRate = configured(
            settings, source, "BankLoanSingleInterestRate"),
        loanPeriodHours = source.BankLoanPeriodHours,
        loanInstallmentPlans = copy(source.BankLoanInstallmentPlans or {}),
        loanOverduePenaltyDailyRate = configured(
            settings, source, "BankLoanOverduePenaltyDailyRate"),
        loanOverduePenaltyMaxRate = configured(
            settings, source, "BankLoanOverduePenaltyMaxRate"),
        loanBankruptcyGraceHours = configured(
            settings, source, "BankLoanBankruptcyGraceHours"),
        loanFreezeHours = configured(settings, source, "BankLoanFreezeHours"),
        loanZombieDebtPerZombie = configured(
            settings, source, "BankLoanZombieDebtPerZombie"),
        loanZombieMaxCount = configured(
            settings, source, "BankLoanZombieMaxCount"),
        loanZombieMinDistance = source.BankLoanZombieMinDistance,
        loanZombieMaxDistance = source.BankLoanZombieMaxDistance,
    }

    snapshot.companion = {
        enabled = snapshot.features.EnableCompanion,
        priceMultiplier = settings.CompanionPriceMultiplier,
    }

    snapshot.autoLoader = {
        enabled = snapshot.features.EnableAutoLoaderShop,
        fullType = source.AutoLoaderFullType,
        ammoCapacity = configured(settings, source, "AutoLoaderAmmoCapacity"),
    }

    snapshot.AutoLoaderFullType = source.AutoLoaderFullType
    snapshot.AutoLoaderAmmoCapacity = configured(
        settings, source, "AutoLoaderAmmoCapacity")
    snapshot.TerminalReliefMarkerKey = source.TerminalReliefItemMarkerKey
    copyOptionalRoot(snapshot, source)
    return snapshot
end

function ConfigSnapshot.copy(value)
    return copy(value)
end

return ConfigSnapshot
