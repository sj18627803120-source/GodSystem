require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}
local Carry = GodSystemCarryCapacity
local LEVEL = "GodSystemCarryCapacityLevel"
local EXTERNAL = "GodSystemCarryExternalBase"
local APPLIED = "GodSystemCarryAppliedBase"
local MODE = "GodSystemCarryMode"
local MAX_INT = 2147483647
local MAX_LEVEL = 1073741823
local MODIFIER_ID = "GodSystem.CarryCapacity"
local RECHECK_MS = 3000
local RESET_WINDOW_MS = 30000
local RETRY_MAX_MS = 300000
local STABLE_MS = 60000
local MARKERS = { LEVEL, EXTERNAL, APPLIED, MODE }
Carry.sessions = Carry.sessions or setmetatable({}, { __mode = "k" })
Carry.sessionSequence = Carry.sessionSequence or 0
Carry.pendingPlayers = Carry.pendingPlayers or {}

function Carry.onSettleTick()
    local active = false
    for player, state in pairs(Carry.pendingPlayers) do
        if Carry.sessions[player] ~= state then
            Carry.pendingPlayers[player] = nil
        else
            state.pendingTicks = (state.pendingTicks or 1) - 1
            if state.pendingTicks <= 0 then
                state.pendingTicks = nil
                Carry.pendingPlayers[player] = nil
            else
                active = true
            end
        end
    end
    if not active and Events and Events.OnTick then Events.OnTick.Remove(Carry.onSettleTick) end
end

local function scheduleSettle(player, state)
    Carry.pendingPlayers[player] = state
    if Events and Events.OnTick then
        Events.OnTick.Remove(Carry.onSettleTick)
        Events.OnTick.Add(Carry.onSettleTick)
    end
end

local function number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function integer(value)
    value = number(value)
    return value and math.floor(value) or nil
end

local function client()
    return isClient and isClient() == true
end

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

local function read(player, method)
    if not player or not player[method] then return nil end
    local ok, value = pcall(function() return player[method](player) end)
    return ok and number(value) or nil
end

local function modData(player)
    if not player or not player.getModData then return nil end
    local ok, data = pcall(function() return player:getModData() end)
    return ok and type(data) == "table" and data or nil
end

local function copy(value)
    local result = {}
    for k, v in pairs(value or {}) do result[k] = v end
    return result
end

local function refreshFinal(player)
    -- B42.20.4: the base setter does not update cached maxWeight. Use the
    -- native formula (strength, moodles, traits/delta), never a copied formula.
    if not player or not player.getBodyDamage then return false end
    local ok = pcall(function() player:getBodyDamage():UpdateStrength() end)
    return ok and read(player, "getMaxWeight") ~= nil
end

local function writeBase(player, value)
    if not value or value < 0 or value > MAX_INT or value ~= math.floor(value)
        or not player or not player.setMaxWeightBase then return false end
    local ok = pcall(function() player:setMaxWeightBase(value) end)
    return ok and read(player, "getMaxWeightBase") == value
end

function Carry.normalizeLevel(value)
    return math.max(0, math.min(MAX_LEVEL, integer(value) or 0))
end

function Carry.getBonus(level)
    return Carry.normalizeLevel(level) * 2
end

function Carry.getNextCost(level)
    if Carry.normalizeLevel(level) >= MAX_LEVEL then return nil end
    return 2000
end

function Carry.getPersistedLevel(player)
    local data = modData(player)
    return Carry.normalizeLevel(data and data[LEVEL])
end

function Carry.getLevel(data, player)
    local upgrades = data and data.upgrades
    -- The account wins, including zero. A player marker is only an SP
    -- migration fallback; never use client/player markers as MP authority.
    if upgrades and upgrades.carryCapacityLevel ~= nil then
        return Carry.normalizeLevel(upgrades.carryCapacityLevel)
    end
    if client() or (isServer and isServer()) then return 0 end
    return Carry.getPersistedLevel(player)
end

