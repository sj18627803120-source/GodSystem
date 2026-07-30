local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local PZClient = require "GodSystem/Runtime/PZClient"
local PZServer = require "GodSystem/Runtime/PZServer"
local Protocol = require "GodSystem/Runtime/Protocol422012"

local legacy = {
    playerData = {
        version = "42.20.1.1",
        started = true,
        currencyInitialized = true,
        points = 0,
        tasks = {},
        unlockedShopItems = {},
        upgrades = {},
        bank = { current = 30 },
        homeSystem = {},
        companion = {},
        adminConfig = {},
        history = {},
        stats = {},
        ui = {},
    },
}
local function stateAdapter()
    local root = {}
    return {
        load = function() return root end,
        save = function(_, value) root = value return true end,
    }
end
local eventHandlers = {}
local eventAdapter = {
    add = function(_, name, handler) eventHandlers[name] = handler return true end,
    remove = function(_, name) eventHandlers[name] = nil return true end,
}
local sent = {}
local transport = {
    sendToServer = function(_, moduleName, command, packet)
        sent[#sent + 1] = { direction = "server", moduleName = moduleName,
            command = command, packet = packet }
        return true
    end,
    sendToClient = function(_, actor, moduleName, command, packet)
        sent[#sent + 1] = { direction = "client", actor = actor,
            moduleName = moduleName, command = command, packet = packet }
        return true
    end,
    send = function() return true end,
}
local actor = { actorKey = "local" }

local sp = PZClient.new({
    multiplayer = false,
    coordinate = false,
    actor = function() return actor end,
    stateAdapter = stateAdapter(),
    eventAdapter = eventAdapter,
    transport = transport,
    legacySnapshots = { { actorKey = "local", snapshot = legacy } },
    configSnapshot = { tasks = { templates = {} } },
})
assert(sp:start(), "SP PZ client start")
local balance = sp.gateway:request("wallet.balance", { scope = "current" })
assert(balance.ok and balance.data.value == 30, "SP PZ gateway dispatch")
assert(sp.runtime and sp.runtime.registry:get("feature.storage"),
    "SP PZ runtime missing feature modules")
assert(sp:stop("test"), "SP PZ client stop")

local mp = PZClient.new({
    multiplayer = true,
    actor = function() return actor end,
    transport = transport,
})
assert(mp:start(), "MP PZ client start")
assert(sent[#sent].command == Protocol.C2S.Hello, "MP PZ client hello")
local helloPacket = sent[#sent].packet
assert(mp:receive(Protocol.Module, Protocol.S2C.Hello, {
    protocol = Protocol.Version,
    requestId = helloPacket.requestId,
    operationId = helloPacket.operationId,
    result = {
        ok = true,
        code = "hello",
        data = { protocol = Protocol.Version },
        moduleId = "runtime.serverBridge",
    },
}), "MP PZ client hello response")
local pending = mp.gateway:request("tasks.snapshot", {})
assert(pending.ok and pending.code == "requestPending",
    "MP PZ gateway did not use remote transport")
assert(mp:stop("test"), "MP PZ client stop")

eventHandlers = {}
local server = PZServer.new({
    coordinate = false,
    stateAdapter = stateAdapter(),
    eventAdapter = eventAdapter,
    transport = transport,
    legacySnapshots = { { actorKey = "local", snapshot = legacy } },
    configSnapshot = { tasks = { templates = {} } },
})
assert(server:start(), "PZ server start")
assert(eventHandlers.OnClientCommand, "PZ server bridge event")
eventHandlers.OnClientCommand(Protocol.Module, Protocol.C2S.Hello, actor, {
    protocol = Protocol.Version,
    requestId = "hello-1",
    operationId = "hello-1",
})
assert(sent[#sent].direction == "client"
    and sent[#sent].command == Protocol.S2C.Hello,
    "PZ server bridge hello response")
assert(server:stop("test"), "PZ server stop")

print("Test-GodSystemV422012PZRuntimeRuntime passed")
