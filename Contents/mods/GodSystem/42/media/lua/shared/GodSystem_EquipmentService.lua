require "GodSystem_Equipment"
require "GodSystem_EquipmentItems"
require "GodSystem_InventoryIndex"

GodSystemEquipmentService = GodSystemEquipmentService or {}
local S, E, I, Index = GodSystemEquipmentService, GodSystemEquipment, GodSystemEquipmentItems, GodSystemInventoryIndex
S.__index = S

function S.new(adapter)
    assert(adapter and adapter.authority == true, "Equipment service requires an authority adapter")
    return setmetatable({ adapter = adapter, known = {}, knownIds = {}, players = {}, loadedRoot = nil,
        unsupportedLogs = {}, metrics = { indexes = 0, itemsVisited = 0, operations = 0, reconciles = 0, syncFailures = 0 } }, S)
end

function S:root()
    local root = self.adapter.store()
    if type(root) ~= "table" then return nil, "EquipmentNotReady" end
    if root.schemaVersion == nil then
        -- B42 Kahlua provides pairs(), but no global next(). Never replace
        -- nonempty, unversioned data with a newly initialized archive.
        for _ in pairs(root) do return nil, "EquipmentDataInvalid" end
        local id = self.adapter.uuid()
        if type(id) ~= "string" or id == "" then return nil, "EquipmentNotReady" end
        root.schemaVersion, root.worldId, root.accounts, root.records, root.localProfiles = E.Schema, id, {}, {}, {}
    end
    if root.schemaVersion ~= E.Schema or type(root.worldId) ~= "string" or type(root.accounts) ~= "table"
        or type(root.records) ~= "table" or type(root.localProfiles) ~= "table" then return nil, "EquipmentDataInvalid" end
    if self.loadedRoot ~= root then
        for _, account in pairs(root.accounts) do
            if type(account) ~= "table" or type(account.receipts) ~= "table" then return nil, "EquipmentDataInvalid" end
            for id, receipt in pairs(account.receipts) do
                if type(receipt) ~= "table" then return nil, "EquipmentDataInvalid" end
                if receipt.status == "processing" then receipt.status = "unknown"; account.uncertainOp = id end
            end
        end
        self.loadedRoot = root
    end
    return root
end

function S:logUnsupported(item, reason, field)
    local fullType = tostring(I.value(item, "getFullType", "unknown"))
    local key = fullType .. "|" .. tostring(reason or "unknown") .. "|" .. tostring(field or "unknown")
    -- A problematic third-party weapon must be diagnosable without turning a
    -- repeated click into a console flood.
    if self.unsupportedLogs[key] then return end
    self.unsupportedLogs[key] = true
    print("[GodSystem] equipment bind rejected: fullType=" .. fullType
        .. " itemId=" .. tostring(I.id(item) or "unknown")
        .. " reason=" .. tostring(reason or "unknown") .. " field=" .. tostring(field or "unknown"))
end

function S:slotRecord(root, account, owner, slot)
    local id = account.slots[slot]
    if id == nil then return nil, nil, nil end
    local record = root.records[id]
    E.normalizeRecord(record)
    local valid, reason = E.validateRecord(record, owner)
    if not valid then return nil, reason or "identity", id end
    if record.id ~= id then return nil, "identity", id end
    return record, nil, id
end

function S:recordAttached(root, record)
    if not E.validRecord(record) or record.state ~= "active" then return false end
    local account = root.accounts[record.ownerKey]
    if type(account) ~= "table" or type(account.slots) ~= "table" then return false end
    -- Slots are bounded by the schema.  This is deliberately not an account
    -- or inventory scan, and detaching a corrupt slot immediately revokes its
    -- formerly marked physical item.
    for slot = 1, 20 do if account.slots[slot] == record.id then return true end end
    return false
end

