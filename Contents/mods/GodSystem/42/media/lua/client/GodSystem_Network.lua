require "GodSystem_App"
require "GodSystem_Config"
require "GodSystem_Core"
require "GodSystem_Protocol"
require "GodSystem_Scheduler"
require "GodSystem_Maintenance"
require "GodSystem_B42JavaCalls"
require "TimedActions/ISTimedActionQueue"
require "ISUI/ISInventoryPane"

if not (isClient and isClient()) then return end

GodSystemNetwork = GodSystemNetwork or {}
GodSystemNetwork.isMultiplayer = true
GodSystemNetwork.hasServerState = GodSystemNetwork.hasServerState == true
GodSystemNetwork.pendingState = GodSystemNetwork.pendingState == true
GodSystemNetwork.stateSerial = tonumber(GodSystemNetwork.stateSerial) or 0
GodSystemNetwork.sentCommands = tonumber(GodSystemNetwork.sentCommands) or 0
GodSystemNetwork.failedCommands = tonumber(GodSystemNetwork.failedCommands) or 0
GodSystemNetwork.receivedStates = tonumber(GodSystemNetwork.receivedStates) or 0

local Protocol = GodSystemProtocol or {}
local MODULE = Protocol.Module or "GodSystem"
local sentHello = false
local pendingRefresh = false
local pendingHelloTick = false
local lastStateRequestMs = 0
local lastSentKills = nil
local lastObservedKills = nil
local pendingKillDelta = 0
local nextBackgroundSyncMs = 0
local BACKGROUND_SYNC_MS = Protocol.BackgroundSyncMs or 300000
local BACKGROUND_BUSY_RETRY_MS = 1000
local KILL_SYNC_THRESHOLD = Protocol.KillSyncThreshold or 10
local STATE_THROTTLE_MS = Protocol.StateThrottleMs or 1200
local KEY_COMMAND_TIMEOUT_MS = Protocol.KeyCommandTimeoutMs or 15000
local reportedTimeoutTasks = {}
local pendingKeyCommand = nil
local pendingOperationId = nil
local pendingOperationStartedMs = 0
local pendingOperationPayload = nil
local timedOutTransactionOperation = nil
local timedOutAttributeOperation = nil
local operationSeq = math.max(0, tonumber(GodSystemNetwork.operationSeq) or 0)
local operationSessionId = tostring(GodSystemNetwork.operationSessionId or "")
local lastAutoTaskClaimHour = nil
local lastAutoDepositHour = nil
local investmentRuntimeHour = nil
local investmentWasActive = false
local send

function GodSystemNetwork.resetInvestmentRuntime()
    investmentRuntimeHour = nil
    investmentWasActive = false
end

function GodSystemNetwork.resetSessionRuntime()
    sentHello = false
    pendingHelloTick = true
    pendingRefresh = false
    lastStateRequestMs = 0
    nextBackgroundSyncMs = 0
    GodSystemNetwork.hasServerState = false
    GodSystemNetwork.pendingState = true
    GodSystemApp.services.runtime.serverAdmin = false
    local rangeService = GodSystemApp.getService and GodSystemApp.getService("rangeRecycle") or nil
    if rangeService and rangeService.resetSession then rangeService:resetSession() end
    if Events and Events.OnTick then
        Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
        Events.OnTick.Add(GodSystemNetwork.helloRetryOnTick)
    end
end

local function player()
    return getPlayer and getPlayer() or nil
end

local function notify(text)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
        GodSystemApp.services.runtime.notify(text)
    end
end

local function formatTemplate(template, args)
    local text = tostring(template or "")
    args = args or {}
    for i = 1, #args do
        text = string.gsub(text, "{" .. tostring(i) .. "}", function()
            return tostring(args[i] or "")
        end)
    end
    return text
end

local function localizeStructuredArgs(code, args)
    local localized = {}
    for i = 1, #(args or {}) do
        localized[i] = args[i]
    end
    if (code == "BankInvestmentCreated" or code == "BankInvestmentRedeemed") and localized[1]
        and GodSystemApp.services.runtime and GodSystemApp.services.runtime.getBankInvestmentLabel then
        localized[1] = GodSystemApp.services.runtime.getBankInvestmentLabel(localized[1])
    end
    local firstArgIsItem = code == "ListOnlySuccess" or code == "ListOnlyAutoShop"
        or code == "ShopItemHidden" or code == "ShopItemVisible" or code == "ShopItemDeleted"
        or code == "MaintenanceRepairSuccess" or code == "MaintenanceReinforceSuccess"
    if firstArgIsItem and localized[1]
        and GodSystemApp.services.runtime and GodSystemApp.services.runtime.getItemDisplayName then
        localized[1] = GodSystemApp.services.runtime.getItemDisplayName(tostring(localized[1]))
    end
    return localized
end

local function notifyPayload(args)
    if not args then return end
    if args.code then
        local template = GodSystemApp.services.runtime and GodSystemApp.services.runtime.text and GodSystemApp.services.runtime.text("NotifyMP_" .. tostring(args.code), "") or ""
        if template and template ~= "" then
            notify(formatTemplate(template, localizeStructuredArgs(tostring(args.code), args.args)))
            return
        end
    end
end

local function resultMessagePayload(args)
    if not args then return "" end
    if args.code then
        local template = GodSystemApp.services.runtime and GodSystemApp.services.runtime.text and GodSystemApp.services.runtime.text("NotifyMP_" .. tostring(args.code), "") or ""
        if template and template ~= "" then
            return formatTemplate(template, localizeStructuredArgs(tostring(args.code), args.args))
        end
    end
    return ""
end

local function handleTeleportPayload(args)
    local id = args and args.id
    local pos = args and args.pos
    local ok = false
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.applyApprovedTeleport then
        ok = GodSystemApp.services.runtime.applyApprovedTeleport(pos) == true
    end
    send((Protocol.C2S and Protocol.C2S.TeleportConfirm) or "teleportConfirm", { id = id, ok = ok })
    if ok and GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify and GodSystemApp.services.runtime.formatPosition then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeTeleported", "Teleported: ") .. GodSystemApp.services.runtime.formatPosition(pos))
    end
end

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function hasSelectedInventoryItems(pane)
    if not pane or type(pane.selected) ~= "table" then return false end
    for _, item in pairs(pane.selected) do
        if item ~= nil then return true end
    end
    return false
