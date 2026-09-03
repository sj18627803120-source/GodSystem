require "TimedActions/ISBaseTimedAction"

ISGodSystemRangeRecycleChannelAction = ISBaseTimedAction:derive("ISGodSystemRangeRecycleChannelAction")

local function rangeService()
    return GodSystemApp and GodSystemApp.services and GodSystemApp.services.rangeRecycle or nil
end

local function playerNumber(character)
    return character and character.getPlayerNum and character:getPlayerNum() or 0
end

local function matchingModel(action)
    local service = rangeService()
    local model = service and service:getViewModel(playerNumber(action.character)) or {}
    local matching = model.status == "running"
        and tostring(model.operationId or "") == tostring(action.operationId or "")
    return service, model, matching
end

local function requestCancel(action)
    local service, model, matching = matchingModel(action)
    if not service or not matching or model.cancelRequested == true then return end
    local playerNum = playerNumber(action.character)
    if service.requestCancel then
        service:requestCancel(playerNum, action.operationId)
    else
        service:execute(playerNum, "cancel", {})
    end
end

local function localizedJobType()
    local key = "IGUI_GodSystem_RangeRecycle_ChannelJob"
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key then return value end
    end
    local runtime = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime or nil
    return runtime and runtime.text and runtime.text("RangeRecycle_ChannelJob", "Range recycle") or "Range recycle"
end

function ISGodSystemRangeRecycleChannelAction:isValid()
    local _, model, matching = matchingModel(self)
    return self.character ~= nil and matching and model.cancelRequested ~= true
end

function ISGodSystemRangeRecycleChannelAction:stop()
    requestCancel(self)
    ISBaseTimedAction.stop(self)
end

function ISGodSystemRangeRecycleChannelAction:perform()
    ISBaseTimedAction.perform(self)
end

function ISGodSystemRangeRecycleChannelAction:complete()
    return true
end

function ISGodSystemRangeRecycleChannelAction:new(character, operationId)
    local o = ISBaseTimedAction.new(self, character)
    o.operationId = operationId
    o.forceProgressBar = true
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.jobType = localizedJobType()
    o.maxTime = -1
    return o
end

return ISGodSystemRangeRecycleChannelAction
