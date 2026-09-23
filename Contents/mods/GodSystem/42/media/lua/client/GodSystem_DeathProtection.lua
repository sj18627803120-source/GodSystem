-- Single-player only. Own state and hooks; no dependency on DeathEscape.
if (isClient and isClient()) or (isServer and isServer()) then return end
GodSystemDeathProtection = GodSystemDeathProtection or {}
local P = GodSystemDeathProtection
local active, cachedData
local nextHealthCheckMs = 0
local marker = "GodSystemDeathProtectionRestore"
local function runtime() return GodSystemApp.services.runtime end
local function now() return getTimestampMs() end
local function text(key, fallback) return runtime().text("DeathProtection_"..key, fallback) end
local function data()
    cachedData = cachedData or runtime().getData()
    return cachedData
end
function P.count()
    local n = tonumber(data().deathProtectionCharges) or 0
    if n ~= n or n < 0 or n > 9007199254740991 then return 0 end
    return math.floor(n)
end
function P.cost()
    return GodSystemRuntimeConfig.get("DeathProtectionCost", 20000)
end
local function supported(p)
    return p and p.setInvulnerable and p.isInvulnerable and p.setAvoidDamage
        and p.setDeathDragDown and p.setHitReaction and p.setBlockMovement
        and p.setKilledByFall and p.teleportTo and p.getBodyDamage
end
local function otherProtection(p)
    return DeathEscape and DeathEscape.isEnabled and DeathEscape.isEnabled(p) == true
end
function P.buy()
    local p = getSpecificPlayer(0)
    if not supported(p) or p:isDead() then return false end
    if otherProtection(p) then runtime().notify(text("OtherActive", "Disable DeathEscape before using this protection.")); return false end
    local count, cost = P.count(), tonumber(P.cost())
    if count >= 9007199254740991 or not cost or cost ~= cost or cost < 0 or cost > 1000000 then return false end
    local paid = runtime().spendCurrency(cost)
    if not paid then runtime().notify(runtime().text("Notify_CurrencyNotEnough", "Not enough currency")); return false end
    data().deathProtectionCharges = count + 1
    data().stats.spentPoints = (data().stats.spentPoints or 0) + cost
    runtime().save()
    runtime().notify(text("Purchased", "Death protection purchased. Remaining: ")..tostring(count + 1))
    return true
end
local function heal(p)
    p:getBodyDamage():RestoreToFullHealth()
    p:setHealth(1)
    p:setDeathDragDown(false)
    if p:getHitReaction() == "EndDeath" then p:setHitReaction("") end
    p:setBlockMovement(false)
    p:setKilledByFall(false)
end
-- Search only when a charge activates, within already loaded squares on this floor.
local function escapePosition(p)
    local cell = getCell()
    if not cell or p:getVehicle() then return nil end
    local zombies, list = {}, cell:getZombieList()
    for i=0,list:size()-1 do
        local z=list:get(i)
        if z and not z:isDead() and math.abs(z:getZ()-p:getZ())<.5 then
            local dx,dy=z:getX()-p:getX(),z:getY()-p:getY()
            if dx*dx+dy*dy <= 900 then zombies[#zombies+1]={x=z:getX(),y=z:getY()} end
        end
    end
    local best, bestDistance
    for _,radius in ipairs({5,8,12,16,20}) do
        for sample=0,15 do
            local angle=sample*math.pi/8
            local x,y=math.floor(p:getX()+math.cos(angle)*radius),math.floor(p:getY()+math.sin(angle)*radius)
            local square=cell:getGridSquare(x,y,math.floor(p:getZ()))
            if square and not square:isSolid() and square:isSolidFloor() and not square:isVehicleIntersecting() and square:isFree(true) then
                local distance=math.huge
                for _,z in ipairs(zombies) do
                    local dx,dy=z.x-x-.5,z.y-y-.5
                    distance=math.min(distance,dx*dx+dy*dy)
                end
                local point={x=x+.5,y=y+.5,z=math.floor(p:getZ())}
                if distance>=25 then return point end
                if distance>=4 and (not bestDistance or distance>bestDistance) then best,bestDistance=point,distance end
            end
        end
    end
    return best
end
local function restoreFlags(p)
    local saved=p:getModData()[marker]
    if type(saved)=="table" then
        p:setInvulnerable(saved.invulnerable == true)
        p:setAvoidDamage(false)
        p:getModData()[marker]=nil
    end
end
function P.activate(p, cancelHit)
    if active or not supported(p) or (p.isOnDeathDone and p:isOnDeathDone()) or P.count()<1 or otherProtection(p) then return false end
    -- Existing native protection does not spend a purchased charge.
    if p:isInvulnerable() or (p.isGodMod and p:isGodMod()) then return false end
    active={player=p,untilMs=now()+500,repair=2}
    p:getModData()[marker]={invulnerable=p:isInvulnerable()}
    local enabled=pcall(function() p:setInvulnerable(true) end)
    if not enabled then restoreFlags(p);active=nil;return false end
    data().deathProtectionCharges=P.count()-1
    runtime().save()
    local ok=pcall(function()
        if cancelHit then p:setAvoidDamage(true) end
        heal(p)
        local point=escapePosition(p)
        if point then
            p:teleportTo(point.x,point.y,point.z)
            data().lastMoveX,data().lastMoveY,data().lastMoveZ=p:getX(),p:getY(),p:getZ()
        end
    end)
    runtime().notify(text(ok and "Used" or "Partial", ok and "Death protection used. Remaining: " or "Protection triggered; recovery was incomplete. Remaining: ")..tostring(P.count()))
    return true
end
local function danger(p)
    return p:getHealth()<=.15 or p:getBodyDamage():getOverallBodyHealth()<=15
end
function P.onDamage(p, damageType, damage)
    if p~=getSpecificPlayer(0) or active or not cachedData or P.count()<1 then return end
    -- Health threshold and drag-down hooks also cover damage events with no amount.
    if danger(p) then P.activate(p,true) end
end
function P.onUpdate(p)
    if p~=getSpecificPlayer(0) then return end
    if active then
        if active.player~=p then restoreFlags(active.player);active=nil
        else
            if active.repair>0 then pcall(heal,p);active.repair=active.repair-1 end
            if now()>=active.untilMs then restoreFlags(p);active=nil end
            return
        end
    end
    if not cachedData or P.count()<1 then return end
    if p:isDeathDragDown() or p:getHitReaction()=="EndDeath" then P.activate(p,false);return end
    if now() >= nextHealthCheckMs then
        nextHealthCheckMs=now()+500
        if danger(p) then P.activate(p,false) end
    end
end
function P.onCreate(_,p)
    if p and p==getSpecificPlayer(0) then restoreFlags(p);active=nil end
end
function P.start()
    nextHealthCheckMs=0
    -- Rebind the current world's data at each load; never keep the previous save's reference.
    active=nil
    cachedData=runtime().getData()
    local p=getSpecificPlayer(0)
    if p then restoreFlags(p) end
end
Events.OnGameStart.Add(P.start)
Events.OnCreatePlayer.Add(P.onCreate)
Events.OnPlayerGetDamage.Add(P.onDamage)
Events.OnPlayerUpdate.Add(P.onUpdate)
return P
