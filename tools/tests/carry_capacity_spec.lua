local passed = 0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name, fn) fn(); passed=passed+1; print("PASS carry: "..name) end
local multiplayer, server, clock = false, false, 1000
function isClient() return multiplayer end
function isServer() return server end
function getTimestampMs() return clock end
function require(name) assert(name=="GodSystem_Config"); return {} end
CharacterTrait={STRONG="strong",WEAK="weak",FEEBLE="feeble",STOUT="stout"}
local callbacks={}
Events={OnTick={Add=function(fn)callbacks[fn]=true end,Remove=function(fn)callbacks[fn]=nil end}}
assert(loadstring(readSource("shared/GodSystem_CarryCapacity.lua")))()
local C=GodSystemCarryCapacity
local function player(base, data)
    local p={base=base or 8,delta=1,factor=1.58,final=12,md=data or {},writes=0,recomputes=0,id=1,flags={}}
    function p:getMaxWeightBase() return self.base end
    function p:setMaxWeightBase(v) self.base=v; self.writes=self.writes+1 end
    function p:getMaxWeightDelta() return self.delta end
    function p:setMaxWeightDelta(v) self.delta=v; self.writes=self.writes+1 end
    function p:getMaxWeight() return self.final end
    function p:setMaxWeight(v) self.final=v; self.writes=self.writes+1 end
    function p:getWeightMod() return self.factor end
    function p:getModData() return self.md end
    function p:getOnlineID() return self.id end
    function p:isDead() return self.dead==true end
    function p:getCharacterTraits() return {get=function(_,token)return p.flags[token]==true end} end
    p.body={UpdateStrength=function() p.recomputes=p.recomputes+1; p.final=math.floor(math.max(0,math.floor(p.base*p.factor)-(p.reducers or 0))*p.delta) end}
    function p:getBodyDamage() return self.body end
    return p
