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
    local bank = type(source.bank) == "table" and source.bank or {}
    local ok, reason = validateNumbers(bank, { "current" })
    if not ok then return nil, reason end
    return { current = math.max(0, math.floor(tonumber(bank.current) or 0)) }
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
    return copyFields(source, { "upgrades" })
end

local function stageBank(context)
    local source = context.player
    local ok, reason = validateTables(source, { "bank" })
    if not ok then return nil, reason end
    local result = clone(source.bank or {})
    result.current = nil
    return result
end

local function stageTerminal(context)
    local source = context.player
    local ok, reason = validateNumbers(source, {
        "autoRecyclerCapacityLevel",
        "autoRecyclerReductionLevel",
        "autoRecyclerReliefLevel",
    })
    if not ok then return nil, reason end
    return {
        revision = 0,
        data = {
            version = 1,
            claimedOnce = source.autoRecyclerClaimed == true,
            capacityLevel = math.max(1,
                math.floor(tonumber(source.autoRecyclerCapacityLevel) or 1)),
            reductionLevel = math.max(1,
                math.floor(tonumber(source.autoRecyclerReductionLevel) or 1)),
            reliefLevel = math.max(0,
                math.floor(tonumber(source.autoRecyclerReliefLevel) or 0)),
        },
    }
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
    return clone(source.companion or {})
end

local function stageAdmin(context)
    local source = context.player
    local ok, reason = validateTables(source, { "adminConfig" })
    if not ok then return nil, reason end
    return clone(source.adminConfig or {})
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
    local ok, reason = validateNumbers(source, { "points" })
    if not ok then return nil, reason end
    ok, reason = validateBooleans(source, { "started", "currencyInitialized" })
    if not ok then return nil, reason end
    local result = copyFields(source, {
        "version", "history", "stats", "ui", "started", "currencyInitialized",
        "lastMoveX", "lastMoveY", "lastMoveZ",
        "attributeSyncPending",
    })
    result.pendingCurrencyGrant = source.currencyInitialized == true
        and 0 or math.max(0, math.floor(tonumber(source.points) or 0))
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

local function commitStaged(root, definition, data, context)
    local moduleId = tostring(definition.targetId or definition.id)
    local row = root.modules[moduleId]
    if type(row) ~= "table" then row = { version = definition.version, data = {} } end
    row.version = definition.version
    row.data = type(row.data) == "table" and row.data or {}
    local bucket = definition.bucket
    if bucket then
        row.data[bucket] = type(row.data[bucket]) == "table" and row.data[bucket] or {}
        row.data[bucket][context.actorKey] = clone(data)
    else
        row.data = clone(data)
    end
    root.modules[moduleId] = row
    return true
end

Migration.Modules = {
    { id = "wallet.accounts", version = 1, bucket = "accounts",
        stage = stageWallet, validate = validateStaged, commit = commitStaged },
    { id = "tasks.state", version = 1, bucket = "players",
        stage = stageTasks, validate = validateStaged, commit = commitStaged },
    { id = "shop.state", version = 1, bucket = "players",
        stage = stageShop, validate = validateStaged, commit = commitStaged },
    { id = "recycle.state", version = 1, bucket = "players",
        stage = stageRecycle, validate = validateStaged, commit = commitStaged },
    { id = "upgrades.state", version = 1, bucket = "players",
        stage = stageUpgrades, validate = validateStaged, commit = commitStaged },
    { id = "terminal.state", version = 1, bucket = "players",
        stage = stageTerminal, validate = validateStaged, commit = commitStaged },
    { id = "bank.state", version = 1, bucket = "players",
        stage = stageBank, validate = validateStaged, commit = commitStaged },
    { id = "home.state", version = 1, bucket = "players",
        stage = stageHome, validate = validateStaged, commit = commitStaged },
    { id = "feature.companion", version = 1, bucket = "actors",
        stage = stageCompanion, validate = validateStaged, commit = commitStaged },
    { id = "admin.state", version = 1,
        stage = stageAdmin, validate = validateStaged, commit = commitStaged },
    { id = "system.state", version = 1, bucket = "players",
        stage = stageSystem, validate = validateStaged, commit = commitStaged },
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

local function migrationContext(snapshot, options)
    local player = snapshot
    if type(snapshot.playerData) == "table" then player = snapshot.playerData end
    options = type(options) == "table" and options or {}
    local actorKey = tostring(options.actorKey or snapshot.actorKey or "local")
    if actorKey == "" then actorKey = "local" end
    return { envelope = snapshot, player = player, actorKey = actorKey }
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

function Migration.commit(definition, root, data, context)
    local ok, committed, reason = pcall(definition.commit, root, definition, data, context)
    if not ok then return false, "commitError:" .. normalizedError(committed) end
    if committed ~= true then return false, tostring(reason or "commitFailed") end
    return true
end

function Migration.run(legacySnapshot, currentRoot, options)
    if type(legacySnapshot) ~= "table" then
        return {
            ok = false,
            code = "invalidLegacySnapshot",
            root = targetRoot(currentRoot),
            modules = {},
            lazy = Migration.lazyStrategies(),
        }
    end

    local context = migrationContext(legacySnapshot, options)
    local root = targetRoot(currentRoot)
    local statuses = {}
    local allSucceeded = true
    local previous = root.migration[Migration.MigrationId]
    local previousActors = type(previous) == "table"
        and type(previous.actors) == "table" and previous.actors or {}
    local previousActor = previousActors[context.actorKey]
    if type(previousActor) ~= "table" and context.actorKey == "local"
            and type(previous) == "table" and type(previous.modules) == "table" then
        previousActor = { modules = previous.modules }
    end
    local previousModules = type(previousActor) == "table"
        and type(previousActor.modules) == "table" and previousActor.modules or {}

    for index = 1, #Migration.Modules do
        local definition = Migration.Modules[index]
        local previousStatus = previousModules[definition.id]
        if type(previousStatus) == "table" and previousStatus.status == "done" then
            statuses[definition.id] = clone(previousStatus)
        else
            local data, reason = Migration.stage(definition, context)
            if data then
                local valid
                valid, reason = Migration.validate(definition, data)
                if valid then
                    valid, reason = Migration.commit(definition, root, data, context)
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
    end

    local migrationRow = type(previous) == "table" and clone(previous) or {}
    migrationRow.sourceVersion = Migration.SourceVersion
    migrationRow.targetVersion = Migration.TargetVersion
    migrationRow.actors = type(migrationRow.actors) == "table" and migrationRow.actors or {}
    migrationRow.actors[context.actorKey] = {
        completed = allSucceeded,
        modules = clone(statuses),
    }
    migrationRow.completed = true
    for _, actorStatus in pairs(migrationRow.actors) do
        if actorStatus.completed ~= true then migrationRow.completed = false break end
    end
    migrationRow.modules = clone(statuses)
    root.migration[Migration.MigrationId] = migrationRow

    return {
        ok = allSucceeded,
        code = allSucceeded and "migrationComplete" or "migrationPartial",
        root = root,
        modules = statuses,
        lazy = Migration.lazyStrategies(),
    }
end

return Migration
