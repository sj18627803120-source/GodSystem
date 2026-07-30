GodSystemAdminPublicPort = GodSystemAdminPublicPort or {}

local Descriptor = GodSystemAdminPublicPort

Descriptor.id = "admin.config"
Descriptor.dependencies = { "feature.admin" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local feature = assert(dependencies["feature.admin"], "feature.admin dependency missing")
    for _, method in ipairs({
        "getSetting", "isFeatureEnabled", "getItemOverride", "getItemOverrides",
        "applyShopBuyPrice", "applyRecycleSellPrice", "applyTaskReward",
        "applyTaskPenalty", "getCategory", "isItemEnabled",
    }) do
        assert(type(feature[method]) == "function", "feature.admin method missing: " .. method)
    end
    local instance = { started = false, public = {} }
    for _, method in ipairs({
        "getSetting", "isFeatureEnabled", "getItemOverride", "getItemOverrides",
        "applyShopBuyPrice", "applyRecycleSellPrice", "applyTaskReward",
        "applyTaskPenalty", "getCategory", "isItemEnabled",
    }) do
        instance.public[method] = feature[method]
    end
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { target = "feature.admin" },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