end

function GodSystemNetwork.isTimedActionBusy(p)
    p = p or player()
    if p and ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue then
        local queue = ISTimedActionQueue.getTimedActionQueue(p)
        if queue and queue.queue and queue.queue[1] then return true, queue.queue[1] end
    end
    if ISMouseDrag and ISMouseDrag.dragging and #ISMouseDrag.dragging > 0 then return true end
    local cell = getCell and getCell() or nil
    local drag = cell and cell.getDrag and cell:getDrag(0) or nil
    if drag and drag.Type == "ISMoveableCursor" then return true end
    return false
end

function GodSystemNetwork.isInventoryInteractionBusy(p)
    local busy, action = GodSystemNetwork.isTimedActionBusy(p)
    if busy then return true, action end
    local inventoryPage = getPlayerInventory and getPlayerInventory(0) or nil
    if inventoryPage and hasSelectedInventoryItems(inventoryPage.inventoryPane) then return true end
    local lootPage = getPlayerLoot and getPlayerLoot(0) or nil
    if lootPage and hasSelectedInventoryItems(lootPage.inventoryPane) then return true end
    return false
end

local function nextAttributeOperationId()
    if operationSessionId == "" then
        local randomPart = ZombRand and ZombRand(100000, 1000000) or 0
        operationSessionId = tostring(nowMs()) .. "-" .. tostring(randomPart)
        GodSystemNetwork.operationSessionId = operationSessionId
    end
    operationSeq = operationSeq + 1
    GodSystemNetwork.operationSeq = operationSeq
    return "gs-" .. operationSessionId .. "-" .. tostring(operationSeq)
end

local function isStateCommand(command)
    if Protocol.isStateCommand then return Protocol.isStateCommand(command) end
    return false
end

local function isKeyCommand(command)
    if Protocol.isKeyCommand then return Protocol.isKeyCommand(command) end
    return false
end

local function copyPayload(args)
    local payload = {}
    for k, v in pairs(args or {}) do
        payload[k] = v
    end
    return payload
end

