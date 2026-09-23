GodSystemProtocol = GodSystemProtocol or {}

GodSystemProtocol.Module = "GodSystem"

GodSystemProtocol.C2S = {
    EquipmentSync = "equipmentSync",
    EquipmentInspect = "equipmentInspect",
    EquipmentAction = "equipmentAction",
    EquipmentCombatAttack = "equipmentCombatAttack",
    Hello = "hello",
    Refresh = "refresh",
    SyncClientData = "syncClientData",
    SyncKills = "syncKills",
    BuyShop = "buyShop",
    ShopQuote = "shopQuote",
    ShopPreferences = "shopPreferences",
    UseLotteryTicket = "useLotteryTicket",
    Recycle = "recycle",
    ListOnlyAutoShop = "listOnlyAutoShop",
    UpgradeSystem = "upgradeSystem",
    RefreshCarryCapacity = "refreshCarryCapacity",
    MedicalService = "medicalService",
    UseMaintenanceItem = "useMaintenanceItem",
    UseMimicKey = "useMimicKey",
    UtilityGenerator = "utilityGenerator",
    UtilityGeneratorStatus = "utilityGeneratorStatus",
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
    ItemConfigRelationsGet = "itemConfigRelationsGet",
    ItemConfigRelationSet = "itemConfigRelationSet",
    ItemConfigRelationDelete = "itemConfigRelationDelete",
    ItemConfigPresetsGet = "itemConfigPresetsGet",
    ItemConfigPresetSave = "itemConfigPresetSave",
    ItemConfigPresetDelete = "itemConfigPresetDelete",
    ItemConfigPresetApply = "itemConfigPresetApply",
    ShopCatalogChunk = "shopCatalogChunk",
    ShopPagePrices = "shopPagePrices",
    UtilityGeneratorStatus = "utilityGeneratorStatus",
}

GodSystemProtocol.S2C = {
    CarryState = "carryState",
    EquipmentState = "equipmentState",
    EquipmentItem = "equipmentItem",
    EquipmentProjection = "equipmentProjection",
    EquipmentFreezeHello = "equipmentFreezeHello",
    EquipmentFreezeEffects = "equipmentFreezeEffects",
    EquipmentCombatHello = "equipmentCombatHello",
    EquipmentCombatProgress = "equipmentCombatProgress",
    EquipmentImpactApply = "equipmentImpactApply",
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
    ItemConfigRelations = "itemConfigRelations",
    ItemConfigPresets = "itemConfigPresets",
    ShopCatalogChunk = "shopCatalogChunk",
    ShopPagePrices = "shopPagePrices",
}

GodSystemProtocol.StateCommands = {
    hello = true,
    refresh = true,
    syncClientData = true,
    buyShop = true,
    shopQuote = true,
    shopPreferences = true,
    useLotteryTicket = true,
    recycle = true,
    listOnlyAutoShop = true,
    upgradeSystem = true,
    refreshCarryCapacity = true,
    medicalService = true,
    useMaintenanceItem = true,
    useMimicKey = true,
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
    itemConfigRelationSet = true,
    itemConfigRelationDelete = true,
    itemConfigPresetSave = true,
    itemConfigPresetDelete = true,
    itemConfigPresetApply = true,
}

GodSystemProtocol.KeyCommands = {
    equipmentAction = true,
    buyShop = true,
    useLotteryTicket = true,
    recycle = true,
    listOnlyAutoShop = true,
    upgradeSystem = true,
    refreshCarryCapacity = true,
    medicalService = true,
    useMaintenanceItem = true,
    useMimicKey = true,
    utilityGenerator = true,
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
    itemConfigRelationSet = true,
    itemConfigRelationDelete = true,
    itemConfigPresetSave = true,
    itemConfigPresetDelete = true,
    itemConfigPresetApply = true,
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

-- Construct only a native teleport command, never arbitrary administrator text.
function GodSystemProtocol.teleportCommand(payload)
    if type(payload)~="table" or payload.native~=true then return nil end
    local name=payload.targetUsername
    if type(name)~="string" or name=="" or #name>128 or name:find('[%c"\\]') then return nil end
    local pos=payload.pos
    if type(pos)~="table" then return nil end
    local x,y,z=tonumber(pos.x),tonumber(pos.y),tonumber(pos.z)
    if not x or not y or not z or x~=x or y~=y or z~=z or math.abs(x)>10000000 or math.abs(y)>10000000
        or z < -32 or z > 31 then return nil end
    return '/teleportto "'..name..'" '..tostring(x)..','..tostring(y)..','..tostring(z)
end
