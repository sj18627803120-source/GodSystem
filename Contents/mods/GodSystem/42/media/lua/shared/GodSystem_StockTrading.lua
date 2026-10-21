require "GodSystem_StockMarket"
require "GodSystem_OperationLedger"
GodSystemStockTrading = GodSystemStockTrading or {}
local T,D,M,L=GodSystemStockTrading,GodSystemStockDefinitions,GodSystemStockMarket,GodSystemOperationLedger
T.normalized=T.normalized or setmetatable({}, {__mode="k"})
function T.account(bank)
    if type(bank)~="table" then return nil end
    if bank.stocks==nil then bank.stocks={schema=1,revision=1,nextSequence=1,positions={},realized=0,fees=0,trades={},ledger={results={},order={}}} end
    local a=bank.stocks
    if type(a)~="table" or a.schema~=1 or type(a.positions)~="table" or not D.integer(a.nextSequence)
        or a.nextSequence<1 or not D.integer(a.revision) or not D.integer(a.fees)
        or not D.integer(math.abs(tonumber(a.realized) or math.huge)) or type(a.trades)~="table"
        or type(a.ledger)~="table" or type(a.ledger.results)~="table" or type(a.ledger.order)~="table" then return nil end
    for id,p in pairs(a.positions) do
        if not D.byId[id] or type(p)~="table" or not D.integer(p.quantity) or p.quantity==0 or not D.integer(p.cost) then return nil end
    end
    if not T.normalized[a] then
        for _,r in pairs(a.ledger.results) do
            if type(r)~="table" or (r.status~="processing" and r.status~="unknown" and r.status~="done") then return nil end
            if r.status=="processing" then r.status="unknown" end
        end
        if a.pending then a.unknown=true end
        T.normalized[a]=true
    end
    return a
end
local function fingerprint(r)
    return table.concat({r.stockId,r.side,r.quantity,r.quoteVersion,r.tradeConfigVersion,r.tradeSequence},"|")
end
local function result(ok,code,r,extra)
    local v=extra or {}; v.ok=ok; v.code=code; v.opId=r and r.opId; return v
end
function T.recover(m,bank,owner)
    local a=T.account(bank); if not a then return false end
    if not a.pending then return not a.unknown end
    local p=a.pending; local receipt=a.ledger.results[p.opId]
    local mark=m.tradeMarks and m.tradeMarks[owner]
    -- Never restore a saved pre-trade bank balance after restart.
    if receipt and receipt.status=="done" and mark and mark.opId==p.opId and mark.sequence==p.sequence then
        a.pending=nil; a.unknown=nil; return true
    end
    a.unknown=true; return false
