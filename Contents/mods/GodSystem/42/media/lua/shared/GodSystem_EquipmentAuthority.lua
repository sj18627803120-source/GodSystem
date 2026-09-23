require "GodSystem_EquipmentService"
require "GodSystem_EquipmentLifecycle"
require "GodSystem_RuntimeConfig"
require "GodSystem_EconomyPolicy"
require "GodSystem_ShopVariants"

GodSystemEquipmentAuthority = GodSystemEquipmentAuthority or {}
local A, E, I = GodSystemEquipmentAuthority, GodSystemEquipment, GodSystemEquipmentItems

function A.defaults(multiplayer)
    return {
        authority = true, multiplayer = multiplayer,
        store = function()
            if not ModData or not ModData.getOrCreate then return nil end
            return ModData.getOrCreate(multiplayer and "GodSystem_Equipment_MP_v1" or "GodSystem_Equipment_SP_v1")
        end,
        config = function() return GodSystemRuntimeConfig.readSandbox() end,
        uuid = function() return getRandomUUID() end,
        owner = function(player) return I.value(player,"getUsername") end,
        exists = function(fullType)
            local manager=getScriptManager and getScriptManager()
            return manager and manager:FindItem(fullType) ~= nil or false
        end,
        price = function(fullType)
            local quote = GodSystemEconomyPolicy.quote(fullType,nil,{kind="shop"})
            return quote and quote.finalBuy
        end,
        random = function(limit) return ZombRand(limit) end,
        create = function(fullType) return GodSystemShopVariants.createItem(fullType,nil) end,
        add = function(player,item)
            local inventory=I.value(player,"getInventory")
            if not inventory or not I.call(inventory,"AddItem",item) or not I.owned(player,item) then return false end
            if multiplayer and sendAddItemToContainer then sendAddItemToContainer(inventory,item) end
            I.call(inventory,"setDrawDirty",true)
            return true
        end,
        remove = function(player,item)
            local container=I.value(item,"getContainer")
            if not container then return true end
            if not I.owned(player,item) then return false end
            if not I.call(container,"Remove",item) then return false end
            local list=I.value(container,"getItems")
            if not list or I.value(list,"contains",true,item) then return false end
            if multiplayer and sendRemoveItemFromContainer then sendRemoveItemFromContainer(container,item) end
            return true
        end,
    }
end

function A.install(service,key)
    local function flush(player)
        for _,item in pairs(service.known) do
            if not player or I.owned(player,item) then
                service:observe(item)
                local root=service.loadedRoot; local record=root and service:recordFor(item,root)
                if record and I.matches(item,root,record) then I.mark(item,root,record) end
            end
        end
    end
    local function forget(player)
        local cached=service.players[player]
        local owner=cached and cached.account.ownerKey
        for id,item in pairs(service.known) do
            local record=service.loadedRoot and service:recordFor(item,service.loadedRoot)
            if (record and record.ownerKey==owner) or I.owned(player,item) then service:forgetRecord(id) end
        end
        service.players[player]=nil
    end
    local function periodic()
        local active={}
        if service.adapter.multiplayer then
            local online=getOnlinePlayers and getOnlinePlayers()
            if online then for n=0,online:size()-1 do local p=online:get(n); if p then active[p]=true end end end
        elseif getNumActivePlayers and getSpecificPlayer then
            for n=0,getNumActivePlayers()-1 do local p=getSpecificPlayer(n); if p then active[p]=true end end
        end
        for player in pairs(service.players) do
            if not active[player] then flush(player); forget(player) end
        end
        for player in pairs(active) do
            if not I.value(player,"isDead",true) then
                service:account(player)
                local primary,secondary=I.value(player,"getPrimaryHandItem"),I.value(player,"getSecondaryHandItem")
                service:reconcile(player,primary,false)
                if secondary ~= primary then service:reconcile(player,secondary,false) end
            end
        end
        for id,item in pairs(service.known) do
            local holder
            for player in pairs(active) do if I.owned(player,item) then holder=player; break end end
            if holder then service:reconcile(holder,item,false)
            else service:forgetRecord(id) end
        end
        flush()
    end
    service.lifecycle=GodSystemEquipmentLifecycle.install(key,{
        item=function(player,item,force) return service:reconcile(player,item,force) end,
        player=function(player) service:account(player) end,
        periodic=periodic, start=periodic, flush=flush,
        observe=function(item) service:observe(item) end,
        beforeCraft=flush,
        afterCraft=function(player)
            for id,item in pairs(service.known) do
                if I.owned(player,item) then service:reconcile(player,item,true)
                elseif not I.value(item,"getContainer") and not I.value(item,"getWorldItem") then service:forgetRecord(id) end
            end
            flush(player)
        end,
        leave=forget,
        reset=function() service.known={}; service.knownIds={}; service.players={}; service.loadedRoot=nil end,
    })
    return service
end
return A
