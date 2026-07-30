require "GodSystem/Platform/Commerce/Support"

GodSystemShopListingsPlatform = GodSystemShopListingsPlatform or {}

local Descriptor = GodSystemShopListingsPlatform
local Support = GodSystemCommercePlatformSupport

Descriptor.id = "shop.listings"
Descriptor.dependencies = { "shop.state", "shop.config" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local state = assert(dependencies["shop.state"], "shop.state dependency missing")
    local config = assert(dependencies["shop.config"], "shop.config dependency missing")
    local instance = { started = false, added = 0, removed = 0 }

    instance.public = {
        isKnown = function(actor, variantKey, request)
            variantKey = tostring(variantKey or "")
            if config.isConfigured(variantKey, request) == true then return true, "configured" end
            local data = state.load(actor, request)
            return type(data) == "table"
                and type(data.unlockedShopItems) == "table"
                and data.unlockedShopItems[variantKey] ~= nil,
                "unlocked"
        end,
        add = function(actor, row, request)
            if type(row) ~= "table" or tostring(row.variantKey or "") == "" then
                return false, "variantInvalid"
            end
            local data, code = state.load(actor, request)
            if type(data) ~= "table" then return false, code or "stateUnavailable" end
            local key = tostring(row.variantKey)
            if config.isConfigured(key, request) == true
                or data.unlockedShopItems[key] ~= nil
            then
                return false, "alreadyListed"
            end
            data.unlockedShopItems[key] = Support.copy(row)
            data.unlockedShopItems[key].variantKey = key
            data.unlockedShopItems[key].hidden = false
            local saved, saveCode = state.save(actor, data, request)
            if saved ~= true then return false, saveCode or "stateSaveFailed" end
            instance.added = instance.added + 1
            return true, { variantKey = key }
        end,
        remove = function(actor, receipt, request)
            local key = tostring(type(receipt) == "table" and receipt.variantKey or "")
            if key == "" then return false end
            local data = state.load(actor, request)
            if type(data) ~= "table" or data.unlockedShopItems[key] == nil then return true end
            data.unlockedShopItems[key] = nil
            local saved = state.save(actor, data, request)
            if saved ~= true then return false end
            instance.removed = instance.removed + 1
            return true
        end,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { added = self.added, removed = self.removed },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