local function framework()
    local value = UnifiedCarryWeightFramework
    if type(value) ~= "table" then return nil end
    if type(value.registerBaseModifier) ~= "function" or type(value.recomputeAll) ~= "function"
        or type(value.baseModifiers) ~= "table" then return nil, "frameworkUnsupported" end
    return value
end

local function session(player)
    local state = Carry.sessions[player]
    if not state then
        Carry.sessionSequence = Carry.sessionSequence + 1
        state = { level = 0, token = tostring(nowMs()) .. ":" .. tostring(Carry.sessionSequence),
            recheckAt = nowMs() + RECHECK_MS }
        Carry.sessions[player] = state
    end
    return state
end

function Carry.scheduleRecheck(player)
    if player then session(player).recheckAt = nowMs() + RECHECK_MS end
end

local function clearResetHistory(state)
    state.resetWindow, state.resetCount, state.retryAt, state.retryDelay = nil, nil, nil, nil
end

local function markStatusChange(state, reason)
    if state.reason ~= reason then state.lastChangeAt = nowMs() end
    state.reason = reason
end

local function allowKnownReset(state, now)
    if state.retryAt then
        if now < state.retryAt then return false end
        -- One probe per cooldown; the next observed reset waits longer.
        state.retryAt = nil
        state.retryDelay = math.min((state.retryDelay or RESET_WINDOW_MS) * 2, RETRY_MAX_MS)
        return true
    end
    if not state.retryDelay then
        if not state.resetWindow or now - state.resetWindow > RESET_WINDOW_MS then
            state.resetWindow, state.resetCount = now, 0
        end
        state.resetCount = (state.resetCount or 0) + 1
        if state.resetCount <= 2 then return true end
        state.retryDelay = RESET_WINDOW_MS
    end
    state.retryAt = now + state.retryDelay
    return false
end

local function saveMarkers(player, state)
    local data = modData(player)
    if not data then return end
    data[LEVEL], data[MODE] = state.level, state.mode
    data[EXTERNAL], data[APPLIED] = state.externalBase, state.appliedBase
end

local function initializeNative(player, state, current)
    if state.externalBase ~= nil then return true end
    local data = modData(player) or {}
    local external, applied = integer(data[EXTERNAL]), integer(data[APPLIED])
    if current == 8 then
        -- B42.20.4 initializes this non-serialized field to 8 on each new
        -- character. Do not restore another mod's saved baseline.
        state.externalBase = 8
    elseif data[MODE] ~= "ucwf" and external and external >= 0 and applied == current then
        state.externalBase, state.appliedBase = external, applied
    elseif applied == nil and data[MODE] ~= "ucwf" then
        state.externalBase = current
    else
        return false
    end
    return true
end

local function nativeApply(player, state, level, recheck)
    local current = read(player, "getMaxWeightBase")
    if not current or current < 0 or current > MAX_INT or not modData(player) then return false, "unsupported" end
    if not initializeNative(player, state, current) then return false, "externalConflict" end
    if state.mode == "native" and state.level == 0 then
        state.externalBase, state.appliedBase = current, current
        clearResetHistory(state)
    end
    local now = nowMs()
    if state.appliedBase and current ~= state.appliedBase then state.stableSince = nil end
    if state.appliedBase and current ~= state.appliedBase and current ~= state.externalBase then
        -- An external scalar write cannot tell us whether our old contribution
        -- survived. Keep the value intact instead of adding the bonus again.
        return false, "externalConflict"
    end
    if state.appliedBase and current == state.externalBase and current ~= state.appliedBase then
        if not allowKnownReset(state, now) then return false, "resetCooldown" end
    end
    local target = state.externalBase + Carry.getBonus(level)
    local weightMod, delta = read(player, "getWeightMod"), read(player, "getMaxWeightDelta")
    if target > MAX_INT or not weightMod or not delta or weightMod <= 0 or delta <= 0
        or target * weightMod * delta > MAX_INT then return false, "overflow" end
    if current ~= target and not writeBase(player, target) then return false, "writeFailed" end
    if current ~= target or state.level ~= level or state.mode ~= "native" or recheck then
        if not refreshFinal(player) then return false, "verificationFailed" end
    end
    if state.mode ~= "native" or state.level ~= level or state.appliedBase ~= target then state.lastChangeAt = now end
    state.mode, state.level, state.appliedBase = "native", level, target
    markStatusChange(state, "ok")
    state.pendingTicks = nil
    state.stableSince = state.stableSince or now
    if now - state.stableSince >= STABLE_MS then clearResetHistory(state) end
    saveMarkers(player, state)
    return true
