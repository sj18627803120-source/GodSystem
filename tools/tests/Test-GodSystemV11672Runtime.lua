local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. package.path

GodSystemConfig = {
    AutoLoaderAmmoCapacity = 2000,
    AutoLoaderFullType = "GodSystem.SystemAutoLoader",
}
package.loaded.GodSystem_Config = true
local configuredCapacity = 2000
GodSystemAdminConfig = { getSetting = function(_, fallback) return configuredCapacity or fallback end }
package.loaded.GodSystem_AdminConfig = true

ItemTag = { AMMO = "ammo" }
instanceof = function(value, className) return value and value.className == className end
syncItemFields = function() end
syncItemModData = function() end
sendRemoveItemFromContainer = function() end
sendAddItemToContainer = function() end

local function list(values)
    local result = { values = values or {} }
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    return result
end

local nextId = 100
local function item(fullType, options)
    options = options or {}
    nextId = nextId + 1
    local value = {
        fullType = fullType,
        id = options.id or nextId,
        favorite = options.favorite == true,
        tags = options.tags or {},
        data = {},
        current = options.current,
        maximum = options.maximum,
        ammoType = options.ammoType,
        className = options.className,
        failSet = options.failSet == true,
    }
    function value:getFullType() return self.fullType end
    function value:getID() return self.id end
    function value:isFavorite() return self.favorite end
    function value:hasTag(tag) return self.tags[tag] == true end
    function value:getModData() return self.data end
    function value:getContainer() return self.container end
    function value:getInventory() return self.inventory end
    function value:getAmmoType()
        if not self.ammoType then return nil end
        local key = self.ammoType
        return { getItemKey = function() return key end }
    end
    function value:getCurrentAmmoCount() return self.current or 0 end
    function value:getMaxAmmo() return self.maximum or 0 end
    function value:setCurrentAmmoCount(count)
        if self.failSet then error("simulated magazine update failure") end
        self.current = count
    end
    function value:getDisplayName() return self.fullType end
    return value
end

