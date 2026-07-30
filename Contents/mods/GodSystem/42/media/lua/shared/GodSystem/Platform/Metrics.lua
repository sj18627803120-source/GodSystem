GodSystemMetricsPlatform = GodSystemMetricsPlatform or {}

local Descriptor = GodSystemMetricsPlatform
local MAX_SAFE_INTEGER = 9007199254740991

Descriptor.id = "metrics"
Descriptor.dependencies = { "wallet.accounts" }
Descriptor.stateVersion = 1

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function integer(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    value = math.floor(value)
    if math.abs(value) > MAX_SAFE_INTEGER then return nil end
    return value
end

local function metricName(value)
    value = tostring(value or "")
    if value == "" or #value > 128 or not value:match("^[%w%._%-]+$") then return nil end
    return value
end

local function cleanCounters(source)
    local result = {}
    for name, value in pairs(type(source) == "table" and source or {}) do
        local key = metricName(name)
        local amount = integer(value)
        if key and amount and amount >= 0 then result[key] = amount end
    end
    return result
end

function Descriptor.create(dependencies, context)
    dependencies = dependencies or {}
    context = context or {}
    local accounts = assert(dependencies["wallet.accounts"], "wallet.accounts dependency missing")
    assert(type(accounts.key) == "function", "wallet.accounts key method missing")
    local root = assert(context.state, "metrics context.state missing"):get()
    local binding = type(context.binding) == "table" and context.binding or {}
    root.counters = type(root.counters) == "table" and root.counters or {}
    local instance = { started = false, reads = 0, writes = 0, restores = 0 }
    local public = {}

    local function actorKey(actor)
        return tostring(accounts.key(actor))
    end

    local function row(actor)
        local key = actorKey(actor)
        local value = root.counters[key]
        if type(value) ~= "table" then
            local initial
            if type(binding.initialCounters) == "function" then
                initial = binding.initialCounters(actor, key)
            elseif type(binding.initialCounters) == "table" then
                initial = binding.initialCounters[key]
            end
            value = cleanCounters(initial)
            root.counters[key] = value
        else
            value = cleanCounters(value)
            root.counters[key] = value
        end
        return value, key
    end

    local function snapshot(actor)
        instance.reads = instance.reads + 1
        local value = row(actor)
        return copy(value)
    end

    local function get(actor, name)
        local key = metricName(name)
        if not key then return 0 end
        instance.reads = instance.reads + 1
        local value = row(actor)
        return integer(value[key]) or 0
    end

    local function increment(actor, nameOrChanges, amount)
        local changes = {}
        if type(nameOrChanges) == "table" then
            for name, delta in pairs(nameOrChanges) do
                local key = metricName(name)
                local value = integer(delta)
                if not key or value == nil then return false, "metricChangeInvalid" end
                changes[key] = (changes[key] or 0) + value
                if math.abs(changes[key]) > MAX_SAFE_INTEGER then return false, "metricOverflow" end
            end
        else
            local key = metricName(nameOrChanges)
            local value = integer(amount)
            if not key or value == nil then return false, "metricChangeInvalid" end
            changes[key] = value
        end
        if next(changes) == nil then return false, "metricChangeEmpty" end

        local value, key = row(actor)
        local before, after = {}, {}
        for name, delta in pairs(changes) do
            local current = integer(value[name]) or 0
            if delta > 0 and current > MAX_SAFE_INTEGER - delta then
                return false, "metricOverflow"
            end
            local target = current + delta
            if target < 0 or target > MAX_SAFE_INTEGER then return false, "metricRangeInvalid" end
            before[name] = current
            after[name] = target
        end
        for name, target in pairs(after) do value[name] = target end
        instance.writes = instance.writes + 1
        return true, {
            actorKey = key,
            before = before,
            after = after,
            changes = copy(changes),
        }
    end

    local function restore(actor, receipt)
        if type(receipt) ~= "table" or tostring(receipt.actorKey or "") ~= actorKey(actor)
            or type(receipt.before) ~= "table" or type(receipt.after) ~= "table"
        then
            return false, "metricReceiptInvalid"
        end
        local value = row(actor)
        for name, expected in pairs(receipt.after) do
            local key = metricName(name)
            local target = integer(expected)
            if not key or target == nil or (integer(value[key]) or 0) ~= target then
                return false, "metricStateChanged"
            end
        end
        for name, previous in pairs(receipt.before) do
            local key = metricName(name)
            local target = integer(previous)
            if not key or target == nil or target < 0 then return false, "metricReceiptInvalid" end
        end
        for name, previous in pairs(receipt.before) do value[name] = previous end
        instance.restores = instance.restores + 1
        return true
    end

    public = {
        snapshot = function(first, second)
            return snapshot(first == public and second or first)
        end,
        get = function(first, second, third)
            if first == public then return get(second, third) end
            return get(first, second)
        end,
        increment = function(first, second, third, fourth)
            if first == public then return increment(second, third, fourth) end
            return increment(first, second, third)
        end,
        restore = function(first, second, third)
            if first == public then return restore(second, third) end
            return restore(first, second)
        end,
    }
    instance.public = public

    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { reads = self.reads, writes = self.writes, restores = self.restores },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
