require "GodSystem/Services/OperationLedger"

GodSystemOperationsService = GodSystemOperationsService or {}

local Descriptor = GodSystemOperationsService

Descriptor.id = "operations"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local state = context.state:get()
    state.buckets = type(state.buckets) == "table" and state.buckets or {}
    local instance = { started = false }
    local public = {}

    local function arguments(first, second, third)
        if first == public then return "default", second, third end
        return tostring(first or "default"), second, third
    end

    local function ledgerFor(moduleId)
        moduleId = tostring(moduleId or "default")
        local bucket = state.buckets[moduleId]
        if type(bucket) ~= "table" then
            bucket = {}
            state.buckets[moduleId] = bucket
        end
        return GodSystemOperationLedger.new(bucket, { maxEntries = 400 })
    end

    public = {
        begin = function(first, second, third)
            local moduleId, operationId, fingerprint = arguments(first, second, third)
            local row, replay = ledgerFor(moduleId):begin(operationId, fingerprint)
            if first == public then return row, replay end
            if not row then return false, replay end
            if replay then return "replay", row.result or replay end
            return "started", row
        end,
        finish = function(first, second, third)
            local moduleId, operationId, result = arguments(first, second, third)
            return ledgerFor(moduleId):finish(operationId, result)
        end,
        markUnknown = function(first, second, third)
            local moduleId, operationId, code = arguments(first, second, third)
            return ledgerFor(moduleId):markUnknown(operationId, code)
        end,
        get = function(first, second)
            local moduleId, operationId = arguments(first, second)
            return ledgerFor(moduleId):get(operationId)
        end,
    }
    instance.public = public

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        local entries = 0
        for _, bucket in pairs(state.buckets) do entries = entries + #(bucket.order or {}) end
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { entries = entries, maximumPerModule = 400 },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
