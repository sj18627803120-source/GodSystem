local luaRoot = assert(arg and arg[1], "Lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/init.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    package.path,
}, ";")

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local nextItemId = 100
local function newContainer(typeName, capacity)
    local value = {
        rows = {}, typeName = typeName or "container", capacity = capacity or 50,
        reduction = 0, contentsWeight = 0, allowed = true, room = true,
        addEnabled = true, removeEnabled = true, drawDirty = false,
    }
    function value:getItems() return javaList(self.rows) end
    function value:getType() return self.typeName end
    function value:getCapacity() return self.capacity end
    function value:setCapacity(nextValue) self.capacity = nextValue end
    function value:getWeightReduction() return self.reduction end
    function value:setWeightReduction(nextValue) self.reduction = nextValue end
    function value:getContentsWeight() return self.contentsWeight end
    function value:isItemAllowed() return self.allowed end
    function value:hasRoomFor() return self.room end
    function value:setDrawDirty(nextValue) self.drawDirty = nextValue end
    function value:getContainingItem() return self.containingItem end
    function value:AddItem(item)
        if not self.addEnabled then error("add disabled") end
        if type(item) == "string" then item = _G.__newItem(item) end
        self.rows[#self.rows + 1] = item
        item.container = self
        return item
    end
    function value:Remove(item)
        if not self.removeEnabled then error("remove disabled") end
        for index = 1, #self.rows do
            if self.rows[index] == item then
                table.remove(self.rows, index)
                item.container = nil
                return
            end
        end
    end
    return value
end

local function newItem(fullType, options)
    options = options or {}
    nextItemId = nextItemId + 1
    local item = {
        id = options.id or nextItemId,
        fullType = fullType,
        displayName = options.displayName or fullType,
        displayCategory = options.displayCategory or "Other",
        typeName = options.typeName or fullType:match("%.([^%.]+)$") or fullType,
        category = options.category or options.displayCategory or "Other",
        modData = {},
        actualWeight = options.weight or 1,
        customWeight = false,
        hungChange = 0,
        favorite = options.favorite == true,
        unwanted = false,
        condition = options.condition or 100,
        conditionMax = options.conditionMax or 100,
        usedDelta = options.usedDelta or 1,
        age = options.age or 0,
        offAge = options.offAge == nil and -1 or options.offAge,
        worldSprite = options.worldSprite or "",
        food = options.food == true,
        bodyLocation = options.bodyLocation,
        aimedFirearm = options.aimedFirearm == true,
    }
    if options.containerType then
        item.child = newContainer(options.containerType, options.capacity or 20)
        item.child.containingItem = item
    end
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getDisplayName() return self.displayName end
    function item:getName() return self.displayName end
    function item:setName(value) self.displayName = value end
    function item:isCustomName() return self.customName == true end
    function item:setCustomName(value) self.customName = value == true end
    function item:getDisplayCategory() return self.displayCategory end
    function item:getCategory() return self.category end
    function item:getType() return self.typeName end
    function item:getModData() return self.modData end
    function item:getInventory() return self.child end
    function item:getContainer() return self.container end
    function item:getCapacity() return self.capacity or 20 end
    function item:setCapacity(value) self.capacity = value end
    function item:getWeightReduction() return self.reduction or 0 end
    function item:setWeightReduction(value) self.reduction = value end
    function item:getActualWeight() return self.actualWeight end
    function item:getWeight() return self.actualWeight end
    function item:setActualWeight(value) self.actualWeight = value end
    function item:isCustomWeight() return self.customWeight end
    function item:setCustomWeight(value) self.customWeight = value == true end
    function item:getHungChange() return self.hungChange end
    function item:setHungChange(value) self.hungChange = value end
    function item:isFavorite() return self.favorite end
    function item:setFavorite(value) self.favorite = value == true end
    function item:isUnwanted() return self.unwanted end
    function item:setUnwanted(_, value)
        if value == nil then value = _ end
        self.unwanted = value == true
    end
    function item:getCondition() return self.condition end
    function item:getConditionMax() return self.conditionMax end
    function item:getUsedDelta() return self.usedDelta end
    function item:getAge() return self.age end
    function item:getOffAge() return self.offAge end
    function item:isRotten() return options.rotten == true end
    function item:isStale() return options.stale == true end
    function item:isFrozen() return options.frozen == true end
    function item:isCooked() return options.cooked == true end
    function item:isCooking() return options.cooking == true end
    function item:isAimedFirearm() return self.aimedFirearm end
    function item:getBodyLocation() return self.bodyLocation end
    function item:getWorldSprite() return self.worldSprite end
    function item:transmitModData() self.transmitted = (self.transmitted or 0) + 1 end
    function item:getScriptItem()
        return {
            getModule = function()
                return { getName = function() return fullType:match("^([^%.]+)") end }
            end,
            getTags = function() return javaList(options.tags or {}) end,
        }
    end
    return item
end
_G.__newItem = function(fullType)
    if fullType == "GodSystem.SystemSpaceTerminal" then
        return newItem(fullType, { containerType = "terminal", capacity = 10 })
    end
    return newItem(fullType)
end

local function newSquare(x, y, z)
    local square = { x = x, y = y, z = z, objects = {}, grounded = {} }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getObjects() return javaList(self.objects) end
    function square:getSpecialObjects() return javaList(self.objects) end
    function square:getWorldObjects() return javaList({}) end
    function square:AddWorldInventoryItem(item)
        self.grounded[#self.grounded + 1] = item
        return item
    end
    return square
end

local function newWorldObject(square, name, containers)
    local object = {
        square = square, name = name, containers = containers or {},
        modData = {}, transmitted = 0,
    }
    square.objects[#square.objects + 1] = object
    function object:getSquare() return self.square end
    function object:getModData() return self.modData end
    function object:getObjectName() return self.name end
    function object:getContainerCount() return #self.containers end
    function object:getContainerByIndex(index) return self.containers[index + 1] end
    function object:getContainer() return self.containers[1] end
    function object:getSprite()
        return { getName = function() return "sprite_" .. name end }
    end
    function object:transmitModData() self.transmitted = self.transmitted + 1 end
    return object
end

local rootInventory = newContainer("player", 100)
local actorSquare = newSquare(0, 0, 0)
local actor = {
    username = "alice", inventory = rootInventory, square = actorSquare,
    primary = nil, secondary = nil, worn = {}, attached = {},
}
function actor:getUsername() return self.username end
function actor:getInventory() return self.inventory end
function actor:getSquare() return self.square end
function actor:getX() return self.square.x end
function actor:getY() return self.square.y end
function actor:getZ() return self.square.z end
function actor:getPrimaryHandItem() return self.primary end
function actor:getSecondaryHandItem() return self.secondary end
function actor:getWornItems() return javaList(self.worn) end
function actor:getAttachedItems() return javaList(self.attached) end
function actor:getAccessLevel() return "" end
function actor:isEquipped(item) return item == self.primary or item == self.secondary end

local otherActor = {
    username = "bob", inventory = newContainer("other", 100), square = actorSquare,
}
function otherActor:getUsername() return self.username end
function otherActor:getInventory() return self.inventory end
function otherActor:getSquare() return self.square end
function otherActor:getX() return self.square.x end
function otherActor:getY() return self.square.y end
function otherActor:getZ() return self.square.z end
function otherActor:getAccessLevel() return "" end

local syncCounts = { add = 0, remove = 0, object = 0, state = 0 }
local binding = {
    identity = function(value) return value.username end,
    instanceof = function(item, className)
        return className == "Food" and item.food == true
    end,
    sendAddItemToContainer = function()
        syncCounts.add = syncCounts.add + 1
        return true
    end,
    sendRemoveItemFromContainer = function()
        syncCounts.remove = syncCounts.remove + 1
        return true
    end,
    transmitStorageState = function()
        syncCounts.state = syncCounts.state + 1
        return true
    end,
    createItem = function(fullType) return newItem(fullType) end,
}

do
    require "GodSystem/Platform/Terminal/Config"
    require "GodSystem/Platform/Terminal/State"
    require "GodSystem/Platform/Terminal/Audit"
    require "GodSystem/Platform/Terminal/Instances"

    local context = {
        state = { get = function() return {} end },
        configSnapshot = {
            AutoRecyclerFullType = "GodSystem.SystemSpaceTerminal",
            TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
            TerminalDisplayName = "System Space Terminal",
        },
        binding = binding,
    }
    local config = GodSystemTerminalConfigPlatform.create({}, context)
    local state = GodSystemTerminalStatePlatform.create({}, context)
    local audit = GodSystemTerminalAuditPlatform.create({}, context)
    local instances = GodSystemTerminalInstancesPlatform.create({}, context)
    config:start(); state:start(); audit:start(); instances:start()
    expect(config.public.snapshot().enabled == true, "terminal config adapter")
    local initial, revision = state.public.load(actor)
    expect(type(initial) == "table" and revision == 0, "terminal scoped state load")
    expect(state.public.commit(actor, { capacityLevel = 1 }, revision) == true,
        "terminal scoped state commit")
    expect(audit.public.record(actor, "adapterTest", {}) == true,
        "terminal audit adapter")

    local terminal = instances.public.create(actor,
        "GodSystem.SystemSpaceTerminal")
    expect(terminal and instances.public.findOwned(actor, terminal:getID()) == terminal,
        "terminal exact owned instance resolution")
    expect(instances.public.findOwned(otherActor, terminal:getID()) == nil,
        "terminal instance ownership isolation")
    local before = instances.public.snapshot(actor, terminal)
    local spec = {
        capacity = 25, reduction = 80, reliefOffset = 10, reliefLevel = 2,
        capacityLevel = 4, reductionLevel = 6,
    }
    expect(instances.public.apply(actor, terminal, spec) == true,
        "terminal verified property application")
    local inspected = instances.public.inspect(actor, terminal, spec)
    expect(inspected.capacityApplied and inspected.reductionApplied
        and inspected.reliefApplied and inspected.reliefItemCount == 1,
        "terminal capacity reduction and singleton relief")
    expect(instances.public.apply(actor, terminal, spec) == true,
        "terminal repeated application")
    inspected = instances.public.inspect(actor, terminal, spec)
    expect(inspected.reliefItemCount == 1, "terminal relief does not duplicate")
    expect(instances.public.restore(actor, terminal, before) == true,
        "terminal snapshot rollback")

    local escaped = rootInventory:AddItem("GodSystem.SystemTerminalRelief")
    expect(escaped ~= nil
        and instances.public.cleanupEscapedRelief(actor, terminal) == 1,
        "terminal escaped relief cleanup")
end

local squares = {}
local function squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end
local function addSquare(square)
    squares[squareKey(square.x, square.y, square.z)] = square
end
addSquare(actorSquare)
local eastSquare, diagonalSquare = newSquare(1, 0, 0), newSquare(1, 1, 0)
addSquare(eastSquare); addSquare(diagonalSquare)
binding.getSquare = function(x, y, z)
    return squares[squareKey(math.floor(x), math.floor(y), math.floor(z))]
end

local crateA = newWorldObject(actorSquare, "Wooden Crate", {
    newContainer("crate", 50),
})
local fridgeB = newWorldObject(eastSquare, "Fridge", {
    newContainer("fridge", 40), newContainer("freezer", 20),
})
local diagonalC = newWorldObject(diagonalSquare, "Diagonal Crate", {
    newContainer("crate", 50),
})
fridgeB.containers[1].powered = true
fridgeB.containers[1].isPowered = function(self) return self.powered end

do
    require "GodSystem/Platform/Storage/Config"
    require "GodSystem/Platform/Storage/State"
    require "GodSystem/Platform/Storage/Clock"
    require "GodSystem/Platform/Storage/Audit"
    require "GodSystem/Platform/Storage/Objects"
    require "GodSystem/Platform/Storage/Containers"
    require "GodSystem/Platform/Storage/Items"
    require "GodSystem/Platform/Storage/Core"
    require "GodSystem/Platform/Storage/Permissions"
    require "GodSystem/Platform/Storage/Sync"

    local storageRoot = {}
    local context = {
        state = { get = function() return storageRoot end },
        configSnapshot = {},
        binding = binding,
    }
    local config = GodSystemStorageConfigPlatform.create({}, context)
    local state = GodSystemStorageStatePlatform.create({}, context)
    local clock = GodSystemStorageClockPlatform.create({}, context)
    local audit = GodSystemStorageAuditPlatform.create({}, context)
    local objects = GodSystemStorageObjectsPlatform.create({}, context)
    local containers = GodSystemStorageContainersPlatform.create({}, context)
    local items = GodSystemStorageItemsPlatform.create({}, context)
    local core = GodSystemStorageCorePlatform.create({}, context)
    local permissions = GodSystemStoragePermissionsPlatform.create({}, context)
    local sync = GodSystemStorageSyncPlatform.create({}, context)
    for _, adapter in ipairs({
        config, state, clock, audit, objects, containers, items, core,
        permissions, sync,
    }) do
        expect(adapter:start() == true, "storage adapter starts")
    end
    expect(config.public.snapshot().maxNodes == 128, "storage config limits")
    expect(type(clock.public.nowMs()) == "number", "storage clock")
    expect(audit.public.record(actor, "adapterTest", {}) == true, "storage audit")

    local scope = objects.public.scope(actor, objects.public.actorPosition(actor))
    expect(scope.key == "personal:alice", "personal storage scope")
    local firstReference = objects.public.reference(crateA, true)
    expect(firstReference and firstReference.objectId ~= ""
        and crateA.transmitted == 1,
        "first interaction assigns and synchronizes stable object id")
    expect(objects.public.setMarker(crateA, {
        scopeKey = scope.key, owner = "alice", name = "Wooden Crate",
        markedAtMs = 10,
    }) == true, "mark first network container")
    expect(objects.public.setMarker(fridgeB, {
        scopeKey = scope.key, owner = "alice", name = "Fridge",
        markedAtMs = 20,
    }) == true, "mark multi-slot network container")
    expect(objects.public.setMarker(diagonalC, {
        scopeKey = scope.key, owner = "alice", name = "Diagonal",
        markedAtMs = 30,
    }) == true, "mark diagonal container")

    local markerA = objects.public.marker(crateA)
    local refA = {
        objectId = markerA.objectId, x = 0, y = 0, z = 0,
    }
    local wrappedA = objects.public.resolve(refA)
    expect(wrappedA and wrappedA.objectId == markerA.objectId,
        "resolve exact stable object id")
    expect(#objects.public.slots(fridgeB) == 2, "multi-slot object adapter")
    local neighbors = objects.public.adjacent(wrappedA, scope.key)
    expect(#neighbors == 1
        and neighbors[1].objectId == objects.public.marker(fridgeB).objectId,
        "cardinal adjacency excludes diagonal")
    expect(objects.public.setSettings(fridgeB, 0, {
        role = "material", priorityTier = "highest",
        allowCategories = { material = true },
    }) == true, "persist routing settings")
    local settings = objects.public.settings(fridgeB, 0)
    expect(settings.role == "material" and settings.priorityTier == "highest"
        and settings.allowCategories.material == true,
        "read routing settings")
    expect(objects.public.installCore(crateA, "network-1", "token-1") == true,
        "install storage core marker")
    local coreMarker = objects.public.coreMarker(crateA)
    expect(coreMarker and coreMarker.capacityMode == "networkStorage",
        "core host has no capacity lock mode")
    local removed, coreReceipt = objects.public.removeCore(crateA, "token-1")
    expect(removed and coreReceipt.networkId == "network-1",
        "remove core host marker")

    local unloaded, unloadedCode = objects.public.resolve({
        objectId = "missing", x = 99, y = 99, z = 0,
    })
    expect(unloaded == nil and unloadedCode == "squareUnloaded",
        "unloaded square is not treated as destroyed")
    local savedRows = actorSquare.objects
    actorSquare.objects = {}
    local missing, missingCode = objects.public.resolve(refA)
    expect(missing == nil and missingCode == "objectMissing",
        "same coordinates cannot replace stable object")
    actorSquare.objects = savedRows

    local material = newItem("Base.Plank", {
        displayName = "Plank", displayCategory = "Material", weight = 3,
        tags = { "Material" },
    })
    local food = newItem("Base.Apple", {
        displayName = "Apple", displayCategory = "Food", food = true,
        age = 1, offAge = 5,
    })
    local weapon = newItem("Base.Axe", {
        displayName = "Axe", displayCategory = "Weapon",
    })
    expect(items.public.category(material) == "material"
        and items.public.category(food) == "perishable"
        and items.public.category(weapon) == "weapon",
        "storage item classification")
    local description = items.public.describe(material,
        { linkId = "node:1:0", name = "Wooden Crate" }, crateA.containers[1])
    expect(description.groupKey == "Base.Plank"
        and description.sourceName == "Wooden Crate"
        and description.tags[1] == "Material",
        "storage item description")
    local protectedItem = newItem("GodSystem.SystemCoin1")
    expect(items.public.isProtected(protectedItem)
        and items.public.canDeposit(actor, protectedItem, "manual") == false,
        "protected storage items")
    material.favorite = true
    expect(items.public.canDeposit(actor, material, "sourceAll") == false
        and items.public.canDeposit(actor, material, "selected") == true,
        "bulk deposit safety differs from selected deposit")
    material.favorite = false

    local source = rootInventory
    source:AddItem(material)
    local target = fridgeB.containers[1]
    expect(containers.public.accepts(target, actor, material) == true,
        "native acceptance succeeds")
    target.allowed = false
    local accepted, acceptCode = containers.public.accepts(target, actor, material)
    expect(accepted == false and acceptCode == "notAllowed",
        "native item rule is honored")
    target.allowed = true
    target.room = false
    accepted, acceptCode = containers.public.accepts(target, actor, material)
    expect(accepted == false and acceptCode == "full",
        "native capacity rule is honored")
    target.room = true
    expect(containers.public.remove(source, material)
        and containers.public.add(target, material),
        "exact per-item transfer primitives")
    expect(containers.public.remove(target, material)
        and containers.public.add(source, material),
        "first-level recovery to original container")

    local failedSource = newContainer("failedSource", 20)
    local failedItem = newItem("Base.Failed", { displayCategory = "Material" })
    failedSource:AddItem(failedItem)
    expect(containers.public.remove(failedSource, failedItem), "remove before recovery")
    failedSource.addEnabled = false
    expect(containers.public.add(failedSource, failedItem) == false
        and containers.public.add(rootInventory, failedItem) == true,
        "second-level recovery to player inventory")
    expect(containers.public.remove(rootInventory, failedItem),
        "prepare third-level recovery")
    rootInventory.addEnabled = false
    expect(containers.public.add(failedSource, failedItem) == false
        and containers.public.add(rootInventory, failedItem) == false,
        "first and second recovery levels can fail visibly")
    expect(containers.public.ground(crateA, actor, failedItem) == true
        and actorSquare.grounded[#actorSquare.grounded] == failedItem,
        "third-level recovery to world square")
    rootInventory.addEnabled = true

    local bag = newItem("Base.Bag", {
        displayCategory = "Container", containerType = "bag",
    })
    rootInventory:AddItem(bag)
    actor.primary = bag
    local resolvedBag = containers.public.playerContainer(actor, bag:getID())
    expect(resolvedBag == bag.child, "equipped player target container")
    actor.primary = nil
    expect(containers.public.playerContainer(actor, bag:getID()) == nil,
        "unequipped arbitrary nested target rejected")

    local coreItem = core.public.create(actor, "network-1", "token-1",
        "GodSystem.StorageController")
    expect(coreItem and core.public.find(actor, "network-1", "token-1",
        coreItem:getID()) == coreItem, "exact core identity resolution")
    local duplicate = core.public.create(actor, "network-1", "token-2",
        "GodSystem.StorageController")
    expect(duplicate and core.public.cleanupDuplicates(
        actor, "network-1", coreItem) == 1, "duplicate network core cleanup")
    local removedCore, receipt = core.public.remove(actor, coreItem)
    expect(removedCore and receipt.container == rootInventory,
        "core removal receipt")
    expect(core.public.restore(actor, coreItem, receipt) == true,
        "core removal rollback")

    local network = {
        scope = "personal", scopeKey = "personal:alice", owner = "alice",
    }
    expect(permissions.public.canUse(actor, network, wrappedA) == true
        and permissions.public.canManage(actor, network, wrappedA) == true,
        "personal network permissions")
    expect(permissions.public.canUse(otherActor, network, wrappedA) == false,
        "personal network actor isolation")
    expect(permissions.public.withinRange(actor, wrappedA, 2.5) == true,
        "distance permission")
    local safehouse = {}
    function safehouse:getId() return "safe-1" end
    function safehouse:getX() return 0 end
    function safehouse:getY() return 0 end
    function safehouse:getW() return 3 end
    function safehouse:getH() return 3 end
    function safehouse:getOwner() return "alice" end
    function safehouse:isOwner(value) return value == actor end
    function safehouse:playerAllowed(username) return username == "bob" end
    function safehouse:getPlayers() return javaList({ "alice", "bob" }) end
    binding.safehouses = function() return { safehouse } end
    local safeScope = objects.public.scope(actor, objects.public.actorPosition(actor))
    local safeNetwork = {
        scope = "safehouse", scopeKey = safeScope.key, owner = "alice",
    }
    expect(safeScope.key == "safehouse:safe-1"
        and permissions.public.canUse(otherActor, safeNetwork, wrappedA) == true
        and permissions.public.canManage(otherActor, safeNetwork, wrappedA) == false,
        "safehouse member use and owner-only management")

    expect(sync.public.object(wrappedA) == true
        and sync.public.add(rootInventory, material) == true
        and sync.public.remove(rootInventory, material) == true
        and sync.public.state(network) == true,
        "storage synchronization adapter")
    expect(crateA.transmitted > 0 and syncCounts.add > 0
        and syncCounts.remove > 0 and syncCounts.state > 0,
        "storage synchronization callbacks")

    local created, revision = state.public.create(actor, {
        networkId = "network-state", scopeKey = "personal:alice",
        owner = "alice",
    })
    expect(created and revision == 0, "storage scoped state create")
    created.owner = "updated"
    expect(state.public.commit(actor, created, revision) == true,
        "storage optimistic state commit")
    expect(state.public.commit(actor, created, revision) == false,
        "storage stale revision rejected")
    local shared = state.public.create(otherActor, {
        networkId = "ignored-duplicate", scopeKey = "personal:alice",
        owner = "alice",
    })
    local bobCurrent = state.public.load(otherActor, { current = true })
    expect(shared.networkId == "network-state"
        and bobCurrent.networkId == "network-state",
        "shared scope is indexed for each participating actor")

    require "GodSystem/Core/Result"
    require "GodSystem/Services/OperationLedger"
    require "GodSystem/Services/Operations"
    require "GodSystem/Features/Storage/Rules"
    require "GodSystem/Features/Storage/Module"
    local operationRoot = {}
    local operationService = GodSystemOperationsService.create({}, {
        state = { get = function() return operationRoot end },
    })
    operationService:start()
    local moduleStateRoot, moduleAuditRoot = {}, {}
    local moduleState = GodSystemStorageStatePlatform.create({}, {
        state = { get = function() return moduleStateRoot end },
        binding = binding,
    })
    local moduleAudit = GodSystemStorageAuditPlatform.create({}, {
        state = { get = function() return moduleAuditRoot end },
        binding = binding,
    })
    moduleState:start(); moduleAudit:start()
    local walletBalance = 10000
    local wallet = {
        getBalance = function() return walletBalance end,
        charge = function(_, amount)
            walletBalance = walletBalance - amount
            return true, { amount = amount }
        end,
        refund = function(_, receipt)
            walletBalance = walletBalance + receipt.amount
            return true
        end,
    }
    local storageModule = GodSystemStorageFeatureModule.create({
        ["storage.config"] = config.public,
        ["storage.state"] = moduleState.public,
        ["storage.objects"] = objects.public,
        ["storage.containers"] = containers.public,
        ["storage.items"] = items.public,
        ["storage.core"] = core.public,
        ["storage.permissions"] = permissions.public,
        ["storage.clock"] = clock.public,
        ["storage.sync"] = sync.public,
        wallet = wallet,
        operations = operationService.public,
        ["storage.audit"] = moduleAudit.public,
    })
    expect(storageModule:start() == true, "storage feature starts with real adapters")
    binding.safehouses = nil
    local hostSquare, routeSquare = newSquare(4, 0, 0), newSquare(5, 0, 0)
    addSquare(hostSquare); addSquare(routeSquare)
    actor.square = hostSquare
    local host = newWorldObject(hostSquare, "Core Crate", {
        newContainer("crate", 50),
    })
    local route = newWorldObject(routeSquare, "Material Crate", {
        newContainer("crate", 50),
    })
    local hostRef = objects.public.reference(host, true)
    local routeRef = objects.public.reference(route, true)
    local linkedHost = storageModule.public.execute({
        action = "setNetworkContainer", actor = actor,
        operationId = "adapter-link-host", enabled = true,
        objectId = hostRef.objectId, x = hostRef.x, y = hostRef.y, z = hostRef.z,
        name = "Core Crate",
    })
    local linkedRoute = storageModule.public.execute({
        action = "setNetworkContainer", actor = actor,
        operationId = "adapter-link-route", enabled = true,
        objectId = routeRef.objectId, x = routeRef.x, y = routeRef.y, z = routeRef.z,
        name = "Material Crate",
    })
    expect(linkedHost.ok and linkedRoute.ok,
        "real object adapters mark connected containers")
    local claimed = storageModule.public.claimCore({
        actor = actor, operationId = "adapter-claim-core",
    })
    expect(claimed.ok, "real core adapter claims first core")
    local moduleNetwork = moduleState.public.load(actor, { current = true })
    local claimedCore = core.public.find(actor, moduleNetwork.networkId,
        moduleNetwork.coreToken)
    expect(claimedCore ~= nil, "claimed core has exact network identity")
    local installed = storageModule.public.installCore({
        actor = actor, operationId = "adapter-install-core",
        objectId = hostRef.objectId, x = hostRef.x, y = hostRef.y, z = hostRef.z,
        coreItemId = claimedCore:getID(),
    })
    expect(installed.ok, "real adapters install core transactionally")
    local routedItem = newItem("Base.NetworkPlank", {
        displayName = "Network Plank", displayCategory = "Material",
    })
    rootInventory:AddItem(routedItem)
    local deposited = storageModule.public.deposit({
        actor = actor, operationId = "adapter-deposit",
        mode = "selected", itemIds = { routedItem:getID() },
    })
    expect(deposited.ok and deposited.data.success == 1
        and containers.public.contains(route.containers[1], routedItem),
        "feature deposit uses real topology and per-item adapters")
end

print("Test-GodSystemV422012TerminalStorageAdaptersRuntime passed")
