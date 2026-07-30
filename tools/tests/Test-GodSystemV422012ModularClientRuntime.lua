local luaRoot = assert(arg[1], "lua root required")

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function markLoaded(name)
    package.loaded[name] = true
end

for _, name in ipairs({
    "GodSystem/Runtime/PZClient",
    "GodSystem/Platform/Companion/PZVisuals",
    "GodSystem/UI/Facade",
    "GodSystem/UI/ShellAdapter",
    "GodSystem/UI/ActionAdapter",
    "GodSystem/UI/StorageAdapter",
    "GodSystem/UI/AutoLoaderAdapter",
    "GodSystem_AutoLoaderClient",
    "GodSystem_AutoLoaderUI",
    "GodSystem_UI",
}) do
    markLoaded(name)
end

local order = {}
local actor = { id = "local" }
local startRuntime = nil

Events = {
    OnGameStart = { Add = function(callback) startRuntime = callback end },
    OnCreatePlayer = { Add = function() end },
    OnServerCommand = { Add = function() end },
    OnTick = { Add = function() end },
    OnDisconnect = { Add = function() end },
    OnMainMenuEnter = { Add = function() end },
}

function isClient() return false end
function getPlayer() return actor end

GodSystemCompanionPZVisualsPlatform = {
    create = function()
        return {
            public = {},
            start = function() return true end,
            stop = function() return true end,
        }
    end,
}

GodSystemPZClientRuntime = {
    new = function()
        return {
            runtime = {
                coordinator = {
                    actorCreated = function(value)
                        expect(value == actor, "runtime actor was not forwarded")
                        order[#order + 1] = "actorCreated"
                    end,
                },
            },
            gateway = {},
            start = function() return true end,
            stop = function() return true end,
            receive = function() return true end,
            poll = function() return true end,
        }
    end,
}

GodSystemUIFacade = {
    new = function()
        return {
            refresh = function(_, queries)
                expect(type(queries) == "table" and queries[1] == "tasks.snapshot",
                    "startup did not request task projection")
                order[#order + 1] = "refresh"
            end,
            stop = function() return true end,
        }
    end,
    defaultQueries = function() return { "tasks.snapshot" } end,
}

local function adapter()
    return {
        install = function() return true end,
        stop = function() return true end,
    }
end

GodSystemUIShellAdapter = { new = adapter }
GodSystemUIActionAdapter = { new = adapter }
GodSystemUIStorageAdapter = { new = adapter }
GodSystemUIAutoLoaderAdapter = { new = adapter }
GodSystem = {}
GodSystemCompanion = {}
GodSystemStorageClient = {}
GodSystemStorage = {}
GodSystemStorageUI = {}
GodSystemStorageContext = {}
GodSystemAutoLoaderClient = {}
GodSystemAutoLoader = {}
GodSystemAutoLoaderUI = {}
GodSystemUI = {
    bindRuntime = function() end,
    bindGateway = function() end,
    bindFacade = function() end,
    onGameStart = function() end,
    stop = function() end,
}

dofile(luaRoot .. "/client/GodSystem_ModularClient.lua")
expect(type(startRuntime) == "function", "modular client did not register startup handler")
startRuntime(nil, actor)

local actorIndex, refreshIndex = nil, nil
for index = 1, #order do
    if order[index] == "actorCreated" then actorIndex = index end
    if order[index] == "refresh" then refreshIndex = index end
end
expect(actorIndex and refreshIndex and actorIndex < refreshIndex,
    "task generation must finish before the first UI refresh")

print("Test-GodSystemV422012ModularClientRuntime passed")
