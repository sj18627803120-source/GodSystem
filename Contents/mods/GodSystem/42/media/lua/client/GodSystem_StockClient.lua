require "GodSystem_StockService"
require "GodSystem_Protocol"
GodSystemStockClient=GodSystemStockClient or {}
local C,S,D,T=GodSystemStockClient,GodSystemStockService,GodSystemStockDefinitions,GodSystemStockTrading
C.generation=C.generation or 0
C.opSequence=C.opSequence or 0
local function multiplayer() return isClient and isClient() end
local function runtime() return GodSystemApp and GodSystemApp.services.runtime end
local function selected() return C.selected or "tool_01" end
function C.newsNotice(sequence)
    if not D.integer(sequence) or sequence<=(C.noticeSequence or 0) then return end
    C.noticeSequence=sequence
    if sequence>(C.readSequence or 0) then C.unread=sequence end
    if GodSystemUI and GodSystemUI.window then GodSystemUI.window:layoutNavigation(true) end
end
local function send(command,args)
    local ok=pcall(sendClientCommand,"GodSystem",command,args)
    if not ok and GodSystemDiagnostics then GodSystemDiagnostics.issue("client","stocks","send","failed",args.opId) end
    return ok
end
local function update(view)
    if C.view and view.revision<C.view.revision then return end
    C.view=view
    local last=view.news and view.news[#view.news]
    if last and last.sequence>(C.readSequence or 0) then C.unread=last.sequence end
    if C.onUpdate then C.onUpdate() end
end
function C.open()
    C.selected=C.selected or "tool_01"
    C.generation=C.generation+1; C.token=nil; C.view=nil; C.opened=true; C.pushSequence=0
    if multiplayer() then send("stockOpen",{generation=C.generation,selected=selected()})
    else
        local r=runtime(); local data=r and r.getData(); local m=S.world()
        if m and data then
            S.market=m; T.recover(m,data.bank,"sp")
            update(S.view(m,data.bank,selected()))
        end
    end
end
function C.close()
    if multiplayer() and C.token then send("stockClose",{generation=C.generation,token=C.token}) end
    C.opened=false; C.token=nil; C.view=nil
end
function C.select(id)
    if not D.byId[id] then return end
    C.selected=id
    if multiplayer() then
        if C.token then send("stockDetail",{generation=C.generation,token=C.token,selected=id}) end
    else
        local r=runtime(); local m=S.market or S.world()
        if m and r then update(S.view(m,r.getData().bank,id)) end
    end
end
function C.trade(side,quantity)
    if C.pending or not C.view then return false end
    local stamp=math.floor(getTimestampMs and getTimestampMs() or 0)
    C.opSequence=C.opSequence+1
    local args={opId="gs-"..string.format("%.0f",stamp).."-"..string.format("%.0f",C.opSequence).."-"..string.format("%.0f",C.generation),
        stockId=selected(),side=side,quantity=quantity,quoteVersion=C.view.quoteVersion,
        tradeConfigVersion=C.view.tradeConfigVersion,tradeSequence=C.view.account.nextSequence,
        token=C.token,generation=C.generation}
    C.pending=args; C.lastSend=stamp
    if multiplayer() then send("stockTrade",args)
    else
        local r=runtime(); local m=S.market or S.world(); local data=r.getData()
        S.syncConfig(m,S.config())
        local response=T.trade(m,data.bank,"sp",args,S.config())
        C.pending=nil; C.result=response.code
        update(S.view(m,data.bank,selected())); if r.save then r.save() end
    end
    return true
end
function C.retry()
    if not C.pending or not multiplayer() or not C.token then return end
    C.pending.token=C.token; C.pending.generation=C.generation
    send("stockTrade",C.pending)
    C.lastSend=math.floor(getTimestampMs and getTimestampMs() or 0)
    if GodSystemDiagnostics then GodSystemDiagnostics.issue("client","stocks","retry","pending",C.pending.opId) end
end
function C.refreshSP()
    if not multiplayer() and C.opened then
        local m=S.market; local r=runtime(); local data=r and r.getData()
        if m and data and (not C.view or C.view.revision~=m.revision or C.view.account.balance~=data.bank.current
            or C.lastConfig~=S.config().signature) then
            C.lastConfig=S.config().signature; C.select(selected())
        end
    end
end
function C.reset()
    C.close(); C.view=nil; C.pending=nil; C.result=nil; C.unread=nil; C.readSequence=0; C.noticeSequence=0; C.generation=C.generation+1
    if not multiplayer() then S.reset() end
    if C.onReset then C.onReset() end
end
local function serverCommand(module,command,args)
    if module~="GodSystem" or type(args)~="table" then return end
    if command=="stockNewsNotice" then
        C.newsNotice(args.sequence)
        return
    end
    if not C.opened or args.generation~=C.generation then return end
    if command=="stockInit" then
        if C.token then return end
        if not D.integer(args.pushSequence) or args.pushSequence<1 then return end
        C.token=args.token; C.pushSequence=args.pushSequence; update(args)
    elseif args.token==C.token then
        if not D.integer(args.pushSequence) then return end
        local fresh=args.pushSequence>C.pushSequence
        if fresh then C.pushSequence=args.pushSequence end
        if command=="stockView" and fresh then update(args)
        elseif command=="stockResult" and C.pending and args.opId==C.pending.opId then
            C.pending=nil; C.result=args.code
            if args.view and fresh then update(args.view)
            elseif C.onUpdate then C.onUpdate() end
        end
    end
end
if Events and Events.OnServerCommand then Events.OnServerCommand.Add(serverCommand) end
if Events and Events.OnGameExit then Events.OnGameExit.Add(C.reset) end
if not multiplayer() then S.onSettled=function(m) C.newsNotice(m.news.sequence) end end
return C
