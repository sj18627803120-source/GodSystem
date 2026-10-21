"""Bounded stock work/MP adapter benchmark in Lua 5.1, not game network timings."""
from pathlib import Path
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/tests'))
from run_stock_simulation import runtime

def main():
    vm=runtime()
    vm.globals().readServerStock=lambda:(ROOT/'Contents/mods/GodSystem/42/media/lua/server/GodSystem_ServerRuntime_Stocks.lua').read_text(encoding='utf8')
    vm.execute('require "GodSystem_StockService"; assert(loadstring(readServerStock()))()')
    benchmark=vm.eval('''function(count,subscribed)
local S,M,D=GodSystemStockService,GodSystemStockMarket,GodSystemStockDefinitions
S.reset()
local root={}; ModData={getOrCreate=function() return root end}
isClient=function() return false end
local callbacks={}; Events={OnTick={Add=function(f) callbacks[f]=true end,Remove=function(f) callbacks[f]=nil end}}
local ms,world=1000,100
getTimestampMs=function() return ms end
GodSystemScheduler={nowMs=function() return os.clock()*1000 end,due=function() return true end}
GodSystemRuntimeConfig={Current={}}
local players,data={},{}
for i=1,count do players[i]={id=i}; data[players[i]]={bank={current=100000}} end
local packets,largest=0,0
local function fields(t)
 local n=0; for k,v in pairs(t) do n=n+#tostring(k)+(type(v)=="table" and fields(v) or #tostring(v)) end; return n
end
local env=setmetatable({Commands={},GodSystemServer={},MODULE="GodSystem",applyRuntimeStores=function() end,
 playerData=function(p) return data[p] end,userKey=function(p) return tostring(p.id) end,nowHours=function() return world end,
 sendServerCommand=function(_,_,_,args) packets=packets+1; largest=math.max(largest,fields(args)) end},{__index=_G})
GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Stocks(env)
local list={size=function() return #players end,get=function(_,i) return players[i+1] end}
env.GodSystemServer.stockTick(list)
if subscribed then for i=1,count do env.Commands.stockOpen(nil,nil,players[i],{generation=1}) end end
packets=0
local active={}; for i=1,count do active[players[i]]=true end
local started=os.clock()
for tick=1,60 do
 ms=ms+1000
 env.GodSystemServer.stockTick(list)
 for i=1,count do env.GodSystemServer.stockPlayer(players[i],data[players[i]]) end
 env.GodSystemServer.stockEnd(active)
end
local stableMs=(os.clock()-started)*1000; local stablePackets=packets
world=world+1; env.GodSystemServer.stockTick(list)
local maxStep,steps=0,0
while S.market.processed<math.floor(S.market.hour) do
 local t=os.clock(); M.step(S.market,S.config(),function() return os.clock()*1000 end)
 maxStep=math.max(maxStep,(os.clock()-t)*1000); steps=steps+1
end
for i=1,count do env.GodSystemServer.stockPlayer(players[i],data[players[i]]) end
env.GodSystemServer.stockEnd(active)
local changedPackets=packets-stablePackets
local bytes=fields(S.market)
S.reset()
return {players=count,subscribed=subscribed,stable60TicksMs=stableMs,stableMessages=stablePackets,
 settlementSteps=steps,maxSettlementStepMs=maxStep,settlementMessages=changedPackets,
 largestPayloadFieldBytes=largest,marketFieldBytes=bytes}
end''')
    cases=[dict(benchmark(n,subscribed)) for n in (1,20,100) for subscribed in (False,True)]
    for r in cases:
        assert r['stableMessages']==0,r
        assert r['settlementMessages']==(r['players'] if r['subscribed'] else 0),r
    out=ROOT/'.test-runtime/stocks-performance.json'
    out.write_text(json.dumps({'kind':'Lua simulation; field bytes are not wire bytes','cases':cases},indent=2)+'\n',encoding='utf8')
    print(json.dumps(cases,indent=2))

if __name__=='__main__': main()
