require "TimedActions/ISBaseTimedAction"

ISGodSystemRangeRecycleWarmupAction = ISBaseTimedAction:derive("ISGodSystemRangeRecycleWarmupAction")

function ISGodSystemRangeRecycleWarmupAction:isValid()
    if not self.character then return false end
    local service = GodSystemApp and GodSystemApp.services and GodSystemApp.services.rangeRecycle or nil
    if not service then return false end
    local playerNum = self.character.getPlayerNum and self.character:getPlayerNum() or 0
    local model = service:getViewModel(playerNum)
    return model.status == "running" and model.cancelRequested ~= true
        and tostring(model.operationId or "") == tostring(self.operationId or "")
end

function ISGodSystemRangeRecycleWarmupAction:stop()
    local service = GodSystemApp and GodSystemApp.services and GodSystemApp.services.rangeRecycle or nil
    local playerNum = self.character and self.character.getPlayerNum and self.character:getPlayerNum() or 0
    local model = service and service:getViewModel(playerNum) or {}
    if service and model.status == "running" and model.cancelRequested ~= true
        and tostring(model.operationId or "") == tostring(self.operationId or "") then
        if service.requestCancel then
            service:requestCancel(playerNum, self.operationId)
        else
            service:execute(playerNum, "cancel", {})
        end
    end
    ISBaseTimedAction.stop(self)
end

function ISGodSystemRangeRecycleWarmupAction:perform()
    ISBaseTimedAction.perform(self)
end

function ISGodSystemRangeRecycleWarmupAction:complete()
    return true
end

function ISGodSystemRangeRecycleWarmupAction:getDuration()
    return 50
end

function ISGodSystemRangeRecycleWarmupAction:new(character, operationId)
    local o = ISBaseTimedAction.new(self, character)
    o.operationId = operationId
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = o:getDuration()
    return o
end

return ISGodSystemRangeRecycleWarmupAction