local function transactionFingerprint(command, args)
    args = type(args) == "table" and args or {}
    local attributeCommand = (Protocol.C2S and Protocol.C2S.Attribute) or "attribute"
    local upgradeCommand = (Protocol.C2S and Protocol.C2S.UpgradeSystem) or "upgradeSystem"
    local recycleCommand = (Protocol.C2S and Protocol.C2S.Recycle) or "recycle"
    local buyShopCommand = (Protocol.C2S and Protocol.C2S.BuyShop) or "buyShop"
    local lotteryCommand = (Protocol.C2S and Protocol.C2S.UseLotteryTicket) or "useLotteryTicket"
    local listOnlyCommand = (Protocol.C2S and Protocol.C2S.ListOnlyAutoShop) or "listOnlyAutoShop"
    if command == attributeCommand then
        return table.concat({
            "attribute",
            tostring(args.perkIndex or ""),
            tostring(args.mode or ""),
            tostring(args.value or ""),
        }, "|")
    end
    if command == upgradeCommand then
        return "upgrade|" .. tostring(args.upgradeType or "")
    end
    if command == buyShopCommand then
        return table.concat({
            "buyShop",
            tostring(args.id or ""),
            "q:" .. tostring(math.max(1, math.floor(tonumber(args.quantity) or 1))),
        }, "|")
    end
    if command == lotteryCommand then
        return "lottery|" .. tostring(args.itemId or "")
    end
    if command == listOnlyCommand then
        return table.concat({
            "listOnly",
            tostring(args.fullType or ""),
            tostring(args.itemId or ""),
        }, "|")
    end
    if command == recycleCommand and type(args.itemIds) == "table" then
        local parts = {
            "recycle",
            tostring(args.mode or ""),
            args.allowDestroyContents == true and "1" or "0",
        }
        local ids = {}
        for i = 1, #args.itemIds do ids[#ids + 1] = tostring(args.itemIds[i] or "") end
        table.sort(ids)
        for i = 1, #ids do parts[#parts + 1] = "i:" .. ids[i] end
        local signatures = type(args.containerContentSignatures) == "table" and args.containerContentSignatures or {}
        local signatureIds = {}
        for id in pairs(signatures) do signatureIds[#signatureIds + 1] = tostring(id) end
        table.sort(signatureIds)
        for i = 1, #signatureIds do
            local id = signatureIds[i]
            parts[#parts + 1] = "s:" .. id .. "=" .. tostring(signatures[id] or "")
        end
        return table.concat(parts, "|")
    end
    local hiddenCommand = (Protocol.C2S and Protocol.C2S.SetShopItemsHidden) or "setShopItemsHidden"
    if command == hiddenCommand and type(args.variantKeys) == "table" then
        local keys, seen = {}, {}
        for i = 1, #args.variantKeys do
            local key = tostring(args.variantKeys[i] or "")
            if key ~= "" and not seen[key] then seen[key] = true; keys[#keys + 1] = key end
        end
        table.sort(keys)
        local parts = { "shopHidden", args.hidden == true and "1" or "0" }
        for i = 1, #keys do parts[#parts + 1] = "k:" .. keys[i] end
        return table.concat(parts, "|")
    end
    return nil
end

local function sameAttributePayload(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return math.floor(tonumber(a.perkIndex) or -1) == math.floor(tonumber(b.perkIndex) or -1)
        and tostring(a.mode or "") == tostring(b.mode or "")
        and math.floor(tonumber(a.value) or 0) == math.floor(tonumber(b.value) or 0)
end

local function readLocalTaskProgress(task, data)
    if not task then return nil end
    local progress = nil
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.getTaskProgress then
        local ok, value = pcall(GodSystemApp.services.runtime.getTaskProgress, task)
        if ok and value ~= nil then progress = value end
    end
    if progress == nil and task.kind == "kill" then
        progress = task.killProgress
    elseif progress == nil and task.kind == "moveDistance" and data and data.stats then
        progress = (tonumber(data.stats.moveDistance) or 0) - (tonumber(task.startMoveDistance) or 0)
    end
    if progress == nil then return nil end
    return math.max(0, math.floor(tonumber(progress) or 0))
end

local function mergeLocalTaskProgress(serverData)
    if not serverData or not serverData.tasks then return serverData end
    local localData = GodSystemApp.services.runtime and GodSystemApp.services.runtime.data or nil
    if not localData or not localData.tasks then return serverData end

    localData.stats = localData.stats or {}
    serverData.stats = serverData.stats or {}

    local localMoveDistance = tonumber(localData.stats.moveDistance) or 0
    local serverMoveDistance = tonumber(serverData.stats.moveDistance) or 0
    if localMoveDistance > serverMoveDistance then
        serverData.stats.moveDistance = localMoveDistance
    end
    if localData.lastMoveX ~= nil then serverData.lastMoveX = localData.lastMoveX end
    if localData.lastMoveY ~= nil then serverData.lastMoveY = localData.lastMoveY end
    if localData.lastMoveZ ~= nil then serverData.lastMoveZ = localData.lastMoveZ end

    local localKillProgress = {}
    local localMoveProgress = {}
    for i = 1, #(localData.tasks or {}) do
        local task = localData.tasks[i]
        if task and task.status == "active" and task.kind == "kill" and task.taskId then
            local progress = readLocalTaskProgress(task, localData) or task.killProgress
            localKillProgress[tostring(task.taskId)] = math.max(0, math.floor(tonumber(progress) or 0))
        elseif task and task.status == "active" and task.kind == "moveDistance" and task.taskId then
            localMoveProgress[tostring(task.taskId)] = readLocalTaskProgress(task, localData)
        end
    end
    for i = 1, #(serverData.tasks or {}) do
        local task = serverData.tasks[i]
        if task and task.status == "active" and task.kind == "kill" and task.taskId then
            local localValue = localKillProgress[tostring(task.taskId)]
            if localValue and localValue > math.max(0, math.floor(tonumber(task.killProgress) or 0)) then
                task.killProgress = localValue
            end
        elseif task and task.status == "active" and task.kind == "moveDistance" and task.taskId then
            local localValue = localMoveProgress[tostring(task.taskId)]
            if localValue then
                local requiredMoveDistance = (tonumber(task.startMoveDistance) or 0) + localValue
                if requiredMoveDistance > (tonumber(serverData.stats.moveDistance) or 0) then
                    serverData.stats.moveDistance = requiredMoveDistance
                end
            end
        end
    end
    return serverData
end

local function clearPendingOperation(reason)
    if pendingKeyCommand then
        GodSystemNetwork.lastPendingClearReason = reason or "cleared"
    end
    pendingKeyCommand = nil
    pendingOperationId = nil
    pendingOperationStartedMs = 0
    pendingOperationPayload = nil
    GodSystemNetwork.pendingCommand = nil
    GodSystemNetwork.pendingOperationId = nil
    GodSystemNetwork.pendingOperationStartedMs = nil
end

local function checkPendingTimeout()
    if not pendingKeyCommand then return false end
    local started = tonumber(pendingOperationStartedMs) or tonumber(GodSystemNetwork.pendingOperationStartedMs) or 0
    if started <= 0 then return false end
    local elapsed = nowMs() - started
    if elapsed < KEY_COMMAND_TIMEOUT_MS then return false end
    local command = pendingKeyCommand
    local fingerprint = transactionFingerprint(command, pendingOperationPayload)
    if fingerprint and pendingOperationId ~= nil then
        timedOutTransactionOperation = {
            opId = pendingOperationId,
            payload = copyPayload(pendingOperationPayload),
            command = command,
            fingerprint = fingerprint,
            expiredAtMs = nowMs(),
        }
        if command == ((Protocol.C2S and Protocol.C2S.Attribute) or "attribute") then
            timedOutAttributeOperation = timedOutTransactionOperation
        end
    end
    GodSystemNetwork.pendingTimeouts = (GodSystemNetwork.pendingTimeouts or 0) + 1
    GodSystemNetwork.lastPendingTimeoutCommand = command
    GodSystemNetwork.lastPendingTimeoutElapsedMs = elapsed
    clearPendingOperation("timeout")
    GodSystemNetwork.pendingState = false
    notify(GodSystemApp.services.runtime.text("Notify_CommandTimeout", "Operation timed out. Please retry."))
    if sentHello and send then
        lastStateRequestMs = 0
        send((Protocol.C2S and Protocol.C2S.Refresh) or "refresh", {})
    end
    return true
end

send = function(command, args)
    local p = player()
    if not p then return false end
    if not sendClientCommand then return false end
    command = tostring(command or "")
    local keyCommand = isKeyCommand(command)
    checkPendingTimeout()
    if keyCommand and pendingKeyCommand then
        GodSystemNetwork.lastBlockedCommand = command
        notify(GodSystemApp.services.runtime.text("Notify_CommandPending", "Operation is still processing."))
        return false
    end
    local payload = copyPayload(args)
    if keyCommand then
        local fingerprint = transactionFingerprint(command, payload)
        local reusedOpId = nil
        if fingerprint and timedOutTransactionOperation
            and command == timedOutTransactionOperation.command
            and nowMs() - (tonumber(timedOutTransactionOperation.expiredAtMs) or 0) <= 60000
            and fingerprint == timedOutTransactionOperation.fingerprint
            and (command ~= ((Protocol.C2S and Protocol.C2S.Attribute) or "attribute") or sameAttributePayload(payload, timedOutTransactionOperation.payload)) then
            reusedOpId = timedOutTransactionOperation.opId
        end
        if reusedOpId == nil then
            if fingerprint then
                reusedOpId = nextAttributeOperationId()
            else
                operationSeq = operationSeq + 1
                GodSystemNetwork.operationSeq = operationSeq
                reusedOpId = operationSeq
            end
        end
        if fingerprint then
            timedOutTransactionOperation = nil
            if command == ((Protocol.C2S and Protocol.C2S.Attribute) or "attribute") then timedOutAttributeOperation = nil end
        end
        pendingKeyCommand = command
        pendingOperationId = reusedOpId
        pendingOperationStartedMs = nowMs()
        pendingOperationPayload = copyPayload(payload)
        payload.opId = reusedOpId
        GodSystemNetwork.pendingCommand = command
        GodSystemNetwork.pendingOperationId = reusedOpId
        GodSystemNetwork.pendingOperationStartedMs = pendingOperationStartedMs
    end
    GodSystemNetwork.lastSentCommand = command
    GodSystemNetwork.lastSentAtMs = nowMs()
    local ok = pcall(sendClientCommand, p, MODULE, command, payload)
    if ok then
        GodSystemNetwork.sentCommands = (GodSystemNetwork.sentCommands or 0) + 1
        if isStateCommand(command) then
            GodSystemNetwork.pendingState = true
        end
        return true
    end
    ok = pcall(sendClientCommand, MODULE, command, payload)
    if ok then
        GodSystemNetwork.sentCommands = (GodSystemNetwork.sentCommands or 0) + 1
        if isStateCommand(command) then
            GodSystemNetwork.pendingState = true
        end
        return true
    end
    GodSystemNetwork.failedCommands = (GodSystemNetwork.failedCommands or 0) + 1
    GodSystemNetwork.lastSendFailedCommand = command
    if keyCommand then
        clearPendingOperation("sendFailed")
    end
    return false
end

-- Runtime services outside this file use the network bridge for authoritative
-- actions. Keep a single public entry point so they receive the same operation
-- IDs, retry protection and pending-command guard as the built-in wrappers.
GodSystemNetwork.send = send

function GodSystemNetwork.requestState(force)
    local t = nowMs()
    checkPendingTimeout()
    if pendingKeyCommand then
        GodSystemNetwork.lastRefreshSkippedReason = "pendingKeyCommand"
        return false
    end
    if GodSystemNetwork.isTimedActionBusy(player()) then
        GodSystemNetwork.lastRefreshSkippedReason = "inventoryInteraction"
        return false
    end
    if not force and t - lastStateRequestMs < STATE_THROTTLE_MS then return false end
    lastStateRequestMs = t
    if not sentHello then
        GodSystemNetwork.pendingState = true
        GodSystemNetwork.hello()
        return false
    end
    GodSystemNetwork.sendKillSync(true)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(player())
    end
    local data = GodSystemApp.services.runtime and GodSystemApp.services.runtime.getData and GodSystemApp.services.runtime.getData() or nil
    local stats = data and data.stats or {}
    return send((Protocol.C2S and Protocol.C2S.Refresh) or "refresh", { clientMoveDistance = stats.moveDistance or 0 })
end

function GodSystemNetwork.requestBackgroundState()
    local t = nowMs()
    checkPendingTimeout()
    if nextBackgroundSyncMs <= 0 then
        nextBackgroundSyncMs = t + BACKGROUND_SYNC_MS
        return false
    end
    if t < nextBackgroundSyncMs then
        return false
    end
    if GodSystemNetwork.pendingState then
        return false
    end
    if pendingKeyCommand then
        GodSystemNetwork.lastRefreshSkippedReason = "pendingKeyCommand"
        return false
    end
    if GodSystemNetwork.isInventoryInteractionBusy(player()) then
        GodSystemNetwork.lastRefreshSkippedReason = "inventoryInteraction"
        nextBackgroundSyncMs = t + BACKGROUND_BUSY_RETRY_MS
        return false
    end
    nextBackgroundSyncMs = t + BACKGROUND_SYNC_MS
    GodSystemNetwork.sendKillSync(true)
    return GodSystemNetwork.requestState(true)
end

function GodSystemNetwork.syncExpiredTasks()
    local data = GodSystemApp.services.runtime and GodSystemApp.services.runtime.getData and GodSystemApp.services.runtime.getData() or nil
    local tasks = data and data.tasks or {}
    for i = 1, #tasks do
        local task = tasks[i]
        local id = task and task.taskId
        if task and task.status == "active" and id and GodSystemApp.services.runtime.isTaskExpired and GodSystemApp.services.runtime.isTaskExpired(task) and not GodSystemApp.services.runtime.isTaskComplete(task) and not reportedTimeoutTasks[id] then
            if task.kind == "moveDistance" and GodSystemApp.services.runtime.updateMoveDistance then
                GodSystemApp.services.runtime.updateMoveDistance(player())
            end
            local sent = send("task", {
                action = "claim",
                taskId = id,
                clientProgress = GodSystemApp.services.runtime.getTaskProgress(task),
                clientExpired = true,
            })
            if sent then
                reportedTimeoutTasks[id] = true
            end
        end
    end
end

function GodSystemNetwork.isStateReady()
    return GodSystemNetwork.hasServerState == true
end

local function requestRefresh()
    if pendingRefresh then return end
    pendingRefresh = true
    Events.OnTick.Remove(GodSystemNetwork.refreshOnTick)
    Events.OnTick.Add(GodSystemNetwork.refreshOnTick)
end

local function readClientKills(p)
    if not p then return nil end
    local methods = { "getZombieKills", "getZombieKillsTotal", "getNumKills", "getKills" }
    for i = 1, #methods do
        local fn = p[methods[i]]
        if type(fn) == "function" then
            local ok, value = pcall(fn, p)
            value = ok and tonumber(value) or nil
            if value ~= nil then return math.max(0, math.floor(value)) end
        end
    end
    return nil
end

function GodSystemNetwork.sendKillSync(force)
    local p = player()
    if not p then return end
    local kills = readClientKills(p)
    if kills == nil then return end

    if lastSentKills == nil then
        lastSentKills = kills
        lastObservedKills = kills
        send("syncKills", { clientKills = kills })
        return
    end

    if lastObservedKills == nil then
        lastObservedKills = lastSentKills
    end
    if kills >= lastObservedKills then
        local observedDelta = kills - lastObservedKills
        if observedDelta > 0 then
            pendingKillDelta = (pendingKillDelta or 0) + observedDelta
            if GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateKillTaskProgress then
                GodSystemApp.services.runtime.updateKillTaskProgress(observedDelta, lastObservedKills)
            end
        end
        lastObservedKills = kills
    end

    if kills < lastSentKills then
        if (pendingKillDelta or 0) > 0 then
            send("syncKills", { clientKills = lastSentKills + pendingKillDelta })
            pendingKillDelta = 0
        end
        lastSentKills = kills
        lastObservedKills = kills
        send("syncKills", { clientKills = kills })
        return
    end

    local delta = pendingKillDelta or (kills - lastSentKills)
    if delta <= 0 then
        return
    end
    if force or delta >= KILL_SYNC_THRESHOLD then
        lastSentKills = lastSentKills + delta
        pendingKillDelta = 0
        send("syncKills", { clientKills = lastSentKills })
    end
end

function GodSystemNetwork.refreshOnTick()
    Events.OnTick.Remove(GodSystemNetwork.refreshOnTick)
    pendingRefresh = false
    if GodSystemUI and GodSystemUI.window and GodSystemUI.window.getIsVisible and GodSystemUI.window:getIsVisible() then
        GodSystemUI.window.waitingForServerState = false
        GodSystemUI.window.lastNetworkStateSerial = GodSystemNetwork.stateSerial or 0
        GodSystemUI.window:populateList()
    end
    if GodSystemUI and GodSystemUI.shopHiddenWindow and GodSystemUI.shopHiddenWindow.getIsVisible and GodSystemUI.shopHiddenWindow:getIsVisible() then
        GodSystemUI.shopHiddenWindow:onServerStateChanged()
    end
    if GodSystemUI and GodSystemUI.taskTracker and GodSystemUI.taskTracker.populateTasks then
        GodSystemUI.taskTracker:populateTasks()
    end
end

function GodSystemNetwork.helloRetryOnTick()
    if sentHello then
        Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
        pendingHelloTick = false
        return
    end
    GodSystemNetwork.hello()
end

function GodSystemNetwork.send(command, args)
    return send(command, args)
end

function GodSystemNetwork.getDiagnostics()
    checkPendingTimeout()
    local pendingElapsedMs = 0
    if pendingKeyCommand and pendingOperationStartedMs > 0 then
        pendingElapsedMs = math.max(0, nowMs() - pendingOperationStartedMs)
    end
    return {
        isMultiplayer = GodSystemNetwork.isMultiplayer == true,
        hasServerState = GodSystemNetwork.hasServerState == true,
        pendingState = GodSystemNetwork.pendingState == true,
        pendingCommand = pendingKeyCommand or GodSystemNetwork.pendingCommand,
        pendingOperationId = pendingOperationId or GodSystemNetwork.pendingOperationId,
        pendingElapsedMs = pendingElapsedMs,
        pendingTimeoutMs = KEY_COMMAND_TIMEOUT_MS,
        pendingTimeouts = GodSystemNetwork.pendingTimeouts or 0,
        lastPendingTimeoutCommand = GodSystemNetwork.lastPendingTimeoutCommand,
        lastPendingClearReason = GodSystemNetwork.lastPendingClearReason,
        stateSerial = GodSystemNetwork.stateSerial or 0,
        sentCommands = GodSystemNetwork.sentCommands or 0,
        failedCommands = GodSystemNetwork.failedCommands or 0,
        receivedStates = GodSystemNetwork.receivedStates or 0,
        lastSentCommand = GodSystemNetwork.lastSentCommand,
        lastResultOk = GodSystemNetwork.lastResultOk,
        lastResultMessage = GodSystemNetwork.lastResultMessage,
        lastError = GodSystemNetwork.lastError,
        lastNotifyCode = GodSystemNetwork.lastNotifyCode,
        lastStateAtMs = GodSystemNetwork.lastStateAtMs,
        lastSentAtMs = GodSystemNetwork.lastSentAtMs,
        nextBackgroundSyncMs = nextBackgroundSyncMs,
        lastRefreshSkippedReason = GodSystemNetwork.lastRefreshSkippedReason,
    }
end

function GodSystemNetwork.hello()
    if sentHello then return end
    local p = player()
    if not p then
        GodSystemNetwork.pendingState = true
        if not pendingHelloTick then
            pendingHelloTick = true
            Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
            Events.OnTick.Add(GodSystemNetwork.helloRetryOnTick)
        end
        return
    end
    if send((Protocol.C2S and Protocol.C2S.Hello) or "hello", { v = 1 }) then
        sentHello = true
        GodSystemNetwork.pendingState = true
        nextBackgroundSyncMs = nowMs() + BACKGROUND_SYNC_MS
        Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
        pendingHelloTick = false
        GodSystemNetwork.sendKillSync(true)
        local rangeService = GodSystemApp.getService and GodSystemApp.getService("rangeRecycle") or nil
        if rangeService and rangeService.syncProfile then rangeService:syncProfile(0) end
    elseif not pendingHelloTick then
        pendingHelloTick = true
        Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
        Events.OnTick.Add(GodSystemNetwork.helloRetryOnTick)
    end
end

local function OnServerCommand(module, command, args)
    if module ~= MODULE then return end
    if command == ((Protocol.S2C and Protocol.S2C.Teleport) or "teleport") then
        handleTeleportPayload(args or {})
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.RuntimeConfig) or "runtimeConfig") then
        if args and args.snapshot and GodSystemApp.services.runtime.applyRuntimeConfigSnapshot then
            GodSystemApp.services.runtime.applyRuntimeConfigSnapshot(args.snapshot)
            BACKGROUND_SYNC_MS = Protocol.BackgroundSyncMs or BACKGROUND_SYNC_MS
            requestRefresh()
        end
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.EconomySnapshot) or "economySnapshot") then
        if args and args.snapshot and GodSystemApp.services.runtime.applyEconomySnapshot then
            GodSystemApp.services.runtime.applyEconomySnapshot(args.snapshot)
            local service = GodSystemApp.getService and GodSystemApp.getService("itemConfig") or nil
            if service and service.handleChanged then service:handleChanged() end
            requestRefresh()
        end
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.EconomyDelta) or "economyDelta") then
        if GodSystemApp.services.runtime.applyEconomyDelta then
            GodSystemApp.services.runtime.applyEconomyDelta(args or {})
            local service = GodSystemApp.getService and GodSystemApp.getService("itemConfig") or nil
            if service and service.handleChanged then service:handleChanged() end
            requestRefresh()
        end
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.ItemConfigDetails) or "itemConfigDetails") then
        local service = GodSystemApp.getService and GodSystemApp.getService("itemConfig") or nil
        if service and service.handleDetails then service:handleDetails(args or {}) end
        requestRefresh()
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.RangeRecycleProgress) or "rangeRecycleProgress") then
        local service = GodSystemApp.getService and GodSystemApp.getService("rangeRecycle") or nil
        if service and service.handleProgress then service:handleProgress(args or {}) end
        requestRefresh()
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.RangeFilterSnapshot) or "rangeFilterSnapshot")
        or command == ((Protocol.S2C and Protocol.S2C.RangeFilterDeltaAck) or "rangeFilterDeltaAck")
        or command == ((Protocol.S2C and Protocol.S2C.RangeFilterSyncAck) or "rangeFilterSyncAck") then
        local service = GodSystemApp.getService and GodSystemApp.getService("rangeRecycle") or nil
        if service and service.handleFilterAck and args and args.snapshot then
            service:handleFilterAck(args.snapshot, args.ready, args.syncId)
        elseif service and service.handleFilter and args and args.snapshot then
            service:handleFilter(args.snapshot, args.ready)
        end
        if command == ((Protocol.S2C and Protocol.S2C.RangeFilterDeltaAck) or "rangeFilterDeltaAck")
            and args and args.ok == false then
            if service and service.syncProfile then service:syncProfile(0) end
            local message = resultMessagePayload(args)
            if message ~= "" then notify(message) end
        end
        requestRefresh()
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.State) or "state") then
        GodSystemApp.services.runtime.serverAdmin = args and args.admin == true
        if args and type(args.data) == "table" then
            args.data = mergeLocalTaskProgress(args.data)
            GodSystemApp.services.runtime.data = args.data
        end
        GodSystemNetwork.hasServerState = true
        GodSystemNetwork.pendingState = false
        GodSystemNetwork.stateSerial = (GodSystemNetwork.stateSerial or 0) + 1
        GodSystemNetwork.receivedStates = (GodSystemNetwork.receivedStates or 0) + 1
        GodSystemNetwork.lastStateAtMs = nowMs()
        requestRefresh()
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.Notify) or "notify") or command == ((Protocol.S2C and Protocol.S2C.Error) or "error") then
        if args and args.code then
            GodSystemNetwork.lastNotifyCode = tostring(args.code)
        end
        if command == ((Protocol.S2C and Protocol.S2C.Error) or "error") then
            GodSystemNetwork.lastError = args and args.code or "ServerCommandFailed"
        end
        notifyPayload(args)
        if command == ((Protocol.S2C and Protocol.S2C.Error) or "error") then
            GodSystemNetwork.pendingState = false
            clearPendingOperation("error")
            requestRefresh()
        end
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.LotteryResult) or "lotteryResult") then
        if GodSystemLotteryContext and GodSystemLotteryContext.handleResult then
            GodSystemLotteryContext.handleResult(args or {})
        end
        return
    end
    if command == ((Protocol.S2C and Protocol.S2C.Result) or "result") then
        local rangeService = GodSystemApp.getService and GodSystemApp.getService("rangeRecycle") or nil
        local suppressResultNotification = rangeService and rangeService.handleResult
            and rangeService:handleResult(args or {}) == true
        suppressResultNotification = suppressResultNotification or (args and args.data and args.data.lottery == true)
        GodSystemNetwork.pendingState = false
        GodSystemNetwork.lastResultOk = args and args.ok == true
        GodSystemNetwork.lastResultMessage = resultMessagePayload(args)
        GodSystemNetwork.lastResultAtMs = nowMs()
        if not suppressResultNotification and GodSystemNetwork.lastResultMessage ~= "" then
            notify(GodSystemNetwork.lastResultMessage)
        end
        if args and args.ok == true and args.payload and args.payload.kind == "medicalService" then
            if GodSystemApp.services.runtime and GodSystemApp.services.runtime.applyMedicalServiceLocally then
                pcall(GodSystemApp.services.runtime.applyMedicalServiceLocally, args.payload.action, player())
            end
        end
        local resultOpId = args and (args.operationId or (args.data and (args.data.operationId or args.data.opId))
            or (args.payload and (args.payload.operationId or args.payload.opId))) or nil
        if resultOpId ~= nil and timedOutTransactionOperation
            and tostring(resultOpId) == tostring(timedOutTransactionOperation.opId) then
            timedOutTransactionOperation = nil
            timedOutAttributeOperation = nil
        end
        if resultOpId == nil or pendingOperationId == nil or tostring(resultOpId) == tostring(pendingOperationId) then
            clearPendingOperation("result")
        end
        return
    end
