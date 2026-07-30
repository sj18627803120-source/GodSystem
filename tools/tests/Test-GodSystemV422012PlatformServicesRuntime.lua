local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Bootstrap"
require "GodSystem/Services/Clock"
require "GodSystem/Services/Random"
require "GodSystem/Services/Operations"
require "GodSystem/Platform/WalletFunds"
require "GodSystem/Features/Wallet/Module"

local nextId = 1
local function item(fullType)
    local value = { id = nextId, fullType = fullType }
    nextId = nextId + 1
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    return value
end

local function list(values)
    local value = { values = values }
    function value:size() return #self.values end
    function value:get(index) return self.values[index + 1] end
    return value
end

local function container()
    local value = { values = {}, dirty = false }
    function value:getItems() return list(self.values) end
    function value:AddItem(input)
        local added = type(input) == "string" and item(input) or input
        if not added then return nil end
        self.values[#self.values + 1] = added
        added.container = self
        return added
    end
    function value:Remove(target)
        for index = #self.values, 1, -1 do
            if self.values[index] == target then
                table.remove(self.values, index)
                target.container = nil
                return
            end
        end
    end
    function value:setDrawDirty(flag) self.dirty = flag == true end
    return value
end

local inventory = container()
inventory:AddItem("GodSystem.SystemCoin100")
local actor = { inventory = inventory }
function actor:getInventory() return self.inventory end
function actor:getUsername() return "platform-test" end

local root = {}
local runtime = GodSystemBootstrap.create({
    version = "42.20.1.2",
    protocolVersion = "42.20.1.2",
    environment = "test",
    adapters = {
        state = {
            load = function() return root end,
            save = function(_, nextRoot) root = nextRoot return true end,
        },
    },
})

assert(runtime:register(GodSystemClockService))
assert(runtime:register(GodSystemRandomService))
assert(runtime:register(GodSystemOperationsService))
assert(runtime:register(GodSystemWalletFundsPlatform))
assert(runtime:register(GodSystemWalletFeatureModule))
assert(runtime:start().ok == true)

local fundsStatus = runtime.registry:status("wallet.funds")
local walletStatus = runtime.registry:status("feature.wallet")
local funds = assert(runtime.registry:get("wallet.funds"),
    "wallet.funds unavailable: " .. tostring(fundsStatus and fundsStatus.code)
        .. " " .. tostring(fundsStatus and fundsStatus.detail and fundsStatus.detail.message))
local wallet = assert(runtime.registry:get("feature.wallet"),
    "feature.wallet unavailable: " .. tostring(walletStatus and walletStatus.code))
assert(funds.balance(actor, "cash") == 100, "PZ cash inventory was not counted")
local credited, currentReceipt = funds.credit(actor, 50, "current")
assert(credited and currentReceipt.toCurrent == 50, "current account credit failed")
assert(wallet.getBalance(actor, "spendable") == 150, "spendable balance did not combine bank and cash")

local granted, grantReceipt = wallet.grant(actor, 25, {
    operationId = "wallet-grant-1",
    scope = "cash",
})
assert(granted and type(grantReceipt) == "table", "cash grant failed")
assert(wallet.getBalance(actor, "cash") == 125, "cash grant amount is wrong")

local charged, chargeReceipt = wallet.charge(actor, 120, {
    operationId = "wallet-charge-1",
    scope = "spendable",
})
assert(charged and type(chargeReceipt) == "table", "spendable charge failed")
assert(wallet.getBalance(actor, "spendable") == 55, "spendable charge did not use current then cash")

local replayed, replayReceipt = wallet.charge(actor, 120, {
    operationId = "wallet-charge-1",
    scope = "spendable",
})
assert(replayed and type(replayReceipt) == "table", "completed wallet operation did not replay")
assert(wallet.getBalance(actor, "spendable") == 55, "replayed charge mutated funds")

local refunded = wallet.refund(actor, chargeReceipt, {
    operationId = "wallet-refund-1",
})
assert(refunded == true, "wallet refund failed")
assert(wallet.getBalance(actor, "spendable") == 175, "wallet refund did not restore original sources")

local snapshot = runtime.state:scoped("wallet.funds", 1):snapshot()
snapshot.data.accounts["platform-test"].current = 999
assert(funds.balance(actor, "current") == 50, "deep state snapshot leaked into live wallet state")

local health = runtime:health()
assert(#health.modules == 5, "platform service health report incomplete")
runtime:stop("test")

print("Test-GodSystemV422012PlatformServicesRuntime passed")
