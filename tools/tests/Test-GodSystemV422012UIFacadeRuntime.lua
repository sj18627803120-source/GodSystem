local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local ReadModel = require "GodSystem/UI/ReadModel"
local Facade = require "GodSystem/UI/Facade"

local observer
local calls = {}
local responses = {
    ["diagnostics.snapshot"] = {
        version = "42.20.1.2",
        environment = "server",
        migration = { ok = true },
        modules = { { moduleId = "feature.wallet", state = "started" } },
    },
    ["system.snapshot"] = {
        started = true,
        ui = { windowX = 10 },
        history = { { kind = "test" } },
    },
    ["wallet.balance"] = { value = 55, scope = "spendable" },
    ["bank.summary"] = {
        current = 30,
        state = {
            current = 30,
            fixed = { { id = "F1", principal = 10 } },
            investments = { stable = { balance = 4 } },
        },
    },
    ["tasks.snapshot"] = {
        tasks = { { taskId = "T1" } },
        autoClaimEnabled = true,
        lastGeneratedDay = 7,
    },
    ["shop.catalog"] = {
        products = {
            { id = "built-in", source = "configured" },
            { id = "custom", variantKey = "Base.Custom", source = "unlocked" },
        },
    },
    ["recycle.snapshot"] = {
        recycleLimitDay = 7,
        recycleLimitUsed = 2,
        waistAutoRecycleEnabled = true,
    },
    ["upgrades.summary"] = {
        carryCapacityLevel = 3,
        maxActiveTasks = 4,
        dailyTaskCount = 6,
        terminalCapacityLevel = 2,
        terminalReductionLevel = 3,
        terminalReliefLevel = 4,
    },
    ["home.snapshot"] = { homeSystem = { homeSet = true } },
    ["terminal.status"] = { state = { claimedOnce = true }, owned = true },
    ["storage.status"] = { networkId = "N1", state = "installed" },
    ["companion.state"] = {
        persistent = { purchased = true },
        runtime = { state = "idle" },
    },
    ["admin.snapshot"] = { settings = { ShopEnabled = true } },
}
local gateway = {
    subscribe = function(_, callback)
        observer = callback
        return function() observer = nil return true end
    end,
    request = function(_, action, args)
        calls[#calls + 1] = { action = action, args = args }
        local result = {
            ok = true,
            code = action,
            data = responses[action] or {},
            operationId = "test:" .. action,
            moduleId = "test",
        }
        observer(action, result)
        return result
    end,
}

local model = ReadModel.new({ version = "42.20.1.2" })
local changes = 0
local facade = Facade.new({
    gateway = gateway,
    readModel = model,
    onChanged = function() changes = changes + 1 end,
})
facade:refresh()
local data = facade:data()
assert(data.started and data.ui.windowX == 10 and #data.history == 1,
    "system projection")
assert(data.modular.balance == 55 and data.bank.current == 30
    and data.bank.fixed[1].id == "F1", "wallet or bank projection")
assert(data.tasks[1].taskId == "T1" and data.autoTaskClaimEnabled,
    "tasks projection")
assert(data.unlockedShopItems["Base.Custom"]
    and not data.unlockedShopItems["built-in"], "shop projection")
assert(data.upgrades.carryCapacityLevel == 3
    and data.autoRecyclerReliefLevel == 4, "upgrades projection")
assert(data.homeSystem.homeSet and data.companion.purchased
    and data.adminConfig.settings.ShopEnabled, "feature projections")
assert(data.modular.storage.networkId == "N1"
    and data.modular.terminal.owned, "storage projection")
assert(data.modular.diagnostics.version == "42.20.1.2"
    and data.modular.diagnostics.modules[1].moduleId == "feature.wallet",
    "diagnostics projection")

local before = #calls
facade:request("bank.execute", { action = "deposit", amount = 5 })
assert(#calls == before + 4, "bank mutation refresh count")
assert(calls[before + 2].action == "wallet.balance"
    and calls[before + 3].action == "bank.summary"
    and calls[before + 4].action == "system.history",
    "bank mutation refresh routes")
assert(changes >= #calls, "change observer")

data.ui.windowX = 99
assert(model:snapshot().ui.windowX == 99,
    "view state should be isolated but locally mutable")
facade:stop()
assert(observer == nil, "facade unsubscribe")

print("Test-GodSystemV422012UIFacadeRuntime passed")
