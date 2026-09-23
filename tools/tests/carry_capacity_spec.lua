local passed = 0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name, fn) fn(); passed=passed+1; print("PASS carry: "..name) end
local multiplayer, server, clock = false, false, 1000
function isClient() return multiplayer end
function isServer() return server end
function getTimestampMs() return clock end
function require(name) assert(name=="GodSystem_Config"); return {} end
assert(loadstring(readSource("shared/GodSystem_CarryCapacity.lua")))()
local C=GodSystemCarryCapacity
local function player(base, data)
    local p={base=base or 8,delta=1,factor=1.58,final=12,md=data or {},writes=0,recomputes=0,id=1}
    function p:getMaxWeightBase() return self.base end
    function p:setMaxWeightBase(v) self.base=v; self.writes=self.writes+1 end
    function p:getMaxWeightDelta() return self.delta end
    function p:setMaxWeightDelta(v) self.delta=v end
    function p:getMaxWeight() return self.final end
    function p:setMaxWeight(v) self.final=v end
    function p:getWeightMod() return self.factor end
    function p:getModData() return self.md end
    function p:getOnlineID() return self.id end
    function p:isDead() return false end
    p.body={UpdateStrength=function() p.recomputes=p.recomputes+1; p.final=math.floor(math.max(0,math.floor(p.base*p.factor)-(p.reducers or 0))*p.delta) end}
    function p:getBodyDamage() return self.body end
    return p
