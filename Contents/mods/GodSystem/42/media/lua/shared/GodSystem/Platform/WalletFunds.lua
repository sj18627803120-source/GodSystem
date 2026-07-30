GodSystemWalletFundsPlatform = GodSystemWalletFundsPlatform or {}

local Descriptor = GodSystemWalletFundsPlatform

Descriptor.id = "wallet.funds"
Descriptor.dependencies = { "wallet.accounts" }
Descriptor.stateVersion = 1

local DEFAULT_DENOMINATIONS = {
    { fullType = "GodSystem.SystemCoin100", value = 100 },
    { fullType = "GodSystem.SystemCoin10", value = 10 },
    { fullType = "GodSystem.SystemCoin1", value = 1 },
}

local function integer(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return math.floor(value)
end

local function itemId(item)
    if not item or type(item.getID) ~= "function" then return nil end
    local value = item:getID()
    return value ~= nil and tostring(value) or nil
end

local function fullType(item)
    if not item or type(item.getFullType) ~= "function" then return nil end
    return tostring(item:getFullType() or "")
end

local function itemsArray(container)
    local result = {}
    if not container or type(container.getItems) ~= "function" then return result end
    local items = container:getItems()
    if not items or type(items.size) ~= "function" or type(items.get) ~= "function" then return result end
    for index = 0, items:size() - 1 do result[#result + 1] = items:get(index) end
    return result
end

local function collect(container, result, visited, depth)
    if not container or visited[container] or depth > 32 then return end
    visited[container] = true
    local items = itemsArray(container)
    for index = 1, #items do
        local item = items[index]
        result[#result + 1] = { item = item, container = container }
        if item and type(item.getInventory) == "function" then
            collect(item:getInventory(), result, visited, depth + 1)
        end
    end
end

local function inventoryRows(actor)
    local rows = {}
    local inventory = actor and type(actor.getInventory) == "function" and actor:getInventory() or nil
    collect(inventory, rows, {}, 0)
    return rows, inventory
end

local function denominationMap(source)
    source = type(source) == "table" and source or DEFAULT_DENOMINATIONS
    local rows = {}
    for index = 1, #source do
        local row = source[index]
        local value = integer(row and row.value)
        local itemType = tostring(row and row.fullType or "")
        if value and value > 0 and itemType ~= "" then
            rows[#rows + 1] = { fullType = itemType, value = value }
        end
    end
    table.sort(rows, function(left, right) return left.value > right.value end)
    return rows
end

local function currencyRows(actor, denominations)
    local byType = {}
    for index = 1, #denominations do byType[denominations[index].fullType] = denominations[index].value end
    local result, total = {}, 0
    local rows = inventoryRows(actor)
    for index = 1, #rows do
        local value = byType[fullType(rows[index].item)]
        if value then
            rows[index].value = value
            result[#result + 1] = rows[index]
            total = total + value
        end
    end
    table.sort(result, function(left, right)
        if left.value ~= right.value then return left.value > right.value end
        return tostring(itemId(left.item) or "") < tostring(itemId(right.item) or "")
    end)
    return result, total
end

local function markDirty(container)
    if container and type(container.setDrawDirty) == "function" then container:setDrawDirty(true) end
    if type(triggerEvent) == "function" then triggerEvent("OnContainerUpdate") end
end

local function syncAdded(container, item)
    if type(sendAddItemToContainer) == "function" then sendAddItemToContainer(container, item) end
end

local function syncRemoved(container, item)
    if type(sendRemoveItemFromContainer) == "function" then sendRemoveItemFromContainer(container, item) end
end

function Descriptor.create(dependencies, context)
    local accounts = assert(dependencies["wallet.accounts"], "wallet.accounts dependency missing")
    local binding = type(context.binding) == "table" and context.binding or {}
    local denominations = denominationMap(binding.denominations)
    local instance = { started = false, mutations = 0, failures = 0 }
    local public = {}

    local function portArguments(first, second, third, fourth)
        if first == public then return second, third, fourth end
        return first, second, third
    end

    local function currentBalance(actor)
        local value = accounts.get(actor)
        return math.max(0, integer(value) or 0)
    end

    local function cashBalance(actor)
        local _, total = currencyRows(actor, denominations)
        return total
    end

    local function balance(actor, scope)
        scope = tostring(scope or "spendable")
        local current = currentBalance(actor)
        local cash = cashBalance(actor)
        if scope == "cash" then return cash end
        if scope == "current" or scope == "bank" then return current end
        if scope == "spendable" then return current + cash end
        return 0
    end

    local function addCurrency(actor, amount)
        amount = integer(amount)
        if not amount or amount < 0 then return false, nil end
        local _, inventory = inventoryRows(actor)
        if not inventory or type(inventory.AddItem) ~= "function" then return false, nil end
        local added, remaining = {}, amount
        for index = 1, #denominations do
            local row = denominations[index]
            local count = math.floor(remaining / row.value)
            for _ = 1, count do
                local item = inventory:AddItem(row.fullType)
                if not item then
                    for addedIndex = #added, 1, -1 do
                        inventory:Remove(added[addedIndex].item)
                        syncRemoved(inventory, added[addedIndex].item)
                    end
                    return false, nil
                end
                added[#added + 1] = { item = item, container = inventory, fullType = row.fullType, value = row.value }
                syncAdded(inventory, item)
                remaining = remaining - row.value
            end
        end
        if remaining ~= 0 then return false, nil end
        markDirty(inventory)
        return true, added
    end

    local function removeAdded(rows)
        for index = #(rows or {}), 1, -1 do
            local row = rows[index]
            if row.container and type(row.container.Remove) == "function" then
                row.container:Remove(row.item)
                syncRemoved(row.container, row.item)
            end
        end
        return true
    end

    local function restoreRemoved(rows, actor)
        local inventory = actor and actor:getInventory() or nil
        local complete = true
        for index = 1, #(rows or {}) do
            local row = rows[index]
            local container = row.container or inventory
            local added = container and type(container.AddItem) == "function" and container:AddItem(row.item) or nil
            if not added and inventory and container ~= inventory then added = inventory:AddItem(row.item) end
            if not added then complete = false
            else syncAdded(container, added) end
        end
        markDirty(inventory)
        return complete
    end

    local function removeCurrency(actor, amount)
        local rows, total = currencyRows(actor, denominations)
        if total < amount then return false, "balanceInsufficient" end
        local removed, value = {}, 0
        for index = 1, #rows do
            if value >= amount then break end
            local row = rows[index]
            if row.container and type(row.container.Remove) == "function" then
                row.container:Remove(row.item)
                removed[#removed + 1] = row
                value = value + row.value
                syncRemoved(row.container, row.item)
            end
        end
        if value < amount then
            restoreRemoved(removed, actor)
            return false, "cashRemovalFailed"
        end
        local change = value - amount
        local changeAdded = {}
        if change > 0 then
            local ok
            ok, changeAdded = addCurrency(actor, change)
            if not ok then
                restoreRemoved(removed, actor)
                return false, "cashChangeFailed"
            end
        end
        return true, {
            kind = "cashDebit",
            amount = amount,
            removed = removed,
            changeAdded = changeAdded,
        }
    end

    local function debit(actor, amount, scope)
        amount = integer(amount)
        if not amount or amount <= 0 then return false, "amountInvalid" end
        scope = tostring(scope or "spendable")
        if balance(actor, scope) < amount then return false, "balanceInsufficient" end
        local current = currentBalance(actor)
        local fromCurrent = 0
        local fromCash = amount
        if scope == "current" or scope == "bank" then
            fromCurrent, fromCash = amount, 0
        elseif scope == "spendable" then
            fromCurrent = math.min(current, amount)
            fromCash = amount - fromCurrent
        elseif scope ~= "cash" then
            return false, "scopeInvalid"
        end
        if fromCurrent > 0 then
            local debited = accounts.debit(actor, fromCurrent)
            if debited ~= true then return false, "currentDebitFailed" end
        end
        local cashReceipt = nil
        if fromCash > 0 then
            local ok, receiptOrCode = removeCurrency(actor, fromCash)
            if not ok then
                if fromCurrent > 0 then accounts.credit(actor, fromCurrent) end
                instance.failures = instance.failures + 1
                return false, receiptOrCode
            end
            cashReceipt = receiptOrCode
        end
        instance.mutations = instance.mutations + 1
        return true, {
            kind = "debit",
            id = tostring(context.moduleId) .. ":" .. tostring(instance.mutations),
            amount = amount,
            scope = scope,
            fromCurrent = fromCurrent,
            fromCash = fromCash,
            cashReceipt = cashReceipt,
        }
    end

    local function credit(actor, amount, scope)
        amount = integer(amount)
        if not amount or amount <= 0 then return false, "amountInvalid" end
        scope = tostring(scope or "cash")
        local receipt = {
            kind = "credit",
            id = tostring(context.moduleId) .. ":" .. tostring(instance.mutations + 1),
            amount = amount,
            scope = scope,
        }
        if scope == "current" or scope == "bank" then
            local credited = accounts.credit(actor, amount)
            if credited ~= true then return false, "currentCreditFailed" end
            receipt.toCurrent = amount
        elseif scope == "cash" then
            local ok, added = addCurrency(actor, amount)
            if not ok then
                instance.failures = instance.failures + 1
                return false, "cashGrantFailed"
            end
            receipt.added = added
        else
            return false, "scopeInvalid"
        end
        instance.mutations = instance.mutations + 1
        return true, receipt
    end

    local function restore(actor, receipt)
        if type(receipt) ~= "table" then return false, "receiptInvalid" end
        if receipt.kind == "debit" then
            if receipt.cashReceipt then
                removeAdded(receipt.cashReceipt.changeAdded)
                if not restoreRemoved(receipt.cashReceipt.removed, actor) then
                    instance.failures = instance.failures + 1
                    return false, "cashRestoreFailed"
                end
            end
            local current = math.max(0, integer(receipt.fromCurrent) or 0)
            if current > 0 and accounts.credit(actor, current) ~= true then
                return false, "currentRestoreFailed"
            end
            return true
        end
        if receipt.kind == "credit" then
            if receipt.added and not removeAdded(receipt.added) then return false, "creditRestoreFailed" end
            local current = math.max(0, integer(receipt.toCurrent) or 0)
            if current > currentBalance(actor) then return false, "creditRestoreFailed" end
            if current > 0 and accounts.debit(actor, current) ~= true then
                return false, "creditRestoreFailed"
            end
            return true
        end
        return false, "receiptInvalid"
    end

    public = {
        balance = function(first, second, third)
            local actor, scope = portArguments(first, second, third)
            return balance(actor, scope)
        end,
        debit = function(first, second, third, fourth)
            local actor, amount, scope = portArguments(first, second, third, fourth)
            return debit(actor, amount, scope)
        end,
        credit = function(first, second, third, fourth)
            local actor, amount, scope = portArguments(first, second, third, fourth)
            return credit(actor, amount, scope)
        end,
        restore = function(first, second, third)
            local actor, receipt = portArguments(first, second, third)
            return restore(actor, receipt)
        end,
        health = function()
            return instance.failures == 0, {
                mutations = instance.mutations,
                failures = instance.failures,
            }
        end,
    }
    instance.public = public
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "fundsFailure" or (self.started and "healthy" or "stopped"),
            data = { mutations = self.mutations, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
