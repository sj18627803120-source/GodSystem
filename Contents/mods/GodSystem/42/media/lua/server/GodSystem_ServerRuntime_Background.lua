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
    local data = playerData(player)
    local changed = false
    for i = 1, #(data.tasks or {}) do
        local task = data.tasks[i]
        if task.status == "active" and task.deadline and nowHours() > task.deadline and taskProgress(data, player, task) < (task.target or 1) then
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
    generateDailyTasks(data, false)
    updateHomeSafeZone(player)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
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
