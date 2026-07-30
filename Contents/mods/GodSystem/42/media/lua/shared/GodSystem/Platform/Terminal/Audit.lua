require "GodSystem/Platform/Terminal/Support"

GodSystemTerminalAuditPlatform = GodSystemTerminalAuditPlatform or {}

local Descriptor = GodSystemTerminalAuditPlatform
local Support = GodSystemTerminalPlatformSupport

Descriptor.id = "terminal.audit"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local scopedState = assert(
        context.state and type(context.state.get) == "function"
            and context.state or nil,
        "terminal.audit context.state missing")
    local root = scopedState:get()
    root.rows = type(root.rows) == "table" and root.rows or {}
    local counters = { records = 0, failures = 0 }
    local public = {}

    function public.record(actor, action, data, request)
        local row = {
            actor = Support.identity(actor, binding),
            action = tostring(action or ""),
            data = Support.copy(data),
            operationId = request and request.operationId or nil,
        }
        root.rows[#root.rows + 1] = row
        while #root.rows > 200 do table.remove(root.rows, 1) end
        if type(binding.record) == "function" then
            local called = pcall(binding.record, row)
            if not called then counters.failures = counters.failures + 1 end
        end
        counters.records = counters.records + 1
        return true
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
