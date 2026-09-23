-- Splash rule, local search and melee-ledger integration regressions.
local loaded={}
function require(name)
    if loaded[name] then return loaded[name] end
    local fn=assert(loadstring(readSource("shared/"..name..".lua"),name))
    loaded[name]=true
    local result=fn(); loaded[name]=result or true
    return loaded[name]
end

require "GodSystem_EquipmentService"
require "GodSystem_EquipmentCombat"
local E,S,I,C=GodSystemEquipment,GodSystemEquipmentSplash,GodSystemEquipmentItems,GodSystemEquipmentCombat
local total=0
local function test(name,fn) fn(); total=total+1; print("PASS splash: "..name) end
local function eq(a,b,message) assert(a==b,(message or "value mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function near(a,b,message) assert(math.abs(a-b)<0.000001,(message or "number mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function list(rows) return {size=function() return #rows end,get=function(_,n) return rows[n+1] end} end

test("levels map linearly from ten to one hundred percent",function()
    eq(S.rule(0),nil); eq(S.rule(1).radius,2); eq(S.rule(10).targets,5); eq(S.rule(11),nil)
    near(S.damage(0.3,1),0.03); near(S.damage(0.3,10),0.3)
    near(S.basis(0.2,0.4),0.3); eq(S.basis(0.4,0.2),nil); eq(S.damage(0,2),nil)
end)

local function makeZombie(x,y,z,health)
    local value={x=x,y=y,z=z,health=health,dead=false,square={}}
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getHealth() return self.health end
    function value:setHealth(v) self.health=v end
    function value:setAttackedBy(player) self.attackedBy=player end
    function value:isDead() return self.dead end
    function value:getCurrentSquare() return self.square end
    function value:Kill(weapon,player)
        eq(weapon,expectedWeapon,"native kill receives the wielded weapon")
        eq(player,expectedPlayer,"native kill receives the real attacker")
        self.killCalls=(self.killCalls or 0)+1
        self.health=0; self.dead=true
    end
    function value:Hit() error("splash must not re-enter weapon hit processing") end
    return value
end

test("Java-userdata bridge reads splash center and weapon damage before queuing",function()
    local callback
    Events={OnTick={Add=function(fn) callback=fn end,Remove=function(fn) eq(callback,fn); callback=nil end}}
    function getTimestampMs() return 100 end
    function instanceof(value,kind)
        return value and ((kind=="HandWeapon" and value.weapon) or (kind=="IsoZombie" and value.zombie))
    end
    local weapon={weapon=true,id=91,fullType="Base.Axe",minimum=0.2,maximum=0.4}
    function weapon:getID() return self.id end
    function weapon:getFullType() return self.fullType end
    function weapon:isRanged() return false end
    function weapon:getMinDamage() return self.minimum end
    function weapon:getMaxDamage() return self.maximum end
    local player={getPrimaryHandItem=function() return weapon end}
    function player:isPerformingShoveAnimation() return self.shove==true end
    function player:isPerformingStompAnimation() return self.stomp==true end
    function player:isShoveStompAnim() return self.shoveStomp==true end
    local zombie=makeZombie(0.2,0.2,0,2); zombie.zombie=true
    local record={id="eq-bridge",generation=1,revision=1,levels={splash=1,impact=0},effectState={}}
    local cfg={enabled=true,splashEnabled=true}
    local combat=C.new({activeRecord=function() return record,cfg end},{})
    -- Kahlua Java userdata cannot use the Lua-table fallback in Bridge.try.
    local nativeType=type
    type=function(value)
        if value==weapon or value==zombie or value==player then return "userdata" end
        return nativeType(value)
    end
    local ok,err=pcall(function()
        eq(I.value(zombie,"getCurrentSquare"),zombie.square)
        eq(I.value(weapon,"getMinDamage"),0.2)
        eq(I.value(weapon,"getMaxDamage"),0.4)
        player.shove=true
        eq(I.value(player,"isPerformingShoveAnimation"),true)
        assert(not combat:begin(player,weapon,1),"shove must not start a splash attack")
        player.shove=false; player.stomp=true
        eq(I.value(player,"isPerformingStompAnimation"),true)
        assert(not combat:begin(player,weapon,1),"stomp must not start a splash attack")
        player.stomp=false; player.shoveStomp=true
        eq(I.value(player,"isShoveStompAnim"),true)
        assert(not combat:begin(player,weapon,1),"combined shove/stomp must not start a splash attack")
        player.shoveStomp=false
        assert(combat:begin(player,weapon,1))
        assert(combat:hit(zombie,player,weapon))
        assert(combat:finish(player,weapon,1))
        eq(combat.splashRuntime.pending,1,"a real-object hit must queue splash")
        combat:reset()
        eq(callback,nil,"the temporary worker must detach")
    end)
    type=nativeType
    if not ok then error(err) end
end)

test("attack ledger splashes once, excludes direct hits, caps nearest targets, and uses native kill attribution",function()
    local attached,detached,callback=0,0,nil
    Events={OnTick={Add=function(fn) attached=attached+1; callback=fn end,
        Remove=function(fn) eq(callback,fn); detached=detached+1; callback=nil end}}
    function getTimestampMs() return 100 end
    function instanceof(value,kind) return value and ((kind=="HandWeapon" and value.weapon) or (kind=="IsoZombie" and value.zombie)) end
    local weapon={weapon=true,id=77,fullType="Base.Axe",minimum=0.2,maximum=0.4}
    function weapon:getID() return self.id end
    function weapon:getFullType() return self.fullType end
    function weapon:isRanged() return false end
    function weapon:getMinDamage() return self.minimum end
    function weapon:getMaxDamage() return self.maximum end
    local player={}; expectedWeapon,expectedPlayer=weapon,player
    function player:getPrimaryHandItem() return weapon end
    local center,direct=makeZombie(0.2,0.2,0,5),makeZombie(1.2,0.2,0,5)
    local candidates={makeZombie(0.4,0.2,0,1),makeZombie(0.6,0.2,0,1),makeZombie(0.8,0.2,0,0.08),
        makeZombie(1.0,0.2,0,1),makeZombie(1.4,0.2,0,1),makeZombie(1.8,0.2,0,1),
        makeZombie(0.3,0.2,1,1),makeZombie(2.5,0.2,0,1)}
    local all={center,direct}; for _,z in ipairs(candidates) do z.zombie=true; all[#all+1]=z end
    center.zombie=true; direct.zombie=true
    local bySquare={}
    for _,z in ipairs(all) do
        local key=math.floor(z.x)..":"..math.floor(z.y)..":"..math.floor(z.z)
        bySquare[key]=bySquare[key] or {}; bySquare[key][#bySquare[key]+1]=z
    end
    function getCell()
        return {getGridSquare=function(_,x,y,z)
            local rows=bySquare[tostring(x)..":"..tostring(y)..":"..tostring(z)]
            return rows and {getMovingObjects=function() return list(rows) end} or nil
        end}
    end
    local record={id="eq-1",generation=1,revision=1,levels={splash=3,impact=0},effectState={}}
    local cfg={enabled=true,splashEnabled=true}
    local combat=C.new({activeRecord=function() return record,cfg end},{})
    assert(combat:begin(player,weapon,1))
    assert(combat:hit(center,player,weapon))
    combat:hit(direct,player,weapon)
    combat:hit(center,player,weapon)
    assert(combat:finish(player,weapon,1))
    eq(combat.metrics.splashQueued,1); eq(combat.splashRuntime.pending,1); eq(attached,1)
    callback()
    eq(detached,1); eq(callback,nil); eq(combat.splashRuntime.pending,0)
    near(candidates[1].health,0.91); near(candidates[2].health,0.91)
    eq(candidates[3].dead,true); eq(candidates[3].killCalls,1)
    eq(candidates[3].attackedBy,player,"native death path is pre-attributed to the attacker")
    near(candidates[4].health,0.91); near(candidates[5].health,0.91)
    near(candidates[6].health,1,"sixth candidate is outside the five-target cap")
    near(candidates[7].health,1,"other floors are excluded")
    near(candidates[8].health,1,"targets outside the radius are excluded")
    eq(center.health,5,"primary target is excluded")
    eq(direct.health,5,"other direct hits from this swing are excluded")
    eq(combat.metrics.splashQueued,1,"multiple hit callbacks schedule only one splash per swing")
    eq(combat.splashRuntime.metrics.damaged,5); eq(combat.splashRuntime.metrics.killed,1)
    assert(not combat.splashRuntime.running,"temporary tick listener is removed after work")
end)

test("disabled splash does not queue, and player reset cancels queued work",function()
    Events={OnTick={Add=function(fn) callback=fn end,Remove=function() callback=nil end}}
    local weapon={weapon=true,id=88,fullType="Base.Axe",minimum=0.2,maximum=0.4}
    function weapon:getID() return self.id end
    function weapon:getFullType() return self.fullType end
    function weapon:isRanged() return false end
    function weapon:getMinDamage() return self.minimum end
    function weapon:getMaxDamage() return self.maximum end
    local player={getPrimaryHandItem=function() return weapon end}
    local target=makeZombie(0.2,0.2,0,2); target.zombie=true
    local record={id="eq-2",generation=1,revision=1,levels={splash=1},effectState={}}
    local cfg={enabled=true,splashEnabled=false}
    local combat=C.new({activeRecord=function() return record,cfg end},{})
    assert(combat:begin(player,weapon,1)); combat:hit(target,player,weapon); combat:finish(player,weapon,1)
    eq(combat.splashRuntime.pending,0,"sandbox toggle is authoritative")
    cfg.splashEnabled=true
    function getCell() return {getGridSquare=function() return {getMovingObjects=function() return list({target}) end} end} end
    assert(combat:begin(player,weapon,2)); combat:hit(target,player,weapon); combat:finish(player,weapon,2)
    eq(combat.splashRuntime.pending,1)
    combat:reset(player)
    callback()
    eq(target.health,2,"disconnect/death reset cancels queued damage")
    eq(combat.splashRuntime.pending,0)
end)

print("Splash runtime groups passed: "..total)
