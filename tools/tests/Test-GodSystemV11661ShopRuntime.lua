InventoryItemFactory = {}
function InventoryItemFactory.CreateItem(fullType)
    local item = { fullType = fullType, sprite = nil }
    function item:getWorldSprite() return self.sprite end
    function item:ReadFromWorldSprite(sprite) self.sprite = sprite end
    return item
end

dofile(arg[1])

local configured = GodSystemShopVariants.getConfiguredKeySet({
    { id = "bandage_single", items = { { fullType = "Base.Bandage", count = 1 } } },
    { id = "bundle_ignored", items = {
        { fullType = "Base.Nails", count = 2 },
        { fullType = "Base.Hammer", count = 1 },
    } },
})
assert(configured["Base.Bandage"] == true, "configured single item must be treated as already listed")
assert(configured["Base.Nails"] == nil, "configured bundles must not hide individual listings")

local bed1 = "Moveables.Moveable@worldSprite=furniture_bedding_01_10"
local bed2 = "Moveables.Moveable@worldSprite=furniture_bedding_01_11"
local dataA = {
    unlockedShopItems = {
        ["Base.Bandage"] = { fullType = "Base.Bandage", label = "Bandage" },
        [bed1] = { fullType = "Moveables.Moveable", worldSprite = "furniture_bedding_01_10", hidden = false },
        legacyBed1 = { fullType = "Moveables.Moveable", worldSprite = "furniture_bedding_01_10", hidden = true },
        [bed2] = { fullType = "Moveables.Moveable", worldSprite = "furniture_bedding_01_11" },
    },
}

local normalized, removedConfigured, mergedDuplicates = GodSystemShopVariants.normalizeUnlocked(dataA, configured)
assert(normalized["Base.Bandage"] == nil, "legacy configured duplicate must be merged away")
assert(removedConfigured == 1, "configured duplicate migration count must be reported")
assert(mergedDuplicates == 1, "duplicate variant migration count must be reported")
assert(normalized[bed1] and normalized[bed1].hidden == true, "hidden intent must survive duplicate migration")
assert(normalized[bed2] and normalized[bed2].hidden == false, "old rows must default to visible")
assert(normalized[bed1].variantKey == bed1 and normalized[bed2].variantKey == bed2, "variant keys must be canonical")

local listed, source = GodSystemShopVariants.isListingKnown(dataA, configured, "Base.Bandage")
assert(listed == true and source == "configured", "configured item must block paid relisting")
listed, source = GodSystemShopVariants.isListingKnown(dataA, configured, bed1)
assert(listed == true and source == "unlocked", "hidden unlocked item must remain listed")

local ok, changed = GodSystemShopVariants.setHidden(dataA, bed2, true)
assert(ok == true and changed == true and dataA.unlockedShopItems[bed2].hidden == true, "hide must update the target row")
ok, changed = GodSystemShopVariants.setHidden(dataA, bed2, true)
assert(ok == true and changed == false, "repeated hide must be idempotent")
ok, changed = GodSystemShopVariants.setHidden(dataA, bed2, false)
assert(ok == true and changed == true and dataA.unlockedShopItems[bed2].hidden == false, "unhide must restore the row")

local visible = GodSystemShopVariants.getUnlockedRows(dataA, false)
local allRows = GodSystemShopVariants.getUnlockedRows(dataA, true)
assert(#visible == 1 and visible[1].variantKey == bed2, "direct shop must omit hidden rows")
assert(#allRows == 2, "management and lottery views must retain hidden rows")

local dataB = { unlockedShopItems = { [bed2] = { fullType = "Moveables.Moveable", worldSprite = "furniture_bedding_01_11" } } }
GodSystemShopVariants.normalizeUnlocked(dataB, configured)
assert(dataB.unlockedShopItems[bed2].hidden == false, "another player's state must remain independent")
assert(dataA.unlockedShopItems[bed2].hidden == false, "player A state must not be shared by reference")

print("Test-GodSystemV11661ShopRuntime passed")