end

function GodSystemNetwork.onPlayerUpdate(p)
    if p and p.isLocalPlayer and not p:isLocalPlayer() then return end
    local currentMs = GodSystemScheduler.nowMs()
    if not GodSystemScheduler.due("client.mp.network.fast", 250, currentMs) then return end
    checkPendingTimeout()
    if GodSystemScheduler.due("client.mp.network.background", 1000, currentMs)
        and GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(p or player())
        GodSystemNetwork.syncExpiredTasks()
        GodSystemNetwork.updateAutoTaskClaim()
        GodSystemNetwork.updateBankAutoDeposit()
        GodSystemNetwork.updateBankInvestmentTime()
        GodSystemNetwork.sendKillSync(false)
        GodSystemNetwork.requestBackgroundState()
    end
end

local function currentGameHour()
    if GameTime and GameTime:getInstance() then
        return GameTime:getInstance():getWorldAgeHours()
    end
    return 0
end

function GodSystemNetwork.updateAutoTaskClaim()
    if pendingKeyCommand or not GodSystemApp.services.runtime or not GodSystemApp.services.runtime.getData then return end
    local data = GodSystemApp.services.runtime.getData()
    if data.autoTaskClaimEnabled ~= true then return end
    local nowHour = currentGameHour()
    local persistedHour = tonumber(data.lastAutoTaskClaimHour) or nowHour
    if lastAutoTaskClaimHour == nil or persistedHour > lastAutoTaskClaimHour then
        lastAutoTaskClaimHour = persistedHour
    end
    if nowHour < lastAutoTaskClaimHour then lastAutoTaskClaimHour = nowHour end
    if nowHour - lastAutoTaskClaimHour < 1 then return end
    if GodSystemApp.services.runtime.updateMoveDistance then GodSystemApp.services.runtime.updateMoveDistance(player()) end
    local claims = {}
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        local manualTurnIn = GodSystemApp.services.runtime.isTurnInTask
            and GodSystemApp.services.runtime.isTurnInTask(task) == true
        if task and task.status == "active" and not manualTurnIn and GodSystemApp.services.runtime.isTaskComplete(task) then
            claims[#claims + 1] = {
                taskId = task.taskId,
                clientProgress = GodSystemApp.services.runtime.getTaskProgress(task),
                clientExpired = GodSystemApp.services.runtime.isTaskExpired(task) == true,
            }
        end
    end
    if #claims <= 0 then
        lastAutoTaskClaimHour = nowHour
        data.lastAutoTaskClaimHour = nowHour
        return
    end
    if send("task", { action = "autoClaim", claims = claims, auto = true }) then
        lastAutoTaskClaimHour = nowHour
        data.lastAutoTaskClaimHour = nowHour
    end
