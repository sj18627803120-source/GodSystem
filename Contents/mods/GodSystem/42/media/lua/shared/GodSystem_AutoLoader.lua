require "GodSystem_Config"
require "GodSystem_RuntimeConfig"
require "GodSystem_ItemConfig"
require "GodSystem_B42JavaCalls"

GodSystemAutoLoader = GodSystemAutoLoader or {}

local AutoLoader = GodSystemAutoLoader

AutoLoader.FullType = GodSystemConfig.AutoLoaderFullType or "GodSystem.SystemAutoLoader"
AutoLoader.DataKey = "GodSystemAutoLoader"
AutoLoader.OperationKey = "GodSystemAutoLoaderOperations"
AutoLoader.Version = 1
AutoLoader.DefaultCapacity = 2000
AutoLoader.MaxSnapshotItems = 20000
AutoLoader.DepositBatchSize = 500
AutoLoader.MaxLoaders = 64
AutoLoader.MaxMagazines = 256
AutoLoader.SessionLifetimeMs = 60000
AutoLoader.runtime = AutoLoader.runtime or { sessions = {}, sessionSequence = 0, normalizedOperations = {} }

function AutoLoader.safeCall(target, methodName, fallback, ...)
    return GodSystemB42JavaCalls.value(target, methodName, fallback, ...)
end

function AutoLoader.itemId(item)
    local value = AutoLoader.safeCall(item, "getID", nil)
    if value == nil then return nil end
    return tostring(value)
end

function AutoLoader.itemFullType(item)
    local value = AutoLoader.safeCall(item, "getFullType", nil)
    if value == nil or tostring(value) == "" then return nil end
    return tostring(value)
end

function AutoLoader.isLoader(item)
    return AutoLoader.itemFullType(item) == AutoLoader.FullType
end

