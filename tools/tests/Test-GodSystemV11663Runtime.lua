local luaRoot = assert(arg[1], "lua root is required")
unpack = unpack or table.unpack

GodSystemConfig = {
    AutoRecyclerFullType = "GodSystem.SystemSpaceTerminal",
    TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
    TerminalReliefLevelKey = "GodSystemTerminalReliefLevel",
    TerminalReliefUpgradeCost = 2000,
    TerminalReliefPerLevel = 5,
    TerminalReliefMaxOffset = 2000,
}
GodSystemAdminConfig = {
    settings = {},
    getSetting = function(key, fallback)
        local value = GodSystemAdminConfig.settings[key]
        return value ~= nil and value or fallback
    end,
}
package.path = luaRoot .. "/shared/?.lua;" .. package.path
package.loaded.GodSystem_Config = true
package.loaded.GodSystem_AdminConfig = true

local function newList(items)
    function items:size() return #self end
    function items:get(index) return self[index + 1] end
    return items
end

local nextId = 100
local testPlayer = { id = 1 }
local function newReliefItem()
    nextId = nextId + 1
    local item = {
        id = nextId,
        fullType = "GodSystem.SystemTerminalRelief",
        hungChange = -0.01,
        favorite = false,
        unwanted = false,
        modData = {},
        setHungCalls = 0,
        setFavoriteCalls = 0,
        setUnwantedCalls = 0,
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getModData() return self.modData end
    function item:setHungChange(value) self.setHungCalls = self.setHungCalls + 1 self.hungChange = value end
    function item:getHungChange() return self.hungChange end
    function item:getActualWeight() return -(self.hungChange * 100) end
    function item:setFavorite(value) self.setFavoriteCalls = self.setFavoriteCalls + 1 self.favorite = value == true end
    function item:isFavorite() return self.favorite end
    function item:setUnwanted(player, value)
        assert(player == testPlayer, "setUnwanted requires the owning player")
        self.setUnwantedCalls = self.setUnwantedCalls + 1
        self.unwanted = value == true
    end
    function item:isUnwanted(player)
        assert(player == testPlayer, "isUnwanted requires the owning player")
        return self.unwanted
    end
    return item
end

local function newTerminal()
    local items = newList({})
    local inventory = {}
    function inventory:getItems() return items end
    function inventory:AddItem(fullType)
        assert(fullType == "GodSystem.SystemTerminalRelief")
        local item = newReliefItem()
        items[#items + 1] = item
        return item
    end
    function inventory:Remove(item)
        for i = #items, 1, -1 do
            if items[i] == item then table.remove(items, i) return item end
        end
        return nil
    end
    local terminal = { id = 77, fullType = "GodSystem.SystemSpaceTerminal", modData = {} }
    function terminal:getID() return self.id end
    function terminal:getFullType() return self.fullType end
    function terminal:getModData() return self.modData end
    function terminal:getInventory() return inventory end
    return terminal, inventory, items
end

dofile(luaRoot .. "/shared/GodSystem_TerminalRelief.lua")

local data = { autoRecyclerReliefLevel = 0 }
assert(GodSystemTerminalRelief.getLevel(data) == 0)
assert(GodSystemTerminalRelief.getMaxLevel() == 400)
local info = GodSystemTerminalRelief.getUpgradeInfo(data)
assert(info.level == 0 and info.offset == 0 and info.nextOffset == 5 and info.nextCost == 2000)

local terminal, inventory, items = newTerminal()
local ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok == true and #items == 0 and report.offset == 0, "level zero must not create a hidden item")

GodSystemTerminalRelief.setLevel(data, 1)
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok == true and #items == 1 and report.offset == 5, "level one must create one hidden item")
local relief = items[1]
assert(relief:getActualWeight() == -5, "level one must contribute -5 weight")
assert(relief:isFavorite() and relief:isUnwanted(testPlayer), "hidden item must carry bulk-transfer guards")
assert(GodSystemTerminalRelief.isReliefItem(relief), "internal item identity must be exact")
local writeCounts = { relief.setHungCalls, relief.setFavoriteCalls, relief.setUnwantedCalls }
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok == true and #report.items == 0 and #report.addedItems == 0 and #report.removedItems == 0, "unchanged relief audit must report no writes")
assert(relief.setHungCalls == writeCounts[1] and relief.setFavoriteCalls == writeCounts[2]
    and relief.setUnwantedCalls == writeCounts[3], "unchanged relief audit must skip native setters")

items[#items + 1] = newReliefItem()
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok == true and #items == 1 and report.removedDuplicates == 1, "audit must remove duplicate internal items")

GodSystemTerminalRelief.setLevel(data, 400)
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok == true and report.offset == 2000 and items[1]:getActualWeight() == -2000, "maximum relief must be -2000")
info = GodSystemTerminalRelief.getUpgradeInfo(data)
assert(info.level == 400 and info.nextCost == nil and info.nextOffset == nil, "maximum relief must stop further purchases")

local snapshot = GodSystemTerminalRelief.snapshot(terminal, testPlayer)
GodSystemTerminalRelief.setLevel(data, 10)
assert(GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer) == true)
assert(items[1]:getActualWeight() == -50)
assert(GodSystemTerminalRelief.restore(snapshot) == true)
assert(items[1]:getActualWeight() == -2000, "rollback must restore the previous internal weight")

local playerItems = newList({ newReliefItem() })
local playerInventory = {}
function playerInventory:getItems() return playerItems end
function playerInventory:Remove(item)
    for i = #playerItems, 1, -1 do
        if playerItems[i] == item then table.remove(playerItems, i) return item end
    end
end
local player = {}
function player:getInventory() return playerInventory end
local removed = GodSystemTerminalRelief.removeEscapedFromPlayer(player, terminal)
assert(removed == 1 and #playerItems == 0, "escaped internal items must be removed")

GodSystemAdminConfig.settings.TerminalReliefUpgradeCost = 1234
GodSystemAdminConfig.settings.TerminalReliefPerLevel = 8
GodSystemAdminConfig.settings.TerminalReliefMaxOffset = 21
local configured = { autoRecyclerReliefLevel = 99 }
assert(GodSystemTerminalRelief.getMaxLevel() == 3, "sandbox/admin settings must change the runtime maximum")
assert(GodSystemTerminalRelief.getLevel(configured) == 3, "saved levels must clamp to the configured maximum")
assert(GodSystemTerminalRelief.getOffset(configured) == 21, "the final configured level must clamp to the exact maximum offset")
local configuredInfo = GodSystemTerminalRelief.getUpgradeInfo({ autoRecyclerReliefLevel = 2 })
assert(configuredInfo.nextCost == 1234 and configuredInfo.nextOffset == 21, "configured price and step must drive upgrade quotes")

print("Test-GodSystemV11663Runtime passed")
