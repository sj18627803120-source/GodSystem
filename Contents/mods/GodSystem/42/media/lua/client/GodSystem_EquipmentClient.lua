require "GodSystem_Core"
require "GodSystem_EquipmentAuthority"
require "GodSystem_FreezeAuthority"
require "GodSystem_FreezeClient"
if isServer and isServer() and not (isClient and isClient()) then return end

GodSystemEquipmentClient = GodSystemEquipmentClient or {}
local C,E,I,A=GodSystemEquipmentClient,GodSystemEquipment,GodSystemEquipmentItems,GodSystemEquipmentAuthority
C.states,C.refs,C.packets,C.windows,C.projections,C.inspectPending,C.inspectNegative={},{},{},{},{},{},{}
C.authority=nil
local multiplayer=isClient and isClient()
local function runtime() return GodSystemApp.services.runtime end
function C.text(key,fallback) return runtime().text(key,fallback or key) end
function C.notify(code) runtime().notify(C.text("NotifyMP_"..tostring(code),tostring(code))) end
function C.player(num) return getSpecificPlayer and getSpecificPlayer(num or 0) or (getPlayer and getPlayer()) end
local function number(player) return I.value(player,"getPlayerNum",0) end

if not multiplayer then
    local adapter=A.defaults(false)
    adapter.data=function() return runtime().getData() end
    -- The existing SP economy is world-scoped. Select the concrete local player's cash inventory only
    -- for the synchronous legacy currency call, then restore the resolver even on an exception.
    local function currencyCall(player,fn,...)
        local env=GodSystemClientRuntimeEnv
        local previous=env.gsPlayer
        env.gsPlayer=function() return player end
        local results={pcall(fn,...)}
        env.gsPlayer=previous
        if not results[1] then error(results[2]) end
        return unpack(results,2)
    end
    adapter.spend=function(player,cost) return currencyCall(player,runtime().spendCurrency,cost) end
    adapter.refund=function(player,bank,cash)
        if not currencyCall(player,runtime().refundCurrencySources,bank,cash) then C.notify("EquipmentRefundToBank") end
        return true
    end
    adapter.committed=function(_,cost)
        local data=runtime().getData(); data.stats.spentPoints=(data.stats.spentPoints or 0)+cost
        runtime().save()
    end
    adapter.sync=function() return true end
    C.authority=A.install(GodSystemEquipmentService.new(adapter),"sp")
    C.freeze=GodSystemFreezeAuthority.new(C.authority,nil)
    C.authority.lifecycle.hooks.swing=function(player,weapon) C.freeze:swing(player,weapon,{}) end
else
    C.freeze=GodSystemFreezeClient.new(function(payload)
        return GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("equipmentFreezeSwing",payload,C.player())
    end)
end

function C.state(player) return C.states[number(player)] end
function C.changed(player,candidates)
    local window=C.windows[number(player)]
    if window and window:getIsVisible() then window:rebuild(C.state(player),candidates) end
end
function C.request(player,heldOnly)
    if not player then return false end
    if multiplayer then
        if not GodSystemNetwork or not GodSystemNetwork.send then return false end
        return GodSystemNetwork.send("equipmentSync",{heldOnly=heldOnly==true},player)
    end
    if heldOnly then
        C.authority:reconcile(player,I.value(player,"getPrimaryHandItem"),true)
        C.authority:reconcile(player,I.value(player,"getSecondaryHandItem"),true)
    else
        local state,candidates=C.authority:snapshot(player)
        C.states[number(player)]=state
        C.changed(player,candidates)
    end
    return true
end
function C.action(player,args)
    if multiplayer then
        return GodSystemNetwork and GodSystemNetwork.send("equipmentAction",args,player) or false
    end
    args.opId="equipment-"..getRandomUUID()
    local result=C.authority:action(player,args)
    C.notify(result.code)
    C.request(player,false)
    return result.ok
end
function C.busy()
    return multiplayer and GodSystemNetwork and GodSystemNetwork.pendingCommand ~= nil
end

local function projectionKey(item, marker)
    local id=I.id(item)
    if not marker or type(id)~="string" or type(marker.worldId)~="string" or type(marker.equipmentId)~="string"
        or not E.integer(marker.generation,1,E.MaxMoney) or not E.integer(marker.revision,1,9007199254740000) then return nil end
    return table.concat({marker.worldId,marker.equipmentId,tostring(marker.generation),id,I.value(item,"getFullType", ""),tostring(marker.revision)},"|")