end

function GodSystemNetwork.updateBankAutoDeposit()
    if pendingKeyCommand or not GodSystemApp.services.runtime or not GodSystemApp.services.runtime.getData then return end
    local data = GodSystemApp.services.runtime.getData()
    local bank = data.bank or {}
    if bank.autoDepositEnabled ~= true then return end
    local nowHour = currentGameHour()
    local persistedHour = tonumber(bank.lastAutoDepositHour) or nowHour
    if lastAutoDepositHour == nil or persistedHour > lastAutoDepositHour then
        lastAutoDepositHour = persistedHour
    end
    if nowHour < lastAutoDepositHour then lastAutoDepositHour = nowHour end
    if nowHour - lastAutoDepositHour < 1 then return end
    local localCash = GodSystemApp.services.runtime.getCurrencyTotal and math.max(0, math.floor(tonumber(GodSystemApp.services.runtime.getCurrencyTotal()) or 0)) or 0
    if localCash <= 0 and math.max(0, math.floor(tonumber(data.balance) or 0)) <= 0 then
        lastAutoDepositHour = nowHour
        bank.lastAutoDepositHour = nowHour
        return
    end
    if send("bank", { action = "depositAllCash", auto = true }) then
        lastAutoDepositHour = nowHour
        bank.lastAutoDepositHour = nowHour
    end
