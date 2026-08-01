local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({ luaRoot .. "/shared/?.lua", package.path }, ";")

local categories = { "food", "perishable", "drink", "medical", "weapon", "ammo", "tool", "material", "clothing", "book", "container", "furniture", "other" }
local Storage = { Categories = categories, MaxDepth = 32 }
function Storage.itemFullType(item) return tostring(item and item.fullType or "") end
function Storage.itemModName(item) return tostring(item and item.modName or "Base") end
function Storage.itemId(item) return tostring(item and item.id or "") end
function Storage.categoryOf(item) return tostring(item and item.category or "other") end
function Storage.statesOf() return {} end
function Storage.getItemContainer(item) return item and item.container or nil end
function Storage.isProtected(item) return item and item.protected == true end
function Storage.containerContains(container, item)
    for i = 1, #((container and container.items) or {}) do if container.items[i] == item then return true end end
    return false
end
function Storage.syncRemove() end
function Storage.syncAdd() end
local nextId = 0
function Storage.newId(prefix)
    nextId = nextId + 1
    return tostring(prefix or "id") .. "-" .. tostring(nextId)
end
GodSystemStorage = Storage
package.loaded["GodSystem_Storage"] = Storage

local function container(items)
    local row = { items = items or {} }
    function row:Remove(item)
        for i = #self.items, 1, -1 do if self.items[i] == item then table.remove(self.items, i); item.container = nil; return end end
    end
    function row:AddItem(item) self.items[#self.items + 1] = item; item.container = self; return item end
    function row:getItems()
        local list = self.items
        return { size = function() return #list end, get = function(_, index) return list[index + 1] end }
    end
    return row
end

local itemNumber = 0
local function item(fullType, category, count, children)
    itemNumber = itemNumber + 1
    local row = {
        id = "item-" .. tostring(itemNumber), fullType = fullType, category = category or "other",
        count = count or 1, condition = 77, modName = fullType:match("^([^.]+)") or "Base",
        modData = { owner = "test", nested = { value = 3 } },
    }
    if children then row.inventory = container(children); for i = 1, #children do children[i].container = row.inventory end end
    function row:getName() return self.fullType end
    function row:getCount() return self.count end
    function row:setCount(value) self.count = value end
    function row:getCondition() return self.condition end
    function row:setCondition(value) self.condition = value end
    function row:getModData() return self.modData end
    function row:getInventory() return self.inventory end
    return row
end

function instanceItem(fullType)
    if fullType == "Missing.Item" then return nil end
    local category = fullType == "Base.Bag" and "container" or fullType == "Base.Apple" and "food" or "other"
    return item(fullType, category, 1, fullType == "Base.Bag" and {} or nil)
end

dofile(luaRoot .. "/shared/GodSystem_ItemSnapshot.lua")
package.loaded["GodSystem_ItemSnapshot"] = GodSystemItemSnapshot
dofile(luaRoot .. "/shared/GodSystem_PersonalStorage.lua")
local Personal = GodSystemPersonalStorage
local Snapshot = GodSystemItemSnapshot

local child = item("Base.Apple", "food", 2)
local bag = item("Base.Bag", "container", 1, { child })
bag.modData.unsupported = function() end
bag.modData.loop = bag.modData
local source = container({ bag })
bag.container = source
local account = {}
local store = Personal.normalizeData(account)
assert(store.generalCapacity == 0 and store.capacities.container == 0, "old account must gain an empty personal-storage slice")
assert(Personal.addCategoryCapacity(store, "container", 200).ok, "permit capacity expansion failed")
local captured = Snapshot.capture(bag)
assert(captured.ok and captured.data.report.simplified == true, "unsupported ModData must be reported as simplified")
assert(Snapshot.count(captured.data.snapshot) == 3, "stack count plus nested content must consume three slots")
local deposited = Personal.deposit(store, bag, source, "deposit-1")
assert(deposited.ok and deposited.data.itemCount == 3 and #source.items == 0, "nested deposit transaction failed")
local replay = Personal.deposit(store, bag, source, "deposit-1")
assert(replay.ok and replay.data.entryId == deposited.data.entryId, "deposit retry must replay the completed result")
local cacheAccount, cacheStore = {}, nil
cacheStore = Personal.normalizeData(cacheAccount)
assert(Personal.beginOperation(cacheStore, "outer-batch", "batch") ~= nil, "outer batch operation did not start")
for index = 1, 250 do
    local childId = "outer-batch:" .. tostring(index)
    assert(Personal.beginOperation(cacheStore, childId, childId) ~= nil, "child operation did not start")
    Personal.finishOperation(cacheStore, childId, { ok = true, code = "done", operationId = childId })
    Personal.discardOperation(cacheStore, childId)
end
Personal.finishOperation(cacheStore, "outer-batch", { ok = true, code = "completed", operationId = "outer-batch" })
local _, cachedOuter = Personal.beginOperation(cacheStore, "outer-batch", "batch")
assert(cachedOuter and cachedOuter.code == "completed", "250 child transactions must not evict the outer retry result")
local target = container()
local withdrawn = Personal.withdraw(store, deposited.data.entryId, target, "withdraw-1")
assert(withdrawn.ok and #target.items == 1 and target.items[1].condition == 77, "snapshot round trip lost core item state")
assert(target.items[1].inventory and #target.items[1].inventory.items == 1 and target.items[1].inventory.items[1].count == 2,
    "snapshot round trip lost nested stack state")

store.capacities.food = 2
store.capacities.material = 1
store.generalCapacity = 4
store.entriesByCategory.food.a = { itemCount = 5 }
store.entriesByCategory.material.b = { itemCount = 3 }
local usage = Personal.usage(store)
assert(usage.generalUsed == 5, "general usage must sum overflow from every category")
local canAdd = Personal.canAdd(store, "food", 1)
assert(canAdd == false, "general overflow must reject a whole item tree when capacity is insufficient")

store.entriesByCategory.other.missing = {
    entryId = "missing", category = "other", fullType = "Missing.Item", itemCount = 1,
    snapshot = { schemaVersion = 1, fullType = "Missing.Item", category = "other", children = {}, weaponParts = {} },
}
local missing = Personal.withdraw(store, "missing", target, "missing-1")
assert(not missing.ok and missing.code == "missingDefinition" and store.entriesByCategory.other.missing ~= nil,
    "missing item definitions must leave the virtual entry intact")

local stressAccount = {}
local stress = Personal.normalizeData(stressAccount)
stress.capacities.other = 20000
for index = 1, 20000 do
    local entryId = "stress-" .. tostring(index)
    stress.entriesByCategory.other[entryId] = {
        entryId = entryId, category = "other", fullType = "Base.Stress", displayName = "Stress", itemCount = 1,
        snapshot = { schemaVersion = 1, fullType = "Base.Stress", category = "other", children = {}, weaponParts = {} },
    }
end
assert(Personal.summary(stress).usage.total == 20000, "20,000-entry summary failed")
assert(#Personal.entries(stress, nil, 0, 100).rows == 100, "detail response must remain paged")

GodSystemConfig = {
    DefaultTaskLimitHours = 24, MaxActiveTasks = 2, DailyTaskCount = 2, RefreshTaskCost = 0,
    TaskTemplates = {
        { id = "kill_one", title = "Kill", kind = "kill", target = 1, rewardPoints = 1, rewardItems = {}, penaltyPoints = 10 },
        { id = "move_one", title = "Move", kind = "moveDistance", target = 1, rewardPoints = 1, rewardItems = {}, penaltyPoints = 40 },
    },
}
GodSystemAdminConfig = {
    applyTaskReward = function(value) return value end,
    applyTaskPenalty = function(value) return value end,
}
package.loaded["GodSystem_Config"] = GodSystemConfig
package.loaded["GodSystem_AdminConfig"] = GodSystemAdminConfig
dofile(luaRoot .. "/shared/GodSystem_TaskService.lua")

local now, permitsGranted, defaultDeath, penaltyPaid = 100, 0, 0, 0
local service = GodSystemTaskService.create({
    nowHours = function() return now end,
    currentDay = function() return 4 end,
    randomIndex = function() return 1 end,
    featureEnabled = function() return true end,
    maxActiveTasks = function() return 2 end,
    dailyTaskCount = function() return 2 end,
    addPoints = function() end,
    giveItems = function(rows)
        for i = 1, #(rows or {}) do if rows[i].fullType == GodSystemTaskService.PermitFullType then permitsGranted = permitsGranted + rows[i].count end end
    end,
    payTaskPenalty = function(_, task, permit)
        local amount = permit and 500 or (task.penaltyPoints or 0)
        penaltyPaid = penaltyPaid + amount
        return amount
    end,
    applyDefaultDeathPenalty = function() defaultDeath = defaultDeath + 1; return 300 end,
    save = function() end,
})
local taskData = { tasks = {}, stats = {} }
service:normalize(taskData)
local permit
for i = 1, #taskData.tasks do if GodSystemTaskService.isPermit(taskData.tasks[i]) then permit = taskData.tasks[i] end end
assert(permit and service:accept(taskData, permit, {}).ok, "permit task must be acceptible")
for index = 1, 50 do
    local ordinary = { taskId = "ordinary-" .. index, sourceId = "kill_one", title = "Kill", kind = "kill", target = 1,
        killProgress = 1, status = "active", rewardPoints = 0, rewardItems = {}, penaltyPoints = 10, difficulty = 1 }
    taskData.tasks[#taskData.tasks + 1] = ordinary
    assert(service:claim(taskData, ordinary, {}).ok, "ordinary task claim failed")
end
assert(permit.permitProgress == 50, "permit progress must count 50 claimed non-permit tasks")
assert(service:claim(taskData, permit, {}).ok and permitsGranted == 1, "completed permit task must grant one real permit")
local permitCount, replacement = 0, nil
for i = 1, #taskData.tasks do
    if GodSystemTaskService.isPermit(taskData.tasks[i]) and (taskData.tasks[i].status == "open" or taskData.tasks[i].status == "active") then
        permitCount = permitCount + 1; replacement = taskData.tasks[i]
    end
end
assert(permitCount == 1 and replacement.status == "open", "permit completion must immediately replenish one open task")
service:generateDaily(taskData, true)
permitCount = 0
for i = 1, #taskData.tasks do if GodSystemTaskService.isPermit(taskData.tasks[i]) then permitCount = permitCount + 1 end end
assert(permitCount == 1, "daily refresh must preserve exactly one permit task")
GodSystemTaskService.sortTasks(taskData.tasks)
assert(GodSystemTaskService.isPermit(taskData.tasks[1]), "permit task must sort to the top")

assert(service:accept(taskData, replacement, {}).ok, "replacement permit must be acceptible")
taskData.tasks[#taskData.tasks + 1] = { taskId = "death-normal", sourceId = "kill_one", title = "Kill", kind = "kill",
    target = 99, killProgress = 0, status = "active", penaltyPoints = 10, difficulty = 1 }
local death = service:settleDeath(taskData, "death-token-1")
assert(death.ok and death.data.permitPenalty == true and defaultDeath == 0, "active permit must replace the normal death-bank penalty")
assert(penaltyPaid == 510, "death must charge permit 50% plus ordinary task penalties")
local duplicate = service:settleDeath(taskData, "death-token-1")
assert(duplicate.code == "duplicateDeath" and penaltyPaid == 510, "the same death token must never settle twice")
assert(service:health(taskData).ok, "task service health check failed")

print("Test-GodSystemV422021Runtime passed")
