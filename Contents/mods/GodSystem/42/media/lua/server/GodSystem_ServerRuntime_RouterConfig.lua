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
    local carryLevel = GodSystemCarryCapacity.getLevel(data, player)
    GodSystemCarryCapacity.restore(player, carryLevel)
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
    local equipment = GodSystemServer.equipment
    local equipmentPlayer = equipment and equipment.players and equipment.players[player]
    GodSystemStateProjection.updateUIRevisions(data, {
        economyRevision = math.max(1, floor((GodSystemItemConfig.Current or {}).economyRevision, 1)),
        shopConfigVersion = GodSystemConfig.Version,
        equipmentRevision = equipmentPlayer and equipmentPlayer.account and equipmentPlayer.account.revision or 0,
    })
    local state = GodSystemStateProjection.build(data, {
        historyLimit = GodSystemConfig.HistoryLimit or 40,
        itemExists = itemExists,
        includeShopPayload = false,
    })
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.State) or "state", {
        data = state,
        balance = data.balance,
        version = GodSystemConfig.Version,
        admin = isAdminPlayer(player),
        carry = GodSystemCarryCapacity.makeSnapshot(player, carryLevel),
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
    if recordTaskCompletions then recordTaskCompletions(player, playerData(player)) end
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
    if updateTaskAuthoritativeProgress then updateTaskAuthoritativeProgress(player, data) end
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
    if args and args.expectedRevision ~= nil and floor(args.expectedRevision, -1) ~= floor(data.economyRevision, 0) then
        return finishCode(player, false, "ItemConfigRevisionConflict", nil, { revision = data.economyRevision })
    end
    applyRuntimeStores()
    if hasItemOverride and override.buyPrice ~= nil then
        local quote = GodSystemEconomyPolicy.quote(fullType, nil, { kind = "admin" })
        local safeMinimum = math.max(0, floor(quote and quote.safeMinimum, 0))
        if override.buyPrice < safeMinimum and args.acknowledgeRisk ~= true then
            return finishCode(player, false, "AdminPriceBelowSafeMinimum", nil, { safeMinimum = safeMinimum })
        end
    end
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
    if args and args.expectedRevision ~= nil and floor(args.expectedRevision, -1) ~= floor(data.economyRevision, 0) then
        return finishCode(player, false, "ItemConfigRevisionConflict", nil, { revision = data.economyRevision })
    end
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

-- Resolve the player-facing display name server-side so MP searches can match localized names.
local function itemDisplayName(fullType)
    if not fullType or fullType == "" then return "" end
    if getText then
        local key = "ItemName_" .. tostring(fullType)
        local value = getText(key)
        if value and value ~= key then return value end
    end
    if getScriptManager and getScriptManager() then
        local scriptItem = getScriptManager():FindItem(fullType)
        if scriptItem and scriptItem.getDisplayName then
            local name = scriptItem:getDisplayName()
            if name and name ~= "" then return name end
        end
    end
    return ""
end

local function relationRows(data, search, page)
    local rows, text = {}, string.lower(trim(search or ""))
    for _, relation in ipairs(GodSystemConversionRelations.all(data)) do
        local haystack = string.lower(table.concat({ relation.id, relation.sourceFullType, relation.recipeName, relation.note }, " "))
        local sourceName = itemDisplayName(relation.sourceFullType)
        if sourceName ~= "" then haystack = haystack .. " " .. string.lower(sourceName) end
        for _, output in ipairs(relation.outputs or {}) do
            haystack = haystack .. " " .. string.lower(output.fullType or "")
            local outputName = itemDisplayName(output.fullType)
            if outputName ~= "" then haystack = haystack .. " " .. string.lower(outputName) end
        end
        if text == "" or string.find(haystack, text, 1, true) then rows[#rows + 1] = relation end
    end
    local total, pageSize = #rows, 20
    page = math.max(1, floor(page, 1))
    local first, last, result = (page - 1) * pageSize + 1, math.min(total, page * pageSize), {}
    for i = first, last do result[#result + 1] = rows[i] end
    return result, total, page, math.max(1, math.ceil(total / pageSize))
end

local function sendRelationRows(player, data, search, page)
    local rows, total, resultPage, pageCount = relationRows(data, search, page)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.ItemConfigRelations) or "itemConfigRelations", {
        rows = rows, total = total, page = resultPage, pageCount = pageCount,
        revision = math.max(1, floor(data.conversionRevision, 1)),
        economyRevision = math.max(1, floor(data.economyRevision, 1)),
    })
end

function Commands.itemConfigRelationsGet(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data = itemConfigStore()
    sendRelationRows(player, data, args and args.search, args and args.page)
end

function Commands.itemConfigRelationSet(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data = itemConfigStore()
    if args and args.expectedRevision ~= nil and floor(args.expectedRevision, -1) ~= floor(data.conversionRevision, 0) then
        return finishCode(player, false, "ConversionRevisionConflict", nil, { revision = data.conversionRevision })
    end
    local id = trim(args and args.id or "")
    local builtin = GodSystemConversionRelations.builtinById()[id]
    local relation = GodSystemConversionRelations.sanitize(args and args.relation, id ~= "" and id or "custom:pending")
    if not relation then return finishCode(player, false, "ConversionRelationInvalid") end
    -- Reject relations referencing items that do not exist in the loaded scripts.
    if not itemExists(relation.sourceFullType) then return finishCode(player, false, "ConversionRelationItemMissing") end
    for _, output in ipairs(relation.outputs or {}) do
        if not itemExists(output.fullType) then return finishCode(player, false, "ConversionRelationItemMissing") end
    end
    if builtin then relation.id = id end
    if not builtin then
        data.conversionRelations = data.conversionRelations or {}
        if id == "" then
            if (function() local n=0 for _ in pairs(data.conversionRelations) do n=n+1 end return n end)() >= 512 then
                return finishCode(player, false, "ConversionRelationLimit")
            end
            data.conversionSequence = math.max(0, floor(data.conversionSequence, 0)) + 1
            id = "custom:" .. tostring(data.conversionSequence)
            relation.id = id
        elseif not data.conversionRelations[id] then return finishCode(player, false, "ConversionRelationUnknown") end
    end
    local candidate = {}
    for key, value in pairs(data) do candidate[key] = value end
    candidate.conversionRelations, candidate.conversionBuiltinOverrides = {}, {}
    for key, value in pairs(data.conversionRelations or {}) do candidate.conversionRelations[key] = value end
    for key, value in pairs(data.conversionBuiltinOverrides or {}) do candidate.conversionBuiltinOverrides[key] = value end
    if builtin then candidate.conversionBuiltinOverrides[id] = relation else candidate.conversionRelations[id] = relation end
    if GodSystemConversionRelations.hasCycle(candidate) then return finishCode(player, false, "ConversionRelationCycle") end
    if builtin then
        data.conversionBuiltinOverrides = data.conversionBuiltinOverrides or {}
        data.conversionBuiltinDisabled = data.conversionBuiltinDisabled or {}
        data.conversionBuiltinDisabled[id] = nil
        data.conversionBuiltinOverrides[id] = relation
    else data.conversionRelations[id] = relation end
    data.conversionRevision = math.max(1, floor(data.conversionRevision, 0) + 1)
    data.economyRevision = math.max(1, floor(data.economyRevision, 0) + 1)
    applyRuntimeStores()
    local public = GodSystemItemConfig.publicSnapshot()
    broadcastEconomyDelta({ revision = data.economyRevision, conversionRevision = data.conversionRevision,
        conversionFloors = public.conversionFloors })
    sendRelationRows(player, data, "", 1)
    finishCode(player, true, "ConversionRelationSaved", nil, { id = id, revision = data.conversionRevision })
end

function Commands.itemConfigRelationDelete(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data, id = itemConfigStore(), trim(args and args.id or "")
    if id == "" then return finishCode(player, false, "ConversionRelationInvalid") end
    if args and args.expectedRevision ~= nil and floor(args.expectedRevision, -1) ~= floor(data.conversionRevision, 0) then
        return finishCode(player, false, "ConversionRevisionConflict", nil, { revision = data.conversionRevision })
    end
    -- Legacy clients sent restore=true/false; map that onto the new action vocabulary.
    local action = tostring(args and args.action or "")
    if action == "" then action = (args and args.restore == true) and "enable" or "disable" end
    local builtin = GodSystemConversionRelations.builtinById()[id]
    local code
    if builtin then
        data.conversionBuiltinDisabled = data.conversionBuiltinDisabled or {}
        data.conversionBuiltinOverrides = data.conversionBuiltinOverrides or {}
        data.conversionBuiltinRemoved = data.conversionBuiltinRemoved or {}
        if action == "enable" then
            data.conversionBuiltinDisabled[id] = nil
            code = "ConversionRelationEnabled"
        elseif action == "delete" then
            data.conversionBuiltinRemoved[id] = true
            data.conversionBuiltinDisabled[id] = nil
            data.conversionBuiltinOverrides[id] = nil
            code = "ConversionRelationDeleted"
        elseif action == "disable" then
            data.conversionBuiltinDisabled[id] = true
            code = "ConversionRelationDisabled"
        else
            return finishCode(player, false, "ConversionRelationInvalid")
        end
    elseif action == "delete" and data.conversionRelations and data.conversionRelations[id] then
        data.conversionRelations[id] = nil
        code = "ConversionRelationDeleted"
    else
        return finishCode(player, false, "ConversionRelationUnknown")
    end
    data.conversionRevision = math.max(1, floor(data.conversionRevision, 0) + 1)
    data.economyRevision = math.max(1, floor(data.economyRevision, 0) + 1)
    applyRuntimeStores()
    local public = GodSystemItemConfig.publicSnapshot()
    broadcastEconomyDelta({ revision = data.economyRevision, conversionRevision = data.conversionRevision,
        conversionFloors = public.conversionFloors })
    sendRelationRows(player, data, "", 1)
    finishCode(player, true, code, nil, { id = id, revision = data.conversionRevision })
end

local function sendPresetList(player, data)
    sendServerCommand(player, MODULE, (Protocol.S2C and Protocol.S2C.ItemConfigPresets) or "itemConfigPresets",
        GodSystemItemConfig.presetListPayload(data))
end

-- Preset apply rewrites many overrides at once; a floors-only delta cannot express that,
-- so online admins receive a full public snapshot instead.
local function broadcastEconomySnapshotAdmins()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players or not players.size or not players.get then return end
    local public = GodSystemItemConfig.publicSnapshot()
    for i = 0, players:size() - 1 do
        local target = players:get(i)
        if target and isAdminPlayer(target) then
            sendServerCommand(target, MODULE, (Protocol.S2C and Protocol.S2C.EconomySnapshot) or "economySnapshot", { snapshot = public })
        end
    end
end

function Commands.itemConfigPresetsGet(_, _, player)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    sendPresetList(player, itemConfigStore())
end

function Commands.itemConfigPresetSave(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data = itemConfigStore()
    local store, err = GodSystemItemConfig.savePreset(data, args and args.name)
    if not store then
        return finishCode(player, false, err == "Limit" and "ItemConfigPresetLimitReached" or "ItemConfigPresetNameInvalid")
    end
    sendPresetList(player, data)
    finishCode(player, true, "ItemConfigPresetSaved", nil, { name = store.active })
end

function Commands.itemConfigPresetDelete(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data = itemConfigStore()
    local name = trim(args and args.name or "")
    if name == GodSystemItemConfig.PRESET_DEFAULT then return finishCode(player, false, "ItemConfigPresetDefaultProtected") end
    local store = GodSystemItemConfig.deletePreset(data, name)
    if not store then return finishCode(player, false, "ItemConfigPresetNotFound") end
    sendPresetList(player, data)
    finishCode(player, true, "ItemConfigPresetDeleted", nil, { name = name })
end

function Commands.itemConfigPresetApply(_, _, player, args)
    if not isAdminPlayer(player) then return finishCode(player, false, "AdminRequired") end
    local data = itemConfigStore()
    local store = GodSystemItemConfig.applyPreset(data, trim(args and args.name or ""))
    if not store then return finishCode(player, false, "ItemConfigPresetNotFound") end
    applyRuntimeStores()
    broadcastEconomyDelta({ revision = data.economyRevision, conversionRevision = data.conversionRevision,
        conversionFloors = GodSystemItemConfig.publicSnapshot().conversionFloors })
    broadcastEconomySnapshotAdmins()
    sendRelationRows(player, data, "", 1)
    sendPresetList(player, data)
    finishCode(player, true, "ItemConfigPresetApplied", nil, { name = store.active })
end

function Commands.syncKills(_, _, player, args)
    applyRuntimeStores()
    local data = playerData(player)
    local kills = math.max(0, floor(player and player.getZombieKills and player:getZombieKills() or 0))
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
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTasks") ~= false then
        applyKillTaskDelta(data, delta, kills - delta)
    end
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
