require "GodSystem_TerminalList"
require "GodSystem_TerminalOverlays"
GodSystemTerminalAutoLoader=GodSystemTerminalAutoLoader or {}
local T,D=GodSystemTerminalAutoLoader,GodSystemTerminalDesign
function T.install()
    if T.installed then return end; T.installed=true
    local UI,W=GodSystemAutoLoaderUI,GodSystemAutoLoaderWindow
    UI.fixedWidth,UI.fixedHeight=640,520
    local create,rebuild=W.createChildren,W.rebuild
    function W:rebuild(state)
        if self.list then GodSystemUISafety.clearList(self.list) end
        rebuild(self,state)
        if self.list then self:terminalLayout() end
    end
    function W:createChildren()
        GodSystemTerminalPreferences.load(); create(self)
        self.backgroundColor=D.copy(D.colors.shell); self.borderColor=D.copy(D.colors.line)
        self:terminalLayout()
        GodSystemUISafety.installList(self.list)
        GodSystemTerminalOverlays.style(self)
    end
    function W:terminalLayout()
        local h=D.height("body")+14; local titleH=self:titleBarHeight()
        local top=titleH+D.height("caption")+24; local y=self.height-h-24
        D.bounds(self.statusLabel,16,titleH+8,self.width-32,D.height("caption")); self.statusLabel.font=D.font("caption")
        local c=D.colors.muted; self.statusLabel:setColor(c.r,c.g,c.b,1)
        D.bounds(self.list,16,top,self.width-32,y-top-20)
        self.list.itemheight=D.height("body")+D.height("caption")+32
        self.list.font=D.font("body"); self.list.backgroundColor=D.copy(D.colors.panel)
        for _,row in ipairs(self.list.items) do row.height=self.list.itemheight end
        D.bounds(self.depositButton,16,y,176,h); D.bounds(self.fillButton,200,y,164,h)
        D.bounds(self.amountEntry,372,y,70,h); D.bounds(self.withdrawButton,450,y,self.width-466,h)
        for _,b in ipairs({self.depositButton,self.fillButton,self.withdrawButton}) do
            D.style(b); b.terminalFullTitle=b.terminalFullTitle or b.title; b.tooltip=b.terminalFullTitle
            b:setTitle(GodSystemUISafety.fitText(b.terminalFullTitle,b.font,b.width-16))
        end
        D.style(self.amountEntry)
    end
    function W:drawAmmoRow(list,y,row,alternate)
        local p=row.item or {}; local h=row.height or list.itemheight; local scroll=list:getYScroll()
        local top,bottom=math.max(y,-scroll),math.min(y+h-6,list.height-scroll)
        if bottom<=top then return y+h end
        D.rect(list,0,top,list.width-16,bottom-top,self.selectedFullType==p.fullType and p.fullType and "selected" or "panel")
        if y+10>=top and y+10+D.height("body")<=bottom then D.label(list,p.name or row.text,58,y+10,list.width-84,p.available==false and "red" or "text") end
        local sy=y+D.height("body")+15
        if sy>=top and sy+D.height("caption")<=bottom and p.kind=="ammo" then D.label(list,tostring(p.count).." / "..tostring(p.capacity),58,sy,list.width-84,"gold","caption") end
        if y+10>=top and y+46<=bottom then D.icon(list,p.texture,10,y+10,36) end
        if p.kind=="ammo" and y+h-12>=top and y+h-9<=bottom then D.bar(list,58,y+h-12,list.width-84,p.count,p.capacity) end
        return y+h
    end
    function W:prerender()
        ISCollapsableWindow.prerender(self)
        if self.isCollapsed then return end
        local top=self:titleBarHeight()
        D.frame(self,0,top,self.width,self.height-top)
        D.rect(self,16,self.depositButton.y-12,self.width-32,1,"line")
    end
end
return T
