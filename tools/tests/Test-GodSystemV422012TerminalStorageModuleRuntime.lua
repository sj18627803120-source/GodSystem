local luaRoot = assert(arg and arg[1], "Lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/init.lua",
    package.path,
}, ";")

require "GodSystem/Core/Result"
require "GodSystem/Services/OperationLedger"
require "GodSystem/Services/Operations"
require "GodSystem/Features/Terminal/Rules"
require "GodSystem/Features/Terminal/Module"
require "GodSystem/Features/Storage/Rules"
require "GodSystem/Features/Storage/Module"

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function dotPort(source)
    local result = {}
    for key, value in pairs(source) do
        if type(value) == "function" then
            local callback = value
            result[key] = function(...) return callback(source, ...) end
        else
            result[key] = value
        end
    end
    return result
end

local function operationsPort()
    local value = {}
    local service = GodSystemOperationsService.create({}, {
        state = {
            get = function() return value end,
        },
    })
    service:start()
    return service.public
end

local function wallet(initial)
    local port = { balance = initial or 0, charges = 0, refunds = 0, nextId = 1 }
    function port:getBalance() return self.balance end
    function port:charge(_, amount)
        if self.balance < amount then return false, "balanceInsufficient" end
        self.balance = self.balance - amount
        self.charges = self.charges + amount
        local receipt = { id = "w" .. tostring(self.nextId), amount = amount, restored = false }
        self.nextId = self.nextId + 1
        return true, receipt
    end
    function port:refund(_, receipt)
        if type(receipt) ~= "table" or receipt.restored then return false, "receiptInvalid" end
        receipt.restored = true
        self.balance = self.balance + receipt.amount
        self.refunds = self.refunds + receipt.amount
        return true
    end
    return port
end

