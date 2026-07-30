require "GodSystem/Runtime/PZClient"
require "GodSystem/Platform/Companion/PZVisuals"
require "GodSystem/UI/Facade"
require "GodSystem/UI/ShellAdapter"
require "GodSystem/UI/ActionAdapter"
require "GodSystem_UI"

GodSystemModularClient = GodSystemModularClient or {
    instance = nil,
    visuals = nil,
    facade = nil,
    shell = nil,
    actions = nil,
}

function GodSystemModularClient.start()
    if GodSystemModularClient.instance then return true end
    local multiplayer = type(isClient) == "function" and isClient() == true
    local visuals
    if not multiplayer then
        visuals = GodSystemCompanionPZVisualsPlatform.create({}, {})
        local started, code = visuals:start()
        if started == false then return false, code end
        GodSystemModularClient.visuals = visuals
    end
    local instance = GodSystemPZClientRuntime.new({
        multiplayer = multiplayer,
        visuals = visuals and visuals.public or nil,
        onResult = function()
            if GodSystemUI.window and GodSystemUI.window.requestDeferredPopulate then
                GodSystemUI.window:requestDeferredPopulate(1)
            end
        end,
    })
    local started, code = instance:start()
    if started == false then
        if visuals then visuals:stop() end
        return false, code
    end
    GodSystemModularClient.instance = instance
    local facade = GodSystemUIFacade.new({
        gateway = instance.gateway,
        version = "42.20.1.2",
        onChanged = function()
            if GodSystemUI.window and GodSystemUI.window.requestDeferredPopulate then
                GodSystemUI.window:requestDeferredPopulate(1)
            end
        end,
    })
    local shell = GodSystemUIShellAdapter.new({
        facade = facade,
        target = GodSystem,
    })
    shell:install()
    local actions = GodSystemUIActionAdapter.new({
        facade = facade,
        target = GodSystem,
        companionTarget = GodSystemCompanion,
    })
    actions:install()
    GodSystemModularClient.facade = facade
    GodSystemModularClient.shell = shell
    GodSystemModularClient.actions = actions
    GodSystemUI.bindRuntime(instance.runtime or instance)
    GodSystemUI.bindGateway(instance.gateway)
    GodSystemUI.bindFacade(facade)
    facade:refresh()
    return true
end

function GodSystemModularClient.stop(reason)
    if GodSystemModularClient.actions then
        GodSystemModularClient.actions:stop()
    end
    if GodSystemModularClient.shell then
        GodSystemModularClient.shell:stop()
    end
    if GodSystemModularClient.facade then
        GodSystemModularClient.facade:stop()
    end
    if GodSystemModularClient.instance then
        GodSystemModularClient.instance:stop(reason)
    end
    if GodSystemModularClient.visuals then
        GodSystemModularClient.visuals:stop()
    end
    GodSystemModularClient.instance = nil
    GodSystemModularClient.visuals = nil
    GodSystemModularClient.facade = nil
    GodSystemModularClient.shell = nil
    GodSystemModularClient.actions = nil
end

function GodSystemModularClient.receive(moduleName, command, packet)
    if not GodSystemModularClient.instance then return false end
    return GodSystemModularClient.instance:receive(moduleName, command, packet)
end

function GodSystemModularClient.poll()
    if GodSystemModularClient.instance then GodSystemModularClient.instance:poll() end
end

return GodSystemModularClient
