_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRangeRecycle"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRangeRecycle then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRangeRecycle = true
    setfenv(1, runtimeEnvironment)

GodSystemServerRangeRecycle = GodSystemServerRangeRecycle or {}
local Range = GodSystemServerRangeRecycle
Range.jobs = Range.jobs or {}
Range.filterCache = Range.filterCache or {}
Range.filterStaging = Range.filterStaging or {}
local FILTER_SYNC_CHUNK_SIZE = 64
local FILTER_SYNC_MAX_ITEMS = 20000
local GLOBAL_TARGET_BUDGET = 20
local GLOBAL_SCAN_BUDGET = 256
Range.globalBudget = Range.globalBudget or { nextAtMs = 0, targets = 0, scans = 0 }
Range.globalCursor = Range.globalCursor or 0

local function listSize(list)
    if not list then return 0 end
    if type(list) == "table" and type(list.size) ~= "function" then return #list end
    return math.max(0, floor(GodSystemB42JavaCalls.value(list, "size", 0), 0))
end

local function listGet(list, index)
    if type(list) == "table" and type(list.get) ~= "function" then return list[index + 1] end
    return GodSystemB42JavaCalls.value(list, "get", nil, index)
end

local function containsIdentity(list, target)
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
    if not item then return nil end
    local ok, container = GodSystemB42JavaCalls.try(item, "getInventory")
    if ok and container then return container end
    return nil
end

local function containerItems(container)
    return GodSystemB42JavaCalls.value(container, "getItems", nil)
end

local function containerEmpty(container)
    return listSize(containerItems(container)) == 0
end

local ScannerHooks = {}

function ScannerHooks:listSize(list) return listSize(list) end
function ScannerHooks:listGet(list, index) return listGet(list, index) end
function ScannerHooks:worldObjects(square)
    return GodSystemB42JavaCalls.value(square, "getWorldObjects", nil)
end
function ScannerHooks:objects(square)
    return GodSystemB42JavaCalls.value(square, "getObjects", nil)
end
function ScannerHooks:worldItem(worldObject)
    return GodSystemB42JavaCalls.value(worldObject, "getItem", nil)
end
function ScannerHooks:itemContainer(item) return itemContainer(item) end
function ScannerHooks:containerItems(container) return containerItems(container) end
function ScannerHooks:fullType(item)
    return tostring(GodSystemB42JavaCalls.value(item, "getFullType", "") or "")
end
function ScannerHooks:isVehicle(object)
    return isType(object, "BaseVehicle")
end
function ScannerHooks:objectContainers(object)
    local result = {}
    if not object or isType(object, "IsoWorldInventoryObject") or isType(object, "IsoDeadBody")
        or isType(object, "BaseVehicle") then
        return result
    end
    local count = GodSystemB42JavaCalls.value(object, "getContainerCount", 0)
    for index = 0, math.max(0, floor(count, 0)) - 1 do
        local container = GodSystemB42JavaCalls.value(object, "getContainerByIndex", nil, index)
        if container then result[#result + 1] = container end
    end
    if #result == 0 then
        local container = GodSystemB42JavaCalls.value(object, "getContainer", nil)
        if container then result[1] = container end
    end
    return result
end
function ScannerHooks:corpses(square)
    local result = {}
    local moving = GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil)
    for index = 0, listSize(moving) - 1 do
        local object = listGet(moving, index)
        if isType(object, "IsoDeadBody") then result[#result + 1] = object end
    end
    return result
end
function ScannerHooks:corpseContainer(corpse)
    return GodSystemB42JavaCalls.value(corpse, "getContainer", nil)
end

local function playerNumber(player, method, fallback)
    return tonumber(GodSystemB42JavaCalls.value(player, method, fallback)) or fallback
end

local function playerFlag(player, method)
    return GodSystemB42JavaCalls.value(player, method, false) == true
end

local function playerIsOnline(player, onlineId)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return true end
    for index = 0, listSize(players) - 1 do
        local candidate = listGet(players, index)
        local candidateId = tonumber(GodSystemB42JavaCalls.value(candidate, "getOnlineID", -2)) or -2
        if candidate == player or candidateId == onlineId then return true end
    end
    return false
end

local function squareFor(coord)
    if not getCell then return nil end
    local okCell, cell = pcall(getCell)
    if not okCell or not cell then return nil end
    return GodSystemB42JavaCalls.value(cell, "getGridSquare", nil, coord.x, coord.y, coord.z)
end

local function canAccessSafehouse(player, square)
    if not SafeHouse or not SafeHouse.isPlayerAllowedOnSquare then return false end
    local ok, allowed = pcall(function()
        return SafeHouse.isPlayerAllowedOnSquare(player, square)
    end)
    return ok and allowed == true
end

local function removeWorldObject(square, candidate)
    local worldObject = candidate.worldObject
    local item = candidate.item
    if not worldObject or not item then return false end
    local current = GodSystemB42JavaCalls.value(worldObject, "getItem", nil)
    if current ~= item then return false end
    if candidate.portableShell and not containerEmpty(itemContainer(item)) then return false end
    local worldObjects = GodSystemB42JavaCalls.value(square, "getWorldObjects", nil)
    if not containsIdentity(worldObjects, worldObject) then return false end
    local ok = GodSystemB42JavaCalls.try(square, "transmitRemoveItemFromSquare", worldObject)
    if not ok then return false end
    worldObjects = GodSystemB42JavaCalls.value(square, "getWorldObjects", nil)
    return not containsIdentity(worldObjects, worldObject)
end

local function removeContainerCandidate(candidate)
    local container = candidate.container
    local item = candidate.item
    if not container or not item or not GodSystemServerContainerContainsItem(container, item) then return false end
    local nested = itemContainer(item)
    if nested and not containerEmpty(nested) then return false end
    return removeItemFromContainer(container, item)
end

local function removeCorpse(square, candidate)
    local corpse = candidate.corpse
    if not corpse then return false end
    local container = GodSystemB42JavaCalls.value(corpse, "getContainer", nil)
    if container and not containerEmpty(container) then return false end
    local moving = GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil)
    if not containsIdentity(moving, corpse) then return false end
    local ok = GodSystemB42JavaCalls.try(square, "removeCorpse", corpse, false)
    if not ok then return false end
    moving = GodSystemB42JavaCalls.value(square, "getStaticMovingObjects", nil)
    return not containsIdentity(moving, corpse)
