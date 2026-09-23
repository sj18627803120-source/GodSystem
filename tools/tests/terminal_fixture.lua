-- Headless ISUI fixture. Loads real mod view/controllers, records drawing calls.
-- Engine settlement and Java rendering are deliberately outside this fixture.
UIFont={Small="Small",Medium="Medium",Large="Large"}
-- Native B42.20.4 CN/1x bitmap-font line heights; tests also exercise CN/2x and CN/4x.
fixtureFontHeights={Small=19,Medium=29,Large=33}
local fixtureUTF16=#"\228\184\173"==1
function getTextManager() return {
    getFontHeight=function(_,font) return fixtureFontHeights[font] or 19 end,
    MeasureStringX=function(_,font,value)
        local width=0
        local advances=fixtureFontAdvances and fixtureFontAdvances[font]
        local pattern=fixtureUTF16 and "." or "[%z\1-\127\194-\244][\128-\191]*"
        -- Each VM's native string indexing, independently of the UI wrapper.
        for ch in tostring(value or ""):gmatch(pattern) do
            local code=ch:byte()
            if not fixtureUTF16 or code<56320 or code>57343 then
                local wide=fixtureUTF16 and code>255 or not fixtureUTF16 and #ch>1
                width=width+((advances and advances[ch]) or (wide and 1 or .54)*(fixtureFontHeights[font] or 19))
            end
        end
        return width
    end,
} end
screenW,screenH=1920,1080
function getCore() return {getScreenWidth=function() return screenW end,getScreenHeight=function() return screenH end,getOptionFontSizeReal=function() return 1 end} end
function isClient() return false end
function isServer() return false end
function getTimestampMs() return 10000 end
function getTexture(path) return {path=path,getWidth=function() return 32 end,getHeight=function() return 32 end} end
function getText(key) return translations and translations[key] or key end
function getTextOrNull(key) return translations and translations[key] end
function getPlayer() return {getPlayerNum=function() return 0 end,isDead=function() return false end,getUsername=function() return "Survivor" end} end
GameTime={getInstance=function() return {getWorldAgeHours=function() return 20 end} end}
Events=setmetatable({}, {__index=function(t,k) local event={Add=function() end,Remove=function() end}; rawset(t,k,event); return event end})
draws={}; local function origin(ui)
    local x,y=ui.x or 0,ui.y or 0; local p=ui.parent
    while p do x=x+(p.x or 0); y=y+(p.y or 0)+(p.scroll or 0); p=p.parent end
    return x,y+(ui.scroll or 0)
end
ISPanel={}
function ISPanel:derive(name) local cls={Type=name}; cls.__index=cls; setmetatable(cls,{__index=self}); return cls end
function ISPanel:new(x,y,w,h)
    return setmetatable({x=x or 0,y=y or 0,width=w or 100,height=h or 100,children={},visible=true,scroll=0,enable=true,
        backgroundColor={r=0,g=0,b=0,a=1},borderColor={r=1,g=1,b=1,a=1},backgroundColorMouseOver={r=0,g=0,b=0,a=1}},self)
