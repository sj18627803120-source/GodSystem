require "GodSystem_PersonalStorage"
require "GodSystem_StorageManager"

GodSystemStorageBridge = GodSystemStorageBridge or {}

local Bridge = GodSystemStorageBridge

Bridge.moduleId = "storageBridge"

local function result(ok, code, data, operationId)
    return {
        ok = ok == true,
        code = tostring(code or ""),
        data = data,
        operationId = operationId and tostring(operationId) or nil,
        moduleId = Bridge.moduleId,
    }
end

local function requestFingerprint(kind, args)
    local parts = { tostring(kind or ""), tostring(args and args.snapshotId or "") }
    for i = 1, #(args and args.requests or {}) do
        local request = args.requests[i] or {}
        parts[#parts + 1] = tostring(request.groupKey or "")
        parts[#parts + 1] = tostring(request.count or "")
        for j = 1, math.min(#(request.itemIds or {}), 250) do parts[#parts + 1] = tostring(request.itemIds[j] or "") end
    end
    for i = 1, math.min(#(args and args.entryIds or {}), 250) do parts[#parts + 1] = tostring(args.entryIds[i] or "") end
    return table.concat(parts, "|")
end

local function boundedPhysicalArgs(args)
    args = type(args) == "table" and args or {}
    local copy = {}
    for key, value in pairs(args) do if key ~= "requests" then copy[key] = value end end
    copy.requests = {}
    local remaining = 250
    for i = 1, #(args.requests or {}) do
        if remaining <= 0 then break end
        local source = type(args.requests[i]) == "table" and args.requests[i] or {}
        local request = { groupKey = source.groupKey, itemIds = {} }
        if type(source.itemIds) == "table" and #source.itemIds > 0 then
            for j = 1, math.min(#source.itemIds, remaining) do request.itemIds[#request.itemIds + 1] = source.itemIds[j] end
            remaining = remaining - #request.itemIds
        else
            request.count = math.min(math.max(1, math.floor(tonumber(source.count) or 1)), remaining)
            remaining = remaining - request.count
        end
        copy.requests[#copy.requests + 1] = request
    end
    return copy
end

function Bridge.create(dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    local personal = dependencies.personal
    local manager = dependencies.manager
    local service = { moduleId = Bridge.moduleId, lastError = nil, lastOperationId = nil }

    function service:physicalToPersonal(player, coreArgs, args, store, operationId)
        operationId = tostring(operationId or "")
        args = boundedPhysicalArgs(args)
        local fingerprint = requestFingerprint("physicalToPersonal", args)
        local operation, previous = personal.beginOperation(store, operationId, fingerprint)
        if previous then return previous end
        local ok, reason, stats = manager.consumeNetworkItems(player, coreArgs, args, function(item, source, _, index)
            local preview = personal.createEntry(item)
            if preview.ok and preview.data.simplified and args.confirmSimplified ~= true then
                return false, "confirmSimplified", { simplified = true, reasons = preview.data.report.reasons }
            end
            local itemOperation = operationId .. ":physical:" .. tostring(index) .. ":" .. tostring(GodSystemStorage.itemId(item) or "")
            local itemOutcome = personal.deposit(store, item, source, itemOperation)
            personal.discardOperation(store, itemOperation)
            return itemOutcome.ok, itemOutcome.code, itemOutcome.data
        end)
        stats = stats or { requested = 0, success = 0, skipped = 0, failed = 0, simplified = 0, rows = {} }
        local outcome = result(ok or (stats.failed == 0 and stats.skipped > 0),
            ok and (stats.failed > 0 and "partial" or "completed") or reason or "nothingMoved", stats, operationId)
        return personal.finishOperation(store, operationId, outcome)
    end

    function service:previewPhysical(player, coreArgs, args)
        args = boundedPhysicalArgs(args)
        local ok, reason, payload = manager.inspectNetworkItems(player, coreArgs, args, function(item, expected)
            local created = personal.createEntry(item)
            return {
                itemId = expected.id,
                ok = created.ok,
                reason = created.code,
                fullType = created.data and created.data.snapshot and created.data.snapshot.fullType,
                name = created.data and created.data.snapshot and created.data.snapshot.displayName,
                category = created.data and created.data.category,
                itemCount = created.data and created.data.itemCount,
                simplified = created.data and created.data.simplified == true,
                reasons = created.data and created.data.report and created.data.report.reasons or {},
            }
        end)
        return result(ok, ok and "preview" or reason, payload, args and args.operationId)
    end

    function service:personalToPhysical(player, coreArgs, args, store, operationId)
        operationId = tostring(operationId or "")
        local fingerprint = requestFingerprint("personalToPhysical", args)
        local operation, previous = personal.beginOperation(store, operationId, fingerprint)
        if previous then return previous end
        local stats = { requested = 0, success = 0, skipped = 0, failed = 0, rows = {} }
        for i = 1, math.min(#(args.entryIds or {}), 250) do
            stats.requested = stats.requested + 1
            local entryId = tostring(args.entryIds[i] or "")
            local itemOperation = operationId .. ":personal:" .. tostring(i) .. ":" .. entryId
            local itemOutcome = personal.withdrawWith(store, entryId, itemOperation,
                function(item)
                    return manager.routeExternalItem(player, coreArgs, item)
                end)
            personal.discardOperation(store, itemOperation)
            if itemOutcome.ok then stats.success = stats.success + 1
            elseif itemOutcome.code == "entryMissing" or itemOutcome.code == "noRoute" then stats.skipped = stats.skipped + 1
            else stats.failed = stats.failed + 1 end
            stats.rows[#stats.rows + 1] = {
                entryId = entryId, ok = itemOutcome.ok, reason = itemOutcome.code, data = itemOutcome.data,
            }
        end
        local ok = stats.success > 0 or (stats.failed == 0 and stats.requested > 0)
        local code = stats.failed > 0 and stats.success > 0 and "partial"
            or stats.failed > 0 and "failed" or stats.success > 0 and "completed" or "nothingMoved"
        return personal.finishOperation(store, operationId, result(ok, code, stats, operationId))
    end

    function service:health()
        local ok = type(personal) == "table" and type(personal.deposit) == "function"
            and type(personal.withdrawWith) == "function" and type(manager) == "table"
            and type(manager.consumeNetworkItems) == "function" and type(manager.routeExternalItem) == "function"
        return result(ok, ok and "ok" or "dependencyMissing", nil, self.lastOperationId)
    end

    return service
end

return Bridge
