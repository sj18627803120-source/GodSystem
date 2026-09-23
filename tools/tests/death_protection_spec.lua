local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function loadModule() assert(loadstring(readSource("client/GodSystem_DeathProtection.lua")))() end
isClient=function() return true end
isServer=function() return false end
GodSystemDeathProtection=nil
loadModule();eq(GodSystemDeathProtection,nil)
isClient=function() return false end
Events={}
for _,name in ipairs({"OnGameStart","OnCreatePlayer","OnPlayerGetDamage","OnPlayerUpdate"}) do Events[name]={Add=function()end} end
local time, balance, reads, scans=0,60000,0,0
local data={stats={}}
local p={health=1,body=100,mod={},invulnerable=false,reaction="",done=false,drag=false}
function p:getModData()return self.mod end
function p:isDead()return self.health<=0 end
function p:isOnDeathDone()return self.done end
function p:getHealth()return self.health end
function p:setHealth(v)self.health=v end
function p:getBodyDamage()return {getOverallBodyHealth=function()return self.body end,RestoreToFullHealth=function()self.body=100 end}end
function p:isInvulnerable()return self.invulnerable end
function p:setInvulnerable(v)self.invulnerable=v end
function p:setAvoidDamage(v)self.avoid=v end
function p:setDeathDragDown(v)self.drag=v end
function p:isDeathDragDown()return self.drag end
function p:setHitReaction(v)self.reaction=v end
function p:getHitReaction()return self.reaction end
function p:setBlockMovement(v)self.block=v end
function p:setKilledByFall(v)self.fall=v end
function p:teleportTo()self.teleports=(self.teleports or 0)+1 end
function p:getVehicle()return nil end
function p:getX()return 0 end
function p:getY()return 0 end
function p:getZ()return 0 end
getSpecificPlayer=function()return p end
getTimestampMs=function()return time end
getCell=function()scans=scans+1;return nil end
GodSystemRuntimeConfig={get=function()return 20000 end}
GodSystemApp={services={runtime={text=function(_,f)return f end,notify=function()end,save=function()end,
    getData=function()reads=reads+1;return data end,
    spendCurrency=function(cost)if balance<cost then return false end;balance=balance-cost;return true end}}}
loadModule()
local P=GodSystemDeathProtection
P.start();assert(P.buy());assert(P.buy());eq(P.count(),2);eq(balance,20000)
for i=1,200 do P.onUpdate(p) end
eq(scans,0);eq(reads,1)
P.onDamage(p,"WEAPONHIT",.05);eq(P.count(),2)
p.health=.1;P.onDamage(p,"BLEEDING",0)
eq(P.count(),1);eq(p.health,1);eq(p.invulnerable,true);eq(scans,1)
p.drag=true;P.onDamage(p,"WEAPONHIT",10);P.onUpdate(p);eq(P.count(),1)
time=501;P.onUpdate(p);eq(p.invulnerable,false);eq(p.avoid,false);eq(p.drag,false)
p.health=0;P.onDamage(p,"FALLDOWN",1000);eq(P.count(),0);eq(p.health,1)
time=1002;P.onUpdate(p);eq(p.invulnerable,false)
assert(P.buy());eq(balance,0);eq(P.count(),1);assert(not P.buy());eq(P.count(),1)
p.invulnerable=true;p.health=.1;P.onUpdate(p);eq(P.count(),1)
p.invulnerable=false;p.done=true;P.onUpdate(p);eq(P.count(),1)
p.done=false;p.health=1
DeathEscape={isEnabled=function()return true end};assert(not P.activate(p));eq(P.count(),1);DeathEscape=nil
p.mod.GodSystemDeathProtectionRestore={invulnerable=false};p.invulnerable=true
P.start();eq(p.invulnerable,false);eq(P.count(),1)
getCell=function() return {getZombieList=function()return {size=function()return 0 end}end,
    getGridSquare=function()return {isSolid=function()return false end,isSolidFloor=function()return true end,
        isVehicleIntersecting=function()return false end,isFree=function()return true end}end}end
p.drag=true;P.onUpdate(p);eq(P.count(),0);eq(p.teleports,1)
-- Loading another world binds its own counter; returning restores that world's count.
local previousWorld=data
previousWorld.deathProtectionCharges=3
data={stats={}}
P.start();eq(P.count(),0)
data.deathProtectionCharges=2
data=previousWorld
P.start();eq(P.count(),3)
print("PASS death protection: SP scope, stacked purchases, trigger deduplication, restore flags, persistence and bounded idle work")
