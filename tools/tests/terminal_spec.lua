assert(loadstring(readFixture("terminal_fixture.lua")))()
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS terminal: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local D,P=GodSystemTerminalDesign,GodSystemTerminalPreferences
local function click(button) assert(button:getIsVisible(),"hidden action"); button.onclick(button.target,button) end
local modes={"tasks","shop","bank","equipment","home","traits","attribute","upgrades","companion","rangeRecycle","info","settings","history","diagnostics"}
GodSystemUI.toggleWindow()
local w=GodSystemUI.window
-- Production builds incrementally while the terminal is visible.  Advance the
-- fixture worker once so layout assertions exercise the completed snapshot.
while GodSystemShopCatalog and GodSystemShopCatalog.isBuilding and GodSystemShopCatalog.isBuilding() do GodSystemShopCatalog.step(50,999) end
if w.mode=="shop" then w:populateList() end
local nativeOpenMode=GodSystemUI.openMode
GodSystemUI.openMode=function(mode,...)
    local result=nativeOpenMode(mode,...)
    if mode=="shop" then
        while GodSystemShopCatalog and GodSystemShopCatalog.isBuilding and GodSystemShopCatalog.isBuilding() do GodSystemShopCatalog.step(50,999) end
        if GodSystemUI.window then GodSystemUI.window:populateList() end
    end
    return result
