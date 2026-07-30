require "GodSystem/Core/Diagnostics"
require "GodSystem/Core/ModuleRegistry"
require "GodSystem/Platform/EventGateway"
require "GodSystem/Platform/CommandRouter"
require "GodSystem/State/Store"

GodSystemBootstrap = GodSystemBootstrap or {}

local Bootstrap = GodSystemBootstrap

function Bootstrap.create(options)
    options = options or {}
    local runtime = {
        version = tostring(options.version or ""),
        protocolVersion = tostring(options.protocolVersion or options.version or ""),
        environment = tostring(options.environment or "unknown"),
        adapters = options.adapters or {},
    }
    runtime.diagnostics = GodSystemDiagnostics.new({
        version = runtime.version,
        environment = runtime.environment,
        protocol = { version = runtime.protocolVersion },
    })
    runtime.events = GodSystemEventGateway.new({ diagnostics = runtime.diagnostics })
    runtime.commands = GodSystemCommandRouter.new({
        diagnostics = runtime.diagnostics,
        protocolVersion = runtime.protocolVersion,
    })
    runtime.state = GodSystemStateStore.new(runtime.adapters.state, {
        schemaVersion = 1,
        releaseVersion = runtime.version,
    })
    runtime.registry = GodSystemModuleRegistry.new({
        diagnostics = runtime.diagnostics,
        runtime = runtime,
    })

    function runtime:register(descriptor)
        return self.registry:register(descriptor)
    end

    function runtime:start()
        return self.registry:start()
    end

    function runtime:stop(reason)
        self.registry:stop(reason)
        self.events:stop()
    end

    function runtime:health()
        return {
            modules = self.registry:health(),
            events = self.events:health(),
            commands = self.commands:health(),
        }
    end

    return runtime
end

