local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local ActionAdapter = require "GodSystem/UI/ActionAdapter"

local data = { autoTaskClaimEnabled = false }
local calls = {}
local facade = {
    data = function() return data end,
    request = function(_, action, args)
        calls[#calls + 1] = { action = action, args = args }
        return { ok = true, code = "accepted", data = {} }
    end,
}
local originalBank = function() return "old-bank" end
local originalVisible = function() return "old-visible" end
local target = { performBankAction = originalBank }
local companion = { toggleVisible = originalVisible }
local adapter = ActionAdapter.new({
    facade = facade,
    target = target,
    companionTarget = companion,
})
assert(adapter:install(), "action adapter install")

assert(target.performBankAction("deposit", 25, "t1", "e1"), "bank action accepted")
assert(calls[#calls].action == "bank.execute"
    and calls[#calls].args.amount == 25
    and calls[#calls].args.termId == "t1", "bank action mapping")
assert(target.acceptTask({ taskId = "task-1" }), "task accept accepted")
assert(calls[#calls].action == "tasks.accept"
    and calls[#calls].args.taskId == "task-1", "task accept mapping")
assert(target.toggleAutoTaskClaim(), "auto claim accepted")
assert(calls[#calls].action == "tasks.autoClaim"
    and calls[#calls].args.enabled == true, "auto claim maps target state")
assert(target.performHomeAction("unlockSafeZone"), "safe zone unlock accepted")
assert(calls[#calls].action == "home.upgradeSafeZone", "safe zone unlock mapping")
assert(target.upgradeTerminal("reduction"), "terminal upgrade accepted")
assert(calls[#calls].action == "terminal.execute"
    and calls[#calls].args.action == "upgradeReduction", "terminal upgrade mapping")
assert(target.buyShopItem({ productId = "configured:item" }, 3), "shop purchase accepted")
assert(calls[#calls].action == "shop.purchase"
    and calls[#calls].args.productId == "configured:item"
    and calls[#calls].args.quantity == 3, "shop product mapping")
assert(companion.toggleVisible(), "companion visibility accepted")
assert(calls[#calls].action == "companion.visible", "companion visibility mapping")

assert(adapter:stop(), "action adapter stop")
assert(target.performBankAction() == "old-bank", "bank action restored")
assert(companion.toggleVisible() == "old-visible", "companion action restored")

print("Test-GodSystemV422012UIActionAdapterRuntime passed")
