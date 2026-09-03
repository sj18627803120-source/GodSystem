require "GodSystem_Config"
require "GodSystem_ContainerCapacity"
require "GodSystem_Result"
require "GodSystem_ManualRecycle"
require "GodSystem_RuntimeConfig"
require "GodSystem_ItemConfig"
require "GodSystem_RangeFilter"
require "GodSystem_RangeRecycleDomain"
require "GodSystem_RangeRecycleScanner"
require "GodSystem_RecyclePayout"
require "GodSystem_Scheduler"
require "GodSystem_StateProjection"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_Localization"
require "GodSystem_Localization_Override"
require "GodSystem_Protocol"
require "GodSystem_EconomyPolicy"
require "GodSystem_Maintenance"
require "GodSystem_Attributes"
require "GodSystem_CarryCapacity"
require "GodSystem_TransactionOps"
require "GodSystem_ShopVariants"
require "GodSystem_B42JavaCalls"
require "GodSystem_Lottery"

if not (isServer and isServer()) then return end

GodSystemServer = GodSystemServer or {}
GodSystemServer.configuredShopKeySet = GodSystemShopVariants.getConfiguredKeySet(GodSystemConfig.ShopItems or {})

GodSystemServerRuntimeEnv = GodSystemServerRuntimeEnv or setmetatable({}, { __index = _G })
require "GodSystem_ServerRuntime_Foundation"
require "GodSystem_ServerRuntime_Bank"
require "GodSystem_ServerRuntime_EconomyTasks"
require "GodSystem_ServerRuntime_RouterConfig"
require "GodSystem_ServerRuntime_Commerce"
require "GodSystem_ServerRuntime_Lottery"
require "GodSystem_ServerRuntime_Services"
require "GodSystem_ServerRuntime_HomeGrowth"
require "GodSystem_ServerRangeRecycle"
require "GodSystem_ServerRuntime_Background"

assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Foundation"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Foundation")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Bank"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Bank")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_EconomyTasks"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_EconomyTasks")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_RouterConfig"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_RouterConfig")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Commerce"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Commerce")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Lottery"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Lottery")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Services"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Services")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_HomeGrowth"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_HomeGrowth")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRangeRecycle"], "GodSystem server runtime installer missing: GodSystem_ServerRangeRecycle")(GodSystemServerRuntimeEnv)
assert(GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Background"], "GodSystem server runtime installer missing: GodSystem_ServerRuntime_Background")(GodSystemServerRuntimeEnv)

return GodSystemServerRuntimeEnv.Commands
