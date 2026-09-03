_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Components"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Components then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Components = true
    setfenv(1, runtimeEnvironment)

function gsSetLabel(label, text)
    if label then
        label.name = text or ""
    end
end

function gsSyncScrollingListGeometry(element)
    if not element or not element.vscroll then
        return
    end
    local vscroll = element.vscroll
    local scrollW = math.floor(tonumber(element.width) or (element.getWidth and element:getWidth()) or 0)
    local scrollH = math.floor(tonumber(element.height) or (element.getHeight and element:getHeight()) or 0)
    local scrollX = math.max(0, scrollW - 16)
    if vscroll.setX then
        vscroll:setX(scrollX)
    else
        vscroll.x = scrollX
    end
    if vscroll.setY then
        vscroll:setY(0)
    else
        vscroll.y = 0
    end
    if vscroll.setHeight then
        vscroll:setHeight(scrollH)
    else
        vscroll.height = scrollH
    end
    if vscroll.updatePos then
        vscroll:updatePos()
    end
end

gsOriginalScrollingListPrerender = ISScrollingListBox.prerender

function gsSafeScrollingListPrerender(self)
    gsSyncScrollingListGeometry(self)
    gsOriginalScrollingListPrerender(self)
    gsSyncScrollingListGeometry(self)
end

function gsInstallSafeScrollingListPrerender(list)
    if not list then
        return
    end
    list.prerender = gsSafeScrollingListPrerender
    gsSyncScrollingListGeometry(list)
end

function gsSetBounds(element, x, y, width, height)
    if not element then
        return
    end
    if x ~= nil then
        element.x = x
        if element.setX then
            element:setX(x)
        end
    end
    if y ~= nil then
        element.y = y
        if element.setY then
            element:setY(y)
        end
    end
    if width ~= nil then
        element.width = width
        if element.setWidth then
            element:setWidth(width)
        end
    end
    if height ~= nil then
        element.height = height
        if element.setHeight then
            element:setHeight(height)
        end
    end
    gsSyncScrollingListGeometry(element)
end

function gsTrim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function gsMeasureText(font, text)
    text = tostring(text or "")
    if getTextManager then
        local ok, width = pcall(function() return getTextManager():MeasureStringX(font or UIFont.Small, text) end)
        if ok and width then
            return width
        end
    end
    return string.len(text) * 7
end

function gsClamp(value, minValue, maxValue)
    value = tonumber(value) or minValue or 0
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

function gsUtf8Chars(text)
    text = tostring(text or "")
    local chars = {}
    local i = 1
    local len = string.len(text)
    while i <= len do
        local b = string.byte(text, i) or 0
        local size = 1
        if b >= 240 then
            size = 4
        elseif b >= 224 then
            size = 3
        elseif b >= 192 then
            size = 2
        end
        table.insert(chars, string.sub(text, i, math.min(i + size - 1, len)))
        i = i + size
    end
    return chars
end

