-- Real controller/fallback; native timed actions are isolated fixtures.
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function fixture(mp)
    local e=setmetatable({}, {__index=_G}); e.require=function() end
    local function load(path) local f=assert(loadstring(readSource(path))); setfenv(f,e); return f() end
    e.time,e.requests,e.payments,e.queue=1000,0,0,{}
    local callbacks={}
    e.Events={OnTick={Add=function(fn) callbacks[fn]=true end,Remove=function(fn) callbacks[fn]=nil end},
        OnGameStart={Add=function() end},OnDisconnect={Add=function() end}}
    e.events=callbacks
    e.GodSystemScheduler={nowMs=function() return e.time end}; e.isClient=function() return mp end
    e.config="stable"; e.GodSystemRuntimeConfig={recyclePreparationToken=function() return e.config end}
    e.player={rows={}}
    function e.player:getInventory() return self end
    function e.player:getItems() return {size=function() return #self.rows end,get=function(_,i) return self.rows[i+1] end} end
    function e.player:isDead() return false end
    e.getSpecificPlayer=function() return e.player end; e.getPlayer=e.getSpecificPlayer
    e.item={id=41,fullType="Base.Bullets9mm",world={},source={}}
    function e.item:getID() return self.id end
    function e.item:getFullType() return self.fullType end
    function e.item:getContainer() return self.source end
    function e.item:getWorldItem() return self.world end
    e.descriptor={kind="worldItem",itemId="41",x=0,y=0,z=0}
    e.GodSystemExternalRecycle={describe=function(item) return item.world and e.descriptor end,
        resolve=function() if e.sourceReady~=false then return {item=e.item} end return nil,"changed" end,
        sameSource=function(a,b) return a.itemId==b.itemId and a.kind==b.kind end,
        canFallbackSources=function(sources) return #sources>0 and sources[1].kind=="worldItem" end}
    e.ISTimedActionQueue={add=function(action) e.queue[#e.queue+1]=action end,
        getTimedActionQueue=function() return {queue=e.queue} end}
    e.ISWorldObjectContextMenu={grabItemTime=function() return 20 end}
    e.ISGrabItemAction={new=function(_,player,world,time)
        eq(player,e.player); eq(world,e.item.world); eq(time,20); return {pickup=true}
    end}
    e.ISWaitWhileGettingUp={new=function() return {setOnComplete=function(self,fn,arg) self.fn,self.arg=fn,arg end} end}
    e.GodSystemNetwork={pendingOperationId="op-1"}; e.GodSystemApp={services={runtime={}}}
    e.GodSystemInventoryContext={register=function() end}
    local r=e.GodSystemApp.services.runtime
    r.text=function(_,fallback) return fallback end; r.notify=function(message) e.lastMessage=message end
    r.recycleSelectedItems=function(_mode,ids,_allow,_signatures,_skipped,sources)
        e.requests=e.requests+1
        if #sources>0 then if mp then return true end; return false,"deleteFailed",{fallbackAllowed=true} end
        eq(#ids,1); eq(ids[1],"41"); e.payments=e.payments+1; return true
    end
    load("shared/GodSystem_B42JavaCalls.lua"); load("shared/GodSystem_InventoryIndex.lua")
    load("client/GodSystem_RecycleFallback.lua"); load("client/GodSystem_RecycleContext.lua")
    e.payload={playerNum=0,mode="recycle",items={e.item},containerContentSignatures={}}
    function e.tick() e.GodSystemRecycleFallback.onTick() end
    function e.finish(pickup)
        if pickup then e.player.rows={e.item}; e.item.source=e.player; e.item.world=nil end
        local barrier=e.queue[#e.queue]; assert(barrier and barrier.fn); barrier.fn(barrier.arg); e.tick()
    end
    return e
end

for _,mp in ipairs({false,true}) do
    local e=fixture(mp); local f=e.GodSystemRecycleFallback
    assert(e.GodSystemRecycleContext.execute(e.payload)); eq(e.requests,1); eq(e.payments,0)
    if mp then
        assert(not f.isBusy())
        assert(not f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="old",data={fallbackAllowed=true}}))
        assert(f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=true}}))
        assert(not f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=true}}))
    end
    assert(f.isBusy()); e.tick(); eq(#e.queue,2)
    e.finish(true); eq(e.requests,2); eq(e.payments,1); assert(not f.isBusy())
    for _ in pairs(e.events) do error("fallback left a tick listener") end
end
print("PASS fallback: SP/MP restored failure picks up/recycles once; receipt replay ignored")

do
    local e=fixture(true); local f=e.GodSystemRecycleFallback
    for _,code in ipairs({"TransactionOperationUnknown","CommandTimeout","RecycleSourceLocked","RecycleSelectionSuccess"}) do
        assert(e.GodSystemRecycleContext.execute(e.payload))
        assert(not f.handleResult({ok=code=="RecycleSelectionSuccess",code=code,operationId="op-1",data={fallbackAllowed=true}}))
        eq(#e.queue,0); assert(not f.isBusy())
    end
    assert(e.GodSystemRecycleContext.execute(e.payload))
    assert(not f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=false}}))
    assert(e.GodSystemRecycleContext.execute(e.payload)); f.cancelPending()
    assert(not f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=true}}))
