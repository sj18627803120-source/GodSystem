require "GodSystem/Runtime/PZServer"

GodSystemModularServer = GodSystemModularServer or { instance = nil }

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

return GodSystemModularServer