end

function GodSystemNetwork.updateBankInvestmentTime()
    if pendingKeyCommand or not GodSystemApp.services.runtime or not GodSystemApp.services.runtime.getData then return end
    local data = GodSystemApp.services.runtime.getData()
    local bank = data.bank or {}
    local active = false
    for _, account in pairs(bank.investments or {}) do
        if math.max(0, tonumber(account and account.balance) or 0) > 0 then
            active = true
            break
        end
    end
    local nowHour = currentGameHour()
    if not active then
        investmentRuntimeHour = nowHour
        investmentWasActive = false
        return
    end
    if not investmentWasActive or investmentRuntimeHour == nil then
        investmentRuntimeHour = nowHour
        investmentWasActive = true
        return
    end
    if nowHour < investmentRuntimeHour then
        investmentRuntimeHour = nowHour
        return
    end
    local elapsedHours = math.floor(nowHour - investmentRuntimeHour)
    if elapsedHours < 1 then return end
    if send("bank", { action = "syncInvestmentHours", hours = elapsedHours, auto = true }) then
        investmentRuntimeHour = investmentRuntimeHour + elapsedHours
    end
end

function GodSystemNetwork.onPlayerDeath(p)
    if p and p.isLocalPlayer and not p:isLocalPlayer() then return end
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(p or player())
    end
    if (pendingKillDelta or 0) > 0 and lastSentKills ~= nil then
        send("syncKills", { clientKills = lastSentKills + pendingKillDelta })
        lastSentKills = lastSentKills + pendingKillDelta
        pendingKillDelta = 0
    end
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.normalizeActiveKillTasks then
        GodSystemApp.services.runtime.normalizeActiveKillTasks(lastObservedKills or lastSentKills or 0)
    end
    send((Protocol.C2S and Protocol.C2S.Death) or "death", {})
