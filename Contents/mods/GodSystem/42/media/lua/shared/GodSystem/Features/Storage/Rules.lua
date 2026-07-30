GodSystemStorageFeatureRules = GodSystemStorageFeatureRules or {}

local Rules = GodSystemStorageFeatureRules

Rules.stateVersion = 1
Rules.schemaVersion = 5
Rules.coreFullType = "GodSystem.StorageController"
Rules.coreRecoveryCost = 2000
Rules.coreUseDistance = 3.5
Rules.manageDistance = 2.5
Rules.maxNodes = 128
Rules.maxDepth = 32
Rules.maxIndexedItems = 20000
Rules.indexBatchItems = 250
Rules.indexBudgetMs = 2
Rules.snapshotGroupChunk = 100

Rules.roles = {
    "general", "fridge", "freezer", "food", "perishable", "drink", "medical",
    "weapon", "ammo", "tool", "material", "clothing", "book", "container",
    "furniture", "other",
}
Rules.categories = {
    "food", "perishable", "drink", "medical", "weapon", "ammo", "tool",
    "material", "clothing", "book", "container", "furniture", "other",
}
Rules.priorityTiers = { "lowest", "low", "normal", "high", "highest" }
Rules.priorityRanks = {
    lowest = 1,
    low = 2,
    normal = 3,
    high = 4,
    highest = 5,
}

local roleSet, categorySet = {}, {}
for index = 1, #Rules.roles do roleSet[Rules.roles[index]] = true end
for index = 1, #Rules.categories do categorySet[Rules.categories[index]] = true end

local function finite(value)
    value = tonumber(value)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
    then
        return nil
    end
    return value
end

local function integer(value, fallback)
    value = finite(value)
    if value == nil then return math.floor(tonumber(fallback) or 0) end
    return math.floor(value)
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function normalizedCategorySet(value)
    local result = {}
    if type(value) ~= "table" then return result end
    for key, child in pairs(value) do
        local category = type(key) == "number" and tostring(child or "") or tostring(key or "")
        local enabled = type(key) == "number" or child == true
        if enabled and categorySet[category] then result[category] = true end
    end
    return result
end

