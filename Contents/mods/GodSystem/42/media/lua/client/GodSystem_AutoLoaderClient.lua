require "GodSystem_AutoLoader"
require "TimedActions/ISGodSystemAutoLoaderDepositAction"
require "TimedActions/ISGodSystemAutoLoaderPostReloadAction"
require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISTimedActionQueue"

GodSystemAutoLoaderClient = GodSystemAutoLoaderClient or {}

local Client = GodSystemAutoLoaderClient
local AutoLoader = GodSystemAutoLoader

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

function Client.format(template, args)
    local result = tostring(template or "")
    for index = 1, #(args or {}) do
        result = result:gsub("{" .. tostring(index) .. "}",
            tostring(args[index]))
    end
    return result
end

function Client.notify(code, payload)
    if not GodSystem or not GodSystem.notify then return end
    payload = type(payload) == "table" and payload or {}
    local key = Client.codeKey(code)
    local args = {}
    if key == "AutoLoader_DepositStarted" then
        args = { payload.total or 0, payload.batchCount or 0 }
    elseif key == "AutoLoader_DepositComplete" then
        args = { payload.stored or 0, payload.skipped or 0, payload.failed or 0 }
    elseif key == "AutoLoader_FillSuccess" then
        args = { payload.rounds or 0, payload.magazines or 0 }
    elseif key == "AutoLoader_FillInsufficient" then
        args = { payload.rounds or 0, payload.remainingNeed or 0 }
    elseif key == "AutoLoader_WithdrawSuccess" then
        args = { payload.created or 0 }
    elseif key == "AutoLoader_LimitReached" then
        args = { AutoLoader.MaxLoaders, AutoLoader.MaxMagazines }
    elseif key == "AutoLoader_Error_Generic" then
        args = { tostring(code or "unknown") }
    end
    GodSystem.notify(Client.format(Client.text(key, tostring(code or "")), args))
end

function Client.player(playerNum)
    if getSpecificPlayer and playerNum ~= nil then
        local ok, value = pcall(getSpecificPlayer, playerNum)
        if ok and value then return value end
    end
    return getPlayer and getPlayer() or nil
end

function Client.makeOperationId(player)
    Client.operationCounter = (Client.operationCounter or 0) + 1
    return table.concat({
        "gsa",
        tostring(AutoLoader.nowMs()),
        tostring(Client.operationCounter),
        tostring(AutoLoader.safeCall(player, "getPlayerNum", 0) or 0),
    }, "-")
end

function Client.handleResult(action, ok, code, payload, silent)
    action = tostring(action or "")
    payload = type(payload) == "table" and payload or {}
    if action == "startDeposit" and ok == true then
        Client.queueDeposit(payload)
    elseif action == "depositComplete" then
        Client.queuedSessions[tostring(payload.sessionId or "")] = nil
        Client.requestState(payload.loaderId)
    elseif action == "manualFill" or action == "withdraw"
        or action == "depositBatch"
    then
        Client.requestState(payload.loaderId
            or (GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.loaderId))
    elseif action == "postReload" and GodSystemAutoLoaderUI
        and GodSystemAutoLoaderUI.loaderId
    then
        Client.requestState(GodSystemAutoLoaderUI.loaderId)
    end
    if silent ~= true then Client.notify(code, payload) end
    if GodSystemAutoLoaderUI and GodSystemAutoLoaderUI.onResult then
        GodSystemAutoLoaderUI.onResult(action, ok == true, code, payload)
    end
end

function Client.queueDeposit(payload)
    payload = type(payload) == "table" and payload or {}
    local sessionId = tostring(payload.sessionId or "")
    if sessionId == "" or Client.queuedSessions[sessionId] then return false end
    local actor = Client.player()
    if not actor then return false end
    Client.queuedSessions[sessionId] = true
    for batchIndex = 1, math.max(1,
        math.floor(tonumber(payload.batchCount) or 1))
    do
        ISTimedActionQueue.add(ISGodSystemAutoLoaderDepositAction:new(
            actor, payload.loaderId, sessionId, batchIndex,
            payload.batchCount, payload.total))
    end
    return true
end

function Client.queueLength(actor)
    local queue = ISTimedActionQueue
        and ISTimedActionQueue.getTimedActionQueue
        and ISTimedActionQueue.getTimedActionQueue(actor) or nil
    if not queue or type(queue.queue) ~= "table" then return 0 end
    return #queue.queue
end

function Client.installReloadHook()
    if not ISReloadWeaponAction
        or type(ISReloadWeaponAction.BeginAutomaticReload) ~= "function"
    then
        return false
    end
    if ISReloadWeaponAction.BeginAutomaticReload == Client.reloadWrapper then
        return true
    end
    Client.originalBeginAutomaticReload =
        ISReloadWeaponAction.BeginAutomaticReload
    Client.reloadWrapper = function(actor, gun)
        local before = Client.queueLength(actor)
        local result = Client.originalBeginAutomaticReload(actor, gun)
        if Client.queueLength(actor) > before then
            local loaders = AutoLoader.getLoaders(actor, 1)
            if #loaders > 0 then
                ISTimedActionQueue.add(
                    ISGodSystemAutoLoaderPostReloadAction:new(
                        actor, Client.makeOperationId(actor)))
            end
        end
        return result
    end
    ISReloadWeaponAction.BeginAutomaticReload = Client.reloadWrapper
    return true
end

function Client.uninstallReloadHook()
    if Client.originalBeginAutomaticReload and ISReloadWeaponAction
        and ISReloadWeaponAction.BeginAutomaticReload == Client.reloadWrapper
    then
        ISReloadWeaponAction.BeginAutomaticReload =
            Client.originalBeginAutomaticReload
    end
    Client.reloadWrapper = nil
    Client.originalBeginAutomaticReload = nil
    return true
end

function Client.clear()
    Client.states = {}
    Client.queuedSessions = {}
end

local function adapterMissing()
    error("modular auto-loader adapter is not installed")
end

for _, name in ipairs({
    "requestState", "startDeposit", "manualFill", "withdraw",
    "onDepositInterrupted", "completeLocalDepositBatch",
    "completeLocalPostReload",
}) do
    Client[name] = adapterMissing
end

return Client
