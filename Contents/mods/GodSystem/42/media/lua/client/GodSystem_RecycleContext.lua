require "GodSystem_Core"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISModalDialog"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWaitWhileGettingUp"

GodSystemRecycleContext = GodSystemRecycleContext or {}

local Context = GodSystemRecycleContext

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function formatText(template, args)
    local value = tostring(template or "")
    for i = 1, #(args or {}) do
        value = value:gsub("{" .. tostring(i) .. "}", tostring(args[i]))
    end
    return value
end

local function itemId(item)
    if not item or not item.getID then return nil end
    local ok, value = pcall(function() return item:getID() end)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function appendItem(result, seen, item)
    if not item or not instanceof(item, "InventoryItem") then return end
    local id = itemId(item)
    if not id or seen[id] then return end
    seen[id] = true
    result[#result + 1] = item
end

local function collectItems(values)
    local result = {}
    local seen = {}
    for _, value in ipairs(values or {}) do
        if instanceof(value, "InventoryItem") then
            appendItem(result, seen, value)
        elseif value and value.items then
            for _, item in ipairs(value.items) do
                appendItem(result, seen, item)
            end
        end
    end
    return result
end

local function inventoryCount(item)
    if not item or not item.getInventory then return 0 end
    local okInventory, inventory = pcall(function() return item:getInventory() end)
    if not okInventory or not inventory or not inventory.getItems then return 0 end
    local okItems, items = pcall(function() return inventory:getItems() end)
    if not okItems or not items or not items.size then return 0 end
    return items:size()
end

local function uniqueTypeCount(items)
    local seen = {}
    local count = 0
    for i = 1, #items do
        local fullType = items[i]:getFullType()
        local variantKey = GodSystemShopVariants.getKey(fullType, items[i])
        if not seen[variantKey] then
            seen[variantKey] = true
            count = count + 1
        end
    end
    return count
end

local function listOnlyCost(items)
    local seen = {}
    local total = 0
    for i = 1, #items do
        local item = items[i]
        local fullType = item:getFullType()
        local variantKey = GodSystemShopVariants.getKey(fullType, item)
        if not seen[variantKey] then
            seen[variantKey] = true
            local sellValue = GodSystem.getItemSellPrice(fullType, item)
            local cost = GodSystem.getAutoShopListOnlyCost(fullType, sellValue)
            total = total + cost
        end
    end
    return total
end

local function classifyItems(items, mode)
    local result = { eligible = {}, skipped = 0, firstReason = nil }
    if not GodSystem or GodSystem.isFeatureEnabled("EnableRecycle") == false then
        result.skipped = #items
        result.firstReason = "ContextReason_RecycleDisabled"
        return result
    end
    for i = 1, #items do
        local item = items[i]
        local allowed, reason = GodSystem.canContextRecycleItem(item)
        local reasonKey = nil
        if not allowed then
            reasonKey = reason == "protected" and "ContextReason_Protected" or "ContextReason_Invalid"
        elseif mode ~= "recycle" then
            local listable, listReason = GodSystem.canContextListItem(item)
            if not listable then
                if listReason == "alreadyListed" then
                    reasonKey = "ContextReason_AlreadyListed"
                elseif listReason == "hiddenListed" then
                    reasonKey = "ContextReason_HiddenListed"
                elseif listReason == "configuredListed" then
                    reasonKey = "ContextReason_ConfiguredListed"
                else
                    reasonKey = "ContextReason_NotListable"
                end
            end
        end
        if reasonKey then
            result.skipped = result.skipped + 1
            result.firstReason = result.firstReason or reasonKey
        else
            result.eligible[#result.eligible + 1] = item
        end
    end
    return result
end

local function setOptionSummary(option, classification)
    if not option or not classification then return end
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    if #classification.eligible <= 0 then
        option.notAvailable = true
        option.toolTip.description = text(classification.firstReason or "ContextReason_Invalid", "No eligible items")
        return
    end
    option.toolTip.description = formatText(text("Context_EligibleSummary", "Eligible: {1}; skipped: {2}"), {
        #classification.eligible,
        classification.skipped,
    })
end

local function containsId(container, expectedId)
    if not container or not container.getItems then return false end
    local items = container:getItems()
    if not items or not items.size then return false end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if itemId(item) == expectedId then return true end
        if item and item.getInventory then
            local ok, child = pcall(function() return item:getInventory() end)
            if ok and child and containsId(child, expectedId) then return true end
        end
    end
    return false
end

local function isInPlayerInventory(player, item)
    local container = item and item.getContainer and item:getContainer() or nil
    if not player or not container then return false end
    if container == player:getInventory() then return true end
    if container.isInCharacterInventory then
        local ok, value = pcall(function() return container:isInCharacterInventory(player) end)
        if ok and value == true then return true end
    end
    return false
end

function Context.execute(payload)
    local player = getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
    if not player then return false end
    local itemIds = {}
    for i = 1, #(payload.items or {}) do
        local id = itemId(payload.items[i])
        if not id or not containsId(player:getInventory(), id) then
            GodSystem.notify(text("Notify_RecycleSelectionTransferFailed", "Could not move all selected items"))
            return false
        end
        itemIds[#itemIds + 1] = id
    end
    return GodSystem.recycleSelectedItems(
        payload.mode,
        itemIds,
        payload.allowDestroyContents == true,
        payload.containerContentSignatures,
        payload.skippedCount or 0
    )
end

function Context.onTransfersComplete(payload)
    Context.execute(payload)
end

function Context.queueTransfers(payload)
    local player = getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
    if not player then return false end
    local actions = {}
    for i = 1, #(payload.items or {}) do
        local item = payload.items[i]
        if not isInPlayerInventory(player, item) then
            local source = item:getContainer()
            if not source then return false end
            actions[#actions + 1] = ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, player:getInventory())
        end
    end
    if #actions <= 0 then return Context.execute(payload) end
    for i = 1, #actions do
        ISTimedActionQueue.add(actions[i])
    end
    local barrier = ISWaitWhileGettingUp:new(player)
    barrier:setOnComplete(Context.onTransfersComplete, payload)
    ISTimedActionQueue.add(barrier)
    return true
end

function Context:onConfirm(button, payload)
    if button and button.internal == "YES" and payload then
        Context.queueTransfers(payload)
    end
end

function Context.begin(payload, mode)
    payload.mode = mode
    payload.allowDestroyContents = false
    payload.containerContentSignatures = {}
    local hasContents = false
    for i = 1, #(payload.items or {}) do
        if inventoryCount(payload.items[i]) > 0 then
            hasContents = true
            local id = itemId(payload.items[i])
            if id and GodSystem and GodSystem.getContextContainerSignature then
                payload.containerContentSignatures[id] = GodSystem.getContextContainerSignature(payload.items[i])
            end
        end
    end

    local message = nil
    if mode == "listOnly" then
        local cost = listOnlyCost(payload.items)
        message = formatText(text("Confirm_ContextListOnly", "List {1} item types for {2} coins? Items will not be removed."), {
            uniqueTypeCount(payload.items),
            cost,
        })
    elseif hasContents then
        payload.allowDestroyContents = true
        message = formatText(text("Confirm_ContextDestroyContainer", "The selection contains non-empty containers. Recycling will destroy all contents. Continue?"), {
            #payload.items,
        })
    end

    if not message then return Context.queueTransfers(payload) end
    local player = getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
    local playerNum = player and player:getPlayerNum() or payload.playerNum or 0
    local x = math.max(80, (getCore():getScreenWidth() / 2) - 260)
    local y = math.max(80, (getCore():getScreenHeight() / 2) - 140)
    local modal = ISModalDialog:new(x, y, 520, 280, message, true, Context, Context.onConfirm, playerNum, payload)
    modal:initialise()
    modal:addToUIManager()
    return true
end

function Context.fillInventoryMenu(playerNum, context, values)
    local items = collectItems(values)
    if #items <= 0 then return end
    local function addModeOption(labelKey, fallback, mode)
        local classification = classifyItems(items, mode)
        local label = text(labelKey, fallback)
        if classification.skipped > 0 and #classification.eligible > 0 then
            label = label .. " (" .. tostring(#classification.eligible) .. "/" .. tostring(#items) .. ")"
        end
        local payload = {
            playerNum = playerNum,
            items = classification.eligible,
            skippedCount = classification.skipped,
        }
        local option = context:addOption(label, payload, Context.begin, mode)
        setOptionSummary(option, classification)
    end

    addModeOption("Menu_ContextRecycle", "Recycle", "recycle")
    addModeOption("Menu_ContextRecycleAndList", "Recycle and list", "recycleAndList")
    addModeOption("Menu_ContextListOnly", "List only", "listOnly")
end

Events.OnFillInventoryObjectContextMenu.Add(Context.fillInventoryMenu)