local function terminalEnvironment(initialState, initialBalance, sharedOperations)
    local statePort = {
        value = clone(initialState or {}),
        revision = 0,
        failCommit = false,
    }
    function statePort:load() return clone(self.value), self.revision end
    function statePort:commit(_, value, expected)
        if self.failCommit then return false, "commitFailed" end
        if expected ~= self.revision then return false, "revisionConflict" end
        self.value = clone(value)
        self.revision = self.revision + 1
        return true, nil, self.revision
    end
    function statePort:health() return true end

    local instancePort = {
        item = nil,
        nextId = 1,
        failApply = false,
        applyCount = 0,
        removedEscaped = 0,
    }
    function instancePort:findOwned(_, expectedId)
        if expectedId and self.item and self.item.id ~= expectedId then return nil, "terminalMissing" end
        return self.item
    end
    function instancePort:create(_, fullType)
        self.item = { id = "terminal-" .. tostring(self.nextId), fullType = fullType, spec = nil }
        self.nextId = self.nextId + 1
        return self.item
    end
    function instancePort:remove(_, item)
        if self.item ~= item then return false, "terminalMissing" end
        self.item = nil
        return true
    end
    function instancePort:snapshot(_, item)
        return { spec = clone(item.spec) }
    end
    function instancePort:apply(_, item, spec)
        self.applyCount = self.applyCount + 1
        if self.failApply then return false, "applyFailed" end
        expect(spec.capacity >= 10 and spec.capacity <= 49, "terminal capacity range")
        expect(spec.reduction >= 50 and spec.reduction <= 99, "terminal reduction range")
        expect(spec.reliefCount == (spec.reliefLevel > 0 and 1 or 0),
            "terminal relief singleton contract")
        item.spec = clone(spec)
        return true, nil, { applied = true }
    end
    function instancePort:restore(_, item, snapshot)
        item.spec = clone(snapshot.spec)
        return true
    end
    function instancePort:cleanupEscapedRelief()
        return self.removedEscaped
    end
    function instancePort:inspect(_, item, expected)
        return {
            capacityApplied = item.spec and item.spec.capacity == expected.capacity,
            reductionApplied = item.spec and item.spec.reduction == expected.reduction,
            reliefApplied = item.spec and item.spec.reliefOffset == expected.reliefOffset,
        }
    end
    function instancePort:health() return true end

    local audit = { rows = {} }
    function audit:record(_, action, data)
        self.rows[#self.rows + 1] = { action = action, data = clone(data) }
        return true
    end
    function audit:health() return true end

    local walletPort = wallet(initialBalance or 100000)
    local config = {}
    function config:snapshot() return { enabled = true } end
    function config:health() return true end
    local module = GodSystemTerminalFeatureModule.create({
        ["terminal.config"] = dotPort(config),
        ["terminal.state"] = dotPort(statePort),
        ["terminal.instances"] = dotPort(instancePort),
        wallet = dotPort(walletPort),
        operations = sharedOperations or operationsPort(),
        ["terminal.audit"] = dotPort(audit),
    })
    return module, statePort, instancePort, walletPort, audit
end

do
    local Rules = GodSystemTerminalFeatureRules
    local state = Rules.normalizeState({})
    expect(Rules.value(state, "capacity") == 10, "terminal initial capacity")
    expect(Rules.value(state, "reduction") == 50, "terminal initial reduction")
    expect(Rules.value(state, "relief") == 0, "terminal initial relief")
    expect(Rules.recoveryCost(state) == 10, "terminal initial recovery tier")
    state.capacityLevel = 7
    state.reductionLevel = 2
    state.reliefLevel = 400
    expect(Rules.recoveryCost(state) == 80, "terminal recovery ignores relief but follows capacity")
    local spec = Rules.spec(state)
    expect(spec.reliefOffset == 2000 and spec.reliefActualWeight == -2000,
        "terminal relief max contract")
    expect(spec.reliefCount == 1 and spec.reliefHungChange == 20,
        "terminal relief lifecycle contract")
end

do
    local module, statePort, instances, walletPort = terminalEnvironment({}, 10000)
    expect(module:start() == true, "terminal starts")
    local claim = module.public.claim({
        actor = "alice", operationId = "terminal-claim",
    })
    expect(claim.ok and claim.code == "TerminalClaimed", "terminal first claim")
    expect(walletPort.charges == 0 and instances.item ~= nil, "terminal first claim free")
    expect(instances.item.spec.capacity == 10 and instances.item.spec.reduction == 50,
        "terminal claim applies instance")

    local capacity = module.public.upgrade({
        actor = "alice", operationId = "terminal-capacity-1",
        upgradeType = "capacity",
    })
    expect(capacity.ok and capacity.data.level == 2 and capacity.data.value == 15,
        "terminal capacity upgrade")
    expect(walletPort.charges == 60 and instances.item.spec.capacity == 15,
        "terminal capacity price and instance")
    local replay = module.public.upgrade({
        actor = "alice", operationId = "terminal-capacity-1",
        upgradeType = "capacity",
    })
    expect(replay.ok and walletPort.charges == 60
        and statePort.value.capacityLevel == 2, "terminal upgrade idempotency")

    local reduction = module.public.upgrade({
        actor = "alice", operationId = "terminal-reduction-1",
        upgradeType = "reduction",
    })
    expect(reduction.ok and reduction.data.value == 55, "terminal reduction upgrade")
    local relief = module.public.upgrade({
        actor = "alice", operationId = "terminal-relief-1",
        upgradeType = "relief",
    })
    expect(relief.ok and relief.data.value == 5
        and instances.item.spec.reliefCount == 1, "terminal relief upgrade")
    expect(walletPort.charges == 60 + 100 + 2000, "terminal independent upgrade costs")

    instances.item = nil
    local recovered = module.public.recover({
        actor = "alice", operationId = "terminal-recover",
    })
    expect(recovered.ok and recovered.data.cost == 10, "terminal recovery tier")
    expect(walletPort.charges == 2170, "terminal recovery charged")
end

do
    local module, statePort, instances, walletPort = terminalEnvironment({
        claimedOnce = true,
        capacityLevel = 1,
        reductionLevel = 1,
        reliefLevel = 0,
    }, 1000)
    module:start()
    local claimed = module.public.claim({
        actor = "bob", operationId = "terminal-rollback-seed",
    })
    expect(claimed.ok, "terminal rollback seed")
    local before = walletPort.balance
    instances.failApply = true
    local failed = module.public.upgrade({
        actor = "bob", operationId = "terminal-apply-fail",
        upgradeType = "capacity",
    })
    expect(not failed.ok and failed.code == "applyFailed", "terminal apply failure surfaced")
    expect(walletPort.balance == before and statePort.value.capacityLevel == 1,
        "terminal apply failure does not charge or advance")
end

do
    local shared = operationsPort()
    local first, _, firstInstances = terminalEnvironment({}, 1000, shared)
    local second, _, secondInstances = terminalEnvironment({}, 1000, shared)
    local alice = { getUsername = function() return "alice" end }
    local bob = { getUsername = function() return "bob" end }
    first:start()
    second:start()
    local firstResult = first.public.claim({
        actor = alice, operationId = "same-terminal-operation",
    })
    local secondResult = second.public.claim({
        actor = bob, operationId = "same-terminal-operation",
    })
    expect(firstResult.ok and secondResult.ok
        and firstInstances.item ~= nil and secondInstances.item ~= nil,
        "terminal same operation id is isolated by player")
end

local function storageEnvironment(options)
    options = options or {}
    local actor = "alice"
    local root = { id = "player-root", rows = {}, failAdd = false }
    local objectById = {}
    local objectOrder = {}
    local function addObject(id, x, y, slots)
        local object = {
            objectId = id,
            x = x,
            y = y,
            z = 0,
            sprite = "sprite_" .. id,
            name = id,
            marker = nil,
            coreMarker = nil,
            settingsRows = {},
            slotsRows = slots or {},
            loaded = true,
        }
        objectById[id] = object
        objectOrder[#objectOrder + 1] = object
        return object
    end
    local function container(id)
        return {
            id = id,
            rows = {},
            capacityValue = 100000,
            failAdd = false,
            failRemove = false,
            coldValue = false,
            poweredValue = false,
        }
    end
    local hostContainer = container("host-slot")
    local host = addObject("host", 0, 0, {
        { slotIndex = 0, name = "Core host", type = "crate", container = hostContainer },
    })
    host.marker = {
        enabled = true, objectId = "host", scopeKey = "personal:alice",
        owner = actor, name = "Core host", markedAtMs = 1,
    }
    host.coreMarker = {
        installed = true, networkId = "network-1", token = "token-1",
        objectId = "host",
    }

    local statePort = {
        value = {
            networkId = "network-1",
            scopeKey = "personal:alice",
            owner = actor,
            coreClaimedOnce = true,
            coreToken = "token-1",
            coreState = "installed",
            coreHost = { objectId = "host", x = 0, y = 0, z = 0 },
            knownObjects = {
                host = { objectId = "host", x = 0, y = 0, z = 0, slots = {
                    { slotIndex = 0, name = "Core host", type = "crate" },
                } },
            },
            revision = 0,
        },
        revision = 0,
    }
    function statePort:load(_, selector)
        if selector and selector.networkId
            and tostring(selector.networkId) ~= tostring(self.value.networkId)
        then return nil, self.revision end
        return clone(self.value), self.revision
    end
    function statePort:create(_, value)
        self.value = clone(value)
        return clone(self.value), self.revision
    end
    function statePort:commit(_, value, expected)
        if expected ~= self.revision then return false, "revisionConflict" end
        self.value = clone(value)
        self.revision = self.revision + 1
        return true, nil, self.revision
    end
    function statePort:health() return true end

    local objectsPort = {}
    function objectsPort:actorPosition() return { x = 0, y = 0, z = 0 } end
    function objectsPort:scope() return { key = "personal:alice", kind = "personal", owner = actor } end
    function objectsPort:resolve(reference)
        local object = objectById[tostring(reference and reference.objectId or "")]
        if not object then return nil, "squareUnloaded" end
        if object.loaded == false then return nil, "squareUnloaded" end
        return object
    end
    function objectsPort:adjacent(object)
        local result = {}
        for index = 1, #objectOrder do
            local candidate = objectOrder[index]
            if candidate.loaded ~= false and candidate ~= object
                and GodSystemStorageFeatureRules.isAdjacent(object, candidate)
            then
                result[#result + 1] = candidate
            end
        end
        return result
    end
    function objectsPort:slots(object) return object.slotsRows end
    function objectsPort:marker(object) return object.marker end
    function objectsPort:setMarker(object, marker)
        object.marker = clone(marker)
        return true
    end
    function objectsPort:clearMarker(object)
        object.marker = nil
        object.settingsRows = {}
        return true
    end
    function objectsPort:settings(object, slotIndex)
        return clone(object.settingsRows[tostring(slotIndex)] or {
            role = "general", priorityTier = "normal", assignedOrder = 0,
        })
    end
    function objectsPort:setSettings(object, slotIndex, settings)
        object.settingsRows[tostring(slotIndex)] = clone(settings)
        return true
    end
    function objectsPort:coreMarker(object) return object.coreMarker end
    function objectsPort:installCore(object, networkId, token)
        if object.coreMarker then return false, "coreInstalled" end
        object.coreMarker = {
            installed = true, networkId = networkId, token = token,
            objectId = object.objectId,
        }
        return true
    end
    function objectsPort:removeCore(object, token)
        if not object.coreMarker or object.coreMarker.token ~= token then
            return false, "coreExpired"
        end
        local marker = object.coreMarker
        object.coreMarker = nil
        return true, marker
    end
    function objectsPort:health() return true end

    local grounded = {}
    local containersPort = {}
    function containersPort:list(value) return value.rows end
    function containersPort:child(item) return item.child end
    function containersPort:contains(value, item)
        for index = 1, #value.rows do if value.rows[index] == item then return true end end
        return false
    end
    function containersPort:accepts(value)
        if value.reject then return false, "notAllowed" end
        if value.full then return false, "full" end
        return true
    end
    function containersPort:remove(value, item)
        if value.failRemove then return false end
        for index = 1, #value.rows do
            if value.rows[index] == item then table.remove(value.rows, index); return true end
        end
        return false
    end
    function containersPort:add(value, item)
        if value.failAdd then return false end
        value.rows[#value.rows + 1] = item
        return true
    end
    function containersPort:playerContainer(_, itemId)
        if itemId and itemId ~= "" then return nil, "targetMissing" end
        return root
    end
    function containersPort:ground(_, _, item)
        grounded[#grounded + 1] = item
        return true
    end
    function containersPort:capacity(value) return value.capacityValue end
    function containersPort:used(value) return #value.rows end
    function containersPort:cold(value) return value.coldValue end
    function containersPort:powered(value) return value.poweredValue end
    function containersPort:health() return true end

    local itemsPort = {}
    function itemsPort:id(item) return item.id end
    function itemsPort:describe(item, link)
        return {
            id = item.id,
            groupKey = item.fullType,
            fullType = item.fullType,
            name = item.name or item.fullType,
            modName = item.modName or "Base",
            category = item.category or "other",
            weight = item.weight or 1,
            conditionRatio = item.conditionRatio or 1,
            usedDelta = item.usedDelta or 1,
            spoilageRemaining = item.spoilageRemaining or 1000000000,
            states = item.states or {},
            tags = item.tags or {},
            sourceLinkId = link.linkId,
            sourceName = link.name,
        }
    end
    function itemsPort:category(item) return item.category or "other" end
    function itemsPort:isProtected(item) return item.protected == true end
    function itemsPort:canDeposit(_, item)
        if item.protected then return false, "protected" end
        return true
    end
    function itemsPort:health() return true end

    local corePort = { item = nil, nextId = 1 }
    function corePort:find(_, networkId, token, expectedId)
        if self.item and self.item.networkId == networkId and self.item.token == token
            and (not expectedId or expectedId == self.item.id)
        then return self.item end
        return nil, "coreMissing"
    end
    function corePort:create(_, networkId, token, fullType)
        self.item = {
            id = "core-" .. tostring(self.nextId), networkId = networkId,
            token = token, fullType = fullType,
        }
        self.nextId = self.nextId + 1
        return self.item
    end
    function corePort:remove(_, item)
        if self.item ~= item then return false, "coreMissing" end
        self.item = nil
        return true, { item = item }
    end
    function corePort:restore(_, item)
        self.item = item
        return true
    end
    function corePort:cleanupDuplicates() return 0 end
    function corePort:health() return true end

    local permissions = {}
    function permissions:canUse() return true end
    function permissions:canManage() return true end
    function permissions:withinRange() return true end
    function permissions:isAdmin() return true end
    function permissions:identity(actor)
        if type(actor) == "table" and actor.getUsername then
            return actor:getUsername()
        end
        return tostring(actor or "")
    end
    function permissions:health() return true end

    local clock = { value = 1000 }
    function clock:nowMs() return self.value end

    local sync = { added = 0, removed = 0, objects = 0, states = 0 }
    function sync:object() self.objects = self.objects + 1; return true end
    function sync:add() self.added = self.added + 1; return true end
    function sync:remove() self.removed = self.removed + 1; return true end
    function sync:state() self.states = self.states + 1; return true end
    function sync:health() return true end

    local audit = { rows = {} }
    function audit:record(_, action, data)
        self.rows[#self.rows + 1] = { action = action, data = clone(data) }
        return true
    end
    function audit:health() return true end

    local walletPort = wallet(options.balance or 100000)
    local config = {}
    function config:snapshot()
        return {
            enabled = true,
            maxNodes = 128,
            maxDepth = 32,
            maxIndexedItems = 20000,
            indexBatchItems = 250,
            indexBudgetMs = 2,
            coreRecoveryCost = 2000,
            coreUseDistance = 3.5,
            manageDistance = 2.5,
        }
    end
    function config:health() return true end
    local module = GodSystemStorageFeatureModule.create({
        ["storage.config"] = dotPort(config),
        ["storage.state"] = dotPort(statePort),
        ["storage.objects"] = dotPort(objectsPort),
        ["storage.containers"] = dotPort(containersPort),
        ["storage.items"] = dotPort(itemsPort),
        ["storage.core"] = dotPort(corePort),
        ["storage.permissions"] = dotPort(permissions),
        ["storage.clock"] = dotPort(clock),
        ["storage.sync"] = dotPort(sync),
        wallet = dotPort(walletPort),
        operations = options.operations or operationsPort(),
        ["storage.audit"] = dotPort(audit),
    })
    return {
        module = module,
        actor = actor,
        root = root,
        host = host,
        addObject = addObject,
        container = container,
        objects = objectById,
        state = statePort,
        containers = containersPort,
        items = itemsPort,
        core = corePort,
        wallet = walletPort,
        grounded = grounded,
        sync = sync,
        audit = audit,
    }
end

do
    local Rules = GodSystemStorageFeatureRules
    local routes = Rules.routeCandidates({
        {
            linkId = "general-high", role = "general", priorityTier = "highest",
            assignedOrder = 1, available = true,
        },
        {
            linkId = "material-low", role = "material", priorityTier = "lowest",
            assignedOrder = 2, available = true,
        },
        {
            linkId = "material-high", role = "material", priorityTier = "highest",
            assignedOrder = 3, available = true,
        },
    }, "material", false)
    expect(routes[1].linkId == "material-high"
        and routes[2].linkId == "material-low"
        and routes[3].linkId == "general-high",
        "specific role wins before general and priority wins inside role")
    local filtered = Rules.routeCandidates({
        {
            linkId = "allow", role = "general", priorityTier = "normal",
            allowCategories = { medical = true }, available = true,
        },
        {
            linkId = "deny", role = "material", priorityTier = "highest",
            denyCategories = { material = true }, available = true,
        },
    }, "material", false)
    expect(#filtered == 0, "allow/deny rules are enforced")
    expect(Rules.isAdjacent({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }),
        "orthogonal adjacency")
    expect(not Rules.isAdjacent({ x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 0 }),
        "diagonal is not adjacent")
    expect(Rules.isAdjacent({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }),
        "same-square stacked furniture adjacency")
end

do
    local env = storageEnvironment()
    local module = env.module
    module:start()
    local materialContainer = env.container("materials")
    local materialSecondSlot = env.container("materials-second-slot")
    local generalContainer = env.container("general")
    local materialObject = env.addObject("materials-object", 1, 0, {
        { slotIndex = 0, name = "Material crate", type = "crate", container = materialContainer },
        { slotIndex = 1, name = "Material shelf", type = "shelf", container = materialSecondSlot },
    })
    local generalObject = env.addObject("general-object", -1, 0, {
        { slotIndex = 0, name = "General crate", type = "crate", container = generalContainer },
    })
    for _, object in ipairs({ materialObject, generalObject }) do
        object.marker = {
            enabled = true, objectId = object.objectId, scopeKey = "personal:alice",
            owner = "alice", name = object.name, markedAtMs = 2,
        }
        env.state.value.knownObjects[object.objectId] = {
            objectId = object.objectId, x = object.x, y = object.y, z = 0,
            name = object.name, slots = {
                { slotIndex = 0, name = object.name, type = "crate" },
            },
        }
    end
    materialObject.settingsRows["0"] = {
        role = "general", priorityTier = "normal", assignedOrder = 2,
    }
    generalObject.settingsRows["0"] = {
        role = "general", priorityTier = "highest", assignedOrder = 1,
    }
    local configured = module.public.execute({
        actor = "alice", operationId = "storage-update-material",
        action = "updateContainer", networkId = "network-1",
        linkId = "node:materials-object:0",
        role = "material", priorityTier = "lowest",
    })
    expect(configured.ok
        and materialObject.settingsRows["0"].role == "material"
        and materialObject.settingsRows["0"].priorityTier == "lowest",
        "right-click container role and priority persist through object settings port")
    local plank = { id = "plank-1", fullType = "Base.Plank", category = "material" }
    env.root.rows[1] = plank
    local deposited = module.public.deposit({
        actor = "alice", operationId = "storage-deposit-material",
        networkId = "network-1", mode = "selected", itemIds = { "plank-1" },
    })
    expect(deposited.ok and materialContainer.rows[1] == plank,
        "deposit follows recognized system category and specific role: "
            .. tostring(deposited.code) .. "/"
            .. tostring(deposited.data and deposited.data.failedItems
                and deposited.data.failedItems[1]
                and deposited.data.failedItems[1].reason))
    expect(#generalContainer.rows == 0, "general container remains fallback")
    local replay = module.public.deposit({
        actor = "alice", operationId = "storage-deposit-material",
        networkId = "network-1", mode = "selected", itemIds = { "plank-1" },
    })
    expect(replay.ok and #materialContainer.rows == 1,
        "storage deposit operation id prevents duplicate movement")

    local indexStarted = module.public.startIndex({
        actor = "alice", networkId = "network-1",
    })
    expect(indexStarted.ok, "storage index starts")
    for _ = 1, 10 do module.public.processJobs() end
    local snapshot = module.public.snapshot(indexStarted.data.snapshotId)
    expect(snapshot and snapshot.itemCount == 1 and snapshot.groupCount == 1
        and #snapshot.containers == 3,
        "storage index summarizes connected items")
    local snapshotResult = module.public.requestSnapshot({
        actor = "alice",
        snapshotId = snapshot.snapshotId,
    })
    expect(snapshotResult.ok and snapshotResult.code == "StorageSnapshot"
        and snapshotResult.data.itemCount == 1,
        "storage snapshot request envelope")
    local detailResult = module.public.requestInstanceDetails({
        actor = "alice",
        snapshotId = snapshot.snapshotId,
        groupKey = "Base.Plank",
    })
    expect(detailResult.ok and detailResult.code == "StorageDetails"
        and #detailResult.data.instances == 1,
        "storage details request envelope")
    local withdrawn = module.public.withdraw({
        actor = "alice", operationId = "storage-withdraw",
        networkId = "network-1", snapshotId = snapshot.snapshotId,
        requests = { { groupKey = "Base.Plank", count = 1 } },
    })
    expect(withdrawn.ok and env.root.rows[#env.root.rows] == plank,
        "storage withdraw uses snapshot then revalidates live item")
end

do
    local env = storageEnvironment()
    local module = env.module
    module:start()
    local retrieved = module.public.retrieveCore({
        actor = "alice", operationId = "storage-core-retrieve",
        networkId = "network-1",
    })
    expect(retrieved.ok and env.host.coreMarker == nil and env.core.item ~= nil,
        "storage core retrieve restores inventory item")
    expect(env.state.value.coreState == "kit"
        and env.state.value.coreHost == nil, "storage core retrieve state")

    local installed = module.public.installCore({
        actor = "alice", operationId = "storage-core-install",
        networkId = "network-1", objectId = "host", x = 0, y = 0, z = 0,
        coreItemId = env.core.item.id,
    })
    expect(installed.ok and env.host.coreMarker ~= nil and env.core.item == nil,
        "storage core installs into marked network container")
    expect(env.host.coreMarker.networkId == "network-1"
        and env.host.coreMarker.token == env.state.value.coreToken,
        "storage core identity survives install lifecycle")
end

do
    local env = storageEnvironment()
    local module = env.module
    module:start()
    local source = env.container("organizer-general")
    local target = env.container("organizer-material")
    local sourceObject = env.addObject("organizer-source", -1, 0, {
        { slotIndex = 0, name = "General", type = "crate", container = source },
    })
    local targetObject = env.addObject("organizer-target", 1, 0, {
        { slotIndex = 0, name = "Material", type = "crate", container = target },
    })
    for _, object in ipairs({ sourceObject, targetObject }) do
        object.marker = {
            enabled = true, objectId = object.objectId, scopeKey = "personal:alice",
            owner = "alice", name = object.name, markedAtMs = 2,
        }
        env.state.value.knownObjects[object.objectId] = {
            objectId = object.objectId, x = object.x, y = object.y, z = 0,
            name = object.name, slots = {
                { slotIndex = 0, name = object.name, type = "crate" },
            },
        }
    end
    sourceObject.settingsRows["0"] = {
        role = "general", priorityTier = "highest", assignedOrder = 1,
    }
    targetObject.settingsRows["0"] = {
        role = "material", priorityTier = "lowest", assignedOrder = 2,
    }
    local item = {
        id = "organizer-plank", fullType = "Base.Plank", category = "material",
    }
    source.rows[1] = item
    local started = module.public.execute({
        actor = "alice", operationId = "storage-organizer",
        action = "startOrganizer", networkId = "network-1",
    })
    expect(started.ok and started.code == "StorageOrganizerStarted",
        "storage organizer starts as bounded job")
    for _ = 1, 10 do module.public.processJobs() end
    expect(#source.rows == 0 and target.rows[1] == item,
        "organizer moves system-classified item to matching role")
    local replay = module.public.execute({
        actor = "alice", operationId = "storage-organizer",
        action = "startOrganizer", networkId = "network-1",
    })
    expect(replay.ok and replay.code == "StorageOrganizerCompleted",
        "completed organizer operation replays final result")
end

do
    local env = storageEnvironment({ balance = 5000 })
    local module = env.module
    env.host.coreMarker = nil
    env.state.value.coreState = "missing"
    env.state.value.coreHost = nil
    module:start()
    local recovered = module.public.claimCore({
        actor = "alice", operationId = "storage-core-recover",
        networkId = "network-1", forceRecovery = true,
    })
    expect(recovered.ok and recovered.data.cost == 2000,
        "storage lost core recovery fixed price")
    expect(env.wallet.balance == 3000 and env.core.item ~= nil,
        "storage recovery charges once and creates one core")
    local replay = module.public.claimCore({
        actor = "alice", operationId = "storage-core-recover",
        networkId = "network-1", forceRecovery = true,
    })
    expect(replay.ok and env.wallet.balance == 3000,
        "storage core recovery operation id is idempotent")
end

do
    local shared = operationsPort()
    local first = storageEnvironment({ operations = shared })
    local second = storageEnvironment({ operations = shared })
    local alice = { getUsername = function() return "alice" end }
    local bob = { getUsername = function() return "bob" end }
    first.module:start()
    second.module:start()
    local firstResult = first.module.public.retrieveCore({
        actor = alice, operationId = "same-storage-operation",
        networkId = "network-1",
    })
    local secondResult = second.module.public.retrieveCore({
        actor = bob, operationId = "same-storage-operation",
        networkId = "network-1",
    })
    expect(firstResult.ok and secondResult.ok
        and first.core.item ~= nil and second.core.item ~= nil,
        "storage same operation id is isolated by player")
end

do
    local env = storageEnvironment()
    local module = env.module
    module:start()
    local targetContainer = env.container("failing-target")
    targetContainer.failAdd = true
    local targetObject = env.addObject("failing-object", 1, 0, {
        { slotIndex = 0, name = "Failing crate", type = "crate", container = targetContainer },
    })
    targetObject.marker = {
        enabled = true, objectId = targetObject.objectId, scopeKey = "personal:alice",
        owner = "alice", name = targetObject.name, markedAtMs = 2,
    }
    targetObject.settingsRows["0"] = {
        role = "material", priorityTier = "highest", assignedOrder = 1,
    }
    env.state.value.knownObjects[targetObject.objectId] = {
        objectId = targetObject.objectId, x = 1, y = 0, z = 0,
        name = targetObject.name, slots = {
            { slotIndex = 0, name = targetObject.name, type = "crate" },
        },
    }
    local item = { id = "restore-1", fullType = "Base.Nails", category = "material" }
    env.root.rows[1] = item
    env.root.failAdd = true
    local failed = module.public.deposit({
        actor = "alice", operationId = "storage-ground-restore",
        networkId = "network-1", mode = "selected", itemIds = { "restore-1" },
    })
    expect(not failed.ok and failed.data.failedItems[1].reason == "restoredToGround",
        "storage transfer reports third-level recovery")
    expect(env.grounded[1] == item, "storage transfer never silently deletes item")
end

do
    local env = storageEnvironment()
    local module = env.module
    module:start()
    local rowsPerNode = 158
    for nodeIndex = 1, 127 do
        local value = env.container("stress-" .. tostring(nodeIndex))
        for itemIndex = 1, rowsPerNode do
            value.rows[#value.rows + 1] = {
                id = "stress-" .. tostring(nodeIndex) .. "-" .. tostring(itemIndex),
                fullType = "Base.Stress" .. tostring(itemIndex % 10),
                category = "material",
            }
        end
        local object = env.addObject("stress-object-" .. tostring(nodeIndex),
            nodeIndex, 0, {
                { slotIndex = 0, name = "Stress crate", type = "crate", container = value },
            })
        object.marker = {
            enabled = true, objectId = object.objectId, scopeKey = "personal:alice",
            owner = "alice", name = object.name, markedAtMs = nodeIndex + 1,
        }
        object.settingsRows["0"] = {
            role = "material", priorityTier = "normal", assignedOrder = nodeIndex,
        }
        env.state.value.knownObjects[object.objectId] = {
            objectId = object.objectId, x = nodeIndex, y = 0, z = 0,
            name = object.name, slots = {
                { slotIndex = 0, name = object.name, type = "crate" },
            },
        }
    end
    env.state.value.knownObjects.offline = {
        objectId = "offline", x = 1000, y = 1000, z = 0,
        name = "Offline crate", slots = {
            { slotIndex = 0, name = "Offline crate", type = "crate" },
        },
    }
    local started = module.public.startIndex({
        actor = "alice", networkId = "network-1", allowRemote = true,
    })
    expect(started.ok, "stress index starts")
    local calls = 0
    while not module.public.snapshot(started.data.snapshotId) and calls < 100 do
        local progress = module.public.processJobs()
        expect(progress.indexJobs <= 2, "bounded number of index jobs per call")
        calls = calls + 1
    end
    local snapshot = module.public.snapshot(started.data.snapshotId)
    expect(snapshot ~= nil, "stress snapshot completes")
    expect(snapshot.itemCount == 20000 and snapshot.incomplete == true,
        "storage index enforces twenty-thousand item boundary")
    expect(snapshot.onlineLinks == 127 and snapshot.offlineLinks == 1,
        "storage supports 128 physical nodes and reports unloaded object")
    expect(calls >= 80, "storage index is split into batches of at most 250 items")
end

print("Test-GodSystemV422012TerminalStorageModuleRuntime passed")
