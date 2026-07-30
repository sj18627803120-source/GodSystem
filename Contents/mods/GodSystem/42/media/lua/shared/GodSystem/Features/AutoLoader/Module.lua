require "GodSystem/Core/Result"

GodSystemAutoLoaderFeatureModule = GodSystemAutoLoaderFeatureModule or {}

local Descriptor = GodSystemAutoLoaderFeatureModule

Descriptor.id = "feature.autoloader"
Descriptor.dependencies = {
    "autoloader.inventory.query",
    "autoloader.inventory.mutation",
    "ammo.catalog",
    "autoloader.store",
    "autoloader.sessions",
    "autoloader.operations",
    "autoloader.synchronization",
    "notifications",
}
Descriptor.stateVersion = 1

local LIMITS = {
    defaultCapacity = 2000,
    minimumCapacity = 100,
    maximumCapacity = 10000,
    snapshotItems = 20000,
    depositBatch = 500,
    loaders = 64,
    magazines = 256,
    sessionLifetimeMs = 60000,
    withdraw = 500,
}

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function call(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function requiredPort(dependencies, dependencyId, methods)
    local port = dependencies[dependencyId]
    assert(type(port) == "table", "missing dependency: " .. dependencyId)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. dependencyId .. " is missing method " .. methods[index])
    end
    return port
end

