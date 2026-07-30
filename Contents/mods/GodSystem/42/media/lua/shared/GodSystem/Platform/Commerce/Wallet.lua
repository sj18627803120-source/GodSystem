require "GodSystem/Platform/Commerce/Support"

local Support = GodSystemCommercePlatformSupport

GodSystemCommerceWalletPlatform = GodSystemCommerceWalletPlatform or {
    id = "commerce.wallet",
    dependencies = { "wallet.funds" },
    stateVersion = 1,
}

function GodSystemCommerceWalletPlatform.create(dependencies)
    local funds = assert(dependencies["wallet.funds"], "wallet.funds dependency missing")
    assert(type(funds.balance) == "function", "wallet.funds.balance missing")
    assert(type(funds.debit) == "function", "wallet.funds.debit missing")
    assert(type(funds.credit) == "function", "wallet.funds.credit missing")
    assert(type(funds.restore) == "function", "wallet.funds.restore missing")
    local instance = {
        started = false,
        charged = 0,
        credited = 0,
        restored = 0,
    }

    local function credit(actor, amount)
        amount = Support.integer(amount, 0, 0)
        if amount <= 0 then return false, "amountInvalid" end
        local ok, receipt = funds.credit(actor, amount, "cash")
        if ok ~= true then return false, receipt or "creditFailed" end
        instance.credited = instance.credited + amount
        return true, receipt
    end

    local function charge(actor, amount)
        amount = Support.integer(amount, 0, 0)
        if amount <= 0 then return false, "amountInvalid" end
        local ok, receipt = funds.debit(actor, amount, "spendable")
        if ok ~= true then return false, receipt or "insufficientFunds" end
        instance.charged = instance.charged + amount
        return true, receipt
    end

    local function refund(actor, receipt)
        if type(receipt) == "table" and receipt.kind == "none" then return true end
        local ok = funds.restore(actor, receipt)
        if ok ~= true then return false end
        instance.restored = instance.restored + Support.integer(receipt and receipt.amount, 0, 0)
        return true
    end

    local function revokeCredit(actor, receipt)
        return refund(actor, receipt)
    end

    instance.public = {
        balance = function(actor)
            return Support.integer(funds.balance(actor, "spendable"), 0, 0)
        end,
        charge = charge,
        refund = refund,
        credit = credit,
        revokeCredit = revokeCredit,
        chargeUpTo = function(actor, amount)
            amount = Support.integer(amount, 0, 0)
            local paid = math.min(instance.public.balance(actor), amount)
            if paid <= 0 then return true, { kind = "none", amount = 0 }, 0 end
            local ok, receipt = charge(actor, paid)
            if ok ~= true then return false, receipt, 0 end
            return true, receipt, paid
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = {
                charged = self.charged,
                credited = self.credited,
                restored = self.restored,
            },
            moduleId = GodSystemCommerceWalletPlatform.id,
        }
    end
    return instance
end

local function descriptor(id, methods)
    local value = { id = id, dependencies = { "commerce.wallet" }, stateVersion = 1 }
    function value.create(dependencies)
        local wallet = assert(dependencies["commerce.wallet"], "commerce.wallet dependency missing")
        local instance = { started = false }
        instance.public = {}
        for name, source in pairs(methods) do
            instance.public[name] = function(...) return wallet[source](...) end
        end
        function instance:start() self.started = true return true end
        function instance:stop() self.started = false return true end
        function instance:health()
            return {
                ok = self.started,
                code = self.started and "healthy" or "stopped",
                data = {},
                moduleId = id,
            }
        end
        return instance
    end
    return value
end

GodSystemTasksWalletPlatform = GodSystemTasksWalletPlatform or descriptor("tasks.wallet", {
    credit = "credit",
    revokeCredit = "revokeCredit",
    chargePenalty = "chargeUpTo",
    refundPenalty = "refund",
})
GodSystemShopWalletPlatform = GodSystemShopWalletPlatform or descriptor("shop.wallet", {
    charge = "charge",
    refund = "refund",
})
GodSystemRecycleWalletPlatform = GodSystemRecycleWalletPlatform or descriptor("recycle.wallet", {
    charge = "charge",
    refund = "refund",
    credit = "credit",
    revokeCredit = "revokeCredit",
})

return {
    commerce = GodSystemCommerceWalletPlatform,
    tasks = GodSystemTasksWalletPlatform,
    shop = GodSystemShopWalletPlatform,
    recycle = GodSystemRecycleWalletPlatform,
}