end
function T.trade(m,bank,owner,r,c,adapter)
    r=type(r)=="table" and r or {}
    if not L.validId(r.opId) or not D.byId[r.stockId] or (r.side~="buy" and r.side~="sell")
        or not D.integer(r.quantity) or r.quantity==0 or not D.integer(r.quoteVersion)
        or not D.integer(r.tradeConfigVersion) or not D.integer(r.tradeSequence) then return result(false,"StockInvalid",r) end
    local a=T.account(bank); if not a then return result(false,"StockAccountInvalid",r) end
    local fp=fingerprint(r); local old=L.get(a.ledger,r.opId,fp)
    if old then
        if old.status=="mismatch" then return result(false,"StockMismatch",r) end
        return D.copy(old.payload or result(false,"StockUnknown",r))
    end
    if a.unknown or a.pending then return result(false,"StockUnknown",r) end
    if r.tradeSequence~=a.nextSequence then return result(false,"StockSequence",r) end
    if not c.enabled then return result(false,"StockDisabled",r) end
    if m.overloaded or M.jobs[m] or m.processed<math.floor(m.hour) then return result(false,"StockUpdating",r) end
    if r.quoteVersion~=m.quoteVersion or r.tradeConfigVersion~=m.tradeConfigVersion then return result(false,"StockStale",r) end
    local stock=m.stocks[r.stockId]
    if not stock or stock.suspended then return result(false,"StockSuspended",r) end
    if not D.integer(bank.current) then return result(false,"StockAccountInvalid",r) end
    local q,code=D.quote(stock.cents,r.quantity,r.side,c.fee)
    if not q then return result(false,code,r) end
    local p=a.positions[r.stockId] or {quantity=0,cost=0}
    if not D.integer(p.quantity) or not D.integer(p.cost) then return result(false,"StockAccountInvalid",r) end
    if r.side=="buy" and bank.current<q.total then return result(false,"StockBalance",r) end
    if r.side=="sell" and p.quantity<r.quantity then return result(false,"StockHolding",r) end
    local cost=r.side=="sell" and D.mulDiv(p.cost,r.quantity,p.quantity) or q.total
    if not cost or a.nextSequence>=D.MAX or a.fees>D.MAX-q.fee then return result(false,"StockLimit",r) end
    local input=M.input(m,math.floor(m.hour)+1)
    local net=input.orders[r.stockId] or 0
    local signed=r.side=="buy" and r.quantity or -r.quantity
    if math.abs(net+signed)>D.MAX or not D.integer(math.abs(net+signed))
        or not D.mulDiv(math.abs(net+signed),stock.cents,100)
        or (r.side=="buy" and (r.quantity>D.MAX-p.quantity or q.total>D.MAX-p.cost))
        or (r.side=="sell" and q.total>D.MAX-bank.current)
        or math.abs(a.realized+(r.side=="sell" and q.total-cost or 0))>D.MAX then return result(false,"StockLimit",r) end
    local before=D.copy(a); local balance=bank.current
    local oldMark=m.tradeMarks and D.copy(m.tradeMarks[owner])
    a.pending={opId=r.opId,sequence=r.tradeSequence,beforeBalance=balance,stockId=r.stockId,
        beforePosition=D.copy(p),quantity=r.quantity,side=r.side,total=q.total}
    a.nextSequence=a.nextSequence+1
    L.put(a.ledger,r.opId,{status="processing",fingerprint=fp})
    local ok,committed=pcall(function()
        if adapter and adapter.stage then adapter.stage("intent") end
        if r.side=="buy" then
            bank.current=balance-q.total; p={quantity=p.quantity+r.quantity,cost=p.cost+q.total}
        else
            bank.current=balance+q.total; p={quantity=p.quantity-r.quantity,cost=p.cost-cost}
            a.realized=a.realized+q.total-cost
        end
        a.positions[r.stockId]=p.quantity>0 and p or nil
        a.fees=a.fees+q.fee; input.orders[r.stockId]=net+signed
        if adapter and adapter.stage then adapter.stage("mutated") end
        if not D.integer(bank.current) or not D.integer(p.quantity) or not D.integer(p.cost) then return false end
        a.revision=a.revision+1
        a.trades[#a.trades+1]={opId=r.opId,hour=m.processed,id=r.stockId,side=r.side,quantity=r.quantity,cents=stock.cents,fee=q.fee,total=q.total}
        while #a.trades>50 do table.remove(a.trades,1) end
        local response=result(true,"StockSuccess",r,{nextSequence=a.nextSequence,quantity=r.quantity,total=q.total,fee=q.fee})
        m.tradeMarks=m.tradeMarks or {}; m.tradeMarks[owner]={opId=r.opId,sequence=r.tradeSequence}
        L.put(a.ledger,r.opId,{status="done",fingerprint=fp,payload=response})
        a.pending=nil; a.unknown=nil
        return true
    end)
    if not ok or committed~=true then
        local restored=pcall(function()
            if adapter and adapter.stage then adapter.stage("rollback") end
            bank.current=balance; bank.stocks=before; input.orders[r.stockId]=net
            if m.tradeMarks then m.tradeMarks[owner]=oldMark end
            before.nextSequence=r.tradeSequence+1; T.normalized[before]=true
            local failure=result(false,"StockRolledBack",r,{nextSequence=before.nextSequence})
            L.put(before.ledger,r.opId,{status="done",fingerprint=fp,payload=failure})
        end)
        if not restored then
            bank.stocks=a; a.unknown=true
            L.put(a.ledger,r.opId,{status="unknown",fingerprint=fp,payload=result(false,"StockUnknown",r)})
            return result(false,"StockUnknown",r)
        end
        return result(false,"StockRolledBack",r,{nextSequence=before.nextSequence})
    end
    return D.copy(a.ledger.results[r.opId].payload)
end
function T.publicAccount(bank)
    local a=T.account(bank); if not a then return {invalid=true} end
    return {revision=a.revision,nextSequence=a.nextSequence,positions=D.copy(a.positions),realized=a.realized,
        fees=a.fees,trades=D.copy(a.trades),unknown=a.unknown==true,balance=bank.current}
end
return T
