_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Lifecycle"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Lifecycle then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Lifecycle = true
    setfenv(1, runtimeEnvironment)

function GodSystemUI.openShopHiddenManager(owner)
    if GodSystemUI.shopHiddenWindow then
        GodSystemUI.presentOverlay(GodSystemUI.shopHiddenWindow)
        GodSystemUI.shopHiddenWindow:populateItems()
        return GodSystemUI.shopHiddenWindow
    end
    local width, height = 760, 520
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.max(0, math.floor((screenW - width) / 2))
    local y = math.max(0, math.floor((screenH - height) / 2))
    local window = GodSystemShopHiddenWindow:new(x, y, width, height, owner or GodSystemUI.window)
    window:initialise()
    GodSystemUI.presentOverlay(window)
    GodSystemUI.shopHiddenWindow = window
    return window
end

function GodSystemUI.closeShopHiddenWindow()
    if GodSystemUI.shopHiddenWindow then GodSystemUI.shopHiddenWindow:close() end
end

function GodSystemUI.toggleWindow()
    if GodSystemUI.window then
        GodSystemUI.window:close()
        GodSystemUI.window = nil
        return
    end
    -- SandboxVars can change between sessions. Refresh the runtime snapshot
    -- before the window builds its navigation so SP-only entries are derived
    -- from the current session instead of a stale cached value.
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.readSandbox then
        pcall(GodSystemRuntimeConfig.readSandbox)
    end
    local data = GodSystemApp.services.runtime.getData()
    if GodSystemNetwork and GodSystemNetwork.requestState then
        GodSystemNetwork.requestState(true)
    end
    local win = (gsTheme().window or {})
    local baseW = win.baseWidth or win.fixedWidth or win.defaultWidth or 1240
    local baseH = win.baseHeight or win.fixedHeight or win.defaultHeight or 690
    local minScale = win.scaleMin or 0.60
    local maxScale = win.scaleMax or 1.50
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local fitScale = math.min(maxScale, math.max(minScale, (screenW - 32) / math.max(1, baseW)), math.max(minScale, (screenH - 32) / math.max(1, baseH)))
    local savedScale = tonumber(data.ui.windowScale) or fitScale
    local scale = gsClamp(savedScale, minScale, fitScale)
    local w = math.floor(baseW * scale + 0.5)
    local h = math.floor(baseH * scale + 0.5)
    local x = math.floor(tonumber(data.ui.windowX) or ((screenW / 2) - (w / 2)))
    local y = math.floor(tonumber(data.ui.windowY) or ((screenH / 2) - (h / 2)))
    x = gsClamp(x, 0, math.max(0, screenW - w))
    y = gsClamp(y, 0, math.max(0, screenH - h))
    local window = GodSystemWindow:new(x, y, w, h)
    window.uiScale = scale
    window:initialise()
    window:setScaledSize(scale)
    window:clampToScreen()
    window:addToUIManager()
    window:setVisible(true)
    GodSystemUI.window = window
    window:requestDeferredPopulate(1)
end

function GodSystemUI.openMode(mode)
    mode = tostring(mode or "tasks")
    if not GodSystemUI.window then
        GodSystemUI.toggleWindow()
    end
    local window = GodSystemUI.window
    if not window then
        return false
    end
    window:captureSelection()
    window.mode = mode
    window:updateModeButtonStyles()
    window:populateList()
    window:requestDeferredPopulate(1)
    return true
end

function GodSystemUI.toggleShortcutWindow(owner)
    if GodSystemUI.shortcutWindow then
        return GodSystemUI.presentOverlay(GodSystemUI.shortcutWindow)
    end
    local data = GodSystemApp.services.runtime.getData()
    local w, h = 280, 218
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.floor(tonumber(data.ui.shortcutX) or ((owner and owner.x or (screenW / 2)) + 40))
    local y = math.floor(tonumber(data.ui.shortcutY) or ((owner and owner.y or (screenH / 2)) + 60))
    x = gsClamp(x, 0, math.max(0, screenW - w))
    y = gsClamp(y, 0, math.max(0, screenH - h))
    local window = GodSystemShortcutWindow:new(x, y, w, h)
    window:initialise()
    GodSystemUI.presentOverlay(window)
    GodSystemUI.shortcutWindow = window
    return window
end

function GodSystemUI.isTaskTrackerVisible()
    return GodSystemUI.taskTracker ~= nil and GodSystemUI.taskTracker:getIsVisible() == true
end