local function container(values)
    local result = { items = list(values or {}) }
    function result:getItems() return self.items end
    function result:AddItem(value)
        if type(value) == "string" then value = item(value, { tags = { ammo = true } }) end
        self.items.values[#self.items.values + 1] = value
        value.container = self
        return value
    end
    function result:Remove(value)
        for i = #self.items.values, 1, -1 do
            if self.items.values[i] == value then
                table.remove(self.items.values, i)
                value.container = nil
                return
            end
        end
    end
    for i = 1, #result.items.values do result.items.values[i].container = result end
    return result
end

local function bag(fullType, id, values)
    local value = item(fullType, { id = id })
    value.inventory = container(values)
    value.inventory.parentItem = value
    return value
end

getScriptManager = function()
    return { FindItem = function(_, fullType)
        if fullType == "Missing.Ammo" then return nil end
        return { getDisplayName = function() return fullType end }
    end }
end

local loader = item("GodSystem.SystemAutoLoader", { id = 1 })
local direct9 = item("Base.Bullets9mm", { id = 11, tags = { ammo = true } })
local favorite9 = item("Base.Bullets9mm", { id = 12, tags = { ammo = true }, favorite = true })
local ammoBox = item("Base.Bullets9mmBox", { id = 13 })
local nested45 = item("Base.Bullets45", { id = 21, tags = { ammo = true } })
local nested9 = item("Base.Bullets9mm", { id = 22, tags = { ammo = true } })
local bagHigh = bag("Base.Bag_DuffelBag", 50, { nested9 })
local bagLow = bag("Base.Bag_Schoolbag", 40, { nested45 })
local magazineHigh = item("Base.9mmClip", { id = 31, current = 12, maximum = 15, ammoType = "Base.Bullets9mm" })
local magazineLow = item("Base.9mmClip", { id = 32, current = 5, maximum = 15, ammoType = "Base.Bullets9mm" })
local weapon = item("Base.Pistol", { id = 33, current = 0, maximum = 15, ammoType = "Base.Bullets9mm", className = "HandWeapon" })
local root = container({ loader, direct9, favorite9, ammoBox, bagHigh, bagLow, magazineLow, magazineHigh, weapon })
local player = { inventory = root }
function player:getInventory() return self.inventory end
function player:getModData() self.data = self.data or {}; return self.data end

local AutoLoader = require "GodSystem_AutoLoader"
assert(AutoLoader.getCapacity() == 2000, "default per-ammo capacity must be 2000")
assert(AutoLoader.depositDurationSeconds(1) == 1.5, "one round must take 1.5 seconds")
assert(AutoLoader.depositDurationSeconds(2801) == 15, "deposit duration must cap at 15 seconds")

local records, scan = AutoLoader.scanDeposit(player, loader)
assert(#records == 3, "scan must include only non-favorite loose ammo")
assert(records[1].itemId == "11", "main-inventory direct ammo must be first")
assert(records[2].itemId == "21" and records[3].itemId == "22",
    "nested containers must use stable container/item IDs")
assert(scan.favoriteSkipped == 1, "favorite loose ammo must be skipped")

local deposited = AutoLoader.settleDepositRecords(player, loader, records)
assert(deposited.stored == 3 and AutoLoader.getBalance(loader, "Base.Bullets9mm") == 2,
    "deposit must remove real rounds and update only the selected loader")
assert(AutoLoader.getBalance(loader, "Base.Bullets45") == 1, "ammo types must have independent balances")

AutoLoader.setBalance(loader, "Base.Bullets9mm", 4)
local fill = AutoLoader.fillMagazines(player, { loader }, 256)
assert(fill.rounds == 4 and magazineHigh.current == 15 and magazineLow.current == 6,
    "fill must prioritize the magazine closest to full")
assert(weapon.current == 0, "weapons and internal magazines must not be filled")
assert(AutoLoader.getBalance(loader, "Base.Bullets45") == 1,
    "one ammo type must never pay for another magazine type")

AutoLoader.setBalance(loader, "Base.Bullets9mm", 105)
local withdrawn = AutoLoader.withdrawAmmo(player, loader, "Base.Bullets9mm", 100)
assert(withdrawn.created == 100 and AutoLoader.getBalance(loader, "Base.Bullets9mm") == 5,
    "withdraw must deduct only the number of real rounds created")

local capacityLoader = item("GodSystem.SystemAutoLoader", { id = 60 })
local capacityAmmo = item("Base.Bullets556", { id = 64, tags = { ammo = true } })
root:AddItem(capacityLoader)
root:AddItem(capacityAmmo)
configuredCapacity = 3000
AutoLoader.setBalance(capacityLoader, "Base.Bullets556", 2500)
configuredCapacity = 1000
assert(AutoLoader.getBalance(capacityLoader, "Base.Bullets556") == 2500,
    "lowering the configured capacity must not destroy an existing over-capacity balance")
local capacityRecords = AutoLoader.scanDeposit(player, capacityLoader)
for index = 1, #capacityRecords do
    assert(capacityRecords[index].itemId ~= "64",
        "an over-capacity ammo type must reject new deposits without trimming its balance")
end
local capacityWithdraw = AutoLoader.withdrawAmmo(player, capacityLoader, "Base.Bullets556", 1)
assert(capacityWithdraw.created == 1 and AutoLoader.getBalance(capacityLoader, "Base.Bullets556") == 2499,
    "over-capacity balances must remain usable and decrease by the exact withdrawn amount")
configuredCapacity = 2000

local loaderA = item("GodSystem.SystemAutoLoader", { id = 61 })
local loaderB = item("GodSystem.SystemAutoLoader", { id = 62 })
root:AddItem(loaderA)
root:AddItem(loaderB)
AutoLoader.setBalance(loaderA, "Base.Bullets45", 2)
AutoLoader.setBalance(loaderB, "Base.Bullets45", 5)
local magazine45 = item("Base.45Clip", { id = 63, current = 0, maximum = 6, ammoType = "Base.Bullets45" })
root:AddItem(magazine45)
local multi = AutoLoader.fillMagazines(player, { loaderB, loaderA }, 256)
assert(multi.rounds >= 6 and AutoLoader.getBalance(loaderA, "Base.Bullets45") == 0,
    "multi-loader fill must consume the lower balance first")
assert(AutoLoader.getBalance(loaderB, "Base.Bullets45") == 1,
    "multi-loader fill must continue from the next stable loader")

local rollbackLoaderA = item("GodSystem.SystemAutoLoader", { id = 71 })
local rollbackLoaderB = item("GodSystem.SystemAutoLoader", { id = 72 })
local failingMagazine = item("Base.38Clip", {
    id = 73,
    current = 0,
    maximum = 6,
    ammoType = "Base.Bullets38",
    failSet = true,
})
local rollbackRoot = container({ rollbackLoaderA, rollbackLoaderB, failingMagazine })
local rollbackPlayer = { inventory = rollbackRoot }
function rollbackPlayer:getInventory() return self.inventory end
function rollbackPlayer:getModData() self.data = self.data or {}; return self.data end
AutoLoader.setBalance(rollbackLoaderA, "Base.Bullets38", 2)
AutoLoader.setBalance(rollbackLoaderB, "Base.Bullets38", 4)
local rolledBack = AutoLoader.fillMagazines(rollbackPlayer, { rollbackLoaderB, rollbackLoaderA }, 256)
assert(rolledBack.rounds == 0 and rolledBack.remainingNeed == 6,
    "failed magazine mutation must report the original unresolved need")
assert(AutoLoader.getBalance(rollbackLoaderA, "Base.Bullets38") == 2
    and AutoLoader.getBalance(rollbackLoaderB, "Base.Bullets38") == 4,
    "failed magazine mutation must restore the exact amount taken from every loader")

AutoLoader.setBalance(loader, "Missing.Ammo", 10)
local state = AutoLoader.stateFor(loader)
local missing
for i = 1, #state.ammo do if state.ammo[i].fullType == "Missing.Ammo" then missing = state.ammo[i] end end
assert(missing and missing.available == false and missing.count == 10,
    "missing-mod ledger rows must persist and remain visible")

local sessionAmmo = item("Base.Bullets223", { id = 81, tags = { ammo = true } })
root:AddItem(sessionAmmo)
local sessionPayload = assert(AutoLoader.startDepositSession(player, "1", "gsa-1-1-0"))
local _, sessionReason, _, _, aggregate = AutoLoader.completeDepositBatch(player, sessionPayload.sessionId, 1)
assert(sessionReason == nil and aggregate and aggregate.finished == true,
    "single-batch deposit session must finish")
assert(aggregate.sessionId == sessionPayload.sessionId and aggregate.loaderId == "1",
    "deposit completion payload must identify both the session and loader")

local pressureLoader = item("GodSystem.SystemAutoLoader", { id = 90000 })
local pressureItems = { pressureLoader }
for index = 1, 20050 do
    pressureItems[#pressureItems + 1] = item("Pressure.Ammo" .. tostring(index), {
        id = 100000 + index,
        tags = { ammo = true },
    })
end
local pressurePlayer = { inventory = container(pressureItems) }
function pressurePlayer:getInventory() return self.inventory end
local pressureStarted = os.clock()
local pressureRecords, pressureStats = AutoLoader.scanDeposit(pressurePlayer, pressureLoader)
local pressureSeconds = os.clock() - pressureStarted
assert(#pressureRecords == AutoLoader.MaxSnapshotItems,
    "deposit pressure scan must stop selecting at the 20000-item snapshot limit")
assert(pressureStats.limitSkipped == 50,
    "deposit pressure scan must report eligible rounds beyond the snapshot limit")
print(string.format("Test-GodSystemV11672Pressure items=%d seconds=%.3f", #pressureItems - 1, pressureSeconds))

print("Test-GodSystemV11672Runtime passed")