end

local function rawItemPayout(item, fullType)
    if not item or not fullType or fullType == "" then return 0 end
    local quote = GodSystemEconomyPolicy.quote(fullType, item, { kind = "recycle" })
    return math.max(0, floor(quote and quote.recycleValue, 0))
end

local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(player)
    local x = playerNumber(player, "getX", 0)
    local y = playerNumber(player, "getY", 0)
    local z = playerNumber(player, "getZ", 0)
    return setmetatable({
        player = player,
        startX = x,
        startY = y,
        startZ = z,
        startHealth = playerNumber(player, "getHealth", 100),
        playerNum = playerNumber(player, "getPlayerNum", 0),
        onlineId = playerNumber(player, "getOnlineID", -1),
        scanner = GodSystemRangeRecycleScanner.new(ScannerHooks),
    }, Adapter)
end

function Adapter:getSquare(coord)
    return squareFor(coord)
end

function Adapter:canAccessSquare(_, square)
    return canAccessSafehouse(self.player, square)
end

function Adapter:isInterrupted()
    local player = self.player
    if not player then return "disconnected" end
    if not playerIsOnline(player, self.onlineId) then return "disconnected" end
    if playerFlag(player, "isDead") then return "dead" end
    if playerNumber(player, "getHealth", self.startHealth) < self.startHealth then return "hurt" end
    if GodSystemB42JavaCalls.value(player, "getVehicle", nil) ~= nil then return "vehicle" end
    if playerFlag(player, "isAiming") or playerFlag(player, "isAttacking") then return "combat" end
    if playerFlag(player, "isRunning") or playerFlag(player, "isSprinting") then return "running" end
    if playerFlag(player, "isPlayerMoving") then return "moved" end
    if playerNumber(player, "getPlayerNum", self.playerNum) ~= self.playerNum then return "playerChanged" end
    if playerNumber(player, "getOnlineID", self.onlineId) ~= self.onlineId then return "playerChanged" end
    local x = playerNumber(player, "getX", self.startX)
    local y = playerNumber(player, "getY", self.startY)
    local z = playerNumber(player, "getZ", self.startZ)
    if math.abs(x - self.startX) > 0.01 or math.abs(y - self.startY) > 0.01 or math.abs(z - self.startZ) > 0.01 then
        return "moved"
    end
    return nil
end

function Adapter:nextCandidate(_, stage, square, cursor)
    return self.scanner:nextCandidate(stage, square, cursor)
end

function Adapter:afterCandidate(_, candidate, outcome)
    self.scanner:afterCandidate(candidate, outcome and outcome.removed == true)
