require "GodSystem_StockDefinitions"
require "GodSystem_StockNews"
GodSystemStockMarket = GodSystemStockMarket or {}
local M,D,N=GodSystemStockMarket,GodSystemStockDefinitions,GodSystemStockNews
M.jobs=M.jobs or setmetatable({}, {__mode="k"})
M.anchors=M.anchors or setmetatable({}, {__mode="k"})
local function seed(master,key)
    local n=master
    for i=1,#key do n=(n*131+key:byte(i))%2147483646 end
    return n+1
end
function M.random(states,master,key)
    local n=((states[key] or seed(master,key))*16807)%2147483647
    states[key]=n; return (n-1)/2147483646
end
local function freshSector() return {hours={},short=0,long=0,sustained=false,grade=0} end
function M.create(master)
    master=math.floor(tonumber(master) or 1)%2147483646+1
    local m={schema=1,master=master,rng={},hour=0,processed=0,revision=1,quoteVersion=1,
        tradeConfigVersion=1,stocks={},sectors={},inputs={},buffer={},activityCursors={},news=N.initial()}
    for i=1,#D.industries do m.sectors[D.industries[i]]=freshSector() end
    for i=1,#D.rows do
        local r=D.rows[i]
        m.stocks[r.id]={natural=math.log(r.initial),target=math.log(r.initial),phaseUntil=0,
            logPrice=math.log(r.initial),cents=r.initial*100,sentiment=0,sentimentTarget=0,
            history={{hour=0,cents=r.initial*100}}}
    end
    return m
end
function M.input(m,hour)
    local row=m.inputs[hour]
    if not row then row={activity={},orders={}}; m.inputs[hour]=row end
    return row
end
function M.addActivity(m,industry,amount,hour)
    if not D.thresholds[industry] or not D.integer(amount) then return false end
    local target
    if m.overloaded then target=m.buffer
    else target=M.input(m,math.max(m.processed+1,math.floor(m.hour)+1,tonumber(hour) or 0)).activity end
    target[industry]=math.min(D.MAX-amount,target[industry] or 0)+amount
    return true
end
function M.advance(m,worldHour,online,c)
    local anchor=M.anchors[m]
    M.anchors[m]={world=worldHour,online=online,enabled=c.enabled}
    if not c.enabled then M.jobs[m]=nil; return end
    if m.configSignature~=c.signature then
        if m.fee~=nil and (m.fee~=c.fee or m.enabled~=c.enabled) then m.tradeConfigVersion=m.tradeConfigVersion+1 end
        m.configSignature=c.signature; M.jobs[m]=nil
    end
    m.fee=c.fee; m.enabled=c.enabled
    if m.hour-m.processed>=168 then m.overloaded=true end
    if m.overloaded then
        if m.hour-m.processed>24 then return end
        m.overloaded=nil
        for i=1,#D.industries do
            local id=D.industries[i]; local amount=m.buffer[id]
            if amount then M.addActivity(m,id,amount); m.buffer[id]=nil end
        end
        return
    end
    if not anchor or not anchor.online or not anchor.enabled or not online then return end
    local delta=worldHour-anchor.world
    if not D.finite(delta) or delta<=0 then return end
    m.hour=math.min(m.processed+168,m.hour+delta)
