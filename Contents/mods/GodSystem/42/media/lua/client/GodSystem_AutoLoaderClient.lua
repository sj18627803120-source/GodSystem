require "GodSystem_Core"
require "GodSystem_RuntimeMode"
require "GodSystem_AutoLoader"
require "TimedActions/ISGodSystemAutoLoaderDepositAction"
require "TimedActions/ISGodSystemAutoLoaderPostReloadAction"
require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISTimedActionQueue"

GodSystemAutoLoaderClient = GodSystemAutoLoaderClient or {}

local Client = GodSystemAutoLoaderClient
local AutoLoader = GodSystemAutoLoader
local MODULE = "GodSystemAutoLoader"

Client.states = Client.states or {}
Client.queuedSessions = Client.queuedSessions or {}
Client.operationCounter = Client.operationCounter or 0

local CODE_KEYS = {
    DepositStarted = "AutoLoader_DepositStarted",
    DepositComplete = "AutoLoader_DepositComplete",
    DepositInterrupted = "AutoLoader_DepositInterrupted",
    DepositFailed = "AutoLoader_Error_Generic",
    nothingToDeposit = "AutoLoader_NothingToDeposit",
    NothingToDeposit = "AutoLoader_NothingToDeposit",
    NotCarried = "AutoLoader_Error_NotCarried",
    notCarried = "AutoLoader_Error_NotCarried",
    FillSuccess = "AutoLoader_FillSuccess",
    FillInsufficient = "AutoLoader_FillInsufficient",
    NoCompatibleMagazine = "AutoLoader_NoCompatibleMagazine",
    WithdrawSuccess = "AutoLoader_WithdrawSuccess",
    Unavailable = "AutoLoader_Unavailable",
    unavailable = "AutoLoader_Unavailable",
    LimitReached = "AutoLoader_LimitReached",
    OperationPending = "AutoLoader_OperationPending",
    OperationUnknown = "AutoLoader_OperationUnknown",
    OperationMismatch = "AutoLoader_OperationMismatch",
    OperationInvalid = "AutoLoader_OperationInvalid",
    sessionExpired = "AutoLoader_SessionExpired",
    sessionMissing = "AutoLoader_SessionExpired",
    InternalError = "AutoLoader_Error_Generic",
}

function Client.text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

function Client.codeKey(code)
    return CODE_KEYS[tostring(code or "")] or "AutoLoader_Error_Generic"
end

function Client.isMultiplayer()
    return isClient and isClient() == true
end

function Client.format(template, args)
    local result = tostring(template or "")
    for index = 1, #(args or {}) do result = result:gsub("{" .. tostring(index) .. "}", tostring(args[index])) end
    return result
end

function Client.notify(code, payload)
    if not GodSystem or not GodSystem.notify then return end
    payload = type(payload) == "table" and payload or {}
    local key = Client.codeKey(code)
    local args = {}
    if key == "AutoLoader_DepositStarted" then args = { payload.total or 0, payload.batchCount or 0 }
    elseif key == "AutoLoader_DepositComplete" then args = { payload.stored or 0, payload.skipped or 0, payload.failed or 0 }
    elseif key == "AutoLoader_FillSuccess" then args = { payload.rounds or 0, payload.magazines or 0 }
    elseif key == "AutoLoader_FillInsufficient" then args = { payload.rounds or 0, payload.remainingNeed or 0 }
    elseif key == "AutoLoader_WithdrawSuccess" then args = { payload.created or 0 }
    elseif key == "AutoLoader_LimitReached" then args = { AutoLoader.MaxLoaders, AutoLoader.MaxMagazines }
    elseif key == "AutoLoader_Error_Generic" then args = { tostring(code or "unknown") } end
    GodSystem.notify(Client.format(Client.text(key, tostring(code or "")), args))
end

function Client.player(playerNum)
    if getSpecificPlayer and playerNum ~= nil then
        local ok, player = pcall(getSpecificPlayer, playerNum)
        if ok and player then return player end
    end
    return getPlayer and getPlayer() or nil
end

function Client.makeOperationId(player)
    Client.operationCounter = (Client.operationCounter or 0) + 1
    local now = AutoLoader.nowMs()
    local playerNum = AutoLoader.safeCall(player, "getPlayerNum", 0)
    return table.concat({ "gsa", tostring(now), tostring(Client.operationCounter), tostring(playerNum or 0) }, "-")
end

function Client.send(command, args, player)
    player = player or Client.player()
    if not player or not sendClientCommand then return false end
    local ok = pcall(sendClientCommand, player, MODULE, command, args or {})
    if ok then return true end
    return pcall(sendClientCommand, MODULE, command, args or {})
end

