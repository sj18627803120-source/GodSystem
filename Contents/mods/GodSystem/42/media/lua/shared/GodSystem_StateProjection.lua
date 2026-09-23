GodSystemStateProjection = GodSystemStateProjection or {}

local Projection = GodSystemStateProjection

local ROOT_FIELDS = {
    "version",
    "started",
    "currencyInitialized",
    "points",
    "balance",
    "lastGeneratedDay",
    "recycleLimitDay",
    "recycleLimitUsed",
    "recycleUnlockMode",
    "upgrades",
    "homeSystem",
    "bank",
    "autoTaskClaimEnabled",
    "lastAutoTaskClaimHour",
    "lastKnownKills",
    "attributeSyncPending",
    "ui",
}

local STAT_FIELDS = {
    "recycledItems",
    "recycledPoints",
    "spentPoints",
    "boughtItems",
    "moveDistance",
    "modifiedTraits",
    "completedTasks",
    "failedTasks",
    "bankDeposited",
    "bankWithdrawn",
    "bankInterest",
    "bankPenalty",
    "bankInvestmentProfit",
    "bankInvestmentLoss",
    "bankInvestmentDeposited",
    "bankInvestmentRedeemed",
}

local RETIRED_MARKERS = {
    "sto" .. "rage",
    "lot" .. "tery",
    "son" .. "ic",
}

local function copyValue(value, seen, depth)
    local valueType = type(value)
    if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    if valueType ~= "table" or depth >= 12 or seen[value] then return nil end
    local result = {}
    seen[value] = true
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local copied = copyValue(child, seen, depth + 1)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function copyTable(value)
    return copyValue(type(value) == "table" and value or {}, {}, 0) or {}
end

local function hasRetiredMarker(value)
    value = tostring(value or ""):lower()
    for i = 1, #RETIRED_MARKERS do
        if string.find(value, RETIRED_MARKERS[i], 1, true) then return true end
    end
    return false
end

