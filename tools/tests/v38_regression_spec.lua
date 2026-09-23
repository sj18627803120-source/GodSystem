local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); print("PASS 3.8 regression: "..name) end
load("shared/GodSystem_ShopInflation.lua")
local S=GodSystemShopInflation
local function config() return {EnableShopDynamicInflation=true,ShopDynamicInflationPercent=10,ShopDynamicInflationHours=24} end

test("disabled quotes can be confirmed, consumed and committed",function()
    local d,c={},config(); c.EnableShopDynamicInflation=false
    local q,id=S.issueQuote(d,c,0,"axe",100,3,true)
    eq(q.total,300); assert(S.consumeQuote(d,c,1,id,"axe",100,3,true))
    assert(S.commit(d,c,1,"axe",3,true)); eq(S.quote(d,c,1,"axe",100,1,true).layers,0)
end)

test("SP one-click purchase uses the stepped batch total without a dialog",function()
    load("client/GodSystem_ClientRuntime_Recycle.lua")
    local data,c,modal={stats={}},config(),nil
    local granted,charged=0,0
    local r={getData=function()return data end,isFeatureEnabled=function()return true end,
        text=function(_,fallback)return fallback end,notify=function()end,save=function()end,
        getShopPrimaryFullType=function()return nil end,getShopBaseUnitPrice=function()return 100 end,
        canAfford=function()return true end,shopItemIsAvailable=function(row)return true,nil,row.items end,
        giveItems=function(items)granted=granted+items[1].count;return items[1].count,nil,{} end,
        spendCurrency=function(price)charged=charged+price;return true,price,0 end,getShopLabel=function()return "Axe" end}
    local env=setmetatable({GodSystemApp={services={runtime=r}},GodSystemRuntimeConfig={Current=c},
        gsNowHours=function()return 0 end,gsPlayer=function()return {getPlayerNum=function()return 0 end}end,
        getCore=function()return {}end,GodSystemUI={presentOverlay=function()end},
        gsFormatText=function(s,args)for i,v in ipairs(args)do s=s:gsub("{"..i.."}",tostring(v))end;return s end,
        gsMultiplyItems=function(items,q)return {{fullType=items[1].fullType,count=q}} end,gsAppendHistory=function()end,
        ISModalDialog={new=function(_,x,y,w,h,message,yes,target,callback)
            modal={message=message,target=target,callback=callback,initialise=function()end};return modal end}}, {__index=_G})
    GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Recycle(env)
    local row={id="axe",items={{fullType="Base.Axe",count=1}}}
    assert(r.buyShopItem(row,10));eq(modal,nil);eq(granted,10);eq(charged,1450)
    assert(r.buyShopItem(row,1));eq(granted,11);eq(charged,1650)
end)

