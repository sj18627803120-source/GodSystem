require "GodSystem_App"
require "GodSystem_Core"
require "GodSystem_RangeFilter"
require "GodSystem_InventoryContext"
require "GodSystem_InventoryIndex"
require "GodSystem_RecyclePreparation"
require "GodSystem_RecyclePreparationUI"
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

function Context.newAnalysis()
    if not GodSystemApp.services.runtime
        or GodSystemApp.services.runtime.isFeatureEnabled("EnableRecycle") == false then
        return { disabled = true, recycle = {} }
    end
    return {
        data = GodSystemApp.services.runtime.getData(),
        configuredShopKeySet = GodSystemInventoryContext.getConfiguredShopKeySet(),
        recycle = {},
        recycleByFullType = {},
        listByVariantKey = {},
    }
end

function Context.analyzeItem(cache, item, snapshotEntry)
        if cache.disabled then return { allowed = false, reason = "disabled" } end
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
        return entry
end

local function createAnalysisCache(items, entries)
    local cache = Context.newAnalysis()
    for i = 1, #items do Context.analyzeItem(cache, items[i], entries and entries[i]) end
    return cache
end

function Context.classifyItem(item, mode, cached)
    if not cached or not cached.allowed then
        local reason = cached and cached.reason
        return false, reason == "disabled" and "ContextReason_RecycleDisabled"
            or reason == "protected" and "ContextReason_Protected" or "ContextReason_Invalid"
    end
    if mode == "recycle" or cached.listable then return true, nil end
    local reasons = { alreadyListed = "ContextReason_AlreadyListed", hiddenListed = "ContextReason_HiddenListed",
        configuredListed = "ContextReason_ConfiguredListed" }
    return mode == "recycleAndList", reasons[cached.listReason] or "ContextReason_NotListable"
end