function S:account(player)
    if not player or not instanceof or not instanceof(player,"IsoPlayer") then return nil,nil,nil,"EquipmentNotReady" end
    if I.value(player, "isDead", true) then return nil, nil, nil, "EquipmentBusy" end
    local root, err = self:root()
    if not root then return nil, nil, nil, err end
    local cfg, cfgError = E.config(self.adapter.config())
    if not cfg then return nil, nil, nil, cfgError end
    local md = I.value(player, "getModData")
    if not md then return nil, nil, nil, "EquipmentNotReady" end
    local owner = self.adapter.owner and self.adapter.owner(player)
    if self.adapter.multiplayer then
        if type(owner) ~= "string" or owner == "" then return nil, nil, nil, "EquipmentNotReady" end
        owner = "mp:" .. owner
    else
        local profileSlot = tostring(I.value(player, "getPlayerNum", 0))
        local marker = md[E.CharacterKey]
        if type(marker) == "table" and marker.worldId == root.worldId and root.accounts[marker.ownerKey] then
            owner = marker.ownerKey
        else
            root.localProfiles[profileSlot] = root.localProfiles[profileSlot] or ("sp:" .. self.adapter.uuid())
            owner = root.localProfiles[profileSlot]
        end
    end
    local character = md[E.CharacterKey]
    if type(character) ~= "table" or character.worldId ~= root.worldId or character.ownerKey ~= owner
        or type(character.id) ~= "string" then
        character = { id = self.adapter.uuid(), ownerKey = owner, worldId = root.worldId }
        md[E.CharacterKey] = character
    end
    local account = root.accounts[owner]
    if not account then
        account = { ownerKey = owner, activeCharacterId = character.id, revision = 1, unlockedSlots = 1,
            completedTasks = 0, slots = {}, receipts = {}, receiptOrder = {} }
        root.accounts[owner] = account
    end
    if type(account.slots) ~= "table" or type(account.receipts) ~= "table" or type(account.receiptOrder) ~= "table"
        or not E.integer(account.unlockedSlots, 1, 20) or not E.integer(account.revision, 1, 9007199254740000) then
        return nil, nil, nil, "EquipmentDataInvalid"
    end
    local invalidSlots = {}
    for slot, id in pairs(account.slots) do
        if E.integer(slot, 1, 20) then
            local record, reason = self:slotRecord(root, account, owner, slot)
            if not record then invalidSlots[slot] = { reason = reason or "identity", recordId = type(id) == "string" and id or nil } end
        else
            -- An out-of-schema key occupies no visible slot.  Leave it intact
            -- for diagnostics instead of treating it as an account-wide fault.
            print("[GodSystem] equipment ignored invalid slot key: " .. tostring(slot))
        end
    end
    if account.activeCharacterId ~= character.id then
        account.activeCharacterId, account.revision = character.id, account.revision + 1
        for slot, id in pairs(account.slots) do
            local record = root.records[id]
            if not invalidSlots[slot] and record then record.characterId = character.id; record.revision = record.revision + 1 end
        end
    end
    local data = self.adapter.data(player)
    E.unlock(account, data and data.stats and data.stats.completedTasks or 0, cfg)
    self.players[player] = { root = root, account = account, cfg = cfg, invalidSlots = invalidSlots }
    if self.lifecycle then self.lifecycle.track(player) end
    return root, account, cfg
end

function S:index(player)
    local start = getTimestampMs and getTimestampMs() or 0
    local index = Index.build(I.value(player, "getInventory"))
    self.metrics.indexes = self.metrics.indexes + 1
    self.metrics.itemsVisited = self.metrics.itemsVisited + index.itemsVisited
    self.metrics.lastIndexMs = (getTimestampMs and getTimestampMs() or start) - start
    return index
end

function S:recordFor(item, root)
    local marker = I.marker(item)
    if not marker or marker.worldId ~= root.worldId then return nil end
    local record = root.records[marker.equipmentId]
    if self:recordAttached(root, record) and record.fullType == I.value(item, "getFullType") then return record end
    return nil
end

-- Constant-time authority lookup for combat effects.  It never builds an
-- inventory index: a combat effect only applies to the currently held item.
function S:activeRecord(player,item)
    local cached=self.players[player]
    if not cached then self:account(player); cached=self.players[player] end
    local root,account,cfg=cached and cached.root,cached and cached.account,cached and cached.cfg
    if not root or not account or not cfg or not cfg.enabled or account.uncertainOp then return nil end
    local record=self:recordFor(item,root)
    if not record or record.identityConflict or record.ownerKey~=account.ownerKey
        or record.characterId~=account.activeCharacterId or not I.matches(item,root,record)
        or not I.owned(player,item) or I.value(player,"isDead",true) then return nil end
    return record,cfg,root
