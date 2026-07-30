GodSystemMigration422011 = GodSystemMigration422011 or {}

local Migration = GodSystemMigration422011

Migration.SourceVersion = "42.20.1.1"
Migration.TargetVersion = "42.20.1.2"
Migration.MigrationId = "42.20.1.1_to_42.20.1.2"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[clone(key, seen)] = clone(child, seen)
    end
    return result
end

local function copyFields(source, names)
    local result = {}
    for index = 1, #names do
        local name = names[index]
        if source[name] ~= nil then result[name] = clone(source[name]) end
    end
    return result
end

local function copyWithout(source, excluded)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if not excluded[key] then result[clone(key)] = clone(value) end
    end
    return result
end

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function requireTable(source, field)
    if source[field] ~= nil and type(source[field]) ~= "table" then
        return false, "invalidTable:" .. tostring(field)
    end
    return true
end

local function requireFinite(source, field)
    if source[field] ~= nil and not finite(source[field]) then
        return false, "invalidNumber:" .. tostring(field)
    end
    return true
end

local function requireBoolean(source, field)
    if source[field] ~= nil and type(source[field]) ~= "boolean" then
        return false, "invalidBoolean:" .. tostring(field)
    end
    return true
end

local function validateTables(source, fields)
    for index = 1, #fields do
        local ok, reason = requireTable(source, fields[index])
        if not ok then return false, reason end
    end
    return true
end

local function validateNumbers(source, fields)
    for index = 1, #fields do
        local ok, reason = requireFinite(source, fields[index])
        if not ok then return false, reason end
    end
    return true
end

local function validateBooleans(source, fields)
    for index = 1, #fields do
        local ok, reason = requireBoolean(source, fields[index])
        if not ok then return false, reason end
    end
    return true
end