local function copyHistory(history, limit)
    local result = {}
    limit = math.max(0, math.floor(tonumber(limit) or 40))
    for i = 1, #(type(history) == "table" and history or {}) do
        local entry = history[i]
        if type(entry) == "table" and not hasRetiredMarker(entry.kind) and not hasRetiredMarker(entry.code) then
            local copied = copyTable(entry)
            copied.text = nil
            for argIndex = 1, #(type(copied.args) == "table" and copied.args or {}) do
                local value = copied.args[argIndex]
                if type(value) == "string" and not string.match(value, "^[%w%._:%-%[%] ]*$") then
                    copied.args[argIndex] = ""
                end
            end
            result[#result + 1] = copied
            if #result >= limit then break end
        end
    end
    return result
end

local function copyTasks(tasks)
    local result = {}
    for i = 1, #(type(tasks) == "table" and tasks or {}) do
        local task = tasks[i]
        if type(task) == "table" then
            local copied = copyTable(task)
            copied.title = nil
            copied.description = nil
            result[#result + 1] = copied
        end
    end
    return result
end

local function copyStats(stats)
    local result = {}
    stats = type(stats) == "table" and stats or {}
    for i = 1, #STAT_FIELDS do
        local key = STAT_FIELDS[i]
        if stats[key] ~= nil then result[key] = copyValue(stats[key], {}, 0) end
    end
    return result
end

local function copyUnlocked(items, itemExists)
    local result = {}
    for key, row in pairs(type(items) == "table" and items or {}) do
        if type(row) == "table" then
            local fullType = tostring(row.fullType or key or "")
            if fullType ~= "" and (type(itemExists) ~= "function" or itemExists(fullType) == true) then
                local copied = copyTable(row)
                copied.label = nil
                result[key] = copied
            end
        end
    end
    return result
end

local function copyDiagnostics(diagnostics)
    diagnostics = type(diagnostics) == "table" and diagnostics or {}
    local function code(value, fallback)
        value = tostring(value or "")
        if value == "" or string.match(value, "^[A-Za-z0-9_]+$") then return value end
        return fallback
    end
    return {
        handledCommands = math.max(0, math.floor(tonumber(diagnostics.handledCommands) or 0)),
        failedCommands = math.max(0, math.floor(tonumber(diagnostics.failedCommands) or 0)),
        lastCommand = code(diagnostics.lastCommand, "UnknownCommand"),
        lastError = diagnostics.lastError and "ServerCommandFailed" or "",
        lastResultOk = diagnostics.lastResultOk == true,
        lastResultMessage = code(diagnostics.lastResultMessage, "OperationFailed"),
        lastTraitBenefitsOk = diagnostics.lastTraitBenefitsOk == true,
        lastTraitBenefitsApplied = math.max(0, math.floor(tonumber(diagnostics.lastTraitBenefitsApplied) or 0)),
        lastTraitBenefitsType = code(diagnostics.lastTraitBenefitsType, "Unknown"),
    }
end

-- Revisions are compact server-owned display hints.  They deliberately do not
-- authorize anything; commands still resolve listings, prices and inventory on
-- the server.  Keeping signatures here lets old saves start at revision one.
local function sameValue(a, b, depth)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if depth >= 12 then return true end
    for key, value in pairs(a) do if not sameValue(value, b[key], depth + 1) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

Projection.uiRevisionStates = setmetatable({}, { __mode = "k" })
function Projection.updateUIRevisions(data, options)
    data = type(data) == "table" and data or {}
    options = type(options) == "table" and options or {}
    local state = Projection.uiRevisionStates[data]
    if not state then state = { revisions = {}, signatures = {} }; Projection.uiRevisionStates[data] = state end
    local taskMembership = {}
    for i, task in ipairs(data.tasks or {}) do
        taskMembership[i] = { task.taskId, task.status, task.kind, task.target, task.item, task.items,
            task.deadline, task.rewardPoints, task.rewardItems, task.penaltyPoints }
    end
    local values = {
        shopCatalog = { options.economyRevision or 0, data.shopCatalogRevision or 0,
            data.shopCatalogCount or 0, options.shopConfigVersion or "" },
        shopPreferences = data.ui and { data.ui.shopFavorites, data.ui.shopRecent, data.ui.shopView } or {},
        walletBank = { data.balance, data.bank, data.stats and data.stats.bankDeposited, data.stats and data.stats.bankWithdrawn },
        tasks = taskMembership,
        equipment = { options.equipmentRevision or 0 },
    }
    for key, value in pairs(values) do
        if not sameValue(state.signatures[key], value, 0) then
            state.signatures[key] = copyTable(value)
            state.revisions[key] = math.max(1, math.floor(tonumber(state.revisions[key]) or 0) + 1)
        end
    end
    return state.revisions
end

function Projection.build(data, options)
    data = type(data) == "table" and data or {}
    options = type(options) == "table" and options or {}
    local result = {}
    for i = 1, #ROOT_FIELDS do
        local key = ROOT_FIELDS[i]
        if data[key] ~= nil then result[key] = copyValue(data[key], {}, 0) end
    end
    result.stats = copyStats(data.stats)
    if type(data.shopInflation) == "table" then
        result.shopInflation = { onlineMinute = data.shopInflation.onlineMinute,
            generation = data.shopInflation.generation, enabled = data.shopInflation.enabled,
            priceRevision = data.shopInflation.priceRevision or data.shopInflation.generation }
        if options.includeShopPayload ~= false then
            result.shopInflation.listings = copyValue(data.shopInflation.listings or {}, {}, 0)
        end
    end
    result.tasks = copyTasks(data.tasks)
    result.history = copyHistory(data.history, options.historyLimit)
    result.shopCatalogSchemaVersion = data.shopCatalogSchemaVersion or 1
    result.shopCatalogRevision = data.shopCatalogRevision or 1
    result.shopCatalogCount = data.shopCatalogCount or 0
    if options.includeShopPayload ~= false then
        result.unlockedShopItems = copyUnlocked(data.unlockedShopItems, options.itemExists)
    end
    result.serverDiagnostics = copyDiagnostics(data.serverDiagnostics)
    local revisions = Projection.uiRevisionStates[data]
    if revisions then result.uiRevisions = copyValue(revisions.revisions, {}, 0) end
    return result
end

return Projection