end
function C.cacheProjection(payload)
    if type(payload)~="table" or payload.valid~=true or type(payload.itemId)~="string" or type(payload.equipmentId)~="string"
        or type(payload.fullType)~="string" or type(payload.levels)~="table" then return end
    local key=table.concat({payload.worldId,payload.equipmentId,tostring(payload.generation),payload.itemId,payload.fullType,tostring(payload.revision)},"|")
    C.projectionOrder=C.projectionOrder or {}
    if not C.projections[key] then C.projectionOrder[#C.projectionOrder+1]=key end
    C.projections[key]=payload
    C.inspectPending[key],C.inspectNegative[key]=nil,nil
    while #C.projectionOrder>128 do
        local oldest=table.remove(C.projectionOrder,1)
        C.projections[oldest],C.inspectPending[oldest],C.inspectNegative[oldest]=nil,nil,nil
    end
end
function C.tooltipProjection(item)
    if not I.isWeapon(item) then return nil end
    local marker=I.marker(item); local key=projectionKey(item,marker)
    if not key then return nil end
    if not multiplayer then
        local root=C.authority and C.authority:root(); local record=root and C.authority:recordFor(item,root)
        if record and I.matches(item,root,record) then
            local _,_,cfg=C.authority:account(C.player())
            if cfg then return {valid=true,levels=E.projectionLevels(record),config=cfg} end
        end
        return nil
    end
    local cached=C.projections[key]
    if cached then return cached end
    local now=GodSystemScheduler.nowMs()
    if not C.inspectPending[key] and (not C.inspectNegative[key] or now-C.inspectNegative[key]>=5000) then
        C.inspectPending[key]=now
        local requestId="inspect-"..getRandomUUID()
        local sent=GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("equipmentInspect",{
            requestId=requestId,worldId=marker.worldId,equipmentId=marker.equipmentId,generation=marker.generation,
            itemId=I.id(item),fullType=I.value(item,"getFullType"),revision=marker.revision},C.player())
        if not sent then C.inspectPending[key]=nil; C.inspectNegative[key]=now end
    end
    return nil
end
function C.getDiagnostics()
    return {authority=C.authority and E.copy(C.authority.metrics) or nil,items=E.copy(I.metrics),
        freeze=C.freeze and E.copy(C.freeze.metrics) or nil}
end

function C.apply(player,item)
    if not I.isWeapon(item) then return end
    local id=I.id(item); local packet=C.packets[id]
    if not packet or packet.fullType~=I.value(item,"getFullType") then return end
    C.refs[id]=item
    local md=I.value(item,"getModData")
    if not md then return end
    -- Only an authenticated S2C payload may repair the local marker or apply attributes.
    local state=C.state(player)
    local identity=false
    for _,row in ipairs(state and state.rows or {}) do
        local r=row.record; local m=packet.marker
        if r and m and m.schema==E.Schema and m.worldId==state.worldId and r.itemId==id and r.id==m.equipmentId
            and r.generation==m.generation and r.revision==m.revision then identity=true; break end
    end
    local cfg=type(packet.growthConfig)=="table" and packet.growthConfig or nil
    local percent=cfg and E.number(cfg.EquipmentGrowthPercent)
    local rule=E.Settings.EquipmentGrowthPercent
    local active=cfg and cfg.enabled==true and percent and percent>=rule[2] and percent<=rule[3]
        and packet.active and identity and state and state.ready and state.config.enabled and not state.blocked
        and packet.ownerKey==state.ownerKey and packet.characterId==state.characterId
        and I.held(player,item) and I.owned(player,item) and not I.value(player,"isDead",true)
    if packet.base then I.apply(item,packet.base,active and packet.levels or nil,cfg)
    elseif packet.raw then I.write(item,packet.raw) end
    md[E.ItemKey]=E.copy(packet.marker)
end

-- One operation-local index at page initialization; retain selected candidates/known gear, never the index.
function C.candidates(player)
    local index=GodSystemInventoryIndex.build(I.value(player,"getInventory"))
    local result={}
    if not index.valid then return result,"EquipmentInventoryChanged" end
    for id,row in pairs(index.byId) do
        if not index.ambiguous[id] and I.isWeapon(row.item) then
            if C.authority and I.marker(row.item) then C.authority:reconcile(player,row.item,true) end
            if multiplayer then C.apply(player,row.item) end
            if I.marker(row.item) then C.refs[id]=row.item
            else result[#result+1]={id=id,item=row.item,name=I.value(row.item,"getDisplayName",I.value(row.item,"getFullType"))} end
        end
    end
    table.sort(result,function(a,b) if a.name==b.name then return a.id<b.id end; return a.name<b.name end)
    return result
end

if multiplayer then
    local lastHeld=0
    GodSystemEquipmentLifecycle.install("client",{
        item=function(player,item,force)
            C.apply(player,item)
            if force and I.marker(item) and player and I.value(player,"isLocalPlayer",false) then
                local now=GodSystemScheduler.nowMs()
                if now-lastHeld>=1000 then lastHeld=now; C.request(player,true) end
            end
        end,
        swing=function(player,weapon) if C.freeze then C.freeze:swing(player,weapon) end end,
        beforeParts=function(_,item)
            local packet=C.packets[I.id(item)]
            if packet and packet.base then I.apply(item,packet.base,nil) end
        end,
        periodic=function()
            for _,item in pairs(C.refs) do
                for n=0,(getNumActivePlayers and getNumActivePlayers() or 1)-1 do
                    local player=C.player(n)
                    if player and I.owned(player,item) then C.apply(player,item) end
                end
            end
            for n,window in pairs(C.windows) do if window:getIsVisible() then C.request(C.player(n),false) end end
        end,
        reset=function()
            C.states={}; C.refs={}; C.packets={}; C.projections={}; C.inspectPending={}; C.inspectNegative={}; C.session=nil; lastHeld=0
            if C.freeze then C.freeze:reset(true) end
        end,
    })
    Events.OnServerCommand.Add(function(module,command,args)
        if module~="GodSystem" or type(args)~="table" then return end
        if command=="equipmentFreezeHello" then
            if C.freeze then C.freeze:hello(args) end
        elseif command=="equipmentFreezeEffects" then
            if C.freeze then C.freeze:effects(args) end
        elseif command=="equipmentState" then
            local player=C.player(args.playerNum or 0)
            if args.state and args.state.ownerKey then
                for n=0,(getNumActivePlayers and getNumActivePlayers() or 1)-1 do
                    local candidate=C.player(n)
                    if candidate and "mp:"..I.value(candidate,"getUsername","")==args.state.ownerKey then player=candidate; break end
                end
            end
            if player then
                C.states[number(player)]=args.state
                if C.freeze then C.freeze:setConfig(args.state.config) end
                local lifecycle=GodSystemEquipmentLifecycle.instances.client
                if lifecycle then lifecycle.track(player) end
                for _,item in pairs(C.refs) do if I.owned(player,item) then C.apply(player,item) end end
                C.apply(player,I.value(player,"getPrimaryHandItem")); C.apply(player,I.value(player,"getSecondaryHandItem"))
                C.changed(player)
            end
        elseif command=="equipmentItem" then
            if type(args.itemId)~="string" or type(args.raw)~="table" or not E.integer(args.serial,1,9007199254740000) then return end
            if C.session~=args.session then
                C.packets={}; C.refs={}; C.packetOrder={}; C.projections={}; C.projectionOrder={}; C.inspectPending={}; C.inspectNegative={}; C.session=args.session
            end
            local old=C.packets[args.itemId]
            if old and old.serial>=args.serial then return end
            -- Bound transient unseen-item delivery cache; a fresh handshake/page operation can resend it.
            C.packetOrder=C.packetOrder or {}
            if not old then C.packetOrder[#C.packetOrder+1]=args.itemId end
            C.packets[args.itemId]=args
            if args.marker and args.levels and args.growthConfig then
                C.cacheProjection({valid=true,worldId=args.marker.worldId,equipmentId=args.marker.equipmentId,
                    generation=args.marker.generation,itemId=args.itemId,fullType=args.fullType,revision=args.marker.revision,
                    levels=args.levels,config=args.growthConfig})
            end
            while #C.packetOrder>128 do local id=table.remove(C.packetOrder,1); C.packets[id]=nil; C.refs[id]=nil end
            for n=0,(getNumActivePlayers and getNumActivePlayers() or 1)-1 do
                local player=C.player(n)
                if player then
                    local item=C.refs[args.itemId]
                    if item and I.owned(player,item) then C.apply(player,item) end
                    C.apply(player,I.value(player,"getPrimaryHandItem"))
                    C.apply(player,I.value(player,"getSecondaryHandItem"))
                end
            end
        elseif command=="equipmentProjection" then
            if args.valid then C.cacheProjection(args)
            else
                local marker=args and args.worldId and {worldId=args.worldId,equipmentId=args.equipmentId,generation=args.generation,revision=args.revision}
                if marker and type(args.itemId)=="string" and type(args.fullType)=="string" then
                    local key=table.concat({marker.worldId,marker.equipmentId,tostring(marker.generation),args.itemId,args.fullType,tostring(marker.revision)},"|")
                    C.inspectPending[key]=nil; C.inspectNegative[key]=GodSystemScheduler.nowMs()
                end
            end
        end
    end)
end
local function sessionEnd()
    C.states={}; C.refs={}; C.packets={}; C.packetOrder={}; C.projections={}; C.projectionOrder={}; C.inspectPending={}; C.inspectNegative={}; C.session=nil
    if C.freeze then C.freeze:reset(true) end
    for _,window in pairs(C.windows) do window:close(); window:removeFromUIManager() end
    C.windows={}
end
if Events.OnDisconnect then Events.OnDisconnect.Add(sessionEnd) end
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(sessionEnd) end
return C
