-- Business reasons only; GodSystem_Result remains the network result format.
GodSystemRecycleResult = GodSystemRecycleResult or {}
local R = GodSystemRecycleResult
R.reasons = {
    distance = { "RecycleSourceDistance", "Move next to the selected items on the same floor; nothing was recycled" },
    blocked = { "RecycleSourceBlocked", "A wall or obstacle prevents access; nothing was recycled" },
    protected = { "RecycleSourceProtected", "These items are protected by a safehouse; nothing was recycled" },
    locked = { "RecycleSourceLocked", "This container is locked or inaccessible; nothing was recycled" },
    removeDenied = { "RecycleSourceDenied", "This container does not allow removal; nothing was recycled" },
    unloaded = { "RecycleSourceUnloaded", "The selected area is not loaded; nothing was recycled" },
    nativeReadFailed = { "RecycleSourceReadFailed", "Could not verify the native item or source; nothing was recycled. Check the console log" },
    identity = { "RecycleSourceIdentity", "Could not verify the selected item's identity; nothing was recycled" },
    coordinates = { "RecycleSourceIdentity", "Could not verify the selected item's identity; nothing was recycled" },
    unsupported = { "RecycleSourceUnsupported", "This source does not support direct recycling; nothing was recycled" },
    contentsChanged = { "RecycleSelectionContainerChanged", "Container contents changed; select and confirm again" },
    configChanged = { "RecycleConfigChanged", "Relevant prices, listing rules or filters changed; select and confirm again" },
    disabled = { "RecycleFeatureDisabled", "Recycling or listing was disabled; nothing was recycled" },
    sessionChanged = { "RecycleSessionChanged", "Player session changed or is still syncing; select again after syncing" },
    changed = { "RecycleSelectionChanged", "Selected items moved or disappeared; nothing was recycled" },
    deleteFailed = { "RecycleDeleteRestored", "Removal failed; selected items were restored and no recycling payment was made" },
    syncFailed = { "RecycleSyncRestored", "Removal synchronization failed; selected items were restored and no recycling payment was made" },
    payoutFailed = { "RecyclePayoutRestored", "Payment failed; selected items were restored" },
    unknown = { "TransactionOperationUnknown", "Result could not be verified. Keep the save and client/server logs; do not repeat payment" },
}
function R.code(reason)
    return (R.reasons[reason] or R.reasons.changed)[1]
end
function R.message(runtime, reason)
    local row = R.reasons[reason] or R.reasons.changed
    return runtime.text("NotifyMP_" .. row[1], row[2])
end
return R
