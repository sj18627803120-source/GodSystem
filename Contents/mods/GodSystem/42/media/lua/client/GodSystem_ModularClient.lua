require "GodSystem/Runtime/PZClient"
require "GodSystem_RuntimeMode"
require "GodSystem/Platform/Companion/PZVisuals"
require "GodSystem/UI/Facade"
require "GodSystem/UI/ShellAdapter"
require "GodSystem/UI/ActionAdapter"
require "GodSystem/UI/StorageAdapter"
require "GodSystem/UI/AutoLoaderAdapter"
require "GodSystem_AutoLoaderClient"
require "GodSystem_AutoLoaderUI"
require "GodSystem_UI"

GodSystemModularClient = GodSystemModularClient or {
    instance = nil,
    visuals = nil,
    facade = nil,
    shell = nil,
    actions = nil,
    storage = nil,
    autoloader = nil,
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
        onSnapshot = function(data)
            if GodSystemModularClient.autoloader then
                GodSystemModularClient.autoloader:receive(data)
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
        multiplayer = multiplayer,
    })
    actions:install()
    local storage = GodSystemUIStorageAdapter.new({
        facade = facade,
        target = GodSystemStorageClient,
        storage = GodSystemStorage,
        ui = GodSystemStorageUI,
        context = GodSystemStorageContext,
        multiplayer = multiplayer,
    })
    storage:install()
    local autoloader = GodSystemUIAutoLoaderAdapter.new({
        facade = facade,
        target = GodSystemAutoLoaderClient,
        helpers = GodSystemAutoLoader,
        ui = GodSystemAutoLoaderUI,
    })
    autoloader:install()
    GodSystemModularClient.facade = facade
    GodSystemModularClient.shell = shell
    GodSystemModularClient.actions = actions
    GodSystemModularClient.storage = storage
    GodSystemModularClient.autoloader = autoloader
    GodSystemUI.bindRuntime(instance.runtime or instance)
    GodSystemUI.bindGateway(instance.gateway)
    GodSystemUI.bindFacade(facade)
    facade:refresh(GodSystemUIFacade.defaultQueries({
        includeCompanion = not multiplayer,
    }))
    return true
end

function GodSystemModularClient.stop(reason)
    if GodSystemModularClient.autoloader then
        GodSystemModularClient.autoloader:stop()
    end
    if GodSystemModularClient.storage then
        GodSystemModularClient.storage:stop()
    end
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
    GodSystemModularClient.storage = nil
    GodSystemModularClient.autoloader = nil
end

function GodSystemModularClient.receive(moduleName, command, packet)
    if not GodSystemModularClient.instance then return false end
    return GodSystemModularClient.instance:receive(moduleName, command, packet)
end

function GodSystemModularClient.poll()
    if GodSystemModularClient.instance then GodSystemModularClient.instance:poll() end
    if GodSystemModularClient.storage then GodSystemModularClient.storage:poll() end
end

GodSystemModularClient.lifecycleInstalled =
    GodSystemModularClient.lifecycleInstalled or false

function GodSystemModularClient.installLifecycle()
    if GodSystemModularClient.lifecycleInstalled then return true end
    if not GodSystemRuntimeMode
        or GodSystemRuntimeMode.modularEnabled ~= true
    then
        return false
    end
    local function startRuntime(_, actor)
        GodSystemModularClient.start()
        local instance = GodSystemModularClient.instance
        local runtime = instance and instance.runtime
        if runtime and runtime.coordinator then
            actor = actor or (getPlayer and getPlayer() or nil)
            if actor then runtime.coordinator.actorCreated(actor) end
        end
    end
    local function receive(moduleName, command, packet)
        GodSystemModularClient.receive(moduleName, command, packet)
    end
    local function stopRuntime()
        GodSystemModularClient.stop("clientStopped")
    end
    if Events.OnGameStart then Events.OnGameStart.Add(startRuntime) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(startRuntime) end
    if Events.OnServerCommand then Events.OnServerCommand.Add(receive) end
    if Events.OnTick then Events.OnTick.Add(GodSystemModularClient.poll) end
    if Events.OnDisconnect then Events.OnDisconnect.Add(stopRuntime) end
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(stopRuntime) end
    GodSystemModularClient.lifecycleInstalled = true
    return true
end

GodSystemModularClient.installLifecycle()

return GodSystemModularClient
