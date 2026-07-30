require "GodSystem/Platform/Progression/Support"

GodSystemUpgradesTasksPlatform = GodSystemUpgradesTasksPlatform or {}

local Descriptor = GodSystemUpgradesTasksPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "upgrades.tasks"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local counters = { added = 0, rolledBack = 0, failures = 0 }
    local public = {}

    function public.addOpen(actor, data, request)
        if type(data) ~= "table" then return false, "stateInvalid" end
        if type(binding.createOpenTask) ~= "function" then return false, "taskFactoryUnavailable" end
        local ok, taskOrCode = pcall(binding.createOpenTask, actor, data, request)
        if not ok or type(taskOrCode) ~= "table" then
            counters.failures = counters.failures + 1
            return false, ok and (taskOrCode or "taskCreationFailed") or "taskFactoryFailed"
        end
        taskOrCode.status = tostring(taskOrCode.status or "open")
        if taskOrCode.status ~= "open" then return false, "taskStatusInvalid" end
        data.tasks = type(data.tasks) == "table" and data.tasks or {}
        data.tasks[#data.tasks + 1] = taskOrCode
        counters.added = counters.added + 1
        return true, {
            task = taskOrCode,
            tasks = data.tasks,
            index = #data.tasks,
            taskId = taskOrCode.id,
        }
    end

    function public.rollback(_, receipt)
        local tasks = type(receipt) == "table" and receipt.tasks or nil
        if type(receipt) ~= "table" or type(tasks) ~= "table" then
            counters.failures = counters.failures + 1
            return false, "receiptInvalid"
        end
        for index = #tasks, 1, -1 do
            local task = tasks[index]
            if task == receipt.task
                or (receipt.taskId ~= nil and tostring(task and task.id or "") == tostring(receipt.taskId)) then
                table.remove(tasks, index)
                counters.rolledBack = counters.rolledBack + 1
                return true
            end
        end
        return true
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
