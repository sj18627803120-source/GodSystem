require "GodSystem/Platform/Progression/Support"

GodSystemMedicalBodyPlatform = GodSystemMedicalBodyPlatform or {}

local Descriptor = GodSystemMedicalBodyPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "medical.body"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local BODY_FIELDS = {
    overall = { get = { "getOverallBodyHealth", "getHealth" }, set = { "setOverallBodyHealth" } },
    infected = { get = { "IsInfected", "isInfected" }, set = { "setInfected" } },
    fakeInfected = { get = { "IsFakeInfected", "isFakeInfected" }, set = { "setIsFakeInfected" } },
    infectionTime = { get = { "getInfectionTime" }, set = { "setInfectionTime" } },
    mortality = { get = { "getInfectionMortalityDuration" }, set = { "setInfectionMortalityDuration" } },
    infectionLevel = { get = { "getInfectionLevel" }, set = { "setInfectionLevel" } },
}

local PART_FIELDS = {
    health = { get = { "getHealth" }, set = { "setHealth", "SetHealth" } },
    bleeding = { get = { "getBleedingTime" }, set = { "setBleedingTime" } },
    deepWound = { get = { "getDeepWoundTime" }, set = { "setDeepWoundTime" } },
    scratch = { get = { "getScratchTime" }, set = { "setScratchTime" } },
    cut = { get = { "getCutTime" }, set = { "setCutTime" } },
    bite = { get = { "getBiteTime" }, set = { "setBiteTime" } },
    burn = { get = { "getBurnTime" }, set = { "setBurnTime" } },
    fracture = { get = { "getFractureTime" }, set = { "setFractureTime" } },
    pain = { get = { "getAdditionalPain" }, set = { "setAdditionalPain" } },
    woundInfection = { get = { "getWoundInfectionLevel" }, set = { "setWoundInfectionLevel" } },
    bullet = { get = { "haveBullet", "HasBullet" }, set = { "setHaveBullet" } },
    glass = { get = { "haveGlass", "HasGlass" }, set = { "setHaveGlass" } },
    stitched = { get = { "stitched", "isStitched" }, set = { "setStitched" } },
    splint = { get = { "isSplint" }, set = { "setSplint" } },
    bandaged = { get = { "bandaged", "isBandaged" }, set = { "setBandaged" } },
    infectedWound = { get = { "isInfectedWound" }, set = { "setInfectedWound", "SetInfected" } },
    fakeInfected = { get = { "isFakeInfected" }, set = { "SetFakeInfected" } },
}

local function capture(target, fields)
    local result = {}
    for name, field in pairs(fields) do result[name] = Support.read(target, field.get, nil) end
    return result
end

local function restore(target, fields, values)
    if not target or type(values) ~= "table" then return false end
    local ok = true
    for name, field in pairs(fields) do
        if values[name] ~= nil then ok = Support.write(target, field.set, values[name]) and ok end
    end
    return ok
