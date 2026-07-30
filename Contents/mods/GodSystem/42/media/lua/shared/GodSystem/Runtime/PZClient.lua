require "GodSystem/Core/Diagnostics"
require "GodSystem/Platform/PZBindings"
require "GodSystem/Platform/PZCommandTransport"
require "GodSystem/Runtime/ClientGateway"
require "GodSystem/Runtime/Kernel"
require "GodSystem/Runtime/RemoteClient"
require "GodSystem/Runtime/Protocol422012"

GodSystemPZClientRuntime = GodSystemPZClientRuntime or {}

local Client = GodSystemPZClientRuntime

function Client.new(options)
    options = type(options) == "table" and options or {}
    local multiplayer = options.multiplayer
    if multiplayer == nil then
        multiplayer = type(isClient) == "function" and isClient() == true
    end
    local transport = options.transport or GodSystemPZCommandTransport.new()
    local diagnostics = options.diagnostics or GodSystemDiagnostics.new({
        version = GodSystemProtocol422012.Version,
        environment = multiplayer and "client" or "sp",
        protocol = { version = GodSystemProtocol422012.Version },
    })
    local actor = type(options.actor) == "function"
        and options.actor or GodSystemPZBindings.currentActor
    local instance = {
        multiplayer = multiplayer,
        diagnostics = diagnostics,
        started = false,
        runtime = nil,
        remote = nil,
        gateway = nil,
    }

    function instance:start()
        if self.started then return true end
        if self.multiplayer then
            self.remote = GodSystemRemoteClient.new({
                transport = transport,
                diagnostics = diagnostics,
                protocolVersion = GodSystemProtocol422012.Version,
                onSnapshot = options.onSnapshot,
                requireHello = false,
            })
            self.gateway = GodSystemClientGateway.new({
                remote = self.remote,
                actor = actor,
                protocolVersion = GodSystemProtocol422012.Version,
                onResult = options.onResult,
                retryStore = options.retryStore,
            })
            if options.hello ~= false then
                self.remote:hello({
                    modId = "GodSystem_CN",
                    version = GodSystemProtocol422012.Version,
                })
            end
        else
            local bindings = GodSystemPZBindings.build({
                visuals = options.visuals,
                overrides = options.bindings,
            })
            self.runtime = GodSystemRuntimeKernel.create({
                environment = "sp",
                bindings = bindings,
                coordinate = options.coordinate,
                stateAdapter = options.stateAdapter,
                eventAdapter = options.eventAdapter,
                commandAdapter = transport,
                legacySnapshots = options.legacySnapshots,
                configSnapshot = options.configSnapshot,
            })
            self.diagnostics = self.runtime.diagnostics
            self.gateway = GodSystemClientGateway.new({
                runtime = self.runtime,
                actor = actor,
                protocolVersion = GodSystemProtocol422012.Version,
                onResult = options.onResult,
            })
        end
        self.started = true
        return true
    end

    function instance:receive(moduleName, command, packet)
        if not self.remote then return false, "remoteUnavailable" end
        return self.remote:receive(moduleName, command, packet)
    end

    function instance:poll()
        if self.remote then return self.remote:poll() end
        return {}
    end

    function instance:stop(reason)
        if not self.started then return true end
        if self.remote then self.remote:disconnect(reason) end
        if self.runtime then self.runtime:stop(reason) end
        self.started = false
        return true
    end

    function instance:health()
        if self.runtime then return self.runtime:health() end
        return {
            remote = self.remote and self.remote:status() or nil,
            gateway = self.gateway and self.gateway:health() or nil,
        }
    end

    return instance
end

return Client
