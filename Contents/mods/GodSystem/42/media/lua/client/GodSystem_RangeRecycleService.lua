require "TimedActions/ISGodSystemRangeRecycleWarmupAction"
require "TimedActions/ISGodSystemRangeRecycleChannelAction"
require "TimedActions/ISTimedActionQueue"
require "GodSystem_RangeFilterProfile"

local service = GodSystemApp.getService("rangeRecycle") or GodSystemApp.createService("rangeRecycle")
local states = {}
local localJobs = {}
local notifiedOperations = {}
local sequence = 0
local syncQueues = {}
local syncSequence = 0
local SYNC_CHUNK_SIZE = 64
local SYNC_INTERVAL_MS = 50

local function playerFor(playerNum)
    if getSpecificPlayer then return getSpecificPlayer(math.floor(tonumber(playerNum) or 0)) end
    return getPlayer and getPlayer() or nil
end

local function isMultiplayer()
    return isClient and isClient() == true
end

local function keyFor(playerNum)
    return tostring(math.floor(tonumber(playerNum) or 0))
end

local function stateFor(playerNum)
    local key = keyFor(playerNum)
    states[key] = states[key] or {
        status = "idle",
        stage = "verifying",
        processed = 0,
        payout = 0,
        skipped = 0,
        cancelRequested = false,
        filter = GodSystemRangeFilter.normalize(nil),
        filterReady = false,
        filterLoaded = false,
        filterSyncing = false,
    }
    local state = states[key]
    if not state.filterLoaded then
        local loaded, loadOk = GodSystemRangeFilterProfile.load(playerFor(playerNum))
        if loadOk == true then
            state.filter = loaded
            state.filterLoaded = true
            state.filterReady = not isMultiplayer()
        end
    end
    state.enabled = GodSystemRuntimeConfig.isFeatureEnabled("EnableRecycle", true)
        and GodSystemRuntimeConfig.isFeatureEnabled("EnableRangeRecycle", true)
    state.radius = GodSystemRuntimeConfig.get("RangeRecycleRadius", 5)
    return state
end

function service:resetSession()
    if not isMultiplayer() then return false end
    states = {}
    notifiedOperations = {}
    localJobs = {}
    syncQueues = {}
    return true
end

local function publish(playerNum, topic)
    service:publish(playerNum, topic or "changed", stateFor(playerNum))
end

local function formatTemplate(template, args)
    local value = tostring(template or "")
    for index = 1, #(args or {}) do
        value = string.gsub(value, "{" .. tostring(index) .. "}", function()
            return tostring(args[index] or "")
        end)
    end
    return value
end

local function localizedText(key, fallback)
    local fullKey = "IGUI_GodSystem_" .. tostring(key or "")
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return value end
    end
    local runtime = GodSystemApp.services.runtime
    return runtime and runtime.text and runtime.text(key, fallback) or fallback
end

local terminalStatuses = { completed = true, cancelled = true, failed = true }
local terminalReasons = {
    cancelled = true,
    moved = true,
    running = true,
    combat = true,
    hurt = true,
    vehicle = true,
    dead = true,
    disconnected = true,
    playerChanged = true,
    serverError = true,
}

local function notifyTerminal(progress)
    local status = tostring(progress and progress.status or "")
    local operationId = tostring(progress and progress.operationId or "")
    if not terminalStatuses[status] or operationId == "" or notifiedOperations[operationId] then return end
    notifiedOperations[operationId] = true
    local processed = math.max(0, math.floor(tonumber(progress.processed) or 0))
    local payout = math.max(0, math.floor(tonumber(progress.payout) or 0))
    local message
    if status == "completed" then
        message = formatTemplate(localizedText("RangeRecycle_SummaryCompleted", "Range recycle completed: {1} items, {2} currency"), {
            processed, payout,
        })
    else
        local reason = tostring(progress.reason or "")
        if not terminalReasons[reason] then reason = "unknown" end
        local reasonLabel = localizedText("RangeRecycle_Reason_" .. reason, reason)
        message = formatTemplate(localizedText("RangeRecycle_SummaryInterrupted", "Range recycle interrupted: {1} items, {2} currency; reason: {3}"), {
            processed, payout, reasonLabel,
        })
    end
    local runtime = GodSystemApp.services.runtime
    if runtime and runtime.notify then runtime.notify(message) end
end

