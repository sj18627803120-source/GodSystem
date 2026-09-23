-- 42.20_3.6 impact search stays local, bounded and deterministic.
local loaded={}
function require(name)
    if loaded[name] then return loaded[name] end
    loaded[name]=true
    local fn=assert(loadstring(readSource("shared/"..name..".lua"),name))
    loaded[name]=fn() or true
    return loaded[name]
end
require "GodSystem_ImpactRuntime"
local R=GodSystemImpactRuntime
local total=0
local function test(name,fn) fn(); total=total+1; print("PASS impact: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function list(rows) return {size=function() return #rows end,get=function(_,n) return rows[n+1] end} end
local function zombie(x,y,z,down)
    return {x=x,y=y,z=z,down=down==true,getX=function(self) return self.x end,getY=function(self) return self.y end,getZ=function(self) return self.z end}
end

test("search selects nearest standing same-floor zombies without sorting all candidates",function()
    local callbacks,applied,finished={}, {}, 0
    local center=zombie(0,0,0)
    local nearest,second,far,down,upper=zombie(.2,0,0),zombie(1,0,0),zombie(2.5,0,0),zombie(.1,.1,0,true),zombie(.1,0,1)
    local rows={["0:0:0"]={center,nearest,second,far,down},["1:0:0"]={second},["0:1:0"]={upper}}
    local now=0
    local runtime=R.new({
        now=function() now=now+1; return now end,
        attach=function(fn) callbacks[#callbacks+1]=fn end,detach=function() end,
        square=function(x,y,z) return {getMovingObjects=function() return list(rows[tostring(x)..":"..tostring(y)..":"..tostring(z)] or {}) end} end,
        valid=function(z) return not z.down end,
        apply=function(z) applied[#applied+1]=z end,
        finished=function() finished=finished+1 end,
    })
    runtime:queue(center,{radius=2,targets=2},{attackId=1})
    for _=1,30 do runtime:tick() end
    eq(#applied,2); eq(applied[1],center); eq(applied[2],nearest); eq(finished,1)
    assert(runtime.metrics.objects<=R.EntryBudget*runtime.metrics.ticks)
end)

test("worker unregisters when no jobs remain",function()
    local attached,detached=0,0
    local runtime=R.new({now=function() return 0 end,attach=function() attached=attached+1 end,detach=function() detached=detached+1 end,
        square=function() return nil end,valid=function() return false end,apply=function() end})
    runtime:queue(zombie(0,0,0),{radius=1,targets=1},{attackId=2})
    eq(attached,1); assert(runtime.running)
    runtime:reset(); eq(detached,1); assert(not runtime.running)
end)

test("unloaded squares advance and an empty search detaches itself",function()
    local detached,visited=0,0
    local runtime=R.new({now=function() return 0 end,attach=function() end,detach=function() detached=detached+1 end,
        square=function() visited=visited+1; return nil end,valid=function() return true end,apply=function() error("no targets") end})
    runtime:queue(zombie(0,0,0),{radius=1,targets=1},{})
    for _=1,10 do if runtime.running then runtime:tick() end end
    eq(visited,9); eq(detached,1); assert(not runtime.running)
end)

test("multiple queued releases survive completed queue slots",function()
    local done={}; local oldBudget=R.EntryBudget; R.EntryBudget=1
    local runtime=R.new({now=function() return 0 end,attach=function() end,detach=function() end,
        square=function() return nil end,valid=function() return false end,apply=function() end,
        finished=function(job) done[#done+1]=job.token.id end})
    runtime:queue(zombie(0,0,0),{radius=0,targets=1},{id=1})
    runtime:queue(zombie(0,0,0),{radius=0,targets=1},{id=2})
    runtime:tick(); runtime:tick() -- leaves a hole at slot 1
    runtime:queue(zombie(0,0,0),{radius=0,targets=1},{id=3})
    for _=1,20 do if runtime.running then runtime:tick() end end
    R.EntryBudget=oldBudget
    eq(table.concat(done,","),"1,2,3"); assert(not runtime.running)
end)

test("deferred scan uses the original impact point and rechecks moving targets",function()
    local center,target=zombie(0,0,0),zombie(.5,0,0)
    local applied=0
    local runtime=R.new({now=function() return 0 end,attach=function() end,detach=function() end,
        square=function() return nil end,valid=function(z) return not z.down end,apply=function() applied=applied+1 end})
    runtime:queue(center,{radius=1,targets=3},{})
    local job=runtime.jobs[1]; center.x=100
    runtime:consider(job,target); eq(#job.best,1)
    target.x=3; runtime:finish(job); eq(applied,0)
    runtime:reset()
end)

-- Integration uses the real combat adapter and only B42.20.4 zombie methods.
-- In particular, there is deliberately NO isCrawler() stub.
require "GodSystem_EquipmentItems"
require "GodSystem_EquipmentCombat"
local C,P=GodSystemEquipmentCombat,GodSystemEquipmentImpact
test("SP charged hit runs the real adapter, knocks down eligible targets once and detaches",function()
    local callback,detached=nil,0
    Events={OnTick={Add=function(fn) callback=fn end,Remove=function(fn) eq(callback,fn); callback=nil; detached=detached+1 end}}
    function getTimestampMs() return 1000 end
    function instanceof(o,kind) return o and o.kind==kind end
    local function target(x,y,z,state)
        local t=zombie(x,y,z); t.kind="IsoZombie"; t.state=state; t.knocks=0
        function t:isDead() return self.state=="dead" end
        function t:isKnockedDown() return self.state=="knocked" end
        function t:isOnFloor() return self.state=="floor" end
        function t:isCrawling() return self.state=="crawler" end
        function t:getCurrentSquare() if self.state~="unloaded" then return {} end end
        function t:knockDown(behind) eq(behind,false); self.knocks=self.knocks+1; self.state="knocked" end
        function t:Hit() error("impact must not deal extra weapon damage") end
        return t
    end
    local center=target(0,0,0)
    local eligible={center,target(.2,0,0),target(.5,0,0),target(1,0,0),target(1.2,0,0),target(1.4,0,0)}
    local invalid={target(.1,0,0,"dead"),target(.1,0,0,"knocked"),target(.1,0,0,"floor"),target(.1,0,0,"crawler"),target(.1,0,1),target(.1,0,0,"unloaded"),target(5,0,0)}
    local rows={}; for _,t in ipairs(eligible) do rows[#rows+1]=t end; for _,t in ipairs(invalid) do rows[#rows+1]=t end
    rows[#rows+1]=center -- duplicate object in scan must not knock down twice
    function getCell() return {getGridSquare=function(_,x,y) if x==0 and y==0 then return {getMovingObjects=function() return list(rows) end} end end} end
    local weapon={kind="HandWeapon",getID=function() return 1 end,getFullType=function() return "Base.Hammer" end,isRanged=function() return false end}
    local player={getPrimaryHandItem=function() return weapon end}
    local record={id="test",generation=1,revision=1,levels={impact=3},effectState={impact={attackCount=7}}}
    local combat=C.new({activeRecord=function() return record,{} end},{})
    -- Attack that reaches the threshold arms it; the following hit releases it.
    assert(combat:begin(player,weapon,1)); assert(not combat:hit(center,player,weapon)); assert(combat:finish(player,weapon,1)); assert(P.state(record).ready)
    assert(combat:begin(player,weapon,2)); assert(combat:hit(center,player,weapon)); assert(not combat:hit(center,player,weapon)); assert(combat:finish(player,weapon,2))
    eq(P.state(record).attackCount,0); assert(not P.state(record).ready); assert(callback)
    for _=1,30 do if callback then callback() end end
    eq(detached,1); eq(callback,nil); eq(combat.runtime.metrics.applied,5); eq(combat.runtime.metrics.failed,0)
    for i,t in ipairs(eligible) do eq(t.knocks,i<=5 and 1 or 0) end
    for _,t in ipairs(invalid) do eq(t.knocks,0) end
    eq(combat.derived,0); eq(combat.metrics.released,1)
end)

print("Impact runtime groups passed: "..total)
