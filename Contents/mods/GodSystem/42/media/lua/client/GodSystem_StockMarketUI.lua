require "GodSystem_StockClient"
require "GodSystem_TerminalDesign"
require "GodSystem_Pinyin"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
---@class GodSystemStockMarketUI: ISCollapsableWindow
GodSystemStockMarketUI=ISCollapsableWindow:derive("GodSystemStockMarketUI")
local UI,C,D,F=GodSystemStockMarketUI,GodSystemStockClient,GodSystemTerminalDesign,GodSystemStockDefinitions
local function text(key,fallback,...)
    local r=GodSystemApp.services.runtime
    local s=r.text("Stock_"..key,fallback or key); local args={...}
    return (tostring(s):gsub("{(%d+)}",function(n) return tostring(args[tonumber(n)] or "") end))
end
local function name(id) return text("Company_"..tostring(id),tostring(id)) end
local function industry(id) return text("Industry_"..tostring(id),tostring(id)) end
local function money(n) return string.format("%.2f",(tonumber(n) or 0)/100) end
local function amount(n) return D.number(n) end
local function now() return getTimestampMs and getTimestampMs() or 0 end
function UI:new(x,y,width,height)
    return ISCollapsableWindow.new(self,x,y,width,height)
end
function UI:button(label,callback)
    local b=ISButton:new(0,0,80,30,label,self,callback); b:initialise(); b:instantiate(); D.style(b); self:addChild(b); return b
