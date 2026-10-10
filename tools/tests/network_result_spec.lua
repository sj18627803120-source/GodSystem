local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
require=function() end
load("shared/GodSystem_Protocol.lua")
load("shared/GodSystem_RecycleFingerprint.lua")
load("shared/GodSystem_Diagnostics.lua")
local clock,received,sent=1000,{},{}
getTimestampMs=function() return clock end
isClient=function() return true end
GodSystemConfig={Version="42.21_3.21"}
GodSystemApp={services={runtime={}},getService=function() end}
local runtime=GodSystemApp.services.runtime
runtime.text=function(key,fallback) if key:find("NotifyMP_",1,true) then return key end return fallback end
runtime.notify=function(message) received[#received+1]=message end
Events=setmetatable({}, {__index=function(t,key)
    local callbacks={}
    local ev={Add=function(fn) callbacks[fn]=true end,Remove=function(fn) callbacks[fn]=nil end,
        fire=function(...) for fn in pairs(callbacks) do fn(...) end end}
    t[key]=ev;return ev
end})
getPlayer=function() return {getUsername=function() return "player" end} end
sendClientCommand=function(_,_,command,args) sent[#sent+1]={command=command,args=args} end
GodSystemMaintenance={}
load("client/GodSystem_Network.lua")
local N=GodSystemNetwork
local args={mode="recycle",itemIds={"1","2"}}
assert(N.send("recycle",args))
local first=assert(N.pendingOperationId)
clock=17000
N.getDiagnostics() -- Timeout does not claim success or cancellation.
eq(N.pendingOperationId,nil)
assert(received[#received]:find(first,1,true))
assert(N.send("recycle",args)); eq(N.pendingOperationId,first)
Events.OnServerCommand.fire("GodSystem","result",{ok=true,code="RecycleSelectionSuccess",operationId=first})
eq(N.pendingOperationId,nil)
assert(N.send("recycle",{mode="recycle",itemIds={"3"}}))
local second=assert(N.pendingOperationId); assert(second~=first)
Events.OnServerCommand.fire("GodSystem","result",{ok=true,code="RecycleSelectionSuccess",operationId=first})
eq(N.pendingOperationId,second) -- Late old result cannot clear the newer operation.
Events.OnServerCommand.fire("GodSystem","result",{ok=false,code="RecycleSourceReadFailed",operationId=second})
eq(N.pendingOperationId,nil); assert(received[#received]:find(second,1,true))
print("PASS network result: timeout uncertainty, same-op retry, late result isolation and operation reference")

-- A chunk response schedules refresh before the queue has been consumed.
-- Completion must schedule exactly one further refresh, even with no open shop.
local marks, refreshes = 0, 0
GodSystemScheduler = { nowMs = function() return clock end,
    due = function(key) return key == "client.mp.network.fast" end }
GodSystemShopCatalog = { invalidate = function(reason) assert(reason == "catalogReady"); marks = marks + 1 end }
GodSystemUI = { shopHiddenWindow = { getIsVisible = function() return true end,
    onServerStateChanged = function() refreshes = refreshes + 1 end } }
GodSystemShopListingStore = { ready = false, step = function(self) GodSystemShopListingStore.ready = true end }
N.onPlayerUpdate(nil)
Events.OnTick.fire()
eq(marks, 1); eq(refreshes, 1)
N.onPlayerUpdate(nil); Events.OnTick.fire()
eq(marks, 1); eq(refreshes, 1)
print("PASS network shop: atomic catalogue completion refreshes once without repeated polling")
GodSystemCarryCapacity = { resetClient = function() end }
runtime.itemConfigPresets = { order = { "1" }, active = "1" }
local presetReset = 0
GodSystemItemEconomyUI = { window = { applyPresets = function(_, value)
    if value == nil then presetReset = presetReset + 1
    else assert(value.active == "2") end
end } }
N.resetSessionRuntime()
assert(runtime.itemConfigPresets == nil and presetReset == 1,
    "reconnect clears old server selection and marks an open window unknown")
Events.OnServerCommand.fire("GodSystem", "itemConfigPresets", { order = { "2" }, active = "2" })
assert(runtime.itemConfigPresets.active == "2", "next server reply replaces the cleared preset state")
print("PASS network preset: reconnect invalidates cached selection and accepts next authoritative reply")

-- Exercise the real result dispatcher, not just the fallback's own handler.
local fallbackOp, starts, cancels, resets = nil, 0, 0, 0
GodSystemRecycleFallback = {
    handleResult = function(result)
        if result.operationId ~= fallbackOp then return false end
        fallbackOp = nil
        if result.ok == false and result.code == "RecycleDeleteRestored" and result.data.fallbackAllowed then
            starts = starts + 1
            return true
        end
        return false
    end,
    cancelPending = function() cancels = cancels + 1; fallbackOp = nil end,
    reset = function() resets = resets + 1; fallbackOp = nil end,
}
assert(N.send("recycle", {mode="recycle", itemIds={"4"}}))
fallbackOp = N.pendingOperationId
local third, notifications = fallbackOp, #received
Events.OnServerCommand.fire("GodSystem", "result", {ok=false,code="RecycleDeleteRestored",operationId="old",data={fallbackAllowed=true}})
eq(starts,0); eq(fallbackOp,third); eq(N.pendingOperationId,third)
notifications = #received
Events.OnServerCommand.fire("GodSystem", "result", {ok=false,code="RecycleDeleteRestored",operationId=third,data={fallbackAllowed=true}})
eq(starts,1); eq(N.pendingOperationId,nil); eq(#received,notifications)
Events.OnServerCommand.fire("GodSystem", "result", {ok=false,code="RecycleDeleteRestored",operationId=third,data={fallbackAllowed=true}})
eq(starts,1)
assert(N.send("recycle", {mode="recycle", itemIds={"5"}})); fallbackOp = N.pendingOperationId
clock = clock + 16000; N.getDiagnostics(); eq(fallbackOp,nil); assert(cancels>0)
N.resetSessionRuntime(); eq(resets,1)
print("PASS network fallback: matching restored result starts before cleanup, suppresses duplicate notice; timeout/session cancel")
