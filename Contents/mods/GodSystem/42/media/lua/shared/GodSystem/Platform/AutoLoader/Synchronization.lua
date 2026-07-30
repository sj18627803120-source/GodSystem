GodSystemAutoLoaderSynchronizationPlatform = GodSystemAutoLoaderSynchronizationPlatform or {}

local Descriptor = GodSystemAutoLoaderSynchronizationPlatform

Descriptor.id = "autoloader.synchronization"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local function optionalCall(callback, ...)
    if type(callback) ~= "function" then return true end
    local ok = pcall(callback, ...)
    return ok
end

function Descriptor.create()
    local instance = {
        started = false,
        calls = 0,
        failures = 0,
    }

    local function track(ok)
        instance.calls = instance.calls + 1
        if not ok then instance.failures = instance.failures + 1 end
        return ok
    end

    instance.public = {
        loader = function(actor, loader)
            local ok = optionalCall(syncItemModData, actor, loader)
                and optionalCall(syncItemFields, actor, loader)
                and optionalCall(sendItemStats, loader)
            return track(ok), ok and nil or "loaderSyncFailed"
        end,
        magazine = function(actor, magazine)
            local ok = optionalCall(syncItemFields, actor, magazine)
            return track(ok), ok and nil or "magazineSyncFailed"
        end,
        created = function(_, receipt)
            local ok = type(receipt) == "table"
                and optionalCall(sendAddItemToContainer, receipt.container, receipt.item)
            return track(ok), ok and nil or "createdSyncFailed"
        end,
        removed = function(_, receipt)
            local ok = type(receipt) == "table"
                and optionalCall(sendRemoveItemFromContainer, receipt.container, receipt.item)
            return track(ok), ok and nil or "removedSyncFailed"
        end,
        restored = function(_, receipt)
            local container = type(receipt) == "table"
                and (receipt.restoredContainer or receipt.container) or nil
            local item = type(receipt) == "table"
                and (receipt.restoredItem or receipt.item) or nil
            local ok = type(receipt) == "table"
                and optionalCall(sendAddItemToContainer, container, item)
            return track(ok), ok and nil or "restoredSyncFailed"
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
            ok = self.started and self.failures == 0,
            code = self.failures > 0 and "synchronizationFailure"
                or (self.started and "healthy" or "stopped"),
            data = { calls = self.calls, failures = self.failures },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
