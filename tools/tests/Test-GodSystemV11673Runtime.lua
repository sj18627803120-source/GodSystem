local luaRoot = assert(arg[1], "lua root is required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    package.path,
}, ";")

GodSystemConfig = { DataKey = "GodSystem_Test" }

local Storage = require "GodSystem_Storage"

assert(Storage.normalizeRole("auto") == "general", "old auto role must map to general")
assert(Storage.normalizeRole("noAuto") == "general", "old noAuto role must map to general")
assert(Storage.normalizeRole("liquid") == "drink", "old liquid role must map to drink")
assert(Storage.normalizePriorityTier(0) == "lowest", "priority 0 migration failed")
assert(Storage.normalizePriorityTier(35) == "low", "priority 35 migration failed")
assert(Storage.normalizePriorityTier(50) == "normal", "priority 50 migration failed")
assert(Storage.normalizePriorityTier(75) == "high", "priority 75 migration failed")
assert(Storage.normalizePriorityTier(100) == "highest", "priority 100 migration failed")

assert(Storage.linkRoleAccepts({ role = "material" }, "material") == true, "exact material role must accept material")
assert(Storage.linkRoleAccepts({ role = "material" }, "food") == false, "material role must reject food")
assert(Storage.linkRoleAccepts({ role = "general" }, "weapon") == true, "general role must accept all categories")
assert(Storage.linkRoleAccepts({ role = "fridge" }, "perishable") == true, "cold role must accept perishables")

local containers = {}
local function addLink(id, role, tier, order, cold, powered, full)
    local container = { id = id, cold = cold, powered = powered, full = full }
    containers[id] = container
    return {
        linkId = id,
        role = role,
        priorityTier = tier,
        assignedOrder = order,
        x = 0, y = 0, z = 0,
        container = container,
    }
end

Storage.resolveLink = function(link) return {}, link.container, nil end
Storage.isWithinNetworkRange = function() return true end
Storage.containerAccepts = function(container)
    if container.full then return false, "full" end
    return true, nil
end
Storage.isColdContainer = function(_, container) return container.cold == true end
Storage.isPoweredColdContainer = function(_, container) return container.cold == true and container.powered == true end
Storage.categoryOf = function(item) return item.category end

local network = { links = {} }
network.links.general = addLink("general", "general", "highest", 1, false, false, false)
network.links.materialOld = addLink("materialOld", "material", "high", 10, false, false, false)
network.links.materialNew = addLink("materialNew", "material", "high", 20, false, false, false)
network.links.materialLow = addLink("materialLow", "material", "low", 1, false, false, false)

local routes, category = Storage.routeCandidates(network, nil, { category = "material" })
assert(category == "material", "category must be returned with routes")
assert(routes[1].link.linkId == "materialOld", "exact role, tier, then earlier assignment must win")
assert(routes[2].link.linkId == "materialNew", "same-tier later assignment must come second")
assert(routes[#routes].link.linkId == "general", "general must remain below exact role even at a higher tier")

local coldNetwork = { links = {} }
coldNetwork.links.general = addLink("coldGeneral", "general", "highest", 1, false, false, false)
coldNetwork.links.perishable = addLink("perishable", "perishable", "highest", 1, false, false, false)
coldNetwork.links.unpowered = addLink("unpowered", "fridge", "highest", 1, true, false, false)
coldNetwork.links.powered = addLink("powered", "fridge", "lowest", 99, true, true, false)
routes = Storage.routeCandidates(coldNetwork, nil, { category = "perishable" })
assert(routes[1].link.linkId == "powered", "powered cold storage must win for perishables")
assert(routes[2].link.linkId == "perishable", "exact perishable role must follow powered cold")
assert(routes[3].link.linkId == "unpowered", "unpowered cold must remain ahead of general")
assert(routes[4].link.linkId == "coldGeneral", "general must be the final perishable fallback")

coldNetwork.links.powered.container.full = true
routes = Storage.routeCandidates(coldNetwork, nil, { category = "perishable" }, true)
assert(routes[1].link.linkId == "powered" and routes[1].available == false,
    "organizer planning must retain a full ideal route")

print("Test-GodSystemV11673Runtime passed")
