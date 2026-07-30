require "GodSystem/Platform/Commerce/Support"

GodSystemCommerceActorIdentityPlatform = GodSystemCommerceActorIdentityPlatform or {}

local Descriptor = GodSystemCommerceActorIdentityPlatform
local Support = GodSystemCommercePlatformSupport

Descriptor.id = "commerce.actor.identity"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create()
    local instance = { started = false, resolved = 0 }
    instance.public = {
        key = function(actor)
            instance.resolved = instance.resolved + 1
            local username = Support.safeCall(actor, "getUsername", nil)
            if username and tostring(username) ~= "" then return "user:" .. tostring(username) end
            local onlineId = Support.safeCall(actor, "getOnlineID", nil)
            if onlineId ~= nil then return "online:" .. tostring(onlineId) end
            local id = type(actor) == "table" and actor.id or nil
            if id ~= nil then return "actor:" .. tostring(id) end
            return "actor:local"
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { resolved = self.resolved },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
