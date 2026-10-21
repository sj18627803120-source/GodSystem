require "GodSystem_StockService"
_G.GodSystemServerRuntimeInstallers=_G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Stocks"]=function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Stocks then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Stocks=true
    setfenv(1,runtimeEnvironment)
    local S,T,D=GodSystemStockService,GodSystemStockTrading,GodSystemStockDefinitions
    local sessions=setmetatable({}, {__mode="k"}); local sequence=0; local dirty=false; local lastNews=0
    local function reply(player,command,payload,session)
        if session then
            session.pushSequence=(session.pushSequence or 0)+1
            payload.token=session.token; payload.generation=session.generation; payload.pushSequence=session.pushSequence
        end
        S.metrics.messages=S.metrics.messages+1
        sendServerCommand(player,MODULE,command,payload)
    end
    local function context(player)
        applyRuntimeStores()
        local owner=userKey(player)
        if owner=="unknown" or owner=="" then return nil end
        local m=S.world(); if not m then return nil end
        S.market=m; S.syncConfig(m,S.config())
        return m,playerData(player),owner
    end
    local function valid(player,args)
        local s=sessions[player]
        if not s or type(args)~="table" or args.token~=s.token or args.generation~=s.generation then return nil end
        return s
    end
    local function markSent(s,m,data)
        s.revision=m.revision; s.config=m.configSignature
        s.balance=data.bank.current; s.accountRevision=data.bank.stocks and data.bank.stocks.revision
    end
    function Commands.stockOpen(_,_,player,args)
        if not D.integer(args.generation) or args.generation==0 then return end
        local m,data,owner=context(player); if not m then return end
        sequence=sequence+1
        local s={token=tostring(getTimestampMs and getTimestampMs() or 0)..":"..sequence,generation=args.generation,
            selected=D.byId[args.selected] and args.selected or "tool_01"}
        sessions[player]=s; T.recover(m,data.bank,owner)
        reply(player,"stockInit",S.view(m,data.bank,s.selected),s)
        markSent(s,m,data)
    end
    function Commands.stockClose(_,_,player,args)
        if valid(player,args) then sessions[player]=nil end
    end
    function Commands.stockDetail(_,_,player,args)
        local s=valid(player,args); if not s or not D.byId[args.selected] then return end
        if not GodSystemScheduler.due("server.stockDetail."..userKey(player),250) then return end
        local m,data=context(player); if not m then return end
        s.selected=args.selected
        reply(player,"stockView",S.view(m,data.bank,s.selected),s)
        markSent(s,m,data)
    end
    function Commands.stockTrade(_,_,player,args)
        local s=valid(player,args); if not s then return end
        local m,data,owner=context(player); if not m then return end
        local previousSequence=data.bank.stocks and data.bank.stocks.nextSequence or 1
        local response=T.trade(m,data.bank,owner,args,S.config())
        if response.code=="StockUnknown" or response.code=="StockRolledBack" then
            if GodSystemDiagnostics then GodSystemDiagnostics.issue("server","stocks","trade",response.code,args.opId) end
        end
        response.view=S.view(m,data.bank,s.selected)
        reply(player,"stockResult",response,s)
        markSent(s,m,data)
        -- Refresh the existing bank/top-bar projection once per new success.
        -- Stock receipts and market history remain excluded from that packet.
        if response.ok and data.bank.stocks.nextSequence>previousSequence and sendState then sendState(player) end
    end
    GodSystemServer.stockTick=function(players)
        S.maintain(nowHours(),players:size()>0)
    end
    GodSystemServer.stockPlayer=function(player,data)
        if data then S.pump(data,userKey(player)) end
        local m=S.market
        if m then
            local s=sessions[player]
            if s and data and (dirty or s.revision~=m.revision or s.config~=m.configSignature
                or s.balance~=data.bank.current or s.accountRevision~=(data.bank.stocks and data.bank.stocks.revision)) then
                reply(player,"stockView",S.view(m,data.bank,s.selected),s)
                markSent(s,m,data)
            end
            if m.news.sequence>lastNews and not s then
                reply(player,"stockNewsNotice",{sequence=m.news.sequence})
            end
        end
    end
    GodSystemServer.stockEnd=function(active)
        for player in pairs(sessions) do if not active[player] then sessions[player]=nil end end
        if S.market then lastNews=S.market.news.sequence end
        dirty=false
    end
    S.onSettled=function() dirty=true end
end
