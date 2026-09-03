_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_RouterConfig"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_RouterConfig then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_RouterConfig = true
    setfenv(1, runtimeEnvironment)

function sendRuntimeConfig(player)
    applyRuntimeStores()
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.RuntimeConfig) or "runtimeConfig", {
        snapshot = GodSystemRuntimeConfig.snapshot(),
    })
end

function sendEconomySnapshot(player)
    applyRuntimeStores()
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.EconomySnapshot) or "economySnapshot", {
        snapshot = GodSystemItemConfig.publicSnapshot(),
    })
end

function sendInitialConfig(player)
    sendRuntimeConfig(player)
    sendEconomySnapshot(player)
end

function broadcastEconomyDelta(delta)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players or not players.size or not players.get then return end
    for i = 0, players:size() - 1 do
        local target = players:get(i)
        if target then
            sendServerCommand(target, MODULE, (Protocol.S2C and Protocol.S2C.EconomyDelta) or "economyDelta", delta or {})
        end
    end
end

function sendState(player)
    local data = playerData(player)
    generateDailyTasks(data, false)
    updateBankLoanForData(player, data)
    data.balance = getBalance(player)
    data.serverDiagnostics = {
        handledCommands = diagnostics.handledCommands or 0,
        failedCommands = diagnostics.failedCommands or 0,
        lastCommand = diagnostics.lastCommand,
        lastError = diagnostics.lastError,
        lastResultOk = diagnostics.lastResultOk,
        lastResultMessage = diagnostics.lastResultMessage,
        lastTraitBenefitsOk = diagnostics.lastTraitBenefitsOk,
        lastTraitBenefitsApplied = diagnostics.lastTraitBenefitsApplied,
        lastTraitBenefitsType = diagnostics.lastTraitBenefitsType,
    }
    local state = GodSystemStateProjection.build(data, {
        historyLimit = GodSystemConfig.HistoryLimit or 40,
        itemExists = itemExists,
    })
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.State) or "state", {
        data = state,
        balance = data.balance,
        version = GodSystemConfig.Version,
        admin = isAdminPlayer(player),
        configRevision = math.max(1, floor((GodSystemItemConfig.Current or {}).economyRevision, 1)),
    })
end

function broadcastState()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players or not players.size or not players.get then return end
    for i = 0, players:size() - 1 do
        local target = players:get(i)
        if target then sendState(target) end
    end
end

function legacyResultCode(ok, message)
    local value = tostring(message or "")
    if value == "CurrencyNotEnough" then return "CurrencyNotEnough" end
    if value == "Bank disabled" then return "BankDisabled" end
    if value == "" then return ok == true and "OperationSucceeded" or "OperationFailed" end
    return ok == true and "OperationSucceeded" or "OperationFailed"
end

function finish(player, ok, message, payload)
    local code = legacyResultCode(ok, message)
    local args = {}
    return finishCode(player, ok, code, args, payload)
end

function finishCode(player, ok, code, args, payload)
    diagnostics.lastResultOk = ok == true
    diagnostics.lastResultMessage = tostring(code or "")
    storeCheckpoint()
    local data = type(payload) == "table" and payload or {}
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.Result) or "result", {
        ok = ok == true,
        code = tostring(code or ""),
        args = args or {},
        data = data,
        operationId = data.operationId or data.opId,
        message = "",
        payload = payload,
    })
    sendState(player)
end

function guard(player)
    local key = userKey(player)
    if pending[key] then
        errorCode(player, "CommandPending")
        return false
    end
    pending[key] = true
    return true
end

function unguard(player)
    pending[userKey(player)] = nil
end

GodSystemServer.attributeOps = GodSystemServer.attributeOps or {}
GodSystemServer.attributeOpsNormalized = GodSystemServer.attributeOpsNormalized or {}

function GodSystemServer.attributeOpId(args)
    local opId = args and tostring(args.opId or "") or ""
    if #opId > 96 or not string.match(opId, "^gs%-%d+%-%d+%-%d+$") then return nil end
    return opId
end

function GodSystemServer.attributeOpFingerprint(args)
    if type(args) ~= "table" then return "" end
    return table.concat({
        tostring(args.perkIndex or ""),
        tostring(args.mode or ""),
        tostring(args.value or ""),
    }, "|")
end

function GodSystemServer.attributeOpBucket(player, create)
    local root = store()
    root.attributeOperations = root.attributeOperations or {}
    local key = userKey(player)
    local bucket = root.attributeOperations[key]
    if not bucket and create == true then
        bucket = { results = {}, order = {} }
        root.attributeOperations[key] = bucket
    end
    if bucket then
        bucket.results = type(bucket.results) == "table" and bucket.results or {}
        bucket.order = type(bucket.order) == "table" and bucket.order or {}
        if GodSystemServer.attributeOpsNormalized[key] ~= bucket then
            for _, result in pairs(bucket.results) do
                if type(result) == "table" and result.status == "processing" then
                    result.status = "unknown"
                    result.ok = false
                    result.code = "AttributeOperationUnknown"
                    result.args = {}
                end
            end
            GodSystemServer.attributeOpsNormalized[key] = bucket
        end
    end
    return bucket
