GodSystemPZCommandTransport = GodSystemPZCommandTransport or {}

local Transport = GodSystemPZCommandTransport

function Transport.new()
    local instance = {}

    function instance:send(direction, moduleId, command, player, args)
        if direction == "server" then
            if type(sendClientCommand) ~= "function" then
                return false, "clientCommandUnavailable"
            end
            sendClientCommand(player, moduleId, command, args)
            return true
        end
        if direction == "client" then
            if type(sendServerCommand) ~= "function" then
                return false, "serverCommandUnavailable"
            end
            sendServerCommand(player, moduleId, command, args)
            return true
        end
        return false, "directionInvalid"
    end

    return instance
end

return Transport
