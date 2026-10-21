require "GodSystem_StockTrading"
require "GodSystem_StockActivity"
GodSystemStockService=GodSystemStockService or {}
local S,D,M,T,A=GodSystemStockService,GodSystemStockDefinitions,GodSystemStockMarket,GodSystemStockTrading,GodSystemStockActivity
S.Key="GodSystem_CN_StockMarket"
S.metrics=S.metrics or {settlements=0,steps=0,messages=0,activityFailures=0,maxStepMs=0}
function S.issue(phase,code,opId)
    if GodSystemDiagnostics and GodSystemDiagnostics.issue then
        GodSystemDiagnostics.issue(isServer and isServer() and "server" or "sp","stocks",phase,code,opId)
    end
end
function S.config()
    return D.config(GodSystemRuntimeConfig and GodSystemRuntimeConfig.Current or GodSystemConfig or {})
end
function S.world()
    if isClient and isClient() then return nil end
    if not ModData or not ModData.getOrCreate then return nil end
    local root=ModData.getOrCreate(S.Key)
    if root.market==nil then root.market=M.create(getTimestamp and getTimestamp() or 1) end
    local m=root.market
    if type(m)~="table" or m.schema~=1 or type(m.stocks)~="table" or type(m.rng)~="table"
        or type(m.sectors)~="table" or type(m.news)~="table" or type(m.inputs)~="table"
        or type(m.activityCursors)~="table" or not D.integer(m.processed) or not D.finite(m.hour)
        or m.hour<m.processed then return nil end
    for i=1,#D.rows do
        local s=m.stocks[D.rows[i].id]
        if type(s)~="table" or not D.integer(s.cents) or s.cents==0 or type(s.history)~="table" then return nil end
    end
    return root.market
end
function S.syncConfig(m,c)
    if m.configSignature~=c.signature then
        if m.fee~=nil and (m.fee~=c.fee or m.enabled~=c.enabled) then m.tradeConfigVersion=m.tradeConfigVersion+1 end
        m.configSignature=c.signature; M.jobs[m]=nil
    end
    m.fee=c.fee; m.enabled=c.enabled
end
local function nowMs() return GodSystemScheduler and GodSystemScheduler.nowMs() or 0 end
local function work()
    local m=S.runningMarket; local c=S.config()
    if not m or not c.enabled then S.stopWorker(); return end
    S.syncConfig(m,c)
    local start=nowMs()
    local ok,changed=pcall(M.step,m,c,nowMs)
    S.metrics.steps=S.metrics.steps+1
    S.metrics.maxStepMs=math.max(S.metrics.maxStepMs,nowMs()-start)
    if not ok then
        S.lastError="StockSettlementFailed"; S.stopWorker()
        S.issue("settlement","failed")
        return
    end
    if changed then
        S.metrics.settlements=S.metrics.settlements+1
        if S.onSettled then
            local notified=pcall(S.onSettled,m)
            if not notified then S.issue("settlementNotice","failed") end
        end
    end
    if m.processed>=math.floor(m.hour) and not M.jobs[m] then S.stopWorker() end
end
function S.stopWorker()
    if S.worker and Events and Events.OnTick then Events.OnTick.Remove(S.worker) end
    S.worker=nil; S.runningMarket=nil
end
function S.maintain(worldHour,online)
    local c=S.config()
    local m=S.market
    if not c.enabled and not m then return end
    m=m or S.world(); if not m then return end
    S.market=m; S.syncConfig(m,c); M.advance(m,worldHour,online,c)
    if m.overloaded then S.issue("clock","backlogPaused") end
    if not c.enabled then S.stopWorker(); return end
    if m.processed<math.floor(m.hour) and not S.worker then
        S.runningMarket=m; S.worker=work
        if Events and Events.OnTick then Events.OnTick.Add(S.worker) else work() end
    end
end
function S.pump(data,owner)
    if not S.config().enabled then return end
    local m=S.market or S.world(); if not m then return end
    S.market=m
    local ok=pcall(A.pump,m,data,owner)
    if not ok then S.metrics.activityFailures=S.metrics.activityFailures+1; S.issue("activity","pumpFailed") end
end
function S.record(data,industry,amount,token)
    local c=S.config(); if not c.enabled then return false end
    if amount==0 then return true end
    local ok,value=pcall(A.record,data,industry,amount,token,c)
    if not ok or not value then S.metrics.activityFailures=S.metrics.activityFailures+1; S.issue("activity","recordFailed",token) end
    if data.stockActivity and data.stockActivity.saturated then S.issue("activity","counterSaturated") end
    return ok and value==true
end
function S.shop(data,row,paid,token)
    local c=S.config(); if not c.enabled then return end
    local ok=pcall(A.shop,data,row,paid,token,c)
    if not ok then S.metrics.activityFailures=S.metrics.activityFailures+1; S.issue("activity","shopClassificationFailed",token) end
end
function S.view(m,bank,selected)
    local c=S.config(); S.syncConfig(m,c)
    local rows={}
    for i=1,#D.rows do
        local def=D.rows[i]; local s=m.stocks[def.id]
        local old=s.history[math.max(1,#s.history-1)]
        rows[i]={id=def.id,cents=s.cents,previous=old and old.cents or s.cents,suspended=s.suspended==true}
    end
    return {revision=m.revision,quoteVersion=m.quoteVersion,tradeConfigVersion=m.tradeConfigVersion,
        hour=m.processed,enabled=c.enabled,fee=c.fee,rows=rows,news=D.copy(m.news.history),
        newsStatus=GodSystemStockNews.status(m.news,m.processed,c),
        account=T.publicAccount(bank),updating=M.jobs[m]~=nil or m.processed<math.floor(m.hour),
        overloaded=m.overloaded==true,selected=selected,
        history=selected and m.stocks[selected] and D.copy(m.stocks[selected].history) or nil}
end
function S.reset()
    S.stopWorker()
    if S.market then M.reset(S.market) end
    S.market=nil; S.lastError=nil
end
if Events and Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(S.reset) end
return S