end

-- Read-only projection for inventory Tooltip presentation.  It deliberately
-- resolves only the supplied equipment UUID in the authority archive: no
-- player inventory, world-container, or account scan happens on hover.
function S:inspect(args)
    args = type(args) == "table" and args or {}
    local root = self:root()
    local result = { valid = false, requestId = args.requestId, worldId = args.worldId, equipmentId = args.equipmentId,
        generation = args.generation, itemId = args.itemId, fullType = args.fullType, revision = args.revision }
    if not root or args.worldId ~= root.worldId or type(args.equipmentId) ~= "string"
        or type(args.itemId) ~= "string" or type(args.fullType) ~= "string" then return result end
    local record = root.records[args.equipmentId]
    if not self:recordAttached(root, record) or record.identityConflict
        or record.generation ~= args.generation or record.revision ~= args.revision
        or record.itemId ~= args.itemId or record.fullType ~= args.fullType then return result end
    local cfg = E.config(self.adapter.config())
    if not cfg then return result end
    result.valid, result.worldId, result.equipmentId = true, root.worldId, record.id
    result.generation, result.itemId, result.fullType, result.revision = record.generation, record.itemId, record.fullType, record.revision
    result.levels = E.projectionLevels(record)
    result.effectState = { impact = GodSystemEquipmentImpact.state(record) }
    result.config = { enabled = cfg.enabled == true, freezeEnabled = cfg.freezeEnabled == true,
        splashEnabled = cfg.splashEnabled == true,
        EquipmentGrowthPercent = cfg.EquipmentGrowthPercent }
    return result
end

function S:observe(item, root)
    root = root or self:root()
    if not root then return end
    local record = self:recordFor(item, root)
    if record and I.matches(item, root, record) then
        local claim=self.knownIds[record.itemId]
        if claim and claim.item~=item then
            local other=root.records[claim.recordId]
            if other and I.matches(claim.item,root,other) then
                record.identityConflict=true; other.identityConflict=true; return
            end
        end
        local previous = self.known[record.id]
        if previous and previous ~= item and I.matches(previous, root, record) then record.identityConflict = true; return end
        local d = I.durability(item)
        record.durability = d
        self.known[record.id] = item
        self.knownIds[record.itemId]={item=item,recordId=record.id}
    end
end

function S:forgetRecord(id)
    local item=self.known[id]
    local nativeId=item and I.id(item)
    if nativeId and self.knownIds[nativeId] and self.knownIds[nativeId].recordId==id then self.knownIds[nativeId]=nil end
    self.known[id]=nil
end

function S:sync(player, item, record, active, syncNativeFields)
    if not self.adapter.sync then return true end
    syncNativeFields=syncNativeFields or (record and record.pendingDurabilitySync)==true
    local cached = self.players[player]
    local ok, result = pcall(self.adapter.sync, player, item, record, active, syncNativeFields, cached and cached.cfg)
    if not ok or result == false then
        self.metrics.syncFailures = self.metrics.syncFailures + 1
        if record then record.pendingSync = true; record.pendingDurabilitySync=syncNativeFields or nil end
        return false
    end
    if record then record.pendingSync = nil; record.pendingDurabilitySync=nil end
    return true
end

