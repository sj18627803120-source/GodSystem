require "GodSystem/Features/Companion/Rules"

GodSystemCompanionFeatureState = GodSystemCompanionFeatureState or {}

local State = GodSystemCompanionFeatureState
local Rules = GodSystemCompanionFeatureRules

function State.newRuntime()
    return {
        robotX = nil, robotY = nil, robotZ = nil,
        targetX = nil, targetY = nil, targetZ = nil,
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
        sightTargets = {},
        projectiles = {},
        shockCooldowns = {},
        corrosionStates = {},
        markStates = {},
        effectVisuals = {},
        lastUpdateMs = nil,
        lastGuardianScanMs = 0,
        nextAttackSearchMs = 0,
        dirty = false,
        lastSaveMs = 0,
        vehicleSuspended = false,
        pauseSuspended = false,
    }
end

function State.cancelAttack(runtime, nextState)
    runtime.pendingAttack = nil
    runtime.chargeStartedMs = 0
    runtime.chargeEndsMs = 0
    runtime.nextChargeParticleMs = 0
    runtime.attackDirection = nil
    runtime.attackFacingUntilMs = 0
    if runtime.behaviorState == "charging" then runtime.behaviorState = nextState or "idle" end
    return runtime
end

function State.clearTransient(runtime, clearSight)
    State.cancelAttack(runtime, "idle")
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
    if clearSight then runtime.sightTargets = {} end
    return runtime
end

function State.resetNear(runtime, position)
    position = type(position) == "table" and position or {}
    State.clearTransient(runtime, false)
    runtime.robotX = Rules.number(position.x, 0) + 0.8
    runtime.robotY = Rules.number(position.y, 0) + 0.8
    runtime.robotZ = Rules.number(position.z, 0)
    runtime.targetX, runtime.targetY, runtime.targetZ = nil, nil, nil
    runtime.nextOrbitRetargetMs = 0
    runtime.idleUntilMs = 0
    runtime.nextLookMs = 0
    runtime.combatUntilMs = 0
    runtime.direction = "SE"
    return runtime
end

function State.new(scope)
    assert(type(scope) == "table" and type(scope.get) == "function"
        and type(scope.replace) == "function", "companion state scope required")
    local instance = { runtimes = {} }

    local function root()
        local value = scope:get()
        value.actors = type(value.actors) == "table" and value.actors or {}
        return value
    end

    function instance:load(ownerKey)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" then return nil, "ownerRequired" end
        local value = root()
        value.actors[ownerKey] = Rules.normalizePersistent(value.actors[ownerKey])
        return Rules.copy(value.actors[ownerKey])
    end

    function instance:save(ownerKey, data)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" then return false, "ownerRequired" end
        local value = root()
        value.actors[ownerKey] = Rules.normalizePersistent(data)
        scope:replace(value, Rules.stateVersion)
        return true
    end

    function instance:runtime(ownerKey)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" then return nil end
        self.runtimes[ownerKey] = self.runtimes[ownerKey] or State.newRuntime()
        return self.runtimes[ownerKey]
    end

    function instance:clearRuntime(ownerKey, clearSight)
        local runtime = self.runtimes[tostring(ownerKey or "")]
        if runtime then State.clearTransient(runtime, clearSight ~= false) end
        self.runtimes[tostring(ownerKey or "")] = nil
        return true
    end

    function instance:clearAll()
        for key, runtime in pairs(self.runtimes) do
            State.clearTransient(runtime, true)
            self.runtimes[key] = nil
        end
        return true
    end

    function instance:health()
        local count = 0
        for _ in pairs(self.runtimes) do count = count + 1 end
        return { ok = true, code = "healthy", data = { activeRuntimes = count } }
    end

    return instance
end

return State