end
print("PASS fallback: unknown/timeout/permission/failed restoration/stale reply never pick up")

for _,failure in ipairs({"partial","cancel","config","session","missing"}) do
    local e=fixture(false); local f=e.GodSystemRecycleFallback
    assert(e.GodSystemRecycleContext.execute(e.payload))
    if failure=="missing" then
        e.sourceReady=false; e.tick(); eq(#e.queue,0); e.time=7000; e.tick()
    elseif failure=="config" then e.config="changed"; e.tick()
    elseif failure=="session" then e.player={}; e.tick()
    else e.tick(); if failure=="partial" then e.finish(false) else e.queue={}; e.time=1400; e.tick() end end
    eq(e.payments,0); eq(e.requests,1); assert(not f.isBusy())
    for _ in pairs(e.events) do error("failed fallback left a tick listener") end
end
print("PASS fallback: incomplete pickup/interruption/config/session/missing targets cancel cleanly")

do
    local e=fixture(false); local f=e.GodSystemRecycleFallback
    assert(e.GodSystemRecycleContext.execute(e.payload)); e.tick()
    local barrier=e.queue[#e.queue]; f.reset(); barrier.fn(barrier.arg)
    eq(e.requests,1); eq(e.payments,0)
    e.payload.fallbackUsed=true; eq(e.GodSystemRecycleContext.execute(e.payload),false); assert(not f.isBusy())
end
print("PASS fallback: canceled barrier is inert; backup cannot recurse")

do
    local e=fixture(true); local f=e.GodSystemRecycleFallback
    assert(e.GodSystemRecycleContext.execute(e.payload))
    assert(f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=true}}))
    e.sourceReady=false; e.tick(); eq(#e.queue,0)
    e.sourceReady=true; e.time=1200; e.tick(); eq(#e.queue,2)
    e.finish(false); eq(e.payments,0); assert(f.isBusy())
    e.player.rows={e.item}; e.item.source=e.player; e.item.world=nil
    e.time=1400; e.tick(); eq(e.payments,1); eq(e.requests,2); assert(not f.isBusy())
end
print("PASS fallback: late restored-object and inventory packets wait without premature cancellation")

do
    local e=fixture(true); local f=e.GodSystemRecycleFallback
    assert(e.GodSystemRecycleContext.execute(e.payload))
    assert(f.handleResult({ok=false,code="RecycleDeleteRestored",operationId="op-1",data={fallbackAllowed=true}}))
    e.tick(); e.finish(false); e.time=7000; e.tick()
    eq(e.payments,0); eq(e.requests,1); assert(not f.isBusy())
end
print("PASS fallback: inventory synchronization timeout never resubmits")
