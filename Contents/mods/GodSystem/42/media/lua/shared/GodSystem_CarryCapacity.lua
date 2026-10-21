require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}
local Carry = GodSystemCarryCapacity
local LEVEL, EXTERNAL, APPLIED, MODE = "GodSystemCarryCapacityLevel", "GodSystemCarryExternalBase", "GodSystemCarryAppliedBase", "GodSystemCarryMode"
local MARKERS = { LEVEL, EXTERNAL, APPLIED, MODE }
local MAX_INT, MAX_LEVEL = 2147483647, 1073741819
local SAFE_INT = MAX_INT - 256 -- float arithmetic must not reach Java's saturating int conversion.
local FEEBLE_FLOAT = 0.8999999761581421 -- Java float, not Lua's double literal 0.9.
local MODIFIER_ID = "GodSystem.CarryCapacity"
Carry.sessions = Carry.sessions or setmetatable({}, { __mode = "k" })
Carry.activePlayers = Carry.activePlayers or {}
Carry.hooks = Carry.hooks or {}
Carry.sessionSequence = Carry.sessionSequence or 0

local function client() return isClient and isClient() == true end
local function nowMs() return getTimestampMs and getTimestampMs() or 0 end
local function number(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
local function integer(v) v = number(v); return v and v == math.floor(v) and v or nil end
-- Both lookup and invocation must be inside pcall (Java userdata may be invalid).
local function invoke(object, method, argument)
    -- Global ModData initializes before a local player exists. This is not
    -- an interface failure; Kahlua logs nil indexing even inside pcall.
    if object == nil then return false, "noObject" end
    return pcall(function()
        if argument == nil then return object[method](object) end
        return object[method](object, argument)
    end)
end
local function read(object, method)
    local ok, value = invoke(object, method)
    if ok then return number(value) end
end
local function modData(player)
    local ok, value = invoke(player, "getModData")
    if ok and type(value) == "table" then return value end
end
local function copy(value)
    local result = {}; for k, v in pairs(value or {}) do result[k] = v end; return result
end
local function session(player)
    local s = Carry.sessions[player]
    if not s then
        Carry.sessionSequence = Carry.sessionSequence + 1
        s = { level = 0, token = tostring(nowMs()) .. ":" .. Carry.sessionSequence }
        Carry.sessions[player] = s
    end
    return s
end
local function status(s, reason)
    if s.reason ~= reason then s.lastChangeAt = nowMs() end
    s.reason = reason
end
local function bypass(player, fn)
    local s = session(player)
    local old = s.bypass
    s.bypass = true
    local ok, value = pcall(fn)
    s.bypass = old
    return ok and value == true
end
local function setter(player, method, value)
    local ok = invoke(player, method, value)
    return ok
end
local function traits(player)
    local ok, collection = invoke(player, "getCharacterTraits")
    if not ok or not collection or type(CharacterTrait) ~= "table" then return nil end
    local delta
    for _, row in ipairs({ { "STRONG", 1.5 }, { "WEAK", 0.75 }, { "FEEBLE", FEEBLE_FLOAT }, { "STOUT", 1.25 } }) do
        local token = CharacterTrait[row[1]]
        if token == nil then return nil end
        local valid, present = invoke(collection, "get", token)
        if not valid or type(present) ~= "boolean" then return nil end
        if present and not delta then delta = row[2] end
    end
    return delta or 1
end
local function safeValues(base, delta, factor, final)
    return integer(base) and base >= 0 and base <= SAFE_INT and number(delta) and delta > 0
        and number(factor) and factor > 0 and base * factor <= SAFE_INT and base * factor * delta <= SAFE_INT
        and (final == nil or (integer(final) and final >= 0 and final <= SAFE_INT))
end
local function saveMarkers(player, s)
    local data = modData(player)
    if data then
        data[LEVEL], data[MODE], data[APPLIED], data[EXTERNAL] = s.level, "priority", s.base, nil
    end
end
local function removeOwnFramework()
    local f = UnifiedCarryWeightFramework
    if type(f) == "table" and type(f.baseModifiers) == "table" and Carry.frameworkModifier
        and f.baseModifiers[MODIFIER_ID] == Carry.frameworkModifier then
        -- Identity proves ownership. Queued old resolvers return zero in priority mode.
        f.baseModifiers[MODIFIER_ID] = nil
    end
end
local function unhookUnused()
    for _ in pairs(Carry.activePlayers) do return end
    for i = #Carry.hooks, 1, -1 do
        local h = Carry.hooks[i]
        if rawget(h.owner, h.name) == h.wrapper then rawset(h.owner, h.name, h.original) end
        table.remove(Carry.hooks, i)
    end
    if Carry.workerInstalled and Events and Events.OnTick then
        Events.OnTick.Remove(Carry.onGuardTick)
    end
    Carry.workerInstalled = false
end
local function methodOwner(player, name)
    local ok, owner = pcall(function()
        local mt = getmetatable(player)
        local index = mt and mt.__index
        local seen = {}
        while type(index) == "table" and not seen[index] do
            seen[index] = true
            if type(rawget(index, name)) == "function" then return index end
            local inherited = getmetatable(index)
            index = inherited and inherited.__index
        end
    end)
    if ok then return owner end
end
local function installProtection(player, s)
    local installed = 0
    for _, name in ipairs({ "setMaxWeightBase", "setMaxWeightDelta", "setMaxWeight" }) do
        local owner = methodOwner(player, name)
        if owner then
            local original = rawget(owner, name)
            local ours = false
            for i = 1, #Carry.hooks do
                local h = Carry.hooks[i]
                if h.owner == owner and h.name == name then
                    ours = original == h.wrapper
                    -- A later mod owns the entry: do not wrap it repeatedly.
                    original = nil
                    break
                end
            end
            if original then
                local method = name
                local wrapper = function(target, value, ...)
                    local state = Carry.sessions[target]
                    if state and state.level > 0 and not state.bypass then
                        if method == "setMaxWeight" then return end
                        value = method == "setMaxWeightBase" and state.base or state.delta
                    end
                    return original(target, value, ...)
                end
                rawset(owner, name, wrapper)
                Carry.hooks[#Carry.hooks + 1] = { owner = owner, name = name, original = original, wrapper = wrapper }
                ours = true
            end
            if ours then installed = installed + 1 end
        end
    end
    s.protection = installed == 3 and "settersAndFields" or "fields"
    Carry.activePlayers[player] = true
    if not Carry.workerInstalled and Events and Events.OnTick then
        Events.OnTick.Add(Carry.onGuardTick)
        Carry.workerInstalled = true
    end
end
local function apply(player, s, recalculate, final)
    if recalculate and not safeValues(s.base, s.delta, read(player, "getWeightMod")) then return false end
    local ok = bypass(player, function()
        if read(player, "getMaxWeightBase") ~= s.base and not setter(player, "setMaxWeightBase", s.base) then return false end
        if read(player, "getMaxWeightDelta") ~= s.delta and not setter(player, "setMaxWeightDelta", s.delta) then return false end
        if recalculate then
            local got, body = invoke(player, "getBodyDamage")
            if not got or not body or not invoke(body, "UpdateStrength") then return false end
        elseif final ~= nil and not setter(player, "setMaxWeight", final) then return false end
        local actual = read(player, "getMaxWeight")
        if read(player, "getMaxWeightBase") ~= s.base or read(player, "getMaxWeightDelta") ~= s.delta
            or not integer(actual) or actual < 0 or actual > SAFE_INT or (final ~= nil and actual ~= final) then return false end
        s.final = actual
        return true
    end)
    return ok
end
local function failed(s, reason)
    s.force = nil
    s.retryAt = nowMs() + 5000
    s.failures = (s.failures or 0) + 1
    status(s, reason)
    if not s.diagnosticAt or nowMs() - s.diagnosticAt >= 30000 then
        s.diagnosticAt = nowMs()
        print("[GodSystem carry] interface recovery failed; code=" .. reason .. "; failures=" .. s.failures)
        s.failures = 0
    end
end
function Carry.normalizeLevel(value)
    local v = number(tonumber(value))
    if not v then return 0 end
    return math.max(0, math.min(MAX_LEVEL, math.floor(v)))
end
function Carry.getBonus(level) return Carry.normalizeLevel(level) * 2 end
function Carry.getNextCost(level) if Carry.normalizeLevel(level) < MAX_LEVEL then return 2000 end end
function Carry.getPersistedLevel(player) local d = modData(player); return Carry.normalizeLevel(d and d[LEVEL]) end
function Carry.getLevel(data, player)
    local u = data and data.upgrades
    if u and u.carryCapacityLevel ~= nil then return Carry.normalizeLevel(u.carryCapacityLevel) end
    if client() or (isServer and isServer()) then return 0 end
    return Carry.getPersistedLevel(player)
end
function Carry.capture(player)
    local d, markers = modData(player), {}
    local f = UnifiedCarryWeightFramework
    local owned = type(f) == "table" and type(f.baseModifiers) == "table" and Carry.frameworkModifier
        and f.baseModifiers[MODIFIER_ID] == Carry.frameworkModifier and f or nil
    for i = 1, #MARKERS do markers[MARKERS[i]] = d and d[MARKERS[i]] end
    return { base = read(player, "getMaxWeightBase"), delta = read(player, "getMaxWeightDelta"), final = read(player, "getMaxWeight"),
        markers = markers, ownedFramework = owned, state = Carry.sessions[player] and copy(Carry.sessions[player]), active = Carry.activePlayers[player] == true }
end
function Carry.rollback(player, snapshot)
    if not snapshot then return false end
    local ok = bypass(player, function()
        return setter(player, "setMaxWeightBase", snapshot.base) and setter(player, "setMaxWeightDelta", snapshot.delta)
            and setter(player, "setMaxWeight", snapshot.final)
            and read(player, "getMaxWeightBase") == snapshot.base and read(player, "getMaxWeightDelta") == snapshot.delta
            and read(player, "getMaxWeight") == snapshot.final
    end)
    Carry.sessions[player] = snapshot.state and copy(snapshot.state) or nil
    Carry.activePlayers[player] = snapshot.active and true or nil
    local d = modData(player)
    if d then for i = 1, #MARKERS do d[MARKERS[i]] = snapshot.markers[MARKERS[i]] end end
    local f = snapshot.ownedFramework
    if f and type(f.baseModifiers) == "table" and f.baseModifiers[MODIFIER_ID] == nil then
        f.baseModifiers[MODIFIER_ID] = Carry.frameworkModifier
    end
    unhookUnused()
    return ok
end
function Carry.restore(player, level, purchase)
    if client() then return false, "authorityRequired" end
    if not player then return false, "unsupported" end
    level = Carry.normalizeLevel(level)
    local s = Carry.sessions[player]
    if level == 0 then
        if not s or s.level == 0 then return true, Carry.getStatus(player, 0) end
        local delta = traits(player)
        local saved = Carry.capture(player)
        s.level, s.base, s.delta = 0, 8, delta
        if not delta or not apply(player, s, true) then Carry.rollback(player, saved); return false, "verificationFailed" end
        Carry.activePlayers[player] = nil; unhookUnused(); status(s, "inactive")
        local d = modData(player); if d then for i = 1, #MARKERS do d[MARKERS[i]] = nil end end
        return true, Carry.getStatus(player, 0)
    end
    s = session(player)
    if not purchase and not s.force and s.retryAt and nowMs() < s.retryAt then return false, s.reason end
    local valid, dead = invoke(player, "isDead")
    if not valid or dead ~= false then failed(s, "unsupported"); return false, "unsupported" end
    local delta, factor = traits(player), read(player, "getWeightMod")
    local base = 8 + Carry.getBonus(level)
    if not delta then failed(s, "unsupported"); return false, "unsupported" end
    if not safeValues(base, delta, factor) then failed(s, "overflow"); return false, "overflow" end
    local changed = s.level ~= level or s.base ~= base or s.delta ~= delta or s.factor ~= factor or s.force
    local drift = read(player, "getMaxWeightBase") ~= base or read(player, "getMaxWeightDelta") ~= delta
        or read(player, "getMaxWeight") ~= s.final
    local saved = (changed or drift) and Carry.capture(player) or nil
    if saved and (not integer(saved.base) or not number(saved.delta) or not integer(saved.final)) then
        -- Do not tentatively mutate a purchase whose previous fields cannot be restored.
        failed(s, "unsupported"); return false, "unsupported"
    end
    s.level, s.base, s.delta, s.factor, s.mode = level, base, delta, factor, "priority"
    if (changed or drift) and not apply(player, s, true) then
        local restored = Carry.rollback(player, saved)
        s = session(player); failed(s, restored and "verificationFailed" or "rollbackFailed")
        return false, s.reason
    end
    if drift and not changed then s.corrections = (s.corrections or 0) + 1 end
    if changed then s.lastChangeAt = nowMs() end
    s.force, s.retryAt = nil, nil
    status(s, "ok")
    removeOwnFramework()
    installProtection(player, s)
    if changed then saveMarkers(player, s) end
    return true, Carry.getStatus(player, level)
end
function Carry.scheduleRecheck(player) if player then session(player).force = true end end
function Carry.getStatus(player, level)
    local s = player and Carry.sessions[player]
    local reason = s and s.reason or (client() and "waitingServer" or "inactive")
    local current, delta = read(player, "getMaxWeightBase"), read(player, "getMaxWeightDelta")
    if s and s.level > 0 and reason == "ok" and (current ~= s.base or delta ~= s.delta
        or (not client() and read(player, "getMaxWeight") ~= s.final)) then reason = "correcting" end
    return { level = Carry.normalizeLevel(level), bonus = Carry.getBonus(level), currentBase = current,
        externalBase = 8, appliedBase = s and s.base, finalCarry = read(player, "getMaxWeight"), mode = "priority",
        weightMod = read(player, "getWeightMod"), weightDelta = delta, protection = s and s.protection or "inactive",
        retrySeconds = s and s.retryAt and math.max(0, math.ceil((s.retryAt - nowMs()) / 1000)),
        lastChangeSeconds = s and s.lastChangeAt and math.max(0, math.floor((nowMs() - s.lastChangeAt) / 1000)),
        reason = reason, restored = reason == "ok" or reason == "inactive", requiresRestore = reason ~= "ok" and reason ~= "inactive" }
end
function Carry.forget(player)
    if player then Carry.sessions[player], Carry.activePlayers[player] = nil, nil end
    unhookUnused()
end
function Carry.resetClient()
    Carry.sessions = setmetatable({}, { __mode = "k" }); Carry.activePlayers = {}; Carry.lastGuardAt = nil
    unhookUnused()
end
function Carry.onGuardTick()
    local now = nowMs()
    if now - (Carry.lastGuardAt or -1000) < 100 then return end
    Carry.lastGuardAt = now
    for player in pairs(Carry.activePlayers) do
        local s = Carry.sessions[player]
        if not s then
            Carry.forget(player)
        elseif not s.retryAt or now >= s.retryAt then
            local ok, dead = invoke(player, "isDead")
            if not ok or type(dead) ~= "boolean" then
                failed(s, "unsupported")
            elseif dead then
                Carry.forget(player)
            else
                local drift = read(player, "getMaxWeightBase") ~= s.base or read(player, "getMaxWeightDelta") ~= s.delta
                    or (not client() and read(player, "getMaxWeight") ~= s.final)
                if drift or s.retryAt then
                    if apply(player, s, not client()) then
                        s.retryAt = nil; status(s, "ok"); s.lastChangeAt = now
                        s.corrections = (s.corrections or 0) + 1
                    else failed(s, "verificationFailed") end
                end
            end
        end
    end
    unhookUnused()
end
function Carry.makeSnapshot(player, level)
    local s = session(player)
    local state = Carry.getStatus(player, level)
    local snapshot = { policyVersion = 2, mode = "priority", level = Carry.normalizeLevel(level), token = s.token,
        playerId = read(player, "getOnlineID"), reason = state.reason, base = level > 0 and (8 + Carry.getBonus(level)) or state.currentBase,
        delta = level > 0 and s.delta or state.weightDelta, final = state.finalCarry, currentBase = state.currentBase,
        externalBase = 8, appliedBase = s.base, bonus = state.bonus, weightMod = state.weightMod, weightDelta = state.weightDelta,
        protection = state.protection, retrySeconds = state.retrySeconds, lastChangeSeconds = state.lastChangeSeconds }
    local signature = table.concat({ tostring(snapshot.level), snapshot.reason, tostring(snapshot.base), tostring(snapshot.delta), tostring(snapshot.final), snapshot.protection }, ":")
    if s.signature ~= signature then s.signature, s.revision = signature, (s.revision or 0) + 1 end
    s.pushSequence = (s.pushSequence or 0) + 1
    snapshot.revision, snapshot.pushSequence = s.revision, s.pushSequence
    return snapshot
end
function Carry.acceptSnapshot(player, snapshot, initializeSession)
    if not client() or not player or type(snapshot) ~= "table" then return false end
    if snapshot.playerId ~= read(player, "getOnlineID") then return false end
    local existing = Carry.sessions[player]
    if existing and existing.serverToken and existing.serverToken ~= snapshot.token then return false end
    if snapshot.policyVersion ~= 2 then
        if initializeSession then
            Carry.forget(player); status(session(player), "updateRequired")
        end
        return false
    end
    local level, revision, sequence = integer(snapshot.level), integer(snapshot.revision), integer(snapshot.pushSequence)
    if not level or level < 0 or level > MAX_LEVEL or snapshot.mode ~= "priority" or not revision or revision < 1
        or revision > 9007199254740991 or not sequence or sequence < 1 or sequence > 9007199254740991
        or type(snapshot.token) ~= "string" or #snapshot.token == 0 or #snapshot.token > 80
        or snapshot.playerId ~= read(player, "getOnlineID") then return false end
    if not integer(snapshot.base) or not number(snapshot.delta) or not integer(snapshot.final)
        or snapshot.base < 0 or snapshot.base > SAFE_INT or snapshot.delta <= 0 or snapshot.delta > MAX_INT
        or snapshot.final < 0 or snapshot.final > SAFE_INT then return false end
    if level > 0 and (snapshot.base ~= 8 + Carry.getBonus(level)
        or (snapshot.delta ~= 1 and snapshot.delta ~= 1.5 and snapshot.delta ~= 0.75 and snapshot.delta ~= FEEBLE_FLOAT and snapshot.delta ~= 1.25)
        or not safeValues(snapshot.base, snapshot.delta, snapshot.weightMod, snapshot.final)) then return false end
    local s = Carry.sessions[player]
    local wasControlled = s and s.level > 0
    -- A full state establishes a token only after explicit connection/character reset.
    -- Even a late full state cannot switch an already initialized live session.
    if s and s.serverToken and s.serverToken ~= snapshot.token then return false end
    if not s or s.serverToken ~= snapshot.token then
        if not initializeSession then return false end
        Carry.forget(player); s = session(player)
    elseif sequence <= (s.serverSequence or 0) or revision < (s.serverRevision or 0) then return false end
    s.serverToken, s.serverSequence, s.serverRevision = snapshot.token, sequence, revision
    s.level, s.base, s.delta, s.mode, s.snapshot = level, snapshot.base, snapshot.delta, "priority", copy(snapshot)
    if level == 0 then
        local applied = not wasControlled or apply(player, s, false, snapshot.final)
        Carry.activePlayers[player] = nil; unhookUnused()
        status(s, applied and "inactive" or "verificationFailed")
        return applied
    end
    if snapshot.reason ~= "ok" then
        Carry.activePlayers[player] = nil; unhookUnused()
        status(s, snapshot.reason or "waitingServer"); return false
    end
    if not apply(player, s, false, snapshot.final) then failed(s, "verificationFailed"); return false end
    s.retryAt = nil; status(s, "ok"); saveMarkers(player, s); installProtection(player, s)
    return true
end
function Carry.updateClient(player)
    if not client() then return false end
    local s = player and Carry.sessions[player]
    if not s or not s.snapshot or s.level == 0 then return false end
    if s.snapshot.reason ~= "ok" then return false end
    if s.retryAt and nowMs() < s.retryAt then return false end
    -- Correct only base/delta. A cached final must never fight native injury packets.
    if read(player, "getMaxWeightBase") ~= s.base or read(player, "getMaxWeightDelta") ~= s.delta then
        if not apply(player, s, false) then failed(s, "verificationFailed"); return false end
    end
    return true
end
return Carry
