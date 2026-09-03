require "GodSystem_App"
require "GodSystem_Core"
require "GodSystem_RangeFilter"
require "GodSystem_InventoryContext"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISModalDialog"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWaitWhileGettingUp"

GodSystemRecycleContext = GodSystemRecycleContext or {}

local Context = GodSystemRecycleContext

local function text(key, fallback)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.text then return GodSystemApp.services.runtime.text(key, fallback) end
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

local function collectFullTypes(items)
    local result = {}
    local seen = {}
    for i = 1, #(items or {}) do
        local item = items[i]
        local ok, value = pcall(function() return item:getFullType() end)
        local fullType = ok and tostring(value or ""):match("^%s*(.-)%s*$") or ""
        if fullType ~= "" and not seen[fullType] then
            seen[fullType] = true
            result[#result + 1] = fullType
        end
    end
    table.sort(result)
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
            local sellValue = GodSystemApp.services.runtime.getItemSellPrice(fullType, item)
            local cost = GodSystemApp.services.runtime.getAutoShopListOnlyCost(fullType, sellValue)
            total = total + cost
        end
    end
    return total
end

local function createAnalysisCache(items, entries)
    if not GodSystemApp.services.runtime
        or GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false then
        return { disabled = true, recycle = {} }
    end
    local cache = {
        data = GodSystemApp.services.runtime.getData(),
        configuredShopKeySet = GodSystemInventoryContext.getConfiguredShopKeySet(),
        recycle = {},
        recycleByFullType = {},
        listByVariantKey = {},
    }
    for i = 1, #items do
        local item = items[i]
        local snapshotEntry = entries and entries[i] or nil
        local fullType = snapshotEntry and snapshotEntry.fullType or item:getFullType()
        local variantKey = snapshotEntry and snapshotEntry.variantKey or GodSystemShopVariants.getKey(fullType, item)
        local entry = cache.recycleByFullType[fullType]
        if not entry then
            local allowed, reason = GodSystemApp.services.runtime.canContextRecycleItem(item)
            entry = { allowed = allowed == true, reason = reason }
            cache.recycleByFullType[fullType] = entry
        end
        -- Expose the per-item result while canContextListItem evaluates the first variant.
        cache.recycle[item] = entry
        local listEntry = cache.listByVariantKey[variantKey]
        if not listEntry then
            listEntry = { listable = false, listReason = entry.reason }
            if entry.allowed then
                local listable, listReason = GodSystemApp.services.runtime.canContextListItem(item, cache)
                listEntry.listable = listable == true
                listEntry.listReason = listReason
            end
            cache.listByVariantKey[variantKey] = listEntry
        end
        entry = { allowed = entry.allowed, reason = entry.reason, listable = listEntry.listable, listReason = listEntry.listReason }
        cache.recycle[item] = entry
    end
    return cache
end

local function classifyItems(items, mode, analysis)
    local result = { eligible = {}, skipped = 0, firstReason = nil }
    if not GodSystemApp.services.runtime or GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false then
        result.skipped = #items
        result.firstReason = "ContextReason_RecycleDisabled"
        return result
    end
    for i = 1, #items do
        local item = items[i]
        local cached = analysis and analysis.recycle[item] or nil
        local allowed = cached and cached.allowed or false
        local reason = cached and cached.reason or nil
        local reasonKey = nil
        if not allowed then
            reasonKey = reason == "protected" and "ContextReason_Protected" or "ContextReason_Invalid"
        elseif mode ~= "recycle" then
            local listable = cached and cached.listable or false
            local listReason = cached and cached.listReason or nil
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
        if reasonKey and mode ~= "recycleAndList" then
            result.skipped = result.skipped + 1
            result.firstReason = result.firstReason or reasonKey
        else
            result.eligible[#result.eligible + 1] = item
            if reasonKey then
                result.skipped = result.skipped + 1
                result.firstReason = result.firstReason or reasonKey
            end
        end
    end
    return result
end

local function classifyAll(items, analysis)
    local result = {
        recycle = { eligible = {}, skipped = 0, firstReason = nil },
        recycleAndList = { eligible = {}, skipped = 0, firstReason = nil },
        listOnly = { eligible = {}, skipped = 0, firstReason = nil },
    }
    local enabled = GodSystemApp.services.runtime
        and GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") ~= false
    for i = 1, #items do
        local item = items[i]
        local cached = analysis and analysis.recycle[item] or nil
        local allowed = cached and cached.allowed or false
        local reason = cached and cached.reason or nil
        local reasonKey = nil
        local listable = cached and cached.listable or false
        local listReason = cached and cached.listReason or nil
        if not allowed then
            reasonKey = reason == "protected" and "ContextReason_Protected" or "ContextReason_Invalid"
        elseif not listable then
            if listReason == "alreadyListed" then
                reasonKey = "ContextReason_AlreadyListed"
            elseif listReason == "hiddenListed" then
                reasonKey = "ContextReason_HiddenListed"
            elseif listReason == "configuredListed" then
                reasonKey = "ContextReason_ConfiguredListed"
            elseif allowed then
                reasonKey = "ContextReason_NotListable"
            end
        end
        local function add(mode, eligible, skippedReason)
            local target = result[mode]
            if not eligible then
                target.skipped = target.skipped + 1
                target.firstReason = target.firstReason or skippedReason
            else
                target.eligible[#target.eligible + 1] = item
                if skippedReason then
                    target.skipped = target.skipped + 1
                    target.firstReason = target.firstReason or skippedReason
                end
            end
        end
        if not enabled then
            add("recycle", false, "ContextReason_RecycleDisabled")
            add("recycleAndList", false, "ContextReason_RecycleDisabled")
            add("listOnly", false, "ContextReason_RecycleDisabled")
        else
            add("recycle", allowed, allowed and nil or reasonKey)
            add("recycleAndList", allowed or reasonKey ~= nil, reasonKey)
            add("listOnly", allowed and listable, allowed and (listable and nil or reasonKey) or reasonKey)
        end
    end
    return result
end

local function rangeFilterView(playerNum)
    local service = GodSystemApp.services and GodSystemApp.services.rangeRecycle
    if not service or not service.getViewModel then return nil end
    return service:getViewModel(playerNum)
end

local function rangeFilterPayload(playerNum, items)
    local state = rangeFilterView(playerNum)
    if not state then return nil end
    local filter = GodSystemRangeFilter.normalize(state.filter)
    local active = {}
    for i = 1, #filter.activeFullTypes do active[filter.activeFullTypes[i]] = true end
    local all = collectFullTypes(items)
    local missing, skipped = {}, 0
    for i = 1, #all do
        if active[all[i]] then
            skipped = skipped + 1
        elseif #missing < 256 then
            missing[#missing + 1] = all[i]
        else
            skipped = skipped + 1
        end
    end
    return {
        playerNum = playerNum,
        fullTypes = missing,
        skippedExisting = skipped,
        mode = filter.mode,
        ready = state.filterReady == true,
    }
end

function Context.addToRangeFilter(payload)
    local data = payload or {}
    if data.ready ~= true then
        GodSystemApp.services.runtime.notify(text("Context_RangeSyncing", "Range recycle list is still syncing"))
        return false
    end
    if #(data.fullTypes or {}) <= 0 then
        local message = formatText(text("Context_RangeAllPresent", "All selected item types are already in the current range list ({1} skipped)"), {
            data.skippedExisting or 0,
        })
        GodSystemApp.services.runtime.notify(message)
        return false
    end
    local service = GodSystemApp.services.rangeRecycle
    local state = service and service.getViewModel and service:getViewModel(data.playerNum) or nil
    local filter = state and GodSystemRangeFilter.normalize(state.filter) or nil
    if not filter then return false end
    local result = service:execute(data.playerNum, "filterDelta", {
        baseRevision = filter.revision,
        op = "addMany",
        fullTypes = data.fullTypes,
    }, function(value)
        if value and value.ok then
            GodSystemApp.services.runtime.notify(formatText(text("Context_RangeAdded", "Added {1} item types to the range list; {2} skipped"), {
                #data.fullTypes, data.skippedExisting or 0,
            }))
        end
    end)
    return result ~= nil
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
            GodSystemApp.services.runtime.notify(text("Notify_RecycleSelectionTransferFailed", "Could not move all selected items"))
            return false
        end
        itemIds[#itemIds + 1] = id
    end
    return GodSystemApp.services.runtime.recycleSelectedItems(
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
            if id and GodSystemApp.services.runtime and GodSystemApp.services.runtime.getContextContainerSignature then
                payload.containerContentSignatures[id] = GodSystemApp.services.runtime.getContextContainerSignature(payload.items[i])
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
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    return true
end

function Context.fillInventoryMenu(playerNum, context, values)
    local items = values and values.__godSystemInventorySnapshot and values.items or collectItems(values)
    local entries = values and values.__godSystemInventorySnapshot and values.entries or nil
    if #items <= 0 then return end
    local analysis = createAnalysisCache(items, entries)
    local classifications = classifyAll(items, analysis)
    local function addModeOption(labelKey, fallback, mode)
        local classification = classifications[mode]
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

    local rangeClassification = classifications.recycle
    local rangePayload = rangeFilterPayload(playerNum, rangeClassification.eligible)
    if rangePayload then
        local labelKey = rangePayload.mode == "denylist" and "Menu_ContextRangeAddForbidden" or "Menu_ContextRangeAddAllowed"
        local fallback = rangePayload.mode == "denylist" and "Add to forbidden range recycle" or "Add to allowed range recycle"
        local label = text(labelKey, fallback)
        if rangePayload.skippedExisting > 0 and #rangePayload.fullTypes > 0 then
            label = label .. " (" .. tostring(#rangePayload.fullTypes) .. "/" .. tostring(#rangePayload.fullTypes + rangePayload.skippedExisting) .. ")"
        end
        local option = context:addOption(label, rangePayload, Context.addToRangeFilter)
        if rangePayload.ready ~= true then
            option.notAvailable = true
            option.toolTip = ISInventoryPaneContextMenu.addToolTip()
            option.toolTip.description = text("Context_RangeSyncing", "Range recycle list is still syncing")
        elseif #rangePayload.fullTypes <= 0 then
            option.notAvailable = true
            option.toolTip = ISInventoryPaneContextMenu.addToolTip()
            option.toolTip.description = text("Context_RangeAllPresent", "All selected item types are already in the current range list")
        end
    end
end

GodSystemInventoryContext.register("recycle", Context.fillInventoryMenu)
