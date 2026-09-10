require "GodSystem_EquipmentItems"
require "GodSystem_FreezeAnimationScales"
GodSystemFreezeNative = GodSystemFreezeNative or {}
local N,I=GodSystemFreezeNative,GodSystemEquipmentItems
local function write(zombie,strength)
    for key,base in pairs(GodSystemFreezeAnimationScales) do zombie:setVariable(key,base*(1-strength)) end
end
local function phase(zombie,value) zombie:setVariable("GSFreezePhase",value) end
local function clear(zombie)
    zombie:clearVariable("GSFreezePhase")
    for key in pairs(GodSystemFreezeAnimationScales) do zombie:clearVariable(key) end
end
function N.alive(zombie)
    return zombie and instanceof(zombie,"IsoZombie") and not zombie:isDead() and zombie:getCurrentSquare()~=nil
end
function N.now(multiplayer)
    if not multiplayer then return getTimestampMs() end
    -- Native B42.20.4 name is Mills, not Millis; synchronized monotonic clock.
    if not GameTime or not GameTime.getServerTimeMills then return 0 end
    return GameTime.getServerTimeMills()
end
function N.apply(entry)
    local zombie=entry.object
    if not N.alive(zombie) then return false end
    local old=tonumber(zombie:getVariableString("GSFreezePhase")) or 0
    local ok,err=pcall(write,zombie,entry.strength)
    if not ok then print("[GodSystem][Freeze] native apply: "..tostring(err)); return false end
    -- New phase starts a new track, since native speed is sampled at track start.
    entry.phase=old==1 and "2" or "1"
    return pcall(phase,zombie,entry.phase)
end
function N.clear(entry)
    local zombie=entry.object
    if not zombie then return end
    local ok,err=pcall(clear,zombie)
    if not ok then print("[GodSystem][Freeze] native restore: "..tostring(err)) end
end
function N.check(entry)
    -- Restore our phase after native controller/state reinitialization, not each tick.
    if entry.object:getVariableString("GSFreezePhase")~=entry.phase then N.apply(entry) end
end
function N.swing(player,weapon,remote)
    if not player or not instanceof(player,"IsoPlayer") or player:isDead() then return false end
    if not I.isWeapon(weapon) or weapon:isRanged() or player:getPrimaryHandItem()~=weapon then return false end
    if player:isPerformingShoveAnimation() or player:isPerformingStompAnimation() or player:isShoveStompAnim() then return false end
    -- The swing event is proof on the originating client.  The server adds
    -- its attack-state check to reject forged network messages.
    return not remote or player:isPerformingAttackAnimation() or player:isAttackStarted()
end
return N
