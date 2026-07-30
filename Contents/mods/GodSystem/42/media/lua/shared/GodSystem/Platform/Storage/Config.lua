require "GodSystem/Platform/Storage/Support"

GodSystemStorageConfigPlatform = GodSystemStorageConfigPlatform or {}

local Descriptor = GodSystemStorageConfigPlatform
local Support = GodSystemStoragePlatformSupport

Descriptor.id = "storage.config"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local source = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local counters = { snapshots = 0, failures = 0 }
    local public = {}
    function public.snapshot()
        counters.snapshots = counters.snapshots + 1
        return {
            enabled = source.EnableStorageNetwork ~= false,
            maxNodes = Support.integer(source.StorageMaxLinks, 128, 1, 128),
            maxDepth = Support.integer(source.StorageMaxDepth, 32, 1, 32),
            maxIndexedItems = Support.integer(
                source.StorageMaxIndexedItems, 20000, 1, 20000),
            indexBatchItems = Support.integer(
                source.StorageIndexBatchItems, 250, 1, 250),
            indexBudgetMs = math.max(0.25, math.min(2,
                Support.number(source.StorageIndexBudgetMs, 2) or 2)),
            coreRecoveryCost = Support.integer(
                source.StorageCoreRecoveryCost, 2000, 0),
            coreUseDistance = math.max(0.5,
                Support.number(source.StorageCoreUseDistance, 3.5) or 3.5),
            manageDistance = math.max(0.5,
                Support.number(source.StorageManageDistance, 2.5) or 2.5),
        }
    end
    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
