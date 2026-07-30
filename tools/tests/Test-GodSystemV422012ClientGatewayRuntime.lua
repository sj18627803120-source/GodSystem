local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local Gateway = require "GodSystem/Runtime/ClientGateway"
local Bindings = require "GodSystem/Platform/PZBindings"

local actor = {
    actorKey = "local",
    getX = function() return 1 end,
    getY = function() return 2 end,
    getZ = function() return 0 end,
    getZombieKills = function() return 7 end,
}
local calls = {}
local runtime = {
    dispatch = function(_, packet, target)
        calls[#calls + 1] = { packet = packet, actor = target }
        return {
            ok = true,
            code = "balance",
            data = { spendable = 99 },
            operationId = packet.operationId,
            moduleId = "feature.wallet",
        }
    end,
}
local updates = {}
local gateway = Gateway.new({
    runtime = runtime,
    actor = function() return actor end,
    onResult = function(action, result)
        updates[#updates + 1] = { action = action, result = result }
    end,
})
local balance = gateway:request("wallet.balance", {})
assert(balance.ok and balance.data.spendable == 99, "SP gateway result")
assert(calls[1].actor == actor and calls[1].packet.protocol == "42.20.1.2",
    "SP gateway protocol or actor")
assert(gateway:get("wallet.balance").data.spendable == 99,
    "SP gateway cache")
assert(#updates == 1 and not gateway:isPending("wallet.balance"),
    "SP gateway completion")

local callback
local remote = {
    request = function(_, action, args, options)
        callback = options.callback
        return options.requestId
    end,
}
local remoteGateway = Gateway.new({
    remote = remote,
    actor = function() return actor end,
})
local pending = remoteGateway:request("tasks.snapshot", {})
assert(pending.ok and pending.code == "requestPending"
    and remoteGateway:isPending("tasks.snapshot"), "MP gateway pending state")
callback({
    ok = true,
    code = "snapshot",
    data = { tasks = {} },
    moduleId = "feature.tasks",
})
assert(not remoteGateway:isPending("tasks.snapshot")
    and remoteGateway:get("tasks.snapshot").ok, "MP gateway completion")

local built = Bindings.build()
assert(built["runtime.coordinator"].actorKey(actor) == "local",
    "PZ actor identity binding")
local x, y, z = built["runtime.coordinator"].position(actor)
assert(x == 1 and y == 2 and z == 0
    and built["runtime.coordinator"].zombieKills(actor) == 7,
    "PZ observation bindings")
assert(built["wallet.accounts"].identity == built["storage.state"].identity,
    "identity binding was not reused")

print("Test-GodSystemV422012ClientGatewayRuntime passed")
