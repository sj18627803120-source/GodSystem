GodSystemAttributesPublicPort = GodSystemAttributesPublicPort or {}

local Descriptor = GodSystemAttributesPublicPort

Descriptor.id = "attributes"
Descriptor.dependencies = { "feature.attributes" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local feature = assert(dependencies["feature.attributes"], "feature.attributes dependency missing")
    local instance = { started = false, public = feature }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { target = "feature.attributes" },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
