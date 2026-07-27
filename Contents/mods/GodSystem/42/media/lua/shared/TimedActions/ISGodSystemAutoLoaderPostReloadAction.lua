require "TimedActions/ISBaseTimedAction"

ISGodSystemAutoLoaderPostReloadAction = ISBaseTimedAction:derive("ISGodSystemAutoLoaderPostReloadAction")

function ISGodSystemAutoLoaderPostReloadAction:isValid()
    return self.character ~= nil
end

function ISGodSystemAutoLoaderPostReloadAction:perform()
    ISBaseTimedAction.perform(self)
end

function ISGodSystemAutoLoaderPostReloadAction:complete()
    if GodSystemAutoLoaderServer and GodSystemAutoLoaderServer.completePostReload then
        return GodSystemAutoLoaderServer.completePostReload(self.character, self.opId)
    end
    if GodSystemAutoLoaderClient and GodSystemAutoLoaderClient.completeLocalPostReload then
        return GodSystemAutoLoaderClient.completeLocalPostReload(self.character, self.opId)
    end
    return false
end

function ISGodSystemAutoLoaderPostReloadAction:getDuration()
    return 1
end

function ISGodSystemAutoLoaderPostReloadAction:new(character, opId)
    local o = ISBaseTimedAction.new(self, character)
    o.opId = opId
    o.stopOnWalk = false
    o.stopOnRun = false
    o.stopOnAim = false
    o.maxTime = 1
    return o
end