function GodSystemUI.createTaskTracker()
    if GodSystemUI.taskTracker then
        local data = GodSystemApp.services.runtime.getData()
        local w = math.max(260, math.floor(tonumber(data.ui.taskTrackerW) or GodSystemUI.taskTracker.width or 340))
        local h = math.max(70, math.floor(tonumber(data.ui.taskTrackerH) or GodSystemUI.taskTracker.height or 92))
        gsSetBounds(GodSystemUI.taskTracker, nil, nil, w, h)
        GodSystemUI.taskTracker:setVisible(true)
        return GodSystemUI.taskTracker
    end
    local data = GodSystemApp.services.runtime.getData()
    local x = math.floor(tonumber(data.ui.taskTrackerX) or 40)
    local y = math.floor(tonumber(data.ui.taskTrackerY) or 270)
    local rows = gsGetActiveTaskRows()
    local defaultH = math.max(92, 34 + (math.max(1, #rows) * 22) + 8)
    local w = math.max(260, math.floor(tonumber(data.ui.taskTrackerW) or 340))
    local h = math.max(70, math.floor(tonumber(data.ui.taskTrackerH) or defaultH))
    local tracker = GodSystemTaskTracker:new(x, y, w, h)
    tracker:initialise()
    tracker:addToUIManager()
    tracker:setVisible(true)
    GodSystemUI.taskTracker = tracker
    return tracker
end

function GodSystemUI.toggleTaskTracker()
    local data = GodSystemApp.services.runtime.getData()
    if GodSystemUI.isTaskTrackerVisible() then
        GodSystemUI.taskTracker:close()
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTrackerOff", "Task tracker hidden"))
        return false
    end
    GodSystemUI.createTaskTracker()
    data.ui.taskTrackerVisible = true
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskTrackerOn", "Task tracker shown"))
    return true
end

function GodSystemUI.createFloatingButton()
    return GodSystemUI.ensureFloatingButton()
end

function GodSystemUI.ensureFloatingButton()
    local data = GodSystemApp.services.runtime.getData()
    local cfg = GodSystemConfig.FloatingButton
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local button, _, moved = GodSystemFloatingButtonLifecycle.ensure(
        GodSystemUI.floating,
        function(x, y, width, height)
            local created = GodSystemFloatingButton:new(data.ui.x or x or cfg.x, data.ui.y or y or cfg.y, width, height)
            created:initialise()
            return created
        end,
        data.ui.x or cfg.x,
        data.ui.y or cfg.y,
        cfg.width,
        cfg.height,
        screenWidth,
        screenHeight
    )
    if not button then return nil end
    GodSystemUI.floating = button
    if moved then
        data.ui.x = button.x
        data.ui.y = button.y
        GodSystemApp.services.runtime.save()
    end
    return button
end

function GodSystemUI.closeFloatingButton()
    local button = GodSystemUI.floating
    if button then
        if button.setVisible then button:setVisible(false) end
        if button.removeFromUIManager then button:removeFromUIManager() end
    end
    GodSystemUI.floating = nil
    GodSystemUI.lastFloatingButtonCheckMs = 0
end

function GodSystemUI.onFloatingButtonTick()
    if not (isIngameState and isIngameState()) then return end
    local now = gsNowMs()
    if now - (GodSystemUI.lastFloatingButtonCheckMs or 0) < GodSystemUI.FloatingButtonRefreshIntervalMs then return end
    GodSystemUI.lastFloatingButtonCheckMs = now
    GodSystemUI.ensureFloatingButton()
end

function GodSystemUI.onGameStart()
    GodSystemUI.lastFloatingButtonCheckMs = 0
    GodSystemUI.createFloatingButton()
    local data = GodSystemApp.services.runtime.getData()
    if data.ui.taskTrackerVisible == true then
        GodSystemUI.createTaskTracker()
    end
end

function GodSystemUI.onSessionEnd()
    if GodSystemPanelKey.isCapturing() then
        GodSystemPanelKey.cancelCapture("sessionEnded")
    end
    GodSystemUI.closeShopHiddenWindow()
    GodSystemUI.closeFloatingButton()
end

GodSystemPanelKey.registerToggle(function()
    GodSystemUI.toggleWindow()
end)

GodSystemPanelKey.registerRangeRecycle(function()
    local player = getPlayer and getPlayer() or nil
    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    local service = GodSystemApp.services.rangeRecycle
    local model = service:getViewModel(playerNum)
    service:execute(playerNum, model.status == "running" and "cancel" or "start", {}, function(result)
        if result and result.ok == false then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("NotifyMP_" .. tostring(result.code), tostring(result.code)))
        end
    end)
end)

if Events.OnGameStart then
    Events.OnGameStart.Remove(GodSystemUI.onGameStart)
    Events.OnGameStart.Add(GodSystemUI.onGameStart)
end
if Events.OnTick then
    Events.OnTick.Remove(GodSystemUI.onFloatingButtonTick)
    Events.OnTick.Add(GodSystemUI.onFloatingButtonTick)
end
if Events.OnDisconnect then
    Events.OnDisconnect.Remove(GodSystemUI.onSessionEnd)
    Events.OnDisconnect.Add(GodSystemUI.onSessionEnd)
end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Remove(GodSystemUI.onSessionEnd)
    Events.OnMainMenuEnter.Add(GodSystemUI.onSessionEnd)
end
end
