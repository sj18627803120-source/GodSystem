-- Presentation adapter for the existing page/action controllers.
-- Own class overrides only; no global ISUI mutation and no business settlement.
require "GodSystem_TerminalDesign"
require "GodSystem_TerminalList"
require "GodSystem_TerminalManual"
GodSystemTerminalShell=GodSystemTerminalShell or {}
local T,D,P=GodSystemTerminalShell,GodSystemTerminalDesign,GodSystemTerminalPreferences
function T.install()
    if T.installed then return end
    T.installed=true
    local W=GodSystemUIRuntimeEnv.GodSystemWindow
    local old={new=W.new,create=W.createChildren,populate=W.populateList,detail=W.updateDetail,
        add=W.addListItem,addActive=W.addActiveListItem,close=W.close,mode=W.onModeButton,update=W.update,
        primary=W.onPrimaryAction,secondary=W.onSecondaryAction,selected=W.getPayloadId,range=W.populateRangeRecycle}
    local function runtime() return GodSystemApp.services.runtime end
    local function button(owner,title,callback)
        local b=ISButton:new(0,0,100,36,title,owner,callback); b:initialise(); D.style(b); owner:addChild(b); return b
    end
    local function label(owner)
        local l=ISLabel:new(0,0,20,"",1,1,1,1,D.font("caption"),true); l:initialise(); owner:addChild(l); return l
    end
    local function mount(list)
        for _,name in ipairs({"layoutGrid","rowAt","topOfItem","onMouseWheel","prerender","doDrawItem"}) do list[name]=GodSystemTerminalList[name] end
        list.drawBorder=false; list.backgroundColor=D.copy(D.colors.shell); list.grid=false; list.columnsCount=1
    end
    function W:new(x,y,width,height)
        local o=old.new(self,x,y,width,height)
        o.title=""; o.terminalTaskTab="open"; o.uiScale=1; o.taskInfoExpanded=false; o.moreInfoExpanded=true
        o.backgroundColor=D.copy(D.colors.shell); o.borderColor=D.copy(D.colors.line)
        o.terminalPrefs=P.normalize(P.current); o.terminalWidgets={}; o.terminalStatus={}
        return o
    end
    function W:S(value) return math.floor(tonumber(value) or 0) end
    function W:getUIScale() return 1 end
    function W:enforceMinimumSize() self:clampToScreen() end
    function W:setScaledSize() return self.width,self.height,1 end
    function W:onResizeGripMouseDown() return false end
    function W:setupLayoutMetrics()
        local margin=18; self.outerPad=margin; self.gap=12; self.topX=margin; self.topY=math.max(30,self:titleBarHeight()+8)
        self.topW=self.width-margin*2; self.topH=D.height("title")+D.height("caption")+24
        self.footerH=math.max(45,D.height("caption")+22)
        self.headerControlH=math.max(36,D.height("body")+12)
        self.navX=margin; self.navY=self.topY+self.topH+14; self.navW=(self.width<1100 and 150 or 178)
        self.navH=self.height-self.navY-self.footerH; self.navPadding=0; self.navListX=self.navX; self.navListY=self.navY
        self.navListW=self.navW; self.navListH=self.navH; self.navItemH=D.height("body")+23; self.navItemGap=0
        self.navGroupH=29; self.navToolH=self.navItemH; self.navMoreHeaderH=self.navItemH
        self.contentX=self.navX+self.navW+16; self.contentY=self.navY; self.contentW=self.width-self.contentX-margin
        self.contentH=self.height-self.contentY-self.footerH; self.titleBarH=self.headerControlH+12
        self.actionButtonH=math.max(36,D.height("body")+14); self.actionH=self.actionButtonH*2+28
        self.actionY=self.height-self.footerH-self.actionH; self.mainX=self.contentX+14; self.mainY=self.contentY+self.titleBarH+14
        self.bankCardsY=self.mainY; self.bankCardsH=D.height("caption")+D.height("body")+24
        self.bankCardsVisible=self.mode=="bank" and self.actionY-self.mainY-self.bankCardsH-26>=D.height("body")*2+30
        if self.bankCardsVisible then self.mainY=self.mainY+self.bankCardsH+14 end
        self.panelRight=self.width-margin-14; self.detailW=math.max(245,math.floor(self.contentW*.34))
        self.detailX=self.panelRight-self.detailW; self.mainW=self.detailX-self.mainX-18
        self.mainH=math.max(80,self.actionY-self.mainY-12); self.panelTop=self.mainY; self.panelBottom=self.actionY-12
        self.actionX=self.mainX; self.actionRight=self.panelRight; self.actionW=self.actionRight-self.actionX
    end
    function W:createChildren()
        self.terminalBuilding=true; old.create(self); self.terminalBuilding=false
        mount(self.list); mount(self.activeList); mount(self.detailList); self.detailList.compact=true
        self.terminalSettingsButton=button(self,D.text("Settings","Settings"),function(win) win:onModeButton({internal="settings"}) end)
        self.terminalHelpButton=button(self,D.text("ManualShort","Guide"),function(win) win:onModeButton({internal="info"}) end)
        self.terminalOpenTab=button(self,D.text("Available","Available"),function(win) GodSystemPageSections.select(win:getPageSections("tasks"),"tasks"); win.terminalTaskTab="open"; win.selectedTaskList="open"; win:populateList() end)
        self.terminalActiveTab=button(self,D.text("Active","Active"),function(win) GodSystemPageSections.select(win:getPageSections("tasks"),"tasks"); win.terminalTaskTab="active"; win.selectedTaskList="active"; win:populateList() end)
        self.terminalExtensions=button(self,D.text("TaskCapacity","Task capacity"),function(win)
            local section=win:getActivePageSection("tasks")=="tasks" and "taskExtensions" or "tasks"
            GodSystemPageSections.select(win:getPageSections("tasks"),section); win:populateList()
        end)
        self.terminalPageHelp=button(self,"?",function(win) win.terminalManualTopic=win.mode; win:onModeButton({internal="info"}) end)
        self.terminalPageLabel=label(self)
        self.terminalSearch=ISTextEntryBox:new("",0,0,240,34); self.terminalSearch:initialise(); self.terminalSearch:instantiate()
        self.terminalSearch.onTextChange=function(entry) if self.mode=="info" and not self.terminalSearchUpdating then self:populateList() end end
        self:addChild(self.terminalSearch)
        self.terminalFont=button(self,"",function(win)
            local cycle={small="normal",normal="large",large="small"}; win.terminalPrefs.font=cycle[win.terminalPrefs.font]; win:populateList()
        end)
        self.terminalSize=button(self,"",function(win)
            local cycle={auto="compact",compact="standard",standard="wide",wide="large",large="xlarge",xlarge="fullscreen",fullscreen="auto"}; win.terminalPrefs.size=cycle[win.terminalPrefs.size]; win:populateList()
        end)
        self.terminalApply=button(self,D.text("Apply","Apply"),function(win) win:applyTerminalPreferences() end)
        self.terminalReset=button(self,D.text("Reset","Reset"),function(win) win.terminalPrefs={font="normal",size="auto"}; win:applyTerminalPreferences() end)
        self.navigationGroupLabels={core=D.text("Operations","OPERATIONS"),systems=D.text("Growth","GROWTH")}
        for _,tab in ipairs(self.navigationTabs) do
            if tab.id=="tasks" then tab.sections=nil end
            tab.label=D.text("Nav_"..tab.id,tab.label)
        end
        self.moreNavigationTabs={
            {id="history",label=D.text("History","Activity")},
            {id="info",label=D.text("Manual","Field guide")},
            {id="settings",label=D.text("Settings","Settings")},
            {id="shortcuts",label=D.text("Shortcuts","Quick actions"),utility=true},
            {id="itemConfig",label=D.text("ItemConfig","Item manager"),utility=true},
            {id="diagnostics",label=D.text("Diagnostics","Diagnostics"),utility=true},
        }
        self:populateList()
    end
    function W:applyStaticLayout()
        D.bounds(self.navigationList,self.navListX,self.navListY,self.navListW,self.navListH)
        D.bounds(self.pageTitleLabel,self.mainX,self.contentY+12,nil,D.height("body"))
        self.pageTitleLabel.font=D.font("body"); self.pageTitleLabel:setColor(D.colors.text.r,D.colors.text.g,D.colors.text.b)
        for _,key in ipairs({"navTitleLabel","pointsLabel","statsLabel","taskStatusLabel","detailLabel","detailHeaderLabel","openTaskLabel","activeTaskLabel"}) do
            if self[key] then self[key]:setVisible(false) end
        end
        if self.terminalSettingsButton then
            local headerY=self.topY+math.floor((self.topH-self.headerControlH)/2)
            for _,b in ipairs({self.terminalHelpButton,self.terminalSettingsButton}) do
                D.style(b); b.font=D.font("caption")
                b:setTitle(GodSystemUISafety.fitText(b==self.terminalHelpButton and D.text("ManualShort","Guide") or D.text("Settings","Settings"),b.font,96))
            end
            D.bounds(self.terminalSettingsButton,self.width-140,headerY,104,self.headerControlH)
            D.bounds(self.terminalHelpButton,self.width-254,headerY,104,self.headerControlH)
            D.style(self.terminalPageHelp); D.bounds(self.terminalPageHelp,self.panelRight-32,self.contentY+8,32,self.headerControlH)
        end
    end
    function W:applyBaseLayout()
        self:setupLayoutMetrics(); self:applyStaticLayout(); self:hidePageSections()
        D.bounds(self.list,self.mainX,self.mainY,self.mainW,self.mainH)
        D.bounds(self.activeList,self.mainX,self.mainY,self.mainW,self.mainH)
        D.bounds(self.detailList,self.detailX,self.mainY,self.detailW,self.mainH)
        self.list:setVisible(true); self.activeList:setVisible(false); self.detailList:setVisible(true)
        self.list.grid=self.mode=="shop"; self.list.compact=false
        self.list.itemheight=math.max(72,D.height("body")+D.height("caption")+30)
        self.activeList.itemheight=self.list.itemheight+10; self.detailList.itemheight=D.height("body")+9
        for _,key in ipairs({"categoryButton","shopSearchBox","shopSearchLabel","fourthButton","fifthButton","sixthButton","seventhButton"}) do self[key]:setVisible(false) end
    end
    function W:setTaskLayout(enabled)
        if enabled then
            self.list:setVisible(self.terminalTaskTab~="active"); self.activeList:setVisible(self.terminalTaskTab=="active")
            self.selectedTaskList=self.terminalTaskTab=="active" and "active" or "open"
        end
    end
    function W:setShopLayout() end
    function W:setTextPageLayout(enabled)
        if enabled then
            D.bounds(self.list,self.mainX,self.mainY,self.panelRight-self.mainX,self.mainH)
            self.list.compact=true; self.list.itemheight=D.height("body")+12; self.detailList:setVisible(false)
        end
    end
    function W:setActionBar(actions)
        self:hideActionControls(); self.terminalActions=actions or {}
        local x,y=self.actionX,self.actionY+12; local right=self.actionRight; local gap=8
        local count,total=0,0
        for _,entry in ipairs(actions or {}) do
            local c=entry.control or self:getActionControl(entry.id)
            if c and entry.visible~=false and entry.id~="category" and entry.id~="searchBox" and entry.id~="searchLabel" then
                count=count+1; total=total+math.max(88,math.min(200,getTextManager():MeasureStringX(D.font("body"),entry.title or c.fullTitle or c.title or "")+28))
            end
        end
        local columns=(total+math.max(0,count-1)*gap<=self.actionW) and count or math.ceil(count/2)
        local maxWidth=columns>0 and math.floor((self.actionW-(columns-1)*gap)/columns) or 200
        local index=0
        for _,entry in ipairs(actions or {}) do
            local c=entry.control or self:getActionControl(entry.id)
            if c and entry.visible~=false then
                if entry.id=="category" or entry.id=="searchBox" or entry.id=="searchLabel" then
                    D.style(c)
                    if c.Type=="ISTextEntryBox" and c.setFont then c:setFont(D.font("body")) end
                    if entry.id=="searchBox" then
                        c:setPlaceholderText(self.mode=="attribute" and D.text("SearchSkills","Search skills") or D.text("SearchItems","Search items"))
                    end
                    c:setVisible(self.mode=="shop" or self.mode=="attribute")
                    local sx=entry.id=="category" and self.mainX or self.mainX+146
                    D.bounds(c,sx,self.contentY+8,entry.id=="category" and 138 or math.max(70,self.mainW-152),self.headerControlH)
                    if entry.id=="category" then c:setTitle(GodSystemUISafety.fitText(c.fullTitle or c.title,D.font("body"),c.width-16)) end
                else
                    local title=entry.title or c.fullTitle or c.title or ""
                    local width=math.min(maxWidth,math.max(88,math.min(200,getTextManager():MeasureStringX(D.font("body"),title)+28)))
                    if index==columns then x=self.actionX; y=y+self.actionButtonH+8 end
                    width=math.min(width,right-x)
                    c:setVisible(true); D.bounds(c,x,y,width,self.actionButtonH); D.style(c,entry.id=="primary" or c==self.terminalApply)
                    c.fullTitle=title; c:setTitle(GodSystemUISafety.fitText(title,D.font("body"),width-20)); c.tooltip=title
                    x=x+width+gap; index=index+1
                end
            end
        end
    end
    function W:applyShopActionLayout()
        self:setActionBar({{id="category"},{id="searchBox"},{id="primary"},{id="fourth"},{id="fifth"},{id="third",visible=self.thirdButton:getIsVisible()},{id="sixth"},{id="secondary",visible=not (isClient and isClient())}})
    end
    function W:applyRecycleActionLayout() self:setStandardActionBar() end
    function W:layoutNavigation(preserve)
        if not self.navigationList then return end
        local l=self.navigationList; local scroll=preserve and l:getYScroll() or 0
        GodSystemUISafety.clearList(l); local group
        for _,tab in ipairs(self.navigationTabs or {}) do
            if self:isNavigationTabVisible(tab) then
                if group~=tab.group then group=tab.group; local row=l:addItem(self.navigationGroupLabels[group] or "",{kind="navGroup"}); row.height=D.height("caption")+10 end
                local row=l:addItem(tab.label,{kind="navTab",id=tab.id}); row.height=self.navItemH
            end
        end
        for _,tab in ipairs(self.moreNavigationTabs or {}) do
            if not tab.utility then
            local row=l:addItem(tab.label,{kind="navTab",id=tab.id}); row.height=self.navItemH
            end
        end
        local height=0; for _,row in ipairs(l.items) do height=height+row.height end
        l:setScrollHeight(height); l:setYScroll(math.max(-math.max(0,l:getScrollHeight()-l.height),math.min(0,scroll)))
    end
    function W:drawNavigationItem(l,y,row)
        local h=row.height or self.navItemH; local p=row.item or {}; local top=math.max(y,-l:getYScroll()); local bottom=math.min(y+h,l.height-l:getYScroll())
        if bottom<=top then return y+h end
        if p.id==self.mode then D.rect(l,0,top,l.width-16,bottom-top,"selected"); D.rect(l,0,top,2,bottom-top,"accent") end
        local role=p.kind=="navGroup" and "caption" or "body"; local ty=y+math.floor((h-D.height(role))/2)
        if ty>=top and ty+D.height(role)<=bottom then D.label(l,row.text,12,ty,l.width-34,p.kind=="navGroup" and "muted" or p.id==self.mode and "accent" or "text",role) end
        return y+h
    end
    function W:decorateTerminalPayload(text,p)
        local r=runtime(); p=p or {}; p.title=text
        if p.kind=="shop" then
            p.title=r.getShopLabel(p.data); p.texture=D.peekTexture(r.getShopPrimaryFullType(p.data),p.data.worldSprite or (p.data.items and p.data.items[1] and p.data.items[1].worldSprite)); p.subtitle=p.detail
        elseif p.kind=="task" then
            p.objective=D.taskPreview(p.data)
            p.title=r.getTaskTitle(p.data); p.progress=p.data.status=="active" and r.getTaskDisplayProgress(p.data) or nil; p.target=p.data.target
            p.subtitle=D.text("Reward","Reward").."  "..D.number(p.data.rewardPoints).."  /  "..tostring(p.data.limitHours or 24).."h"
            if p.data.status=="active" then p.subtitle=tostring(math.min(p.progress,p.target or 1)).." / "..tostring(p.target).."    "..tostring(r.getRemainingHours(p.data)).."h" end
        elseif p.kind=="bankCurrent" then p.title=D.text("Current","Current account"); p.subtitle=D.number((p.data or {}).current)
        elseif p.kind=="upgrade" then
            local info=p.data or {}
            p.subtitle="Lv. "..tostring(info.current or 0).."  /  "..(info.cost and D.number(info.cost) or r.text("Upgrade_Maxed","Maxed"))
        elseif p.kind=="bankInvestment" then p.title=r.getBankInvestmentLabel((p.profile or {}).id); p.subtitle=D.number((p.data or {}).balance).."  ·  "..r.text((p.data or {}).redeemUnlocked and "Bank_InvestmentRedeemable" or "Bank_InvestmentLocked","")
        end
        return p
    end
    function W:addListItem(text,p)
        p=p or {}
        if p.kind=="shopPager" then self.terminalPager=text; return end
        if p.kind=="bankSummary" or p.kind=="bankLoanSummary" or p.kind=="rangeFilterHint" then return end
        old.add(self,text,self:decorateTerminalPayload(text,p))
    end
    function W:addActiveListItem(text,p) old.addActive(self,text,self:decorateTerminalPayload(text,p)) end
    function W:addWrappedListText(value,payload)
        for _,line in ipairs(D.wrap(value,math.max(80,self.list.width-40),"body")) do
            local p={}; for key,v in pairs(payload or {}) do p[key]=v end
            self:addListItem(line,p)
        end
    end
    function W:populateRangeRecycle()
        old.range(self)
        local model=GodSystemApp.services.rangeRecycle:getViewModel(self.playerNum or 0)
        GodSystemUISafety.clearList(self.list)
        local r=runtime()
        local status=r.text("RangeStatus_"..tostring(model.status or "idle"),tostring(model.status or "idle"))
        self:addListItem(D.text("RecycleState","Recycling"),{kind="rangeStatus",detail=status})
        self:addListItem(D.text("Processed","Processed"),{kind="rangeStatus",detail=tostring(model.processed or 0)})
        self:addListItem(D.text("Payout","Payout"),{kind="rangeStatus",detail=D.number(model.payout)})
        self:addListItem(D.text("Skipped","Skipped"),{kind="rangeStatus",detail=tostring(model.skipped or 0)})
    end
    function W:refreshTerminalStatus()
        local r=runtime(); local data=r.getData(); local bank=data.bank or {}
        -- The title bar does not need fixed-deposit or investment aggregation.  In MP
        -- balance is already projected by the server, so this avoids an inventory scan.
        local summary=self.mode=="bank" and r.getBankSummary and r.getBankSummary() or nil
        self.terminalStatus={cash=(r.getCurrencyDisplayTotal and r.getCurrencyDisplayTotal()) or data.balance or 0,bank=bank.current or 0,investment=summary and summary.investmentTotal or 0,
            completed=(data.stats or {}).completedTasks or 0}
    end
    function W:populateList()
        if self.terminalBuilding then return end
        local perfStart=GodSystemShopCatalog.nowMs()
        GodSystemShopCatalog.note("page."..tostring(self.mode)..".refresh")
        self.terminalPager=nil
        if self.mode=="equipment" then
            self:hideTerminalWidgets(); self:applyBaseLayout(); self:setActionBar({}); self.list:setVisible(false); self.detailList:setVisible(false)
            self:showTerminalEquipment(); self:updateModeButtonStyles(); self:refreshTerminalStatus()
            GodSystemShopCatalog.note("page.equipment.ms",math.max(0,GodSystemShopCatalog.nowMs()-perfStart)); return
        end
        if self.terminalEquipment then self.terminalEquipment:setVisible(false) end
        self:hideTerminalWidgets()
        if self.mode=="info" then self:populateTerminalManual()
        elseif self.mode=="settings" then self:populateTerminalSettings()
        else
            self.terminalDeferDetail=true
            old.populate(self)
            self.terminalDeferDetail=nil
            if self.mode=="tasks" and self:getActivePageSection("tasks")=="tasks" then self:setTaskLayout(true) end
            local selectedList=self.mode=="tasks" and self.selectedTaskList=="active" and self.activeList or self.list
            if not self:getSelectedPayload() then
                for i,row in ipairs(selectedList.items) do
                    if row.item and row.item.selectable~=false then selectedList.selected=i; break end
                end
            end
            self:updateDetail()
        end
        self:refreshTerminalStatus(); self:layoutTerminalExtras()
        for _,list in ipairs({self.list,self.activeList,self.detailList}) do
            for _,row in ipairs(list.items or {}) do row.height=list.itemheight end
        end
        GodSystemShopCatalog.note("page."..tostring(self.mode)..".ms",math.max(0,GodSystemShopCatalog.nowMs()-perfStart))
    end
    function W:hideTerminalWidgets()
        for _,key in ipairs({"terminalOpenTab","terminalActiveTab","terminalExtensions","terminalSearch","terminalFont","terminalSize","terminalApply","terminalReset","terminalPageLabel"}) do
            if self[key] then self[key]:setVisible(false) end
        end
        for _,b in ipairs(self.terminalSettingButtons or {}) do b:setVisible(false) end
    end
    function W:layoutTerminalExtras()
        if not self.terminalOpenTab then return end
        if self.mode=="tasks" then
            local data=runtime().getData() or {}
            local tasks=data.tasks or {}
            local openCount,activeCount=0,0
            for _,task in pairs(tasks) do
                if task.status=="open" then openCount=openCount+1
                elseif task.status=="active" then activeCount=activeCount+1 end
            end
            self.terminalOpenTab.fullTitle=D.text("TaskTabOpen","Available").." "..tostring(openCount)
            local maxActive=runtime().getMaxActiveTasks and runtime().getMaxActiveTasks() or 0
            self.terminalActiveTab.fullTitle=D.text("TaskTabActive","Active").." "..tostring(activeCount).."/"..tostring(maxActive)
            self.terminalExtensions.fullTitle=D.text("TaskCapacity","Task capacity")
            local x=self.mainX
            for _,key in ipairs({"terminalOpenTab","terminalActiveTab","terminalExtensions"}) do
                local b=self[key]; b:setVisible(true); D.bounds(b,x,self.contentY+8,math.min(160,(self.contentW-60)/3),self.headerControlH); D.style(b)
                b.fullTitle=b.fullTitle or b.title; b:setTitle(GodSystemUISafety.fitText(b.fullTitle,D.font("body"),b.width-16))
                x=x+b.width+8
            end
            self.pageTitleLabel:setVisible(false)
            D.style(self.terminalOpenTab,self:getActivePageSection("tasks")=="tasks" and self.terminalTaskTab=="open")
            D.style(self.terminalActiveTab,self:getActivePageSection("tasks")=="tasks" and self.terminalTaskTab=="active")
            D.style(self.terminalExtensions,self:getActivePageSection("tasks")=="taskExtensions")
        elseif self.mode=="shop" then self.pageTitleLabel:setVisible(false)
        else self.pageTitleLabel:setVisible(true) end
        self.terminalPageLabel:setVisible(self.mode=="shop"); self.terminalPageLabel:setName(self.terminalPager or "")
        D.bounds(self.terminalPageLabel,self.mainX,self.height-self.footerH+10,nil,D.height("caption")); self.terminalPageLabel.font=D.font("caption")
    end
    function W:setDetailText(value)
        self.detailText=tostring(value or "")
        if not self.detailList then return end
        GodSystemUISafety.clearList(self.detailList)
        for _,line in ipairs(D.wrap(self.detailText,math.max(80,self.detailList.width-40),"body")) do
            self.detailList:addItem(line,{kind="detailLine",title=line})
        end
        self.detailList.itemheight=D.height("body")+9
        for _,row in ipairs(self.detailList.items) do row.height=self.detailList.itemheight end
    end
    function W:updateDetail()
        if self.terminalDeferDetail then return end
        if self.mode=="equipment" then return end
        if self.mode=="info" then return self:updateTerminalManualArticle() end
        if self.mode=="settings" then
            return self:updateTerminalSettingDetail()
        end
        local p=self:getSelectedPayload()
        self.terminalOwnsDetail=p and (p.kind=="shop" or p.kind=="task" or p.kind=="upgrade" or p.kind=="bankCurrent") or self.mode=="rangeRecycle"
        old.detail(self)
        self.terminalOwnsDetail=nil
        local r=runtime()
        if self.mode=="tasks" then self:setStandardActionBar() end
        if self.mode=="rangeRecycle" then
            local model=GodSystemApp.services.rangeRecycle:getViewModel(self.playerNum or 0); local filter=model.filter or {}
            local fast=filter.mode=="denylist"
            local summary=model.filterReady and r.text(fast and "RangeFilter_ModeFast" or "RangeFilter_ModeSafe",fast and "Quick recycle" or "Safe recycle").."\n"..tostring(#(filter.activeFullTypes or filter.allowedFullTypes or {})).." "..D.text(fast and "ForbiddenTypes" or "AllowedTypes",fast and "excluded types" or "allowed types") or r.text("RangeFilter_Syncing","Syncing")
            if model.radius then summary=summary.."\n\n"..D.text("RecycleRadius","Radius").."  "..tostring(model.radius) end
            if model.status=="running" then summary=summary.."\n"..r.text("RangeStage_"..tostring(model.stage or "verifying"),tostring(model.stage or "")) end
            self:setDetailText(D.text("Filter","Item filter").."\n\n"..summary)
            return
        end
        if not p then self:setDetailText(D.text("SelectEntry","Select an entry")); return end
        if p.kind=="shop" then
            local row=p.data
            local current, cachedQuote
            if p.shopRow then current,cachedQuote=GodSystemShopCatalog.price(p.shopRow) end
            local description=r.getShopDescription(row)
            local inflation = ""
            if r.getShopInflationQuote then
                local quote = cachedQuote or r.getShopInflationQuote(row, 1)
                if quote then
                    inflation = r.text("Shop_InflationInfo", "Base: {1} | Current: {2} | Increase: {3}% | Next expiry: {4} game minutes")
                    local percent = (GodSystemRuntimeConfig.get("ShopDynamicInflationPercent",10) or 10) * quote.layers
                    local values = {quote.basePrice, quote.total, percent, quote.nextExpiryMinute and math.max(0,quote.nextExpiryMinute-quote.onlineMinute) or "-"}
                    for i=1,4 do inflation = string.gsub(inflation,"{"..i.."}",tostring(values[i])) end
                    inflation = "\n\n"..inflation
                end
            end
            self:setDetailText(r.getShopLabel(row).."\n\n"..D.text("Price","Price").."  "..D.number(current or r.getShopItemUnitPrice(row))
                ..inflation..(description and description~="" and "\n\n"..description or "").."\n\n"..r.getShopRewardText(row))
        elseif p.kind=="task" then
            local task=p.data
            local description=r.getTaskDescription and r.getTaskDescription(task) or task.description or ""
            local rewards=r.getRewardText and r.getRewardText(task.rewardPoints,task.rewardItems) or D.number(task.rewardPoints)
            self:setDetailText(r.getTaskTitle(task).."\n\n"..description.."\n\n"..D.text("Target","Target").."  "..tostring(task.target or 1).."\n"..D.text("TimeLimit","Time limit").."  "..tostring(task.limitHours or GodSystemConfig.DefaultTaskLimitHours or 24).."h\n\n"..D.text("Reward","Reward").."\n"..rewards.."\n\n"..D.text("FailureCost","Failure penalty").."  "..D.number(task.penaltyPoints))
        elseif p.kind=="upgrade" then
            local info=p.data or {}; local extra=""
            if info.carryStatus then
                extra="\n"..D.text("CarryLimit","Carrying capacity").."  "..tostring(info.carryStatus.finalCarry or "-")
                if r.getCarryCapacityStateText then extra=extra.."\n"..r.getCarryCapacityStateText(info.carryStatus) end
            end
            self:setDetailText(tostring(info.label or "").."\n\nLv. "..tostring(info.current or 0).."\n"..D.text("Price","Price").."  "..(info.cost and D.number(info.cost) or r.text("Upgrade_Maxed","Maxed"))..extra)
        elseif p.kind=="bankCurrent" then
            local s=r.getBankSummary(); local loan=r.getBankLoanSummary and r.getBankLoanSummary() or {}
            self:setDetailText(D.text("Current","Current account").."\n\n"..D.text("Balance","Balance").."  "..D.number(s.current).."\n"..D.text("DeathPenalty","Death penalty preview").."  "..D.number(s.deathPenalty).."\n\n"..D.text("Credit","Available credit").."  "..D.number(loan.creditAvailable).."\n"..D.text("Debt","Outstanding debt").."  "..D.number(loan.unpaidTotal))
        end
    end
    function W:getPayloadId(p)
        if p and p.kind=="manual" then return "manual:"..p.id end
        return old.selected(self,p)
    end
    function W:onModeButton(b)
        if b.internal=="equipment" then
            if GodSystemPanelKey.isCapturing() then GodSystemPanelKey.cancelCapture("pageChanged") end
            local tab=self:navigationTabById("equipment"); if tab and self:isNavigationTabVisible(tab) then self.mode="equipment"; self:populateList() end
            return
        end
        return old.mode(self,b)
    end
    function W:recordInfoSecretClick() end
    function W:prerender()
        ISCollapsableWindow.prerender(self)
        if self.isCollapsed then return end
        local titleH=self:titleBarHeight()
        D.rect(self,0,titleH,self.width,self.height-titleH,"shell"); D.border(self,0,titleH,self.width,self.height-titleH)
        -- Static, inexpensive metal seams; no animated noise or background scans.
        for i=1,4 do D.rect(self,18,29+i*2,self.width-36,1,{r=.10,g=.13,b=.12,a=.14}) end
        local brandY=self.topY+8
        D.label(self,"GOD SYSTEM",30,brandY,math.min(260,self.width*.25),"text","title")
        D.label(self,D.text("Subtitle","SURVIVE / GROW / ENDURE"),31,brandY+D.height("title")+6,255,"muted","caption")
        local s=self.terminalStatus or {}; local x=math.max(290,math.floor(self.width*.28)); local width=math.max(92,math.floor((self.width-x-270)/2))
        D.label(self,D.text("Wallet","Carried currency"),x,brandY,width-12,"muted","caption"); D.label(self,D.number(s.cash),x,brandY+D.height("caption")+6,width-12,"gold","body")
        D.label(self,D.text("Current","Current account"),x+width,brandY,width-12,"muted","caption"); D.label(self,D.number(s.bank),x+width,brandY+D.height("caption")+6,width-12,"accent","body")
        D.rect(self,18,self.navY-8,self.width-36,1,"line")
        D.frame(self,self.navX,self.navY,self.navW,self.navH)
        D.frame(self,self.contentX,self.contentY,self.contentW,self.contentH)
        if self.mode~="equipment" and self.mode~="info" then D.rect(self,self.mainX,self.actionY-2,self.actionW,1,"line") end
        if self.detailList and self.detailList:getIsVisible() then D.rect(self,self.detailList.x-9,self.detailList.y,1,self.detailList.height,"line") end
        if self.bankCardsVisible then
            local labels={D.text("Wallet","Cash"),D.text("Current","Current"),D.text("Investments","Investments")}; local values={s.cash,s.bank,s.investment}
            local width=math.floor((self.actionW-20)/3)
            for i=1,3 do local cx=self.mainX+(i-1)*(width+10); D.frame(self,cx,self.bankCardsY,width,self.bankCardsH)
                D.label(self,labels[i],cx+12,self.bankCardsY+8,width-24,"muted","caption"); D.label(self,D.number(values[i]),cx+12,self.bankCardsY+D.height("caption")+14,width-24,i==3 and "gold" or "accent") end
        end
        D.label(self,"GS  /  "..tostring(GodSystemConfig.Version),self.navX,self.height-self.footerH+10,self.navW,"muted","caption")
        if self.mode~="shop" then D.label(self,D.text("Footer","A new day. A little stronger."),self.width-345,self.height-self.footerH+10,310,"muted","caption") end
    end
    function W:relayoutIfNeeded() end
    function W:update()
        if not self.getIsVisible or not self:getIsVisible() then return end
        if old.update then old.update(self) end
        GodSystemShopCatalog.flushDiagnostics()
        local now=(getTimestampMs and getTimestampMs() or math.floor(((os and os.clock and os.clock()) or 0)*1000))
        if GodSystemUIRefresh then GodSystemUIRefresh.flush(self) end
        if not self.terminalStatusAt or now-self.terminalStatusAt>=750 then
            self.terminalStatusAt=now; self:refreshTerminalStatus()
        end
        if self.mode=="tasks" and (not self.terminalTasksAt or now-self.terminalTasksAt>=750) then
            self.terminalTasksAt=now
            local tasks={}
            for _,task in ipairs(runtime().getData().tasks or {}) do if task.taskId then tasks[task.taskId]=task end end
            for _,list in ipairs({self.list,self.activeList}) do
                for _,entry in ipairs(list.items or {}) do
                    local p=entry.item
                    if p and p.kind=="task" then
                        p.data=tasks[p.data.taskId] or p.data
                        self:decorateTerminalPayload(entry.text,p)
                    end
                end
            end
        end
        if self.mode=="shop" and self.getIsVisible and self:getIsVisible() then
            local completed=GodSystemShopCatalog and GodSystemShopCatalog.step and GodSystemShopCatalog.step(50,2)
            local now=(getTimestampMs and getTimestampMs() or math.floor(((os and os.clock and os.clock()) or 0)*1000))
            if self.shopSearchDueMs and now>=self.shopSearchDueMs then self.shopSearchDueMs=nil; self:populateList()
            elseif completed then self:populateList()
            elseif GodSystemShopCatalog and GodSystemShopCatalog.isBuilding and GodSystemShopCatalog.isBuilding() and (not self.terminalShopProgressAt or now-self.terminalShopProgressAt>=150) then
                self.terminalShopProgressAt=now; self:populateList()
            end
            D.resolvePageIcons(self.list.items)
            if not GodSystemShopCatalog.isBuilding() and (not self.terminalPricesAt or now-self.terminalPricesAt>=1000) then
                self.terminalPricesAt=now
                for _,entry in ipairs(self.list.items or {}) do
                    local payload=entry.item
                    if payload and payload.shopRow then
                        local price=GodSystemShopCatalog.price(payload.shopRow)
                        payload.detail=tostring(price)..runtime().text("Unit_Coin", " coins"); payload.subtitle=payload.detail
                    end
                end
                self:updateDetail()
            end
        elseif GodSystemShopCatalog and GodSystemShopCatalog.isBuilding() then
            GodSystemShopCatalog.cancelBuild()
        end
        if not GodSystemScheduler or not self.getSelectedPayload then return end
        local p=self:getSelectedPayload()
        if p and p.kind=="upgrade" and p.data and p.data.carryStatus
            and GodSystemScheduler.due("client.carry.detail",1000) then
            p.data.carryStatus=GodSystemCarryCapacity.getStatus(getSpecificPlayer(self.playerNum or 0),p.data.current or 0)
            self:updateDetail()
        end
    end
    function W:relayoutVisiblePage()
        local actions=self.terminalActions
        local detailScroll=self.detailList and self.detailList:getYScroll() or 0
        self:applyBaseLayout()
        self:setTaskLayout(self.mode=="tasks" and self:getActivePageSection("tasks")=="tasks")
        self:setShopLayout(self.mode=="shop" or self.mode=="attribute")
        self:setTextPageLayout(self.mode=="settings" or self.mode=="history" or self.mode=="info" or self.mode=="diagnostics")
        self:setActionBar(actions)
        self:layoutTerminalExtras()
        if self.mode=="equipment" and self.terminalEquipment then
            self.list:setVisible(false); self.detailList:setVisible(false); self:showTerminalEquipment()
        end
        self:setDetailText(self.detailText or "")
        if self.detailList then self.detailList:setYScroll(detailScroll) end
    end
    function W:close()
        local r=runtime()
        if self.mode=="shop" and r.setShopViewPreference then
            local p=self:getSelectedPayload()
            local key=p and p.kind=="shop" and r.shopPreferenceKey(p.data) or nil
            r.setShopViewPreference(self.shopCategoryKey,self.shopSearchText,key)
            if not (GodSystemNetwork and GodSystemNetwork.isMultiplayer) then r.save() end
        end
        if GodSystemShopCatalog and GodSystemShopCatalog.cancelBuild then GodSystemShopCatalog.cancelBuild() end
        if self.terminalEquipment then
            self.terminalEquipment:close()
            if GodSystemEquipmentClient.windows[self.playerNum or 0]==self.terminalEquipment then GodSystemEquipmentClient.windows[self.playerNum or 0]=nil end
        end
        return old.close(self)
    end
    function GodSystemUI.toggleWindow()
        if GodSystemUI.window then GodSystemUI.window:close(); return end
        P.load(); D.applyTheme()
        local core=getCore(); local w,h=P.dimensions(core:getScreenWidth(),core:getScreenHeight())
        local window=W:new(math.floor((core:getScreenWidth()-w)/2),math.floor((core:getScreenHeight()-h)/2),w,h)
        GodSystemUI.window=window; window:initialise(); GodSystemUI.presentMain(window)
    end
    GodSystemTerminalManual.install(W)
end
return T
