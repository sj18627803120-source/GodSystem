GodSystemStockDefinitions = GodSystemStockDefinitions or {}
local D = GodSystemStockDefinitions
D.MAX = 9007199254740991
D.industries = {"tool", "security", "biotech", "food", "medical", "energy", "industry", "logistics"}
D.thresholds = {
    tool={1000,3000,10000,30000}, security={50,150,400,1000},
    biotech={2000,8000,20000,60000}, food={1000,3000,10000,30000},
    medical={1000,3000,10000,30000}, energy={1000,3000,10000,30000},
    industry={1000,3000,10000,30000}, logistics={1000,3000,10000,30000},
}
D.rows, D.byId = {}, {}
for i=1,#D.industries do
    for j=1,3 do
        local row={id=D.industries[i].."_0"..j, industry=D.industries[i], initial=60+j*20, factor=0.6+j*0.2}
        D.rows[#D.rows+1]=row; D.byId[row.id]=row
    end
end
function D.finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
function D.integer(n) return D.finite(n) and n>=0 and n<=D.MAX and math.floor(n)==n end
function D.copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=D.copy(v) end; return result
end
function D.clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
-- Exact floor(a*b/d), with bounded intermediates. No bit library, no next().
function D.mulDiv(a,b,d)
    if not D.integer(a) or not D.integer(b) or not D.integer(d) or d==0 then return nil end
    -- Kahlua's % path narrows very large quotients; never use it here.
    local aq=math.floor(a/d)
    local ar=a-aq*d
    if ar<0 then aq=aq-1; ar=ar+d elseif ar>=d then aq=aq+1; ar=ar-d end
    local q,r=0,0
    while b>0 do
        local half=math.floor(b/2)
        if b-half*2==1 then
            local carry=0
            if r>=d-ar then r=r-(d-ar); carry=1 else r=r+ar end
            if aq>D.MAX-q-carry then return nil end
            q=q+aq+carry
        end
        b=half
        if b>0 then
            local carry=0
            if ar>=d-ar then ar=ar-(d-ar); carry=1 else ar=ar+ar end
            -- If the doubled quotient is too big, any remaining bit overflows.
            if aq>math.floor((D.MAX-carry)/2) then return nil end
            aq=aq+aq+carry
        end
    end
    return q,r
end
function D.ceilMulDiv(a,b,d)
    local q,r=D.mulDiv(a,b,d); if not q or (r>0 and q==D.MAX) then return nil end
    return q+(r>0 and 1 or 0)
end
function D.config(raw)
    raw=raw or {}
    local function num(key,default,lo,hi)
        local n=tonumber(raw[key]); if not D.finite(n) then n=default end
        return D.clamp(n,lo,hi)
    end
    local function on(key) return raw[key]~=false and raw[key]~=0 end
    local c={enabled=on("EnableBank") and on("EnableStockMarket"),
        minDays=math.floor(num("StockTrendMinDays",3,1,30)),
        maxDays=math.floor(num("StockTrendMaxDays",7,1,60)),
        news=math.floor(num("StockNewsMaxPerDay",3,0,3)),
        fee=math.floor(num("StockTradeFeePercent",0.5,0,10)*100+0.5),
        volatility=num("StockVolatilityMultiplier",1,0,3),
        threshold=num("StockActivityThresholdMultiplier",1,0.1,100),
        activity=num("StockActivityImpactMultiplier",1,0,3),
        order=num("StockOrderImpactMultiplier",1,0,3)}
    c.maxDays=math.max(c.minDays,c.maxDays)
    c.signature=table.concat({c.enabled and "1" or "0",c.minDays,c.maxDays,c.news,c.fee,c.volatility,c.threshold,c.activity,c.order},"|")
    return c
end
function D.quote(cents,quantity,side,fee)
    if not D.integer(cents) or cents==0 or not D.integer(quantity) or quantity==0
        or not D.integer(fee) or fee>1000 or (side~="buy" and side~="sell") then return nil,"StockInvalid" end
    local gross=side=="buy" and D.ceilMulDiv(quantity,cents,100) or D.mulDiv(quantity,cents,100)
    if not gross then return nil,"StockLimit" end
    local charge=D.ceilMulDiv(gross,fee,10000)
    if not charge then return nil,"StockLimit" end
    if fee>0 then charge=math.max(1,charge) end
    if side=="buy" and charge>D.MAX-gross then return nil,"StockLimit" end
    local total=side=="buy" and gross+charge or gross-charge
    if total<=0 then return nil,"StockTooSmall" end
    return {gross=gross,fee=charge,total=total}
end
function D.maxBuy(cents,balance,fee)
    if not D.integer(balance) or not D.integer(cents) or cents==0 then return 0 end
    local lo,hi=0,D.MAX
    while lo<hi do
        local mid=lo+math.floor((hi-lo)/2)+1
        local q=D.quote(cents,mid,"buy",fee)
        if q and q.total<=balance then lo=mid else hi=mid-1 end
    end
    return lo
end
return D
