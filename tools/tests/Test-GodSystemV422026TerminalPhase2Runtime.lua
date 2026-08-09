local luaRoot = assert(arg[1], "lua root is required")

GodSystemConfig = {
    AutoRecyclerFullType = "GodSystem.SystemSpaceTerminal",
    TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
    TerminalReliefLevelKey = "GodSystemTerminalReliefLevel",
    TerminalReliefOffsetKey = "GodSystemTerminalReliefOffset",
    TerminalReliefUpgradeCost = 2000,
    TerminalReliefPerLevel = 5,
    TerminalReliefMaxOffset = 2000,
    TerminalPhase2CapacityPerLevel = 10,
    TerminalPhase2CapacityMaxOffset = 5000,
    TerminalPhase2UpgradeCost = 2000,
    TerminalPhase2LevelKey = "GodSystemTerminalPhase2Level",
    TerminalPhase2OffsetKey = "GodSystemTerminalPhase2Offset",
    TerminalCompensationOffsetKey = "GodSystemTerminalCompensationOffset",
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

local testPlayer = { id = 1 }
local nextId = 100
local function newReliefItem()
    nextId = nextId + 1
    local item = {
        id = nextId,
        fullType = "GodSystem.SystemTerminalRelief",
        hungChange = -0.01,
        favorite = false,
        unwanted = false,
        modData = {},
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getModData() return self.modData end
    function item:setHungChange(value) self.hungChange = value end
    function item:getHungChange() return self.hungChange end
    function item:getActualWeight() return -(self.hungChange * 100) end
    function item:setFavorite(value) self.favorite = value == true end
    function item:isFavorite() return self.favorite end
    function item:setUnwanted(player, value) assert(player == testPlayer) self.unwanted = value == true end
    function item:isUnwanted(player) assert(player == testPlayer) return self.unwanted end
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
    end
    local terminal = { id = 77, fullType = "GodSystem.SystemSpaceTerminal", modData = {} }
    function terminal:getID() return self.id end
    function terminal:getFullType() return self.fullType end
    function terminal:getModData() return self.modData end
    function terminal:getInventory() return inventory end
    return terminal, items
end

dofile(luaRoot .. "/shared/GodSystem_TerminalRelief.lua")

local data = { autoRecyclerReliefLevel = 0 }
assert(GodSystemTerminalRelief.getPhase2Level(data) == 0, "old saves must default phase two to zero")
assert(GodSystemTerminalRelief.getPhase2MaxLevel() == 500, "default cap must yield 500 +10 levels")
local info = GodSystemTerminalRelief.getPhase2UpgradeInfo(data)
assert(info.level == 0 and info.offset == 0 and info.nextOffset == 10 and info.nextCost == 2000)

local terminal, items = newTerminal()
assert(GodSystemTerminalRelief.setPhase2Level(data, 1))
local ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok and #items == 1 and report.phase2Offset == 10 and report.offset == 10, "first phase-two level must add ten space")
assert(items[1]:getActualWeight() == -10, "phase two must use the native negative Food weight")
assert(items[1]:getModData().GodSystemTerminalPhase2Offset == 10, "phase-two source metadata must be preserved")
assert(items[1]:getModData().GodSystemTerminalCompensationOffset == 10, "combined metadata must be preserved")

data.autoRecyclerReliefLevel = 2
assert(GodSystemTerminalRelief.getOffset(data) == 10, "existing relief must remain independent")
assert(GodSystemTerminalRelief.getTotalOffset(data) == 20, "relief and phase two must add together")
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok and report.reliefOffset == 10 and report.phase2Offset == 10 and report.offset == 20)
assert(items[1]:getActualWeight() == -20, "one helper item must carry the total compensation")

data.autoRecyclerReliefLevel = 0
assert(GodSystemTerminalRelief.setPhase2Level(data, 500))
assert(GodSystemTerminalRelief.getPhase2Offset(data) == 5000)
ok, report = GodSystemTerminalRelief.ensureTerminal(terminal, data, testPlayer)
assert(ok and report.offset == 5000 and items[1]:getActualWeight() == -5000, "maximum phase two must provide +5000")

GodSystemAdminConfig.settings.TerminalPhase2CapacityMaxOffset = 0
assert(GodSystemTerminalRelief.getPhase2MaxLevel() == 0, "admin zero must disable phase two")
assert(GodSystemTerminalRelief.getPhase2Level(data) == 0, "saved levels must clamp when phase two is disabled")
assert(GodSystemTerminalRelief.getTotalOffset(data) == 0, "disabling phase two must remove only its own compensation")

print("Test-GodSystemV422026TerminalPhase2Runtime passed")