local function integer(value, fallback, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    value = math.floor(tonumber(value) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

local function copyTable(source)
    local target = {}
    for key, value in pairs(type(source) == "table" and source or {}) do target[key] = value end
    return target
end

local function requestOperationId(request)
    local value = tostring(type(request) == "table" and request.operationId or "")
    return value ~= "" and value or nil
end

local function itemKey(value)
    value = tostring(value or "")
    return value ~= "" and value or nil
end

local function durationSeconds(count)
    count = integer(count, 0, 0)
    if count <= 0 then return 0 end
    return math.min(15, 1 + math.ceil(count / 100) * 0.5)
end

local function operationFingerprint(action, request)
    request = type(request) == "table" and request or {}
    return table.concat({
        tostring(action or ""),
        "loader:" .. tostring(request.loaderId or ""),
        "type:" .. tostring(request.fullType or ""),
        "count:" .. tostring(integer(request.count, 0, 0)),
    }, "|")
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}

    local moduleId = tostring(context.moduleId or Descriptor.id)
    local query = requiredPort(dependencies, "autoloader.inventory.query", {
        "resolveItem", "resolveLoader", "scanCarried", "scanLoaders", "scanMagazines", "isCarried", "ownerKey",
    })
    local mutation = requiredPort(dependencies, "autoloader.inventory.mutation", {
        "removeAmmo", "restoreAmmo", "createAmmo", "removeCreated", "setMagazineRounds",
        "restoreMagazineRounds",
    })
    local catalog = requiredPort(dependencies, "ammo.catalog", {
        "itemId", "fullType", "displayName", "isLooseAmmo", "isFavorite", "isProtected",
        "isAvailable", "magazineAmmoType", "magazineRounds", "magazineCapacity",
    })
    local store = requiredPort(dependencies, "autoloader.store", {
        "capacity", "getBalance", "setBalance", "entries",
    })
    local sessions = requiredPort(dependencies, "autoloader.sessions", {
        "nowMs", "get", "put", "remove", "cleanup",
    })
    local operations = requiredPort(dependencies, "autoloader.operations", { "begin", "finish" })
    local synchronization = requiredPort(dependencies, "autoloader.synchronization", {
        "loader", "magazine", "created", "removed", "restored",
    })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })

    local instance = {
        started = false,
        completed = 0,
        failed = 0,
        replayed = 0,
        rollbackFailures = 0,
        sessionSequence = 0,
        lastIssue = nil,
        activeStage = nil,
    }

    local function invoke(stage, port, method, ...)
        instance.activeStage = stage
        local ok, first, second, third, fourth = call(port[method], ...)
        if not ok then error(tostring(first)) end
        return first, second, third, fourth
    end

    local function makeResult(ok, code, data, request, countResult)
        local value
        if ok then
            if countResult ~= false then instance.completed = instance.completed + 1 end
            value = GodSystemResult.ok(moduleId, code, data, requestOperationId(request))
        else
            if countResult ~= false then instance.failed = instance.failed + 1 end
            value = GodSystemResult.fail(moduleId, code, data, requestOperationId(request))
        end

        local notified, notifyError = call(notifications.publish, value, request)
        if not notified then
            instance.lastIssue = {
                stage = "notify",
                code = "notificationFailed",
                message = tostring(notifyError),
            }
        end
        return value
    end

    local function guarded(request, stage, callback)
        instance.activeStage = stage
        local ok, value = xpcall(callback, traceback)
        if ok then return value end
        instance.lastIssue = {
            stage = instance.activeStage or stage,
            code = "portError",
            message = tostring(value),
        }
        return makeResult(false, "portError", {
            stage = instance.activeStage or stage,
            message = tostring(value),
        }, request)
    end

    local function recordSyncIssue(stage, message)
        instance.lastIssue = {
            stage = stage,
            code = "synchronizationFailed",
            message = tostring(message or ""),
        }
    end

    local function sync(portMethod, stage, ...)
        local ok, synced, message = call(synchronization[portMethod], ...)
        if not ok or synced == false then
            recordSyncIssue(stage, ok and message or synced)
            return false
        end
        return true
    end

    local function capacity(loader, request)
        return integer(
            invoke("capacity", store, "capacity", loader, request),
            LIMITS.defaultCapacity,
            LIMITS.minimumCapacity,
            LIMITS.maximumCapacity)
    end

    local function balance(loader, fullType, request)
        return integer(invoke("balance", store, "getBalance", loader, fullType, request), 0, 0)
    end

    local function setBalance(loader, fullType, count, displayName, request)
        local applied, code = invoke(
            "setBalance", store, "setBalance", loader, fullType,
            integer(count, 0, 0), displayName, request)
        return applied ~= false, code
    end

    local function resolveLoader(request)
        local actor = request.actor
        if actor == nil then return nil, "actorRequired" end
        local loader, code = invoke(
            "resolveLoader", query, "resolveLoader", actor, request.loaderId, request)
        if loader == nil then return nil, code or "NotCarried" end
        if invoke("loaderCarried", query, "isCarried", actor, loader, request) ~= true then
            return nil, "NotCarried"
        end
        return loader
    end

    local function replayResult(record, status, request)
        if status == "done" and type(record.result) == "table" then
            instance.replayed = instance.replayed + 1
            local notified, notifyError = call(notifications.publish, record.result, request)
            if not notified then recordSyncIssue("notifyReplay", notifyError) end
            return record.result
        end
        local codes = {
            processing = "OperationPending",
            unknown = "OperationUnknown",
            mismatch = "OperationMismatch",
            invalid = "OperationInvalid",
        }
        return makeResult(false, codes[status] or "OperationInvalid", nil, request, false)
    end

    local function beginOperation(action, request)
        local operationId = requestOperationId(request)
        if not operationId then return nil, makeResult(false, "OperationInvalid", nil, request) end
        local record, status = invoke(
            "operationBegin", operations, "begin", moduleId, action, operationId,
            operationFingerprint(action, request), request)
        if record == nil then
            return nil, makeResult(false,
                status == "mismatch" and "OperationMismatch" or "OperationInvalid", nil, request)
        end
        if status ~= nil and status ~= "new" then return nil, replayResult(record, status, request) end
        return record
    end

    local function finishOperation(record, value, request)
        local stored, code = invoke("operationFinish", operations, "finish", record, value, request)
        if stored == false then
            instance.lastIssue = {
                stage = "operationFinish",
                code = "operationCommitFailed",
                message = tostring(code or ""),
            }
            return makeResult(false, "operationCommitFailed", {
                outcome = value,
                reason = code,
            }, request, false)
        end
        return value
    end

    local function isProtected(item, purpose, request)
        return invoke("itemProtection", catalog, "isProtected", item, purpose, request) == true
    end

    local function stateFor(loader, request)
        local rows = invoke("storeEntries", store, "entries", loader, request)
        rows = type(rows) == "table" and rows or {}
        local data = {
            loaderId = itemKey(invoke("loaderId", catalog, "itemId", loader)),
            capacity = capacity(loader, request),
            total = 0,
            ammo = {},
        }
        for index = 1, #rows do
            local row = rows[index] or {}
            local fullType = itemKey(row.fullType)
            local count = integer(row.count, 0, 0)
            if fullType and count > 0 then
                local name = invoke(
                    "ammoDisplayName", catalog, "displayName", fullType, row.name, request)
                data.ammo[#data.ammo + 1] = {
                    fullType = fullType,
                    count = count,
                    capacity = data.capacity,
                    available = invoke(
                        "ammoAvailable", catalog, "isAvailable", fullType, request) == true,
                    name = tostring(name or row.name or fullType),
                }
                data.total = data.total + count
            end
        end
        table.sort(data.ammo, function(left, right)
            local leftName = tostring(left.name or left.fullType):lower()
            local rightName = tostring(right.name or right.fullType):lower()
            if leftName ~= rightName then return leftName < rightName end
            return tostring(left.fullType) < tostring(right.fullType)
        end)
        return data
    end

    local function getState(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "state", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local loader, code = resolveLoader(request)
            if not loader then return makeResult(false, code, nil, request) end
            return makeResult(true, "State", stateFor(loader, request), request)
        end)
    end

    local function scanDeposit(actor, loader, request)
        local candidates, scan = invoke(
            "scanDeposit", query, "scanCarried", actor,
            LIMITS.snapshotItems + LIMITS.loaders + LIMITS.magazines + 4096, request)
        candidates = type(candidates) == "table" and candidates or {}
        scan = type(scan) == "table" and scan or {}
        local records = {}
        local stats = {
            eligible = 0,
            favoriteSkipped = 0,
            protectedSkipped = 0,
            capacitySkipped = 0,
            limitSkipped = integer(scan.limitSkipped, 0, 0),
        }
        local reserved = {}
        local loaderId = itemKey(invoke("loaderId", catalog, "itemId", loader))
        local maximum = capacity(loader, request)

        for index = 1, #candidates do
            local item = candidates[index]
            local candidateId = itemKey(invoke("candidateId", catalog, "itemId", item))
            if candidateId ~= loaderId
                    and invoke("isLooseAmmo", catalog, "isLooseAmmo", item, request) == true then
                stats.eligible = stats.eligible + 1
                if invoke("isFavorite", catalog, "isFavorite", item, request) == true then
                    stats.favoriteSkipped = stats.favoriteSkipped + 1
                elseif isProtected(item, "deposit", request) then
                    stats.protectedSkipped = stats.protectedSkipped + 1
                else
                    local fullType = itemKey(invoke("ammoFullType", catalog, "fullType", item, request))
                    local used = fullType and (balance(loader, fullType, request) + (reserved[fullType] or 0)) or maximum
                    if not candidateId or not fullType then
                        stats.limitSkipped = stats.limitSkipped + 1
                    elseif used >= maximum then
                        stats.capacitySkipped = stats.capacitySkipped + 1
                    elseif #records >= LIMITS.snapshotItems then
                        stats.limitSkipped = stats.limitSkipped + 1
                    else
                        reserved[fullType] = (reserved[fullType] or 0) + 1
                        records[#records + 1] = {
                            itemId = candidateId,
                            fullType = fullType,
                            displayName = tostring(invoke(
                                "itemDisplayName", catalog, "displayName", item, fullType, request) or fullType),
                        }
                    end
                end
            end
        end
        stats.selected = #records
        return records, stats
    end

    local function startDeposit(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "startDeposit", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local operation, replay = beginOperation("startDeposit", request)
            if not operation then return replay end
            local loader, code = resolveLoader(request)
            if not loader then
                return finishOperation(operation, makeResult(false, code, nil, request), request)
            end
            local records, scan = scanDeposit(request.actor, loader, request)
            if #records <= 0 then
                return finishOperation(operation,
                    makeResult(false, "nothingToDeposit", scan, request), request)
            end

            local owner = tostring(invoke("ownerKey", query, "ownerKey", request.actor, request) or "")
            local now = integer(invoke("sessionClock", sessions, "nowMs"), 0, 0)
            instance.sessionSequence = instance.sessionSequence + 1
            local sessionId = table.concat({
                "gsa", owner, tostring(request.loaderId or ""),
                tostring(now), tostring(instance.sessionSequence),
            }, "-")
            local session = {
                sessionId = sessionId,
                owner = owner,
                loaderId = tostring(request.loaderId or ""),
                operationId = requestOperationId(request),
                records = records,
                scan = scan,
                batchCount = math.ceil(#records / LIMITS.depositBatch),
                completed = {},
                createdAt = now,
                expiresAt = now + LIMITS.sessionLifetimeMs,
            }
            local stored, storeCode = invoke("sessionPut", sessions, "put", session, request)
            if stored == false then
                return finishOperation(operation,
                    makeResult(false, storeCode or "sessionStoreFailed", nil, request), request)
            end
            local payload = {
                sessionId = sessionId,
                loaderId = session.loaderId,
                total = #records,
                batchCount = session.batchCount,
                durationSeconds = durationSeconds(#records),
                skipped = (scan.favoriteSkipped or 0) + (scan.protectedSkipped or 0)
                    + (scan.capacitySkipped or 0) + (scan.limitSkipped or 0),
            }
            return finishOperation(operation,
                makeResult(true, "DepositStarted", payload, request), request)
        end)
    end

    local function restoreRemoved(actor, receipt, request)
        local restored = invoke("restoreAmmo", mutation, "restoreAmmo", actor, receipt, request)
        if restored == false then
            instance.rollbackFailures = instance.rollbackFailures + 1
            return false
        end
        sync("restored", "syncRestored", actor, receipt, request)
        return true
    end

    local function settleDepositRecord(actor, loader, record, request)
        local item, code = invoke(
            "resolveDepositItem", query, "resolveItem", actor, record.itemId, record, request)
        if item == nil then return "skipped", code or "itemMissing" end
        local fullType = itemKey(invoke("depositFullType", catalog, "fullType", item, request))
        if fullType ~= tostring(record.fullType or "")
                or invoke("depositLooseAmmo", catalog, "isLooseAmmo", item, request) ~= true
                or invoke("depositFavorite", catalog, "isFavorite", item, request) == true
                or isProtected(item, "deposit", request)
                or invoke("depositCarried", query, "isCarried", actor, item, request) ~= true
                or balance(loader, fullType, request) >= capacity(loader, request) then
            return "skipped", "eligibilityChanged"
        end

        local removed, receiptOrCode = invoke(
            "removeAmmo", mutation, "removeAmmo", actor, item, record, request)
        if removed ~= true or receiptOrCode == nil then return "failed", receiptOrCode or "removeFailed" end

        local previous = balance(loader, fullType, request)
        local stored, storeCode = setBalance(
            loader, fullType, previous + 1, record.displayName, request)
        if not stored then
            local restored = restoreRemoved(actor, receiptOrCode, request)
            if not restored then return "rollbackIncomplete", storeCode or "storeFailed" end
            return "failed", storeCode or "storeFailed"
        end
        sync("removed", "syncRemoved", actor, receiptOrCode, request)
        return "stored"
    end

    local function aggregateSession(session)
        local aggregate = {
            requested = #session.records,
            stored = 0,
            skipped = 0,
            failed = 0,
            rollbackIncomplete = 0,
            completedBatches = 0,
            batchCount = session.batchCount,
            sessionId = session.sessionId,
            loaderId = session.loaderId,
        }
        for index = 1, session.batchCount do
            local row = session.completed[index]
            if row then
                aggregate.completedBatches = aggregate.completedBatches + 1
                aggregate.stored = aggregate.stored + (row.stored or 0)
                aggregate.skipped = aggregate.skipped + (row.skipped or 0)
                aggregate.failed = aggregate.failed + (row.failed or 0)
                aggregate.rollbackIncomplete = aggregate.rollbackIncomplete + (row.rollbackIncomplete or 0)
            end
        end
        aggregate.skipped = aggregate.skipped + (session.scan.favoriteSkipped or 0)
            + (session.scan.protectedSkipped or 0) + (session.scan.capacitySkipped or 0)
            + (session.scan.limitSkipped or 0)
        aggregate.finished = aggregate.completedBatches >= session.batchCount
        return aggregate
    end

    local function completeDepositBatch(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "completeDepositBatch", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local sessionId = tostring(request.sessionId or "")
            local session = invoke("sessionGet", sessions, "get", sessionId, request)
            local owner = tostring(invoke("ownerKey", query, "ownerKey", request.actor, request) or "")
            if type(session) ~= "table" or session.owner ~= owner then
                return makeResult(false, "sessionMissing", { sessionId = sessionId }, request)
            end
            local now = integer(invoke("sessionClock", sessions, "nowMs"), 0, 0)
            if now > integer(session.expiresAt, 0, 0) then
                invoke("sessionRemove", sessions, "remove", sessionId, request)
                return makeResult(false, "sessionExpired", { sessionId = sessionId }, request)
            end
            local batchIndex = integer(request.batchIndex, 0)
            if batchIndex < 1 or batchIndex > integer(session.batchCount, 0, 0) then
                return makeResult(false, "batchInvalid", { sessionId = sessionId }, request)
            end
            if type(session.completed[batchIndex]) == "table" then
                instance.replayed = instance.replayed + 1
                return makeResult(true, "DepositBatchReplayed", {
                    batch = session.completed[batchIndex],
                    aggregate = aggregateSession(session),
                }, request, false)
            end
            local loader, code = resolveLoader({
                actor = request.actor,
                loaderId = session.loaderId,
                operationId = request.operationId,
            })
            if not loader then return makeResult(false, code, { sessionId = sessionId }, request) end

            local first = ((batchIndex - 1) * LIMITS.depositBatch) + 1
            local last = math.min(#session.records, first + LIMITS.depositBatch - 1)
            local stats = {
                requested = last - first + 1,
                stored = 0,
                skipped = 0,
                failed = 0,
                rollbackIncomplete = 0,
                byType = {},
            }
            for index = first, last do
                local record = session.records[index]
                local outcome = settleDepositRecord(request.actor, loader, record, request)
                if outcome == "stored" then
                    stats.stored = stats.stored + 1
                    stats.byType[record.fullType] = (stats.byType[record.fullType] or 0) + 1
                elseif outcome == "skipped" then
                    stats.skipped = stats.skipped + 1
                elseif outcome == "rollbackIncomplete" then
                    stats.failed = stats.failed + 1
                    stats.rollbackIncomplete = stats.rollbackIncomplete + 1
                else
                    stats.failed = stats.failed + 1
                end
            end
            session.completed[batchIndex] = stats
            local aggregate = aggregateSession(session)
            if aggregate.finished then
                invoke("sessionRemove", sessions, "remove", sessionId, request)
            else
                invoke("sessionPut", sessions, "put", session, request)
            end
            if stats.stored > 0 then sync("loader", "syncLoader", request.actor, loader, request) end
            if stats.rollbackIncomplete > 0 then
                instance.lastIssue = {
                    stage = "depositRollback",
                    code = "rollbackIncomplete",
                    message = tostring(stats.rollbackIncomplete),
                }
                return makeResult(false, "rollbackIncomplete", {
                    batch = stats,
                    aggregate = aggregate,
                }, request)
            end
            return makeResult(aggregate.finished and aggregate.stored > 0 or stats.stored > 0,
                aggregate.finished and "DepositComplete" or "DepositBatchComplete", {
                    batch = stats,
                    aggregate = aggregate,
                }, request)
        end)
    end

    local function withdraw(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "withdraw", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local operation, replay = beginOperation("withdraw", request)
            if not operation then return replay end
            local loader, code = resolveLoader(request)
            if not loader then
                return finishOperation(operation, makeResult(false, code, nil, request), request)
            end
            local fullType = itemKey(request.fullType)
            if not fullType or invoke(
                    "ammoAvailable", catalog, "isAvailable", fullType, request) ~= true then
                return finishOperation(operation,
                    makeResult(false, "Unavailable", { created = 0 }, request), request)
            end
            local requested = integer(request.count, 100, 1, LIMITS.withdraw)
            local previous = balance(loader, fullType, request)
            local target = math.min(previous, requested)
            local receipts = {}
            for index = 1, target do
                local created, receipt = invoke(
                    "createAmmo", mutation, "createAmmo", request.actor, fullType, request)
                if created ~= true or receipt == nil then break end
                receipts[#receipts + 1] = receipt
            end
            if #receipts <= 0 then
                return finishOperation(operation, makeResult(false, "createFailed", {
                    requested = requested,
                    created = 0,
                }, request), request)
            end
            local stored, storeCode = setBalance(
                loader, fullType, previous - #receipts, nil, request)
            if not stored then
                local restored = true
                for index = #receipts, 1, -1 do
                    local removed = invoke(
                        "removeCreated", mutation, "removeCreated",
                        request.actor, receipts[index], request)
                    if removed ~= false then
                        sync("removed", "syncRemoved", request.actor, receipts[index], request)
                    end
                    restored = removed ~= false and restored
                end
                if not restored then
                    instance.rollbackFailures = instance.rollbackFailures + 1
                    instance.lastIssue = {
                        stage = "withdrawRollback",
                        code = "rollbackIncomplete",
                        message = tostring(storeCode or ""),
                    }
                    return finishOperation(operation,
                        makeResult(false, "rollbackIncomplete", {
                            causeCode = storeCode or "storeFailed",
                            created = #receipts,
                        }, request), request)
                end
                return finishOperation(operation,
                    makeResult(false, storeCode or "storeFailed", nil, request), request)
            end
            sync("loader", "syncLoader", request.actor, loader, request)
            for index = 1, #receipts do
                sync("created", "syncCreated", request.actor, receipts[index], request)
            end
            return finishOperation(operation, makeResult(true, "WithdrawSuccess", {
                loaderId = tostring(request.loaderId or ""),
                requested = requested,
                created = #receipts,
            }, request), request)
        end)
    end

    local function sortLoaders(loaders)
        table.sort(loaders, function(left, right)
            local leftId = tostring(invoke("loaderSortId", catalog, "itemId", left) or "")
            local rightId = tostring(invoke("loaderSortId", catalog, "itemId", right) or "")
            local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
            if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
            return leftId < rightId
        end)
        return loaders
    end

    local function sortMagazines(magazines, request)
        table.sort(magazines, function(left, right)
            local leftCount = integer(
                invoke("magazineSortRounds", catalog, "magazineRounds", left, request), 0, 0)
            local rightCount = integer(
                invoke("magazineSortRounds", catalog, "magazineRounds", right, request), 0, 0)
            if leftCount ~= rightCount then return leftCount > rightCount end
            local leftId = tostring(invoke("magazineSortId", catalog, "itemId", left) or "")
            local rightId = tostring(invoke("magazineSortId", catalog, "itemId", right) or "")
            local leftNumber, rightNumber = tonumber(leftId), tonumber(rightId)
            if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
            return leftId < rightId
        end)
        return magazines
    end

    local function fillMagazines(actor, loaders, request)
        local usable = {}
        for index = 1, math.min(#loaders, LIMITS.loaders) do
            local loader = loaders[index]
            if invoke("fillLoaderCarried", query, "isCarried", actor, loader, request) == true then
                usable[#usable + 1] = loader
            end
        end
        sortLoaders(usable)
        local magazines, magazineLimited = invoke(
            "scanMagazines", query, "scanMagazines", actor, LIMITS.magazines, request)
        magazines = sortMagazines(type(magazines) == "table" and magazines or {}, request)
        local stats = {
            rounds = 0,
            magazines = 0,
            need = 0,
            remainingNeed = 0,
            loaderLimited = #loaders > LIMITS.loaders,
            magazineLimited = magazineLimited == true,
            rollbackIncomplete = 0,
        }
        local changedLoaders = {}

        for magazineIndex = 1, #magazines do
            local magazine = magazines[magazineIndex]
            local ammoType = itemKey(invoke(
                "magazineAmmoType", catalog, "magazineAmmoType", magazine, request))
            local current = integer(invoke(
                "magazineRounds", catalog, "magazineRounds", magazine, request), 0, 0)
            local maximum = integer(invoke(
                "magazineCapacity", catalog, "magazineCapacity", magazine, request), 0, 0)
            local need = math.max(0, maximum - current)
            stats.need = stats.need + need
            if ammoType and need > 0 then
                local suppliers = {}
                for loaderIndex = 1, #usable do
                    local loader = usable[loaderIndex]
                    local available = balance(loader, ammoType, request)
                    if available > 0 then
                        suppliers[#suppliers + 1] = {
                            loader = loader,
                            balance = available,
                            itemId = tostring(invoke(
                                "supplierId", catalog, "itemId", loader) or ""),
                        }
                    end
                end
                table.sort(suppliers, function(left, right)
                    if left.balance ~= right.balance then return left.balance < right.balance end
                    local leftNumber, rightNumber = tonumber(left.itemId), tonumber(right.itemId)
                    if leftNumber and rightNumber and leftNumber ~= rightNumber then
                        return leftNumber < rightNumber
                    end
                    return left.itemId < right.itemId
                end)

                local added, taken = 0, {}
                for supplierIndex = 1, #suppliers do
                    if added >= need then break end
                    local supplier = suppliers[supplierIndex]
                    local amount = math.min(supplier.balance, need - added)
                    if amount > 0 then
                        local applied = setBalance(
                            supplier.loader, ammoType, supplier.balance - amount, nil, request)
                        if applied then
                            taken[#taken + 1] = {
                                loader = supplier.loader,
                                count = amount,
                            }
                            supplier.balance = supplier.balance - amount
                            added = added + amount
                        end
                    end
                end

                if added > 0 then
                    local changed = invoke(
                        "setMagazineRounds", mutation, "setMagazineRounds",
                        actor, magazine, current + added, request)
                    local verified = changed == true and integer(invoke(
                        "verifyMagazineRounds", catalog, "magazineRounds",
                        magazine, request), -1) == current + added
                    if verified then
                        for index = 1, #taken do changedLoaders[taken[index].loader] = true end
                        sync("magazine", "syncMagazine", actor, magazine, request)
                        stats.rounds = stats.rounds + added
                        stats.magazines = stats.magazines + 1
                    else
                        local rollbackComplete = invoke(
                            "restoreMagazineRounds", mutation, "restoreMagazineRounds",
                            actor, magazine, current, request) ~= false
                        for index = 1, #taken do
                            local row = taken[index]
                            local restored = setBalance(
                                row.loader, ammoType,
                                balance(row.loader, ammoType, request) + row.count, nil, request)
                            rollbackComplete = restored and rollbackComplete
                        end
                        if not rollbackComplete then
                            stats.rollbackIncomplete = stats.rollbackIncomplete + 1
                            instance.rollbackFailures = instance.rollbackFailures + 1
                        end
                        added = 0
                    end
                end
                stats.remainingNeed = stats.remainingNeed + math.max(0, need - added)
            elseif need > 0 then
                stats.remainingNeed = stats.remainingNeed + need
            end
        end

        for loader in pairs(changedLoaders) do
            sync("loader", "syncLoader", actor, loader, request)
        end
        return stats
    end

    local function fillResult(action, request, loaders, loaderLimited, postReload)
        local stats = fillMagazines(request.actor, loaders, request)
        stats.loaderLimited = stats.loaderLimited or loaderLimited == true
        if stats.rollbackIncomplete > 0 then
            instance.lastIssue = {
                stage = "fillRollback",
                code = "rollbackIncomplete",
                message = tostring(stats.rollbackIncomplete),
            }
            return makeResult(false, "rollbackIncomplete", stats, request)
        end
        if postReload then
            local limited = stats.loaderLimited or stats.magazineLimited
            local code, silent = "FillSuccess", stats.rounds > 0 and stats.remainingNeed <= 0 and not limited
            if limited then code, silent = "LimitReached", false
            elseif stats.need <= 0 then code, silent = "NoCompatibleMagazine", true
            elseif stats.remainingNeed > 0 then code, silent = "FillInsufficient", false end
            stats.silent = silent
            return makeResult(true, code, stats, request)
        end
        local code = "NoCompatibleMagazine"
        if stats.rounds > 0 and stats.remainingNeed <= 0 then code = "FillSuccess"
        elseif stats.rounds > 0 or stats.remainingNeed > 0 then code = "FillInsufficient" end
        return makeResult(stats.rounds > 0, code, stats, request)
    end

    local function manualFill(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "manualFill", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local operation, replay = beginOperation("manualFill", request)
            if not operation then return replay end
            local loader, code = resolveLoader(request)
            if not loader then
                return finishOperation(operation, makeResult(false, code, nil, request), request)
            end
            local value = fillResult("manualFill", request, { loader }, false, false)
            if type(value.data) == "table" then value.data.loaderId = tostring(request.loaderId or "") end
            return finishOperation(operation, value, request)
        end)
    end

    local function postReload(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "postReload", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local operation, replay = beginOperation("postReload", request)
            if not operation then return replay end
            local loaders, limited = invoke(
                "scanLoaders", query, "scanLoaders", request.actor, LIMITS.loaders, request)
            loaders = type(loaders) == "table" and loaders or {}
            if #loaders <= 0 then
                return finishOperation(operation, makeResult(true, "NoLoader", {
                    rounds = 0,
                    silent = true,
                }, request), request)
            end
            return finishOperation(
                operation, fillResult("postReload", request, loaders, limited, true), request)
        end)
    end

    local function cancelDeposit(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "cancelDeposit", function()
            if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
            local sessionId = tostring(request.sessionId or "")
            local session = invoke("sessionGet", sessions, "get", sessionId, request)
            local owner = tostring(invoke("ownerKey", query, "ownerKey", request.actor, request) or "")
            if type(session) ~= "table" or session.owner ~= owner then
                return makeResult(false, "sessionMissing", { sessionId = sessionId }, request)
            end
            invoke("sessionRemove", sessions, "remove", sessionId, request)
            return makeResult(true, "DepositInterrupted", {
                sessionId = sessionId,
                loaderId = session.loaderId,
            }, request)
        end)
    end

    local function cleanup(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "cleanupSessions", function()
            local now = integer(invoke("sessionClock", sessions, "nowMs"), 0, 0)
            local removed = integer(invoke(
                "sessionCleanup", sessions, "cleanup", now, request), 0, 0)
            return makeResult(true, "SessionsCleaned", { removed = removed }, request)
        end)
    end

    instance.public = {
        limits = copyTable(LIMITS),
        durationSeconds = durationSeconds,
        state = getState,
        startDeposit = startDeposit,
        completeDepositBatch = completeDepositBatch,
        cancelDeposit = cancelDeposit,
        withdraw = withdraw,
        manualFill = manualFill,
        postReload = postReload,
        cleanupSessions = cleanup,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            replayed = self.replayed,
            rollbackFailures = self.rollbackFailures,
            lastIssue = self.lastIssue,
        }
        if self.lastIssue then
            return GodSystemResult.fail(moduleId, self.lastIssue.code, data)
        end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