end

function Adapter:recycle(_, candidate, stage, square)
    local removed = false
    if candidate.kind == "worldItem" then
        removed = removeWorldObject(square, candidate)
    elseif candidate.kind == "containerItem" then
        removed = removeContainerCandidate(candidate)
    elseif candidate.kind == "corpse" then
        removed = removeCorpse(square, candidate)
    end
    if not removed then return { removed = false, payout = 0, reason = "targetChanged" } end
    local payout = stage == "corpses" and 1 or rawItemPayout(candidate.item, candidate.fullType)
    return { removed = true, payout = payout }
end

local function filterFor(player)
    local key = userKey(player)
    local cached = Range.filterCache[key]
    return cached and cached.ready == true and cached.compiled or nil
end

local function progressCommand(player, progress)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.RangeRecycleProgress) or "rangeRecycleProgress", progress)
end

local function sendProgress(record, progress)
    progress.operationId = record.operationId
    progress.jobId = record.job.id
    progressCommand(record.player, progress)
end

local function finishRecord(record, progress, stateDeferred)
    local key = record.key
    Range.jobs[key] = nil
    local data = playerData(record.player)
    appendHistory(data, historyEntry("recycle", "RangeRecycleSummary", {
        progress.processed or 0,
        progress.payout or 0,
        progress.skipped or 0,
        progress.reason or "",
    }))
    storeCheckpoint()
    sendProgress(record, progress)
    if not stateDeferred then sendState(record.player) end
end

