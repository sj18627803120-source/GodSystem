require "GodSystem/Bootstrap"
require "GodSystem/Services/Clock"
require "GodSystem/Services/Random"
require "GodSystem/Services/Operations"
require "GodSystem/Services/Notifications"
require "GodSystem/Platform/InventoryQuery"
require "GodSystem/Platform/InventoryMutation"
require "GodSystem/Platform/WalletFunds"
require "GodSystem/Platform/AutoLoader/AmmoCatalog"
require "GodSystem/Platform/AutoLoader/InventoryQuery"
require "GodSystem/Platform/AutoLoader/InventoryMutation"
require "GodSystem/Platform/AutoLoader/Store"
require "GodSystem/Platform/AutoLoader/Sessions"
require "GodSystem/Platform/AutoLoader/Operations"
require "GodSystem/Platform/AutoLoader/Synchronization"
require "GodSystem/Features/Wallet/Module"
require "GodSystem/Features/Wallet/PublicPort"
require "GodSystem/Features/Maintenance/Rules"
require "GodSystem/Features/Maintenance/Module"
require "GodSystem/Features/AutoLoader/Module"

GodSystemComposition = GodSystemComposition or {}

local Composition = GodSystemComposition

local BASE_DESCRIPTORS = {
    GodSystemClockService,
    GodSystemRandomService,
    GodSystemOperationsService,
    GodSystemNotificationsService,
    GodSystemInventoryQueryPlatform,
    GodSystemInventoryMutationPlatform,
    GodSystemWalletFundsPlatform,
    GodSystemAutoLoaderAmmoCatalogPlatform,
    GodSystemAutoLoaderInventoryQueryPlatform,
    GodSystemAutoLoaderInventoryMutationPlatform,
    GodSystemAutoLoaderStorePlatform,
    GodSystemAutoLoaderSessionsPlatform,
    GodSystemAutoLoaderOperationsPlatform,
    GodSystemAutoLoaderSynchronizationPlatform,
    GodSystemWalletFeatureModule,
    GodSystemWalletPublicPort,
    GodSystemMaintenanceRulesFeature,
    GodSystemMaintenanceFeatureModule,
    GodSystemAutoLoaderFeatureModule,
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
