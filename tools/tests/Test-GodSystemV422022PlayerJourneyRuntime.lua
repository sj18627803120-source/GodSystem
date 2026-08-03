local root = assert(arg[1], "42.20.2.2 repository root is required")
local luaRoot = root .. "/Contents/mods/GodSystem/42/media/lua"

package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/server/?.lua;" .. package.path
getScriptManager = nil
isServer = function() return true end

dofile(luaRoot .. "/shared/GodSystem_Config.lua")
dofile(luaRoot .. "/shared/GodSystem_Prices.lua")
dofile(luaRoot .. "/shared/GodSystem_AdminConfig.lua")
dofile(luaRoot .. "/shared/GodSystem_ShopVariants.lua")

GodSystem = GodSystem or {}
GodSystem.isEconomicItemAllowed = function(fullType)
    return fullType ~= "Base.Hidden" and not tostring(fullType or ""):match("^GodSystem%.SystemCoin")
end

dofile(luaRoot .. "/shared/GodSystem_EconomyPolicy.lua")

-- The real eligibility module requires the game's ScriptManager. This headless
-- journey test has no loaded game scripts, so restore the controlled item
-- eligibility fixture after EconomyPolicy loads its dependencies.
GodSystem.isEconomicItemAllowed = function(fullType)
    return fullType ~= "Base.Hidden"
        and not tostring(fullType or ""):match("^GodSystem%.SystemCoin")
end

dofile(luaRoot .. "/server/GodSystem_TransactionOps.lua")

local Policy = assert(GodSystemEconomyPolicy, "economy policy did not load")
local Admin = assert(GodSystemAdminConfig, "administrator config did not load")
local Variants = assert(GodSystemShopVariants, "shop variant service did not load")
local Ops = assert(GodSystemTransactionOps, "transaction operation service did not load")

Policy.rebuildTransformIndex(nil)

