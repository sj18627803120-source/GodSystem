local luaRoot = assert(arg[1], "Lua root argument required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local now = 1234
getTimestampMs = function() return now end
isGamePaused = function() return false end

local actor = {
    x = 0, y = 0, z = 0, kills = 0,
    getX = function(self) return self.x end,
    getY = function(self) return self.y end,
    getZ = function(self) return self.z end,
    getUsername = function() return "alice" end,
    getVehicle = function() return nil end,
    CanSee = function() return true end,
    getZombieKills = function(self) return self.kills end,
    setZombieKills = function(self, value) self.kills = value end,
}
local target = {
    x = 2, y = 0, z = 0, health = 1, dead = false, reaction = nil,
    getX = function(self) return self.x end,
    getY = function(self) return self.y end,
    getZ = function(self) return self.z end,
    isDead = function(self) return self.dead end,
    isAlive = function(self) return not self.dead end,
    getHealth = function(self) return self.health end,
    setHealth = function(self, value) self.health = value self.dead = value <= 0 end,
    setAttackedBy = function(self, value) self.attacker = value end,
    Kill = function(self) self.dead = true end,
    isOnFloor = function() return false end,
    setHitReaction = function(self, value) self.reaction = value end,
    setStaggerBack = function(self, value) self.stagger = value end,
    setKnockedDown = function(self, value) self.knocked = value end,
}
getSpecificPlayer = function() return actor end

require "GodSystem/Platform/Companion/Query"
require "GodSystem/Platform/Companion/Mutation"
require "GodSystem/Platform/Companion/Events"
require "GodSystem/Platform/Companion/Visuals"

local query = GodSystemCompanionQueryPlatform.create({}, {
    binding = {
        scanTargets = function() return { { target = target, distanceSquared = 4 } } end,
        pointAvailable = function() return true end,
        randomBetween = function(minimum) return minimum end,
    },
})
assert(query:start())
assert(query.public.currentActor() == actor)
assert(query.public.ownerKey(actor) == "alice")
assert(query.public.nowMs() == 1234)
assert(query.public.actorSnapshot(actor).inVehicle == false)
assert(query.public.targetSnapshot(actor, target).visible == true)
assert(query.public.scanTargets(actor, 5)[1].target == target)
assert(query.public.pointAvailable(actor, { x = 1, y = 1, z = 0 }, true))

local mutation = GodSystemCompanionMutationPlatform.create({}, {})
assert(mutation:start())
assert(mutation.public.shock(target))
assert(target.reaction == "ShotBelly")
assert(mutation.public.knockDown(target))
assert(target.stagger and target.knocked)
assert(mutation.public.damage(actor, target, 2))
assert(target.dead and target.attacker == actor and actor.kills == 1)

local subscriptions = {}
local events = GodSystemCompanionEventsPlatform.create({}, {
    events = {
        subscribe = function(_, name, handler)
            subscriptions[name] = handler
            return true
        end,
    },
})
assert(events:start())
assert(events.public.bind({
    gameStart = function() end,
    playerUpdate = function() end,
    playerDeath = function() end,
    render = function() end,
}))
assert(subscriptions.OnGameStart and subscriptions.OnPlayerUpdate
    and subscriptions.OnPlayerDeath and subscriptions.OnPreUIDraw)

local calls = {}
local visuals = GodSystemCompanionVisualsPlatform.create({}, {
    binding = {
        emit = function(kind) calls[#calls + 1] = kind return true end,
        reset = function() calls[#calls + 1] = "reset" return true end,
        render = function() calls[#calls + 1] = "render" return true end,
    },
})
assert(visuals:start())
assert(visuals.public.emit("charge", {}, {}, actor, target))
assert(visuals.public.render({}, {}, actor))
assert(visuals.public.reset({}))
assert(table.concat(calls, ",") == "charge,render,reset")
assert(query:health().ok and mutation:health().ok and events:health().ok and visuals:health().ok)

print("Test-GodSystemV422012CompanionPlatformRuntime passed")