end

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local counters = { inspections = 0, snapshots = 0, mutations = 0, restores = 0, failures = 0 }
    local public = {}

    local function bodyFor(actor, request)
        if type(binding.body) == "function" then
            local ok, body = pcall(binding.body, actor, request)
            if ok and body then return body end
        end
        local ok, body = Support.call(actor, "getBodyDamage")
        return ok and body or nil
    end

    local function parts(body)
        return Support.values(Support.read(body, { "getBodyParts" }, nil))
    end

    local function infected(body)
        if Support.read(body, { "IsInfected", "isInfected" }, false) == true then return true end
        if (Support.number(Support.read(body, { "getInfectionLevel" }, 0), 0) or 0) > 0 then return true end
        return (Support.number(Support.read(body, { "getInfectionTime" }, -1), -1) or -1) > 0
    end

    local function injured(body)
        local overall = Support.number(Support.read(body, { "getOverallBodyHealth", "getHealth" }, nil), nil)
        if overall and overall < 99.5 then return true end
        local values = parts(body)
        for index = 1, #values do
            local state = capture(values[index], PART_FIELDS)
            if Support.number(state.health, 100) < 99.5
                or Support.number(state.bleeding, 0) > 0
                or Support.number(state.deepWound, 0) > 0
                or Support.number(state.scratch, 0) > 0
                or Support.number(state.cut, 0) > 0
                or Support.number(state.bite, 0) > 0
                or Support.number(state.burn, 0) > 0
                or Support.number(state.fracture, 0) > 0
                or Support.number(state.pain, 0) > 0
                or Support.number(state.woundInfection, 0) > 0
                or state.bullet == true or state.glass == true or state.stitched == true
                or state.splint == true or state.bandaged == true then return true end
        end
        return false
    end

    local function nativeSnapshot(actor, action, request)
        local body = bodyFor(actor, request)
        if not body then return nil, "medicalUnavailable" end
        local bodyParts, states = parts(body), {}
        for index = 1, #bodyParts do
            states[index] = { part = bodyParts[index], values = capture(bodyParts[index], PART_FIELDS) }
        end
        local zombieStat = nil
        local stats = Support.read(actor, { "getStats" }, nil)
        if stats and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil
            and type(stats.get) == "function" then
            local ok, value = pcall(stats.get, stats, CharacterStat.ZOMBIE_INFECTION)
            if ok then zombieStat = value end
        end
        return {
            actor = actor,
            body = body,
            action = action,
            bodyValues = capture(body, BODY_FIELDS),
            playerHealth = Support.read(actor, { "getHealth" }, nil),
            zombieStat = zombieStat,
            parts = states,
        }
    end

    local function nativeRestore(snapshot)
        if type(snapshot) ~= "table" or not snapshot.body then return false end
        local ok = restore(snapshot.body, BODY_FIELDS, snapshot.bodyValues)
        if snapshot.playerHealth ~= nil then
            ok = Support.write(snapshot.actor, { "setHealth" }, snapshot.playerHealth) and ok
        end
        for index = 1, #(snapshot.parts or {}) do
            ok = restore(snapshot.parts[index].part, PART_FIELDS, snapshot.parts[index].values) and ok
        end
        if snapshot.zombieStat ~= nil and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil then
            local stats = Support.read(snapshot.actor, { "getStats" }, nil)
            if stats and type(stats.set) == "function" then
                ok = pcall(stats.set, stats, CharacterStat.ZOMBIE_INFECTION, snapshot.zombieStat) and ok
            end
        end
        return ok
    end

    local function heal(actor, body)
        local values = parts(body)
        for index = 1, #values do
            local part = values[index]
            Support.write(part, { "setHealth", "SetHealth" }, 100)
            Support.write(part, { "setBleedingTime" }, 0)
            Support.write(part, { "setDeepWoundTime" }, 0)
            Support.write(part, { "setScratchTime" }, 0)
            Support.write(part, { "setCutTime" }, 0)
            Support.write(part, { "setBiteTime" }, 0)
            Support.write(part, { "setBurnTime" }, 0)
            Support.write(part, { "setFractureTime" }, 0)
            Support.write(part, { "setAdditionalPain" }, 0)
            Support.write(part, { "setWoundInfectionLevel" }, 0)
            Support.write(part, { "setHaveBullet" }, false, 0)
            Support.write(part, { "setHaveGlass" }, false)
            Support.write(part, { "setStitched" }, false)
            Support.write(part, { "setSplint" }, false, 0)
            Support.write(part, { "setBandaged" }, false, 0, false, "", nil)
        end
        Support.write(body, { "setOverallBodyHealth" }, 100)
        Support.write(actor, { "setHealth" }, 1.0)
        return injured(body) ~= true
    end

    local function cure(actor, body)
        Support.write(body, { "setInfectionTime" }, -1)
        Support.write(body, { "setInfectionLevel" }, 0)
        Support.write(body, { "setInfected" }, false)
        Support.write(body, { "setIsFakeInfected" }, false)
        Support.write(body, { "setInfectionMortalityDuration" }, -1)
        local values = parts(body)
        for index = 1, #values do
            Support.write(values[index], { "setInfectedWound", "SetInfected" }, false)
            Support.write(values[index], { "SetFakeInfected" }, false)
            Support.write(values[index], { "setWoundInfectionLevel" }, -1)
        end
        local stats = Support.read(actor, { "getStats" }, nil)
        if stats and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil
            and type(stats.set) == "function" then
            pcall(stats.set, stats, CharacterStat.ZOMBIE_INFECTION, 0)
        end
        return infected(body) ~= true
    end

    function public.inspect(actor, request)
        counters.inspections = counters.inspections + 1
        if type(binding.inspect) == "function" then return binding.inspect(actor, request) end
        local body = bodyFor(actor, request)
        if not body then return nil, "medicalUnavailable" end
        return { infected = infected(body), injured = injured(body) }
    end

    function public.snapshot(actor, action, request)
        counters.snapshots = counters.snapshots + 1
        if type(binding.snapshot) == "function" then return binding.snapshot(actor, action, request) end
        return nativeSnapshot(actor, action, request)
    end

    function public.apply(actor, action, snapshot, request)
        counters.mutations = counters.mutations + 1
        if type(binding.apply) == "function" then return binding.apply(actor, action, snapshot, request) end
        local body = snapshot and snapshot.body or bodyFor(actor, request)
        if not body then return false, "medicalUnavailable" end
        if action == "checkInfection" then return true, infected(body) and "infected" or "clean" end
        if action == "healInjuries" then return heal(actor, body), "healed" end
        if action == "cureInfection" then return cure(actor, body), "cured" end
        return false, "medicalActionInvalid"
    end

    function public.restore(actor, snapshot, request)
        counters.restores = counters.restores + 1
        local ok
        if type(binding.restore) == "function" then
            ok = binding.restore(actor, snapshot, request)
        else
            ok = nativeRestore(snapshot)
        end
        if ok ~= true then counters.failures = counters.failures + 1 end
        return ok == true
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