function Client.requestState(loader, playerNum)
    local player = Client.player(playerNum)
    local loaderId = AutoLoader.itemId(loader) or tostring(loader or "")
    if loaderId == "" then return false end
    if not Client.isMultiplayer() then
        local carried = AutoLoader.findCarriedItem(player, loaderId)
        local ok = AutoLoader.isLoader(carried)
        local state = ok and AutoLoader.stateFor(carried) or nil
        if ok then Client.states[loaderId] = state end
        if GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.onState then
            GodSystemAutoLoaderUI.onState(loaderId, state, ok, ok and nil or "NotCarried")
        end
        return ok
    end
    return Client.send("state", { loaderId = loaderId }, player)
end

function Client.handleResult(action, ok, code, payload, silent)
    action = tostring(action or "")
    payload = type(payload) == "table" and payload or {}
    if action == "startDeposit" and ok == true then
        Client.queueDeposit(payload)
    elseif action == "depositComplete" then
        Client.queuedSessions[tostring(payload.sessionId or "")] = nil
        Client.requestState(payload.loaderId)
    elseif action == "manualFill" or action == "withdraw" or action == "depositBatch" then
        Client.requestState(payload.loaderId or (GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.loaderId))
    elseif action == "postReload" and GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.loaderId then
        Client.requestState(GodSystemAutoLoaderUI.loaderId)
    end
    if silent ~= true then Client.notify(code, payload) end
    if GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.onResult then
        GodSystemAutoLoaderUI.onResult(action, ok == true, code, payload)
    end
end

function Client.startDeposit(loader, playerNum)
    local player = Client.player(playerNum)
    local loaderId = AutoLoader.itemId(loader) or tostring(loader or "")
    if loaderId == "" then return false end
    local opId = Client.makeOperationId(player)
    if Client.isMultiplayer() then
        return Client.send("startDeposit", { loaderId = loaderId, opId = opId }, player)
    end
    local payload, reason = AutoLoader.startDepositSession(player, loaderId, opId)
    if not payload then Client.handleResult("startDeposit", false, reason or "DepositFailed", {}, false) return false end
    Client.handleResult("startDeposit", true, "DepositStarted", payload, false)
    return Client.queuedSessions[tostring(payload.sessionId or "")] == true
end

function Client.manualFill(loader, playerNum)
    local player = Client.player(playerNum)
    local loaderId = AutoLoader.itemId(loader) or tostring(loader or "")
    if loaderId == "" then return false end
    if Client.isMultiplayer() then
        return Client.send("manualFill", { loaderId = loaderId, opId = Client.makeOperationId(player) }, player)
    end
    local carried = AutoLoader.findCarriedItem(player, loaderId)
    if not AutoLoader.isLoader(carried) then Client.handleResult("manualFill", false, "NotCarried", {}, false) return false end
    local stats = AutoLoader.fillMagazines(player, { carried }, AutoLoader.MaxMagazines)
    stats.loaderId = loaderId
    local code = "NoCompatibleMagazine"
    if stats.rounds > 0 and stats.remainingNeed <= 0 then code = "FillSuccess"
    elseif stats.rounds > 0 or stats.remainingNeed > 0 then code = "FillInsufficient" end
    local ok = stats.rounds > 0
    Client.handleResult("manualFill", ok, code, stats, false)
    return ok
end

function Client.withdraw(loader, fullType, count, playerNum)
    local player = Client.player(playerNum)
    local loaderId = AutoLoader.itemId(loader) or tostring(loader or "")
    count = math.max(1, math.min(500, math.floor(tonumber(count) or 100)))
    if loaderId == "" or tostring(fullType or "") == "" then return false end
    local args = {
        loaderId = loaderId,
        fullType = tostring(fullType),
        count = count,
        opId = Client.makeOperationId(player),
    }
    if Client.isMultiplayer() then return Client.send("withdraw", args, player) end
    local carried = AutoLoader.findCarriedItem(player, loaderId)
    if not AutoLoader.isLoader(carried) then Client.handleResult("withdraw", false, "NotCarried", {}, false) return false end
    local stats = AutoLoader.withdrawAmmo(player, carried, args.fullType, args.count)
    stats.loaderId = loaderId
    local ok = stats.created > 0
    local code = ok and "WithdrawSuccess" or (stats.reason == "unavailable" and "Unavailable" or stats.reason or "WithdrawFailed")
    Client.handleResult("withdraw", ok, code, stats, false)
    return ok
end

function Client.queueDeposit(payload)
    payload = type(payload) == "table" and payload or {}
    local sessionId = tostring(payload.sessionId or "")
    if sessionId == "" or Client.queuedSessions[sessionId] then return false end
    local player = Client.player()
    if not player then return false end
    Client.queuedSessions[sessionId] = true
    for batchIndex = 1, math.max(1, math.floor(tonumber(payload.batchCount) or 1)) do
        ISTimedActionQueue.add(ISGodSystemAutoLoaderDepositAction:new(
            player,
            payload.loaderId,
            sessionId,
            batchIndex,
            payload.batchCount,
            payload.total
        ))
    end
    return true
