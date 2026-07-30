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
        bindings = options.bindings or {},
    }
    runtime.diagnostics = GodSystemDiagnostics.new({
        version = runtime.version,
        environment = runtime.environment,
        protocol = { version = runtime.protocolVersion },
    })
    runtime.events = GodSystemEventGateway.new({
        diagnostics = runtime.diagnostics,
        source = runtime.adapters.events,
    })
    runtime.commands = GodSystemCommandRouter.new({
        diagnostics = runtime.diagnostics,
        protocolVersion = runtime.protocolVersion,
        transport = runtime.adapters.commands,
    })
    runtime.state = GodSystemStateStore.new(runtime.adapters.state, {
        schemaVersion = 1,
        releaseVersion = runtime.version,
    })
    runtime.registry = GodSystemModuleRegistry.new({
        diagnostics = runtime.diagnostics,
        runtime = runtime,
    })

    function runtime:contextFor(moduleId, descriptor)
        local context = {
            moduleId = tostring(moduleId),
            version = self.version,
            protocolVersion = self.protocolVersion,
            environment = self.environment,
            binding = self.bindings[moduleId],
            state = self.state:scoped(moduleId, descriptor and descriptor.stateVersion or 1),
        }
        context.events = {
            subscribe = function(_, eventName, handler, priority)
                return runtime.events:subscribe(moduleId, eventName, handler, priority)
            end,
        }
        context.commands = {
            register = function(_, protocolModule, command, handler)
                return runtime.commands:register(protocolModule, command, handler)
            end,
            send = function(_, protocolModule, command, actor, args)
                return runtime.commands:send("server", protocolModule, command, actor, args)
            end,
            reply = function(_, protocolModule, command, actor, args)
                return runtime.commands:send("client", protocolModule, command, actor, args)
            end,
        }
        context.diagnostics = {
            record = function(_, issue)
                issue = type(issue) == "table" and issue or { message = issue }
                issue.moduleId = moduleId
                return runtime.diagnostics:record(issue)
            end,
        }
        return context
    end

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