function S:reconcile(player, item, forceSync)
    if not I.isWeapon(item) or not I.marker(item) then return false end
    local cached = self.players[player]
    if not cached then self:account(player); cached = self.players[player] end
    local root, account, cfg = cached and cached.root, cached and cached.account, cached and cached.cfg
    if not root then return false end
    local record = self:recordFor(item, root)
    if not record then
        -- Old/cross-world markers simply lose GodSystem identity.  Do not
        -- write any native combat field while reconciling.
        I.value(item, "getModData")[E.ItemKey] = nil
        self:sync(player, item, nil, false)
        return true
    end
    self:observe(item, root)
    local matches = I.matches(item, root, record)
    local active = matches and cfg.enabled and record.ownerKey == account.ownerKey
        and record.characterId == account.activeCharacterId and not account.uncertainOp and not record.identityConflict
        and I.held(player, item) and I.owned(player, item) and not I.value(player, "isDead", true)
    if not matches then
        local md = I.value(item, "getModData")
        if md then md[E.ItemKey] = nil end
    else
        I.mark(item, root, record)
        self:observe(item, root)
    end
    self.metrics.reconciles = self.metrics.reconciles + 1
    if forceSync or record.pendingSync then self:sync(player, item, record, active) end
    return true
end

function S:retrieveCost(fullType, cfg)
    if self.adapter.exists and not self.adapter.exists(fullType) then return nil end
    local price = E.number(self.adapter.price(fullType))
    if not price or price <= 0 then return nil end
    return E.integer(math.ceil(price * cfg.EquipmentRetrieveMultiplier), 1, E.MaxMoney)
end

