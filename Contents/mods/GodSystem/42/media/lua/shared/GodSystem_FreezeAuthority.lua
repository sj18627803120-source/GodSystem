require "GodSystem_FreezeRuntime"
require "GodSystem_FreezeNative"
require "GodSystem_RuntimeConfig"
GodSystemFreezeAuthority = GodSystemFreezeAuthority or {}
local A,E,I,F,N,R=GodSystemFreezeAuthority,GodSystemEquipment,GodSystemEquipmentItems,
    GodSystemEquipmentFreeze,GodSystemFreezeNative,GodSystemFreezeRuntime
A.__index=A
function A.new(equipment,send)
    local self=setmetatable({equipment=equipment,send=send,session=getRandomUUID(),players={},
        serial=0,pending={},pendingSet={},lastFlush=0,lastConfig=0,
        metrics={accepted=0,rejected=0,messages=0,estimatedBytes=0,visualFrames=0}},A)
    self.mp=equipment.adapter.multiplayer
    self.runtime=R.new({
        now=function() return N.now(self.mp) end,budgetNow=getTimestampMs,
        enabled=function() local cfg=self:config(); return cfg and cfg.enabled and cfg.freezeEnabled end,
        alive=N.alive,square=function(x,y,z) return getCell():getGridSquare(x,y,z) end,
        attach=function(fn) Events.OnTick.Add(fn) end,detach=function(fn) Events.OnTick.Remove(fn) end,
        apply=function(entry)
            entry.token=entry.token or getRandomUUID()
            return N.apply(entry)
        end,
        clear=function(entry)
            N.clear(entry)
            if self.mp then entry.expires=0; self:queue(entry) end
        end,
        changed=function(entry,now)
            entry.touched=now
            -- SP renders these authority records directly; there is no MP
            -- receive step to populate their presentation flag.
            entry.visuals=self.cfg and self.cfg.freezeVisuals==true
            if self.mp then self:queue(entry) end
        end,
        check=function(entry,now)
            N.check(entry)
            -- Resend only active targets for control transfer / newly relevant clients.
            if self.mp and now>=(entry.nextSend or 0) then entry.nextSend=now+500; self:queue(entry) end
        end,
        flush=function(now) self:flush(now) end,
        pending=function() return #self.pending>0 end,
    })
    return self
end
function A:config()
    local now=getTimestampMs()
    if not self.cfg or now-self.lastConfig>=1000 or now<self.lastConfig then
        local cfg=E.config(self.equipment.adapter.config())
        if self.cfg and (not cfg or cfg.token~=self.cfg.token) then self.runtime:stop() end
        self.cfg=cfg; self.lastConfig=now
    end
    return self.cfg
end
function A:hello(player)
    local state={key=getRandomUUID(),seq=0,lastAt=0}; self.players[player]=state
    if self.send then self.send(player,"equipmentFreezeHello",{session=self.session,key=state.key}) end
end
function A:queue(entry)
    if not self.pendingSet[entry] then self.pendingSet[entry]=true; self.pending[#self.pending+1]=entry end
end
function A:flush(now)
    if not self.mp or #self.pending==0 then return end
    -- Every bounded tick sends at most one 32-target batch; never delay final clears.
    local rows={}
    for n=1,math.min(32,#self.pending) do
        local entry=table.remove(self.pending); self.pendingSet[entry]=nil
        local z=entry.object
        rows[#rows+1]={id=z:getOnlineID(),token=entry.token,x=z:getX(),y=z:getY(),z=z:getZ(),
            strength=entry.strength,expires=entry.expires,
            touched=entry.touched,visuals=self.cfg and self.cfg.freezeVisuals}
    end
    self.serial=self.serial+1
    local online=getOnlinePlayers()
    for n=0,online:size()-1 do
        local player=online:get(n); local relevant=false
        -- Native MP zombie simulation belongs to nearby clients. Do not broadcast map-wide.
        for _,row in ipairs(rows) do
            local dx,dy=player:getX()-row.x,player:getY()-row.y
            if dx*dx+dy*dy<=128*128 then relevant=true; break end
        end
        if relevant then
            self.send(player,"equipmentFreezeEffects",{session=self.session,serial=self.serial,at=now,rows=rows})
            self.metrics.messages=self.metrics.messages+1
            self.metrics.estimatedBytes=self.metrics.estimatedBytes+80+#rows*180
        end
    end
    -- A pending final-clear batch keeps the worker alive via flush-only ticks.
end
function A:weaponRecord(player,weapon)
    local cached=self.equipment.players[player]
    if not cached then self.equipment:account(player); cached=self.equipment.players[player] end
    if not cached or cached.account.uncertainOp then return nil end
    local record=self.equipment:recordFor(weapon,cached.root)
    if not record or record.identityConflict or not I.matches(weapon,cached.root,record)
        or record.ownerKey~=cached.account.ownerKey or record.characterId~=cached.account.activeCharacterId
        or not I.owned(player,weapon) then return nil end
    return record
end
function A:swing(player,weapon,args)
    local cfg=self:config()
    if not cfg or not cfg.enabled or not cfg.freezeEnabled then return false end
    local now=N.now(self.mp)
    if now<=0 or not N.swing(player,weapon,self.mp) then return false end
    if self.mp then
        local state=self.players[player]
        if not state or type(args)~="table" or args.key~=state.key or args.session~=self.session
            or not E.integer(args.seq,1,9007199254740000) or args.seq<=state.seq
            or args.itemId~=I.id(weapon) or not E.number(args.at)
            or args.at<=state.lastAt or args.at>now+500 or now-args.at>2000 then
            self.metrics.rejected=self.metrics.rejected+1; return false
        end
        state.seq=args.seq; state.lastAt=args.at
    end
    local record=self:weaponRecord(player,weapon)
    local level=record and E.level(record,"freeze") or 0
    if level<=0 then return false end
    self.runtime:pulse(player:getX(),player:getY(),player:getZ(),cfg.EquipmentFreezeRadius,
        F.strength(level,cfg),now+cfg.EquipmentFreezeSeconds*1000,now)
    self.metrics.accepted=self.metrics.accepted+1
    return true
end
function A:reset()
    self.runtime:reset(); self.players={}; self.pending={}; self.pendingSet={}; self.cfg=nil
end
return A
