require "GodSystem/Platform/Commerce/Support"

GodSystemShopIdentityPlatform = GodSystemShopIdentityPlatform or {}

local Descriptor = GodSystemShopIdentityPlatform
local Support = GodSystemCommercePlatformSupport
local SEPARATOR = "@worldSprite="

Descriptor.id = "shop.identity"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create()
    local instance = { started = false, generated = 0 }
    local function variantKey(fullType, itemOrSprite)
        instance.generated = instance.generated + 1
        fullType = tostring(fullType or "")
        local sprite = Support.worldSprite(itemOrSprite)
        if sprite then return fullType .. SEPARATOR .. sprite end
        return fullType
    end
    instance.public = {
        variantKey = variantKey,
        productId = function(row, source)
            instance.generated = instance.generated + 1
            if tostring(source or "") == "configured" and tostring(row and row.id or "") ~= "" then
                return tostring(row.id)
            end
            local key = tostring(row and row.variantKey or "")
            if key == "" and row then key = variantKey(row.fullType, row.worldSprite) end
            return key ~= "" and ("unlocked:" .. key) or nil
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { generated = self.generated },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
