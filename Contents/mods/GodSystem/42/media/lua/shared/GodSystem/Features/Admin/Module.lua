require "GodSystem/Core/Result"
require "GodSystem/Features/Admin/Rules"

GodSystemAdminFeatureModule = GodSystemAdminFeatureModule or {}

local Descriptor = GodSystemAdminFeatureModule
local Rules = GodSystemAdminFeatureRules

Descriptor.id = "feature.admin"
Descriptor.dependencies = {
    "admin.source",
    "admin.permissions",
    "admin.runtime",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

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

local function required(dependencies, id, methods)
    local port = dependencies[id]
    assert(type(port) == "table", "missing dependency: " .. id)
    for index = 1, #methods do
        assert(type(port[methods[index]]) == "function",
            "dependency " .. id .. " is missing method " .. methods[index])
    end
    return port
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 160 then return nil end
    return value
end

local function stable(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    local parts = {}
    for index = 1, #keys do
        local key = keys[index]
        parts[#parts + 1] = key .. "=" .. stable(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function Descriptor.create(dependencies, context)
    dependencies, context = dependencies or {}, context or {}
    local moduleId = tostring(context.moduleId or Descriptor.id)
    local source = required(dependencies, "admin.source", { "defaults", "staticOverrides" })
    local permissions = required(dependencies, "admin.permissions", { "canConfigure" })
    local runtime = required(dependencies, "admin.runtime", { "apply", "health" })
    local operations = required(dependencies, "operations", { "begin", "finish", "markUnknown" })
    local notifications = required(dependencies, "notifications", { "publish" })
    local scope = assert(context.state, "feature.admin state context required")
    assert(type(scope.get) == "function" and type(scope.replace) == "function",
        "feature.admin state scope invalid")
    local instance = { started = false, completed = 0, failed = 0, lastIssue = nil }
    local baseSettings, staticOverrides = {}, {}

    local function makeResult(ok, code, data, request)
        if ok then instance.completed = instance.completed + 1
        else instance.failed = instance.failed + 1 end
        local result = ok and GodSystemResult.ok(moduleId, code, data, operationId(request))
            or GodSystemResult.fail(moduleId, code, data, operationId(request))
        local called, published = call(notifications.publish, result, request)
        if not called or published == false then
            instance.lastIssue = { stage = "notify", code = "notificationFailed" }
        end
        return result
    end

    local function root()
        local data = scope:get()
        data.settings = type(data.settings) == "table" and data.settings or {}
        data.itemOverrides = type(data.itemOverrides) == "table" and data.itemOverrides or {}
        data.revision = math.max(0, math.floor(tonumber(data.revision) or 0))
        return data
    end

    local function stored()
        local data = root()
        return {
            settings = Rules.sanitizeSettings(data.settings, baseSettings),
            itemOverrides = Rules.sanitizeOverrides(data.itemOverrides),
            revision = data.revision,
        }
    end

    local function snapshot(value)
        return Rules.snapshot(value or stored(), baseSettings, staticOverrides)
    end

    local function persist(value)
        value = type(value) == "table" and value or {}
        scope:replace({
            settings = Rules.sanitizeSettings(value.settings, baseSettings),
            itemOverrides = Rules.sanitizeOverrides(value.itemOverrides),
            revision = math.max(0, math.floor(tonumber(value.revision) or 0)),
        }, Rules.stateVersion)
        return true
    end

    local function apply(value)
        local called, applied, code = call(
            runtime.apply, Rules.copy(value.settings), Rules.copy(value.itemOverrides), value.revision)
        if not called then return false, "portError" end
        return applied == true, code or "runtimeApplyFailed"
    end

    local function begin(action, fingerprintValue, request)
        local id = operationId(request)
        if not id then return nil, makeResult(false, "operationIdRequired", nil, request) end
        local called, status, value = call(
            operations.begin, moduleId, id, tostring(action) .. "|" .. stable(fingerprintValue), request)
        if not called then
            instance.lastIssue = { stage = "operationBegin", code = "portError", message = tostring(status) }
            return nil, makeResult(false, "portError", { stage = "operationBegin" }, request)
        end
        if status == "replay" then return nil, value end
        if status ~= "new" then
            return nil, makeResult(false,
                type(value) == "table" and value.code or tostring(value or "operationPending"), nil, request)
        end
        return id
    end

    local function finish(id, result, request)
        local called, stored = call(operations.finish, moduleId, id, result, request)
        if called and stored ~= false then return result end
        call(operations.markUnknown, moduleId, id, "operationOutcomeUnknown", request)
        instance.lastIssue = { stage = "operationFinish", code = "operationOutcomeUnknown" }
        return GodSystemResult.fail(moduleId, "operationOutcomeUnknown", {
            committed = result and result.ok == true,
        }, id)
    end

    local function allowed(actor)
        local called, value = call(permissions.canConfigure, actor)
        return called and value == true
    end

    local function mutate(action, fingerprintValue, request, transform)
        request = type(request) == "table" and request or {}
        if not instance.started then return makeResult(false, "moduleStopped", nil, request) end
        local id, replay = begin(action, fingerprintValue, request)
        if replay then return replay end
        if not allowed(request.actor) then
            return finish(id, makeResult(false, "adminPermissionDenied", nil, request), request)
        end
        local before = stored()
        local nextValue, transformCode = transform(Rules.copy(before))
        if type(nextValue) ~= "table" then
            return finish(id, makeResult(false, transformCode or "adminInputInvalid", nil, request), request)
        end
        nextValue.revision = before.revision + 1
        persist(nextValue)
        local applied, applyCode = apply(snapshot(nextValue))
        if not applied then
            persist(before)
            local restored = apply(snapshot(before))
            return finish(id, makeResult(false,
                restored and applyCode or "rollbackIncomplete", nil, request), request)
        end
        local current = snapshot(stored())
        return finish(id, makeResult(true, action .. "Applied", {
            revision = current.revision,
            settings = current.settings,
            itemOverrides = current.itemOverrides,
        }, request), request)
    end

    local function setSettings(request)
        request = type(request) == "table" and request or {}
        return mutate("settings", request.settings, request, function(value)
            value.settings = Rules.sanitizeSettings(request.settings, baseSettings)
            return value
        end)
    end

    local function setItemOverride(request)
        request = type(request) == "table" and request or {}
        local fullType = Rules.text(request.fullType, 120)
        return mutate("itemOverride", { fullType = fullType, value = request.override }, request,
            function(value)
                local override = Rules.sanitizeOverride(request.override)
                if fullType == "" or not override then return nil, "itemOverrideInvalid" end
                value.itemOverrides = Rules.sanitizeOverrides(value.itemOverrides)
                value.itemOverrides[fullType] = override
                return value
            end)
    end

    local function clearItemOverride(request)
        request = type(request) == "table" and request or {}
        local fullType = Rules.text(request.fullType, 120)
        return mutate("itemOverrideCleared", fullType, request, function(value)
            if fullType == "" then return nil, "itemOverrideInvalid" end
            value.itemOverrides = Rules.sanitizeOverrides(value.itemOverrides)
            value.itemOverrides[fullType] = nil
            return value
        end)
    end

    local function getSetting(key, fallback)
        local current = snapshot()
        local value = current.settings[tostring(key or "")]
        if value == nil then return fallback end
        return value
    end

    local function getItemOverride(fullType)
        return Rules.copy(snapshot().itemOverrides[tostring(fullType or "")])
    end

    local function applyPrice(fullType, price, kind, multiplierKey)
        price = math.max(0, math.floor(tonumber(price) or 0))
        local override = getItemOverride(fullType)
        if override and override[kind] ~= nil then return override[kind] end
        return math.max(0, math.floor(price * (tonumber(getSetting(multiplierKey, 1)) or 1)))
    end

    instance.public = {
        getSnapshot = function() return snapshot() end,
        getMeta = function() return Rules.copy(Rules.meta) end,
        setSettings = setSettings,
        setItemOverride = setItemOverride,
        clearItemOverride = clearItemOverride,
        getSetting = getSetting,
        isFeatureEnabled = function(key) return getSetting(key, true) == true end,
        getItemOverride = getItemOverride,
        getItemOverrides = function() return Rules.copy(snapshot().itemOverrides) end,
        applyShopBuyPrice = function(fullType, price)
            return applyPrice(fullType, price, "buyPrice", "ShopBuyPriceMultiplier")
        end,
        applyRecycleSellPrice = function(fullType, price)
            return applyPrice(fullType, price, "sellPrice", "RecycleSellPriceMultiplier")
        end,
        applyTaskReward = function(value)
            return math.max(0, math.floor((tonumber(value) or 0)
                * (tonumber(getSetting("TaskRewardMultiplier", 1)) or 1)))
        end,
        applyTaskPenalty = function(value)
            return math.max(0, math.floor((tonumber(value) or 0)
                * (tonumber(getSetting("TaskPenaltyMultiplier", 1)) or 1)))
        end,
        getCategory = function(fullType, fallback)
            local override = getItemOverride(fullType)
            return override and override.category or fallback
        end,
        isItemEnabled = function(fullType, field, fallback)
            local override = getItemOverride(fullType)
            if override and override[field] ~= nil then return override[field] == true end
            return fallback ~= false
        end,
    }

    function instance:start()
        local defaultsCalled, defaults = call(source.defaults)
        local overridesCalled, overrides = call(source.staticOverrides)
        if not defaultsCalled or type(defaults) ~= "table"
            or not overridesCalled or type(overrides) ~= "table"
        then
            self.lastIssue = { stage = "source", code = "portError" }
            return false
        end
        baseSettings = Rules.sanitizeSettings(defaults)
        staticOverrides = Rules.sanitizeOverrides(overrides)
        local value = stored()
        persist(value)
        local applied, code = apply(snapshot(value))
        if not applied then
            self.lastIssue = { stage = "runtime", code = code }
            return false
        end
        self.started = true
        return true
    end

    function instance:stop() self.started = false return true end
    function instance:health()
        local data = {
            started = self.started,
            completed = self.completed,
            failed = self.failed,
            revision = snapshot().revision,
            lastIssue = self.lastIssue,
        }
        local called, healthy, detail = call(runtime.health)
        if not called or healthy == false then
            data.runtime = detail or healthy
            return GodSystemResult.fail(moduleId, "runtimeUnhealthy", data)
        end
        if self.lastIssue then return GodSystemResult.fail(moduleId, self.lastIssue.code, data) end
        return GodSystemResult.ok(moduleId, self.started and "healthy" or "stopped", data)
    end

    return instance
end

return Descriptor
