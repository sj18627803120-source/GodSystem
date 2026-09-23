require "GodSystem_EquipmentUI"
require "GodSystem_TerminalList"
GodSystemTerminalEquipment=GodSystemTerminalEquipment or {}
local T,D,C=GodSystemTerminalEquipment,GodSystemTerminalDesign,GodSystemEquipmentClient
function T.install(Main)
    if T.installed then return end; T.installed=true
    local W=GodSystemEquipmentWindow
    local old={create=W.createChildren,refresh=W.refreshDetails,rebuild=W.rebuild,mouseDown=W.onMouseDown}
    function W:onMouseDown(x,y)
        if self.terminalEmbedded then self.moving=false; self.parent:bringToTop(); return true end
        return old.mouseDown(self,x,y)
    end
    function W:createChildren()
        old.create(self)
        for _,list in ipairs({self.slots,self.candidates,self.details,self.attributes}) do
            list.doDrawItem=GodSystemTerminalList.doDrawItem
            list.compact=true; list.font=D.font("body"); list.fontHgt=D.height("body")
            list.backgroundColor=D.copy(D.colors.shell); list.drawBorder=false
        end
        self:terminalLayout()
    end
    function W:terminalLayout()
        if not self.slots then return end
        local pad=12; local top=self.terminalEmbedded and 0 or self:titleBarHeight()+8
        local captionH,bodyH=D.height("caption"),D.height("body")
        local buttonH=bodyH+14; local bottom=self.height-buttonH-8
        local usable=self.height-top; local left=math.max(190,math.floor(self.width*.29)); local rx=left+26; local rw=self.width-rx-pad
        self.terminalLeft,self.terminalRightX,self.terminalRightW=left,rx,rw
        if self.terminalEmbedded then
            for _,key in ipairs({"closeButton","pinButton","collapseButton","resizeWidget","resizeWidget2"}) do if self[key] then self[key]:setVisible(false) end end
            self.moveWithMouse=false; self.drawFrame=false; self.clearStentil=false
        end
        D.bounds(self.status,pad,top+4,self.width-24,D.height("caption")); self.status.font=D.font("caption")
        local listY=top+captionH+14
        local slotsH=math.floor((bottom-listY-captionH-28)*.48)
        D.bounds(self.slots,pad,listY,left,slotsH)
        D.bounds(self.candidateLabel,pad,listY+slotsH+8,left,captionH); self.candidateLabel.font=D.font("caption")
        self.candidateLabel:setName(D.text("CarriedWeapons","Carried weapons"))
        local candidateY=listY+slotsH+captionH+16
        D.bounds(self.candidates,pad,candidateY,left,bottom-candidateY-8)
        D.bounds(self.bind,pad,bottom,left,buttonH); D.bounds(self.clearInvalid,pad,bottom,left,buttonH)
        local reasonY=bottom-captionH-8; local boostY=reasonY-buttonH-8; local qy=boostY-captionH-8
        self.reason:setVisible(true)
        if qy-listY-8<bodyH+18 then
            -- On short screens keep the refusal reason on the action tooltip.
            self.reason:setVisible(false); boostY=bottom-buttonH-8; qy=boostY-captionH-8
        end
        if qy-listY-16<(bodyH+18)*2 then
            local half=math.floor((rw-10)/2)
            D.bounds(self.details,rx,listY,half,qy-listY-8)
            D.bounds(self.attributes,rx+half+10,listY,rw-half-10,qy-listY-8)
        else
            local detailsH=math.floor((qy-listY-16)*.48)
            D.bounds(self.details,rx,listY,rw,detailsH)
            D.bounds(self.attributes,rx,listY+detailsH+8,rw,qy-listY-detailsH-16)
        end
        D.bounds(self.quoteLabel,rx,qy,rw,captionH); self.quoteLabel.font=D.font("caption")
        D.bounds(self.boostLabel,rx,boostY+7,rw-211,captionH); self.boostLabel.font=D.font("caption")
        self.boostLabel:setName(D.text("TargetChance","Target success %"))
        D.bounds(self.boost,rx+rw-206,boostY,70,buttonH); D.style(self.boost)
        D.bounds(self.enhance,rx+rw-128,boostY,128,buttonH)
        D.bounds(self.reason,rx,reasonY,rw,captionH); self.reason.font=D.font("caption")
        local width=math.floor((rw-18)/4)
        for i,key in ipairs({"repair","rename","retrieve","unbind"}) do D.bounds(self[key],rx+(i-1)*(width+6),bottom,width,buttonH) end
        for _,key in ipairs({"bind","clearInvalid","enhance","repair","rename","retrieve","unbind"}) do
            local b=self[key]; D.style(b,key=="enhance")
            if key~="repair" and key~="retrieve" then b.terminalFullTitle=b.terminalFullTitle or b.title end
            local title=b.terminalFullTitle or b.title; b.tooltip=b.tooltip or title
            b:setTitle(GodSystemUISafety.fitText(title,b.font,b.width-16))
        end
        self.note:setVisible(false)
        for _,key in ipairs({"status","candidateLabel","boostLabel","reason","quoteLabel"}) do
            local c=D.colors[key=="quoteLabel" and "gold" or "muted"]; self[key]:setColor(c.r,c.g,c.b,1)
        end
        for _,key in ipairs({"boostLabel","candidateLabel"}) do
            local l=self[key]; l.tooltip=l.name; l:setName(GodSystemUISafety.fitText(l.name,l.font,l.width))
        end
        for _,list in ipairs({self.slots,self.candidates,self.details,self.attributes}) do
            list.font=D.font("body"); list.fontHgt=bodyH
            list.itemheight=D.height("body")+18
            for _,row in ipairs(list.items) do row.height=list.itemheight end
        end
    end
    function W:refreshDetails()
        old.refresh(self)
        if not self.details then return end
        self.enhance.tooltip=self.reason.tooltip or self.reason.name
        self:terminalLayout()
        local row=self:row(); local record=row and row.record
        if record and not row.invalid then
            local originalDetails=self.details.items
            GodSystemUISafety.clearList(self.details)
            local title=record.name or ""
            self.details:addItem(title,{title=title})
            -- Keep gameplay details, including the next effect level; omit internal identity lines.
            for i=3,#originalDetails do
                for _,line in ipairs(D.wrap(originalDetails[i].text,self.details.width-40,"body")) do self.details:addItem(line,originalDetails[i].item) end
            end
            if self.quote and self.enhance.enable then self.reason:setName("") end
        end
        -- Wrap effect descriptions into selectable lines sharing the same effect payload.
        local rows=self.attributes.items; GodSystemUISafety.clearList(self.attributes)
        for _,entry in ipairs(rows) do
            local first=#self.attributes.items+1
            for _,line in ipairs(D.wrap(entry.text,self.attributes.width-40,"body")) do self.attributes:addItem(line,entry.item) end
            if entry.item.attribute==self.attribute then self.attributes.selected=first end
        end
        if self.attributes.selected>0 then self.attributes:ensureVisible(self.attributes.selected) end
        self:terminalLayout()
        for _,key in ipairs({"quoteLabel","reason","status"}) do
            local label=self[key]; local full=label.name or ""; label.tooltip=label.tooltip or full
            label:setName(GodSystemUISafety.fitText(full,label.font,key=="status" and self.width-24 or self.terminalRightW))
        end
        for _,key in ipairs({"repair","rename","retrieve","unbind"}) do
            local b=self[key]; b.tooltip=b.tooltip or b.title; b:setTitle(GodSystemUISafety.fitText(b.title,D.font("body"),b.width-16))
        end
    end
    function W:rebuild(state,candidates)
        old.rebuild(self,state,candidates)
        for _,entry in ipairs(self.candidates.items) do entry.text=entry.item.name or entry.text; entry.item.title=entry.text end
    end
    function W:prerender()
        if not self.terminalEmbedded then ISCollapsableWindow.prerender(self) end
        local top=self.terminalEmbedded and 0 or self:titleBarHeight()+8
        D.rect(self,0,top,self.width,self.height-top,"panel")
        if self.slots then
            D.frame(self,self.slots.x-1,self.slots.y-1,self.slots.width+2,self.slots.height+2)
            D.frame(self,self.candidates.x-1,self.candidates.y-1,self.candidates.width+2,self.candidates.height+2)
            D.frame(self,self.details.x-1,self.details.y-1,self.details.width+2,self.details.height+2)
            D.frame(self,self.attributes.x-1,self.attributes.y-1,self.attributes.width+2,self.attributes.height+2)
        end
    end
    function Main:showTerminalEquipment()
        local player=C.player(self.playerNum or 0); if not player then return end
        local w=self.terminalEquipment
        local entering=not w or not w:getIsVisible()
        if not w then
            local previous=C.windows[self.playerNum or 0]
            if previous then previous:close(); previous:removeFromUIManager() end
            w=W:new(0,0,self.playerNum or 0); w.terminalEmbedded=true; w:initialise()
            self.terminalEquipment=w; self:addChild(w); C.windows[self.playerNum or 0]=w
        end
        local y=self.mainY-6
        D.bounds(w,self.mainX-10,y,self.actionW+20,self.height-self.footerH-y-8)
        w:setVisible(true); w:terminalLayout()
        if entering then
            -- SP request returns the state and its operation-local candidate
            -- scan synchronously; do not scan once here and a second time there.
            if GodSystemNetwork and GodSystemNetwork.isMultiplayer then w:rebuild(C.state(player),nil) end
            C.request(player,false)
        end
        self.pageTitleLabel:setVisible(true)
    end
    function GodSystemEquipmentUI.open(playerNum)
        return GodSystemUI.openMode("equipment")
    end
end
return T
