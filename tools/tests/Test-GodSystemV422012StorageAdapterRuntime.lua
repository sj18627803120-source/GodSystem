local luaRoot = assert(arg[1], "Lua root required")
dofile(luaRoot .. "/shared/GodSystem/UI/StorageAdapter.lua")

local requests = {}
local snapshotPolls = 0
local clock = 1000
local facade = {
    gateway = {
        isPending = function() return false end,
    },
}

function facade:request(route, args, options)
    requests[#requests + 1] = { route = route, args = args }
    local result = { ok = true, code = "ok", data = {} }
    if route == "storage.status" then
        result.data = {
            state = "installed", networkId = "network-1",
            nextCost = 2000,
        }
    elseif route == "storage.networkState" then
        result.data = {
            connectedObjectIds = { ["object-1"] = true },
            canManage = true,
            isAdmin = false,
        }
    elseif route == "storage.index" then
        result.data = { snapshotId = "snapshot-1" }
    elseif route == "storage.snapshot" then
        snapshotPolls = snapshotPolls + 1
        if snapshotPolls == 1 then
            result.code = "StorageSnapshotPending"
            result.data = { snapshotId = "snapshot-1", pending = true }
        else
            result.code = "StorageSnapshot"
            result.data = {
                snapshotId = "snapshot-1",
                groups = { { key = "Base.Plank", count = 1 } },
                containers = {},
            }
        end
    elseif route == "storage.details" then
        result.data = {
            groupKey = args.groupKey,
            instances = { { id = "plank-1" } },
        }
    elseif route == "storage.organizerStatus" then
        result.data = { state = "completed", moved = 1 }
    elseif route == "storage.execute" then
        result.data = { success = 1 }
    end
    if options and options.callback then options.callback(result) end
    return result
end

local object = {}
local target = {
    pending = {},
    details = {},
    organizer = { state = "idle" },
    core = {
        x = 1, y = 2, z = 0, objectId = "object-1",
        networkId = "network-1", token = "token-1",
    },
    operation = 0,
}

function target.coreArgs()
    return {
        x = 1, y = 2, z = 0, objectId = "object-1",
        networkId = "network-1", coreToken = "token-1",
    }
end
function target.newOperationId(command)
    target.operation = target.operation + 1
    return command .. "-" .. tostring(target.operation)
end
function target.hasPendingOperation(command)
    for _, row in pairs(target.pending) do
        if row.command == command then return true end
    end
    return false
end
function target.notifyReason(code) target.reason = code end
function target.applySnapshot(snapshot) target.snapshot = snapshot end
function target.setCoreHost() return true end
function target.findCarriedCore() return { id = "core-1" } end

local storage = {
    nowMs = function() return clock end,
    objectCoordinates = function()
        return { x = 3, y = 4, z = 0 }
    end,
    getObjectId = function(value, create)
        assert(value == object and create == true)
        return "marked-object"
    end,
    objectSpriteName = function() return "crate_sprite" end,
    itemId = function(item) return item.id end,
}

local ui
ui = {
    onSnapshot = function(snapshot) ui.snapshot = snapshot end,
    onNetworkState = function(state) ui.networkState = state end,
    onIndexStarted = function(data) ui.indexStarted = data.snapshotId end,
    onDetails = function(key, rows) ui.details = { key = key, rows = rows } end,
    onOperationResult = function(command, ok)
        ui.operation = { command = command, ok = ok }
    end,
    onOrganizerStatus = function(state) ui.organizer = state end,
    open = function() ui.opened = true end,
}
local context
context = {
    refreshHighlights = function()
        context.refreshed = (context.refreshed or 0) + 1
    end,
}

local adapter = GodSystemUIStorageAdapter.new({
    facade = facade,
    target = target,
    storage = storage,
    ui = ui,
    context = context,
    multiplayer = false,
    now = function() return clock end,
})
assert(adapter:install())

target.requestCoreStatus(true)
assert(target.claimState and target.claimState.state == "installed")
assert(target.claimState.recoveryCost == 2000)

target.setNetworkContainer({
    object = object,
    enabled = true,
    name = "Wooden Crate",
})
local marked
for index = #requests, 1, -1 do
    if requests[index].route == "storage.execute" then
        marked = requests[index]
        break
    end
end
assert(marked)
assert(marked.route == "storage.execute")
assert(marked.args.action == "setNetworkContainer")
assert(marked.args.object.objectId == "marked-object")
assert(marked.args.object.raw == nil)
assert(next(target.pending) == nil)

assert(target.open(1, 2, 0, object))
assert(ui.opened and ui.indexStarted == "snapshot-1")
adapter:poll()
assert(snapshotPolls == 1 and target.snapshot == nil)
clock = clock + 100
adapter:poll()
assert(target.snapshot and target.snapshot.groups[1].key == "Base.Plank")
assert(ui.networkState and ui.networkState.connectedObjectIds["object-1"])

assert(target.requestDetails("Base.Plank"))
assert(target.details["Base.Plank"][1].id == "plank-1")

target.organizer = { state = "running" }
clock = clock + 300
adapter:poll()
assert(target.organizer.state == "completed" and target.organizer.moved == 1)

assert(adapter:stop())
assert(target.setNetworkContainer == nil)

print("Test-GodSystemV422012StorageAdapterRuntime passed")
