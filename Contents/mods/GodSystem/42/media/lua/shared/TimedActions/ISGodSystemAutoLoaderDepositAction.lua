require "TimedActions/ISBaseTimedAction"
require "GodSystem_AutoLoader"
require "GodSystem_RuntimeMode"

ISGodSystemAutoLoaderDepositAction = ISBaseTimedAction:derive("ISGodSystemAutoLoaderDepositAction")

function ISGodSystemAutoLoaderDepositAction:loader()
    return GodSystemAutoLoader.findCarriedItem(self.character, self.loaderId)
end

function ISGodSystemAutoLoaderDepositAction:isValid()
    if self.character and self.character.getVehicle and self.character:getVehicle() then return false end
    return GodSystemAutoLoader.isLoader(self:loader())
end

function ISGodSystemAutoLoaderDepositAction:start()
    local loader = self:loader()
    if loader then
        loader:setJobType(getText("IGUI_GodSystem_AutoLoader_DepositAll"))
        loader:setJobDelta(0)
    end
end

function ISGodSystemAutoLoaderDepositAction:update()
    local loader = self:loader()
    if loader then loader:setJobDelta(self:getJobDelta()) end
end

function ISGodSystemAutoLoaderDepositAction:stop()
    local loader = self:loader()
    if loader then loader:setJobDelta(0) end
    if GodSystemAutoLoaderClient and GodSystemAutoLoaderClient.onDepositInterrupted then
        GodSystemAutoLoaderClient.onDepositInterrupted(self.loaderId, self.sessionId)
    end
    ISBaseTimedAction.stop(self)
end

function ISGodSystemAutoLoaderDepositAction:perform()
    local loader = self:loader()
    if loader then loader:setJobDelta(0) end
    ISBaseTimedAction.perform(self)
end

function ISGodSystemAutoLoaderDepositAction:complete()
    if GodSystemRuntimeMode.legacyBusinessEnabled() ~= true then
        if GodSystemModularServer and GodSystemModularServer.execute then
            return GodSystemModularServer.execute(
                "autoloader.depositBatch", {
                    sessionId = self.sessionId,
                    batchIndex = self.batchIndex,
                }, self.character, "autoloader.result")
        end
        if GodSystemAutoLoaderClient
            and GodSystemAutoLoaderClient.completeLocalDepositBatch
        then
            return GodSystemAutoLoaderClient.completeLocalDepositBatch(
                self.character, self.sessionId, self.batchIndex)
        end
        return false
    end
    if GodSystemAutoLoaderServer and GodSystemAutoLoaderServer.completeDepositBatch then
        return GodSystemAutoLoaderServer.completeDepositBatch(self.character, self.sessionId, self.batchIndex)
    end
    if GodSystemAutoLoaderClient and GodSystemAutoLoaderClient.completeLocalDepositBatch then
        return GodSystemAutoLoaderClient.completeLocalDepositBatch(self.character, self.sessionId, self.batchIndex)
    end
    return false
end

function ISGodSystemAutoLoaderDepositAction:getDuration()
    if self.character and self.character.isTimedActionInstant and self.character:isTimedActionInstant() then return 1 end
    local totalCount = self.totalCount
    local batchCount = self.batchCount
    if isServer and isServer() then
        local session = GodSystemAutoLoader.runtime.sessions[tostring(self.sessionId or "")]
        totalCount = session and #session.records or 0
        batchCount = session and session.batchCount or 1
    end
    local seconds = GodSystemAutoLoader.depositDurationSeconds(totalCount)
    return math.max(1, math.ceil((seconds * 50) / math.max(1, tonumber(batchCount) or 1)))
end

function ISGodSystemAutoLoaderDepositAction:new(character, loaderId, sessionId, batchIndex, batchCount, totalCount)
    local o = ISBaseTimedAction.new(self, character)
    o.loaderId = loaderId
    o.sessionId = sessionId
    o.batchIndex = batchIndex
    o.batchCount = batchCount
    o.totalCount = totalCount
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = o:getDuration()
    return o
end
