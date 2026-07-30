require "GodSystem/Platform/PZBindings"
require "GodSystem/Platform/PZCommandTransport"
require "GodSystem/Runtime/Kernel"
require "GodSystem/Runtime/Protocol422012"
require "GodSystem/Runtime/ServerBridge"

GodSystemPZServerRuntime = GodSystemPZServerRuntime or {}

local Server = GodSystemPZServerRuntime

function Server.new(options)
    options = type(options) == "table" and options or {}
    local transport = options.transport or GodSystemPZCommandTransport.new()
    local instance = {
        runtime = nil,
        bridge = nil,
        started = false,
    }

    function instance:start()
        if self.started then return true end
        self.runtime = GodSystemRuntimeKernel.create({
            environment = "server",
            bindings = GodSystemPZBindings.build({
                overrides = options.bindings,
            }),
            coordinate = options.coordinate,
            stateAdapter = options.stateAdapter,
            eventAdapter = options.eventAdapter,
            commandAdapter = transport,
            legacySnapshots = options.legacySnapshots,
            adminConfig = options.adminConfig,
            configSnapshot = options.configSnapshot,
        })
        self.bridge = GodSystemServerBridge.new({
            transport = transport,
            protocolVersion = GodSystemProtocol422012.Version,
            requireHello = false,
            actorKey = GodSystemPZBindings.identity,
            diagnostics = self.runtime.diagnostics,
            dispatcher = {
                dispatch = function(_, packet, actor)
                    return instance.runtime:dispatch(packet, actor)
                end,
            },
        })
        local ok, code = self.runtime.events:subscribe(
            "runtime.serverBridge", "OnClientCommand",
            function(moduleName, command, player, packet)
                self.bridge:receive(player, moduleName, command, packet)
            end, 100)
        if not ok then return false, code end
        self.runtime.events:subscribe(
            "runtime.serverBridge", "OnDisconnect",
            function(player) self.bridge:disconnect(player) end, 100)
        self.started = true
        return true
    end

    function instance:stop(reason)
        if not self.started then return true end
        self.runtime.events:unsubscribeModule("runtime.serverBridge")
        self.runtime:stop(reason)
        self.started = false
        return true
    end

    function instance:push(actor, data)
        if not self.started then return false, "serverStopped" end
        return transport:sendToClient(actor,
            GodSystemProtocol422012.Module,
            GodSystemProtocol422012.S2C.Snapshot, {
                protocol = GodSystemProtocol422012.Version,
                data = data,
            })
    end

    function instance:health()
        return {
            runtime = self.runtime and self.runtime:health() or nil,
            bridge = self.bridge and self.bridge:status() or nil,
        }
    end

    return instance
end

return Server
