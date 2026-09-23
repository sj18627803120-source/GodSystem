-- Local presentation preferences. No economy, save schema or network changes.
GodSystemTerminalPreferences = GodSystemTerminalPreferences or {}
local P = GodSystemTerminalPreferences
P.sizes = {
    {id="auto",w=0,h=0}, {id="compact",w=1100,h=680}, {id="standard",w=1280,h=780},
    {id="wide",w=1500,h=900}, {id="large",w=1700,h=1000}, {id="xlarge",w=1920,h=1080},
    {id="fullscreen",w=0,h=0,fullscreen=true},
}
P.current = P.current or {font="normal",size="auto"}
local function enum(value, values, fallback)
    for _,v in ipairs(values) do if value==v then return v end end
    return fallback
end
function P.normalize(value)
    value=type(value)=="table" and value or {}
    return {font=enum(value.font,{"small","normal","large"},"normal"),size=enum(value.size,{"auto","compact","standard","wide","large","xlarge","fullscreen"},"auto")}
end
function P.load()
    local runtime=GodSystemApp and GodSystemApp.services.runtime
    local data=runtime and runtime.getData and runtime.getData()
    P.current=P.normalize(data and data.ui and data.ui.terminal)
    return P.current
end
function P.save(value)
    P.current=P.normalize(value)
    local runtime=GodSystemApp and GodSystemApp.services.runtime
    local data=runtime and runtime.getData and runtime.getData()
    if data then data.ui=data.ui or {}; data.ui.terminal=P.normalize(P.current); runtime.save() end
    return P.current
end
function P.dimensions(sw,sh,value)
    value=P.normalize(value or P.current)
    sw,sh=math.max(320,tonumber(sw) or 1920),math.max(240,tonumber(sh) or 1080)
    local w,h=math.min(1440,math.floor(sw*0.91)),math.min(850,math.floor(sh*0.88))
    if value.size=="auto" and getTextManager then
        local body=value.font=="small" and UIFont.Small or value.font=="large" and UIFont.Large or UIFont.Medium
        local caption=value.font=="large" and UIFont.Medium or UIFont.Small
        h=math.max(h,420+getTextManager():getFontHeight(body)*4+getTextManager():getFontHeight(caption)*2)
    end
    for _,size in ipairs(P.sizes) do
        if size.id==value.size then
            if size.fullscreen then w,h=sw-24,sh-24
            elseif size.w>0 then w,h=size.w,size.h end
        end
    end
    return math.min(w,sw-24),math.min(h,sh-24)
end
function P.font(role,value)
    local size=P.normalize(value or P.current).font
    if role=="title" then return UIFont.Large end
    if role=="caption" then return size=="large" and UIFont.Medium or UIFont.Small end
    return size=="small" and UIFont.Small or size=="large" and UIFont.Large or UIFont.Medium
end
function P.fontPixelHeight(value)
    if not getTextManager then return 0 end
    return math.max(0, math.floor(getTextManager():getFontHeight(P.font("body",value)) or 0))
end
return P
