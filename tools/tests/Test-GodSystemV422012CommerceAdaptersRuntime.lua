local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local nextId = 100
local worldHours = 120
local sync = { added = 0, removed = 0 }

GameTime = {
    getInstance = function()
        return { getWorldAgeHours = function() return worldHours end }
    end,
}
ItemType = { KEY_RING = "keyRing" }
ItemTag = { KEY_RING = "keyRing" }
function instanceof(item, kind) return kind == "Key" and item and item.kind == "key" end
function sendAddItemToContainer(container, item)
    assert(container and item)
    sync.added = sync.added + 1
end
function sendRemoveItemFromContainer(container, item)
    assert(container and item)
    sync.removed = sync.removed + 1
end

local registered = {
    ["GodSystem.SystemCoin100"] = { name = "System Coin 100", category = "Currency" },
    ["GodSystem.SystemCoin10"] = { name = "System Coin 10", category = "Currency" },
    ["GodSystem.SystemCoin1"] = { name = "System Coin 1", category = "Currency" },
    ["Base.Scrap"] = { name = "Scrap", category = "Material" },
    ["Base.Bandage"] = { name = "Bandage", category = "Medical" },
    ["Base.KeyRing"] = { name = "Key Ring", category = "Key" },
    ["Mod.Chair"] = { name = "Chair", category = "Furniture" },
    ["ThirdParty.Alloy"] = { name = "Alloy", category = "Material" },
}
function getScriptManager()
    return {
        FindItem = function(_, fullType)
            local row = registered[fullType]
            if not row then return nil end
            return {
                getDisplayName = function() return row.name end,
                getObsolete = function() return false end,
                isHidden = function() return false end,
                getDisplayCategory = function() return row.category end,
                getBodyLocation = function() return nil end,
            }
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
    function container:AddItem(item)
        if type(item) == "string" then item = InventoryItemFactory.CreateItem(item) end
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

newItem = function(id, fullType, kind, sprite)
    local row = registered[fullType] or { name = fullType, category = "Other" }
    local item = {
        id = id,
        fullType = fullType,
        kind = kind or "normal",
        name = row.name,
        category = row.category,
        worldSprite = sprite,
        modData = {},
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getDisplayName() return self.name end
    function item:getCategory() return self.category end
    function item:getDisplayCategory() return self.category end
    function item:getWorldSprite() return self.worldSprite end
    function item:ReadFromWorldSprite(value) self.worldSprite = value end
    function item:getInventory() return self.child end
    function item:getModData() return self.modData end
    function item:isBroken() return false end
    function item:getUsedDelta() return nil end
    function item:isItemType(value) return value == ItemType.KEY_RING and self.kind == "keyRing" end
    function item:hasTag(value) return value == ItemTag.KEY_RING and self.kind == "keyRing" end
    return item
end

InventoryItemFactory = {
    CreateItem = function(fullType)
        if not registered[fullType] then return nil end
        nextId = nextId + 1
        return newItem(nextId, fullType)
    end,
}

local rootInventory = newContainer("root")
local nestedInventory = newContainer("nested")
local bag = newItem(1, "Base.Bag", "container")
bag.name = "Bag"
bag.category = "Container"
bag.child = nestedInventory
local scrap = newItem(2, "Base.Scrap")
local chair = newItem(3, "Mod.Chair", "moveable", "mod_chair_01")
local alloy = newItem(4, "ThirdParty.Alloy")
local keyRing = newItem(5, "Base.KeyRing", "keyRing")
rootInventory:AddItem(bag)
rootInventory:AddItem(chair)
rootInventory:AddItem(alloy)
rootInventory:AddItem(keyRing)
nestedInventory:AddItem(scrap)

local player = { username = "tester", onlineId = 11 }
function player:getInventory() return rootInventory end
function player:getUsername() return self.username end
function player:getOnlineID() return self.onlineId end

local snapshot = {
    wallet = { initialBalance = 500 },
    tasks = {
        dailyCount = 1,
        maxActive = 3,
        defaultLimitHours = 24,
        templates = {
            {
                id = "turnin_scrap",
                title = "Turn in scrap",
                kind = "turnInItem",
                target = 1,
                item = "Base.Scrap",
                rewardPoints = 20,
                rewardItems = { { fullType = "Base.Bandage", count = 1 } },
                penaltyPoints = 5,
            },
        },
    },
    shop = {
        defaultListingCost = 10,
        defaultLotteryPrice = 100,
        products = {
            {
                id = "configured:bandage",
                label = "Bandage",
                categoryKey = "medical",
                price = 6,
                items = { { fullType = "Base.Bandage", count = 1 } },
            },
        },
    },
    recycle = {
        sellPrices = {
            ["Base.Scrap"] = 5,
            ["ThirdParty.Alloy"] = 8,
        },
        defaultListingCost = 7,
        buyMultiplier = 4,
    },
    eligibility = {
        allowAnyModule = true,
        recycleBlacklist = {},
        shopBlacklist = {},
    },
}

local function context(initial)
    local value = initial or {}
    return {
        configSnapshot = snapshot,
        state = { get = function() return value end },
    }
end

require "GodSystem/Core/Result"
require "GodSystem/Platform/Commerce/Support"
require "GodSystem/Platform/Commerce/ActorIdentity"
require "GodSystem/Platform/Commerce/ShopIdentity"
require "GodSystem/Services/Clock"
require "GodSystem/Services/Random"
require "GodSystem/Services/Operations"
require "GodSystem/Platform/WalletAccounts"
require "GodSystem/Platform/WalletFunds"
require "GodSystem/Platform/Commerce/States"
require "GodSystem/Platform/Commerce/ConfigSnapshots"
require "GodSystem/Platform/Commerce/Inventory"
require "GodSystem/Platform/Commerce/Wallet"
require "GodSystem/Platform/Commerce/ItemEligibility"
require "GodSystem/Platform/Commerce/ShopListings"
require "GodSystem/Services/Notifications"
require "GodSystem/Features/Tasks/Module"
require "GodSystem/Features/Shop/Module"
require "GodSystem/Features/Recycle/Module"
require "GodSystem/Composition"

local actorIdentity = GodSystemCommerceActorIdentityPlatform.create()
local shopIdentity = GodSystemShopIdentityPlatform.create()
local clock = GodSystemClockService.create()
local random = GodSystemRandomService.create()
assert(actorIdentity:start() and shopIdentity:start() and clock:start() and random:start())

local operations = GodSystemOperationsService.create({}, context())
local taskState = GodSystemTasksStatePlatform.create({
    ["commerce.actor.identity"] = actorIdentity.public,
}, context())
local shopState = GodSystemShopStatePlatform.create({
    ["commerce.actor.identity"] = actorIdentity.public,
}, context())
local recycleState = GodSystemRecycleStatePlatform.create({
    ["commerce.actor.identity"] = actorIdentity.public,
}, context())
assert(operations:start() and taskState:start() and shopState:start() and recycleState:start())

local tasksConfig = GodSystemTasksConfigPlatform.create({}, context())
local shopConfig = GodSystemShopConfigPlatform.create({
    ["shop.identity"] = shopIdentity.public,
}, context())
local recycleConfig = GodSystemRecycleConfigPlatform.create({}, context())
local eligibility = GodSystemItemEligibilityPlatform.create({}, context())
assert(tasksConfig:start() and shopConfig:start() and recycleConfig:start() and eligibility:start())

local commerceInventory = GodSystemCommerceInventoryPlatform.create()
assert(commerceInventory:start())
local tasksInventory = GodSystemTasksInventoryPlatform.create({
    ["commerce.inventory"] = commerceInventory.public,
})
local shopInventory = GodSystemShopInventoryPlatform.create({
    ["commerce.inventory"] = commerceInventory.public,
})
local recycleInventory = GodSystemRecycleInventoryPlatform.create({
    ["commerce.inventory"] = commerceInventory.public,
})
assert(tasksInventory:start() and shopInventory:start() and recycleInventory:start())

local accountsContext = context()
accountsContext.binding = { initialBalance = function() return 500 end }
local walletAccounts = GodSystemWalletAccountsPlatform.create({}, accountsContext)
assert(walletAccounts:start())
local walletFunds = GodSystemWalletFundsPlatform.create({
    ["wallet.accounts"] = walletAccounts.public,
}, context())
assert(walletFunds:start())
local commerceWallet = GodSystemCommerceWalletPlatform.create({
    ["wallet.funds"] = walletFunds.public,
}, context())
assert(commerceWallet:start())
local tasksWallet = GodSystemTasksWalletPlatform.create({
    ["commerce.wallet"] = commerceWallet.public,
})
local shopWallet = GodSystemShopWalletPlatform.create({
    ["commerce.wallet"] = commerceWallet.public,
})
local recycleWallet = GodSystemRecycleWalletPlatform.create({
    ["commerce.wallet"] = commerceWallet.public,
})
assert(tasksWallet:start() and shopWallet:start() and recycleWallet:start())

local listings = GodSystemShopListingsPlatform.create({
    ["shop.state"] = shopState.public,
    ["shop.config"] = shopConfig.public,
})
assert(listings:start())

local notifications = GodSystemNotificationsService.create({}, context())
assert(notifications:start())

local tasks = GodSystemTasksFeatureModule.create({
    ["tasks.config"] = tasksConfig.public,
    ["tasks.state"] = taskState.public,
    ["tasks.inventory"] = tasksInventory.public,
    ["tasks.wallet"] = tasksWallet.public,
    ["upgrades.read"] = {
        limits = function()
            return { dailyTaskCount = 2, maxActiveTasks = 3 }
        end,
    },
    clock = clock.public,
    random = random.public,
    operations = operations.public,
    notifications = notifications.public,
}, { moduleId = "feature.tasks" })
local shop = GodSystemShopFeatureModule.create({
    ["shop.config"] = shopConfig.public,
    ["shop.state"] = shopState.public,
    ["shop.identity"] = shopIdentity.public,
    ["shop.inventory"] = shopInventory.public,
    ["shop.wallet"] = shopWallet.public,
    ["item.eligibility"] = eligibility.public,
    clock = clock.public,
    random = random.public,
    operations = operations.public,
    notifications = notifications.public,
}, { moduleId = "feature.shop" })
local recycle = GodSystemRecycleFeatureModule.create({
    ["recycle.config"] = recycleConfig.public,
    ["recycle.state"] = recycleState.public,
    ["recycle.inventory"] = recycleInventory.public,
    ["recycle.wallet"] = recycleWallet.public,
    ["item.eligibility"] = eligibility.public,
    ["shop.identity"] = shopIdentity.public,
    ["shop.listings"] = listings.public,
    operations = operations.public,
    notifications = notifications.public,
}, { moduleId = "feature.recycle" })
assert(tasks:start() and shop:start() and recycle:start())

local generated = tasks.public.generate({
    actor = player,
    operationId = "tasks-generate-1",
})
assert(generated.ok and generated.data.count == 1, "PZ task config/state adapters failed")
local taskData = taskState.public.load(player)
local taskId = taskData.tasks[1].taskId
assert(tasks.public.accept({
    actor = player,
    taskId = taskId,
    operationId = "tasks-accept-1",
}).ok, "PZ task accept failed")
assert(tasks.public.progress({ actor = player, taskId = taskId }).data.complete,
    "nested PZ inventory task count failed")
local claimed = tasks.public.claim({
    actor = player,
    taskId = taskId,
    operationId = "tasks-claim-1",
})
assert(claimed.ok and claimed.code == "claimed", "PZ task settlement failed")
assert(commerceInventory.public.resolve(player, "2") == nil,
    "task turn-in did not remove exact nested item")
assert(commerceWallet.public.balance(player) == 520,
    "task reward did not use shared wallet")

local listed = shop.public.listItem({
    actor = player,
    itemId = "3",
    operationId = "shop-list-1",
})
assert(listed.ok and listed.data.variantKey == "Mod.Chair@worldSprite=mod_chair_01",
    "furniture variant identity changed")
assert(commerceWallet.public.balance(player) == 510, "shop listing cost changed")
local purchased = shop.public.purchase({
    actor = player,
    productId = listed.data.productId,
    quantity = 1,
    operationId = "shop-purchase-1",
})
assert(purchased.ok and commerceWallet.public.balance(player) == 506,
    "shop purchase did not use shared wallet")
local restoredFurniture = false
for index = 1, #rootInventory.values do
    local item = rootInventory.values[index]
    if item ~= chair and item.fullType == "Mod.Chair"
        and item.worldSprite == "mod_chair_01"
    then
        restoredFurniture = true
    end
end
assert(restoredFurniture, "Moveable worldSprite was not restored during purchase")
local rootCount = #rootInventory.values
local replay = shop.public.purchase({
    actor = player,
    productId = listed.data.productId,
    quantity = 1,
    operationId = "shop-purchase-1",
})
assert(replay == purchased and #rootInventory.values == rootCount,
    "shared operation ledger allowed duplicate shop grant")

local recycled = recycle.public.execute({
    actor = player,
    mode = "recycle",
    itemIds = { "4", "5" },
    operationId = "recycle-batch-1",
})
assert(recycled.ok and recycled.code == "recycledPartial"
    and recycled.data.processedCount == 1 and recycled.data.skippedCount == 1,
    "PZ smart recycle filtering failed")
assert(recycled.data.payout == 8 and commerceWallet.public.balance(player) == 514,
    "third-party dynamic recycle value or shared wallet settlement failed")
assert(commerceInventory.public.resolve(player, "4") == nil
    and commerceInventory.public.resolve(player, "5") ~= nil,
    "recycle exact removal/protected key handling failed")

assert(shopConfig.public.resolveProduct(player, "configured:bandage") ~= nil,
    "injected shop snapshot was not available")
assert(eligibility.public.allowed("ThirdParty.Alloy", "purchase") == true,
    "registered third-party item was not dynamically recognized")
assert(sync.added >= 2 and sync.removed >= 2,
    "PZ container synchronization calls were not emitted")

for _, instance in ipairs({
    actorIdentity, shopIdentity, clock, random, operations, walletAccounts, walletFunds,
    taskState, shopState, recycleState,
    tasksConfig, shopConfig, recycleConfig, eligibility,
    commerceInventory, tasksInventory, shopInventory, recycleInventory,
    commerceWallet, tasksWallet, shopWallet, recycleWallet,
    listings, notifications, tasks, shop, recycle,
}) do
    local health = instance:health()
    assert(health.ok, "commerce component health failed: " .. tostring(health.moduleId))
end

local composedState = {}
local composed = GodSystemComposition.create({
    version = "42.20.1.2",
    protocolVersion = "42.20.1.2",
    environment = "test",
    configSnapshot = snapshot,
    adapters = {
        events = {
            add = function() return true end,
            remove = function() return true end,
        },
        state = {
            load = function() return composedState end,
            save = function(_, value)
                composedState = value
                return true
            end,
        },
    },
    bindings = {
        ["wallet.accounts"] = {
            initialBalance = function() return 500 end,
        },
    },
})
assert(composed.startResult and composed.startResult.ok,
    "Commerce descriptors could not be registered by Composition")
for _, moduleId in ipairs({
    "commerce.actor.identity", "shop.identity",
    "tasks.state", "shop.state", "recycle.state",
    "tasks.config", "shop.config", "recycle.config",
    "commerce.inventory", "tasks.inventory", "shop.inventory", "recycle.inventory",
    "commerce.wallet", "tasks.wallet", "shop.wallet", "recycle.wallet",
    "item.eligibility", "shop.listings",
    "feature.tasks", "feature.shop", "feature.recycle",
}) do
    local status = composed.registry:status(moduleId)
    assert(status and status.state == "started",
        "Composition did not start Commerce descriptor: " .. moduleId)
end
assert(composed.registry:get("shop.config").resolveProduct(
    player, "configured:bandage") ~= nil,
    "Composition did not inject the Commerce config snapshot")
assert(composed.registry:get("item.eligibility").allowed(
    "ThirdParty.Alloy", "purchase") == true,
    "Composition lost dynamic third-party item recognition")
composed:stop("test")

print("Test-GodSystemV422012CommerceAdaptersRuntime passed")