test("MP shop receipt, insufficient funds, delivery failure and stale quote preserve value",function()
    isServer=function()return true end
    load("shared/GodSystem_RecycleFingerprint.lua");load("server/GodSystem_TransactionOps.lua");load("server/GodSystem_ServerRuntime_Commerce.lua")
    local root,data,c={},{stats={}},config()
    local amount,items,failGrant,failPay,last=1000,0,false,false,nil
    local row={id="axe",items={{fullType="Base.Axe",count=1}}}
    local player={getInventory=function()return {}end}
    local env=setmetatable({Commands={},GodSystemRuntimeConfig={Current=c,isFeatureEnabled=function()return true end},
        applyRuntimeStores=function()end,store=function()return root end,userKey=function()return "owner" end,
        playerData=function()return data end,storeCheckpoint=function()return true end,
        guard=function()return true end,unguard=function()end,nowHours=function()return 0 end,
        floor=function(v,f)return math.floor(tonumber(v) or f or 0)end,
        shopById=function()return row end,shopUnitPrice=function()return 100 end,itemExists=function()return true end,
        canAfford=function(_,price)return amount>=price end,
        giveItem=function(_,_,q)if failGrant then return false,{}end;local a={};for i=1,q do a[i]={};items=items+1 end;return true,a end,
        removeItemFromContainer=function()items=items-1;return true end,
        spendCurrency=function(_,_,price)if failPay then return false,0,0 end;amount=amount-price;return true,price,0 end,
        GodSystemServer={refundCurrencySources=function(_,_,bank,cash)amount=amount+bank+cash;return true end},
        finishCode=function(_,ok,code,_,payload)last={ok=ok,code=code,payload=payload}end,
        appendHistory=function()end,shopHistoryEntry=function()return {}end,errorMessage=function(_,why)error(why)end}, {__index=_G})
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Commerce(env)
    local function request(seq,q)
        local _,id=S.issueQuote(data,c,0,S.key(row),100,q,true)
        return {id="axe",quantity=q,quoteId=id,opId="gs-1-1-"..seq}
    end
    local args=request(1,3);env.Commands.buyShop(nil,nil,player,args)
    eq(last.ok,true);eq(items,3);eq(amount,670);eq(data.stats.boughtItems,3)
    env.Commands.buyShop(nil,nil,player,args);eq(items,3);eq(amount,670)
    failGrant=true;env.Commands.buyShop(nil,nil,player,request(2,1));eq(last.code,"ItemGrantFailed");eq(amount,670)
    failGrant=false;failPay=true;env.Commands.buyShop(nil,nil,player,request(3,1));eq(items,3);eq(amount,670)
    failPay=false;local stale=request(4,1);c.ShopDynamicInflationHours=1
    env.Commands.buyShop(nil,nil,player,stale);eq(last.payload.kind,"shopQuote");eq(items,3);eq(amount,670)
    eq(S.quote(data,c,0,S.key(row),100,1,true).layers,3)
    local direct={id="axe",quantity=1,opId="gs-1-1-5"}
    env.Commands.buyShop(nil,nil,player,direct);eq(last.ok,true);eq(items,4);eq(amount,540)
    env.Commands.buyShop(nil,nil,player,direct);eq(items,4);eq(amount,540)
end)
test("offline time is excluded and reconnect resumes at a fresh baseline",function()
    local d,c={},config(); S.commit(d,c,0,"axe",1,true); S.advance(d,c,10,true)
    S.pause(d,c,10); S.advance(d,c,1000,true); eq(d.shopInflation.onlineMinute,10)
    S.advance(d,c,1010,true); eq(d.shopInflation.onlineMinute,20)
    -- A fresh VM / server process has no session baseline.
    load("shared/GodSystem_ShopInflation.lua"); S.advance(d,c,9000,true); eq(d.shopInflation.onlineMinute,20)
end)
test("offline accounts clear layers through persistent configuration generation",function()
    local root,d,c={},{},config(); S.observeConfig(root,c); S.commit(d,c,0,"axe",1,true)
    c.EnableShopDynamicInflation=false; S.observeConfig(root,c)
    c.EnableShopDynamicInflation=true; S.observeConfig(root,c)
    eq(S.quote(d,c,999,"axe",100,1,true).layers,0)
end)
test("all price configuration changes invalidate confirmation",function()
    local d,c={},config(); local _,id=S.issueQuote(d,c,0,"axe",100,1,true)
    c.ShopDynamicInflationHours=1; assert(not S.consumeQuote(d,c,0,id,"axe",100,1,true))
    _,id=S.issueQuote(d,c,0,"axe",100,1,true); c.ShopDynamicInflationPercent=20
    assert(not S.consumeQuote(d,c,0,id,"axe",100,1,true))
end)
test("fractional, free, overflow and unbounded-work requests are handled",function()
    local d,c={},config(); eq(S.quote(d,c,0,"axe",10.5,3,true).total,36)
    eq(S.quote(d,c,0,"free",0,3,true).total,0)
    for _,q in ipairs({1001,math.huge,-1,0.5}) do assert(not S.quote(d,c,0,"axe",1,q,true)) end
    assert(not S.quote(d,c,0,"axe",math.huge,1,true))
    assert(not S.quote(d,c,0,"axe",0/0,1,true))
    assert(not S.quote(d,c,0,"axe",9007199254740000,2,true))
end)
test("independent expiries and bounded quote storage and cleanup",function()
    local d,c={},config(); c.ShopDynamicInflationHours=1
    S.commit(d,c,0,"axe",1,true); S.commit(d,c,30,"axe",1,true)
    eq(S.quote(d,c,61,"axe",100,1,true).layers,1)
    for i=1,80 do S.issueQuote(d,c,61,"axe",100,1,true) end
    local count=0; for _ in pairs(d.shopInflation.quotes) do count=count+1 end; eq(count,1)
    S.advance(d,c,92,true); S.sweep(d,8); eq(d.shopInflation.listings.axe,nil)
end)
test("public state contains price layers but no private confirmation tokens",function()
    load("shared/GodSystem_StateProjection.lua")
    local d,c={},config(); S.commit(d,c,0,"axe",3,true); S.issueQuote(d,c,0,"axe",100,1,true)
    local result=GodSystemStateProjection.build(d)
    eq(result.shopInflation.listings.axe[1].count,3); eq(result.shopInflation.quotes,nil)
end)

