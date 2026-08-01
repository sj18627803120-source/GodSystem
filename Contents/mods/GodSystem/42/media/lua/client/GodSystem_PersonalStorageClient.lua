require "GodSystem_PersonalStorage"
require "GodSystem_StorageBridge"
require "ISUI/ISModalDialog"

GodSystemPersonalStorageClient = GodSystemPersonalStorageClient or {}

local Client = GodSystemPersonalStorageClient
local Personal = GodSystemPersonalStorage
local Storage = GodSystemStorage
local Bridge = GodSystemStorageBridge.create({
    personal = GodSystemPersonalStorage,
    manager = GodSystemStorageManager,
})
local MODULE = "GodSystemPersonalStorage"

Client.moduleId = "personalStorageClient"
Client.state = Client.state or nil
Client.details = Client.details or {}
Client.pending = Client.pending or {}
Client.lastError = nil
Client.lastOperationId = nil

local function multiplayer()
    return isClient and isClient()
end

local function playerByNumber(playerNum)
    if getSpecificPlayer then return getSpecificPlayer(playerNum or 0) end
    return getPlayer and getPlayer() or nil
end

local function send(command, args)
    local current = playerByNumber(0)
    if not current or not sendClientCommand then return false end
    sendClientCommand(current, MODULE, command, args or {})
    return true
end

local function store()
    return Personal.normalizeData(GodSystem.getData())
end

local function notify(code, data)
    if not GodSystem or not GodSystem.notify then return end
    local fallback = {
        stored = "已存入个人分类仓",
        storedSimplified = "已按简化状态存入个人分类仓",
        withdrawn = "已从个人分类仓取出",
        capacityExpanded = "分类专属容量已增加 200",
        generalExpanded = "通用容量已增加 10",
        capacityFull = "个人分类仓容量不足",
        protectedItem = "该物品不能存入个人分类仓",
        missingDefinition = "缺少物品定义，快照已保留",
        insufficientFunds = "系统币不足",
        partial = "批量操作部分完成",
        failed = "个人分类仓操作失败",
    }
    local key = "PersonalStorage_" .. tostring(code or "failed")
    GodSystem.notify(GodSystem.text(key, fallback[code] or tostring(code or "failed")))
end

local function completed(command, outcome)
    Client.lastOperationId = outcome and outcome.operationId
    if not (outcome and outcome.ok) then Client.lastError = outcome and outcome.code or "invalidResult" end
    if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onOperationResult then
        GodSystemPersonalStorageUI.onOperationResult(command, outcome)
    end
    if GodSystemStorageUI and GodSystemStorageUI.onPersonalOperationResult then
        GodSystemStorageUI.onPersonalOperationResult(command, outcome)
    end
    if (command == "bridgeDeposit" or command == "bridgeWithdraw")
        and GodSystemStorageClient and GodSystemStorageClient.refresh then
        GodSystemStorageClient.refresh()
    end
    if outcome and outcome.code and outcome.code ~= "completed" then notify(outcome.code, outcome.data) end
end

function Client.getSummary()
    if multiplayer() then return Client.state end
    Client.state = Personal.summary(store())
    return Client.state
end

function Client.requestState()
    if multiplayer() then send("state", {})
    else
        Client.state = Personal.summary(store())
        if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onState then GodSystemPersonalStorageUI.onState(Client.state) end
    end
end

function Client.requestDetails(groupKey, offset, limit)
    if multiplayer() then
        send("details", { groupKey = groupKey, offset = offset or 0, limit = limit or 50 })
    else
        local page = Personal.entries(store(), groupKey, offset, limit)
        Client.details[tostring(groupKey or "all")] = page
        if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onDetails then GodSystemPersonalStorageUI.onDetails(groupKey, page) end
    end
end

function Client.findItem(itemId)
    local player = getPlayer and getPlayer() or nil
    if not player then return nil, nil end
    return Storage.findItemRecursive(player:getInventory(), itemId, Storage.MaxDepth)
end

