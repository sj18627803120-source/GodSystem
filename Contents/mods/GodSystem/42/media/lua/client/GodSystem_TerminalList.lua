require "ISUI/ISScrollingListBox"
require "GodSystem_TerminalDesign"
GodSystemTerminalList=ISScrollingListBox:derive("GodSystemTerminalList")
local L,D=GodSystemTerminalList,GodSystemTerminalDesign
function L:new(x,y,w,h,owner,callback)
    local o=ISScrollingListBox.new(self,x,y,w,h)
    o.owner=owner; o.itemheight=74; o.font=D.font("body"); o.fontHgt=D.height("body")
    o.drawBorder=false; o.backgroundColor=D.copy(D.colors.shell); o.onmousedown=callback; o.target=owner
    o.grid=false; o.columnsCount=1
    return o
end
function L:layoutGrid()
    self.columnsCount=math.max(1,math.floor((self.width-16)/math.max(130,D.height("body")*6)))
    self.tileWidth=math.floor((self.width-16)/self.columnsCount)
    self.tileHeight=84+D.height("body")+D.height("caption")
end
function L:rowAt(x,y)
    if not self.grid then return ISScrollingListBox.rowAt(self,x,y) end
    self:layoutGrid()
    if x<0 or x>=self.columnsCount*self.tileWidth or y<0 then return -1 end
    local index=math.floor(y/self.tileHeight)*self.columnsCount+math.floor(x/self.tileWidth)+1
    return self.items[index] and index or -1
end
function L:topOfItem(index)
    if not self.grid then return ISScrollingListBox.topOfItem(self,index) end
    return math.floor((index-1)/self.columnsCount)*self.tileHeight
end
function L:onMouseWheel(delta)
    local max=math.max(0,self:getScrollHeight()-self.height)
    self.smoothScrollTargetY=nil; self.smoothScrollY=nil
    self:setYScroll(math.max(-max,math.min(0,self:getYScroll()-delta*(self.grid and 70 or 46))))
    return true
end
function L:prerender()
    GodSystemUISafety.syncListGeometry(self)
    self.font=D.font("body"); self.fontHgt=D.height("body")
    if not self.grid then return ISScrollingListBox.prerender(self) end
    self:layoutGrid()
    local total=math.ceil(#self.items/self.columnsCount)*self.tileHeight
    self:setScrollHeight(total)
    self:setYScroll(math.max(-math.max(0,total-self.height),math.min(0,self:getYScroll())))
    local first=math.max(0,math.floor(-self:getYScroll()/self.tileHeight))
    local last=math.ceil((-self:getYScroll()+self.height)/self.tileHeight)
    D.rect(self,0,-self:getYScroll(),self.width,self.height,"shell")
    for row=first,last do
        for col=0,self.columnsCount-1 do
            local index=row*self.columnsCount+col+1; local item=self.items[index]
            if item then
                item.index=index
                local x,y=col*self.tileWidth,row*self.tileHeight
                -- Submit only fully visible text/icons; clip panel geometry independently of stencil.
                local top=math.max(y,-self:getYScroll()); local bottom=math.min(y+self.tileHeight-8,self.height-self:getYScroll())
                if bottom>top then
                    D.rect(self,x+2,top,self.tileWidth-9,bottom-top,self.selected==index and "selected" or "panel")
                    D.border(self,x+2,top,self.tileWidth-9,bottom-top,self.selected==index and "accent" or "line")
                    local p=item.item or {}; local bodyH=D.height("body"); local captionH=D.height("caption")
                    if y+8>=top and y+62<=bottom then D.icon(self,p.texture,x+(self.tileWidth-54)/2,y+8,48) end
                    if y+65>=top and y+65+bodyH<=bottom then D.label(self,p.title or item.text,x+11,y+65,self.tileWidth-28,"text") end
                    if y+70+bodyH>=top and y+70+bodyH+captionH<=bottom then D.label(self,p.detail,x+11,y+70+bodyH,self.tileWidth-28,"gold","caption") end
                end
            end
        end
    end
    self:updateTooltip()
end
function L:doDrawItem(y,item,alt)
    local p=item.item or {}; local h=item.height or self.itemheight; local scroll=self:getYScroll()
    local top,bottom=math.max(y,-scroll),math.min(y+h-(self.compact and 0 or 6),self.height-scroll)
    if bottom<=top then return y+h end
    local selected=self.selected==item.index
    D.rect(self,0,top,self.width-16,bottom-top,selected and "selected" or "panel")
    if selected then D.rect(self,0,top,2,bottom-top,"accent") end
    local caption=p.subtitle or p.detail or ""
    local title=p.title or item.text or ""
    local ty=y+10
    if self.compact then ty=y+5 end
    if ty>=top and ty+D.height("body")<=bottom then
        local width=self.width-40
        if p.kind=="task" and p.objective and p.objective~="" then
            local titleWidth=math.min(getTextManager():MeasureStringX(D.font("body"),title),math.floor(width*.45))
            D.label(self,title,12,ty,titleWidth,"text")
            D.label(self,p.objective,12+titleWidth+12,ty+math.max(0,D.height("body")-D.height("caption")),math.max(0,width-titleWidth-12),"muted","caption")
        else
            D.label(self,title,12,ty,width,p.selectable==false and "muted" or "text")
        end
    end
    local sy=ty+D.height("body")+5
    if not self.compact and sy>=top and sy+D.height("caption")<=bottom then D.label(self,caption,12,sy,self.width-40,p.kind=="task" and "gold" or "muted","caption") end
    if p.progress and y+h-12>=top and y+h-9<=bottom then D.bar(self,12,y+h-12,self.width-42,p.progress,p.target) end
    return y+h
end
return L