function gsJoinChars(chars, count)
    local parts = {}
    count = math.min(math.floor(count or 0), #chars)
    for i = 1, count do
        parts[i] = chars[i]
    end
    return table.concat(parts, "")
end

function gsTruncateText(text, font, maxWidth)
    text = tostring(text or "")
    maxWidth = math.max(0, math.floor(maxWidth or 0))
    if maxWidth <= 0 or text == "" then
        return ""
    end
    if gsMeasureText(font, text) <= maxWidth then
        return text
    end

    local suffix = "..."
    if gsMeasureText(font, suffix) > maxWidth then
        return ""
    end

    local chars = gsUtf8Chars(text)
    local low = 0
    local high = #chars
    local best = suffix
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local candidate = gsJoinChars(chars, mid) .. suffix
        if gsMeasureText(font, candidate) <= maxWidth then
            best = candidate
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return best
end

function gsWrapText(text, font, maxWidth)
    text = tostring(text or "")
    maxWidth = math.max(40, math.floor(maxWidth or 0))
    local lines = {}
    text = text:gsub("\r", "\n")
    text = text:gsub("%s*|%s*", "\n")
    for rawLine in string.gmatch(text .. "\n", "(.-)\n") do
        if rawLine == "" then
            table.insert(lines, "")
        else
            local chars = gsUtf8Chars(rawLine)
            local current = ""
            for i = 1, #chars do
                local candidate = current .. chars[i]
                if current ~= "" and gsMeasureText(font or UIFont.Small, candidate) > maxWidth then
                    table.insert(lines, current)
                    current = chars[i]
                else
                    current = candidate
                end
            end
            if current ~= "" then
                table.insert(lines, current)
            end
        end
    end
    if #lines == 0 then
        table.insert(lines, "")
    end
    return lines
end

function gsDrawTextCentre(ui, text, x, y, w, r, g, b, a, font)
    ui:drawTextCentre(text, x + (w / 2), y, r, g, b, a, font or UIFont.Small)
end

function gsTheme()
    return GodSystemUITheme or {}
end

function gsThemeColor(name, fallback)
    local theme = gsTheme()
    local colors = theme.colors or {}
    return colors[name] or fallback or { r = 1, g = 1, b = 1, a = 1 }
end

function gsColorRGBA(color, fallback)
    color = color or fallback or {}
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

function gsColorARGB(color, fallback)
    color = color or fallback or {}
    return color.a or 1, color.r or 1, color.g or 1, color.b or 1
end

function gsDrawRect(ui, x, y, width, height, color)
    local a, r, g, b = gsColorARGB(color)
    ui:drawRect(x, y, width, height, a, r, g, b)
end

function gsDrawRectBorder(ui, x, y, width, height, color)
    local a, r, g, b = gsColorARGB(color)
    ui:drawRectBorder(x, y, width, height, a, r, g, b)
end

function gsDrawText(ui, text, x, y, color, font)
    local r, g, b, a = gsColorRGBA(color)
    ui:drawText(tostring(text or ""), x, y, r, g, b, a, font or UIFont.Small)
end

function gsDrawTextRight(ui, text, x, y, width, color, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    local textW = gsMeasureText(font, text)
    gsDrawText(ui, text, x + math.max(0, (width or 0) - textW), y, color, font)
end

function gsDrawProgressBar(ui, x, y, width, height, value, maxValue, fillColor)
    value = math.max(0, tonumber(value) or 0)
    maxValue = math.max(1, tonumber(maxValue) or 1)
    local ratio = gsClamp(value / maxValue, 0, 1)
    gsDrawRect(ui, x, y, width, height, gsThemeColor("progressTrack"))
    if ratio > 0 then
        gsDrawRect(ui, x + 1, y + 1, math.max(1, math.floor((width - 2) * ratio)), math.max(1, height - 2), fillColor or gsThemeColor("progressFill"))
    end
    gsDrawRectBorder(ui, x, y, width, height, gsThemeColor("border"))
end

function gsSetButtonTitle(button, title)
    if not button then
        return
    end
    button.fullTitle = tostring(title or "")
    if button.setTitle then
        button:setTitle(button.fullTitle)
    end
end

function gsStyleButton(button, active)
    if not button then
        return
    end
    local bg = active and gsThemeColor("navActive") or (button.navTool and gsThemeColor("navTool") or gsThemeColor("button"))
    local border = active and gsThemeColor("borderStrong") or gsThemeColor("border")
    local hover = gsThemeColor("buttonHover")
    button.backgroundColor = { r = bg.r, g = bg.g, b = bg.b, a = bg.a }
    button.backgroundColorMouseOver = { r = hover.r, g = hover.g, b = hover.b, a = hover.a }
    button.borderColor = { r = border.r, g = border.g, b = border.b, a = border.a }
end

function gsStyleActionButton(button, variant)
    if not button then
        return
    end
    local colorName = "button"
    if variant == "primary" then
        colorName = "buttonPrimary"
    elseif variant == "danger" then
        colorName = "buttonDanger"
    end
    local bg = gsThemeColor(colorName)
    local border = variant == "primary" and gsThemeColor("green") or variant == "danger" and gsThemeColor("red") or gsThemeColor("border")
    local hover = gsThemeColor("buttonHover")
    button.backgroundColor = { r = bg.r, g = bg.g, b = bg.b, a = bg.a }
    button.backgroundColorMouseOver = { r = hover.r, g = hover.g, b = hover.b, a = hover.a }
    button.borderColor = { r = border.r, g = border.g, b = border.b, a = border.a }
end

function gsFormatTemplate(template, args)
    local text = tostring(template or "")
    args = args or {}
    for i = 1, #args do
        text = string.gsub(text, "{" .. tostring(i) .. "}", function()
            return tostring(args[i] or "")
        end)
    end
    return text
end

function gsNowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

function gsFormatCompactNumber(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    if value < 10000 then
        return tostring(value)
    end
    local units = {
        { size = 1000000000, suffix = "B" },
        { size = 1000000, suffix = "M" },
        { size = 1000, suffix = "K" },
    }
    for i = 1, #units do
        local unit = units[i]
        if value >= unit.size then
            local scaled = value / unit.size
            if scaled < 10 then
                local text = string.format("%.1f", scaled)
                text = string.gsub(text, "%.0$", "")
                return text .. unit.suffix
            end
            return tostring(math.floor(scaled)) .. unit.suffix
        end
    end
    return tostring(value)
end

function gsIsMultiplayer()
    if isClient and isClient() then
        return true
    end
    if isServer and isServer() then
        return true
    end
    -- The network marker is only a compatibility fallback for old B42 builds
    -- that do not expose the native side query to the UI Lua environment.
    return (isClient == nil and isServer == nil)
        and GodSystemNetwork ~= nil
        and GodSystemNetwork.isMultiplayer == true
end

function gsHasServerState()
    if not gsIsMultiplayer() then
        return true
    end
    if GodSystemNetwork and GodSystemNetwork.isStateReady then
        return GodSystemNetwork.isStateReady() == true
    end
    return GodSystemNetwork and GodSystemNetwork.hasServerState == true
end

GodSystemFloatingButton = ISPanel:derive("GodSystemFloatingButton")

function GodSystemFloatingButton:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    local shell = gsThemeColor("shellDeep")
    local primary = gsThemeColor("primary")
    o.backgroundColor = { r = shell.r, g = shell.g, b = shell.b, a = 0.94 }
    o.borderColor = { r = primary.r, g = primary.g, b = primary.b, a = 0.95 }
    o.iconTexture = getTexture and getTexture("media/textures/GodSystem_OpenIcon.png") or nil
    o.tooltip = GodSystemApp.services.runtime.text("FloatingButton_Tooltip", "Open Nexus Protocol")
    o.dragging = false
    o.moved = false
    return o
end

function GodSystemFloatingButton:prerender()
    ISPanel.prerender(self)
    local primary = gsThemeColor("primary")
    self:drawRectBorder(0, 0, self.width, self.height, primary.a, primary.r, primary.g, primary.b)
    if self.iconTexture and self.drawTextureScaled then
        local inset = 4
        self:drawTextureScaled(self.iconTexture, inset, inset, self.width - inset * 2, self.height - inset * 2, 1)
    else
        local textColor = gsThemeColor("text")
        gsDrawTextCentre(self, "GS", 0, math.max(4, math.floor((self.height - 18) / 2)), self.width, textColor.r, textColor.g, textColor.b, textColor.a, UIFont.Medium)
    end
end

function GodSystemFloatingButton:clampDragPosition(x, y)
    local screenW = getCore and getCore():getScreenWidth() or 0
    local screenH = getCore and getCore():getScreenHeight() or 0
    return gsClamp(x, 0, math.max(0, screenW - (self.width or 0))),
        gsClamp(y, 0, math.max(0, screenH - (self.height or 0)))
end

function GodSystemFloatingButton:onMouseDown(x, y)
    self.dragging = true
    self.moved = false
    self.downX = x
    self.downY = y
    self.startX = self.x
    self.startY = self.y
    self:setCapture(true)
    return true
end

function GodSystemFloatingButton:onMouseMove(dx, dy)
    if self.dragging then
        local nextX, nextY = self:clampDragPosition(getMouseX() - self.downX, getMouseY() - self.downY)
        self:setX(nextX)
        self:setY(nextY)
        if math.abs(self.x - self.startX) > 3 or math.abs(self.y - self.startY) > 3 then
            self.moved = true
        end
        return true
    end
    return false
end

function GodSystemFloatingButton:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        self:setCapture(false)
        local data = GodSystemApp.services.runtime.getData()
        data.ui.x = math.floor(self.x or 0)
        data.ui.y = math.floor(self.y or 0)
        GodSystemApp.services.runtime.save()
        if not self.moved then
            GodSystemUI.toggleWindow()
        end
        return true
    end
    return false
end

function GodSystemFloatingButton:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function GodSystemFloatingButton:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function gsGetActiveTaskRows()
    local rows = {}
    local data = GodSystemApp.services.runtime.getData()
    local tasks = TaskOrder.sortedCopy(data.tasks or {}, "active", GodSystemApp.services.runtime.getTaskTitle)
    for i = 1, #tasks do
        local task = tasks[i]
        if task and task.status == "active" then
            local target = math.max(1, math.floor(tonumber(task.target) or 1))
            local progress = math.min(GodSystemApp.services.runtime.getTaskDisplayProgress(task), target)
            local done = progress >= target
            local detail = tostring(progress) .. "/" .. tostring(target)
            if done then
                detail = detail .. " " .. GodSystemApp.services.runtime.text("TaskTracker_Done", "Ready")
            else
                detail = detail .. " " .. GodSystemApp.services.runtime.text("TaskTracker_Left", "Left") .. tostring(GodSystemApp.services.runtime.getRemainingHours(task)) .. "h"
            end
            table.insert(rows, {
                title = GodSystemApp.services.runtime.getTaskTitle(task),
                detail = detail,
            })
        end
    end
    return rows
end

GodSystemTaskTracker = ISPanel:derive("GodSystemTaskTracker")

function GodSystemTaskTracker:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = gsThemeColor("trackerBackground")
    o.borderColor = gsThemeColor("trackerBorder")
    o.dragging = false
    o.resizing = false
    o.minimumWidth = 260
    o.minimumHeight = 70
    o.resizeGripSize = 14
    return o
end

function GodSystemTaskTracker:enforceMinimumSize()
    local minW = self.minimumWidth or 260
    local minH = self.minimumHeight or 70
    if (self.width or 0) < minW then
        gsSetBounds(self, nil, nil, minW, nil)
    end
    if (self.height or 0) < minH then
        gsSetBounds(self, nil, nil, nil, minH)
    end
end

function GodSystemTaskTracker:prerender()
    ISPanel.prerender(self)
    self:enforceMinimumSize()
    local rows = gsGetActiveTaskRows()
    local rowH = 22
    local grip = self.resizeGripSize or 14
    local background = gsThemeColor("trackerBackground")
    local border = gsThemeColor("trackerBorder")
    local header = gsThemeColor("trackerHeader")
    local accent = gsThemeColor("trackerAccent")
    local text = gsThemeColor("trackerText")
    local dimText = gsThemeColor("trackerDimText")
    local rowColor = gsThemeColor("trackerRow")

    gsDrawRect(self, 0, 0, self.width, self.height, background)
    gsDrawRectBorder(self, 0, 0, self.width, self.height, border)
    gsDrawRect(self, 0, 0, self.width, 26, header)
    gsDrawText(self, GodSystemApp.services.runtime.text("TaskTracker_Title", "Task tracker"), 8, 6, accent, UIFont.Small)
    gsDrawText(self, "x", self.width - 18, 5, text, UIFont.Small)
    gsDrawRect(self, self.width - grip + 3, self.height - 4, grip - 5, 1, border)
    gsDrawRect(self, self.width - grip + 6, self.height - 8, grip - 8, 1, border)
    gsDrawRect(self, self.width - grip + 9, self.height - 12, grip - 11, 1, border)

    if #rows == 0 then
        gsDrawText(self, GodSystemApp.services.runtime.text("TaskTracker_Empty", "No active tasks"), 8, 36, dimText, UIFont.Small)
        return
    end

    local availableW = math.max(80, self.width - 16)
    local maxDetailW = 0
    for i = 1, #rows do
        maxDetailW = math.max(maxDetailW, gsMeasureText(UIFont.Small, rows[i].detail or ""))
    end
    local detailW = math.min(math.max(110, maxDetailW + 8), math.floor(availableW * 0.48))
    local titleW = math.max(60, availableW - detailW - 10)
    local maxRows = math.max(1, math.floor(((self.height or 0) - 38) / rowH))
    local visibleRows = math.min(#rows, maxRows)
    for i = 1, visibleRows do
        local y = 30 + ((i - 1) * rowH)
        local row = rows[i]
        if i % 2 == 0 then
            gsDrawRect(self, 4, y - 2, self.width - 8, rowH, rowColor)
        end
        gsDrawText(self, gsTruncateText(row.title or "", UIFont.Small, titleW), 8, y, text, UIFont.Small)
        gsDrawText(self, gsTruncateText(row.detail or "", UIFont.Small, detailW), self.width - 8 - detailW, y, dimText, UIFont.Small)
    end
    if visibleRows < #rows then
        gsDrawText(self, "...", self.width - 28, self.height - 20, dimText, UIFont.Small)
    end
end

function GodSystemTaskTracker:onMouseDown(x, y)
    local grip = self.resizeGripSize or 14
    if x >= self.width - grip and y >= self.height - grip then
        self.resizing = true
        self.resizeStartMouseX = getMouseX()
        self.resizeStartMouseY = getMouseY()
        self.resizeStartW = self.width
        self.resizeStartH = self.height
        return true
    end
    if x >= self.width - 24 and y <= 26 then
        self:close()
        return true
    end
    self.dragging = true
    self.downX = x
    self.downY = y
    return true
end

function GodSystemTaskTracker:onMouseMove(dx, dy)
    if self.resizing then
        local newW = (self.resizeStartW or self.width) + (getMouseX() - (self.resizeStartMouseX or getMouseX()))
        local newH = (self.resizeStartH or self.height) + (getMouseY() - (self.resizeStartMouseY or getMouseY()))
        local minW = self.minimumWidth or 260
        local minH = self.minimumHeight or 70
        if getCore then
            local core = getCore()
            if core then
                newW = math.min(newW, math.max(minW, core:getScreenWidth() - self.x - 8))
                newH = math.min(newH, math.max(minH, core:getScreenHeight() - self.y - 8))
            end
        end
        gsSetBounds(self, nil, nil, math.max(minW, math.floor(newW)), math.max(minH, math.floor(newH)))
        return true
    end
    if self.dragging then
        self:setX(getMouseX() - self.downX)
        self:setY(getMouseY() - self.downY)
        return true
    end
    return false
end

function GodSystemTaskTracker:onMouseUp(x, y)
    if self.resizing then
        self.resizing = false
        local data = GodSystemApp.services.runtime.getData()
        data.ui.taskTrackerX = self.x
        data.ui.taskTrackerY = self.y
        data.ui.taskTrackerW = math.floor(self.width or 300)
        data.ui.taskTrackerH = math.floor(self.height or 92)
        GodSystemApp.services.runtime.save()
        return true
    end
    if self.dragging then
        self.dragging = false
        local data = GodSystemApp.services.runtime.getData()
        data.ui.taskTrackerX = self.x
        data.ui.taskTrackerY = self.y
        data.ui.taskTrackerW = math.floor(self.width or 300)
        data.ui.taskTrackerH = math.floor(self.height or 92)
        GodSystemApp.services.runtime.save()
        return true
    end
    return false
end

function GodSystemTaskTracker:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function GodSystemTaskTracker:close()
    local data = GodSystemApp.services.runtime.getData()
    data.ui.taskTrackerVisible = false
    data.ui.taskTrackerX = self.x
    data.ui.taskTrackerY = self.y
    data.ui.taskTrackerW = math.floor(self.width or 300)
    data.ui.taskTrackerH = math.floor(self.height or 92)
    GodSystemApp.services.runtime.save()
    self:setVisible(false)
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
    if GodSystemUI.taskTracker == self then
        GodSystemUI.taskTracker = nil
    end
end

GodSystemShortcutWindow = ISCollapsableWindow:derive("GodSystemShortcutWindow")
GodSystemShortcutWindow.RefreshIntervalMs = 5000

function GodSystemShortcutWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = GodSystemApp.services.runtime.text("Shortcut_Title", "Shortcuts")
    o.resizable = false
    o.shortcutButtons = {}
    o.shortcutActionSignature = ""
    o.lastShortcutRefreshMs = 0
    return o
end

function GodSystemShortcutWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.shortcutButtons = {}
    self:refreshActions(true)
end

function GodSystemShortcutWindow:buildActionSignature(actions)
    actions = actions or self:getActions()
    local parts = {}
    for i = 1, #actions do
        local entry = actions[i] or {}
        parts[#parts + 1] = tostring(entry.action or "") .. ":" .. tostring(entry.label or "")
    end
    return table.concat(parts, "|")
end

function GodSystemShortcutWindow:clearShortcutButtons()
    local buttons = self.shortcutButtons or {}
    for i = 1, #buttons do
        local button = buttons[i]
        if button then
            button:setVisible(false)
            if self.removeChild then
                pcall(function() self:removeChild(button) end)
            elseif self.children then
                for childIndex = #self.children, 1, -1 do
                    if self.children[childIndex] == button then
                        table.remove(self.children, childIndex)
                        break
                    end
                end
            end
        end
    end
    self.shortcutButtons = {}
end

function GodSystemShortcutWindow:addShortcutButtons(buttons)
    local x = 12
    local y = 34
    local w = math.floor(((self.width or 260) - 36) / 2)
    local h = 30
    for i = 1, #buttons do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local button = ISButton:new(x + (col * (w + 12)), y + (row * (h + 10)), w, h, buttons[i].label, self, self.onShortcut)
        button.internal = buttons[i].action
        button:initialise()
        gsStyleButton(button, false)
        self:addChild(button)
        self.shortcutButtons[#self.shortcutButtons + 1] = button
    end
end

function GodSystemShortcutWindow:refreshActions(force)
    local buttons = self:getActions()
    local signature = self:buildActionSignature(buttons)
    if not force and signature == self.shortcutActionSignature then
        return false
    end
    self:clearShortcutButtons()
    self.shortcutActionSignature = signature
    self:addShortcutButtons(buttons)
    return true
end

function GodSystemShortcutWindow:refreshActionsIfDue(force)
    local now = gsNowMs()
    if not force and now - (self.lastShortcutRefreshMs or 0) < (GodSystemShortcutWindow.RefreshIntervalMs or 5000) then
        return false
    end
    self.lastShortcutRefreshMs = now
    return self:refreshActions(force)
end

function GodSystemShortcutWindow:update()
    if ISCollapsableWindow.update then
        ISCollapsableWindow.update(self)
    end
    self:refreshActionsIfDue(false)
end

function GodSystemShortcutWindow:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
end

function GodSystemShortcutWindow:onShortcut(button)
    if button and button.internal then
        self:performAction(button.internal)
    end
end

function GodSystemShortcutWindow:getActions()
    local actions = {}
    local home = GodSystemApp.services.runtime.getHomeSystem and GodSystemApp.services.runtime.getHomeSystem() or nil
    if home and home.home then
        actions[#actions + 1] = { action = "teleportHome", label = GodSystemApp.services.runtime.text("Shortcut_Home", "Home") }
    end
    if home and home.returnPoint then
        actions[#actions + 1] = { action = "return", label = GodSystemApp.services.runtime.text("Shortcut_Return", "Return") }
    end
    actions[#actions + 1] = { action = "depositAllCash", label = GodSystemApp.services.runtime.text("Shortcut_DepositAllCash", "Deposit cash") }
    return actions
end

function GodSystemShortcutWindow:finishShortcutCommand(sent)
    local window = GodSystemUI and GodSystemUI.window or nil
    if window and window.finishMultiplayerCommand then
        return window:finishMultiplayerCommand(sent)
    end
    if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.requestState then
        GodSystemNetwork.requestState(sent == false)
    end
    return sent ~= false
end

function GodSystemShortcutWindow:formatShortcutHomeSource(source)
    if type(source) == "table" then
        return GodSystemApp.services.runtime.formatPosition(source)
    end
    source = tostring(source or "")
    if source == "" then
        return GodSystemApp.services.runtime.text("Home_ReturnPoint", "Return point")
    end
    return source
end

function GodSystemShortcutWindow:getShortcutHomeConfirmMessage(action)
    local cost = GodSystemConfig.HomeTravelCost or 10
    local line = ""
    if action == "teleportHome" then
        line = GodSystemApp.services.runtime.text("Confirm_HomeTeleport", "You are teleporting home. Confirm?")
    elseif action == "return" then
        local home = GodSystemApp.services.runtime.getHomeSystem and GodSystemApp.services.runtime.getHomeSystem() or nil
        local source = self:formatShortcutHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystemApp.services.runtime.text("Confirm_HomeReturn", "You are returning to the departure point: ") .. tostring(source) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    end
    local player = getPlayer and getPlayer() or nil
    local pos = GodSystemApp.services.runtime.formatPosition((player and { x = player:getX(), y = player:getY(), z = player:getZ() }) or nil)
    return line .. "\n" .. GodSystemApp.services.runtime.text("Home_CurrentPosition", "Current: ") .. pos .. "\n" .. GodSystemApp.services.runtime.text("Trait_ConfirmCost", "Cost: ") .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
end

function GodSystemShortcutWindow:confirmShortcutHomeAction(action)
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer and getPlayer() or nil
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, self:getShortcutHomeConfirmMessage(action), true, self, self.onShortcutHomeConfirm, playerNum, { action = action })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        self:onShortcutHomeConfirm({ internal = "YES" }, { action = action })
    end
end

function GodSystemShortcutWindow:onShortcutHomeConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local action = payload and payload.action
    if action == "teleportHome" or action == "return" then
        self:finishShortcutCommand(GodSystemApp.services.runtime.performHomeAction(action))
    end
end

function GodSystemShortcutWindow:performAction(action)
    action = tostring(action or "")
    local home = GodSystemApp.services.runtime.getHomeSystem and GodSystemApp.services.runtime.getHomeSystem() or nil
    if action == "teleportHome" then
        if not (home and home.home) then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNotSet", "Home is not set"))
            return false
        end
        self:confirmShortcutHomeAction("teleportHome")
        return true
    elseif action == "return" then
        if not (home and home.returnPoint) then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNoReturn", "No return point"))
            return false
        end
        self:confirmShortcutHomeAction("return")
        return true
    elseif action == "depositAllCash" then
        return self:finishShortcutCommand(GodSystemApp.services.runtime.performBankAction("depositAllCash"))
    end
    return false
end

function GodSystemShortcutWindow:close()
    local data = GodSystemApp.services.runtime.getData()
    data.ui.shortcutX = math.floor(self.x or 0)
    data.ui.shortcutY = math.floor(self.y or 0)
    GodSystemApp.services.runtime.save()
    self:setVisible(false)
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
    if GodSystemUI.shortcutWindow == self then
        GodSystemUI.shortcutWindow = nil
    end
end

GodSystemSecretGrantDialog = ISCollapsableWindow:derive("GodSystemSecretGrantDialog")

function GodSystemSecretGrantDialog:new(x, y, width, height, owner)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = "GodSystem"
    o.owner = owner
    o.resizable = false
    return o
end

function GodSystemSecretGrantDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.entry = ISTextEntryBox:new("", 16, 42, self.width - 32, 26)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    self:addChild(self.entry)

    self.confirmButton = ISButton:new(16, 82, 96, 28, "OK", self, self.onConfirm)
    self.confirmButton:initialise()
    gsStyleButton(self.confirmButton, false)
    self:addChild(self.confirmButton)

    self.cancelButton = ISButton:new(self.width - 112, 82, 96, 28, "Cancel", self, self.onCancel)
    self.cancelButton:initialise()
    gsStyleButton(self.cancelButton, false)
    self:addChild(self.cancelButton)
end

function GodSystemSecretGrantDialog:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
end

function GodSystemSecretGrantDialog:onConfirm()
    local text = ""
    if self.entry and self.entry.getInternalText then
        text = self.entry:getInternalText() or ""
    end
    if gsTrim(text) ~= "12130" then
        GodSystemApp.services.runtime.notify("Code error")
        self:onCancel()
        return
    end
    local sent = true
    if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.send then
        sent = GodSystemNetwork.send("debugGrant", { code = "12130" })
    else
        sent = GodSystemApp.services.runtime.addPoints(10000, GodSystemApp.services.runtime.text("Reason_Debug", "Debug"))
    end
    if self.owner and self.owner.finishMultiplayerCommand then
        self.owner:finishMultiplayerCommand(sent)
    end
    self:onCancel()
end

function GodSystemSecretGrantDialog:onCancel()
    self:setVisible(false)
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
end

GodSystemBankAmountDialog = ISCollapsableWindow:derive("GodSystemBankAmountDialog")

function GodSystemBankAmountDialog:new(x, y, width, height, owner, payload)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = (payload and payload.title) or GodSystemApp.services.runtime.text("Bank_AmountTitle", "Bank amount")
    o.owner = owner
    o.payload = payload or {}
    o.resizable = false
    return o
end

function GodSystemBankAmountDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.messageLabel = ISLabel:new(16, 36, 20, tostring(self.payload.message or ""), 0.9, 0.9, 0.86, 1, UIFont.Small, true)
    self.messageLabel:initialise()
    self:addChild(self.messageLabel)

    self.entry = ISTextEntryBox:new("", 16, 62, self.width - 32, 26)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    self:addChild(self.entry)

    self.confirmButton = ISButton:new(16, 104, 96, 28, GodSystemApp.services.runtime.text("Btn_Confirm", "Confirm"), self, self.onConfirm)
    self.confirmButton:initialise()
    gsStyleButton(self.confirmButton, false)
    self:addChild(self.confirmButton)

    self.cancelButton = ISButton:new(self.width - 112, 104, 96, 28, GodSystemApp.services.runtime.text("Btn_Cancel", "Cancel"), self, self.onCancel)
    self.cancelButton:initialise()
    gsStyleButton(self.cancelButton, false)
    self:addChild(self.cancelButton)
end

function GodSystemBankAmountDialog:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
end

function GodSystemBankAmountDialog:onConfirm()
    local text = ""
    if self.entry and self.entry.getInternalText then
        text = self.entry:getInternalText() or ""
    end
    text = gsTrim(text)
    local amount = math.floor(tonumber(text) or 0)
    if amount <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvalidAmount", "Enter a valid amount"))
        return
    end
    local payload = self.payload or {}
    local sent = false
    if payload.kind == "attribute" then
        sent = GodSystemApp.services.runtime.performAttributePurchase(payload.perkIndex, payload.mode, amount)
    else
        sent = GodSystemApp.services.runtime.performBankAction(payload.action, amount, payload.termId, payload.entryId)
    end
    if self.owner and self.owner.finishMultiplayerCommand then
        self.owner:finishMultiplayerCommand(sent)
    end
    self:onCancel(payload.kind == "attribute" and sent ~= false)
end

function GodSystemBankAmountDialog:onCancel(preserveActionSelection)
    local payload = self.payload or {}
    if preserveActionSelection ~= true and payload.kind == "attribute"
        and self.owner and self.owner.clearPendingActionSelection then
        self.owner:clearPendingActionSelection()
    end
    self:setVisible(false)
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
end

GodSystemShopHiddenWindow = ISCollapsableWindow:derive("GodSystemShopHiddenWindow")

function GodSystemShopHiddenWindow:new(x, y, width, height, owner)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = GodSystemApp.services.runtime.text("ShopHidden_Title", "Hidden shop items")
    o.owner = owner
    o.categoryKey = "all"
    o.statusFilter = "all"
    o.searchText = ""
    o.selectedVariantKey = nil
    o.selectedVariantKeys = {}
    o.selectionAnchorVariantKey = nil
    o.waitingForServer = false
    o.lastStateSerial = GodSystemNetwork and GodSystemNetwork.stateSerial or 0
    o.resizable = false
    return o
end

function GodSystemShopHiddenWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local margin = 12
    local top = 30
    local filterH = 30
    local buttonH = 34

    self.categoryButton = ISButton:new(margin, top, 190, filterH, "", self, self.onCategoryButton)
    self.categoryButton:initialise()
    gsStyleActionButton(self.categoryButton, false)
    self:addChild(self.categoryButton)

    self.statusButton = ISButton:new(210, top, 170, filterH, "", self, self.onStatusButton)
    self.statusButton:initialise()
    gsStyleActionButton(self.statusButton, false)
    self:addChild(self.statusButton)

    self.searchBox = ISTextEntryBox:new("", 388, top, self.width - 400, filterH)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.font = UIFont.Small
    self.searchBox.target = self
    self.searchBox.onTextChange = function(entry) self:onSearchChange(entry) end
    self:addChild(self.searchBox)

    self.list = ISScrollingListBox:new(margin, top + filterH + 10, self.width - (margin * 2), self.height - top - filterH - buttonH - 38)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 32
    self.list.doDrawItem = function(list, y, row, alt) return self:drawItem(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onListMouseDown)
    local originalListMouseDown = self.list.onMouseDown
    self.list.onMouseDown = function(list, x, y)
        list.gsCheckboxClick = x >= 6 and x <= 24
        return originalListMouseDown(list, x, y)
    end
    gsInstallSafeScrollingListPrerender(self.list)
    self:addChild(self.list)

    local actionY = self.height - buttonH - 12
    self.hideButton = ISButton:new(margin, actionY, 150, buttonH, GodSystemApp.services.runtime.text("ShopHidden_Add", "Hide"), self, self.onHide)
    self.hideButton:initialise()
    gsStyleActionButton(self.hideButton, "primary")
    self:addChild(self.hideButton)

    self.showButton = ISButton:new(172, actionY, 150, buttonH, GodSystemApp.services.runtime.text("ShopHidden_Remove", "Show"), self, self.onShow)
    self.showButton:initialise()
    gsStyleActionButton(self.showButton, false)
    self:addChild(self.showButton)

    self.deleteButton = ISButton:new(332, actionY, 150, buttonH, GodSystemApp.services.runtime.text("ShopHidden_Delete", "Delete listing"), self, self.onDelete)
    self.deleteButton:initialise()
    gsStyleActionButton(self.deleteButton, false)
    self:addChild(self.deleteButton)

    self.selectionLabel = ISLabel:new(490, actionY + 9, 18, "", 0.62, 0.76, 0.82, 1, UIFont.Small, true)
    self.selectionLabel:initialise()
    self:addChild(self.selectionLabel)

    self.closeButton = ISButton:new(self.width - 132, actionY, 120, buttonH, GodSystemApp.services.runtime.text("ShopHidden_Close", "Close"), self, self.close)
    self.closeButton:initialise()
    gsStyleActionButton(self.closeButton, false)
    self:addChild(self.closeButton)

    self:populateItems()
end

function GodSystemShopHiddenWindow:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
    self:updateButtons()
end

function GodSystemShopHiddenWindow:drawItem(list, y, row, alt)
    local data = row and row.item or nil
    local color = data and data.hidden == true and gsThemeColor("dimText") or gsThemeColor("text")
    local background = alt and gsThemeColor("panel") or gsThemeColor("panelDeep")
    gsDrawRect(list, 0, y, list.width, list.itemheight - 1, background)
    if list.selected == row.index then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("rowSelect"))
    end
    if data and data.variantKey then
        local selected = self.selectedVariantKeys and self.selectedVariantKeys[tostring(data.variantKey)] == true
        gsDrawRectBorder(list, 8, y + 10, 12, 12, gsThemeColor("borderStrong"))
        if selected then gsDrawRect(list, 10, y + 12, 8, 8, gsThemeColor("gold")) end
    end
    gsDrawText(list, tostring(row and row.text or ""), 28, y + 8, color, UIFont.Small)
    return y + list.itemheight
end

function GodSystemShopHiddenWindow:getSelected()
    local index = self.list and math.floor(tonumber(self.list.selected) or 0) or 0
    local row = index > 0 and self.list.items[index] or nil
    return row and row.item or nil
end

function GodSystemShopHiddenWindow:listStateContext()
    return table.concat({
        "shopHidden",
        tostring(self.categoryKey or "all"),
        tostring(self.statusFilter or "all"),
        tostring(self.searchText or ""),
    }, "\30")
end

function GodSystemShopHiddenWindow:captureListState()
    if not ListState then return nil end
    return ListState.capture(self.list, self:listStateContext(), function(payload)
        return payload and payload.variantKey or nil
    end)
end

function GodSystemShopHiddenWindow:visibleVariantKeys()
    local result = {}
    for i = 1, #(self.list and self.list.items or {}) do
        local payload = self.list.items[i] and self.list.items[i].item or nil
        if payload and payload.variantKey then result[#result + 1] = tostring(payload.variantKey) end
    end
    return result
end

function GodSystemShopHiddenWindow:clearSelectedVariants()
    for key in pairs(self.selectedVariantKeys or {}) do self.selectedVariantKeys[key] = nil end
    self.selectedVariantKey = nil
    self.selectionAnchorVariantKey = nil
end

function GodSystemShopHiddenWindow:applyVariantSelection(key, checkboxClick)
    key = key and tostring(key) or nil
    if not key then return end
    self.selectedVariantKeys = self.selectedVariantKeys or {}
    local keys = self:visibleVariantKeys()
    local function clear()
        for selected in pairs(self.selectedVariantKeys) do self.selectedVariantKeys[selected] = nil end
    end
    local ctrl = Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LCONTROL) or isKeyDown(Keyboard.KEY_RCONTROL))
    local shift = Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
    if shift and self.selectionAnchorVariantKey then
        local first, last
        for i = 1, #keys do
            if keys[i] == tostring(self.selectionAnchorVariantKey) then first = i end
            if keys[i] == key then last = i end
        end
        if first and last then
            if not ctrl then clear() end
            for i = math.min(first, last), math.max(first, last) do self.selectedVariantKeys[keys[i]] = true end
        else
            self.selectedVariantKeys[key] = true
        end
    elseif ctrl or checkboxClick then
        self.selectedVariantKeys[key] = self.selectedVariantKeys[key] ~= true and true or nil
        self.selectionAnchorVariantKey = key
    else
        clear()
        self.selectedVariantKeys[key] = true
        self.selectionAnchorVariantKey = key
    end
    self.selectedVariantKey = key
end

function GodSystemShopHiddenWindow:selectedVariantRows(targetHidden)
    local result = {}
    local seen = {}
    for i = 1, #(self.list and self.list.items or {}) do
        local payload = self.list.items[i] and self.list.items[i].item or nil
        local key = payload and payload.variantKey and tostring(payload.variantKey) or nil
        if key and self.selectedVariantKeys and self.selectedVariantKeys[key] == true and not seen[key]
            and (targetHidden == nil or payload.hidden == targetHidden) then
            seen[key] = true
            result[#result + 1] = payload
        end
    end
    return result
end

function GodSystemShopHiddenWindow:pruneSelectedVariants()
    local valid = {}
    for i = 1, #(self.list and self.list.items or {}) do
        local payload = self.list.items[i] and self.list.items[i].item or nil
        if payload and payload.variantKey then valid[tostring(payload.variantKey)] = true end
    end
    for key in pairs(self.selectedVariantKeys or {}) do
        if not valid[key] then self.selectedVariantKeys[key] = nil end
    end
    if self.selectedVariantKey and not valid[tostring(self.selectedVariantKey)] then self.selectedVariantKey = nil end
    if self.selectionAnchorVariantKey and not valid[tostring(self.selectionAnchorVariantKey)] then self.selectionAnchorVariantKey = nil end
end

function GodSystemShopHiddenWindow:onListMouseDown(row)
    local data = row and (row.item or row) or self:getSelected()
    local checkboxClick = self.list and self.list.gsCheckboxClick == true
    if self.list then self.list.gsCheckboxClick = nil end
    if data and data.variantKey then self:applyVariantSelection(data.variantKey, checkboxClick) end
    self:updateButtons()
end

function GodSystemShopHiddenWindow:updateButtons()
    local row = self:getSelected()
    local blocked = self.waitingForServer == true
    local visibleRows = self:selectedVariantRows(false)
    local hiddenRows = self:selectedVariantRows(true)
    local selectedCount = #visibleRows + #hiddenRows
    self.hideButton.enable = not blocked and #visibleRows > 0
    self.showButton.enable = not blocked and #hiddenRows > 0
    self.deleteButton.enable = not blocked and row ~= nil and row.empty ~= true
    gsSetLabel(self.selectionLabel, GodSystemApp.services.runtime.text("ShopHidden_SelectedCount", "Selected: {1}"):gsub("{1}", tostring(selectedCount)))
end

function GodSystemShopHiddenWindow:statusLabel()
    if self.statusFilter == "visible" then return GodSystemApp.services.runtime.text("ShopHidden_FilterVisible", "Visible") end
    if self.statusFilter == "hidden" then return GodSystemApp.services.runtime.text("ShopHidden_FilterHidden", "Hidden") end
    return GodSystemApp.services.runtime.text("ShopHidden_FilterAll", "All")
end

function GodSystemShopHiddenWindow:categoryLabel()
    if self.categoryKey == "all" then return GodSystemApp.services.runtime.text("ShopHidden_FilterAll", "All") end
    for i = 1, #(self.categories or {}) do
        if self.categories[i].key == self.categoryKey then return self.categories[i].label end
    end
    return self.categoryKey
end

function GodSystemShopHiddenWindow:matches(row, category)
    if self.categoryKey ~= "all" and category.key ~= self.categoryKey then return false end
    if self.statusFilter == "visible" and row.hidden == true then return false end
    if self.statusFilter == "hidden" and row.hidden ~= true then return false end
    local query = string.lower(gsTrim(self.searchText or ""))
    if query == "" then return true end
    local haystack = table.concat({
        tostring(row.label or ""),
        tostring(row.fullType or ""),
        tostring(category.key or ""),
        tostring(category.label or ""),
        tostring(row.worldSprite or ""),
    }, " ")
    return string.find(string.lower(haystack), query, 1, true) ~= nil
end

function GodSystemShopHiddenWindow:populateItems(preserveState)
    if not self.list then return end
    local listState = preserveState ~= false and self:captureListState() or nil
    self.list:clear()
    self.list.selected = 0
    self.list:setScrollHeight(0)
    self.list.smoothScrollTargetY = nil
    self.list.smoothScrollY = nil
    local rows = GodSystemApp.services.runtime.getUnlockedShopItemsList(true)
    local categories, categoryMap = {}, {}
    for i = 1, #rows do
        local category = GodSystemApp.services.runtime.getShopPrimaryCategory(rows[i])
        if not categoryMap[category.key] then
            categoryMap[category.key] = true
            categories[#categories + 1] = category
        end
    end
    table.sort(categories, function(a, b) return tostring(a.label) < tostring(b.label) end)
    self.categories = categories
    if self.categoryKey ~= "all" and not categoryMap[self.categoryKey] then self.categoryKey = "all" end

    local visibleCount = 0
    for i = 1, #rows do
        local row = rows[i]
        local category = GodSystemApp.services.runtime.getShopPrimaryCategory(row)
        if self:matches(row, category) then
            local status = row.hidden == true and GodSystemApp.services.runtime.text("ShopHidden_StatusHidden", "Hidden") or GodSystemApp.services.runtime.text("ShopHidden_StatusVisible", "Visible")
            local sprite = row.worldSprite and (" | " .. tostring(row.worldSprite)) or ""
            self.list:addItem("[" .. status .. "] " .. tostring(row.label or row.fullType) .. " | " .. tostring(row.fullType or "") .. sprite, {
                variantKey = row.variantKey,
                fullType = row.fullType,
                worldSprite = row.worldSprite,
                hidden = row.hidden == true,
                label = row.label,
                categoryKey = category.key,
            })
            visibleCount = visibleCount + 1
        end
    end
    if visibleCount == 0 then
        self.list:addItem(GodSystemApp.services.runtime.text("ShopHidden_Empty", "No player-listed items match the filters"), { empty = true })
        self.list.selected = 0
        self:clearSelectedVariants()
    end
    self:pruneSelectedVariants()
    if ListState and listState then
        local context = self:listStateContext()
        if ListState.restore(self.list, listState, context, function(payload)
            return payload and payload.variantKey or nil
        end) then
            ListState.restoreNextTick(self.list, listState, context, function(payload)
                return payload and payload.variantKey or nil
            end)
        end
    end
    gsSetButtonTitle(self.categoryButton, GodSystemApp.services.runtime.text("ShopHidden_Category", "Category") .. ": " .. self:categoryLabel())
    gsSetButtonTitle(self.statusButton, GodSystemApp.services.runtime.text("ShopHidden_Status", "Status") .. ": " .. self:statusLabel())
    self:updateButtons()
end

function GodSystemShopHiddenWindow:setCategory(key)
    self.categoryKey = tostring(key or "all")
    self:clearSelectedVariants()
    self:populateItems(false)
end

function GodSystemShopHiddenWindow:onCategoryButton()
    local player = getPlayer()
    local context = ISContextMenu.get(player and player:getPlayerNum() or 0, getMouseX(), getMouseY())
    context:addOption(GodSystemApp.services.runtime.text("ShopHidden_FilterAll", "All"), self, self.setCategory, "all")
    for i = 1, #(self.categories or {}) do
        context:addOption(self.categories[i].label, self, self.setCategory, self.categories[i].key)
    end
end

function GodSystemShopHiddenWindow:setStatus(status)
    self.statusFilter = tostring(status or "all")
    self:clearSelectedVariants()
    self:populateItems(false)
end

function GodSystemShopHiddenWindow:onStatusButton()
    local player = getPlayer()
    local context = ISContextMenu.get(player and player:getPlayerNum() or 0, getMouseX(), getMouseY())
    context:addOption(GodSystemApp.services.runtime.text("ShopHidden_FilterAll", "All"), self, self.setStatus, "all")
    context:addOption(GodSystemApp.services.runtime.text("ShopHidden_FilterVisible", "Visible"), self, self.setStatus, "visible")
    context:addOption(GodSystemApp.services.runtime.text("ShopHidden_FilterHidden", "Hidden"), self, self.setStatus, "hidden")
end

function GodSystemShopHiddenWindow:onSearchChange(entry)
    self.searchText = entry and entry.getInternalText and entry:getInternalText() or ""
    self:clearSelectedVariants()
    self:populateItems(false)
end

function GodSystemShopHiddenWindow:setSelectedHidden(hidden)
    local rows = self:selectedVariantRows(nil)
    if #rows == 0 then return end
    local keys = {}
    for i = 1, #rows do keys[#keys + 1] = rows[i].variantKey end
    local sent = GodSystemApp.services.runtime.setShopItemsHidden(keys, hidden == true)
    self.waitingForServer = gsIsMultiplayer() and sent ~= false
    if self.owner and self.owner.finishMultiplayerCommand then self.owner:finishMultiplayerCommand(sent) end
    if not self.waitingForServer then
        self:populateItems()
    end
end

function GodSystemShopHiddenWindow:onHide()
    self:setSelectedHidden(true)
end

function GodSystemShopHiddenWindow:onShow()
    self:setSelectedHidden(false)
end

function GodSystemShopHiddenWindow:onDelete()
    local row = self:getSelected()
    if not row or not row.variantKey or row.empty then return end
    local message = gsFormatTemplate(GodSystemApp.services.runtime.text("Confirm_ShopItemDelete", "Delete the listing for {1}? No currency will be refunded; relisting will charge the normal fee."), {
        tostring(row.label or row.fullType or row.variantKey),
    })
    local player = getPlayer and getPlayer() or nil
    local playerNum = player and player:getPlayerNum() or 0
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local modal = ISModalDialog:new(x, y, 500, 260, message, true, self, self.onDeleteConfirm, playerNum, {
            variantKey = row.variantKey,
        })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitConfirmMissing", "Confirmation dialog unavailable"))
    end
end

function GodSystemShopHiddenWindow:onDeleteConfirm(button, payload)
    if not button or button.internal ~= "YES" then return end
    local variantKey = payload and payload.variantKey or nil
    if not variantKey then return end
    self:clearSelectedVariants()
    local sent = GodSystemApp.services.runtime.deleteShopItem(variantKey)
    self.waitingForServer = gsIsMultiplayer() and sent ~= false
    if self.owner and self.owner.finishMultiplayerCommand then self.owner:finishMultiplayerCommand(sent) end
    if not self.waitingForServer then
        self:populateItems()
    end
end

function GodSystemShopHiddenWindow:onServerStateChanged()
    self.waitingForServer = false
    self.lastStateSerial = GodSystemNetwork and GodSystemNetwork.stateSerial or self.lastStateSerial
    self:populateItems()
end

function GodSystemShopHiddenWindow:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if GodSystemUI.shopHiddenWindow == self then GodSystemUI.shopHiddenWindow = nil end
end

GodSystemTaskTurnInDialog = ISCollapsableWindow:derive("GodSystemTaskTurnInDialog")

function GodSystemTaskTurnInDialog:new(x, y, width, height, owner, task, candidates)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = GodSystemApp.services.runtime.text("TaskTurnIn_Title", "Submit task items")
    o.owner = owner
    o.task = task
    o.candidates = candidates or {}
    o.selectedItemIds = {}
    o.resizable = false
    return o
end

function GodSystemTaskTurnInDialog:target()
    return math.max(1, math.floor(tonumber(self.task and self.task.target) or 1))
end

function GodSystemTaskTurnInDialog:selectedCount()
    local count = 0
    for _ in pairs(self.selectedItemIds or {}) do count = count + 1 end
    return count
end

function GodSystemTaskTurnInDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local margin, top, buttonH = 12, 34, 34
    self.descriptionLabel = ISLabel:new(margin, top, 18, "", 0.76, 0.82, 0.9, 1, UIFont.Small, true)
    self.descriptionLabel:initialise()
    self:addChild(self.descriptionLabel)

    self.list = ISScrollingListBox:new(margin, top + 28, self.width - (margin * 2), self.height - top - buttonH - 56)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 34
    self.list.doDrawItem = function(list, y, row, alt) return self:drawCandidate(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onListMouseDown)
    gsInstallSafeScrollingListPrerender(self.list)
    self:addChild(self.list)

    local actionY = self.height - buttonH - 12
    self.submitButton = ISButton:new(margin, actionY, 132, buttonH, GodSystemApp.services.runtime.text("Btn_TaskTurnIn", "Submit"), self, self.onSubmit)
    self.submitButton:initialise()
    gsStyleActionButton(self.submitButton, "primary")
    self:addChild(self.submitButton)

    self.cancelButton = ISButton:new(self.width - 132, actionY, 120, buttonH, GodSystemApp.services.runtime.text("Btn_Cancel", "Cancel"), self, self.close)
    self.cancelButton:initialise()
    gsStyleActionButton(self.cancelButton, false)
    self:addChild(self.cancelButton)

    self.selectionLabel = ISLabel:new(158, actionY + 9, 18, "", 0.62, 0.76, 0.82, 1, UIFont.Small, true)
    self.selectionLabel:initialise()
    self:addChild(self.selectionLabel)
    self:populateCandidates()
end

function GodSystemTaskTurnInDialog:populateCandidates()
    self.list:clear()
    self.list.selected = 0
    self.list:setScrollHeight(0)
    for i = 1, #(self.candidates or {}) do
        local row = self.candidates[i]
        self.list:addItem(tostring(row.label or row.fullType or ""), row)
    end
    if #(self.candidates or {}) == 0 then
        self.list:addItem(GodSystemApp.services.runtime.text("TaskTurnIn_Empty", "No matching items carried"), { empty = true })
    end
    self:updateState()
end

function GodSystemTaskTurnInDialog:drawCandidate(list, y, row, alt)
    local data = row and row.item or nil
    local background = alt and gsThemeColor("panel") or gsThemeColor("panelDeep")
    gsDrawRect(list, 0, y, list.width, list.itemheight - 1, background)
    gsDrawRectBorder(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("border"))
    if data and not data.empty then
        local itemId = tostring(data.itemId or "")
        local selected = self.selectedItemIds[itemId] == true
        gsDrawRectBorder(list, 8, y + 10, 12, 12, gsThemeColor("borderStrong"))
        if selected then gsDrawRect(list, 10, y + 12, 8, 8, gsThemeColor("gold")) end
        local label = gsTruncateText(tostring(data.label or data.fullType or ""), UIFont.Small, list.width - 156)
        gsDrawText(list, label, 30, y + 8, gsThemeColor("text"), UIFont.Small)
        gsDrawText(list, gsTruncateText(tostring(data.fullType or ""), UIFont.Small, 112), list.width - 120, y + 8, gsThemeColor("dimText"), UIFont.Small)
    else
        gsDrawText(list, tostring(row and row.text or ""), 10, y + 8, gsThemeColor("dimText"), UIFont.Small)
    end
    return y + list.itemheight
end

function GodSystemTaskTurnInDialog:onListMouseDown(row)
    local data = row and (row.item or row) or nil
    if not data or data.empty then return end
    local itemId = tostring(data.itemId or "")
    if itemId == "" then return end
    self.selectedItemIds[itemId] = self.selectedItemIds[itemId] ~= true and true or nil
    self:updateState()
end

function GodSystemTaskTurnInDialog:selectedItemIdsInOrder()
    local result = {}
    for i = 1, #(self.candidates or {}) do
        local itemId = tostring(self.candidates[i].itemId or "")
        if itemId ~= "" and self.selectedItemIds[itemId] == true then result[#result + 1] = itemId end
    end
    return result
end

function GodSystemTaskTurnInDialog:updateState()
    local selectedCount = self:selectedCount()
    local target = self:target()
    self.submitButton.enable = selectedCount == target
    gsSetLabel(self.descriptionLabel, GodSystemApp.services.runtime.text("TaskTurnIn_Instruction", "Select the items to submit"))
    gsSetLabel(self.selectionLabel, GodSystemApp.services.runtime.text("TaskTurnIn_Selected", "Selected: {1}/{2}"):gsub("{1}", tostring(selectedCount)):gsub("{2}", tostring(target)))
end

function GodSystemTaskTurnInDialog:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
    self:updateState()
end

function GodSystemTaskTurnInDialog:onSubmit()
    local selectedCount = self:selectedCount()
    local target = self:target()
    if selectedCount ~= target then return end
    local itemIds = self:selectedItemIdsInOrder()
    if #itemIds ~= target then return end
    local sent = GodSystemApp.services.runtime.submitTurnInTask(self.task, itemIds)
    if self.owner and self.owner.finishMultiplayerCommand then self.owner:finishMultiplayerCommand(sent) end
    if sent ~= false then self:close() end
end

function GodSystemTaskTurnInDialog:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if GodSystemUI.taskTurnInDialog == self then GodSystemUI.taskTurnInDialog = nil end
end

GodSystemWindow = ISCollapsableWindow:derive("GodSystemWindow")

GS_NON_SELECTABLE_KINDS = {
    traitHeader = true,
    attributeHeader = true,
    companionState = true,
    bankSummary = true,
    bankLoanSummary = true,
    adminInfo = true,
    empty = true,
    detailLine = true,
    info = true,
    history = true,
    diagnostics = true,
    spacer = true,
}

GS_SECTION_HEADER_KINDS = {
    traitHeader = true,
    attributeHeader = true,
}

GS_INFO_ROW_KINDS = {
    companionState = true,
    bankSummary = true,
    bankLoanSummary = true,
    adminInfo = true,
    detailLine = true,
    info = true,
    history = true,
    diagnostics = true,
}
end