end

local function registerFramework(value)
    if not Carry.frameworkModifier then
        Carry.frameworkModifier = {
            id = MODIFIER_ID,
            resolve = function(context)
                local state = context and Carry.sessions[context.player]
                return { add = state and state.mode == "ucwf" and Carry.getBonus(state.level) or 0 }
            end,
        }
    end
    if value.baseModifiers[MODIFIER_ID] ~= Carry.frameworkModifier then
        value.registerBaseModifier(Carry.frameworkModifier)
    end
end

local function frameworkApply(player, state, level, value, purchase, recheck)
    if purchase and SandboxVars and SandboxVars.UnifiedCarryWeightFramework
        and SandboxVars.UnifiedCarryWeightFramework.CapWeight == true
        and (read(player, "getMaxWeight") or 0) >= 50 then return false, "capacityLimit" end
    registerFramework(value)
    local changed = state.mode ~= "ucwf" or state.level ~= level or state.framework ~= value or recheck
    state.mode, state.level, state.framework = "ucwf", level, value
    state.externalBase, state.appliedBase = nil, nil
    if changed then
        value.recomputeAll(player)
        local base = read(player, "getMaxWeightBase")
        local factor = read(player, "getWeightMod")
        if not base or base < 0 or base > MAX_INT or not factor or base * factor > MAX_INT then
            return false, "overflow"
        end
        if not refreshFinal(player) then return false, "verificationFailed" end
        -- UCWF completes max modifiers on its own deferred worker. Do not
        -- project the intermediate delta=1 to the MP client.
        state.pendingTicks = 3
        scheduleSettle(player, state)
    end
    if changed then state.lastChangeAt = nowMs() end
    markStatusChange(state, "ok")
    saveMarkers(player, state)
    return true
end

function Carry.capture(player)
    local data, markers = modData(player), {}
    for i = 1, #MARKERS do markers[MARKERS[i]] = data and data[MARKERS[i]] end
    return { base = read(player, "getMaxWeightBase"), delta = read(player, "getMaxWeightDelta"),
        final = read(player, "getMaxWeight"), markers = markers,
        state = Carry.sessions[player] and copy(Carry.sessions[player]) or nil }
end

function Carry.rollback(player, snapshot)
    if not snapshot then return false end
    Carry.sessions[player] = snapshot.state and copy(snapshot.state) or nil
    Carry.pendingPlayers[player] = nil
    local restoredState = Carry.sessions[player]
    if restoredState and restoredState.pendingTicks then scheduleSettle(player, restoredState) end
    local data = modData(player)
    if data then for i = 1, #MARKERS do data[MARKERS[i]] = snapshot.markers[MARKERS[i]] end end
    local ok = writeBase(player, snapshot.base)
    local restored = pcall(function()
        if snapshot.delta ~= nil then player:setMaxWeightDelta(snapshot.delta) end
        if snapshot.final ~= nil then player:setMaxWeight(snapshot.final) end
    end)
    -- Any queued UCWF worker observes the restored resolver state.
    return ok and restored
end