test("task reward failure rolls back partial grants, preserves eligibility, and replay does not duplicate",function()
    load("server/GodSystem_ServerRuntime_EconomyTasks.lua")
    local given,removed,paid,fail=0,0,0,true
    local p={getInventory=function()return {} end}
    local env=setmetatable({Commands={},GodSystemEquipment=false,nowHours=function()return 1 end,
        giveItem=function() given=given+1; if fail and given==2 then return false,{} end; return true,{{id=given}} end,
        removeItemFromContainer=function()removed=removed+1;return true end,
        addPoints=function()paid=paid+1;return true end}, {__index=_G})
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_EconomyTasks(env)
    local t={status="active",rewardPoints=100,rewardItems={{fullType="axe"},{fullType="hammer"}}}
    assert(not env.grantTaskRewards(p,{},t)); eq(removed,1); eq(paid,0); eq(t.rewardReceipt,nil); eq(t.status,"active")
    fail=false; assert(env.grantTaskRewards(p,{},t)); eq(paid,1); eq(t.rewardReceipt,"done")
    local before=given; assert(env.grantTaskRewards(p,{},t)); eq(given,before);eq(paid,1)
end)

test("native command builder quotes names and rejects control characters and invalid coordinates",function()
    load("shared/GodSystem_Protocol.lua")
    local payload={native=true,targetUsername="Player One",pos={x=100.5,y=200,z=0}}
    eq(GodSystemProtocol.teleportCommand(payload),'/teleportto "Player One" 100.5,200,0')
    for _,name in ipairs({'bad"name','bad\\name','bad\nname',''}) do
        payload.targetUsername=name; eq(GodSystemProtocol.teleportCommand(payload),nil)
    end
    payload.targetUsername="ordinary";payload.pos.x=math.huge;eq(GodSystemProtocol.teleportCommand(payload),nil)
    payload.pos.x=100;payload.native=false;eq(GodSystemProtocol.teleportCommand(payload),nil)
end)

