local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Features/Tasks/Module"
require "GodSystem/Features/Shop/Module"
require "GodSystem/Features/Recycle/Module"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
    return result
end

local function newOperations()
    local rows = {}
    return {
        begin = function(moduleId, operationId, fingerprint)
            local key = tostring(moduleId) .. "|" .. tostring(operationId)
            local row = rows[key]
            if row then
                if row.fingerprint ~= fingerprint then return "blocked", "operationMismatch" end
                if row.result then return "replay", row.result end
                return "blocked", "operationPending"
            end
            rows[key] = { fingerprint = fingerprint }
            return "new"
        end,
        finish = function(moduleId, operationId, result)
            local key = tostring(moduleId) .. "|" .. tostring(operationId)
            assert(rows[key], "operation was not begun")
            rows[key].result = result
            return true
        end,
    }
end

local function newNotifications()
    local values = {}
    return {
        values = values,
        publish = function(value)
            values[#values + 1] = value
            return true
        end,
    }
end

local function taskFixture(environment)
    local fixture = {
        environment = environment,
        actor = { id = environment .. "-player" },
        data = { tasks = {}, stats = {} },
        counts = { ["Base.Scrap"] = 2 },
        balance = 100,
        rewardPoints = 0,
        rewardItems = 0,
        now = 50,
        day = 5,
        failGrant = false,
        failNextSave = false,
    }
    local templates = {
        {
            id = "turnin",
            title = "Turn in",
            kind = "turnInItem",
            target = 2,
            item = "Base.Scrap",
            limitHours = 12,
            rewardPoints = 20,
            rewardItems = { { fullType = "Base.Bandage", count = 1 } },
            penaltyPoints = 4,
        },
        {
            id = "kill",
            title = "Kill",
            kind = "kill",
            target = 3,
            rewardPoints = 5,
            penaltyPoints = 7,
        },
    }
    local notifications = newNotifications()
    local dependencies = {
        ["tasks.config"] = {
            getTemplates = function() return clone(templates) end,
            getDailyCount = function() return 2 end,
            getMaxActive = function() return 3 end,
            getDefaultLimitHours = function() return 24 end,
        },
        ["tasks.state"] = {
            load = function() return fixture.data end,
            save = function(_, data)
                if fixture.failNextSave then
                    fixture.failNextSave = false
                    return false, "stateSaveFailed"
                end
                fixture.data = clone(data)
                return true
            end,
        },
        ["tasks.inventory"] = {
            count = function(_, fullTypes)
                local count = 0
                for i = 1, #(fullTypes or {}) do count = count + (fixture.counts[fullTypes[i]] or 0) end
                return count
            end,
            consume = function(_, fullTypes, count)
                local remaining = count
                local removed = {}
                for i = 1, #fullTypes do
                    local fullType = fullTypes[i]
                    local take = math.min(remaining, fixture.counts[fullType] or 0)
                    if take > 0 then
                        fixture.counts[fullType] = fixture.counts[fullType] - take
                        removed[#removed + 1] = { fullType = fullType, count = take }
                        remaining = remaining - take
                    end
                end
                if remaining > 0 then
                    for i = 1, #removed do
                        fixture.counts[removed[i].fullType] = (fixture.counts[removed[i].fullType] or 0) + removed[i].count
                    end
                    return false, "turnInNotEnough"
                end
                return true, removed
            end,
            restore = function(_, receipt)
                for i = 1, #receipt do
                    fixture.counts[receipt[i].fullType] = (fixture.counts[receipt[i].fullType] or 0) + receipt[i].count
                end
                return true
            end,
            grant = function(_, items)
                if fixture.failGrant then return false, "rewardFailed" end
                local count = 0
                for i = 1, #items do count = count + (items[i].count or 1) end
                fixture.rewardItems = fixture.rewardItems + count
                return true, { count = count }
            end,
            revoke = function(_, receipt)
                fixture.rewardItems = fixture.rewardItems - receipt.count
                return true
            end,
        },
        ["tasks.wallet"] = {
            credit = function(_, amount)
                fixture.rewardPoints = fixture.rewardPoints + amount
                return true, { amount = amount }
            end,
            revokeCredit = function(_, receipt)
                fixture.rewardPoints = fixture.rewardPoints - receipt.amount
                return true
            end,
            chargePenalty = function(_, amount)
                local paid = math.min(amount, fixture.balance)
                fixture.balance = fixture.balance - paid
                return true, { amount = paid }, paid
            end,
            refundPenalty = function(_, receipt)
                fixture.balance = fixture.balance + receipt.amount
                return true
            end,
        },
        clock = {
            nowHours = function() return fixture.now end,
            currentDay = function() return fixture.day end,
        },
        random = { index = function() return 1 end },
        operations = newOperations(),
        notifications = notifications,
    }
    fixture.instance = GodSystemTasksFeatureModule.create(dependencies, {
        moduleId = "feature.tasks",
        environment = environment,
    })
    assert(fixture.instance:start())
    return fixture
end

local function runTaskSuccess(environment)
    local f = taskFixture(environment)
    local generated = f.instance.public.generate({
        actor = f.actor,
        operationId = environment .. "-generate",
    })
    assert(generated.ok and generated.code == "generated" and generated.data.count == 2, "task generation failed")
    assert(#f.data.tasks == 2 and f.data.tasks[1].kind == "turnInItem", "task templates were not generated")
    local turnInId = f.data.tasks[1].taskId
    local accepted = f.instance.public.accept({
        actor = f.actor,
        taskId = turnInId,
        operationId = environment .. "-accept",
    })
    assert(accepted.ok and f.data.tasks[1].status == "active", "task accept failed")
    local progress = f.instance.public.progress({ actor = f.actor, taskId = turnInId })
    assert(progress.ok and progress.data.value == 2 and progress.data.complete, "turn-in progress is wrong")
    local claimed = f.instance.public.claim({
        actor = f.actor,
        taskId = turnInId,
        operationId = environment .. "-claim",
    })
    assert(claimed.ok and claimed.code == "claimed", "task claim failed")
    assert(f.counts["Base.Scrap"] == 0 and f.rewardPoints == 20 and f.rewardItems == 1,
        "task rewards or turn-in settlement are wrong")
    local replay = f.instance.public.claim({
        actor = f.actor,
        taskId = turnInId,
        operationId = environment .. "-claim",
    })
    assert(replay == claimed and f.rewardPoints == 20 and f.rewardItems == 1, "task claim was not idempotent")

    local killId = f.data.tasks[2].taskId
    assert(f.instance.public.accept({
        actor = f.actor,
        taskId = killId,
        operationId = environment .. "-accept-kill",
    }).ok)
    local failed = f.instance.public.fail({
        actor = f.actor,
        taskId = killId,
        operationId = environment .. "-fail",
    })
    assert(failed.ok and failed.code == "failed" and failed.data.penaltyPaid == 7, "task failure failed")
    assert(f.balance == 93 and f.data.stats.failedTasks == 1, "task failure penalty is wrong")
    return table.concat({ claimed.code, failed.code, f.rewardPoints, f.rewardItems, f.balance }, "|")
end

assert(runTaskSuccess("sp") == runTaskSuccess("mp"), "SP/MP task behavior diverged")

do
    local f = taskFixture("task-rollback")
    assert(f.instance.public.generate({ actor = f.actor, operationId = "tg" }).ok)
    local id = f.data.tasks[1].taskId
    assert(f.instance.public.accept({ actor = f.actor, taskId = id, operationId = "ta" }).ok)
    f.failGrant = true
    local result = f.instance.public.claim({ actor = f.actor, taskId = id, operationId = "tc" })
    assert(not result.ok and result.code == "rewardFailed", "task reward failure code was lost")
    assert(f.counts["Base.Scrap"] == 2 and f.rewardPoints == 0 and f.data.tasks[1].status == "active",
        "task claim rollback was incomplete")
end

do
    local f = taskFixture("task-expired")
    assert(f.instance.public.generate({ actor = f.actor, operationId = "teg" }).ok)
    local killId = f.data.tasks[2].taskId
    assert(f.instance.public.accept({ actor = f.actor, taskId = killId, operationId = "tea" }).ok)
    f.now = f.data.tasks[2].deadline + 1
    local result = f.instance.public.claim({
        actor = f.actor,
        taskId = killId,
        killProgress = 0,
        operationId = "tec",
    })
    assert(not result.ok and result.code == "taskFailed" and result.data.expired == true,
        "expired incomplete task did not fail")
    assert(f.data.tasks[2].status == "failed" and f.balance == 93,
        "expired task penalty or state is wrong")
end

local function shopFixture(environment)
    local fixture = {
        actor = { id = environment .. "-player" },
        data = { unlockedShopItems = {}, stats = {} },
        balance = 200,
        now = 80,
        items = {
            chair1 = {
                id = "chair1", fullType = "Mod.Chair", worldSprite = "mod_chair_01",
                label = "Chair 1", buyPrice = 40, sellPrice = 10, categoryKey = "furniture",
            },
            chair2 = {
                id = "chair2", fullType = "Mod.Chair", worldSprite = "mod_chair_02",
                label = "Chair 2", buyPrice = 40, sellPrice = 10, categoryKey = "furniture",
            },
        },
        grants = {},
        failCharge = false,
        failSave = false,
    }
    local notifications = newNotifications()
    local function variantKey(fullType, sprite)
        return tostring(fullType) .. (sprite and ("@worldSprite=" .. tostring(sprite)) or "")
    end
    local dependencies = {
        ["shop.config"] = {
            resolveProduct = function(_, productId)
                if productId == "configured:bandage" then
                    return {
                        id = productId,
                        source = "configured",
                        label = "Bandage",
                        price = 6,
                        items = { { fullType = "Base.Bandage", count = 1 } },
                    }, "configured"
                end
                return nil, "productMissing"
            end,
            configuredCandidates = function(_, category)
                if category == "medical" or category == "all" then
                    return {
                        {
                            label = "Bandage",
                            categoryKey = "medical",
                            items = { { fullType = "Base.Bandage", count = 1 } },
                        },
                    }
                end
                return {}
            end,
            isConfigured = function() return false end,
            purchasePrice = function(_, product, quantity) return (product.price or 40) * quantity end,
            listingPrice = function() return 10 end,
            lotteryPrice = function(_, _, count) return 5 * count end,
        },
        ["shop.state"] = {
            load = function() return fixture.data end,
            save = function(_, data)
                if fixture.failSave then
                    fixture.failSave = false
                    return false, "stateSaveFailed"
                end
                fixture.data = clone(data)
                return true
            end,
        },
        ["shop.identity"] = {
            variantKey = variantKey,
            productId = function(row, source)
                if source == "configured" then return tostring(row.id) end
                return "unlocked:" .. tostring(row.variantKey)
            end,
        },
        ["shop.inventory"] = {
            resolve = function(_, itemId) return fixture.items[itemId], "itemMissing" end,
            grant = function(_, entries)
                local receipt = { entries = clone(entries) }
                fixture.grants[#fixture.grants + 1] = receipt
                return true, receipt
            end,
            revoke = function(_, receipt)
                for i = #fixture.grants, 1, -1 do
                    if fixture.grants[i] == receipt then table.remove(fixture.grants, i) return true end
                end
                return false
            end,
        },
        ["shop.wallet"] = {
            charge = function(_, amount)
                if fixture.failCharge or fixture.balance < amount then return false, "insufficientFunds" end
                fixture.balance = fixture.balance - amount
                return true, { amount = amount }
            end,
            refund = function(_, receipt)
                fixture.balance = fixture.balance + receipt.amount
                return true
            end,
        },
        ["item.eligibility"] = {
            allowed = function(fullType)
                if fullType == "Base.HiddenDebug" then return false, "itemNotEligible" end
                return fullType:find(".", 1, true) ~= nil
            end,
        },
        clock = { nowHours = function() return fixture.now end },
        random = { index = function(maximum) return maximum end },
        operations = newOperations(),
        notifications = notifications,
    }
    fixture.instance = GodSystemShopFeatureModule.create(dependencies, {
        moduleId = "feature.shop",
        environment = environment,
    })
    assert(fixture.instance:start())
    fixture.variantKey = variantKey
    return fixture
end

local function runShopSuccess(environment)
    local f = shopFixture(environment)
    local first = f.instance.public.listItem({
        actor = f.actor, itemId = "chair1", operationId = environment .. "-list-1",
    })
    local second = f.instance.public.listItem({
        actor = f.actor, itemId = "chair2", operationId = environment .. "-list-2",
    })
    assert(first.ok and second.ok and first.data.variantKey ~= second.data.variantKey,
        "furniture variants did not receive stable independent identities")
    local firstKey, secondKey = first.data.variantKey, second.data.variantKey
    assert(f.balance == 180, "listing fees are wrong")

    local hidden = f.instance.public.setHidden({
        actor = f.actor, variantKey = firstKey, hidden = true, operationId = environment .. "-hide",
    })
    assert(hidden.ok and f.data.unlockedShopItems[firstKey].hidden == true, "listing was not hidden")
    local stale = f.instance.public.purchase({
        actor = f.actor, productId = "unlocked:" .. firstKey, quantity = 1,
        operationId = environment .. "-hidden-buy",
    })
    assert(not stale.ok and stale.code == "productHidden", "hidden listing was directly purchasable")

    local purchased = f.instance.public.purchase({
        actor = f.actor, productId = "unlocked:" .. secondKey, quantity = 1,
        operationId = environment .. "-buy",
    })
    assert(purchased.ok and purchased.data.items[1].worldSprite == "mod_chair_02",
        "furniture worldSprite did not pass through the inventory port")
    local grantsBeforeReplay = #f.grants
    local purchaseReplay = f.instance.public.purchase({
        actor = f.actor, productId = "unlocked:" .. secondKey, quantity = 1,
        operationId = environment .. "-buy",
    })
    assert(purchaseReplay == purchased and #f.grants == grantsBeforeReplay, "shop purchase was not idempotent")

    assert(f.instance.public.deleteListing({
        actor = f.actor, variantKey = secondKey, operationId = environment .. "-delete",
    }).ok)
    local lottery = f.instance.public.lottery({
        actor = f.actor, category = "furniture", count = 1,
        operationId = environment .. "-lottery",
    })
    assert(lottery.ok and lottery.data.selected[1].hidden == true and
        lottery.data.selected[1].fullType == "Mod.Chair",
        "hidden listing did not remain in the lottery pool")
    return table.concat({ first.code, purchased.code, lottery.code, f.balance }, "|")
end

assert(runShopSuccess("sp") == runShopSuccess("mp"), "SP/MP shop behavior diverged")

do
    local f = shopFixture("shop-rollback")
    f.failCharge = true
    local result = f.instance.public.purchase({
        actor = f.actor, productId = "configured:bandage", quantity = 2, operationId = "shop-fail",
    })
    assert(not result.ok and result.code == "insufficientFunds", "purchase payment failure code was lost")
    assert(#f.grants == 0 and f.balance == 200, "failed purchase did not revoke granted items")
end

local function recycleFixture(environment)
    local fixture = {
        actor = { id = environment .. "-player" },
        data = { stats = {} },
        balance = 100,
        removed = {},
        listings = {},
        failRemoveId = nil,
        failListingKey = nil,
        items = {
            a = { id = "a", fullType = "Base.Scrap", label = "Scrap", value = 5, sellPrice = 2, buyPrice = 6 },
            b = { id = "b", fullType = "Base.KeyRing", label = "Protected", value = 20, protected = true },
            c = { id = "c", fullType = "ThirdParty.Alloy", label = "Alloy", value = 8, sellPrice = 4, buyPrice = 10 },
            d = { id = "d", fullType = "Base.Scrap", label = "Scrap 2", value = 5, sellPrice = 2, buyPrice = 6 },
        },
    }
    local notifications = newNotifications()
    local function key(fullType, sprite)
        return tostring(fullType) .. (sprite and ("@worldSprite=" .. tostring(sprite)) or "")
    end
    local dependencies = {
        ["recycle.config"] = {
            recycleValue = function(item) return item.value end,
            payout = function(groups)
                local total = 0
                for i = 1, #groups do total = total + groups[i].rawValue end
                return total, { recycleLimitUsed = total }
            end,
            listingPrice = function(item) return 7, item.buyPrice end,
        },
        ["recycle.state"] = {
            load = function() return fixture.data end,
            save = function(_, data) fixture.data = clone(data) return true end,
        },
        ["recycle.inventory"] = {
            resolve = function(_, itemId)
                local item = fixture.items[itemId]
                if not item or fixture.removed[itemId] then return nil, "selectionChanged" end
                return clone(item)
            end,
            remove = function(_, item)
                if fixture.failRemoveId == item.id then return false, "selectionFailed" end
                fixture.removed[item.id] = true
                return true, { itemId = item.id }
            end,
            restore = function(_, receipt)
                fixture.removed[receipt.itemId] = nil
                return true
            end,
        },
        ["recycle.wallet"] = {
            charge = function(_, amount)
                if fixture.balance < amount then return false, "insufficientFunds" end
                fixture.balance = fixture.balance - amount
                return true, { amount = amount }
            end,
            refund = function(_, receipt) fixture.balance = fixture.balance + receipt.amount return true end,
            credit = function(_, amount) fixture.balance = fixture.balance + amount return true, { amount = amount } end,
            revokeCredit = function(_, receipt) fixture.balance = fixture.balance - receipt.amount return true end,
        },
        ["item.eligibility"] = {
            canRecycle = function(item) return item.protected ~= true end,
            canList = function(item) return item.listBlocked ~= true end,
        },
        ["shop.identity"] = { variantKey = key },
        ["shop.listings"] = {
            isKnown = function(_, variantKey) return fixture.listings[variantKey] ~= nil end,
            add = function(_, row)
                if fixture.failListingKey == row.variantKey then return false, "listingFailed" end
                fixture.listings[row.variantKey] = clone(row)
                return true, { variantKey = row.variantKey }
            end,
            remove = function(_, receipt)
                fixture.listings[receipt.variantKey] = nil
                return true
            end,
        },
        operations = newOperations(),
        notifications = notifications,
    }
    fixture.instance = GodSystemRecycleFeatureModule.create(dependencies, {
        moduleId = "feature.recycle",
        environment = environment,
    })
    assert(fixture.instance:start())
    fixture.key = key
    return fixture
end

local function runRecycleSuccess(environment)
    local f = recycleFixture(environment)
    local result = f.instance.public.execute({
        actor = f.actor,
        mode = "recycle",
        itemIds = { "a", "b", "c" },
        operationId = environment .. "-recycle",
    })
    assert(result.ok and result.code == "recycledPartial", "smart recycle partial result failed")
    assert(result.data.processedCount == 2 and result.data.skippedCount == 1 and result.data.payout == 13,
        "smart recycle counts or payout are wrong")
    assert(f.removed.a and f.removed.c and not f.removed.b and f.balance == 113,
        "third-party item or protected-item handling is wrong")
    local replay = f.instance.public.execute({
        actor = f.actor,
        mode = "recycle",
        itemIds = { "a", "b", "c" },
        operationId = environment .. "-recycle",
    })
    assert(replay == result and f.balance == 113, "recycle batch was not idempotent")
    return table.concat({ result.code, result.data.processedCount, result.data.skippedCount, f.balance }, "|")
end

assert(runRecycleSuccess("sp") == runRecycleSuccess("mp"), "SP/MP recycle behavior diverged")

do
    local f = recycleFixture("list-only")
    local result = f.instance.public.execute({
        actor = f.actor,
        mode = "listOnly",
        itemIds = { "a", "d", "b" },
        operationId = "list-only-1",
    })
    assert(result.ok and result.code == "listOnlyPartial", "list-only partial result failed")
    assert(result.data.processedCount == 1 and result.data.selectedCount == 2 and
        result.data.skippedCount == 1 and result.data.cost == 7,
        "list-only did not charge once per unique variant")
    assert(not f.removed.a and not f.removed.d and f.balance == 93, "list-only removed items or charged incorrectly")
end

do
    local f = recycleFixture("remove-rollback")
    f.failRemoveId = "c"
    local result = f.instance.public.execute({
        actor = f.actor,
        mode = "recycle",
        itemIds = { "a", "c" },
        operationId = "remove-rollback-1",
    })
    assert(not result.ok and result.code == "selectionFailed", "remove failure code was lost")
    assert(not f.removed.a and not f.removed.c and f.balance == 100, "batch removal rollback failed")
    assert(f.data.recycleLimitUsed == nil, "failed batch leaked payout-limit state")
end

do
    local f = recycleFixture("listing-rollback")
    f.failListingKey = f.key("ThirdParty.Alloy")
    local result = f.instance.public.execute({
        actor = f.actor,
        mode = "recycleAndList",
        itemIds = { "a", "c" },
        operationId = "listing-rollback-1",
    })
    assert(not result.ok and result.code == "listingFailed", "listing failure code was lost")
    assert(not f.removed.a and not f.removed.c and f.balance == 100 and
        next(f.listings) == nil, "recycle-and-list rollback was incomplete")
end

print("Test-GodSystemV422012TaskShopRecycleModuleRuntime passed")
