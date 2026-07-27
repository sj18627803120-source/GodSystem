if not (isServer and isServer()) then return end

require "GodSystem_AutoLoader"

GodSystemAutoLoaderServer = GodSystemAutoLoaderServer or {}

local Server = GodSystemAutoLoaderServer
local AutoLoader = GodSystemAutoLoader
local MODULE = "GodSystemAutoLoader"

Server.Commands = Server.Commands or {}
Server.cleanupTicks = Server.cleanupTicks or 0

function Server.fingerprint(kind, args)
    return AutoLoader.fingerprint(kind, args)
end

function Server.send(player, command, args)
    if sendServerCommand then pcall(sendServerCommand, player, MODULE, command, args or {}) end
end

function Server.sendState(player, loader)
    if not AutoLoader.isLoader(loader) or not AutoLoader.isItemCarried(player, loader) then
        return Server.send(player, "state", { ok = false, code = "NotCarried", loaderId = AutoLoader.itemId(loader) })
    end
    Server.send(player, "state", { ok = true, loaderId = AutoLoader.itemId(loader), state = AutoLoader.stateFor(loader) })
end

function Server.sendResult(player, action, ok, code, payload, silent)
    Server.send(player, "result", {
        action = tostring(action or ""),
        ok = ok == true,
        code = tostring(code or ""),
        payload = payload or {},
        silent = silent == true,
    })
end

function Server.replayOperation(player, action, operation, state)
    if state == nil then return false end
    if state == "processing" then
        Server.sendResult(player, action, false, "OperationPending", {}, false)
    elseif state == "unknown" then
        Server.sendResult(player, action, false, "OperationUnknown", {}, false)
    elseif state == "done" then
        Server.sendResult(player, action, operation.ok == true, operation.code, operation.payload, operation.silent == true)
    else
        Server.sendResult(player, action, false, state == "operationMismatch" and "OperationMismatch" or "OperationInvalid", {}, false)
    end
    return true
end

function Server.finishOperation(player, action, operation, ok, code, payload, silent)
    AutoLoader.finishOperation(operation, ok, code, payload)
    if operation then operation.silent = silent == true end
    Server.sendResult(player, action, ok, code, payload, silent)
end

function Server.Commands.state(player, args)
    local loader = AutoLoader.findCarriedItem(player, args and args.loaderId)
    Server.sendState(player, loader)
end

function Server.Commands.startDeposit(player, args)
    local operation, state = AutoLoader.beginOperation(player, "startDeposit", args)
    if not operation then return Server.sendResult(player, "startDeposit", false, state or "OperationInvalid", {}, false) end
    if Server.replayOperation(player, "startDeposit", operation, state) then return end
    local payload, reason = AutoLoader.startDepositSession(player, args and args.loaderId, args and args.opId)
    if not payload then return Server.finishOperation(player, "startDeposit", operation, false, reason or "DepositFailed", {}, false) end
    Server.finishOperation(player, "startDeposit", operation, true, "DepositStarted", payload, false)
end

function Server.Commands.manualFill(player, args)
    local operation, state = AutoLoader.beginOperation(player, "manualFill", args)
    if not operation then return Server.sendResult(player, "manualFill", false, state or "OperationInvalid", {}, false) end
    if Server.replayOperation(player, "manualFill", operation, state) then return end
    local loader = AutoLoader.findCarriedItem(player, args and args.loaderId)
    if not AutoLoader.isLoader(loader) then return Server.finishOperation(player, "manualFill", operation, false, "NotCarried", {}, false) end
    local stats = AutoLoader.fillMagazines(player, { loader }, AutoLoader.MaxMagazines)
    local code = "NoCompatibleMagazine"
    if stats.rounds > 0 and stats.remainingNeed <= 0 then code = "FillSuccess"
    elseif stats.rounds > 0 or stats.remainingNeed > 0 then code = "FillInsufficient" end
    local ok = stats.rounds > 0
    Server.finishOperation(player, "manualFill", operation, ok, code, stats, false)
end

function Server.Commands.withdraw(player, args)
    local operation, state = AutoLoader.beginOperation(player, "withdraw", args)
    if not operation then return Server.sendResult(player, "withdraw", false, state or "OperationInvalid", {}, false) end
    if Server.replayOperation(player, "withdraw", operation, state) then return end
    local loader = AutoLoader.findCarriedItem(player, args and args.loaderId)
    if not AutoLoader.isLoader(loader) then return Server.finishOperation(player, "withdraw", operation, false, "NotCarried", {}, false) end
    local stats = AutoLoader.withdrawAmmo(player, loader, args and args.fullType, args and args.count)
    local ok = stats.created > 0
    local code = ok and "WithdrawSuccess" or (stats.reason == "unavailable" and "Unavailable" or stats.reason or "WithdrawFailed")
    Server.finishOperation(player, "withdraw", operation, ok, code, stats, false)
end

function Server.completeDepositBatch(player, sessionId, batchIndex)
    local _, reason, session, replayed, aggregate = AutoLoader.completeDepositBatch(player, sessionId, batchIndex)
    if reason then
        Server.sendResult(player, "depositBatch", false, reason, { sessionId = tostring(sessionId or "") }, false)
        return false
    end
    if aggregate and aggregate.finished and not replayed then
        Server.sendResult(player, "depositComplete", aggregate.stored > 0, "DepositComplete", aggregate, false)
    end
    return true
end

function Server.completePostReload(player, opId)
    local args = { opId = tostring(opId or ""), loaderId = "", fullType = "", count = 0 }
    local operation, state = AutoLoader.beginOperation(player, "postReload", args)
    if not operation then return false end
    if state ~= nil then return operation.ok == true end
    local loaders, loaderLimited = AutoLoader.getLoaders(player, AutoLoader.MaxLoaders)
    if #loaders <= 0 then
        AutoLoader.finishOperation(operation, true, "NoLoader", { rounds = 0 })
        operation.silent = true
        return true
    end
    local stats = AutoLoader.fillMagazines(player, loaders, AutoLoader.MaxMagazines)
    stats.loaderLimited = stats.loaderLimited or loaderLimited
    local limited = stats.loaderLimited or stats.magazineLimited
    local silent = stats.rounds > 0 and stats.remainingNeed <= 0 and not limited
    local code = "FillSuccess"
    if limited then code = "LimitReached"; silent = false
    elseif stats.need <= 0 then code = "NoCompatibleMagazine"; silent = true
    elseif stats.remainingNeed > 0 then code = "FillInsufficient"; silent = false end
    AutoLoader.finishOperation(operation, true, code, stats)
    operation.silent = silent
    if not silent then Server.sendResult(player, "postReload", true, code, stats, false) end
    return true
end

function Server.onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    local handler = Server.Commands[tostring(command or "")]
    if not handler then return end
    local ok, err = pcall(handler, player, type(args) == "table" and args or {})
    if not ok then Server.sendResult(player, command, false, "InternalError", { detail = tostring(err) }, false) end
end

function Server.onTick()
    Server.cleanupTicks = (Server.cleanupTicks or 0) + 1
    if Server.cleanupTicks < 600 then return end
    Server.cleanupTicks = 0
    AutoLoader.cleanupSessions()
end

if Events.OnClientCommand then
    Events.OnClientCommand.Remove(Server.onClientCommand)
    Events.OnClientCommand.Add(Server.onClientCommand)
end
if Events.OnTick then
    Events.OnTick.Remove(Server.onTick)
    Events.OnTick.Add(Server.onTick)
end

return Server