function Carry.restore(player, level, purchase)
    if client() then return false, "authorityRequired" end
    if not player then return false, "unsupported" end
    level = Carry.normalizeLevel(level)
    local snapshot = Carry.capture(player)
    local state = session(player)
    local value, unsupported = framework()
    local recheck = state.recheckAt and nowMs() >= state.recheckAt
    local ok, applied, reason = pcall(function()
        if unsupported then return false, unsupported end
        if value then return frameworkApply(player, state, level, value, purchase, recheck) end
        if state.mode == "ucwf" then return false, "frameworkUnsupported" end
        return nativeApply(player, state, level, recheck)
    end)
    if not ok or not applied then
        -- Conflicts have not made a native mutation. Leave external writes.
        if not ok or (reason ~= "externalConflict" and reason ~= "frameworkUnsupported" and reason ~= "resetCooldown") then
            Carry.rollback(player, snapshot)
        end
        state = session(player)
        markStatusChange(state, ok and reason or "applyFailed")
        return false, state.reason
    end
    if recheck then state.recheckAt = nil end
    return true, Carry.getStatus(player, level)
end

function Carry.getStatus(player, level)
    local state = player and Carry.sessions[player] or nil
    local remote = client() and state and state.remoteStatus or nil
    local current = read(player, "getMaxWeightBase")
    local reason = state and state.reason or (client() and "waitingServer" or "pending")
    if state and state.mode == "native" and state.appliedBase ~= current then
        reason = current == state.externalBase and state.retryAt and "resetCooldown" or "externalConflict"
    end
    if state and state.mode == "ucwf" and state.projectedRevision
        and (current ~= state.projectedBase or read(player, "getMaxWeightDelta") ~= state.projectedDelta) then
        reason = "externalConflict"
    end
    if state and state.pendingTicks then reason = "pending" end
    local retrySeconds = state and state.retryAt and math.max(0, math.ceil((state.retryAt - nowMs()) / 1000)) or nil
    local lastChangeSeconds = state and state.lastChangeAt and math.max(0, math.floor((nowMs() - state.lastChangeAt) / 1000)) or nil
    if remote then
        local elapsed = math.max(0, math.floor((nowMs() - (state.remoteStatusAt or nowMs())) / 1000))
        retrySeconds = remote.retrySeconds and math.max(0, remote.retrySeconds - elapsed) or retrySeconds
        lastChangeSeconds = remote.lastChangeSeconds and remote.lastChangeSeconds + elapsed or lastChangeSeconds
    end
    return { level = Carry.normalizeLevel(level), bonus = Carry.getBonus(level), currentBase = current,
        externalBase = remote and remote.externalBase or state and state.externalBase,
        appliedBase = remote and remote.appliedBase or state and state.appliedBase,
        finalCarry = read(player, "getMaxWeight"), mode = state and state.mode or "native",
        weightMod = read(player, "getWeightMod"), weightDelta = read(player, "getMaxWeightDelta"),
        retrySeconds = retrySeconds, lastChangeSeconds = lastChangeSeconds,
        source = remote and remote.source or (state and state.mode == "ucwf" and "UnifiedCarryWeightFramework" or nil),
        reason = reason, restored = reason == "ok", requiresRestore = reason ~= "ok" }
end

function Carry.forget(player)
    if player then Carry.sessions[player] = nil; Carry.pendingPlayers[player] = nil end
end

function Carry.resetClient()
    if client() then Carry.sessions = setmetatable({}, { __mode = "k" }); Carry.pendingPlayers = {} end
end

function Carry.makeSnapshot(player, level)
    local state = session(player)
    local status = Carry.getStatus(player, level)
    local snapshot = { level = Carry.normalizeLevel(level), mode = state.mode or "native",
        reason = status.reason, token = state.token, playerId = read(player, "getOnlineID"),
        currentBase = status.currentBase, externalBase = status.externalBase, appliedBase = status.appliedBase,
        bonus = status.bonus, weightMod = status.weightMod, weightDelta = status.weightDelta,
        retrySeconds = status.retrySeconds, lastChangeSeconds = status.lastChangeSeconds, source = status.source }
    if snapshot.mode == "ucwf" and status.reason == "ok" then
        snapshot.base, snapshot.delta = status.currentBase, read(player, "getMaxWeightDelta")
    end
    local signature = table.concat({ tostring(snapshot.level), snapshot.mode, snapshot.reason,
        tostring(snapshot.base), tostring(snapshot.delta), tostring(snapshot.currentBase), tostring(snapshot.externalBase),
        tostring(snapshot.appliedBase) }, ":")
    if state.signature ~= signature then
        state.signature, state.revision = signature, (state.revision or 0) + 1
    end
    snapshot.revision = state.revision
    return snapshot
