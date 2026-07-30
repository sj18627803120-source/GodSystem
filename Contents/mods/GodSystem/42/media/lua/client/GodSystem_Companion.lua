if (isClient and isClient()) or (isServer and isServer()) then return end

require "GodSystem_CompanionConfig"
require "GodSystem_CompanionVisual"

GodSystem = GodSystem or {}
GodSystemCompanion = GodSystemCompanion or {}

local Companion = GodSystemCompanion
local Config = GodSystemCompanionConfig
local Visual = GodSystemCompanionVisual

Companion.runtime = {
    robotX = nil,
    robotY = nil,
    robotZ = nil,
    targetX = nil,
    targetY = nil,
    targetZ = nil,
    direction = "SE",
    attackDirection = nil,
    attackFacingUntilMs = 0,
    behaviorState = "idle",
    pendingAttack = nil,
    chargeStartedMs = 0,
    chargeEndsMs = 0,
    recoveryUntilMs = 0,
    recoilUntilMs = 0,
    fireFlashUntilMs = 0,
    sightFlashUntilMs = 0,
    guardianFlashUntilMs = 0,
    nextLookMs = 0,
    nextStrafeMs = 0,
    nextTrailMs = 0,
    nextChargeParticleMs = 0,
    lastCombatTarget = nil,
    lastCombatTargetExpiresMs = 0,
    animationFrame = 0,
    animationElapsed = 0,
    bobPhase = 0,
    nextOrbitRetargetMs = 0,
    idleUntilMs = 0,
    combatUntilMs = 0,
    light = nil,
    lightCell = nil,
    lightX = nil,
    lightY = nil,
    lightZ = nil,
    lightRadius = nil,
    sightTargets = {},
    projectiles = {},
    shockCooldowns = {},
    corrosionStates = {},
    markStates = {},
    effectVisuals = {},
    lastUpdateMs = nil,
    lastGuardianScanMs = 0,
    nextAttackSearchMs = 0,
    lastSaveMs = 0,
    dirty = false,
    vehicleSuspended = false,
    pauseSuspended = false,
}

local LIGHT_R, LIGHT_G, LIGHT_B = 0.38, 0.68, 1.0
local CYAN_R, CYAN_G, CYAN_B = 0.18, 0.92, 1.0
local RED_BEAM_OUTER_R, RED_BEAM_OUTER_G, RED_BEAM_OUTER_B = 0.45, 0.02, 0.03
local RED_BEAM_CORE_R, RED_BEAM_CORE_G, RED_BEAM_CORE_B = 1.0, 0.10, 0.12

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor((os and os.time and os.time() or 0) * 1000)
end

local function playerObject()
    return getSpecificPlayer and getSpecificPlayer(0) or (getPlayer and getPlayer()) or nil
end

local function companionData()
    if GodSystem and GodSystem.getCompanionData then return GodSystem.getCompanionData() end
    return nil
end

local function notify(key, fallback)
    if GodSystem and GodSystem.notify and GodSystem.text then
        GodSystem.notify(GodSystem.text(key, fallback))
    end
end

local function saveSoon(force)
    local runtime = Companion.runtime
    runtime.dirty = true
    local now = nowMs()
    if force or now - (runtime.lastSaveMs or 0) >= 5000 then
        runtime.lastSaveMs = now
        runtime.dirty = false
        if GodSystem and GodSystem.save then GodSystem.save() end
    end
end

local function distanceSquared(ax, ay, bx, by)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    return dx * dx + dy * dy
end

local function sameFloor(a, b)
    if not a or not b then return false end
    return math.floor((a:getZ() or 0) + 0.1) == math.floor((b:getZ() or 0) + 0.1)
end

local function isDeadZombie(zombie)
    if not zombie then return true end
    local ok, dead = pcall(function() return zombie:isDead() end)
    if ok and dead then return true end
    local okAlive, alive = pcall(function() return zombie:isAlive() end)
    return okAlive and alive == false
end

local function removeLight()
    local runtime = Companion.runtime
    if runtime.light and runtime.lightCell then
        pcall(runtime.lightCell.removeLamppost, runtime.lightCell, runtime.light)
    end
    runtime.light = nil
    runtime.lightCell = nil
    runtime.lightX, runtime.lightY, runtime.lightZ = nil, nil, nil
    runtime.lightRadius = nil
end

local function cancelPendingAttack(nextState)
    local runtime = Companion.runtime
    runtime.pendingAttack = nil
    runtime.chargeStartedMs = 0
    runtime.chargeEndsMs = 0
    runtime.nextChargeParticleMs = 0
    runtime.attackDirection = nil
    runtime.attackFacingUntilMs = 0
    if runtime.behaviorState == "charging" then runtime.behaviorState = nextState or "idle" end
end

local function clearTransientEffects(clearSight)
    removeLight()
    local runtime = Companion.runtime
    cancelPendingAttack("idle")
    runtime.projectiles = {}
    runtime.shockCooldowns = {}
    runtime.corrosionStates = {}
    runtime.markStates = {}
    runtime.effectVisuals = {}
    runtime.recoveryUntilMs = 0
    runtime.recoilUntilMs = 0
    runtime.fireFlashUntilMs = 0
    runtime.sightFlashUntilMs = 0
    runtime.guardianFlashUntilMs = 0
    runtime.lastCombatTarget = nil
    runtime.lastCombatTargetExpiresMs = 0
    runtime.nextStrafeMs = 0
    runtime.nextTrailMs = 0
    runtime.behaviorState = "idle"
    if Visual and Visual.reset then Visual.reset() end
    if clearSight then runtime.sightTargets = {} end
end

local function randomBetween(minimum, maximum)
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or minimum
    return ZombRandFloat(minimum, maximum)
end

local function resetRobotNear(player)
    local runtime = Companion.runtime
    runtime.robotX = player:getX() + 0.8
    runtime.robotY = player:getY() + 0.8
    runtime.robotZ = player:getZ()
    runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
    runtime.nextOrbitRetargetMs = 0
    runtime.idleUntilMs = 0
    runtime.nextLookMs = 0
    runtime.nextStrafeMs = 0
    runtime.nextTrailMs = 0
    runtime.combatUntilMs = 0
    runtime.lastCombatTarget = nil
    runtime.lastCombatTargetExpiresMs = 0
    runtime.recoveryUntilMs = 0
    runtime.recoilUntilMs = 0
    runtime.fireFlashUntilMs = 0
    runtime.behaviorState = "idle"
    cancelPendingAttack("idle")
    if Visual and Visual.reset then Visual.reset() end
    runtime.direction = "SE"
end

local function pointVisibleToPlayer(square, player)
    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    if square.isCouldSee then
        local ok, visible = pcall(function() return square:isCouldSee(playerNum) end)
        if ok then return visible == true end
    end
    if square.isSeen then
        local ok, visible = pcall(function() return square:isSeen(playerNum) end)
        if ok then return visible == true end
    end
    return false