end
test("all pages draw at supported screen sizes and each native font preset",function()
    for _,screen in ipairs({{1280,720},{1366,768},{1920,1080},{2560,1440}}) do
        screenW,screenH=screen[1],screen[2]
        for _,font in ipairs({"small","normal","large"}) do
            w.terminalPrefs={font=font,size="auto"}; w:applyTerminalPreferences()
            assert(w.x>=0 and w.y>=0 and w.x+w.width<=screenW and w.y+w.height<=screenH)
            for _,mode in ipairs(modes) do
                GodSystemUI.openMode(mode); draws={}; renderTree(w)
                GodSystemListState.onTick()
                if w.list:getIsVisible() then assert(w.list.y+w.list.height<=w.actionY or mode=="info",mode.." list overlaps action area") end
                for _,entry in ipairs(w.terminalActions or {}) do
                    local b=entry.control or w:getActionControl(entry.id)
                    if b and entry.visible~=false and entry.id~="searchLabel" then
                        assert(b:getIsVisible(),mode.." action hidden: "..tostring(entry.id or b.title))
                        assert(b.x>=0 and b.y>=0 and b.x+b.width<=w.width and b.y+b.height<=w.height,mode.." action outside window")
                        if b.Type=="ISButton" then
                            assert(getTextManager():getFontHeight(b.font)<=b.height,mode.." action font too tall")
                            assert(getTextManager():MeasureStringX(b.font,b.title)<=b.width,mode.." action text too wide")
                        end
                    end
                end
                for _,d in ipairs(draws) do
                    if d.ui==w.list or d.ui==w.activeList or d.ui==w.detailList or (w.terminalEquipment and d.ui==w.terminalEquipment.attributes) then
                        local l=d.ui; local px,py=l.x,l.y; local parent=l.parent
                        while parent do px=px+parent.x; py=py+parent.y; parent=parent.parent end
                        assert(d.x>=px-.1 and d.y>=py-.1,mode.." list draw before viewport")
                        local height=d.kind=="text" and getTextManager():getFontHeight(d.font) or d.h
                        local width=d.kind=="text" and getTextManager():MeasureStringX(d.font,d.value) or d.w
                        assert(d.y+height<=py+l.height+.1,mode.." list draw below viewport")
                        assert(d.x+width<=px+l.width+.1,mode.." list draw beyond width")
                    end
                end
            end
        end
    end
end)
test("settings buttons cycle, apply and reset preferences without changing key bindings",function()
    w.terminalPrefs={font="normal",size="auto"}; w:applyTerminalPreferences(); GodSystemUI.openMode("settings")
    local oldHeight=w.height
    click(w.primaryButton); eq(w.terminalPrefs.font,"large"); eq(P.current.font,"normal"); eq(w.height,oldHeight)
    assert(w.detailText:find(D.text("PendingDisplay","Pending apply"),1,true))
    click(w.terminalApply); eq(P.current.font,"large"); eq(fixtureData.ui.terminal.font,"large")
    w.list.selected=2; w:updateDetail(); click(w.primaryButton); eq(w.terminalPrefs.size,"compact")
    click(w.terminalApply); eq(w.width,1100); eq(w.height,680); eq(w:getSelectedPayload().target,"size")
    click(w.secondaryButton); eq(w.terminalPrefs.size,"auto"); eq(P.current.size,"compact")
    click(w.terminalReset); eq(P.current.font,"normal"); eq(P.current.size,"auto")
end)
test("large, extra-large and fullscreen terminal sizes clamp safely",function()
    screenW,screenH=2560,1440
    local dimensions={large={1700,1000},xlarge={1920,1080},fullscreen={2536,1416}}
    for size,expected in pairs(dimensions) do
        w.terminalPrefs={font="normal",size=size}; w:applyTerminalPreferences()
        eq(w.width,expected[1],size.." width"); eq(w.height,expected[2],size.." height")
        assert(w.x>=0 and w.y>=0 and w.x+w.width<=screenW and w.y+w.height<=screenH)
    end
    screenW,screenH=1280,720
    for _,size in ipairs({"large","xlarge","fullscreen"}) do
        local width,height=P.dimensions(screenW,screenH,{font="large",size=size})
        eq(width,1256,size.." clamp width"); eq(height,696,size.." clamp height")
    end
    eq(P.normalize({font="normal",size="fullscreen"}).size,"fullscreen")
    screenW,screenH=1920,1080; w.terminalPrefs={font="normal",size="auto"}; w:applyTerminalPreferences()
end)
test("font setting reports the terminal native pixel height",function()
    GodSystemUI.openMode("settings")
    for _,font in ipairs({"small","normal","large"}) do
        w.terminalPrefs={font=font,size="auto"}; w:populateList()
        local row=w.list.items[1].item
        assert(row.subtitle:find(tostring(P.fontPixelHeight(w.terminalPrefs)).."px",1,true))
    end
end)
test("display settings persist and survive reopen",function()
    screenW,screenH=1366,768; w.terminalPrefs={font="large",size="wide"}; w:applyTerminalPreferences()
    eq(fixtureData.ui.terminal.font,"large"); assert(fixtureSaved); eq(w.width,1342); eq(w.height,744)
    GodSystemUI.toggleWindow(); eq(GodSystemUI.window,nil); GodSystemUI.toggleWindow(); w=GodSystemUI.window
    eq(w.terminalPrefs.font,"large"); eq(w.width,1342)
    eq(P.normalize({font="invalid",size="broken"}).font,"normal")
end)
test("task tabs select the visible list and extension tab returns to tasks",function()
    GodSystemUI.openMode("tasks"); click(w.terminalActiveTab)
    eq(w.selectedTaskList,"active"); eq(w.list.visible,false); eq(w.activeList.visible,true)
    assert(w:getSelectedPayload().data.status=="active")
    click(w.terminalExtensions); eq(w:getActivePageSection("tasks"),"taskExtensions")
    click(w.terminalOpenTab); eq(w:getActivePageSection("tasks"),"tasks"); eq(w.selectedTaskList,"open")
    assert(w:getSelectedPayload().data.status=="open")
end)
test("task tabs display open and active capacity counts",function()
    GodSystemUI.openMode("tasks")
    eq(w.terminalOpenTab.fullTitle,D.text("TaskTabOpen","Available").." 6")
    eq(w.terminalActiveTab.fullTitle,D.text("TaskTabActive","Active").." 6/6")
    fixtureData.tasks[1].status="active"; w:populateList()
    eq(w.terminalOpenTab.fullTitle,D.text("TaskTabOpen","Available").." 5")
    eq(w.terminalActiveTab.fullTitle,D.text("TaskTabActive","Active").." 7/6")
    fixtureData.tasks[1].status="open"; w:populateList()
end)
test("shop grid hit testing matches drawn tiles through scrolling and resizing",function()
    GodSystemUI.openMode("shop"); local l=w.list
    for _,width in ipairs({280,420,650}) do
        l:setWidth(width); l:layoutGrid(); l:prerender()
        for i=1,#l.items do
            local col=(i-1)%l.columnsCount; local row=math.floor((i-1)/l.columnsCount)
            eq(l:rowAt(col*l.tileWidth+10,row*l.tileHeight+10),i)
        end
        eq(l:rowAt(-1,0),-1); eq(l:rowAt(l.width+10,10),-1)
        l:setYScroll(-72.5); draws={}; l:prerender()
        assert(#draws<#l.items*10,"offscreen tiles rendered")
    end
end)
test("manual searches item names and body text, keeps stable selection and contextual links",function()
    local articles=GodSystemTerminalManual.search("GodSystem.SystemRepairKit"); eq(#articles,1)
    eq(articles[1].fullType,"GodSystem.SystemRepairKit")
    eq(#GodSystemTerminalManual.search("no_such_item_zzz"),0)
    local itemCount=0; for _,a in ipairs(GodSystemTerminalGuideData) do if a.fullType then itemCount=itemCount+1 end end; eq(itemCount,19)
    GodSystemUI.openMode("equipment"); click(w.terminalPageHelp); eq(w.mode,"info"); eq(w.terminalManualId,"equipment")
    w:populateList(); eq(w.terminalManualId,"equipment")
    GodSystemUI.openMode("rangeRecycle"); click(w.terminalPageHelp); eq(w.terminalManualId,"recycle")
    w.terminalSearch:setText("GodSystem.SystemRepairKit"); w.terminalSearch.onTextChange(w.terminalSearch)
    eq(#w.list.items,1); eq(w:getSelectedPayload().article.fullType,"GodSystem.SystemRepairKit")
end)
test("equipment keeps exact identity/quote and confirmation boundary inside terminal",function()
    GodSystemUI.openMode("equipment"); local e=w.terminalEquipment
    eq(GodSystemEquipmentClient.windows[0],e); eq(e.parent,w)
    e:onMouseDown(10,10); eq(e.moving,false); eq(e.drawFrame,false); eq(e.clearStentil,false)
    e:onAttribute({attribute="impact"}); eq(e.attributes.items[e.attributes.selected].item.attribute,"impact")
    local nextInfo=false
    for _,row in ipairs(e.details.items) do if row.text:find("8",1,true) and row.text:find("3",1,true) then nextInfo=true end end
    assert(nextInfo,"next effect level details lost")
    local args=e:makeArgs("enhance"); eq(args.equipmentId,"equipment1"); eq(args.generation,1); eq(args.revision,3); eq(args.configToken,"test")
    e:onAction(e.enhance); assert(e.confirmation); eq(fixtureEquipmentAction,nil)
    e.confirmation.callback(e,{internal="YES"},e.confirmation.payload)
    eq(fixtureEquipmentAction.action,"enhance"); eq(fixtureEquipmentAction.cost,500)
    GodSystemUI.openMode("shop"); eq(e.visible,false)
    GodSystemUI.openMode("equipment"); eq(w.terminalEquipment,e)
end)
test("compact screens preserve readable equipment lists and all actions with enlarged game fonts",function()
    local oldHeights,oldAdvances=fixtureFontHeights,fixtureFontAdvances
    fixtureFontAdvances=nil
    for _,heights in ipairs({{Small=26,Medium=33,Large=40},{Small=38,Medium=45,Large=50}}) do
        fixtureFontHeights=heights; screenW,screenH=1280,720
        w.terminalPrefs={font="large",size="auto"}; w:applyTerminalPreferences()
        for _,mode in ipairs({"bank","settings","equipment"}) do
            GodSystemUI.openMode(mode); draws={}; renderTree(w)
            if mode=="equipment" then
                local e=w.terminalEquipment
                for _,l in ipairs({e.slots,e.candidates,e.details,e.attributes}) do
                    assert(l.height>=D.height("body")+14,"equipment list cannot show a complete line")
                    assert(l.y+l.height<=e.bind.y,"equipment list overlaps bottom actions")
                end
                for _,key in ipairs({"bind","enhance","repair","rename","retrieve","unbind","boost"}) do
                    local c=e[key]; assert(c.y+c.height<=e.height and c.x+c.width<=e.width,key.." outside equipment")
                end
            else
                assert(w.list.y+w.list.height<=w.actionY,mode.." list overlaps actions at game font scale")
            end
        end
    end
    fixtureFontHeights,fixtureFontAdvances=oldHeights,oldAdvances
    screenW,screenH=1920,1080; w.terminalPrefs={font="normal",size="auto"}; w:applyTerminalPreferences()
end)
test("auto-loader preserves inventory commands, selected ammo and amount clamps",function()
    local a=GodSystemAutoLoaderUI.open("loader1",0)
    local state={total=100,capacity=10000,ammo={{fullType="Base.Bullets9mm",name="9mm",available=true,count=100,capacity=10000}}}
    a:rebuild(state); a.list.selected=1; a:onSelection()
    click(a.depositButton); eq(fixtureAmmoAction.action,"startDeposit"); eq(fixtureAmmoAction.loader,"loader1")
    click(a.fillButton); eq(fixtureAmmoAction.action,"manualFill")
    a.amountEntry:setText("9999"); click(a.withdrawButton)
    eq(fixtureAmmoAction.action,"withdraw"); eq(fixtureAmmoAction.amount,500); eq(fixtureAmmoAction.fullType,"Base.Bullets9mm")
    a.list:setYScroll(-400); a:rebuild(state); eq(a.list.selected,1); eq(a.list:getYScroll(),0)
    for _,font in ipairs({"small","normal","large"}) do
        w.terminalPrefs={font=font,size="auto"}; w:applyTerminalPreferences()
        eq(a.amountEntry.font,D.font("body")); assert(a.list.y+a.list.height<a.depositButton.y)
        draws={}; renderTree(a)
        for _,b in ipairs({a.depositButton,a.fillButton,a.withdrawButton}) do
            assert(getTextManager():MeasureStringX(b.font,b.title)<=b.width and D.height("body")<b.height)
        end
    end
    a:close()
end)
test("task details retain rewards, target and failure costs",function()
    local runtime=GodSystemApp.services.runtime; local original=runtime.getRewardText
    runtime.getRewardText=function() return "reward-item-regression" end
    GodSystemUI.openMode("tasks"); click(w.terminalOpenTab)
    local task=w:getSelectedPayload().data
    assert(w.detailText:find("reward-item-regression",1,true))
    assert(w.detailText:find(tostring(task.target),1,true)); assert(w.detailText:find(tostring(task.penaltyPoints),1,true))
    runtime.getRewardText=original
end)
test("recycle summary distinguishes allowed and forbidden lists",function()
    local service=GodSystemApp.services.rangeRecycle; local original=service.getViewModel
    service.getViewModel=function() return {status="idle",filterReady=true,radius=7,filter={mode="denylist",activeFullTypes={"Base.Nails"}}} end
    GodSystemUI.openMode("rangeRecycle")
    assert(w.detailText:find(D.text("ForbiddenTypes","excluded types"),1,true))
    assert(w.detailText:find("7",1,true))
    service.getViewModel=original
end)
test("feedback: full Chinese detail survives wrapping across pages, widths and font sizes",function()
    local runtime=GodSystemApp.services.runtime
    local oldDescription=runtime.getShopDescription
    local description="物品说明：用于修理随身装备，使用前确认物品状态。"
    runtime.getShopDescription=function() return description end
    for _,screen in ipairs({{1280,720},{1920,1080}}) do
        screenW,screenH=screen[1],screen[2]
        for _,font in ipairs({"small","normal","large"}) do
            w.terminalPrefs={font=font,size="auto"}; w:applyTerminalPreferences()
            for _,mode in ipairs({"tasks","shop","home","traits","upgrades","info"}) do
                GodSystemUI.openMode(mode)
                local lines={}; for _,row in ipairs(w.detailList.items) do lines[#lines+1]=row.text end
                eq(table.concat(lines,""),w.detailText:gsub("\n",""))
                if mode=="shop" then assert(table.concat(lines,""):find(description,1,true),"shop description lost") end
            end
        end
    end
    runtime.getShopDescription=oldDescription
end)

test("feedback: equipment effect labels and activity text retain their Chinese",function()
    translations=translations or {}
    translations.Equipment_FreezeAttributeRow="冰霜 Lv{1} | 减速 {2}% | 半径 {3} 格 | {4} 秒"
    translations.Equipment_ImpactAttributeRow="冲击 Lv{1} | 蓄力 {2} | 半径 {3} 格 | 最多 {4} 只"
    GodSystemUI.openMode("equipment")
    local texts={}; for _,row in ipairs(w.terminalEquipment.attributes.items) do texts[#texts+1]=row.text end
    local text=table.concat(texts,"")
    for _,label in ipairs({"冰霜","减速","半径","冲击","蓄力","最多"}) do assert(text:find(label,1,true),label.." lost") end
    local original=w.formatHistoryEntry
    local activity="武器找回 -195\n技能升级 7 -> 8 -70\n任务完成 +110"
    w.formatHistoryEntry=function() return activity end; fixtureData.history={{kind="test"}}
    GodSystemUI.openMode("history")
    texts={}; for _,row in ipairs(w.list.items) do texts[#texts+1]=row.text end
    eq(table.concat(texts,""),activity:gsub("\n",""))
    w.formatHistoryEntry=original; fixtureData.history={}
end)

test("rendering never quotes, creates items or reads inventory",function()
    GodSystemUI.openMode("shop")
    local original=GodSystemApp.services.runtime.getBankSummary
    GodSystemApp.services.runtime.getBankSummary=function() error("render inventory read") end
    local quote=GodSystemEquipment.quoteTarget; GodSystemEquipment.quoteTarget=function() error("render quote") end
    instanceItem=function() error("render item creation") end
    draws={}; renderTree(w)
    GodSystemApp.services.runtime.getBankSummary=original; GodSystemEquipment.quoteTarget=quote; instanceItem=nil
end)
test("native enable mutation cannot change theme palette",function()
    local b=ISButton:new(0,0,100,38,"test"); D.style(b,true); b:setEnable(false)
    eq(D.colors.selected.a,.98); eq(GodSystemUITheme.colors.button.a,.98)
end)
test("3.9 death protection row keeps selection and purchases on the growth page",function()
    local original=GodSystemDeathProtection
    local count=2
    GodSystemDeathProtection={count=function()return count end,cost=function()return 20000 end,buy=function()count=count+1;return true end}
    GodSystemUI.openMode("upgrades")
    local index
    for i,row in ipairs(w.list.items) do if row.item.kind=="deathProtection" then index=i end end
    assert(index,"missing protection row")
    w.list.selected=index;w:updateDetail()
    eq(w:getPayloadId(w:getSelectedPayload()),"deathProtection")
    w:onPrimaryAction();eq(count,3)
    eq(w:getSelectedPayload().kind,"deathProtection")
    draws={};renderTree(w)
    GodSystemDeathProtection=original
end)
test("audit: visible page resolves two icons per update and never creates items",function()
    local r=GodSystemApp.services.runtime
    local originalPrimary=r.getShopPrimaryFullType
    local originalBridge,originalManager,originalInstanceof=GodSystemB42JavaCalls,getScriptManager,instanceof
    instanceof=function(value,class) return type(value)=="table" and value.textureMock==true and class=="Texture" end
    local calls=0
    r.getShopPrimaryFullType=function(item) return item.fullType end
    getScriptManager=function() return {} end
    GodSystemB42JavaCalls={value=function(object,method,fallback,fullType)
        if method=="FindItem" then calls=calls+1; return {name=fullType} end
        if method=="getNormalTexture" then return {textureMock=true,name=object.name} end
        if method=="getIconsForTexture" then error("icon names must not be used as Texture objects") end
        return fallback
    end}
    instanceItem=function() error("display must not instantiate") end
    D.clearIcons()
    local rows={}
    for i=1,20 do rows[i]={item={kind="shop",data={fullType="Base.Test"..i}}} end
    for step=1,10 do
        local before=calls; eq(D.resolvePageIcons(rows),2); eq(calls-before,2)
    end
    for i=1,20 do assert(rows[i].item.texture) end
    eq(D.resolvePageIcons(rows),0); eq(calls,20)
    for i=21,600 do D.texture("Base.Test"..i) end
    local n=0; for _ in pairs(D.iconCache) do n=n+1 end; eq(n,512)
    local draws=0
    local ui={drawTextureScaledAspect=function(_,tex) assert(instanceof(tex,"Texture")); draws=draws+1 end,
        drawRect=function() end,drawRectBorder=function() end}
    D.icon(ui,rows[1].item.texture,0,0,24); eq(draws,1)
    D.icon(ui,"Item_Axe",0,0,24); eq(draws,1)
    local nativeBridge=GodSystemB42JavaCalls.value
    GodSystemB42JavaCalls.value=function(object,method,fallback,arg)
        if method=="getNormalTexture" then return "Item_Axe" end
        return nativeBridge(object,method,fallback,arg)
    end
    eq(D.texture("Base.InvalidTexture"),nil)
    local failedCalls=calls
    eq(D.texture("Base.InvalidTexture"),nil); eq(calls,failedCalls)
    D.clearIcons(); eq(D.peekTexture("Base.Test600"),nil)
    r.getShopPrimaryFullType=originalPrimary; GodSystemB42JavaCalls=originalBridge; getScriptManager=originalManager; instanceof=originalInstanceof; instanceItem=nil
end)
test("audit: top status uses cached cash and bank page retains investment total",function()
    GodSystemUI.openMode("bank"); w:refreshTerminalStatus()
    eq(w.terminalStatus.cash,3680); eq(w.terminalStatus.investment,12000)
    GodSystemUI.openMode("shop")
    local r=GodSystemApp.services.runtime
    local original=r.getBankSummary
    r.getBankSummary=function() error("top bar must not aggregate bank products") end
    w:refreshTerminalStatus(); eq(w.terminalStatus.cash,3680)
    r.getBankSummary=original
end)
test("audit: live update runs worker and resize does not quote or repopulate",function()
    GodSystemUI.openMode("shop")
    w:update()
    local populate=w.populateList
    w.populateList=function() error("resize rebuilt display data") end
    w:relayoutVisiblePage()
    assert(w.primaryButton:getIsVisible() and w.fourthButton:getIsVisible(),"resize lost shop actions")
    w.populateList=populate
end)
test("audit: catalogue rebuild retains selection across loading updates",function()
    GodSystemUI.openMode("shop"); w.list.selected=2
    local selected=w:getPayloadId(w:getSelectedPayload())
    GodSystemShopCatalog.invalidate("test"); w:populateList(); w:populateList()
    while GodSystemShopCatalog.isBuilding() do GodSystemShopCatalog.step(50,999) end
    w:populateList()
    eq(w:getPayloadId(w:getSelectedPayload()),selected)
end)
test("audit: tracker draw never requests task progress",function()
    local tracker=GodSystemUIRuntimeEnv.GodSystemTaskTracker:new(0,0,340,120)
    tracker:initialise(); tracker:setVisible(true); tracker:update()
    local r=GodSystemApp.services.runtime
    local progress=r.getTaskDisplayProgress
    r.getTaskDisplayProgress=function() error("tracker draw scanned task inventory") end
    tracker:prerender(); tracker:prerender()
    r.getTaskDisplayProgress=progress
end)
print("Terminal behavior groups passed: "..passed)
