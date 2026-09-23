require "GodSystem_EquipmentImpact"
require "GodSystem_ImpactRuntime"
require "GodSystem_EquipmentSplash"
require "GodSystem_SplashRuntime"
GodSystemEquipmentCombat = GodSystemEquipmentCombat or {}
local C,E,I,P,R,S,SR=GodSystemEquipmentCombat,GodSystemEquipment,GodSystemEquipmentItems,
    GodSystemEquipmentImpact,GodSystemImpactRuntime,GodSystemEquipmentSplash,GodSystemSplashRuntime
C.__index=C

local function now() return getTimestampMs and getTimestampMs() or 0 end
local function weaponOK(player,weapon)
    return player and I.isWeapon(weapon) and not I.value(weapon,"isRanged",false)
        and I.value(player,"getPrimaryHandItem")==weapon
        and not I.value(player,"isPerformingShoveAnimation",false)
        and not I.value(player,"isPerformingStompAnimation",false)
        and not I.value(player,"isShoveStompAnim",false)
end

function C.new(service,adapter)
    local self=setmetatable({service=service,a=adapter,attacks={},serial=0,derived=0,
        metrics={begun=0,finished=0,hits=0,released=0,rejected=0,splashQueued=0,splashApplied=0,
            splashKills=0,splashRejected=0}},C)
    self.runtime=R.new({
        now=now,attach=function(fn) Events.OnTick.Add(fn) end,detach=function(fn) Events.OnTick.Remove(fn) end,
        square=function(x,y,z) return getCell():getGridSquare(x,y,z) end,
        valid=function(z) return z and instanceof(z,"IsoZombie") and not z:isDead() and not z:isKnockedDown()
            and not z:isOnFloor() and not z:isCrawling() and z:getCurrentSquare()~=nil end,
        apply=function(z,token) self:apply(z,token) end,
        finished=function(job) if self.a.impactFinished then self.a.impactFinished(job) end end,
    })
    self.splashRuntime=SR.new({
        now=now,attach=function(fn) Events.OnTick.Add(fn) end,detach=function(fn) Events.OnTick.Remove(fn) end,
        square=function(x,y,z) return getCell():getGridSquare(x,y,z) end,
        valid=function(z)
            if not z or not instanceof(z,"IsoZombie") then return false end
            local ok,dead=pcall(function() return z:isDead() end)
            local health=E.number(I.value(z,"getHealth"))
            return ok and not dead and health~=nil and health>0 and I.value(z,"getCurrentSquare")~=nil
        end,
        apply=function(z,rule,token) return self:applySplash(z,rule,token) end,
    })
    return self
end

function C:apply(zombie,token)
    self.derived=self.derived+1
    -- Same call as B42.20.4 DebugContextMenu.OnSelectedZombieKnockDown.
    -- Do not substitute state flags for the engine's actual knockdown transition.
    local ok,err=pcall(function() zombie:knockDown(false) end)
    self.derived=self.derived-1
    if not ok then error(err) end
end

function C:applySplash(zombie,rule,token)
    if self.derived>0 or not zombie or type(token)~="table" then return false end
    local player,weapon=token.player,token.weapon
    if not weaponOK(player,weapon) or I.id(weapon)~=token.itemId
        or I.value(weapon,"getFullType")~=token.fullType then return false end
    local record,cfg=self.service:activeRecord(player,weapon)
    if not record or not cfg or not cfg.enabled or not cfg.splashEnabled
        or record.id~=token.equipmentId or record.generation~=token.generation
        or record.revision~=token.revision or (E.level(record,"splash") or 0)<rule.level then return false end
    local damage=S.damage(token.basis,rule.level)
    local health=E.number(I.value(zombie,"getHealth"))
    if not damage or not health or health<=0 then return false end
    self.derived=self.derived+1
    local ok,result=pcall(function()
        if damage>=health then
            -- Preserve native corpse creation, kill attribution, and MP replication.
            zombie:setAttackedBy(player)
            zombie:Kill(weapon,player)
            if zombie:isDead() or (E.number(zombie:getHealth()) or 1)<=0 then return "killed" end
            return false
        end
        zombie:setHealth(health-damage)
        local after=E.number(zombie:getHealth())
        if after and after<health then return "damaged" end
        return false
    end)
    self.derived=self.derived-1
    if not ok then
        self.metrics.splashRejected=self.metrics.splashRejected+1
        if not self.metrics.splashErrorLogged then
            self.metrics.splashErrorLogged=true
            print("[GodSystem] Native splash damage call failed: "..tostring(result))
        end
        return false
    end
    if result=="killed" then self.metrics.splashKills=self.metrics.splashKills+1 end
    if result then self.metrics.splashApplied=self.metrics.splashApplied+1 end
    return result
end

