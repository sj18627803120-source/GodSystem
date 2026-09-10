require "GodSystem_FreezeRuntime"
require "GodSystem_FreezeNative"

-- MP presentation bridge.  The server chooses every target and strength; this
-- client only resolves a short-lived nearby entity reference before applying
-- the already-authoritative animation variables.
GodSystemFreezeClient = GodSystemFreezeClient or {}
local C,N,R=GodSystemFreezeClient,GodSystemFreezeNative,GodSystemFreezeRuntime
C.__index=C

local function nowMs() return N.now(true) end
local function budgetNow() return getTimestampMs() end
local function number(value,minimum,maximum)
    value=tonumber(value)
    if not value or value~=value or value<minimum or value>maximum then return nil end
    return value
end

function C.new(send)
    local self=setmetatable({send=send,mp=true,session=nil,key=nil,sequence=0,serial=0,
        pending={},head=1,metrics={received=0,dropped=0,resolved=0,unresolved=0,
        sent=0,visualFrames=0}},C)
    self.runtime=R.new({
        now=nowMs,budgetNow=budgetNow,
        enabled=function() return self:enabled() end,
        alive=N.alive,
        square=function(x,y,z) return getCell():getGridSquare(x,y,z) end,
        attach=function(fn) Events.OnTick.Add(fn) end,
        detach=function(fn) Events.OnTick.Remove(fn) end,
        apply=N.apply,clear=N.clear,check=N.check,
        prepare=function(now) return self:prepare(now) end,
        pending=function() return self.pending[self.head]~=nil end,
    })
    return self
end

function C:enabled()
    return self.config and self.config.enabled and self.config.freezeEnabled
end
function C:setConfig(config)
    self.config=config
    if not self:enabled() then self:reset(false) end
end
function C:hello(args)
    if type(args)~="table" or type(args.session)~="string" or type(args.key)~="string" then return false end
    self:reset(false)
    self.session,args.session=args.session,args.session
    self.key=args.key
    return true
end
function C:effects(args)
    if type(args)~="table" or args.session~=self.session or not number(args.serial,1,9007199254740000)
        or args.serial<=self.serial or type(args.rows)~="table" then return false end
    self.serial=args.serial
    for _,row in ipairs(args.rows) do
        local id=number(row.id,0,9007199254740000)
        local x,y,z=number(row.x,-10000000,10000000),number(row.y,-10000000,10000000),number(row.z,-128,128)
        local strength,expires=number(row.strength,0,0.8),number(row.expires,0,9007199254740000)
        if id and x and y and z and strength and expires then
            self.pending[#self.pending+1]={id=id,x=x,y=y,z=math.floor(z),strength=strength,expires=expires,
                visual=row.visuals~=false,token=tostring(row.token or ""),created=nowMs()}
            self.metrics.received=self.metrics.received+1
        else self.metrics.dropped=self.metrics.dropped+1 end
    end
    -- The queue is only a recovery path for nearby entities.  Do not let a
    -- burst of stale packets turn into a permanent scene scan.
    while #self.pending-self.head+1>256 do self.pending[self.head]=nil; self.head=self.head+1; self.metrics.dropped=self.metrics.dropped+1 end
    self.runtime:wake()
    return true
end
function C:nextRow()
    local row=self.pending[self.head]
    self.pending[self.head]=nil; self.head=self.head+1
    if self.head>#self.pending then self.pending={}; self.head=1 end
    return row
end
function C:prepare(now)
    local row=self.pending[self.head]
    if not row then return false end
    if row.expires<=now then
        self:nextRow(); return true
    end
    if not row.sx then
        row.sx=math.floor(row.x)-2; row.sy=math.floor(row.y)-2
        row.minY=row.sy; row.maxX=math.floor(row.x)+2; row.maxY=math.floor(row.y)+2; row.index=0
    end
    if row.sx>row.maxX then self.metrics.unresolved=self.metrics.unresolved+1; self:nextRow(); return true end
    if not row.list then
        local square=self.runtime.a.square(row.sx,row.sy,row.z)
        row.list=square and square:getMovingObjects() or nil
    end
    if row.list and row.index<row.list:size() then
        local object=row.list:get(row.index); row.index=row.index+1
        if N.alive(object) and object:getOnlineID()==row.id then
            if row.expires<=now then self.runtime:clearObject(object)
            else
                self.runtime:touch(object,row.strength,row.expires,now)
                local entry=self.runtime.byObject[object]
                if entry then entry.visuals=row.visual end
            end
            self.metrics.resolved=self.metrics.resolved+1; self:nextRow()
        end
    else
        row.list=nil; row.index=0; row.sy=row.sy+1
        if row.sy>row.maxY then row.sy=row.minY; row.sx=row.sx+1 end
    end
    return true
end
function C:swing(player,weapon)
    if not self:enabled() or not self.key or not N.swing(player,weapon,false) then return false end
    self.sequence=self.sequence+1
    local payload={session=self.session,key=self.key,seq=self.sequence,itemId=GodSystemEquipmentItems.id(weapon),at=nowMs()}
    local sent=self.send and self.send(payload)
    if sent then self.metrics.sent=self.metrics.sent+1 end
    return sent==true
end
function C:reset(clearSession)
    self.runtime:reset(); self.pending={}; self.head=1; self.serial=0
    if clearSession then self.session=nil; self.key=nil; self.sequence=0 end
end

local texture=nil
local function mark(renderer,tex,x,y,zoom)
    -- B42.20.4: render(Texture, float x8, Consumer). Kahlua requires
    -- the final callback argument explicitly; nil means no callback.
    local size=12/zoom
    renderer:render(tex,math.floor(x-size/2),math.floor(y-size/2),math.ceil(size),math.ceil(size),0.42,0.78,1.0,0.86,nil)
    local inner=4/zoom
    renderer:render(tex,math.floor(x-inner/2),math.floor(y-inner/2),math.ceil(inner),math.ceil(inner),0.90,0.98,1.0,0.96,nil)
end
function C:render()
    -- The SP authority already caches config while applying/checking effects.
    -- Rendering must not refresh configuration or stop runtime work.
    -- cfg is legitimately nil before the first world config and after reset.
    -- Do not use "SP and cfg or config": it falls back to A:config (a method).
    local config
    if self.mp==false then config=self.cfg else config=self.config end
    if not (config and config.enabled and config.freezeEnabled and config.freezeVisuals)
        or not ISCoordConversion or not ISCoordConversion.ToScreen then return end
    local renderer=getRenderer and getRenderer() or nil
    if not renderer then return end
    texture=texture or getTexture("media/textures/GodSystem_WhitePixel.png")
    if not texture then return end
    local now=self.mp==false and getTimestampMs() or nowMs(); local drawn=0
    for _,entry in ipairs(self.runtime.effects) do
        if drawn>=32 then break end
        if entry.visuals and now<(entry.visualUntil or 0) and N.alive(entry.object) then
            local sx,sy=ISCoordConversion.ToScreen(entry.object:getX(),entry.object:getY(),entry.object:getZ())
            if sx and sy then
                local zoom=getCore():getZoom(0); sx,sy=sx/zoom,sy/zoom-38/zoom
                mark(renderer,texture,sx,sy-18/zoom,zoom)
                drawn=drawn+1
            end
        end
    end
    if drawn>0 then self.metrics.visualFrames=self.metrics.visualFrames+1 end
end

if Events.OnPreUIDraw then Events.OnPreUIDraw.Add(function()
    local client=GodSystemEquipmentClient and GodSystemEquipmentClient.freeze
    if client and client.runtime then C.render(client) end
end) end
return C
