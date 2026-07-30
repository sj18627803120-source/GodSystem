GodSystemPZCommandTransport = GodSystemPZCommandTransport or {}

local Transport = GodSystemPZCommandTransport

function Transport.new(options)
    options = type(options) == "table" and options or {}
    local instance = {}

    local function localPlayer()
        if type(options.player) == "function" then return options.player() end
        if type(getPlayer) == "function" then return getPlayer() end
        return nil
    end

    function instance:sendToServer(moduleId, command, args)
        if type(sendClientCommand) ~= "function" then
            return false, "clientCommandUnavailable"
        end
        local player = localPlayer()
        if not player then return false, "playerUnavailable" end
        sendClientCommand(player, moduleId, command, args)
        return true
    end

    function instance:sendToClient(player, moduleId, command, args)
        if type(sendServerCommand) ~= "function" then
            return false, "serverCommandUnavailable"
        end
        if not player then return false, "playerUnavailable" end
        sendServerCommand(player, moduleId, command, args)
        return true
    end

    function instance:send(direction, moduleId, command, player, args)
        if direction == "server" then
            return self:sendToServer(moduleId, command, args)
        end
        if direction == "client" then
            return self:sendToClient(player, moduleId, command, args)
        end
        return false, "directionInvalid"
    end

    return instance
end

return Transport