function C:begin(player,weapon,sequence)
    if self.derived>0 or not weaponOK(player,weapon) then self.metrics.rejected=self.metrics.rejected+1; return nil end
    local record,cfg=self.service:activeRecord(player,weapon)
    if not record then return nil end
    local old=self.attacks[player]
    if old and now()-old.startedAt<2000 and old.sequence==sequence then return old end
    self.serial=self.serial+1
    local ledger={attackId=self.serial,sequence=sequence,weapon=weapon,itemId=I.id(weapon),fullType=I.value(weapon,"getFullType"),
        equipmentId=record.id,generation=record.generation,revision=record.revision,startedAt=now(),
        impactReadyAtStart=P.state(record).ready,impactReleased=false,record=record,cfg=cfg,
        directTargets={},splashLevel=cfg.splashEnabled and (E.level(record,"splash") or 0) or 0,
        splashCenter=nil,splashBasis=nil,splashQueued=false}
    self.attacks[player]=ledger; self.metrics.begun=self.metrics.begun+1
    if self.a.begin then self.a.begin(player,weapon,ledger) end
    return ledger
end

function C:hit(zombie,player,weapon)
    if self.derived>0 or not zombie or not player then return false end
    local ledger=self.attacks[player]
    if not ledger or ledger.finished or now()-ledger.startedAt>2000 or ledger.weapon~=weapon
        or ledger.itemId~=I.id(weapon) or ledger.fullType~=I.value(weapon,"getFullType") then return false end
    self.metrics.hits=self.metrics.hits+1
    local didSomething=false
    if zombie and instanceof and instanceof(zombie,"IsoZombie") then
        ledger.directTargets[zombie]=true
        if ledger.splashLevel>0 and not ledger.splashCenter
            and I.value(zombie,"getCurrentSquare")~=nil then
            local x,y,z=E.number(I.value(zombie,"getX")),E.number(I.value(zombie,"getY")),E.number(I.value(zombie,"getZ"))
            local basis=S.basis(I.value(weapon,"getMinDamage"),I.value(weapon,"getMaxDamage"))
            if x and y and z and basis and basis>0 then
                ledger.splashCenter=zombie; ledger.splashBasis=basis; didSomething=true
            end
        end
    end
    if ledger.impactReleased or not ledger.impactReadyAtStart or zombie:isDead() then return didSomething end
    local record,cfg=self.service:activeRecord(player,weapon)
    if not record or record.id~=ledger.equipmentId or record.generation~=ledger.generation or record.revision~=ledger.revision then return didSomething end
    local level=E.level(record,"impact") or 0
    local rule=P.rule(level)
    if not rule or not P.state(record).ready then return didSomething end
    -- Consume before the deferred search.  A thrown engine exception can
    -- never become an unlimited repeat-release loop.
    P.consume(record); ledger.impactReleased=true; self.metrics.released=self.metrics.released+1
    if self.a.progress then self.a.progress(player,record) end
    self.runtime:queue(zombie,rule,{attackId=ledger.attackId,player=player})
    return true
end

function C:finish(player,weapon,sequence)
    local ledger=self.attacks[player]
    if not ledger or ledger.finished or ledger.weapon~=weapon or (sequence and ledger.sequence~=sequence) then return false end
    ledger.finished=true; self.attacks[player]=nil; self.metrics.finished=self.metrics.finished+1
    local record,cfg=self.service:activeRecord(player,weapon)
    if ledger.splashCenter and not ledger.splashQueued and record and cfg and cfg.enabled and cfg.splashEnabled
        and record.id==ledger.equipmentId and record.generation==ledger.generation and record.revision==ledger.revision
        and I.value(ledger.splashCenter,"getCurrentSquare")~=nil then
        local level=E.level(record,"splash") or 0
        local rule=S.rule(level)
        if rule then
            local queued=self.splashRuntime:queue(ledger.splashCenter,rule,{attackId=ledger.attackId,
                player=player,weapon=weapon,itemId=ledger.itemId,fullType=ledger.fullType,
                equipmentId=ledger.equipmentId,generation=ledger.generation,revision=ledger.revision,
                basis=ledger.splashBasis,directTargets=ledger.directTargets})
            ledger.splashQueued=queued
            if queued then self.metrics.splashQueued=self.metrics.splashQueued+1 end
        end
    end
    if ledger.impactReleased then return true end
    if not record or record.id~=ledger.equipmentId or record.revision~=ledger.revision then return false end
    local level=E.level(record,"impact") or 0
    local state,changed=P.advance(record,level)
    if changed and self.a.progress then self.a.progress(player,record,state) end
    return true
end

function C:reset(player)
    if player then self.attacks[player]=nil; self.splashRuntime:cancelPlayer(player)
    else self.attacks={}; self.runtime:reset(); self.splashRuntime:reset() end
end

return C
