local luaRoot = assert(arg[1], "lua root is required")

GodSystemConfig = {
    AutoRecyclerFullType = "GodSystem.SystemSpaceTerminal",
    AutoRecyclerCapacityLevelKey = "GodSystemTerminalCapacityLevel",
    AutoRecyclerReductionLevelKey = "GodSystemTerminalReductionLevel",
    AutoRecyclerLevelKey = "GodSystemAutoRecyclerLevel",
    TerminalCapacityHardLimit = 2000,
    TerminalCapacityMaxValue = 1999,
    TerminalCapacityLevels = {
        { level = 1, value = 10, upgradeCost = 0 },
        { level = 2, value = 15, upgradeCost = 60 },
        { level = 3, value = 20, upgradeCost = 120 },
        { level = 4, value = 25, upgradeCost = 220 },
        { level = 5, value = 30, upgradeCost = 350 },
        { level = 6, value = 35, upgradeCost = 550 },
        { level = 7, value = 42, upgradeCost = 800 },
        { level = 8, value = 49, upgradeCost = 1100 },
    },
    TerminalReductionLevels = {
        { level = 1, value = 50, upgradeCost = 0 },
        { level = 8, value = 99, upgradeCost = 2500 },
    },
}
for value = 54, 1999, 5 do
    GodSystemConfig.TerminalCapacityLevels[#GodSystemConfig.TerminalCapacityLevels + 1] = {
        level = #GodSystemConfig.TerminalCapacityLevels + 1,
        value = value,
        upgradeCost = 1100,
    }
end

package.path = luaRoot .. "/shared/?.lua;" .. package.path
package.loaded.GodSystem_Config = true

dofile(luaRoot .. "/shared/GodSystem_ShopVariants.lua")
local key = "Moveables.Moveable@worldSprite=furniture_test_01"
local shopData = { unlockedShopItems = { [key] = { fullType = "Moveables.Moveable", worldSprite = "furniture_test_01" } } }
local ok, row = GodSystemShopVariants.deleteUnlocked(shopData, key)
assert(ok == true and row and shopData.unlockedShopItems[key] == nil, "exact listing deletion must remove one row")
ok = GodSystemShopVariants.deleteUnlocked(shopData, key)
assert(ok == false, "repeated deletion must not report success")

local originalEffectiveCalls, originalRoomCalls = 0, 0
local index = {}
function index:getCapacity() return self.nativeCapacity or 49 end
function index:getEffectiveCapacity() originalEffectiveCalls = originalEffectiveCalls + 1 return self.nativeCapacity or 49 end
function index:hasRoomFor(_, _) originalRoomCalls = originalRoomCalls + 1 return false end
function index:getContentsWeight() return self.contentsWeight or 0 end
function index:getContainingItem() return self.parent end
ItemContainer = { class = {}, __classmetatables = {} }
ItemContainer.__classmetatables[ItemContainer.class] = { __index = index }
Events = nil
dofile(luaRoot .. "/shared/GodSystem_TerminalCapacity.lua")
assert(GodSystemTerminalCapacity.install() == true, "capacity override must install in a ready runtime")

local terminal = { modData = {}, fullType = "GodSystem.SystemSpaceTerminal" }
function terminal:getFullType() return self.fullType end
function terminal:getModData() return self.modData end
local container = setmetatable({ parent = terminal, nativeCapacity = 49, contentsWeight = 1200 }, { __index = index })
function terminal:getInventory() return container end
assert(GodSystemTerminalCapacity.register(terminal, 1999) == true)
assert(container:getEffectiveCapacity(nil) == 1999, "registered terminal must expose its target capacity")
assert(container:hasRoomFor(nil, 798) == true, "terminal must accept weight below the custom boundary")
assert(container:hasRoomFor(nil, 800) == false, "terminal must reject weight above the custom boundary")

local other = setmetatable({ nativeCapacity = 20, contentsWeight = 0 }, { __index = index })
assert(other:getEffectiveCapacity(nil) == 20 and originalEffectiveCalls > 0, "non-terminal capacity must call vanilla behavior")
assert(other:hasRoomFor(nil, 1) == false and originalRoomCalls > 0, "non-terminal room checks must call vanilla behavior")

print("Test-GodSystemV11662Runtime passed")
