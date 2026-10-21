-- Actual controllers; isolated PZ/render boundaries, not a live-game test.
local function eq(a,b,msg) assert(a==b,(msg or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function load(path) return assert(loadstring(readSource(path),path))() end
function require() end
function isClient() return false end
function isServer() return false end
local clock,zoom,scans,saves=1000,1,0,0
function getTimestampMs() return clock end
function getCore() return {getZoom=function() return zoom end} end
function ZombRandFloat(a,b) return (a+b)/2 end
function isGamePaused() return false end
local player={x=10,y=20,z=0}
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:getVehicle() return self.vehicle end
function getSpecificPlayer() return player end
local square={}
function getCell() return {getGridSquare=function() scans=scans+1; return square end} end
Events={OnGameStart={Add=function() end},OnPlayerUpdate={Add=function() end},
    OnPlayerDeath={Add=function() end},OnPreUIDraw={Add=function() end}}
GodSystemApp={services={runtime={save=function() saves=saves+1 end}}}
load("shared/GodSystem_CompanionConfig.lua")
local cfg=GodSystemCompanionConfig
local data=cfg.ensureData({unlocked=true,followMode="guard",guardPoint={x=500,y=500,z=7},
    resonance=3,unlocks={attack=true},levels={attackDamage=2},visible=false,combatMode="ceasefire"})
eq(data.followMode,"guard"); eq(data.guardPoint,nil); eq(data.resonance,3); eq(data.levels.attackDamage,2)
eq(cfg.getRobotVisualHeight("guard"),96); eq(cfg.getRobotVisualHeight("follow5"),48)
GodSystemApp.services.runtime.getCompanionData=function() return data end
load("client/GodSystem_CompanionVisual.lua")
local source=readSource("client/GodSystem_Companion.lua")
if type(source)=="string" then
    local count
    source,count=source:gsub("return GodSystemCompanion%s*$",[[
Companion.testHover={position=updateRobotPosition,sync=syncHoverAnchor,update=updateCompanion,
    launch=launchPendingAttack,renderProjectile=renderProjectile}
return GodSystemCompanion]])
    eq(count,1)
end
assert(loadstring(source))()
local C=GodSystemCompanion
local H=C.testHover
assert(C.setFollowMode("guard")); eq(C.runtime.robotX,10); eq(C.runtime.robotY,20); eq(C.runtime.robotZ,0)
C.runtime.targetX,C.runtime.targetY=999,999; C.runtime.pendingAttack={target={}}
H.position(player,data,0.1,clock); eq(C.runtime.behaviorState,"charging"); eq(C.runtime.targetX,nil)
C.runtime.pendingAttack=nil; C.runtime.recoveryUntilMs=clock+100
H.position(player,data,0.1,clock); eq(C.runtime.behaviorState,"recovery"); C.runtime.recoveryUntilMs=0
scans=0; local before=saves
for i=1,10000 do
    player.x,player.y,player.z=i/10,i/20,i%4; H.position(player,data,0.1,clock)
    eq(C.runtime.robotX,player.x); eq(C.runtime.robotY,player.y); eq(C.runtime.robotZ,player.z)
end
eq(scans,0); eq(saves,before); eq(data.followMode,"guard"); eq(C.runtime.behaviorState,"guard")
player.vehicle={}; H.update(player); eq(C.runtime.vehicleSuspended,true)
player.vehicle=nil; clock=clock+100; H.update(player)
eq(C.runtime.vehicleSuspended,false); eq(C.runtime.robotX,player.x); eq(C.runtime.robotZ,player.z)
local zombie={}
function zombie:getModData() return {} end
function zombie:isDead() return false end
function zombie:isAlive() return true end
function zombie:getCurrentSquare() return square end
function zombie:getX() return player.x+1 end
function zombie:getY() return player.y end
function zombie:getZ() return player.z end
C.runtime.pendingAttack={target=zombie}; data.combatMode="active"
H.sync(player,data); H.launch(player,data,clock); eq(#C.runtime.projectiles,1)
local shot=C.runtime.projectiles[#C.runtime.projectiles]
eq(shot.startX,player.x); eq(shot.startZ,player.z); eq(shot.startVisualHeight,96)
assert(C.setFollowMode("follow3")); eq(shot.startVisualHeight,96)
assert(C.setFollowMode("guard")); assert(C.recall()); eq(data.followMode,"follow5")
eq(cfg.RobotFollowBands.follow3.maximum,3); eq(cfg.RobotFollowBands.follow10.maximum,10)
ISCoordConversion={ToScreen=function(x,y,z) return x*10,1000+y*10-z*100 end}
local V=GodSystemCompanionVisual
local lines={}
local renderer={renderline=function(_,_,x1,y1,x2,y2) lines[#lines+1]={x1,y1,x2,y2} end}
local rt={robotX=0,robotY=0,robotZ=0,direction="SE",animationFrame=0,bobPhase=0,recoilUntilMs=clock+100}
data.visible=true; data.followMode="guard"
for _,value in ipairs({0.5,1,2}) do
    zoom=value; lines={}; V.renderRobot(renderer,{},rt,data); local first=lines
    rt.bobPhase=2; lines={}; V.renderRobot(renderer,{},rt,data); eq(#lines,#first)
    for i,row in ipairs(lines) do for j=1,4 do eq(row[j],first[i][j],"hover must not bob or recoil") end end
    rt.bobPhase=0; rt.recoilUntilMs=0; data.followMode="follow5"; lines={}; V.renderRobot(renderer,{},rt,data)
    eq(lines[1][2]-first[1][2],48/zoom); data.followMode="guard"; rt.recoilUntilMs=clock+100
    V.reset(); V.emit("charge",0,0,0,96); lines={}; V.renderParticles(renderer,{}); local elevated=lines[1][2]
    V.reset(); V.emit("charge",0,0,0); lines={}; V.renderParticles(renderer,{})
    eq(lines[1][2]-elevated,48/zoom,"particle height captured at emission")
    lines={}; H.renderProjectile(renderer,{},shot,player); local elevatedShot=lines[1][4]
    shot.startVisualHeight=48; lines={}; H.renderProjectile(renderer,{},shot,player)
    eq(lines[1][4]-elevatedShot,48/zoom,"shot origin retains launch height"); shot.startVisualHeight=96
end
assert(C.setFollowMode("guard")); C.shutdown(); eq(C.runtime.robotX,nil); eq(#C.runtime.projectiles,0)
lines={}; V.renderParticles(renderer,{}); eq(#lines,0)
GodSystemApp.services.runtime.text=function(_,fallback) return fallback end
ISCollapsableWindow={createChildren=function() end}
function ISCollapsableWindow:derive() return setmetatable({}, {__index=self}) end
ISButton={new=function(_,_,_,_,_,title) return {title=title,initialise=function() end,
    setTitle=function(self,value) self.title=value end} end}
load("client/GodSystem_CompanionUI.lua")
local window=setmetatable({width=452,actionButtons={},addChild=function() end}, {__index=GodSystemCompanionShortcutWindow})
window:createChildren(); eq(#window.actionButtons,11)
for index,mode in ipairs({"follow3","follow5","follow10","guard"}) do eq(window.actionButtons[index+3].internal,mode) end
eq(window.actionButtons[7].title,"Guard"); eq(window.actionButtons[9].internal,"guardian")
window:onAction(window.actionButtons[7]); eq(data.followMode,"guard"); eq(C.runtime.robotX,player.x)
C.shutdown()
print("PASS companion hover: migration, 10k scan-free anchors, charge/recovery, vehicle, recall, three zooms, particles and shot origins")