local function listSize(list)
    if not list then return 0 end
    if type(list) == "table" and type(list.size) ~= "function" then return #list end
    return math.max(0, math.floor(tonumber(GodSystemB42JavaCalls.value(list, "size", 0)) or 0))
end

local function listGet(list, index)
    if type(list) == "table" and type(list.get) ~= "function" then return list[index + 1] end
    return GodSystemB42JavaCalls.value(list, "get", nil, index)
end

local function contains(list, target)
    for index = 0, listSize(list) - 1 do
        if listGet(list, index) == target then return true end
    end
    return false
end

local function isType(value, className)
    if not value or not instanceof then return false end
    local ok, result = pcall(instanceof, value, className)
    return ok and result == true
end

local function itemContainer(item)
    local ok, container = GodSystemB42JavaCalls.try(item, "getInventory")
    return ok and container or nil
end

local function containerItems(container)
    return GodSystemB42JavaCalls.value(container, "getItems", nil)
end

local Hooks = {}
function Hooks:listSize(list) return listSize(list) end
function Hooks:listGet(list, index) return listGet(list, index) end
function Hooks:worldObjects(square) return GodSystemB42JavaCalls.value(square, "getWorldObjects", nil) end
function Hooks:objects(square) return GodSystemB42JavaCalls.value(square, "getObjects", nil) end
function Hooks:worldItem(object) return GodSystemB42JavaCalls.value(object, "getItem", nil) end
function Hooks:itemContainer(item) return itemContainer(item) end
function Hooks:containerItems(container) return containerItems(container) end
function Hooks:fullType(item) return tostring(GodSystemB42JavaCalls.value(item, "getFullType", "") or "") end
function Hooks:isVehicle(object) return isType(object, "BaseVehicle") end
function Hooks:objectContainers(object)
    local result = {}
    if not object or isType(object, "IsoWorldInventoryObject") or isType(object, "IsoDeadBody")
        or isType(object, "BaseVehicle") then return result end
    local count = math.max(0, math.floor(tonumber(GodSystemB42JavaCalls.value(object, "getContainerCount", 0)) or 0))
    for index = 0, count - 1 do
        local container = GodSystemB42JavaCalls.value(object, "getContainerByIndex", nil, index)
        if container then result[#result + 1] = container end
    end
    if #result == 0 then
        local container = GodSystemB42JavaCalls.value(object, "getContainer", nil)
        if container then result[1] = container end
    end
    return result
end
function Hooks:corpses(square)
    local result = {}
    local moving = GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil)
    for index = 0, listSize(moving) - 1 do
        local object = listGet(moving, index)
        if isType(object, "IsoDeadBody") then result[#result + 1] = object end
    end
    return result
end
function Hooks:corpseContainer(corpse) return GodSystemB42JavaCalls.value(corpse, "getContainer", nil) end

local Adapter = {}
Adapter.__index = Adapter

local function numberValue(object, method, fallback)
    return tonumber(GodSystemB42JavaCalls.value(object, method, fallback)) or fallback
end

local function flag(object, method)
    return GodSystemB42JavaCalls.value(object, method, false) == true
end

function Adapter.new(player)
    return setmetatable({
        player = player,
        startX = numberValue(player, "getX", 0),
        startY = numberValue(player, "getY", 0),
        startZ = numberValue(player, "getZ", 0),
        startHealth = numberValue(player, "getHealth", 100),
        playerNum = numberValue(player, "getPlayerNum", 0),
        scanner = GodSystemRangeRecycleScanner.new(Hooks),
    }, Adapter)
end

function Adapter:getSquare(coord)
    local cell = getCell and getCell() or nil
    return cell and GodSystemB42JavaCalls.value(cell, "getGridSquare", nil, coord.x, coord.y, coord.z) or nil
end

function Adapter:canAccessSquare(_, square)
    if not SafeHouse or not SafeHouse.isPlayerAllowedOnSquare then return false end
    local ok, allowed = pcall(function() return SafeHouse.isPlayerAllowedOnSquare(self.player, square) end)
    return ok and allowed == true
end

function Adapter:isInterrupted()
    local player = self.player
    if not player then return "disconnected" end
    if flag(player, "isDead") then return "dead" end
    if numberValue(player, "getHealth", self.startHealth) < self.startHealth then return "hurt" end
    if GodSystemB42JavaCalls.value(player, "getVehicle", nil) then return "vehicle" end
    if flag(player, "isAiming") or flag(player, "isAttacking") then return "combat" end
    if flag(player, "isRunning") or flag(player, "isSprinting") then return "running" end
    if flag(player, "isPlayerMoving") then return "moved" end
    if numberValue(player, "getPlayerNum", self.playerNum) ~= self.playerNum then return "playerChanged" end
    if math.abs(numberValue(player, "getX", self.startX) - self.startX) > 0.01
        or math.abs(numberValue(player, "getY", self.startY) - self.startY) > 0.01
        or math.abs(numberValue(player, "getZ", self.startZ) - self.startZ) > 0.01 then return "moved" end
    return nil
end

function Adapter:nextCandidate(_, stage, square, cursor)
    return self.scanner:nextCandidate(stage, square, cursor)
end

function Adapter:afterCandidate(_, candidate, outcome)
    self.scanner:afterCandidate(candidate, outcome and outcome.removed == true)
end

local function containerContains(container, item)
    return contains(containerItems(container), item)
end

function Adapter:recycle(_, candidate, stage, square)
    local removed = false
    if candidate.kind == "containerItem" then
        local nested = itemContainer(candidate.item)
        if (not nested or listSize(containerItems(nested)) == 0) and containerContains(candidate.container, candidate.item) then
            local ok = GodSystemB42JavaCalls.try(candidate.container, "Remove", candidate.item)
            removed = ok and not containerContains(candidate.container, candidate.item)
        end
    elseif candidate.kind == "worldItem" then
        local nested = itemContainer(candidate.item)
        local worldObjects = GodSystemB42JavaCalls.value(square, "getWorldObjects", nil)
        if (not candidate.portableShell or not nested or listSize(containerItems(nested)) == 0)
            and contains(worldObjects, candidate.worldObject)
            and GodSystemB42JavaCalls.value(candidate.worldObject, "getItem", nil) == candidate.item then
            local ok = GodSystemB42JavaCalls.try(square, "transmitRemoveItemFromSquare", candidate.worldObject)
            removed = ok and not contains(GodSystemB42JavaCalls.value(square, "getWorldObjects", nil), candidate.worldObject)
        end
    elseif candidate.kind == "corpse" then
        local container = GodSystemB42JavaCalls.value(candidate.corpse, "getContainer", nil)
        local moving = GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil)
        if (not container or listSize(containerItems(container)) == 0) and contains(moving, candidate.corpse) then
            local ok = GodSystemB42JavaCalls.try(square, "removeCorpse", candidate.corpse, false)
            removed = ok and not contains(GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil), candidate.corpse)
        end
    end
    if not removed then return { removed = false, payout = 0 } end
    if stage == "corpses" then return { removed = true, payout = 1 } end
    local quote = GodSystemEconomyPolicy.quote(candidate.fullType, candidate.item, { kind = "recycle" })
    return { removed = true, payout = math.max(0, math.floor(tonumber(quote and quote.recycleValue) or 0)) }
