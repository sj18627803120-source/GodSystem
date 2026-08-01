require "GodSystem_PersonalStorage"
require "GodSystem_AdminConfig"
require "GodSystem_StorageBridge"

GodSystemPersonalStorageServer = GodSystemPersonalStorageServer or {}

local Server = GodSystemPersonalStorageServer
local Personal = GodSystemPersonalStorage
local Bridge = GodSystemStorageBridge.create({
    personal = GodSystemPersonalStorage,
    manager = GodSystemStorageManager,
})
local MODULE = "GodSystemPersonalStorage"

Server.moduleId = "personalStorageServer"
Server.lastError = nil
Server.lastOperationId = nil

local function send(player, command, args)
    sendServerCommand(player, MODULE, command, args or {})
end

local function enabled()
    return GodSystemAdminConfig.isFeatureEnabled("EnablePersonalStorage") ~= false
end

local function account(player)
    return GodSystemServer.personalStorageData(player)
end

local function storeFor(player)
    return Personal.normalizeData(account(player))
end

local function targetContainer(player, itemId)
    return GodSystemStorage.resolvePlayerContainer(player, itemId)
end

local function coreArgs(args)
    return {
        x = args.x or args.coreX,
        y = args.y or args.coreY,
        z = args.z or args.coreZ,
        coreObjectId = args.coreObjectId,
        coreToken = args.coreToken,
        networkId = args.networkId,
        allowRemote = args.allowRemote == true,
    }
end

local function sendState(player)
    local summary = Personal.summary(storeFor(player))
    send(player, "state", summary)
end

local function sendResult(player, command, outcome)
    outcome = type(outcome) == "table" and outcome or { ok = false, code = "invalidResult" }
    Server.lastOperationId = outcome.operationId
    if not outcome.ok then Server.lastError = outcome.code end
    send(player, "result", {
        command = command,
        ok = outcome.ok == true,
        code = outcome.code,
        data = outcome.data,
        operationId = outcome.operationId,
        moduleId = outcome.moduleId,
    })
    sendState(player)
end

local function batchResult(operationId, stats)
    return {
        ok = stats.success > 0 or stats.failed == 0,
        code = stats.failed > 0 and stats.success > 0 and "partial" or stats.failed > 0 and "failed" or "completed",
        data = stats,
        operationId = operationId,
        moduleId = Personal.moduleId,
    }
end