end
function ISPanel:initialise() end
function ISPanel:instantiate() if self.javaObject then return end; self.javaObject={}; if self.createChildren then self:createChildren() end end
function ISPanel:addChild(child) child.parent=self; self.children[#self.children+1]=child; child:instantiate() end
function ISPanel:removeChild(child) for i,c in ipairs(self.children) do if c==child then table.remove(self.children,i); break end end end
function ISPanel:addToUIManager() self:instantiate() end
function ISPanel:removeFromUIManager() self.removed=true end
function ISPanel:bringToTop() end
function ISPanel:setAlwaysOnTop(v) self.alwaysOnTop=v end
function ISPanel:close() self:setVisible(false) end
function ISPanel:setVisible(v) self.visible=v end
function ISPanel:getIsVisible() return self.visible end
function ISPanel:setEnable(v) self.enable=v; self.backgroundColor.a=v and 1 or .5 end
function ISPanel:setTitle(v) self.title=v end
function ISPanel:getTitle() return self.title end
function ISPanel:setName(v) self.name=v end
function ISPanel:setColor(r,g,b,a) self.r,self.g,self.b,self.a=r,g,b,a or 1 end
function ISPanel:setText(v) self.text=v end
function ISPanel:getText() return self.text or "" end
function ISPanel:setOnlyNumbers() end
function ISPanel:setAnchorRight() end
function ISPanel:setAnchorLeft() end
function ISPanel:setAnchorTop() end
function ISPanel:setAnchorBottom() end
function ISPanel:setImage(v) self.image=v end
function ISPanel:setTooltip(v) self.tooltip=v end
function ISPanel:setFont(v) self.font=v end
function ISPanel:setMaxTextLength() end
function ISPanel:focus() end
function ISPanel:unfocus() end
function ISPanel:setCapture() end
function ISPanel:setStencilRect() end
function ISPanel:clearStencilRect() end
function ISPanel:repaintStencilRect() end
function ISPanel:drawRect(x,y,w,h,a,r,g,b) local ox,oy=origin(self); draws[#draws+1]={kind="rect",x=x+ox,y=y+oy,w=w,h=h,a=a,r=r,g=g,b=b,ui=self} end
function ISPanel:drawRectBorder(x,y,w,h,a,r,g,b) local ox,oy=origin(self); draws[#draws+1]={kind="border",x=x+ox,y=y+oy,w=w,h=h,a=a,r=r,g=g,b=b,ui=self} end
function ISPanel:drawText(value,x,y,r,g,b,a,font) local ox,oy=origin(self); draws[#draws+1]={kind="text",value=value,x=x+ox,y=y+oy,r=r,g=g,b=b,a=a,font=font or UIFont.Small,ui=self} end
function ISPanel:drawTextCentre(value,x,y,r,g,b,a,font) self:drawText(value,x-getTextManager():MeasureStringX(font,value)/2,y,r,g,b,a,font) end
function ISPanel:drawTextRight(value,x,y,r,g,b,a,font) self:drawText(value,x-getTextManager():MeasureStringX(font,value),y,r,g,b,a,font) end
function ISPanel:drawTextureScaledAspect(tex,x,y,w,h) self:drawRectBorder(x,y,w,h,.7,.45,.6,.5) end
function ISPanel:drawTexture(tex,x,y) self:drawTextureScaledAspect(tex,x,y,32,32) end
function ISPanel:prerender() end
function ISPanel:render() end
for _,field in ipairs({"X","Y","Width","Height"}) do local f=field:sub(1,1):lower()..field:sub(2); ISPanel["set"..field]=function(self,v) self[f]=v end; ISPanel["get"..field]=function(self) return self[f] end end
function ISPanel:getYScroll() return self.scroll or 0 end
function ISPanel:setYScroll(v) self.scroll=v end
function ISPanel:setScrollHeight(v) self.scrollHeight=v end
function ISPanel:getScrollHeight() return self.scrollHeight or 0 end
ISPanel.__index=ISPanel
ISCollapsableWindow=ISPanel:derive("ISCollapsableWindow")
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:titleBarHeight() return 20 end
function ISCollapsableWindow:resizeWidgetHeight() return 0 end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:onMouseDown(x,y) self.moving=true end
ISButton=ISPanel:derive("ISButton")
function ISButton:new(x,y,w,h,title,target,callback) local o=ISPanel.new(self,x,y,w,h); o.title,o.target,o.onclick=title,target,callback; return o end
function ISButton:prerender()
    local c=self.backgroundColor; self:drawRect(0,0,self.width,self.height,c.a,c.r,c.g,c.b)
    c=self.borderColor; self:drawRectBorder(0,0,self.width,self.height,c.a,c.r,c.g,c.b)
    local font=self.font or UIFont.Small; self:drawTextCentre(self.title or "",self.width/2,(self.height-getTextManager():getFontHeight(font))/2,.85,.88,.83,self.enable and 1 or .4,font)
end
ISLabel=ISPanel:derive("ISLabel")
function ISLabel:new(x,y,h,name,r,g,b,a,font,left) local o=ISPanel.new(self,x,y,1,h); o.name,o.r,o.g,o.b,o.a,o.font=name,r,g,b,a,font; o.originalX=x; return o end
function ISLabel:prerender() self:drawText(self.name or "",0,0,self.r,self.g,self.b,self.a,self.font) end
ISTextEntryBox=ISPanel:derive("ISTextEntryBox")
function ISTextEntryBox:new(value,x,y,w,h) local o=ISPanel.new(self,x,y,w,h); o.text=value; return o end
function ISTextEntryBox:setPlaceholderText(value) self.placeholderText=value end
function ISTextEntryBox:getPlaceholderText() return self.placeholderText end
function ISTextEntryBox:prerender()
    self:drawRect(0,0,self.width,self.height,1,.025,.04,.038); self:drawRectBorder(0,0,self.width,self.height,.5,.3,.4,.35)
    local value=self.text~="" and self.text or self.placeholderText or ""
    local font=self.font or UIFont.Small
    self:drawText(GodSystemUISafety.fitText(value,font,self.width-16),8,8,.8,.85,.8,self.text~="" and 1 or .5,font)
end
ISScrollingListBox=ISPanel:derive("ISScrollingListBox")
function ISScrollingListBox:new(x,y,w,h) local o=ISPanel.new(self,x,y,w,h); o.items={}; o.selected=0; o.itemheight=32; o.vscroll=ISPanel:new(w-16,0,16,h); o.vscroll.updatePos=function() end; return o end
function ISScrollingListBox:addItem(text,item) local row={text=text,item=item,height=self.itemheight,index=#self.items+1}; self.items[#self.items+1]=row; return row end
function ISScrollingListBox:clear() self.items={}; self.selected=0 end
function ISScrollingListBox:setOnMouseDownFunction(target,fn) self.target,self.onmousedown=target,fn end
function ISScrollingListBox:isVScrollBarVisible() return self:getScrollHeight()>self.height end
function ISScrollingListBox:ensureVisible() end
function ISScrollingListBox:updateTooltip() end
function ISScrollingListBox:updateSmoothScrolling() end
function ISScrollingListBox:topOfItem(index) local y=0; for i=1,index-1 do y=y+(self.items[i].height or self.itemheight) end; return y end
function ISScrollingListBox:rowAt(x,y) local total=0; for i,row in ipairs(self.items) do total=total+(row.height or self.itemheight); if y<total then return i end end; return -1 end
function ISScrollingListBox:prerender() local y=0; for i,row in ipairs(self.items) do row.index=i; y=self:doDrawItem(y,row,i%2==0) end; self:setScrollHeight(y) end
ISScrollBar=ISPanel:derive("ISScrollBar")
ISModalDialog=ISCollapsableWindow:derive("ISModalDialog")
function ISModalDialog:new(x,y,w,h,message,yesno,target,callback,num,payload) local o=ISPanel.new(self,x,y,w,h); o.message,o.target,o.callback,o.payload=message,target,callback,payload; return o end
ISContextMenu={get=function() return {addOption=function() return {} end,addSubMenu=function() end} end}
GodSystemPanelKey={isCapturing=function() return false end,getKey=function() return 49 end,getRangeKey=function() return 44 end,getKeyName=function(k) return k==49 and "N" or "Z" end,cancelCapture=function() end}
GodSystemCompanionConfig={isEnabled=function() return true end}
GodSystemPanelKey.registerToggle=function() end
GodSystemPanelKey.registerRangeRecycle=function() end
GodSystemNetwork={isMultiplayer=false}
GodSystemItemCatalog={}
GodSystemShopVariants={getKey=function(ft,sprite) return tostring(ft)..tostring(sprite or "") end}
GodSystemAttributes={getXpPerCoin=function() return 1 end}
GodSystemConfig={Version="42.20_3.7",EnableTasks=true,EnableShop=true,EnableBank=true,EnableEquipment=true,RefreshTaskCost=100,ShopItems={},TaskTemplates={}}
fixtureData={ui={},tasks={},stats={completedTasks=128,failedTasks=2},bank={current=24000,fixedDeposits={},investments={}},history={}}
for i=1,12 do fixtureData.tasks[i]={id="task"..i,title=({"清理周边威胁","收集医疗物资","储备饮用水","巡猎行动"})[(i-1)%4+1],description="完成目标，领取系统币奖励。",type="kill",target=50+i*10,progress=i*3,status=i<7 and "open" or "active",rewardPoints=250+i*80,penaltyPoints=100,limitHours=24,expireHour=40} end
local r={}
GodSystemApp={services={runtime=r}}
function r.text(key,fallback) return (translations and (translations[key] or translations["IGUI_GodSystem_"..key])) or fallback or key end
function r.getData() return fixtureData end
function r.save() fixtureSaved=true end
function r.getBank() return fixtureData.bank end
function r.getBankSummary() return {cash=3680,current=24000,investmentTotal=12000} end
function r.getCurrencyTotal() return 3680 end
function r.getCurrencyDisplayTotal() return 3680 end
function r.getDailyTaskCount() return 12 end
function r.getMaxActiveTasks() return 6 end
function r.getDailyTaskRefreshText() return "08:00" end
function r.getTaskTitle(t) return t.title end
r.getTaskListTitle=r.getTaskTitle
function r.getTaskDisplayProgress(t) return t.progress or 0 end
function r.getTaskListStatusLine(t) return "进行中" end
function r.getTaskStatusText(t) return t.status end
function r.getTaskDetailText(t) return t.description end
function r.getRemainingHours() return 18 end
function r.isTaskComplete() return false end
function r.isTurnInTask() return false end
function r.generateDailyTasks() end
function r.isFeatureEnabled() return true end
function r.isItemConfigAllowed() return true end
function r.getHeadUpNotificationsEnabled() return true end
function r.isRecycleUnlockMode() return true end
function r.getShopLabel(item) return item.name end
function r.getShopPrimaryFullType(item) return item.fullType end
function r.getShopItemUnitPrice(item) return item.price end
function r.getShopRewardText(item) return item.name.." x 1" end
function r.getShopDescription(item) return item.name end
function r.getShopPrimaryCategory() return {key="other",label="物资"} end
function r.getEconomyQuoteDetail() return "" end
function r.getShopGroup() return "other" end
function r.shopItemIsAvailable() return true end
function r.getShopBuyReference(item) return item.id end
function r.getForcedShopItemsList() return {} end
function r.getUnlockedShopItemsList() return GodSystemConfig.ShopItems end
function r.getAutoShopListOnlyCost() return 100 end
function r.getItemDisplayName(ft) return ft end
for i=1,27 do GodSystemConfig.ShopItems[i]={id="shop"..i,name=({"系统修复组件","医疗抽奖券","耐久强化核心","系统自动装填机","十连随机抽奖券","系统车辆修复模块"})[(i-1)%6+1],fullType="GodSystem.SystemRepairKit",price=i*120,items={{fullType="GodSystem.SystemRepairKit",count=1}}} end
function r.getBankLoanSummary() return {creditTotal=10000,creditAvailable=10000,unpaidTotal=0} end
function r.getBankLoanPlans() return {{id="short",kind="single",periods=1,totalInterestRate=.05,dueHours=72}} end
function r.getBankInvestmentProfiles() return {{id="steady",minRate=-.03,maxRate=.05}} end
function r.getBankInvestmentLabel() return "稳健投资" end
function r.getBankInvestmentAccount() return {balance=12000,onlineHours=12,redeemUnlocked=true} end
function r.getBankInvestmentProfile() return {minRate=-.03,maxRate=.05} end
function r.getBankFixedPayout() return 1000 end
function r.getTraitModificationLists() return {{label="灵巧",traitType="Dextrous",price=1500,costPoints=2}},{{label="笨拙",traitType="Clumsy",price=1800,costPoints=2}},0 end
function r.getTraitDetailText(entry) return entry.label.."\n调整此特质需要 "..entry.price.." 系统币。" end
function r.getAttributePerks() return {{id="Strength",perk="Strength",label="力量",group="body",currentLevel=5,maxLevel=10,currentXp=450,maxXp=1000},{id="Axe",perk="Axe",label="斧术",group="combat",currentLevel=3,maxLevel=10,currentXp=200,maxXp=1000}} end
function r.getAttributeQuote() return {xp=100,cost=500,price=500,maxXp=1000} end
function r.getSystemUpgradeInfo(kind) return {id=kind,upgradeType=kind,label=({activeTasks="同时任务上限",dailyTasks="每日任务数量",carryCapacity="基础负重"})[kind] or kind,current=3,maxValue=10,cost=kind=="carryCapacity" and 2000 or 1800,carryStatus={bonus=6,externalBase=8,currentBase=14,finalCarry=22,mode="native",reason="ok"}} end
function r.getCarryCapacityStateText() return r.text("CarryState_Native", "Independent carry active") end
function r.getSystemUpgradeDetailText(kind) local info=r.getSystemUpgradeInfo(kind); return info.label.."\n当前等级 "..info.current.."\n升级费用 "..info.cost end
function r.notify() end
function r.getHomeEntries() return {{kind="home",label="家园",point={x=10000,y=9000,z=0}},{kind="temp",index=1,label="临时传送点",owned=true}} end
function r.getHomeSystem() return {} end
function r.getHomeEntryDetail(entry) return entry.point and "已设定 · 10000, 9000" or "未设定" end
function r.getCompanionData() return {unlocked=true,visible=true} end
GodSystemCompanionConfig.Unlocks={}
GodSystemCompanion={getStateDetail=function() return "已召唤" end,getRows=function() return {{kind="companionNode",id="guard",label="守护",detail="提升机械同伴的守护能力。",unlocked=true,cost=1500,maxed=false}} end}
GodSystemApp.services.rangeRecycle={subscribe=function() return function() end end,getViewModel=function() return {status="idle",stage="verifying",filterReady=true,processed=0,payout=0,filter={activeFullTypes={"Base.Nails"}}} end}
function r.refreshCarryCapacity() end
local loaded={}
local nativeRequire=require
function require(name)
    if loaded[name] then return end
    local client=name=="GodSystem_UI" or name:find("GodSystem_UI_Runtime_",1,true)==1 or name:find("GodSystem_Terminal",1,true)==1 or name=="GodSystem_EquipmentUI" or name=="GodSystem_UITheme" or name=="GodSystem_UISafety" or name=="GodSystem_ShopCatalog" or name=="GodSystem_UIRefresh"
    client=client or name=="GodSystem_ListState" or name=="GodSystem_PageSections" or name=="GodSystem_AutoLoaderUI"
    local shared=name=="GodSystem_TaskOrder"
    if name=="GodSystem_TerminalGuideData" then client=false; shared=true end
    if not client and not shared then return end
    loaded[name]=true
    return assert(loadstring(readSource((client and "client/" or "shared/")..name..".lua"),"@"..name))()
end
GodSystemEquipmentClient={windows={},text=r.text,player=function() return getPlayer() end,busy=function() return false end,candidates=function() return {} end}
GodSystemEquipment={copy=function(t) local c={}; for k,v in pairs(t or {}) do c[k]=v end; return c end}
GodSystemEquipmentItems={}
local record={name="远行者之斧",fullType="Base.Axe",id="equipment1",itemId=123,revision=2,generation=1,durability={condition=8,conditionMax=10},effects={}}
fixtureEquipmentState={ready=true,completedTasks=128,revision=3,config={enabled=true,freezeEnabled=true,token="test",EquipmentFreezeRadius=3,EquipmentFreezeSeconds=2},rows={{slot=1,record=record,present=true,repairCost=200,repairable=true},{slot=2},{slot=3,locked=true,target=200}}}
function GodSystemEquipmentClient.state() return fixtureEquipmentState end
function GodSystemEquipmentClient.request()
    local window=GodSystemEquipmentClient.windows[0]
    if window then window:rebuild(fixtureEquipmentState,GodSystemEquipmentClient.candidates()) end
end
function GodSystemEquipmentClient.candidates() return {{id=124,name="消防斧"},{id=125,name="撬棍"}} end
function GodSystemEquipmentClient.action(player,args) fixtureEquipmentAction=args; return true end
function GodSystemEquipment.weaponKind() return "melee" end
function GodSystemEquipment.supports() return true end
function GodSystemEquipment.level() return 2 end
GodSystemEquipment.Effects={"freeze","impact"}
function GodSystemEquipment.quoteTarget() return {cost=500,baseCost=500,chanceBP=8000,baseChanceBP=8000,boostCost=0,boost=0} end
function GodSystemEquipmentItems.full() return false end
GodSystemEquipmentFreeze={strength=function() return .2 end}
GodSystemEquipmentImpact={rule=function() return {radius=3,targets=6,attacks=8} end,state=function() return {attackCount=3,ready=false} end}
GodSystemAutoLoader={getCapacity=function() return 10000 end,itemId=function() return "loader1" end,findCarriedItem=function() return "loader1" end}
GodSystemAutoLoaderClient={states={},player=getPlayer}
for _,action in ipairs({"startDeposit","manualFill","withdraw"}) do
    GodSystemAutoLoaderClient[action]=function(loader,fullType,amount,playerNum) fixtureAmmoAction={action=action,loader=loader,fullType=fullType,amount=amount,playerNum=playerNum} end
end
function renderTree(ui)
    if not ui:getIsVisible() then return end
    ui:prerender()
    for _,child in ipairs(ui.children or {}) do renderTree(child) end
    ui:render()
end
require "GodSystem_UI"
require "GodSystem_AutoLoaderUI"