end

function Client.onDepositInterrupted(loaderId, sessionId)
    Client.queuedSessions[tostring(sessionId or "")] = nil
    Client.notify("DepositInterrupted", {})
    Client.requestState(tostring(loaderId or ""))
end

function Client.completeLocalDepositBatch(player, sessionId, batchIndex)
    if Client.isMultiplayer() then return false end
    local _, reason, _, replayed, aggregate = AutoLoader.completeDepositBatch(player, sessionId, batchIndex)
    if reason then
        Client.handleResult("depositBatch", false, reason, { sessionId = tostring(sessionId or "") }, false)
        return false
    end
    if aggregate and aggregate.finished and not replayed then
        Client.handleResult("depositComplete", aggregate.stored > 0, "DepositComplete", aggregate, false)
    end
    return true
end

function Client.completeLocalPostReload(player)
    if Client.isMultiplayer() then return false end
    local loaders, loaderLimited = AutoLoader.getLoaders(player, AutoLoader.MaxLoaders)
    if #loaders <= 0 then return true end
    local stats = AutoLoader.fillMagazines(player, loaders, AutoLoader.MaxMagazines)
    stats.loaderLimited = stats.loaderLimited or loaderLimited
    local limited = stats.loaderLimited or stats.magazineLimited
    local silent = stats.rounds > 0 and stats.remainingNeed <= 0 and not limited
    local code = "FillSuccess"
    if limited then code = "LimitReached"; silent = false
    elseif stats.need <= 0 then code = "NoCompatibleMagazine"; silent = true
    elseif stats.remainingNeed > 0 then code = "FillInsufficient"; silent = false end
    for index = 1, #loaders do
        local loaderId = AutoLoader.itemId(loaders[index])
        if loaderId then Client.states[loaderId] = AutoLoader.stateFor(loaders[index]) end
    end
    Client.handleResult("postReload", true, code, stats, silent)
    return true
end

function Client.onServerCommand(module, command, args)
    if module ~= MODULE then return end
    args = type(args) == "table" and args or {}
    if command == "state" then
        local loaderId = tostring(args.loaderId or (args.state and args.state.loaderId) or "")
        if args.ok == true and loaderId ~= "" then Client.states[loaderId] = args.state end
        if GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.onState then GodSystemAutoLoaderUI.onState(loaderId, args.state, args.ok == true, args.code) end
        return
    end
    if command ~= "result" then return end
    Client.handleResult(args.action, args.ok == true, args.code, args.payload, args.silent == true)
end

function Client.queueLength(player)
    local queue = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(player) or nil
    if not queue or type(queue.queue) ~= "table" then return 0 end
    return #queue.queue
end

function Client.installReloadHook()
    if not ISReloadWeaponAction or type(ISReloadWeaponAction.BeginAutomaticReload) ~= "function" then return false end
    if ISReloadWeaponAction.BeginAutomaticReload == Client.reloadWrapper then return true end
    Client.originalBeginAutomaticReload = ISReloadWeaponAction.BeginAutomaticReload
    Client.reloadWrapper = function(player, gun)
        local before = Client.queueLength(player)
        local result = Client.originalBeginAutomaticReload(player, gun)
        local after = Client.queueLength(player)
        if after > before then
            local loaders = AutoLoader.getLoaders(player, 1)
            if #loaders > 0 then ISTimedActionQueue.add(ISGodSystemAutoLoaderPostReloadAction:new(player, Client.makeOperationId(player))) end
        end
        return result
    end
    ISReloadWeaponAction.BeginAutomaticReload = Client.reloadWrapper
    return true
end

function Client.clear()
    Client.states = {}
    Client.queuedSessions = {}
end

if GodSystemRuntimeMode.legacyBusinessEnabled() then
    Client.installReloadHook()
    if Events.OnGameStart then
        Events.OnGameStart.Remove(Client.installReloadHook)
        Events.OnGameStart.Add(Client.installReloadHook)
    end
    if Events.OnServerCommand then
        Events.OnServerCommand.Remove(Client.onServerCommand)
        Events.OnServerCommand.Add(Client.onServerCommand)
    end
    if Events.OnDisconnect then
        Events.OnDisconnect.Remove(Client.clear)
        Events.OnDisconnect.Add(Client.clear)
    end
    if Events.OnMainMenuEnter then
        Events.OnMainMenuEnter.Remove(Client.clear)
        Events.OnMainMenuEnter.Add(Client.clear)
    end
end

return Client
