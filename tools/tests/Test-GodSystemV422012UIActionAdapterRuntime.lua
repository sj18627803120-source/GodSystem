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
    request = function(_, action, args, options)
        calls[#calls + 1] = { action = action, args = args }
        local result = { ok = true, code = "accepted", data = {} }
        if action == "maintenance.execute" then
            result.code = "completed"
            result.data = {
                before = { condition = 4, conditionMax = 10 },
                after = { condition = 10, conditionMax = 10 },
            }
        end
        if options and options.callback then options.callback(result) end
        return result
    end,
}
local originalBank = function() return "old-bank" end
local originalVisible = function() return "old-visible" end
local target
target = {
    performBankAction = originalBank,
    text = function(key) return key end,
    notify = function(value) target.lastNotification = value end,
    getPlayer = function()
        return {
            getPrimaryHandItem = function()
                return {
                    getDisplayName = function() return "Axe" end,
                }
            end,
        }
    end,
    getInventoryRecycleGroups = function()
        return {
            ["Base.Scrap"] = {
                itemIds = { "i1", "i2", "i3" },
            },
        }
    end,
    getWaistSpaceRecycleGroups = function()
        return {
            ["Base.Plank"] = {
                items = { { id = "w1" }, { id = "w2" } },
            },
        }, { "Base.Plank" }, 1
    end,
}
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
assert(target.recycleInventoryItems("Base.Scrap", 2), "inventory recycle accepted")
assert(calls[#calls].action == "recycle.execute"
    and calls[#calls].args.mode == "recycleAndList"
    and #calls[#calls].args.itemIds == 2
    and calls[#calls].args.itemIds[2] == "i2",
    "inventory recycle exact item mapping")
assert(target.recycleWaistSpaceItems(nil), "terminal recycle accepted")
assert(calls[#calls].args.mode == "recycle"
    and #calls[#calls].args.itemIds == 2
    and calls[#calls].args.clientSkipped == 1,
    "terminal recycle exact item mapping")
assert(target.recycleSelectedItems("recycle", { "c1" }, true,
    { c1 = "1:7" }, 2), "context recycle accepted")
assert(calls[#calls].args.allowDestroyContents == true
    and calls[#calls].args.containerContentSignatures.c1 == "1:7",
    "context recycle confirmation mapping")
assert(target.toggleWaistAutoRecycle(), "auto recycle toggle accepted")
assert(calls[#calls].action == "recycle.preference"
    and calls[#calls].args.key == "waistAutoRecycleEnabled"
    and calls[#calls].args.value == true,
    "auto recycle preference mapping")
assert(target.useMaintenanceItem("repairHeld", { id = "repair-kit" }, "axe-1"),
    "maintenance action accepted")
assert(calls[#calls].action == "maintenance.execute"
    and calls[#calls].args.action == "repairItem"
    and calls[#calls].args.consumableId == "repair-kit"
    and calls[#calls].args.targetId == "axe-1",
    "maintenance action mapping")
assert(target.lastNotification == "Notify_MaintenanceRepairSuccess",
    "maintenance completion uses localized notification")

assert(adapter:stop(), "action adapter stop")
assert(target.performBankAction() == "old-bank", "bank action restored")
assert(companion.toggleVisible() == "old-visible", "companion action restored")

print("Test-GodSystemV422012UIActionAdapterRuntime passed")
