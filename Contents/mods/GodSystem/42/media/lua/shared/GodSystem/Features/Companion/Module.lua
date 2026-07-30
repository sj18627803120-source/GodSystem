require "GodSystem/Core/Result"
require "GodSystem/Features/Companion/Rules"
require "GodSystem/Features/Companion/State"

GodSystemCompanionFeatureModule = GodSystemCompanionFeatureModule or {}

local Descriptor = GodSystemCompanionFeatureModule
local Rules = GodSystemCompanionFeatureRules
local State = GodSystemCompanionFeatureState
local C = Rules.constants

Descriptor.id = "feature.companion"
Descriptor.dependencies = {
    "companion.query",
    "companion.mutation",
    "companion.events",
    "companion.visuals",
    "wallet",
    "operations",
    "notifications",
}
Descriptor.stateVersion = Rules.stateVersion

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function call(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function requiredPort(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. tostring(id))
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. tostring(id) .. " is missing method " .. tostring(methods[index]))
    end
    return port
end

local function operationId(request)
    local value = tostring(type(request) == "table" and request.operationId or "")
    return value ~= "" and #value <= 160 and value or nil
end

local function direction(dx, dy)
    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return nil end
    local screenX, screenY = dx - dy, (dx + dy) * 0.5
    local ax, ay = math.abs(screenX), math.abs(screenY)
    if ax > ay * 2.414 then return screenX >= 0 and "E" or "W" end
    if ay > ax * 2.414 then return screenY >= 0 and "S" or "N" end
    if screenX >= 0 then return screenY >= 0 and "SE" or "NE" end
    return screenY >= 0 and "SW" or "NW"
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local query = requiredPort(dependencies, "companion.query", {
        "currentActor", "ownerKey", "nowMs", "actorSnapshot", "targetSnapshot",
        "scanTargets", "randomBetween", "pointAvailable",
    })
    local mutation = requiredPort(dependencies, "companion.mutation", {
        "damage", "shock", "knockDown", "setLight", "removeLight",
    })
    local events = requiredPort(dependencies, "companion.events", { "bind", "unbind" })
    local visuals = requiredPort(dependencies, "companion.visuals", { "emit", "reset", "render" })
    local wallet = requiredPort(dependencies, "wallet", { "charge", "refund" })
    local operations = requiredPort(dependencies, "operations", { "begin", "finish", "markUnknown" })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })
    local store = State.new(assert(context.state, "companion state context required"))
    local config = type(context.configSnapshot) == "table"
        and type(context.configSnapshot.companion) == "table"
        and context.configSnapshot.companion or {}

    local instance = {
        started = false,
        completed = 0,
        failed = 0,
        ticks = 0,
        renders = 0,
        cancelledAttacks = 0,
        launchedAttacks = 0,
        lastIssue = nil,
        activeStage = nil,
    }

    local function result(ok, code, data, request, count)
        if count ~= false then
            if ok then instance.completed = instance.completed + 1
            else instance.failed = instance.failed + 1 end
        end
        local value = ok and GodSystemResult.ok(moduleId, code, data, operationId(request))
            or GodSystemResult.fail(moduleId, code, data, operationId(request))
        local notified, message = call(notifications.publish, value, request)
        if not notified then
            instance.lastIssue = { stage = "notification", code = "notificationFailed", message = tostring(message) }
        end
        return value
    end

    local function port(stage, callback, ...)
        instance.activeStage = stage
        local ok, first, second, third = call(callback, ...)
        if not ok then error(tostring(first)) end
        return first, second, third
    end

    local function guarded(request, stage, callback)
        instance.activeStage = stage
        local ok, value = xpcall(callback, traceback)
        if ok then return value end
        instance.lastIssue = {
            stage = instance.activeStage or stage,
            code = "portError",
            message = tostring(value),
        }
        return result(false, "portError", {
            stage = instance.activeStage or stage,
            message = tostring(value),
        }, request)
    end

    local function actorContext(actor)
        actor = actor or port("currentActor", query.currentActor)
        if not actor then return nil, nil, nil, "actorMissing" end
        local owner = tostring(port("ownerKey", query.ownerKey, actor) or "")
        if owner == "" then return nil, nil, nil, "ownerMissing" end
        local data, code = store:load(owner)
        if not data then return nil, nil, nil, code end
        return actor, owner, data, nil
    end

    local function save(owner, data, runtime, force)
        runtime.dirty = true
        local now = Rules.integer(port("clock", query.nowMs), 0, 0)
        local saved, code = store:save(owner, data)
        if saved and (force or now - Rules.integer(runtime.lastSaveMs, 0, 0) >= 5000) then
            runtime.lastSaveMs = now
            runtime.dirty = false
        end
        return saved, code
    end

    local function sightMarked(runtime, target, now)
        for index = #runtime.sightTargets, 1, -1 do
            local row = runtime.sightTargets[index]
            if not row or now >= Rules.integer(row.expiresAt, 0, 0) then
                table.remove(runtime.sightTargets, index)
            elseif row.target == target then
                return true
            end
        end
        return false
    end

    local function targetAllowed(actor, data, runtime, target, now)
        local actorView = port("actorSnapshot", query.actorSnapshot, actor)
        local targetView = port("targetSnapshot", query.targetSnapshot, actor, target)
        return Rules.targetAllowed(data, actorView, targetView, sightMarked(runtime, target, now))
    end

    local function cancelAttack(runtime, data)
        if runtime.pendingAttack then instance.cancelledAttacks = instance.cancelledAttacks + 1 end
        State.cancelAttack(runtime, data.followMode == "guard" and "guard" or "idle")
    end

    local function beginAttack(runtime, actorView, target, targetView, now)
        if not runtime.robotX then State.resetNear(runtime, actorView) end
        runtime.pendingAttack = { target = target }
        runtime.chargeStartedMs = now
        runtime.chargeEndsMs = now + C.robotChargeSeconds * 1000
        runtime.nextChargeParticleMs = now
        runtime.attackDirection = direction(
            targetView.x - runtime.robotX, targetView.y - runtime.robotY)
        runtime.attackFacingUntilMs = runtime.chargeEndsMs + C.projectileTravelSeconds * 1000
        runtime.combatUntilMs = runtime.chargeEndsMs + C.robotCombatGraceSeconds * 1000
        runtime.lastCombatTarget = target
        runtime.lastCombatTargetExpiresMs = runtime.combatUntilMs
        runtime.idleUntilMs = 0
        runtime.behaviorState = "charging"
    end

    local function launchAttack(data, runtime, now)
        local target = runtime.pendingAttack and runtime.pendingAttack.target
        if not target then cancelAttack(runtime, data) return false end
        local attackDirection = runtime.attackDirection
        runtime.pendingAttack = nil
        runtime.chargeStartedMs = 0
        runtime.chargeEndsMs = 0
        runtime.nextChargeParticleMs = 0
        runtime.attackDirection = attackDirection
        runtime.attackFacingUntilMs = now + C.projectileTravelSeconds * 1000
        runtime.projectiles[#runtime.projectiles + 1] = {
            target = target,
            startX = runtime.robotX,
            startY = runtime.robotY,
            startZ = runtime.robotZ,
            elapsed = 0,
            duration = C.projectileTravelSeconds,
        }
        data.cooldowns.attack = Rules.statValue(data, "attackCooldown") or 4
        runtime.behaviorState = "recovery"
        runtime.recoveryUntilMs = now + C.robotRecoverySeconds * 1000
        runtime.recoilUntilMs = now + math.min(0.10, C.robotRecoverySeconds) * 1000
        runtime.fireFlashUntilMs = now + 120
        runtime.combatUntilMs = now + C.robotCombatGraceSeconds * 1000
        runtime.lastCombatTarget = target
        runtime.lastCombatTargetExpiresMs = runtime.combatUntilMs
        instance.launchedAttacks = instance.launchedAttacks + 1
        port("visualFire", visuals.emit, "fire", runtime, data, nil, target)
        return true
    end

    local function scan(actor, radius, maximum)
        local rows = port("scanTargets", query.scanTargets, actor, radius, maximum)
        return type(rows) == "table" and rows or {}
    end

    local function findTarget(actor, data, runtime, now)
        local rows = scan(actor, Rules.attackRadius(data), nil)
        for index = 1, #rows do
            local target = rows[index].target or rows[index]
            if targetAllowed(actor, data, runtime, target, now) then return target end
        end
        return nil
    end

    local function effectTargets(actor, source, radius, runtime, now)
        local rows = scan(actor, radius, nil)
        local sourceView = port("effectSource", query.targetSnapshot, actor, source)
        local result = {}
        for index = 1, #rows do
            local target = rows[index].target or rows[index]
            if target ~= source then
                local view = port("effectTarget", query.targetSnapshot, actor, target)
                if Rules.distanceSquared(sourceView, view) <= radius * radius
                        and Rules.targetAllowed({ combatMode = "active" },
                            sourceView, view, sightMarked(runtime, target, now) or view.visible) then
                    result[#result + 1] = target
                end
            end
        end
        return result
    end

    local function queueVisual(runtime, kind, source, target, now, duration)
        runtime.effectVisuals[#runtime.effectVisuals + 1] = {
            kind = kind,
            source = source,
            target = target,
            createdAt = now,
            expiresAt = now + math.max(80, Rules.integer(duration, 250, 80)),
        }
    end

    local function applyDamage(actor, target, amount)
        return port("damage", mutation.damage, actor, target, amount) == true
    end

    local function applyEffects(actor, target, data, runtime, directDamage, now)
        if data.effects.shock then
            local readyAt = Rules.integer(runtime.shockCooldowns[target], 0, 0)
            if now >= readyAt then
                port("shock", mutation.shock, target)
                runtime.shockCooldowns[target] = now + C.shockInternalCooldownSeconds * 1000
                queueVisual(runtime, "shock", target, nil, now, 260)
            end
        end
        if data.effects.corrosion then
            local tickDamage = math.max(0.01, directDamage * C.corrosionDamageRatio)
            local row = runtime.corrosionStates[target]
            if row then
                row.damage = math.max(Rules.number(row.damage, 0), tickDamage)
                row.expiresAt = now + C.corrosionDurationSeconds * 1000
            else
                runtime.corrosionStates[target] = {
                    damage = tickDamage,
                    nextTickMs = now + C.corrosionTickSeconds * 1000,
                    expiresAt = now + C.corrosionDurationSeconds * 1000,
                }
            end
            queueVisual(runtime, "corrosion", target, nil, now, 360)
        end
        if data.effects.mark then runtime.markStates[target] = now + C.markDurationSeconds * 1000 end
        local used, occupied = { [target] = true }, 0
        if data.effects.chain then
            local chained = effectTargets(actor, target, C.chainRadius, runtime, now)[1]
            if chained then
                used[chained], occupied = true, 1
                applyDamage(actor, chained, directDamage * C.chainDamageRatio)
                queueVisual(runtime, "chain", target, chained, now, 280)
            end
        end
        if data.effects.blast then
            queueVisual(runtime, "blast", target, nil, now, 420)
            for _, candidate in ipairs(effectTargets(actor, target, C.blastRadius, runtime, now)) do
                if occupied >= C.blastTargetCap then break end
                if not used[candidate] then
                    used[candidate], occupied = true, occupied + 1
                    applyDamage(actor, candidate, directDamage * C.blastDamageRatio)
                end
            end
        end
    end

    local function updateEffects(actor, data, runtime, now)
        for target, readyAt in pairs(runtime.shockCooldowns) do
            local view = port("shockTarget", query.targetSnapshot, actor, target)
            if not view or view.dead or now >= Rules.integer(readyAt, 0, 0) then
                runtime.shockCooldowns[target] = nil
            end
        end
        for target, expiresAt in pairs(runtime.markStates) do
            local view = port("markTarget", query.targetSnapshot, actor, target)
            if not view or view.dead or now >= Rules.integer(expiresAt, 0, 0) then
                runtime.markStates[target] = nil
            end
        end
        for target, row in pairs(runtime.corrosionStates) do
            local view = port("corrosionTarget", query.targetSnapshot, actor, target)
            if not view or view.dead then
                runtime.corrosionStates[target] = nil
            else
                local expiresAt = Rules.integer(row.expiresAt, 0, 0)
                local nextTick = Rules.integer(row.nextTickMs, now + C.corrosionTickSeconds * 1000, 0)
                while nextTick <= now and nextTick <= expiresAt do
                    if not applyDamage(actor, target, row.damage) then break end
                    queueVisual(runtime, "corrosion", target, nil, now, 260)
                    nextTick = nextTick + C.corrosionTickSeconds * 1000
                end
                row.nextTickMs = nextTick
                if now >= expiresAt and nextTick > expiresAt then runtime.corrosionStates[target] = nil end
            end
        end
        for index = #runtime.effectVisuals, 1, -1 do
            if now >= Rules.integer(runtime.effectVisuals[index].expiresAt, 0, 0) then
                table.remove(runtime.effectVisuals, index)
            end
        end
    end

    local function updateProjectiles(actor, data, runtime, delta, now)
        for index = #runtime.projectiles, 1, -1 do
            local projectile = runtime.projectiles[index]
            projectile.elapsed = Rules.number(projectile.elapsed, 0, 0)
                + Rules.number(delta, 0, 0, 0.25)
            local targetView = port("projectileTarget", query.targetSnapshot, actor, projectile.target)
            if not targetView or targetView.dead then
                table.remove(runtime.projectiles, index)
            elseif projectile.elapsed >= Rules.number(projectile.duration, C.projectileTravelSeconds, 0.01) then
                local damage = Rules.finalDamage(data)
                if Rules.integer(runtime.markStates[projectile.target], 0, 0) > now then
                    damage = damage * C.markDamageMultiplier
                end
                if applyDamage(actor, projectile.target, damage) then
                    applyEffects(actor, projectile.target, data, runtime, damage, now)
                end
                table.remove(runtime.projectiles, index)
            end
        end
    end

    local function updateAttack(actor, actorView, data, runtime, now)
        if runtime.pendingAttack then
            local target = runtime.pendingAttack.target
            if not data.unlocks.attack or not targetAllowed(actor, data, runtime, target, now) then
                cancelAttack(runtime, data)
                return
            end
            local targetView = port("chargingTarget", query.targetSnapshot, actor, target)
            runtime.attackDirection = direction(
                targetView.x - runtime.robotX, targetView.y - runtime.robotY)
            runtime.behaviorState = "charging"
            if data.visible and now >= Rules.integer(runtime.nextChargeParticleMs, 0, 0) then
                port("visualCharge", visuals.emit, "charge", runtime, data, actor, target)
                runtime.nextChargeParticleMs = now + 60
            end
            if now >= Rules.integer(runtime.chargeEndsMs, 0, 0) then launchAttack(data, runtime, now) end
            return
        end
        if now < Rules.integer(runtime.recoveryUntilMs, 0, 0) then
            runtime.behaviorState = "recovery"
            return
        end
        if data.combatMode == "ceasefire" or not data.unlocks.attack
                or data.cooldowns.attack > 0
                or now < Rules.integer(runtime.nextAttackSearchMs, 0, 0) then return end
        runtime.nextAttackSearchMs = now + C.attackSearchSeconds * 1000
        local target = findTarget(actor, data, runtime, now)
        if target then
            beginAttack(runtime, actorView, target,
                port("beginTarget", query.targetSnapshot, actor, target), now)
        end
    end

    local function chooseOrbit(actor, actorView, data, runtime, now)
        local minimum, maximum
        if data.followMode == "guard" and data.guardPoint then
            minimum, maximum = 0.15, C.robotGuardDriftRadius
            actorView = data.guardPoint
        else
            local band = Rules.followBands[data.followMode] or Rules.followBands.follow5
            minimum, maximum = band.minimum, band.maximum
            if port("nearPatrol", query.randomBetween, 0, 1) < C.robotNearPatrolChance then
                maximum = math.min(maximum, minimum + math.max(0.25, (maximum - minimum) * 0.35))
            end
        end
        for _ = 1, 12 do
            local angle = port("orbitAngle", query.randomBetween, 0, math.pi * 2)
            local radius = port("orbitRadius", query.randomBetween, minimum, maximum)
            local point = {
                x = actorView.x + math.cos(angle) * radius,
                y = actorView.y + math.sin(angle) * radius,
                z = actorView.z,
            }
            if port("pointAvailable", query.pointAvailable, actor, point, false) == true then
                runtime.targetX, runtime.targetY, runtime.targetZ = point.x, point.y, point.z
                runtime.nextOrbitRetargetMs = now + port("retargetDelay", query.randomBetween,
                    C.robotOrbitRetargetMinSeconds, C.robotOrbitRetargetMaxSeconds) * 1000
                return
            end
        end
        runtime.nextOrbitRetargetMs = now + C.robotOrbitRetargetMinSeconds * 1000
    end

    local function updateMotion(actor, actorView, data, runtime, delta, now)
        if not runtime.robotX then State.resetNear(runtime, actorView) end
        if math.floor(runtime.robotZ + 0.1) ~= math.floor(actorView.z + 0.1)
                or Rules.distanceSquared({ x = runtime.robotX, y = runtime.robotY },
                    actorView) > C.robotRecallDistance * C.robotRecallDistance then
            State.resetNear(runtime, actorView)
        end
        if runtime.pendingAttack then runtime.behaviorState = "charging" return end
        if now < Rules.integer(runtime.recoveryUntilMs, 0, 0) then
            runtime.behaviorState = "recovery"
            return
        end
        local band = Rules.followBands[data.followMode] or Rules.followBands.follow5
        local playerDistance = math.sqrt(Rules.distanceSquared(
            { x = runtime.robotX, y = runtime.robotY }, actorView))
        local catchup = data.followMode ~= "guard" and playerDistance > band.maximum + C.robotCatchupMargin
        if catchup then
            runtime.targetX, runtime.targetY, runtime.targetZ = actorView.x, actorView.y, actorView.z
            runtime.behaviorState = "catchup"
        elseif not runtime.targetX and now >= Rules.integer(runtime.nextOrbitRetargetMs, 0, 0) then
            chooseOrbit(actor, actorView, data, runtime, now)
        end
        local tx, ty, tz = runtime.targetX, runtime.targetY, runtime.targetZ
        if tx == nil then
            runtime.behaviorState = data.followMode == "guard" and "guard" or "idle"
            return
        end
        if not catchup then runtime.behaviorState = data.followMode == "guard" and "guard" or "patrol" end
        local dx, dy = tx - runtime.robotX, ty - runtime.robotY
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= 0.08 then
            runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
            runtime.idleUntilMs = now + port("idleDelay", query.randomBetween,
                C.robotIdleMinSeconds, C.robotIdleMaxSeconds) * 1000
            return
        end
        local step = math.min(distance,
            (catchup and C.robotCatchupSpeed or C.robotNormalSpeed) * delta)
        local nx, ny = runtime.robotX + dx / distance * step, runtime.robotY + dy / distance * step
        local point = { x = nx, y = ny, z = tz }
        if port("motionPoint", query.pointAvailable, actor, point, false) ~= true then
            runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
            return
        end
        if now >= Rules.integer(runtime.attackFacingUntilMs, 0, 0) then
            runtime.direction = direction(nx - runtime.robotX, ny - runtime.robotY) or runtime.direction
        end
        runtime.robotX, runtime.robotY, runtime.robotZ = nx, ny, tz
        if data.visible and now >= Rules.integer(runtime.nextTrailMs, 0, 0) then
            port("visualTrail", visuals.emit, catchup and "catchup" or "trail",
                runtime, data, actor, nil)
            runtime.nextTrailMs = now + C.robotTrailSeconds * 1000
        end
    end

    local function updateLight(actor, data, runtime)
        if not data.visible or runtime.vehicleSuspended or not runtime.robotX then
            if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
            runtime.light = nil
            return
        end
        local radius = Rules.statValue(data, "light") or 6
        local wanted = {
            x = math.floor(runtime.robotX),
            y = math.floor(runtime.robotY),
            z = math.floor(runtime.robotZ + 0.1),
        }
        local current = runtime.lightPosition
        if runtime.light and current and current.x == wanted.x and current.y == wanted.y
                and current.z == wanted.z and runtime.lightRadius == radius then return end
        runtime.light = port("setLight", mutation.setLight, runtime.light, wanted, radius)
        runtime.lightPosition, runtime.lightRadius = wanted, radius
    end

    local function triggerGuardian(actor, data, runtime, now)
        if not data.unlocks.guardian or not data.guardianEnabled or data.cooldowns.guardian > 0 then return end
        local threats = scan(actor, C.guardianTriggerRadius, C.guardianTriggerCount)
        if #threats < C.guardianTriggerCount then return end
        local targets = scan(actor, Rules.statValue(data, "guardianRange") or 4, nil)
        local maximum, knocked = Rules.integer(Rules.statValue(data, "guardianCount"), 4, 0), 0
        for index = 1, math.min(maximum, #targets) do
            local target = targets[index].target or targets[index]
            if port("guardian", mutation.knockDown, target) == true then knocked = knocked + 1 end
        end
        if knocked > 0 then
            data.cooldowns.guardian = Rules.statValue(data, "guardianCooldown") or 180
            runtime.combatUntilMs = now + C.robotCombatGraceSeconds * 1000
            runtime.guardianFlashUntilMs = now + 450
            runtime.idleUntilMs = 0
            port("visualGuardian", visuals.emit, "guardian", runtime, data, actor, nil)
            queueVisual(runtime, "guardian", actor, nil, now, 450)
        end
    end

    local function shutdownActor(actor)
        local actual, owner, data = actorContext(actor)
        if not actual then return true end
        local runtime = store:runtime(owner)
        if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
        runtime.light = nil
        port("visualReset", visuals.reset, runtime)
        State.clearTransient(runtime, true)
        if runtime.dirty then store:save(owner, data) end
        store:clearRuntime(owner, true)
        return true
    end

    local function tick(actor)
        local request = { actor = actor }
        return guarded(request, "tick", function()
            if not instance.started then return result(false, "moduleStopped", nil, request, false) end
            local actual, owner, data, code = actorContext(actor)
            if not actual then return result(false, code, nil, request, false) end
            local runtime = store:runtime(owner)
            local actorView = port("actorSnapshot", query.actorSnapshot, actual)
            if not data.unlocked or config.enabled == false or actorView.dead then
                shutdownActor(actual)
                return result(true, "inactive", nil, request, false)
            end
            local now = Rules.integer(port("clock", query.nowMs), 0, 0)
            local previous = runtime.lastUpdateMs or now
            runtime.lastUpdateMs = now
            local delta = Rules.number((now - previous) / 1000, 0, 0, 0.25)
            if actorView.paused then
                if not runtime.pauseSuspended then
                    cancelAttack(runtime, data)
                    runtime.combatUntilMs = 0
                    runtime.lastCombatTarget = nil
                    runtime.nextStrafeMs = 0
                    port("visualReset", visuals.reset, runtime)
                    runtime.pauseSuspended = true
                end
                return result(true, "paused", nil, request, false)
            end
            runtime.pauseSuspended = false
            if actorView.inVehicle then
                if not runtime.vehicleSuspended then
                    if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
                    runtime.light = nil
                    State.clearTransient(runtime, true)
                    port("visualReset", visuals.reset, runtime)
                    runtime.vehicleSuspended = true
                end
                return result(true, "vehicleSuspended", nil, request, false)
            elseif runtime.vehicleSuspended then
                runtime.vehicleSuspended = false
                runtime.lastUpdateMs = now
                State.resetNear(runtime, actorView)
            end
            data = Rules.decrementCooldowns(data, delta)
            updateEffects(actual, data, runtime, now)
            updateProjectiles(actual, data, runtime, delta, now)
            updateAttack(actual, actorView, data, runtime, now)
            updateMotion(actual, actorView, data, runtime, delta, now)
            runtime.animationElapsed = Rules.number(runtime.animationElapsed, 0, 0) + delta
            while runtime.animationElapsed >= 0.18 do
                runtime.animationElapsed = runtime.animationElapsed - 0.18
                runtime.animationFrame = runtime.animationFrame == 0 and 1 or 0
            end
            runtime.bobPhase = (Rules.number(runtime.bobPhase, 0) + delta * 2.4) % (math.pi * 2)
            updateLight(actual, data, runtime)
            if now - Rules.integer(runtime.lastGuardianScanMs, 0, 0)
                    >= C.guardianScanSeconds * 1000 then
                runtime.lastGuardianScanMs = now
                triggerGuardian(actual, data, runtime, now)
            end
            save(owner, data, runtime, false)
            instance.ticks = instance.ticks + 1
            return result(true, "updated", {
                behaviorState = runtime.behaviorState,
                pendingAttack = runtime.pendingAttack ~= nil,
                projectiles = #runtime.projectiles,
            }, request, false)
        end)
    end

    local function render()
        return guarded({}, "render", function()
            if not instance.started then return false end
            local actor, owner, data = actorContext(nil)
            if not actor or not data.unlocked then return false end
            local runtime = store:runtime(owner)
            local rendered = port("visualRender", visuals.render, runtime, data, actor)
            instance.renders = instance.renders + 1
            return rendered ~= false
        end)
    end

    local function purchase(request)
        request = type(request) == "table" and request or {}
        return guarded(request, "purchase", function()
            if not instance.started then return result(false, "moduleStopped", nil, request) end
            local id = operationId(request)
            if not id then return result(false, "operationIdRequired", nil, request) end
            local actual, owner, data, code = actorContext(request.actor)
            if not actual then return result(false, code, nil, request) end
            local fingerprint = "purchase|" .. tostring(request.nodeId or "")
            local status, ledger = port("operationBegin", operations.begin,
                moduleId, id, fingerprint, request)
            if status == "replay" then return ledger end
            if status ~= "new" then
                return result(false, type(ledger) == "table" and ledger.code or "operationInvalid", nil, request)
            end
            local quote, quoteCode = Rules.purchaseQuote(data, request.nodeId,
                Rules.number(config.priceMultiplier, 1, 0.01))
            if not quote then
                local value = result(false, quoteCode, nil, request)
                port("operationFinish", operations.finish, moduleId, id, value, request)
                return value
            end
            local paid, receiptOrCode, paymentData = port(
                "walletCharge", wallet.charge, actual, quote.cost, request)
            if paid ~= true then
                local value = result(false, receiptOrCode or "paymentFailed", paymentData, request)
                port("operationFinish", operations.finish, moduleId, id, value, request)
                return value
            end
            local before = Rules.copy(data)
            local nextData, applyCode = Rules.applyPurchase(data, quote)
            if not nextData or not store:save(owner, nextData) then
                local refunded = port("walletRefund", wallet.refund, actual, receiptOrCode, request)
                store:save(owner, before)
                local value = result(false, refunded == true and (applyCode or "stateSaveFailed")
                    or "rollbackIncomplete", nil, request)
                port("operationFinish", operations.finish, moduleId, id, value, request)
                return value
            end
            local value = result(true, "purchased", {
                nodeId = quote.nodeId,
                kind = quote.kind,
                cost = quote.cost,
            }, request)
            local finished, stored = call(operations.finish, moduleId, id, value, request)
            if not finished or stored == false then
                port("operationUnknown", operations.markUnknown,
                    moduleId, id, "operationOutcomeUnknown", request)
                instance.lastIssue = {
                    stage = "operationFinish",
                    code = "operationOutcomeUnknown",
                    message = tostring(stored),
                }
                return result(false, "operationOutcomeUnknown", { committed = true }, request)
            end
            return value
        end)
    end

    local function mutateControl(request, callback)
        request = type(request) == "table" and request or {}
        return guarded(request, "control", function()
            if not instance.started then return result(false, "moduleStopped", nil, request) end
            local actor, owner, data, code = actorContext(request.actor)
            if not actor or not data.unlocked then return result(false, code or "projectionLocked", nil, request) end
            local runtime = store:runtime(owner)
            local ok, resultCode, resultData = callback(actor, data, runtime)
            if ok == false then return result(false, resultCode or "controlInvalid", nil, request) end
            local saved, saveCode = store:save(owner, data)
            if not saved then return result(false, saveCode or "stateSaveFailed", nil, request) end
            return result(true, resultCode or "updated", resultData, request)
        end)
    end

    local function setPreference(request)
        return mutateControl(request, function(_, data)
            local ui = type(request.ui) == "table" and request.ui or {}
            data.ui = type(data.ui) == "table" and data.ui or {}
            if ui.shortcutVisible ~= nil then
                data.ui.shortcutVisible = ui.shortcutVisible == true
            end
            if ui.shortcutX ~= nil then
                local value = tonumber(ui.shortcutX)
                if not value or value ~= value
                    or value == math.huge or value == -math.huge
                then
                    return false, "preferenceValueInvalid"
                end
                data.ui.shortcutX = math.floor(value)
            end
            if ui.shortcutY ~= nil then
                local value = tonumber(ui.shortcutY)
                if not value or value ~= value
                    or value == math.huge or value == -math.huge
                then
                    return false, "preferenceValueInvalid"
                end
                data.ui.shortcutY = math.floor(value)
            end
            return true, "preferenceChanged", {
                ui = Rules.copy(data.ui),
            }
        end)
    end

    local function activateSight(request)
        return mutateControl(request, function(actor, data, runtime)
            if not data.unlocks.sight then return false, "sightLocked" end
            if runtime.vehicleSuspended or data.cooldowns.sight > 0 then return false, "cooldown" end
            local targets = scan(actor, Rules.statValue(data, "sightRange") or 10, nil)
            if #targets == 0 then return false, "targetMissing" end
            runtime.sightTargets = {}
            local now = Rules.integer(port("clock", query.nowMs), 0, 0)
            local expiresAt = now + C.sightDurationSeconds * 1000
            for index = 1, math.min(C.sightTargetCap, #targets) do
                runtime.sightTargets[#runtime.sightTargets + 1] = {
                    target = targets[index].target or targets[index],
                    expiresAt = expiresAt,
                }
            end
            data.cooldowns.sight = Rules.statValue(data, "sightCooldown") or 120
            runtime.sightFlashUntilMs = now + 460
            port("visualSight", visuals.emit, "sight", runtime, data, actor, nil)
            return true, "sightActivated"
        end)
    end

    local function setCombatMode(request)
        return mutateControl(request, function(_, data, runtime)
            local mode = request.mode
            if mode ~= "active" and mode ~= "defensive" and mode ~= "ceasefire" then
                return false, "modeInvalid"
            end
            data.combatMode = mode
            if mode == "ceasefire" then
                cancelAttack(runtime, data)
                runtime.combatUntilMs = 0
                runtime.lastCombatTarget = nil
                runtime.lastCombatTargetExpiresMs = 0
                runtime.nextStrafeMs = 0
            end
            return true, "combatModeChanged"
        end)
    end

    local function setFollowMode(request)
        return mutateControl(request, function(actor, data, runtime)
            local mode = request.mode
            if mode ~= "follow3" and mode ~= "follow5" and mode ~= "follow10" and mode ~= "guard" then
                return false, "modeInvalid"
            end
            data.followMode = mode
            if mode == "guard" then
                local actorView = port("actorSnapshot", query.actorSnapshot, actor)
                if not runtime.robotX then State.resetNear(runtime, actorView) end
                data.guardPoint = { x = runtime.robotX, y = runtime.robotY, z = runtime.robotZ }
            else
                data.guardPoint = nil
            end
            runtime.nextOrbitRetargetMs = 0
            return true, "followModeChanged"
        end)
    end

    local function toggleVisible(request)
        return mutateControl(request, function(_, data, runtime)
            data.visible = not data.visible
            if not data.visible then
                if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
                runtime.light = nil
                cancelAttack(runtime, data)
                runtime.combatUntilMs = 0
                runtime.lastCombatTarget = nil
                runtime.lastCombatTargetExpiresMs = 0
                runtime.nextStrafeMs = 0
                port("visualReset", visuals.reset, runtime)
            end
            return true, "visibilityChanged"
        end)
    end

    local function recall(request)
        return mutateControl(request, function(actor, data, runtime)
            data.followMode, data.guardPoint = "follow5", nil
            if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
            runtime.light = nil
            port("visualReset", visuals.reset, runtime)
            State.resetNear(runtime, port("actorSnapshot", query.actorSnapshot, actor))
            port("visualRecall", visuals.emit, "recall", runtime, data, actor, nil)
            return true, "recalled"
        end)
    end

    instance.public = {
        purchase = purchase,
        tick = tick,
        render = render,
        activateSight = activateSight,
        setCombatMode = setCombatMode,
        setFollowMode = setFollowMode,
        toggleVisible = toggleVisible,
        toggleGuardian = function(request)
            return mutateControl(request, function(_, data)
                if not data.unlocks.guardian then return false, "guardianLocked" end
                data.guardianEnabled = not data.guardianEnabled
                return true, "guardianChanged"
            end)
        end,
        recall = recall,
        setPreference = setPreference,
        getState = function(request)
            request = type(request) == "table" and request or {}
            local actor, owner, data, code = actorContext(request.actor)
            if not actor then return result(false, code, nil, request) end
            return result(true, "state", {
                persistent = Rules.copy(data),
                runtime = Rules.copy(store:runtime(owner)),
            }, request)
        end,
        shutdown = function(request)
            request = type(request) == "table" and request or {}
            return guarded(request, "shutdown", function()
                shutdownActor(request.actor)
                return result(true, "stopped", nil, request)
            end)
        end,
    }

    function instance:start()
        local bound, code = events.bind({
            gameStart = function() store:clearAll() end,
            playerUpdate = function(actor) tick(actor) end,
            playerDeath = function(actor) shutdownActor(actor) end,
            render = render,
        })
        if bound == false then
            self.lastIssue = { stage = "eventBind", code = code or "eventBindingFailed" }
            return false, code
        end
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        events.unbind()
        for _, runtime in pairs(store.runtimes) do
            if runtime.light then port("removeLight", mutation.removeLight, runtime.light) end
            port("visualReset", visuals.reset, runtime)
        end
        store:clearAll()
        return true
    end

    function instance:health()
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            ticks = self.ticks,
            renders = self.renders,
            cancelledAttacks = self.cancelledAttacks,
            launchedAttacks = self.launchedAttacks,
            state = store:health(),
            lastIssue = self.lastIssue,
        }
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
