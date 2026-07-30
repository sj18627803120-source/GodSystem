require "GodSystem/Platform/AutoLoader/Support"

GodSystemAutoLoaderOperationsPlatform = GodSystemAutoLoaderOperationsPlatform or {}

local Descriptor = GodSystemAutoLoaderOperationsPlatform
local Support = GodSystemAutoLoaderPlatformSupport

Descriptor.id = "autoloader.operations"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function validOperationId(value)
    value = tostring(value or "")
    if #value > 96 or not string.match(value, "^gsa%-%d+%-%d+%-%d+$") then return nil end
    return value
end

local function bucketFor(actor)
    local modData = Support.safeCall(actor, "getModData", nil)
    if type(modData) ~= "table" then return nil end
    local bucket = modData[Support.OperationKey]
    if type(bucket) ~= "table" then
        bucket = { results = {}, order = {} }
        modData[Support.OperationKey] = bucket
    end
    bucket.results = type(bucket.results) == "table" and bucket.results or {}
    bucket.order = type(bucket.order) == "table" and bucket.order or {}
    return bucket
end

function Descriptor.create()
    local normalized = {}
    local instance = {
        started = false,
        begun = 0,
        replayed = 0,
        mismatched = 0,
    }

    local function normalize(bucket)
        if normalized[bucket] then return end
        normalized[bucket] = true
        for _, result in pairs(bucket.results) do
            if type(result) == "table" and result.status == "processing" then
                result.status = "unknown"
            end
        end
    end

    instance.public = {
        begin = function(_, action, operationId, fingerprint, request)
            operationId = validOperationId(operationId)
            local actor = type(request) == "table" and request.actor or nil
            local bucket = operationId and bucketFor(actor) or nil
            if not bucket then return nil, "invalid" end
            normalize(bucket)
            local existing = bucket.results[operationId]
            if existing then
                if tostring(existing.fingerprint or "") ~= tostring(fingerprint or "") then
                    instance.mismatched = instance.mismatched + 1
                    return nil, "mismatch"
                end
                instance.replayed = instance.replayed + 1
                return existing, existing.status
            end
            local row = {
                operationId = operationId,
                action = tostring(action or ""),
                status = "processing",
                fingerprint = tostring(fingerprint or ""),
                createdAt = Support.nowMs(),
            }
            bucket.results[operationId] = row
            bucket.order[#bucket.order + 1] = operationId
            while #bucket.order > 64 do
                bucket.results[table.remove(bucket.order, 1)] = nil
            end
            instance.begun = instance.begun + 1
            return row, "new"
        end,
        finish = function(row, result)
            if type(row) ~= "table" then return false, "operationMissing" end
            row.status = "done"
            row.ok = result and result.ok == true
            row.code = tostring(result and result.code or "")
            row.result = result
            row.finishedAt = Support.nowMs()
            return true
        end,
    }

    function instance:start()
        self.started = true
        return true
    end

    function instance:stop()
        self.started = false
        return true
    end

    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = {
                begun = self.begun,
                replayed = self.replayed,
                mismatched = self.mismatched,
            },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
