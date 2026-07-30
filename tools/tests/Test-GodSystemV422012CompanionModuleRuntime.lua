local luaRoot = assert(arg[1], "Lua root argument required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

require "GodSystem/Features/Companion/Module"

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local function close(value, expected, epsilon, message)
    expect(math.abs(value - expected) <= (epsilon or 0.0001), message)
end

local function scope(initial)
    local row = { data = initial or {}, version = 1 }
    return {
        get = function() return row.data end,
        replace = function(_, value, version)
            row.data, row.version = value, version or row.version
            return row.data
        end,
        snapshot = function() return { data = row.data, version = row.version } end,
    }
end

local function fixture(environment, options)
    options = options or {}
    local actor = { id = "alice", x = 0, y = 0, z = 0, dead = false, vehicle = false, paused = false }
    local target = { id = "zombie", x = 2, y = 0, z = 0, dead = false, visible = true, health = 10 }
    local now, ledger, charged = 0, {}, 0
    local visuals, events, notifications = {}, {}, {}
    local stateScope = scope({
        actors = {
            alice = {
                unlocked = true,
                unlocks = { attack = true, sight = true, guardian = true },
                levels = {},
                effects = {},
                cooldowns = { attack = 0, sight = 0, guardian = 0 },
                combatMode = "active",
                followMode = "follow5",
                visible = true,
                guardianEnabled = false,
            },
        },
    })

    local query = {
        currentActor = function() return actor end,
        ownerKey = function(value) return value.id end,
        nowMs = function() return now end,
        actorSnapshot = function(value)
            return {
                x = value.x, y = value.y, z = value.z, dead = value.dead,
                inVehicle = value.vehicle, paused = value.paused,
            }
        end,
        targetSnapshot = function(_, value)
            if not value then return nil end
            return { x = value.x, y = value.y, z = value.z, dead = value.dead, visible = value.visible }
        end,
        scanTargets = function(_, radius, maximum)
            if target.dead or target.outOfRange then return {} end
            if radius < 2 then return {} end
            local rows = { { target = target, distanceSquared = 4 } }
            if maximum then
                while #rows > maximum do table.remove(rows) end
            end
            return rows
        end,
        randomBetween = function(minimum) return minimum end,
        pointAvailable = function() return true end,
    }
    local mutation = {
        damage = function(_, value, amount)
            if options.damageThrows then error("damage exploded") end
            if value.dead then return false end
            value.health = math.max(0, value.health - amount)
            if value.health <= 0 then value.dead = true end
            return true
        end,
        shock = function() return true end,
        knockDown = function() return true end,
        setLight = function(_, position, radius) return { position = position, radius = radius } end,
        removeLight = function() return true end,
    }
    local eventPort = {
        bind = function(handlers)
            events.handlers = handlers
            return true
        end,
        unbind = function() events.handlers = nil return true end,
    }
    local visualPort = {
        emit = function(kind)
            visuals[#visuals + 1] = kind
            return true
        end,
        reset = function() visuals[#visuals + 1] = "reset" return true end,
        render = function() visuals[#visuals + 1] = "render" return true end,
    }
    local wallet = {
        charge = function(_, amount)
            charged = charged + amount
            return true, { amount = amount }
        end,
        refund = function(_, receipt)
            charged = charged - receipt.amount
            return true
        end,
    }
    local operations = {
        begin = function(_, id, fingerprint)
            local row = ledger[id]
            if row then
                if row.fingerprint ~= fingerprint then return false, "operationMismatch" end
                return "replay", row.result
            end
            ledger[id] = { fingerprint = fingerprint }
            return "new", ledger[id]
        end,
        finish = function(_, id, value)
            ledger[id].result = value
            return value
        end,
        markUnknown = function(_, id, code)
            ledger[id] = ledger[id] or {}
            ledger[id].unknown = code
            return true
        end,
    }
    local notificationPort = {
        publish = function(value)
            notifications[#notifications + 1] = value
            return true
        end,
    }
    local instance = GodSystemCompanionFeatureModule.create({
        ["companion.query"] = query,
        ["companion.mutation"] = mutation,
        ["companion.events"] = eventPort,
        ["companion.visuals"] = visualPort,
        wallet = wallet,
        operations = operations,
        notifications = notificationPort,
    }, {
        moduleId = "feature.companion",
        environment = environment,
        state = stateScope,
        configSnapshot = { companion = { enabled = true, priceMultiplier = 1 } },
    })
    expect(instance:start() == true, "companion failed to start")

    return {
        actor = actor,
        target = target,
        instance = instance,
        events = events,
        visuals = visuals,
        notifications = notifications,
        state = stateScope,
        now = function(value) now = value end,
        charged = function() return charged end,
    }
end

local function attackContract(environment)
    local f = fixture(environment)
    f.now(0)
    local queued = f.instance.public.tick(f.actor)
    expect(queued.ok and queued.data.pendingAttack, environment .. " did not queue attack")
    local queuedState = f.instance.public.getState({ actor = f.actor })
    expect(queuedState.data.runtime.chargeEndsMs == 200, "charge must last exactly 0.2 seconds")
    expect(queuedState.data.persistent.cooldowns.attack == 0, "cooldown started before firing")

    f.now(199)
    f.instance.public.tick(f.actor)
    local charging = f.instance.public.getState({ actor = f.actor })
    expect(charging.data.runtime.pendingAttack ~= nil, "attack fired before 0.2 seconds")
    expect(#charging.data.runtime.projectiles == 0, "projectile existed before charge completed")
    expect(charging.data.persistent.cooldowns.attack == 0, "cooldown changed during charge")

    f.target.visible = false
    f.now(200)
    f.instance.public.tick(f.actor)
    local cancelled = f.instance.public.getState({ actor = f.actor })
    expect(cancelled.data.runtime.pendingAttack == nil, "invalid target did not cancel")
    expect(cancelled.data.persistent.cooldowns.attack == 0, "cancelled attack consumed cooldown")

    f.target.visible = true
    f.now(201)
    f.instance.public.tick(f.actor)
    f.now(401)
    f.instance.public.tick(f.actor)
    local fired = f.instance.public.getState({ actor = f.actor })
    expect(fired.data.runtime.pendingAttack == nil and #fired.data.runtime.projectiles == 1,
        "valid target did not launch after 0.2 seconds")
    close(fired.data.persistent.cooldowns.attack, 4, 0.0001,
        "base attack cooldown did not start at launch")

    f.now(651)
    f.instance.public.tick(f.actor)
    f.now(751)
    f.instance.public.tick(f.actor)
    expect(f.target.health < 10, "projectile did not apply damage after 0.35 seconds")
    expect(f.instance:health().ok == true, environment .. " health failed")
    f.instance:stop()
end

attackContract("singleplayer")
attackContract("multiplayer")

do
    local f = fixture("singleplayer")
    f.now(0)
    f.instance.public.tick(f.actor)
    local stopped = f.instance.public.setCombatMode({ actor = f.actor, mode = "ceasefire" })
    expect(stopped.ok, "ceasefire rejected")
    local state = f.instance.public.getState({ actor = f.actor })
    expect(state.data.runtime.pendingAttack == nil, "ceasefire did not cancel charge")
    expect(state.data.persistent.cooldowns.attack == 0, "ceasefire cancellation consumed cooldown")

    f.instance.public.setCombatMode({ actor = f.actor, mode = "active" })
    f.now(201)
    f.instance.public.tick(f.actor)
    expect(f.events.handlers and f.events.handlers.playerDeath, "death handler not bound")
    f.events.handlers.playerDeath(f.actor)
    local afterDeath = f.instance.public.getState({ actor = f.actor })
    expect(afterDeath.data.runtime.pendingAttack == nil
        and #afterDeath.data.runtime.projectiles == 0
        and #afterDeath.data.runtime.sightTargets == 0,
        "death cleanup left transient effects")
end

do
    local f = fixture("singleplayer")
    local purchase = f.instance.public.purchase({
        actor = f.actor,
        nodeId = "attackDamage",
        operationId = "companion-buy-1",
    })
    expect(purchase.ok and purchase.data.cost == 100, "stat purchase price changed")
    expect(f.charged() == 100, "stat purchase did not charge once")
    local replay = f.instance.public.purchase({
        actor = f.actor,
        nodeId = "attackDamage",
        operationId = "companion-buy-1",
    })
    expect(replay == purchase and f.charged() == 100, "purchase replay charged twice")
end

do
    local healthy = fixture("singleplayer")
    local broken = fixture("singleplayer", { damageThrows = true })
    broken.now(0)
    broken.instance.public.tick(broken.actor)
    broken.now(200)
    broken.instance.public.tick(broken.actor)
    broken.now(450)
    broken.instance.public.tick(broken.actor)
    broken.now(550)
    local failure = broken.instance.public.tick(broken.actor)
    expect(not failure.ok and failure.code == "portError", "port failure escaped module boundary")
    expect(not broken.instance:health().ok, "module health did not expose isolated failure")
    healthy.now(0)
    expect(healthy.instance.public.tick(healthy.actor).ok, "independent module was affected by failure")
end

print("Test-GodSystemV422012CompanionModuleRuntime passed")