end

Events.OnServerCommand.Remove(OnServerCommand)
Events.OnServerCommand.Add(OnServerCommand)
if GodSystemApp.services.runtime then
    if Events.OnInitGlobalModData and GodSystemApp.services.runtime.onInitGlobalModData then
        Events.OnInitGlobalModData.Remove(GodSystemApp.services.runtime.onInitGlobalModData)
    end
    if Events.OnGameStart and GodSystemApp.services.runtime.onGameStart then
        Events.OnGameStart.Remove(GodSystemApp.services.runtime.onGameStart)
    end
    if Events.OnPlayerUpdate and GodSystemApp.services.runtime.onPlayerUpdate then
        Events.OnPlayerUpdate.Remove(GodSystemApp.services.runtime.onPlayerUpdate)
    end
end
Events.OnGameStart.Remove(GodSystemNetwork.hello)
Events.OnGameStart.Add(GodSystemNetwork.hello)
Events.OnCreatePlayer.Remove(GodSystemNetwork.hello)
Events.OnCreatePlayer.Add(GodSystemNetwork.hello)
Events.OnTick.Remove(GodSystemNetwork.helloRetryOnTick)
Events.OnTick.Add(GodSystemNetwork.helloRetryOnTick)
if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Remove(GodSystemNetwork.onPlayerUpdate)
    Events.OnPlayerUpdate.Add(GodSystemNetwork.onPlayerUpdate)
end
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Remove(GodSystemNetwork.onPlayerDeath)
    Events.OnPlayerDeath.Add(GodSystemNetwork.onPlayerDeath)
end
if Events.OnConnected then
    Events.OnConnected.Remove(GodSystemNetwork.resetSessionRuntime)
    Events.OnConnected.Add(GodSystemNetwork.resetSessionRuntime)
    Events.OnConnected.Remove(GodSystemNetwork.resetInvestmentRuntime)
    Events.OnConnected.Add(GodSystemNetwork.resetInvestmentRuntime)
end
if Events.OnDisconnect then
    Events.OnDisconnect.Remove(GodSystemNetwork.resetSessionRuntime)
    Events.OnDisconnect.Add(GodSystemNetwork.resetSessionRuntime)
    Events.OnDisconnect.Remove(GodSystemNetwork.resetInvestmentRuntime)
    Events.OnDisconnect.Add(GodSystemNetwork.resetInvestmentRuntime)
end

local original = {}

local function wrap(name, fn)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime[name] then
        original[name] = GodSystemApp.services.runtime[name]
        GodSystemApp.services.runtime[name] = fn
    end
end

wrap("save", function()
    return true
end)

wrap("getCurrencyTotal", function()
    local data = GodSystemApp.services.runtime and GodSystemApp.services.runtime.getData and GodSystemApp.services.runtime.getData() or nil
    if data and data.balance ~= nil then
        return math.max(0, math.floor(tonumber(data.balance) or 0))
    end
    if original.getCurrencyTotal then
        local ok, value = pcall(original.getCurrencyTotal)
        if ok and value ~= nil then
            return math.max(0, math.floor(tonumber(value) or 0))
        end
    end
    return 0
end)

