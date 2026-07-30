local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Runtime/RemoteClient"
require "GodSystem/Runtime/ServerBridge"

local now = 1000
local clientPackets = {}
local serverPackets = {}
local executions = {}
local actorA = { key = "alice" }
local actorB = { key = "bob" }

local dispatcher = {
    dispatch = function(_, packet, actor)
        local key = actor.key .. "|" .. tostring(packet.operationId)
        executions[key] = (executions[key] or 0) + 1
        if packet.action == "test.explode" then error("expected dispatcher failure") end
        return {
            ok = true,
            code = "executed",
            data = { actor = actor.key, value = packet.args.value },
            moduleId = "feature.test",
            operationId = packet.operationId,
        }
    end,
}

local serverTransport = {
    sendToClient = function(_, actor, moduleName, command, packet)
        serverPackets[#serverPackets + 1] = {
            actor = actor,
            moduleName = moduleName,
            command = command,
            packet = packet,
        }
        return true
    end,
}
local server = GodSystemServerBridge.new({
    transport = serverTransport,
    dispatcher = dispatcher,
    actorKey = function(actor) return actor.key end,
})

local clientTransport = {
    sendToServer = function(_, moduleName, command, packet)
        clientPackets[#clientPackets + 1] = {
            moduleName = moduleName,
            command = command,
            packet = packet,
        }
        return true
    end,
}
local callbacks = {}
local client = GodSystemRemoteClient.new({
    transport = clientTransport,
    now = function() return now end,
    timeoutMs = 100,
    nextRequestId = function(sequence) return "request-" .. tostring(sequence) end,
})

local helloId = client:hello({}, {
    operationId = "hello-operation",
    callback = function(result) callbacks.hello = result end,
})
assert(helloId == "request-1" and #clientPackets == 1, "hello was not sent")
local hello = clientPackets[1]
server:receive(actorA, hello.moduleName, hello.command, hello.packet)
assert(#serverPackets == 1 and serverPackets[1].command == GodSystemProtocol422012.S2C.Hello,
    "server did not answer hello")
local helloReply = serverPackets[1]
assert(client:receive(helloReply.moduleName, helloReply.command, helloReply.packet) == true,
    "client rejected valid hello")
assert(client:status().connected and callbacks.hello.ok, "hello did not connect client")

local requestId = client:request("test.run", { value = 7 }, {
    operationId = "operation-shared",
    callback = function(result) callbacks.first = result end,
})
assert(requestId == "request-2", "request id drifted")
local firstPacket = clientPackets[#clientPackets]
server:receive(actorA, firstPacket.moduleName, firstPacket.command, firstPacket.packet)
local firstReply = serverPackets[#serverPackets]
assert(client:receive(firstReply.moduleName, firstReply.command, firstReply.packet) == true,
    "client rejected valid response")
assert(callbacks.first.ok and callbacks.first.data.value == 7,
    "response did not reach callback")
assert(executions["alice|operation-shared"] == 1, "request executed wrong number of times")

local replayPacket = {
    protocol = "42.20.1.2",
    requestId = "request-retry",
    operationId = "operation-shared",
    action = "test.run",
    args = { value = 7 },
}
server:receive(actorA, GodSystemProtocol422012.Module,
    GodSystemProtocol422012.C2S.Request, replayPacket)
assert(executions["alice|operation-shared"] == 1, "server repeated completed operation")
assert(server:status().replays == 1, "server did not report replay")

server:receive(actorB, GodSystemProtocol422012.Module,
    GodSystemProtocol422012.C2S.Hello, {
        protocol = "42.20.1.2",
        requestId = "bob-hello",
        operationId = "bob-hello",
        action = "runtime.hello",
        args = {},
    })
server:receive(actorB, GodSystemProtocol422012.Module,
    GodSystemProtocol422012.C2S.Request, {
        protocol = "42.20.1.2",
        requestId = "bob-request",
        operationId = "operation-shared",
        action = "test.run",
        args = { value = 9 },
    })
assert(executions["bob|operation-shared"] == 1,
    "operation cache leaked across players")

local mismatch = server:receive(actorA, GodSystemProtocol422012.Module,
    GodSystemProtocol422012.C2S.Request, {
        protocol = "42.20.1.1",
        requestId = "old-request",
        operationId = "old-operation",
        action = "test.run",
        args = {},
    })
assert(mismatch.result.code == "protocolMismatch", "old protocol was accepted")

local lateId = client:request("test.run", { value = 10 }, {
    operationId = "late-operation",
    callback = function(result) callbacks.late = result end,
})
assert(lateId ~= nil, "timeout request was not queued")
now = 1200
local expired = client:poll()
assert(#expired == 1 and expired[1].code == "requestTimeout",
    "timeout was not reported")
assert(callbacks.late.code == "requestTimeout" and client:pendingCount() == 0,
    "timeout did not clear pending request")

local disconnectId = client:request("test.run", { value = 11 }, {
    operationId = "disconnect-operation",
    callback = function(result) callbacks.disconnect = result end,
})
assert(disconnectId ~= nil and client:disconnect("test") == 1,
    "disconnect did not clear pending request")
assert(callbacks.disconnect.code == "disconnected" and not client:status().connected,
    "disconnect result drifted")

print("Test-GodSystemV422012RemoteBridgeRuntime passed")
