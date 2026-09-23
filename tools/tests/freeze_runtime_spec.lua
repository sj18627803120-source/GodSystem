-- Focused 3.2 regression: pure rules and bounded worker only.  Engine calls,
-- animation selection and network ownership remain B42.20.4 in-game checks.
local loaded={}
function require(name)
    if loaded[name] then return loaded[name] end
    loaded[name]=true
    local fn=assert(loadstring(readSource("shared/"..name..".lua"),name))
    loaded[name]=fn() or true
    return loaded[name]
end
require "GodSystem_Equipment"
require "GodSystem_FreezeRuntime"
local E,F,R=GodSystemEquipment,GodSystemEquipmentFreeze,GodSystemFreezeRuntime
local groups=0
local function test(name,fn) fn(); groups=groups+1; print("PASS freeze: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

test("configurable task thresholds retain historical unlocks",function()
    local cfg=assert(E.config({EquipmentMaxSlots=6,EquipmentSlotTaskBase=25,EquipmentSlotTaskMultiplier=2}))
    eq(E.slotTarget(1,cfg),0); eq(E.slotTarget(2,cfg),25); eq(E.slotTarget(3,cfg),50); eq(E.slotTarget(4,cfg),100)
    local account={unlockedSlots=1,completedTasks=0,revision=1}
    E.unlock(account,50,cfg); eq(account.unlockedSlots,3); eq(account.completedTasks,50)
    local harder=assert(E.config({EquipmentMaxSlots=6,EquipmentSlotTaskBase=100,EquipmentSlotTaskMultiplier=3}))
    E.unlock(account,50,harder); eq(account.unlockedSlots,3)
    local free=assert(E.config({EquipmentMaxSlots=6,EquipmentSlotTaskBase=0,EquipmentSlotTaskMultiplier=10}))
    E.unlock(account,50,free); eq(account.unlockedSlots,6)
end)

test("freeze uses shared X and refuses an ineffective paid level",function()
    local cfg=assert(E.config({EnableEquipmentFreeze=true,EquipmentGrowthPercent=10}))
    eq(F.strength(0,cfg),0); eq(F.strength(1,cfg),0.1); eq(F.strength(8,cfg),0.8); eq(F.strength(999,cfg),0.8)
    local record={weaponKind="melee",levels={freeze=8,impact=0}}
    local quote,code=E.quote(record,"freeze",0,cfg)
    eq(quote,nil); eq(code,"EquipmentParameterCap")
end)

local function list(rows)
    return {size=function() return #rows end,get=function(_,index) return rows[index+1] end}
end
local function zombie(x,y,z)
    return {x=x,y=y,z=z,alive=true,getX=function(self) return self.x end,getY=function(self) return self.y end,
        getZ=function(self) return self.z end}
end

test("worker scans nearby squares incrementally, merges strongest and restores",function()
    local now=1000; local callbacks={}; local applied,cleared={},{}
    local near,other=zombie(1,0,0),zombie(8,0,0)
    local runtime=R.new({
        now=function() return now end,budgetNow=function() return now end,enabled=function() return true end,
        alive=function(object) return object.alive end,
        square=function(x,y,z)
            if z~=0 then return nil end
            if x==1 and y==0 then return {getMovingObjects=function() return list({near}) end} end
            if x==8 and y==0 then return {getMovingObjects=function() return list({other}) end} end
            return nil
        end,
        attach=function(fn) callbacks[#callbacks+1]=fn end,detach=function() end,
        apply=function(entry) applied[#applied+1]=entry.strength; return true end,
        clear=function(entry) cleared[#cleared+1]=entry.object end,
        check=function() end,
    })
    runtime:pulse(0,0,0,3,0.2,4000,now)
    runtime:pulse(0,0,0,3,0.6,5000,now)
    for _=1,20 do runtime:tick() end
    eq(#runtime.effects,1); eq(runtime.byObject[near].strength,0.6); eq(runtime.byObject[near].expires,5000)
    eq(runtime.byObject[other],nil); assert(runtime.metrics.entries<=20*F.EntryBudget)
    now=5001; runtime:tick(); eq(#runtime.effects,0); eq(#cleared,1)
end)

test("weaker repeat refreshes duration without lowering active strength",function()
    local now=0; local object=zombie(0,0,0); local applies=0
    local runtime=R.new({now=function() return now end,budgetNow=function() return now end,enabled=function() return true end,
        alive=function() return true end,square=function() return nil end,attach=function() end,detach=function() end,
        apply=function() applies=applies+1; return true end,clear=function() end,check=function() end})
    assert(runtime:touch(object,0.8,1000,now)); now=100
    assert(runtime:touch(object,0.2,2000,now)); eq(runtime.byObject[object].strength,0.8)
    eq(runtime.byObject[object].expires,2000); eq(applies,1)
end)

-- Exercise the real SP authority -> effect record -> client draw path. Keep
-- Java/renderer boundaries mocked; this catches a missing presentation flag
-- without claiming that desktop tests verify the in-game GPU output.
local clock=1000
getTimestampMs=function() return clock end
getRandomUUID=function() return "freeze-visual-test" end
local callbacks={}
Events=setmetatable({}, {__index=function(t,key)
    local event={Add=function(fn) callbacks[key]=fn end,Remove=function() end}; rawset(t,key,event); return event
end})
require "GodSystem_FreezeAuthority"
assert(loadstring(readSource("client/GodSystem_FreezeClient.lua")))()
local A,C,N=GodSystemFreezeAuthority,GodSystemFreezeClient,GodSystemFreezeNative
N.alive=function(object) return object.alive end
N.apply=function() return true end
N.clear=function() end
ISCoordConversion={ToScreen=function() return 200,200 end}
local draws=0
-- B42.20.4 SpriteRenderer.render(Texture, float x8, Consumer) requires
-- the final callback argument, even when it is nil. No nine-argument overload
-- exists in the installed jar; a permissive mock previously hid this bug.
getRenderer=function() return {render=function(_,...)
    eq(select("#",...),10)
    local args={...}
    assert(type(args[1])=="table")
    for n=2,9 do assert(type(args[n])=="number") end
    eq(select(10,...),nil)
    draws=draws+1
end} end
getTexture=function() return {} end
getCore=function() return {getZoom=function() return 1 end} end

test("UI draw is safe before SP config, after invalid config/reset, and before MP sync",function()
    local configReads=0
    local source={}
    local authority=A.new({adapter={multiplayer=false,config=function()
        configReads=configReads+1; return source
    end}})
    GodSystemEquipmentClient={freeze=authority}
    draws=0
    for _=1,1000 do callbacks.OnPreUIDraw() end
    eq(configReads,0); eq(draws,0)
    authority:config()
    assert(authority.runtime:touch(zombie(1,0,0),0.4,clock+3000,clock))
    callbacks.OnPreUIDraw(); eq(draws,2)
    source={EquipmentFreezeSeconds=-1}; clock=clock+1001
    eq(authority:config(),nil)
    callbacks.OnPreUIDraw(); eq(draws,2)
    authority:reset()
    local before=configReads
    for _=1,1000 do callbacks.OnPreUIDraw() end
    eq(configReads,before); eq(draws,2)
    source={}; authority:config()
    assert(authority.runtime:touch(zombie(1,0,0),0.4,clock+3000,clock))
    callbacks.OnPreUIDraw(); eq(draws,4)
    GodSystemEquipmentClient.freeze=C.new()
    callbacks.OnPreUIDraw(); eq(draws,4)
    GodSystemEquipmentClient.freeze=nil
    callbacks.OnPreUIDraw(); eq(draws,4)
end)

test("SP authority supplies visible markers and rendering initializes its counter",function()
    local source={EnableEquipmentFreeze=true,EquipmentFreezeVisuals=true}
    local authority=A.new({adapter={multiplayer=false,config=function() return source end}})
    authority:config()
    local object=zombie(1,0,0)
    assert(authority.runtime:touch(object,0.4,clock+3000,clock))
    draws=0; C.render(authority)
    eq(draws,2); eq(authority.metrics.visualFrames,1)
    clock=clock+F.VisualMs
    C.render(authority); eq(draws,2)
    assert(authority.runtime:touch(object,0.4,clock+3000,clock))
    C.render(authority); eq(draws,4)
    authority.cfg.freezeVisuals=false
    C.render(authority); eq(draws,4)
    eq(#authority.runtime.effects,1) -- presentation switch does not remove slow
end)

test("MP markers obey the received flag and the 32-target drawing limit",function()
    N.now=function() return clock end
    local client=C.new()
    client:setConfig(E.config({}))
    for n=1,40 do
        local object=zombie(n,0,0)
        client.runtime:touch(object,0.4,clock+3000,clock)
        client.runtime.byObject[object].visuals=true
    end
    draws=0; C.render(client); eq(draws,F.VisualLimit*2)
    for _,entry in ipairs(client.runtime.effects) do entry.visuals=false end
    C.render(client); eq(draws,F.VisualLimit*2)
end)

print("Freeze behavior groups passed: "..groups)
