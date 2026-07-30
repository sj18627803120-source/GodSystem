require "GodSystem/Core/Result"

GodSystemHomeFeatureModule = GodSystemHomeFeatureModule or {}

local Descriptor = GodSystemHomeFeatureModule

Descriptor.id = "feature.home"
Descriptor.dependencies = {
    "home.config",
    "home.state",
    "home.position",
    "home.world",
    "home.wallet",
    "clock",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

local function callPort(callback, ...)
    local args = { ... }
    local function invoke() return callback(unpack(args)) end
    if xpcall then return xpcall(invoke, traceback) end
    return pcall(invoke)
end

local function requiredPort(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. id)
    for i = 1, #methods do
        assert(type(port[methods[i]]) == "function", "dependency " .. id .. " is missing method " .. methods[i])
    end
    return port
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeInteger(value, fallback)
    if not finite(value) then return fallback end
    value = math.floor(tonumber(value))
    if math.abs(value) > 9007199254740991 then return fallback end
    return value
end

local function safePosition(value)
    if type(value) ~= "table" or not finite(value.x) or not finite(value.y) or not finite(value.z or 0) then return nil end
    return {
        x = tonumber(value.x),
        y = tonumber(value.y),
        z = tonumber(value.z or 0),
        source = value.source,
    }
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    return value ~= "" and value or nil
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local config = requiredPort(dependencies, "home.config",
        { "isEnabled", "cost", "maxTempSlots", "safeLevel", "nextSafeLevel" })
    local state = requiredPort(dependencies, "home.state", { "load", "save" })
    local position = requiredPort(dependencies, "home.position",
        { "blockedReason", "current", "validate", "teleport", "restore" })
    local world = requiredPort(dependencies, "home.world", { "planClear", "executeClear" })
    local wallet = requiredPort(dependencies, "home.wallet", { "charge", "refund" })
    local clock = requiredPort(dependencies, "clock", { "nowHours" })
    local operations = requiredPort(dependencies, "operations", { "begin", "finish" })
    local notifications = requiredPort(dependencies, "notifications", { "publish" })
    local instance = { started = false, completed = 0, failed = 0, lastIssue = nil }

    local function makeResult(ok, code, data, request)
        local result
        if ok then
            instance.completed = instance.completed + 1
            result = GodSystemResult.ok(moduleId, code, data, operationId(request))
        else
            instance.failed = instance.failed + 1
            result = GodSystemResult.fail(moduleId, code, data, operationId(request))
        end
        local called, value = callPort(notifications.publish, result, request)
        if not called or value == false then instance.lastIssue = { stage = "notify", code = "notificationFailed" } end
        return result
    end

    local function begin(action, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local fingerprint = action .. "|" .. tostring(request and request.index or "")
        local called, status, value = callPort(operations.begin, moduleId, id, fingerprint, request)
        if not called then return nil, makeResult(false, "portError", { stage = "operationBegin" }, request) end
        if status == "replay" then return nil, value end
        if status ~= "new" then return nil, makeResult(false, value or "operationPending", nil, request) end
        return id
    end

    local function finish(id, result, request)
        local called, stored = callPort(operations.finish, moduleId, id, result, request)
        if not called or stored == false then
            instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
            return makeResult(false, "operationOutcomeUnknown", { original = result }, request)
        end
        return result
    end

    local function load(actor, request)
        local called, data, code = callPort(state.load, actor, request)
        if not called then return nil, makeResult(false, "portError", { stage = "stateLoad" }, request) end
        if type(data) ~= "table" then return nil, makeResult(false, code or "stateUnavailable", nil, request) end
        data.homeSystem = type(data.homeSystem) == "table" and data.homeSystem or {}
        data.homeSystem.tempSlots = type(data.homeSystem.tempSlots) == "table" and data.homeSystem.tempSlots or {}
        data.homeSystem.safeZone = type(data.homeSystem.safeZone) == "table" and data.homeSystem.safeZone or {}
        data.stats = type(data.stats) == "table" and data.stats or {}
        return data
    end

    local function save(actor, data, request)
        local called, saved, code = callPort(state.save, actor, data, request)
        if not called then return false, "portError" end
        return saved == true, code or "stateSaveFailed"
    end

    local function enabled(actor, request)
        local called, value = callPort(config.isEnabled, actor, request)
        return called and value == true
    end

    local function quote(action, actor, data, request)
        local called, value = callPort(config.cost, action, actor, data, request)
        local cost = called and safeInteger(value, nil) or nil
        if cost == nil or cost < 0 then return nil end
        return cost
    end

    local function charge(actor, cost, request)
        if cost <= 0 then return true, nil end
        local called, paid, receiptOrCode = callPort(wallet.charge, actor, cost, request)
        if not called then return false, "portError" end
        if paid ~= true or receiptOrCode == nil then return false, receiptOrCode or "insufficientFunds" end
        return true, receiptOrCode
    end

    local function refund(actor, receipt, request)
        if receipt == nil then return true end
        local called, value = callPort(wallet.refund, actor, receipt, request)
        return called and value ~= false
    end

    local function nowHours(request)
        local called, value = callPort(clock.nowHours, request)
        return called and finite(value) and tonumber(value) or nil
    end

    local function validateCurrent(actor, request)
        local blockedCalled, reason = callPort(position.blockedReason, actor, request)
        if not blockedCalled then return nil, "portError" end
        if reason ~= nil and tostring(reason) ~= "" then return nil, tostring(reason) end
        local currentCalled, current = callPort(position.current, actor, request)
        current = currentCalled and safePosition(current) or nil
        if not current then return nil, "positionInvalid" end
        local validateCalled, safe, code = callPort(position.validate, actor, current, request)
        safe = validateCalled and safePosition(safe) or nil
        if not safe then return nil, validateCalled and (code or "positionUnsafe") or "portError" end
        return safe
    end

    local function mutatePoint(action, request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        if not enabled(request.actor, request) then return makeResult(false, "teleportDisabled", nil, request) end
        local id, replay = begin(action, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local home = data.homeSystem
        local index = math.max(1, safeInteger(request.index, 1))
        local cost
        if action == "buyTemp" then
            local maxCalled, maximum = callPort(config.maxTempSlots, request.actor, data, request)
            maximum = maxCalled and safeInteger(maximum, 0) or 0
            if index > maximum then return finish(id, makeResult(false, "tempSlotInvalid", nil, request), request) end
            home.tempSlots[index] = home.tempSlots[index] or { owned = false, point = nil }
            if home.tempSlots[index].owned == true then
                return finish(id, makeResult(false, "tempSlotOwned", nil, request), request)
            end
        elseif action == "setTemp" then
            local slot = home.tempSlots[index]
            if type(slot) ~= "table" or slot.owned ~= true then
                return finish(id, makeResult(false, "tempSlotLocked", nil, request), request)
            end
        end
        local point
        if action == "setHome" or action == "setTemp" then
            local positionCode
            point, positionCode = validateCurrent(request.actor, request)
            if not point then return finish(id, makeResult(false, positionCode, nil, request), request) end
        end
        cost = quote(action, request.actor, data, request)
        if cost == nil then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local before = copy(data)
        local paid, receiptOrCode = charge(request.actor, cost, request)
        if not paid then return finish(id, makeResult(false, receiptOrCode, nil, request), request) end
        local paymentReceipt = receiptOrCode
        if action == "setHome" then
            home.home = copy(point)
        elseif action == "buyTemp" then
            home.tempSlots[index].owned = true
        elseif action == "setTemp" then
            home.tempSlots[index].point = copy(point)
        end
        data.stats.spentPoints = (safeInteger(data.stats.spentPoints, 0) or 0) + cost
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local walletRestored = refund(request.actor, paymentReceipt, request)
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false,
                walletRestored and stateRestored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, action .. "Completed", {
            index = action ~= "setHome" and index or nil,
            point = point,
            cost = cost,
        }, request), request)
    end

    local function teleport(action, request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        if not enabled(request.actor, request) then return makeResult(false, "teleportDisabled", nil, request) end
        local id, replay = begin(action, request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local home, target, source = data.homeSystem, nil, nil
        local index = math.max(1, safeInteger(request.index, 1))
        if action == "teleportHome" then
            target = home.home
            source = "home"
        elseif action == "teleportTemp" then
            local slot = home.tempSlots[index]
            if type(slot) ~= "table" or slot.owned ~= true then
                return finish(id, makeResult(false, "tempSlotLocked", nil, request), request)
            end
            target = slot.point
            source = "temp:" .. tostring(index)
        elseif action == "return" then
            target = home.returnPoint
            source = target and target.source or "return"
        end
        target = safePosition(target)
        if not target then return finish(id, makeResult(false, "targetMissing", nil, request), request) end
        local blockedCalled, blocked = callPort(position.blockedReason, request.actor, request)
        if not blockedCalled then return finish(id, makeResult(false, "portError", { stage = "blockedReason" }, request), request) end
        if blocked ~= nil and tostring(blocked) ~= "" then
            return finish(id, makeResult(false, tostring(blocked), nil, request), request)
        end
        local validateCalled, safe, validateCode = callPort(position.validate, request.actor, target, request)
        safe = validateCalled and safePosition(safe) or nil
        if not safe then return finish(id, makeResult(false,
            validateCalled and (validateCode or "targetInvalid") or "portError", nil, request), request) end
        local currentCalled, current = callPort(position.current, request.actor, request)
        current = currentCalled and safePosition(current) or nil
        if not current then return finish(id, makeResult(false, "positionInvalid", nil, request), request) end
        local cost = quote(action, request.actor, data, request)
        if cost == nil then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local before = copy(data)
        local paid, receiptOrCode = charge(request.actor, cost, request)
        if not paid then return finish(id, makeResult(false, receiptOrCode, nil, request), request) end
        local paymentReceipt = receiptOrCode
        local teleportCalled, moved, moveReceiptOrCode = callPort(position.teleport, request.actor, safe, request)
        if not teleportCalled or moved ~= true or moveReceiptOrCode == nil then
            local walletRestored = refund(request.actor, paymentReceipt, request)
            return finish(id, makeResult(false,
                walletRestored and (teleportCalled and (moveReceiptOrCode or "teleportFailed") or "portError")
                    or "rollbackIncomplete", nil, request), request)
        end
        local moveReceipt = moveReceiptOrCode
        if action == "return" then
            home.returnPoint = nil
        else
            home.returnPoint = copy(current)
            home.returnPoint.source = source
        end
        data.stats.spentPoints = (safeInteger(data.stats.spentPoints, 0) or 0) + cost
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restoreCalled, restored = callPort(position.restore, request.actor, moveReceipt, request)
            local walletRestored = refund(request.actor, paymentReceipt, request)
            local stateRestored = save(request.actor, before, request)
            local rollbackOk = restoreCalled and restored ~= false and walletRestored and stateRestored
            return finish(id, makeResult(false, rollbackOk and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "teleported", {
            action = action,
            target = safe,
            cost = cost,
        }, request), request)
    end

    local function clearReturn(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("clearReturn", request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        if not data.homeSystem.returnPoint then
            return finish(id, makeResult(false, "returnPointMissing", nil, request), request)
        end
        local before = copy(data)
        data.homeSystem.returnPoint = nil
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restored = save(request.actor, before, request)
            return finish(id, makeResult(false, restored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "returnPointCleared", nil, request), request)
    end

    local function upgradeSafeZone(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("upgradeSafeZone", request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local home, safe = data.homeSystem, data.homeSystem.safeZone
        if not safePosition(home.home) then return finish(id, makeResult(false, "homeRequired", nil, request), request) end
        local level = math.max(0, safeInteger(safe.level, 0))
        local nextCalled, nextLevel, nextCode = callPort(config.nextSafeLevel, level, request.actor, data, request)
        if not nextCalled or type(nextLevel) ~= "table" then
            return finish(id, makeResult(false,
                nextCalled and (nextCode or "safeZoneMaxed") or "portError", nil, request), request)
        end
        local nextValue = safeInteger(nextLevel.level, nil)
        local cost = safeInteger(level <= 0 and (nextLevel.unlockCost or nextLevel.upgradeCost)
            or nextLevel.upgradeCost, nil)
        if nextValue == nil or nextValue <= level or cost == nil or cost < 0 then
            return finish(id, makeResult(false, "quoteInvalid", nil, request), request)
        end
        local before = copy(data)
        local paid, receiptOrCode = charge(request.actor, cost, request)
        if not paid then return finish(id, makeResult(false, receiptOrCode, nil, request), request) end
        safe.level = nextValue
        safe.enabled = true
        safe.lastScanHours = nowHours(request) or safe.lastScanHours
        data.stats.spentPoints = (safeInteger(data.stats.spentPoints, 0) or 0) + cost
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local walletRestored = refund(request.actor, receiptOrCode, request)
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false,
                walletRestored and stateRestored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, "safeZoneUpgraded", {
            level = nextValue,
            radius = nextLevel.radius,
            cost = cost,
        }, request), request)
    end

    local function toggleSafeZone(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("toggleSafeZone", request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local safe = data.homeSystem.safeZone
        local levelCalled, levelInfo = callPort(config.safeLevel, safeInteger(safe.level, 0), request)
        if not levelCalled or type(levelInfo) ~= "table" then
            return finish(id, makeResult(false, "safeZoneLocked", nil, request), request)
        end
        local before = copy(data)
        safe.enabled = safe.enabled ~= true
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local restored = save(request.actor, before, request)
            return finish(id, makeResult(false, restored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        return finish(id, makeResult(true, safe.enabled and "safeZoneEnabled" or "safeZoneDisabled", {
            enabled = safe.enabled,
        }, request), request)
    end

    local function clearSafeZone(request)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin("clearSafeZone", request)
        if replay then return replay end
        local data, failure = load(request.actor, request)
        if not data then return finish(id, failure, request) end
        local home, safe = data.homeSystem, data.homeSystem.safeZone
        local center = safePosition(home.home)
        if not center then return finish(id, makeResult(false, "homeRequired", nil, request), request) end
        local levelCalled, levelInfo = callPort(config.safeLevel, safeInteger(safe.level, 0), request)
        if not levelCalled or type(levelInfo) ~= "table" then
            return finish(id, makeResult(false, "safeZoneLocked", nil, request), request)
        end
        if request.manual ~= true and safe.enabled ~= true then
            return finish(id, makeResult(true, "safeZonePaused", { removed = 0 }, request), request)
        end
        local planCalled, plan, planCode = callPort(
            world.planClear, request.actor, center, tonumber(levelInfo.radius) or 0, request)
        if not planCalled or type(plan) ~= "table" then
            return finish(id, makeResult(false,
                planCalled and (planCode or "clearPlanFailed") or "portError", nil, request), request)
        end
        local count = math.max(0, safeInteger(plan.count, 0))
        local before = copy(data)
        local now = nowHours(request)
        safe.lastScanHours = now or safe.lastScanHours
        if count <= 0 then
            safe.lastCleared = 0
            local saved, saveCode = save(request.actor, data, request)
            if not saved then
                local restored = save(request.actor, before, request)
                return finish(id, makeResult(false, restored and saveCode or "rollbackIncomplete", nil, request), request)
            end
            return finish(id, makeResult(true, "safeZoneEmpty", { removed = 0 }, request), request)
        end
        local cost = quote("clearSafeZone", request.actor, data, request)
        if cost == nil then return finish(id, makeResult(false, "quoteInvalid", nil, request), request) end
        local paid, receiptOrCode = charge(request.actor, cost, request)
        if not paid then return finish(id, makeResult(false, receiptOrCode, nil, request), request) end
        local paymentReceipt = receiptOrCode
        safe.lastCleared = count
        safe.lastClearHour = now or safe.lastClearHour
        data.stats.spentPoints = (safeInteger(data.stats.spentPoints, 0) or 0) + cost
        data.stats.homeSafeCleared = (safeInteger(data.stats.homeSafeCleared, 0) or 0) + count
        local saved, saveCode = save(request.actor, data, request)
        if not saved then
            local walletRestored = refund(request.actor, paymentReceipt, request)
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false,
                walletRestored and stateRestored and saveCode or "rollbackIncomplete", nil, request), request)
        end
        local executeCalled, executed, removedOrCode = callPort(
            world.executeClear, request.actor, plan, request)
        local removed = safeInteger(removedOrCode, nil)
        if not executeCalled or executed ~= true or removed ~= count then
            local walletRestored = refund(request.actor, paymentReceipt, request)
            local stateRestored = save(request.actor, before, request)
            return finish(id, makeResult(false,
                walletRestored and stateRestored and
                    (executeCalled and (removedOrCode or "clearFailed") or "portError") or "rollbackIncomplete",
                { planned = count, removed = removed }, request), request)
        end
        return finish(id, makeResult(true, "safeZoneCleared", {
            removed = removed,
            cost = cost,
        }, request), request)
    end

    instance.public = {
        setHome = function(request) return mutatePoint("setHome", request) end,
        buyTemp = function(request) return mutatePoint("buyTemp", request) end,
        setTemp = function(request) return mutatePoint("setTemp", request) end,
        teleportHome = function(request) return teleport("teleportHome", request) end,
        teleportTemp = function(request) return teleport("teleportTemp", request) end,
        returnToDeparture = function(request) return teleport("return", request) end,
        clearReturn = clearReturn,
        upgradeSafeZone = upgradeSafeZone,
        toggleSafeZone = toggleSafeZone,
        clearSafeZone = clearSafeZone,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        local data = { started = self.started, completed = self.completed, failed = self.failed, lastIssue = self.lastIssue }
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end
    return instance
end

return Descriptor