local function classifyAll(items, analysis)
    local result = {
        recycle = { eligible = {}, skipped = 0 },
        recycleAndList = { eligible = {}, skipped = 0 },
        listOnly = { eligible = {}, skipped = 0 },
    }
    for i = 1, #items do
        local item = items[i]
        for mode, target in pairs(result) do
            local eligible, reason = Context.classifyItem(item, mode, analysis.recycle[item])
            if eligible then target.eligible[#target.eligible + 1] = item end
            if not eligible or reason then
                target.skipped = target.skipped + 1
                target.firstReason = target.firstReason or reason
            end
        end
    end
    return result
end

local function rangeFilterView(playerNum)
    local service = GodSystemApp.services and GodSystemApp.services.rangeRecycle
    if not service or not service.getContextMenuState then return nil end
    return service:getContextMenuState(playerNum)
end

local function rangeFilterPayload(playerNum, items)
    local state = rangeFilterView(playerNum)
    if not state or not state.enabled then return nil end
    local active = state.members
    local all = collectFullTypes(items)
    local missing, existing, skipped = {}, {}, 0
    for i = 1, #all do
        if active[all[i]] then
            skipped = skipped + 1
            existing[#existing + 1] = all[i]
        elseif #missing < 256 then
            missing[#missing + 1] = all[i]
        else
            skipped = skipped + 1
        end
    end
    return {
        playerNum = playerNum,
        fullTypes = missing,
        existingTypes = existing,
        skippedExisting = skipped,
        mode = state.mode,
        revision = state.revision,
        token = state.token,
        ready = state.ready == true,
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
    local state = rangeFilterView(data.playerNum)
    if not state or not state.enabled or not state.ready or (data.token and state.token ~= data.token) then
        GodSystemApp.services.runtime.notify(text("Notify_RecycleSelectionChanged", "Selection changed; reopen the menu"))
        return false
    end
    local result = service:execute(data.playerNum, "filterDelta", {
        baseRevision = state.revision,
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

function Context.removeFromRangeFilter(payload)
    local data = payload or {}
    if data.ready ~= true then
        GodSystemApp.services.runtime.notify(text("Context_RangeSyncing", "Range recycle list is still syncing"))
        return false
    end
    if #(data.existingTypes or {}) <= 0 then
        GodSystemApp.services.runtime.notify(text("Notify_RecycleSelectionChanged", "Selection changed; reopen the menu"))
        return false
    end
    local service = GodSystemApp.services.rangeRecycle
    local state = rangeFilterView(data.playerNum)
    if not state or not state.enabled or not state.ready or (data.token and state.token ~= data.token) then
        GodSystemApp.services.runtime.notify(text("Notify_RecycleSelectionChanged", "Selection changed; reopen the menu"))
        return false
    end
    local result = service:execute(data.playerNum, "filterDelta", {
        baseRevision = state.revision,
        op = "removeMany",
        fullTypes = data.existingTypes,
    }, function(value)
        if value and value.ok then
            GodSystemApp.services.runtime.notify(formatText(text("Context_RangeRemoved", "Removed {1} item types from the range list"), {
                #data.existingTypes,
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
    local inventoryIndex = GodSystemInventoryIndex.build(player:getInventory())
    for i = 1, #(payload.items or {}) do
        local id = itemId(payload.items[i])
        if not id or GodSystemInventoryIndex.find(inventoryIndex, id) ~= payload.items[i] then
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

function Context.startBulk(payload, mode)
    local UI = GodSystemRecyclePreparationUI
    local job = GodSystemRecyclePreparation.start(payload.snapshot, mode, {
        close = UI.dismiss, progress = UI.update, ready = UI.update,
        failed = function(_, reason)
            GodSystemApp.services.runtime.notify(reason == "submission"
                and text("RecyclePrep_SubmissionFailed", "Submission failed; check inventory and transaction result before retrying")
                or reason == "empty"
                and text("RecyclePrep_Empty", "No eligible items or new types")
                or text("RecyclePrep_Changed", "Items, contents or settings changed; please try again"))
        end,
        execute = function(prepared)
            if prepared.mode == "rangeFilter" then
                Context.addToRangeFilter({ playerNum = prepared.playerNum, fullTypes = prepared.rangeTypes,
                    skippedExisting = prepared.rangeSkipped, ready = true, token = prepared.range.token })
            else
                Context.queueTransfers({ playerNum = prepared.playerNum, items = prepared.items, mode = prepared.mode,
                    allowDestroyContents = prepared.hasContents == true,
                    containerContentSignatures = prepared.containerContentSignatures, skippedCount = prepared.skipped })
            end
        end,
    })
    if not job then
        GodSystemApp.services.runtime.notify(text("RecyclePrep_Changed", "Items, contents or settings changed; please try again"))
        return false
    end
    UI.open(job)
    return true
end

local function unavailable(option, key, fallback)
    option.notAvailable = true
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    option.toolTip.description = text(key, fallback)
end

function Context.fillInventoryMenu(playerNum, context, values)
    local runtime = GodSystemApp.services.runtime
    if not runtime or runtime.isFeatureEnabled("EnableRecycle") == false then return end
    local snapshot = values and values.__godSystemInventorySnapshot and values
        or GodSystemInventoryContext.createSnapshot(playerNum, values)
    local items = snapshot.items
    if #items <= 0 then return end
    local syncing = isClient and isClient() and GodSystemNetwork and not GodSystemNetwork.isStateReady()
    local classifications
    if not snapshot.bulk and not syncing then
        local entries = GodSystemInventoryContext.getEntries(snapshot)
        classifications = classifyAll(items, createAnalysisCache(items, entries))
    end
    local function addModeOption(labelKey, fallback, mode)
        if not classifications then
            local option = context:addOption(text(labelKey .. "Bulk", fallback .. "..."), { snapshot = snapshot }, Context.startBulk, mode)
            if syncing then unavailable(option, "Context_RecycleSyncing", "Player data is still syncing") end
            return
        end
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
    if runtime.isFeatureEnabled("EnableShop") ~= false
        and runtime.isFeatureEnabled("EnableRecycleListing") ~= false then
        addModeOption("Menu_ContextRecycleAndList", "Recycle and list", "recycleAndList")
        addModeOption("Menu_ContextListOnly", "List only", "listOnly")
    end

    local rangeState = rangeFilterView(playerNum)
    if not rangeState or not rangeState.enabled then return end
    if not classifications then
        local option = context:addOption(text("Menu_ContextRangeBulk", "Add types to range list..."), { snapshot = snapshot }, Context.startBulk, "rangeFilter")
        if not rangeState.ready then unavailable(option, "Context_RangeSyncing", "Range recycle list is still syncing")
        elseif syncing then unavailable(option, "Context_RecycleSyncing", "Player data is still syncing") end
        return
    end
    local rangeClassification = classifications.recycle
    local rangePayload = rangeFilterPayload(playerNum, rangeClassification.eligible)
    if rangePayload then
        local function markSyncing(option)
            option.notAvailable = true
            option.toolTip = ISInventoryPaneContextMenu.addToolTip()
            option.toolTip.description = text("Context_RangeSyncing", "Range recycle list is still syncing")
        end
        -- Types not yet in the list: offer to add them.
        if #rangePayload.fullTypes > 0 then
            local labelKey = rangePayload.mode == "denylist" and "Menu_ContextRangeAddForbidden" or "Menu_ContextRangeAddAllowed"
            local fallback = rangePayload.mode == "denylist" and "Add to forbidden range recycle" or "Add to allowed range recycle"
            local label = text(labelKey, fallback)
            if rangePayload.skippedExisting > 0 then
                label = label .. " (" .. tostring(#rangePayload.fullTypes) .. "/" .. tostring(#rangePayload.fullTypes + rangePayload.skippedExisting) .. ")"
            end
            local option = context:addOption(label, rangePayload, Context.addToRangeFilter)
            if rangePayload.ready ~= true then markSyncing(option) end
        end
        -- Types already in the denylist: replace the add entry with a remove
        -- entry.  The allowlist mode intentionally offers no remove option:
        -- moving a type out of the allowed list silently changes recycle
        -- behavior and is done deliberately from the filter window instead.
        if #rangePayload.existingTypes > 0 and rangePayload.mode == "denylist" then
            local option = context:addOption(text("Menu_ContextRangeRemoveForbidden", "Remove from forbidden range recycle"), rangePayload, Context.removeFromRangeFilter)
            if rangePayload.ready ~= true then markSyncing(option) end
        end
    end
end

GodSystemInventoryContext.register("recycle", Context.fillInventoryMenu)
