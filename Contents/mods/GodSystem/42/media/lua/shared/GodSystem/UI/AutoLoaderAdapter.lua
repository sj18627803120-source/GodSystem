GodSystemUIAutoLoaderAdapter = GodSystemUIAutoLoaderAdapter or {}

local AutoLoaderAdapter = GodSystemUIAutoLoaderAdapter

local REPLACEMENTS = {
    "requestState", "startDeposit", "manualFill", "withdraw",
    "onDepositInterrupted", "completeLocalDepositBatch",
    "completeLocalPostReload",
}

function AutoLoaderAdapter.new(options)
    options = type(options) == "table" and options or {}
    local facade = assert(options.facade, "auto-loader facade required")
    local target = assert(options.target, "auto-loader client required")
    local helpers = assert(options.helpers, "auto-loader helpers required")
    local ui = options.ui
    local originals = {}
    local seen = {}
    local instance = { installed = false }

    local function loaderId(loader)
        return tostring(helpers.itemId(loader) or loader or "")
    end

    local function request(route, args, callback, operationId)
        local primary, secondary = facade:request(route, args or {}, {
            operationId = operationId,
            callback = callback,
        })
        local value = type(primary) == "table" and primary or secondary
        return type(value) == "table"
            and (value.ok == true or value.code == "requestPending")
    end

    local function updateState(id, result)
        id = tostring(id or "")
        if result.ok and id ~= "" then target.states[id] = result.data end
        if ui and ui.onState then
            ui.onState(id, result.data, result.ok == true, result.code)
        end
    end

    local function handleBatch(result, sessionId, batchIndex)
        local key = tostring(sessionId or "") .. ":" .. tostring(batchIndex or "")
        if seen[key] then return true end
        local data = type(result.data) == "table" and result.data or {}
        local aggregate = type(data.aggregate) == "table"
            and data.aggregate or data
        if result.ok and aggregate.finished == true then
            seen[key] = true
            target.handleResult("depositComplete",
                (aggregate.stored or 0) > 0,
                "DepositComplete", aggregate, false)
        elseif not result.ok then
            seen[key] = true
            target.handleResult("depositBatch", false,
                result.code, aggregate, false)
        end
        return result.ok == true
    end

    local replacements = {}

    replacements.requestState = function(loader)
        local id = loaderId(loader)
        if id == "" then return false end
        return request("autoloader.state", { loaderId = id }, function(result)
            updateState(id, result)
        end)
    end

    replacements.startDeposit = function(loader)
        local id = loaderId(loader)
        if id == "" then return false end
        local operationId = target.makeOperationId(target.player())
        return request("autoloader.deposit", {
            loaderId = id,
        }, function(result)
            target.handleResult("startDeposit", result.ok,
                result.code, result.data, false)
        end, operationId)
    end

    replacements.manualFill = function(loader)
        local id = loaderId(loader)
        if id == "" then return false end
        local operationId = target.makeOperationId(target.player())
        return request("autoloader.fill", {
            loaderId = id,
        }, function(result)
            local data = type(result.data) == "table" and result.data or {}
            data.loaderId = data.loaderId or id
            target.handleResult("manualFill", result.ok,
                result.code, data, false)
        end, operationId)
    end

    replacements.withdraw = function(loader, fullType, count)
        local id = loaderId(loader)
        if id == "" or tostring(fullType or "") == "" then return false end
        local operationId = target.makeOperationId(target.player())
        return request("autoloader.withdraw", {
            loaderId = id,
            fullType = tostring(fullType),
            count = math.max(1, math.min(500,
                math.floor(tonumber(count) or 100))),
        }, function(result)
            local data = type(result.data) == "table" and result.data or {}
            data.loaderId = data.loaderId or id
            target.handleResult("withdraw", result.ok,
                result.code, data, false)
        end, operationId)
    end

    replacements.onDepositInterrupted = function(id, sessionId)
        sessionId = tostring(sessionId or "")
        target.queuedSessions[sessionId] = nil
        return request("autoloader.cancel", {
            sessionId = sessionId,
        }, function(result)
            target.handleResult("depositBatch", result.ok,
                result.code, result.data, false)
            replacements.requestState(id)
        end)
    end

    replacements.completeLocalDepositBatch = function(_, sessionId, batchIndex)
        local operationId = table.concat({
            "autoloader-batch",
            tostring(sessionId or ""),
            tostring(batchIndex or ""),
        }, ":")
        return request("autoloader.depositBatch", {
            sessionId = sessionId,
            batchIndex = batchIndex,
        }, function(result)
            handleBatch(result, sessionId, batchIndex)
        end, operationId)
    end

    replacements.completeLocalPostReload = function(_, operationId)
        operationId = tostring(operationId or target.makeOperationId(target.player()))
        return request("autoloader.reload", {}, function(result)
            local data = type(result.data) == "table" and result.data or {}
            target.handleResult("postReload", result.ok,
                result.code, data, data.silent == true)
        end, operationId)
    end

    function instance:receive(data)
        if type(data) ~= "table" or data.kind ~= "autoloader.result" then
            return false
        end
        local result = type(data.result) == "table" and data.result or {
            ok = false, code = "InternalError",
        }
        if data.action == "autoloader.depositBatch" then
            local payload = type(result.data) == "table" and result.data or {}
            local aggregate = type(payload.aggregate) == "table"
                and payload.aggregate or payload
            return handleBatch(result, aggregate.sessionId,
                aggregate.completedBatches)
        end
        if data.action == "autoloader.reload" then
            target.handleResult("postReload", result.ok,
                result.code, result.data,
                result.data and result.data.silent == true)
            return true
        end
        return false
    end

    function instance:install()
        if self.installed then return true end
        for index = 1, #REPLACEMENTS do
            local name = REPLACEMENTS[index]
            originals[name] = target[name]
            target[name] = replacements[name]
        end
        if target.installReloadHook then target.installReloadHook() end
        self.installed = true
        return true
    end

    function instance:stop()
        if not self.installed then return true end
        if target.uninstallReloadHook then target.uninstallReloadHook() end
        target.clear()
        self.installed = false
        return true
    end

    return instance
end

return AutoLoaderAdapter
