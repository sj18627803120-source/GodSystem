-- Pure receipt storage; existing server wrapper keeps its public API and migration.
GodSystemOperationLedger = GodSystemOperationLedger or {}
local L=GodSystemOperationLedger
function L.validId(id) return type(id)=="string" and #id<=96 and id:match("^gs%-%d+%-%d+%-%d+$")~=nil end
function L.get(bucket,id,fingerprint)
    local r=bucket.results[id]
    if r and r.fingerprint~=fingerprint then return {status="mismatch",code="StockMismatch"} end
    return r
end
function L.put(bucket,id,result,limit)
    if not bucket.results[id] then bucket.order[#bucket.order+1]=id end
    bucket.results[id]=result
    while #bucket.order>(limit or 64) do
        local at=nil
        for i=1,#bucket.order do if bucket.results[bucket.order[i]].status=="done" then at=i; break end end
        if not at then break end
        local old=table.remove(bucket.order,at); bucket.results[old]=nil
    end
end
return L
