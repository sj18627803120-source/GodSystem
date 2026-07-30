GodSystemUIActionAdapter = GodSystemUIActionAdapter or {}

local ActionAdapter = GodSystemUIActionAdapter

local function taskId(task)
    if type(task) ~= "table" then return nil end
    local value = tostring(task.taskId or "")
    return value ~= "" and value or nil
end

local function productId(product)
    if type(product) ~= "table" then return nil end
    local value = tostring(product.productId or product.id or product.variantKey or "")
    return value ~= "" and value or nil
end

local function itemId(item)
    if not item then return nil end
    if type(item) == "string" or type(item) == "number" then
        local value = tostring(item)
        return value ~= "" and value or nil
    end
    if type(item.getID) == "function" then
        local value = item:getID()
        return value ~= nil and tostring(value) or nil
    end
    local value = item.id
    return value ~= nil and tostring(value) or nil
end

local function appendItemIds(targetIds, items, limit)
    limit = math.max(0, math.floor(tonumber(limit) or #(items or {})))
    for index = 1, math.min(limit, #(items or {})) do
        local value = itemId(items[index])
        if value then targetIds[#targetIds + 1] = value end
    end
end

function ActionAdapter.new(options)
    options = type(options) == "table" and options or {}
    local facade = assert(options.facade, "UI action facade required")
    local target = assert(options.target, "UI action target required")
    local companion = options.companionTarget
    local originals = {}
    local companionOriginals = {}
    local instance = {
        installed = false,
        lastResult = nil,
    }

    local function request(action, args)
        local primary, secondary = facade:request(action,
            type(args) == "table" and args or {})
        local result = type(primary) == "table" and primary or secondary
        instance.lastResult = result
        return type(result) == "table" and result.ok == true
    end

    local function recycleSelection(mode, itemIds, allowDestroyContents,
            containerContentSignatures, clientSkipped)
        return request("recycle.execute", {
            mode = mode,
            itemIds = itemIds,
            allowDestroyContents = allowDestroyContents == true,
            containerContentSignatures = containerContentSignatures,
            clientSkipped = clientSkipped,
        })
    end

    local function waistSelection(selectedFullTypes, mode)
        if type(target.getWaistSpaceRecycleGroups) ~= "function" then return false end
        local groups, order, skipped = target.getWaistSpaceRecycleGroups()
        local ids = {}
        for index = 1, #(order or {}) do
            local fullType = order[index]
            if selectedFullTypes == nil or selectedFullTypes[fullType] == true then
                local group = groups and groups[fullType]
                appendItemIds(ids, group and group.items or {})
            end
        end
        return recycleSelection(mode, ids, false, nil, skipped)
    end

    local replacements = {
        consolidateCurrency = function()
            return request("wallet.consolidate")
        end,
        performBankAction = function(action, amount, termId, entryId)
            return request("bank.execute", {
                action = action,
                amount = amount,
                termId = termId,
                entryId = entryId,
            })
        end,
        generateDailyTasks = function(force)
            return request("tasks.generate", { force = force == true })
        end,
        refreshOpenTasks = function()
            return request("tasks.refresh")
        end,
        acceptTask = function(task)
            return request("tasks.accept", { taskId = taskId(task) })
        end,
        abandonTask = function(task)
            return request("tasks.fail", { taskId = taskId(task) })
        end,
        claimTask = function(task)
            return request("tasks.claim", { taskId = taskId(task) })
        end,
        toggleAutoTaskClaim = function()
            local data = facade:data()
            return request("tasks.autoClaim", {
                enabled = not (data and data.autoTaskClaimEnabled == true),
            })
        end,
        performMedicalService = function(action)
            return request("medical.execute", { action = action })
        end,
        performAttributePurchase = function(perkIndex, mode, value)
            return request("attributes.purchase", {
                perkIndex = perkIndex,
                mode = mode,
                value = value,
            })
        end,
        performTraitModification = function(action, traitType)
            return request("attributes.traitModify", {
                action = action,
                traitType = traitType,
            })
        end,
        upgradeSystem = function(upgradeType)
            return request("upgrades.purchase", { upgradeType = upgradeType })
        end,
        refreshCarryCapacity = function()
            return request("upgrades.refresh", {
                upgradeType = "carryCapacity",
            })
        end,
        purchaseCompanionNode = function(nodeId)
            return request("companion.purchase", { nodeId = nodeId })
        end,
        claimOrRecoverAutoRecycler = function()
            return request("terminal.execute", { action = "claim" })
        end,
        upgradeTerminal = function(upgradeType)
            local names = {
                capacity = "upgradeCapacity",
                reduction = "upgradeReduction",
                relief = "upgradeRelief",
            }
            return request("terminal.execute", {
                action = names[tostring(upgradeType or "")],
                upgradeType = upgradeType,
            })
        end,
        upgradeAutoRecycler = function()
            return request("terminal.execute", {
                action = "upgradeCapacity",
                upgradeType = "capacity",
            })
        end,
        performHomeAction = function(action, index)
            local routes = {
                setHome = "home.set",
                buyTemp = "home.buyTemp",
                setTemp = "home.setTemp",
                teleportHome = "home.teleport",
                teleportTemp = "home.teleportTemp",
                ["return"] = "home.return",
                clearReturn = "home.clearReturn",
                unlockSafeZone = "home.upgradeSafeZone",
                upgradeSafeZone = "home.upgradeSafeZone",
                toggleSafeZone = "home.toggleSafeZone",
                clearSafeZone = "home.clearSafeZone",
            }
            local route = routes[tostring(action or "")]
            if not route then return false end
            return request(route, {
                index = index,
                manual = action == "clearSafeZone",
            })
        end,
        buyShopItem = function(product, quantity)
            return request("shop.purchase", {
                productId = productId(product),
                quantity = quantity,
            })
        end,
        performLotteryDraw = function(_, categoryKey, count)
            return request("shop.lottery", {
                category = categoryKey,
                count = count,
            })
        end,
        listOnlyAutoShopItem = function(_, itemId)
            return request("shop.list", { itemId = itemId })
        end,
        setShopItemHidden = function(variantKey, hidden)
            return request("shop.hide", {
                variantKey = variantKey,
                hidden = hidden == true,
            })
        end,
        deleteShopItem = function(variantKey)
            return request("shop.delete", { variantKey = variantKey })
        end,
        recycleSelectedItems = function(mode, itemIds, allowDestroyContents,
                containerContentSignatures, clientSkipped)
            return recycleSelection(mode, itemIds, allowDestroyContents,
                containerContentSignatures, clientSkipped)
        end,
        recycleInventoryItems = function(fullType, count)
            if type(target.getInventoryRecycleGroups) ~= "function" then
                return false
            end
            local groups = target.getInventoryRecycleGroups()
            local group = groups and groups[fullType]
            local ids = {}
            appendItemIds(ids, group and group.itemIds or {}, count)
            local data = facade:data()
            local mode = data and data.recycleUnlockMode == false
                and "recycle" or "recycleAndList"
            return recycleSelection(mode, ids)
        end,
        recycleWaistSpaceItems = function(selectedFullTypes)
            return waistSelection(selectedFullTypes, "recycle")
        end,
        recycleWaistSpaceItemsAndUnlock = function(selectedFullTypes)
            return waistSelection(selectedFullTypes, "recycleAndList")
        end,
        recycleWaistSpaceItemsByMode = function(selectedFullTypes)
            local data = facade:data()
            local mode = data and data.waistRecycleUnlockMode == true
                and "recycleAndList" or "recycle"
            return waistSelection(selectedFullTypes, mode)
        end,
        toggleRecycleUnlockMode = function()
            local data = facade:data()
            return request("recycle.preference", {
                key = "recycleUnlockMode",
                value = not (data and data.recycleUnlockMode ~= false),
            })
        end,
        toggleWaistRecycleUnlockMode = function()
            local data = facade:data()
            return request("recycle.preference", {
                key = "waistRecycleUnlockMode",
                value = not (data and data.waistRecycleUnlockMode == true),
            })
        end,
        toggleWaistAutoRecycle = function()
            local data = facade:data()
            return request("recycle.preference", {
                key = "waistAutoRecycleEnabled",
                value = not (data and data.waistAutoRecycleEnabled == true),
            })
        end,
        saveAdminSettings = function(settings)
            return request("admin.save", { settings = settings })
        end,
        saveItemOverride = function(fullType, override)
            return request("admin.itemOverride", {
                fullType = fullType,
                override = override,
            })
        end,
        clearItemOverride = function(fullType)
            return request("admin.clearItemOverride", { fullType = fullType })
        end,
    }

    local companionReplacements = {
        activateSight = function()
            return request("companion.sight")
        end,
        setCombatMode = function(mode)
            return request("companion.combatMode", { mode = mode })
        end,
        setFollowMode = function(mode)
            return request("companion.followMode", { mode = mode })
        end,
        toggleGuardian = function()
            return request("companion.guardian")
        end,
        toggleVisible = function()
            return request("companion.visible")
        end,
        recall = function()
            return request("companion.recall")
        end,
    }

    function instance:install()
        if self.installed then return true end
        for name, callback in pairs(replacements) do
            originals[name] = target[name]
            target[name] = callback
        end
        if type(companion) == "table" then
            for name, callback in pairs(companionReplacements) do
                companionOriginals[name] = companion[name]
                companion[name] = callback
            end
        end
        self.installed = true
        return true
    end

    function instance:stop()
        if not self.installed then return true end
        for name in pairs(replacements) do target[name] = originals[name] end
        if type(companion) == "table" then
            for name in pairs(companionReplacements) do
                companion[name] = companionOriginals[name]
            end
        end
        self.installed = false
        return true
    end

    return instance
end

return ActionAdapter
