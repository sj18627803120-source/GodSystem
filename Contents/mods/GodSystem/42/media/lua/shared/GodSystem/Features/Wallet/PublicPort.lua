GodSystemWalletPublicPort = GodSystemWalletPublicPort or {}

local Descriptor = GodSystemWalletPublicPort

Descriptor.id = "wallet"
Descriptor.dependencies = { "feature.wallet" }
Descriptor.stateVersion = 1

function Descriptor.create(dependencies)
    local wallet = assert(dependencies["feature.wallet"], "feature.wallet dependency missing")
    local instance = {
        started = false,
        public = wallet,
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started,
            code = self.started and "healthy" or "stopped",
            data = { target = "feature.wallet" },
            moduleId = Descriptor.id,
        }
    end
    return instance
end

return Descriptor
