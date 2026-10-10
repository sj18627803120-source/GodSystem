require "GodSystem_B42JavaCalls"
require "GodSystem_InventoryIndex"
require "GodSystem_ExternalRecycle"
require "TimedActions/ISGrabItemAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWaitWhileGettingUp"
require "ISUI/ISWorldObjectContextMenu"

-- One temporary, client-side pickup job. Authority still validates the second
-- inventory recycle; a timeout/unknown receipt never authorizes this fallback.
GodSystemRecycleFallback = GodSystemRecycleFallback or {}
local F, Bridge = GodSystemRecycleFallback, GodSystemB42JavaCalls
local pending, job

local function now()
    return GodSystemScheduler.nowMs()
end

local function playerFor(payload)
    return getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
end

local function token(mode)
    return tostring(GodSystemRuntimeConfig.recyclePreparationToken(mode))
end

local function notify(key, fallback)
    local runtime = GodSystemApp.services.runtime
    runtime.notify(runtime.text(key, fallback))
end

function F.reset()
    pending, job = nil, nil
    if Events and Events.OnTick then Events.OnTick.Remove(F.onTick) end
end

function F.cancelPending()
    pending = nil
end

function F.isBusy()
    return job ~= nil
end

local function fail(reason)
    if GodSystemDiagnostics then GodSystemDiagnostics.issue("client", "RecycleSelectedItems", "pickupFallback", reason) end
    F.reset()
    notify("Notify_RecycleFallbackCancelled", "Backup pickup stopped. Nothing was recycled; check the ground and inventory.")
end

function F.capture(payload, sources)
    if payload.fallbackUsed or payload.mode == "listOnly" or not GodSystemExternalRecycle.canFallbackSources(sources) then return nil end
    local saved = { playerNum = payload.playerNum, mode = payload.mode, skippedCount = payload.skippedCount,
        allowDestroyContents = payload.allowDestroyContents, fallbackUsed = true, items = {}, ids = {}, types = {},
        sources = {}, containerContentSignatures = {}, token = token(payload.mode) }
    for i = 1, #payload.items do
        local item = payload.items[i]
        local ok, id, fullType = pcall(function() return item:getID(), item:getFullType() end)
        if not ok or id == nil or not fullType then return nil end
        saved.ids[i], saved.types[i] = tostring(id), fullType
    end
    for i = 1, #sources do
        local source = {}
        for key, value in pairs(sources[i]) do source[key] = value end
        saved.sources[source.itemId] = source
    end
    for key, value in pairs(payload.containerContentSignatures or {}) do saved.containerContentSignatures[key] = value end
    return saved
end

function F.offer(payload)
    if not payload or job then return false end
    local player = playerFor(payload)
    if not player or token(payload.mode) ~= payload.token then return false end
    job = { payload = payload, player = player, phase = "resolve", index = 1, deadline = now() + 5000 }
    notify("Notify_RecycleFallbackStarted", "Direct recycling failed; trying native pickup and one inventory recycle.")
    Events.OnTick.Add(F.onTick)
    return true
end

function F.track(operationId, payload)
    if operationId ~= nil and payload then pending = { opId = tostring(operationId), payload = payload } end
end

function F.handleResult(args)
    if not pending or not args then return false end
    local data = args.data or args.payload or {}
    local operationId = args.operationId or data.operationId or data.opId
    if operationId == nil or tostring(operationId) ~= pending.opId then return false end
    local payload = pending.payload
    pending = nil -- Receipt replay cannot enqueue the pickup a second time.
    if args.ok == false and args.code == "RecycleDeleteRestored" and data.fallbackAllowed == true then
        return F.offer(payload)
    end
    return false
end

function F.complete(current)
    if job ~= current then return end
    local payload = current.payload
    if playerFor(payload) ~= current.player or token(payload.mode) ~= payload.token then fail("sessionOrConfigChanged"); return end
    -- MP native completion can precede the inventory replication packet.
    current.phase, current.index, current.inventory = "inventoryWait", 1, nil
    current.deadline, current.nextDue = now() + 5000, 0
end