wrap("getCurrencyDisplayTotal", function()
    local data = GodSystemApp.services.runtime and GodSystemApp.services.runtime.getData and GodSystemApp.services.runtime.getData() or nil
    return data and math.max(0, math.floor(tonumber(data.balance) or 0)) or 0
end)

wrap("canAfford", function(cost)
    if GodSystemApp.services.runtime.getSpendableBalance then
        return GodSystemApp.services.runtime.getSpendableBalance() >= math.max(0, math.floor(tonumber(cost) or 0))
    end
    return GodSystemApp.services.runtime.getCurrencyTotal() >= math.max(0, math.floor(tonumber(cost) or 0))
end)

wrap("ensureCurrencyInitialized", function()
    return true
end)

wrap("generateDailyTasks", function()
    if not sentHello then
        GodSystemNetwork.hello()
    end
    return true
end)

wrap("updateKillRewards", function()
end)

wrap("updateTaskTimeouts", function()
end)

wrap("updateHomeSafeZone", function()
end)

wrap("buyShopItem", function(shopItem, quantity)
    if not shopItem then return false end
    local id = shopItem.id
    if not id and shopItem.fullType then id = tostring(shopItem.fullType) end
    return send("buyShop", { id = id, quantity = quantity or 1 })
end)

wrap("recycleInventoryItems", function(fullType, count)
    return send("recycle", { fullType = fullType, count = count or 1 })
end)

wrap("recycleSelectedItems", function(mode, itemIds, allowDestroyContents, containerContentSignatures, clientSkipped)
    return send("recycle", {
        mode = mode,
        itemIds = itemIds,
        allowDestroyContents = allowDestroyContents == true,
        containerContentSignatures = containerContentSignatures,
        clientSkipped = math.min(10000, math.max(0, math.floor(tonumber(clientSkipped) or 0))),
    })
end)

wrap("listOnlyAutoShopItem", function(fullType, itemId)
    return send((Protocol.C2S and Protocol.C2S.ListOnlyAutoShop) or "listOnlyAutoShop", { fullType = fullType, itemId = tostring(itemId or "") })
end)

wrap("upgradeSystem", function(upgradeType)
    return send("upgradeSystem", { upgradeType = upgradeType })
end)

wrap("refreshCarryCapacity", function()
    return send((Protocol.C2S and Protocol.C2S.RefreshCarryCapacity) or "refreshCarryCapacity", {})
end)

wrap("performMedicalService", function(action)
    return send((Protocol.C2S and Protocol.C2S.MedicalService) or "medicalService", { action = action })
end)

wrap("acceptTask", function(task)
    if not task then return false end
    local p = player()
    if task.kind == "moveDistance" and GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(p)
    end
    local data = GodSystemApp.services.runtime and GodSystemApp.services.runtime.getData and GodSystemApp.services.runtime.getData() or nil
    local stats = data and data.stats or {}
    return send("task", {
        action = "accept",
        taskId = task.taskId,
        clientKills = readClientKills(p),
        clientMoveDistance = stats.moveDistance or 0,
    })
end)

wrap("claimTask", function(task)
    if not task then return false end
    if task.kind == "moveDistance" and GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(player())
    end
    return send("task", {
        action = "claim",
        taskId = task.taskId,
        clientProgress = GodSystemApp.services.runtime.getTaskProgress(task),
        clientExpired = GodSystemApp.services.runtime.isTaskExpired(task) == true,
    })
end)

wrap("submitTurnInTask", function(task, itemIds)
    if not task then return false end
    return send("task", {
        action = "submitTurnIn",
        taskId = task.taskId,
        itemIds = itemIds,
    })
end)

wrap("toggleAutoTaskClaim", function()
    return send("task", { action = "toggleAutoClaim" })
end)

wrap("abandonTask", function(task)
    if not task then return false end
    if task.kind == "moveDistance" and GodSystemApp.services.runtime and GodSystemApp.services.runtime.updateMoveDistance then
        GodSystemApp.services.runtime.updateMoveDistance(player())
    end
    return send("task", {
        action = "abandon",
        taskId = task.taskId,
        clientProgress = GodSystemApp.services.runtime.getTaskProgress(task),
    })
end)

wrap("refreshOpenTasks", function()
    return send("refreshTasks", {})
end)

wrap("performHomeAction", function(action, index)
    return send("home", { action = action, index = index })
end)

wrap("performTraitModification", function(action, traitType)
    return send("trait", { action = action, traitType = traitType })
end)

wrap("performBankAction", function(action, amount, termId, entryId)
    return send("bank", { action = action, amount = amount, termId = termId, entryId = entryId })
end)

wrap("consolidateCurrency", function()
    return send((Protocol.C2S and Protocol.C2S.ConsolidateCurrency) or "consolidateCurrency", {})
end)

wrap("toggleRecycleUnlockMode", function()
    return send("toggleRecycleMode", {})
end)

wrap("setShopItemHidden", function(variantKey, hidden)
    return send((Protocol.C2S and Protocol.C2S.SetShopItemHidden) or "setShopItemHidden", { variantKey = variantKey, hidden = hidden == true })
end)

wrap("setShopItemsHidden", function(variantKeys, hidden)
    local keys, seen = {}, {}
    for i = 1, #(variantKeys or {}) do
        local key = tostring(variantKeys[i] or "")
        if key ~= "" and not seen[key] then seen[key] = true; keys[#keys + 1] = key end
    end
    table.sort(keys)
    if #keys == 0 or #keys > 500 then return false end
    return send((Protocol.C2S and Protocol.C2S.SetShopItemsHidden) or "setShopItemsHidden", {
        variantKeys = keys,
        hidden = hidden == true,
    })
end)

wrap("deleteShopItem", function(variantKey)
    return send((Protocol.C2S and Protocol.C2S.DeleteShopItem) or "deleteShopItem", { variantKey = variantKey })
end)

wrap("debugAddPoints", function()
    return send("debugGrant", { code = "12130" })
end)

function GodSystemNetwork.requestDiagnostics()
    return send((Protocol.C2S and Protocol.C2S.Diagnostics) or "diagnostics", {})
end
