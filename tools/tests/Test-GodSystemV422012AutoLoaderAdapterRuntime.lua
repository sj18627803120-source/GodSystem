local luaRoot = assert(arg[1], "Lua root required")
dofile(luaRoot .. "/shared/GodSystem/UI/AutoLoaderAdapter.lua")

local requests = {}
local facade = {}
function facade:request(route, args, options)
    requests[#requests + 1] = { route = route, args = args, options = options }
    local result = { ok = true, code = "ok", data = {} }
    if route == "autoloader.state" then
        result.code = "State"
        result.data = {
            loaderId = args.loaderId,
            capacity = 1000,
            total = 12,
            ammo = {},
        }
    elseif route == "autoloader.deposit" then
        result.code = "DepositStarted"
        result.data = {
            loaderId = args.loaderId,
            sessionId = "session-1",
            total = 4,
            batchCount = 2,
        }
    elseif route == "autoloader.depositBatch" then
        result.code = args.batchIndex == 2
            and "DepositComplete" or "DepositBatchComplete"
        result.data = {
            aggregate = {
                sessionId = args.sessionId,
                loaderId = "loader-1",
                completedBatches = args.batchIndex,
                batchCount = 2,
                stored = args.batchIndex * 2,
                skipped = 0,
                failed = 0,
                finished = args.batchIndex == 2,
            },
        }
    elseif route == "autoloader.fill" then
        result.code = "FillSuccess"
        result.data = { rounds = 5, magazines = 1 }
    elseif route == "autoloader.withdraw" then
        result.code = "WithdrawSuccess"
        result.data = { created = args.count }
    elseif route == "autoloader.reload" then
        result.code = "FillSuccess"
        result.data = { rounds = 2, silent = false }
    elseif route == "autoloader.cancel" then
        result.code = "DepositInterrupted"
        result.data = { sessionId = args.sessionId }
    end
    if options and options.callback then options.callback(result) end
    return result
end

local target = {
    states = {},
    queuedSessions = {},
    results = {},
    sequence = 0,
}
function target.player() return "player" end
function target.makeOperationId()
    target.sequence = target.sequence + 1
    return "operation-" .. tostring(target.sequence)
end
function target.handleResult(action, ok, code, payload, silent)
    target.results[#target.results + 1] = {
        action = action,
        ok = ok,
        code = code,
        payload = payload,
        silent = silent,
    }
    if action == "startDeposit" and ok then
        target.queuedSessions[payload.sessionId] = true
    elseif action == "depositComplete" then
        target.queuedSessions[payload.sessionId] = nil
    end
end
function target.installReloadHook()
    target.reloadInstalled = true
    return true
end
function target.uninstallReloadHook()
    target.reloadInstalled = false
    return true
end
function target.clear()
    target.states = {}
    target.queuedSessions = {}
end

local ui = {}
function ui.onState(id, state, ok)
    ui.state = { id = id, state = state, ok = ok }
end

local adapter = GodSystemUIAutoLoaderAdapter.new({
    facade = facade,
    target = target,
    helpers = {
        itemId = function(item)
            return type(item) == "table" and item.id or nil
        end,
    },
    ui = ui,
})

assert(adapter:install() and target.reloadInstalled)
assert(target.requestState({ id = "loader-1" }))
assert(target.states["loader-1"].total == 12 and ui.state.ok)

assert(target.startDeposit({ id = "loader-1" }))
assert(target.queuedSessions["session-1"] == true)
assert(target.completeLocalDepositBatch("player", "session-1", 1))
assert(target.queuedSessions["session-1"] == true)
assert(target.completeLocalDepositBatch("player", "session-1", 2))
assert(target.queuedSessions["session-1"] == nil)
assert(target.results[#target.results].action == "depositComplete")

assert(target.manualFill({ id = "loader-1" }))
assert(target.results[#target.results].code == "FillSuccess")
assert(target.withdraw({ id = "loader-1" }, "Base.Bullets9mm", 20))
assert(target.results[#target.results].payload.created == 20)
assert(target.completeLocalPostReload("player", "reload-operation"))
assert(target.results[#target.results].action == "postReload")

local before = #target.results
assert(adapter:receive({
    kind = "autoloader.result",
    action = "autoloader.depositBatch",
    result = {
        ok = true,
        code = "DepositComplete",
        data = {
            aggregate = {
                sessionId = "session-1",
                completedBatches = 2,
                stored = 4,
                finished = true,
            },
        },
    },
}))
assert(#target.results == before, "duplicate pushed batch result must be ignored")

assert(adapter:stop() and not target.reloadInstalled)
assert(target.requestState == nil)

print("Test-GodSystemV422012AutoLoaderAdapterRuntime passed")
