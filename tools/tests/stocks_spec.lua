local loaded={}
function require(key)
    if loaded[key] then return loaded[key] end
    local value=assert(loadstring(readSource("shared/"..key..".lua")))()
    loaded[key]=value; return value
end
local D=require "GodSystem_StockDefinitions"
local M=require "GodSystem_StockMarket"
local T=require "GodSystem_StockTrading"
local A=require "GodSystem_StockActivity"
local passed=0
local function check(condition,message) assert(condition,message); passed=passed+1 end
local function eq(a,b,message) check(a==b,(message or "equality")..": "..tostring(a).." / "..tostring(b)) end
local function request(m,bank,seq,side,quantity,id)
    local a=T.account(bank)
    return {opId="gs-100-1-"..seq,stockId=id or "tool_01",side=side or "buy",quantity=quantity or 1,
        quoteVersion=m.quoteVersion,tradeConfigVersion=m.tradeConfigVersion,tradeSequence=a.nextSequence}
end
local c=D.config({})
local function hours(m,n,config)
    config=config or c
    for _=1,n do m.hour=m.hour+1; while m.processed<math.floor(m.hour) do M.step(m,config) end end
end
eq(#D.rows,24)
eq(D.quote(10000,10,"buy",50).total,1005)
eq(D.quote(10000,10,"sell",50).total,995)
eq(D.quote(101,3,"buy",0).total,4)
eq(D.quote(101,3,"sell",0).total,3)
eq(D.maxBuy(10000,1000,50),9)
eq(D.quote(1,1,"sell",50),nil)
eq(D.quote(D.MAX,D.MAX,"buy",50),nil)
eq(D.mulDiv(D.MAX,10000,10000),D.MAX)
eq(D.mulDiv(9007199254740991,3,7),3860228252031853)
eq(D.config({StockTradeFeePercent=0.005}).fee,1)
eq(D.config({StockTrendMinDays=20,StockTrendMaxDays=1}).maxDays,20)

-- Python big-integer oracle, executed unchanged in both Lua 5.1 and native Kahlua.
local oracle={
{2010636221335887,950172642255283,8666103874944663,220451030660314,5901261643036839},
{8002605963799304,5675146294536728,4201651922818107,-1,-1},
{6363038799189849,8776599048024585,7283229585445749,7667730312814963,942054522495378},
{6529955472366490,2053635502415131,4062528610161974,3300936356164424,2534802936947214},
{1279445082470866,7631463394259496,3659404893798526,2668203873364363,3331389753514598},
{2694740614901916,6914265035154942,8985739254912586,2073524535250884,1695134193442848},
{3588639001043753,8831436218376229,4356817194197072,7274309441008354,1994572769807949},
{7931104490720819,4605381146858272,3589373786363254,-1,-1},
{2288042287048050,191589944554950,4916049176057453,89170364090311,405944698709617},
{6231736688736989,5758383400401014,749744834922317,-1,-1},
{7961604729831422,8730193609569263,7489664206936777,-1,-1},
{2368250843827546,1711599990598866,8238711063237870,492006345521471,7024021301856066},
{3212705323175630,4924585023961118,2945650361178120,5371051747833075,1132575302835340},
{8574067561961595,4289521940337631,5123618492083440,7178257120782615,4694632273885845},
{6836029065500322,60731258857917,4226984217309898,98216749671556,182130547887986},
{8430187294188458,6505450410671602,2751415217922520,-1,-1},
{2381232815112734,335660125813424,1010445924530095,791021950712997,611494576396501},
{8478174964125801,2702095358527658,2571785797830013,8907754774398175,2304069422477783},
{4205339057208717,2667377780964039,8638830752261105,1298465994334108,5491140871058623},
{4275657876008276,4178114223326044,5042549161007086,3542689702257341,2852963693821818},
{1638339849847844,4605977342311518,5117168161150294,1474674270956324,1075616274907936},
{2511846938169848,3209202216794469,7053775724875297,1142795727654863,1959129098351401},
{2635274318478413,2074942072919719,2653435791001750,2060740107463219,212549093892697},
{2241317336047815,3607206477831401,3273886132416186,2469509960476451,810316860202929},
{7123984566057014,546540858661430,2774170813904331,1403499965578488,622362799138492},
{3183964711735202,8649324802576754,2882930764184957,-1,-1},
{2331575623701067,4785633901671880,3145720641762000,3547062380862167,713018621641960},
{7478301618962569,4000493589251517,4166687739262852,7180019132041254,630886735770765},
{1395499060637146,3896541845176755,1726879798424678,3148812378046165,793878729481360},
{8453288826919159,820971215835803,2832119755303470,2450428444295569,1288557727525247},
{4597869023078146,5340583827584769,1417666578173204,-1,-1},
{6663677730224808,4935042289638054,995745106839665,-1,-1},
{2439846925655317,646122816665689,6976516134959417,225963896211458,3509430353918427},
{4035460085850479,476568196280732,1161249037091578,1656123598684186,737037678285120},
{5031586103799456,1276241733870477,8505532113079018,754981591728658,2649964717962668},
{7614026699502693,3806515784375242,664462054935843,-1,-1},
{4226978883805217,6679675017585867,2122361508500644,-1,-1},
{7594456251855505,4754011789479564,1796779072329603,-1,-1},
{6474444008292319,1328376679843552,3551214411352100,2421847694714031,1382102051961988},
{7188329331230073,1768525540571649,7155040508112791,1776753604945530,6891048108726147},
{3103482139484504,4620839771106728,8903664705049787,1610650689812696,61203101447160},
{4982121901213961,2897045121828687,2219240164751462,6503771957409667,1453161203516053},
{4581048988012398,3098835780056281,4839216045134992,2933516169114833,1508298131235502},
{6292461387657788,8155580402163044,8738009562901150,5873039438230021,7226738266962522},
{1681729586399309,8689652492192697,1215314615311703,-1,-1},
{17301281596110,6188265922515889,5784115143909033,18510165972370,3833321484173580},
{7809333890742457,5650215712734513,8336202347741764,5293108206210501,3623257925254677},
{3766851613996356,31351775134137,8364574291066431,14118768111343,6571911311577939}
}
for _,v in ipairs(oracle) do
 local q,r=D.mulDiv(v[1],v[2],v[3])
 if v[4]<0 then eq(q,nil) else eq(q,v[4]); eq(r,v[5]) end
end
local m=M.create(123); local bank={current=10000}
m.stocks.tool_01.cents=10000
local r=request(m,bank,1,"buy",10)
local result=T.trade(m,bank,"a",r,c)
check(result.ok); eq(bank.current,8995); eq(bank.stocks.positions.tool_01.cost,1005)
eq(T.trade(m,bank,"a",r,c).total,1005); eq(bank.current,8995)
local changed=D.copy(r); changed.quantity=11
eq(T.trade(m,bank,"a",changed,c).code,"StockMismatch")
local sell=request(m,bank,2,"sell",3)
check(T.trade(m,bank,"a",sell,c).ok)
eq(bank.stocks.positions.tool_01.cost,704)
eq(bank.stocks.realized,-3)
check(T.trade(m,bank,"a",request(m,bank,3,"sell",7),c).ok)
eq(bank.stocks.positions.tool_01,nil)
eq(bank.stocks.realized,-11)
eq(m.inputs[1].orders.tool_01,0)
local balance=bank.current
local fail=request(m,bank,4,"buy",1)
local beforeSeq=bank.stocks.nextSequence
local rolled=T.trade(m,bank,"a",fail,c,{stage=function(stage) if stage=="mutated" then error("injected trade failure") end end})
eq(rolled.code,"StockRolledBack"); eq(bank.current,balance); eq(bank.stocks.nextSequence,beforeSeq+1)
eq(bank.stocks.positions.tool_01,nil)
eq(T.trade(m,bank,"a",fail,c).code,"StockRolledBack")
local stale=request(m,bank,5)
stale.quoteVersion=0
local beforeSeq2=bank.stocks.nextSequence
eq(T.trade(m,bank,"a",stale,c).code,"StockStale"); eq(bank.stocks.nextSequence,beforeSeq2)
local unknown=request(m,bank,6)
local unresolved=T.trade(m,bank,"a",unknown,c,{stage=function(stage) if stage=="mutated" or stage=="rollback" then error("injected unresolved") end end})
eq(unresolved.code,"StockUnknown"); check(bank.stocks.unknown)
bank.current=bank.current+777 -- unrelated deposit after the unresolved operation
local preserved=bank.current
eq(T.recover(m,bank,"a"),false); eq(bank.current,preserved)
eq(T.trade(m,bank,"a",request(m,bank,7),c).code,"StockUnknown")
local other={current=1000}
check(T.trade(m,other,"b",request(m,other,8),c).ok,"other account must remain usable")
-- High water prevents replay even after receipt eviction.
local replayMarket=M.create(5); local replayBank={current=100000}
local oldest=request(replayMarket,replayBank,1)
check(T.trade(replayMarket,replayBank,"a",oldest,c).ok)
for i=2,70 do check(T.trade(replayMarket,replayBank,"a",request(replayMarket,replayBank,i),c).ok) end
eq(#replayBank.stocks.ledger.order,64)
eq(T.trade(replayMarket,replayBank,"a",oldest,c).code,"StockSequence")
-- Same-price round trips never create funds, including zero fees.
for cents=1,303,13 do
    local market=M.create(cents); market.stocks.tool_01.cents=cents
    local b={current=10000}; local cfg=D.config({StockTradeFeePercent=0})
    check(T.trade(market,b,"a",request(market,b,1,"buy",100),cfg).ok)
    check(T.trade(market,b,"a",request(market,b,2,"sell",100),cfg).ok)
    check(b.current<=10000)
    eq(market.inputs[1].orders.tool_01,0)
end
-- News/UI randomness never changes market prices.
local news=GodSystemStockNews
local schedule=news.initial()
eq(news.status(schedule,0,c).nextHour,8)
eq(news.status(schedule,7,c).nextHour,8)
check(news.status(schedule,10,c).pending)
eq(news.status(schedule,10,c).nextHour,nil)
schedule.scheduleCount=3
eq(news.status(schedule,8,c).nextHour,16)
eq(news.status(schedule,16,c).nextHour,24)
eq(news.status(schedule,24,c).nextHour,32)
schedule.scheduleCount=1
eq(news.status(schedule,8,c).nextHour,32)
eq(news.status(schedule,0,D.config({StockNewsMaxPerDay=0})).nextHour,nil)
eq(news.status(schedule,0,D.config({EnableStockMarket=false})).nextHour,nil)
local releases=M.create(42)
hours(releases,7,c); eq(#releases.news.history,0)
hours(releases,1,c); eq(#releases.news.history,1); eq(releases.news.history[1].publishedHour,8)
hours(releases,24,c); check(#releases.news.history>=2)
local withNews=M.create(42); local noNews=M.create(42)
local silent=D.config({StockNewsMaxPerDay=0})
hours(withNews,24*30,c); hours(noNews,24*30,silent)
for i=1,#D.rows do eq(withNews.stocks[D.rows[i].id].cents,noNews.stocks[D.rows[i].id].cents,"news parity") end
check(#withNews.news.history<=64); eq(#noNews.news.history,0)
local dayCounts={}
for _,row in ipairs(withNews.news.history) do
    local day=math.floor((row.publishedHour-1)/24); dayCounts[day]=(dayCounts[day] or 0)+1
    check(dayCounts[day]<=3,"daily news budget")
end
-- Half-built jobs are invisible; new contributions are not cleared on commit.
local staged=M.create(7); staged.hour=1
M.addActivity(staged,"tool",1000)
local startVersion=staged.quoteVersion
local tick=0
M.step(staged,c,function() tick=tick+2; return tick end)
eq(staged.processed,0); eq(staged.quoteVersion,startVersion)
check(M.jobs[staged]~=nil)
M.addActivity(staged,"tool",3000)
while staged.processed<1 do M.step(staged,c) end
eq(staged.inputs[2].activity.tool,4000)
eq(#staged.stocks.tool_01.history,2)
-- Cancellation does not advance committed RNG or mutate public prices.
local cancel=M.create(9); cancel.hour=1
local saved=D.copy(cancel.rng); local t=0
M.step(cancel,c,function() t=t+2; return t end)
eq(cancel.rng.market,saved.market)
M.reset(cancel); eq(cancel.processed,0)
local control=M.create(9); control.hour=1
while cancel.processed<1 do M.step(cancel,c) end
M.step(control,c)
eq(cancel.stocks.tool_01.cents,control.stocks.tool_01.cents)
-- Late outbox retries land in an open hour, and each cumulative delta applies once.
local activity=M.create(3); local data={}
check(A.record(data,"tool",30000,"purchase1",c))
check(A.record(data,"tool",30000,"purchase1",c))
eq(data.stockActivity.totals.tool,30000)
A.pump(activity,data,"a"); A.pump(activity,data,"a")
eq(activity.inputs[1].activity.tool,30000)
hours(activity,2)
check(A.record(data,"tool",1000,"purchase2",c)); A.pump(activity,data,"a")
eq(activity.inputs[3].activity.tool,1000)
check(not A.record(data,"tool",1000,"disabled",D.config({EnableStockMarket=false})))
local sustained=M.create(3)
for _=1,30 do M.addActivity(sustained,"tool",30000); hours(sustained,1) end
check(sustained.sectors.tool.short<=0.005 and sustained.sectors.tool.long<=0.015)
check(sustained.sectors.tool.sustained)
hours(sustained,1000)
eq(sustained.sectors.tool.long,0)
check(not sustained.sectors.tool.sustained)
check(#sustained.stocks.tool_01.history<=169)
-- Clock anchors exclude offline/restart differences and preserve fractions.
local clock=M.create(1)
M.advance(clock,100,true,c); M.advance(clock,100.5,true,c); eq(clock.hour,0.5)
M.advance(clock,100.5,false,c); M.advance(clock,500,true,c); eq(clock.hour,0.5)
M.advance(clock,500.5,true,c); eq(clock.hour,1)
M.reset(clock); M.advance(clock,900,true,c); eq(clock.hour,1)
M.advance(clock,899,true,c); eq(clock.hour,1)
M.advance(clock,900,true,c); eq(clock.hour,2)
-- Bounded backlog freezes the clock, retains contributions and resumes deterministically.
local backlog=M.create(1); backlog.hour=168
M.advance(backlog,100,true,c); check(backlog.overloaded)
M.addActivity(backlog,"security",100)
eq(backlog.buffer.security,100)
while backlog.processed<144 do M.step(backlog,c) end
M.advance(backlog,101,true,c); eq(backlog.overloaded,nil)
eq(backlog.inputs[169].activity.security,100)
-- Native-free category allocation, no duplicated paid amount.
GodSystemEconomyPolicy={quote=function(fullType) return {referenceBuy=fullType=="Base.Hammer" and 100 or 300,category=fullType=="Base.Hammer" and "tool" or "food"} end}
local allocation={}
A.shop(allocation,{items={{fullType="Base.Hammer",count=1},{fullType="Base.Food",count=1}}},101,"bundle",c)
eq(allocation.stockActivity.totals.tool,25); eq(allocation.stockActivity.totals.food,76)
eq(A.industry("GodSystem.UtilityGenerator","tool",false),"energy")
eq(A.industry("Base.X","tool",true),"industry")
local unlocked={}
A.shop(unlocked,{variantKey="Base.Hammer",fullType="Base.Hammer"},100,"unlocked",c)
eq(unlocked.stockActivity.totals.tool,100)
eq(unlocked.stockActivity.totals.industry,nil)
print("Stock market regression passed: "..passed.." assertions")
