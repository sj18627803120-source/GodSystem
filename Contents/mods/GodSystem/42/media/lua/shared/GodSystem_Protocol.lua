GodSystemProtocol = GodSystemProtocol or {}

GodSystemProtocol.Module = "GodSystem"

GodSystemProtocol.C2S = {
    Hello = "hello",
    Refresh = "refresh",
    SyncClientData = "syncClientData",
    SyncKills = "syncKills",
    BuyShop = "buyShop",
    UseLotteryTicket = "useLotteryTicket",
    Recycle = "recycle",
    ListOnlyAutoShop = "listOnlyAutoShop",
    UpgradeSystem = "upgradeSystem",
    RefreshCarryCapacity = "refreshCarryCapacity",
    MedicalService = "medicalService",
    UseMaintenanceItem = "useMaintenanceItem",
    Task = "task",
    RefreshTasks = "refreshTasks",
    Home = "home",
    TeleportConfirm = "teleportConfirm",
    Trait = "trait",
    Attribute = "attribute",
    Bank = "bank",
    ConsolidateCurrency = "consolidateCurrency",
    Death = "death",
    ToggleRecycleMode = "toggleRecycleMode",
    SetShopItemHidden = "setShopItemHidden",
    SetShopItemsHidden = "setShopItemsHidden",
    DeleteShopItem = "deleteShopItem",
    DebugGrant = "debugGrant",
    Diagnostics = "diagnostics",
    RangeRecycleStart = "rangeRecycleStart",
    RangeRecycleCancel = "rangeRecycleCancel",
    RangeFilterDelta = "rangeFilterDelta",
    RangeFilterSyncBegin = "rangeFilterSyncBegin",
    RangeFilterSyncChunk = "rangeFilterSyncChunk",
    RangeFilterSyncCommit = "rangeFilterSyncCommit",
    ItemConfigDetailsGet = "itemConfigDetailsGet",
    ItemConfigOverrideSet = "itemConfigOverrideSet",
    ItemConfigOverrideClear = "itemConfigOverrideClear",
}

GodSystemProtocol.S2C = {
    State = "state",
    Result = "result",
    Notify = "notify",
    Error = "error",
    Teleport = "teleport",
    RangeRecycleProgress = "rangeRecycleProgress",
    RangeFilterSnapshot = "rangeFilterSnapshot",
    RangeFilterDeltaAck = "rangeFilterDeltaAck",
    RangeFilterSyncAck = "rangeFilterSyncAck",
    LotteryResult = "lotteryResult",
    RuntimeConfig = "runtimeConfig",
    EconomySnapshot = "economySnapshot",
    EconomyDelta = "economyDelta",
    ItemConfigDetails = "itemConfigDetails",
}

GodSystemProtocol.StateCommands = {
    hello = true,
    refresh = true,
    syncClientData = true,
    buyShop = true,
    useLotteryTicket = true,
    recycle = true,
    listOnlyAutoShop = true,
    upgradeSystem = true,
    refreshCarryCapacity = true,
    medicalService = true,
    useMaintenanceItem = true,
    task = true,
    refreshTasks = true,
    home = true,
    trait = true,
    attribute = true,
    bank = true,
    consolidateCurrency = true,
    toggleRecycleMode = true,
    setShopItemHidden = true,
    setShopItemsHidden = true,
    deleteShopItem = true,
    debugGrant = true,
    diagnostics = true,
    rangeRecycleStart = true,
    rangeRecycleCancel = true,
    itemConfigOverrideSet = true,
    itemConfigOverrideClear = true,
}

GodSystemProtocol.KeyCommands = {
    buyShop = true,
    useLotteryTicket = true,
    recycle = true,
    listOnlyAutoShop = true,
    upgradeSystem = true,
    refreshCarryCapacity = true,
    medicalService = true,
    useMaintenanceItem = true,
    task = true,
    refreshTasks = true,
    home = true,
    trait = true,
    attribute = true,
    bank = true,
    consolidateCurrency = true,
    toggleRecycleMode = true,
    setShopItemHidden = true,
    setShopItemsHidden = true,
    deleteShopItem = true,
    debugGrant = true,
    itemConfigOverrideSet = true,
    itemConfigOverrideClear = true,
}

GodSystemProtocol.BackgroundSyncMs = 300000
GodSystemProtocol.KillSyncThreshold = 10
GodSystemProtocol.StateThrottleMs = 1200
GodSystemProtocol.KeyCommandTimeoutMs = 15000

function GodSystemProtocol.isStateCommand(command)
    return GodSystemProtocol.StateCommands[tostring(command or "")] == true
end

function GodSystemProtocol.isKeyCommand(command)
    return GodSystemProtocol.KeyCommands[tostring(command or "")] == true
end
