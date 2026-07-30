require "GodSystem/Core/Result"

GodSystemSystemFeatureModule = GodSystemSystemFeatureModule or {}

local Descriptor = GodSystemSystemFeatureModule

Descriptor.id = "feature.system"
Descriptor.dependencies = {
    "wallet.accounts",
    "wallet",
    "operations",
    "notifications",
}
Descriptor.stateVersion = 1

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function integer(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.floor(value)
end

local function operationId(request)
    local value = tostring(request and request.operationId or "")
    if value == "" or #value > 160 then return nil end
    return value
end

function Descriptor.create(dependencies, context)
    dependencies, context = dependencies or {}, context or {}
    local accounts = assert(dependencies["wallet.accounts"], "wallet.accounts dependency missing")
    local wallet = assert(dependencies.wallet, "wallet dependency missing")
    local operations = assert(dependencies.operations, "operations dependency missing")
    local notifications = assert(dependencies.notifications, "notifications dependency missing")
    local scope = assert(context.state, "feature.system state missing")
    local root = scope:get()
    root.players = type(root.players) == "table" and root.players or {}
    local config = type(context.configSnapshot) == "table" and context.configSnapshot or {}
    local historyLimit = math.max(20, integer(config.HistoryLimit, 200) or 200)
    local instance = { started = false, initialized = 0, failures = 0 }

    local function key(actor)
        return tostring(accounts.key(actor))
    end

    local function row(actor)
        local actorKey = key(actor)
        local data = root.players[actorKey]
        if type(data) ~= "table" then
            data = {
                version = tostring(context.version or ""),
                started = false,
                currencyInitialized = false,
                pendingCurrencyGrant = math.max(0,
                    integer(config.StartingPoints, 60) or 60),
                history = {},
                ui = {},
            }
            root.players[actorKey] = data
        end
        data.history = type(data.history) == "table" and data.history or {}
        data.ui = type(data.ui) == "table" and data.ui or {}
        return data, actorKey
    end

    local function result(ok, code, data, request)
        local value = ok
            and GodSystemResult.ok(Descriptor.id, code, data, operationId(request))
            or GodSystemResult.fail(Descriptor.id, code, data, operationId(request))
        notifications.publish(value, request)
        if not ok then instance.failures = instance.failures + 1 end
        return value
    end

    local function appendHistory(data, entry)
        entry = copy(type(entry) == "table" and entry or {})
        entry.kind = tostring(entry.kind or "system")
        data.history[#data.history + 1] = entry
        while #data.history > historyLimit do table.remove(data.history, 1) end
    end

    local function ensureInitialized(request)
        request = type(request) == "table" and request or {}
        if not request.actor then return result(false, "actorRequired", nil, request) end
        local id = operationId(request)
        if not id then return result(false, "operationIdRequired", nil, request) end
        local data = row(request.actor)
        if data.currencyInitialized == true then
            return result(true, "alreadyInitialized", {
                granted = 0,
                started = data.started == true,
            }, request)
        end
        local status, cached = operations.begin(Descriptor.id, id,
            "initialize|" .. key(request.actor), request)
        if status == "replay" then return cached end
        if status ~= "new" then
            return result(false, type(cached) == "table" and cached.code
                or "operationInvalid", nil, request)
        end
        local before = copy(data)
        local amount = math.max(0, integer(data.pendingCurrencyGrant,
            integer(config.StartingPoints, 60) or 60) or 0)
        local receipt
        if amount > 0 then
            local granted, receiptOrCode = wallet.grant(request.actor, amount, {
                actor = request.actor,
                operationId = id .. ":currency",
                scope = "cash",
            })
            if granted ~= true then
                local failure = result(false, receiptOrCode or "currencyGrantFailed",
                    { amount = amount }, request)
                operations.finish(Descriptor.id, id, failure, request)
                return failure
            end
            receipt = receiptOrCode
        end
        data.started = true
        data.currencyInitialized = true
        data.pendingCurrencyGrant = 0
        data.version = tostring(context.version or data.version or "")
        appendHistory(data, {
            kind = "system",
            code = "initialCurrency",
            amount = amount,
        })
        local success = result(true, "initialized", {
            granted = amount,
            receipt = receipt,
        }, request)
        local finished = operations.finish(Descriptor.id, id, success, request)
        if type(finished) ~= "table" then
            root.players[key(request.actor)] = before
            if receipt then
                wallet.refund(request.actor, receipt, {
                    actor = request.actor,
                    operationId = id .. ":rollback",
                })
            end
            operations.markUnknown(Descriptor.id, id, "operationOutcomeUnknown", request)
            return result(false, "operationOutcomeUnknown", nil, request)
        end
        instance.initialized = instance.initialized + 1
        return finished
    end

    local function snapshot(request)
        request = type(request) == "table" and request or {}
        if not request.actor then return result(false, "actorRequired", nil, request) end
        local data = row(request.actor)
        return result(true, "snapshot", copy(data), request)
    end

    local function setPreference(request)
        request = type(request) == "table" and request or {}
        if not request.actor then return result(false, "actorRequired", nil, request) end
        local preferenceKey = tostring(request.key or "")
        if preferenceKey == "" or #preferenceKey > 80
            or not preferenceKey:match("^[%w%._%-]+$")
        then
            return result(false, "preferenceKeyInvalid", nil, request)
        end
        local data = row(request.actor)
        local valueType = type(request.value)
        if valueType ~= "string" and valueType ~= "number"
            and valueType ~= "boolean" and valueType ~= "nil"
        then
            return result(false, "preferenceValueInvalid", nil, request)
        end
        data.ui[preferenceKey] = request.value
        return result(true, "preferenceChanged", {
            key = preferenceKey,
            value = request.value,
        }, request)
    end

    local function setPreferences(request)
        request = type(request) == "table" and request or {}
        if not request.actor then return result(false, "actorRequired", nil, request) end
        local values = type(request.values) == "table" and request.values or nil
        if not values then return result(false, "preferenceValuesInvalid", nil, request) end
        local clean, count = {}, 0
        for preferenceKey, value in pairs(values) do
            preferenceKey = tostring(preferenceKey or "")
            if preferenceKey == "" or #preferenceKey > 80
                or not preferenceKey:match("^[%w%._%-]+$")
            then
                return result(false, "preferenceKeyInvalid", nil, request)
            end
            local valueType = type(value)
            if valueType ~= "string" and valueType ~= "number"
                and valueType ~= "boolean" and valueType ~= "nil"
            then
                return result(false, "preferenceValueInvalid", nil, request)
            end
            clean[preferenceKey] = value
            count = count + 1
        end
        local data = row(request.actor)
        for preferenceKey, value in pairs(clean) do
            data.ui[preferenceKey] = value
        end
        return result(true, "preferencesChanged", {
            values = copy(clean),
            count = count,
        }, request)
    end

    local function history(request)
        request = type(request) == "table" and request or {}
        if not request.actor then return result(false, "actorRequired", nil, request) end
        local data = row(request.actor)
        return result(true, "history", copy(data.history), request)
    end

    instance.public = {
        ensureInitialized = ensureInitialized,
        snapshot = snapshot,
        setPreference = setPreference,
        setPreferences = setPreferences,
        history = history,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = {
                initialized = self.initialized,
                failures = self.failures,
            },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
