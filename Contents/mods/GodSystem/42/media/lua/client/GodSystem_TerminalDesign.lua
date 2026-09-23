require "GodSystem_TerminalPreferences"
require "GodSystem_UISafety"
GodSystemTerminalDesign = GodSystemTerminalDesign or {}
local D,P=GodSystemTerminalDesign,GodSystemTerminalPreferences
D.colors={
    shell={r=.034,g=.047,b=.047,a=.985}, panel={r=.051,g=.068,b=.068,a=.97},
    raised={r=.077,g=.098,b=.094,a=.98}, hover={r=.102,g=.145,b=.127,a=1},
    line={r=.24,g=.31,b=.28,a=.46}, accent={r=.49,g=.75,b=.61,a=1},
    selected={r=.10,g=.19,b=.145,a=.98}, text={r=.85,g=.88,b=.83,a=1},
    muted={r=.48,g=.56,b=.52,a=1}, gold={r=.77,g=.66,b=.44,a=1},
    red={r=.80,g=.39,b=.32,a=1}, blue={r=.48,g=.67,b=.72,a=1},
}
function D.copy(c) return {r=c.r,g=c.g,b=c.b,a=c.a} end
function D.font(role) return P.font(role) end
function D.height(role) return getTextManager():getFontHeight(D.font(role)) end
function D.text(key,fallback,...)
    local r=GodSystemApp and GodSystemApp.services.runtime
    local value=r and r.text and r.text("Terminal_"..key,fallback or key) or fallback or key
    local args={...}; return (tostring(value):gsub("{(%d+)}",function(n) return tostring(args[tonumber(n)] or "") end))
end
function D.rect(ui,x,y,w,h,c)
    if w<=0 or h<=0 then return end
    c=type(c)=="table" and c or D.colors[c or "panel"]
    ui:drawRect(x,y,w,h,c.a,c.r,c.g,c.b)
end
function D.border(ui,x,y,w,h,c)
    c=type(c)=="table" and c or D.colors[c or "line"]
    ui:drawRectBorder(x,y,w,h,c.a,c.r,c.g,c.b)
end
function D.label(ui,value,x,y,width,color,role)
    local c=D.colors[color or "text"]; local font=D.font(role)
    local v=GodSystemUISafety.fitText(tostring(value or ""),font,math.max(0,width))
    ui:drawText(v,x,y,c.r,c.g,c.b,c.a,font)
end
-- Build once with the row snapshot; drawing never queries task progress or inventory.
function D.taskPreview(task)
    if not task then return "" end
    local templates={kill="Kill {1} zombies",recycleItems="Recycle {1} items",
        recyclePoints="Earn {1} coins recycling",surviveHours="Survive {1} game hours",
        turnInItem="Turn in {1} x {2}",turnInAnyItem="Turn in {1} eligible items",
        spendPoints="Spend {1} coins",buyItems="Buy {1} items",moveDistance="Walk {1} tiles"}
    local template=templates[task.kind]
    if not template then return "" end
    local name=""
    if task.kind=="turnInItem" then
        local r=GodSystemApp and GodSystemApp.services.runtime
        name=r and r.getItemDisplayName and r.getItemDisplayName(task.item) or task.item or "?"
    end
    return D.text("TaskPreview_"..task.kind,template,task.target or "?",name)
end
function D.frame(ui,x,y,w,h)
    D.rect(ui,x,y,w,h,"panel"); D.border(ui,x,y,w,h)
    D.rect(ui,x,y,math.min(22,w),1,"accent")
    D.rect(ui,x+w-math.min(22,w),y+h-1,math.min(22,w),1,"line")
end
function D.bar(ui,x,y,w,value,total,color)
    D.rect(ui,x,y,w,3,"line"); D.rect(ui,x,y,w*math.max(0,math.min(1,(tonumber(value) or 0)/math.max(1,tonumber(total) or 1))),3,color or "accent")
end
function D.number(value)
    local n=math.floor(tonumber(value) or 0); local s=tostring(math.abs(n)); local result=s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
    return n<0 and "-"..result or result
end
function D.bounds(c,x,y,w,h)
    if not c then return end
    if x then c:setX(math.floor(x)); if c.originalX then c.originalX=math.floor(x) end end
    if y then c:setY(math.floor(y)) end
    if w then c:setWidth(math.max(1,math.floor(w))) end
    if h then c:setHeight(math.max(1,math.floor(h))) end
    if c.vscroll then GodSystemUISafety.syncListGeometry(c) end
end
function D.style(c,primary)
    c.backgroundColor=D.copy(D.colors[primary and "selected" or "raised"])
    c.backgroundColorMouseOver=D.copy(D.colors.hover)
    c.borderColor=D.copy(D.colors[primary and "accent" or "line"])
    c.textColor=D.copy(D.colors.text); c.font=D.font("body")
    if c.Type=="ISTextEntryBox" and c.setFont then c:setFont(c.font) end
    if c.fontHgt then c.fontHgt=D.height("body") end
