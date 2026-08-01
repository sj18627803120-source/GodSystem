require "GodSystem_Storage"
require "GodSystem_ItemSnapshot"

GodSystemPersonalStorage = GodSystemPersonalStorage or {}

local Personal = GodSystemPersonalStorage
local Storage = GodSystemStorage
local Snapshot = GodSystemItemSnapshot

Personal.SchemaVersion = 1
Personal.moduleId = "personalStorage"
Personal.PermitFullType = "GodSystem.StorageExpansionPermit"
Personal.PermitCapacity = 200
Personal.GeneralPurchaseCost = 10000
Personal.GeneralPurchaseCapacity = 10
Personal.MaxOperationCache = 128
Personal.Categories = Storage.Categories

local function result(ok, code, data, operationId)
    return {
        ok = ok == true,
        code = tostring(code or ""),
        data = data,
        operationId = operationId and tostring(operationId) or nil,
        moduleId = Personal.moduleId,
    }
end

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then value = fallback or 0 end
    return math.max(0, math.floor(value))
end

local function categoryValid(category)
    category = tostring(category or "")
    for i = 1, #Personal.Categories do
        if Personal.Categories[i] == category then return true end
    end
    return false
end

local function emptyStore()
    local capacities, entries = {}, {}
    for i = 1, #Personal.Categories do
        capacities[Personal.Categories[i]] = 0
        entries[Personal.Categories[i]] = {}
    end
    return {
        schemaVersion = Personal.SchemaVersion,
        capacities = capacities,
        generalCapacity = 0,
        revision = 0,
        nextEntryId = 1,
        entriesByCategory = entries,
        simplifiedTypes = {},
        boundedOperations = {},
        operationOrder = {},
    }
end

function Personal.normalizeData(accountData)
    accountData = type(accountData) == "table" and accountData or {}
    local store = type(accountData.personalStorage) == "table" and accountData.personalStorage or emptyStore()
    store.schemaVersion = Personal.SchemaVersion
    store.capacities = type(store.capacities) == "table" and store.capacities or {}
    store.entriesByCategory = type(store.entriesByCategory) == "table" and store.entriesByCategory or {}
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        store.capacities[category] = integer(store.capacities[category], 0)
        store.entriesByCategory[category] = type(store.entriesByCategory[category]) == "table"
            and store.entriesByCategory[category] or {}
    end
    store.generalCapacity = integer(store.generalCapacity, 0)
    store.revision = integer(store.revision, 0)
    store.nextEntryId = math.max(1, integer(store.nextEntryId, 1))
    store.simplifiedTypes = type(store.simplifiedTypes) == "table" and store.simplifiedTypes or {}
    store.boundedOperations = type(store.boundedOperations) == "table" and store.boundedOperations or {}
    store.operationOrder = type(store.operationOrder) == "table" and store.operationOrder or {}
    accountData.personalStorage = store
    return store
end

function Personal.entryCount(entry)
    return math.max(1, integer(entry and entry.itemCount, entry and entry.snapshot and Snapshot.count(entry.snapshot) or 1))
end

function Personal.usage(store)
    store = type(store) == "table" and store or emptyStore()
    local categories, generalUsed, total = {}, 0, 0
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        local used = 0
        for _, entry in pairs((store.entriesByCategory or {})[category] or {}) do
            used = used + Personal.entryCount(entry)
        end
        local capacity = integer((store.capacities or {})[category], 0)
        local overflow = math.max(0, used - capacity)
        categories[category] = { used = used, capacity = capacity, overflow = overflow }
        generalUsed = generalUsed + overflow
        total = total + used
    end
    return {
        categories = categories,
        generalUsed = generalUsed,
        generalCapacity = integer(store.generalCapacity, 0),
        total = total,
    }
end

function Personal.canAdd(store, category, amount)
    if not categoryValid(category) then return false, "invalidCategory" end
    amount = math.max(1, integer(amount, 1))
    local usage = Personal.usage(store)
    local row = usage.categories[category]
    local newOverflow = math.max(0, row.used + amount - row.capacity)
    local projectedGeneral = usage.generalUsed - row.overflow + newOverflow
    if projectedGeneral > usage.generalCapacity then return false, "capacityFull", projectedGeneral end
    return true, nil, projectedGeneral
end

function Personal.hasCapacity(store)
    store = type(store) == "table" and store or {}
    if integer(store.generalCapacity, 0) > 0 then return true end
    for i = 1, #Personal.Categories do
        if integer(store.capacities and store.capacities[Personal.Categories[i]], 0) > 0 then return true end
    end
    return false
end