test("ordinary players delegate native teleport to an authorized online executor",function()
    load("server/GodSystem_ServerRuntime_HomeGrowth.lua")
    local ms,debits,refunds,sends=0,0,0,0
    local supersededId
    local allowFallback=true
    local p={x=0,y=0,z=0,getUsername=function()return "p" end,isDead=function()return false end}
    function p:getX()return self.x end; function p:getY()return self.y end; function p:getZ()return self.z end
    function p:getRole()return {hasCapability=function()return false end} end
    local admin={getUsername=function()return "admin" end,getRole=function()return {hasCapability=function()return true end}end}
    local online={p,admin}
    local data={homeSystem={},stats={},bank={current=0}}
    local env=setmetatable({Commands={},Capability={TeleportToCoordinates="coords",TeleportPlayerToAnotherPlayer="other"},
        GodSystemConfig={HomeTravelCost=10},GodSystemScheduler={nowMs=function()return ms end},
        GodSystemRuntimeConfig={get=function()return allowFallback end},
        GodSystemServer={refundCurrencySources=function(_,_,b,c)refunds=refunds+b+c end},
        Protocol=GodSystemProtocol,n=function(v)return tonumber(v) or 0 end,floor=function(v,f)return math.floor(v or f or 0)end,
        nowHours=function()return 0 end,userKey=function(v)return v:getUsername() end,playerData=function()return data end,
        getOnlinePlayers=function()return {size=function()return #online end,get=function(_,i)return online[i+1]end}end,
        getBank=function(d)return d.bank end,
        copyPosition=function(v)return {x=v.x,y=v.y,z=v.z}end,canAfford=function()return true end,
        spendCurrency=function()debits=debits+1;return true,7,3 end,randomIndex=function()return 1 end,
        sendServerCommand=function(executor,_,_,payload)
            eq(payload.targetUsername,"p")
            if payload.native then eq(executor,admin);eq(payload.fallback,nil)
            else
                eq(executor,p);eq(payload.native,false);eq(payload.fallback,"approvedClient")
                supersededId=payload.supersedes
            end
            sends=sends+1
        end,
        finish=function(_,ok)return ok end,finishCode=function(_,ok,code)return code end,
        appendHistory=function()end,historyEntry=function()return {}end}, {__index=_G})
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_HomeGrowth(env)
    env.sendTeleportRequest(p,data,"teleportHome",1,{x=100,y=100,z=0},"TeleportHome",{})
    local id=data.homeSystem.pendingTeleport.id
    env.Commands.teleportConfirm(nil,nil,p,{id=id,ok=false}); assert(data.homeSystem.pendingTeleport);eq(refunds,0)
    env.Commands.teleportConfirm(nil,nil,admin,{id=id,ok=true}); assert(data.homeSystem.pendingTeleport)
    env.sendTeleportRequest(p,data,"teleportHome",1,{x=100,y=100,z=0},"TeleportHome",{}); eq(debits,1)
    p.x=100;p.y=100; env.checkPendingTeleport(p,data);eq(data.homeSystem.pendingTeleport,nil)
    eq(data.stats.spentPoints,10);eq(refunds,0);eq(sends,1)
    env.Commands.teleportConfirm(nil,nil,p,{id=id,ok=true});eq(debits,1)
    env.sendTeleportRequest(p,data,"return",1,{x=0,y=0,z=0},"Return",{})
    local nativeId=data.homeSystem.pendingTeleport.id
    ms=16000;env.checkPendingTeleport(p,data);eq(refunds,0);eq(debits,2)
    eq(data.homeSystem.pendingTeleport.fallback,true)
    eq(supersededId,nativeId)
    env.Commands.teleportConfirm(nil,nil,admin,{id=nativeId,ok=false});eq(refunds,0)
    ms=32000;env.checkPendingTeleport(p,data);eq(refunds,10);eq(data.stats.spentPoints,10)
    online={p}
    allowFallback=false
    eq(env.sendTeleportRequest(p,data,"return",1,{x=0,y=0,z=0},"Return",{}),"TeleportExecutorUnavailable")
    eq(debits,2);eq(sends,3)
    allowFallback=true
    env.sendTeleportRequest(p,data,"return",1,{x=0,y=0,z=0},"Return",{})
    local fallbackId=data.homeSystem.pendingTeleport.id
    eq(data.homeSystem.pendingTeleport.fallback,true);eq(debits,3)
    env.Commands.teleportConfirm(nil,nil,admin,{id=fallbackId,ok=false});eq(refunds,10)
    env.Commands.teleportConfirm(nil,nil,p,{id=fallbackId,ok=true});assert(data.homeSystem.pendingTeleport)
    p.x=0;p.y=0;env.checkPendingTeleport(p,data);eq(data.homeSystem.pendingTeleport,nil);eq(data.stats.spentPoints,20)
    env.Commands.teleportConfirm(nil,nil,p,{id=fallbackId,ok=true});eq(debits,3)
    env.sendTeleportRequest(p,data,"teleportHome",1,{x=100,y=100,z=0},"TeleportHome",{})
    ms=48000;env.checkPendingTeleport(p,data);eq(refunds,20);eq(data.stats.spentPoints,20)
    online={p,admin}
    env.sendTeleportRequest(p,data,"teleportHome",1,{x=100,y=100,z=0},"TeleportHome",{})
    local refusedId=data.homeSystem.pendingTeleport.id
    local paidBefore=debits
    env.Commands.teleportConfirm(nil,nil,admin,{id=refusedId,ok=false})
    eq(data.homeSystem.pendingTeleport.fallback,true);eq(debits,paidBefore);eq(refunds,20)
    p.x=100;p.y=100
    -- Arrival must commit once even when a failure acknowledgement arrives late.
    env.Commands.teleportConfirm(nil,nil,p,{id=data.homeSystem.pendingTeleport.id,ok=false})
    eq(data.homeSystem.pendingTeleport,nil);eq(data.stats.spentPoints,30);eq(refunds,20)
    env.sendTeleportRequest(p,data,"return",1,{x=0,y=0,z=0},"Return",{})
    env.cleanupTeleportRequests({admin=true});eq(data.bank.current,10);eq(data.homeSystem.pendingTeleport,nil)
end)

test("attribute purchases use the vanilla server XP bridge and refund when unavailable",function()
    load("server/GodSystem_ServerRuntime_HomeGrowth.lua")
    local xp,paid,refunded,calls,result=0,0,0,0,nil
    local data={stats={spentPoints=0}}
    local receipts={}
    local bridge=function(_,_,amount) calls=calls+1; xp=xp+amount end
    local player={getXp=function()return {AddXP=function()error("direct XP mutation is forbidden")end}end}
    local env=setmetatable({Commands={},applyRuntimeStores=function()end,
        GodSystemAttributes={isEnabled=function()return true end,getXpPerCoin=function()return 2 end,
            quote=function()return {cost=10,currentXp=xp,actualXp=20,info={perk="perk",label="Skill",index=1}}end,
            getPlayerState=function()return {currentXp=xp,currentLevel=1}end},
        GodSystemServer={attributeOpId=function(args)return args.opId end,
            getAttributeOpResult=function(_,args)return receipts[args.opId]end,
            beginAttributeOp=function()return true end,
            rememberAttributeOpResult=function(_,args,ok,code,codeArgs,payload)
                receipts[args.opId]={status="done",ok=ok,code=code,args=codeArgs,payload=payload}
            end,
            refundCurrencySources=function(_,_,bank,cash)refunded=refunded+bank+cash;return true end},
        playerData=function()return data end,canAfford=function()return true end,
        spendCurrency=function()paid=paid+1;return true,10,0 end,
        guard=function()return true end,unguard=function()end,
        addXp=function(p,perk,amount)return bridge(p,perk,amount)end,
        SyncXp=function()end,appendHistory=function()end,historyEntry=function()return {}end,
        finishCode=function(_,ok,code)result={ok=ok,code=code}end}, {__index=_G})
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_HomeGrowth(env)
    env.Commands.attribute(nil,nil,player,{opId="xp-one"})
    eq(result.code,"AttributePurchased");eq(xp,20);eq(calls,1);eq(paid,1);eq(refunded,0)
    env.Commands.attribute(nil,nil,player,{opId="xp-one"})
    eq(calls,1);eq(paid,1)
    env.addXp=nil
    env.Commands.attribute(nil,nil,player,{opId="xp-two"})
    eq(result.code,"AttributeApplyFailed");eq(xp,20);eq(refunded,10)
end)