function F.onTick()
    local current = job
    if not current then return end
    local time = now()
    if time < (current.nextDue or 0) then return end
    local payload, player = current.payload, current.player
    if playerFor(payload) ~= player or Bridge.value(player, "isDead", true) ~= false
        or token(payload.mode) ~= payload.token then fail("sessionOrConfigChanged"); return end
    if current.phase == "queued" then
        current.nextDue = time + 250
        if time > current.queueDeadline then fail("pickupTimeout"); return end
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        for i = 1, #(queue and queue.queue or {}) do if queue.queue[i] == current.barrier then return end end
        fail("pickupInterrupted")
        return
    end
    local started, work = time, 0
    local cache = {} -- Discard native lookup indices at every frame boundary.
    if (current.phase == "resolve" or current.phase == "inventoryWait") and not current.inventory then
        current.inventory = GodSystemInventoryIndex.build(player:getInventory())
    end
    while job == current and work < 64 and now() - started < 2 do
        local i = current.index
        if i > #payload.ids then
            if current.phase == "inventoryWait" then
                F.reset()
                GodSystemRecycleContext.execute(payload) -- New MP op ID; inventory-only; never another fallback.
                return
            elseif current.phase == "resolve" then
                current.phase, current.index, current.inventory = "queue", 1, nil
            else
                local barrier = ISWaitWhileGettingUp:new(player)
                barrier:setOnComplete(F.complete, current)
                current.barrier, current.phase = barrier, "queued"
                current.queueDeadline = time + math.max(300000, #payload.ids * 30000)
                ISTimedActionQueue.add(barrier)
                return
            end
        else
            local item = payload.items[i]
            if current.phase == "inventoryWait" then
                item = GodSystemInventoryIndex.find(current.inventory, payload.ids[i])
                if not item then
                    if not (isClient and isClient()) or time >= current.deadline then fail("pickupIncomplete")
                    else current.inventory, current.nextDue = nil, time + 100 end
                    return
                end
                if Bridge.value(item, "getFullType", nil) ~= payload.types[i] then fail("pickupIdentityChanged"); return end
                payload.items[i] = item
            elseif current.phase == "resolve" then
                item = GodSystemInventoryIndex.find(current.inventory, payload.ids[i])
                if not item and payload.sources[payload.ids[i]] then
                    local row = GodSystemExternalRecycle.resolve(player, payload.sources[payload.ids[i]], cache)
                    item = row and row.item
                end
                if not item then
                    if time >= current.deadline then fail("restoredSourceUnavailable") else current.nextDue = time + 100 end
                    return
                end
                if Bridge.value(item, "getFullType", nil) ~= payload.types[i] then fail("restoredIdentityChanged"); return end
                payload.items[i] = item
            elseif not Bridge.value(item:getContainer(), "isInCharacterInventory", false, player)
                and item:getContainer() ~= player:getInventory() then
                local source = GodSystemExternalRecycle.describe(item)
                if not source or not GodSystemExternalRecycle.sameSource(source, payload.sources[payload.ids[i]] or {}) then fail("pickupSourceChanged"); return end
                local world = Bridge.value(item, "getWorldItem", nil)
                if not world then fail("pickupSourceChanged"); return end
                local duration = ISWorldObjectContextMenu.grabItemTime(player, world)
                ISTimedActionQueue.add(ISGrabItemAction:new(player, world, duration))
            end
            current.index, work = i + 1, work + 1
        end
    end
end

-- Protect the callback boundary; an engine exception cancels rather than
-- leaving a permanent worker or sending an uncertain recycle request.
local tick = F.onTick
F.onTick = function()
    local ok, err = pcall(tick)
    if not ok then
        if GodSystemDiagnostics then GodSystemDiagnostics.issue("client", "RecycleSelectedItems", "pickupFallback", "nativeFailure", nil, { error = err }) end
        fail("nativeFailure")
    end
end

local complete = F.complete
F.complete = function(current)
    local ok, err = pcall(complete, current)
    if not ok then
        if GodSystemDiagnostics then GodSystemDiagnostics.issue("client", "RecycleSelectedItems", "pickupFallback", "nativeFailure", nil, { error = err }) end
        fail("nativeFailure")
    end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(F.reset) end
    if Events.OnDisconnect then Events.OnDisconnect.Add(F.reset) end
end

return F
