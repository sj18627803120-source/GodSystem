require "GodSystem_Config"
require "GodSystem_ContainerCapacity"
require "GodSystem_App"
require "GodSystem_Result"
require "GodSystem_ManualRecycle"
require "GodSystem_RuntimeConfig"
require "GodSystem_ItemConfig"
require "GodSystem_RangeFilter"
require "GodSystem_RangeRecycleDomain"
require "GodSystem_RangeRecycleScanner"
require "GodSystem_RecyclePayout"
require "GodSystem_Scheduler"
require "GodSystem_Prices"
require "GodSystem_ItemEligibility"
require "GodSystem_Localization"
require "GodSystem_Localization_Override"
require "GodSystem_EconomyPolicy"
require "GodSystem_CompanionConfig"
require "GodSystem_Attributes"
require "GodSystem_CarryCapacity"
require "GodSystem_ShopVariants"
require "GodSystem_TaskOrder"
require "GodSystem_B42JavaCalls"
require "GodSystem_InventoryContext"

GodSystemApp.services.runtime = GodSystemApp.services.runtime or {}
GodSystemApp.services.runtime.data = nil
GodSystemApp.services.runtime.configuredShopKeySet = GodSystemShopVariants.getConfiguredKeySet(GodSystemConfig.ShopItems or {})
GodSystemApp.services.runtime.updateTicks = 0
GodSystemApp.services.runtime.notifyQueue = GodSystemApp.services.runtime.notifyQueue or {}
GodSystemApp.services.runtime.notifyQueueActive = GodSystemApp.services.runtime.notifyQueueActive == true
GodSystemApp.services.runtime.notifyLastMs = tonumber(GodSystemApp.services.runtime.notifyLastMs) or 0

GodSystemClientRuntimeEnv = GodSystemClientRuntimeEnv or setmetatable({}, { __index = _G })
require "GodSystem_ClientRuntime_Foundation"
require "GodSystem_ClientRuntime_BankGrowth"
require "GodSystem_ClientRuntime_MedicalTraits"
require "GodSystem_ClientRuntime_Economy"
require "GodSystem_ClientRuntime_Home"
require "GodSystem_ClientRuntime_Recycle"
require "GodSystem_ClientRuntime_Tasks"
require "GodSystem_RangeRecycleService"
require "GodSystem_ItemConfigService"

assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Foundation"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_Foundation")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_BankGrowth"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_BankGrowth")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_MedicalTraits"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_MedicalTraits")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Economy"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_Economy")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Home"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_Home")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Recycle"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_Recycle")(GodSystemClientRuntimeEnv)
assert(GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_Tasks"], "GodSystem client runtime installer missing: GodSystem_ClientRuntime_Tasks")(GodSystemClientRuntimeEnv)
