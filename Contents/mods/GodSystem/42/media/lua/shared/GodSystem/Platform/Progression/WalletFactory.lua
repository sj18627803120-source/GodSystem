require "GodSystem/Platform/Progression/Support"

GodSystemProgressionWalletFactory = GodSystemProgressionWalletFactory or {}

local Factory = GodSystemProgressionWalletFactory
local Support = GodSystemProgressionPlatformSupport

function Factory.descriptor(moduleId)
    local Descriptor = {
        id = moduleId,
        dependencies = { "wallet.funds" },
        stateVersion = 1,
    }

    function Descriptor.create(dependencies)
        local funds = assert(dependencies["wallet.funds"], "wallet.funds dependency missing")
        assert(type(funds.debit) == "function", "wallet.funds.debit missing")
        assert(type(funds.restore) == "function", "wallet.funds.restore missing")
        local counters = { charges = 0, refunds = 0, failures = 0 }
        local public = {}
        function public.charge(actor, amount)
            amount = Support.integer(amount, nil, 1)
            if amount == nil then
                counters.failures = counters.failures + 1
                return false, "amountInvalid"
            end
            local ok, receiptOrCode = funds.debit(actor, amount, "spendable")
            if ok == true and receiptOrCode ~= nil then
                counters.charges = counters.charges + 1
                return true, receiptOrCode
            end
            return false, receiptOrCode or "insufficientFunds"
        end
        function public.refund(actor, receipt)
            local ok, code = funds.restore(actor, receipt)
            if ok == true then
                counters.refunds = counters.refunds + 1
                return true
            end
            counters.failures = counters.failures + 1
            return false, code or "refundFailed"
        end
        return Support.lifecycle(moduleId, public, counters)
    end

    return Descriptor
end

return Factory
