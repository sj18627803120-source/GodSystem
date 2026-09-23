require "GodSystem_TerminalDesign"
require "GodSystem_TerminalGuideData"
GodSystemTerminalManual=GodSystemTerminalManual or {}
local M,D,P=GodSystemTerminalManual,GodSystemTerminalDesign,GodSystemTerminalPreferences
function M.search(query)
    query=string.lower(tostring(query or "")); local found={}
    for _,article in ipairs(GodSystemTerminalGuideData) do
        local haystack=string.lower(article.title.." "..article.group.." "..article.body.." "..(article.fullType or ""))
        if query=="" or string.find(haystack,query,1,true) then found[#found+1]=article end
    end
    return found
end
function M.install(W)
    local primary,secondary=W.onPrimaryAction,W.onSecondaryAction
    function W:onPrimaryAction()
        local p=self:getSelectedPayload()
        if self.mode=="settings" and p and p.kind=="terminalPreference" then
            local b=p.target=="font" and self.terminalFont or self.terminalSize
            b.onclick(self,b); return
        end
        return primary(self)
    end
    function W:onSecondaryAction()
        local p=self:getSelectedPayload()
        if self.mode=="settings" and p and p.kind=="terminalPreference" then
            self.terminalPrefs[p.target]=p.target=="font" and "normal" or "auto"; self:populateList(); return
        end
        return secondary(self)
    end
    function W:populateTerminalManual()
        self:applyBaseLayout(); self:setActionBar({}); self:updateModeButtonStyles()
        local selected=self.terminalManualId; local topic=self.terminalManualTopic; self.terminalManualTopic=nil
        if topic then self.terminalSearchUpdating=true; self.terminalSearch:setText(""); self.terminalSearchUpdating=false end
        GodSystemUISafety.clearList(self.list)
        self.list.itemheight=D.height("body")+D.height("caption")+26
        local listW=math.max(235,math.floor(self.actionW*.32))
        local height=self.height-self.footerH-self.mainY-12
        D.bounds(self.list,self.mainX,self.mainY,listW,height)
        D.bounds(self.detailList,self.mainX+listW+18,self.mainY,self.actionW-listW-18,height)
        self.terminalSearch:setVisible(true); D.style(self.terminalSearch)
        local labelW=math.min(240,getTextManager():MeasureStringX(D.font("body"),D.text("Manual","Field guide"))+20)
        D.bounds(self.terminalSearch,self.mainX+labelW,self.contentY+8,math.max(90,math.min(380,self.actionW-labelW-48)),self.headerControlH)
        self.terminalSearch:setTooltip(D.text("SearchGuide","Search functions or items"))
        self.terminalSearch:setPlaceholderText(D.text("SearchGuide","Search functions or items"))
        local matched=M.search(self.terminalSearch:getText())
        self.list.selected=0
        for _,a in ipairs(matched) do
            self.list:addItem(a.title,{kind="manual",id=a.id,article=a,title=a.title,subtitle=a.group})
            if (topic and self.list.selected==0 and (a.id==topic or a.topic==topic)) or (not topic and a.id==selected) then self.list.selected=#self.list.items end
        end
        if #matched>0 and self.list.selected==0 then self.list.selected=1 end
        self:updateTerminalManualArticle()
    end
    function W:updateTerminalManualArticle()
        local row=self.list.items[self.list.selected or 0]; local a=row and row.item.article
        if not a then self:setDetailText(D.text("NoMatches","No matching articles")); return end
        self.terminalManualId=a.id
        self:setDetailText(a.group.."\n\n"..a.title.."\n\n"..a.body)
    end
    function W:populateTerminalSettings()
        self:applyBaseLayout(); self:hideActionControls(); self:updateModeButtonStyles()
        GodSystemUISafety.clearList(self.list)
        local runtime=GodSystemApp.services.runtime
        local fontNames={small=D.text("FontSmall","Small"),normal=D.text("FontNormal","Standard"),large=D.text("FontLarge","Large")}
        local fontHeight=P.fontPixelHeight(self.terminalPrefs)
        local fontValue=fontNames[self.terminalPrefs.font].." · "..tostring(fontHeight).."px"
        local sizeNames={auto=D.text("SizeAuto","Fit screen"),compact="1100 x 680",standard="1280 x 780",wide="1500 x 900",large="1700 x 1000",xlarge="1920 x 1080",fullscreen=D.text("SizeFullscreen","Fullscreen")}
        local sizeValue=sizeNames[self.terminalPrefs.size] or sizeNames.auto
        if self.terminalPrefs.size=="fullscreen" then
            local core=getCore(); local width,height=P.dimensions(core:getScreenWidth(),core:getScreenHeight(),self.terminalPrefs)
            sizeValue=sizeValue.." · "..tostring(width).." x "..tostring(height)
        end
        self.list:addItem(D.text("FontSize","Font size"),{kind="terminalPreference",target="font",title=D.text("FontSize","Font size"),subtitle=fontValue})
        self.list:addItem(D.text("WindowSize","Window size"),{kind="terminalPreference",target="size",title=D.text("WindowSize","Window size"),subtitle=sizeValue})
        self.list:addItem(D.text("PanelKey","Panel shortcut"),{kind="keyBinding",target="panel",title=D.text("PanelKey","Panel shortcut"),subtitle=GodSystemPanelKey.getKeyName(GodSystemPanelKey.getKey())})
        self.list:addItem(D.text("RangeKey","Recycle shortcut"),{kind="keyBinding",target="range",title=D.text("RangeKey","Recycle shortcut"),subtitle=GodSystemPanelKey.getKeyName(GodSystemPanelKey.getRangeKey())})
        self.list:addItem(D.text("Notifications","Head-up notifications"),{kind="settingToggle",target="headUpNotifications",title=D.text("Notifications","Head-up notifications"),subtitle=D.text(runtime.getHeadUpNotificationsEnabled() and "Shown" or "Hidden","Toggle")})
        self.list.selected=1
        for i,row in ipairs(self.list.items) do if row.item.target==self.terminalSettingSelected then self.list.selected=i end end
        self.primaryButton.fullTitle=D.text("ChangeKey","Change key"); self.secondaryButton.fullTitle=D.text("ResetBinding","Restore default")
        self:resetActionButtonEnabledState()
        self.list.itemheight=D.height("body")+D.height("caption")+22
        for _,b in ipairs({self.terminalApply,self.terminalReset}) do b:setVisible(true); D.style(b) end
        if not self.terminalSettingButtons then
            self.terminalSettingButtons={}
            for _,entry in ipairs({{"shortcuts","Shortcuts","Quick actions"},{"itemConfig","ItemConfig","Item manager"},{"diagnostics","Diagnostics","Diagnostics"}}) do
                local b=ISButton:new(0,0,110,36,D.text(entry[2],entry[3]),self,function(win,pressed) win:onModeButton(pressed) end)
                b.internal=entry[1]; b:initialise(); self:addChild(b); self.terminalSettingButtons[#self.terminalSettingButtons+1]=b
            end
        end
        local actions={{control=self.terminalApply},{control=self.terminalReset},{id="primary"},{id="secondary"}}
        for _,b in ipairs(self.terminalSettingButtons) do
            local tab=self:navigationTabById(b.internal)
            if tab and self:isNavigationTabVisible(tab) then actions[#actions+1]={control=b} end
        end
        self.terminalSettingActions=actions
        self:updateDetail()
    end
    function W:updateTerminalSettingDetail()
        local p=self:getSelectedPayload(); self.terminalSettingSelected=p and p.target or nil
        local preference=p and p.kind=="terminalPreference"
        self.primaryButton.fullTitle=D.text(preference and "NextOption" or p and p.target=="headUpNotifications" and "Toggle" or "ChangeKey","Change")
        self.secondaryButton.fullTitle=D.text("ResetBinding","Restore default")
        self.secondaryButton.enable=not (p and p.target=="headUpNotifications")
        local detail=p and (p.title.."\n\n"..p.subtitle) or ""
        if preference then
            local pending=self.terminalPrefs[p.target]~=P.current[p.target]
            detail=detail.."\n\n"..D.text(pending and "PendingDisplay" or "AppliedDisplay",pending and "Pending apply" or "Applied")
            if p.target=="size" then
                local core=getCore(); local width,height=P.dimensions(core:getScreenWidth(),core:getScreenHeight(),self.terminalPrefs)
                detail=detail.."\n"..tostring(width).." x "..tostring(height)
            end
        end
        self:setDetailText(detail)
        self:setActionBar(self.terminalSettingActions or {})
    end
    function W:applyTerminalPreferences()
        local preferred=P.save(self.terminalPrefs); self.terminalPrefs=P.normalize(preferred)
        local core=getCore(); local w,h=P.dimensions(core:getScreenWidth(),core:getScreenHeight(),preferred)
        self:setWidth(w); self:setHeight(h); self:setX(math.floor((core:getScreenWidth()-w)/2)); self:setY(math.floor((core:getScreenHeight()-h)/2))
        self.minimumWidth=math.min(1000,w); self.minimumHeight=math.min(640,h)
        if self.terminalEquipment then self.terminalEquipment:terminalLayout() end
        self:populateList()
        if GodSystemTerminalOverlays then GodSystemTerminalOverlays.refresh() end
    end
end
return M
