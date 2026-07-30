local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local timestamp = 1000
local nextItemId = 100
local syncCalls = {
    modData = 0,
    fields = 0,
    stats = 0,
    added = 0,
    removed = 0,
}

ItemTag = { AMMO = "ammo" }
GodSystemConfig = {
    AutoLoaderAmmoCapacity = 2000,
    RecycleBlacklist = { ["Base.ProtectedAmmo"] = true },
}
GodSystemAdminConfig = {
    getSetting = function(key, fallback)
        if key == "AutoLoaderAmmoCapacity" then return 2500 end
        return fallback
    end,
}

function getTimestampMs() return timestamp end
function instanceof(item, className)
    return className == "HandWeapon" and item and item.kind == "weapon"
end
function syncItemModData(_, item)
    assert(item, "syncItemModData item missing")
    syncCalls.modData = syncCalls.modData + 1
end
function syncItemFields(_, item)
    assert(item, "syncItemFields item missing")
    syncCalls.fields = syncCalls.fields + 1
end
function sendItemStats(item)
    assert(item, "sendItemStats item missing")
    syncCalls.stats = syncCalls.stats + 1
end
function sendAddItemToContainer(container, item)
    assert(container and item, "sendAddItemToContainer arguments missing")
    syncCalls.added = syncCalls.added + 1
end
function sendRemoveItemFromContainer(container, item)
    assert(container and item, "sendRemoveItemFromContainer arguments missing")
    syncCalls.removed = syncCalls.removed + 1
end

local registered = {
    ["Base.Bullets9mm"] = "9mm Rounds",
    ["Base.ProtectedAmmo"] = "Protected Rounds",
}
function getScriptManager()
    return {
        FindItem = function(_, fullType)
            local name = registered[fullType]
            if not name then return nil end
            return { getDisplayName = function() return name end }
        end,
    }
