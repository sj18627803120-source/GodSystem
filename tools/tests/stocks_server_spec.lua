local loaded={}
function require(key)
    if loaded[key] then return loaded[key] end
    local folder=key=="GodSystem_ServerRuntime_Stocks" and "server/" or "shared/"
    local value=assert(loadstring(readSource(folder..key..".lua")))()
    loaded[key]=value or true; return value
end
isClient=function() return false end
local events={}
Events={OnTick={Add=function(f) events[f]=true end,Remove=function(f) events[f]=nil end}}
local ms=1000
getTimestampMs=function() return ms end
GodSystemScheduler={nowMs=function() return ms end,due=function() return true end}
GodSystemRuntimeConfig={Current={}}
local root={}; ModData={getOrCreate=function() return root end}
local S=require "GodSystem_StockService"
require "GodSystem_ServerRuntime_Stocks"
local p1,p2={},{}; local data1,data2={bank={current=10000}},{bank={current=20000}}
local users={[p1]="one",[p2]="two"}; local data={[p1]=data1,[p2]=data2}; local sent={}; local bankPushes=0
local env=setmetatable({Commands={},GodSystemServer={},MODULE="GodSystem",applyRuntimeStores=function() end,
    userKey=function(p) return users[p] end,playerData=function(p) return data[p] end,
    nowHours=function() return ms/1000 end,sendState=function() bankPushes=bankPushes+1 end,sendServerCommand=function(p,_,command,args)
        sent[#sent+1]={player=p,command=command,args=GodSystemStockDefinitions.copy(args)}
    end},{__index=_G})
GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Stocks(env)
env.Commands.stockOpen(nil,nil,p1,{generation=1})
local init=sent[#sent].args
assert(init.account.balance==10000 and init.token and init.pushSequence==1)
assert(init.rng==nil and init.stocks==nil and init.activityCursors==nil)
env.Commands.stockOpen(nil,nil,p2,{generation=1})
assert(sent[#sent].args.account.balance==20000)
local token2=sent[#sent].args.token
local args={opId="gs-1-2-3",stockId="tool_01",side="buy",quantity=10,quoteVersion=init.quoteVersion,
    tradeConfigVersion=init.tradeConfigVersion,tradeSequence=init.account.nextSequence,token=init.token,generation=1}
env.Commands.stockTrade(nil,nil,p1,args)
assert(sent[#sent].args.ok and sent[#sent].player==p1)
local balance=data1.bank.current
assert(balance<10000 and data2.bank.current==20000)
env.Commands.stockTrade(nil,nil,p1,args); assert(data1.bank.current==balance)
assert(bankPushes==1,"duplicate stock receipt repeated bank sync")
local forged=GodSystemStockDefinitions.copy(args); forged.token=token2; forged.opId="gs-1-2-4"
local count=#sent
env.Commands.stockTrade(nil,nil,p1,forged)
assert(#sent==count and data1.bank.current==balance,"another account's token must be rejected")
-- Current bank balance is refreshed without publishing other accounts or receipts.
env.Commands.stockDetail(nil,nil,p1,{token=init.token,generation=1,selected="security_02"})
assert(sent[#sent].args.selected=="security_02" and sent[#sent].args.account.ledger==nil)
local list={size=function() return 2 end,get=function(_,i) return i==0 and p1 or p2 end}
env.GodSystemServer.stockTick(list)
env.GodSystemServer.stockPlayer(p1,data1); env.GodSystemServer.stockPlayer(p2,data2)
env.GodSystemServer.stockEnd({[p1]=true,[p2]=true})
local m=S.market
local before=m.hour
ms=2000; env.GodSystemServer.stockTick(list)
assert(m.hour>before)
for f in pairs(events) do f() end
while m.processed<math.floor(m.hour) do GodSystemStockMarket.step(m,S.config()) end
env.Commands.stockClose(nil,nil,p1,{token=init.token,generation=1})
env.GodSystemServer.stockEnd({[p2]=true})
count=#sent; env.GodSystemServer.stockPlayer(p1,data1)
assert(#sent==count,"closed stock window must not receive market snapshots")
-- Normal state projection never carries personal stock receipts or history.
require "GodSystem_StateProjection"
local projected=GodSystemStateProjection.build and GodSystemStateProjection.build(data1)
-- Projection's existing fixture covers its adapter options; inspect the copy path here.
assert(type(GodSystemStateProjection)=="table")
assert(projected.bank.current==data1.bank.current and projected.bank.stocks==nil)
local revision=GodSystemStateProjection.updateUIRevisions(data1).walletBank
data1.bank.stocks.fees=data1.bank.stocks.fees+1
assert(GodSystemStateProjection.updateUIRevisions(data1).walletBank==revision,"private stock fields changed ordinary wallet signature")
S.reset(); assert(S.market==nil and S.worker==nil)
print("Stock server adapter passed: authority, account isolation, sessions, receipts, subscriptions and worker cleanup")
