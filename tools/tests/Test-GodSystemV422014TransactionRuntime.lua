isServer = function() return true end

dofile(arg[1])

local kind = "setShopItemsHidden"
local root = {}
local original = {
    opId = "gs-1-2-3",
    hidden = true,
    variantKeys = { "weapon.beta", "", "weapon.alpha", "weapon.beta" },
}
local retry = {
    opId = "gs-1-2-3",
    hidden = true,
    variantKeys = { "weapon.alpha", "weapon.beta" },
}

local fingerprint = GodSystemTransactionOps.fingerprint(kind, original)
assert(fingerprint == "shopHidden|1|k:weapon.alpha|k:weapon.beta", "batch fingerprint must sort and deduplicate non-empty keys")
assert(GodSystemTransactionOps.begin(root, "player", kind, original) == true, "first batch request must begin")

local pending = GodSystemTransactionOps.get(root, "player", kind, retry)
assert(pending and pending.status == "processing", "normalized retry must retain the original operation identity")

GodSystemTransactionOps.remember(root, "player", kind, original, true, "ShopItemsHidden", { 2, 0 }, { changed = 2 })
local replay = GodSystemTransactionOps.get(root, "player", kind, retry)
assert(replay and replay.status == "done" and replay.ok == true, "normalized retry must replay the first completed result")
assert(replay.payload and replay.payload.changed == 2, "replayed result must retain the original payload")

local mismatch = {
    opId = "gs-1-2-3",
    hidden = false,
    variantKeys = { "weapon.alpha", "weapon.beta" },
}
local rejected = GodSystemTransactionOps.get(root, "player", kind, mismatch)
assert(rejected and rejected.status == "mismatch", "same operation ID with a different target state must be rejected")

print("Test-GodSystemV422014TransactionRuntime passed")
