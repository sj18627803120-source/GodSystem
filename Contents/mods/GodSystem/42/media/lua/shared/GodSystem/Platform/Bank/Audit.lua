require "GodSystem/Platform/Bank/Support"

GodSystemBankAuditPlatform = GodSystemBankAuditPlatform or {}

local Descriptor = GodSystemBankAuditPlatform
local Support = GodSystemBankPlatformSupport

Descriptor.id = "bank.audit"
Descriptor.dependencies = { "wallet.accounts" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies, context)
    context = context or {}
    local accounts = assert(dependencies["wallet.accounts"], "wallet.accounts dependency missing")
    local root = assert(context.state, "bank.audit context.state missing"):get()
    local binding = type(context.binding) == "table" and context.binding or {}
    root.players = type(root.players) == "table" and root.players or {}
    local instance = { started = false, records = 0, increments = 0 }

    local function row(actor)
        local key = accounts.key(actor)
        local value = root.players[key]
        if type(value) ~= "table" then
            value = { counters = {}, events = {} }
            root.players[key] = value
        end
        value.counters = type(value.counters) == "table" and value.counters or {}
        value.events = type(value.events) == "table" and value.events or {}
        return value, key
    end

    local public = {}
    function public:counter(actor, name)
        name = tostring(name or "")
        if type(binding.counterSource) == "function" then
            local value = binding.counterSource(actor, name)
            if value ~= nil then return Support.integer(value, 0, 0) end
        end
        return Support.integer(row(actor).counters[name], 0, 0)
    end
    function public:increment(actor, name, amount, request)
        name = tostring(name or "")
        amount = Support.integer(amount, 0)
        if name == "" then return false end
        local value = row(actor)
        value.counters[name] = math.max(0,
            Support.integer(value.counters[name], 0, 0) + amount)
        instance.increments = instance.increments + 1
        if type(binding.incrementSink) == "function"
            and binding.incrementSink(actor, name, amount, request) == false
        then
            value.counters[name] = math.max(0, value.counters[name] - amount)
            return false
        end
        return true
    end
    function public:record(actor, code, data, request)
        code = tostring(code or "")
        if code == "" then return false end
        local value = row(actor)
        local event = {
            code = code,
            data = Support.copy(data or {}),
            operationId = tostring(request and request.operationId or ""),
        }
        table.insert(value.events, 1, event)
        while #value.events > 200 do table.remove(value.events) end
        instance.records = instance.records + 1
        if type(binding.recordSink) == "function"
            and binding.recordSink(actor, Support.copy(event), request) == false
        then
            table.remove(value.events, 1)
            return false
        end
        return true
    end

    instance.public = public
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { records = self.records, increments = self.increments },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
