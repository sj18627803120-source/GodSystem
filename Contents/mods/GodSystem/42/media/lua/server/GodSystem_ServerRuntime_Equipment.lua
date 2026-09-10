require "GodSystem_EquipmentAuthority"
require "GodSystem_FreezeAuthority"
_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Equipment"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Equipment then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Equipment = true
    setfenv(1,runtimeEnvironment)
    local E,I,A=GodSystemEquipment,GodSystemEquipmentItems,GodSystemEquipmentAuthority
    local adapter=A.defaults(true)
    adapter.data=playerData
    adapter.spend=function(player,cost) return spendCurrency(player,playerData(player),cost) end
    adapter.refund=function(player,bank,cash)
        local original=GodSystemServer.refundCurrencySources(player,playerData(player),bank,cash)
        if not original then notifyCode(player,"EquipmentRefundToBank") end
        return true -- Existing helper preserves failed cash refunds in the bank.
    end
    adapter.committed=function(player,cost)
        local data=playerData(player)
        data.stats.spentPoints=(data.stats.spentPoints or 0)+cost
        storeCheckpoint()
    end
    local session,serial=getRandomUUID(),0
    local syncMetrics={messages=0,estimatedBytes=0,lastMs=0}
    local function estimate(value)
        if type(value)~="table" then return #tostring(value)+5 end
        local size=8
        for key,entry in pairs(value) do size=size+estimate(key)+estimate(entry) end
        return size
    end
    adapter.sync=function(player,item,record,active,syncNativeFields,cfg)
        local started=GodSystemScheduler.nowMs()
        if not item then return false end
        serial=serial+1
        local payload={session=session,serial=serial,itemId=I.id(item),fullType=I.value(item,"getFullType"),
            raw=I.raw(item),base=record and E.copy(record.base),levels=record and E.copy(record.levels),
            marker=E.copy(I.marker(item)),active=active==true,
            ownerKey=record and record.ownerKey,characterId=record and record.characterId}
        -- Keep the applied rule alongside the item, even when the page snapshot is older.
        payload.growthConfig=cfg and {enabled=cfg.enabled,freezeEnabled=cfg.freezeEnabled,
            EquipmentGrowthPercent=cfg.EquipmentGrowthPercent} or nil
        if not payload.raw then return false end
        -- Never resend wear during an ordinary equip/page sync. Paid repair/recovery uses native fields;
        -- our raw payload avoids SyncHandWeaponFieldsPacket's sharpness-derived max-damage getter.
        if syncNativeFields then
            if not syncItemFields or not player then return false end
            syncItemFields(player,item)
        end
        local online=getOnlinePlayers and getOnlinePlayers()
        if not online then return false end
        for n=0,online:size()-1 do sendServerCommand(online:get(n),MODULE,"equipmentItem",payload) end
        syncMetrics.messages=syncMetrics.messages+online:size()
        syncMetrics.estimatedBytes=syncMetrics.estimatedBytes+estimate(payload)*online:size()
        syncMetrics.lastMs=GodSystemScheduler.nowMs()-started
        return true
    end
    local service=A.install(GodSystemEquipmentService.new(adapter),"server")
    GodSystemServer.equipment=service
    service.metrics.network=syncMetrics
    local freeze=GodSystemFreezeAuthority.new(service,function(player,command,payload)
        sendServerCommand(player,MODULE,command,payload)
    end)
    GodSystemServer.freeze=freeze
    service.metrics.freeze=freeze.metrics
    local lastSync={}
    local lastInspect,lastInspectOrder={},{}
    local function sendEquipment(player)
        local payload={playerNum=I.value(player,"getPlayerNum",0),state=service:snapshot(player)}
        sendServerCommand(player,MODULE,"equipmentState",payload)
        syncMetrics.messages=syncMetrics.messages+1
        syncMetrics.estimatedBytes=syncMetrics.estimatedBytes+estimate(payload)
    end
    function Commands.equipmentSync(_,_,player,args)
        local key=I.value(player,"getUsername","")..(args and args.heldOnly and ":held" or ":page")
        local now=GodSystemScheduler.nowMs()
        if lastSync[key] and now-lastSync[key]<1000 then return end
        lastSync[key]=now
        if args and args.heldOnly then
            service:account(player)
            local primary,secondary=I.value(player,"getPrimaryHandItem"),I.value(player,"getSecondaryHandItem")
            if I.isWeapon(primary) and not service:reconcile(player,primary,true) then adapter.sync(player,primary,nil,false) end
            if secondary~=primary and I.isWeapon(secondary) and not service:reconcile(player,secondary,true) then adapter.sync(player,secondary,nil,false) end
        else sendEquipment(player) end
    end
    function Commands.equipmentInspect(_,_,player,args)
        if type(args) ~= "table" or type(args.requestId) ~= "string" or #args.requestId > 96
            or type(args.equipmentId) ~= "string" or type(args.itemId) ~= "string" then return end
        local key=I.value(player,"getUsername","")..":"..args.equipmentId..":"..args.itemId..":"..tostring(args.revision)
        local now=GodSystemScheduler.nowMs()
        if lastInspect[key] and now-lastInspect[key]<500 then return end
        if not lastInspect[key] then lastInspectOrder[#lastInspectOrder+1]=key end
        lastInspect[key]=now
        while #lastInspectOrder>256 do lastInspect[table.remove(lastInspectOrder,1)]=nil end
        local payload=service:inspect(args)
        sendServerCommand(player,MODULE,"equipmentProjection",payload)
        syncMetrics.messages=syncMetrics.messages+1
        syncMetrics.estimatedBytes=syncMetrics.estimatedBytes+estimate(payload)
    end
    function Commands.equipmentAction(_,_,player,args)
        if not guard(player) then return end
        local ok,result=pcall(service.action,service,player,args)
        unguard(player)
        if not ok then
            print("[GodSystem] equipment action exception: "..tostring(result))
            result={ok=false,code="EquipmentUnknown",operationId=args and args.opId,equipment=true}
        end
        sendEquipment(player)
        finishCode(player,result.ok,result.code,{},result)
    end
    function Commands.equipmentFreezeSwing(_,_,player,args)
        if not guard(player) then return end
        local weapon=I.value(player,"getPrimaryHandItem")
        freeze:swing(player,weapon,args)
        unguard(player)
    end
    local hello=Commands.hello
    Commands.hello=function(module,command,player,args)
        hello(module,command,player,args)
        service:account(player)
        sendEquipment(player)
        freeze:hello(player)
    end
end
