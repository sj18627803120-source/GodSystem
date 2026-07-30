require "GodSystem/Runtime/PZServer"

GodSystemModularServer = GodSystemModularServer or { instance = nil }
GodSystemModularServer.sequence = GodSystemModularServer.sequence or 0

function GodSystemModularServer.start()
    if GodSystemModularServer.instance then return true end
    local instance = GodSystemPZServerRuntime.new()
    local started, code = instance:start()
    if started == false then return false, code end
    GodSystemModularServer.instance = instance
    return true
end

function GodSystemModularServer.stop(reason)
    if GodSystemModularServer.instance then
        GodSystemModularServer.instance:stop(reason)
        GodSystemModularServer.instance = nil
    end
end

function GodSystemModularServer.execute(action, args, actor, pushKind, operationId)
    local instance = GodSystemModularServer.instance
    if not instance or not instance.runtime then return false end
    GodSystemModularServer.sequence = GodSystemModularServer.sequence + 1
    local suffix = tostring(operationId or GodSystemModularServer.sequence)
    local requestId = "server-action:" .. tostring(action) .. ":" .. suffix
    local result = instance.runtime:dispatch({
        protocol = GodSystemProtocol422012.Version,
        requestId = requestId,
        operationId = tostring(operationId or requestId),
        action = tostring(action or ""),
        args = type(args) == "table" and args or {},
    }, actor)
    if pushKind and instance.push then
        instance:push(actor, {
            kind = tostring(pushKind),
            action = tostring(action or ""),
            result = result,
        })
    end
    return result and result.ok == true
end

return GodSystemModularServer