function S:snapshot(player)
    local root, account, cfg, err = self:account(player)
    if not root then return { ready = false, code = err } end
    local cached = self.players[player]
    local invalidSlots = cached and cached.invalidSlots or {}
    local index = self:index(player)
    if not index.valid then return { ready = false, code = "EquipmentInventoryChanged" } end
    local candidates={}
    for id,row in pairs(index.byId) do
        if not index.ambiguous[id] then
            if I.marker(row.item) then self:reconcile(player,row.item,true) end
            if not self.adapter.multiplayer and I.isWeapon(row.item) and not I.marker(row.item) then
                local durability, reason = I.durability(row.item)
                local bindable = durability ~= nil
                candidates[#candidates+1]={id=id,item=row.item,name=I.value(row.item,"getDisplayName",I.value(row.item,"getFullType")),
                    bindable=bindable, bindReason=reason}
            end
        end
    end
    local state = { ready = true, ownerKey = account.ownerKey, characterId = account.activeCharacterId,
        worldId = root.worldId, revision = account.revision, config = cfg, rows = {},
        completedTasks = account.completedTasks, blocked = account.uncertainOp ~= nil }
    for slot = 1, math.max(account.unlockedSlots, cfg.EquipmentMaxSlots) do
        local invalid = invalidSlots[slot]
        local record = invalid and nil or root.records[account.slots[slot]]
        local target = E.slotTarget(slot,cfg)
        local row = { slot = slot, target = target ~= math.huge and target or nil, unreachable = target == math.huge, locked = slot > account.unlockedSlots,
            overLimit = slot > cfg.EquipmentMaxSlots }
        if invalid then
            row.invalid, row.invalidReason, row.invalidRecordId = true, invalid.reason, invalid.recordId
        elseif record then
            local item = Index.find(index, record.itemId)
            local present = item and I.matches(item, root, record) or false
            if present then self:observe(item, root) end
            row.record = { id = record.id, itemId = record.itemId, generation = record.generation,
                revision = record.revision, fullType = record.fullType, name = record.name,
                weaponKind = E.weaponKind(record), levels = E.projectionLevels(record),
                effectState = E.copy(record.effectState), durability = E.copy(record.durability) }
            row.present, row.conflict = present, index.ambiguous[record.itemId] == true or record.identityConflict == true
                or (item and I.value(item,"getFullType")~=record.fullType) or false
            row.parameterError = record.parameterError == true
            row.retrieveCost = self:retrieveCost(record.fullType, cfg)
            row.repairCost = cfg.EquipmentRepairCost
            row.repairable = present and I.canRepair(item) or false
        end
        state.rows[#state.rows + 1] = row
    end
    if not self.adapter.multiplayer then
        table.sort(candidates,function(a,b) if a.name==b.name then return a.id<b.id end; return a.name<b.name end)
    end
    return state,candidates
end

local function response(ok, code, opId)
    return { ok = ok == true, code = code, operationId = opId, equipment = true }
end

function S:performAction(player, args)
    args = type(args) == "table" and args or {}
    local root, account, cfg, err = self:account(player)
    if not root then return response(false, err, args.opId) end
    if args.action == "rename" and args.mode == "custom" then
        local name, nameError = E.validateName(args.name)
        if not name then return response(false, nameError, args.opId) end
        args = E.copy(args)
        args.name = name
    end
    local opId, fingerprint = args.opId, E.fingerprint(args)
    if type(opId) ~= "string" or #opId < 8 or #opId > 96 or not opId:match("^[%w%-]+$") or not fingerprint then
        return response(false, "EquipmentRequestInvalid", opId)
    end
    local previous = account.receipts[opId]
    if previous then
        if previous.fingerprint ~= fingerprint then return response(false, "EquipmentRequestMismatch", opId) end
        if previous.status == "done" then return E.copy(previous.result) end
        return response(false, "EquipmentUnknown", opId)
    end
    if account.uncertainOp or account.inFlight then return response(false, "EquipmentUnknown", opId) end
    if not cfg.enabled then return response(false, "EquipmentDisabled", opId) end
    if I.value(player, "isDead", true) or I.value(player, "isAttacking", false) then return response(false, "EquipmentBusy", opId) end
    if args.revision ~= account.revision or args.configToken ~= cfg.token then return response(false, "EquipmentQuoteChanged", opId) end
    local slot = E.integer(args.slot, 1, account.unlockedSlots)
    if not slot then return response(false, "EquipmentSlotLocked", opId) end
    local action = args.action
    if action ~= "bind" and action ~= "unbind" and action ~= "enhance" and action ~= "repair" and action ~= "retrieve"
        and action ~= "rename" and action ~= "clearInvalidSlot" then
        return response(false, "EquipmentRequestInvalid", opId)
    end
    local record, slotReason, slotId = self:slotRecord(root, account, account.ownerKey, slot)
    local invalidSlot = slotId ~= nil and not record
    if action == "clearInvalidSlot" then
        if args.cost ~= 0 then return response(false, "EquipmentQuoteChanged", opId) end
        if not invalidSlot then return response(false, "EquipmentIdentityInvalid", opId) end
    elseif action == "bind" then
        if slotId ~= nil or slot > cfg.EquipmentMaxSlots then return response(false, "EquipmentSlotLocked", opId) end
        for _,equipmentId in pairs(account.slots) do
            local other = root.records[equipmentId]
            if E.validRecord(other, account.ownerKey) and other.itemId == tostring(args.itemId or "") then
                return response(false,"EquipmentIdentityInvalid",opId)
            end
        end
    elseif not record or record.ownerKey ~= account.ownerKey or record.state ~= "active"
        or record.characterId ~= account.activeCharacterId or args.equipmentId ~= record.id or args.recordRevision ~= record.revision
        or (args.generation ~= nil and args.generation ~= record.generation) then
        return response(false, "EquipmentIdentityInvalid", opId)
    end
    local index, id, item, present = nil, nil, nil, false
    if action ~= "clearInvalidSlot" then
        index = self:index(player)
        if not index.valid then return response(false, "EquipmentInventoryChanged", opId) end
        id = action == "bind" and tostring(args.itemId or "") or record.itemId
        if index.ambiguous[id] then return response(false, "EquipmentIdentityInvalid", opId) end
        item = Index.find(index, id)
        local claim=self.knownIds[id]
        if claim and claim.item~=item and action~="retrieve" and item then return response(false,"EquipmentIdentityInvalid",opId) end
        if record and item and I.value(item,"getFullType")~=record.fullType then return response(false,"EquipmentIdentityInvalid",opId) end
        present = record and item and I.matches(item, root, record)
        if record and record.identityConflict then return response(false, "EquipmentIdentityInvalid", opId) end
        if action == "retrieve" and present then return response(false, "EquipmentAlreadyCarried", opId) end
        if (action == "enhance" or action == "repair" or action == "rename") and (not present or tostring(args.itemId or "") ~= id) then
            return response(false, "EquipmentNotCarried", opId)
        end
        if action == "bind" and (not item or not I.owned(player, item) or not I.isWeapon(item) or I.marker(item)) then
            return response(false, "EquipmentIdentityInvalid", opId)
        end
    end
    local snapshot, quote, cost, bindRecord = nil, nil, 0, nil
    if action ~= "retrieve" and action ~= "clearInvalidSlot" and item and (action == "bind" or present) then
        snapshot = I.snapshot(item, action == "bind" or action == "repair")
        if not snapshot then
            if action == "bind" then self:logUnsupported(item, "snapshot", "item") end
            return response(false, action == "bind" and "EquipmentBindUnsupported" or "EquipmentUnsupported", opId)
        end
    end
    if action == "bind" then
        local equipmentId = self.adapter.uuid()
        bindRecord = { id = equipmentId, ownerKey = account.ownerKey, characterId = account.activeCharacterId,
            generation = 1, revision = 1, itemId = id, fullType = I.value(item, "getFullType"),
            name = I.name(item), customName = I.customName(item) and I.name(item) or nil,
            weaponKind = I.value(item,"isRanged",false) and "ranged" or "melee",
            levels = E.newLevels(I.value(item,"isRanged",false) and "ranged" or "melee"),
            effectState = { impact = { attackCount = 0, ready = false, stateRevision = 0 } },
            durability = E.copy(snapshot.durability), state = "active" }
        local valid, reason, field = E.validateRecord(bindRecord, account.ownerKey)
        if type(equipmentId) ~= "string" or equipmentId == "" or root.records[equipmentId] or not valid then
            self:logUnsupported(item, reason or "identity", field or "id")
            return response(false, "EquipmentBindUnsupported", opId)
        end
    elseif action == "enhance" then
        quote, err = E.quote(record, args.attribute, args.boost, cfg)
        if not quote then return response(false, err, opId) end
        cost = quote.cost
    elseif action == "repair" then
        if not I.canRepair(item,snapshot.durability) then
            return response(false, "EquipmentUnsupported", opId)
        end
        if I.full(snapshot.durability) then return response(false, "EquipmentAlreadyFull", opId) end
        cost = cfg.EquipmentRepairCost
    elseif action == "retrieve" then
        if not record.durability then return response(false, "EquipmentUnsupported", opId) end
        cost = self:retrieveCost(record.fullType, cfg)
        if not cost then return response(false, "EquipmentCostInvalid", opId) end
    elseif action == "rename" then
        if args.mode ~= "custom" and args.mode ~= "default" then return response(false, "EquipmentRequestInvalid", opId) end
        if args.cost ~= 0 then return response(false, "EquipmentQuoteChanged", opId) end
    end
    if args.cost ~= cost then return response(false, "EquipmentQuoteChanged", opId) end
    local receipt = { status = "processing", fingerprint = fingerprint, action = action, cost = cost,
        oldRevision = account.revision, oldRecord = E.copy(record or root.records[slotId]), itemSnapshot = E.copy(snapshot) }
    account.receipts[opId], account.inFlight = receipt, opId
    account.receiptOrder[#account.receiptOrder + 1] = opId
    self.metrics.operations = self.metrics.operations + 1
    local paid, bank, cash, newItem, changedItem = false, 0, 0, nil, nil
    local working = record and E.copy(record) or nil
    local result
    local callOK, applied, failure = pcall(function()
        if cost > 0 then
            receipt.paymentStarted = true
            local affordable, fromBank, fromCash = self.adapter.spend(player, cost)
            receipt.paymentReturned = true
            if not affordable then return false, "EquipmentInsufficientFunds" end
            paid, bank, cash = true, fromBank or 0, fromCash or 0
            receipt.bank, receipt.cash = bank, cash
        end
        if snapshot and (not I.owned(player, item) or I.id(item) ~= id) then return false, "EquipmentInventoryChanged" end
        if action == "clearInvalidSlot" then
            result = response(true, "EquipmentInvalidSlotCleared", opId)
        elseif action == "bind" then
            -- bindRecord was already fully validated before a receipt, marker,
            -- slot or revision could be changed.
            working = E.copy(bindRecord)
            changedItem = item
            if not I.mark(item, root, working) then return false, "EquipmentApplyFailed" end
            result = response(true, "EquipmentBound", opId)
        elseif action == "unbind" then
            if present then
                changedItem = item
                I.value(item, "getModData")[E.ItemKey] = nil
            end
            working.state, working.levels, working.revision = "retired", {}, record.revision + 1
            result = response(true, "EquipmentUnbound", opId)
        elseif action == "enhance" then
            local roll = E.integer(self.adapter.random(10000), 0, 9999)
            if not roll then return false, "EquipmentApplyFailed" end
            receipt.roll = roll
            local won = roll < quote.chanceBP
            working.levels[args.attribute] = won and quote.level + 1 or math.max(0, quote.level - 1)
            changedItem = item
            if args.attribute=="impact" then GodSystemEquipmentImpact.reset(working) end
            working.revision = working.revision + 1
            result = response(true, won and "EquipmentEnhanced" or "EquipmentEnhanceFailed", opId)
        elseif action == "repair" then
            changedItem = item
            if not I.setDurability(item, snapshot.durability, false, true) then return false, "EquipmentApplyFailed" end
            working.revision = working.revision + 1
            result = response(true, "EquipmentRepaired", opId)
        elseif action == "rename" then
            local custom = args.mode == "custom"
            local target = custom and args.name or I.defaultName(item)
            if type(target) ~= "string" or target == "" then return false, "EquipmentApplyFailed" end
            if I.name(item) == target and I.customName(item) == custom then
                receipt.unchanged = true
                result = response(true, "EquipmentNameUnchanged", opId)
            else
                changedItem = item
                if not I.setName(item, target, custom) then return false, "EquipmentApplyFailed" end
                working.name, working.customName, working.revision = target, custom and target or nil, record.revision + 1
                result = response(true, custom and "EquipmentNameChanged" or "EquipmentNameReset", opId)
            end
        elseif action == "retrieve" then
            newItem = self.adapter.create(record.fullType)
            if not newItem or not I.isWeapon(newItem) or I.value(newItem, "getFullType") ~= record.fullType then return false, "EquipmentCreateFailed" end
            if not I.emptyRecovery(newItem) or not I.setDurability(newItem, record.durability, true, false)
                then return false, "EquipmentCreateFailed" end
            local newId = I.id(newItem)
            if not newId or newId == record.itemId or index.byId[newId] or self.knownIds[newId] then return false, "EquipmentIdentityInvalid" end
            working.itemId, working.generation, working.revision = newId, record.generation + 1, record.revision + 1
            receipt.newItemId = newId
            if record.customName and not I.setName(newItem, record.customName, true) then return false, "EquipmentCreateFailed" end
            if not I.mark(newItem, root, working) or not self.adapter.add(player, newItem) or not I.owned(player, newItem) then return false, "EquipmentCreateFailed" end
            changedItem = newItem
            result = response(true, "EquipmentRetrieved", opId)
        end
        if working and working.state == "active" and changedItem then
            working.durability = I.durability(changedItem)
            if not I.mark(changedItem, root, working) then return false, "EquipmentApplyFailed" end
        end
        if changedItem and not I.owned(player,changedItem) then return false, "EquipmentInventoryChanged" end
        return true
    end)
    -- Kahlua logs error() even inside pcall. Expected refusal/rollback codes
    -- return normally; unexpected engine exceptions still retain their trace.
    if not callOK then failure = applied end
    if callOK and applied then
        if receipt.unchanged then
            account.inFlight = nil
            result.paid, result.revision = 0, account.revision
            receipt.status, receipt.result = "done", E.copy(result)
            while #account.receiptOrder > 64 do
                local oldest = table.remove(account.receiptOrder, 1)
                if oldest ~= account.uncertainOp then account.receipts[oldest] = nil end
            end
            return result
        end
        if action == "clearInvalidSlot" then
            account.slots[slot] = nil
        else
            root.records[working.id] = working
            if action == "unbind" then account.slots[slot] = nil else account.slots[slot] = working.id end
        end
        account.revision = account.revision + 1
        if working then self:forgetRecord(working.id) end
        if changedItem and working and working.state == "active" then self:observe(changedItem,root) end
        result.paid, result.revision = cost, account.revision
        receipt.status, receipt.result = "done", E.copy(result)
        account.inFlight = nil
        if self.adapter.committed then pcall(self.adapter.committed, player, cost, result) end
        if changedItem and working then self:sync(player, changedItem, working, I.held(player, changedItem) and action ~= "unbind", action=="repair" or action=="retrieve" or action=="rename") end
    else
        local rollback = not receipt.paymentStarted or receipt.paymentReturned == true
        if newItem then
            local ok, removed = pcall(self.adapter.remove, player, newItem)
            rollback = rollback and ok and removed == true
        elseif changedItem then
            local ok, restored = pcall(I.restore, changedItem, snapshot)
            rollback = rollback and ok and restored == true and I.owned(player,changedItem)
        end
        if rollback and paid then
            local ok, refunded = pcall(self.adapter.refund, player, bank, cash)
            rollback = ok and refunded ~= false
        end
        account.inFlight = nil
        -- Rename is free and changes only the item's display fields. If the
        -- engine accepted part of a rename but cannot restore the old name,
        -- reconcile the authoritative record to the observed real item. Do
        -- this only while the original bound identity is still unambiguous.
        local renameReconciled = false
        if not rollback and action == "rename" and cost == 0 and item and record
            and I.owned(player, item) and I.matches(item, root, record) then
            local observedName, observedCustom = I.name(item), I.customName(item)
            if type(observedName) == "string" and observedName ~= "" then
                local reconciled = E.copy(record)
                reconciled.name = observedName
                reconciled.customName = observedCustom and observedName or nil
                reconciled.revision = record.revision + 1
                if E.validRecord(reconciled, account.ownerKey) and I.mark(item, root, reconciled) then
                    root.records[reconciled.id] = reconciled
                    account.revision = account.revision + 1
                    self:forgetRecord(reconciled.id)
                    self:observe(item, root)
                    record = reconciled
                    renameReconciled = true
                    print("[GodSystem] equipment rename reconciled after rollback failure op=" .. tostring(opId))
                end
            end
        end
        if not rollback then
            if renameReconciled then
                result = response(false, "EquipmentApplyFailed", opId)
                result.revision = account.revision
                receipt.status, receipt.result = "done", E.copy(result)
            else
                account.uncertainOp, receipt.status = opId, "unknown"
                result = response(false, "EquipmentUnknown", opId)
                print("[GodSystem] equipment rollback uncertain action=" .. tostring(action)
                    .. " op=" .. tostring(opId) .. " failure=" .. tostring(failure))
            end
        else
            local code = tostring(failure):match("(Equipment[%w]+)$") or "EquipmentApplyFailed"
            result = response(false, code, opId)
            account.revision = account.revision + 1 -- Also fence rolled-back requests after receipt eviction.
            result.revision = account.revision
            receipt.status, receipt.result = "done", E.copy(result)
        end
        if changedItem and not newItem then self:sync(player, changedItem, record, I.held(player, changedItem), action=="repair" or action=="rename") end
    end
    -- Revision checks remain after receipt eviction; an old successful request cannot execute twice.
    if receipt.status=="done" then receipt.oldRecord=nil; receipt.itemSnapshot=nil end
    while #account.receiptOrder > 64 do
        local oldest = table.remove(account.receiptOrder, 1)
        if oldest ~= account.uncertainOp then account.receipts[oldest] = nil end
    end
    return result
end

function S:action(player,args)
    local start=getTimestampMs and getTimestampMs() or 0
    local ok,result=pcall(self.performAction,self,player,args)
    self.metrics.lastActionMs=(getTimestampMs and getTimestampMs() or start)-start
    if ok then return result end
    self.lastError=tostring(result)
    print("[GodSystem] equipment transaction exception: "..self.lastError)
    local cached=self.players[player]
    local account=cached and cached.account
    local code="EquipmentDataInvalid"
    if account and account.inFlight then
        account.uncertainOp=account.inFlight
        local receipt=account.receipts[account.inFlight]
        if receipt then receipt.status="unknown" end
        account.inFlight=nil
        code="EquipmentUnknown"
    end
    return response(false,code,type(args)=="table" and args.opId or nil)
end

return S
