require "GodSystem/Core/Result"

GodSystemCommandRouter = GodSystemCommandRouter or {}

local Router = GodSystemCommandRouter

function Router.new(options)
    options = options or {}
    local instance = {
        diagnostics = options.diagnostics,
        protocolVersion = tostring(options.protocolVersion or ""),
        transport = options.transport,
        routes = {},
    }

    function instance:register(moduleId, command, handler)
        moduleId, command = tostring(moduleId or ""), tostring(command or "")
        if moduleId == "" or command == "" or type(handler) ~= "function" then
            return false, "invalidRoute"
        end
        local key = moduleId .. "/" .. command
        if self.routes[key] then return false, "routeAlreadyRegistered" end
        self.routes[key] = { moduleId = moduleId, command = command, handler = handler }
        return true
    end

    function instance:dispatch(moduleId, command, player, args)
        moduleId, command = tostring(moduleId or ""), tostring(command or "")
        local route = self.routes[moduleId .. "/" .. command]
        if not route then return GodSystemResult.fail("core", "commandUnknown", { module = moduleId, command = command }) end
        args = type(args) == "table" and args or {}
        if command ~= "hello" and self.protocolVersion ~= "" and tostring(args.protocolVersion or "") ~= self.protocolVersion then
            return GodSystemResult.fail(route.moduleId, "protocolMismatch", {
                expected = self.protocolVersion,
                actual = tostring(args.protocolVersion or ""),
            }, args.operationId)
        end
        local ok, value = pcall(route.handler, player, args)
        if not ok then
            if self.diagnostics then
                self.diagnostics:record({
                    moduleId = route.moduleId,
                    stage = "command:" .. command,
                    code = "commandFailed",
                    message = value,
                    operationId = args.operationId,
                })
            end
            return GodSystemResult.fail(route.moduleId, "commandFailed", { message = tostring(value) }, args.operationId)
        end
        return GodSystemResult.normalize(value, route.moduleId, args.operationId)
    end

    function instance:unregisterModule(moduleId)
        moduleId = tostring(moduleId or "")
        for key, route in pairs(self.routes) do
            if route.moduleId == moduleId then self.routes[key] = nil end
        end
    end

    function instance:send(direction, moduleId, command, player, args)
        direction = tostring(direction or "")
        moduleId, command = tostring(moduleId or ""), tostring(command or "")
        args = type(args) == "table" and args or {}
        if args.protocolVersion == nil and self.protocolVersion ~= "" then
            args.protocolVersion = self.protocolVersion
        end
        if not self.transport or type(self.transport.send) ~= "function" then
            return GodSystemResult.fail(moduleId, "transportUnavailable", {
                direction = direction,
                command = command,
            }, args.operationId)
        end
        local ok, code = self.transport:send(direction, moduleId, command, player, args)
        if ok ~= true then
            return GodSystemResult.fail(moduleId, code or "transportFailed", {
                direction = direction,
                command = command,
            }, args.operationId)
        end
        return GodSystemResult.ok(moduleId, "dispatched", {
            direction = direction,
            command = command,
        }, args.operationId)
    end

    function instance:health()
        local count = 0
        for _ in pairs(self.routes) do count = count + 1 end
        return GodSystemResult.ok("platform.commands", "ok", { routeCount = count, protocolVersion = self.protocolVersion })
    end

    return instance
end
