require "GodSystem/Platform/Progression/Support"

GodSystemAdminPermissionsPlatform = GodSystemAdminPermissionsPlatform or {}

local Descriptor = GodSystemAdminPermissionsPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "admin.permissions"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local ALLOWED = {
    admin = true,
    moderator = true,
    overseer = true,
    gm = true,
}

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local counters = { checks = 0, denied = 0 }

    local function canConfigure(actor)
        counters.checks = counters.checks + 1
        if type(binding.canConfigure) == "function" then
            local ok, value = pcall(binding.canConfigure, actor)
            if not ok or value ~= true then counters.denied = counters.denied + 1 return false end
            return true
        end
        local multiplayer = binding.multiplayer
        if multiplayer == nil then multiplayer = type(isClient) == "function" and isClient() == true end
        if multiplayer ~= true then return true end
        local access = tostring(Support.read(actor, { "getAccessLevel" }, "")):lower()
        local allowed = ALLOWED[access] == true
        if not allowed and type(actor and actor.isAccessLevel) == "function" then
            for _, label in ipairs({ "Admin", "Moderator", "Overseer", "GM" }) do
                local ok, value = pcall(actor.isAccessLevel, actor, label)
                if ok and value == true then allowed = true break end
            end
        end
        if not allowed then counters.denied = counters.denied + 1 end
        return allowed
    end

    return Support.lifecycle(Descriptor.id, { canConfigure = canConfigure }, counters)
end

return Descriptor
