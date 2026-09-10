-- Appends GodSystem's small equipment summary without replacing the native
-- InventoryItem DoTooltip implementation or any already chained Tooltip mod.
require "ISUI/ISToolTipInv"
require "GodSystem_EquipmentClient"
if isServer and isServer() and not (isClient and isClient()) then return end

GodSystemEquipmentTooltip = GodSystemEquipmentTooltip or {}
local T,C,E,I=GodSystemEquipmentTooltip,GodSystemEquipmentClient,GodSystemEquipment,GodSystemEquipmentItems

local function format(key, fallback, ...)
    local value=C.text(key,fallback); local args={...}
    return (value:gsub("{(%d+)}",function(index) return tostring(args[tonumber(index)] or "") end))
end
local function percent(value)
    value=math.floor((E.number(value) or 0)*100+0.5)/100
    local text=string.format("%.2f",value)
    return (text:gsub("%.?0+$", ""))
end
local function lines(item)
    local projection=C.tooltipProjection(item)
    if not projection or projection.valid~=true or type(projection.levels)~="table" then return nil end
    local cfg=projection.config
    if type(cfg)~="table" then return nil end
    local raw=I.raw(item)
    if not raw or not E.supports(raw,"damage") then return nil end
    local result={}
    for _, entry in ipairs(E.tooltipEntries(raw,projection.levels,cfg)) do
        local label=C.text("Equipment_Attr_"..entry.attribute,entry.attribute)
        if entry.direction=="freeze" then
            result[#result+1]=format("Equipment_TooltipFreeze","Slow Lv.{1}, -{2}% zombie movement speed",entry.level,percent(entry.percent))
        elseif entry.direction=="decrease" then
            result[#result+1]=format("Equipment_TooltipDecrease","{1} Lv.{2}, -{3}% {1}",label,entry.level,percent(entry.percent))
        else
            result[#result+1]=format("Equipment_TooltipIncrease","{1} Lv.{2}, +{3}% {1}",label,entry.level,percent(entry.percent))
        end
    end
    return #result>0 and result or nil
end
local function append(self, rows)
    if not rows or #rows==0 or not self.tooltip then return end
    local font=self.tooltip:getFont() or UIFont.Small
    local lineHeight=getTextManager():getFontHeight(font)
    local widest=0
    for _,row in ipairs(rows) do widest=math.max(widest,getTextManager():MeasureStringX(font,row)) end
    local baseWidth,baseHeight=self.width,self.height
    local width=math.max(baseWidth,widest+16)
    local height=baseHeight+#rows*(lineHeight+2)+8
    self:setWidth(width); self:setHeight(height)
    local x,y=self:getX(),self:getY()
    local core=getCore()
    if x+width>core:getScreenWidth() then self:setX(math.max(0,core:getScreenWidth()-width-1)) end
    if y+height>core:getScreenHeight() then self:setY(math.max(0,core:getScreenHeight()-height-1)) end
    local color=self.backgroundColor or {a=0.8,r=0,g=0,b=0}
    local border=self.borderColor or {a=1,r=1,g=1,b=1}
    self:drawRect(0,baseHeight-1,width,height-baseHeight+1,color.a,color.r,color.g,color.b)
    self:drawRectBorder(0,0,width,height,border.a,border.r,border.g,border.b)
    local rowY=baseHeight+4
    for _,row in ipairs(rows) do
        self:drawText(row,8,rowY,0.72,0.9,1,1,font)
        rowY=rowY+lineHeight+2
    end
end
function T.install()
    if T.installed or not ISToolTipInv or not ISToolTipInv.render then return end
    T.installed=true
    local previous=ISToolTipInv.render
    function ISToolTipInv:render()
        previous(self)
        if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
        local ok,err=pcall(function()
            if self.item and I.isWeapon(self.item) then append(self,lines(self.item)) end
        end)
        if not ok then
            local now=GodSystemScheduler and GodSystemScheduler.nowMs and GodSystemScheduler.nowMs() or 0
            if not T.lastErrorAt or now-T.lastErrorAt>=5000 then
                T.lastErrorAt=now; print("[GodSystem] equipment Tooltip append skipped: "..tostring(err))
            end
        end
    end
end
T.install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(T.install) end
return T