end

local function robotPointVisible(player, x, y, z)
    if not player then return false end
    local cell = getCell and getCell() or nil
    local square = cell and cell:getGridSquare(math.floor(x), math.floor(y), math.floor((tonumber(z) or 0) + 0.1)) or nil
    return square ~= nil and pointVisibleToPlayer(square, player)
end

local function validRobotPoint(player, x, y, z, requireVisible)
    if not player or math.floor((tonumber(z) or -99) + 0.1) ~= math.floor(player:getZ() + 0.1) then return false end
    local cell = getCell and getCell() or nil
    if not cell then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z + 0.1))
    if not square then return false end
    if square.isSolid and square:isSolid() then return false end
    if square.isSolidTrans and square:isSolidTrans() then return false end
    if square.TreatAsSolidFloor and not square:TreatAsSolidFloor() then return false end
    return requireVisible ~= true or pointVisibleToPlayer(square, player)
end

local function directionFromVector(dx, dy)
    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return nil end
    local screenX = dx - dy
    local screenY = (dx + dy) * 0.5
    local ax, ay = math.abs(screenX), math.abs(screenY)
    if ax > ay * 2.414 then return screenX >= 0 and "E" or "W" end
    if ay > ax * 2.414 then return screenY >= 0 and "S" or "N" end
    if screenX >= 0 then return screenY >= 0 and "SE" or "NE" end
    return screenY >= 0 and "SW" or "NW"
end

local function updateFacing(dx, dy)
    local runtime = Companion.runtime
    if nowMs() < (runtime.attackFacingUntilMs or 0) then return end
    local direction = directionFromVector(dx, dy)
    if direction then runtime.direction = direction end
end

local function followBand(data)
    return Config.RobotFollowBands[data.followMode] or Config.RobotFollowBands.follow5
end

local function setRobotTarget(x, y, z, now)
    local runtime = Companion.runtime
    runtime.targetX, runtime.targetY, runtime.targetZ = x, y, z
    runtime.nextOrbitRetargetMs = now
end

local function chooseRobotOrbitTargetPass(player, data, now, requireVisible)
    local baseX, baseY, baseZ = player:getX(), player:getY(), player:getZ()
    local minimum, maximum
    if data.followMode == "guard" and data.guardPoint then
        baseX, baseY, baseZ = data.guardPoint.x, data.guardPoint.y, data.guardPoint.z
        minimum, maximum = 0.15, Config.RobotGuardDriftRadius
    else
        local band = followBand(data)
        minimum, maximum = band.minimum, band.maximum
        if randomBetween(0, 1) < Config.RobotNearPatrolChance then
            maximum = minimum + (maximum - minimum) * 0.5
        end
    end
    for _ = 1, 12 do
        local angle = randomBetween(0, math.pi * 2)
        local radius = randomBetween(minimum, maximum)
        local x = baseX + math.cos(angle) * radius
        local y = baseY + math.sin(angle) * radius
        if validRobotPoint(player, x, y, baseZ, requireVisible) then
            setRobotTarget(x, y, baseZ, now)
            return true
        end
    end
    return false
end