end

local function updateState(playerNum, progress)
    local state = stateFor(playerNum)
    for key, value in pairs(progress or {}) do state[key] = value end
    publish(playerNum, "progress")
end

local function publishFilter(playerNum, topic)
    publish(playerNum, topic or "filter")
end

function service:syncProfile(playerNum)
    if not isMultiplayer() then return false end
    local state = stateFor(playerNum)
    local player = playerFor(playerNum)
    local loaded, loadOk = GodSystemRangeFilterProfile.load(player)
    if loadOk ~= true then return false end
    state.filter = loaded
    state.filterLoaded = true
    state.filterReady = false
    state.filterSyncing = true
    syncSequence = syncSequence + 1
    local syncId = "range-filter-" .. tostring(GodSystemScheduler.nowMs()) .. "-" .. tostring(syncSequence)
    state.filterSyncId = syncId
    syncQueues[keyFor(playerNum)] = {
        playerNum = playerNum,
        syncId = syncId,
        mode = state.filter.mode,
        fullTypes = state.filter.activeFullTypes,
        phase = "begin",
        nextIndex = 1,
        nextAtMs = 0,
        retries = 0,
    }
    publishFilter(playerNum, "filterSyncQueued")
    return true
end

local function sendSyncStep(record, nowMs)
    if nowMs < (record.nextAtMs or 0) then return end
    if not GodSystemNetwork or not GodSystemNetwork.send then return end
    local sent = false
    if record.phase == "begin" then
        sent = GodSystemNetwork.send("rangeFilterSyncBegin", {
            syncId = record.syncId,
            total = #record.fullTypes,
            mode = record.mode,
        })
        if sent then record.phase = "chunks" end
    elseif record.phase == "chunks" then
        if record.nextIndex > #record.fullTypes then
            record.phase = "commit"
        else
            local chunk = {}
            local last = math.min(#record.fullTypes, record.nextIndex + SYNC_CHUNK_SIZE - 1)
            for index = record.nextIndex, last do chunk[#chunk + 1] = record.fullTypes[index] end
            sent = GodSystemNetwork.send("rangeFilterSyncChunk", {
                syncId = record.syncId,
                offset = record.nextIndex,
                fullTypes = chunk,
            })
            if sent then record.nextIndex = last + 1 end
        end
    elseif record.phase == "commit" then
        sent = GodSystemNetwork.send("rangeFilterSyncCommit", { syncId = record.syncId })
        if sent then
            syncQueues[keyFor(record.playerNum)] = nil
            return
        end
    end
    record.nextAtMs = nowMs + SYNC_INTERVAL_MS
end

local function finishLocal(record, progress)
    localJobs[record.key] = nil
    progress.operationId = record.job.id
    updateState(record.playerNum, progress)
    notifyTerminal(progress)
    GodSystemApp.services.runtime.save()
end

local function settleLocal(record, progress)
    local raw = math.max(0, math.floor(tonumber(progress.batchPayout) or 0))
    local payout = GodSystemApp.services.runtime.applyRecycleDailyPayout(raw)
    record.job.payout = math.max(0, record.job.payout - raw + payout)
    progress.batchPayout = payout
    progress.payout = record.job.payout
    local data = GodSystemApp.services.runtime.getData()
    local delivery = GodSystemRecyclePayout.deliver(payout, function(value)
        return GodSystemApp.services.runtime.giveCurrency(value)
    end, function(value)
        local bank = GodSystemApp.services.runtime.getBank()
        bank.current = math.max(0, math.floor(tonumber(bank.current) or 0)) + value
        return true
    end)
    progress.bankFallback = delivery.bankFallback
    if not delivery.ok then progress.payoutDeliveryFailed = true end
    if (progress.batchProcessed or 0) > 0 then
        data.stats.recycledItems = (data.stats.recycledItems or 0) + progress.batchProcessed
        data.stats.recycledPoints = (data.stats.recycledPoints or 0) + payout
    end
    return progress
end

local function tickLocal()
    local nowMs = GodSystemScheduler.nowMs()
    if isMultiplayer() then
        local syncRecords = {}
        for _, record in pairs(syncQueues) do syncRecords[#syncRecords + 1] = record end
        for index = 1, #syncRecords do sendSyncStep(syncRecords[index], nowMs) end
    end
    local records = {}
    for _, record in pairs(localJobs) do records[#records + 1] = record end
    for index = 1, #records do
        local record = records[index]
        if localJobs[record.key] == record then
            local interrupted = record.job.adapter:isInterrupted()
            if interrupted then
                finishLocal(record, GodSystemRangeRecycleDomain.cancel(record.job, interrupted))
            elseif nowMs >= record.warmupUntilMs and nowMs >= record.nextBatchMs then
                local interval = math.max(0.10, math.min(2.00, tonumber(GodSystemRuntimeConfig.get("RangeRecycleBatchIntervalSeconds", 0.25)) or 0.25))
                record.nextBatchMs = nowMs + math.floor(interval * 1000)
                local progress = settleLocal(record, GodSystemRangeRecycleDomain.step(record.job))
                if progress.status == "running" then updateState(record.playerNum, progress) else finishLocal(record, progress) end
            end
        end
    end
end

local function result(ok, code, args, data, operationId)
    return { ok = ok == true, code = code, args = args or {}, data = data or {}, operationId = operationId }
end

local function timedActionBusy(player)
    if GodSystemNetwork and GodSystemNetwork.isTimedActionBusy then
        local busy = GodSystemNetwork.isTimedActionBusy(player)
        return busy == true
    end
    local queue = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue
        and ISTimedActionQueue.getTimedActionQueue(player) or nil
    return queue and queue.queue and queue.queue[1] ~= nil
end

local function queueRangeActions(player, operationId)
    if not player or not ISTimedActionQueue or not ISGodSystemRangeRecycleWarmupAction
        or not ISGodSystemRangeRecycleChannelAction then return false end
    ISTimedActionQueue.add(ISGodSystemRangeRecycleWarmupAction:new(player, operationId))
    ISTimedActionQueue.add(ISGodSystemRangeRecycleChannelAction:new(player, operationId))
    return true
end

local function startLocal(playerNum, callback)
    local key = keyFor(playerNum)
    if localJobs[key] then
        local value = result(false, "RangeRecycleAlreadyRunning")
        if callback then callback(value) end
        return nil
    end
    local player = playerFor(playerNum)
    if not player then
        local value = result(false, "RangeRecyclePlayerMissing")
        if callback then callback(value) end
        return nil
    end
    local adapter = Adapter.new(player)
    if adapter:isInterrupted() then
        local value = result(false, "RangeRecycleStartInvalid")
        if callback then callback(value) end
        return nil
    end
    sequence = sequence + 1
    local operationId = "range-sp-" .. tostring(GodSystemScheduler.nowMs()) .. "-" .. tostring(sequence)
    local filterState = stateFor(playerNum).filter
    local compiledFilter = GodSystemRangeFilter.compile(filterState)
    if not GodSystemRangeFilter.canStart(compiledFilter) then
        local value = result(false, "RangeRecycleNoAllowedItems")
        if callback then callback(value) end
        return nil
    end
    local job = GodSystemRangeRecycleDomain.newJob({
        id = operationId,
        playerId = key,
        origin = { x = adapter.startX, y = adapter.startY, z = adapter.startZ },
        radius = GodSystemRuntimeConfig.get("RangeRecycleRadius", 5),
        batchSize = 20,
        scanBudget = 256,
        filter = compiledFilter,
        adapter = adapter,
    })
    local nowMs = GodSystemScheduler.nowMs()
    localJobs[key] = { key = key, playerNum = playerNum, job = job, warmupUntilMs = nowMs + 1000, nextBatchMs = nowMs + 1000 }
    updateState(playerNum, {
        status = "running", stage = "verifying", processed = 0, payout = 0, skipped = 0,
        operationId = operationId, warmupSeconds = 1, cancelRequested = false,
    })
    local value = result(true, "RangeRecycleStarted", { job.radius }, { radius = job.radius }, operationId)
    if callback then callback(value) end
    return operationId
end

service:setViewModelProvider(function(playerNum)
    return stateFor(playerNum)
end)

function service:requestCancel(playerNum, operationId, callback)
    local state = stateFor(playerNum)
    if state.status ~= "running" or state.cancelRequested == true
        or tostring(state.operationId or "") ~= tostring(operationId or state.operationId or "") then
        if callback then callback(result(false, "RangeRecycleNotRunning")) end
        return nil
    end
    state.cancelRequested = true
    publish(playerNum, "cancelRequested")
    if isMultiplayer() then
        local sent = GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("rangeRecycleCancel", {})
        if callback then callback(result(sent == true, sent and "RangeRecycleCancelQueued" or "RangeRecycleSendFailed")) end
        return sent and tostring(state.operationId or "cancel") or nil
    end
    local record = localJobs[keyFor(playerNum)]
    if not record then
        if callback then callback(result(false, "RangeRecycleNotRunning")) end
        return nil
    end
    finishLocal(record, GodSystemRangeRecycleDomain.cancel(record.job, "cancelled"))
    if callback then callback(result(true, "RangeRecycleCancelled", nil, nil, record.job.id)) end
    return record.job.id
end

service:setExecutor(function(playerNum, intent, payload, callback)
    intent = tostring(intent or "")
    payload = type(payload) == "table" and payload or {}
    if intent == "start" then
        if not stateFor(playerNum).enabled then
            local value = result(false, "RangeRecycleDisabled")
            if callback then callback(value) end
            return nil
        end
        local currentState = stateFor(playerNum)
        if isMultiplayer() and currentState.filterReady ~= true then
            service:syncProfile(playerNum)
            local value = result(false, "RangeFilterSyncRequired")
            if callback then callback(value) end
            return nil
        end
        local currentFilter = GodSystemRangeFilter.compile(currentState.filter)
        if not GodSystemRangeFilter.canStart(currentFilter) then
            local value = result(false, "RangeRecycleNoAllowedItems")
            if callback then callback(value) end
            return nil
        end
        if isMultiplayer() and (currentState.pendingOperationId ~= nil or currentState.status == "running") then
            local value = result(false, "RangeRecycleAlreadyRunning")
            if callback then callback(value) end
            return nil
        end
        local player = playerFor(playerNum)
        if timedActionBusy(player) then
            local value = result(false, "RangeRecycleTimedActionBusy")
            if callback then callback(value) end
            return nil
        end
        if not isMultiplayer() then
            local operationId = startLocal(playerNum, callback)
            if operationId then queueRangeActions(player, operationId) end
            return operationId
        end
        sequence = sequence + 1
        local operationId = "range-mp-" .. tostring(GodSystemScheduler.nowMs()) .. "-" .. tostring(sequence)
        local sent = GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("rangeRecycleStart", { operationId = operationId })
        if sent then
            local state = stateFor(playerNum)
            state.pendingOperationId = operationId
            state.cancelRequested = false
            publish(playerNum, "startPending")
        end
        local value = result(sent == true, sent and "RangeRecycleQueued" or "RangeRecycleSendFailed", nil, nil, operationId)
        if callback then callback(value) end
        return sent and operationId or nil
    elseif intent == "cancel" then
        return service:requestCancel(playerNum, stateFor(playerNum).operationId, callback)
    elseif intent == "filterGet" then
        if isMultiplayer() then service:syncProfile(playerNum) end
        if callback then callback(result(true, "RangeFilterRequested", nil, { snapshot = stateFor(playerNum).filter })) end
        return "filter"
    elseif intent == "filterDelta" then
        local state = stateFor(playerNum)
        local changed = GodSystemRangeFilter.applyDelta(state.filter, payload)
        if changed.ok and changed.code == "RangeFilterUpdated" then
            local saved = GodSystemRangeFilterProfile.save(playerFor(playerNum), changed.state)
            if not saved then
                local value = result(false, "RangeFilterSaveFailed", nil, { snapshot = state.filter })
                if callback then callback(value) end
                return nil
            end
            state.filter = changed.state
        elseif changed.ok then
            state.filter = changed.state
        end
        publishFilter(playerNum, "filter")
        if isMultiplayer() and changed.ok and changed.code == "RangeFilterUpdated" then
            local count = #(payload.fullTypes or {})
            if count > SYNC_CHUNK_SIZE or state.filterReady ~= true then
                service:syncProfile(playerNum)
            else
                local sent = GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("rangeFilterDelta", payload)
                if not sent and callback then callback(result(false, "RangeRecycleSendFailed")) end
            end
        end
        local value = result(changed.ok, changed.code, nil, { snapshot = changed.state })
        if callback then callback(value) end
        return changed.ok and "filter" or nil
    elseif intent == "filterMode" then
        local state = stateFor(playerNum)
        local changed = GodSystemRangeFilter.applyDelta(state.filter, {
            baseRevision = state.filter.revision,
            op = "setMode",
            mode = payload.mode,
        })
        if changed.ok then
            if changed.code == "RangeFilterModeChanged" then
                local saved = GodSystemRangeFilterProfile.save(playerFor(playerNum), changed.state)
                if not saved then
                    local value = result(false, "RangeFilterSaveFailed", nil, { snapshot = state.filter })
                    if callback then callback(value) end
                    return nil
                end
            end
            state.filter = changed.state
            publishFilter(playerNum, "filterMode")
            if isMultiplayer() then
                if state.filterReady == true then
                    local sent = GodSystemNetwork and GodSystemNetwork.send and GodSystemNetwork.send("rangeFilterDelta", {
                        baseRevision = changed.state.revision - 1,
                        op = "setMode",
                        mode = changed.state.mode,
                    })
                    if not sent then service:syncProfile(playerNum) end
                else
                    service:syncProfile(playerNum)
                end
            end
        end
        local value = result(changed.ok, changed.code, nil, { snapshot = changed.state })
        if callback then callback(value) end
        return changed.ok and "filter" or nil
    elseif intent == "filterReplace" then
        local state = stateFor(playerNum)
        local requested = type(payload.state) == "table" and payload.state or nil
        local rawValues = requested and (requested.activeFullTypes or requested.allowedFullTypes) or nil
        local values = GodSystemRangeFilter.cleanBatch(rawValues, GodSystemRangeFilter.MAX_ACTIVE_ITEMS)
        if not values then
            local value = result(false, "RangeFilterTooManyItems")
            if callback then callback(value) end
            return nil
        end
        local nextState = GodSystemRangeFilter.normalize({ mode = requested.mode, activeFullTypes = values })
        nextState.revision = math.max(state.filter.revision + 1, nextState.revision)
        local saved = GodSystemRangeFilterProfile.save(playerFor(playerNum), nextState)
        if not saved then
            local value = result(false, "RangeFilterSaveFailed", nil, { snapshot = state.filter })
            if callback then callback(value) end
            return nil
        end
        state.filter = nextState
        publishFilter(playerNum, "filter")
        if isMultiplayer() then service:syncProfile(playerNum) end
        local value = result(true, "RangeFilterUpdated", nil, { snapshot = nextState })
        if callback then callback(value) end
        return "filter"
    end
    if callback then callback(result(false, "ServiceIntentUnsupported")) end
    return nil
end)

function service:handleProgress(progress)
    local playerNum = playerFor(0) and numberValue(playerFor(0), "getPlayerNum", 0) or 0
    progress = type(progress) == "table" and progress or {}
    local state = stateFor(playerNum)
    local status = tostring(progress.status or "")
    local operationId = tostring(progress.operationId or "")
    local pendingOperationId = tostring(state.pendingOperationId or "")
    if pendingOperationId ~= "" and pendingOperationId ~= operationId then return end
    if status == "running" then
        local currentOperationId = tostring(state.operationId or "")
        if (pendingOperationId ~= "" and pendingOperationId ~= operationId)
            or (pendingOperationId == "" and state.status == "running"
                and currentOperationId ~= "" and currentOperationId ~= operationId) then return end
        local pendingMatches = operationId ~= "" and pendingOperationId == operationId
        progress.cancelRequested = false
        updateState(playerNum, progress)
        state.pendingOperationId = nil
        if pendingMatches and tostring(state.queuedOperationId or "") ~= operationId then
            if queueRangeActions(playerFor(playerNum), operationId) then state.queuedOperationId = operationId end
        end
        return
    end
    if terminalStatuses[status] and state.status == "running"
        and tostring(state.operationId or "") ~= "" and tostring(state.operationId or "") ~= operationId then
        return
    end
    updateState(playerNum, progress)
    if terminalStatuses[status] then
        state.pendingOperationId = nil
        notifyTerminal(progress)
    end
end

function service:handleFilter(snapshot, ready)
    return service:handleFilterAck(snapshot, ready, nil)
end

function service:handleFilterAck(snapshot, ready, syncId)
    local playerNum = playerFor(0) and numberValue(playerFor(0), "getPlayerNum", 0) or 0
    local state = stateFor(playerNum)
    local queue = syncQueues[keyFor(playerNum)]
    if syncId and tostring(state.filterSyncId or "") ~= tostring(syncId) then return end
    if queue and not syncId and ready == true then return end
    if ready ~= true then
        state.filterReady = false
        state.filterSyncing = true
        publishFilter(playerNum, "filterSyncing")
        return
    end
    state.filter = GodSystemRangeFilter.normalize(snapshot)
    state.filterReady = true
    state.filterSyncing = false
    if not queue or not syncId or queue.syncId == syncId then
        syncQueues[keyFor(playerNum)] = nil
        state.filterSyncId = nil
        GodSystemRangeFilterProfile.save(playerFor(playerNum), state.filter)
    end
    publishFilter(playerNum, "filter")
end

function service:handleResult(payload)
    payload = type(payload) == "table" and payload or {}
    local code = tostring(payload.code or "")
    if code:find("^RangeRecycle") and payload.ok ~= true then
        local playerNum = playerFor(0) and numberValue(playerFor(0), "getPlayerNum", 0) or 0
        stateFor(playerNum).pendingOperationId = nil
    end
    if code == "RangeFilterSyncRequired" or code == "RangeFilterSyncInvalid" then
        local playerNum = playerFor(0) and numberValue(playerFor(0), "getPlayerNum", 0) or 0
        service:syncProfile(playerNum)
    end
    return payload.ok == true and code == "RangeRecycleCancelled"
end

Events.OnTick.Add(tickLocal)

return service