end
function D.wrap(value,width,role)
    local font=D.font(role); local lines={}
    for paragraph in (tostring(value or "").."\n"):gmatch("(.-)\n") do
        local line=""; local pos=1
        while pos<=#paragraph do
            local nextPos=GodSystemUISafety.nextTextIndex(paragraph,pos)
            local ch=paragraph:sub(pos,nextPos-1)
            if line~="" and getTextManager():MeasureStringX(font,line..ch)>width then lines[#lines+1]=line; line="" end
            line=line..ch
            pos=nextPos
        end
        lines[#lines+1]=line
    end
    return lines
end
function D.isTexture(value)
    return value ~= nil and value ~= false and type(value) ~= "string" and instanceof and instanceof(value,"Texture") == true
end
function D.icon(ui,texture,x,y,size)
    if D.isTexture(texture) and ui.drawTextureScaledAspect then ui:drawTextureScaledAspect(texture,x,y,size,size,1,1,1,1)
    else D.border(ui,x+size*.23,y+size*.23,size*.54,size*.54,"line"); D.rect(ui,x+size*.38,y+size*.38,size*.24,size*.24,"muted") end
end
D.iconCache=D.iconCache or {}
D.iconUse=D.iconUse or 0
D.iconResolvedAt=D.iconResolvedAt or 0
D.iconResolvedThisStep=D.iconResolvedThisStep or 0
local function iconNow()
    if getTimestampMs then local ok,v=pcall(getTimestampMs); if ok and v then return tonumber(v) or 0 end end
    return math.floor(((os and os.clock and os.clock()) or 0)*1000)
end
local function pruneIcons()
    local count=0; for _ in pairs(D.iconCache) do count=count+1 end
    while count>512 do
        local oldestKey,oldest=nil,nil
        for key,value in pairs(D.iconCache) do if not oldest or (value.used or 0)<oldest then oldestKey,oldest=key,value.used or 0 end end
        if not oldestKey then break end
        D.iconCache[oldestKey]=nil; count=count-1
    end
end
function D.clearIcons()
    D.iconCache={}; D.iconUse=0
end
local function iconKey(fullType,worldSprite)
    return tostring(fullType or "")..(worldSprite and ("|"..tostring(worldSprite)) or "")
end
function D.peekTexture(fullType,worldSprite)
    local cached=D.iconCache[iconKey(fullType,worldSprite)]
    if cached then
        D.iconUse=D.iconUse+1; cached.used=D.iconUse
        if GodSystemShopCatalog and GodSystemShopCatalog.note then GodSystemShopCatalog.note("iconHits") end
    end
    return cached and cached.texture or nil
end
function D.texture(fullType,worldSprite)
    if GodSystemShopCatalog and GodSystemShopCatalog.note then GodSystemShopCatalog.note("iconRequests") end
    fullType=tostring(fullType or ""); if fullType=="" then return nil end
    D.iconUse=D.iconUse+1
    local key=iconKey(fullType,worldSprite)
    local cached=D.iconCache[key]
    if cached then cached.used=D.iconUse; return cached.texture or nil end
    -- The visible-page worker owns the per-update budget. Drawing only peeks.
    local texture=nil
    -- Furniture variants without a verified safe texture path use the normal
    -- placeholder. Their identity must never share another variant's icon.
    local manager=not worldSprite and getScriptManager and getScriptManager() or nil
    local script=manager and GodSystemB42JavaCalls and GodSystemB42JavaCalls.value(manager,"FindItem",nil,fullType) or nil
    if script then
        -- B42 crafting widgets use getNormalTexture directly. IconsForTexture
        -- entries can be names (Strings), not renderable Texture objects.
        texture=GodSystemB42JavaCalls.value(script,"getNormalTexture",nil)
    end
    if not D.isTexture(texture) then texture=nil end
    D.iconCache[key]={texture=texture or false,used=D.iconUse}; pruneIcons()
    if not texture and GodSystemShopCatalog and GodSystemShopCatalog.note then GodSystemShopCatalog.note("iconFailures") end
    return texture
end
function D.resolvePageIcons(items)
    local resolved=0
    local r=GodSystemApp.services.runtime
    for _,row in ipairs(items or {}) do
        local p=row.item
        if p and p.kind=="shop" then
            local fullType=tostring(r.getShopPrimaryFullType(p.data) or "")
            local sprite=p.data.worldSprite or (p.data.items and p.data.items[1] and p.data.items[1].worldSprite)
            if not D.iconCache[iconKey(fullType,sprite)] and resolved<2 then
                D.texture(fullType,sprite); resolved=resolved+1
            end
            p.texture=D.peekTexture(fullType,sprite)
        end
    end
    return resolved
end
-- Existing auxiliary windows consume this same palette.
function D.applyTheme()
    local c=GodSystemUITheme and GodSystemUITheme.colors
    if not c then return end
    local aliases={shell="shell",shellDeep="shell",topBar="panel",topCell="raised",nav="panel",navActive="selected",navTool="panel",
        navScrollTrack="shell",navScrollThumb="line",navScrollThumbHover="muted",navScrollThumbActive="accent",navScrollBorder="line",
        panel="panel",panelDeep="shell",panelWarm="raised",panelLine="line",border="line",borderStrong="accent",primary="accent",
        text="text",dimText="muted",muted="muted",gold="gold",green="accent",red="red",orange="gold",row="panel",rowAlt="raised",
        rowSelect="selected",rowDanger="raised",progressTrack="raised",progressFill="accent",button="raised",buttonHover="hover",buttonPrimary="selected",buttonDanger="raised",
        trackerBackground="shell",trackerHeader="raised",trackerBorder="line",trackerAccent="accent",trackerText="text",trackerDimText="muted",trackerRow="panel"}
    for key,value in pairs(aliases) do c[key]=D.copy(D.colors[value]) end
end
D.applyTheme()
return D