end

function GodSystemServer.getAttributeOpResult(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return nil end
    local bucket = GodSystemServer.attributeOpBucket(player, false)
    local result = bucket and bucket.results[opId] or nil
    if result and result.fingerprint and result.fingerprint ~= GodSystemServer.attributeOpFingerprint(args) then
        return { status = "mismatch" }
    end
    return result
end

function GodSystemServer.trimAttributeOps(bucket)
    while bucket and #bucket.order > 64 do
        local removeAt = 1
        for i = 1, #bucket.order do
            local candidate = bucket.results[bucket.order[i]]
            if candidate and candidate.status == "done" then
                removeAt = i
                break
            end
        end
        local expired = table.remove(bucket.order, removeAt)
        bucket.results[expired] = nil
    end
end

function GodSystemServer.beginAttributeOp(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return false end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    if bucket.results[opId] ~= nil then return false end
    bucket.order[#bucket.order + 1] = opId
    bucket.results[opId] = { status = "processing", fingerprint = GodSystemServer.attributeOpFingerprint(args) }
    GodSystemServer.trimAttributeOps(bucket)
    return true
end

function GodSystemServer.rememberAttributeOpResult(player, args, ok, code, codeArgs, payload)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    if bucket.results[opId] == nil then
        bucket.order[#bucket.order + 1] = opId
    end
    local current = bucket.results[opId]
    bucket.results[opId] = {
        status = "done",
        fingerprint = current and current.fingerprint or GodSystemServer.attributeOpFingerprint(args),
        ok = ok == true,
        code = tostring(code or ""),
        args = codeArgs or {},
        payload = payload,
    }
    GodSystemServer.trimAttributeOps(bucket)
end

function GodSystemServer.markAttributeOpUnknown(player, args)
    local opId = GodSystemServer.attributeOpId(args)
    if not opId then return end
    local bucket = GodSystemServer.attributeOpBucket(player, true)
    local current = bucket.results[opId]
    if current and current.status == "processing" then
        bucket.results[opId] = {
            status = "unknown",
            fingerprint = current.fingerprint or GodSystemServer.attributeOpFingerprint(args),
            ok = false,
            code = "AttributeOperationUnknown",
            args = {},
            payload = { opId = opId },
        }
    end
end

Commands = {}

function Commands.hello(_, _, player)
    applyRuntimeStores()
    local data = playerData(player)
    if not data.currencyInitialized then
        local grant = 0
        if data.points and data.points > 0 then grant = floor(data.points, 0)
        elseif not data.started then grant = GodSystemConfig.StartingPoints or 0 end
        if grant > 0 and not giveCurrency(player, grant) then
            return finish(player, false, "初始系统币发放失败，将在下次进入时重试")
        end
        data.started = true
        data.currencyInitialized = true
        data.points = 0
        if grant > 0 then appendHistory(data, historyEntry("system", "InitialCurrency", { grant })) end
    end
    if data.attributeSyncPending == true and type(SyncXp) == "function" then
        local okSync = pcall(function() SyncXp(player) end)
        if okSync then data.attributeSyncPending = nil end
    end
    generateDailyTasks(data, false)
    sendInitialConfig(player)
    sendState(player)
    GodSystemServerRangeRecycle.sendFilterSnapshot(player)
end

function Commands.syncClientData(_, _, player, args)
    sendState(player)
end

function Commands.refresh(_, _, player, args)
    local data = playerData(player)
    data.stats.moveDistance = math.max(data.stats.moveDistance or 0, n(args and args.clientMoveDistance, data.stats.moveDistance or 0))
    sendState(player)
end

function Commands.diagnostics(_, _, player)
    sendState(player)
end

function Commands.itemConfigDetailsGet(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    applyRuntimeStores()
    local fullType = trim(args and args.fullType or "")
    local variantKey = trim(args and args.variantKey or "")
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.ItemConfigDetails) or "itemConfigDetails", {
        fullType = fullType,
        variantKey = variantKey,
        override = fullType ~= "" and GodSystemItemConfig.getItemOverride(fullType) or nil,
        variantOverride = variantKey ~= "" and GodSystemItemConfig.getShopVariantOverride(variantKey) or nil,
        revision = math.max(1, floor((GodSystemItemConfig.Current or {}).economyRevision, 1)),
    })
end

function Commands.itemConfigOverrideSet(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local fullType = trim(args and args.fullType or "")
    local hasItemOverride = fullType ~= ""
    local override = hasItemOverride and GodSystemItemConfig.sanitizeItemOverride(args and args.override or {}) or nil
    local variantKey = trim(args and args.variantKey or "")
    if (hasItemOverride and not override) or (not hasItemOverride and variantKey == "") then
        return finishCode(player, false, "ItemOverrideInvalid")
    end
    if hasItemOverride and GodSystemItemEligibility.isEconomicItemAllowed
        and GodSystemItemEligibility.isEconomicItemAllowed(fullType, "admin") == false then
        return finishCode(player, false, "ItemOverrideUnsafe")
    end
    local variant = nil
    if variantKey ~= "" then
        variant = GodSystemItemConfig.sanitizeShopVariantOverride(args and args.variantOverride or {})
        local variantType = variant and variant.fullType or ""
        if not variant or (hasItemOverride and variantType ~= fullType)
            or GodSystemShopVariants.getKey(variantType, variant.worldSprite) ~= variantKey then
            return finishCode(player, false, "ItemVariantMismatch")
        end
        if not hasItemOverride then fullType = variantType end
    elseif hasItemOverride and override.shopMode == "forced" and fullType == "Moveables.Moveable" then
        return finishCode(player, false, "ItemVariantRequired")
    end
    local data = itemConfigStore()
    data.itemOverrides = data.itemOverrides or {}
    data.shopVariantOverrides = data.shopVariantOverrides or {}
    if hasItemOverride then data.itemOverrides[fullType] = override end
    if variant then data.shopVariantOverrides[variantKey] = variant end
    data.economyRevision = math.max(1, floor(data.economyRevision, 1)) + 1
    applyRuntimeStores()
    local removedListings = 0
    if hasItemOverride and GodSystemItemConfig.getShopMode(fullType) == "disabled" then
        removedListings = GodSystemServer.clearDisabledShopListings(fullType, nil)
    elseif variantKey ~= ""
        and GodSystemItemConfig.getShopVariantMode(variantKey, fullType) == "disabled" then
        removedListings = GodSystemServer.clearDisabledShopListings(fullType, variantKey)
    end
    local public = GodSystemItemConfig.publicSnapshot()
    broadcastEconomyDelta({
        fullType = fullType,
        override = hasItemOverride and public.itemOverrides[fullType] or nil,
        variantKey = variantKey ~= "" and variantKey or nil,
        variantOverride = variantKey ~= "" and public.shopVariantOverrides[variantKey] or nil,
        revision = data.economyRevision,
    })
    if removedListings > 0 then broadcastState() end
    finishCode(player, true, "ItemOverrideSaved", nil, { revision = data.economyRevision })
end

function Commands.itemConfigOverrideClear(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local fullType = trim(args and args.fullType or "")
    local variantKey = trim(args and args.variantKey or "")
    if fullType == "" and variantKey == "" then return finishCode(player, false, "ItemFullTypeRequired") end
    local data = itemConfigStore()
    data.itemOverrides = data.itemOverrides or {}
    data.shopVariantOverrides = data.shopVariantOverrides or {}
    if fullType ~= "" then data.itemOverrides[fullType] = nil end
    if variantKey ~= "" then data.shopVariantOverrides[variantKey] = nil end
    data.economyRevision = math.max(1, floor(data.economyRevision, 1)) + 1
    applyRuntimeStores()
    local public = GodSystemItemConfig.publicSnapshot()
    broadcastEconomyDelta({
        fullType = fullType,
        override = fullType ~= "" and public.itemOverrides[fullType] or nil,
        cleared = fullType ~= "",
        variantKey = variantKey ~= "" and variantKey or nil,
        variantOverride = variantKey ~= "" and public.shopVariantOverrides[variantKey] or nil,
        variantCleared = variantKey ~= "",
        revision = data.economyRevision,
    })
    finishCode(player, true, "ItemOverrideCleared", nil, { revision = data.economyRevision })
end

function Commands.syncKills(_, _, player, args)
    applyRuntimeStores()
    local data = playerData(player)
    local kills = math.max(0, floor(args and args.clientKills, 0))
    if data.lastKnownKills == nil or kills < data.lastKnownKills then
        if data.lastKnownKills ~= nil and kills < data.lastKnownKills then
            for i = 1, #(data.tasks or {}) do
                local task = data.tasks[i]
                if task and task.status == "active" and task.kind == "kill" then
                    ensureKillTaskProgress(task, data.lastKnownKills)
                end
            end
        end
        data.lastKnownKills = kills
        return
    end
    local delta = kills - data.lastKnownKills
    if delta <= 0 then return end
    data.lastKnownKills = kills
    applyKillTaskDelta(data, delta, kills - delta)
    local reward = math.max(0, floor(GodSystemConfig.KillPointReward, 0))
    if reward <= 0 then return end
    local amount = delta * reward
    if giveCurrency(player, amount) then
        appendHistory(data, historyEntry("points", "KillReward", { amount }))
        notifyCode(player, "KillReward", { amount })
        sendState(player)
    end
end
end