local function setCount(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

function Rules.copy(value)
    return copy(value)
end

function Rules.integer(value, fallback)
    return integer(value, fallback)
end

function Rules.normalizeRole(value)
    value = tostring(value or "general")
    if value == "auto" or value == "noAuto" then value = "general" end
    if value == "liquid" then value = "drink" end
    if roleSet[value] then return value end
    return "general"
end

function Rules.isRole(value)
    return roleSet[tostring(value or "")] == true
        or value == "auto"
        or value == "noAuto"
        or value == "liquid"
end

function Rules.normalizePriority(value)
    value = tostring(value or "")
    if Rules.priorityRanks[value] then return value end
    local numeric = math.max(0, math.min(100, integer(value, 50)))
    if numeric <= 20 then return "lowest" end
    if numeric <= 40 then return "low" end
    if numeric <= 60 then return "normal" end
    if numeric <= 80 then return "high" end
    return "highest"
end

function Rules.priorityRank(value)
    return Rules.priorityRanks[Rules.normalizePriority(value)]
end

function Rules.normalizeSettings(value, assignedOrder)
    value = type(value) == "table" and value or {}
    return {
        role = Rules.normalizeRole(value.role),
        priorityTier = Rules.normalizePriority(value.priorityTier or value.priority),
        assignedOrder = finite(value.assignedOrder) or finite(assignedOrder) or 0,
        allowCategories = normalizedCategorySet(
            value.allowCategories or value.allowedCategories),
        denyCategories = normalizedCategorySet(
            value.denyCategories or value.deniedCategories),
    }
end

function Rules.categoryAllowed(settings, category)
    settings = Rules.normalizeSettings(settings)
    category = tostring(category or "other")
    if not categorySet[category] then category = "other" end
    if settings.denyCategories[category] then return false, "categoryDenied" end
    if setCount(settings.allowCategories) > 0
        and not settings.allowCategories[category]
    then
        return false, "categoryNotAllowed"
    end
    local role = settings.role
    if role == "general" then return true end
    if role == "fridge" or role == "freezer" then
        return category == "food" or category == "perishable" or category == "drink"
    end
    return role == category
end

local function matchRank(route, category)
    local role = Rules.normalizeRole(route.role)
    if category == "perishable" then
        if route.coldContainer == true and route.powered == true then return 5 end
        if role == "perishable" then return 4 end
        if route.coldContainer == true then return 3 end
        if role == "general" then return 1 end
        return 0
    end
    if role == category then return 4 end
    if (role == "fridge" or role == "freezer")
        and (category == "food" or category == "drink")
    then
        return 3
    end
    if role == "general" then return 1 end
    return 0
end

function Rules.routeCandidates(routes, category, includeFull)
    category = categorySet[tostring(category or "")] and tostring(category) or "other"
    local result = {}
    for index = 1, #(routes or {}) do
        local source = routes[index]
        local allowed = Rules.categoryAllowed(source, category)
        local available = source.available ~= false
        if allowed and (available or (includeFull == true and source.reason == "full")) then
            local row = {}
            for key, value in pairs(source) do row[key] = value end
            row.role = Rules.normalizeRole(source.role)
            row.priorityTier = Rules.normalizePriority(
                source.priorityTier or source.priority)
            row.priorityRank = Rules.priorityRank(row.priorityTier)
            row.matchRank = matchRank(source, category)
            row.assignedOrder = finite(source.assignedOrder) or math.huge
            row.available = available
            result[#result + 1] = row
        end
    end
    table.sort(result, function(left, right)
        if left.matchRank ~= right.matchRank then
            return left.matchRank > right.matchRank
        end
        if left.priorityRank ~= right.priorityRank then
            return left.priorityRank > right.priorityRank
        end
        if left.assignedOrder ~= right.assignedOrder then
            return left.assignedOrder < right.assignedOrder
        end
        return tostring(left.linkId or "") < tostring(right.linkId or "")
    end)
    return result
end

function Rules.normalizeState(value)
    value = type(value) == "table" and copy(value) or {}
    value.version = Rules.stateVersion
    value.schemaVersion = Rules.schemaVersion
    value.networkId = tostring(value.networkId or "")
    value.scopeKey = tostring(value.scopeKey or "")
    value.owner = tostring(value.owner or "")
    value.coreClaimedOnce = value.coreClaimedOnce == true
    value.coreToken = tostring(value.coreToken or "")
    value.coreState = tostring(value.coreState or
        (value.coreToken == "" and "unclaimed" or "missing"))
    value.coreHost = type(value.coreHost) == "table" and copy(value.coreHost) or nil
    value.pendingCoreUnlock = type(value.pendingCoreUnlock) == "table"
        and copy(value.pendingCoreUnlock) or nil
    value.knownObjects = type(value.knownObjects) == "table"
        and copy(value.knownObjects) or {}
    value.revision = math.max(0, integer(value.revision, 0))
    value.routingSequence = math.max(0, finite(value.routingSequence) or 0)
    return value
end

function Rules.objectRef(object)
    if type(object) ~= "table" then return nil end
    local objectId = tostring(object.objectId or "")
    if objectId == "" then return nil end
    return {
        objectId = objectId,
        x = integer(object.x, 0),
        y = integer(object.y, 0),
        z = integer(object.z, 0),
        sprite = tostring(object.sprite or ""),
        name = tostring(object.name or "Container"),
    }
end

function Rules.isAdjacent(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if integer(left.z, -999) ~= integer(right.z, -998) then return false end
    local distance = math.abs(integer(left.x, 0) - integer(right.x, 0))
        + math.abs(integer(left.y, 0) - integer(right.y, 0))
    return distance <= 1
end

function Rules.linkId(objectId, slotIndex)
    return "node:" .. tostring(objectId or "") .. ":" .. tostring(integer(slotIndex, 0))
end

function Rules.emptySnapshot(network, now)
    return {
        kind = "storageSnapshot",
        networkId = network and network.networkId or nil,
        revision = network and integer(network.revision, 0) or 0,
        snapshotId = nil,
        groups = {},
        containers = {},
        itemCount = 0,
        groupCount = 0,
        onlineLinks = 0,
        offlineLinks = 0,
        totalCapacity = 0,
        usedCapacity = 0,
        incomplete = false,
        indexedAtMs = finite(now) or 0,
    }
end

function Rules.mergeSummary(groups, order, instances, description)
    local key = tostring(description.groupKey or description.fullType or "")
    if key == "" then return false end
    local group = groups[key]
    if not group then
        group = {
            key = key,
            fullType = tostring(description.fullType or ""),
            name = tostring(description.name or description.fullType or ""),
            modName = tostring(description.modName or "Base"),
            category = tostring(description.category or "other"),
            count = 0,
            totalWeight = 0,
            bestCondition = 0,
            earliestSpoilage = 1000000000,
            states = {},
            tags = {},
            sources = {},
            sourceNames = {},
        }
        groups[key] = group
        order[#order + 1] = key
        instances[key] = {}
    end
    group.count = group.count + 1
    group.totalWeight = group.totalWeight + math.max(0, finite(description.weight) or 0)
    group.bestCondition = math.max(group.bestCondition,
        finite(description.conditionRatio) or 0)
    group.earliestSpoilage = math.min(group.earliestSpoilage,
        finite(description.spoilageRemaining) or 1000000000)
    for index = 1, #(description.states or {}) do
        group.states[tostring(description.states[index])] = true
    end
    for index = 1, #(description.tags or {}) do
        group.tags[tostring(description.tags[index])] = true
    end
    local sourceLinkId = tostring(description.sourceLinkId or "")
    if sourceLinkId ~= "" then group.sources[sourceLinkId] = true end
    local sourceName = tostring(description.sourceName or "")
    if sourceName ~= "" then group.sourceNames[sourceName] = true end
    instances[key][#instances[key] + 1] = copy(description)
    return true
end

local function setToArray(value)
    local result = {}
    for key in pairs(value or {}) do result[#result + 1] = key end
    table.sort(result)
    return result
end

function Rules.finalizeSnapshot(snapshot, groups, order, instances, now)
    table.sort(order, function(left, right)
        local leftName = string.lower(tostring(groups[left].name or ""))
        local rightName = string.lower(tostring(groups[right].name or ""))
        if leftName ~= rightName then return leftName < rightName end
        return left < right
    end)
    snapshot.groups = {}
    for index = 1, #order do
        local source = groups[order[index]]
        local row = copy(source)
        row.states = setToArray(source.states)
        row.tags = setToArray(source.tags)
        row.sources = setToArray(source.sources)
        row.sourceNames = setToArray(source.sourceNames)
        snapshot.groups[#snapshot.groups + 1] = row
    end
    for _, rows in pairs(instances or {}) do
        table.sort(rows, function(left, right)
            if left.category == "perishable" and right.category == "perishable"
                and left.spoilageRemaining ~= right.spoilageRemaining
            then
                return left.spoilageRemaining < right.spoilageRemaining
            end
            if left.conditionRatio ~= right.conditionRatio then
                return (left.conditionRatio or 0) > (right.conditionRatio or 0)
            end
            if left.usedDelta ~= right.usedDelta then
                return (left.usedDelta or 0) > (right.usedDelta or 0)
            end
            return tostring(left.id or "") < tostring(right.id or "")
        end)
    end
    snapshot.groupCount = #snapshot.groups
    snapshot.indexedAtMs = finite(now) or snapshot.indexedAtMs
    return snapshot
end

return Rules