local function chooseIdleDirection()
    local directions = Config.RobotDirections
    local index = math.floor(randomBetween(1, #directions + 0.999))
    return directions[math.max(1, math.min(#directions, index))]
end

local chooseCombatStrafeTarget

local function chooseRobotOrbitTarget(player, data, now)
    if chooseRobotOrbitTargetPass(player, data, now, true) then return true end
    if chooseRobotOrbitTargetPass(player, data, now, false) then return true end
    local baseX, baseY, baseZ = player:getX(), player:getY(), player:getZ()
    if data.followMode == "guard" and data.guardPoint then
        baseX = tonumber(data.guardPoint.x) or baseX
        baseY = tonumber(data.guardPoint.y) or baseY
        baseZ = tonumber(data.guardPoint.z) or baseZ
    end
    if validRobotPoint(player, baseX, baseY, baseZ, false) then
        setRobotTarget(baseX, baseY, baseZ, now)
        return true
    end
    Companion.runtime.targetX, Companion.runtime.targetY, Companion.runtime.targetZ = nil, nil, nil
    Companion.runtime.nextOrbitRetargetMs = now + Config.RobotOrbitRetargetMinSeconds * 1000
    return false
end

local function guardPointStillValid(player, data)
    local point = data.guardPoint
    if not point then return false end
    if math.floor((tonumber(point.z) or -99) + 0.1) ~= math.floor(player:getZ() + 0.1) then return false end
    return distanceSquared(point.x, point.y, player:getX(), player:getY()) <= Config.RobotRecallDistance ^ 2
end

local function updateRobotPosition(player, data, delta, now)
    local runtime = Companion.runtime
    if data.followMode == "guard" and not guardPointStillValid(player, data) then
        data.followMode = "follow5"
        data.guardPoint = nil
        saveSoon(true)
    end
    if not runtime.robotX then resetRobotNear(player) end
    if math.floor((runtime.robotZ or -99) + 0.1) ~= math.floor(player:getZ() + 0.1)
        or distanceSquared(runtime.robotX, runtime.robotY, player:getX(), player:getY()) > Config.RobotRecallDistance ^ 2 then
        resetRobotNear(player)
    end

    if runtime.pendingAttack then
        runtime.behaviorState = "charging"
        return
    end
    if now < (runtime.recoveryUntilMs or 0) then
        runtime.behaviorState = "recovery"
        return
    end

    local band = followBand(data)
    local playerDistance = math.sqrt(distanceSquared(runtime.robotX, runtime.robotY, player:getX(), player:getY()))
    local catchup = data.followMode ~= "guard" and playerDistance > band.maximum + Config.RobotCatchupMargin
    if catchup then
        runtime.behaviorState = "catchup"
        runtime.idleUntilMs = 0
        local offsetX = runtime.robotX - player:getX()
        local offsetY = runtime.robotY - player:getY()
        local offsetLength = math.max(0.001, math.sqrt(offsetX * offsetX + offsetY * offsetY))
        local trailingDistance = math.max(1, band.minimum)
        local x = player:getX() + offsetX / offsetLength * trailingDistance
        local y = player:getY() + offsetY / offsetLength * trailingDistance
        if validRobotPoint(player, x, y, player:getZ(), false) then
            runtime.targetX, runtime.targetY, runtime.targetZ = x, y, player:getZ()
        else
            runtime.targetX, runtime.targetY, runtime.targetZ = player:getX(), player:getY(), player:getZ()
        end
    elseif now < (runtime.combatUntilMs or 0) and data.followMode ~= "guard"
        and now >= (runtime.nextStrafeMs or 0) and chooseCombatStrafeTarget(player, data, now) then
        runtime.behaviorState = "patrol"
    elseif now < (runtime.idleUntilMs or 0) then
        runtime.behaviorState = data.followMode == "guard" and "guard" or "idle"
        if now >= (runtime.nextLookMs or 0) then
            runtime.direction = chooseIdleDirection()
            runtime.nextLookMs = now + randomBetween(Config.RobotLookMinSeconds, Config.RobotLookMaxSeconds) * 1000
        end
        return
    elseif not runtime.targetX and now >= (runtime.nextOrbitRetargetMs or 0) then
        chooseRobotOrbitTarget(player, data, now)
    end

    local tx, ty, tz = runtime.targetX, runtime.targetY, runtime.targetZ
    if not tx then return end
    if not catchup then runtime.behaviorState = data.followMode == "guard" and "guard" or "patrol" end
    local dx, dy = tx - runtime.robotX, ty - runtime.robotY
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= 0.05 then
        runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
        if not catchup then
            if now < (runtime.combatUntilMs or 0) then
                chooseRobotOrbitTarget(player, data, now)
            else
                runtime.idleUntilMs = now + randomBetween(Config.RobotIdleMinSeconds, Config.RobotIdleMaxSeconds) * 1000
                runtime.nextLookMs = now + randomBetween(Config.RobotLookMinSeconds, Config.RobotLookMaxSeconds) * 1000
            end
        end
        return
    end
    local speed = catchup and Config.RobotCatchupSpeed or Config.RobotNormalSpeed
    local step = math.min(distance, math.max(0.01, delta * speed))
    local nx = runtime.robotX + dx / distance * step
    local ny = runtime.robotY + dy / distance * step
    if not validRobotPoint(player, nx, ny, tz, false) then
        runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
        chooseRobotOrbitTarget(player, data, now)
        return
    end
    updateFacing(nx - runtime.robotX, ny - runtime.robotY)
    runtime.robotX, runtime.robotY, runtime.robotZ = nx, ny, tz
    if data.visible and Visual and Visual.emit and now >= (runtime.nextTrailMs or 0) then
        Visual.emit(catchup and "catchup" or "trail", runtime.robotX, runtime.robotY, runtime.robotZ)
        runtime.nextTrailMs = now + Config.RobotTrailSeconds * 1000
    end
end

local function ensureLight(player, data)
    local runtime = Companion.runtime
    if not data.visible or runtime.vehicleSuspended or not runtime.robotX then removeLight(); return end
    local ix, iy, iz = math.floor(runtime.robotX), math.floor(runtime.robotY), math.floor(runtime.robotZ + 0.1)
    local radius = Config.getStatValue(data, "light") or 6
    if runtime.light and runtime.lightX == ix and runtime.lightY == iy and runtime.lightZ == iz and runtime.lightRadius == radius then return end
    removeLight()
    local cell = getCell and getCell() or nil
    if not cell or not IsoLightSource then return end
    local ok, light = pcall(IsoLightSource.new, ix, iy, iz, LIGHT_R, LIGHT_G, LIGHT_B, radius)
    if ok and light and pcall(cell.addLamppost, cell, light) then
        runtime.light = light
        runtime.lightCell = cell
        runtime.lightX, runtime.lightY, runtime.lightZ = ix, iy, iz
        runtime.lightRadius = radius
    end
end

local function validZombie(zombie, player)
    return zombie and not isDeadZombie(zombie) and sameFloor(zombie, player)
end

chooseCombatStrafeTarget = function(player, data, now)
    local runtime = Companion.runtime
    local target = runtime.lastCombatTarget
    if not target or now >= (runtime.lastCombatTargetExpiresMs or 0) or not validZombie(target, player) then
        runtime.lastCombatTarget = nil
        return false
    end
    local dx, dy = target:getX() - player:getX(), target:getY() - player:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.01 then return false end
    local band = followBand(data)
    local radius = math.max(band.minimum, math.min(band.maximum, 2.5))
    local side = randomBetween(0, 1) < 0.5 and -1 or 1
    local x = player:getX() - dy / length * radius * side
    local y = player:getY() + dx / length * radius * side
    if validRobotPoint(player, x, y, player:getZ(), false) then
        setRobotTarget(x, y, player:getZ(), now)
        runtime.nextStrafeMs = now + randomBetween(
            Config.RobotCombatStrafeMinSeconds,
            Config.RobotCombatStrafeMaxSeconds
        ) * 1000
        return true
    end
    return false
end

local function collectZombies(player, radius, visibleOnly, earlyLimit)
    local result, seen = {}, {}
    local cell = getCell and getCell() or nil
    if not cell or not player then return result end
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ() + 0.1)
    local radiusSq = radius * radius
    for x = math.floor(px - radius), math.floor(px + radius) do
        for y = math.floor(py - radius), math.floor(py + radius) do
            local square = cell:getGridSquare(x, y, pz)
            local objects = square and square.getMovingObjects and square:getMovingObjects() or nil
            if objects then
                for i = 0, objects:size() - 1 do
                    local zombie = objects:get(i)
                    if not seen[zombie] and instanceof(zombie, "IsoZombie") and validZombie(zombie, player) then
                        seen[zombie] = true
                        local d2 = distanceSquared(px, py, zombie:getX(), zombie:getY())
                        if d2 <= radiusSq then
                            local visible = true
                            if visibleOnly then
                                local okSee, canSee = pcall(function() return player:CanSee(zombie) end)
                                visible = okSee and canSee == true
                            end
                            if visible then
                                result[#result + 1] = { zombie = zombie, distanceSq = d2 }
                                if earlyLimit and #result >= earlyLimit then return result end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.distanceSq < b.distanceSq end)
    return result
end

local function cleanSightTargets(player, data)
    local runtime = Companion.runtime
    local now = nowMs()
    local radius = Config.getStatValue(data, "sightRange") or 10
    local radiusSq = radius * radius
    for i = #runtime.sightTargets, 1, -1 do
        local entry = runtime.sightTargets[i]
        local zombie = entry and entry.zombie
        if not validZombie(zombie, player) or now >= (entry.expiresAt or 0)
            or distanceSquared(player:getX(), player:getY(), zombie:getX(), zombie:getY()) > radiusSq then
            table.remove(runtime.sightTargets, i)
        end
    end
end

local function isSightMarked(zombie)
    for i = 1, #Companion.runtime.sightTargets do
        if Companion.runtime.sightTargets[i].zombie == zombie then return true end
    end
    return false
end

local function attackRadius(data)
    return data.combatMode == "defensive" and 5 or (Config.getStatValue(data, "attackRange") or 6)
end

local function isAttackTargetValid(player, data, zombie)
    if not player or not data or data.combatMode == "ceasefire" or not validZombie(zombie, player) then return false end
    local radius = attackRadius(data)
    if distanceSquared(player:getX(), player:getY(), zombie:getX(), zombie:getY()) > radius * radius then return false end
    if isSightMarked(zombie) then return true end
    local okSee, visible = pcall(function() return player:CanSee(zombie) end)
    return okSee and visible == true
end

local function findAttackTarget(player, data)
    local radius = attackRadius(data)
    local candidates = collectZombies(player, radius, false, nil)
    for i = 1, #candidates do
        local zombie = candidates[i].zombie
        if isAttackTargetValid(player, data, zombie) then return zombie end
    end
    return nil
end

local function queueEffectVisual(kind, source, target, durationMs)
    local sourceX = source and source.getX and source:getX() or nil
    local sourceY = source and source.getY and source:getY() or nil
    local sourceZ = source and source.getZ and source:getZ() or nil
    local targetX = target and target.getX and target:getX() or nil
    local targetY = target and target.getY and target:getY() or nil
    local targetZ = target and target.getZ and target:getZ() or nil
    Companion.runtime.effectVisuals[#Companion.runtime.effectVisuals + 1] = {
        kind = kind,
        source = source,
        target = target,
        x = sourceX,
        y = sourceY,
        z = sourceZ,
        targetX = targetX,
        targetY = targetY,
        targetZ = targetZ,
        createdAt = nowMs(),
        expiresAt = nowMs() + math.max(80, tonumber(durationMs) or 250),
    }
end

local function applyCompanionDamage(zombie, player, damage)
    if not validZombie(zombie, player) then return false end
    damage = math.max(0, tonumber(damage) or 0)
    if damage <= 0 then return false end
    local oldHealth = tonumber(zombie:getHealth()) or 0
    if oldHealth <= 0 then return false end
    local previousKills = player:getZombieKills()
    pcall(function() zombie:setAttackedBy(player) end)
    local applied = pcall(function() zombie:setHealth(math.max(0, oldHealth - damage)) end)
    if not applied then return false end
    if zombie:getHealth() <= 0 then
        pcall(function() zombie:Kill(player) end)
        local expectedKills = previousKills + 1
        if player:getZombieKills() < expectedKills then player:setZombieKills(expectedKills) end
    end
    return true
end

local function collectEffectTargets(player, source, radius)
    local result, seen = {}, {}
    local cell = getCell and getCell() or nil
    if not cell or not source or not player then return result end
    local sx, sy, sz = source:getX(), source:getY(), math.floor(source:getZ() + 0.1)
    local radiusSq = radius * radius
    for x = math.floor(sx - radius), math.floor(sx + radius) do
        for y = math.floor(sy - radius), math.floor(sy + radius) do
            local square = cell:getGridSquare(x, y, sz)
            local objects = square and square.getMovingObjects and square:getMovingObjects() or nil
            if objects then
                for index = 0, objects:size() - 1 do
                    local zombie = objects:get(index)
                    if zombie ~= source and not seen[zombie] and instanceof(zombie, "IsoZombie") and validZombie(zombie, player) then
                        seen[zombie] = true
                        local distanceSq = distanceSquared(sx, sy, zombie:getX(), zombie:getY())
                        if distanceSq <= radiusSq then
                            local allowed = isSightMarked(zombie)
                            if not allowed then
                                local okSee, visible = pcall(function() return player:CanSee(zombie) end)
                                allowed = okSee and visible == true
                            end
                            if allowed then result[#result + 1] = { zombie = zombie, distanceSq = distanceSq } end
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.distanceSq < b.distanceSq end)
    return result
end

local function applyDirectEffects(target, player, data, directDamage)
    local effects = data.effects or {}
    local runtime = Companion.runtime
    local now = nowMs()

    if validZombie(target, player) and effects.shock then
        local readyAt = tonumber(runtime.shockCooldowns[target]) or 0
        if now >= readyAt then
            local onFloor = false
            if target.isOnFloor then
                local okFloor, value = pcall(function() return target:isOnFloor() end)
                onFloor = okFloor and value == true
            end
            if not onFloor then pcall(function() target:setHitReaction("ShotBelly") end) end
            runtime.shockCooldowns[target] = now + Config.ShockInternalCooldownSeconds * 1000
            queueEffectVisual("shock", target, nil, 260)
        end
    end

    if validZombie(target, player) and effects.corrosion then
        local state = runtime.corrosionStates[target]
        local tickDamage = math.max(0.01, directDamage * Config.CorrosionDamageRatio)
        if state then
            state.damage = math.max(tonumber(state.damage) or 0, tickDamage)
            state.expiresAt = now + Config.CorrosionDurationSeconds * 1000
        else
            runtime.corrosionStates[target] = {
                damage = tickDamage,
                nextTickMs = now + Config.CorrosionTickSeconds * 1000,
                expiresAt = now + Config.CorrosionDurationSeconds * 1000,
            }
        end
        queueEffectVisual("corrosion", target, nil, 360)
    end

    if validZombie(target, player) and effects.mark then
        runtime.markStates[target] = now + Config.MarkDurationSeconds * 1000
    end

    local used = { [target] = true }
    local occupied = 0
    if effects.chain then
        local candidates = collectEffectTargets(player, target, Config.ChainRadius)
        local chained = candidates[1] and candidates[1].zombie or nil
        if chained then
            used[chained] = true
            occupied = 1
            applyCompanionDamage(chained, player, directDamage * Config.ChainDamageRatio)
            queueEffectVisual("chain", target, chained, 280)
        end
    end

    if effects.blast then
        queueEffectVisual("blast", target, nil, 420)
        local candidates = collectEffectTargets(player, target, Config.BlastRadius)
        for index = 1, #candidates do
            if occupied >= Config.BlastTargetCap then break end
            local zombie = candidates[index].zombie
            if not used[zombie] then
                used[zombie] = true
                occupied = occupied + 1
                applyCompanionDamage(zombie, player, directDamage * Config.BlastDamageRatio)
            end
        end
    end
end

local function applyProjectileDamage(entry, player, data)
    local zombie = entry.target
    if not validZombie(zombie, player) then return end
    local damage = Config.getFinalDamage(data)
    local markedUntil = tonumber(Companion.runtime.markStates[zombie]) or 0
    if markedUntil > nowMs() then damage = damage * Config.MarkDamageMultiplier end
    if applyCompanionDamage(zombie, player, damage) then
        applyDirectEffects(zombie, player, data, damage)
    end
end

local function updateEffectStates(player)
    local runtime = Companion.runtime
    local now = nowMs()
    for zombie, readyAt in pairs(runtime.shockCooldowns) do
        if not validZombie(zombie, player) or now >= (tonumber(readyAt) or 0) then runtime.shockCooldowns[zombie] = nil end
    end
    for zombie, expiresAt in pairs(runtime.markStates) do
        if not validZombie(zombie, player) or now >= (tonumber(expiresAt) or 0) then runtime.markStates[zombie] = nil end
    end
    for zombie, state in pairs(runtime.corrosionStates) do
        if not validZombie(zombie, player) then
            runtime.corrosionStates[zombie] = nil
        else
            local expiresAt = tonumber(state.expiresAt) or 0
            local nextTick = tonumber(state.nextTickMs) or (now + Config.CorrosionTickSeconds * 1000)
            while nextTick <= now and nextTick <= expiresAt and validZombie(zombie, player) do
                applyCompanionDamage(zombie, player, state.damage)
                queueEffectVisual("corrosion", zombie, nil, 260)
                nextTick = nextTick + Config.CorrosionTickSeconds * 1000
            end
            state.nextTickMs = nextTick
            if now >= expiresAt and nextTick > expiresAt then runtime.corrosionStates[zombie] = nil end
        end
    end
    for index = #runtime.effectVisuals, 1, -1 do
        local visual = runtime.effectVisuals[index]
        if not visual or now >= (visual.expiresAt or 0) then table.remove(runtime.effectVisuals, index) end
    end
end

local function updateProjectiles(delta, player, data)
    local list = Companion.runtime.projectiles
    for i = #list, 1, -1 do
        local entry = list[i]
        entry.elapsed = (entry.elapsed or 0) + delta
        if entry.elapsed >= (entry.duration or Config.ProjectileTravelSeconds) then
            applyProjectileDamage(entry, player, data)
            table.remove(list, i)
        elseif not validZombie(entry.target, player) then
            table.remove(list, i)
        end
    end
end

local function beginAttack(player, target, now)
    local runtime = Companion.runtime
    if not runtime.robotX then resetRobotNear(player) end
    runtime.pendingAttack = { target = target }
    runtime.chargeStartedMs = now
    runtime.chargeEndsMs = now + Config.RobotChargeSeconds * 1000
    runtime.nextChargeParticleMs = now
    runtime.attackDirection = directionFromVector(target:getX() - runtime.robotX, target:getY() - runtime.robotY)
    runtime.attackFacingUntilMs = runtime.chargeEndsMs + Config.ProjectileTravelSeconds * 1000
    runtime.combatUntilMs = runtime.chargeEndsMs + Config.RobotCombatGraceSeconds * 1000
    runtime.lastCombatTarget = target
    runtime.lastCombatTargetExpiresMs = runtime.combatUntilMs
    runtime.idleUntilMs = 0
    runtime.behaviorState = "charging"
end

local function launchPendingAttack(data, now)
    local runtime = Companion.runtime
    local pending = runtime.pendingAttack
    local target = pending and pending.target or nil
    if not target then cancelPendingAttack("idle"); return end
    local attackDirection = runtime.attackDirection
    runtime.pendingAttack = nil
    runtime.chargeStartedMs = 0
    runtime.chargeEndsMs = 0
    runtime.nextChargeParticleMs = 0
    runtime.attackDirection = attackDirection
    runtime.attackFacingUntilMs = now + Config.ProjectileTravelSeconds * 1000
    runtime.projectiles[#runtime.projectiles + 1] = {
        target = target,
        startX = runtime.robotX,
        startY = runtime.robotY,
        startZ = runtime.robotZ,
        elapsed = 0,
        duration = Config.ProjectileTravelSeconds,
    }
    data.cooldowns.attack = Config.getStatValue(data, "attackCooldown") or 4
    runtime.behaviorState = "recovery"
    runtime.recoveryUntilMs = now + Config.RobotRecoverySeconds * 1000
    runtime.recoilUntilMs = now + math.min(0.10, Config.RobotRecoverySeconds) * 1000
    runtime.fireFlashUntilMs = now + 120
    runtime.combatUntilMs = now + Config.RobotCombatGraceSeconds * 1000
    runtime.lastCombatTarget = target
    runtime.lastCombatTargetExpiresMs = runtime.combatUntilMs
    if data.visible and Visual and Visual.emit then
        Visual.emit("fire", runtime.robotX, runtime.robotY, runtime.robotZ)
    end
    saveSoon(false)
end

local function updateAttackState(player, data, now)
    local runtime = Companion.runtime
    if runtime.pendingAttack then
        local target = runtime.pendingAttack.target
        if not data.unlocks.attack or not isAttackTargetValid(player, data, target) then
            cancelPendingAttack(data.followMode == "guard" and "guard" or "idle")
            return
        end
        runtime.attackDirection = directionFromVector(target:getX() - runtime.robotX, target:getY() - runtime.robotY)
        runtime.behaviorState = "charging"
        if data.visible and Visual and Visual.emit and now >= (runtime.nextChargeParticleMs or 0) then
            Visual.emit("charge", runtime.robotX, runtime.robotY, runtime.robotZ)
            runtime.nextChargeParticleMs = now + 60
        end
        if now >= (runtime.chargeEndsMs or 0) then launchPendingAttack(data, now) end
        return
    end
    if now < (runtime.recoveryUntilMs or 0) then runtime.behaviorState = "recovery"; return end
    if data.combatMode == "ceasefire" or not data.unlocks.attack or data.cooldowns.attack > 0 then return end
    if now < (runtime.nextAttackSearchMs or 0) then return end
    runtime.nextAttackSearchMs = now + Config.AttackSearchSeconds * 1000
    local target = findAttackTarget(player, data)
    if target then beginAttack(player, target, now) end
end

local function triggerGuardian(player, data)
    if not data.unlocks.guardian or not data.guardianEnabled or data.cooldowns.guardian > 0 then return end
    local threats = collectZombies(player, Config.GuardianTriggerRadius, false, Config.GuardianTriggerCount)
    if #threats < Config.GuardianTriggerCount then return end
    local radius = Config.getStatValue(data, "guardianRange") or 4
    local maximum = Config.getStatValue(data, "guardianCount") or 4
    local targets = collectZombies(player, radius, false, nil)
    local knocked = 0
    for i = 1, math.min(maximum, #targets) do
        local zombie = targets[i].zombie
        local ok = pcall(function()
            zombie:setStaggerBack(true)
            zombie:setKnockedDown(true)
        end)
        if ok then knocked = knocked + 1 end
    end
    if knocked > 0 then
        data.cooldowns.guardian = Config.getStatValue(data, "guardianCooldown") or 180
        local runtime = Companion.runtime
        local now = nowMs()
        runtime.combatUntilMs = now + Config.RobotCombatGraceSeconds * 1000
        runtime.guardianFlashUntilMs = now + 450
        runtime.idleUntilMs = 0
        if data.visible and runtime.robotX and Visual and Visual.emit then
            Visual.emit("guardian", runtime.robotX, runtime.robotY, runtime.robotZ)
        end
        queueEffectVisual("guardian", player, nil, 450)
        notify("Notify_CompanionGuardianTriggered", "Guardian triggered")
        saveSoon(true)
    end
end

local function decrementCooldowns(data, delta)
    local changed = false
    for _, id in ipairs({ "attack", "sight", "guardian" }) do
        local value = tonumber(data.cooldowns[id]) or 0
        if value > 0 then
            data.cooldowns[id] = math.max(0, value - delta)
            changed = true
        end
    end
    if changed then saveSoon(false) end
end

function Companion.activateSight()
    local player = playerObject()
    local data = companionData()
    if not player or not data or not data.unlocked or not data.unlocks.sight then
        notify("Notify_CompanionSightLocked", "Spirit sight is locked")
        return false
    end
    if Companion.runtime.vehicleSuspended then return false end
    if data.cooldowns.sight > 0 then
        notify("Notify_CompanionCooldown", "Ability is cooling down")
        return false
    end
    local targets = collectZombies(player, Config.getStatValue(data, "sightRange") or 10, false, nil)
    if #targets <= 0 then
        notify("Notify_CompanionNoTarget", "No target in range")
        return false
    end
    Companion.runtime.sightTargets = {}
    local expiresAt = nowMs() + Config.SightDurationSeconds * 1000
    for i = 1, math.min(Config.SightTargetCap, #targets) do
        Companion.runtime.sightTargets[#Companion.runtime.sightTargets + 1] = { zombie = targets[i].zombie, expiresAt = expiresAt }
    end
    data.cooldowns.sight = Config.getStatValue(data, "sightCooldown") or 120
    local runtime = Companion.runtime
    runtime.sightFlashUntilMs = nowMs() + 460
    if data.visible and runtime.robotX and Visual and Visual.emit then
        Visual.emit("sight", runtime.robotX, runtime.robotY, runtime.robotZ)
    end
    saveSoon(true)
    notify("Notify_CompanionSightActivated", "Spirit sight activated")
    return true
end

function Companion.setCombatMode(mode)
    if mode ~= "active" and mode ~= "defensive" and mode ~= "ceasefire" then return false end
    local data = companionData()
    if not data or not data.unlocked then return false end
    data.combatMode = mode
    if mode == "ceasefire" then
        cancelPendingAttack(data.followMode == "guard" and "guard" or "idle")
        Companion.runtime.combatUntilMs = 0
        Companion.runtime.lastCombatTarget = nil
        Companion.runtime.lastCombatTargetExpiresMs = 0
        Companion.runtime.nextStrafeMs = 0
    end
    saveSoon(true)
    return true
end

function Companion.setFollowMode(mode)
    if mode ~= "follow3" and mode ~= "follow5" and mode ~= "follow10" and mode ~= "guard" then return false end
    local player = playerObject()
    local data = companionData()
    if not player or not data or not data.unlocked then return false end
    data.followMode = mode
    if mode == "guard" then
        local runtime = Companion.runtime
        if not runtime.robotX then resetRobotNear(player) end
        data.guardPoint = { x = runtime.robotX, y = runtime.robotY, z = runtime.robotZ }
    else
        data.guardPoint = nil
    end
    Companion.runtime.nextOrbitRetargetMs = 0
    saveSoon(true)
    return true
end

function Companion.toggleGuardian()
    local data = companionData()
    if not data or not data.unlocked or not data.unlocks.guardian then return false end
    data.guardianEnabled = not data.guardianEnabled
    saveSoon(true)
    return true
end

function Companion.toggleVisible()
    local data = companionData()
    if not data or not data.unlocked then return false end
    data.visible = not data.visible
    if not data.visible then
        removeLight()
        cancelPendingAttack(data.followMode == "guard" and "guard" or "idle")
        Companion.runtime.combatUntilMs = 0
        Companion.runtime.lastCombatTarget = nil
        Companion.runtime.lastCombatTargetExpiresMs = 0
        Companion.runtime.nextStrafeMs = 0
        if Visual and Visual.reset then Visual.reset() end
    end
    saveSoon(true)
    return true
end

function Companion.recall()
    local player = playerObject()
    local data = companionData()
    if not player or not data or not data.unlocked then return false end
    data.followMode = "follow5"
    data.guardPoint = nil
    if Visual and Visual.reset then Visual.reset() end
    resetRobotNear(player)
    removeLight()
    if data.visible and Visual and Visual.emit then
        Visual.emit("recall", Companion.runtime.robotX, Companion.runtime.robotY, Companion.runtime.robotZ)
    end
    saveSoon(true)
    return true
end

function Companion.remainingCooldown(id)
    local data = companionData()
    return math.max(0, tonumber(data and data.cooldowns and data.cooldowns[id]) or 0)
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if math.floor(value) == value then return tostring(math.floor(value)) end
    return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function localized(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback
end

local function companionNodeRow(id, labelKey, fallback, unlocked, cost, detailKey, detailFallback)
    local status = unlocked and localized("Companion_StatusUnlocked", "Unlocked")
        or localized("Companion_StatusCost", "Cost") .. " " .. tostring(cost or 0) .. localized("Unit_CoinShort", "c")
    return {
        id = id,
        kind = "companionNode",
        label = localized(labelKey, fallback) .. " | " .. status,
        detail = localized(detailKey, detailFallback),
        unlocked = unlocked == true,
        cost = cost,
    }
end

function Companion.getRows()
    local data = companionData()
    if not data then return {} end
    local rows = {
        companionNodeRow("projection", "Companion_Unlock", "Robot", data.unlocked,
            Config.scaleCost(Config.UnlockCost), "Companion_ProjectionDetail", "Unlocks the blue pixel robot, lighting and behavior controls."),
        companionNodeRow("attack", "Companion_Attack", "Attack", data.unlocks.attack,
            Config.scaleCost(Config.AttackUnlockCost), "Companion_AttackDetail", "Unlocks red beam attacks."),
        companionNodeRow("sight", "Companion_Sight", "Spirit sight", data.unlocks.sight,
            Config.scaleCost(Config.SightUnlockCost), "Companion_SightDetail", "Marks up to 50 nearby zombies for 10 seconds and permits attacks through walls."),
        companionNodeRow("guardian", "Companion_Guardian", "Guardian", data.unlocks.guardian,
            Config.scaleCost(Config.GuardianUnlockCost), "Companion_GuardianDetail", "Knocks down nearby zombies when one enters the danger radius."),
    }
    for _, id in ipairs(Config.StatOrder) do
        local definition = Config.Stats[id]
        local level = data.levels[id] or 1
        local current = Config.getStatValue(data, id)
        local nextValue = definition.values[level + 1]
        local cost = Config.getUpgradeCost(data, id)
        local label = localized(definition.labelKey, id) .. " Lv." .. tostring(level)
        local detail = localized("Companion_Current", "Current") .. ": " .. formatNumber(current)
        if nextValue then
            label = label .. " | " .. tostring(cost) .. localized("Unit_CoinShort", "c")
            detail = detail .. "  ->  " .. formatNumber(nextValue)
        else
            label = label .. " | " .. localized("Upgrade_Maxed", "Maxed")
        end
        rows[#rows + 1] = {
            id = id,
            kind = "companionNode",
            label = label,
            detail = detail,
            unlocked = Config.isUnlocked(data, definition.requires),
            maxed = nextValue == nil,
            cost = cost,
        }
    end
    for _, id in ipairs(Config.EffectOrder) do
        local definition = Config.Effects[id]
        local owned = Config.isEffectUnlocked(data, id)
        local cost = Config.getEffectCost(data, id)
        local available = owned or cost ~= nil
        local status
        if owned then
            status = localized("Companion_StatusUnlocked", "Unlocked")
        elseif cost then
            status = localized("Companion_StatusCost", "Cost") .. " " .. tostring(cost) .. localized("Unit_CoinShort", "c")
        else
            status = localized("Companion_EffectRequiresPrevious", "Unlock the previous effect first")
        end
        rows[#rows + 1] = {
            id = id,
            kind = "companionNode",
            label = localized(definition.labelKey, id) .. " | " .. status,
            detail = localized(definition.detailKey, id),
            unlocked = available,
            maxed = owned,
            cost = cost,
            companionEffect = true,
        }
    end
    local resonanceCost = Config.getResonanceCost(data)
    local resonanceAvailable = Config.canPurchaseResonance(data)
    rows[#rows + 1] = {
        id = "resonance",
        kind = "companionNode",
        label = localized("Companion_Resonance", "Resonance") .. " Lv." .. tostring(data.resonance or 0) .. " | " .. (resonanceCost and (tostring(resonanceCost) .. localized("Unit_CoinShort", "c")) or localized("Companion_ResonanceLockedShort", "Locked")),
        detail = localized("Companion_ResonanceDetail", "Each level increases final attack damage by 1% after all functional upgrades and attack effects are unlocked."),
        unlocked = resonanceAvailable,
        cost = resonanceCost,
    }
    return rows
end

function Companion.getStateDetail()
    local data = companionData()
    if not data then return "" end
    local combat = localized("Companion_Mode_" .. tostring(data.combatMode), tostring(data.combatMode))
    local follow = localized("Companion_Mode_" .. tostring(data.followMode), tostring(data.followMode))
    local visible = data.visible and localized("Companion_Visible", "Visible") or localized("Companion_Hidden", "Hidden")
    return localized("Companion_State", "State") .. ": " .. localized("Companion_Robot", "Blue pixel robot") .. " | " .. combat .. " | " .. follow .. " | " .. visible
end

function GodSystemCompanion.shutdown()
    clearTransientEffects(true)
    local runtime = Companion.runtime
    runtime.robotX, runtime.robotY, runtime.robotZ = nil, nil, nil
    runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
    runtime.lastUpdateMs = nil
    runtime.vehicleSuspended = false
    runtime.pauseSuspended = false
    if runtime.dirty and GodSystem and GodSystem.save then GodSystem.save() end
    runtime.dirty = false
end

local function updateAnimation(delta)
    local runtime = Companion.runtime
    runtime.animationElapsed = (runtime.animationElapsed or 0) + delta
    while runtime.animationElapsed >= Config.RobotFrameSeconds do
        runtime.animationElapsed = runtime.animationElapsed - Config.RobotFrameSeconds
        runtime.animationFrame = runtime.animationFrame == 0 and 1 or 0
    end
    runtime.bobPhase = ((runtime.bobPhase or 0) + delta * 2.4) % (math.pi * 2)
end

local function updateCompanion(player)
    if not player or player ~= playerObject() then return end
    local data = companionData()
    if not data or not data.unlocked or not Config.isEnabled() then Companion.shutdown(); return end
    local runtime = Companion.runtime
    local now = nowMs()
    local previous = runtime.lastUpdateMs or now
    runtime.lastUpdateMs = now
    local delta = math.min(0.25, math.max(0, (now - previous) / 1000))
    if isGamePaused and isGamePaused() then
        if not runtime.pauseSuspended then
            cancelPendingAttack(data.followMode == "guard" and "guard" or "idle")
            runtime.combatUntilMs = 0
            runtime.lastCombatTarget = nil
            runtime.lastCombatTargetExpiresMs = 0
            runtime.nextStrafeMs = 0
            if Visual and Visual.reset then Visual.reset() end
            runtime.pauseSuspended = true
        end
        return
    end
    runtime.pauseSuspended = false

    local inVehicle = player.getVehicle and player:getVehicle() ~= nil
    if inVehicle then
        if not runtime.vehicleSuspended then clearTransientEffects(true); runtime.vehicleSuspended = true end
        return
    end
    if runtime.vehicleSuspended then
        runtime.vehicleSuspended = false
        runtime.lastUpdateMs = now
        resetRobotNear(player)
    end

    decrementCooldowns(data, delta)
    cleanSightTargets(player, data)
    updateEffectStates(player)
    updateProjectiles(delta, player, data)
    updateAttackState(player, data, now)
    updateRobotPosition(player, data, delta, now)
    updateAnimation(delta)
    if Visual and Visual.update then Visual.update(delta) end
    ensureLight(player, data)
    if now - (runtime.lastGuardianScanMs or 0) >= Config.GuardianScanSeconds * 1000 then
        runtime.lastGuardianScanMs = now
        triggerGuardian(player, data)
    end
    if runtime.dirty then saveSoon(false) end
end

local function screenPoint(x, y, z)
    if not ISCoordConversion or not ISCoordConversion.ToScreen then return nil, nil, nil end
    local sx, sy = ISCoordConversion.ToScreen(x, y, z)
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom, zoom
end

local function drawColoredLine(renderer, texture, x1, y1, x2, y2, r, g, b, alpha)
    renderer:renderline(texture, math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), r, g, b, alpha or 0.9)
end

local function renderCornerBox(renderer, texture, zombie, red, green, blue, alpha)
    local sx, sy, zoom = screenPoint(zombie:getX(), zombie:getY(), zombie:getZ())
    if not sx or not sy or not zoom then return end
    local halfW, halfH = 18 / zoom, 38 / zoom
    local arm = 8 / zoom
    sy = sy - 38 / zoom
    local left, right, top, bottom = sx - halfW, sx + halfW, sy - halfH, sy + halfH
    red, green, blue = red or CYAN_R, green or CYAN_G, blue or CYAN_B
    alpha = alpha or 0.92
    local function line(x1, y1, x2, y2)
        drawColoredLine(renderer, texture, x1, y1, x2, y2, red, green, blue, alpha)
    end
    line(left, top, left + arm, top); line(left, top, left, top + arm)
    line(right, top, right - arm, top); line(right, top, right, top + arm)
    line(left, bottom, left + arm, bottom); line(left, bottom, left, bottom - arm)
    line(right, bottom, right - arm, bottom); line(right, bottom, right, bottom - arm)
end

local function renderEffectRing(renderer, texture, sx, sy, radius, red, green, blue, alpha)
    local segments = 12
    local previousX = sx + radius
    local previousY = sy
    for index = 1, segments do
        local angle = (math.pi * 2 * index) / segments
        local nextX = sx + math.cos(angle) * radius
        local nextY = sy + math.sin(angle) * radius * 0.55
        drawColoredLine(renderer, texture, previousX, previousY, nextX, nextY, red, green, blue, alpha)
        previousX, previousY = nextX, nextY
    end
end

local function renderEffectVisual(renderer, texture, visual)
    if not visual then return end
    local source = visual.source
    local now = nowMs()
    local duration = math.max(1, (visual.expiresAt or now) - (visual.createdAt or now))
    local progress = math.max(0, math.min(1, (now - (visual.createdAt or now)) / duration))
    local alpha = math.max(0.08, 1 - progress)
    local sourceX = visual.x or (source and source.getX and source:getX())
    local sourceY = visual.y or (source and source.getY and source:getY())
    local sourceZ = visual.z or (source and source.getZ and source:getZ())
    if sourceX == nil or sourceY == nil or sourceZ == nil then return end
    local sx, sy, zoom = screenPoint(sourceX, sourceY, sourceZ)
    if not sx or not sy or not zoom then return end
    sy = sy - ((visual.kind == "guardian" and 12 or 38) / zoom)
    if visual.kind == "chain" then
        local target = visual.target
        local txWorld = visual.targetX or (target and target.getX and target:getX())
        local tyWorld = visual.targetY or (target and target.getY and target:getY())
        local tzWorld = visual.targetZ or (target and target.getZ and target:getZ())
        if txWorld == nil or tyWorld == nil or tzWorld == nil then return end
        local tx, ty, targetZoom = screenPoint(txWorld, tyWorld, tzWorld)
        if not tx or not ty or not targetZoom then return end
        ty = ty - 38 / targetZoom
        drawColoredLine(renderer, texture, sx, sy, tx, ty, 0.20, 0.92, 1.0, alpha)
        drawColoredLine(renderer, texture, sx + 1, sy, tx + 1, ty, 0.72, 1.0, 1.0, alpha * 0.8)
        return
    end
    if visual.kind == "guardian" then
        local radius = (14 + progress * 42) / zoom
        renderEffectRing(renderer, texture, sx, sy, radius, 0.42, 0.86, 1.0, alpha)
        renderEffectRing(renderer, texture, sx, sy, math.max(2, radius - 2 / zoom), 0.82, 0.96, 1.0, alpha * 0.72)
        return
    end
    if visual.kind == "blast" then
        local radius = (12 + progress * 30) / zoom
        renderEffectRing(renderer, texture, sx, sy, radius, 1.0, 0.12, 0.04, alpha)
        renderEffectRing(renderer, texture, sx, sy, math.max(2, radius - 2 / zoom), 1.0, 0.52, 0.12, alpha * 0.70)
        return
    end
    local radius = (visual.kind == "blast" and (12 + progress * 24) or (7 + progress * 8)) / zoom
    local red, green, blue = 0.35, 0.88, 1.0
    if visual.kind == "corrosion" then red, green, blue = 1.0, 0.28, 0.04 end
    if visual.kind == "blast" then red, green, blue = 1.0, 0.08, 0.04 end
    drawColoredLine(renderer, texture, sx, sy - radius, sx + radius, sy, red, green, blue, alpha)
    drawColoredLine(renderer, texture, sx + radius, sy, sx, sy + radius, red, green, blue, alpha)
    drawColoredLine(renderer, texture, sx, sy + radius, sx - radius, sy, red, green, blue, alpha)
    drawColoredLine(renderer, texture, sx - radius, sy, sx, sy - radius, red, green, blue, alpha)
end

local function renderProjectile(renderer, texture, entry)
    local target = entry.target
    if not target then return end
    local progress = math.min(1, (entry.elapsed or 0) / math.max(0.01, entry.duration or Config.ProjectileTravelSeconds))
    local sourceX, sourceY, sourceZoom = screenPoint(entry.startX, entry.startY, entry.startZ)
    local targetX, targetY, targetZoom = screenPoint(target:getX(), target:getY(), target:getZ())
    if not sourceX or not sourceY or not sourceZoom or not targetX or not targetY or not targetZoom then return end
    sourceY = sourceY - 48 / sourceZoom
    targetY = targetY - 38 / targetZoom
    local currentX = sourceX + (targetX - sourceX) * progress
    local currentY = sourceY + (targetY - sourceY) * progress
    local dx, dy = targetX - sourceX, targetY - sourceY
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.01 then return end
    local beamLength = math.min(30, length)
    local tailX = currentX - dx / length * beamLength
    local tailY = currentY - dy / length * beamLength
    for offset = -1, 1 do
        drawColoredLine(renderer, texture, tailX, tailY + offset, currentX, currentY + offset,
            RED_BEAM_OUTER_R, RED_BEAM_OUTER_G, RED_BEAM_OUTER_B, 0.55)
    end
    drawColoredLine(renderer, texture, tailX, tailY, currentX, currentY,
        RED_BEAM_CORE_R, RED_BEAM_CORE_G, RED_BEAM_CORE_B, 0.98)
end

local function renderRobot(renderer, texture, data, player)
    local runtime = Companion.runtime
    if not data.visible or not runtime.robotX then return end
    if not robotPointVisible(player, runtime.robotX, runtime.robotY, runtime.robotZ) then return end
    if Visual and Visual.renderRobot then Visual.renderRobot(renderer, texture, runtime, data) end
    return true
end

local function renderCompanionEffects()
    if not isIngameState or not isIngameState() then return end
    if not ISCoordConversion or not ISCoordConversion.ToScreen then return end
    local player = playerObject()
    local data = companionData()
    if not player or not data or not data.unlocked or Companion.runtime.vehicleSuspended then return end
    local renderer = getRenderer and getRenderer() or nil
    local now = nowMs()
    local lineTexture = Visual and Visual.getLineTexture and Visual.getLineTexture(now) or nil
    if not renderer or not lineTexture then return end
    local robotRendered = renderRobot(renderer, lineTexture, data, player)
    for i = 1, #Companion.runtime.sightTargets do
        local zombie = Companion.runtime.sightTargets[i].zombie
        if validZombie(zombie, player) then renderCornerBox(renderer, lineTexture, zombie) end
    end
    for zombie, expiresAt in pairs(Companion.runtime.markStates) do
        if nowMs() < (tonumber(expiresAt) or 0) and validZombie(zombie, player) then
            renderCornerBox(renderer, lineTexture, zombie, 1.0, 0.76, 0.12, 0.88)
        end
    end
    for i = 1, #Companion.runtime.projectiles do
        renderProjectile(renderer, lineTexture, Companion.runtime.projectiles[i])
    end
    for i = 1, #Companion.runtime.effectVisuals do
        renderEffectVisual(renderer, lineTexture, Companion.runtime.effectVisuals[i])
    end
    if robotRendered and Visual and Visual.renderParticles then Visual.renderParticles(renderer, lineTexture) end
end

local function onGameStart()
    Companion.shutdown()
end

local function onPlayerDeath(player)
    if not player or player == playerObject() then Companion.shutdown() end
end

if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
if Events.OnPlayerUpdate then Events.OnPlayerUpdate.Add(updateCompanion) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
if Events.OnPreUIDraw then Events.OnPreUIDraw.Add(renderCompanionEffects) end

return GodSystemCompanion