end

function Carry.acceptSnapshot(player, snapshot)
    if not client() or not player or type(snapshot) ~= "table" then return false end
    local level, revision = integer(snapshot.level), integer(snapshot.revision)
    if not level or level ~= snapshot.level or level < 0 or level > MAX_LEVEL
        or not revision or revision ~= snapshot.revision or revision < 1
        or type(snapshot.token) ~= "string" or #snapshot.token == 0 or #snapshot.token > 80
        or snapshot.playerId ~= read(player, "getOnlineID")
        or (snapshot.mode ~= "native" and snapshot.mode ~= "ucwf") then return false end
    local state = session(player)
    if state.serverToken and (state.serverToken ~= snapshot.token or revision <= (state.serverRevision or 0)) then return false end
    if snapshot.mode == "ucwf" and snapshot.reason == "ok" then
        local base, delta = integer(snapshot.base), number(snapshot.delta)
        if not base or base ~= snapshot.base or base < 0 or base > MAX_INT
            or not delta or delta ~= snapshot.delta or delta <= 0
            or base * math.max(1, read(player, "getWeightMod") or 1) * delta > MAX_INT then return false end
    end
    state.serverToken, state.serverRevision, state.snapshot = snapshot.token, revision, copy(snapshot)
    state.remoteStatus, state.remoteStatusAt = copy(snapshot), nowMs()
    return Carry.updateClient(player)
end

function Carry.updateClient(player)
    if not client() then return false end
    local state = player and Carry.sessions[player]
    local snapshot = state and state.snapshot
    if not snapshot then return false end
    if snapshot.reason ~= "ok" then state.reason = snapshot.reason; return false end
    if snapshot.mode == "native" then
        if state.mode == "ucwf" then state.reason = "frameworkUnsupported"; return false end
        local saved = Carry.capture(player)
        local recheck = state.recheckAt and nowMs() >= state.recheckAt
        local ok, reason = nativeApply(player, state, snapshot.level, recheck)
        if not ok then
            if reason ~= "externalConflict" and reason ~= "resetCooldown" then Carry.rollback(player, saved) end
            session(player).reason = reason
        elseif recheck then
            state.recheckAt = nil
        end
        return ok
    end
    -- Apply the approved UCWF aggregate once; do not add our bonus again.
    if state.projectedRevision == snapshot.revision then
        state.reason = Carry.getStatus(player, snapshot.level).reason
        return state.reason == "ok"
    end
    if state.projectedRevision and (read(player, "getMaxWeightBase") ~= state.projectedBase
        or read(player, "getMaxWeightDelta") ~= state.projectedDelta) then
        state.reason = "externalConflict"
        return false
    end
    local saved = Carry.capture(player)
    local ok, applied = pcall(function()
        if not writeBase(player, snapshot.base) then return false end
        player:setMaxWeightDelta(snapshot.delta)
        return refreshFinal(player)
    end)
    if not ok or not applied then
        Carry.rollback(player, saved)
        session(player).reason = "applyFailed"
        return false
    end
    state.mode, state.level, state.reason = "ucwf", snapshot.level, "ok"
    state.externalBase, state.appliedBase = nil, nil
    state.projectedRevision = snapshot.revision
    state.projectedBase, state.projectedDelta = read(player, "getMaxWeightBase"), read(player, "getMaxWeightDelta")
    saveMarkers(player, state)
    return true
end

return Carry
