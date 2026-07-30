GodSystemPZBindings = GodSystemPZBindings or {}

local Bindings = GodSystemPZBindings

local function call(target, method)
    if not target or type(target[method]) ~= "function" then return nil end
    return target[method](target)
end

local function identity(actor)
    local username = call(actor, "getUsername")
    if username and tostring(username) ~= "" then return "user:" .. tostring(username) end
    local onlineId = call(actor, "getOnlineID")
    if onlineId ~= nil and tonumber(onlineId) ~= -1 then
        return "online:" .. tostring(onlineId)
    end
    if type(actor) == "table" and actor.actorKey ~= nil then
        return tostring(actor.actorKey)
    end
    return "local"
end

local function currentActor()
    return type(getPlayer) == "function" and getPlayer() or nil
end

local function position(actor)
    return call(actor, "getX"), call(actor, "getY"), call(actor, "getZ")
end

local function zombieKills(actor)
    return tonumber(call(actor, "getZombieKills")) or 0
end

function Bindings.build(options)
    options = type(options) == "table" and options or {}
    local result = {}
    local identityBinding = { identity = identity }
    local identityModules = {
        "wallet.accounts",
        "upgrades.state",
        "medical.state",
        "home.state",
        "terminal.state",
        "terminal.instances",
        "storage.state",
        "storage.objects",
        "storage.containers",
        "storage.items",
        "storage.core",
        "storage.permissions",
        "storage.sync",
    }
    for index = 1, #identityModules do
        result[identityModules[index]] = identityBinding
    end
    result["companion.query"] = {
        currentActor = currentActor,
    }
    result["runtime.coordinator"] = {
        actorKey = identity,
        position = position,
        zombieKills = zombieKills,
    }
    if type(options.visuals) == "table" then
        result["companion.visuals"] = options.visuals
    end
    for moduleId, binding in pairs(type(options.overrides) == "table"
        and options.overrides or {})
    do
        local target = result[moduleId] or {}
        for key, value in pairs(binding) do target[key] = value end
        result[moduleId] = target
    end
    return result
end

Bindings.identity = identity
Bindings.currentActor = currentActor
Bindings.position = position
Bindings.zombieKills = zombieKills

return Bindings