function AutoLoader.itemsArray(container)
    local values = {}
    local items = AutoLoader.safeCall(container, "getItems", nil)
    if not items then return values end
    if items.size and items.get then
        for index = 0, items:size() - 1 do values[#values + 1] = items:get(index) end
    elseif type(items) == "table" then
        local source = items.values or items
        for index = 1, #source do values[#values + 1] = source[index] end
    end
    return values
end

function AutoLoader.sortItemsById(items)
    table.sort(items, function(left, right)
        local leftId = AutoLoader.itemId(left) or ""
        local rightId = AutoLoader.itemId(right) or ""
        local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
        if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
        return leftId < rightId
    end)
    return items
end

function AutoLoader.childContainer(item)
    return AutoLoader.safeCall(item, "getInventory", nil)
end

function AutoLoader.walkCarried(player, visitor, maximum)
    local root = AutoLoader.safeCall(player, "getInventory", nil)
    if not root then return 0, false end
    maximum = math.max(1, math.floor(tonumber(maximum) or AutoLoader.MaxSnapshotItems))
    local count, limited = 0, false
    local pending, seenContainers = {}, {}

    local function visitContainer(container, depth, sortItems)
        if not container or seenContainers[container] then return true end
        seenContainers[container] = true
        local items = AutoLoader.itemsArray(container)
        if sortItems then AutoLoader.sortItemsById(items) end
        for index = 1, #items do
            count = count + 1
            if count > maximum then limited = true return false end
            local item = items[index]
            if visitor(item, container, depth, count) == false then return false end
            local child = AutoLoader.childContainer(item)
            if child then pending[#pending + 1] = { item = item, container = child, depth = depth + 1 } end
        end
        return true
    end

    if not visitContainer(root, 0, false) then return math.min(count, maximum), limited end
    while #pending > 0 do
        table.sort(pending, function(left, right)
            local leftId = AutoLoader.itemId(left.item) or ""
            local rightId = AutoLoader.itemId(right.item) or ""
            local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
            if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
            return leftId < rightId
        end)
        local row = table.remove(pending, 1)
        if not visitContainer(row.container, row.depth, true) then break end
    end
    return math.min(count, maximum), limited
end

function AutoLoader.findCarriedItem(player, itemId)
    itemId = tostring(itemId or "")
    if itemId == "" then return nil end
    local found, source
    AutoLoader.walkCarried(player, function(item, container)
        if AutoLoader.itemId(item) == itemId then found, source = item, container return false end
        return true
    end, AutoLoader.MaxSnapshotItems + AutoLoader.MaxLoaders + AutoLoader.MaxMagazines)
    return found, source
end

function AutoLoader.isItemCarried(player, item)
    local itemId = AutoLoader.itemId(item)
    if not itemId then return false end
    return AutoLoader.findCarriedItem(player, itemId) == item
end

function AutoLoader.isFavorite(item)
    return AutoLoader.safeCall(item, "isFavorite", false) == true
end

function AutoLoader.isLooseAmmo(item)
    if not item or not item.hasTag or not ItemTag or not ItemTag.AMMO then return false end
    local ok, value = GodSystemB42JavaCalls.try(item, "hasTag", ItemTag.AMMO)
    return ok and value == true
end

function AutoLoader.isHandWeapon(item)
    if not item then return false end
    if instanceof then
        local ok, value = pcall(instanceof, item, "HandWeapon")
        if ok and value == true then return true end
    end
    return false
end

function AutoLoader.magazineAmmoFullType(item)
    if not item or AutoLoader.isHandWeapon(item) then return nil end
    local ammoType = AutoLoader.safeCall(item, "getAmmoType", nil)
    local maximum = tonumber(AutoLoader.safeCall(item, "getMaxAmmo", 0)) or 0
    if not ammoType or maximum <= 0 or not ammoType.getItemKey then return nil end
    local ok, itemKey = GodSystemB42JavaCalls.try(ammoType, "getItemKey")
    if not ok or not itemKey or tostring(itemKey) == "" then return nil end
    return tostring(itemKey)
end

function AutoLoader.isMagazine(item)
    return AutoLoader.magazineAmmoFullType(item) ~= nil
end

function AutoLoader.getCapacity()
    local fallback = tonumber(GodSystemConfig.AutoLoaderAmmoCapacity) or AutoLoader.DefaultCapacity
    local value = fallback
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        value = tonumber(GodSystemRuntimeConfig.get("AutoLoaderAmmoCapacity", fallback)) or fallback
    end
    return math.max(100, math.min(10000, math.floor(value)))
end

function AutoLoader.getStore(loader, create)
    if not AutoLoader.isLoader(loader) then return nil end
    local modData = AutoLoader.safeCall(loader, "getModData", nil)
    if type(modData) ~= "table" then return nil end
    local store = modData[AutoLoader.DataKey]
    if type(store) ~= "table" and create == true then
        store = { version = AutoLoader.Version, ammo = {}, names = {} }
        modData[AutoLoader.DataKey] = store
    end
    if type(store) ~= "table" then return nil end
    store.version = AutoLoader.Version
    store.ammo = type(store.ammo) == "table" and store.ammo or {}
    store.names = type(store.names) == "table" and store.names or {}
    for fullType, count in pairs(store.ammo) do
        fullType = tostring(fullType or "")
        count = math.max(0, math.floor(tonumber(count) or 0))
        if fullType == "" or count <= 0 then store.ammo[fullType] = nil else store.ammo[fullType] = count end
    end
    return store
end

function AutoLoader.getBalance(loader, fullType)
    local store = AutoLoader.getStore(loader, false)
    if not store then return 0 end
    return math.max(0, math.floor(tonumber(store.ammo[tostring(fullType or "")]) or 0))
end

function AutoLoader.setBalance(loader, fullType, count, displayName)
    fullType = tostring(fullType or "")
    if fullType == "" then return 0 end
    local store = AutoLoader.getStore(loader, true)
    if not store then return 0 end
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then
        store.ammo[fullType] = nil
    else
        store.ammo[fullType] = count
        if displayName and tostring(displayName) ~= "" then store.names[fullType] = tostring(displayName) end
    end
    return count
end

function AutoLoader.syncLoader(player, loader)
    if syncItemModData then pcall(syncItemModData, player, loader) end
    if syncItemFields then pcall(syncItemFields, player, loader) end
    if sendItemStats then pcall(sendItemStats, loader) end
end

function AutoLoader.scriptItem(fullType)
    if not getScriptManager then return nil end
    local okManager, manager = pcall(getScriptManager)
    if not okManager or not manager or not manager.FindItem then return nil end
    local okItem, scriptItem = GodSystemB42JavaCalls.try(manager, "FindItem", tostring(fullType or ""))
    return okItem and scriptItem or nil
end

function AutoLoader.typeAvailable(fullType)
    return AutoLoader.scriptItem(fullType) ~= nil
end

function AutoLoader.typeDisplayName(fullType, fallback)
    local scriptItem = AutoLoader.scriptItem(fullType)
    local name = AutoLoader.safeCall(scriptItem, "getDisplayName", nil)
    if name and tostring(name) ~= "" then return tostring(name) end
    return tostring(fallback or fullType or "")
end

function AutoLoader.stateFor(loader)
    if not AutoLoader.isLoader(loader) then return nil end
    local store = AutoLoader.getStore(loader, true)
    local state = { loaderId = AutoLoader.itemId(loader), capacity = AutoLoader.getCapacity(), total = 0, ammo = {} }
    for fullType, count in pairs(store.ammo) do
        count = math.max(0, math.floor(tonumber(count) or 0))
        if count > 0 then
            local row = {
                fullType = tostring(fullType),
                count = count,
                capacity = state.capacity,
                available = AutoLoader.typeAvailable(fullType),
                name = AutoLoader.typeDisplayName(fullType, store.names[fullType]),
            }
            state.ammo[#state.ammo + 1] = row
            state.total = state.total + count
        end
    end
    table.sort(state.ammo, function(left, right)
        local leftName = tostring(left.name or left.fullType):lower()
        local rightName = tostring(right.name or right.fullType):lower()
        if leftName ~= rightName then return leftName < rightName end
        return tostring(left.fullType) < tostring(right.fullType)
    end)
    return state
end

function AutoLoader.depositDurationSeconds(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return 0 end
    return math.min(15, 1 + math.ceil(count / 100) * 0.5)
end

function AutoLoader.scanDeposit(player, loader)
    if not AutoLoader.isLoader(loader) or not AutoLoader.isItemCarried(player, loader) then return {}, { reason = "notCarried" } end
    local records = {}
    local stats = { eligible = 0, favoriteSkipped = 0, capacitySkipped = 0, limitSkipped = 0 }
    local capacity = AutoLoader.getCapacity()
    local reserved = {}
    AutoLoader.walkCarried(player, function(item)
        if item ~= loader and AutoLoader.isLooseAmmo(item) then
            stats.eligible = stats.eligible + 1
            if AutoLoader.isFavorite(item) then
                stats.favoriteSkipped = stats.favoriteSkipped + 1
            else
                local fullType = AutoLoader.itemFullType(item)
                local used = AutoLoader.getBalance(loader, fullType) + (reserved[fullType] or 0)
                if used >= capacity then
                    stats.capacitySkipped = stats.capacitySkipped + 1
                elseif #records >= AutoLoader.MaxSnapshotItems then
                    stats.limitSkipped = stats.limitSkipped + 1
                else
                    reserved[fullType] = (reserved[fullType] or 0) + 1
                    records[#records + 1] = {
                        itemId = AutoLoader.itemId(item),
                        fullType = fullType,
                        displayName = tostring(AutoLoader.safeCall(item, "getDisplayName", fullType)),
                    }
                end
            end
        end
        return true
    end, AutoLoader.MaxSnapshotItems + AutoLoader.MaxLoaders + AutoLoader.MaxMagazines + 4096)
    stats.selected = #records
    return records, stats
end

function AutoLoader.containerContains(container, target)
    local targetId = AutoLoader.itemId(target)
    if not targetId then return false end
    local items = AutoLoader.itemsArray(container)
    for index = 1, #items do if AutoLoader.itemId(items[index]) == targetId then return true end end
    return false
end

function AutoLoader.settleDepositRecords(player, loader, records)
    local stats = { requested = #(records or {}), stored = 0, skipped = 0, failed = 0, byType = {} }
    if not AutoLoader.isLoader(loader) or not AutoLoader.isItemCarried(player, loader) then stats.reason = "notCarried" return stats end
    local carried = {}
    AutoLoader.walkCarried(player, function(item, container)
        local itemId = AutoLoader.itemId(item)
        if itemId then carried[itemId] = { item = item, container = container } end
        return true
    end, AutoLoader.MaxSnapshotItems + AutoLoader.MaxLoaders + AutoLoader.MaxMagazines + 4096)
    local changed = false
    for index = 1, #(records or {}) do
        local record = records[index] or {}
        local row = carried[tostring(record.itemId or "")]
        local item = row and row.item or nil
        local fullType = item and AutoLoader.itemFullType(item) or nil
        if not item or fullType ~= tostring(record.fullType or "") or not AutoLoader.isLooseAmmo(item) or AutoLoader.isFavorite(item) then
            stats.skipped = stats.skipped + 1
        elseif AutoLoader.getBalance(loader, fullType) >= AutoLoader.getCapacity() then
            stats.skipped = stats.skipped + 1
        else
            local source = row.container or AutoLoader.safeCall(item, "getContainer", nil)
            local removed = source and select(1, GodSystemB42JavaCalls.try(source, "Remove", item))
            if removed and not AutoLoader.containerContains(source, item) then
                if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, source, item) end
                AutoLoader.setBalance(loader, fullType, AutoLoader.getBalance(loader, fullType) + 1, record.displayName)
                stats.stored = stats.stored + 1
                stats.byType[fullType] = (stats.byType[fullType] or 0) + 1
                changed = true
            else
                stats.failed = stats.failed + 1
            end
        end
    end
    if changed then AutoLoader.syncLoader(player, loader) end
    return stats
end

function AutoLoader.getLoaders(player, maximum)
    maximum = math.max(1, math.min(AutoLoader.MaxLoaders, math.floor(tonumber(maximum) or AutoLoader.MaxLoaders)))
    local result, limited = {}, false
    AutoLoader.walkCarried(player, function(item)
        if AutoLoader.isLoader(item) then
            if #result < maximum then result[#result + 1] = item else limited = true end
        end
        return true
    end, AutoLoader.MaxSnapshotItems + AutoLoader.MaxLoaders + AutoLoader.MaxMagazines + 4096)
    AutoLoader.sortItemsById(result)
    return result, limited
end

function AutoLoader.getMagazines(player, maximum)
    maximum = math.max(1, math.min(AutoLoader.MaxMagazines, math.floor(tonumber(maximum) or AutoLoader.MaxMagazines)))
    local result, limited = {}, false
    AutoLoader.walkCarried(player, function(item)
        if AutoLoader.isMagazine(item) then
            if #result < maximum then result[#result + 1] = item else limited = true end
        end
        return true
    end, AutoLoader.MaxSnapshotItems + AutoLoader.MaxLoaders + AutoLoader.MaxMagazines + 4096)
    table.sort(result, function(left, right)
        local leftCount = math.floor(tonumber(AutoLoader.safeCall(left, "getCurrentAmmoCount", 0)) or 0)
        local rightCount = math.floor(tonumber(AutoLoader.safeCall(right, "getCurrentAmmoCount", 0)) or 0)
        if leftCount ~= rightCount then return leftCount > rightCount end
        local leftId, rightId = AutoLoader.itemId(left) or "", AutoLoader.itemId(right) or ""
        local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
        if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
        return leftId < rightId
    end)
    return result, limited
end

function AutoLoader.fillMagazines(player, loaders, magazineLimit)
    local usableLoaders, changedLoaders = {}, {}
    for index = 1, math.min(#(loaders or {}), AutoLoader.MaxLoaders) do
        local loader = loaders[index]
        if AutoLoader.isLoader(loader) and AutoLoader.isItemCarried(player, loader) then usableLoaders[#usableLoaders + 1] = loader end
    end
    local magazines, magazineLimited = AutoLoader.getMagazines(player, magazineLimit or AutoLoader.MaxMagazines)
    local stats = { rounds = 0, magazines = 0, need = 0, remainingNeed = 0, loaderLimited = #(loaders or {}) > AutoLoader.MaxLoaders, magazineLimited = magazineLimited }
    for index = 1, #magazines do
        local magazine = magazines[index]
        local ammoFullType = AutoLoader.magazineAmmoFullType(magazine)
        local current = math.max(0, math.floor(tonumber(AutoLoader.safeCall(magazine, "getCurrentAmmoCount", 0)) or 0))
        local maximum = math.max(0, math.floor(tonumber(AutoLoader.safeCall(magazine, "getMaxAmmo", 0)) or 0))
        local need = math.max(0, maximum - current)
        stats.need = stats.need + need
        if need > 0 then
            local suppliers = {}
            for loaderIndex = 1, #usableLoaders do
                local loader = usableLoaders[loaderIndex]
                local balance = AutoLoader.getBalance(loader, ammoFullType)
                if balance > 0 then suppliers[#suppliers + 1] = { loader = loader, balance = balance, itemId = AutoLoader.itemId(loader) or "" } end
            end
            table.sort(suppliers, function(left, right)
                if left.balance ~= right.balance then return left.balance < right.balance end
                local leftNumber, rightNumber = tonumber(left.itemId), tonumber(right.itemId)
                if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
                return left.itemId < right.itemId
            end)
            local added = 0
            local taken = {}
            for supplierIndex = 1, #suppliers do
                if added >= need then break end
                local supplier = suppliers[supplierIndex]
                local take = math.min(supplier.balance, need - added)
                if take > 0 then
                    AutoLoader.setBalance(supplier.loader, ammoFullType, supplier.balance - take)
                    supplier.balance = supplier.balance - take
                    taken[#taken + 1] = { loader = supplier.loader, count = take }
                    added = added + take
                end
            end
            if added > 0 then
                local updated = GodSystemB42JavaCalls.try(magazine, "setCurrentAmmoCount", current + added)
                local verified = updated
                    and math.floor(tonumber(AutoLoader.safeCall(magazine, "getCurrentAmmoCount", -1)) or -1) == current + added
                if verified then
                    for takenIndex = 1, #taken do changedLoaders[taken[takenIndex].loader] = true end
                    if syncItemFields then pcall(syncItemFields, player, magazine) end
                    stats.rounds = stats.rounds + added
                    stats.magazines = stats.magazines + 1
                else
                    for takenIndex = 1, #taken do
                        local row = taken[takenIndex]
                        AutoLoader.setBalance(row.loader, ammoFullType,
                            AutoLoader.getBalance(row.loader, ammoFullType) + row.count)
                    end
                    added = 0
                end
            end
            stats.remainingNeed = stats.remainingNeed + math.max(0, need - added)
        end
    end
    for loader in pairs(changedLoaders) do AutoLoader.syncLoader(player, loader) end
    return stats
end

function AutoLoader.withdrawAmmo(player, loader, fullType, count)
    local stats = { requested = math.max(1, math.min(500, math.floor(tonumber(count) or 100))), created = 0 }
    fullType = tostring(fullType or "")
    if not AutoLoader.isLoader(loader) or not AutoLoader.isItemCarried(player, loader) then stats.reason = "notCarried" return stats end
    if not AutoLoader.typeAvailable(fullType) then stats.reason = "unavailable" return stats end
    local balance = AutoLoader.getBalance(loader, fullType)
    local targetCount = math.min(balance, stats.requested)
    local inventory = AutoLoader.safeCall(player, "getInventory", nil)
    if not inventory or not inventory.AddItem then stats.reason = "inventoryMissing" return stats end
    for _ = 1, targetCount do
        local ok, created = GodSystemB42JavaCalls.try(inventory, "AddItem", fullType)
        if not ok or not created then break end
        stats.created = stats.created + 1
        if sendAddItemToContainer then pcall(sendAddItemToContainer, inventory, created) end
    end
    if stats.created > 0 then
        AutoLoader.setBalance(loader, fullType, balance - stats.created)
        AutoLoader.syncLoader(player, loader)
    end
    if stats.created <= 0 and not stats.reason then stats.reason = "createFailed" end
    return stats
end

function AutoLoader.nowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return math.floor(tonumber(value)) end
    end
    return math.floor((os.time and os.time() or 0) * 1000)
end

function AutoLoader.ownerKey(player)
    local username = AutoLoader.safeCall(player, "getUsername", nil)
    if username and tostring(username) ~= "" then return tostring(username) end
    return tostring(AutoLoader.safeCall(player, "getOnlineID", "player"))
end

function AutoLoader.startDepositSession(player, loaderId, opId)
    local loader = AutoLoader.findCarriedItem(player, loaderId)
    if not AutoLoader.isLoader(loader) then return nil, "notCarried" end
    local records, scan = AutoLoader.scanDeposit(player, loader)
    if #records <= 0 then return nil, "nothingToDeposit", scan end
    AutoLoader.runtime.sessionSequence = (AutoLoader.runtime.sessionSequence or 0) + 1
    local sessionId = table.concat({ "gsa", AutoLoader.ownerKey(player), tostring(loaderId), tostring(AutoLoader.nowMs()), tostring(AutoLoader.runtime.sessionSequence) }, "-")
    local batchCount = math.ceil(#records / AutoLoader.DepositBatchSize)
    local session = {
        sessionId = sessionId,
        owner = AutoLoader.ownerKey(player),
        loaderId = tostring(loaderId),
        opId = tostring(opId or ""),
        records = records,
        scan = scan,
        batchCount = batchCount,
        completed = {},
        createdAt = AutoLoader.nowMs(),
        expiresAt = AutoLoader.nowMs() + AutoLoader.SessionLifetimeMs,
    }
    AutoLoader.runtime.sessions[sessionId] = session
    return {
        sessionId = sessionId,
        loaderId = tostring(loaderId),
        total = #records,
        batchCount = batchCount,
        durationSeconds = AutoLoader.depositDurationSeconds(#records),
        skipped = (scan.favoriteSkipped or 0) + (scan.capacitySkipped or 0) + (scan.limitSkipped or 0),
    }, nil, session
end

function AutoLoader.completeDepositBatch(player, sessionId, batchIndex)
    local session = AutoLoader.runtime.sessions[tostring(sessionId or "")]
    if not session or session.owner ~= AutoLoader.ownerKey(player) then return nil, "sessionMissing" end
    if AutoLoader.nowMs() > (tonumber(session.expiresAt) or 0) then
        AutoLoader.runtime.sessions[session.sessionId] = nil
        return nil, "sessionExpired"
    end
    batchIndex = math.floor(tonumber(batchIndex) or 0)
    if batchIndex < 1 or batchIndex > session.batchCount then return nil, "batchInvalid" end
    if session.completed[batchIndex] then return session.completed[batchIndex], nil, session, true end
    local loader = AutoLoader.findCarriedItem(player, session.loaderId)
    if not AutoLoader.isLoader(loader) then return nil, "notCarried", session end
    local first = ((batchIndex - 1) * AutoLoader.DepositBatchSize) + 1
    local last = math.min(#session.records, first + AutoLoader.DepositBatchSize - 1)
    local records = {}
    for index = first, last do records[#records + 1] = session.records[index] end
    local result = AutoLoader.settleDepositRecords(player, loader, records)
    session.completed[batchIndex] = result
    local aggregate = { requested = #session.records, stored = 0, skipped = 0, failed = 0, completedBatches = 0, batchCount = session.batchCount }
    for index = 1, session.batchCount do
        local row = session.completed[index]
        if row then
            aggregate.completedBatches = aggregate.completedBatches + 1
            aggregate.stored = aggregate.stored + (row.stored or 0)
            aggregate.skipped = aggregate.skipped + (row.skipped or 0)
            aggregate.failed = aggregate.failed + (row.failed or 0)
        end
    end
    aggregate.skipped = aggregate.skipped + (session.scan.favoriteSkipped or 0) + (session.scan.capacitySkipped or 0) + (session.scan.limitSkipped or 0)
    aggregate.finished = aggregate.completedBatches >= session.batchCount
    aggregate.sessionId = session.sessionId
    aggregate.loaderId = session.loaderId
    if aggregate.finished then AutoLoader.runtime.sessions[session.sessionId] = nil end
    return result, nil, session, false, aggregate
end

function AutoLoader.cleanupSessions()
    local now = AutoLoader.nowMs()
    for sessionId, session in pairs(AutoLoader.runtime.sessions) do
        if now > (tonumber(session.expiresAt) or 0) then AutoLoader.runtime.sessions[sessionId] = nil end
    end
end

function AutoLoader.fingerprint(kind, args)
    args = type(args) == "table" and args or {}
    local parts = {
        tostring(kind or ""),
        "loader:" .. tostring(args.loaderId or ""),
        "type:" .. tostring(args.fullType or ""),
        "count:" .. tostring(math.floor(tonumber(args.count) or 0)),
    }
    return table.concat(parts, "|")
end

function AutoLoader.validOperationId(args)
    local opId = type(args) == "table" and tostring(args.opId or "") or ""
    if #opId > 96 or not string.match(opId, "^gsa%-%d+%-%d+%-%d+$") then return nil end
    return opId
end

function AutoLoader.operationBucket(player)
    local modData = AutoLoader.safeCall(player, "getModData", nil)
    if type(modData) ~= "table" then return nil end
    modData[AutoLoader.OperationKey] = type(modData[AutoLoader.OperationKey]) == "table" and modData[AutoLoader.OperationKey] or { results = {}, order = {} }
    local bucket = modData[AutoLoader.OperationKey]
    bucket.results = type(bucket.results) == "table" and bucket.results or {}
    bucket.order = type(bucket.order) == "table" and bucket.order or {}
    if not AutoLoader.runtime.normalizedOperations[bucket] then
        for _, result in pairs(bucket.results) do
            if type(result) == "table" and result.status == "processing" then result.status = "unknown" end
        end
        AutoLoader.runtime.normalizedOperations[bucket] = true
    end
    return bucket
end

function AutoLoader.beginOperation(player, kind, args)
    local opId = AutoLoader.validOperationId(args)
    if not opId then return nil, "operationInvalid" end
    local bucket = AutoLoader.operationBucket(player)
    if not bucket then return nil, "operationInvalid" end
    local fingerprint = AutoLoader.fingerprint(kind, args)
    local existing = bucket.results[opId]
    if existing then
        if existing.fingerprint ~= fingerprint then return nil, "operationMismatch" end
        return existing, existing.status
    end
    local operation = { status = "processing", fingerprint = fingerprint }
    bucket.results[opId] = operation
    bucket.order[#bucket.order + 1] = opId
    while #bucket.order > 64 do bucket.results[table.remove(bucket.order, 1)] = nil end
    return operation, nil
end

function AutoLoader.finishOperation(operation, ok, code, payload)
    if not operation then return end
    operation.status = "done"
    operation.ok = ok == true
    operation.code = tostring(code or "")
    operation.payload = payload
end

return AutoLoader