end
test("standalone restores once and preserves native delta and conditions",function()
    local p=player(); p.delta=1.5; p.reducers=2
    assert(C.restore(p,3)); eq(p.base,14); eq(p.final,30); eq(p.delta,1.5)
    for i=1,100 do assert(C.restore(p,3)) end
    eq(p.writes,1); eq(p.recomputes,1)
    p.factor=2.5; p.body:UpdateStrength(); assert(C.restore(p,3)); eq(p.final,49); eq(p.writes,1)
end)
test("external additive change is preserved without duplicating our bonus",function()
    local p=player(); assert(C.restore(p,3)); p.base=15
    for i=1,20 do local ok,why=C.restore(p,3); eq(ok,false); eq(why,"externalConflict") end
    eq(p.base,15); eq(p.writes,1); eq(C.getStatus(p,3).reason,"externalConflict")
    eq(C.getPersistedLevel(p),3)
end)
test("known reset retries after cooldown and backs off under repeated competition",function()
    local p=player(); assert(C.restore(p,3))
    p.base=8; assert(C.restore(p,3)); eq(p.base,14)
    p.base=8; assert(C.restore(p,3)); eq(p.base,14)
    p.base=8; local ok,why=C.restore(p,3); eq(ok,false); eq(why,"resetCooldown"); eq(p.base,8)
    eq(C.getStatus(p,3).reason,"resetCooldown")
    local writes=p.writes
    for i=1,29 do clock=clock+1000; eq(C.restore(p,3),false) end
    eq(p.writes,writes)
    clock=clock+1000; assert(C.restore(p,3)); eq(p.base,14); eq(p.writes,writes+1)
    for _,delay in ipairs({60000,120000,240000,300000,300000}) do
        p.base=8; ok,why=C.restore(p,3); eq(ok,false); eq(why,"resetCooldown")
        writes=p.writes; clock=clock+delay-1; eq(C.restore(p,3),false); eq(p.writes,writes)
        clock=clock+1; assert(C.restore(p,3)); eq(p.base,14); eq(p.writes,writes+1)
    end
    clock=clock+60000; assert(C.restore(p,3))
    p.base=8; assert(C.restore(p,3)); eq(p.base,14)
end)
test("expired reset cooldown never authorizes an unknown base",function()
    local p=player(); assert(C.restore(p,3))
    for i=1,2 do p.base=8; assert(C.restore(p,3)) end
    p.base=8; eq(C.restore(p,3),false)
    p.base=15; local writes=p.writes
    for i=1,10 do
        clock=clock+60000; local ok,why=C.restore(p,3)
        eq(ok,false); eq(why,"externalConflict"); eq(p.base,15)
        eq(C.getStatus(p,3).reason,"externalConflict")
    end
    eq(p.writes,writes)
    p.base=8; assert(C.restore(p,3)); eq(p.base,14)
end)
test("delayed initialization recheck refreshes native cache once without adding again",function()
    local p=player(); assert(C.restore(p,3)); p.final=12
    clock=clock+2999; assert(C.restore(p,3)); eq(p.final,12)
    clock=clock+1; assert(C.restore(p,3)); eq(p.final,22); eq(p.writes,1); eq(p.recomputes,2)
    for i=1,100 do clock=clock+1000; assert(C.restore(p,3)) end
    eq(p.writes,1); eq(p.recomputes,2)
    C.scheduleRecheck(p); p.base=8; clock=clock+3000
    assert(C.restore(p,3)); eq(p.base,14); eq(p.recomputes,3)
end)
test("load and respawn rebuild from account instead of old object values",function()
    local old=player(10); assert(C.restore(old,4)); eq(old.base,18)
    local fresh=player(8,old.md); assert(C.restore(fresh,4)); eq(fresh.base,16)
    local respawn=player(); assert(C.restore(respawn,4)); eq(respawn.base,16)
    for i=1,5 do assert(C.restore(fresh,4)) end
    eq(fresh.base,16)
end)
test("legacy owned value is removed exactly once",function()
    local p=player(14,{GodSystemCarryCapacityLevel=3,GodSystemCarryExternalBase=8,GodSystemCarryAppliedBase=14})
    assert(C.restore(p,4)); eq(p.base,16)
    assert(C.restore(p,4)); eq(p.base,16)
end)
test("zero contribution permits new external base",function()
    local p=player(); assert(C.restore(p,0)); p.base=11
    assert(C.restore(p,1)); eq(p.base,13)
end)
test("authoritative zero overrides markers; MP never imports marker levels",function()
    local p=player(8,{GodSystemCarryCapacityLevel=100})
    eq(C.getLevel({upgrades={carryCapacityLevel=0}},p),0)
    eq(C.getLevel({},p),100)
    server=true; eq(C.getLevel({},p),0); server=false
    multiplayer=true; eq(C.getLevel({},p),0); eq(C.restore(p,99),false); multiplayer=false
end)
test("failed payment snapshot restores exact base, markers and runtime",function()
    local p=player(); assert(C.restore(p,2)); local before=C.capture(p)
    assert(C.restore(p,3,true)); eq(p.base,14)
    assert(C.rollback(p,before)); eq(p.base,12); eq(C.getPersistedLevel(p),2)
    assert(C.restore(p,2)); eq(p.base,12)
end)
test("partial setter failure restores pre-operation fields and markers",function()
    local p=player()
    function p:setMaxWeightBase(v) self.base=v==10 and 9 or v end
    local ok,why=C.restore(p,1); eq(ok,false); eq(why,"writeFailed")
    eq(p.base,8); eq(p.final,12); eq(p.md.GodSystemCarryCapacityLevel,nil)
end)
test("overflow and terminal level are unavailable",function()
    local p=player(); eq(C.restore(p,1073741823),false); eq(p.base,8)
    eq(C.getNextCost(1073741823),nil); eq(C.getNextCost(100),2000)
end)
local function ucwf()
    local f={baseModifiers={},calls=0,registrations=0}
    f.baseModifiers.OtherMod={resolve=function() return {add=1} end}
    function f.registerBaseModifier(def) f.registrations=f.registrations+1; f.baseModifiers[def.id]=def end
    function f.recomputeAll(p)
        f.calls=f.calls+1; local base=8
        for _,def in pairs(f.baseModifiers) do base=base+(def.resolve({player=p}).add or 0) end
        p:setMaxWeightBase(base); p:setMaxWeightDelta(1)
    end
    return f