local function cloneOperations(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        if key == "status" and child == "processing" then
            result[key] = "unknown"
        else
            result[cloneOperations(key, seen)] = cloneOperations(child, seen)
        end
    end
    return result
end

local function operationSource(context, key)
    if context.envelope[key] ~= nil then return context.envelope[key] end
    return context.player[key]
end

local function stageWallet(context)
    local source = context.player
    local ok, reason = validateNumbers(source, { "points" })
    if not ok then return nil, reason end
    ok, reason = validateBooleans(source, { "started", "currencyInitialized" })
    if not ok then return nil, reason end
    return copyFields(source, { "started", "currencyInitialized", "points" })
end

local function stageTasks(context)
    local source = context.player
    local ok, reason = validateTables(source, { "tasks" })
    if not ok then return nil, reason end
    return copyFields(source, {
        "lastGeneratedDay", "tasks", "lastKnownKills",
        "autoTaskClaimEnabled", "lastAutoTaskClaimHour",
    })
end

local function stageShop(context)
    local source = context.player
    local ok, reason = validateTables(source, { "unlockedShopItems" })
    if not ok then return nil, reason end
    return copyFields(source, { "unlockedShopItems" })
end

local function stageRecycle(context)
    return copyFields(context.player, {
        "recycleLimitDay", "recycleLimitUsed", "recycleUnlockMode",
        "autoRecyclerClaimed", "lastAutoRecyclerHour",
        "waistAutoRecycleUnlocked", "waistAutoRecycleEnabled",
        "waistRecycleUnlockMode", "lastWaistAutoRecycleHour",
    })
end

local function stageUpgrades(context)
    local source = context.player
    local ok, reason = validateTables(source, { "upgrades" })
    if not ok then return nil, reason end
    ok, reason = validateNumbers(source, {
        "autoRecyclerCapacityLevel",
        "autoRecyclerReductionLevel",
        "autoRecyclerReliefLevel",
    })
    if not ok then return nil, reason end
    return copyFields(source, {
        "upgrades",
        "autoRecyclerCapacityLevel",
        "autoRecyclerReductionLevel",
        "autoRecyclerReliefLevel",
    })
end

local function stageBank(context)
    local source = context.player
    local ok, reason = validateTables(source, { "bank" })
    if not ok then return nil, reason end
    return copyFields(source, { "bank" })
end

local function stageHome(context)
    local source = context.player
    local ok, reason = validateTables(source, { "homeSystem" })
    if not ok then return nil, reason end
    local result = {}
    if source.homeSystem ~= nil then
        result.homeSystem = copyWithout(source.homeSystem, { pendingTeleport = true })
    end
    return result
end

local function stageCompanion(context)
    local source = context.player
    local ok, reason = validateTables(source, { "companion" })
    if not ok then return nil, reason end
    return copyFields(source, { "companion" })
end

local function stageAdmin(context)
    local source = context.player
    local ok, reason = validateTables(source, { "adminConfig" })
    if not ok then return nil, reason end
    return copyFields(source, { "adminConfig" })
end

local function stageSystem(context)
    local source = context.player
    local ok, reason = validateTables(source, { "history", "stats", "ui" })
    if not ok then return nil, reason end
    local transactionOperations = operationSource(context, "transactionOperations")
    local attributeOperations = operationSource(context, "attributeOperations")
    if transactionOperations ~= nil and type(transactionOperations) ~= "table" then
        return nil, "invalidTable:transactionOperations"
    end
    if attributeOperations ~= nil and type(attributeOperations) ~= "table" then
        return nil, "invalidTable:attributeOperations"
    end
    local result = copyFields(source, {
        "version", "history", "stats", "ui",
        "lastMoveX", "lastMoveY", "lastMoveZ",
        "attributeSyncPending",
    })
    result.operationCaches = {}
    if transactionOperations ~= nil then
        result.operationCaches.transactionOperations = cloneOperations(transactionOperations)
    end
    if attributeOperations ~= nil then
        result.operationCaches.attributeOperations = cloneOperations(attributeOperations)
    end
    return result
end

local function validateStaged(data)
    if type(data) ~= "table" then return false, "stagedDataNotTable" end
    return true
end

local function commitStaged(root, definition, data)
    root.modules[definition.id] = {
        version = definition.version,
        data = clone(data),
    }
    return true
end

Migration.Modules = {
    { id = "wallet", version = 1, stage = stageWallet, validate = validateStaged, commit = commitStaged },
    { id = "tasks", version = 1, stage = stageTasks, validate = validateStaged, commit = commitStaged },
    { id = "shop", version = 1, stage = stageShop, validate = validateStaged, commit = commitStaged },
    { id = "recycle", version = 1, stage = stageRecycle, validate = validateStaged, commit = commitStaged },
    { id = "upgrades", version = 1, stage = stageUpgrades, validate = validateStaged, commit = commitStaged },
    { id = "bank", version = 1, stage = stageBank, validate = validateStaged, commit = commitStaged },
    { id = "home", version = 1, stage = stageHome, validate = validateStaged, commit = commitStaged },
    { id = "companion", version = 1, stage = stageCompanion, validate = validateStaged, commit = commitStaged },
    { id = "admin", version = 1, stage = stageAdmin, validate = validateStaged, commit = commitStaged },
    { id = "system", version = 1, stage = stageSystem, validate = validateStaged, commit = commitStaged },
}

function Migration.lazyStrategies()
    return {
        storageNetwork = {
            mode = "validateInPlaceWhenLoaded",
            copyInstanceData = false,
            globalKey = "GodSystem_CN_Data_StorageNetworkV1",
            itemIdentity = "GodSystemStorageCoreNetworkId",
            objectIdentity = "GodSystemStorageObjectId",
        },
        autoLoader = {
            mode = "validateCarriedInstanceOnAccess",
            copyInstanceData = false,
            itemKey = "GodSystemAutoLoader",
            operationKey = "GodSystemAutoLoaderOperations",
        },
    }
end

local function migrationContext(snapshot)
    local player = snapshot
    if type(snapshot.playerData) == "table" then player = snapshot.playerData end
    return { envelope = snapshot, player = player }
end

local function targetRoot(currentRoot)
    local root = clone(type(currentRoot) == "table" and currentRoot or {})
    root.schemaVersion = math.max(1, math.floor(tonumber(root.schemaVersion) or 1))
    root.releaseVersion = Migration.TargetVersion
    root.modules = type(root.modules) == "table" and root.modules or {}
    root.migration = type(root.migration) == "table" and root.migration or {}
    return root
end

local function normalizedError(value)
    value = tostring(value or "unknown")
    return value:gsub("^.-:%d+:%s*", "")
end

function Migration.stage(definition, context)
    local ok, data, reason = pcall(definition.stage, context)
    if not ok then return nil, "stageError:" .. normalizedError(data) end
    if data == nil then return nil, tostring(reason or "stageFailed") end
    return data
end

function Migration.validate(definition, data)
    local ok, valid, reason = pcall(definition.validate, data)
    if not ok then return false, "validateError:" .. normalizedError(valid) end
    if valid ~= true then return false, tostring(reason or "validationFailed") end
    return true
end

function Migration.commit(definition, root, data)
    local ok, committed, reason = pcall(definition.commit, root, definition, data)
    if not ok then return false, "commitError:" .. normalizedError(committed) end
    if committed ~= true then return false, tostring(reason or "commitFailed") end
    return true
end

function Migration.run(legacySnapshot, currentRoot)
    if type(legacySnapshot) ~= "table" then
        return {
            ok = false,
            code = "invalidLegacySnapshot",
            root = targetRoot(currentRoot),
            modules = {},
            lazy = Migration.lazyStrategies(),
        }
    end

    local context = migrationContext(legacySnapshot)
    local root = targetRoot(currentRoot)
    local statuses = {}
    local allSucceeded = true

    for index = 1, #Migration.Modules do
        local definition = Migration.Modules[index]
        local data, reason = Migration.stage(definition, context)
        if data then
            local valid
            valid, reason = Migration.validate(definition, data)
            if valid then
                valid, reason = Migration.commit(definition, root, data)
            end
            if valid then
                statuses[definition.id] = { status = "done", version = definition.version }
            else
                allSucceeded = false
                statuses[definition.id] = { status = "failed", code = reason }
            end
        else
            allSucceeded = false
            statuses[definition.id] = { status = "failed", code = reason }
        end
    end

    root.migration[Migration.MigrationId] = {
        sourceVersion = Migration.SourceVersion,
        targetVersion = Migration.TargetVersion,
        completed = allSucceeded,
        modules = clone(statuses),
    }

    return {
        ok = allSucceeded,
        code = allSucceeded and "migrationComplete" or "migrationPartial",
        root = root,
        modules = statuses,
        lazy = Migration.lazyStrategies(),
    }
end

return Migration
