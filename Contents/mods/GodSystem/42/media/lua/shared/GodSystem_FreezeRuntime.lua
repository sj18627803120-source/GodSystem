require "GodSystem_EquipmentFreeze"
-- Bounded spatial preparation and transient effects; native/network work is injected.
GodSystemFreezeRuntime = GodSystemFreezeRuntime or {}
local R,F=GodSystemFreezeRuntime,GodSystemEquipmentFreeze
R.__index=R
function R.new(adapter)
    return setmetatable({a=adapter,effects={},byObject={},pulses={},head=1,cursor=1,
        metrics={ticks=0,entries=0,squares=0,objects=0,applied=0,restored=0,maxMs=0,maxQueueMs=0}},R)
end
function R:wake()
    if self.running then return end
    self.running=true
    self.tickCallback=self.tickCallback or function() self:tick() end
    self.a.attach(self.tickCallback)
end
function R:touch(object,strength,expires,now)
    if expires<=now or strength<=0 or not self.a.alive(object) then return false end
    local entry=self.byObject[object]
    if entry and entry.expires<=now then
        self.a.clear(entry); self.byObject[object]=nil; entry.dead=true; entry=nil
    end
    local changed=not entry or strength>entry.strength
    if not entry then
        entry={object=object,strength=0,expires=0,nextCheck=0}
        self.effects[#self.effects+1]=entry; self.byObject[object]=entry
    end
    entry.strength,entry.expires=F.merge(entry,strength,expires)
    entry.visualUntil=now+F.VisualMs
    if changed then
        if self.a.apply(entry)==false then
            self.a.clear(entry); self.byObject[object]=nil; entry.dead=true
            self:wake()
            return false
        end
        self.metrics.applied=self.metrics.applied+1
    end
    if self.a.changed then self.a.changed(entry,now) end
    self:wake()
    return true
end
function R:clearObject(object)
    local entry=self.byObject[object]
    if not entry then return false end
    self.a.clear(entry)
    self.byObject[object]=nil
    entry.dead=true
    self:wake()
    return true
end
function R:pulse(x,y,z,radius,strength,expires,now)
    self.pulses[#self.pulses+1]={x=x,y=y,z=math.floor(z),radius=radius,strength=strength,expires=expires,
        sx=math.floor(x-radius),sy=math.floor(y-radius),minY=math.floor(y-radius),
        maxX=math.floor(x+radius),maxY=math.floor(y+radius),index=0,seen={},created=now}
    self:wake()
end
function R:scan(now)
    local p=self.pulses[self.head]
    if not p then return false end
    if p.expires<=now or p.sx>p.maxX then
        self.metrics.maxQueueMs=math.max(self.metrics.maxQueueMs,now-p.created)
        self.pulses[self.head]=false; self.head=self.head+1
        if self.head>#self.pulses then self.pulses={}; self.head=1 end
        return true
    end
    if not p.list then
        local square=self.a.square(p.sx,p.sy,p.z)
        p.list=square and square:getMovingObjects() or nil
        self.metrics.squares=self.metrics.squares+1
    end
    if p.list and p.index<p.list:size() then
        local object=p.list:get(p.index); p.index=p.index+1
        self.metrics.objects=self.metrics.objects+1
        if not p.seen[object] and self.a.alive(object) then
            p.seen[object]=true
            if F.inside(object:getX(),object:getY(),object:getZ(),p.x,p.y,p.z,p.radius) then
                self:touch(object,p.strength,p.expires,now)
            end
        end
    else
        p.list=nil; p.index=0; p.sy=p.sy+1
        if p.sy>p.maxY then p.sy=p.minY; p.sx=p.sx+1 end
    end
    return true
end
function R:check(now)
    if #self.effects==0 then return false end
    if self.cursor>#self.effects then self.cursor=1 end
    local entry=self.effects[self.cursor]
    if entry.dead or self.stopping or entry.expires<=now or not self.a.alive(entry.object) then
        if not entry.dead then
            self.a.clear(entry); self.byObject[entry.object]=nil
            self.metrics.restored=self.metrics.restored+1
        end
        self.effects[self.cursor]=self.effects[#self.effects]; self.effects[#self.effects]=nil
    else
        if now>=entry.nextCheck then
            entry.nextCheck=now+100
            if self.a.check then self.a.check(entry,now) end
        end
        self.cursor=self.cursor+1
    end
    return true
end
function R:stop()
    self.pulses={}; self.head=1; self.stopping=true
    if #self.effects>0 then self:wake() end
end
function R:tick()
    local now=self.a.now(); local started=self.a.budgetNow()
    if not self.a.enabled() then self:stop() end
    local used,checked=0,0
    while used<F.EntryBudget do
        local worked=false
        if not self.stopping and self.a.prepare and used%3==0 then worked=self.a.prepare(now) end
        if not worked and not self.stopping and self.pulses[self.head] and used%2==0 then worked=self:scan(now) end
        if not worked and checked<#self.effects then worked=self:check(now); checked=checked+1 end
        if not worked and not self.stopping then worked=self:scan(now) end
        if not worked and not self.stopping and self.a.prepare then worked=self.a.prepare(now) end
        if not worked then break end
        used=used+1
        if self.a.budgetNow()-started>=F.TimeBudgetMs then break end
    end
    if self.a.flush then self.a.flush(now) end
    self.metrics.ticks=self.metrics.ticks+1; self.metrics.entries=self.metrics.entries+used
    self.metrics.lastEntries=used
    self.metrics.maxMs=math.max(self.metrics.maxMs,self.a.budgetNow()-started)
    if #self.effects==0 and not self.pulses[self.head] and not (self.a.pending and self.a.pending()) then
        self.running=false; self.stopping=false; self.a.detach(self.tickCallback)
    end
end
-- Lifecycle teardown is rare and synchronous: never leave native variables behind.
function R:reset()
    for _,entry in ipairs(self.effects) do if not entry.dead then self.a.clear(entry) end end
    if self.running then self.a.detach(self.tickCallback) end
    self.effects={}; self.byObject={}; self.pulses={}; self.head=1; self.cursor=1
    self.running=false; self.stopping=false
end
return R
