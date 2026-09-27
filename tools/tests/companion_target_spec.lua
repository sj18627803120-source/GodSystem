-- Exercise the packaged companion implementation with faulty native-style targets.
local source = readSource("client/GodSystem_Companion.lua")
if type(source) == "string" then
    local count
    source, count = source:gsub("return GodSystemCompanion%s*$", [[
Companion.testTargets = {
    snapshot = zombieSnapshot,
    find = findAttackTarget,
    effects = collectEffectTargets,
    updateAttack = updateAttackState,
    projectileHit = applyProjectileDamage,
    renderProjectile = renderProjectile,
}
return GodSystemCompanion]])
    assert(count == 1)
end

local clock = 1000
function getTimestampMs() return clock end
function isClient() return false end
function isServer() return false end
function instanceof(value, kind) return kind == "IsoZombie" and value and value.zombie == true end
local squares = {}
local function key(x, y, z) return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y)) .. ":" .. tostring(math.floor(z)) end
local cell = { getGridSquare = function(_, x, y, z) return squares[key(x, y, z)] end }
function getCell() return cell end
local function square(x, y, z)
    local id = key(x, y, z)
    local value = { rows = {} }
    function value:getMovingObjects()
        local rows = self.rows
        return { size = function() return #rows end, get = function(_, index) return rows[index + 1] end }
    end
    squares[id] = value
    return value
end
local player = { x = 0, y = 0, z = 0, kills = 0, sightCalls = 0 }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:CanSee() self.sightCalls = self.sightCalls + 1; error("sight must not be used") end
function player:getZombieKills() return self.kills end
function player:setZombieKills(value) self.kills = value end
function getSpecificPlayer() return player end
local data = { unlocked = true, unlocks = { attack = true }, cooldowns = { attack = 0 }, combatMode = "active", followMode = "follow5", visible = false, effects = {} }
GodSystemApp = { services = { runtime = { getCompanionData = function() return data end } } }
GodSystemCompanionVisual = {}
GodSystemCompanionConfig = {
    RobotChargeSeconds = 0.2, RobotRecoverySeconds = 0.15, RobotCombatGraceSeconds = 3,
    ProjectileTravelSeconds = 0.35, AttackSearchSeconds = 0.5,
    SightDurationSeconds = 10, SightTargetCap = 50,
    ChainRadius = 3, ChainDamageRatio = 0.5, BlastRadius = 2, BlastDamageRatio = 0.25, BlastTargetCap = 4,
    getAttackSearchSeconds = function() return 0.5 end,
    getAttackSearchCandidateLimit = function() return 8 end,
    getStatValue = function(_, id) return ({ attackRange = 6, attackCooldown = 4 })[id] end,
    getFinalDamage = function() return 2 end,
}
Events = { OnGameStart = { Add = function() end }, OnPlayerUpdate = { Add = function() end },
    OnPlayerDeath = { Add = function() end }, OnPreUIDraw = { Add = function() end } }
function require() return true end
assert(loadstring(source, "GodSystem_Companion"))()
local C = GodSystemCompanion
local T = C.testTargets
local function eq(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local function zombie(x, y, z)
    local value = { zombie = true, x = x, y = y, z = z, health = 5, dead = false }
    value.square = squares[key(x, y, z)] or square(x, y, z)
    value.square.rows[#value.square.rows + 1] = value
    function value:getModData() return {} end
    function value:isDead() return self.dead end
    function value:isAlive() return not self.dead end
    function value:getCurrentSquare() return self.square end
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getHealth() return self.health end
    function value:setHealth(amount) self.health = amount end
    function value:setAttackedBy() end
    function value:Kill() self.dead = true; player.kills = player.kills + 1 end
    return value
end

local wallTarget = zombie(2, 0, 0)
eq(T.find(player, data), wallTarget)
eq(player.sightCalls, 0)
function wallTarget:getModData() return nil end
assert(T.snapshot(wallTarget, player), "ordinary zombies without ModData must remain valid")
T.projectileHit({ target = wallTarget }, player, data)
eq(wallTarget.health, 3)
eq(player.sightCalls, 0)
local secondary = zombie(2, 1, 0)
local candidates = T.effects(player, T.snapshot(wallTarget, player), 2, wallTarget)
eq(candidates[1].zombie, secondary)
eq(player.sightCalls, 0)
local another = zombie(2, -1, 0)
data.effects = { chain = true, blast = true }
T.projectileHit({ target = wallTarget }, player, data)
assert(secondary.health < 5 and another.health < 5, "both range effects should damage unseen nearby zombies")
eq(player.sightCalls, 0)
data.effects = {}
data.unlocks.sight = true
data.cooldowns.sight = 0
assert(C.activateSight())
eq(T.find(player, data), wallTarget)
eq(player.sightCalls, 0)

local upper = zombie(0, 0, 1)
eq(T.snapshot(upper, player), nil)
local far = zombie(20, 0, 0)
eq(T.find(player, data), wallTarget)
eq(T.projectileHit({ target = far }, player, data), nil)
eq(far.health, 5)
local moved = zombie(4, 0, 0)
moved.x = 9
moved.square = square(9, 0, 0)
eq(T.projectileHit({ target = moved }, player, data), nil)
eq(moved.health, 5)
local unloaded = zombie(5, 0, 0)
unloaded.square = nil
eq(T.snapshot(unloaded, player), nil)
data.combatMode = "ceasefire"
eq(T.find(player, data), nil)
data.combatMode = "active"

local broken = zombie(3, 0, 0)
local deadReads = 0
function broken:isDead() deadReads = deadReads + 1; error("native dead read failed") end
eq(T.snapshot(broken, player), nil)
for _ = 1, 1800 do clock = clock + 16; T.snapshot(broken, player) end
assert(deadReads <= 3, "one stale target must not fail every frame")
eq(T.renderProjectile({}, {}, { target = broken, elapsed = 0, duration = 0.35 }, player), nil)
local brokenAlive = zombie(3, 1, 0)
function brokenAlive:isAlive() error("native alive read failed") end
eq(T.snapshot(brokenAlive, player), nil)
eq(T.snapshot(brokenAlive, player), nil)

clock = 50000
C.runtime.pendingAttack = nil
C.runtime.robotX, C.runtime.robotY, C.runtime.robotZ = 0, 0, 0
C.runtime.nextAttackSearchMs = 0
T.updateAttack(player, data, clock)
assert(C.runtime.pendingAttack, "attack should begin without sight")
local pending = C.runtime.pendingAttack.target
local positionReads = 0
function pending:getZ() positionReads = positionReads + 1; error("native position read failed") end
clock = clock + 100
T.updateAttack(player, data, clock)
assert(C.runtime.pendingAttack, "charging should use its captured direction")
clock = clock + 101
T.updateAttack(player, data, clock)
eq(C.runtime.pendingAttack, nil)
eq(#C.runtime.projectiles, 0)
for _ = 1, 60 do clock = clock + 16; T.updateAttack(player, data, clock) end
eq(positionReads, 1)

print("PASS companion target selection, impact validation, and stale target quarantine")