end
local function tick() clock=clock+100; C.onGuardTick() end
test("priority ignores external baseline and preserves native conditions",function()
    local p=player(15); p.flags.strong=true; p.reducers=2
    assert(C.restore(p,3)); eq(p.base,14); eq(p.final,30); eq(p.delta,1.5)
    local writes=p.writes
    for i=1,100 do assert(C.restore(p,3)) end
    eq(p.writes,writes); eq(p.recomputes,1)
    p.factor=2.5; p.body:UpdateStrength(); tick(); eq(p.final,49)
end)
test("external base and final-only writes are restored without conflict or cooldown",function()
    local p=player(); assert(C.restore(p,3))
    for i=1,100 do p.base=15; p.final=1; tick(); eq(p.base,14); eq(p.final,22) end
    p.final=12; eq(C.getStatus(p,3).reason,"correcting"); tick(); eq(p.final,22)
    assert(C.restore(p,4,true)); eq(p.base,16)
end)
test("all native traits and float roundtrip, zero final, trait changes",function()
    for _,row in ipairs({{"strong",1.5},{"weak",0.75},{"feeble",0.8999999761581421},{"stout",1.25}}) do
        local p=player(); p.flags[row[1]]=true; assert(C.restore(p,1)); eq(p.delta,row[2])
        local writes=p.writes; for i=1,100 do tick() end; eq(p.writes,writes)
        p.flags={}; assert(C.restore(p,1)); eq(p.delta,1)
        p.reducers=999; p.body:UpdateStrength(); tick(); eq(p.final,0); assert(C.restore(p,2))
    end
    local p=player(); p.flags.strong=true;p.flags.weak=true;assert(C.restore(p,1));eq(p.delta,1.5)
end)
test("zero leaves other mods alone, owned contribution released, load uses account",function()
    local p=player(11);p.delta=3;assert(C.restore(p,0));eq(p.base,11);eq(p.delta,3);eq(p.writes,0)
    assert(C.restore(p,1));eq(p.base,10);eq(p.delta,1)
    assert(C.restore(p,0));eq(p.base,8);eq(C.activePlayers[p],nil)
    p.base=19;assert(C.restore(p,0));eq(p.base,19)
    local fresh=player(8,{GodSystemCarryCapacityLevel=3,GodSystemCarryMode="ucwf"});assert(C.restore(fresh,3));eq(fresh.base,14)
    eq(C.getLevel({upgrades={carryCapacityLevel=0}},fresh),0)
    eq(C.getLevel({},fresh),3);server=true;eq(C.getLevel({},fresh),0);server=false
    multiplayer=true;eq(C.getLevel({},fresh),0);multiplayer=false
end)
test("first purchase and existing purchase rollback restores participation and markers",function()
    local p=player(11);local before=C.capture(p);assert(C.restore(p,1,true));assert(C.rollback(p,before))
    eq(p.base,11);eq(p.final,12);eq(C.activePlayers[p],nil);eq(p.md.GodSystemCarryCapacityLevel,nil)
    assert(C.restore(p,2));before=C.capture(p);assert(C.restore(p,3,true));assert(C.rollback(p,before))
    eq(p.base,12);eq(C.getPersistedLevel(p),2);eq(C.activePlayers[p],true)
end)
test("partial native write failure, lookup exceptions, retry gate and numeric limits",function()
    local p=player();function p:setMaxWeightBase(v) self.base=v==10 and 9 or v end
    eq(C.restore(p,1),false);eq(p.base,8);eq(p.final,12);eq(C.activePlayers[p],nil)
    local unreadable=player();function unreadable:getMaxWeight()return nil end
    eq(C.restore(unreadable,1,true),false);eq(unreadable.base,8);eq(unreadable.writes,0);eq(C.activePlayers[unreadable],nil)
    local q=player();q.getCharacterTraits=nil
    setmetatable(q,{__index=function()error("invalid object lookup")end})
    eq(C.restore(q,1),false);eq(q.writes,0)
    local r=player();r.factor=0/0;eq(C.restore(r,1),false);eq(r.writes,0)
    r.factor=math.huge;clock=clock+5000;eq(C.restore(r,1),false)
    r.factor=1.58;clock=clock+5000;assert(C.restore(r,1))
    local huge=player();eq(C.restore(huge,1073741823),false);eq(huge.base,8)
    eq(C.getNextCost(1073741823),nil)
end)
test("invalid liveness is retried every five seconds, not on every field tick",function()
    C.resetClient();local p=player();assert(C.restore(p,3))
    local reads=0;function p:isDead()reads=reads+1;error("invalid native liveness")end
    for i=1,300 do tick() end
    eq(reads,6);eq(C.activePlayers[p],true)
    function p:isDead()return false end
    clock=clock+5000;C.onGuardTick();eq(C.getStatus(p,3).reason,"ok")
end)
test("framework is never registered, only identity-owned contribution removed",function()
    local other={resolve=function()return {add=99}end}
    local f={baseModifiers={OtherMod=other},registerBaseModifier=function()error("must not register")end}
    UnifiedCarryWeightFramework=f
    local p=player();assert(C.restore(p,30));eq(p.base,68);eq(f.baseModifiers.OtherMod,other)
    local own={};C.frameworkModifier=own;f.baseModifiers["GodSystem.CarryCapacity"]=own
    assert(C.restore(p,30));eq(f.baseModifiers["GodSystem.CarryCapacity"],nil)
    f.baseModifiers["GodSystem.CarryCapacity"]=other;assert(C.restore(p,30));eq(f.baseModifiers["GodSystem.CarryCapacity"],other)
    UnifiedCarryWeightFramework=nil
end)
test("setter lookup chain, bypass, captured writes, later wrapper and cleanup",function()
    C.resetClient()
    local p=player(); local methods={}
    for _,k in ipairs({"setMaxWeightBase","setMaxWeightDelta","setMaxWeight"})do methods[k]=p[k];p[k]=nil end
    local inherited=setmetatable({},{__index=methods});setmetatable(p,{__index=inherited})
    local raw=methods.setMaxWeightBase
    assert(C.restore(p,3));eq(C.getStatus(p,3).protection,"settersAndFields")
    local wrapped=methods.setMaxWeightBase;assert(C.restore(p,3));eq(methods.setMaxWeightBase,wrapped)
    p:setMaxWeightBase(100);p:setMaxWeightDelta(3);p:setMaxWeight(1);eq(p.base,14);eq(p.delta,1);eq(p.final,22)
    raw(p,99);tick();eq(p.base,14)
    local before=C.capture(p);assert(C.restore(p,4,true));assert(C.rollback(p,before));eq(p.base,14)
    local later=function(target,v)return raw(target,v)end;methods.setMaxWeightBase=later
    tick();assert(C.restore(p,3));eq(methods.setMaxWeightBase,later)
    p:setMaxWeightBase(999);tick();eq(p.base,14)
    C.forget(p);eq(methods.setMaxWeightBase,later);for _ in pairs(C.activePlayers) do error("unexpected active player") end;eq(C.workerInstalled,false)
    local zero=player();setmetatable(zero,{__index=inherited});zero.setMaxWeightBase=nil;zero:setMaxWeightBase(12);eq(zero.base,12)
end)
test("MP sequence heartbeat, final injury interleaving and full initialization",function()
    C.resetClient();local host=player();assert(C.restore(host,3));local first=C.makeSnapshot(host,3)
    multiplayer=true;local p=player();eq(C.acceptSnapshot(p,first),false)
    assert(C.acceptSnapshot(p,first,true));eq(p.base,14);eq(p.final,22);eq(p.recomputes,0)
    eq(C.acceptSnapshot(p,first),false)
    p.final=5;for i=1,20 do tick();assert(C.updateClient(p))end;eq(p.final,5);eq(p.recomputes,0)
    multiplayer=false;local heartbeat=C.makeSnapshot(host,3);eq(heartbeat.revision,first.revision)
    multiplayer=true;assert(C.acceptSnapshot(p,heartbeat));eq(p.final,22)
    local bad={};for k,v in pairs(heartbeat)do bad[k]=v end
    bad.pushSequence=heartbeat.pushSequence+1;bad.token="late";eq(C.acceptSnapshot(p,bad),false);eq(C.acceptSnapshot(p,bad,true),false)
    bad.token=heartbeat.token;bad.playerId=2;eq(C.acceptSnapshot(p,bad),false)
    bad.playerId=1;bad.delta=0/0;eq(C.acceptSnapshot(p,bad),false)
    bad.delta=1;bad.base=99;eq(C.acceptSnapshot(p,bad),false)
    multiplayer=false;assert(C.restore(host,0));local zero=C.makeSnapshot(host,0);eq(zero.token,first.token)
    multiplayer=true;assert(C.acceptSnapshot(p,zero));eq(p.base,8);eq(C.activePlayers[p],nil)
    C.resetClient();eq(C.acceptSnapshot(p,heartbeat),false);assert(C.acceptSnapshot(p,heartbeat,true))
    local old={policyVersion=1,playerId=1,token=heartbeat.token};eq(C.acceptSnapshot(p,old,true),false);eq(C.getStatus(p,3).reason,"updateRequired")
    eq(C.activePlayers[p],nil);multiplayer=false
end)
test("death and last player remove the worker, stable 10,000 checks do not recompute",function()
    C.resetClient();local p=player();assert(C.restore(p,3));local writes,recomputes=p.writes,p.recomputes
    for i=1,10000 do tick() end
    eq(p.writes,writes);eq(p.recomputes,recomputes)
    p.dead=true;tick();eq(C.sessions[p],nil);eq(C.workerInstalled,false)
end)
test("failed native upgrade never charges through SP purchase adapter",function()
    local p=player(); assert(C.restore(p,2)); p.base=13
    function p:getCharacterTraits() return nil end
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
            canAfford=function()return true end,storeCheckpoint=function()return true end,appendHistory=function()end,historyEntry=function()return {} end,
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
    eq(charges,1); eq(conflict.base,14); eq(results[2].code,"CarryCapacityUpgraded")
    server=false
end)
test("server committed notification failure retains receipt; unknown commit cannot repay",function()
    server=true
    for _,phase in ipairs({"notify","checkpoint"}) do
        C.resetClient();local p=player();local data={upgrades={carryCapacityLevel=0},stats={spentPoints=0}}
        local root={players={owner=data}};local charges,checkpoints=0,0
        local env=setmetatable({Commands={},GodSystemServer={},playerData=function()return data end,store=function()return root end,
            userKey=function()return "owner" end,guard=function()return true end,unguard=function()end,canAfford=function()return true end,
            storeCheckpoint=function()checkpoints=checkpoints+1;if phase=="checkpoint" and checkpoints==2 then return false,"simulated save failure" end;return true end,
            appendHistory=function()end,historyEntry=function()return {} end,addPoints=function()charges=charges+1;return true end,
            finishCode=function()if phase=="notify" then error("simulated reply lost") end end,
            errorMessage=function()end,sendState=function()end},{__index=_G})
        GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Services(env)
        local args={upgradeType="carryCapacity",opId="gs-99-2-3"}
        env.Commands.upgradeSystem(nil,nil,p,args)
        eq(charges,1);eq(data.upgrades.carryCapacityLevel,1)
        local result=GodSystemTransactionOps.get(root,"owner","upgradeSystem",args)
        eq(result.status,phase=="notify" and "done" or "unknown")
        if phase=="notify" then
            env.finishCode=function()end
        end
        env.Commands.upgradeSystem(nil,nil,p,args);eq(charges,1)
    end
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
    p.base=15; clock=clock+100; C.onGuardTick(); clock=clock+900; env.onCarryTick(); eq(#sends,2); eq(sends[2].reason,"ok"); eq(p.base,14)
    clock=clock+1000; env.onCarryTick(); eq(#sends,2)
    local fresh=player(8,p.md); fresh.id=11; p=fresh; active={fresh}
    clock=clock+1000; env.onCarryTick(); eq(#sends,3); eq(fresh.base,14)
    assert(sends[3].token~=sends[1].token)
    local count = #sends
    for i=1,60 do clock=clock+1000; env.onCarryTick() end
    eq(#sends-count,12)
    for i=count+1,#sends do eq(sends[i].revision,sends[count].revision);assert(sends[i].pushSequence>sends[i-1].pushSequence) end
    eq(C.sessions[active[1]].level,3)
    root.players[11].upgrades.carryCapacityLevel=0;clock=clock+1000;env.onCarryTick()
    eq(sends[#sends].level,0);eq(sends[#sends].token,sends[count].token);eq(C.activePlayers[p],nil)
    local stopped=#sends;clock=clock+5000;env.onCarryTick();eq(#sends,stopped)
    assert(C.restore(p,1));root.players[11].upgrades.carryCapacityLevel=1
    local oldPlayer=active[1];active={};clock=clock+1000;env.onCarryTick();eq(C.sessions[oldPlayer],nil)
    server=false
end)
test("actual SP lifecycle recalibrates and clears the worker on exit",function()
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
    p.final=12; clock=clock+100; assert(C.restore(p,3)); eq(p.final,22); eq(p.recomputes,3)
    p=player(); events.OnCreatePlayer.callback(0,p); eq(p.base,14)
    p.base=8; clock=clock+3000; assert(C.restore(p,3)); eq(p.base,14)
    events.OnInitGlobalModData.callback();eq(C.sessions[p],nil);eq(C.workerInstalled,false)
    events.OnCreatePlayer.callback(0,p);eq(p.base,14)
    events.OnGameExit.callback();eq(C.sessions[p],nil);eq(C.workerInstalled,false)
end)
test("missing player is an expected state, not a caught native exception",function()
    local original, calls = pcall, 0
    pcall=function(...) calls=calls+1; return original(...) end
    local level=C.getPersistedLevel(nil)
    pcall=original
    eq(level,0);eq(calls,0)
end)

test("real initialization defers missing carry level until player creation",function()
    for _,case in ipairs({{legacy=0,expected=0},{legacy=3,expected=3},
        {account=2,legacy=7,expected=2},{account=0,legacy=7,expected=0}}) do
        C.resetClient()
        local current, data, reads = nil, {upgrades={carryCapacityLevel=case.account}}, 0
        local events={}
        for _,name in ipairs({"OnInitGlobalModData","OnCreatePlayer","OnGameStart","OnGameExit"}) do
            events[name]={Add=function(fn)events[name].callback=fn end}
        end
        local r={}
        local noop=function()end
        local env=setmetatable({Events=events, getPlayer=function()return current end,
            GodSystemApp={services={runtime=r}},GodSystemConfig={Version="test",DataKey="test",FloatingButton={x=0,y=0}},
            ModData={getOrCreate=function()return data end},
            GodSystemShopVariants={normalizeUnlocked=noop},GodSystemShopInflation={state=noop},
            GodSystemRuntimeConfig={Current={},readSandbox=noop,normalizeTaskUpgrades=noop},
            GodSystemCompanionConfig={ensureData=function(d)return d or {} end},
            GodSystemItemConfig={migrate=function()return {} end,applyRuntime=noop}}, {__index=_G})
        assert(loadstring(readSource("client/GodSystem_ClientRuntime_Foundation.lua")))()
        GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Foundation(env)
        assert(loadstring(readSource("client/GodSystem_ClientRuntime_Tasks.lua")))()
        GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Tasks(env)
        env.gsCurrentDay=function()return 0 end;env.gsNowHours=function()return 0 end
        events.OnInitGlobalModData.callback()
        eq(data.upgrades.carryCapacityLevel,case.account)
        eq(r.getCarryCapacityLevel(),case.account or 0)
        eq(data.upgrades.carryCapacityLevel,case.account)
        local p=player(8,{GodSystemCarryCapacityLevel=case.legacy})
        function p:getModData() reads=reads+1;return self.md end
        function p:getZombieKills()return 0 end
        -- The create event can provide the player before getPlayer() does.
        events.OnCreatePlayer.callback(0,p)
        eq(data.upgrades.carryCapacityLevel,case.expected)
        eq(p.base,8+2*case.expected)
        current=p
        eq(r.getCarryCapacityLevel(),case.expected)
        local before=reads;p.md.GodSystemCarryCapacityLevel=99
        eq(r.getCarryCapacityLevel(),case.expected);eq(reads,before)
        events.OnGameExit.callback();eq(C.sessions[p],nil)
    end
end)
print("Carry capacity cases passed: "..passed)
