require "GodSystem_StockMarket"
GodSystemStockActivity=GodSystemStockActivity or {}
local A,D,M=GodSystemStockActivity,GodSystemStockDefinitions,GodSystemStockMarket
local categories={tool="tool",food="food",drink="food",farming="food",medical="medical",electronics="energy",
    material="industry",vehicle="logistics",container="logistics"}
function A.industry(fullType,category,furniture)
    if fullType=="GodSystem.UtilityGenerator" then return "energy" end
    if furniture then return "industry" end
    return categories[category]
end
-- Eight monotonic counters form a bounded outbox. Applied watermarks live in
-- the world market. Delayed retries enter the earliest unsealed hour.
function A.record(data,industry,amount,token,c)
    if not c.enabled or not D.thresholds[industry] or not D.integer(amount) or amount==0 then return false end
    local ok,value=pcall(function()
        data.stockActivity=data.stockActivity or {totals={},tokens={},order={}}
        local a=data.stockActivity
        token=token and tostring(token) or nil
        if token and a.tokens[token] then return true end
        local previous=a.totals[industry] or 0
        if previous>D.MAX-amount then a.saturated=true end
        a.totals[industry]=math.min(D.MAX-amount,previous)+amount
        if token then
            a.tokens[token]=true; a.order[#a.order+1]=token
            while #a.order>64 do a.tokens[table.remove(a.order,1)]=nil end
        end
        return true
    end)
    if not ok then return false end
    return value
end
function A.pump(m,data,owner)
    local a=data.stockActivity
    if not a or type(a.totals)~="table" then return end
    local old=m.activityCursors[owner] or {}; local nextCursor=D.copy(old)
    local delta={}
    for i=1,#D.industries do
        local id=D.industries[i]; local total=a.totals[id] or 0; local cursor=old[id] or 0
        if D.integer(total) and D.integer(cursor) and total>cursor then delta[id]=total-cursor; nextCursor[id]=total end
    end
    -- Table arithmetic only, no callbacks/yields/native calls between input and watermark.
    for i=1,#D.industries do local id=D.industries[i]; if delta[id] then M.addActivity(m,id,delta[id]) end end
    m.activityCursors[owner]=nextCursor
end
function A.shop(data,row,paid,token,c)
    if not c.enabled or not D.integer(paid) or paid==0 then return end
    local contents=row.items or (row.fullType and {{item=row.fullType,count=row.count or 1}}) or {}
    local weights,total={},0
    for i=1,#contents do
        local item=contents[i]; local fullType=item.item or item.fullType
        local quote=GodSystemEconomyPolicy and GodSystemEconomyPolicy.quote(fullType,nil,"shop")
        local weight=quote and (quote.referenceBuy or 0)*(item.count or item.quantity or 1) or 0
        if not D.finite(weight) or weight<0 then weight=0 end
        local sprite=item.worldSprite or row.worldSprite
        weights[i]={industry=A.industry(fullType,quote and quote.category,type(sprite)=="string" and sprite~=""),weight=weight}
        total=total+weight
    end
    if total<=0 then return end
    local allocated=0
    for i=1,#weights do
        local value=i==#weights and paid-allocated or math.floor(paid*(weights[i].weight/total))
        value=math.max(0,math.min(value,paid-allocated)); allocated=allocated+value
        if weights[i].industry then A.record(data,weights[i].industry,value,token and (token..":"..i),c) end
    end
end
return A
