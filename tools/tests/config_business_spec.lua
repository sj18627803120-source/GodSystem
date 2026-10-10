-- Actual computed business outcomes, not just RuntimeConfig.get echoes.
local function load(e,path) local fn=assert(loadstring(readSource(path))); setfenv(fn,e); return fn() end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local e=setmetatable({}, {__index=_G}); e._G=e
e.require=function() end
e.GodSystemEquipment={Settings={}}
e.GodSystemConfig={BankInvestmentProfiles={},BankInvestmentMinAmount=1,BankLoanBaseCredit=2000,BankLoanCreditSpendStep=100,BankLoanCreditPerStep=5}
e.SandboxVars={GodSystem={}}
e.isClient=function() return false end
e.GodSystemApp={services={runtime={}}}
e.GodSystemClientRuntimeInstallers={}
load(e,"shared/GodSystem_RuntimeConfig.lua")
load(e,"client/GodSystem_ClientRuntime_BankGrowth.lua")
e.GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_BankGrowth(e)
local C=e.GodSystemRuntimeConfig
local runtime=e.GodSystemApp.services.runtime
runtime.text=function(_,fallback) return fallback end
runtime.isFeatureEnabled=function(key) return C.isFeatureEnabled(key) end
local function apply(values) e.SandboxVars.GodSystem=values; C.readSandbox() end

-- Twelve dynamically named settings must actually alter native business profiles
-- and account balances through the real settlement function.
for _,tier in ipairs({{"stable","Stable"},{"balanced","Balanced"},{"aggressive","Aggressive"}}) do
    local prefix="BankInvestment"..tier[2]
    apply({[prefix.."GainChance"]=100,[prefix.."LossChance"]=100,[prefix.."GainPercent"]=10,[prefix.."LossPercent"]=7})
    local profile=e.GodSystemConfig.BankInvestmentProfiles[tier[1]]
    eq(profile.gainChance,100); eq(profile.lossChance,0)
    e.gsRandomIndex=function() return 50 end
    local account={balance=1000}
    eq(e.gsSettleBankInvestmentAccount(account,profile,24),100); eq(account.balance,1100)
    apply({[prefix.."GainChance"]=0,[prefix.."LossChance"]=100,[prefix.."GainPercent"]=0,[prefix.."LossPercent"]=7})
    profile=e.GodSystemConfig.BankInvestmentProfiles[tier[1]]
    account={balance=1000}
    eq(e.gsSettleBankInvestmentAccount(account,profile,48),-70); eq(account.balance,930)
    apply({[prefix.."GainChance"]=10,[prefix.."LossChance"]=20,[prefix.."GainPercent"]=0,[prefix.."LossPercent"]=0})
    profile=e.GodSystemConfig.BankInvestmentProfiles[tier[1]]
    e.gsRandomIndex=function() return 50 end
    account={balance=1000}; eq(e.gsSettleBankInvestmentAccount(account,profile,72),0); eq(account.balance,1000)
end
apply({BankLoanBaseCredit=0,BankLoanCreditSpendStep=50,BankLoanCreditPerStep=7})
eq(e.gsBankLoanCredit({stats={spentPoints=125}},{loanCreditSpentOffset=25}),14)
apply({BankLoanBaseCredit=100,BankLoanCreditSpendStep=100,BankLoanCreditPerStep=0})
eq(e.gsBankLoanCredit({stats={spentPoints=125}},{}),100)
apply({BankInvestmentMinAmount=10}); eq(runtime.getBankInvestmentMinimum(),10)
apply({BankInvestmentMinAmount=100}); eq(runtime.getBankInvestmentMinimum(),100)

-- Native engine interfaces do not participate in this arithmetic regression.
e.GodSystemEquipment=nil
load(e,"shared/GodSystem_EquipmentFreeze.lua")
load(e,"shared/GodSystem_EquipmentImpact.lua")
load(e,"shared/GodSystem_EquipmentSplash.lua")
load(e,"shared/GodSystem_Equipment.lua")
local E=e.GodSystemEquipment
local record={weaponKind="melee",levels={impact=1,splash=0,freeze=0}}
local a=assert(E.config({EquipmentBaseCost=100,EquipmentCostExponent=1,EquipmentBaseChance=90,EquipmentChanceFloor=1,EquipmentChanceDecay=0.9}))
local b=assert(E.config({EquipmentBaseCost=200,EquipmentCostExponent=2,EquipmentBaseChance=60,EquipmentChanceFloor=1,EquipmentChanceDecay=0.5}))
local qa=assert(E.quote(record,"impact",0,a)); local qb=assert(E.quote(record,"impact",0,b))
eq(qa.cost,200); eq(qb.cost,800); eq(qa.baseChanceBP,8100); eq(qb.baseChanceBP,3000)
assert(qa.configToken~=qb.configToken)
eq(select(2,E.config({EquipmentBaseChance=20,EquipmentChanceFloor=30})),"EquipmentConfigInvalid")
eq(select(2,E.quote(record,"splash",0,E.config({EnableEquipmentSplash=false}))),"EquipmentSplashDisabled")

-- Nonfinite administrative/network values cannot enter settlement configuration.
apply({BankInvestmentStableGainChance=0/0,UtilityGeneratorWaterPricePer100L=math.huge,
       RecycleSellPriceMultiplier=-math.huge,EnableRecycle=false,RefreshTaskCost=0})
assert(C.get("BankInvestmentStableGainChance")==nil)
eq(C.get("UtilityGeneratorWaterPricePer100L"),20)
eq(C.get("EnableRecycle"),false); eq(C.get("RefreshTaskCost"),0)
print("PASS config business: investment settlement, loan credit, equipment quotes and nonfinite input")