end

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local newItem
local function newContainer(name)
    local container = { name = name, values = {} }
    function container:getItems() return javaList(self.values) end
    function container:AddItem(value)
        local item = value
        if type(value) == "string" then
            nextItemId = nextItemId + 1
            item = newItem(nextItemId, "ammo", value, value)
        end
        self.values[#self.values + 1] = item
        item.container = self
        return item
    end
    function container:Remove(item)
        for index = 1, #self.values do
            if self.values[index] == item then
                table.remove(self.values, index)
                item.container = nil
                return
            end
        end
    end
    return container
end

newItem = function(id, kind, fullType, name)
    local item = {
        id = id,
        kind = kind,
        fullType = fullType,
        name = name,
        modData = {},
        favorite = false,
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getDisplayName() return self.name end
    function item:getModData() return self.modData end
    function item:getContainer() return self.container end
    function item:getInventory() return self.child end
    function item:isFavorite() return self.favorite end
    function item:hasTag(tag) return tag == ItemTag.AMMO and self.kind == "ammo" end
    function item:getAmmoType()
        if not self.ammoType then return nil end
        local key = self.ammoType
        return { getItemKey = function() return key end }
    end
    function item:getCurrentAmmoCount() return self.rounds or 0 end
    function item:getMaxAmmo() return self.maximum or 0 end
    function item:setCurrentAmmoCount(value) self.rounds = value end
    return item
end

local root = newContainer("root")
local nested = newContainer("nested")
local loader = newItem(1, "loader", "GodSystem.SystemAutoLoader", "System Auto-loader")
local bag = newItem(2, "container", "Base.Bag", "Bag")
bag.child = nested
local loose = newItem(3, "ammo", "Base.Bullets9mm", "9mm Rounds")
local favorite = newItem(4, "ammo", "Base.Bullets9mm", "Favorite 9mm")
favorite.favorite = true
local protected = newItem(5, "ammo", "Base.ProtectedAmmo", "Protected Rounds")
local magazine = newItem(6, "magazine", "Base.9mmClip", "9mm Magazine")
magazine.ammoType = "Base.Bullets9mm"
magazine.rounds = 1
magazine.maximum = 3

root:AddItem(loader)
root:AddItem(bag)
root:AddItem(favorite)
root:AddItem(protected)
root:AddItem(magazine)
nested:AddItem(loose)

local player = { modData = {}, username = "tester", onlineId = 7 }
function player:getInventory() return root end
function player:getModData() return self.modData end
function player:getUsername() return self.username end
function player:getOnlineID() return self.onlineId end

require "GodSystem/Core/Result"
require "GodSystem/Platform/AutoLoader/AmmoCatalog"
require "GodSystem/Platform/AutoLoader/InventoryQuery"
require "GodSystem/Platform/AutoLoader/InventoryMutation"
require "GodSystem/Platform/AutoLoader/Store"
require "GodSystem/Platform/AutoLoader/Sessions"
require "GodSystem/Platform/AutoLoader/Operations"
require "GodSystem/Platform/AutoLoader/Synchronization"
require "GodSystem/Features/AutoLoader/Module"

local catalogInstance = GodSystemAutoLoaderAmmoCatalogPlatform.create()
assert(catalogInstance:start())
local queryInstance = GodSystemAutoLoaderInventoryQueryPlatform.create({
    ["ammo.catalog"] = catalogInstance.public,
})
assert(queryInstance:start())
local mutationInstance = GodSystemAutoLoaderInventoryMutationPlatform.create({
    ["autoloader.inventory.query"] = queryInstance.public,
})
assert(mutationInstance:start())
local storeInstance = GodSystemAutoLoaderStorePlatform.create()
local sessionsInstance = GodSystemAutoLoaderSessionsPlatform.create()
local operationsInstance = GodSystemAutoLoaderOperationsPlatform.create()
local syncInstance = GodSystemAutoLoaderSynchronizationPlatform.create()
assert(storeInstance:start() and sessionsInstance:start()
    and operationsInstance:start() and syncInstance:start())

local notifications = { values = {} }
notifications.publish = function(value)
    notifications.values[#notifications.values + 1] = value
    return true
end

local module = GodSystemAutoLoaderFeatureModule.create({
    ["autoloader.inventory.query"] = queryInstance.public,
    ["autoloader.inventory.mutation"] = mutationInstance.public,
    ["ammo.catalog"] = catalogInstance.public,
    ["autoloader.store"] = storeInstance.public,
    ["autoloader.sessions"] = sessionsInstance.public,
    ["autoloader.operations"] = operationsInstance.public,
    ["autoloader.synchronization"] = syncInstance.public,
    notifications = notifications,
}, {
    moduleId = "feature.autoloader",
    environment = "pz-style-test",
})
assert(module:start())

local resolved, _, source = queryInstance.public.resolveItem(player, "3")
assert(resolved == loose and source == nested, "Java-list nested inventory resolution failed")
local values = queryInstance.public.scanCarried(player, 100)
assert(#values == 6, "Java-list carried scan changed")
assert(catalogInstance.public.isLooseAmmo(loose), "ItemTag.AMMO recognition failed")
assert(catalogInstance.public.magazineAmmoType(magazine) == "Base.Bullets9mm",
    "magazine ammo type recognition failed")
assert(catalogInstance.public.isProtected(protected),
    "configured protected item recognition failed")
assert(storeInstance.public.capacity(loader) == 2500,
    "admin auto-loader capacity did not override the configured fallback")

local removed, receipt = mutationInstance.public.removeAmmo(player, loose)
assert(removed and queryInstance.public.resolveItem(player, "3") == nil,
    "exact nested item removal failed")
assert(mutationInstance.public.restoreAmmo(player, receipt)
    and queryInstance.public.resolveItem(player, "3") == loose,
    "exact nested item restoration failed")

local started = module.public.startDeposit({
    actor = player,
    loaderId = "1",
    operationId = "gsa-1000-1-0",
})
assert(started.ok and started.code == "DepositStarted", "PZ adapter deposit did not start")
assert(started.data.total == 1 and started.data.skipped == 2,
    "favorite/protected deposit filtering changed")
local completed = module.public.completeDepositBatch({
    actor = player,
    sessionId = started.data.sessionId,
    batchIndex = 1,
})
assert(completed.ok and completed.data.aggregate.stored == 1,
    "PZ adapter deposit did not settle")
local loaderData = loader:getModData().GodSystemAutoLoader
assert(type(loaderData) == "table" and loaderData.version == 1
    and loaderData.ammo["Base.Bullets9mm"] == 1,
    "legacy-compatible loader ModData was not written")
assert(queryInstance.public.resolveItem(player, "3") == nil,
    "stored ammunition remained in its nested container")

local filled = module.public.manualFill({
    actor = player,
    loaderId = "1",
    operationId = "gsa-1000-2-0",
})
assert(filled.ok and filled.code == "FillInsufficient" and magazine.rounds == 2,
    "PZ-style magazine fill changed")
assert(loaderData.ammo["Base.Bullets9mm"] == nil,
    "magazine fill did not consume the stored balance")

assert(storeInstance.public.setBalance(loader, "Base.Bullets9mm", 3, "9mm Rounds"))
local beforeRoot = #root.values
local withdrawn = module.public.withdraw({
    actor = player,
    loaderId = "1",
    fullType = "Base.Bullets9mm",
    count = 2,
    operationId = "gsa-1000-3-0",
})
assert(withdrawn.ok and withdrawn.data.created == 2 and #root.values == beforeRoot + 2,
    "PZ-style ammo creation failed")
assert(loaderData.ammo["Base.Bullets9mm"] == 1, "withdraw balance changed")
local replay = module.public.withdraw({
    actor = player,
    loaderId = "1",
    fullType = "Base.Bullets9mm",
    count = 2,
    operationId = "gsa-1000-3-0",
})
assert(replay == withdrawn and #root.values == beforeRoot + 2,
    "PZ ModData operation ledger did not prevent duplicate withdrawal")
assert(type(player.modData.GodSystemAutoLoaderOperations) == "table"
    and player.modData.GodSystemAutoLoaderOperations.results["gsa-1000-3-0"].status == "done",
    "legacy-compatible operation ModData was not written")

local invalid = module.public.withdraw({
    actor = player,
    loaderId = "1",
    fullType = "Base.Bullets9mm",
    count = 1,
    operationId = "invalid-operation",
})
assert(not invalid.ok and invalid.code == "OperationInvalid",
    "legacy operation ID validation changed")

assert(syncCalls.removed >= 1 and syncCalls.added >= 2,
    "container add/remove synchronization calls were not emitted")
assert(syncCalls.modData >= 1 and syncCalls.fields >= 2 and syncCalls.stats >= 1,
    "loader/magazine synchronization calls were not emitted")

for _, component in ipairs({
    catalogInstance,
    queryInstance,
    mutationInstance,
    storeInstance,
    sessionsInstance,
    operationsInstance,
    syncInstance,
}) do
    local health = component:health()
    assert(health.ok, "PZ adapter health failed: " .. tostring(health.moduleId))
end
local featureHealth = module:health()
assert(featureHealth.ok, "auto-loader feature health failed with PZ adapters: "
    .. tostring(featureHealth.code) .. " / "
    .. tostring(featureHealth.data and featureHealth.data.lastIssue
        and featureHealth.data.lastIssue.stage))

print("Test-GodSystemV422012AutoLoaderModuleAdaptersRuntime passed")