end
test("framework receives one delayed initialization recomputation",function()
    local f=ucwf(); UnifiedCarryWeightFramework=f
    local p=player(); assert(C.restore(p,3)); eq(p.base,15)
    f.baseModifiers.LateMod={resolve=function()return {add=4} end}
    clock=clock+3000; assert(C.restore(p,3)); eq(p.base,19); eq(f.calls,2)
    for i=1,3 do C.onSettleTick() end
    for i=1,100 do clock=clock+1000; assert(C.restore(p,3)) end
    eq(f.calls,2); eq(C.getStatus(p,3).reason,"ok")
    UnifiedCarryWeightFramework=nil
end)
test("optional UCWF registration coexists; repeated maintenance does not overwrite",function()
    local f=ucwf(); UnifiedCarryWeightFramework=f
    local p=player(); assert(C.restore(p,3)); eq(p.base,15); eq(f.registrations,1)
    local other=f.baseModifiers.OtherMod
    for i=1,100 do assert(C.restore(p,3)) end
    eq(f.calls,1); eq(f.registrations,1); eq(f.baseModifiers.OtherMod,other)
    eq(C.getStatus(p,3).reason,"pending")
    for i=1,3 do C.onSettleTick() end
    eq(C.getStatus(p,3).reason,"ok")
    UnifiedCarryWeightFramework=nil
end)
test("native to framework handover contributes once and rollback restores resolver",function()
    local p=player(); assert(C.restore(p,2)); eq(p.base,12)
    local f=ucwf(); UnifiedCarryWeightFramework=f
    assert(C.restore(p,2)); eq(p.base,13)
    local before=C.capture(p); assert(C.restore(p,3,true)); eq(p.base,15)
    assert(C.rollback(p,before)); f.recomputeAll(p); eq(p.base,13)
    eq(f.baseModifiers["GodSystem.CarryCapacity"].resolve({player=p}).add,4)
    for i=1,3 do C.onSettleTick() end
    eq(C.getStatus(p,2).reason,"ok"); eq(C.pendingPlayers[p],nil)
    UnifiedCarryWeightFramework=nil
end)
test("framework cap rejects purchase but retains existing level",function()
    UnifiedCarryWeightFramework=ucwf(); SandboxVars={UnifiedCarryWeightFramework={CapWeight=true}}
    local p=player(); p.final=50
    eq(C.restore(p,1,true),false); eq(p.base,8)
    assert(C.restore(p,1)); eq(p.base,11)
    UnifiedCarryWeightFramework=nil; SandboxVars=nil
end)
test("native MP projection uses server level once and rejects stale/foreign state",function()
    local host=player(); assert(C.restore(host,3)); local snapshot=C.makeSnapshot(host,3)
    multiplayer=true
    local p=player(); assert(C.acceptSnapshot(p,snapshot)); eq(p.base,14)
    eq(C.acceptSnapshot(p,snapshot),false); eq(p.base,14)
    for i=1,20 do assert(C.updateClient(p)) end
    eq(p.writes,1)
    local bad={}; for k,v in pairs(snapshot) do bad[k]=v end
    bad.playerId=2; bad.revision=100; bad.level=999; eq(C.acceptSnapshot(p,bad),false); eq(p.base,14)
    p.base=15; eq(C.updateClient(p),false); eq(p.base,15)
    multiplayer=false
end)
test("UCWF MP projects the approved aggregate without another addition",function()
    multiplayer=true
    local p=player()
    assert(C.acceptSnapshot(p,{level=3,mode="ucwf",reason="ok",token="session",playerId=1,revision=1,base=15,delta=1.5}))
    eq(p.base,15); eq(p.final,34)
    for i=1,20 do assert(C.updateClient(p)) end
    eq(p.writes,1)
    p.base=16; eq(C.updateClient(p),false); eq(p.base,16)
    eq(C.getStatus(p,3).reason,"externalConflict")
    eq(C.acceptSnapshot(p,{level=3,mode="ucwf",reason="ok",token="session",playerId=1,revision=2,base=17,delta=1.5}),false)
    eq(p.base,16)
    C.resetClient(); eq(C.updateClient(p),false)
    multiplayer=false
end)
test("MP native projection retains cooldown and automatically retries",function()
    local host=player(); assert(C.restore(host,3)); local snapshot=C.makeSnapshot(host,3)
    multiplayer=true; local p=player(); assert(C.acceptSnapshot(p,snapshot))
    for i=1,2 do p.base=8; assert(C.updateClient(p)) end
    p.base=8; eq(C.updateClient(p),false); eq(C.getStatus(p,3).reason,"resetCooldown")
    local writes=p.writes; clock=clock+29999
    eq(C.updateClient(p),false); eq(p.writes,writes)
    clock=clock+1; assert(C.updateClient(p)); eq(p.base,14)
    p.base=15; clock=clock+600000; eq(C.updateClient(p),false); eq(p.base,15)
    multiplayer=false
end)
test("malformed scalar snapshots are rejected before mutation",function()
    multiplayer=true; local p=player()
    local s={level=3,mode="ucwf",reason="ok",token="session",playerId=1,revision=1,base=15.5,delta=1}
    eq(C.acceptSnapshot(p,s),false); eq(p.writes,0)
    s.base=15; s.level="3"; eq(C.acceptSnapshot(p,s),false)
    s.level=3; s.revision=1.5; eq(C.acceptSnapshot(p,s),false)
    s.revision=1; s.delta=0/0; eq(C.acceptSnapshot(p,s),false)
    multiplayer=false
end)
test("failed native upgrade never charges through SP purchase adapter",function()
    local p=player(); assert(C.restore(p,2)); p.base=13
    local data={upgrades={carryCapacityLevel=2},stats={spentPoints=0}}
    local charges=0
    local runtime={getData=function()return data end,getCarryCapacityLevel=function()return 2 end,
        text=function(_,fallback)return fallback end,notify=function()end,canAfford=function()return true end,
        addPoints=function()charges=charges+1;return true end,getCarryCapacityStateText=function()return "conflict" end}
    local env=setmetatable({GodSystemApp={services={runtime=runtime}},gsPlayer=function()return p end},{__index=_G})
    assert(loadstring(readSource("client/GodSystem_ClientRuntime_BankGrowth.lua")))()
    GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_BankGrowth(env)
    eq(runtime.upgradeSystem("carryCapacity"),false); eq(charges,0); eq(data.upgrades.carryCapacityLevel,2); eq(p.base,13)
end)
test("failed SP charge returns the exact previous state",function()
    local p=player(); assert(C.restore(p,2)); local data={upgrades={carryCapacityLevel=2},stats={spentPoints=0}}
    local runtime={getData=function()return data end,getCarryCapacityLevel=function()return 2 end,
        text=function(_,fallback)return fallback end,notify=function()end,canAfford=function()return true end,
        addPoints=function()return false end}
    local env=setmetatable({GodSystemApp={services={runtime=runtime}},gsPlayer=function()return p end},{__index=_G})
    GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_BankGrowth(env)
    eq(runtime.upgradeSystem("carryCapacity"),false); eq(p.base,12); eq(C.getPersistedLevel(p),2)
    eq(data.upgrades.carryCapacityLevel,2); eq(data.stats.spentPoints,0)
end)
test("server purchase retries are idempotent and payment failures roll back",function()
    server=true
    assert(loadstring(readSource("shared/GodSystem_RecycleFingerprint.lua")))()
    assert(loadstring(readSource("server/GodSystem_TransactionOps.lua")))()
    assert(loadstring(readSource("server/GodSystem_ServerRuntime_Services.lua")))()
    local function fixture(p, canPay)
        local data={upgrades={carryCapacityLevel=2},stats={spentPoints=0}}
        local root={players={owner=data}}
        local charges,results=0,{}
        local env=setmetatable({Commands={},GodSystemServer={},playerData=function()return data end,store=function()return root end,
            userKey=function()return "owner" end,guard=function()return true end,unguard=function()end,
            storeCheckpoint=function()return true end,appendHistory=function()end,historyEntry=function()return {} end,
            addPoints=function(_,amount) eq(amount,-2000); charges=charges+1; return canPay end,
            finishCode=function(_,ok,code) results[#results+1]={ok=ok,code=code} end,
            errorMessage=function(_,err) error(err) end},{__index=_G})
        GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Services(env)
        local args={upgradeType="carryCapacity",opId="gs-1-2-3"}
        env.Commands.upgradeSystem(nil,nil,p,args)
        env.Commands.upgradeSystem(nil,nil,p,args)
        return data,charges,results
    end
    local paid=player(); assert(C.restore(paid,2))
    local data,charges,results=fixture(paid,true)
    eq(data.upgrades.carryCapacityLevel,3); eq(data.stats.spentPoints,2000); eq(charges,1); eq(paid.base,14)
    eq(#results,2); eq(results[1].code,"CarryCapacityUpgraded"); eq(results[2].ok,true)
    local declined=player(); assert(C.restore(declined,2))
    data,charges,results=fixture(declined,false)
    eq(data.upgrades.carryCapacityLevel,2); eq(data.stats.spentPoints,0); eq(charges,1); eq(declined.base,12)
    eq(results[2].code,"CurrencyNotEnough")
    local conflict=player(); assert(C.restore(conflict,2)); conflict.base=13
    data,charges,results=fixture(conflict,true)
    eq(charges,0); eq(conflict.base,13); eq(results[2].code,"CarryCapacityApplyFailed")
    server=false
end)
test("server tick maintains remote players and sends only changed state",function()
    server=true
    assert(loadstring(readSource("shared/GodSystem_Scheduler.lua")))()
    local p,dead=player(),player(); p.id=11; dead.id=12
    function dead:isDead()return true end
    local active={p,dead}; local root={players={[11]={upgrades={carryCapacityLevel=3}}}}
    local reads,sends=0,{}
    local events={}; for _,name in ipairs({"OnTick","OnPlayerUpdate","OnClientCommand"}) do
        events[name]={Add=function()end,Remove=function()end}
    end
    local env=setmetatable({Events=events,Commands={},MODULE="GodSystem",Protocol={S2C={CarryState="carryState"}},
        getOnlinePlayers=function()return {size=function()return #active end,get=function(_,i)return active[i+1] end} end,
        store=function()reads=reads+1;return root end,userKey=function(target)return target.id end,
        playerData=function()error("known account should not be normalized every tick") end,
        sendServerCommand=function(target,module,command,snapshot)
            eq(target,p); eq(module,"GodSystem"); eq(command,"carryState"); sends[#sends+1]=snapshot
        end},{__index=_G})
    assert(loadstring(readSource("server/GodSystem_ServerRuntime_Background.lua")))()
    GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Background(env)
    env.onCarryTick(); eq(p.base,14); eq(dead.writes,0); eq(#sends,1)
    for i=1,100 do env.onCarryTick() end
    eq(reads,1); eq(p.writes,1)
    clock=clock+1000; env.onCarryTick(); eq(#sends,1); eq(reads,2)
    p.base=15; clock=clock+1000; env.onCarryTick(); eq(#sends,2); eq(sends[2].reason,"externalConflict"); eq(p.base,15)
    clock=clock+1000; env.onCarryTick(); eq(#sends,2)
    local fresh=player(8,p.md); fresh.id=11; p=fresh; active={fresh}
    clock=clock+1000; env.onCarryTick(); eq(#sends,3); eq(fresh.base,14)
    assert(sends[3].token~=sends[1].token)
    server=false
end)
test("actual SP create and game-start hooks schedule a bounded delayed check",function()
    local p=player(); local events={}
    for _,name in ipairs({"OnInitGlobalModData","OnGameStart","OnCreatePlayer","OnPlayerUpdate","OnPlayerDeath","OnGameExit"}) do
        events[name]={Add=function(fn)events[name].callback=fn end}
    end
    local r={getData=function()return {} end, ensureCurrencyInitialized=function()end,
        restoreCarryCapacity=function(target)return C.restore(target,3) end}
    local env=setmetatable({Events=events,GodSystemShopInflation={pause=function()end},GodSystemRuntimeConfig={Current={}},gsNowHours=function()return 0 end,GodSystemApp={services={runtime=r}},gsPlayer=function()return p end}, {__index=_G})
    assert(loadstring(readSource("client/GodSystem_ClientRuntime_Tasks.lua")))()
    GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Tasks(env)
    r.generateDailyTasks=function()end
    events.OnCreatePlayer.callback(0,p); eq(p.base,14)
    clock=clock+1000; events.OnGameStart.callback(); eq(p.writes,1)
    p.final=12; clock=clock+2999; assert(C.restore(p,3)); eq(p.final,12)
    clock=clock+1; assert(C.restore(p,3)); eq(p.final,22); eq(p.recomputes,2)
    p=player(); events.OnCreatePlayer.callback(0,p); eq(p.base,14)
    p.base=8; clock=clock+3000; assert(C.restore(p,3)); eq(p.base,14)
end)
print("Carry capacity cases passed: "..passed)
