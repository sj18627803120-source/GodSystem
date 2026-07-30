require "GodSystem/Platform/Commerce/Support"

local Support = GodSystemCommercePlatformSupport

GodSystemCommerceWalletPlatform = GodSystemCommerceWalletPlatform or {
    id = "commerce.wallet",
    dependencies = { "commerce.actor.identity" },
    stateVersion = 1,
}

function GodSystemCommerceWalletPlatform.create(dependencies, context)
    local identity = assert(dependencies["commerce.actor.identity"],
        "commerce.actor.identity dependency missing")
    local root = assert(context and context.state, "commerce.wallet context.state missing"):get()
    root.accounts = type(root.accounts) == "table" and root.accounts or {}
    local snapshot = type(context.configSnapshot) == "table" and context.configSnapshot or {}
    local walletConfig = type(snapshot.wallet) == "table" and snapshot.wallet or {}
    local instance = {
        started = false,
        charged = 0,
        credited = 0,
        restored = 0,
    }

    local function account(actor)
        local key = identity.key(actor)
        local value = root.accounts[key]
        if type(value) ~= "table" then
            value = { balance = Support.integer(walletConfig.initialBalance, 0, 0) }
            root.accounts[key] = value
        end
        value.balance = Support.integer(value.balance, 0, 0)
        return value, key
    end

    local function credit(actor, amount)
        amount = Support.integer(amount, 0, 0)
        if amount <= 0 then return false, "amountInvalid" end
        local value, key = account(actor)
        local receipt = { actorKey = key, kind = "credit", amount = amount, before = value.balance }
        value.balance = value.balance + amount
        receipt.after = value.balance
        instance.credited = instance.credited + amount
        return true, receipt
    end

    local function charge(actor, amount)
        amount = Support.integer(amount, 0, 0)
        if amount <= 0 then return false, "amountInvalid" end
        local value, key = account(actor)
        if value.balance < amount then return false, "insufficientFunds" end
        local receipt = { actorKey = key, kind = "charge", amount = amount, before = value.balance }
        value.balance = value.balance - amount
        receipt.after = value.balance
        instance.charged = instance.charged + amount
        return true, receipt
    end

    local function refund(actor, receipt)
        if type(receipt) ~= "table" or receipt.kind ~= "charge" then return false end
        local value, key = account(actor)
        if receipt.actorKey ~= key then return false end
        value.balance = value.balance + Support.integer(receipt.amount, 0, 0)
        instance.restored = instance.restored + Support.integer(receipt.amount, 0, 0)
        return true
    end

    local function revokeCredit(actor, receipt)
        if type(receipt) ~= "table" or receipt.kind ~= "credit" then return false end
        local value, key = account(actor)
        local amount = Support.integer(receipt.amount, 0, 0)
        if receipt.actorKey ~= key or value.balance < amount then return false end
        value.balance = value.balance - amount
        instance.restored = instance.restored + amount
        return true
    end

    instance.public = {
        balance = function(actor) return account(actor).balance end,
        setBalance = function(actor, amount)
            local value = account(actor)
            value.balance = Support.integer(amount, 0, 0)
            return true
        end,
        charge = charge,
        refund = refund,
        credit = credit,
        revokeCredit = revokeCredit,
        chargeUpTo = function(actor, amount)
            amount = Support.integer(amount, 0, 0)
            local value, key = account(actor)
            local paid = math.min(value.balance, amount)
            local receipt = {
                actorKey = key,
                kind = "charge",
                amount = paid,
                before = value.balance,
            }
            value.balance = value.balance - paid
            receipt.after = value.balance
            instance.charged = instance.charged + paid
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