function Client.deposit(itemIds, confirmSimplified)
    itemIds = itemIds or {}
    local operationId = Personal.newOperationId("deposit")
    if multiplayer() then
        send("deposit", {
            operationId = operationId,
            itemIds = itemIds,
            confirmSimplified = confirmSimplified == true,
        })
        return operationId
    end
    local targetStore = store()
    local operation, previous = Personal.beginOperation(targetStore, operationId,
        "depositBatch|" .. table.concat(itemIds, "|") .. "|" .. tostring(confirmSimplified == true))
    if previous then completed("deposit", previous); return operationId end
    local stats = { requested = math.min(#itemIds, 250), success = 0, skipped = 0, failed = 0, simplified = 0, rows = {} }
    for i = 1, math.min(#itemIds, 250) do
        local item, source = Client.findItem(itemIds[i])
        local preview = Personal.createEntry(item)
        if preview.ok and preview.data.simplified and confirmSimplified ~= true then
            stats.skipped = stats.skipped + 1
            stats.rows[#stats.rows + 1] = { itemId = itemIds[i], reason = "confirmSimplified" }
        elseif item and source then
            local outcome = Personal.deposit(targetStore, item, source, operationId .. ":" .. tostring(i))
            Personal.discardOperation(targetStore, operationId .. ":" .. tostring(i))
            if outcome.ok then stats.success = stats.success + 1; if outcome.data.simplified then stats.simplified = stats.simplified + 1 end
            elseif outcome.code == "capacityFull" or outcome.code == "protectedItem" then stats.skipped = stats.skipped + 1
            else stats.failed = stats.failed + 1 end
            stats.rows[#stats.rows + 1] = { itemId = itemIds[i], reason = outcome.code, ok = outcome.ok }
        else
            stats.failed = stats.failed + 1
        end
    end
    GodSystem.save()
    Client.state = Personal.summary(targetStore)
    completed("deposit", Personal.finishOperation(targetStore, operationId,
        { ok = stats.success > 0 or stats.failed == 0, code = stats.failed > 0 and "partial" or "completed", data = stats, operationId = operationId, moduleId = Personal.moduleId }))
    return operationId
end

function Client.previewDeposit(itemIds)
    local rows = {}
    for i = 1, math.min(#(itemIds or {}), 250) do
        local item = Client.findItem(itemIds[i])
        local captured = Personal.createEntry(item)
        if captured.ok then
            rows[#rows + 1] = {
                itemId = itemIds[i], fullType = captured.data.snapshot.fullType,
                name = captured.data.snapshot.displayName, simplified = captured.data.simplified,
                reasons = captured.data.report.reasons,
            }
        end
    end
    return rows
end

function Client.withdraw(entryIds, targetItemId)
    entryIds = entryIds or {}
    local operationId = Personal.newOperationId("withdraw")
    if multiplayer() then
        send("withdraw", { operationId = operationId, entryIds = entryIds, targetItemId = targetItemId })
        return operationId
    end
    local player = getPlayer and getPlayer() or nil
    if not player then return nil end
    local target = Storage.resolvePlayerContainer(player, targetItemId)
    local targetStore = store()
    local operation, previous = Personal.beginOperation(targetStore, operationId,
        "withdrawBatch|" .. table.concat(entryIds, "|") .. "|" .. tostring(targetItemId or ""))
    if previous then completed("withdraw", previous); return operationId end
    local stats = { requested = math.min(#entryIds, 250), success = 0, skipped = 0, failed = 0, rows = {} }
    for i = 1, math.min(#entryIds, 250) do
        local outcome = Personal.withdraw(targetStore, entryIds[i], target, operationId .. ":" .. tostring(i))
        Personal.discardOperation(targetStore, operationId .. ":" .. tostring(i))
        if outcome.ok then stats.success = stats.success + 1
        elseif outcome.code == "entryMissing" then stats.skipped = stats.skipped + 1
        else stats.failed = stats.failed + 1 end
        stats.rows[#stats.rows + 1] = { entryId = entryIds[i], reason = outcome.code, ok = outcome.ok }
    end
    GodSystem.save()
    Client.state = Personal.summary(targetStore)
    completed("withdraw", Personal.finishOperation(targetStore, operationId,
        { ok = stats.success > 0 or stats.failed == 0, code = stats.failed > 0 and "partial" or "completed", data = stats, operationId = operationId, moduleId = Personal.moduleId }))
    return operationId
end

function Client.usePermit(itemId, category)
    local operationId = Personal.newOperationId("permit")
    if multiplayer() then
        send("usePermit", { operationId = operationId, itemId = itemId, category = category })
        return operationId
    end
    local targetStore = store()
    local operation, previous = Personal.beginOperation(targetStore, operationId,
        "permitUse|" .. tostring(itemId or "") .. "|" .. tostring(category or ""))
    if previous then completed("usePermit", previous); return operationId end
    local item, source = Client.findItem(itemId)
    local itemOperation = operationId .. ":item"
    local outcome = Personal.consumePermit(targetStore, item, source, category, itemOperation)
    Personal.discardOperation(targetStore, itemOperation)
    outcome.operationId = operationId
    if outcome.ok then GodSystem.save(); Client.state = Personal.summary(targetStore) end
    completed("usePermit", Personal.finishOperation(targetStore, operationId, outcome))
    return operationId
end

function Client.buyGeneral()
    local operationId = Personal.newOperationId("buyGeneral")
    if multiplayer() then send("buyGeneral", { operationId = operationId }); return operationId end
    local targetStore = store()
    local fingerprint = "buyGeneral|10000|10"
    local op, previous = Personal.beginOperation(targetStore, operationId, fingerprint)
    if previous then completed("buyGeneral", previous); return operationId end
    if not GodSystem.canAfford(Personal.GeneralPurchaseCost) or not GodSystem.addPoints(-Personal.GeneralPurchaseCost) then
        local failed = Personal.finishOperation(targetStore, operationId, { ok = false, code = "insufficientFunds", operationId = operationId, moduleId = Personal.moduleId })
        completed("buyGeneral", failed)
        return operationId
    end
    local outcome = Personal.addGeneralCapacity(targetStore, Personal.GeneralPurchaseCapacity)
    outcome.operationId = operationId
    if outcome.ok then
        local data = GodSystem.getData()
        data.stats.spentPoints = (data.stats.spentPoints or 0) + Personal.GeneralPurchaseCost
        if GodSystem.recordPersonalStoragePurchase then
            GodSystem.recordPersonalStoragePurchase(Personal.GeneralPurchaseCost, Personal.GeneralPurchaseCapacity)
        end
        GodSystem.save()
        Client.state = Personal.summary(targetStore)
    else
        GodSystem.addPoints(Personal.GeneralPurchaseCost)
    end
    completed("buyGeneral", Personal.finishOperation(targetStore, operationId, outcome))
    return operationId
end

local function mergedCoreArgs(args)
    local merged = GodSystemStorageClient and GodSystemStorageClient.coreArgs
        and GodSystemStorageClient.coreArgs() or {}
    for key, value in pairs(args or {}) do merged[key] = value end
    return merged
end

function Client.bridgeDeposit(requests, confirmSimplified)
    local operationId = Personal.newOperationId("bridgeDeposit")
    local args = mergedCoreArgs({
        operationId = operationId,
        snapshotId = GodSystemStorageClient and GodSystemStorageClient.snapshot
            and GodSystemStorageClient.snapshot.snapshotId,
        requests = requests or {},
        confirmSimplified = confirmSimplified == true,
    })
    if multiplayer() then send("bridgeDeposit", args); return operationId end
    local player = playerByNumber(0)
    local outcome = Bridge:physicalToPersonal(player, args, args, store(), operationId)
    if outcome.ok then GodSystem.save() end
    Client.state = Personal.summary(store())
    completed("bridgeDeposit", outcome)
    if GodSystemStorageClient and GodSystemStorageClient.refresh then GodSystemStorageClient.refresh() end
    return operationId
end

function Client.previewBridgeDeposit(requests)
    local operationId = Personal.newOperationId("bridgePreview")
    local args = mergedCoreArgs({
        operationId = operationId,
        snapshotId = GodSystemStorageClient and GodSystemStorageClient.snapshot
            and GodSystemStorageClient.snapshot.snapshotId,
        requests = requests or {},
    })
    if multiplayer() then send("bridgePreview", args); return operationId end
    local outcome = Bridge:previewPhysical(playerByNumber(0), args, args)
    local rows = outcome.data and outcome.data.rows or {}
    local simplified = {}
    for i = 1, #rows do if rows[i].simplified then simplified[#simplified + 1] = rows[i] end end
    if GodSystemStorageUI and GodSystemStorageUI.onPersonalPreview then
        GodSystemStorageUI.onPersonalPreview({
            command = "bridgePreview", operationId = operationId, ok = outcome.ok,
            code = outcome.code, rows = rows, simplified = simplified, confirmRequired = #simplified > 0,
        })
    end
    return operationId
end

function Client.bridgeWithdraw(entryIds)
    local operationId = Personal.newOperationId("bridgeWithdraw")
    local args = mergedCoreArgs({ operationId = operationId, entryIds = entryIds or {} })
    if multiplayer() then send("bridgeWithdraw", args); return operationId end
    local player = playerByNumber(0)
    local outcome = Bridge:personalToPhysical(player, args, args, store(), operationId)
    if outcome.ok then GodSystem.save() end
    Client.state = Personal.summary(store())
    completed("bridgeWithdraw", outcome)
    if GodSystemStorageClient and GodSystemStorageClient.refresh then GodSystemStorageClient.refresh() end
    return operationId
end

function Client.onPermitConfirm(button, payload)
    if button and button.internal == "YES" and payload then Client.usePermit(payload.itemId, payload.category) end
end

function Client.confirmPermit(item, category, playerNum)
    local itemId = Storage.itemId(item)
    local summary = Client.getSummary() or Personal.summary(store())
    local before = summary.usage and summary.usage.categories and summary.usage.categories[category]
        and summary.usage.categories[category].capacity or 0
    local message = GodSystem.text("PersonalStorage_PermitConfirm", "确认使用扩容许可？")
        .. "\n" .. GodSystem.text("PersonalStorage_Category_" .. category, category)
        .. ": " .. tostring(before) .. " → " .. tostring(before + Personal.PermitCapacity)
    local modal = ISModalDialog:new(math.max(40, getCore():getScreenWidth() / 2 - 240),
        math.max(40, getCore():getScreenHeight() / 2 - 100), 480, 200, message, true,
        Client, Client.onPermitConfirm, playerNum or 0, { itemId = itemId, category = category })
    modal:initialise()
    modal:addToUIManager()
end

function Client.selectedPermit(items)
    local selected
    for _, value in ipairs(items or {}) do
        local candidates = value and value.items or { value }
        for i = 1, #(candidates or {}) do
            local item = candidates[i]
            if item and Storage.itemFullType(item) == Personal.PermitFullType then
                if selected and selected ~= item then return nil end
                selected = item
            end
        end
    end
    return selected
end

function Client.fillInventoryMenu(playerNum, context, items)
    if GodSystem.isFeatureEnabled and GodSystem.isFeatureEnabled("EnablePersonalStorage") == false then return end
    local permit = Client.selectedPermit(items)
    if not permit then return end
    local root = context:addOption(GodSystem.text("PersonalStorage_UsePermit", "使用个人仓扩容许可"))
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(root, submenu)
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        local selectedCategory = category
        submenu:addOption(GodSystem.text("PersonalStorage_Category_" .. category, category), permit,
            function(item) Client.confirmPermit(item, selectedCategory, playerNum) end)
    end
end

function Client.onServerCommand(module, command, args)
    if module ~= MODULE then return end
    args = type(args) == "table" and args or {}
    if command == "state" then
        Client.state = args
        if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onState then GodSystemPersonalStorageUI.onState(args) end
    elseif command == "details" then
        Client.details[tostring(args.groupKey or "all")] = args
        if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onDetails then GodSystemPersonalStorageUI.onDetails(args.groupKey, args) end
    elseif command == "result" then
        completed(args.command, args)
    elseif command == "preview" then
        if GodSystemPersonalStorageUI and GodSystemPersonalStorageUI.onPreview then GodSystemPersonalStorageUI.onPreview(args) end
        if GodSystemStorageUI and GodSystemStorageUI.onPersonalPreview then GodSystemStorageUI.onPersonalPreview(args) end
    elseif command == "health" then
        Client.healthState = args
    end
end

function Client.health()
    local summary = Client.state
    if not multiplayer() then
        local accountData = GodSystem and GodSystem.data or nil
        local domainHealth = Personal.health(accountData)
        summary = domainHealth.ok and Personal.summary(accountData.personalStorage) or nil
    end
    local bridgeHealth = Bridge:health()
    return {
        ok = summary ~= nil and bridgeHealth.ok == true,
        code = not summary and "stateMissing" or bridgeHealth.code,
        data = {
            summary = summary,
            bridge = bridgeHealth,
            lastError = Client.lastError,
            lastOperationId = Client.lastOperationId,
        },
        operationId = Client.lastOperationId,
        moduleId = Client.moduleId,
    }
end

Events.OnServerCommand.Add(Client.onServerCommand)
Events.OnFillInventoryObjectContextMenu.Add(Client.fillInventoryMenu)

return Client
