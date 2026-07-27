local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/client/?.lua;" .. package.path

GodSystem = {
    notices = {},
    text = function(key, fallback) return fallback or key end,
    notify = function(message) GodSystem.notices[#GodSystem.notices + 1] = message end,
}
package.preload.GodSystem_Core = function() return GodSystem end

local loader = { id = "loader-1" }
local testPlayer = { getPlayerNum = function() return 0 end }
local fillCalls = 0
local withdrawCalls = 0
local depositCompletions = 0

GodSystemAutoLoader = {
    MaxLoaders = 64,
    MaxMagazines = 256,
    itemId = function(item) return type(item) == "table" and item.id or nil end,
    nowMs = function() return 12345 end,
    safeCall = function(target, methodName, fallback, ...)
        if target and target[methodName] then return target[methodName](target, ...) end
        return fallback
    end,
    findCarriedItem = function(_, itemId) return tostring(itemId) == loader.id and loader or nil end,
    isLoader = function(item) return item == loader end,
    stateFor = function(item) return { loaderId = item.id, total = 9, ammo = {} } end,
    startDepositSession = function(_, loaderId)
        return { sessionId = "session-1", loaderId = tostring(loaderId), total = 1, batchCount = 1 }
    end,
    completeDepositBatch = function()
        depositCompletions = depositCompletions + 1
        return { stored = 1 }, nil, {}, false, {
            finished = true,
            sessionId = "session-1",
            loaderId = loader.id,
            stored = 1,
            skipped = 0,
            failed = 0,
        }
    end,
    fillMagazines = function()
        fillCalls = fillCalls + 1
        return { rounds = 3, magazines = 1, need = 3, remainingNeed = 0 }
    end,
    withdrawAmmo = function()
        withdrawCalls = withdrawCalls + 1
        return { requested = 2, created = 2 }
    end,
    getLoaders = function() return { loader }, false end,
}
package.preload.GodSystem_AutoLoader = function() return GodSystemAutoLoader end

ISGodSystemAutoLoaderDepositAction = {
    new = function(_, _, _, sessionId, batchIndex) return { sessionId = sessionId, batchIndex = batchIndex } end,
}
ISGodSystemAutoLoaderPostReloadAction = { new = function() return {} end }
package.preload["TimedActions/ISGodSystemAutoLoaderDepositAction"] = function() return ISGodSystemAutoLoaderDepositAction end
package.preload["TimedActions/ISGodSystemAutoLoaderPostReloadAction"] = function() return ISGodSystemAutoLoaderPostReloadAction end

ISReloadWeaponAction = { BeginAutomaticReload = function() return true end }
package.preload["TimedActions/ISReloadWeaponAction"] = function() return ISReloadWeaponAction end

local queued = {}
ISTimedActionQueue = {
    add = function(action) queued[#queued + 1] = action end,
    getTimedActionQueue = function() return { queue = {} } end,
}
package.preload["TimedActions/ISTimedActionQueue"] = function() return ISTimedActionQueue end

local function event() return { Add = function() end, Remove = function() end } end
Events = {
    OnGameStart = event(), OnServerCommand = event(), OnDisconnect = event(), OnMainMenuEnter = event(),
}
getPlayer = function() return testPlayer end
getSpecificPlayer = function() return testPlayer end
isClient = function() return false end
local networkCalls = 0
sendClientCommand = function() networkCalls = networkCalls + 1 end

local stateCallbacks = 0
local resultCallbacks = 0
GodSystemAutoLoaderUI = {
    loaderId = loader.id,
    onState = function() stateCallbacks = stateCallbacks + 1 end,
    onResult = function() resultCallbacks = resultCallbacks + 1 end,
}

local Client = require "GodSystem_AutoLoaderClient"
assert(Client.codeKey("DepositInterrupted") == "AutoLoader_DepositInterrupted",
    "deposit interruption must use its dedicated localization key")

assert(Client.requestState(loader, 0) == true and Client.states[loader.id].total == 9,
    "SP state requests must resolve the carried loader locally")
assert(stateCallbacks == 1 and networkCalls == 0, "SP state requests must not use the MP command bridge")

assert(Client.startDeposit(loader, 0) == true and #queued == 1,
    "SP deposit must create and queue the local timed action session")
assert(Client.queuedSessions["session-1"] == true and networkCalls == 0,
    "SP deposit session must be tracked without a network command")

assert(Client.completeLocalDepositBatch(testPlayer, "session-1", 1) == true,
    "SP deposit timed-action completion must settle locally")
assert(depositCompletions == 1 and Client.queuedSessions["session-1"] == nil,
    "SP deposit completion must clear the queued session")

assert(Client.manualFill(loader, 0) == true and fillCalls == 1,
    "SP manual fill must use the shared authoritative settlement")
assert(Client.withdraw(loader, "Base.Bullets9mm", 2, 0) == true and withdrawCalls == 1,
    "SP withdraw must create real rounds through the shared settlement")
assert(Client.completeLocalPostReload(testPlayer, "gsa-12345-1-0") == true and fillCalls == 2,
    "SP quick-reload post action must fill magazines locally")
assert(networkCalls == 0 and resultCallbacks >= 4,
    "all SP operations must complete locally and publish UI results")

print("Test-GodSystemV11672ClientRuntime passed")
