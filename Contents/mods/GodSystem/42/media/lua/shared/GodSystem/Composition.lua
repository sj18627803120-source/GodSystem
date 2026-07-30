require "GodSystem/Bootstrap"
require "GodSystem/Services/Clock"
require "GodSystem/Services/Random"
require "GodSystem/Services/Operations"
require "GodSystem/Services/Notifications"
require "GodSystem/Platform/InventoryQuery"
require "GodSystem/Platform/InventoryMutation"
require "GodSystem/Platform/WalletAccounts"
require "GodSystem/Platform/WalletFunds"
require "GodSystem/Platform/AutoLoader/AmmoCatalog"
require "GodSystem/Platform/AutoLoader/InventoryQuery"
require "GodSystem/Platform/AutoLoader/InventoryMutation"
require "GodSystem/Platform/AutoLoader/Store"
require "GodSystem/Platform/AutoLoader/Sessions"
require "GodSystem/Platform/AutoLoader/Operations"
require "GodSystem/Platform/AutoLoader/Synchronization"
require "GodSystem/Platform/Commerce/ActorIdentity"
require "GodSystem/Platform/Commerce/ShopIdentity"
require "GodSystem/Platform/Commerce/States"
require "GodSystem/Platform/Commerce/ConfigSnapshots"
require "GodSystem/Platform/Commerce/Inventory"
require "GodSystem/Platform/Commerce/Wallet"
require "GodSystem/Platform/Commerce/ItemEligibility"
require "GodSystem/Platform/Commerce/ShopListings"
require "GodSystem/Platform/Progression/UpgradesConfig"
require "GodSystem/Platform/Progression/UpgradesState"
require "GodSystem/Platform/Progression/UpgradesAbilities"
require "GodSystem/Platform/Progression/UpgradesTasks"
require "GodSystem/Platform/Progression/UpgradesWallet"
require "GodSystem/Platform/Progression/MedicalConfig"
require "GodSystem/Platform/Progression/MedicalState"
require "GodSystem/Platform/Progression/MedicalBody"
require "GodSystem/Platform/Progression/MedicalWallet"
require "GodSystem/Platform/Progression/HomeConfig"
require "GodSystem/Platform/Progression/HomeState"
require "GodSystem/Platform/Progression/HomePosition"
require "GodSystem/Platform/Progression/HomeWorld"
require "GodSystem/Platform/Progression/HomeWallet"
require "GodSystem/Platform/Companion/Query"
require "GodSystem/Platform/Companion/Mutation"
require "GodSystem/Platform/Companion/Events"
require "GodSystem/Platform/Companion/Visuals"
require "GodSystem/Platform/Bank/Descriptors"
require "GodSystem/Features/Wallet/Module"
require "GodSystem/Features/Wallet/PublicPort"
require "GodSystem/Features/Maintenance/Rules"
require "GodSystem/Features/Maintenance/Module"
require "GodSystem/Features/AutoLoader/Module"
require "GodSystem/Features/Tasks/Module"
require "GodSystem/Features/Shop/Module"
require "GodSystem/Features/Recycle/Module"
require "GodSystem/Features/Upgrades/Module"
require "GodSystem/Features/Upgrades/PublicPort"
require "GodSystem/Features/Medical/Module"
require "GodSystem/Features/Home/Module"
require "GodSystem/Features/Companion/Module"
require "GodSystem/Features/Bank/Module"

GodSystemComposition = GodSystemComposition or {}

local Composition = GodSystemComposition

local BASE_DESCRIPTORS = {
    GodSystemClockService,
    GodSystemRandomService,
    GodSystemOperationsService,
    GodSystemNotificationsService,
    GodSystemInventoryQueryPlatform,
    GodSystemInventoryMutationPlatform,
    GodSystemWalletAccountsPlatform,
    GodSystemWalletFundsPlatform,
    GodSystemAutoLoaderAmmoCatalogPlatform,
    GodSystemAutoLoaderInventoryQueryPlatform,
    GodSystemAutoLoaderInventoryMutationPlatform,
    GodSystemAutoLoaderStorePlatform,
    GodSystemAutoLoaderSessionsPlatform,
    GodSystemAutoLoaderOperationsPlatform,
    GodSystemAutoLoaderSynchronizationPlatform,
    GodSystemCommerceActorIdentityPlatform,
    GodSystemShopIdentityPlatform,
    GodSystemTasksStatePlatform,
    GodSystemShopStatePlatform,
    GodSystemRecycleStatePlatform,
    GodSystemTasksConfigPlatform,
    GodSystemShopConfigPlatform,
    GodSystemRecycleConfigPlatform,
    GodSystemCommerceInventoryPlatform,
    GodSystemTasksInventoryPlatform,
    GodSystemShopInventoryPlatform,
    GodSystemRecycleInventoryPlatform,
    GodSystemCommerceWalletPlatform,
    GodSystemTasksWalletPlatform,
    GodSystemShopWalletPlatform,
    GodSystemRecycleWalletPlatform,
    GodSystemItemEligibilityPlatform,
    GodSystemShopListingsPlatform,
    GodSystemUpgradesConfigPlatform,
    GodSystemUpgradesStatePlatform,
    GodSystemUpgradesAbilitiesPlatform,
    GodSystemUpgradesTasksPlatform,
    GodSystemUpgradesWalletPlatform,
    GodSystemMedicalConfigPlatform,
    GodSystemMedicalStatePlatform,
    GodSystemMedicalBodyPlatform,
    GodSystemMedicalWalletPlatform,
    GodSystemHomeConfigPlatform,
    GodSystemHomeStatePlatform,
    GodSystemHomePositionPlatform,
    GodSystemHomeWorldPlatform,
    GodSystemHomeWalletPlatform,
    GodSystemCompanionQueryPlatform,
    GodSystemCompanionMutationPlatform,
    GodSystemCompanionEventsPlatform,
    GodSystemCompanionVisualsPlatform,
    GodSystemBankStatePlatform,
    GodSystemBankClockPlatform,
    GodSystemBankRandomPlatform,
    GodSystemBankFeaturesPlatform,
    GodSystemBankAuditPlatform,
    GodSystemBankDebtPlatform,
    GodSystemWalletFeatureModule,
    GodSystemWalletPublicPort,
    GodSystemMaintenanceRulesFeature,
    GodSystemMaintenanceFeatureModule,
    GodSystemAutoLoaderFeatureModule,
    GodSystemTasksFeatureModule,
    GodSystemShopFeatureModule,
    GodSystemRecycleFeatureModule,
    GodSystemUpgradesFeatureModule,
    GodSystemUpgradesPublicPort,
    GodSystemMedicalFeatureModule,
    GodSystemHomeFeatureModule,
    GodSystemCompanionFeatureModule,
    GodSystemBankFeatureModule,
}

function Composition.create(options)
    options = options or {}
    local runtime = GodSystemBootstrap.create(options)
    for index = 1, #BASE_DESCRIPTORS do
        local ok, code = runtime:register(BASE_DESCRIPTORS[index])
        assert(ok, "composition registration failed: " .. tostring(code))
    end
    for index = 1, #(options.descriptors or {}) do
        local ok, code = runtime:register(options.descriptors[index])
        assert(ok, "feature registration failed: " .. tostring(code))
    end
    if options.start ~= false then
        runtime.startResult = runtime:start()
    end
    return runtime
end

return Composition
