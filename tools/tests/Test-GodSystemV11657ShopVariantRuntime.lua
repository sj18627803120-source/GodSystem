InventoryItemFactory = {}
function InventoryItemFactory.CreateItem(fullType)
    local item = { fullType = fullType, sprite = nil }
    function item:getWorldSprite() return self.sprite end
    function item:ReadFromWorldSprite(sprite) self.sprite = sprite end
    return item
end

dofile(arg[1])

local bed1 = InventoryItemFactory.CreateItem("Moveables.Moveable")
bed1:ReadFromWorldSprite("furniture_bedding_01_10")
local bed2 = InventoryItemFactory.CreateItem("Moveables.Moveable")
bed2:ReadFromWorldSprite("furniture_bedding_01_11")
local key1 = GodSystemShopVariants.getKey(bed1.fullType, bed1)
local key2 = GodSystemShopVariants.getKey(bed2.fullType, bed2)
assert(key1 ~= key2)

local data = { unlockedShopItems = {
    [key1] = { fullType = bed1.fullType, worldSprite = bed1.sprite },
    [key2] = { fullType = bed2.fullType, worldSprite = bed2.sprite },
} }
GodSystemShopVariants.normalizeUnlocked(data)
assert(data.unlockedShopItems[key1] ~= nil)
assert(data.unlockedShopItems[key2] ~= nil)

local inventory = { items = {} }
function inventory:AddItem(item) self.items[#self.items + 1] = item return item end
function inventory:Remove(item)
    for i = #self.items, 1, -1 do if self.items[i] == item then table.remove(self.items, i) end end
end
local ok, added = GodSystemShopVariants.addItems(inventory, bed1.fullType, bed2.sprite, 1)
assert(ok == true and #added == 1)
assert(added[1]:getWorldSprite() == bed2.sprite)
print("Test-GodSystemV11657ShopVariantRuntime passed")
