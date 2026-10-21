assert(loadstring(readFixture("terminal_fixture.lua")))()
assert(loadstring(readSource("shared/GodSystem_Localization_Override.lua")))()
translations=GodSystemFallbackText.zh
local fixtureRequire=require; local loaded={}
function require(key)
    if key:find("GodSystem_Stock",1,true)==1 or key=="GodSystem_OperationLedger" then
        if loaded[key] then return loaded[key] end
        local folder=(key=="GodSystem_StockClient" or key=="GodSystem_StockMarketUI") and "client/" or "shared/"
        local v=assert(loadstring(readSource(folder..key..".lua")))(); loaded[key]=v; return v
    end
    return fixtureRequire(key)
end
function ISPanel:update() end
function ISPanel:setResizable(v) self.resizable=v end
function ISTextEntryBox:getInternalText() return self.text end
local root={}
ModData={getOrCreate=function() return root end}
GodSystemScheduler={nowMs=function() return 10000 end}
local UI=require "GodSystem_StockMarketUI"
local C,D,M=GodSystemStockClient,GodSystemStockDefinitions,GodSystemStockMarket
local w=UI.open()
assert(w and C.view and #w.list.items==24)
assert(C.selected=="tool_01" and w.buy.enable)
local before=fixtureData.bank.current
C.trade("buy",10)
assert(fixtureData.bank.current<before and C.view.account.positions.tool_01.quantity==10)
w.mode="positions"; w:rebuild(); assert(#w.list.items==1)
-- Empty history is explicit. News is scheduled in online game time, not real minutes.
assert(#w.candles==0 and w.chartMessage)
w.mode="news"; w:rebuild()
assert(table.concat(w.newsSummary," "):find("8",1,true))
local market=GodSystemStockService.market
market.hour=8
while market.processed<8 do M.step(market,GodSystemStockService.config()) end
C.refreshSP()
assert(#C.view.news==1 and #w.list.items==1,"news did not refresh an open SP window")
assert(w.list.items[1].item.news.publishedHour==8)
assert(C.unread==nil,"visible news remained unread")
local originalQuote=D.quote
D.quote=function() error("hidden trade panel requested quote") end
w:rebuild(); assert(#w.candles==0 and #w.newsSummary>0)
D.quote=originalQuote
-- OHLC comes solely from persisted hourly samples, including open/flat candles.
local liveHistory=C.view.history
C.view.history={{hour=0,cents=10000},{hour=1,cents=11000},{hour=2,cents=9000},
    {hour=3,cents=9500},{hour=4,cents=9500}}
w.mode="market"; w.days=1; w:rebuild()
assert(#w.candles==4 and w.candles[1].color=="red" and w.candles[2].color=="accent")
assert(w.candles[4].color=="muted" and w.candles[4].h==1)
w.days=3; w:chart()
assert(#w.candles==2 and w.candles[1].open==10000 and w.candles[1].close==9500)
assert(w.candles[1].high==11000 and w.candles[1].low==9000)
local sampledHistory={}
for h=0,168 do sampledHistory[#sampledHistory+1]={hour=h,cents=10000+(h%9)*100} end
C.view.history=sampledHistory
for _,days in ipairs({1,3,7}) do
    w.days=days; w:chart()
    assert(#w.candles==(days==7 and 28 or 24),"range aggregation exceeded expected candle count")
end
-- Rendering never queries a price, scans inventory or sends a request.
local quote=D.quote; local wrapped=GodSystemTerminalDesign.wrap
D.quote=function() error("draw requested a quote") end
GodSystemTerminalDesign.wrap=function() error("draw rebuilt text") end
draws={}; renderTree(w)
D.quote=quote; GodSystemTerminalDesign.wrap=wrapped
assert(#draws>0)
-- Actual controller draws and list culling at each terminal font and screen size.
for _,screen in ipairs({{1280,720},{1920,1080},{2560,1440},{3840,2160}}) do
    for _,font in ipairs({"small","normal","large"}) do
        screenW,screenH=screen[1],screen[2]
        GodSystemTerminalPreferences.current={font=font,size="auto"}
        w.width=math.min(1120,screenW-24); w.height=math.min(740,screenH-24)
        w.x=(screenW-w.width)/2; w.y=(screenH-w.height)/2
        w:layout(); w.mode="market"; w:rebuild()
        assert(w.orderRowH>=w.ch*2+4,"cost lines overlap quantity shortcuts")
        assert(w.quick[1].y>=w.oy+w.ch*2,"fee text overlaps buttons")
        assert(#w.candles>0,"chart vanished at a supported font/resolution")
        for _,bar in ipairs(w.candles) do
            assert(bar.w<=12 and bar.wickY>=w.chartY and bar.wickY+bar.wickH<=w.chartY+w.chartH)
            assert(bar.y>=w.chartY and bar.y+bar.h<=w.chartY+w.chartH)
        end
        assert(w.quantity.x>=w.dx+w.quantityLabelW and w.quantity.width>=50)
        assert(w.latestY+w.ch<w.chartY,"company details overlap chart")
        draws={}; renderTree(w)
        for _,b in ipairs(w.quick) do
            assert(b.x>=0 and b.y>=0 and b.x+b.width<=w.width and b.y+b.height<=w.height)
            assert(getTextManager():getFontHeight(b.font)<=b.height)
            assert(getTextManager():MeasureStringX(b.font,b.title)<=b.width,"stock button text clipped")
        end
        assert(w.chartY+w.chartH<w.oy)
        for _,scroll in ipairs({0,-20,-200}) do
            w.list:setYScroll(scroll); draws={}
            w:drawRow(w.list,-scroll-20,{height=w.list.itemheight,index=1,item={label="boundary",subtitle="test"}},false)
            w:drawRow(w.list,-scroll+w.list.height-5,{height=w.list.itemheight,index=2,item={label="boundary",subtitle="test"}},false)
            assert(#draws>0,"scrolled list became blank")
            for _,draw in ipairs(draws) do
            if draw.ui==w.list then
                local originY=w.y+w.list.y
                local h=draw.kind=="text" and getTextManager():getFontHeight(draw.font) or draw.h
                assert(draw.y>=originY and draw.y+h<=originY+w.list.height)
            end
            end
        end
    end
end
C.view.history=liveHistory
-- Selection and scroll survive market snapshots; closing releases the overlay.
w.list:setYScroll(-30); C.select("food_02"); w:rebuild()
assert(C.selected=="food_02" and w.list:getYScroll()<=0)
assert(UI.open()==w)
w:close(); assert(not C.opened and UI.instance==nil)
-- Exercise client session filtering using real network adapter, not a fake trade handler.
local callbacks={}; Events.OnServerCommand.Add=function(fn) callbacks[#callbacks+1]=fn end
local sent={}; isClient=function() return true end
sendClientCommand=function(module,command,args) sent[#sent+1]={command=command,args=args} end
GodSystemStockClient=nil; loaded.GodSystem_StockClient=nil
C=require "GodSystem_StockClient"
C.open(); local generation=C.generation
local callback=callbacks[#callbacks]
local m=M.create(1); local bank={current=10000}
local view=GodSystemStockService.view(m,bank,"tool_01")
view.generation=generation-1; view.token="old"; view.pushSequence=1
callback("GodSystem","stockInit",view); assert(C.token==nil)
view.generation=generation; view.token="new"
callback("GodSystem","stockInit",view); assert(C.token=="new")
C.trade("buy",1); local pending=C.pending
assert(pending and sent[#sent].command=="stockTrade")
C.retry(); assert(sent[#sent].args.opId==pending.opId)
callback("GodSystem","stockResult",{generation=generation,token="old",opId=pending.opId,code="StockSuccess",pushSequence=2})
assert(C.pending==pending)
callback("GodSystem","stockResult",{generation=generation,token="new",opId=pending.opId,code="StockStale",view=view,pushSequence=3})
assert(C.pending==nil and C.result=="StockStale")
local saved=C.view
local late=GodSystemStockDefinitions.copy(view); late.account.balance=0; late.pushSequence=2
callback("GodSystem","stockView",late)
assert(C.view==saved and C.view.account.balance==10000,"late same-price view overwrote account")
C.reset(); assert(C.token==nil and C.view==nil and C.pending==nil)
print("Stock UI and client sessions passed: SP trades, four resolutions, fonts, clipping, cached draw, replay and late packets")
