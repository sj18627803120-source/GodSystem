require "GodSystem/Platform/Bank/State"
require "GodSystem/Platform/Bank/Clock"
require "GodSystem/Platform/Bank/Random"
require "GodSystem/Platform/Bank/Features"
require "GodSystem/Platform/Bank/Audit"
require "GodSystem/Platform/Bank/Debt"

GodSystemBankPlatformDescriptors = GodSystemBankPlatformDescriptors or {}

function GodSystemBankPlatformDescriptors.all()
    return {
        GodSystemBankStatePlatform,
        GodSystemBankClockPlatform,
        GodSystemBankRandomPlatform,
        GodSystemBankFeaturesPlatform,
        GodSystemBankAuditPlatform,
        GodSystemBankDebtPlatform,
    }
end

GodSystemBankPlatformDescriptors.externalDependencies = {
    "wallet.accounts",
    "wallet",
    "clock",
    "random",
    "operations",
}

return GodSystemBankPlatformDescriptors