local function fingerprint(kind, values, suffix)
    local parts = { tostring(kind or "") }
    for i = 1, math.min(#(values or {}), 250) do parts[#parts + 1] = tostring(values[i] or "") end
    parts[#parts + 1] = tostring(suffix or "")
    return table.concat(parts, "|")
end

local Commands = {}

function Commands.state(player)
    sendState(player)
end

function Commands.details(player, args)
    local store = storeFor(player)
    send(player, "details", Personal.entries(store, args.groupKey, args.offset, args.limit))
end

function Commands.previewDeposit(player, args)
    local rows, simplified, failed = {}, {}, {}
    for i = 1, math.min(#(args.itemIds or {}), 250) do
        local itemId = tostring(args.itemIds[i] or "")
        local item = GodSystemServer.personalStorageFindItem(player, itemId)
        local created = Personal.createEntry(item)
        if created.ok then
            rows[#rows + 1] = {
                itemId = itemId,
                fullType = created.data.snapshot.fullType,
                name = created.data.snapshot.displayName,
                category = created.data.category,
                itemCount = created.data.itemCount,
                simplified = created.data.simplified,
                reasons = created.data.report.reasons,
            }
            if created.data.simplified then simplified[#simplified + 1] = rows[#rows] end
        else
            failed[#failed + 1] = { itemId = itemId, reason = created.code }
        end
    end
    send(player, "preview", {
        command = "previewDeposit",
        operationId = args.operationId,
        rows = rows,
        simplified = simplified,
        failed = failed,
        confirmRequired = #simplified > 0,
    })
end


function Commands.bridgePreview(player, args)
    local outcome = Bridge:previewPhysical(player, coreArgs(args), args)
    local rows = outcome.data and outcome.data.rows or {}
    local simplified = {}
    for i = 1, #rows do if rows[i].simplified then simplified[#simplified + 1] = rows[i] end end
    send(player, "preview", {
        command = "bridgePreview",
        operationId = args.operationId,
        ok = outcome.ok,
        code = outcome.code,
        rows = rows,
        simplified = simplified,
        confirmRequired = #simplified > 0,
    })
end

function Commands.deposit(player, args)
    local store = storeFor(player)
    local operationId = tostring(args.operationId or "")
    local operation, previous = Personal.beginOperation(store, operationId,
        fingerprint("depositBatch", args.itemIds, args.confirmSimplified == true))
    if previous then return sendResult(player, "deposit", previous) end
    local stats = { requested = 0, success = 0, skipped = 0, failed = 0, simplified = 0, rows = {} }
    for i = 1, math.min(#(args.itemIds or {}), 250) do
        stats.requested = stats.requested + 1
        local itemId = tostring(args.itemIds[i] or "")
        local item, source = GodSystemServer.personalStorageFindItem(player, itemId)
        local preview = Personal.createEntry(item)
        if preview.ok and preview.data.simplified and args.confirmSimplified ~= true then
            stats.skipped = stats.skipped + 1
            stats.rows[#stats.rows + 1] = { itemId = itemId, ok = false, reason = "confirmSimplified" }
        elseif not item or not source then
            stats.failed = stats.failed + 1
            stats.rows[#stats.rows + 1] = { itemId = itemId, ok = false, reason = "sourceChanged" }
        else
            local itemOperation = tostring(args.operationId or "") .. ":" .. tostring(i) .. ":" .. itemId
            local outcome = Personal.deposit(store, item, source, itemOperation)
            Personal.discardOperation(store, itemOperation)
            if outcome.ok then
                stats.success = stats.success + 1
                if outcome.data and outcome.data.simplified then stats.simplified = stats.simplified + 1 end
            elseif outcome.code == "capacityFull" or outcome.code == "protectedItem" then
                stats.skipped = stats.skipped + 1
            else
                stats.failed = stats.failed + 1
            end
            stats.rows[#stats.rows + 1] = { itemId = itemId, ok = outcome.ok, reason = outcome.code, data = outcome.data }
        end
    end
    sendResult(player, "deposit", Personal.finishOperation(store, operationId, batchResult(operationId, stats)))
end

function Commands.withdraw(player, args)
    local store = storeFor(player)
    local operationId = tostring(args.operationId or "")
    local operation, previous = Personal.beginOperation(store, operationId,
        fingerprint("withdrawBatch", args.entryIds, args.targetItemId))
    if previous then return sendResult(player, "withdraw", previous) end
    local target = targetContainer(player, args.targetItemId)
    if not target then
        return sendResult(player, "withdraw", Personal.finishOperation(store, operationId,
            { ok = false, code = "targetMissing", operationId = operationId, moduleId = Personal.moduleId }))
    end
    local stats = { requested = 0, success = 0, skipped = 0, failed = 0, rows = {} }
    for i = 1, math.min(#(args.entryIds or {}), 250) do
        stats.requested = stats.requested + 1
        local entryId = tostring(args.entryIds[i] or "")
        local itemOperation = tostring(args.operationId or "") .. ":" .. tostring(i) .. ":" .. entryId
        local outcome = Personal.withdraw(store, entryId, target, itemOperation)
        Personal.discardOperation(store, itemOperation)
        if outcome.ok then stats.success = stats.success + 1
        elseif outcome.code == "entryMissing" then stats.skipped = stats.skipped + 1
        else stats.failed = stats.failed + 1 end
        stats.rows[#stats.rows + 1] = { entryId = entryId, ok = outcome.ok, reason = outcome.code, data = outcome.data }
    end
    sendResult(player, "withdraw", Personal.finishOperation(store, operationId, batchResult(operationId, stats)))
end

function Commands.usePermit(player, args)
    local store = storeFor(player)
    local operationId = tostring(args.operationId or "")
    local operation, previous = Personal.beginOperation(store, operationId,
        fingerprint("permitUse", { args.itemId, args.category }))
    if previous then return sendResult(player, "usePermit", previous) end
    local permit, source = GodSystemServer.personalStorageFindItem(player, args.itemId)
    local itemOperation = operationId .. ":item"
    local outcome = Personal.consumePermit(store, permit, source, args.category, itemOperation)
    Personal.discardOperation(store, itemOperation)
    outcome.operationId = operationId
    sendResult(player, "usePermit", Personal.finishOperation(store, operationId, outcome))
end

function Commands.buyGeneral(player, args)
    local store = storeFor(player)
    local fingerprint = "buyGeneral|10000|10"
    local op, previous = Personal.beginOperation(store, args.operationId, fingerprint)
    if previous then return sendResult(player, "buyGeneral", previous) end
    local paid, receipt = GodSystemServer.personalStorageCharge(player, Personal.GeneralPurchaseCost)
    if not paid then
        return sendResult(player, "buyGeneral", Personal.finishOperation(store, args.operationId, {
            ok = false, code = "insufficientFunds", operationId = args.operationId, moduleId = Personal.moduleId,
        }))
    end
    local outcome = Personal.addGeneralCapacity(store, Personal.GeneralPurchaseCapacity)
    if not outcome.ok then
        GodSystemServer.personalStorageRefund(player, receipt)
        outcome.operationId = args.operationId
        return sendResult(player, "buyGeneral", Personal.finishOperation(store, args.operationId, outcome))
    end
    outcome.operationId = args.operationId
    GodSystemServer.personalStorageCommit(player, Personal.GeneralPurchaseCost, "PersonalStorageGeneralPurchased", {
        Personal.GeneralPurchaseCost, Personal.GeneralPurchaseCapacity,
    })
    sendResult(player, "buyGeneral", Personal.finishOperation(store, args.operationId, outcome))
end

function Commands.bridgeDeposit(player, args)
    sendResult(player, "bridgeDeposit", Bridge:physicalToPersonal(player, coreArgs(args), args,
        storeFor(player), args.operationId))
end

function Commands.bridgeWithdraw(player, args)
    sendResult(player, "bridgeWithdraw", Bridge:personalToPhysical(player, coreArgs(args), args,
        storeFor(player), args.operationId))
end

function Commands.health(player)
    local health = Personal.health(account(player))
    health.bridge = Bridge:health()
    send(player, "health", health)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= MODULE or not player then return end
    if not enabled() then
        sendResult(player, command, { ok = false, code = "disabled", operationId = args and args.operationId, moduleId = Personal.moduleId })
        return
    end
    local handler = Commands[command]
    if not handler then
        sendResult(player, command, { ok = false, code = "unknownCommand", operationId = args and args.operationId, moduleId = Personal.moduleId })
        return
    end
    handler(player, type(args) == "table" and args or {})
end)

return Server
