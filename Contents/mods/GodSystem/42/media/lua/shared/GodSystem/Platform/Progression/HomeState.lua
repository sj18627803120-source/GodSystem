require "GodSystem/Platform/Progression/StateFactory"

GodSystemHomeStatePlatform = GodSystemHomeStatePlatform or GodSystemProgressionStateFactory.descriptor(
    "home.state", {
        homeSystem = {
            home = nil,
            tempSlots = {},
            returnPoint = nil,
            safeZone = { level = 0, enabled = false },
        },
        stats = {},
    })

return GodSystemHomeStatePlatform