local function settleBatch(record, progress)
    local rawPayout = math.max(0, floor(progress.batchPayout, 0))
    local data = playerData(record.player)
    local payout = applyRecycleDailyPayout(data, rawPayout)
    record.job.payout = math.max(0, record.job.payout - rawPayout + payout)
    progress.batchPayout = payout
    progress.payout = record.job.payout
    local delivery = GodSystemRecyclePayout.deliver(payout, function(value)
        return giveCurrency(record.player, value)
    end, function(value)
        local bank = getBank(data)
        bank.current = math.max(0, floor(bank.current, 0)) + value
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

function Range.tickRecord(record, nowMs)
    local interrupted = record.job.adapter:isInterrupted(record.job)
    if interrupted then
        local progress = GodSystemRangeRecycleDomain.cancel(record.job, interrupted)
        finishRecord(record, progress)
        return progress
    end
    if nowMs < record.warmupUntilMs then return nil end
    local targetBudget = math.max(1, math.floor(tonumber(record.targetBudget) or record.job.batchSize or 20))
    local scanBudget = math.max(1, math.floor(tonumber(record.scanBudget) or record.job.scanBudget or 256))
    local oldBatchSize, oldScanBudget = record.job.batchSize, record.job.scanBudget
    record.job.batchSize = math.min(oldBatchSize, targetBudget)
    record.job.scanBudget = math.min(oldScanBudget, scanBudget)
    local progress = settleBatch(record, GodSystemRangeRecycleDomain.step(record.job))
    record.job.batchSize, record.job.scanBudget = oldBatchSize, oldScanBudget
    if progress.status == "running" then
        sendProgress(record, progress)
    else
        finishRecord(record, progress)
    end
    return progress
end

function Range.onTick()
    local nowMs = GodSystemScheduler.nowMs()
    local intervalMs = math.floor(math.max(0.10, math.min(2.00,
        tonumber(GodSystemRuntimeConfig.get("RangeRecycleBatchIntervalSeconds", 0.25)) or 0.25
    )) * 1000)
    local budget = Range.globalBudget
    if nowMs >= (budget.nextAtMs or 0) then
        budget.nextAtMs = nowMs + intervalMs
        budget.targets = GLOBAL_TARGET_BUDGET
        budget.scans = GLOBAL_SCAN_BUDGET
    end
    if budget.targets <= 0 or budget.scans <= 0 then return end
    local records = {}
    for _, record in pairs(Range.jobs) do records[#records + 1] = record end
    table.sort(records, function(a, b) return tostring(a.key) < tostring(b.key) end)
    local eligible = {}
    for index = 1, #records do
        local record = records[index]
        if Range.jobs[record.key] == record and nowMs >= record.warmupUntilMs and nowMs >= record.nextBatchMs then
            eligible[#eligible + 1] = record
        end
    end
    if #eligible == 0 then return end
    local start = ((Range.globalCursor or 0) % #eligible) + 1
    Range.globalCursor = Range.globalCursor + 1
    for offset = 0, #eligible - 1 do
        if budget.targets <= 0 or budget.scans <= 0 then break end
        local index = ((start + offset - 1) % #eligible) + 1
        local record = eligible[index]
        if Range.jobs[record.key] == record then
            local remaining = #eligible - offset
            record.targetBudget = math.max(1, math.min(record.job.batchSize, math.floor(budget.targets / remaining)))
            record.scanBudget = math.max(1, math.min(record.job.scanBudget, math.floor(budget.scans / remaining)))
            record.nextBatchMs = nowMs + intervalMs
            local ok, progressOrError = pcall(Range.tickRecord, record, nowMs)
            if not ok then
                record.job.status = "failed"
                record.job.reason = "serverError"
                diagnostics.lastError = tostring(progressOrError)
                finishRecord(record, GodSystemRangeRecycleDomain.progress(record.job))
            elseif progressOrError then
                budget.targets = math.max(0, budget.targets - math.max(0, math.floor(tonumber(progressOrError.batchTargets) or 0)))
                budget.scans = math.max(0, budget.scans - math.max(0, math.floor(tonumber(progressOrError.batchInspected) or 0)))
            end
        end
    end
end

function Commands.rangeRecycleStart(_, _, player, args)
    applyRuntimeStores()
    if not GodSystemRuntimeConfig.isFeatureEnabled("EnableRecycle", GodSystemConfig.EnableRecycle ~= false)
        or not GodSystemRuntimeConfig.isFeatureEnabled("EnableRangeRecycle", true) then
        return finishCode(player, false, "RangeRecycleDisabled", nil, nil)
    end
    local key = userKey(player)
    if Range.jobs[key] then return finishCode(player, false, "RangeRecycleAlreadyRunning", nil, nil) end
    local adapter = Adapter.new(player)
    if adapter:isInterrupted() then return finishCode(player, false, "RangeRecycleStartInvalid", nil, nil) end
    local radius = math.max(1, math.min(10, floor(GodSystemRuntimeConfig.get("RangeRecycleRadius", 5), 5)))
    local nowMs = GodSystemScheduler.nowMs()
    local operationId = tostring(args and (args.operationId or args.opId) or ("range-" .. key .. "-" .. tostring(nowMs)))
    if #operationId > 96 then operationId = "range-" .. key .. "-" .. tostring(nowMs) end
    local data = playerData(player)
    local filter = filterFor(player)
    if not filter then return finishCode(player, false, "RangeFilterSyncRequired", nil, nil) end
    if not GodSystemRangeFilter.canStart(filter) then
        return finishCode(player, false, "RangeRecycleNoAllowedItems", nil, nil)
    end
    local job = GodSystemRangeRecycleDomain.newJob({
        id = operationId,
        playerId = key,
        origin = { x = adapter.startX, y = adapter.startY, z = adapter.startZ },
        radius = radius,
        batchSize = 20,
        scanBudget = 256,
        filter = filter,
        adapter = adapter,
    })
    local record = {
        key = key,
        player = player,
        operationId = operationId,
        job = job,
        warmupUntilMs = nowMs + 1000,
        nextBatchMs = nowMs + 1000,
    }
    Range.jobs[key] = record
    sendProgress(record, {
        status = "running",
        stage = "verifying",
        processed = 0,
        payout = 0,
        skipped = 0,
        batchProcessed = 0,
        batchPayout = 0,
        warmupSeconds = 1,
    })
    return finishCode(player, true, "RangeRecycleStarted", { radius }, { operationId = operationId, radius = radius })
end

function Commands.rangeRecycleCancel(_, _, player)
    local record = Range.jobs[userKey(player)]
    if not record then return finishCode(player, false, "RangeRecycleNotRunning", nil, nil) end
    finishRecord(record, GodSystemRangeRecycleDomain.cancel(record.job, "cancelled"), true)
    return finishCode(player, true, "RangeRecycleCancelled", nil, { operationId = record.operationId })
end

function Range.sendFilterSnapshot(player)
    local cached = Range.filterCache[userKey(player)]
    local ready = cached and cached.ready == true
    local state = ready and cached.state or GodSystemRangeFilter.normalize(nil)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.RangeFilterSnapshot) or "rangeFilterSnapshot", {
        snapshot = state,
        ready = ready,
    })
end

function Commands.rangeFilterDelta(_, _, player, args)
    local key = userKey(player)
    local cached = Range.filterCache[key]
    if not cached or cached.ready ~= true then
        Range.sendFilterSnapshot(player)
        return finishCode(player, false, "RangeFilterSyncRequired", nil, nil)
    end
    local result = GodSystemRangeFilter.applyDelta(cached.state, args)
    if result.ok then
        Range.filterCache[key] = {
            ready = true,
            state = result.state,
            compiled = GodSystemRangeFilter.compile(result.state),
        }
    end
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.RangeFilterDeltaAck) or "rangeFilterDeltaAck", {
        ok = result.ok == true,
        code = result.code,
        args = {},
        data = { snapshot = result.state },
        operationId = nil,
        snapshot = result.state,
        ready = true,
    })
end

local function validSyncId(value)
    value = tostring(value or "")
    if value == "" or #value > 96 then return nil end
    return value
end

local function validateChunk(values, seen)
    if type(values) ~= "table" or #values > FILTER_SYNC_CHUNK_SIZE then return nil end
    local result = {}
    for index = 1, #values do
        local fullType = GodSystemRangeFilter.cleanFullType(values[index])
        if not fullType or seen[fullType] then return nil end
        seen[fullType] = true
        result[#result + 1] = fullType
    end
    return result
end

function Commands.rangeFilterSyncBegin(_, _, player, args)
    local syncId = validSyncId(args and args.syncId)
    local total = math.floor(tonumber(args and args.total) or -1)
    local mode = GodSystemRangeFilter.cleanMode(args and args.mode)
    if not syncId or not mode or total < 0 or total > FILTER_SYNC_MAX_ITEMS then
        return finishCode(player, false, "RangeFilterSyncInvalid", nil, nil)
    end
    local key = userKey(player)
    local current = Range.filterCache[key]
    Range.filterCache[key] = { ready = false }
    Range.filterStaging[key] = {
        syncId = syncId,
        total = total,
        nextOffset = 1,
        values = {},
        seen = {},
        mode = mode,
        revision = current and current.state and current.state.revision or 0,
    }
    Range.sendFilterSnapshot(player)
end

function Commands.rangeFilterSyncChunk(_, _, player, args)
    local key = userKey(player)
    local staged = Range.filterStaging[key]
    local syncId = validSyncId(args and args.syncId)
    local offset = math.floor(tonumber(args and args.offset) or -1)
    if not staged or syncId ~= staged.syncId or offset ~= staged.nextOffset then
        return finishCode(player, false, "RangeFilterSyncInvalid", nil, nil)
    end
    local chunk = validateChunk(args and args.fullTypes, staged.seen)
    if not chunk or (#staged.values + #chunk) > staged.total then
        return finishCode(player, false, "RangeFilterSyncInvalid", nil, nil)
    end
    for index = 1, #chunk do staged.values[#staged.values + 1] = chunk[index] end
    staged.nextOffset = staged.nextOffset + #chunk
end

function Commands.rangeFilterSyncCommit(_, _, player, args)
    local key = userKey(player)
    local staged = Range.filterStaging[key]
    local syncId = validSyncId(args and args.syncId)
    if not staged or syncId ~= staged.syncId or #staged.values ~= staged.total then
        return finishCode(player, false, "RangeFilterSyncInvalid", nil, nil)
    end
    local state = GodSystemRangeFilter.normalize({
        mode = staged.mode,
        revision = math.max(1, staged.revision + 1),
        activeFullTypes = staged.values,
    })
    Range.filterStaging[key] = nil
    Range.filterCache[key] = {
        ready = true,
        state = state,
        compiled = GodSystemRangeFilter.compile(state),
    }
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.RangeFilterSyncAck) or "rangeFilterSyncAck", {
        ok = true,
        snapshot = state,
        ready = true,
        syncId = syncId,
    })
end

function Range.onDisconnect(player)
    local key = player and userKey(player) or nil
    local record = key and Range.jobs[key] or nil
    if record then
        Range.jobs[record.key] = nil
        GodSystemRangeRecycleDomain.cancel(record.job, "disconnected")
    end
    if key then
        Range.filterCache[key] = nil
        Range.filterStaging[key] = nil
    end
end

function Range.onPlayerDeath(player)
    local record = player and Range.jobs[userKey(player)] or nil
    if record then finishRecord(record, GodSystemRangeRecycleDomain.cancel(record.job, "dead")) end
end

Events.OnTick.Add(Range.onTick)
if Events.OnDisconnect then Events.OnDisconnect.Add(Range.onDisconnect) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(Range.onPlayerDeath) end

return Range
end
