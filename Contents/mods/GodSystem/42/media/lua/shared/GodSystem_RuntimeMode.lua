GodSystemRuntimeMode = GodSystemRuntimeMode or {
    targetVersion = "42.20.1.2",
    modularEnabled = false,
}

function GodSystemRuntimeMode.enableModular()
    GodSystemRuntimeMode.modularEnabled = true
end

function GodSystemRuntimeMode.legacyBusinessEnabled()
    return GodSystemRuntimeMode.modularEnabled ~= true
end

return GodSystemRuntimeMode