local function newItem(id, fullType, options)
    options = options or {}
    local item = {
        id = tostring(id),
        fullType = fullType,
        broken = options.broken == true,
        usedDelta = tonumber(options.usedDelta) or 1,
        worldSprite = options.worldSprite,
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getDisplayName() return self.fullType end
    function item:isBroken() return self.broken end
    function item:getUsedDelta() return self.usedDelta end
    function item:getWorldSprite() return self.worldSprite end
    return item
end

local player = {
    owner = "ordinary-player",
    currency = 5000,
    nextItemId = 1000,
    inventory = {},
    data = {
        unlockedShopItems = {},
        stats = { spentPoints = 0, boughtItems = 0, recycledItems = 0, recycledPoints = 0 },
    },
}
local transactionRoot = {}

local function inventoryCount(fullType)
    local count = 0
    for _, item in pairs(player.inventory) do
        if item.fullType == fullType then count = count + 1 end
    end
    return count
end

local function addInventory(fullType, options)
    player.nextItemId = player.nextItemId + 1
    local item = newItem(player.nextItemId, fullType, options)
    player.inventory[item.id] = item
    return item
end

local function removeInventory(itemId)
    local item = player.inventory[tostring(itemId)]
    if item then player.inventory[tostring(itemId)] = nil end
    return item
end

local function cachedResult(kind, args)
    local cached = Ops.get(transactionRoot, player.owner, kind, args)
    if not cached then return nil end
    if cached.status == "done" or cached.status == "mismatch" or cached.status == "invalid" or cached.status == "unknown" then
        return cached
    end
    return { status = "processing" }
end

local function remember(kind, args, ok, code, payload)
    Ops.remember(transactionRoot, player.owner, kind, args, ok, code, {}, payload or {})
    return Ops.get(transactionRoot, player.owner, kind, args)
end

local function listOnly(args)
    local cached = cachedResult("listOnlyAutoShop", args)
    if cached then return cached end
    assert(Ops.begin(transactionRoot, player.owner, "listOnlyAutoShop", args), "listing operation must begin")
    local item = player.inventory[tostring(args.itemId)]
    if not item or item.fullType ~= args.fullType then
        return remember("listOnlyAutoShop", args, false, "RecycleSelectionChanged", { cost = 0 })
    end
    local key = Variants.getKey(item.fullType, item)
    local known = Variants.isListingKnown(player.data, {}, key)
    if known then
        return remember("listOnlyAutoShop", args, true, "ListOnlyAlreadyUnlocked", { cost = 0, variantKey = key })
    end
    local cost, buyPrice = Policy.listingCost(item.fullType, item)
    if player.currency < cost then
        return remember("listOnlyAutoShop", args, false, "ListOnlyInsufficient", { cost = 0 })
    end
    player.currency = player.currency - cost
    player.data.stats.spentPoints = player.data.stats.spentPoints + cost
    player.data.unlockedShopItems[key] = {
        fullType = item.fullType,
        variantKey = key,
        label = item:getDisplayName(),
        hidden = false,
        buyPrice = buyPrice,
    }
    return remember("listOnlyAutoShop", args, true, "ListOnlySuccess", { cost = cost, buyPrice = buyPrice, variantKey = key })
end

local function buyListed(args)
    local cached = cachedResult("buyShop", args)
    if cached then return cached end
    assert(Ops.begin(transactionRoot, player.owner, "buyShop", args), "shop purchase must begin")
    local key = tostring(args.id or ""):gsub("^unlocked_", "")
    local row = player.data.unlockedShopItems[key]
    if not row or row.hidden == true then
        return remember("buyShop", args, false, row and "ShopItemHiddenStale" or "ShopItemNotFound", { price = 0 })
    end
    local quantity = math.max(1, math.floor(tonumber(args.quantity) or 1))
    local unitPrice = Policy.quote(row.fullType, nil, { kind = "shop" }).finalBuy
    local price = unitPrice * quantity
    if player.currency < price then
        return remember("buyShop", args, false, "CurrencyNotEnough", { price = 0 })
    end
    player.currency = player.currency - price
    player.data.stats.spentPoints = player.data.stats.spentPoints + price
    player.data.stats.boughtItems = player.data.stats.boughtItems + quantity
    for _ = 1, quantity do addInventory(row.fullType) end
    return remember("buyShop", args, true, "ShopBuySuccess", { price = price, quantity = quantity, fullType = row.fullType })
end

local function recycleSelected(args)
    local cached = cachedResult("recycleSelectedItems", args)
    if cached then return cached end
    assert(Ops.begin(transactionRoot, player.owner, "recycleSelectedItems", args), "recycle operation must begin")
    local payout, removed = 0, 0
    for i = 1, #(args.itemIds or {}) do
        local item = player.inventory[tostring(args.itemIds[i])]
        if item then
            local quote = Policy.quote(item.fullType, item, { kind = "recycle" })
            if quote.eligible == true and quote.recycleValue > 0 then
                payout = payout + quote.recycleValue
                removeInventory(item.id)
                removed = removed + 1
            end
        end
    end
    player.currency = player.currency + payout
    player.data.stats.recycledItems = player.data.stats.recycledItems + removed
    player.data.stats.recycledPoints = player.data.stats.recycledPoints + payout
    return remember("recycleSelectedItems", args, true, "RecycleSelectionComplete", { payout = payout, removed = removed })
end

local function unpackFirst(fullType)
    local source
    for _, item in pairs(player.inventory) do
        if item.fullType == fullType then source = item break end
    end
    assert(source, "unpack source is missing: " .. tostring(fullType))
    local routes = Policy.transformIndex and Policy.transformIndex[fullType]
    assert(routes and routes[1] and routes[1].outputs, "deterministic unpack route is missing")
    removeInventory(source.id)
    local created = {}
    for i = 1, #routes[1].outputs do
        local output = routes[1].outputs[i]
        for _ = 1, output.count do created[#created + 1] = addInventory(output.fullType) end
    end
    return created
end

print("[Journey 1] Player loads the economy and inspects ordinary items")
local normalAxe = addInventory("Base.Axe")
local wornAxe = addInventory("Base.Axe", { broken = true, usedDelta = 0.5 })
local bundleOwned = addInventory("Base.MoneyBundle")
local unknownModItem = addInventory("ThirdParty.ExperimentalCrate")
local normalQuote = Policy.quote(normalAxe.fullType, normalAxe, { kind = "recycle" })
local wornQuote = Policy.quote(wornAxe.fullType, wornAxe, { kind = "recycle" })
local unknownQuote = Policy.quote(unknownModItem.fullType, unknownModItem, { kind = "shop" })
assert(normalQuote.recycleValue >= 1, "ordinary known item must have a recycle value")
assert(wornQuote.recycleValue >= 1 and wornQuote.recycleValue < normalQuote.recycleValue, "broken and used items must be discounted")
assert(unknownQuote.recycleValue == 1 and unknownQuote.finalBuy == 120 and unknownQuote.verificationStatus == "not_applicable",
    "ordinary unknown Mod items must recycle for one and use the normal category buy price without the dynamic risk floor")

print("[Journey 2] Player lists an exact MoneyBundle instance")
local listArgs = { opId = "gs-1000-2000-1", fullType = bundleOwned.fullType, itemId = bundleOwned.id }
local cashBeforeListing = player.currency
local listed = listOnly(listArgs)
assert(listed.status == "done" and listed.ok == true and listed.payload.cost == 55, "MoneyBundle listing must cost 55")
assert(player.currency == cashBeforeListing - 55, "listing fee must be charged once")
local replayListing = listOnly(listArgs)
assert(replayListing.payload.cost == 55 and player.currency == cashBeforeListing - 55, "listing retry must not charge twice")
local changedListing = { opId = listArgs.opId, fullType = bundleOwned.fullType, itemId = normalAxe.id }
assert(listOnly(changedListing).status == "mismatch", "same listing operation ID with another item must be rejected")
local missingListing = listOnly({ opId = "gs-1000-2000-2", fullType = "Base.Axe", itemId = "missing" })
assert(missingListing.ok == false and player.currency == cashBeforeListing - 55, "missing exact item must not charge a listing fee")

local bundleKey = Variants.getKey("Base.MoneyBundle")
local found, changed = Variants.setHidden(player.data, bundleKey, true)
assert(found and changed and #Variants.getUnlockedRows(player.data, false) == 0, "hidden product must disappear from the ordinary shop list")
assert(#Variants.getUnlockedRows(player.data, true) == 1, "hidden manager must retain the product")
Variants.setHidden(player.data, bundleKey, false)

local ordinaryRecycleArgs = {
    opId = "gs-1000-2000-7",
    mode = "recycle",
    itemIds = { normalAxe.id, wornAxe.id },
    allowDestroyContents = false,
    containerContentSignatures = {},
}
local ordinaryRecycle = recycleSelected(ordinaryRecycleArgs)
assert(ordinaryRecycle.ok == true and ordinaryRecycle.payload.removed == 2,
    "ordinary and broken items must both complete through selected recycling")
assert(ordinaryRecycle.payload.payout == normalQuote.recycleValue + wornQuote.recycleValue,
    "ordinary transaction payout must match the values shown by the quote policy")

print("[Journey 3] Player buys, unpacks and recycles MoneyBundle")
local cashBeforeLoop = player.currency
local inventoryBeforeBuy = inventoryCount("Base.MoneyBundle")
local buyArgs = { opId = "gs-1000-2000-3", id = "unlocked_" .. bundleKey, quantity = 1 }
local bought = buyListed(buyArgs)
assert(bought.ok == true and bought.payload.price == 110, "MoneyBundle purchase price must be 110")
assert(player.currency == cashBeforeLoop - 110 and inventoryCount("Base.MoneyBundle") == inventoryBeforeBuy + 1, "purchase must charge and grant exactly once")
local replayBuy = buyListed(buyArgs)
assert(replayBuy.payload.price == 110 and player.currency == cashBeforeLoop - 110 and inventoryCount("Base.MoneyBundle") == inventoryBeforeBuy + 1, "purchase retry must not charge or grant twice")
assert(buyListed({ opId = buyArgs.opId, id = buyArgs.id, quantity = 2 }).status == "mismatch", "changed retry quantity must be rejected")

local moneyItems = unpackFirst("Base.MoneyBundle")
assert(#moneyItems == 100 and inventoryCount("Base.Money") == 100, "MoneyBundle must unpack into 100 banknotes")
local moneyIds = {}
for i = 1, #moneyItems do moneyIds[i] = moneyItems[i].id end
local recycleArgs = { opId = "gs-1000-2000-4", mode = "recycle", itemIds = moneyIds, allowDestroyContents = false, containerContentSignatures = {} }
local recycled = recycleSelected(recycleArgs)
assert(recycled.ok == true and recycled.payload.removed == 100 and recycled.payload.payout == 100,
    "100 banknotes must recycle for 100; removed=" .. tostring(recycled.payload.removed) .. ", payout=" .. tostring(recycled.payload.payout))
assert(player.currency == cashBeforeLoop - 10, "buy-unpack-recycle loop must lose 10 instead of making profit")
local replayRecycle = recycleSelected(recycleArgs)
assert(replayRecycle.payload.payout == 100 and player.currency == cashBeforeLoop - 10, "recycle retry must not pay twice")

print("[Journey 4] Player encounters insufficient balance and an unknown Mod item")
local cashBeforeFailure = player.currency
local inventoryBeforeFailure = inventoryCount("Base.MoneyBundle")
local failedBuy = buyListed({ opId = "gs-1000-2000-5", id = "unlocked_" .. bundleKey, quantity = 100000 })
assert(failedBuy.ok == false and failedBuy.code == "CurrencyNotEnough", "unaffordable purchase must fail")
assert(player.currency == cashBeforeFailure and inventoryCount("Base.MoneyBundle") == inventoryBeforeFailure, "failed purchase must not change currency or inventory")
local unknownRecycle = recycleSelected({ opId = "gs-1000-2000-6", mode = "recycle", itemIds = { unknownModItem.id }, allowDestroyContents = false, containerContentSignatures = {} })
assert(unknownRecycle.payload.payout == 1, "unknown Mod item must pay one coin")

print("[Journey 5] Completed results survive a reconnect-style ledger reload")
Ops.normalized = {}
local persistedBuy = Ops.get(transactionRoot, player.owner, "buyShop", buyArgs)
local persistedRecycle = Ops.get(transactionRoot, player.owner, "recycleSelectedItems", recycleArgs)
assert(persistedBuy.status == "done" and persistedRecycle.status == "done", "completed operations must remain replayable after reload")

print("[Journey 6] Administrator pricing changes are visible after a state-style reload")
local defaults = Admin.getSandboxDefaults()
Admin.applyRuntime(defaults, { ["Base.MoneyBundle"] = { buyPrice = 120, shopMode = "auto" } }, {}, 20)
local overridden = Policy.quote("Base.MoneyBundle", nil, { kind = "shop" })
assert(overridden.finalBuy == 120 and overridden.safeMinimum == 110, "administrator override must be visible while retaining the safety warning baseline")
local snapshot = Admin.buildSnapshot()
Admin.applyRuntime(snapshot.settings, snapshot.itemOverrides, snapshot.shopVariantOverrides, snapshot.economyRevision)
assert(Policy.quote("Base.MoneyBundle", nil, { kind = "shop" }).finalBuy == 120, "economy override must survive snapshot reapplication")
Admin.applyRuntime(defaults, {}, {}, 21)
Policy.rebuildTransformIndex(nil)
assert(Policy.quote("Base.MoneyBundle", nil, { kind = "shop" }).finalBuy == 110, "restoring automatic pricing must return MoneyBundle to 110")

assert(player.data.stats.boughtItems == 1, "only one successful purchase may count")
assert(player.data.stats.recycledItems == 103, "two ordinary items, 100 banknotes and one Mod item must count as recycled")
assert(player.data.stats.recycledPoints == 101 + normalQuote.recycleValue + wornQuote.recycleValue,
    "recycle statistics must equal the real payout")

print("Test-GodSystemV422022PlayerJourneyRuntime OK")
