require "GodSystem_EquipmentItems"
require "GodSystem_Scheduler"
require "TimedActions/ISUpgradeWeapon"
require "TimedActions/ISRemoveWeaponUpgrade"
require "TimedActions/ISFixAction"
require "TimedActions/ISCraftAction"
require "Entity/TimedActions/ISHandcraftAction"

GodSystemEquipmentLifecycle = GodSystemEquipmentLifecycle or {}
local L, I = GodSystemEquipmentLifecycle, GodSystemEquipmentItems

-- No resident OnTick/OnPlayerUpdate hook. All callbacks touch only known or hand-held weapons.
function L.install(key, hooks)
    L.instances = L.instances or {}
    if L.instances[key] then return L.instances[key] end
    local state = { hands = {}, swingAt = {}, dirty = false, lastMs = 0, hooks = hooks }
    L.instances[key] = state
    state.track=function(player)
        if player then state.hands[player]={I.value(player,"getPrimaryHandItem"),I.value(player,"getSecondaryHandItem")} end
    end
    local function event(name, callback)
        if Events and Events[name] then Events[name].Add(callback) end
    end
    local function hands(player)
        if not player then return end
        local old = state.hands[player] or {}
        local primary, secondary = I.value(player, "getPrimaryHandItem"), I.value(player, "getSecondaryHandItem")
        state.hands[player] = { primary, secondary }
        for _, item in pairs(old) do if item ~= primary and item ~= secondary then hooks.item(player,item,true) end end
        if primary then hooks.item(player,primary,true) end
        if secondary and secondary ~= primary then hooks.item(player,secondary,true) end
    end
    event("OnEquipPrimary", hands)
    event("OnEquipSecondary", hands)
    event("OnCreatePlayer", function(_,player) if hooks.player then hooks.player(player) end; hands(player) end)
    -- B42 can emit different combat callbacks for an empty swing, a hit and
    -- the end of an attack.  Route all of them through one short debounce so
    -- a valid melee swing never depends on one callback variant, while a
    -- multi-target hit still creates exactly one special-effect pulse.
    local function swing(player,weapon)
        if not player then return end
        state.track(player)
        weapon = weapon or I.value(player,"getPrimaryHandItem")
        hooks.item(player,weapon,false)
        if not hooks.swing then return end
        local now=GodSystemScheduler.nowMs()
        local old=state.swingAt[player]
        if old and now>=old and now-old<250 then return end
        state.swingAt[player]=now
        hooks.swing(player,weapon)
    end
    event("OnWeaponSwing", swing)
    event("OnWeaponSwingHitPoint", swing)
    event("OnPlayerAttackFinished", swing)
    event("OnContainerUpdate", function() state.dirty = true end)
    event("EveryOneMinute", function()
        local now = GodSystemScheduler.nowMs()
        if now >= state.lastMs and now-state.lastMs < 10000 then return end
        state.lastMs = now
        if hooks.periodic then hooks.periodic(state.dirty) end
        state.dirty = false
    end)
    event("OnSave", function() if hooks.flush then hooks.flush() end end)
    event("OnPlayerDeath", function(player)
        if hooks.flush then hooks.flush(player) end
        hands(player)
        state.hands[player], state.swingAt[player] = nil, nil
        if hooks.leave then hooks.leave(player) end
    end)
    local function reset()
        if hooks.flush then hooks.flush() end
        state.hands, state.swingAt, state.lastMs = {}, {}, 0
        if hooks.reset then hooks.reset() end
    end
    event("OnDisconnect", reset)
    event("OnMainMenuEnter", reset)
    event("OnGameStart", function() if hooks.start then hooks.start() end end)
    return state
end

-- Preserve vanilla actions and their return values. Strip only our multiplier around native part arithmetic.
local function wrap(class, field, parts)
    if not class or class.__GodSystemEquipmentWrapped or not class.complete then return end
    class.__GodSystemEquipmentWrapped = true
    local original = class.complete
    class.complete = function(action,...)
        local item, player = action[field], action.character
        local marked = I.isWeapon(item) and I.marker(item)
        if marked and parts then
            for _,state in pairs(L.instances or {}) do if state.hooks.beforeParts then state.hooks.beforeParts(player,item) end end
        end
        local results = { pcall(original,action,...) }
        if marked then
            for _,state in pairs(L.instances or {}) do
                state.hooks.item(player,item,true)
                if state.hooks.observe then state.hooks.observe(item) end
            end
        end
        if not results[1] then error(results[2]) end
        return unpack(results,2)
    end
end
wrap(ISUpgradeWeapon,"weapon",true)
wrap(ISRemoveWeaponUpgrade,"weapon",true)
wrap(ISFixAction,"item",false)
local function wrapCraft(class,method)
    if not class or class.__GodSystemEquipmentCraftWrapped or not class[method] then return end
    class.__GodSystemEquipmentCraftWrapped=true
    local original=class[method]
    class[method]=function(action,...)
        for _,state in pairs(L.instances or {}) do if state.hooks.beforeCraft then state.hooks.beforeCraft(action.character) end end
        local result={pcall(original,action,...)}
        for _,state in pairs(L.instances or {}) do if state.hooks.afterCraft then state.hooks.afterCraft(action.character) end end
        if not result[1] then error(result[2]) end
        return unpack(result,2)
    end
end
-- B42 sharpening is a recipe operation, not a generic OnItemFound/pickup event.
wrapCraft(ISCraftAction,"complete")
wrapCraft(ISHandcraftAction,"performRecipe")
return L
