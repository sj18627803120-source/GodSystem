_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_Background"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Background then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_Background = true
    setfenv(1, runtimeEnvironment)

function sendStateSoon(player, data)
    data = data or playerData(player)
    local nowHour = nowHours()
    if nowHour - (data.lastServerPushHour or -999) < 0.02 then return end
    data.lastServerPushHour = nowHour
    sendState(player)
end

function updateKillRewards(player)
    if player and player.getZombieKills then
        Commands.syncKills(nil, nil, player, { clientKills = player:getZombieKills() })
    end
end

function updateTaskTimeouts(player)
    if GodSystemRuntimeConfig.isFeatureEnabled("EnableTasks") == false then return false end
    local data = playerData(player)
    local changed = false
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" and not isTurnInTask(task) and nowHours() <= (task.deadline or math.huge)
            and taskProgress(data, player, task) >= (task.target or 1) then task.completedAt = task.completedAt or nowHours() end
        if task.status == "active" and task.deadline and nowHours() > task.deadline and not task.completedAt then
            failTask(player, data, task, "TaskFailed")
            changed = true
        end
    end
    if changed then sendStateSoon(player, data) end
end

function updateHomeSafeZone(player)
    local data = playerData(player)
    local home = data.homeSystem or {}
    local safe = home.safeZone or {}
    if not home.home or safe.enabled ~= true or floor(safe.level, 0) <= 0 then return end
    local row = safeZoneLevelConfig(floor(safe.level, 0))
    if not row then return end
    local interval = math.max(0.05, n(GodSystemRuntimeConfig.get("HomeSafeZoneScanIntervalHours", 1), 1))
    if nowHours() - (safe.lastScanHours or 0) < interval then return end
    local removed = clearHomeSafeZone(player, data, false)
    if removed and removed > 0 then sendStateSoon(player, data) end
end

playerUpdateState = {}
shopInflationOnline = shopInflationOnline or {}
shopInflationCheckMs = shopInflationCheckMs or {}
taskAuthorityCheckMs = taskAuthorityCheckMs or {}

function updateShopInflationOnline(player, data)
    if not player or not data or not GodSystemShopInflation then return end
    local key, currentMs = userKey(player), GodSystemScheduler.nowMs()
    if shopInflationOnline[key] ~= player then
        GodSystemShopInflation.pause(data, GodSystemRuntimeConfig.Current, math.floor((nowHours and nowHours() or 0) * 60))
        shopInflationCheckMs[key] = nil
        data.taskMotion = nil
    end
    if currentMs - (shopInflationCheckMs[key] or 0) < 30000 then return end
    shopInflationCheckMs[key] = currentMs
    local minute = math.floor((nowHours and nowHours() or 0) * 60)
    GodSystemShopInflation.advance(data, GodSystemRuntimeConfig.Current or GodSystemRuntimeConfig.readSandbox(), minute, true)
    GodSystemShopInflation.sweep(data, 8)
    shopInflationOnline[key] = player
end

function prunePlayerUpdateState()
    local active = {}
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if players and players.size and players.get then
        for i = 0, players:size() - 1 do
            local onlinePlayer = players:get(i)
            if onlinePlayer then active[userKey(onlinePlayer)] = true end
        end
    end
    for key in pairs(playerUpdateState) do
        if not active[key] then
            playerUpdateState[key] = nil
            shopInflationCheckMs[key], taskAuthorityCheckMs[key] = nil, nil
            GodSystemScheduler.resetKey("server.player." .. key)
        end
    end
end

function onPlayerUpdate(player)
    if not player then return end
    local key = userKey(player)
    local nowMs = GodSystemScheduler.nowMs()
    if not GodSystemScheduler.due("server.player." .. key, 1000, nowMs) then return end
    if GodSystemScheduler.due("server.playerState.cleanup", 60000, nowMs) then
        prunePlayerUpdateState()
    end
    playerUpdateState[key] = { player = player }
    local data = playerData(player)
    updateShopInflationOnline(player, data)
    generateDailyTasks(data, false)
    updateHomeSafeZone(player)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
-- B42.20.4 skips OnPlayerUpdate for server remote players. Maintain their
-- carry state from a real-time gate, with no inventory traversal or UI work.
carryPushState = setmetatable({}, { __mode = "k" })
function onCarryTick()
    if not GodSystemScheduler.due("server.carry", 1000) then return end
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return end
    local root, active = store(), {}
    for i = 0, players:size() - 1 do
        local target = players:get(i)
        if target then
            local key = userKey(target)
            local data = root.players and root.players[key] or nil
            if data then
                active[key] = true
                updateShopInflationOnline(target, data)
                if checkPendingTeleport then checkPendingTeleport(target, data) end
            end
            if data and not target:isDead() then
                local currentMs = GodSystemScheduler.nowMs()
                if currentMs - (taskAuthorityCheckMs[key] or 0) >= 5000 then
                taskAuthorityCheckMs[key] = currentMs
                if updateTaskAuthoritativeProgress then updateTaskAuthoritativeProgress(target, data) end
                if updateTaskTimeouts and GodSystemRuntimeConfig then updateTaskTimeouts(target) end
                if Commands.syncKills then Commands.syncKills(nil, nil, target, {}) end
                end
            end
            if not target:isDead() then
                data = data or playerData(target)
                local level = GodSystemCarryCapacity.getLevel(data, target)
                GodSystemCarryCapacity.restore(target, level)
                local snapshot = GodSystemCarryCapacity.makeSnapshot(target, level)
                if carryPushState[target] ~= snapshot.revision then
                    sendServerCommand(target, MODULE, Protocol.S2C.CarryState, snapshot)
                    carryPushState[target] = snapshot.revision
                end
            end
        end
    end
    if cleanupTeleportRequests then cleanupTeleportRequests(active) end
    for key in pairs(shopInflationOnline) do
        if not active[key] then
            local data = root.players and root.players[key]
            if data and GodSystemShopInflation then GodSystemShopInflation.pause(data, GodSystemRuntimeConfig.Current, math.floor((nowHours and nowHours() or 0) * 60)) end
            shopInflationOnline[key] = nil
            shopInflationCheckMs[key], taskAuthorityCheckMs[key] = nil, nil
        end
    end
end
Events.OnTick.Add(onCarryTick)
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= MODULE or not player then return end
    diagnostics.handledCommands = (diagnostics.handledCommands or 0) + 1
    diagnostics.lastCommand = tostring(command or "")
    local fn = Commands[command]
    if fn then
        local ok, err = pcall(fn, module, command, player, args or {})
        if not ok then
            diagnostics.failedCommands = (diagnostics.failedCommands or 0) + 1
            diagnostics.lastError = tostring(err)
            print("[GodSystem] command '" .. tostring(command) .. "' failed: " .. tostring(err))
            errorMessage(player, tostring(err))
            sendState(player)
        end
    else
        diagnostics.failedCommands = (diagnostics.failedCommands or 0) + 1
        errorCode(player, "UnknownCommand", { tostring(command or "") })
        sendState(player)
    end
end)

return Commands
end
