"""Reproducible Lua 5.1 stock calibration; not a game-frame benchmark."""
import argparse
import json
import random
import statistics
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.test-runtime'))
from lupa.lua51 import LuaRuntime

def runtime():
    vm=LuaRuntime(unpack_returned_tuples=True)
    lua=ROOT/'Contents/mods/GodSystem/42/media/lua'
    vm.globals().readStockSource=lambda name:(lua/'shared'/f'{name}.lua').read_text(encoding='utf8')
    vm.execute('''local loaded={}
function require(name)
 if loaded[name] then return loaded[name] end
 local m=assert(loadstring(readStockSource(name)))(); loaded[name]=m; return m
end
next=nil
require "GodSystem_StockTrading"
require "GodSystem_StockActivity"
''')
    return vm

def numeric(vm):
    rng=random.Random(323)
    fn=vm.eval('GodSystemStockDefinitions.mulDiv')
    maximum=2**53-1
    for _ in range(10000):
        a=rng.randrange(maximum+1); b=rng.randrange(maximum+1); d=rng.randrange(1,maximum+1)
        expected,remainder=divmod(a*b,d)
        actual=fn(a,b,d)
        if expected>maximum:
            assert actual is None,(a,b,d,actual)
        else:
            assert actual==(expected,remainder),(a,b,d,actual,(expected,remainder))
    return 10000

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--seeds',type=int,default=100)
    parser.add_argument('--days',type=int,default=180)
    parser.add_argument('--output',default='.test-runtime/stocks-simulation.json')
    args=parser.parse_args(); vm=runtime()
    result={'vm':'Lua 5.1 simulation; not in-game timings','numeric_cases':numeric(vm),'days':args.days,'seeds':args.seeds}
    simulate=vm.eval('''function(seed,hours,scenario)
local D,M,T=GodSystemStockDefinitions,GodSystemStockMarket,GodSystemStockTrading
local m=M.create(seed); local c=D.config({StockNewsMaxPerDay=scenario=="silent" and 0 or 3})
local initial=0; for i=1,#D.rows do initial=initial+D.rows[i].initial end
local peak,drawdown,minimum,maximum=initial,0,math.huge,0
local favorableDown,unfavorableUp=0,0
local investor={current=1000000}; local newsTrader={current=1000000}; local fees=0; local tradeNo=0
for h=1,hours do
 if scenario=="single" and h==1 then M.addActivity(m,"tool",30000) end
 if scenario=="sustained" then M.addActivity(m,"tool",30000) end
 local old={}; for i=1,#D.rows do local id=D.rows[i].id; old[id]=m.stocks[id].cents end
 m.hour=h; while m.processed<h do M.step(m,c) end
 local value=0
 for i=1,#D.rows do
  local id=D.rows[i].id; local p=m.stocks[id].cents
  assert(D.integer(p) and p>0 and not m.stocks[id].suspended)
  minimum=math.min(minimum,p/100); maximum=math.max(maximum,p/100); value=value+p/100
 end
 peak=math.max(peak,value); drawdown=math.max(drawdown,(peak-value)/peak)
 local news=m.news.history[#m.news.history]
 if news and news.publishedHour==h and news.id and news.delta then
  local change=m.stocks[news.id].cents-old[news.id]
  if news.delta>0 and change<0 then favorableDown=favorableDown+1 end
  if news.delta<0 and change>0 then unfavorableUp=unfavorableUp+1 end
 end
 -- Two comparable T+0 strategies, trading every 24h with real fees and net flow.
 if h%24==0 then
  for strategy=1,2 do
   local bank=strategy==1 and investor or newsTrader
   local chosen=strategy==1 and D.rows[(math.floor(h/24)+seed)%24+1].id or (news and news.id or "tool_01")
   local a=T.account(bank)
   for i=1,#D.rows do
    local id=D.rows[i].id; local p=a.positions[id]
    if p then
     tradeNo=tradeNo+1
     local r=T.trade(m,bank,"strategy"..strategy,{opId="gs-1-1-"..tradeNo,stockId=id,side="sell",quantity=p.quantity,quoteVersion=m.quoteVersion,tradeConfigVersion=m.tradeConfigVersion,tradeSequence=a.nextSequence},c)
     if r.ok then fees=fees+r.fee end
    end
   end
   local qty=D.maxBuy(m.stocks[chosen].cents,math.floor(bank.current/10),c.fee)
   if qty>0 then
    tradeNo=tradeNo+1
    local r=T.trade(m,bank,"strategy"..strategy,{opId="gs-1-1-"..tradeNo,stockId=chosen,side="buy",quantity=qty,quoteVersion=m.quoteVersion,tradeConfigVersion=m.tradeConfigVersion,tradeSequence=a.nextSequence},c)
    if r.ok then fees=fees+r.fee end
   end
  end
 end
end
local basket=0; for i=1,#D.rows do basket=basket+m.stocks[D.rows[i].id].cents/100 end
local function wealth(bank)
 local total=bank.current; local a=T.account(bank)
 for id,p in pairs(a.positions) do local q=D.quote(m.stocks[id].cents,p.quantity,"sell",c.fee); total=total+(q and q.total or 0) end
 return total
end
return {basketReturn=basket/initial-1,maxDrawdown=drawdown,minPrice=minimum,maxPrice=maximum,
 randomReturn=wealth(investor)/1000000-1,newsReturn=wealth(newsTrader)/1000000-1,fees=fees,
 favorableDown=favorableDown,unfavorableUp=unfavorableUp,toolOffset=m.sectors.tool.short+m.sectors.tool.long,
 history=#m.stocks.tool_01.history,news=#m.news.history}
end''')
    start=time.perf_counter(); scenarios={}
    for scenario in ('baseline','single','sustained'):
        rows=[]; scenario_start=time.perf_counter()
        for seed in range(1,args.seeds+1):
            r=dict(simulate(seed,args.days*24,scenario)); rows.append(r)
        scenarios[scenario]={
            'elapsed_seconds':time.perf_counter()-scenario_start,
            'mean_basket_return':statistics.mean(r['basketReturn'] for r in rows),
            'worst_basket_drawdown':max(r['maxDrawdown'] for r in rows),
            'price_range':[min(r['minPrice'] for r in rows),max(r['maxPrice'] for r in rows)],
            'mean_random_strategy_return':statistics.mean(r['randomReturn'] for r in rows),
            'mean_news_strategy_return':statistics.mean(r['newsReturn'] for r in rows),
            'mean_fees':statistics.mean(r['fees'] for r in rows),
            'positive_news_down_cases':sum(r['favorableDown'] for r in rows),
            'negative_news_up_cases':sum(r['unfavorableUp'] for r in rows),
            'max_history':max(r['history'] for r in rows),'max_news':max(r['news'] for r in rows),
            'mean_final_tool_offset':statistics.mean(r['toolOffset'] for r in rows),
            'seeds':rows,
        }
        print(f'{scenario}: {args.seeds} seeds x {args.days} days completed in {scenarios[scenario]["elapsed_seconds"]:.2f}s',flush=True)
    result['scenarios']=scenarios; result['elapsed_seconds']=time.perf_counter()-start
    out=ROOT/args.output; out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
    print('Simulation report: '+str(out),flush=True)

if __name__=='__main__': main()