function Personal.addCategoryCapacity(store, category, amount)
    if not categoryValid(category) then return result(false, "invalidCategory") end
    amount = math.max(1, integer(amount, Personal.PermitCapacity))
    store.capacities[category] = integer(store.capacities[category], 0) + amount
    store.revision = integer(store.revision, 0) + 1
    return result(true, "capacityExpanded", {
        category = category,
        amount = amount,
        capacity = store.capacities[category],
        revision = store.revision,
    })
end

function Personal.addGeneralCapacity(store, amount)
    amount = math.max(1, integer(amount, Personal.GeneralPurchaseCapacity))
    store.generalCapacity = integer(store.generalCapacity, 0) + amount
    store.revision = integer(store.revision, 0) + 1
    return result(true, "generalExpanded", {
        amount = amount,
        capacity = store.generalCapacity,
        revision = store.revision,
    })
end

local function operationFingerprint(kind, values)
    local parts = { tostring(kind or "") }
    for i = 1, #(values or {}) do parts[#parts + 1] = tostring(values[i] or "") end
    return table.concat(parts, "|")
end

function Personal.beginOperation(store, operationId, fingerprint)
    operationId = tostring(operationId or "")
    if operationId == "" then return nil, result(false, "operationIdRequired") end
    local existing = store.boundedOperations[operationId]
    if existing then
        if tostring(existing.fingerprint or "") ~= tostring(fingerprint or "") then
            return nil, result(false, "operationMismatch", nil, operationId)
        end
        return nil, existing.result or result(false, "operationPending", nil, operationId)
    end
    store.boundedOperations[operationId] = { fingerprint = tostring(fingerprint or ""), pending = true }
    store.operationOrder[#store.operationOrder + 1] = operationId
    while #store.operationOrder > Personal.MaxOperationCache do
        local oldest = table.remove(store.operationOrder, 1)
        store.boundedOperations[oldest] = nil
    end
    return store.boundedOperations[operationId], nil
end

function Personal.finishOperation(store, operationId, operationResult)
    operationId = tostring(operationId or "")
    local row = store.boundedOperations[operationId]
    if row then
        row.pending = nil
        row.result = operationResult
    end
    return operationResult
end

function Personal.discardOperation(store, operationId)
    operationId = tostring(operationId or "")
    if operationId == "" or type(store) ~= "table" then return end
    store.boundedOperations[operationId] = nil
    for i = #(store.operationOrder or {}), 1, -1 do
        if tostring(store.operationOrder[i]) == operationId then table.remove(store.operationOrder, i); break end
    end
end

local function nextEntryId(store)
    local number = math.max(1, integer(store.nextEntryId, 1))
    store.nextEntryId = number + 1
    return "ps-" .. tostring(number)
end

function Personal.createEntry(item)
    if not item then return result(false, "missingItem") end
    if Storage.isProtected(item) or Storage.itemFullType(item) == Personal.PermitFullType then
        return result(false, "protectedItem")
    end
    local captured = Snapshot.capture(item)
    if not captured.ok then return result(false, captured.code, captured.data) end
    local snapshot = captured.data.snapshot
    return result(true, captured.code, {
        snapshot = snapshot,
        category = snapshot.category,
        itemCount = Snapshot.count(snapshot),
        simplified = captured.data.report.simplified == true,
        report = captured.data.report,
    })
end

local function removeFrom(container, item)
    if not container or not item or not Storage.containerContains(container, item) then return false end
    local ok = pcall(function() container:Remove(item) end)
    if ok and not Storage.containerContains(container, item) then
        Storage.syncRemove(container, item)
        return true
    end
    return false
end

local function addTo(container, item)
    if not container or not item then return false end
    local ok = pcall(function() container:AddItem(item) end)
    if ok and Storage.containerContains(container, item) then
        Storage.syncAdd(container, item)
        return true
    end
    return false
end

function Personal.deposit(store, item, sourceContainer, operationId)
    local itemId = Storage.itemId(item)
    local fingerprint = operationFingerprint("deposit", { itemId, Storage.itemFullType(item) })
    local op, previous = Personal.beginOperation(store, operationId, fingerprint)
    if previous then return previous end
    local created = Personal.createEntry(item)
    if not created.ok then return Personal.finishOperation(store, operationId, result(false, created.code, created.data, operationId)) end
    local data = created.data
    local allowed, reason = Personal.canAdd(store, data.category, data.itemCount)
    if not allowed then return Personal.finishOperation(store, operationId, result(false, reason, nil, operationId)) end
    if not Storage.containerContains(sourceContainer, item) then
        return Personal.finishOperation(store, operationId, result(false, "sourceChanged", nil, operationId))
    end
    if not removeFrom(sourceContainer, item) then
        return Personal.finishOperation(store, operationId, result(false, "removeFailed", nil, operationId))
    end
    local entryId = nextEntryId(store)
    local entry = {
        entryId = entryId,
        category = data.category,
        fullType = data.snapshot.fullType,
        displayName = data.snapshot.displayName,
        modName = data.snapshot.modName,
        states = data.snapshot.states,
        itemCount = data.itemCount,
        simplified = data.simplified,
        simplifiedReasons = data.report.reasons,
        snapshot = data.snapshot,
    }
    local committed = pcall(function() store.entriesByCategory[data.category][entryId] = entry end)
    if not committed then
        addTo(sourceContainer, item)
        return Personal.finishOperation(store, operationId, result(false, "commitFailed", nil, operationId))
    end
    if data.simplified then
        store.simplifiedTypes[entry.fullType] = integer(store.simplifiedTypes[entry.fullType], 0) + 1
    end
    store.revision = integer(store.revision, 0) + 1
    return Personal.finishOperation(store, operationId, result(true, data.simplified and "storedSimplified" or "stored", {
        entryId = entryId,
        category = entry.category,
        itemCount = entry.itemCount,
        simplified = entry.simplified,
        revision = store.revision,
    }, operationId))
end

function Personal.findEntry(store, entryId)
    entryId = tostring(entryId or "")
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        local entry = store.entriesByCategory[category][entryId]
        if entry then return entry, category end
    end
    return nil, nil
end

function Personal.withdraw(store, entryId, targetContainer, operationId)
    local entry, category = Personal.findEntry(store, entryId)
    local fingerprint = operationFingerprint("withdraw", { entryId })
    local op, previous = Personal.beginOperation(store, operationId, fingerprint)
    if previous then return previous end
    if not entry then return Personal.finishOperation(store, operationId, result(false, "entryMissing", nil, operationId)) end
    local restored = Snapshot.restore(entry.snapshot)
    if not restored.ok then
        return Personal.finishOperation(store, operationId, result(false, restored.code, {
            entryId = entryId,
            missingDefinition = restored.code == "missingDefinition",
        }, operationId))
    end
    local item = restored.data.item
    if not addTo(targetContainer, item) then
        if targetContainer and Storage.containerContains(targetContainer, item) then removeFrom(targetContainer, item) end
        return Personal.finishOperation(store, operationId, result(false, "targetRejected", nil, operationId))
    end
    store.entriesByCategory[category][entryId] = nil
    if entry.simplified and store.simplifiedTypes[entry.fullType] then
        store.simplifiedTypes[entry.fullType] = math.max(0, integer(store.simplifiedTypes[entry.fullType], 1) - 1)
        if store.simplifiedTypes[entry.fullType] == 0 then store.simplifiedTypes[entry.fullType] = nil end
    end
    store.revision = integer(store.revision, 0) + 1
    return Personal.finishOperation(store, operationId, result(true, "withdrawn", {
        entryId = entryId,
        itemId = Storage.itemId(item),
        category = category,
        revision = store.revision,
    }, operationId))
end

function Personal.withdrawWith(store, entryId, operationId, acceptItem)
    local entry, category = Personal.findEntry(store, entryId)
    local fingerprint = operationFingerprint("withdrawWith", { entryId })
    local op, previous = Personal.beginOperation(store, operationId, fingerprint)
    if previous then return previous end
    if not entry then return Personal.finishOperation(store, operationId, result(false, "entryMissing", nil, operationId)) end
    if type(acceptItem) ~= "function" then
        return Personal.finishOperation(store, operationId, result(false, "targetMissing", nil, operationId))
    end
    local restored = Snapshot.restore(entry.snapshot)
    if not restored.ok then
        return Personal.finishOperation(store, operationId, result(false, restored.code, {
            entryId = entryId,
            missingDefinition = restored.code == "missingDefinition",
        }, operationId))
    end
    local item = restored.data.item
    local accepted, acceptReason, acceptData = acceptItem(item, entry)
    if accepted ~= true then
        return Personal.finishOperation(store, operationId, result(false, acceptReason or "targetRejected", acceptData, operationId))
    end
    store.entriesByCategory[category][entryId] = nil
    if entry.simplified and store.simplifiedTypes[entry.fullType] then
        store.simplifiedTypes[entry.fullType] = math.max(0, integer(store.simplifiedTypes[entry.fullType], 1) - 1)
        if store.simplifiedTypes[entry.fullType] == 0 then store.simplifiedTypes[entry.fullType] = nil end
    end
    store.revision = integer(store.revision, 0) + 1
    return Personal.finishOperation(store, operationId, result(true, "withdrawn", {
        entryId = entryId,
        itemId = Storage.itemId(item),
        category = category,
        route = acceptData,
        revision = store.revision,
    }, operationId))
end

function Personal.consumePermit(store, permit, sourceContainer, category, operationId)
    local permitId = Storage.itemId(permit)
    local fingerprint = operationFingerprint("permit", { permitId, category })
    local op, previous = Personal.beginOperation(store, operationId, fingerprint)
    if previous then return previous end
    if not categoryValid(category) then
        return Personal.finishOperation(store, operationId, result(false, "invalidCategory", nil, operationId))
    end
    if Storage.itemFullType(permit) ~= Personal.PermitFullType or not Storage.containerContains(sourceContainer, permit) then
        return Personal.finishOperation(store, operationId, result(false, "permitMissing", nil, operationId))
    end
    if not removeFrom(sourceContainer, permit) then
        return Personal.finishOperation(store, operationId, result(false, "permitRemoveFailed", nil, operationId))
    end
    local expanded = Personal.addCategoryCapacity(store, category, Personal.PermitCapacity)
    if not expanded.ok then
        addTo(sourceContainer, permit)
        return Personal.finishOperation(store, operationId, result(false, expanded.code, nil, operationId))
    end
    expanded.operationId = tostring(operationId)
    return Personal.finishOperation(store, operationId, expanded)
end

function Personal.summary(store)
    local usage = Personal.usage(store)
    local groups, simplified = {}, 0
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        local grouped = {}
        for _, entry in pairs(store.entriesByCategory[category] or {}) do
            local key = tostring(entry.fullType or "") .. "|" .. tostring(entry.displayName or "")
            local row = grouped[key]
            if not row then
                row = {
                    groupKey = key,
                    category = category,
                    fullType = entry.fullType,
                    name = entry.displayName,
                    modName = entry.modName,
                    entries = 0,
                    items = 0,
                    simplified = 0,
                    states = {},
                }
                grouped[key] = row
            end
            row.entries = row.entries + 1
            row.items = row.items + Personal.entryCount(entry)
            for stateIndex = 1, #(entry.states or {}) do row.states[tostring(entry.states[stateIndex])] = true end
            if entry.simplified then
                row.simplified = row.simplified + 1
                row.states.simplified = true
                simplified = simplified + 1
            end
        end
        for _, row in pairs(grouped) do
            local stateList = {}
            for state in pairs(row.states) do stateList[#stateList + 1] = state end
            table.sort(stateList)
            row.states = stateList
            groups[#groups + 1] = row
        end
    end
    table.sort(groups, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
        return tostring(a.fullType) < tostring(b.fullType)
    end)
    return {
        schemaVersion = Personal.SchemaVersion,
        revision = integer(store.revision, 0),
        usage = usage,
        groups = groups,
        simplifiedEntries = simplified,
        unlocked = Personal.hasCapacity(store),
    }
end

function Personal.entries(store, groupKey, offset, limit)
    offset = integer(offset, 0)
    limit = math.min(100, math.max(1, integer(limit, 50)))
    local rows = {}
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        for _, entry in pairs(store.entriesByCategory[category] or {}) do
            local key = tostring(entry.fullType or "") .. "|" .. tostring(entry.displayName or "")
            if not groupKey or tostring(groupKey) == key then
                rows[#rows + 1] = {
                    entryId = entry.entryId,
                    groupKey = key,
                    category = category,
                    fullType = entry.fullType,
                    displayName = entry.displayName,
                    modName = entry.modName,
                    states = entry.states,
                    itemCount = Personal.entryCount(entry),
                    simplified = entry.simplified == true,
                    simplifiedReasons = entry.simplifiedReasons,
                }
            end
        end
    end
    table.sort(rows, function(a, b) return tostring(a.entryId) < tostring(b.entryId) end)
    local page = {}
    for i = offset + 1, math.min(#rows, offset + limit) do page[#page + 1] = rows[i] end
    return { rows = page, total = #rows, offset = offset, limit = limit }
end

function Personal.newOperationId(kind)
    return Storage.newId("personal-" .. tostring(kind or "op"), tostring(kind or ""))
end

function Personal.health(accountData)
    local store = type(accountData) == "table" and accountData.personalStorage or nil
    if type(store) ~= "table" then
        return result(false, "stateMissing", {
            schemaVersion = 0, revision = 0, entries = 0, generalUsed = 0, generalCapacity = 0,
        })
    end
    local usage = Personal.usage(store)
    return result(true, "ok", {
        schemaVersion = store.schemaVersion,
        revision = store.revision,
        entries = usage.total,
        generalUsed = usage.generalUsed,
        generalCapacity = usage.generalCapacity,
    })
end

return Personal
