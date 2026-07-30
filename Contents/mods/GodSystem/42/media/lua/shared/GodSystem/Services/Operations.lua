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

    local function actorKey(request)
        request = type(request) == "table" and request or {}
        local explicit = tostring(request.actorKey or "")
        if explicit ~= "" then return explicit end
        local actor = request.actor
        if actor and type(actor.getUsername) == "function" then
            local username = actor:getUsername()
            if username ~= nil and tostring(username) ~= "" then return tostring(username) end
        end
        if actor and type(actor.getOnlineID) == "function" then
            local onlineId = actor:getOnlineID()
            if onlineId ~= nil then return "id:" .. tostring(onlineId) end
        end
        return "local"
    end

    local function arguments(first, second, third, fourth)
        if first == public then return "default", second, third, fourth end
        return tostring(first or "default"), second, third, fourth
    end

    local function ledgerFor(moduleId, request)
        local scope = tostring(moduleId or "default") .. "@" .. actorKey(request)
        local bucket = state.buckets[scope]
        if type(bucket) ~= "table" then
            bucket = {}
            state.buckets[scope] = bucket
        end
        return GodSystemOperationLedger.new(bucket, { maxEntries = 400 })
    end

    public = {
        begin = function(first, second, third, fourth)
            local moduleId, operationId, fingerprint, request = arguments(first, second, third, fourth)
            local row, replay = ledgerFor(moduleId, request):begin(operationId, fingerprint)
            if first == public then return row, replay end
            if not row then return false, replay end
            if replay then return "replay", row.result or replay end
            return "new", row
        end,
        finish = function(first, second, third, fourth)
            local moduleId, operationId, result, request = arguments(first, second, third, fourth)
            return ledgerFor(moduleId, request):finish(operationId, result)
        end,
        markUnknown = function(first, second, third, fourth)
            local moduleId, operationId, code, request = arguments(first, second, third, fourth)
            return ledgerFor(moduleId, request):markUnknown(operationId, code)
        end,
        get = function(first, second, third)
            local moduleId, operationId, request = arguments(first, second, third)
            return ledgerFor(moduleId, request):get(operationId)
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