end
function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.tabs={}
    for _,mode in ipairs({"market","positions","news"}) do
        local value=mode
        self.tabs[#self.tabs+1]=self:button(text(mode),function() self.mode=value; self:rebuild() end)
    end
    self.search=ISTextEntryBox:new("",12,70,250,30); self.search:initialise(); self.search:instantiate(); D.style(self.search)
    self.search:setPlaceholderText(text("Search"))
    self.search.onTextChange=function() self.searchDue=now()+250 end; self:addChild(self.search)
    self.list=ISScrollingListBox:new(12,110,350,400); self.list:initialise(); self.list:instantiate()
    self.list.doDrawItem=function(list,y,row,alt) return self:drawRow(list,y,row,alt) end
    self.list:setOnMouseDownFunction(self,self.onRow); GodSystemUISafety.installList(self.list); self:addChild(self.list)
    self.quantity=ISTextEntryBox:new("1",0,0,120,30); self.quantity:initialise(); self.quantity:instantiate(); D.style(self.quantity)
    self.quantity.onTextChange=function() self:order() end; self:addChild(self.quantity)
    self.quick={}
    for _,n in ipairs({1,10,100}) do
        local value=n
        self.quick[#self.quick+1]=self:button(tostring(n),function() self.quantity:setText(tostring(value)); self:order() end)
    end
    self.quick[#self.quick+1]=self:button(text("MaxBuy"),function()
        local v=C.view; local s=self:stock()
        if v and s then self.quantity:setText(tostring(F.maxBuy(s.cents,v.account.balance or 0,v.fee))); self:order() end
    end)
    self.quick[#self.quick+1]=self:button(text("AllSell"),function()
        local v=C.view; local p=v and v.account.positions and v.account.positions[C.selected]
        self.quantity:setText(tostring(p and p.quantity or 0)); self:order()
    end)
    self.buy=self:button(text("Buy"),function() C.trade("buy",tonumber(self.quantity:getInternalText())); self:order() end)
    self.sell=self:button(text("Sell"),function() C.trade("sell",tonumber(self.quantity:getInternalText())); self:order() end)
    self.retry=self:button(text("Retry"),function() C.retry() end)
    self.ranges={}
    for _,days in ipairs({1,3,7}) do
        local value=days
        self.ranges[#self.ranges+1]=self:button(text("Days",nil,days),function() self.days=value; self:chart() end)
    end
    self:layout(); self:rebuild()
end
function UI:stock()
    for _,row in ipairs(C.view and C.view.rows or {}) do if row.id==C.selected then return row end end
end
function UI:layout()
    self.font=D.font("body"); self.fh=D.height("body"); self.ch=D.height("caption")
    local h=math.max(28,self.fh+10); self.bh=h
    local left=math.floor(self.width*0.35); self.dx=left+26; self.dw=self.width-self.dx-14
    for i=1,#self.tabs do D.bounds(self.tabs[i],12+(i-1)*(left-8)/3,34,(left-14)/3,h); D.style(self.tabs[i]) end
    D.bounds(self.search,12,40+h,left,h)
    self.ly=48+h*2; D.bounds(self.list,12,self.ly,left,self.height-self.ly-16)
    self.list.itemheight=self.fh+self.ch+18
    self.orderRowH=math.max(h,self.ch*2+4)
    self.oy=self.height-self.orderRowH-h*3-28
    self.quantityLabelW=getTextManager():MeasureStringX(self.font,text("Shares"))+12
    D.bounds(self.quantity,self.dx+self.quantityLabelW,self.oy,self.dw*0.28-self.quantityLabelW,h)
    local qx=self.dx
    for i=1,#self.quick do
        local width=(self.dw-16)*(i<=3 and 0.15 or 0.275)
        D.bounds(self.quick[i],qx,self.oy+self.orderRowH+5,width,h); D.style(self.quick[i]); qx=qx+width+4
    end
    D.bounds(self.buy,self.dx,self.oy+self.orderRowH+h+10,(self.dw-8)/2,h)
    D.bounds(self.sell,self.dx+(self.dw+8)/2,self.oy+self.orderRowH+h+10,(self.dw-8)/2,h)
    D.bounds(self.retry,self.dx+self.dw*0.3,self.oy,self.dw*0.7,h)
    self.companyY=54+self.fh*2
    self.positionY=self.companyY+self.fh+7; self.profitY=self.positionY+self.ch+5
    self.profileY=self.profitY+self.ch+5; self.latestY=self.profileY+self.ch+5
    self.chartY=self.latestY+self.ch+12
    self.chartH=math.max(40,self.oy-self.chartY-h-14)
    for i=1,#self.ranges do D.bounds(self.ranges[i],self.dx+(i-1)*82,self.chartY+self.chartH+3,76,h); D.style(self.ranges[i]) end
    D.style(self.search); D.style(self.quantity); D.style(self.buy,true); D.style(self.sell)
end
function UI:rebuild()
    if not self.list then return end
    local scroll=self.list:getYScroll(); local old=self.list.items[self.list.selected]
    local key=old and old.item and old.item.key
    self.list:clear(); self.indices=self.indices or {}
    local query=self.search:getInternalText()
    if self.mode=="news" then
        local news=C.view and C.view.news or {}
        local keep={}
        for _,def in ipairs(F.rows) do keep[def.id]=self.indices[def.id] end
        for i=#news,1,-1 do
            local row=news[i]; local title=self:newsText(row)
            local heading=text("NewsKind_"..row.kind).." | "..(row.id and name(row.id) or industry(row.industry))
            local fields=heading.."|"..title
            local cacheKey="news:"..row.sequence
            if not self.indices[cacheKey] or self.indices[cacheKey].fields~=fields then
                self.indices[cacheKey]={fields=fields,index=GodSystemPinyin.buildIndex({heading,title,row.id or "",row.industry or ""})}
            end
            keep[cacheKey]=self.indices[cacheKey]
            if GodSystemPinyin.matches(self.indices[cacheKey].index,query) then
                self.list:addItem(heading,{key="news:"..row.sequence,news=row,label=heading,body=title,
                    subtitle=text("Hour",nil,row.publishedHour)})
            end
        end
        self.indices=keep
        local latest=news[#news]
        C.readSequence=latest and latest.sequence or C.readSequence or 0; C.unread=nil
    else
        for i=1,#(C.view and C.view.rows or {}) do
            local row=C.view.rows[i]; local def=F.byId[row.id]; local label=name(row.id)
            local fields=label.."|"..industry(def.industry).."|"..row.id
            if not self.indices[row.id] or self.indices[row.id].fields~=fields then
                self.indices[row.id]={fields=fields,index=GodSystemPinyin.buildIndex({label,row.id,industry(def.industry)})}
            end
            local holding=C.view.account.positions and C.view.account.positions[row.id]
            if (self.mode~="positions" or holding) and GodSystemPinyin.matches(self.indices[row.id].index,query) then
                self.list:addItem(label,{key=row.id,label=label,stock=row,
                    changeColor=row.cents>row.previous and "red" or row.cents<row.previous and "accent" or "muted",
                    subtitle=money(row.cents).."  "..string.format("%+.2f%%",(row.cents/row.previous-1)*100)})
            end
        end
    end
    local selected=0
    for i=1,#self.list.items do
        local item=self.list.items[i].item
        if item.key==(self.mode=="news" and key or C.selected) then selected=i; break end
    end
    self.list.selected=selected>0 and selected or (#self.list.items>0 and 1 or 0)
    local current=self.list.items[self.list.selected]
    if self.mode~="news" and current and current.item.stock and current.item.stock.id~=C.selected then C.select(current.item.stock.id) end
    local overflow=math.max(0,#self.list.items*self.list.itemheight-self.list.height)
    self.list:setYScroll(math.max(-overflow,math.min(0,scroll)))
    self.list.targetYScroll=nil; self.list.smoothScrollY=nil; self.list.smoothScrollTargetY=nil
    GodSystemUISafety.syncListGeometry(self.list)
    self:order(); self:chart()
    self.tabs[3]:setTitle(text("news")..(C.unread and " *" or ""))
    for i,mode in ipairs({"market","positions","news"}) do D.style(self.tabs[i],self.mode==mode) end
    self.search:setPlaceholderText(text(self.mode=="news" and "SearchNews" or "Search"))
end
function UI:onRow(row)
    local item=row and (row.item or row)
    if item and item.stock then C.select(item.stock.id) end
    self:order(); self:chart()
end
function UI:drawRow(list,y,row,alt)
    local height=row.height or list.itemheight; local bottom=list.height or 0
    local scroll=list:getYScroll()
    if y+height+scroll>0 and y+scroll<bottom then
        local top=math.max(0,y+scroll); local visible=math.min(bottom,y+height+scroll)-top
        D.rect(list,0,top-scroll,list.width,visible,list.selected==row.index and "selected" or (alt and "raised" or "panel"))
        if y+5+scroll>=0 and y+5+scroll+self.fh<=bottom then D.label(list,row.item.label,8,y+5,list.width-28,"text","body") end
        if y+8+self.fh+scroll>=0 and y+8+self.fh+scroll+self.ch<=bottom then
            D.label(list,row.item.subtitle,8,y+8+self.fh,list.width-28,row.item.changeColor or "muted","caption")
        end
    end
    return y+height
end
function UI:newsText(row)
    return text("News_"..row.kind,nil,row.id and name(row.id) or industry(row.industry),row.delta and (row.delta>0 and text("Positive") or text("Negative")) or "")
end
function UI:chart()
    self.candles={}; self.chartGrid={}; self.chartTimes={}; self.chartMessage=nil
    self.chartLegend=nil; self.chartOHLC=nil
    for i,days in ipairs({1,3,7}) do D.style(self.ranges[i],self.days==days) end
    if self.mode=="news" then return end
    local view=C.view
    if not view or view.selected~=C.selected or not view.history then
        self.chartMessage=text("ChartWaiting"); return
    end
    local history=view.history; local last=history[#history]
    local period=self.days==1 and 1 or self.days==3 and 3 or 6
    local cutoff=(last and last.hour or 0)-self.days*24
    local bars={}; local bucket=nil
    for i=2,#history do
        local p,previous=history[i],history[i-1]
        if F.finite(p.hour) and F.finite(previous.hour) and p.hour>previous.hour and p.hour>cutoff
            and F.integer(p.cents) and p.cents>0 and F.integer(previous.cents) and previous.cents>0 then
            local key=math.floor((p.hour-1)/period)
            local bar=bars[#bars]
            if key~=bucket then
                bar={open=previous.cents,high=previous.cents,low=previous.cents,
                    firstHour=previous.hour,lastHour=p.hour}
                bars[#bars+1]=bar; bucket=key
            end
            bar.high=math.max(bar.high,p.cents); bar.low=math.min(bar.low,p.cents)
            bar.close=p.cents; bar.lastHour=p.hour
        end
    end
    if #bars==0 then self.chartMessage=text("ChartEmpty"); return end
    if self.chartH<self.ch*2+48 then self.chartMessage=text("ChartEnlarge"); return end
    local low,high=math.huge,-math.huge
    for _,bar in ipairs(bars) do low=math.min(low,bar.low); high=math.max(high,bar.high) end
    local pad=math.max(1,(high-low)*0.12); low=math.max(0,low-pad); high=high+pad
    local axis=math.max(getTextManager():MeasureStringX(D.font("caption"),money(low)),
        getTextManager():MeasureStringX(D.font("caption"),money(high)))+16
    self.compactChart=self.chartH<self.ch*3+100
    local headerRows=self.compactChart and 1 or 2
    local plot={x=self.dx+axis,y=self.chartY+self.ch*headerRows+16,
        w=self.dw-axis-12,h=self.chartH-self.ch*(headerRows+1)-24}
    if plot.w<60 then self.chartMessage=text("ChartEnlarge"); return end
    local function priceY(value) return math.floor(plot.y+plot.h-(value-low)/(high-low)*plot.h) end
    local steps=plot.h<self.ch*3 and 1 or 2
    for i=0,steps do
        self.chartGrid[#self.chartGrid+1]={x=plot.x,y=math.floor(plot.y+plot.h*i/steps),w=plot.w,
            label=money(high-(high-low)*i/steps)}
    end
    self.chartLegend=text("ChartLegend",nil,period)
    local latest=bars[#bars]
    self.chartOHLC=text("ChartOHLC",nil,money(latest.open),money(latest.high),money(latest.low),money(latest.close))
    local step=plot.w/#bars; local width=math.max(1,math.min(12,math.floor(step*0.6)))
    for i,bar in ipairs(bars) do
        bar.x=math.floor(plot.x+(i-0.5)*step)
        bar.wickY=priceY(bar.high); bar.wickH=math.max(1,priceY(bar.low)-bar.wickY)
        bar.y=math.min(priceY(bar.open),priceY(bar.close)); bar.h=math.max(1,math.abs(priceY(bar.close)-priceY(bar.open)))
        bar.w=width; bar.color=bar.close>bar.open and "red" or bar.close<bar.open and "accent" or "muted"
        self.candles[#self.candles+1]=bar
    end
    for _,index in ipairs({1,math.ceil(#bars/2),#bars}) do
        local bar=bars[index]
        if #self.chartTimes==0 or self.chartTimes[#self.chartTimes].hour~=bar.lastHour then
            local label=text("ChartTime",nil,bar.lastHour)
            local tw=getTextManager():MeasureStringX(D.font("caption"),label)
            self.chartTimes[#self.chartTimes+1]={hour=bar.lastHour,label=label,
                x=math.max(plot.x,math.min(plot.x+plot.w-tw,bar.x-tw/2)),y=plot.y+plot.h+5}
        end
    end
end
function UI:order()
    if not self.buy then return end
    local news=self.mode=="news"
    local view=C.view; local s=self:stock(); local n=tonumber(self.quantity:getInternalText())
    local enabled=not news and view and view.enabled and not view.updating and not view.overloaded and not view.account.invalid
        and not view.account.unknown and not C.pending and s and not s.suspended
    local buy=enabled and F.quote(s.cents,n,"buy",view.fee) or nil
    local sell=enabled and F.quote(s.cents,n,"sell",view.fee) or nil
    local p=view and view.account.positions and view.account.positions[C.selected]
    self.buy:setEnable(buy~=nil and buy.total<=(view.account.balance or 0))
    self.sell:setEnable(sell~=nil and p~=nil and p.quantity>=n)
    self.orderLines={buy and text("BuyCost",nil,amount(buy.total),amount(buy.fee)) or "",
        sell and text("SellValue",nil,amount(sell.total),amount(sell.fee)) or ""}
    self.quantity:setVisible(not news and not C.pending)
    for _,b in ipairs(self.quick) do b:setVisible(not news) end
    for _,b in ipairs(self.ranges) do b:setVisible(not news) end
    self.buy:setVisible(not news); self.sell:setVisible(not news)
    self.retry:setVisible(not news and C.pending~=nil)
    self.info={balance=text("Balance",nil,amount(view and view.account.balance or 0)),
        status=text(not view and "Loading" or not view.enabled and "StockDisabled" or view.overloaded and "Overloaded"
            or view.updating and "Updating" or view.account.invalid and "StockAccountInvalid" or view.account.unknown and "StockUnknown" or "MarketClock",nil,view and view.hour or 0),
        result=C.result and text(C.result) or text("Hour",nil,view and view.hour or 0)}
    if view and s and not news then
        local a=view.account
        local value=p and F.mulDiv(p.quantity,s.cents,100) or 0
        local net=p and F.quote(s.cents,p.quantity,"sell",view.fee)
        local average=p and p.quantity>0 and p.cost/p.quantity or 0
        self.info.company=name(s.id).."  "..money(s.cents).."  "..industry(F.byId[s.id].industry)
        self.info.profile=s.id.." | "..text("Profile_"..F.byId[s.id].industry)
        self.info.latest=text("NoCompanyNews")
        for i=#(view.news or {}),1,-1 do
            local newsRow=view.news[i]
            if newsRow.id==s.id or newsRow.industry==F.byId[s.id].industry then self.info.latest=self:newsText(newsRow); break end
        end
        self.info.position=text("Position",nil,amount(p and p.quantity or 0),amount(p and p.cost or 0),amount(value or 0),string.format("%.2f",average))
        self.info.profit=text("Profit",nil,amount(p and value and value-p.cost or 0),amount(a.realized),amount(net and net.total or 0))
    end
    local row=self.list.items[self.list.selected]
    self.newsHeading=row and row.item.news and row.item.label or nil
    self.newsLines=D.wrap(row and row.item.news and row.item.body or text("NoNews"),self.dw,"body")
    local schedule=view and view.newsStatus
    local last=view and view.news and view.news[#view.news]
    local status=not view and text("Loading") or not view.enabled and text("NewsPaused")
        or schedule and schedule.limit==0 and text("NewsDisabled")
        or schedule and schedule.nextHour and text("NewsSchedule",nil,schedule.nextHour,math.max(0,schedule.nextHour-view.hour))
        or schedule and schedule.pending and text("NewsSchedulePending")
        or text("NewsTiming")
    self.newsSummary=D.wrap(status.."\n"
        ..(last and text("NewsLatest",nil,last.publishedHour) or text("NewsNonePublished")),self.dw,"caption")
end
function UI:update()
    ISCollapsableWindow.update(self)
    if self.lastW~=self.width or self.lastH~=self.height or self.font~=D.font("body") then
        self.lastW=self.width; self.lastH=self.height; self:layout(); self:rebuild()
    end
    if self.searchDue and now()>=self.searchDue then self.searchDue=nil; self:rebuild() end
    if self.language~=name("tool_01") then self.language=name("tool_01"); self.indices={}; self:rebuild() end
    if C.pending and now()-(C.lastSend or 0)>=5000 then self.retry:setTitle(text("Retry")) end
end
function UI:prerender()
    ISCollapsableWindow.prerender(self)
    local x,w=self.dx,self.dw; local info=self.info or {}
    D.label(self,info.balance or "",x,34,w,"gold","body")
    D.label(self,info.status or "",x,38+self.fh,w,"muted","caption")
    D.label(self,self.mode=="news" and text("NewsDisclaimer") or info.result or "",x,self.height-self.ch-8,w,
        self.mode~="news" and C.result and "gold" or "muted","caption")
    if self.mode=="news" then
        local y=50+self.fh*2
        D.frame(self,x-8,y-8,w+8,#(self.newsSummary or {})*(self.ch+5)+16)
        for _,line in ipairs(self.newsSummary or {}) do
            if y+self.ch<self.height-35 then D.label(self,line,x,y,w,"muted","caption"); y=y+self.ch+5 end
        end
        y=y+24
        if self.newsHeading and y+self.fh<self.height-35 then
            D.label(self,self.newsHeading,x,y,w,"gold","body"); y=y+self.fh+12
        end
        local lines=self.newsLines or {}
        for i=1,#lines do if y+self.fh<self.height-35 then D.label(self,lines[i],x,y,w); y=y+self.fh+6 end end
        return
    end
    D.rect(self,x-8,self.companyY-8,w+8,1,"line")
    D.label(self,info.company or "",x,self.companyY,w,"text","body")
    D.label(self,info.position or "",x,self.positionY,w,"muted","caption")
    D.label(self,info.profit or "",x,self.profitY,w,"muted","caption")
    D.label(self,info.profile or "",x,self.profileY,w,"muted","caption")
    D.label(self,info.latest or "",x,self.latestY,w,"gold","caption")
    D.frame(self,x,self.chartY,w,self.chartH)
    if self.chartMessage then D.label(self,self.chartMessage,x+8,self.chartY+8,w-16,"muted","caption") end
    if self.chartLegend then
        D.label(self,self.chartLegend,x+8,self.chartY+4,w-16,"muted","caption")
        if not self.compactChart then D.label(self,self.chartOHLC,x+8,self.chartY+self.ch+8,w-16,"text","caption") end
    end
    for _,grid in ipairs(self.chartGrid or {}) do
        D.rect(self,grid.x,grid.y,grid.w,1,"line")
        D.label(self,grid.label,x+6,grid.y-self.ch/2,grid.x-x-12,"muted","caption")
    end
    for _,bar in ipairs(self.candles or {}) do
        D.rect(self,bar.x,bar.wickY,1,bar.wickH,bar.color)
        D.rect(self,bar.x-math.floor(bar.w/2),bar.y,bar.w,bar.h,bar.color)
    end
    for _,tick in ipairs(self.chartTimes or {}) do D.label(self,tick.label,tick.x,tick.y,w,"muted","caption") end
    D.frame(self,x-8,self.oy-8,w+8,self.orderRowH+self.bh*2+26)
    if not C.pending then
        D.label(self,text("Shares"),x,self.oy+(self.bh-self.fh)/2,self.quantityLabelW-8,"text","body")
        D.label(self,(self.orderLines or {})[1] or "",x+self.dw*0.3,self.oy,self.dw*0.7,"muted","caption")
        D.label(self,(self.orderLines or {})[2] or "",x+self.dw*0.3,self.oy+self.ch,self.dw*0.7,"muted","caption")
    end
end
function UI:close()
    C.close(); C.onUpdate=nil; C.onReset=nil
    self:setVisible(false); self:removeFromUIManager(); UI.instance=nil
    if GodSystemUI and GodSystemUI.window then GodSystemUI.window:layoutNavigation(true) end
end
function UI.open()
    if UI.instance then GodSystemUISafety.presentOverlay(UI.instance); return UI.instance end
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,h=math.min(1180,sw-24),math.min(820,sh-24)
    local self=UI:new((sw-w)/2,(sh-h)/2,w,h)
    self.mode="market"; self.days=7; self.title=text("Title"); self.backgroundColor=D.copy(D.colors.shell)
    self.minimumWidth=math.min(840,w); self.minimumHeight=math.min(620,h)
    self:initialise(); self:instantiate(); self:setResizable(true)
    UI.instance=self
    C.onUpdate=function() self:rebuild() end
    C.onReset=function() if UI.instance then UI.instance:close() end end
    GodSystemUISafety.presentOverlay(self); C.open()
    return self
end
return UI
