GodSystemConfig = { Version = "42.20_3.19" }
local lines = {}
print = function(line) lines[#lines + 1] = line end
getTimestampMs = function() return 1000 end
assert(loadstring(readSource("shared/GodSystem_Diagnostics.lua"), "@Diagnostics"))()
assert(GodSystemDiagnostics.issue("client", "recycle", "timeout", "CommandTimeout", "op-1"))
assert(not GodSystemDiagnostics.issue("client", "recycle", "timeout", "CommandTimeout", "op-1"))
assert(#lines == 1 and lines[1]:find("op=op%-1") and lines[1]:find("feature=recycle"))
assert(GodSystemDiagnostics.isUnexpected("TransactionOperationUnknown"))
assert(not GodSystemDiagnostics.isUnexpected("CurrencyNotEnough"))
getTimestampMs = function() return 32000 end
assert(GodSystemDiagnostics.issue("client", "recycle", "result", "TransactionOperationUnknown", "op-1"))
assert(not GodSystemDiagnostics.issue("client", "recycle", "result", "TransactionOperationUnknown", "op-1"))
assert(#lines == 2, "a later unknown result must be visible, identical retries suppressed")
assert(GodSystemDiagnostics.issue("client", "recycle", "timeout", "CommandTimeout", nil))
local context = { source="worldItem", itemType="Base.Bullets9mm", step="worldTransmit",
    restored="yes", error="native error\nsecond line", payload="must not leak" }
assert(GodSystemDiagnostics.issue("sp","RecycleSelectedItems","remove","deleteFailed",nil,context))
local detail=lines[#lines]
assert(detail:find("step=worldTransmit",1,true) and detail:find("itemType=Base.Bullets9mm",1,true))
assert(detail:find("restored=yes",1,true) and detail:find("native error second line",1,true))
assert(not detail:find("\n",1,true) and not detail:find("must not leak",1,true))
assert(not GodSystemDiagnostics.issue("sp","RecycleSelectedItems","remove","deleteFailed",nil,context))
context.step="worldVerify"
assert(GodSystemDiagnostics.issue("sp","RecycleSelectedItems","remove","deleteFailed",nil,context))
context.error=string.rep("x",254).."\228\184\173".."overflow"
GodSystemDiagnostics.issue("sp","RecycleSelectedItems","remove","unknown",nil,context)
local expected = string.rep("x",254)
if #"\228\184\173" == 1 then expected = expected .. "\228\184\173o" end
assert(lines[#lines]:match("error=(.*)$")==expected,"exception truncation must preserve Lua UTF-8 and Kahlua UTF-16 boundaries")
