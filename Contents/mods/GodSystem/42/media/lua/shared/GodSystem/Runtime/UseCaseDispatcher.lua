require "GodSystem/Core/Result"
require "GodSystem/Runtime/Protocol422012"

GodSystemUseCaseDispatcher = GodSystemUseCaseDispatcher or {}

local Dispatcher = GodSystemUseCaseDispatcher

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function invoke(callback, request)
    if xpcall then
        return xpcall(function() return callback(request) end, traceback)
    end
    return pcall(callback, request)
end

function Dispatcher.new(options)
    options = type(options) == "table" and options or {}
    local protocolVersion = tostring(options.protocolVersion or GodSystemProtocol422012.Version)
    local routes = type(options.routes) == "table" and options.routes or GodSystemProtocol422012.Routes
    local resolve = options.resolve
    local diagnostics = options.diagnostics
    local onFault = options.onFault
    assert(type(resolve) == "function", "dispatcher resolver required")

    local instance = {}

    function instance:dispatch(packet, actor)
        packet = type(packet) == "table" and packet or {}
        local operationId = tostring(packet.operationId or packet.requestId or "")
        if tostring(packet.protocol or "") ~= protocolVersion then
            return GodSystemResult.fail("runtime.dispatcher", "protocolMismatch", {
                expected = protocolVersion,
                actual = tostring(packet.protocol or ""),
            }, operationId)
        end
        local action = tostring(packet.action or "")
        local route = routes[action]
        if type(route) ~= "table" then
            return GodSystemResult.fail("runtime.dispatcher", "actionUnknown", {
                action = action,
            }, operationId)
        end
        local moduleId = tostring(route.moduleId or "")
        local method = tostring(route.method or "")
        local public = resolve(moduleId)
        if type(public) ~= "table" then
            return GodSystemResult.fail(moduleId, "moduleUnavailable", nil, operationId)
        end
        local callback = public[method]
        if type(callback) ~= "function" then
            return GodSystemResult.fail(moduleId, "useCaseUnavailable", {
                action = action,
                method = method,
            }, operationId)
        end
        local request = copy(type(packet.args) == "table" and packet.args or {})
        request.actor = actor
        request.operationId = operationId
        request.requestId = tostring(packet.requestId or "")
        request.protocolVersion = protocolVersion
        local ok, value = invoke(callback, request)
        if not ok then
            if diagnostics and type(diagnostics.record) == "function" then
                diagnostics:record({
                    moduleId = moduleId,
                    stage = "useCase",
                    code = "useCaseFailed",
                    operationId = operationId,
                    message = tostring(value),
                })
            end
            if type(onFault) == "function" then
                onFault(moduleId, "useCaseFailed", {
                    action = action,
                    operationId = operationId,
                    message = tostring(value),
                })
            end
            return GodSystemResult.fail(moduleId, "useCaseFailed", {
                action = action,
                message = tostring(value),
            }, operationId)
        end
        return GodSystemResult.normalize(value, moduleId, operationId)
    end

    function instance:protocolVersion()
        return protocolVersion
    end

    return instance
end

return Dispatcher
