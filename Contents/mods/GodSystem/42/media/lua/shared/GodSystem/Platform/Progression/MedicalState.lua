require "GodSystem/Platform/Progression/StateFactory"

GodSystemMedicalStatePlatform = GodSystemMedicalStatePlatform or GodSystemProgressionStateFactory.descriptor(
    "medical.state", { stats = {} })

return GodSystemMedicalStatePlatform