end
local function sectorStep(s,input,c)
    local amount=input or 0
    s.hours[#s.hours+1]=amount; while #s.hours>24 do table.remove(s.hours,1) end
    local heat,days=0,0
    local base=D.thresholds[s.id]; local t={}
    for i=1,4 do t[i]=base[i]*c.threshold end
    for i=1,#s.hours do heat=heat+s.hours[i]; if s.hours[i]>=t[1]/4 then days=days+1 end end
    local points={0,0.001,0.002,0.0035,0.005}; local target,grade=0,0
    local previous=0
    for i=1,4 do
        if heat>=t[i] then target=points[i+1]; grade=i
        else target=points[i]+(points[i+1]-points[i])*(heat-previous)/(t[i]-previous); break end
        previous=t[i]
    end
    s.short=s.short+0.25*(target-s.short)
    if heat>=t[4] then
        s.long=s.long+0.125*(0.015-s.long)
        if days>=3 and not s.sustained then s.sustained=true; s.report=true end
    else s.long=s.long*math.exp(-math.log(2)/(s.sustained and 36 or 12)) end
    if s.long<0.000001 and heat<t[4] then s.long=0; s.sustained=false end
    if grade>=2 and grade>(s.grade or 0) then s.report=true end
    s.grade=grade
end
function M.begin(m,c)
    if not c.enabled or m.processed>=math.floor(m.hour) then return nil end
    local h=m.processed+1; local input=D.copy(M.input(m,h))
    local j={hour=h,config=D.copy(c),signature=c.signature,rng=D.copy(m.rng),stocks={},sectors=D.copy(m.sectors),
        news=D.copy(m.news),input=input,cursor=1}
    local function random(key) return M.random(j.rng,m.master,key) end
    for i=1,#D.rows do
        local id=D.rows[i].id; local src=m.stocks[id]; local s={}
        for key,value in pairs(src) do if key~="history" then s[key]=value end end
        if h>=s.phaseUntil then
            local r=random("phase."..id); local u=random("phase."..id)
            local shift
            if r<0.3 then shift=math.log(1.04)+u*(math.log(1.12)-math.log(1.04))
            elseif r<0.7 then shift=(u*2-1)*math.log(1.02)
            else shift=-math.log(1.04)-u*(math.log(1.12)-math.log(1.04)) end
            s.target=s.natural+shift
            s.phaseUntil=h+c.minDays*24+math.floor(random("phase."..id)*((c.maxDays-c.minDays)*24+1))
        end
        j.stocks[id]=s
    end
    for i=1,#D.industries do
        local id=D.industries[i]; local s=j.sectors[id]; s.id=id
        sectorStep(s,input.activity[id],c)
    end
    N.prepare(j,random)
    j.marketNoise=(random("market")*2-1)*0.002*c.volatility
    j.sectorNoise={}
    for i=1,#D.industries do local id=D.industries[i]; j.sectorNoise[id]=(random("sector."..id)*2-1)*0.004*c.volatility end
    M.jobs[m]=j; return j
end
function M.step(m,c,nowMs)
    if not c.enabled then M.jobs[m]=nil; return false end
    local start=nowMs and nowMs() or 0
    local j=M.jobs[m]
    if j and j.signature~=c.signature then M.jobs[m]=nil; j=nil end
    j=j or M.begin(m,c); if not j then return false end
    local processed=0
    while j.cursor<=#D.rows and processed<24 do
        local def=D.rows[j.cursor]; local id=def.id; local s=j.stocks[id]; local sector=j.sectors[def.industry]
        s.natural=s.natural+0.025*(s.target-s.natural)
        s.sentiment=s.sentiment+0.25*(s.sentimentTarget-s.sentiment)
        local effective=s.natural+math.log(1+def.factor*c.activity*(sector.short+sector.long))+s.sentiment
        local noise=(M.random(j.rng,m.master,"noise."..id)+M.random(j.rng,m.master,"noise."..id)-1)*0.02*def.factor*c.volatility
        local net=j.input.orders[id] or 0
        local order=0.002*D.clamp(net*(m.stocks[id].cents/100)/(def.initial*2000),-1,1)*c.order
        local change=0.06*(effective-s.logPrice)+j.marketNoise+j.sectorNoise[def.industry]+noise+order
        local bound=0.06*math.max(1,c.volatility)
        change=D.clamp(change,math.log(1-bound),math.log(1+bound))
        local logPrice=s.logPrice+change; local cents=math.floor(math.exp(logPrice)*100+0.5)
        if D.integer(cents) and cents>0 and D.finite(logPrice) then s.logPrice=logPrice; s.cents=cents; s.suspended=nil
        else s.suspended=true end
        j.cursor=j.cursor+1; processed=processed+1
        if nowMs and nowMs()-start>=2 then break end
    end
    if j.cursor<=#D.rows then return false end
    local changed=false
    for i=1,#D.rows do
        local id=D.rows[i].id; local old=m.stocks[id]; local s=j.stocks[id]
        if old.cents~=s.cents or old.suspended~=s.suspended then changed=true end
        s.history=old.history
        s.history[#s.history+1]={hour=j.hour,cents=s.cents}
        while #s.history>169 do table.remove(s.history,1) end
        m.stocks[id]=s
    end
    m.rng=j.rng; m.sectors=j.sectors; m.news=j.news
    m.processed=j.hour; m.inputs[j.hour]=nil; m.revision=m.revision+1
    if changed then m.quoteVersion=m.quoteVersion+1 end
    M.jobs[m]=nil
    return true
end
function M.reset(m) M.jobs[m]=nil; M.anchors[m]=nil end
return M
