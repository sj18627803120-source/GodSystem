local transactionPath = assert(arg[1], "transaction module path is required")

isServer = function() return true end
dofile(transactionPath)

local Ops = assert(GodSystemTransactionOps, "transaction module did not load")
local root = {}
local owner = "player-a"

local buy = { opId = "gs-100-200-1", id = "admin:Base.MoneyBundle", quantity = 2 }
assert(Ops.fingerprint("buyShop", buy) == "buyShop|admin:Base.MoneyBundle|q:2", "buy fingerprint mismatch")
assert(Ops.get(root, owner, "buyShop", buy) == nil, "new operation must not have a cached result")
assert(Ops.begin(root, owner, "buyShop", buy) == true, "new buy operation must begin")
assert(Ops.get(root, owner, "buyShop", buy).status == "processing", "buy operation must enter processing state")
Ops.remember(root, owner, "buyShop", buy, true, "ShopBuySuccess", { 2, 220 }, { price = 220 })
local completed = Ops.get(root, owner, "buyShop", buy)
assert(completed.status == "done" and completed.ok == true and completed.payload.price == 220, "buy result must be replayable")
assert(Ops.begin(root, owner, "buyShop", buy) == false, "completed buy operation must not begin twice")

local changedBuy = { opId = buy.opId, id = buy.id, quantity = 3 }
assert(Ops.get(root, owner, "buyShop", changedBuy).status == "mismatch", "same operation ID with another quantity must be rejected")

local listing = { opId = "gs-100-200-2", fullType = "Base.MoneyBundle", itemId = "9001" }
assert(Ops.fingerprint("listOnlyAutoShop", listing) == "listOnly|Base.MoneyBundle|9001", "listing fingerprint mismatch")
assert(Ops.begin(root, owner, "listOnlyAutoShop", listing) == true, "new listing operation must begin")
Ops.remember(root, owner, "listOnlyAutoShop", listing, true, "ListOnlySuccess", {}, { cost = 55 })
assert(Ops.get(root, owner, "listOnlyAutoShop", listing).payload.cost == 55, "listing result must be replayable")

print("Test-GodSystemV422021TransactionRuntime OK")
