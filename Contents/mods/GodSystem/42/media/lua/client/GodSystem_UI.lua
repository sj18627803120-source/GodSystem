require "GodSystem_Config"
require "GodSystem_Core"
require "GodSystem_UITheme"
require "GodSystem_CompanionConfig"
if not ((isClient and isClient()) or (isServer and isServer())) then
    require "GodSystem_Companion"
    require "GodSystem_CompanionUI"
end
require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISContextMenu"
require "ISUI/ISModalDialog"
require "ISUI/ISTextEntryBox"

GodSystemUI = GodSystemUI or {}
GodSystemUI.floating = nil
GodSystemUI.window = nil
GodSystemUI.taskTracker = nil
GodSystemUI.shortcutWindow = nil

local function gsSetLabel(label, text)
    if label then
        label.name = text or ""
    end
end

local function gsSyncScrollingListGeometry(element)
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

local gsOriginalScrollingListPrerender = ISScrollingListBox.prerender

local function gsSafeScrollingListPrerender(self)
    gsSyncScrollingListGeometry(self)
    gsOriginalScrollingListPrerender(self)
    gsSyncScrollingListGeometry(self)
end

local function gsInstallSafeScrollingListPrerender(list)
    if not list then
        return
    end
    list.prerender = gsSafeScrollingListPrerender
    gsSyncScrollingListGeometry(list)
end

local function gsSetBounds(element, x, y, width, height)
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

local function gsTrim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function gsMeasureText(font, text)
    text = tostring(text or "")
    if getTextManager then
        local ok, width = pcall(function() return getTextManager():MeasureStringX(font or UIFont.Small, text) end)
        if ok and width then
            return width
        end
    end
    return string.len(text) * 7
end

local function gsClamp(value, minValue, maxValue)
    value = tonumber(value) or minValue or 0
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function gsUtf8Chars(text)
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

local function gsJoinChars(chars, count)
    local parts = {}
    count = math.min(math.floor(count or 0), #chars)
    for i = 1, count do
        parts[i] = chars[i]
    end
    return table.concat(parts, "")
end

local function gsTruncateText(text, font, maxWidth)
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

local function gsWrapText(text, font, maxWidth)
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

local function gsDrawTextCentre(ui, text, x, y, w, r, g, b, a, font)
    ui:drawTextCentre(text, x + (w / 2), y, r, g, b, a, font or UIFont.Small)
end

local function gsTheme()
    return GodSystemUITheme or {}
end

local function gsThemeColor(name, fallback)
    local theme = gsTheme()
    local colors = theme.colors or {}
    return colors[name] or fallback or { r = 1, g = 1, b = 1, a = 1 }
end

local function gsColorRGBA(color, fallback)
    color = color or fallback or {}
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

local function gsColorARGB(color, fallback)
    color = color or fallback or {}
    return color.a or 1, color.r or 1, color.g or 1, color.b or 1
end

local function gsDrawRect(ui, x, y, width, height, color)
    local a, r, g, b = gsColorARGB(color)
    ui:drawRect(x, y, width, height, a, r, g, b)
end

local function gsDrawRectBorder(ui, x, y, width, height, color)
    local a, r, g, b = gsColorARGB(color)
    ui:drawRectBorder(x, y, width, height, a, r, g, b)
end

local function gsDrawText(ui, text, x, y, color, font)
    local r, g, b, a = gsColorRGBA(color)
    ui:drawText(tostring(text or ""), x, y, r, g, b, a, font or UIFont.Small)
end

local function gsDrawTextRight(ui, text, x, y, width, color, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    local textW = gsMeasureText(font, text)
    gsDrawText(ui, text, x + math.max(0, (width or 0) - textW), y, color, font)
end

local function gsDrawProgressBar(ui, x, y, width, height, value, maxValue, fillColor)
    value = math.max(0, tonumber(value) or 0)
    maxValue = math.max(1, tonumber(maxValue) or 1)
    local ratio = gsClamp(value / maxValue, 0, 1)
    gsDrawRect(ui, x, y, width, height, gsThemeColor("progressTrack"))
    if ratio > 0 then
        gsDrawRect(ui, x + 1, y + 1, math.max(1, math.floor((width - 2) * ratio)), math.max(1, height - 2), fillColor or gsThemeColor("progressFill"))
    end
    gsDrawRectBorder(ui, x, y, width, height, gsThemeColor("border"))
end

local function gsSetButtonTitle(button, title)
    if not button then
        return
    end
    button.fullTitle = tostring(title or "")
    if button.setTitle then
        button:setTitle(button.fullTitle)
    end
end

local function gsStyleButton(button, active)
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

local function gsStyleActionButton(button, variant)
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

local function gsFormatTemplate(template, args)
    local text = tostring(template or "")
    args = args or {}
    for i = 1, #args do
        text = string.gsub(text, "{" .. tostring(i) .. "}", function()
            return tostring(args[i] or "")
        end)
    end
    return text
end

local function gsNowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

local function gsFormatCompactNumber(value)
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

local function gsIsMultiplayer()
    return GodSystemNetwork ~= nil and GodSystemNetwork.isMultiplayer == true
end

local function gsHasServerState()
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
    o.backgroundColor = { r = 0.05, g = 0.06, b = 0.07, a = 0.88 }
    o.borderColor = { r = 0.95, g = 0.68, b = 0.22, a = 0.95 }
    o.iconTexture = getTexture and getTexture("media/textures/GodSystem_OpenIcon.png") or nil
    o.dragging = false
    o.moved = false
    return o
end

function GodSystemFloatingButton:prerender()
    ISPanel.prerender(self)
    self:drawRectBorder(0, 0, self.width, self.height, 0.95, 0.95, 0.68, 0.22)
    if self.iconTexture and self.drawTextureScaled then
        local inset = 4
        self:drawTextureScaled(self.iconTexture, inset, inset, self.width - inset * 2, self.height - inset * 2, 1)
    else
        gsDrawTextCentre(self, "GS", 0, math.max(4, math.floor((self.height - 18) / 2)), self.width, 1, 0.74, 0.22, 1, UIFont.Medium)
    end
end

function GodSystemFloatingButton:onMouseDown(x, y)
    self.dragging = true
    self.moved = false
    self.downX = x
    self.downY = y
    self.startX = self.x
    self.startY = self.y
    return true
end

function GodSystemFloatingButton:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(getMouseX() - self.downX)
        self:setY(getMouseY() - self.downY)
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
        local data = GodSystem.getData()
        data.ui.x = self.x
        data.ui.y = self.y
        GodSystem.save()
        if not self.moved then
            GodSystemUI.toggleWindow()
        end
        return true
    end
    return false
end

local function gsGetActiveTaskRows()
    local rows = {}
    local data = GodSystem.getData()
    local tasks = data.tasks or {}
    for i = 1, #tasks do
        local task = tasks[i]
        if task and task.status == "active" then
            local target = math.max(1, math.floor(tonumber(task.target) or 1))
            local progress = math.min(GodSystem.getTaskProgress(task), target)
            local done = progress >= target
            local detail = tostring(progress) .. "/" .. tostring(target)
            if done then
                detail = detail .. " " .. GodSystem.text("TaskTracker_Done", "Ready")
            else
                detail = detail .. " " .. GodSystem.text("TaskTracker_Left", "Left") .. tostring(GodSystem.getRemainingHours(task)) .. "h"
            end
            table.insert(rows, {
                title = GodSystem.getTaskTitle(task),
                detail = detail,
            })
        end
    end
    return rows
end

GodSystemTaskTracker = ISPanel:derive("GodSystemTaskTracker")

function GodSystemTaskTracker:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0.02, g = 0.024, b = 0.028, a = 0.78 }
    o.borderColor = { r = 0.95, g = 0.68, b = 0.22, a = 0.88 }
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

    self:drawRect(0, 0, self.width, self.height, 0.78, 0.02, 0.024, 0.028)
    self:drawRectBorder(0, 0, self.width, self.height, 0.88, 0.95, 0.68, 0.22)
    self:drawRect(0, 0, self.width, 26, 0.68, 0.05, 0.055, 0.06)
    self:drawText(GodSystem.text("TaskTracker_Title", "Task tracker"), 8, 6, 1, 0.86, 0.36, 1, UIFont.Small)
    self:drawText("x", self.width - 18, 5, 0.9, 0.9, 0.86, 1, UIFont.Small)
    self:drawRect(self.width - grip + 3, self.height - 4, grip - 5, 1, 0.55, 0.95, 0.68, 0.22)
    self:drawRect(self.width - grip + 6, self.height - 8, grip - 8, 1, 0.55, 0.95, 0.68, 0.22)
    self:drawRect(self.width - grip + 9, self.height - 12, grip - 11, 1, 0.55, 0.95, 0.68, 0.22)

    if #rows == 0 then
        self:drawText(GodSystem.text("TaskTracker_Empty", "No active tasks"), 8, 36, 0.78, 0.78, 0.72, 1, UIFont.Small)
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
            self:drawRect(4, y - 2, self.width - 8, rowH, 0.10, 0.92, 0.92, 0.88)
        end
        self:drawText(gsTruncateText(row.title or "", UIFont.Small, titleW), 8, y, 0.94, 0.94, 0.9, 1, UIFont.Small)
        self:drawText(gsTruncateText(row.detail or "", UIFont.Small, detailW), self.width - 8 - detailW, y, 0.78, 0.86, 0.78, 1, UIFont.Small)
    end
    if visibleRows < #rows then
        self:drawText("...", self.width - 28, self.height - 20, 0.78, 0.78, 0.72, 1, UIFont.Small)
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
        local data = GodSystem.getData()
        data.ui.taskTrackerX = self.x
        data.ui.taskTrackerY = self.y
        data.ui.taskTrackerW = math.floor(self.width or 300)
        data.ui.taskTrackerH = math.floor(self.height or 92)
        GodSystem.save()
        return true
    end
    if self.dragging then
        self.dragging = false
        local data = GodSystem.getData()
        data.ui.taskTrackerX = self.x
        data.ui.taskTrackerY = self.y
        data.ui.taskTrackerW = math.floor(self.width or 300)
        data.ui.taskTrackerH = math.floor(self.height or 92)
        GodSystem.save()
        return true
    end
    return false
end

function GodSystemTaskTracker:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function GodSystemTaskTracker:close()
    local data = GodSystem.getData()
    data.ui.taskTrackerVisible = false
    data.ui.taskTrackerX = self.x
    data.ui.taskTrackerY = self.y
    data.ui.taskTrackerW = math.floor(self.width or 300)
    data.ui.taskTrackerH = math.floor(self.height or 92)
    GodSystem.save()
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
    o.title = GodSystem.text("Shortcut_Title", "Shortcuts")
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
    local home = GodSystem.getHomeSystem and GodSystem.getHomeSystem() or nil
    if home and home.home then
        actions[#actions + 1] = { action = "teleportHome", label = GodSystem.text("Shortcut_Home", "Home") }
    end
    if home and home.returnPoint then
        actions[#actions + 1] = { action = "return", label = GodSystem.text("Shortcut_Return", "Return") }
    end
    actions[#actions + 1] = { action = "recycleWaistOnly", label = GodSystem.text("Shortcut_RecycleWaistOnly", "Waist recycle") }
    actions[#actions + 1] = { action = "recycleWaistAndList", label = GodSystem.text("Shortcut_RecycleWaistAndList", "Waist recycle and list") }
    actions[#actions + 1] = { action = "depositAllCash", label = GodSystem.text("Shortcut_DepositAllCash", "Deposit cash") }
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
        return GodSystem.formatPosition(source)
    end
    source = tostring(source or "")
    if source == "" then
        return GodSystem.text("Home_ReturnPoint", "Return point")
    end
    return source
end

function GodSystemShortcutWindow:getShortcutHomeConfirmMessage(action)
    local cost = GodSystemConfig.HomeTravelCost or 10
    local line = ""
    if action == "teleportHome" then
        line = GodSystem.text("Confirm_HomeTeleport", "You are teleporting home. Confirm?")
    elseif action == "return" then
        local home = GodSystem.getHomeSystem and GodSystem.getHomeSystem() or nil
        local source = self:formatShortcutHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystem.text("Confirm_HomeReturn", "You are returning to the departure point: ") .. tostring(source) .. GodSystem.text("Confirm_Question", ". Confirm?")
    end
    local player = getPlayer and getPlayer() or nil
    local pos = GodSystem.formatPosition((player and { x = player:getX(), y = player:getY(), z = player:getZ() }) or nil)
    return line .. "\n" .. GodSystem.text("Home_CurrentPosition", "Current: ") .. pos .. "\n" .. GodSystem.text("Trait_ConfirmCost", "Cost: ") .. tostring(cost) .. GodSystem.text("Unit_CoinShort", "c")
end

function GodSystemShortcutWindow:confirmShortcutHomeAction(action)
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer and getPlayer() or nil
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, self:getShortcutHomeConfirmMessage(action), true, self, self.onShortcutHomeConfirm, playerNum, { action = action })
        modal:initialise()
        modal:addToUIManager()
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
        self:finishShortcutCommand(GodSystem.performHomeAction(action))
    end
end

function GodSystemShortcutWindow:performAction(action)
    action = tostring(action or "")
    local home = GodSystem.getHomeSystem and GodSystem.getHomeSystem() or nil
    if action == "teleportHome" then
        if not (home and home.home) then
            GodSystem.notify(GodSystem.text("Notify_HomeNotSet", "Home is not set"))
            return false
        end
        self:confirmShortcutHomeAction("teleportHome")
        return true
    elseif action == "return" then
        if not (home and home.returnPoint) then
            GodSystem.notify(GodSystem.text("Notify_HomeNoReturn", "No return point"))
            return false
        end
        self:confirmShortcutHomeAction("return")
        return true
    elseif action == "recycleWaistOnly" then
        return self:finishShortcutCommand(GodSystem.recycleWaistSpaceItems(nil))
    elseif action == "recycleWaistAndList" then
        return self:finishShortcutCommand(GodSystem.recycleWaistSpaceItemsAndUnlock(nil))
    elseif action == "depositAllCash" then
        return self:finishShortcutCommand(GodSystem.performBankAction("depositAllCash"))
    end
    return false
end

function GodSystemShortcutWindow:close()
    local data = GodSystem.getData()
    data.ui.shortcutX = math.floor(self.x or 0)
    data.ui.shortcutY = math.floor(self.y or 0)
    GodSystem.save()
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
        GodSystem.notify("Code error")
        self:onCancel()
        return
    end
    local sent = true
    if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.send then
        sent = GodSystemNetwork.send("debugGrant", { code = "12130" })
    else
        sent = GodSystem.addPoints(10000, GodSystem.text("Reason_Debug", "Debug"))
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
    o.title = (payload and payload.title) or GodSystem.text("Bank_AmountTitle", "Bank amount")
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

    self.confirmButton = ISButton:new(16, 104, 96, 28, GodSystem.text("Btn_Confirm", "Confirm"), self, self.onConfirm)
    self.confirmButton:initialise()
    gsStyleButton(self.confirmButton, false)
    self:addChild(self.confirmButton)

    self.cancelButton = ISButton:new(self.width - 112, 104, 96, 28, GodSystem.text("Btn_Cancel", "Cancel"), self, self.onCancel)
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
        GodSystem.notify(GodSystem.text("Notify_BankInvalidAmount", "Enter a valid amount"))
        return
    end
    local payload = self.payload or {}
    local sent = false
    if payload.kind == "attribute" then
        sent = GodSystem.performAttributePurchase(payload.perkIndex, payload.mode, amount)
    else
        sent = GodSystem.performBankAction(payload.action, amount, payload.termId, payload.entryId)
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

GodSystemAdminTextDialog = ISCollapsableWindow:derive("GodSystemAdminTextDialog")

function GodSystemAdminTextDialog:new(x, y, width, height, owner, payload)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = tostring(payload and payload.title or "Admin")
    o.owner = owner
    o.payload = payload or {}
    o.resizable = false
    return o
end

function GodSystemAdminTextDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.messageLabel = ISLabel:new(16, 36, 20, tostring(self.payload.message or ""), 0.9, 0.9, 0.86, 1, UIFont.Small, true)
    self.messageLabel:initialise()
    self:addChild(self.messageLabel)

    self.entry = ISTextEntryBox:new(tostring(self.payload.value or ""), 16, 64, self.width - 32, 28)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    self:addChild(self.entry)

    self.confirmButton = ISButton:new(16, self.height - 42, 96, 28, GodSystem.text("Btn_Confirm", "Confirm"), self, self.onConfirm)
    self.confirmButton:initialise()
    gsStyleButton(self.confirmButton, false)
    self:addChild(self.confirmButton)

    self.cancelButton = ISButton:new(self.width - 112, self.height - 42, 96, 28, GodSystem.text("Btn_Cancel", "Cancel"), self, self.onCancel)
    self.cancelButton:initialise()
    gsStyleButton(self.cancelButton, false)
    self:addChild(self.cancelButton)
end

function GodSystemAdminTextDialog:prerender()
    ISCollapsableWindow.prerender(self)
    gsDrawRect(self, 0, 16, self.width, self.height - 16, gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, 17, self.width - 2, self.height - 18, gsThemeColor("borderStrong"))
end

function GodSystemAdminTextDialog:onConfirm()
    local text = ""
    if self.entry and self.entry.getInternalText then
        text = self.entry:getInternalText() or ""
    end
    if self.owner and self.owner.onAdminDialogConfirm then
        self.owner:onAdminDialogConfirm(self.payload, gsTrim(text))
    end
    self:onCancel()
end

function GodSystemAdminTextDialog:onCancel()
    self:setVisible(false)
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
end

GodSystemWindow = ISCollapsableWindow:derive("GodSystemWindow")

local GS_NON_SELECTABLE_KINDS = {
    traitHeader = true,
    attributeHeader = true,
    lotteryInfo = true,
    lotteryHeader = true,
    lotteryResult = true,
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

local GS_SECTION_HEADER_KINDS = {
    traitHeader = true,
    attributeHeader = true,
    lotteryHeader = true,
}

local GS_INFO_ROW_KINDS = {
    lotteryInfo = true,
    lotteryResult = true,
    companionState = true,
    bankSummary = true,
    bankLoanSummary = true,
    adminInfo = true,
    detailLine = true,
    info = true,
    history = true,
    diagnostics = true,
}

local function gsIsSelectablePayload(payload)
    return payload ~= nil and payload.selectable ~= false and GS_NON_SELECTABLE_KINDS[payload.kind] ~= true
end

function GodSystemWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    local win = (gsTheme().window or {})
    o.title = GodSystem.text("Title", "God System") .. " v" .. tostring(GodSystemConfig.Version)
    o.mode = "tasks"
    o.selectedTaskList = "open"
    o.waistSelected = {}
    o.shopSearchText = ""
    o.recycleSearchText = ""
    o.adminSearchText = ""
    o.attributeSearchText = ""
    o.shopSearchPurpose = "shop"
    o.navScroll = 0
    o.navPageIndex = 1
    o.lastSelectableListRow = 0
    o.lastSelectableActiveRow = 0
    o.pendingRestoreSelectedId = nil
    o.pendingRestoreSelectedTaskList = nil
    o.pendingRestoreMode = nil
    o.pendingRestoreScroll = nil
    o.lotteryCategoryKey = "all"
    o.lotteryCustomCount = 10
    o.latestLotteryResult = nil
    o.resizable = false
    o.resizeAspect = (win.baseWidth or win.fixedWidth or 1240) / math.max(1, (win.baseHeight or win.fixedHeight or 690))
    o.minimumScale = win.scaleMin or 0.75
    o.maximumScale = win.scaleMax or 1.15
    o.minimumWidth = win.minimumWidth or math.floor((win.baseWidth or win.fixedWidth or 1240) * o.minimumScale)
    o.minimumHeight = win.minimumHeight or math.floor((win.baseHeight or win.fixedHeight or 690) * o.minimumScale)
    o.resizeGripSize = win.resizeGripSize or 18
    o.uiScale = 1
    return o
end

function GodSystemWindow:getBaseWidth()
    local win = (gsTheme().window or {})
    return win.baseWidth or win.fixedWidth or 1240
end

function GodSystemWindow:getBaseHeight()
    local win = (gsTheme().window or {})
    return win.baseHeight or win.fixedHeight or 690
end

function GodSystemWindow:getUIScale()
    return tonumber(self.uiScale) or ((self.width or self:getBaseWidth()) / math.max(1, self:getBaseWidth())) or 1
end

function GodSystemWindow:S(value)
    return math.floor((tonumber(value) or 0) * self:getUIScale() + 0.5)
end

function GodSystemWindow:clampScale(scale)
    local minScale = self.minimumScale or ((gsTheme().window or {}).scaleMin) or 0.75
    local maxScale = self.maximumScale or ((gsTheme().window or {}).scaleMax) or 1.15
    local screenW = getCore and getCore():getScreenWidth() or nil
    local screenH = getCore and getCore():getScreenHeight() or nil
    if screenW and screenH then
        local baseW = self:getBaseWidth()
        local baseH = self:getBaseHeight()
        maxScale = math.min(maxScale, math.max(minScale, (screenW - 32) / math.max(1, baseW)), math.max(minScale, (screenH - 32) / math.max(1, baseH)))
    end
    return gsClamp(scale, minScale, maxScale)
end

function GodSystemWindow:getScaledSize(scale)
    scale = self:clampScale(scale or self:getUIScale())
    return math.floor(self:getBaseWidth() * scale + 0.5), math.floor(self:getBaseHeight() * scale + 0.5), scale
end

function GodSystemWindow:setScaledSize(scale)
    local w, h, appliedScale = self:getScaledSize(scale)
    self.uiScale = appliedScale
    gsSetBounds(self, nil, nil, w, h)
    return appliedScale
end

function GodSystemWindow:clampToScreen()
    if not getCore then
        return
    end
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = gsClamp(math.floor(self.x or 0), 0, math.max(0, screenW - math.floor(self.width or 0)))
    local y = gsClamp(math.floor(self.y or 0), 0, math.max(0, screenH - math.floor(self.height or 0)))
    gsSetBounds(self, x, y, nil, nil)
end

function GodSystemWindow:enforceMinimumSize()
    local scale = self:getUIScale()
    if (self.width or 0) <= 0 then
        scale = 1
    end
    self:setScaledSize(scale)
    self:clampToScreen()
end

function GodSystemWindow:setupLayoutMetrics()
    self:enforceMinimumSize()
    local win = (gsTheme().window or {})
    local top = win.topBar or {}
    local nav = win.nav or {}
    local content = win.content or {}
    self.outerPad = self:S(win.outerPad or 14)
    self.gap = self:S(win.gap or 12)
    self.topX = self:S(top.x or 14)
    self.topY = self:S(top.y or 18)
    self.topW = self:S(top.w or ((win.baseWidth or win.fixedWidth or 1240) - 28))
    self.topH = self:S(top.h or 68)
    self.navX = self:S(nav.x or 24)
    self.navY = self:S(nav.y or 100)
    self.navW = self:S(nav.w or 198)
    self.navH = self:S(nav.h or 560)
    self.navItemH = self:S(win.navItemHeight or 56)
    self.navItemGap = self:S(win.navItemGap or 8)
    self.navToolH = self:S(win.navToolHeight or 30)
    self.navPageButtonH = self:S(28)
    self.navBottomInset = self:S(8)
    self.navViewportY = self.navY + self.navPageButtonH + self.navItemGap
    self.navViewportH = math.max(self.navItemH, self.navH - (self.navPageButtonH * 2) - (self.navItemGap * 2) - self.navBottomInset)
    self.contentX = self:S(content.x or 236)
    self.contentY = self:S(content.y or 100)
    self.contentW = self:S(content.w or 980)
    self.contentH = self:S(content.h or 560)
    self.titleBarH = self:S(win.titleBarHeight or 36)
    self.actionH = self:S(win.actionHeight or 54)
    self.actionButtonH = self:S(win.actionButtonHeight or 38)
    self.actionY = self.contentY + self.contentH - self.actionH
    self.panelTop = self.contentY + self.titleBarH + 6
    self.panelBottom = self.actionY - 10
    self.mainX = self.contentX + self:S(12)
    self.mainY = self:S(win.listY or 170)
    self.panelRight = self.contentX + self.contentW - 12
    self.detailW = self:S(win.detailWidth or 478)
    self.detailX = self.panelRight - self.detailW
    self.mainW = math.max(self:S(360), self.detailX - self.mainX - self:S(win.panelGap or 20))
    self.mainH = math.max(self:S(220), self.panelBottom - self.mainY)
    self.headerStatsX = self.contentX + self:S(260)
    self.headerStatsW = self:S(360)
    self.actionX = self.mainX
    self.actionRight = self.panelRight
    self.actionW = math.max(self:S(280), self.actionRight - self.actionX)
end

function GodSystemWindow:getNavPageLayout()
    local count = math.max(0, math.floor(tonumber(self.navNormalCount) or 0))
    local itemH = self.navItemH or self:S(56)
    local gap = self.navItemGap or self:S(8)
    local fullViewportH = math.max(itemH, (self.navH or itemH) - (gap * 2))
    local fullCapacity = math.max(1, math.floor((fullViewportH + gap) / math.max(1, itemH + gap)))
    if count <= fullCapacity then
        return math.max(1, count), 1
    end
    local viewportH = math.max(itemH,
        (self.navH or itemH)
        - ((self.navPageButtonH or self:S(28)) * 2)
        - (gap * 2)
        - (self.navBottomInset or self:S(8)))
    local capacity = math.max(1, math.floor((viewportH + gap) / math.max(1, itemH + gap)))
    local pageCount = math.max(1, math.ceil(count / capacity))
    return capacity, pageCount
end

function GodSystemWindow:getNavItemsPerPage()
    local perPage = self:getNavPageLayout()
    return perPage
end

function GodSystemWindow:getNavPageCount()
    local _, pageCount = self:getNavPageLayout()
    return pageCount
end

function GodSystemWindow:clampNavPage()
    self.navPageIndex = gsClamp(math.floor(tonumber(self.navPageIndex) or 1), 1, self:getNavPageCount())
    self.navScroll = (self.navPageIndex - 1) * self:getNavItemsPerPage()
    return self.navPageIndex
end

function GodSystemWindow:updateNavPageButtons()
    local page = self:clampNavPage()
    local pageCount = self:getNavPageCount()
    local canPage = pageCount > 1
    if self.navPageUpButton then
        self.navPageUpButton:setVisible(canPage)
        self.navPageUpButton.enable = page > 1
        gsStyleButton(self.navPageUpButton, false)
    end
    if self.navPageDownButton then
        self.navPageDownButton:setVisible(canPage)
        self.navPageDownButton.enable = page < pageCount
        gsStyleButton(self.navPageDownButton, false)
    end
end

function GodSystemWindow:updateNavButtonVisibility()
    local page = self:clampNavPage()
    if not self.modeButtons then
        return
    end
    local perPage = self:getNavItemsPerPage()
    local first = ((page - 1) * perPage) + 1
    local last = first + perPage - 1
    for _, button in pairs(self.modeButtons) do
        if button.navTool ~= true then
            local normalIndex = button.navNormalIndex or 0
            button:setVisible(normalIndex >= first and normalIndex <= last)
        end
    end
    self:updateNavPageButtons()
end

function GodSystemWindow:scrollNav(delta)
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then
        return false
    end
    local before = math.floor(tonumber(self.navPageIndex) or 1)
    self.navPageIndex = before + (delta > 0 and 1 or -1)
    self:clampNavPage()
    if self.navPageIndex ~= before then
        self:applyStaticLayout()
        return true
    end
    return false
end

function GodSystemWindow:onNavPage(button)
    if not button then
        return
    end
    if button.internal == "up" then
        self:scrollNav(-1)
    elseif button.internal == "down" then
        self:scrollNav(1)
    end
end

function GodSystemWindow:relayoutIfNeeded(force)
    if self.relayouting or not self.list then
        return
    end
    self:enforceMinimumSize()
    local w = math.floor(self.width or 0)
    local h = math.floor(self.height or 0)
    if force or self.layoutW ~= w or self.layoutH ~= h then
        self.relayouting = true
        self.layoutW = w
        self.layoutH = h
        self:populateList()
        self.relayouting = false
    end
end

function GodSystemWindow:onResizeGripMouseDown(x, y)
    local grip = self:S(self.resizeGripSize or ((gsTheme().window or {}).resizeGripSize) or 18)
    return x >= (self.width - grip) and y >= (self.height - grip)
end

function GodSystemWindow:onMouseDown(x, y)
    if self:onResizeGripMouseDown(x, y) then
        self.resizingGodSystem = true
        self.resizeStartMouseX = getMouseX()
        self.resizeStartMouseY = getMouseY()
        self.resizeStartScale = self:getUIScale()
        self.resizeStartW = self.width
        self.resizeStartH = self.height
        return true
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function GodSystemWindow:onMouseWheel(del)
    local absX = self.getAbsoluteX and self:getAbsoluteX() or (self.x or 0)
    local absY = self.getAbsoluteY and self:getAbsoluteY() or (self.y or 0)
    local mx = getMouseX and (getMouseX() - absX) or 0
    local my = getMouseY and (getMouseY() - absY) or 0
    local navTop = (self.navY or 0) - self:S(8)
    local navBottom = navTop + (self.navH or 0) + self:S(16)
    if mx >= (self.navX or 0) and mx <= ((self.navX or 0) + (self.navW or 0)) and my >= navTop and my <= navBottom then
        if self:scrollNav(tonumber(del) or 0) then
            return true
        end
    end
    if ISCollapsableWindow.onMouseWheel then
        return ISCollapsableWindow.onMouseWheel(self, del)
    end
    return false
end

function GodSystemWindow:onMouseMove(dx, dy)
    if self.resizingGodSystem then
        local baseW = self:getBaseWidth()
        local baseH = self:getBaseHeight()
        local deltaX = getMouseX() - (self.resizeStartMouseX or getMouseX())
        local deltaY = getMouseY() - (self.resizeStartMouseY or getMouseY())
        local widthScale = ((self.resizeStartW or self.width or baseW) + deltaX) / math.max(1, baseW)
        local heightScale = ((self.resizeStartH or self.height or baseH) + deltaY) / math.max(1, baseH)
        local scale = math.max(widthScale, heightScale)
        self:setScaledSize(scale)
        self:setupLayoutMetrics()
        self:applyStaticLayout()
        return true
    end
    return ISCollapsableWindow.onMouseMove(self, dx, dy)
end

function GodSystemWindow:onMouseUp(x, y)
    if self.resizingGodSystem then
        self.resizingGodSystem = false
        self.resizeStartMouseX = nil
        self.resizeStartMouseY = nil
        self.resizeStartScale = nil
        self.resizeStartW = nil
        self.resizeStartH = nil
        local data = GodSystem.getData()
        data.ui.windowX = math.floor(self.x or 0)
        data.ui.windowY = math.floor(self.y or 0)
        data.ui.windowScale = self:getUIScale()
        GodSystem.save()
        self:relayoutIfNeeded(true)
        return true
    end
    return ISCollapsableWindow.onMouseUp(self, x, y)
end

function GodSystemWindow:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function GodSystemUI.deferredPopulateOnTick()
    local window = GodSystemUI.window
    if not window or not window.getIsVisible or not window:getIsVisible() then
        Events.OnTick.Remove(GodSystemUI.deferredPopulateOnTick)
        return
    end
    local ticks = math.max(0, math.floor(tonumber(window.deferredPopulateTicks) or 0))
    if ticks > 0 then
        window.deferredPopulateTicks = ticks - 1
        return
    end
    Events.OnTick.Remove(GodSystemUI.deferredPopulateOnTick)
    local mode = window.deferredPopulateMode
    window.deferredPopulateMode = nil
    if mode and mode == window.mode and not window.relayouting then
        window:populateList()
    end
end

function GodSystemWindow:requestDeferredPopulate(ticks)
    if not Events or not Events.OnTick then
        return
    end
    self.deferredPopulateMode = self.mode
    self.deferredPopulateTicks = math.max(0, math.floor(tonumber(ticks) or 1))
    Events.OnTick.Remove(GodSystemUI.deferredPopulateOnTick)
    Events.OnTick.Add(GodSystemUI.deferredPopulateOnTick)
end

function GodSystemWindow:applyStaticLayout()
    if self.navTitleLabel then
        gsSetBounds(self.navTitleLabel, self.topX + self:S(78), self.topY + self:S(19), nil, nil)
        gsSetLabel(self.navTitleLabel, gsTruncateText(GodSystem.text("Title", "God System"), UIFont.Large, self:S(210)))
    end
    if self.pointsLabel then
        gsSetBounds(self.pointsLabel, self.topX + self:S(320), self.topY + self:S(18), nil, nil)
    end
    if self.statsLabel then
        gsSetBounds(self.statsLabel, self.topX + self:S(320), self.topY + self:S(42), nil, nil)
    end
    if self.taskStatusLabel then
        gsSetBounds(self.taskStatusLabel, self.contentX + self.contentW - self:S(258), self.topY + self:S(42), nil, nil)
    end
    if self.pageTitleLabel then
        gsSetBounds(self.pageTitleLabel, self.contentX + self:S(16), self.contentY + self:S(10), nil, nil)
    end
    local pageCount = self:getNavPageCount()
    local perPage = self:getNavItemsPerPage()
    local pageButtonH = self.navPageButtonH or self:S(28)
    local navGap = self.navItemGap or self:S(8)
    local navViewportY
    if pageCount <= 1 then
        navViewportY = self.navY + navGap
    else
        local itemH = self.navItemH or self:S(56)
        local availableH = (self.navH or itemH)
            - (pageButtonH * 2)
            - (self.navBottomInset or self:S(8))
        navGap = math.max(navGap, (availableH - (perPage * itemH)) / (perPage + 1))
        navViewportY = self.navY + pageButtonH + navGap
    end
    self.navViewportY = navViewportY
    self.navLayoutGap = navGap
    if self.navPageUpButton then
        gsSetBounds(self.navPageUpButton, self.navX + self:S(10), self.navY, self.navW - self:S(20), pageButtonH)
        gsSetButtonTitle(self.navPageUpButton, gsTruncateText(GodSystem.text("Nav_PageUp", "Page up"), UIFont.Small, self.navW - self:S(30)))
    end
    if self.navPageDownButton then
        gsSetBounds(self.navPageDownButton, self.navX + self:S(10),
            self.navY + self.navH - pageButtonH - (self.navBottomInset or self:S(8)),
            self.navW - self:S(20), pageButtonH)
        gsSetButtonTitle(self.navPageDownButton, gsTruncateText(GodSystem.text("Nav_PageDown", "Page down"), UIFont.Small, self.navW - self:S(30)))
    end
    if self.modeButtons then
        local page = self:clampNavPage()
        local first = ((page - 1) * perPage) + 1
        for _, button in pairs(self.modeButtons) do
            local index = button.navIndex or 1
            local isTool = button.navTool == true
            local buttonH = isTool and (self.navToolH or 30) or (self.navItemH or 56)
            if isTool then
                local toolW = self:S(70)
                local gap = self:S(8)
                local toolIndex = button.navToolIndex or 1
                local x = self.contentX + self.contentW - self:S(12) - (toolIndex * toolW) - ((toolIndex - 1) * gap)
                gsSetBounds(button, x, self.contentY + self:S(8), toolW, buttonH)
                button:setVisible(true)
            else
                local gap = self.navLayoutGap or self.navItemGap or 8
                local normalIndex = button.navNormalIndex or index
                local displayIndex = normalIndex - first + 1
                local y = (self.navViewportY or self.navY)
                    + ((math.max(1, displayIndex) - 1) * (buttonH + gap))
                gsSetBounds(button, self.navX + self:S(10), y, self.navW - self:S(20), buttonH)
            end
            if button.setTitle then
                local font = isTool and UIFont.Small or UIFont.Medium
                local maxTitleW = isTool and self:S(58) or (self.navW - self:S(34))
                button:setTitle(gsTruncateText(button.modeLabel or "", font, maxTitleW))
            end
        end
        self:updateNavButtonVisibility()
    end
end

function GodSystemWindow:setDetailText(text)
    self.detailText = tostring(text or "")
    if self.detailList and self.detailList:getIsVisible() then
        self:resetScrollingListState(self.detailList)
        local lines = gsWrapText(self.detailText, UIFont.Small, (self.detailList.width or 240) - 18)
        for i = 1, #lines do
            self.detailList:addItem(lines[i], { kind = "detailLine", selectable = false })
        end
        return
    end
    local maxWidth = math.max(120, (self.width or 640) - 32)
    gsSetLabel(self.detailLabel, gsTruncateText(self.detailText, UIFont.Small, maxWidth))
end

function GodSystemWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setupLayoutMetrics()

    self.navTitleLabel = ISLabel:new(self.topX + 78, self.topY + 19, 28, GodSystem.text("Title", "God System"), 0.86, 0.84, 0.76, 1, UIFont.Large, true)
    self.navTitleLabel:initialise()
    self.navTitleLabel:setVisible(false)
    self:addChild(self.navTitleLabel)

    self.pointsLabel = ISLabel:new(self.topX + 320, self.topY + 18, 18, GodSystem.text("CurrencyLabel", "Currency: ") .. "0", 1, 0.68, 0.2, 1, UIFont.Small, true)
    self.pointsLabel:initialise()
    self.pointsLabel:setVisible(false)
    self:addChild(self.pointsLabel)

    self.statsLabel = ISLabel:new(self.topX + 320, self.topY + 42, 18, "", 0.74, 0.72, 0.65, 1, UIFont.Small, true)
    self.statsLabel:initialise()
    self.statsLabel:setVisible(false)
    self:addChild(self.statsLabel)

    self.taskStatusLabel = ISLabel:new(self.contentX + self.contentW - 258, self.topY + 42, 18, "", 0.62, 0.78, 0.72, 1, UIFont.Small, true)
    self.taskStatusLabel:initialise()
    self.taskStatusLabel:setVisible(false)
    self:addChild(self.taskStatusLabel)

    self.pageTitleLabel = ISLabel:new(self.contentX + self:S(16), self.contentY + self:S(10), 20, "", 0.86, 0.84, 0.76, 1, UIFont.Medium, true)
    self.pageTitleLabel:initialise()
    self:addChild(self.pageTitleLabel)

    self.navPageUpButton = ISButton:new(self.navX + self:S(10), self.navY, self.navW - self:S(20), self.navPageButtonH or self:S(28), GodSystem.text("Nav_PageUp", "Page up"), self, self.onNavPage)
    self.navPageUpButton.internal = "up"
    self.navPageUpButton:initialise()
    gsStyleButton(self.navPageUpButton, false)
    self:addChild(self.navPageUpButton)

    self.navPageDownButton = ISButton:new(self.navX + self:S(10), self.navY + self.navH - (self.navPageButtonH or self:S(28)), self.navW - self:S(20), self.navPageButtonH or self:S(28), GodSystem.text("Nav_PageDown", "Page down"), self, self.onNavPage)
    self.navPageDownButton.internal = "down"
    self.navPageDownButton:initialise()
    gsStyleButton(self.navPageDownButton, false)
    self:addChild(self.navPageDownButton)

    local tabs = {
        { id = "tasks", label = GodSystem.text("Tab_Tasks", "Tasks") },
        { id = "lottery", label = GodSystem.text("Tab_Lottery", "Lottery") },
        { id = "shop", label = GodSystem.text("Tab_Shop", "Shop") },
        { id = "bank", label = GodSystem.text("Tab_Bank", "Bank") },
        { id = "waist", label = GodSystem.text("Tab_WaistSpace", "Waist") },
        { id = "home", label = GodSystem.text("Tab_Home", "Home/Teleport") },
        { id = "traits", label = GodSystem.text("Tab_Traits", "Traits") },
        { id = "upgrades", label = GodSystem.text("Tab_Upgrades", "Upgrades") },
        { id = "shortcuts", label = GodSystem.text("Btn_Shortcuts", "Shortcuts"), tool = true },
        { id = "history", label = GodSystem.text("Tab_History", "History"), tool = true },
        { id = "info", label = GodSystem.text("Tab_Info", "Info"), tool = true },
        { id = "admin", label = GodSystem.text("Tab_Admin", "Admin"), tool = true },
        { id = "diagnostics", label = GodSystem.text("Tab_Diagnostics", "Diagnostics"), tool = true },
    }
    local attributesEnabled = GodSystem.isFeatureEnabled("EnableAttributes")
    if attributesEnabled then
        table.insert(tabs, 8, { id = "attribute", label = GodSystem.text("Tab_Attributes", "Attributes") })
    end
    if not gsIsMultiplayer() and GodSystemCompanionConfig.isEnabled() then
        table.insert(tabs, attributesEnabled and 10 or 9, { id = "companion", label = GodSystem.text("Tab_Companion", "Companion") })
    end
    self.modeButtons = {}
    local toolIndex = 0
    local normalIndex = 0
    for i = 1, #tabs do
        local isTool = tabs[i].tool == true
        if isTool then
            toolIndex = toolIndex + 1
        else
            normalIndex = normalIndex + 1
        end
        local buttonH = isTool and (self.navToolH or 30) or (self.navItemH or 56)
        local x = self.navX + self:S(10)
        local y = (self.navViewportY or self.navY) + ((math.max(1, normalIndex) - 1) * ((self.navItemH or 56) + (self.navItemGap or 8)))
        local w = self.navW - self:S(20)
        if isTool then
            w = self:S(70)
            local gap = self:S(8)
            x = self.contentX + self.contentW - self:S(12) - (toolIndex * w) - ((toolIndex - 1) * gap)
            y = self.contentY + self:S(8)
        end
        local button = ISButton:new(x, y, w, buttonH, tabs[i].label, self, self.onModeButton)
        button.internal = tabs[i].id
        button.modeLabel = tabs[i].label
        button.navIndex = i
        button.navTool = isTool
        button.navToolIndex = toolIndex
        button.navNormalIndex = isTool and nil or normalIndex
        button:initialise()
        gsStyleButton(button, false)
        self:addChild(button)
        self.modeButtons[tabs[i].id] = button
    end
    self.navNormalCount = normalIndex

    self.shopCategoryKey = "all"
    self.shopCategories = {}
    self.lotteryCategories = {}

    self.shopSearchLabel = ISLabel:new(self.mainX + self:S(168), self.actionY + self:S(18), 18, GodSystem.text("Search_Label", "Search"), 0.78, 0.78, 0.78, 1, UIFont.Small, true)
    self.shopSearchLabel:initialise()
    self.shopSearchLabel:setVisible(false)
    self:addChild(self.shopSearchLabel)

    self.shopSearchBox = ISTextEntryBox:new("", self.mainX + self:S(212), self.actionY + self:S(14), math.max(self:S(120), self.mainW - self:S(212)), self:S(28))
    self.shopSearchBox:initialise()
    self.shopSearchBox:instantiate()
    self.shopSearchBox.font = UIFont.Small
    self.shopSearchBox.target = self
    self.shopSearchBox.onTextChange = function(entry) self:onShopSearchChange(entry) end
    self.shopSearchBox:setVisible(false)
    self:addChild(self.shopSearchBox)

    self.list = ISScrollingListBox:new(self.mainX, self.mainY, self.mainW, self.mainH)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = self:S((gsTheme().window and gsTheme().window.rowHeight) or 44)
    self.list.doDrawItem = function(list, y, item, alt)
        return self:drawListItem(list, y, item, alt)
    end
    gsInstallSafeScrollingListPrerender(self.list)
    self.list:setOnMouseDownFunction(self, self.onListMouseDown)
    local oldRightMouseUp = self.list.onRightMouseUp
    self.list.onRightMouseUp = function(list, x, y)
        if self:onListRightMouseUp(x, y) then
            return true
        end
        if oldRightMouseUp then
            return oldRightMouseUp(list, x, y)
        end
        return false
    end
    self:addChild(self.list)

    self.detailHeaderLabel = ISLabel:new(self.detailX + self:S(12), self.contentY + self:S(10), 18, GodSystem.text("Panel_Detail", "Detail"), 1, 0.68, 0.2, 1, UIFont.Small, true)
    self.detailHeaderLabel:initialise()
    self:addChild(self.detailHeaderLabel)

    self.detailList = ISScrollingListBox:new(self.detailX, self.mainY, self.detailW, self.mainH)
    self.detailList:initialise()
    self.detailList:instantiate()
    self.detailList.itemheight = self:S(22)
    self.detailList.doDrawItem = function(list, y, item, alt)
        return self:drawListItem(list, y, item, alt)
    end
    gsInstallSafeScrollingListPrerender(self.detailList)
    self.detailList:setVisible(true)
    self:addChild(self.detailList)

    self.openTaskLabel = ISLabel:new(self.mainX, self.mainY - self:S(26), 18, GodSystem.text("Task_OpenColumn", "Available"), 0.95, 0.68, 0.22, 1, UIFont.Small, true)
    self.openTaskLabel:initialise()
    self.openTaskLabel:setVisible(false)
    self:addChild(self.openTaskLabel)

    self.activeTaskLabel = ISLabel:new(self.mainX + self:S(210), self.mainY - self:S(26), 18, GodSystem.text("Task_ActiveColumn", "Active"), 0.95, 0.68, 0.22, 1, UIFont.Small, true)
    self.activeTaskLabel:initialise()
    self.activeTaskLabel:setVisible(false)
    self:addChild(self.activeTaskLabel)

    self.activeList = ISScrollingListBox:new(self.mainX + self:S(210), self.mainY, self:S(200), self.mainH)
    self.activeList:initialise()
    self.activeList:instantiate()
    self.activeList.itemheight = self:S((gsTheme().window and gsTheme().window.taskRowHeight) or 44)
    self.activeList.doDrawItem = function(list, y, item, alt)
        return self:drawListItem(list, y, item, alt)
    end
    gsInstallSafeScrollingListPrerender(self.activeList)
    self.activeList:setOnMouseDownFunction(self, self.onActiveListMouseDown)
    local oldActiveRightMouseUp = self.activeList.onRightMouseUp
    self.activeList.onRightMouseUp = function(list, x, y)
        local payload = self:selectListRowAt(x, y, list, "active")
        if payload then
            self:updateDetail()
            return true
        end
        if oldActiveRightMouseUp then
            return oldActiveRightMouseUp(list, x, y)
        end
        return false
    end
    self.activeList:setVisible(false)
    self:addChild(self.activeList)

    self.detailLabel = ISLabel:new(self.mainX, self.actionY - self:S(24), 20, "", 0.85, 0.85, 0.85, 1, UIFont.Small, true)
    self.detailLabel:initialise()
    self.detailLabel:setVisible(false)
    self:addChild(self.detailLabel)

    self.primaryButton = ISButton:new(self.actionX, self.actionY + self:S(8), self:S(142), self.actionButtonH or self:S(38), GodSystem.text("Btn_Buy", "Buy"), self, self.onPrimaryAction)
    self.primaryButton:initialise()
    gsStyleActionButton(self.primaryButton, "primary")
    self:addChild(self.primaryButton)

    self.secondaryButton = ISButton:new(self.actionX + self:S(156), self.actionY + self:S(8), self:S(156), self.actionButtonH or self:S(38), GodSystem.text("Btn_Refresh", "Refresh"), self, self.onSecondaryAction)
    self.secondaryButton:initialise()
    gsStyleActionButton(self.secondaryButton, false)
    self:addChild(self.secondaryButton)

    self.thirdButton = ISButton:new(self.actionX + self:S(326), self.actionY + self:S(8), self:S(156), self.actionButtonH or self:S(38), GodSystem.text("Btn_RecycleBatch", "Batch recycle"), self, self.onThirdAction)
    self.thirdButton:initialise()
    gsStyleActionButton(self.thirdButton, false)
    self:addChild(self.thirdButton)

    self.fourthButton = ISButton:new(self.actionX + self:S(496), self.actionY + self:S(8), self:S(126), self.actionButtonH or self:S(38), "", self, self.onFourthAction)
    self.fourthButton:initialise()
    gsStyleActionButton(self.fourthButton, false)
    self.fourthButton:setVisible(false)
    self:addChild(self.fourthButton)

    self.fifthButton = ISButton:new(self.actionX + self:S(636), self.actionY + self:S(8), self:S(126), self.actionButtonH or self:S(38), "", self, self.onFifthAction)
    self.fifthButton:initialise()
    gsStyleActionButton(self.fifthButton, false)
    self.fifthButton:setVisible(false)
    self:addChild(self.fifthButton)

    self.categoryButton = ISButton:new(self.mainX, self.actionY + self:S(12), self:S(158), self:S(30), GodSystem.text("ShopCategory_ButtonAll", "Category: All"), self, self.onCategoryButton)
    self.categoryButton:initialise()
    gsStyleActionButton(self.categoryButton, false)
    self.categoryButton:setVisible(false)
    self:addChild(self.categoryButton)

    self:updateModeButtonStyles()
    self:applyStaticLayout()
    self:populateList()
    self.layoutW = math.floor(self.width or 0)
    self.layoutH = math.floor(self.height or 0)
end

function GodSystemWindow:drawFramePanel(x, y, width, height, fillColor, borderColor)
    gsDrawRect(self, x, y, width, height, fillColor or gsThemeColor("panel"))
    gsDrawRectBorder(self, x, y, width, height, borderColor or gsThemeColor("border"))
    gsDrawRectBorder(self, x + 3, y + 3, math.max(1, width - 6), math.max(1, height - 6), gsThemeColor("panelLine"))
end

function GodSystemWindow:drawProgressBar(x, y, width, height, value, maxValue)
    gsDrawProgressBar(self, x, y, width, height, value, maxValue, gsThemeColor("progressFill"))
end

function GodSystemWindow:getPlayerLoadText()
    local player = getPlayer and getPlayer() or nil
    if not player then
        return "-"
    end
    local inv = player.getInventory and player:getInventory() or nil
    if not inv then
        return "-"
    end
    local weight = inv.getCapacityWeight and inv:getCapacityWeight() or inv.getWeight and inv:getWeight() or 0
    local maxWeight = player.getMaxWeight and player:getMaxWeight() or 0
    return string.format("%.1f / %d", tonumber(weight) or 0, math.floor(tonumber(maxWeight) or 0))
end

function GodSystemWindow:getGameTimeText()
    local gt = GameTime and GameTime:getInstance() or nil
    if not gt then
        return "-"
    end
    local days = 0
    local hour = 0
    local minute = 0
    pcall(function()
        days = math.floor(tonumber(gt:getNightsSurvived()) or 0)
    end)
    pcall(function()
        hour = math.floor(tonumber(gt:getHour()) or 0)
        minute = math.floor(tonumber(gt:getMinutes()) or 0)
    end)
    return tostring(days) .. "d " .. string.format("%02d:%02d", hour, minute)
end

function GodSystemWindow:drawTopStatusCell(label, value, x, y, width)
    local h = self:S(44)
    gsDrawRect(self, x, y, width, h, gsThemeColor("topCell"))
    gsDrawRectBorder(self, x, y, width, h, gsThemeColor("panelLine"))
    gsDrawText(self, tostring(label or ""), x + self:S(10), y + self:S(7), gsThemeColor("dimText"), UIFont.Small)
    gsDrawText(self, tostring(value or ""), x + self:S(10), y + self:S(24), gsThemeColor("gold"), UIFont.Small)
end

function GodSystemWindow:drawTopStatusBar(activeCount)
    local data = GodSystem.getData()
    local stats = data.stats or {}
    local bankSummary = GodSystem.getBankSummary and GodSystem.getBankSummary() or {}
    local currency = GodSystem.getCurrencyTotal and GodSystem.getCurrencyTotal() or 0
    local completed = stats.completedTasks or 0
    local failed = stats.failedTasks or 0

    self:drawFramePanel(self.topX, self.topY, self.topW, self.topH, gsThemeColor("topBar"), gsThemeColor("borderStrong"))
    gsDrawRect(self, self.topX + self:S(18), self.topY + self:S(10), self:S(48), self:S(48), gsThemeColor("panelWarm"))
    gsDrawRectBorder(self, self.topX + self:S(18), self.topY + self:S(10), self:S(48), self:S(48), gsThemeColor("borderStrong"))
    gsDrawTextCentre(self, "GS", self.topX + self:S(18), self.topY + self:S(23), self:S(48), 1, 0.68, 0.2, 1, UIFont.Medium)

    gsDrawText(self, GodSystem.text("Title", "God System"), self.topX + self:S(78), self.topY + self:S(16), gsThemeColor("text"), UIFont.Large)
    gsDrawText(self, "v" .. tostring(GodSystemConfig.Version or "?"), self.topX + self:S(78), self.topY + self:S(44), gsThemeColor("dimText"), UIFont.Small)

    local startX = self.topX + self:S(270)
    local cellW = self:S(108)
    self:drawTopStatusCell(GodSystem.text("CurrencyLabel", "Currency"), gsFormatCompactNumber(currency), startX, self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystem.text("Tab_Bank", "Bank"), gsFormatCompactNumber(bankSummary.current or 0), startX + self:S(116), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystem.text("Task_ActiveColumn", "Active"), tostring(activeCount or 0) .. "/" .. tostring(GodSystem.getMaxActiveTasks()), startX + self:S(232), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystem.text("Stats_Completed", "Done"), tostring(completed), startX + self:S(348), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystem.text("Stats_Failed", "Failed"), tostring(failed), startX + self:S(464), self.topY + self:S(12), cellW)
    self:drawTopStatusCell("Load", self:getPlayerLoadText(), startX + self:S(580), self.topY + self:S(12), cellW)
    self:drawTopStatusCell("Time", self:getGameTimeText(), startX + self:S(696), self.topY + self:S(12), self:S(132))
end

function GodSystemWindow:prerender()
    self:relayoutIfNeeded(false)
    ISCollapsableWindow.prerender(self)
    local data = GodSystem.getData()
    gsSetLabel(self.pointsLabel, "")
    local stats = data.stats or {}
    local statsText = GodSystem.text("Stats_Completed", "Completed ") .. tostring(stats.completedTasks or 0) .. " | " .. GodSystem.text("Stats_Failed", "Failed ") .. tostring(stats.failedTasks or 0) .. " | " .. GodSystem.text("Stats_Daily", "Daily ") .. tostring(GodSystem.getDailyTaskCount())
    if (GodSystemConfig.DailyRecycleSoftCap or 0) > 0 then
        statsText = statsText .. " | " .. GodSystem.text("Stats_RecycleRemain", "Recycle left ") .. tostring(GodSystem.getRecycleDailyRemaining())
    end
    gsSetLabel(self.statsLabel, "")
    local activeCount = 0
    local tasks = data.tasks or {}
    for i = 1, #tasks do
        if tasks[i].status == "active" then
            activeCount = activeCount + 1
        end
    end
    gsSetLabel(self.taskStatusLabel, "")

    gsDrawRect(self, 0, self:S(16), self.width, self.height - self:S(16), gsThemeColor("shell"))
    gsDrawRectBorder(self, 1, self:S(17), self.width - 2, self.height - self:S(18), gsThemeColor("borderStrong"))
    self:drawTopStatusBar(activeCount)
    self:drawFramePanel(self.navX, self.navY - self:S(10), self.navW, self.navH + self:S(10), gsThemeColor("nav"), gsThemeColor("border"))
    self:drawFramePanel(self.contentX, self.contentY, self.contentW, self.contentH, gsThemeColor("panel"), gsThemeColor("border"))
    gsDrawRect(self, self.contentX + self:S(4), self.contentY + self:S(4), self.contentW - self:S(8), self.titleBarH or self:S(36), gsThemeColor("panelDeep"))
    gsDrawRectBorder(self, self.contentX + self:S(4), self.contentY + self:S(4), self.contentW - self:S(8), self.titleBarH or self:S(36), gsThemeColor("panelLine"))
    self:drawFramePanel(self.mainX - self:S(6), self.mainY - self:S(8), self.mainW + self:S(12), self.mainH + self:S(12), gsThemeColor("panelDeep"), gsThemeColor("border"))
    if self.detailList and self.detailList:getIsVisible() then
        local detailY = math.max(self.mainY - self:S(8), (self.detailList.y or self.mainY) - self:S(8))
        local detailH = math.max(self:S(120), (self.detailList.height or self.mainH) + self:S(12))
        self:drawFramePanel(self.detailX - self:S(6), detailY, self.detailW + self:S(12), detailH, gsThemeColor("panelDeep"), gsThemeColor("border"))
    end
    self:drawFramePanel(self.actionX - self:S(6), self.actionY, self.actionRight - self.actionX + self:S(12), self.actionH or self:S(54), gsThemeColor("panelWarm"), gsThemeColor("border"))
    local grip = self:S(self.resizeGripSize or ((gsTheme().window or {}).resizeGripSize) or 18)
    gsDrawRectBorder(self, self.width - grip - 2, self.height - grip - 2, grip, grip, gsThemeColor("borderStrong"))
end

function GodSystemWindow:onModeButton(button)
    if button and button.internal == "shortcuts" then
        if GodSystemUI.toggleShortcutWindow then
            GodSystemUI.toggleShortcutWindow(self)
        end
        return
    end
    self:captureSelection()
    self.mode = button.internal
    if self.mode == "info" then
        self:recordInfoSecretClick()
    end
    self:updateModeButtonStyles()
    self:populateList()
    self:requestDeferredPopulate(1)
end

function GodSystemWindow:recordInfoSecretClick()
    local now = gsNowMs()
    if now - (self.infoSecretLastClickMs or 0) > 4000 then
        self.infoSecretClicks = 0
    end
    self.infoSecretLastClickMs = now
    self.infoSecretClicks = (self.infoSecretClicks or 0) + 1
    if self.infoSecretClicks >= 5 then
        self.infoSecretClicks = 0
        self:showSecretGrantDialog()
    end
end

function GodSystemWindow:showSecretGrantDialog()
    if GodSystemUI.secretGrantDialog and GodSystemUI.secretGrantDialog.getIsVisible and GodSystemUI.secretGrantDialog:getIsVisible() then
        return
    end
    local w, h = 300, 130
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemSecretGrantDialog:new(x, y, w, h, self)
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setVisible(true)
    GodSystemUI.secretGrantDialog = dialog
end

function GodSystemWindow:updateModeButtonStyles()
    if not self.modeButtons then
        return
    end
    for id, button in pairs(self.modeButtons) do
        if id == "admin" then
            button:setVisible(GodSystem.isAdminConfigAllowed and GodSystem.isAdminConfigAllowed() == true)
            if self.mode == "admin" and not button:getIsVisible() then
                self.mode = "info"
            end
        end
        gsStyleButton(button, id == self.mode)
    end
    if self.pageTitleLabel and self.modeButtons[self.mode] then
        gsSetLabel(self.pageTitleLabel, self.modeButtons[self.mode].modeLabel or "")
    end
end

function GodSystemWindow:onListMouseDown(item)
    local payload = self:getPayloadFromListCallback(item)
    if not gsIsSelectablePayload(payload) then
        self.list.selected = math.floor(tonumber(self.lastSelectableListRow) or 0)
        return
    end
    self.lastSelectableListRow = math.floor(tonumber(self.list.selected) or 0)
    if self.mode == "tasks" then
        self:clearOppositeTaskSelection("open")
    elseif self.mode == "waist" then
        if payload and payload.kind == "waist" and payload.data then
            self.waistSelected = self.waistSelected or {}
            local fullType = payload.data.fullType
            self.waistSelected[fullType] = not self.waistSelected[fullType]
            self:populateList()
            return
        end
    end
    self:updateDetail()
end

function GodSystemWindow:onActiveListMouseDown(item)
    local payload = self:getPayloadFromListCallback(item)
    if not gsIsSelectablePayload(payload) then
        self.activeList.selected = math.floor(tonumber(self.lastSelectableActiveRow) or 0)
        return
    end
    self.lastSelectableActiveRow = math.floor(tonumber(self.activeList.selected) or 0)
    self:clearOppositeTaskSelection("active")
    self:updateDetail()
end

function GodSystemWindow:clearOppositeTaskSelection(taskListName)
    if self.mode ~= "tasks" then
        return
    end
    taskListName = taskListName == "active" and "active" or "open"
    self.selectedTaskList = taskListName
    if taskListName == "active" then
        if self.list then self.list.selected = 0 end
        self.lastSelectableListRow = 0
    else
        if self.activeList then self.activeList.selected = 0 end
        self.lastSelectableActiveRow = 0
    end
end

function GodSystemWindow:drawListItem(list, y, item, alt)
    if not item then
        return y
    end
    local payload = item.item or {}
    local rowText = tostring(item.text or payload.displayText or payload.label or "")
    local selectable = gsIsSelectablePayload(payload)
    if payload.kind == "spacer" then
        return y + math.max(self:S(10), math.floor((list.itemheight or self:S(24)) / 2))
    end
    if payload.kind == "detailLine" then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("rowAlt"))
        gsDrawText(list, rowText, self:S(8), y + self:S(4), gsThemeColor("dimText"), UIFont.Small)
        return y + list.itemheight
    end
    if GS_SECTION_HEADER_KINDS[payload.kind] then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("panelWarm"))
    elseif GS_INFO_ROW_KINDS[payload.kind] then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("rowAlt"))
    elseif payload.kind == "empty" then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("panel"))
    else
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, alt and gsThemeColor("rowAlt") or gsThemeColor("row"))
    end
    if selectable and list.selected == item.index then
        gsDrawRect(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("rowSelect"))
        gsDrawRectBorder(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("borderStrong"))
    else
        gsDrawRectBorder(list, 0, y, list.width, list.itemheight - 1, gsThemeColor("border"))
    end

    if payload.kind == "task" and payload.data then
        local task = payload.data
        local target = math.max(1, math.floor(tonumber(task.target) or 1))
        local progress = math.min(GodSystem.getTaskProgress(task), target)
        local status = GodSystem.getTaskStatusText(task)
        local titleWidth = math.max(self:S(80), list.width - self:S(22))
        local title = gsTruncateText(GodSystem.getTaskListTitle(task), UIFont.Small, titleWidth)
        local line = gsTruncateText(GodSystem.getTaskListStatusLine(task), UIFont.Small, titleWidth)
        local textColor = task.status == "open" and gsThemeColor("text") or gsThemeColor("gold")
        gsDrawText(list, title, self:S(12), y + self:S(6), textColor, UIFont.Small)
        gsDrawText(list, line, self:S(12), y + self:S(24), task.status == "active" and gsThemeColor("gold") or gsThemeColor("dimText"), UIFont.Small)
        gsDrawProgressBar(list, self:S(12), y + self:S(44), math.max(self:S(70), list.width - self:S(24)), math.max(4, self:S(7)), progress, target, gsThemeColor("progressFill"))
        return y + list.itemheight
    end

    local detailRaw = tostring(payload.detail or "")
    if payload.kind == "history" or payload.kind == "info" then
        detailRaw = ""
    end
    local detailWidth = math.min(math.max(self:S(92), math.floor(list.width * 0.42)), math.max(self:S(92), list.width - self:S(90)))
    if payload.kind == "task" then
        detailWidth = math.min(self:S(96), math.max(self:S(44), gsMeasureText(UIFont.Small, detailRaw) + self:S(10)))
        detailWidth = math.min(detailWidth, math.max(self:S(44), math.floor(list.width * 0.30)))
    end
    local detailX = list.width - detailWidth - self:S(8)
    local textWidth = (detailRaw == "") and math.max(self:S(40), list.width - self:S(16)) or math.max(self:S(40), detailX - self:S(16))
    local text = gsTruncateText(rowText, UIFont.Small, textWidth)
    local detail = gsTruncateText(detailRaw, UIFont.Small, detailWidth)
    local textColor = gsThemeColor("text")
    if payload.kind == "empty" or GS_INFO_ROW_KINDS[payload.kind] then
        textColor = gsThemeColor("dimText")
    elseif GS_SECTION_HEADER_KINDS[payload.kind] then
        textColor = gsThemeColor("gold")
    end
    local textY = y + math.max(self:S(6), math.floor(((list.itemheight or self:S(30)) - self:S(18)) / 2))
    gsDrawText(list, text, self:S(10), textY, textColor, UIFont.Small)
    if detail ~= "" then
        gsDrawText(list, detail, detailX, textY, gsThemeColor("dimText"), UIFont.Small)
    end
    return y + list.itemheight
end

GodSystemWindow.ShopPageSize = 20

function GodSystemWindow:captureScrollState()
    self.restoreScrollMode = self.mode
    self.restoreScrollCategory = self.shopCategoryKey
    self.restoreScrollShopSearch = self.shopSearchText
    self.restoreScrollRecycleSearch = self.recycleSearchText
    self.restoreScrollY = 0
    if self.list and self.list.getYScroll then
        local ok, value = pcall(function() return self.list:getYScroll() end)
        if ok then self.restoreScrollY = value or 0 end
    end
end

function GodSystemWindow:restoreScrollState()
    local pending = self.pendingRestoreMode == self.mode and self.pendingRestoreScroll or nil
    local restoreMode = pending and pending.mode or self.restoreScrollMode
    local restoreCategory = pending and pending.category or self.restoreScrollCategory
    local restoreShopSearch = pending and pending.shopSearch or self.restoreScrollShopSearch
    local restoreRecycleSearch = pending and pending.recycleSearch or self.restoreScrollRecycleSearch
    local restoreY = pending and pending.y or self.restoreScrollY
    if restoreMode ~= self.mode then return end
    if self.mode == "shop" then
        if restoreCategory ~= self.shopCategoryKey then return end
        if restoreShopSearch ~= self.shopSearchText then return end
    elseif self.mode == "recycle" then
        if restoreRecycleSearch ~= self.recycleSearchText then return end
    end
    if self.list and self.list.setYScroll and restoreY then
        self.list:setYScroll(restoreY)
    end
end

function GodSystemWindow:clearPendingActionSelection()
    self.pendingRestoreSelectedId = nil
    self.pendingRestoreSelectedTaskList = nil
    self.pendingRestoreMode = nil
    self.pendingRestoreScroll = nil
end

function GodSystemWindow:resetScrollingListState(list)
    if not list then
        return
    end
    if list.clear then
        list:clear()
    end
    list.selected = 0
    list.mouseoverselected = -1
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
    if list.setYScroll then
        list:setYScroll(0)
    end
    if list.setScrollHeight then
        list:setScrollHeight(0)
    end
    gsSyncScrollingListGeometry(list)
end

function GodSystemWindow:clearList()
    self:resetScrollingListState(self.list)
    self.lastSelectableListRow = 0
    if self.activeList then
        self:resetScrollingListState(self.activeList)
        self.lastSelectableActiveRow = 0
    end
    if self.detailList then
        self:resetScrollingListState(self.detailList)
    end
    self:setDetailText("")
end

function GodSystemWindow:addListItem(text, payload)
    payload = payload or {}
    if GS_NON_SELECTABLE_KINDS[payload.kind] then payload.selectable = false end
    payload.displayText = tostring(text or "")
    self.list:addItem(text, payload)
end

function GodSystemWindow:addActiveListItem(text, payload)
    payload = payload or {}
    if GS_NON_SELECTABLE_KINDS[payload.kind] then payload.selectable = false end
    payload.displayText = tostring(text or "")
    self.activeList:addItem(text, payload)
end

function GodSystemWindow:addWrappedListText(text, payload)
    local width = math.max(self:S(120), (self.list and self.list.width or self.mainW or self:S(300)) - self:S(18))
    local lines = gsWrapText(text, UIFont.Small, width)
    if payload and payload.kind == "spacer" and #lines == 1 and lines[1] == "" then
        self:addListItem("", payload)
        return
    end
    for i = 1, #lines do
        local rowPayload = {}
        local source = payload or {}
        for key, value in pairs(source) do
            rowPayload[key] = value
        end
        if i > 1 and source.kind == "history" then
            rowPayload.detail = ""
        end
        self:addListItem(lines[i], rowPayload)
    end
end

function GodSystemWindow:formatHistoryEntry(entry)
    if not entry then
        return GodSystem.text("Tab_History", "History")
    end
    if entry.code then
        local template = GodSystem.text("HistoryMP_" .. tostring(entry.code), "")
        if template and template ~= "" then
            local args = {}
            for i = 1, #(entry.args or {}) do
                args[i] = entry.args[i]
            end
            if entry.taskId then
                args = { GodSystem.getTaskTitle({ sourceId = entry.taskId, title = entry.taskTitle }) }
                if entry.args then
                    for i = 1, #entry.args do args[#args + 1] = entry.args[i] end
                end
            elseif entry.shopId then
                args = { GodSystem.getShopLabel({ id = entry.shopId, items = entry.shopItems }) }
                if entry.args then
                    for i = 1, #entry.args do args[#args + 1] = entry.args[i] end
                end
            end
            if entry.code == "UpgradeSystem" and args[1] then
                local info = GodSystem.getSystemUpgradeInfo(tostring(args[1]))
                if info and info.label then
                    args[1] = info.label
                end
            elseif entry.code == "MedicalService" and args[1] then
                local info = GodSystem.getMedicalServiceInfo and GodSystem.getMedicalServiceInfo(tostring(args[1])) or nil
                if info and info.label then
                    args[1] = info.label
                end
            elseif (entry.code == "BankInvestmentCreated" or entry.code == "BankInvestmentRedeemed" or entry.code == "BankInvestmentSettled") and args[1] then
                args[1] = GodSystem.getBankInvestmentLabel(tostring(args[1]))
            end
            return gsFormatTemplate(template, args)
        end
    end
    return tostring(entry.text or GodSystem.text("Tab_History", "History"))
end

function GodSystemWindow:setTextPageLayout(enabled)
    if not enabled then
        return
    end
    local width = math.max(self:S(300), (self.actionRight or self.panelRight or (self.mainX + self.mainW)) - self.mainX)
    gsSetBounds(self.list, self.mainX, self.mainY, width, self.mainH)
    self.list.itemheight = self:S(24)
    if self.detailList then
        self.detailList:setVisible(false)
        self.detailList:clear()
    end
    if self.detailHeaderLabel then
        self.detailHeaderLabel:setVisible(false)
    end
end

function GodSystemWindow:formatHomeSource(source)
    local key = tostring(source or "")
    if key ~= "" then
        local text = GodSystem.text("HomeSource_" .. key, "")
        if text and text ~= "" then
            return text
        end
        return key
    end
    return GodSystem.text("Home_ReturnPoint", "return point")
end

function GodSystemWindow:getPayloadId(payload)
    if not payload then
        return nil
    end
    if payload.kind == "task" and payload.data then
        return "task:" .. tostring(payload.data.taskId or payload.data.sourceId or "")
    end
    if payload.kind == "shop" and payload.data then
        return "shop:" .. tostring(payload.data.id or payload.data.fullType or GodSystem.getShopPrimaryFullType(payload.data) or "")
    end
    if payload.kind == "recycle" and payload.data then
        return "recycle:" .. tostring(payload.data.fullType or "")
    end
    if payload.kind == "waist" and payload.data then
        return "waist:" .. tostring(payload.data.fullType or "")
    end
    if payload.kind == "bankTerm" and payload.data then
        return "bankTerm:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankFixed" and payload.data then
        return "bankFixed:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankInvestment" then
        local profile = payload.profile or {}
        local account = payload.data or {}
        return "bankInvestment:" .. tostring(profile.id or account.tierId or "")
    end
    if payload.kind == "bankLoanPlan" and payload.data then
        return "bankLoanPlan:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankLoanActive" and payload.data then
        return "bankLoanActive:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "trait" and payload.data then
        return "trait:" .. tostring(payload.data.action or "") .. ":" .. tostring(payload.data.traitType or "")
    end
    if payload.kind == "attribute" and payload.data then
        return "attribute:" .. tostring(payload.data.index or "")
    end
    if payload.kind == "upgrade" and payload.data then
        return "upgrade:" .. tostring(payload.data.upgradeType or "")
    end
    if payload.kind == "medicalService" and payload.data then
        return "medical:" .. tostring(payload.data.action or "")
    end
    if payload.kind == "companionNode" then
        return "companionNode:" .. tostring(payload.id or "")
    end
    if payload.kind == "homePoint" and payload.data then
        return "home:" .. tostring(payload.data.kind or "") .. ":" .. tostring(payload.data.index or "")
    end
    return nil
end

function GodSystemWindow:captureSelection()
    if self.pendingRestoreSelectedId and self.pendingRestoreMode == self.mode then
        return
    end
    local payload = self:getSelectedPayload()
    self.restoreSelectedId = self:getPayloadId(payload)
    self.restoreSelectedTaskList = self.selectedTaskList
end

function GodSystemWindow:prepareActionSelection(payload)
    local selectedId = self:getPayloadId(payload or self:getSelectedPayload())
    if not selectedId or selectedId == "" then return end
    self.pendingRestoreSelectedId = selectedId
    self.pendingRestoreSelectedTaskList = self.selectedTaskList
    self.pendingRestoreMode = self.mode
    self.restoreSelectedId = selectedId
    self.restoreSelectedTaskList = self.selectedTaskList
    self:captureScrollState()
    self.pendingRestoreScroll = {
        mode = self.restoreScrollMode,
        category = self.restoreScrollCategory,
        shopSearch = self.restoreScrollShopSearch,
        recycleSearch = self.restoreScrollRecycleSearch,
        y = self.restoreScrollY,
    }
end

function GodSystemWindow:restoreSelection()
    local selectedId = self.pendingRestoreMode == self.mode and self.pendingRestoreSelectedId or self.restoreSelectedId
    if not selectedId or selectedId == "" then
        return false
    end
    local function selectInList(list)
        if not list or not list.items then
            return false
        end
        for i = 1, #list.items do
            local item = list.items[i]
            if self:getPayloadId(item and item.item) == selectedId then
                list.selected = i
                if list == self.activeList then
                    self.lastSelectableActiveRow = i
                else
                    self.lastSelectableListRow = i
                end
                return true
            end
        end
        return false
    end
    if self.mode == "tasks" and self.restoreSelectedTaskList == "active" and selectInList(self.activeList) then
        self:clearOppositeTaskSelection("active")
        return true
    end
    if selectInList(self.list) then
        if self.mode == "tasks" then
            self:clearOppositeTaskSelection("open")
        end
        return true
    end
    if self.mode == "tasks" and selectInList(self.activeList) then
        self:clearOppositeTaskSelection("active")
        return true
    end
    return false
end

function GodSystemWindow:addSyncPlaceholder(detail)
    self:addListItem(GodSystem.text("State_Syncing", "正在同步服务器数据..."), { kind = "empty", detail = detail or GodSystem.text("State_SyncingHint", "请稍等，服务器状态返回后会自动刷新。") })
end

function GodSystemWindow:needsServerState()
    if not gsIsMultiplayer() then
        return false
    end
    return not gsHasServerState()
end

function GodSystemWindow:finishMultiplayerCommand(sent)
    if not gsIsMultiplayer() then
        self:populateList()
        return sent ~= false
    end
    if sent == false then
        self.waitingForServerState = false
        GodSystemNetwork.requestState(true)
        self:populateList()
        return false
    end
    self.waitingForServerState = true
    if GodSystemNetwork and GodSystemNetwork.requestState then
        GodSystemNetwork.requestState(false)
    end
    return true
end

function GodSystemWindow:requestServerRefresh()
    if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.requestState then
        self.waitingForServerState = true
        GodSystemNetwork.requestState(true)
        return true
    end
    return false
end

function GodSystemWindow:getActionControl(id)
    if id == "primary" then
        return self.primaryButton
    elseif id == "secondary" then
        return self.secondaryButton
    elseif id == "third" then
        return self.thirdButton
    elseif id == "fourth" then
        return self.fourthButton
    elseif id == "fifth" then
        return self.fifthButton
    elseif id == "category" then
        return self.categoryButton
    elseif id == "searchLabel" then
        return self.shopSearchLabel
    elseif id == "searchBox" then
        return self.shopSearchBox
    end
    return nil
end

function GodSystemWindow:hideActionControls()
    local ids = { "primary", "secondary", "third", "fourth", "fifth", "category", "searchLabel", "searchBox" }
    for i = 1, #ids do
        local control = self:getActionControl(ids[i])
        if control then
            control:setVisible(false)
        end
    end
end

function GodSystemWindow:setActionBar(actions)
    self:hideActionControls()
    local visibleActions = {}
    local requested = 0
    for i = 1, #(actions or {}) do
        local action = actions[i]
        local control = action and (action.control or self:getActionControl(action.id))
        if control and action.visible ~= false then
            action.control = control
            action.requestedWidth = self:S(tonumber(action.width) or 120)
            requested = requested + action.requestedWidth
            table.insert(visibleActions, action)
        end
    end
    local x = self.actionX or (self.contentX + self:S(12))
    local rowY = self.actionY + self:S(8)
    local actionTheme = (gsTheme().actionButtons or {})
    local gap = self:S(actionTheme.gap or ((#visibleActions > 4) and 8 or 14))
    local right = self.actionRight or (self.contentX + self.contentW - self:S(12))
    local available = math.max(self:S(80), right - x - (math.max(0, #visibleActions - 1) * gap))
    local scale = requested > available and (available / requested) or 1
    for i = 1, #visibleActions do
        local action = visibleActions[i]
        local control = action.control
        local minWidth = self:S(tonumber(action.minWidth) or 70)
        local width = math.floor(action.requestedWidth * scale)
        width = math.max(minWidth, width)
        if i == #visibleActions then
            width = math.max(minWidth, right - x)
        end
        local height = math.floor(tonumber(action.height) and self:S(action.height) or actionTheme.height and self:S(actionTheme.height) or self.actionButtonH or self:S(38))
        local title = action.title or control.fullTitle or control.title
        if control.setTitle and title and width > 0 then
            control:setTitle(gsTruncateText(title, UIFont.Small, width - self:S(12)))
        end
        if x + width > right then
            width = math.max(minWidth, right - x)
        end
        if width > 0 then
            control:setVisible(true)
            gsSetBounds(control, x, rowY + math.floor(tonumber(action.offsetY) or 0), width, height)
            x = x + width + gap
        end
        if x >= right then
            break
        end
    end
end

function GodSystemWindow:setStandardActionBar()
    local actions = {}
    if self.primaryButton and self.primaryButton:getIsVisible() then
        table.insert(actions, { id = "primary", width = 122 })
    end
    if self.secondaryButton and self.secondaryButton:getIsVisible() then
        table.insert(actions, { id = "secondary", width = 122 })
    end
    if self.thirdButton and self.thirdButton:getIsVisible() then
        table.insert(actions, { id = "third", width = 122 })
    end
    if self.fourthButton and self.fourthButton:getIsVisible() then
        table.insert(actions, { id = "fourth", width = 122 })
    end
    if self.fifthButton and self.fifthButton:getIsVisible() then
        table.insert(actions, { id = "fifth", width = 122 })
    end
    self:setActionBar(actions)
end

function GodSystemWindow:applyBaseLayout()
    self:setupLayoutMetrics()
    self:applyStaticLayout()
    if self.openTaskLabel then
        self.openTaskLabel:setVisible(false)
    end
    if self.activeTaskLabel then
        self.activeTaskLabel:setVisible(false)
    end
    if self.activeList then
        self.activeList:setVisible(false)
    end
    if self.detailLabel then
        self.detailLabel:setVisible(false)
    end
    if self.detailList then
        self.detailList:setVisible(true)
        gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        self.detailList.itemheight = self:S(22)
    end
    if self.detailHeaderLabel then
        self.detailHeaderLabel:setVisible(true)
        gsSetBounds(self.detailHeaderLabel, self.detailX + self:S(8), self:S(88), nil, nil)
    end
    if self.categoryButton then
        self.categoryButton:setVisible(false)
    end
    if self.shopSearchLabel then
        self.shopSearchLabel:setVisible(false)
    end
    if self.shopSearchBox then
        self.shopSearchBox:setVisible(false)
    end
    if self.fourthButton then
        self.fourthButton:setVisible(false)
    end
    if self.fifthButton then
        self.fifthButton:setVisible(false)
    end
    gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
    self.list.itemheight = self:S((gsTheme().window and gsTheme().window.rowHeight) or 44)
    self:setStandardActionBar()
end

function GodSystemWindow:applyShopActionLayout()
    local thirdVisible = self.thirdButton and self.thirdButton:getIsVisible()
    self:setActionBar({
        { id = "category", width = 112, minWidth = 96 },
        { id = "searchBox", width = 122, minWidth = 96 },
        { id = "primary", width = 74, minWidth = 58 },
        { id = "secondary", width = 82, minWidth = 68, visible = not gsIsMultiplayer() },
        { id = "third", width = 88, minWidth = 72, visible = thirdVisible == true },
        { id = "fourth", width = 78, minWidth = 62 },
        { id = "fifth", width = 78, minWidth = 62 },
    })
end

function GodSystemWindow:applyRecycleActionLayout()
    self:setActionBar({
        { id = "searchBox", width = 210, minWidth = 140 },
        { id = "primary", width = 90, minWidth = 72 },
        { id = "secondary", width = 100, minWidth = 82, visible = not gsIsMultiplayer() },
        { id = "third", width = 118, minWidth = 96 },
    })
end

function GodSystemWindow:applyLotteryActionLayout()
    self:setActionBar({
        { id = "category", width = 150, minWidth = 120 },
        { id = "primary", width = 92, minWidth = 78 },
        { id = "secondary", width = 92, minWidth = 78 },
        { id = "searchBox", width = 110, minWidth = 82 },
        { id = "third", width = 120, minWidth = 96 },
    })
end

function GodSystemWindow:setTaskLayout(enabled)
    if self.openTaskLabel then
        self.openTaskLabel:setVisible(enabled)
    end
    if self.activeTaskLabel then
        self.activeTaskLabel:setVisible(enabled)
    end
    if self.activeList then
        self.activeList:setVisible(enabled)
    end
    if self.detailList then
        self.detailList:setVisible(true)
        gsSetBounds(self.detailList, self.detailX, self:S(136), self.detailW, self.actionY - self:S(146))
        self.detailList.itemheight = self:S(22)
    end
    if self.detailLabel then
        self.detailLabel:setVisible(false)
    end
    if enabled then
        local gap = self:S(12)
        local colW = math.floor((self.mainW - gap) / 2)
        local win = (gsTheme().window or {})
        local taskHeaderH = self:S(win.taskHeaderHeight or 18)
        local taskHeaderGap = self:S(win.taskHeaderGap or 8)
        local taskY = self.mainY
        local taskH = math.max(self:S(160), self.mainH)
        gsSetBounds(self.list, self.mainX, taskY, colW, taskH)
        self.list.itemheight = self:S((gsTheme().window and gsTheme().window.taskRowHeight) or 44)
        if self.activeList then
            gsSetBounds(self.activeList, self.mainX + colW + gap, taskY, colW, taskH)
            self.activeList.itemheight = self:S((gsTheme().window and gsTheme().window.taskRowHeight) or 44)
        end
        if self.openTaskLabel then
            gsSetBounds(self.openTaskLabel, self.list.x, self.mainY - taskHeaderH - taskHeaderGap, nil, nil)
        end
        if self.activeTaskLabel then
            gsSetBounds(self.activeTaskLabel, self.activeList and self.activeList.x or (self.mainX + colW + gap), self.mainY - taskHeaderH - taskHeaderGap, nil, nil)
        end
    else
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if self.activeList then
            gsSetBounds(self.activeList, nil, nil, nil, self.mainH)
        end
    end
end

function GodSystemWindow:setShopLayout(enabled)
    local adminMode = self.mode == "admin"
    local attributeMode = self.mode == "attribute"
    local searchEnabled = enabled or adminMode or attributeMode
    local shopMode = enabled and self.mode == "shop"
    local lotteryMode = enabled and self.mode == "lottery"
    if self.categoryButton then
        self.categoryButton:setVisible(shopMode or lotteryMode)
    end
    if self.shopSearchLabel then
        self.shopSearchLabel:setVisible(false)
    end
    if self.shopSearchBox then
        self.shopSearchBox:setVisible(searchEnabled)
    end
    if searchEnabled then
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if adminMode then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        elseif attributeMode then
            self:setStandardActionBar()
        elseif shopMode then
            self:applyShopActionLayout()
        elseif lotteryMode then
            self:applyLotteryActionLayout()
        else
            self:applyRecycleActionLayout()
        end
        if self.detailList then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        end
    elseif self.mode ~= "tasks" then
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if self.detailList then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        end
    end
end

function GodSystemWindow:updateShopCategoryButton(categories)
    self.shopCategories = categories or {}
    local selectedLabel = GodSystem.text("ShopCategory_All", "All categories")
    for i = 1, #(categories or {}) do
        local category = categories[i]
        if category.key == self.shopCategoryKey then
            selectedLabel = category.label
        end
    end
    if selectedLabel == GodSystem.text("ShopCategory_All", "All categories") and self.shopCategoryKey ~= "all" then
        self.shopCategoryKey = "all"
    end
    if self.categoryButton then
        gsSetButtonTitle(self.categoryButton, tostring(selectedLabel))
    end
end

function GodSystemWindow:updateLotteryCategoryButton(categories)
    self.lotteryCategories = categories or {}
    local selectedLabel = GodSystem.text("Lottery_ModeAll", "All categories")
    for i = 1, #(categories or {}) do
        local category = categories[i]
        if category.key == self.lotteryCategoryKey then
            selectedLabel = category.label
        end
    end
    if self.lotteryCategoryKey ~= "all" and selectedLabel == GodSystem.text("Lottery_ModeAll", "All categories") then
        self.lotteryCategoryKey = "all"
    end
    if self.categoryButton then
        gsSetButtonTitle(self.categoryButton, tostring(selectedLabel))
    end
end

function GodSystemWindow:updateTaskPrimaryButton(payload)
    if self.mode ~= "tasks" or not self.primaryButton then
        return
    end
    local title = GodSystem.text("Btn_TaskAccept", "Accept")
    local variant = "primary"
    if payload and payload.kind == "task" and payload.data then
        local task = payload.data
        if task.status == "open" then
            title = GodSystem.text("Btn_TaskAccept", "Accept")
            variant = "primary"
        elseif task.status == "active" then
            if GodSystem.isTaskComplete(task) then
                title = GodSystem.text("Btn_TaskClaim", "Claim reward")
                variant = "primary"
            else
                title = GodSystem.text("Btn_TaskAbandon", "Abandon")
                variant = "danger"
            end
        elseif task.status == "failed" then
            title = GodSystem.text("Status_Failed", "Failed")
            variant = false
        elseif task.status == "claimed" then
            title = GodSystem.text("Status_Claimed", "Claimed")
            variant = false
        end
    end
    gsSetButtonTitle(self.primaryButton, title)
    gsStyleActionButton(self.primaryButton, variant)
end

function GodSystemWindow:setShopCategory(key)
    key = key or "all"
    if key ~= self.shopCategoryKey then
        self.shopCategoryKey = key
        self.shopPage = 1
        self:populateList()
    end
end

function GodSystemWindow:setLotteryCategory(key)
    key = key or "all"
    if key ~= self.lotteryCategoryKey then
        self.lotteryCategoryKey = key
        self:populateList()
    end
end

function GodSystemWindow:changeShopPage(delta)
    self.shopPage = math.max(1, math.floor((self.shopPage or 1) + (delta or 0)))
    self:populateList()
end

function GodSystemWindow:onShopCategoryButton()
    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(GodSystem.text("ShopCategory_All", "All categories"), self, self.setShopCategory, "all")
    for i = 1, #(self.shopCategories or {}) do
        local category = self.shopCategories[i]
        context:addOption(tostring(category.label or category.key), self, self.setShopCategory, category.key)
    end
end

function GodSystemWindow:onLotteryCategoryButton()
    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(GodSystem.text("Lottery_ModeAll", "All categories"), self, self.setLotteryCategory, "all")
    for i = 1, #(self.lotteryCategories or {}) do
        local category = self.lotteryCategories[i]
        context:addOption(tostring(category.label or category.key) .. " (" .. tostring(category.price or 0) .. GodSystem.text("Unit_CoinShort", "c") .. ")", self, self.setLotteryCategory, category.key)
    end
end

function GodSystemWindow:onCategoryButton()
    if self.mode == "lottery" then
        return self:onLotteryCategoryButton()
    end
    return self:onShopCategoryButton()
end

function GodSystemWindow:onShopSearchChange(entry)
    if self.suppressSearchChange == true then
        return
    end
    if self.mode ~= "shop" and self.mode ~= "recycle" and self.mode ~= "admin" and self.mode ~= "lottery" and self.mode ~= "attribute" then
        return
    end
    local text = ""
    if entry and entry.getInternalText then
        text = entry:getInternalText() or ""
    elseif self.shopSearchBox and self.shopSearchBox.getInternalText then
        text = self.shopSearchBox:getInternalText() or ""
    end
    if self.shopSearchPurpose == "recycle" then
        if text ~= self.recycleSearchText then
            self.recycleSearchText = text
            self:populateList()
        end
    elseif self.shopSearchPurpose == "admin" then
        if text ~= self.adminSearchText then
            self.adminSearchText = text
            self:populateList()
        end
    elseif self.shopSearchPurpose == "attribute" then
        if text ~= self.attributeSearchText then
            self.attributeSearchText = text
            self:populateList()
        end
    elseif self.shopSearchPurpose == "lottery" then
        local value = math.floor(tonumber(text) or 0)
        if value > 0 then
            self.lotteryCustomCount = value
        end
    else
        if text ~= self.shopSearchText then
            self.shopSearchText = text
            self.shopPage = 1
            self:populateList()
        end
    end
end

function GodSystemWindow:syncSearchBoxText(purpose)
    self.shopSearchPurpose = purpose or "shop"
    if not self.shopSearchBox or not self.shopSearchBox.setText then
        return
    end
    local text = self.shopSearchText or ""
    if self.shopSearchPurpose == "recycle" then
        text = self.recycleSearchText or ""
    elseif self.shopSearchPurpose == "admin" then
        text = self.adminSearchText or ""
    elseif self.shopSearchPurpose == "attribute" then
        text = self.attributeSearchText or ""
    elseif self.shopSearchPurpose == "lottery" then
        text = tostring(self.lotteryCustomCount or 10)
    elseif self.shopSearchPurpose ~= "shop" then
        text = ""
    end
    if self.shopSearchBox.getInternalText then
        local current = self.shopSearchBox:getInternalText() or ""
        if current == text then
            return
        end
    end
    self.suppressSearchChange = true
    self.shopSearchBox:setText(text)
    self.suppressSearchChange = false
end

function GodSystemWindow:shopItemMatchesSearch(item, category)
    local query = gsTrim(self.shopSearchText or "")
    if query == "" then
        return true
    end
    local haystack = tostring(GodSystem.getShopLabel(item)) .. " " ..
        tostring(GodSystem.getShopDescription(item)) .. " " ..
        tostring(GodSystem.getShopRewardText(item)) .. " " ..
        tostring(category and category.label or "") .. " " ..
        tostring(GodSystem.getShopPrimaryFullType(item) or "")
    return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(query or "")), 1, true) ~= nil
end

function GodSystemWindow:recycleItemMatchesSearch(group)
    local query = gsTrim(self.recycleSearchText or "")
    if query == "" then
        return true
    end
    local haystack = tostring(group and group.label or "") .. " " ..
        tostring(group and group.fullType or "") .. " " ..
        tostring(group and group.valueEach or "") .. " " ..
        tostring(group and group.totalValue or "") .. " " ..
        tostring(group and group.count or "")
    return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(query or "")), 1, true) ~= nil
end

function GodSystemWindow:adminRowMatchesSearch(text, payload)
    local query = gsTrim(self.adminSearchText or "")
    if query == "" then
        return true
    end
    payload = payload or {}
    local haystack = tostring(text or "") .. " " ..
        tostring(payload.detail or "") .. " " ..
        tostring(payload.fullType or "") .. " " ..
        tostring(payload.data and payload.data.key or "") .. " " ..
        tostring(payload.data and payload.data.group or "") .. " " ..
        tostring(payload.data and payload.data.type or "") .. " " ..
        tostring(payload.data and gsAdminGroupLabel(payload.data.group) or "") .. " " ..
        tostring(payload.data and gsAdminSettingLabel(payload.data) or "") .. " " ..
        tostring(payload.data and gsAdminSettingDesc(payload.data) or "")
    return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(query or "")), 1, true) ~= nil
end

function GodSystemWindow:populateShop()
    self.shopSearchPurpose = "shop"
    self:syncSearchBoxText(self.shopSearchPurpose)
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_Buy", "Buy"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_RemoveUnlocked", "Remove unlocked"))
    self.thirdButton:setVisible(false)
    gsSetButtonTitle(self.fourthButton, GodSystem.text("Btn_ShopPrevPage", "Prev"))
    self.fourthButton:setVisible(true)
    gsSetButtonTitle(self.fifthButton, GodSystem.text("Btn_ShopNextPage", "Next"))
    self.fifthButton:setVisible(true)
    local shopItems = {}
    local categoryMap = {}
    local categories = {}
    for i = 1, #GodSystemConfig.ShopItems do
        local item = GodSystemConfig.ShopItems[i]
        local available, reason, availableItems, missingItems = GodSystem.shopItemIsAvailable(item)
        if available and (not missingItems or #missingItems == 0) then
            table.insert(shopItems, item)
        end
    end

    local unlocked = GodSystem.getUnlockedShopItemsList()
    for i = 1, #unlocked do
        table.insert(shopItems, unlocked[i])
    end

    for i = 1, #shopItems do
        local category = GodSystem.getShopPrimaryCategory(shopItems[i])
        if not categoryMap[category.key] then
            categoryMap[category.key] = true
            table.insert(categories, category)
        end
    end
    table.sort(categories, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)
    self:updateShopCategoryButton(categories)

    local filteredShopItems = {}
    for i = 1, #shopItems do
        local item = shopItems[i]
        local category = GodSystem.getShopPrimaryCategory(item)
        if (self.shopCategoryKey == "all" or category.key == self.shopCategoryKey) and self:shopItemMatchesSearch(item, category) then
            filteredShopItems[#filteredShopItems + 1] = { item = item, category = category }
        end
    end
    local pageSize = self.ShopPageSize or 20
    local totalPages = math.max(1, math.ceil(#filteredShopItems / pageSize))
    self.shopPage = math.max(1, math.min(math.floor(self.shopPage or 1), totalPages))
    local startIndex = ((self.shopPage - 1) * pageSize) + 1
    local endIndex = math.min(#filteredShopItems, startIndex + pageSize - 1)
    if #filteredShopItems > 0 then
        self:addListItem(string.format("%s %d/%d | %d %s", GodSystem.text("Shop_Page", "Page"), self.shopPage, totalPages, #filteredShopItems, GodSystem.text("Shop_Items", "items")), { kind = "shopPager", detail = GodSystem.text("Shop_PageHint", "Use page buttons below") })
    end
    for i = startIndex, endIndex do
        local row = filteredShopItems[i]
        local item = row.item
        local category = row.category
        local text = string.format("[%s] %s", category.label or GodSystem.getShopGroup(item), GodSystem.getShopLabel(item))
        local detail = tostring(GodSystem.getShopItemUnitPrice(item) or 0) .. GodSystem.text("Unit_CoinShort", "c")
        self:addListItem(text, { kind = "shop", data = item, detail = detail })
    end
    if #filteredShopItems == 0 then
        local detail = GodSystem.text("Shop_EmptyHint", "No shop item matches this category or search.")
        self:addListItem(GodSystem.text("Shop_EmptyCategory", "No item in this category"), { kind = "empty", detail = detail })
    end
    self:applyShopActionLayout()
    self:updateShopCategoryButton(categories)
end

function GodSystemWindow:populateLottery()
    self.shopSearchPurpose = "lottery"
    self:syncSearchBoxText(self.shopSearchPurpose)
    if self.shopSearchBox then
        self.shopSearchBox:setVisible(true)
        self.suppressSearchChange = true
        self.shopSearchBox:setText(tostring(self.lotteryCustomCount or 10))
        self.suppressSearchChange = false
    end
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_LotteryOne", "Draw 1"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_LotteryTen", "Draw 10"))
    self.secondaryButton:setVisible(true)
    gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_LotteryCustom", "Custom draw"))
    self.thirdButton:setVisible(true)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)

    local categories = GodSystem.getLotteryCategories()
    self:updateLotteryCategoryButton(categories)
    local categoryKey = self.lotteryCategoryKey or "all"
    local preview = GodSystem.getLotteryPreview(categoryKey)
    local price = preview.price or GodSystem.getLotteryPrice(categoryKey)
    local count = preview.count or 0
    local maxCount = preview.maxCount or GodSystemConfig.LotteryCustomMaxCount or 50
    local modeText = categoryKey == "all" and GodSystem.text("Lottery_ModeAll", "All categories") or GodSystem.text("Lottery_ModeCategory", "Single category")
    self:addListItem(GodSystem.text("Lottery_StatusTitle", "Lottery pool"), {
        kind = "lotteryInfo",
        detail = modeText .. " | " .. GodSystem.text("Lottery_Category", "Category") .. ": " .. tostring(preview.categoryLabel or categoryKey) ..
            " | " .. GodSystem.text("Lottery_CandidateCount", "Candidates") .. ": " .. tostring(count) ..
            " | " .. GodSystem.text("Lottery_Price", "Price") .. ": " .. tostring(price) .. GodSystem.text("Unit_CoinShort", "c") ..
            " | " .. GodSystem.text("Lottery_MaxCount", "Max") .. ": " .. tostring(maxCount),
    })
    self:addListItem(GodSystem.text("Lottery_DrawOptions", "Draw 1 / 10 / custom count from the action bar"), {
        kind = "lotteryInfo",
        detail = GodSystem.text("Lottery_CustomHint", "Enter a number in the box, then click custom draw."),
    })
    if self.latestLotteryResult then
        local result = self.latestLotteryResult
        self:addListItem(GodSystem.text("Lottery_LatestResult", "Latest result") .. " -" .. tostring(result.totalCost or 0) .. GodSystem.text("Unit_CoinShort", "c"), {
            kind = "lotteryResult",
            data = result,
            detail = self:formatLotteryResultDetail(result),
        })
    end
    self:addListItem(GodSystem.text("Lottery_PoolPreview", "Pool preview"), {
        kind = "lotteryHeader",
        detail = GodSystem.text("Lottery_PoolPreviewHint", "The following rows are possible draw results."),
    })
    local previewLimit = 30
    for i = 1, math.min(#(preview.candidates or {}), previewLimit) do
        local item = preview.candidates[i]
        local text = "[" .. tostring(item.categoryLabel or item.categoryKey or "") .. "] " .. tostring(item.label or item.fullType)
        self:addListItem(text, {
            kind = "lotteryCandidate",
            data = item,
            detail = tostring(item.fullType or "") .. " | " .. GodSystem.text("Price_Buy", "Buy ") .. tostring(item.buyPrice or 0) .. GodSystem.text("Unit_CoinShort", "c"),
        })
    end
    if count > previewLimit then
        self:addListItem(GodSystem.text("Lottery_PreviewMore", "More items not shown") .. ": " .. tostring(count - previewLimit), { kind = "lotteryInfo", detail = "" })
    elseif count <= 0 then
        self:addListItem(GodSystem.text("Lottery_Empty", "No item in this lottery pool"), { kind = "empty", detail = "" })
    end
    self:applyLotteryActionLayout()
end

function GodSystemWindow:populateRecycle()
    self.shopSearchPurpose = "recycle"
    self:syncSearchBoxText(self.shopSearchPurpose)
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_SellOne", "Sell 1"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshBag", "Refresh bag"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    if GodSystem.isRecycleUnlockMode() then
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_RecycleModeUnlock", "Mode: unlock"))
    else
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_RecycleModeOnly", "Mode: recycle only"))
    end
    self.thirdButton:setVisible(true)
    local groups, order = GodSystem.getInventoryRecycleGroups()
    local shown = 0
    for i = 1, #order do
        local group = groups[order[i]]
        if self:recycleItemMatchesSearch(group) then
            shown = shown + 1
            local text = string.format("%s x%d", group.label, group.count)
            local buyRef = GodSystem.getShopBuyReference(group.fullType)
            local buyText = buyRef and (GodSystem.text("Price_Buy", "Buy ") .. tostring(buyRef.price) .. GodSystem.text("Unit_CoinShort", "c") .. "/" .. tostring(buyRef.label)) or GodSystem.text("Price_BuyNone", "Buy none")
            local sellText = ""
            if (group.unitDivisor or 1) > 1 then
                sellText = string.format("%s %d%s/%d%s", GodSystem.text("Price_Sell", "Sell"), group.totalValue or 0, GodSystem.text("Unit_CoinShort", "c"), group.count or 0, GodSystem.text("Unit_ItemShort", "items"))
            else
                sellText = string.format("%s %d%s", GodSystem.text("Price_Sell", "Sell"), group.valueEach, GodSystem.text("Unit_CoinEach", "c each"))
            end
            local detail = string.format("%s | %s", sellText, buyText)
            self:addListItem(text, { kind = "recycle", data = group, detail = detail })
        end
    end
    if shown == 0 then
        self:addListItem(GodSystem.text("Recycle_Empty", "No recyclable item"), { kind = "empty", detail = "" })
    end
end

function GodSystemWindow:populateWaistSpace()
    local info = GodSystem.getAutoRecyclerInfo()
    self.thirdButton:setVisible(true)
    if not info.found then
        if info.claimed then
            gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_RecoverWaistBag", "Recover terminal") .. " -" .. tostring(info.recoverCost or 0) .. GodSystem.text("Unit_CoinShort", "c"))
        else
            gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_ClaimWaistBag", "Claim terminal"))
        end
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
        self.secondaryButton:setVisible(not gsIsMultiplayer())
        self.thirdButton:setVisible(false)
        self.fourthButton:setVisible(false)
        self.fifthButton:setVisible(false)
        self:addListItem(GodSystem.text("Waist_NotFound", "System space terminal not found"), { kind = "empty", detail = GodSystem.text("Hint_WaistSpaceMissing", "Claim or recover the system space terminal first.") })
        return
    end

    local waistUnlockMode = GodSystem.isWaistRecycleUnlockMode()
    if waistUnlockMode then
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_WaistSellAndListSelected", "Sell+list selected"))
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_WaistSellAndListAll", "Sell+list all"))
    else
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_SellSelected", "Sell selected"))
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_SellAllWaist", "Sell all"))
    end
    local nextCost = info.nextCost
    if nextCost then
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_UpgradeWaistBag", "Upgrade terminal") .. " -" .. tostring(nextCost) .. GodSystem.text("Unit_CoinShort", "c"))
    else
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_WaistMaxLevel", "Max level"))
    end
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(true)
    if waistUnlockMode then
        gsSetButtonTitle(self.fifthButton, GodSystem.text("Btn_WaistModeUnlock", "Mode: sell+list"))
    else
        gsSetButtonTitle(self.fifthButton, GodSystem.text("Btn_WaistModeOnly", "Mode: sell only"))
    end
    if not info.autoRecycleUnlocked then
        gsSetButtonTitle(self.fourthButton, GodSystem.text("Btn_WaistAutoRecycleUnlock", "Unlock auto -") .. tostring(info.autoRecycleUnlockCost or 0) .. GodSystem.text("Unit_CoinShort", "c"))
    elseif info.autoRecycleEnabled then
        gsSetButtonTitle(self.fourthButton, GodSystem.text("Btn_WaistAutoRecycleDisable", "Auto off"))
    else
        gsSetButtonTitle(self.fourthButton, GodSystem.text("Btn_WaistAutoRecycleEnable", "Auto on"))
    end

    local status = string.format("%s Lv.%d/%d | %s %d | %s %d%% | %s %d/%d",
        GodSystem.text("Waist_Status", "System space terminal"),
        info.level or 1,
        info.maxLevel or 1,
        GodSystem.text("Waist_Capacity", "Capacity"),
        info.capacity or 0,
        GodSystem.text("Waist_Reduction", "Reduction"),
        info.weightReduction or 0,
        GodSystem.text("Waist_Items", "Items"),
        info.itemCount or 0,
        info.capacity or 0
    )
    self:addListItem(status, { kind = "info", data = status, detail = "" })

    local autoState = GodSystem.text("Waist_AutoRecycleLocked", "Locked")
    if info.autoRecycleUnlocked then
        if info.autoRecycleEnabled then
            autoState = GodSystem.text("Waist_AutoRecycleEnabled", "Enabled")
        else
            autoState = GodSystem.text("Waist_AutoRecycleDisabled", "Disabled")
        end
    end
    local autoDetail = string.format("%s: %s | %s: %d%s | %s: %d%s",
        GodSystem.text("Waist_AutoRecycle", "Auto recycle"),
        autoState,
        GodSystem.text("Waist_AutoRecycleInterval", "Interval"),
        info.autoRecycleIntervalHours or 1,
        GodSystem.text("Unit_Hour", "h"),
        GodSystem.text("Waist_AutoRecycleUnlockCost", "Unlock cost"),
        info.autoRecycleUnlockCost or 0,
        GodSystem.text("Unit_CoinShort", "c")
    )
    self:addListItem(autoDetail, { kind = "info", data = autoDetail, detail = "" })

    local groups, order, skipped = GodSystem.getWaistSpaceRecycleGroups()
    local seen = {}
    for i = 1, #order do
        local group = groups[order[i]]
        seen[group.fullType] = true
        local checked = self.waistSelected and self.waistSelected[group.fullType] == true
        local mark = checked and "[x] " or "[ ] "
        local text = string.format("%s%s x%d", mark, group.label, group.count)
        local detail = ""
        if (group.unitDivisor or 1) > 1 then
            detail = string.format("%d%s / %d%s", group.totalValue or 0, GodSystem.text("Unit_CoinShort", "c"), group.count or 0, GodSystem.text("Unit_ItemShort", "items"))
        else
            detail = string.format("%d%s/%s", group.valueEach or 0, GodSystem.text("Unit_CoinShort", "c"), GodSystem.text("Unit_ItemShort", "item"))
        end
        self:addListItem(text, { kind = "waist", data = group, detail = detail })
    end
    for fullType, _ in pairs(self.waistSelected or {}) do
        if not seen[fullType] then
            self.waistSelected[fullType] = nil
        end
    end
    if #order == 0 then
        self:addListItem(GodSystem.text("Waist_Empty", "No recyclable item in terminal"), { kind = "empty", detail = "" })
    end
    if skipped and skipped > 0 then
        self:setDetailText(GodSystem.text("Waist_Skipped", "Skipped protected items: ") .. tostring(skipped))
    end
end

function GodSystemWindow:populateBank()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankDeposit", "Deposit"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_BankWithdraw", "Withdraw"))
    self.thirdButton:setVisible(false)
    local bank = GodSystem.getBank()
    gsSetButtonTitle(self.fourthButton, GodSystem.text(bank.autoDepositEnabled and "Btn_BankAutoDepositOn" or "Btn_BankAutoDepositOff", bank.autoDepositEnabled and "Auto deposit: ON" or "Auto deposit: OFF"))
    gsSetButtonTitle(self.fifthButton, GodSystem.text("Btn_BankConsolidateCurrency", "Sort coins"))
    self.secondaryButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(true)

    local summary = GodSystem.getBankSummary()
    local line = GodSystem.text("Bank_SummaryV2", "Cash {1} | Current {2} | Investment {3} | Legacy fixed {4} | Death penalty preview {5}")
    line = gsFormatTemplate(line, { summary.cash or 0, summary.current or 0, summary.investmentTotal or 0, summary.fixedPrincipal or 0, summary.deathPenalty or 0 })
    self:addListItem(line, { kind = "bankSummary", data = summary, detail = "" })

    local currentText = GodSystem.text("Bank_Current", "Current account")
    self:addListItem(currentText, { kind = "bankCurrent", data = summary, detail = tostring(summary.current or 0) .. GodSystem.text("Unit_CoinShort", "c") })

    local loanSummary = GodSystem.getBankLoanSummary and GodSystem.getBankLoanSummary() or {}
    local freezeText = (loanSummary.freezeLeftHours or 0) > 0 and tostring(loanSummary.freezeLeftHours or 0) .. GodSystem.text("Unit_Hour", "h") or "0"
    local loanLine = gsFormatTemplate(GodSystem.text("Bank_LoanSummary", "Loan credit {1} | Available {2} | Debt {3} | Frozen {4}"), {
        loanSummary.creditTotal or 0,
        loanSummary.creditAvailable or 0,
        loanSummary.unpaidTotal or 0,
        freezeText,
    })
    self:addListItem(loanLine, { kind = "bankLoanSummary", data = loanSummary, detail = "" })

    local loan = loanSummary.loan
    if loan then
        local activeText = gsFormatTemplate(GodSystem.text("Bank_LoanActive", "Active loan {1} | Paid {2}/{3}"), {
            tostring(loan.id or ""),
            tostring(loan.paid or 0),
            tostring(loan.totalDue or 0),
        })
        local activeDetail = GodSystem.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(loanSummary.dueNow or 0) .. GodSystem.text("Unit_CoinShort", "c") ..
            " | " .. GodSystem.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(loanSummary.payoff or 0) .. GodSystem.text("Unit_CoinShort", "c")
        if loanSummary.overdueStartHour then
            local nowHours = GameTime and GameTime:getInstance() and GameTime:getInstance():getWorldAgeHours() or 0
            activeDetail = activeDetail .. " | " .. gsFormatTemplate(GodSystem.text("Bank_LoanOverdue", "Overdue {1} hours"), { tostring(math.max(0, math.ceil(nowHours - (loanSummary.overdueStartHour or nowHours)))) })
        end
        self:addListItem(activeText, { kind = "bankLoanActive", data = loan, summary = loanSummary, detail = activeDetail })
    else
        self:addListItem(GodSystem.text("Bank_LoanNoDebt", "No active loan"), { kind = "empty", detail = "" })
    end

    local loanPlans = GodSystem.getBankLoanPlans and GodSystem.getBankLoanPlans() or {}
    for i = 1, #loanPlans do
        local plan = loanPlans[i]
        local label
        if plan.kind == "single" then
            label = GodSystem.text("Bank_LoanPlanSingle", "Short loan | 3 days | interest 5%")
        else
            label = gsFormatTemplate(GodSystem.text("Bank_LoanPlanInstallment", "{1} period loan | every 3 days | interest {2}%"), {
                tostring(plan.periods or 1),
                tostring(math.floor((tonumber(plan.totalInterestRate) or 0) * 100)),
            })
        end
        local detail = GodSystem.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(math.max(1, math.floor((tonumber(plan.dueHours) or 72) / 24))) .. "d" ..
            " | " .. GodSystem.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(math.floor((tonumber(plan.totalInterestRate) or 0) * 100)) .. "%"
        self:addListItem(label, { kind = "bankLoanPlan", data = plan, summary = loanSummary, detail = detail })
    end

    if GodSystem.isFeatureEnabled("EnableBankInvestments") ~= false then
        local profiles = GodSystem.getBankInvestmentProfiles()
        local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
        for i = 1, #profiles do
            local profile = profiles[i]
            local account = GodSystem.getBankInvestmentAccount(profile.id) or {}
            local progress = math.min(settlementHours, math.max(0, tonumber(account.onlineHours) or 0))
            local label = GodSystem.getBankInvestmentLabel(profile.id) .. " | " .. tostring(account.balance or 0) .. GodSystem.text("Unit_CoinShort", "c")
            local status = account.redeemUnlocked == true and GodSystem.text("Bank_InvestmentRedeemable", "Redeemable") or GodSystem.text("Bank_InvestmentLocked", "Locked until first settlement")
            local detail = gsFormatTemplate(GodSystem.text("Bank_InvestmentProgress", "Online progress {1}/{2}h"), { math.floor(progress), settlementHours }) .. " | " .. status
            if (account.settlementCount or 0) > 0 then
                detail = detail .. " | " .. gsFormatTemplate(GodSystem.text("Bank_InvestmentLastResult", "Last {1}"), { account.lastDelta or 0 })
            end
            self:addListItem(label, { kind = "bankInvestment", data = account, profile = profile, detail = detail })
        end
    end

    if #(bank.fixed or {}) <= 0 then
        self:addListItem(GodSystem.text("Bank_NoLegacyFixed", "No legacy fixed deposits"), { kind = "empty", detail = "" })
        self:setStandardActionBar()
        return
    end
    for i = 1, #(bank.fixed or {}) do
        local entry = bank.fixed[i]
        local payout, interestOrPenalty, mature = GodSystem.getBankFixedPayout(entry)
        local state = mature and GodSystem.text("Bank_Mature", "Mature") or (GodSystem.text("Bank_NotMature", "Not mature") .. " " .. tostring(math.max(0, math.ceil((tonumber(entry.matureHour) or 0) - (GameTime and GameTime:getInstance() and GameTime:getInstance():getWorldAgeHours() or 0)))) .. GodSystem.text("Unit_Hour", "h"))
        local text = GodSystem.text("Bank_LegacyFixed", "Legacy fixed") .. " " .. tostring(entry.id or i) .. " | " .. tostring(entry.principal or 0) .. GodSystem.text("Unit_CoinShort", "c")
        local detail = state .. " | " .. GodSystem.text("Bank_Payout", "payout") .. " " .. tostring(payout)
        if interestOrPenalty < 0 then
            detail = detail .. " | " .. GodSystem.text("Bank_Penalty", "penalty") .. " " .. tostring(math.abs(interestOrPenalty))
        elseif interestOrPenalty > 0 then
            detail = detail .. " | " .. GodSystem.text("Bank_Interest", "interest") .. " " .. tostring(interestOrPenalty)
        end
        self:addListItem(text, { kind = "bankFixed", data = entry, detail = detail })
    end
    self:setStandardActionBar()
end

function GodSystemWindow:updateBankActionButtons(payload)
    if self.mode ~= "bank" then
        return
    end
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankDeposit", "Deposit"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_BankWithdraw", "Withdraw"))
    self.thirdButton:setVisible(false)
    local bank = GodSystem.getBank()
    gsSetButtonTitle(self.fourthButton, GodSystem.text(bank.autoDepositEnabled and "Btn_BankAutoDepositOn" or "Btn_BankAutoDepositOff", bank.autoDepositEnabled and "Auto deposit: ON" or "Auto deposit: OFF"))
    gsSetButtonTitle(self.fifthButton, GodSystem.text("Btn_BankConsolidateCurrency", "Sort coins"))
    self.secondaryButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(true)
    if payload and payload.kind == "bankLoanPlan" then
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankBorrowLoan", "Borrow"))
        self.secondaryButton:setVisible(false)
        self.thirdButton:setVisible(false)
    elseif payload and payload.kind == "bankLoanActive" then
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankRepayLoan", "Repay due"))
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_BankPayoffLoan", "Pay off"))
        self.secondaryButton:setVisible(true)
        self.thirdButton:setVisible(false)
    elseif payload and payload.kind == "bankInvestment" then
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankInvestCurrent", "Invest current"))
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_BankInvestCash", "Invest cash"))
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_BankInvestmentRedeem", "Redeem"))
        self.secondaryButton:setVisible(true)
        self.thirdButton:setVisible(true)
    elseif payload and payload.kind == "bankFixed" then
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_BankWithdrawFixed", "Withdraw fixed"))
        self.secondaryButton:setVisible(false)
        self.thirdButton:setVisible(false)
    end
    self:setStandardActionBar()
end

function GodSystemWindow:populateTraits()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_TraitModify", "Modify"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(false)

    local positive, negative, blockedCount = GodSystem.getTraitModificationLists()
    local positiveRule = GodSystem.text("Trait_PricePerPointPrefix", "Each point ") .. tostring(GodSystemConfig.PositiveTraitCostPerPoint or 800) .. GodSystem.text("Unit_CoinShort", "c")
    local negativeRule = GodSystem.text("Trait_PricePerPointPrefix", "Each point ") .. tostring(GodSystemConfig.NegativeTraitRemoveCostPerPoint or 500) .. GodSystem.text("Unit_CoinShort", "c")
    self:addListItem(GodSystem.text("Trait_PositiveHeader", "Positive traits") .. " | " .. positiveRule, { kind = "traitHeader", detail = "" })
    if #positive == 0 then
        self:addListItem(GodSystem.text("Trait_PositiveEmpty", "No positive trait available"), { kind = "empty", detail = "" })
    else
        for i = 1, #positive do
            local entry = positive[i]
            local risk = entry.risk and (GodSystem.text("Trait_RiskTag", "[Risk] ") or "[Risk] ") or ""
            local owned = entry.owned and (" " .. GodSystem.text("Trait_StatusOwnedTag", "[Owned]")) or ""
            local text = risk .. tostring(entry.label or entry.traitType) .. owned
            local detail = "+" .. tostring(entry.costPoints or 0) .. " | " .. tostring(entry.price or 0) .. GodSystem.text("Unit_CoinShort", "c")
            if entry.disabledReason then
                detail = GodSystem.text("Trait_DisabledShort", "Disabled") .. " | " .. detail
            end
            self:addListItem(text, { kind = "trait", data = entry, detail = detail })
        end
    end

    self:addListItem(GodSystem.text("Trait_NegativeHeader", "Remove negative traits") .. " | " .. negativeRule, { kind = "traitHeader", detail = "" })
    if #negative == 0 then
        self:addListItem(GodSystem.text("Trait_NegativeEmpty", "No negative trait owned"), { kind = "empty", detail = "" })
    else
        for i = 1, #negative do
            local entry = negative[i]
            local risk = entry.risk and (GodSystem.text("Trait_RiskTag", "[Risk] ") or "[Risk] ") or ""
            local text = risk .. tostring(entry.label or entry.traitType)
            local detail = tostring(entry.costPoints or 0) .. " | " .. tostring(entry.price or 0) .. GodSystem.text("Unit_CoinShort", "c")
            self:addListItem(text, { kind = "trait", data = entry, detail = detail })
        end
    end

    if blockedCount and blockedCount > 0 then
        self:setDetailText(GodSystem.text("Trait_BlockedSummary", "Hidden free/profession/body traits: ") .. tostring(blockedCount))
    end
end

function GodSystemWindow:applyAttributeActionBar(payload)
    local selected = payload and payload.kind == "attribute" and payload.data or nil
    local enabled = selected ~= nil and selected.maxed ~= true
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Attribute_BuyXP", "Buy XP"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Attribute_NextLevel", "Next level"))
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)
    self.primaryButton.enable = enabled
    self.secondaryButton.enable = enabled
    self:setActionBar({
        { id = "searchBox", width = 230, minWidth = 140 },
        { id = "primary", width = 140 },
        { id = "secondary", width = 160 },
    })
end

function GodSystemWindow:populateAttributes()
    if GodSystem.isFeatureEnabled("EnableAttributes") == false then
        self.mode = "traits"
        self:populateTraits()
        return
    end
    self.shopSearchPurpose = "attribute"
    self:syncSearchBoxText("attribute")
    local rows = GodSystem.getAttributePerks(self.attributeSearchText or "")
    local groupKeys = {
        body = "Attribute_GroupBody",
        combat = "Attribute_GroupCombat",
        survival = "Attribute_GroupSurvival",
        crafting = "Attribute_GroupCrafting",
        mod = "Attribute_GroupMod",
    }
    local lastGroup = nil
    for i = 1, #rows do
        local row = rows[i]
        if row.group ~= lastGroup then
            lastGroup = row.group
            self:addListItem(GodSystem.text(groupKeys[row.group] or "Attribute_GroupMod", tostring(row.parentLabel or row.group)), { kind = "attributeHeader", detail = "" })
        end
        local status = row.maxed and GodSystem.text("Attribute_Maxed", "Maxed") or ("Lv." .. tostring(row.currentLevel or 0) .. "/" .. tostring(row.maxLevel or 10))
        local detail = status .. " | XP " .. tostring(math.floor(row.currentXp or 0)) .. "/" .. tostring(math.floor(row.maxXp or 0))
        self:addListItem(tostring(row.label), { kind = "attribute", data = row, detail = detail })
    end
    if #rows == 0 then
        self:addListItem(GodSystem.text("Attribute_Empty", "No matching standard skills"), { kind = "empty", detail = "" })
    end
    self:applyAttributeActionBar(self:getSelectedPayload())
end

function GodSystemWindow:populateTasks()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_TaskAccept", "Accept"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshOpenTasksShort", "Refresh tasks -") .. tostring(GodSystemConfig.RefreshTaskCost or 0) .. GodSystem.text("Unit_CoinShort", "c"))
    self.thirdButton:setVisible(true)
    if GodSystemUI.isTaskTrackerVisible and GodSystemUI.isTaskTrackerVisible() then
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_TaskTrackerHide", "Hide tracker"))
    else
        gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_TaskTrackerShow", "Show tracker"))
    end
    local data = GodSystem.getData()
    gsSetButtonTitle(self.fourthButton, GodSystem.text(data.autoTaskClaimEnabled and "Btn_TaskAutoClaimOn" or "Btn_TaskAutoClaimOff", data.autoTaskClaimEnabled and "Auto claim: ON" or "Auto claim: OFF"))
    self.fourthButton:setVisible(true)
    if not (GodSystemNetwork and GodSystemNetwork.isMultiplayer) then
        GodSystem.generateDailyTasks(false)
    end
    local tasks = data.tasks or {}
    local openCount = 0
    local activeCount = 0
    for i = 1, #tasks do
        local task = tasks[i]
        local progress = GodSystem.getTaskProgress(task)
        local text = GodSystem.getTaskListTitle(task)
        local remain = task.status == "active" and (" " .. GodSystem.text("Short_Remain", "Left") .. tostring(GodSystem.getRemainingHours(task)) .. "h") or ""
        local detail = string.format("%d/%d%s", math.min(progress, task.target or 1), task.target or 1, remain)
        if task.status == "open" then
            openCount = openCount + 1
            self:addListItem(text, { kind = "task", data = task, detail = detail })
        elseif task.status == "active" then
            activeCount = activeCount + 1
            self:addActiveListItem(text, { kind = "task", data = task, detail = detail })
        end
    end
    if openCount == 0 then
        self:addListItem(GodSystem.text("Task_OpenEmpty", "No available task"), { kind = "empty", detail = "" })
    end
    if activeCount == 0 then
        self:addActiveListItem(GodSystem.text("Task_ActiveEmpty", "No active task"), { kind = "empty", detail = "" })
    end
    local labelWidth = math.max(120, (self.list and self.list.width or 180) - 6)
    gsSetLabel(self.openTaskLabel, gsTruncateText(GodSystem.text("Task_OpenColumn", "Available") .. " | " .. GodSystem.text("Task_NextRefresh", "Next refresh ") .. GodSystem.getDailyTaskRefreshText(), UIFont.Small, labelWidth))
    gsSetLabel(self.activeTaskLabel, gsTruncateText(GodSystem.text("Task_ActiveColumn", "Active") .. " " .. tostring(activeCount) .. "/" .. tostring(GodSystem.getMaxActiveTasks()), UIFont.Small, labelWidth))
    self:setStandardActionBar()
end

function GodSystemWindow:populateUpgrades()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_UpgradeSystem", "Upgrade"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    self.thirdButton:setVisible(false)

    local upgrades = { "activeTasks", "dailyTasks" }
    for i = 1, #upgrades do
        local info = GodSystem.getSystemUpgradeInfo(upgrades[i])
        if info then
            local costText = info.cost and (tostring(info.cost) .. GodSystem.text("Unit_CoinShort", "c")) or GodSystem.text("Upgrade_Maxed", "Maxed")
            local detail = tostring(info.current) .. "/" .. tostring(info.maxValue) .. " | " .. costText
            self:addListItem(info.label, { kind = "upgrade", data = info, detail = detail })
        end
    end
    local services = GodSystem.getMedicalServiceList and GodSystem.getMedicalServiceList() or {}
    for i = 1, #services do
        local info = services[i]
        local detail = tostring(info.cost or 0) .. GodSystem.text("Unit_CoinShort", "c")
        self:addListItem(info.label, { kind = "medicalService", data = info, detail = detail })
    end
end

function GodSystemWindow:applyCompanionActionBar(payload)
    local data = GodSystem.getCompanionData()
    local unlocked = data and data.unlocked == true
    local canPurchase = payload and payload.kind == "companionNode" and payload.unlocked == true and payload.maxed ~= true
    local unlockDefinition = payload and GodSystemCompanionConfig.Unlocks[payload.id] or nil
    if unlockDefinition then
        local data = GodSystem.getCompanionData()
        local requiresMet = not unlockDefinition.requires or GodSystemCompanionConfig.isUnlocked(data, unlockDefinition.requires)
        canPurchase = payload.unlocked ~= true and requiresMet
    end
    if payload and payload.id == "resonance" then canPurchase = payload.unlocked == true end

    local primaryTitle = GodSystem.text("Companion_Upgrade", "Unlock / upgrade")
    if payload and payload.cost and canPurchase then
        primaryTitle = primaryTitle .. " -" .. tostring(payload.cost) .. GodSystem.text("Unit_CoinShort", "c")
    elseif payload and payload.maxed then
        primaryTitle = GodSystem.text("Upgrade_Maxed", "Maxed")
    end
    gsSetButtonTitle(self.primaryButton, primaryTitle)
    gsSetButtonTitle(self.secondaryButton, data and data.visible and GodSystem.text("Companion_ActionHide", "Hide") or GodSystem.text("Companion_ActionShow", "Show"))
    gsSetButtonTitle(self.thirdButton, GodSystem.text("Companion_ShortcutToggle", "Shortcut bar"))
    gsSetButtonTitle(self.fourthButton, GodSystem.text("Companion_ActionRecall", "Recall"))
    self.primaryButton.enable = canPurchase == true
    self.secondaryButton.enable = unlocked
    self.thirdButton.enable = unlocked
    self.fourthButton.enable = unlocked
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(false)
    self:setStandardActionBar()
end

function GodSystemWindow:populateCompanion()
    if gsIsMultiplayer() or not GodSystemCompanion or not GodSystemCompanionConfig.isEnabled() then
        self.mode = "upgrades"
        self:populateUpgrades()
        return
    end
    local state = GodSystemCompanion.getStateDetail and GodSystemCompanion.getStateDetail() or ""
    self:addListItem(GodSystem.text("Companion_Title", "Blue pixel floating robot"), { kind = "companionState", detail = state })
    local rows = GodSystemCompanion.getRows and GodSystemCompanion.getRows() or {}
    for i = 1, #rows do
        local row = rows[i]
        self:addListItem(row.label, row)
    end
    self:applyCompanionActionBar(self:getSelectedPayload())
end

function GodSystemWindow:applyUpgradeActionBar(payload)
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)
    if payload and payload.kind == "medicalService" and payload.data then
        local info = payload.data
        local title = tostring(info.button or GodSystem.text("Btn_Confirm", "Confirm")) .. " -" .. tostring(info.cost or 0) .. GodSystem.text("Unit_CoinShort", "c")
        gsSetButtonTitle(self.primaryButton, title)
        self.secondaryButton:setVisible(false)
    else
        gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_UpgradeSystem", "Upgrade"))
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
    end
    self:setStandardActionBar()
end

function GodSystemWindow:getHomeActionTitles(payload)
    local primary = nil
    local secondary = nil
    local third = nil
    local fourth = gsIsMultiplayer() and nil or GodSystem.text("Btn_RefreshDisplay", "Refresh")
    local fifth = nil
    local home = GodSystem.getHomeSystem()
    local travelCost = GodSystemConfig.HomeTravelCost or 10
    if home and home.returnPoint then
        third = GodSystem.text("Btn_HomeReturn", "Return") .. " -" .. tostring(travelCost) .. GodSystem.text("Unit_CoinShort", "c")
    end
    if payload and payload.kind == "homePoint" and payload.data then
        local entry = payload.data
        if entry.kind == "home" then
            primary = GodSystem.text("Btn_HomeSet", "Set home") .. " -" .. tostring(GodSystemConfig.HomeSetCost or 100) .. GodSystem.text("Unit_CoinShort", "c")
            if entry.point then
                secondary = GodSystem.text("Btn_HomeTeleport", "Go home") .. " -" .. tostring(travelCost) .. GodSystem.text("Unit_CoinShort", "c")
            end
        elseif entry.kind == "temp" then
            if not entry.owned then
                primary = GodSystem.text("Btn_HomeBuyTemp", "Buy slot") .. " -" .. tostring(GodSystemConfig.TempTeleportSlotCost or 500) .. GodSystem.text("Unit_CoinShort", "c")
            else
                primary = GodSystem.text("Btn_HomeSetTemp", "Set point") .. " -" .. tostring(GodSystemConfig.TempTeleportSetCost or 100) .. GodSystem.text("Unit_CoinShort", "c")
                if entry.point then
                    secondary = GodSystem.text("Btn_HomeTeleportTemp", "Teleport") .. " -" .. tostring(travelCost) .. GodSystem.text("Unit_CoinShort", "c")
                end
            end
        elseif entry.kind == "return" then
            primary = GodSystem.text("Btn_HomeReturn", "Return") .. " -" .. tostring(travelCost) .. GodSystem.text("Unit_CoinShort", "c")
            secondary = GodSystem.text("Btn_HomeClearReturn", "Clear departure")
            third = nil
        elseif entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystem.getHomeSafeZoneInfo()
            third = nil
            if not info.homeSet then
                primary = nil
            elseif not info.unlocked then
                primary = GodSystem.text("Btn_HomeSafeUnlock", "Unlock safe zone") .. " -" .. tostring(info.unlockCost or 0) .. GodSystem.text("Unit_CoinShort", "c")
            else
                primary = info.enabled and GodSystem.text("Btn_HomeSafeDisable", "Pause safe zone") or GodSystem.text("Btn_HomeSafeEnable", "Enable safe zone")
                secondary = GodSystem.text("Btn_HomeSafeClear", "Clear now") .. " -" .. tostring(info.clearCost or 0) .. GodSystem.text("Unit_CoinShort", "c")
                if info.nextLevel then
                    third = GodSystem.text("Btn_HomeSafeUpgrade", "Upgrade range") .. " -" .. tostring(info.nextLevel.upgradeCost or 0) .. GodSystem.text("Unit_CoinShort", "c")
                end
            end
        end
    end
    return primary, secondary, third, fourth, fifth
end

function GodSystemWindow:applyHomeActionBar(payload)
    local primary, secondary, third, fourth, fifth = self:getHomeActionTitles(payload)
    if primary then gsSetButtonTitle(self.primaryButton, primary) end
    if secondary then gsSetButtonTitle(self.secondaryButton, secondary) end
    if third then gsSetButtonTitle(self.thirdButton, third) end
    if fourth then gsSetButtonTitle(self.fourthButton, fourth) end
    if fifth then gsSetButtonTitle(self.fifthButton, fifth) end
    self:setActionBar({
        { id = "primary", width = 156, minWidth = 92, visible = primary ~= nil },
        { id = "secondary", width = 156, minWidth = 92, visible = secondary ~= nil },
        { id = "third", width = 156, minWidth = 92, visible = third ~= nil },
        { id = "fourth", width = 126, minWidth = 82, visible = fourth ~= nil },
        { id = "fifth", width = 110, minWidth = 76, visible = fifth ~= nil },
    })
end

function GodSystemWindow:populateHome()
    self.primaryButton:setVisible(false)
    self.secondaryButton:setVisible(false)
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(not gsIsMultiplayer())
    gsSetButtonTitle(self.fourthButton, GodSystem.text("Btn_RefreshDisplay", "Refresh"))
    local entries = GodSystem.getHomeEntries()
    for i = 1, #entries do
        local entry = entries[i]
        local label = entry.label or GodSystem.text("Tab_Home", "Home/Teleport")
        if entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystem.getHomeSafeZoneInfo()
            if not info.homeSet then
                label = label .. " [" .. GodSystem.text("HomeSafe_NeedHomeShort", "Set home first") .. "]"
            elseif not info.unlocked then
                label = label .. " [" .. GodSystem.text("HomeSafe_Locked", "Locked") .. "]"
            else
                local state = info.enabled and GodSystem.text("HomeSafe_Enabled", "Enabled") or GodSystem.text("HomeSafe_Disabled", "Paused")
                label = label .. " [Lv." .. tostring(info.level) .. " R" .. tostring(info.radius) .. " " .. state .. "]"
            end
        elseif entry.kind == "temp" and not entry.owned then
            label = label .. " [" .. GodSystem.text("Home_TempLocked", "Locked") .. "]"
        elseif entry.point then
            label = label .. " [" .. GodSystem.text("Home_Set", "Set") .. "]"
        end
        self:addListItem(label, { kind = "homePoint", data = entry, detail = GodSystem.getHomeEntryDetail(entry) })
    end
    self:applyHomeActionBar(self:getSelectedPayload())
end

function GodSystemWindow:populateHistory()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(false)
    local history = GodSystem.getData().history or {}
    if #history == 0 then
        self:addWrappedListText(GodSystem.text("History_Empty", "No history"), { kind = "history", detail = "" })
        return
    end
    for i = 1, #history do
        self:addWrappedListText(self:formatHistoryEntry(history[i]), { kind = "history", data = history[i], detail = history[i].kind or "" })
    end
end

function GodSystemWindow:populateInfo()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(GodSystemConfig.EnableDebugTools == true)
    if GodSystemConfig.EnableDebugTools then
        gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_DebugCurrency", "Debug +500"))
    end
    local text = GodSystem.text("Info_Kill", "Zombie kill reward: +") .. tostring(GodSystemConfig.KillPointReward or 0)
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Shop", "Shop uses currency items in your inventory.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Unlock", "Recycle allowed vanilla items to unlock single-item shop entries.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Recycle", "Recycle skips equipped, favorite and blacklisted items.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_WaistSpace", "The space terminal reads first-level items from the system space terminal and sells selected items.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Traits", "Traits can be modified with currency. Risk traits are experimental.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Tasks", "Daily tasks: ") .. tostring(GodSystem.getDailyTaskCount()) .. " / " .. GodSystem.text("Info_MaxActive", "max active: ") .. tostring(GodSystem.getMaxActiveTasks())
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_Failure", "Expired unfinished tasks deduct currency.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystem.text("Info_HomeSafe", "Home safe zone clears loaded zombies without kill rewards or task progress.")
    self:addWrappedListText(text, { kind = "info", data = text })
end

local function gsBoolText(value)
    return value == true and "true" or "false"
end

function GodSystemWindow:populateDiagnostics()
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(gsIsMultiplayer())
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_DiagnosticsRefresh", "Refresh diagnostics"))

    local data = GodSystem.getData() or {}
    local server = data.serverDiagnostics or {}
    local client = {}
    if GodSystemNetwork and GodSystemNetwork.getDiagnostics then
        client = GodSystemNetwork.getDiagnostics() or {}
    end

    local lines = {
        GodSystem.text("Diag_Header", "Diagnostics"),
        "mode=" .. (gsIsMultiplayer() and "MP" or "SP") .. " version=" .. tostring(GodSystemConfig.Version or "?"),
        "balance=" .. tostring(GodSystem.getCurrencyTotal and GodSystem.getCurrencyTotal() or 0),
        "client.hasServerState=" .. gsBoolText(client.hasServerState),
        "client.pendingState=" .. gsBoolText(client.pendingState),
        "client.pendingCommand=" .. tostring(client.pendingCommand or "-"),
        "client.pendingElapsed=" .. tostring(math.floor((tonumber(client.pendingElapsedMs) or 0) / 1000)) .. "s/" .. tostring(math.floor((tonumber(client.pendingTimeoutMs) or 0) / 1000)) .. "s",
        "client.pendingTimeouts=" .. tostring(client.pendingTimeouts or 0) .. " last=" .. tostring(client.lastPendingTimeoutCommand or "-"),
        "client.pendingClearReason=" .. tostring(client.lastPendingClearReason or "-"),
        "client.stateSerial=" .. tostring(client.stateSerial or 0),
        "client.sentCommands=" .. tostring(client.sentCommands or 0) .. " failed=" .. tostring(client.failedCommands or 0),
        "client.receivedStates=" .. tostring(client.receivedStates or 0),
        "client.lastSentCommand=" .. tostring(client.lastSentCommand or "-"),
        "client.lastResultOk=" .. tostring(client.lastResultOk),
        "client.lastResultMessage=" .. tostring(client.lastResultMessage or "-"),
        "client.lastError=" .. tostring(client.lastError or "-"),
        "client.lastNotifyCode=" .. tostring(client.lastNotifyCode or "-"),
        "server.handledCommands=" .. tostring(server.handledCommands or 0) .. " failed=" .. tostring(server.failedCommands or 0),
        "server.lastCommand=" .. tostring(server.lastCommand or "-"),
        "server.lastResultOk=" .. tostring(server.lastResultOk),
        "server.lastResultMessage=" .. tostring(server.lastResultMessage or "-"),
        "server.lastError=" .. tostring(server.lastError or "-"),
        "server.lastTraitBenefitsOk=" .. tostring(server.lastTraitBenefitsOk),
        "server.lastTraitBenefitsApplied=" .. tostring(server.lastTraitBenefitsApplied or 0),
        "server.lastTraitBenefitsType=" .. tostring(server.lastTraitBenefitsType or "-"),
    }

    for i = 1, #lines do
        self:addWrappedListText(lines[i], { kind = "diagnostics", data = lines[i] })
    end
end

function gsAdminBoolText(value)
    return value == true and GodSystem.text("Admin_On", "ON") or GodSystem.text("Admin_Off", "OFF")
end

function gsAdminGroupLabel(group)
    local key = tostring(group or "base")
    return GodSystem.text("AdminGroup_" .. key, key)
end

function gsAdminSettingLabel(meta)
    meta = meta or {}
    return GodSystem.text(meta.labelKey or "", tostring(meta.key or ""))
end

function gsAdminSettingDesc(meta)
    meta = meta or {}
    return GodSystem.text(meta.descKey or "", "")
end

function gsAdminTypeLabel(typeName)
    local key = tostring(typeName or "")
    return GodSystem.text("AdminType_" .. key, key)
end

local function gsAdminValueText(meta, value)
    if meta and meta.type == "boolean" then
        return gsAdminBoolText(value)
    end
    return tostring(value)
end

local function gsAdminSettingText(meta, value)
    local group = gsAdminGroupLabel(meta and meta.group)
    local label = gsAdminSettingLabel(meta)
    local key = tostring(meta and meta.key or "")
    if meta and meta.type == "boolean" then
        return "[" .. group .. "] " .. label .. " (" .. key .. ") = " .. gsAdminBoolText(value)
    end
    return "[" .. group .. "] " .. label .. " (" .. key .. ") = " .. tostring(value)
end

function GodSystemWindow:addAdminListItem(text, payload)
    if self:adminRowMatchesSearch(text, payload) then
        self:addListItem(text, payload)
    end
end

local function gsAdminOverrideText(fullType, override)
    override = override or {}
    local parts = {}
    if override.buyPrice ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Buy", "buy") .. "=" .. tostring(override.buyPrice) end
    if override.sellPrice ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Sell", "sell") .. "=" .. tostring(override.sellPrice) end
    if override.category ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Category", "cat") .. "=" .. tostring(override.category) end
    if override.shopEnabled ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Shop", "shop") .. "=" .. gsAdminBoolText(override.shopEnabled) end
    if override.recycleEnabled ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Recycle", "recycle") .. "=" .. gsAdminBoolText(override.recycleEnabled) end
    if override.lotteryEnabled ~= nil then parts[#parts + 1] = GodSystem.text("AdminOverride_Lottery", "lottery") .. "=" .. gsAdminBoolText(override.lotteryEnabled) end
    if #parts == 0 then parts[#parts + 1] = GodSystem.text("AdminOverride_Default", "default") end
    return tostring(fullType or "") .. " | " .. table.concat(parts, ", ")
end

function gsAdminOverrideDetailText(fullType, override)
    local lines = {
        GodSystem.text("AdminOverride_Current", "Current override") .. ":",
        gsAdminOverrideText(fullType, override),
        "",
        GodSystem.text("Admin_Example", "Example") .. ":",
        "Base.Axe|buy=500,sell=25,cat=weapon,shop=1,recycle=1,lottery=1",
        "",
        GodSystem.text("AdminOverride_Buy", "buy") .. " buy = 500",
        GodSystem.text("AdminOverride_Sell", "sell") .. " sell = 25",
        GodSystem.text("AdminOverride_Category", "category") .. " cat = weapon",
        GodSystem.text("AdminOverride_Shop", "shop") .. " shop = 1/0",
        GodSystem.text("AdminOverride_Recycle", "recycle") .. " recycle = 1/0",
        GodSystem.text("AdminOverride_Lottery", "lottery") .. " lottery = 1/0",
    }
    return table.concat(lines, "\n")
end

function GodSystemWindow:populateAdmin()
    self.shopSearchPurpose = "admin"
    self:syncSearchBoxText(self.shopSearchPurpose)
    gsSetButtonTitle(self.primaryButton, GodSystem.text("Btn_AdminEdit", "Edit"))
    gsSetButtonTitle(self.secondaryButton, GodSystem.text("Btn_Refresh", "Refresh"))
    self.thirdButton:setVisible(true)
    gsSetButtonTitle(self.thirdButton, GodSystem.text("Btn_AdminReset", "Reset"))
    self:setDetailText(GodSystem.text("Admin_Select", "Select a setting or item override."))

    if not (GodSystem.isAdminConfigAllowed and GodSystem.isAdminConfigAllowed()) then
        self:addListItem(GodSystem.text("Admin_Only", "Admin only"), { kind = "adminInfo", detail = GodSystem.text("Admin_Only", "Admin only") })
        self:setActionBar({})
        return
    end

    local snapshot = GodSystem.getAdminConfigSnapshot()
    local settings = snapshot.settings or {}
    local meta = snapshot.meta or GodSystemAdminConfig.getMeta()
    self:addAdminListItem(GodSystem.text("Admin_AddItem", "+ Item override"), { kind = "adminAddItem", detail = GodSystem.text("Admin_AddItemDetail", "Add or replace one item override.") })
    for i = 1, #meta do
        local row = meta[i]
        if not (gsIsMultiplayer() and row.singlePlayerOnly == true) then
            local value = settings[row.key]
            local text = gsAdminSettingText(row, value)
            self:addAdminListItem(text, { kind = "adminSetting", data = row, value = value, detail = GodSystem.text("Admin_EditPrefix", "Edit ") .. tostring(row.key) })
        end
    end

    local overrides = snapshot.itemOverrides or {}
    local keys = {}
    for fullType, _ in pairs(overrides) do
        keys[#keys + 1] = fullType
    end
    table.sort(keys)
    for i = 1, #keys do
        local fullType = keys[i]
        local text = gsAdminOverrideText(fullType, overrides[fullType])
        self:addAdminListItem(text, { kind = "adminItemOverride", fullType = fullType, data = overrides[fullType], detail = text })
    end
    if self.list and self.list.items and #self.list.items == 0 then
        self:addListItem(GodSystem.text("Admin_SearchPlaceholder", "No matching admin config"), { kind = "empty", detail = GodSystem.text("Search_Label", "Search") })
    end
end

function GodSystemWindow:populateList()
    if self.mode == "recycle" then
        self.mode = "shop"
    end
    self:captureSelection()
    self:clearList()
    self.thirdButton:setVisible(false)
    self.secondaryButton:setVisible(true)
    self.primaryButton:setVisible(true)
    self:applyBaseLayout()
    self:setTaskLayout(self.mode == "tasks")
    self:setShopLayout(self.mode == "shop" or self.mode == "recycle" or self.mode == "admin" or self.mode == "lottery" or self.mode == "attribute")
    self:setTextPageLayout(self.mode == "history" or self.mode == "info" or self.mode == "diagnostics")
    self:updateModeButtonStyles()

    if self:needsServerState() then
        self:addSyncPlaceholder()
        if GodSystemNetwork and GodSystemNetwork.requestState then
            GodSystemNetwork.requestState(false)
        end
        self:setActionBar({})
        self:updateDetail()
        return
    end

    if self.mode == "shop" then
        self:populateShop()
    elseif self.mode == "lottery" then
        self:populateLottery()
    elseif self.mode == "recycle" then
        self:populateRecycle()
    elseif self.mode == "waist" then
        self:populateWaistSpace()
    elseif self.mode == "bank" then
        self:populateBank()
    elseif self.mode == "traits" then
        self:populateTraits()
    elseif self.mode == "attribute" then
        self:populateAttributes()
    elseif self.mode == "home" then
        self:populateHome()
    elseif self.mode == "tasks" then
        self:populateTasks()
    elseif self.mode == "upgrades" then
        self:populateUpgrades()
    elseif self.mode == "companion" then
        self:populateCompanion()
    elseif self.mode == "history" then
        self:populateHistory()
    elseif self.mode == "info" then
        self:populateInfo()
    elseif self.mode == "diagnostics" then
        self:populateDiagnostics()
    elseif self.mode == "attribute" then
        self:applyAttributeActionBar(self:getSelectedPayload())
    elseif self.mode == "admin" then
        self:populateAdmin()
    end

    if self.mode == "shop" then
        self:applyShopActionLayout()
    elseif self.mode == "lottery" then
        self:applyLotteryActionLayout()
    elseif self.mode == "recycle" then
        self:applyRecycleActionLayout()
    elseif self.mode == "home" then
        self:applyHomeActionBar(self:getSelectedPayload())
    elseif self.mode == "admin" then
        self:setActionBar({
            { id = "searchBox", width = 240, minWidth = 150 },
            { id = "primary", width = 118 },
            { id = "secondary", width = 118 },
            { id = "third", width = 118 },
        })
    else
        self:setStandardActionBar()
    end
    local selectionRestored = self:restoreSelection()
    self:restoreScrollState()
    if selectionRestored and self.pendingRestoreMode == self.mode then
        self:clearPendingActionSelection()
    end
    self:updateDetail()
    self:consumeLotteryResult()
end

function GodSystemWindow:getSelectedPayload()
    if self.mode == "tasks" and self.selectedTaskList == "active" and self.activeList then
        local index = math.floor(tonumber(self.activeList.selected) or 0)
        local selected = index > 0 and self.activeList.items[index] or nil
        local payload = selected and selected.item or nil
        return gsIsSelectablePayload(payload) and payload or nil
    end
    local index = math.floor(tonumber(self.list.selected) or 0)
    local selected = index > 0 and self.list.items[index] or nil
    local payload = selected and selected.item or nil
    return gsIsSelectablePayload(payload) and payload or nil
end

function GodSystemWindow:getPayloadFromListCallback(item)
    if item and item.kind then
        return item
    end
    if item and item.item then
        return item.item
    end
    return self:getSelectedPayload()
end

function GodSystemWindow:selectListRowAt(x, y, list, taskListName)
    list = list or self.list
    if list and list.rowAt then
        local row = list:rowAt(x, y)
        if row and row > 0 and list.items[row] then
            local payload = list.items[row].item
            if not gsIsSelectablePayload(payload) then return nil end
            list.selected = row
            if list == self.activeList then
                self.lastSelectableActiveRow = row
            else
                self.lastSelectableListRow = row
            end
            if self.mode == "tasks" and taskListName then
                self:clearOppositeTaskSelection(taskListName)
            end
            return payload
        end
    end
    return self:getSelectedPayload()
end

function GodSystemWindow:updateDetail()
    local payload = self:getSelectedPayload()
    if self.mode == "tasks" then
        self:updateTaskPrimaryButton(payload)
    end
    if self.mode == "shop" and self.thirdButton then
        local removable = payload and payload.kind == "shop" and payload.data and payload.data.unlocked == true
        self.thirdButton:setVisible(removable == true)
        self:applyShopActionLayout()
    end
    if self.mode == "home" then
        self:applyHomeActionBar(payload)
    end
    if self.mode == "bank" then
        self:updateBankActionButtons(payload)
    end
    if self.mode == "upgrades" then
        self:applyUpgradeActionBar(payload)
    end
    if self.mode == "companion" then
        self:applyCompanionActionBar(payload)
    end
    if self.mode == "attribute" then
        self:applyAttributeActionBar(payload)
    end
    if not payload then
        if self.mode == "recycle" then
            self:setDetailText(GodSystem.text("Hint_Recycle", "Click an item to view prices. Use button or right click to sell."))
        elseif self.mode == "shop" then
            self:setDetailText(GodSystem.text("Hint_Shop", "Only existing basic items are shown. Recycled vanilla items appear as unlocked entries."))
        elseif self.mode == "lottery" then
            self:setDetailText(GodSystem.text("Hint_Lottery", "Choose all-category or a category, then draw 1, 10, or a custom count. Results are granted directly."))
        elseif self.mode == "waist" then
            self:setDetailText(GodSystem.text("Hint_WaistSpace", "The space terminal reads the system space terminal. Click rows to select, then sell selected or sell all."))
        elseif self.mode == "bank" then
            self:setDetailText(GodSystem.text("Hint_Bank", "Deposit cash into current account, move current balance into fixed deposits, and withdraw when needed. Death penalty only deducts current account."))
        elseif self.mode == "traits" then
            self:setDetailText(GodSystem.text("Hint_Traits", "Buy positive traits or remove owned negative traits. Risk traits are experimental."))
        elseif self.mode == "attribute" then
            self:setDetailText(GodSystem.text("Hint_Attributes", "Select a standard skill, then buy XP by amount or upgrade to the next level."))
        elseif self.mode == "tasks" then
            self:setDetailText(GodSystem.text("Hint_TasksSplit", "Available tasks are on the left. Active tasks are on the right."))
        elseif self.mode == "upgrades" then
            self:setDetailText(GodSystem.text("Hint_Upgrades", "Upgrade system task limits here. Terminal upgrades stay on the space terminal page."))
        elseif self.mode == "companion" then
            self:setDetailText(GodSystem.text("Hint_Companion", "Select an ability to unlock or upgrade. Use the controls below for visibility, shortcuts and recall."))
        elseif self.mode == "home" then
            self:setDetailText(GodSystem.text("Hint_Home", "Set a home or temp teleport point, then teleport with confirmation."))
        elseif self.mode == "admin" then
            self:setDetailText("Select a setting or item override.")
        else
            self:setDetailText("")
        end
        return
    end
    if payload.kind == "shop" then
        local item = payload.data
        self:setDetailText(tostring(GodSystem.getShopDescription(item)) .. " " .. GodSystem.text("Detail_Content", "Content: ") .. GodSystem.getShopRewardText(item))
    elseif payload.kind == "lotteryCandidate" then
        local item = payload.data or {}
        self:setDetailText(tostring(item.label or item.fullType) .. "\n" ..
            tostring(item.fullType or "") .. "\n" ..
            GodSystem.text("Lottery_Category", "Category") .. ": " .. tostring(item.categoryLabel or item.categoryKey or "") .. "\n" ..
            GodSystem.text("Lottery_Price", "Price") .. ": " .. tostring(GodSystem.getLotteryPrice(item.categoryKey)) .. GodSystem.text("Unit_CoinShort", "c") .. "\n" ..
            GodSystem.text("Price_Buy", "Buy ") .. tostring(item.buyPrice or 0) .. GodSystem.text("Unit_CoinShort", "c"))
    elseif payload.kind == "lotteryResult" then
        self:setDetailText(self:formatLotteryResultDetail(payload.data))
    elseif payload.kind == "lotteryInfo" or payload.kind == "lotteryHeader" then
        self:setDetailText(payload.detail or "")
    elseif payload.kind == "recycle" then
        local group = payload.data
        local buyRef = GodSystem.getShopBuyReference(group.fullType)
        local buyText = buyRef and (GodSystem.text("Detail_BuyRef", "Buy ref: ") .. tostring(buyRef.label) .. " " .. tostring(buyRef.price) .. GodSystem.text("Unit_CoinShort", "c")) or GodSystem.text("Detail_BuyRefNone", "Buy ref: none")
        local priceText = ""
        if (group.unitDivisor or 1) > 1 then
            priceText = GodSystem.text("Price_BatchValue", "Batch value ") .. tostring(group.totalValue or 0) .. GodSystem.text("Unit_CoinShort", "c") .. "/" .. tostring(group.count or 0) .. GodSystem.text("Unit_ItemShort", " items") .. " (" .. tostring(group.unitDivisor) .. GodSystem.text("Unit_ItemToCoin", " items = 1c") .. ")"
        else
            priceText = GodSystem.text("Price_Sell", "Sell") .. " " .. tostring(group.valueEach) .. GodSystem.text("Unit_CoinEach", "c each")
        end
        self:setDetailText(GodSystem.text("Detail_Sell", "Sell: ") .. group.label .. " | " .. priceText .. ", " .. GodSystem.text("Detail_Count", "count ") .. tostring(group.count) .. " | " .. buyText)
    elseif payload.kind == "waist" then
        local group = payload.data
        local selected = self.waistSelected and self.waistSelected[group.fullType] == true
        local priceText = ""
        if (group.unitDivisor or 1) > 1 then
            priceText = GodSystem.text("Price_BatchValue", "Batch value ") .. tostring(group.totalValue or 0) .. GodSystem.text("Unit_CoinShort", "c") .. "/" .. tostring(group.count or 0) .. GodSystem.text("Unit_ItemShort", " items") .. " (" .. tostring(group.unitDivisor) .. GodSystem.text("Unit_ItemToCoin", " items = 1c") .. ")"
        else
            priceText = GodSystem.text("Price_Sell", "Sell") .. " " .. tostring(group.valueEach) .. GodSystem.text("Unit_CoinEach", "c each")
        end
        local selectedText = selected and GodSystem.text("Waist_Selected", "Selected") or GodSystem.text("Waist_Unselected", "Not selected")
        self:setDetailText(selectedText .. " | " .. GodSystem.text("Detail_Sell", "Sell: ") .. group.label .. " | " .. priceText .. ", " .. GodSystem.text("Detail_Count", "count ") .. tostring(group.count))
    elseif payload.kind == "attribute" then
        local row = payload.data or {}
        local nextLevel = math.min(tonumber(row.maxLevel) or 10, (tonumber(row.currentLevel) or 0) + 1)
        local quote = GodSystem.getAttributeQuote(row.index, "targetLevel", nextLevel)
        local nextText = quote and (tostring(math.floor(quote.actualXp or 0)) .. " XP / " .. tostring(quote.cost or 0) .. GodSystem.text("Unit_CoinShort", "c")) or GodSystem.text("Attribute_Maxed", "Maxed")
        self:setDetailText(tostring(row.label or "") .. "\n" ..
            GodSystem.text("Attribute_CurrentLevel", "Current level") .. ": " .. tostring(row.currentLevel or 0) .. "/" .. tostring(row.maxLevel or 10) .. "\n" ..
            GodSystem.text("Attribute_TotalXP", "Total XP") .. ": " .. tostring(math.floor(row.currentXp or 0)) .. "/" .. tostring(math.floor(row.maxXp or 0)) .. "\n" ..
            GodSystem.text("Attribute_NextCost", "Next level") .. ": " .. nextText .. "\n" ..
            GodSystem.text("Attribute_Rate", "Rate") .. ": 1" .. GodSystem.text("Unit_CoinShort", "c") .. " = " .. tostring(GodSystemAttributes.getXpPerCoin()) .. " XP")
    elseif payload.kind == "bankSummary" or payload.kind == "bankCurrent" then
        local summary = GodSystem.getBankSummary()
        local text = GodSystem.text("Bank_DetailSummaryV2", "Cash {1} | Current {2} | Investment {3} | Legacy fixed principal {4} | Legacy mature value {5} | Death deducts current only, preview {6}")
        self:setDetailText(gsFormatTemplate(text, { summary.cash or 0, summary.current or 0, summary.investmentTotal or 0, summary.fixedPrincipal or 0, summary.fixedMatureValue or 0, summary.deathPenalty or 0 }))
    elseif payload.kind == "bankTerm" then
        local term = payload.data or {}
        local days = math.max(1, math.floor(tonumber(term.days) or 1))
        local rate = math.floor((tonumber(term.interestRate) or 0) * 100)
        self:setDetailText(gsFormatTemplate(GodSystem.text("Bank_DetailTerm", "Move current account balance or carried cash into a {1}-day fixed deposit. Interest {2}%. Early withdrawal has no interest and loses part of principal."), { days, rate }))
    elseif payload.kind == "bankInvestment" then
        local account = payload.data or {}
        local profile = payload.profile or GodSystem.getBankInvestmentProfile(account.tierId) or {}
        local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
        local status = account.redeemUnlocked == true and GodSystem.text("Bank_InvestmentRedeemable", "Redeemable") or GodSystem.text("Bank_InvestmentLocked", "Locked until first settlement")
        local rule = gsFormatTemplate(GodSystem.text("Bank_InvestmentRule", "Gain {1}% chance +{2}% | Loss {3}% chance -{4}% | Flat {5}%"), {
            profile.gainChance or 0,
            profile.gainPercent or 0,
            profile.lossChance or 0,
            profile.lossPercent or 0,
            math.max(0, 100 - (profile.gainChance or 0) - (profile.lossChance or 0)),
        })
        local progress = gsFormatTemplate(GodSystem.text("Bank_InvestmentProgress", "Online progress {1}/{2}h"), { math.floor(tonumber(account.onlineHours) or 0), settlementHours })
        self:setDetailText(GodSystem.getBankInvestmentLabel(profile.id or account.tierId) .. " | " .. tostring(account.balance or 0) .. GodSystem.text("Unit_CoinShort", "c") .. "\n" .. rule .. "\n" .. progress .. " | " .. status)
    elseif payload.kind == "bankFixed" then
        local entry = payload.data
        local payout, interestOrPenalty, mature = GodSystem.getBankFixedPayout(entry)
        local text = mature and GodSystem.text("Bank_DetailFixedMature", "Matured. Withdraw to current account with interest.") or GodSystem.text("Bank_DetailFixedEarly", "Not mature. Early withdrawal gives no interest and applies penalty.")
        self:setDetailText(text .. " | " .. GodSystem.text("Bank_Payout", "payout") .. " " .. tostring(payout) .. " | " .. GodSystem.text("Bank_InterestPenalty", "interest/penalty") .. " " .. tostring(interestOrPenalty))
    elseif payload.kind == "bankLoanSummary" then
        local s = payload.data or GodSystem.getBankLoanSummary and GodSystem.getBankLoanSummary() or {}
        local text = gsFormatTemplate(GodSystem.text("Bank_LoanSummary", "Loan credit {1} | Available {2} | Debt {3} | Frozen {4}"), {
            tostring(s.creditTotal or 0),
            tostring(s.creditAvailable or 0),
            tostring(s.unpaidTotal or 0),
            tostring(s.freezeLeftHours or 0) .. GodSystem.text("Unit_Hour", "h"),
        })
        self:setDetailText(text)
    elseif payload.kind == "bankLoanPlan" then
        local plan = payload.data or {}
        local s = payload.summary or GodSystem.getBankLoanSummary and GodSystem.getBankLoanSummary() or {}
        local rate = math.floor((tonumber(plan.totalInterestRate) or 0) * 100)
        local days = math.max(1, math.floor((tonumber(plan.dueHours) or 72) / 24))
        local periods = math.max(1, math.floor(tonumber(plan.periods) or 1))
        local text = GodSystem.text("Bank_LoanPrompt", "Enter loan amount. Loan goes to current account; overdue more than 10 days causes bankruptcy.") ..
            " | " .. GodSystem.text("Bank_LoanDueNow", "Due now") .. ": " .. tostring(days) .. "d x " .. tostring(periods) ..
            " | " .. GodSystem.text("Bank_Interest", "interest") .. ": " .. tostring(rate) .. "%" ..
            " | " .. GodSystem.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(s.creditAvailable or 0) .. GodSystem.text("Unit_CoinShort", "c")
        self:setDetailText(text)
    elseif payload.kind == "bankLoanActive" then
        local loan = payload.data or {}
        local s = payload.summary or GodSystem.getBankLoanSummary and GodSystem.getBankLoanSummary() or {}
        local text = gsFormatTemplate(GodSystem.text("Bank_LoanActive", "Active loan {1} | Paid {2}/{3}"), {
            tostring(loan.id or ""),
            tostring(loan.paid or 0),
            tostring(loan.totalDue or 0),
        }) .. " | " .. GodSystem.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(s.dueNow or 0) .. GodSystem.text("Unit_CoinShort", "c") ..
            " | " .. GodSystem.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(s.payoff or 0) .. GodSystem.text("Unit_CoinShort", "c")
        if s.bankruptcyInHours then
            text = text .. " | " .. GodSystem.text("Bank_LoanFrozen", "Loan frozen, remaining {1} hours"):gsub("{1}", tostring(s.bankruptcyInHours))
        end
        self:setDetailText(text)
    elseif payload.kind == "task" then
        self:setDetailText(GodSystem.getTaskDetailText(payload.data))
    elseif payload.kind == "trait" then
        self:setDetailText(GodSystem.getTraitDetailText(payload.data))
    elseif payload.kind == "upgrade" then
        local upgradeType = payload.data and payload.data.upgradeType
        self:setDetailText(GodSystem.getSystemUpgradeDetailText(upgradeType))
    elseif payload.kind == "medicalService" then
        local info = payload.data or {}
        self:setDetailText(tostring(info.desc or "") .. " | " .. GodSystem.text("Upgrade_Cost", "Cost") .. " " .. tostring(info.cost or 0) .. GodSystem.text("Unit_CoinShort", "c"))
    elseif payload.kind == "companionNode" or payload.kind == "companionState" then
        local detail = tostring(payload.detail or "")
        local state = GodSystemCompanion and GodSystemCompanion.getStateDetail and GodSystemCompanion.getStateDetail() or ""
        if state ~= "" and payload.kind ~= "companionState" then detail = detail .. "\n\n" .. state end
        self:setDetailText(detail)
    elseif payload.kind == "homePoint" then
        local entry = payload.data
        self:setDetailText((entry and entry.label or GodSystem.text("Tab_Home", "Home/Teleport")) .. " | " .. GodSystem.getHomeEntryDetail(entry))
    elseif payload.kind == "traitHeader" then
        self:setDetailText(payload.detail or "")
    elseif payload.kind == "history" then
        self:setDetailText(payload.data and payload.data.text or GodSystem.text("Tab_History", "History"))
    elseif payload.kind == "info" then
        self:setDetailText(payload.data or "")
    elseif payload.kind == "adminSetting" then
        local meta = payload.data or {}
        local lines = {
            GodSystem.text("Admin_Name", "Name") .. ": " .. gsAdminSettingLabel(meta),
            GodSystem.text("Admin_InternalKey", "Key") .. ": " .. tostring(meta.key or ""),
            GodSystem.text("Admin_Type", "Type") .. ": " .. gsAdminTypeLabel(meta.type),
            GodSystem.text("Admin_Group", "Group") .. ": " .. gsAdminGroupLabel(meta.group),
        }
        if meta.min ~= nil or meta.max ~= nil then
            lines[#lines + 1] = GodSystem.text("Admin_Range", "Range") .. ": " .. tostring(meta.min or "-") .. " - " .. tostring(meta.max or "-")
        end
        lines[#lines + 1] = GodSystem.text("Admin_Default", "Default") .. ": " .. gsAdminValueText(meta, meta.default)
        lines[#lines + 1] = GodSystem.text("Admin_Current", "Current") .. ": " .. gsAdminValueText(meta, payload.value)
        local desc = gsAdminSettingDesc(meta)
        if desc and desc ~= "" then
            lines[#lines + 1] = ""
            lines[#lines + 1] = GodSystem.text("Admin_Description", "Description") .. ": " .. desc
        end
        self:setDetailText(table.concat(lines, "\n"))
    elseif payload.kind == "adminAddItem" then
        self:setDetailText(GodSystem.text("Admin_FormatHint", "Format: Base.Axe|buy=500,sell=25,cat=weapon,shop=1,recycle=1,lottery=1"))
    elseif payload.kind == "adminItemOverride" then
        self:setDetailText(gsAdminOverrideDetailText(payload.fullType, payload.data))
    elseif payload.kind == "empty" then
        self:setDetailText(payload.detail or "")
    else
        self:setDetailText("")
    end
end

function GodSystemWindow:confirmMedicalService(service)
    if not service or not service.action then
        GodSystem.notify(GodSystem.text("Notify_SelectOne", "Select an item first"))
        return
    end
    local message = gsFormatTemplate(GodSystem.text("Confirm_MedicalService", "Confirm medical service: {1}\nCost: {2}"), {
        tostring(service.label or service.action),
        tostring(service.cost or 0) .. GodSystem.text("Unit_CoinShort", "c"),
    })
    if service.desc and tostring(service.desc) ~= "" then
        local lines = gsWrapText(service.desc, UIFont.Small, 430)
        local desc = {}
        for i = 1, math.min(#lines, 5) do
            desc[#desc + 1] = lines[i]
        end
        message = message .. "\n\n" .. table.concat(desc, "\n")
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 140)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 280, message, true, self, self.onMedicalServiceConfirm, playerNum, { action = service.action })
        modal:initialise()
        modal:addToUIManager()
    else
        local sent = GodSystem.performMedicalService(service.action)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onMedicalServiceConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local sent = GodSystem.performMedicalService(payload and payload.action)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:confirmTraitModification(entry)
    if not entry then
        GodSystem.notify(GodSystem.text("Notify_SelectTrait", "Select a trait first"))
        return
    end
    if entry.disabledReason then
        GodSystem.notify(entry.disabledReason)
        return
    end

    local actionText = entry.action == "remove" and GodSystem.text("Trait_ActionRemove", "Remove negative trait") or GodSystem.text("Trait_ActionBuy", "Buy positive trait")
    local message = actionText .. "\n" ..
        tostring(entry.label or entry.traitType) .. "\n" ..
        GodSystem.text("Trait_PointCost", "Trait points ") .. tostring(entry.costPoints or 0) .. "\n" ..
        GodSystem.text("Trait_ConfirmCost", "Cost: ") .. tostring(entry.price or 0) .. GodSystem.text("Unit_CoinShort", "c")
    if entry.description and tostring(entry.description) ~= "" then
        local descLines = gsWrapText(entry.description, UIFont.Small, 430)
        local desc = {}
        for i = 1, math.min(#descLines, 5) do
            table.insert(desc, descLines[i])
        end
        message = message .. "\n\n" .. table.concat(desc, "\n")
    end
    if entry.action == "buy" then
        message = message .. "\n\n" .. GodSystem.text("Trait_EffectWarning", "Trait effect warning: skill bonuses and recipes are attempted immediately; carry capacity, body changes and starting items may require reloading, and items are not guaranteed.")
    end
    if entry.risk then
        message = message .. "\n" .. GodSystem.text("Trait_RiskConfirm", "Risk: experimental trait, test carefully.")
    end
    if entry.conflictLabels and #entry.conflictLabels > 0 then
        message = message .. "\n" .. GodSystem.text("Trait_Conflicts", "Conflicts: ") .. table.concat(entry.conflictLabels, ", ")
    end

    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 150)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 300, message, true, self, self.onTraitConfirm, playerNum, { action = entry.action, traitType = entry.traitType })
        modal:initialise()
        modal:addToUIManager()
    else
        GodSystem.notify(GodSystem.text("Notify_TraitConfirmMissing", "Confirmation dialog unavailable"))
    end
end

function GodSystemWindow:onTraitConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    if payload then
        local sent = GodSystem.performTraitModification(payload.action, payload.traitType)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:confirmAbandonTask(task)
    if not task or task.status ~= "active" then
        GodSystem.notify(GodSystem.text("Notify_SelectTask", "Select a task first"))
        return
    end
    local message = GodSystem.text("Confirm_AbandonTask", "Abandon this task? This counts as failure.") .. "\n" ..
        GodSystem.getTaskListTitle(task) .. "\n" ..
        GodSystem.text("Task_Progress", "Progress") .. ": " .. GodSystem.getTaskListStatusLine(task) .. "\n" ..
        GodSystem.text("Task_Penalty", "Penalty") .. ": " .. tostring(task.penaltyPoints or 0) .. GodSystem.text("Unit_CoinShort", "c")
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 125)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 250, message, true, self, self.onAbandonTaskConfirm, playerNum, { taskId = task.taskId })
        modal:initialise()
        modal:addToUIManager()
    else
        local sent = GodSystem.abandonTask(task)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onAbandonTaskConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local task = nil
    local tasks = GodSystem.getData().tasks or {}
    local taskId = payload and payload.taskId
    for i = 1, #tasks do
        if tostring(tasks[i].taskId or "") == tostring(taskId or "") then
            task = tasks[i]
            break
        end
    end
    local sent = GodSystem.abandonTask(task)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:onInfoDialogClose(button, payload)
end

function GodSystemWindow:showInfoDialog(message)
    message = tostring(message or "")
    if message == "" then
        return
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 120)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 240, message, false, self, self.onInfoDialogClose, playerNum, nil)
        modal:initialise()
        modal:addToUIManager()
    else
        GodSystem.notify(message)
    end
end

function GodSystemWindow:formatLotteryResultDetail(result)
    if not result then
        return ""
    end
    local lines = {
        GodSystem.text("Lottery_ResultCount", "Draw count") .. ": " .. tostring(result.count or 0),
        GodSystem.text("Lottery_ResultCost", "Total cost") .. ": " .. tostring(result.totalCost or 0) .. GodSystem.text("Unit_CoinShort", "c"),
    }
    local grouped = result.groupedItems or {}
    for i = 1, #grouped do
        local item = grouped[i]
        local label = item.fullType and GodSystem.getItemDisplayName(item.fullType, item.label) or item.label
        lines[#lines + 1] = tostring(label or item.fullType) .. " x" .. tostring(item.count or 1)
    end
    return table.concat(lines, "\n")
end

function GodSystemWindow:showLotteryResult(result)
    if not result then
        return
    end
    self.latestLotteryResult = result
    local message = GodSystem.text("Result_LotteryTitle", "Lottery result") .. "\n" .. self:formatLotteryResultDetail(result)
    self:showInfoDialog(message)
end

function GodSystemWindow:consumeLotteryResult()
    if not gsIsMultiplayer() or not GodSystemNetwork then
        return
    end
    local result = GodSystemNetwork.pendingLotteryResult or GodSystemNetwork.pendingShopLotteryResult
    if not result then
        return
    end
    GodSystemNetwork.pendingLotteryResult = nil
    GodSystemNetwork.pendingShopLotteryResult = nil
    self:showLotteryResult(result)
end

function GodSystemWindow:getLotteryCustomCount()
    local value = self.lotteryCustomCount or 10
    if self.shopSearchBox and self.shopSearchBox.getInternalText then
        value = tonumber(self.shopSearchBox:getInternalText()) or value
    end
    value = math.max(1, math.floor(tonumber(value) or 1))
    self.lotteryCustomCount = value
    return value
end

function GodSystemWindow:performLottery(count)
    local categoryKey = self.lotteryCategoryKey or "all"
    local mode = categoryKey == "all" and "all" or "category"
    count = math.max(1, math.floor(tonumber(count) or 1))
    local ok, result = GodSystem.performLotteryDraw(mode, categoryKey, count)
    if gsIsMultiplayer() then
        self:finishMultiplayerCommand(ok)
        return
    end
    if ok and result then
        self:showLotteryResult(result)
    end
    self:populateList()
end

function GodSystemWindow:getHomeConfirmMessage(action, index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local cost = 0
    local line = ""
    if action == "setHome" then
        cost = GodSystemConfig.HomeSetCost or 100
        line = GodSystem.text("Confirm_HomeSet", "Set current position as home?")
    elseif action == "buyTemp" then
        cost = GodSystemConfig.TempTeleportSlotCost or 500
        line = GodSystem.text("Confirm_HomeBuyTemp", "Buy temp teleport point ") .. tostring(index) .. GodSystem.text("Confirm_Question", ". Confirm?")
    elseif action == "setTemp" then
        cost = GodSystemConfig.TempTeleportSetCost or 100
        line = GodSystem.text("Confirm_HomeSetTemp", "Set or overwrite temp teleport point ") .. tostring(index) .. GodSystem.text("Confirm_Question", ". Confirm?")
    elseif action == "teleportHome" then
        cost = GodSystemConfig.HomeTravelCost or 10
        line = GodSystem.text("Confirm_HomeTeleport", "You are teleporting home. Confirm?")
    elseif action == "teleportTemp" then
        cost = GodSystemConfig.HomeTravelCost or 10
        line = GodSystem.text("Confirm_HomeTeleportTemp", "You are teleporting to temp point ") .. tostring(index) .. GodSystem.text("Confirm_Question", ". Confirm?")
    elseif action == "return" then
        cost = GodSystemConfig.HomeTravelCost or 10
        local home = GodSystem.getHomeSystem()
        local source = self:formatHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystem.text("Confirm_HomeReturn", "You are returning to the departure point: ") .. tostring(source) .. GodSystem.text("Confirm_Question", ". Confirm?")
    elseif action == "clearReturn" then
        cost = 0
        local home = GodSystem.getHomeSystem()
        local source = self:formatHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystem.text("Confirm_HomeClearReturn", "You are clearing the current departure point: ") .. tostring(source) .. GodSystem.text("Confirm_Question", ". Confirm?")
    elseif action == "unlockSafeZone" then
        local info = GodSystem.getHomeSafeZoneInfo()
        cost = info.unlockCost or 0
        line = GodSystem.text("Confirm_HomeSafeUnlock", "Unlock home safe zone?")
    elseif action == "upgradeSafeZone" then
        local info = GodSystem.getHomeSafeZoneInfo()
        cost = info.nextLevel and (info.nextLevel.upgradeCost or 0) or 0
        line = GodSystem.text("Confirm_HomeSafeUpgrade", "Upgrade home safe zone range?")
    elseif action == "clearSafeZone" then
        local info = GodSystem.getHomeSafeZoneInfo()
        cost = info.clearCost or 0
        line = GodSystem.text("Confirm_HomeSafeClear", "Clear zombies in home safe zone now?")
    end
    local pos = GodSystem.formatPosition((getPlayer() and { x = getPlayer():getX(), y = getPlayer():getY(), z = getPlayer():getZ() }) or nil)
    return line .. "\n" .. GodSystem.text("Home_CurrentPosition", "Current: ") .. pos .. "\n" .. GodSystem.text("Trait_ConfirmCost", "Cost: ") .. tostring(cost) .. GodSystem.text("Unit_CoinShort", "c")
end

function GodSystemWindow:confirmHomeAction(action, index)
    if not action then
        return
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, self:getHomeConfirmMessage(action, index), true, self, self.onHomeConfirm, playerNum, { action = action, index = index })
        modal:initialise()
        modal:addToUIManager()
    else
        GodSystem.notify(GodSystem.text("Notify_TraitConfirmMissing", "Confirmation dialog unavailable"))
    end
end

function GodSystemWindow:onHomeConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    if payload then
        local sent = GodSystem.performHomeAction(payload.action, payload.index)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:showBankAmountDialog(action, message, termId, entryId)
    local w, h = 340, 150
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemBankAmountDialog:new(x, y, w, h, self, {
        action = action,
        message = message,
        termId = termId,
        entryId = entryId,
    })
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setVisible(true)
end

function GodSystemWindow:showAttributeAmountDialog(payload)
    payload = payload or self:getSelectedPayload()
    local row = payload and payload.kind == "attribute" and payload.data or nil
    if not row or row.maxed == true then
        GodSystem.notify(GodSystem.text(row and "Notify_AttributeMaxed" or "Notify_AttributeSelect", row and "This skill is already maxed" or "Select a skill first"))
        return
    end
    self:prepareActionSelection(payload)
    local title = GodSystem.text("Attribute_BuyXP", "Buy XP")
    local message = GodSystem.text("Attribute_AmountPrompt", "Enter the amount of currency to spend")
    local w, h = 380, 150
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemBankAmountDialog:new(x, y, w, h, self, {
        kind = "attribute",
        title = title,
        message = message,
        perkIndex = row.index,
        mode = "amount",
    })
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setVisible(true)
end

function GodSystemWindow:showAttributeNextLevelConfirm(payload)
    payload = payload or self:getSelectedPayload()
    local row = payload and payload.kind == "attribute" and payload.data or nil
    if not row or row.maxed == true then
        GodSystem.notify(GodSystem.text(row and "Notify_AttributeMaxed" or "Notify_AttributeSelect", row and "This skill is already maxed" or "Select a skill first"))
        return
    end
    self:prepareActionSelection(payload)
    local currentLevel = math.max(0, math.floor(tonumber(row.currentLevel) or 0))
    local quote = GodSystem.getAttributeQuote(row.index, "targetLevel", currentLevel + 1)
    if not quote or (tonumber(quote.actualXp) or 0) <= 0 then
        GodSystem.notify(GodSystem.text("Notify_AttributeInvalid", "Unable to purchase skill XP"))
        return
    end
    local targetLevel = currentLevel + 1
    local message = GodSystem.text("Attribute_NextLevelConfirm", "Upgrade this skill to the next level?") .. "\n\n"
        .. tostring(row.label or quote.info and quote.info.label or "") .. "\n"
        .. GodSystem.text("Attribute_CurrentLevel", "Current level") .. ": " .. tostring(currentLevel) .. "\n"
        .. GodSystem.text("Attribute_TargetLevel", "Target level") .. ": " .. tostring(targetLevel) .. "\n"
        .. GodSystem.text("Attribute_RequiredXP", "Required XP") .. ": " .. tostring(math.floor(tonumber(quote.actualXp) or 0)) .. " XP\n"
        .. GodSystem.text("Attribute_Cost", "Cost") .. ": " .. tostring(math.floor(tonumber(quote.cost) or 0)) .. GodSystem.text("Unit_Coin", " coins")
    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
    local y = math.max(80, (getCore():getScreenHeight() / 2) - 140)
    local modal = ISModalDialog:new(x, y, 500, 280, message, true, self, self.onAttributeNextLevelConfirm, playerNum, {
        perkIndex = row.index,
        targetLevel = targetLevel,
    })
    modal:initialise()
    modal:addToUIManager()
end

function GodSystemWindow:onAttributeNextLevelConfirm(button, payload)
    if not button or button.internal ~= "YES" or not payload then
        self:clearPendingActionSelection()
        return
    end
    local sent = GodSystem.performAttributePurchase(payload.perkIndex, "targetLevel", payload.targetLevel)
    self:finishMultiplayerCommand(sent)
    if sent == false then self:clearPendingActionSelection() end
end

function GodSystemWindow:showAdminSettingDialog(payload)
    if not payload or payload.kind ~= "adminSetting" then
        GodSystem.notify(GodSystem.text("Admin_SelectSetting", "Select a setting"))
        return
    end
    local meta = payload.data or {}
    local w, h = 520, 150
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemAdminTextDialog:new(x, y, w, h, self, {
        kind = "setting",
        title = GodSystem.text("Admin_DialogTitle", "GodSystem Admin"),
        message = tostring(meta.key or "") .. " (" .. tostring(meta.type or "") .. ")",
        key = meta.key,
        settingType = meta.type,
        value = tostring(payload.value),
    })
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setVisible(true)
end

local function gsParseAdminBool(text)
    text = tostring(text or ""):lower()
    return text == "1" or text == "true" or text == "on" or text == "yes"
end

local function gsParseAdminOverrideText(text)
    local fullType = nil
    local body = text
    local pipe = string.find(text, "|", 1, true)
    if pipe then
        fullType = gsTrim(string.sub(text, 1, pipe - 1))
        body = string.sub(text, pipe + 1)
    end
    local override = {}
    for part in string.gmatch(body or "", "[^,]+") do
        local eq = string.find(part, "=", 1, true)
        if eq then
            local key = gsTrim(string.sub(part, 1, eq - 1)):lower()
            local value = gsTrim(string.sub(part, eq + 1))
            if key == "buy" or key == "buyprice" then
                override.buyPrice = tonumber(value)
            elseif key == "sell" or key == "sellprice" then
                override.sellPrice = tonumber(value)
            elseif key == "cat" or key == "category" then
                override.category = value
            elseif key == "shop" then
                override.shopEnabled = gsParseAdminBool(value)
            elseif key == "recycle" then
                override.recycleEnabled = gsParseAdminBool(value)
            elseif key == "lottery" then
                override.lotteryEnabled = gsParseAdminBool(value)
            elseif key == "note" then
                override.note = value
            end
        end
    end
    return fullType, override
end

function GodSystemWindow:showAdminItemDialog(payload)
    payload = payload or {}
    local w, h = 620, 160
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local value = "Base.Axe|buy=500,sell=25,cat=weapon,shop=1,recycle=1,lottery=1"
    if payload.kind == "adminItemOverride" then
        local override = payload.data or {}
        local parts = {}
        if override.buyPrice ~= nil then parts[#parts + 1] = "buy=" .. tostring(override.buyPrice) end
        if override.sellPrice ~= nil then parts[#parts + 1] = "sell=" .. tostring(override.sellPrice) end
        if override.category ~= nil then parts[#parts + 1] = "cat=" .. tostring(override.category) end
        if override.shopEnabled ~= nil then parts[#parts + 1] = "shop=" .. (override.shopEnabled and "1" or "0") end
        if override.recycleEnabled ~= nil then parts[#parts + 1] = "recycle=" .. (override.recycleEnabled and "1" or "0") end
        if override.lotteryEnabled ~= nil then parts[#parts + 1] = "lottery=" .. (override.lotteryEnabled and "1" or "0") end
        value = tostring(payload.fullType or "") .. "|" .. table.concat(parts, ",")
    end
    local dialog = GodSystemAdminTextDialog:new(x, y, w, h, self, {
        kind = "item",
        title = GodSystem.text("Admin_ItemDialogTitle", "GodSystem Item Override"),
        message = GodSystem.text("Admin_FormatHint", "fullType|buy=500,sell=25,cat=weapon,shop=1,recycle=1,lottery=1"),
        value = value,
    })
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setVisible(true)
end

function GodSystemWindow:onAdminDialogConfirm(payload, text)
    payload = payload or {}
    if payload.kind == "setting" then
        local snapshot = GodSystem.getAdminConfigSnapshot()
        local settings = {}
        for key, value in pairs(snapshot.settings or {}) do settings[key] = value end
        if payload.settingType == "boolean" then
            settings[payload.key] = gsParseAdminBool(text)
        else
            settings[payload.key] = tonumber(text)
        end
        local sent = GodSystem.saveAdminSettings(settings)
        self:finishMultiplayerCommand(sent)
        self:requestDeferredPopulate(2)
    elseif payload.kind == "item" then
        local fullType, override = gsParseAdminOverrideText(text)
        if not fullType or fullType == "" then
            GodSystem.notify(GodSystem.text("Admin_ItemRequired", "Item fullType required"))
            return
        end
        local sent = GodSystem.saveItemOverride(fullType, override)
        self:finishMultiplayerCommand(sent)
        self:requestDeferredPopulate(2)
    end
end

function GodSystemWindow:confirmBankFixedWithdraw(entry)
    if not entry then
        GodSystem.notify(GodSystem.text("Notify_BankSelectFixed", "Select a fixed deposit first"))
        return
    end
    local payout, interestOrPenalty, mature = GodSystem.getBankFixedPayout(entry)
    local message = ""
    if mature then
        message = GodSystem.text("Confirm_BankFixedWithdraw", "Withdraw matured fixed deposit to current account?")
    else
        message = GodSystem.text("Confirm_BankFixedEarlyWithdraw", "Fixed deposit is not mature. Early withdrawal gives no interest and applies penalty. Continue?")
    end
    message = message .. "\n" .. GodSystem.text("Bank_Payout", "payout") .. ": " .. tostring(payout)
    if interestOrPenalty < 0 then
        message = message .. "\n" .. GodSystem.text("Bank_Penalty", "penalty") .. ": " .. tostring(math.abs(interestOrPenalty))
    elseif interestOrPenalty > 0 then
        message = message .. "\n" .. GodSystem.text("Bank_Interest", "interest") .. ": " .. tostring(interestOrPenalty)
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 120)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 240, message, true, self, self.onBankFixedConfirm, playerNum, { entryId = entry.id })
        modal:initialise()
        modal:addToUIManager()
    else
        local sent = GodSystem.performBankAction("withdrawFixed", nil, nil, entry.id)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onBankFixedConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local sent = GodSystem.performBankAction("withdrawFixed", nil, nil, payload and payload.entryId)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:getSelectedHomeEntry()
    local payload = self:getSelectedPayload()
    if payload and payload.kind == "homePoint" then
        return payload.data
    end
    return nil
end

function GodSystemWindow:onPrimaryAction()
    local payload = self:getSelectedPayload()
    if self.mode == "attribute" then
        self:showAttributeAmountDialog(payload)
        return
    end
    if self.mode == "companion" then
        if not payload or payload.kind ~= "companionNode" then
            GodSystem.notify(GodSystem.text("Notify_CompanionSelectAbility", "Select a companion ability"))
            return
        end
        self:prepareActionSelection(payload)
        if GodSystem.purchaseCompanionNode(payload.id) then
            self:populateList()
        else
            self:clearPendingActionSelection()
        end
        return
    end
    if self.mode == "admin" then
        if not payload then
            GodSystem.notify(GodSystem.text("Admin_SelectItemOrSetting", "Select a setting or item override"))
            return
        end
        if payload.kind == "adminSetting" then
            self:showAdminSettingDialog(payload)
        elseif payload.kind == "adminAddItem" or payload.kind == "adminItemOverride" then
            self:showAdminItemDialog(payload)
        else
            GodSystem.notify(GodSystem.text("Admin_SelectItemOrSetting", "Select a setting or item override"))
        end
        return
    end
    if self.mode == "info" or self.mode == "history" or self.mode == "diagnostics" then
        self:close()
        return
    end
    if self.mode == "lottery" then
        self:performLottery(1)
        return
    end
    if self.mode == "bank" then
        if payload and payload.kind == "bankLoanPlan" then
            local plan = payload.data or {}
            self:showBankAmountDialog("borrowLoan", GodSystem.text("Bank_LoanPrompt", "Enter loan amount. Loan goes to current account; overdue more than 10 days causes bankruptcy."), plan.id)
            return
        elseif payload and payload.kind == "bankLoanActive" then
            local sent = GodSystem.performBankAction("repayLoanDue", 1)
            self:finishMultiplayerCommand(sent)
            return
        elseif payload and payload.kind == "bankInvestment" then
            local profile = payload.profile or {}
            self:showBankAmountDialog("investFromCurrent", GodSystem.text("Bank_InvestCurrentPrompt", "Enter amount to invest from current account"), profile.id)
            return
        elseif payload and payload.kind == "bankFixed" then
            self:confirmBankFixedWithdraw(payload.data)
            return
        end
        self:showBankAmountDialog("deposit", GodSystem.text("Bank_DepositPrompt", "Deposit cash into current account"))
        return
    end
    if self.mode == "upgrades" then
        if not payload then
            GodSystem.notify(GodSystem.text("Notify_SelectOne", "Select an item first"))
            return
        end
        if payload.kind == "medicalService" then
            self:confirmMedicalService(payload.data)
            return
        elseif payload.kind == "upgrade" then
            local sent = GodSystem.upgradeSystem(payload.data and payload.data.upgradeType)
            self:finishMultiplayerCommand(sent)
            return
        end
    end
    if self.mode == "waist" then
        local info = GodSystem.getAutoRecyclerInfo()
        if not info.found then
            local sent = GodSystem.claimOrRecoverAutoRecycler()
            self:finishMultiplayerCommand(sent)
            return
        end
        local selected = self.waistSelected or {}
        local hasSelected = false
        for _, value in pairs(selected) do
            if value == true then
                hasSelected = true
                break
            end
        end
        if not hasSelected then
            GodSystem.notify(GodSystem.text("Notify_SelectWaistItem", "Select space terminal items first"))
            return
        end
        self:prepareActionSelection(payload)
        local sent = GodSystem.recycleWaistSpaceItemsByMode(selected)
        self.waistSelected = {}
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "traits" then
        if not payload or payload.kind ~= "trait" then
            GodSystem.notify(GodSystem.text("Notify_SelectTrait", "Select a trait first"))
            return
        end
        self:confirmTraitModification(payload.data)
        return
    end
    if self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if not entry then
            GodSystem.notify(GodSystem.text("Notify_SelectOne", "Select an item first"))
            return
        end
        if entry.kind == "home" then
            self:confirmHomeAction("setHome")
        elseif entry.kind == "return" then
            self:confirmHomeAction("return")
        elseif entry.kind == "temp" then
            if not entry.owned then
                self:confirmHomeAction("buyTemp", entry.index)
            else
                self:confirmHomeAction("setTemp", entry.index)
            end
        elseif entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystem.getHomeSafeZoneInfo()
            if not info.homeSet then
                GodSystem.notify(GodSystem.text("HomeSafe_NeedHome", "Set a home first."))
            elseif not info.unlocked then
                self:confirmHomeAction("unlockSafeZone")
            else
                local sent = GodSystem.performHomeAction("toggleSafeZone")
                self:finishMultiplayerCommand(sent)
            end
        end
        return
    end
    if not payload then
        GodSystem.notify(GodSystem.text("Notify_SelectOne", "Select an item first"))
        return
    end
    if payload.kind == "shop" then
        self:prepareActionSelection(payload)
        local sent = GodSystem.buyShopItem(payload.data, 1)
        self:finishMultiplayerCommand(sent)
        return
    elseif payload.kind == "recycle" then
        self:recyclePayload(payload, 1)
        return
    elseif payload.kind == "task" then
        local task = payload.data
        if task.status == "open" then
            local sent = GodSystem.acceptTask(task)
            self:finishMultiplayerCommand(sent)
            return
        elseif task.status == "active" then
            if GodSystem.isTaskComplete(task) then
                local sent = GodSystem.claimTask(task)
                self:finishMultiplayerCommand(sent)
            else
                self:confirmAbandonTask(task)
            end
            return
        elseif task.status == "failed" then
            GodSystem.notify(GodSystem.text("Notify_TaskAlreadyFailed", "Task already failed"))
        elseif task.status == "claimed" then
            GodSystem.notify(GodSystem.text("Notify_RewardClaimed", "Reward already claimed"))
        end
    elseif payload.kind == "upgrade" then
        local sent = GodSystem.upgradeSystem(payload.data and payload.data.upgradeType)
        self:finishMultiplayerCommand(sent)
        return
    end
    self:populateList()
end

function GodSystemWindow:recyclePayload(payload, count)
    if not payload or payload.kind ~= "recycle" or not payload.data then
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    count = math.max(1, math.floor(count or 1))
    count = math.min(count, payload.data.count or count)
    self:prepareActionSelection(payload)
    local sent = GodSystem.recycleInventoryItems(payload.data.fullType, count)
    self:finishMultiplayerCommand(sent)
    return true
end

function GodSystemWindow:confirmListOnlyAutoShop(payload)
    if not payload or payload.kind ~= "recycle" or not payload.data then
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    local fullType = payload.data.fullType
    if not fullType then
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    local cost, buyPrice = GodSystem.getAutoShopListOnlyCost(fullType, payload.data.sellPrice or payload.data.valueEach or payload.data.value or 1)
    local message = gsFormatTemplate(GodSystem.text("Confirm_ListOnlyAutoShop", "List {1} in shop?\nFee: {2}\nShop price: {3}\nThe item will not be removed or sold."), {
        tostring(payload.data.label or payload.text or fullType),
        tostring(cost) .. GodSystem.text("Unit_CoinShort", "c"),
        tostring(buyPrice) .. GodSystem.text("Unit_CoinShort", "c"),
    })
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, message, true, self, self.onListOnlyAutoShopConfirm, playerNum, { payload = payload })
        modal:initialise()
        modal:addToUIManager()
    else
        self:onListOnlyAutoShopConfirm({ internal = "YES" }, { payload = payload })
    end
    return true
end

function GodSystemWindow:onListOnlyAutoShopConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local row = payload and payload.payload
    if not row or not row.data then
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return
    end
    self:prepareActionSelection(row)
    local sent = GodSystem.listOnlyAutoShopItem(row.data.fullType)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:buyShopPayload(payload, count)
    if not payload or payload.kind ~= "shop" or not payload.data then
        GodSystem.notify(GodSystem.text("Notify_SelectOne", "Select an item first"))
        return false
    end
    self:prepareActionSelection(payload)
    local sent = GodSystem.buyShopItem(payload.data, count or 1)
    self:finishMultiplayerCommand(sent)
    return true
end

function GodSystemWindow:onListRightMouseUp(x, y)
    if self.mode ~= "recycle" and self.mode ~= "shop" then
        return false
    end
    local payload = self:selectListRowAt(x, y, self.list, self.mode == "tasks" and "open" or nil)
    if not payload or not payload.data then
        return false
    end

    if self.mode == "shop" then
        if payload.kind ~= "shop" then
            return false
        end
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
        context:addOption(GodSystem.text("Menu_BuyOne", "Buy 1"), self, self.buyShopPayload, payload, 1)
        context:addOption(GodSystem.text("Menu_BuyTen", "Buy 10"), self, self.buyShopPayload, payload, 10)
        context:addOption(GodSystem.text("Menu_BuyFifty", "Buy 50"), self, self.buyShopPayload, payload, 50)
        return true
    end

    if payload.kind ~= "recycle" then
        return false
    end
    local count = payload.data.count or 0
    if count <= 0 then
        return false
    end

    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(GodSystem.text("Menu_SellOne", "Sell 1"), self, self.recyclePayload, payload, 1)

    local half = math.floor(count / 2)
    if half > 0 then
        context:addOption(GodSystem.text("Menu_SellHalf", "Sell half") .. " (" .. tostring(half) .. ")", self, self.recyclePayload, payload, half)
    end
    context:addOption(GodSystem.text("Menu_SellAll", "Sell all") .. " (" .. tostring(count) .. ")", self, self.recyclePayload, payload, count)
    context:addOption(GodSystem.text("Menu_ListOnly", "List only"), self, self.confirmListOnlyAutoShop, payload)
    return true
end

function GodSystemWindow:onSecondaryAction()
    if self.mode == "attribute" then
        self:showAttributeNextLevelConfirm(self:getSelectedPayload())
        return
    end
    if self.mode == "companion" then
        if GodSystemCompanion and GodSystemCompanion.toggleVisible then GodSystemCompanion.toggleVisible() end
        self:populateList()
        return
    end
    if self.mode == "admin" then
        if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.send then
            self:finishMultiplayerCommand(GodSystemNetwork.send("adminConfigGet", {}))
        else
            self:populateList()
        end
        return
    end
    if self.mode == "bank" then
        local payload = self:getSelectedPayload()
        if payload and payload.kind == "bankLoanActive" then
            local sent = GodSystem.performBankAction("payoffLoan", 1)
            self:finishMultiplayerCommand(sent)
            return
        elseif payload and payload.kind == "bankInvestment" then
            local profile = payload.profile or {}
            self:showBankAmountDialog("investFromCash", GodSystem.text("Bank_InvestCashPrompt", "Enter carried cash amount to invest"), profile.id)
            return
        end
        self:showBankAmountDialog("withdraw", GodSystem.text("Bank_WithdrawPrompt", "Withdraw current account to cash"))
        return
    elseif self.mode == "lottery" then
        self:performLottery(10)
        return
    elseif self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if entry and entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystem.getHomeSafeZoneInfo()
            if info.unlocked then
                self:confirmHomeAction("clearSafeZone")
            else
                GodSystem.notify(GodSystem.text("HomeSafe_Locked", "Locked"))
            end
        elseif entry and entry.kind == "return" then
            self:confirmHomeAction("clearReturn")
        elseif entry and entry.kind == "home" and entry.point then
            self:confirmHomeAction("teleportHome")
        elseif entry and entry.kind == "temp" and entry.owned and entry.point then
            self:confirmHomeAction("teleportTemp", entry.index)
        else
            if self:requestServerRefresh() then
                return
            end
            self:populateList()
        end
    elseif self.mode == "shop" or self.mode == "recycle" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "waist" then
        local info = GodSystem.getAutoRecyclerInfo()
        local sent = true
        if info.found then
            sent = GodSystem.recycleWaistSpaceItemsByMode(nil)
        end
        self.waistSelected = {}
        self:finishMultiplayerCommand(sent)
    elseif self.mode == "traits" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "upgrades" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "tasks" then
        local sent = GodSystem.refreshOpenTasks()
        self:finishMultiplayerCommand(sent)
    elseif self.mode == "diagnostics" then
        if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.requestDiagnostics then
            local sent = GodSystemNetwork.requestDiagnostics()
            self:finishMultiplayerCommand(sent)
        else
            self:populateList()
        end
    elseif self.mode == "info" and GodSystemConfig.EnableDebugTools then
        local sent = GodSystem.debugAddPoints()
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onThirdAction()
    local payload = self:getSelectedPayload()
    if self.mode == "companion" then
        if GodSystemCompanionUI and GodSystemCompanionUI.toggleShortcut then GodSystemCompanionUI.toggleShortcut(self) end
        self:populateList()
        return
    end
    if self.mode == "admin" then
        if payload and payload.kind == "adminItemOverride" and payload.fullType then
            local sent = GodSystem.clearItemOverride(payload.fullType)
            self:finishMultiplayerCommand(sent)
            self:requestDeferredPopulate(2)
            return
        elseif payload and payload.kind == "adminSetting" then
            local snapshot = GodSystem.getAdminConfigSnapshot()
            local settings = {}
            for key, value in pairs(snapshot.settings or {}) do settings[key] = value end
            local meta = payload.data or {}
            settings[meta.key] = meta.default
            local sent = GodSystem.saveAdminSettings(settings)
            self:finishMultiplayerCommand(sent)
            self:requestDeferredPopulate(2)
            return
        end
        GodSystem.notify(GodSystem.text("Admin_SelectItemOrSetting", "Select an item override or setting"))
        return
    end
    if self.mode == "bank" then
        if not payload or payload.kind ~= "bankInvestment" then
            GodSystem.notify(GodSystem.text("Notify_BankInvestmentSelect", "Select an investment account"))
            return
        end
        local profile = payload.profile or {}
        self:showBankAmountDialog("redeemInvestment", GodSystem.text("Bank_RedeemInvestmentPrompt", "Enter amount to redeem to current account"), profile.id)
        return
    end
    if self.mode == "lottery" then
        self:performLottery(self:getLotteryCustomCount())
        return
    end
    if self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if entry and entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystem.getHomeSafeZoneInfo()
            if info.nextLevel then
                self:confirmHomeAction("upgradeSafeZone")
            else
                GodSystem.notify(GodSystem.text("Notify_HomeSafeMaxLevel", "Home safe zone is already at max level"))
            end
        else
            local home = GodSystem.getHomeSystem()
            if home and home.returnPoint then
                self:confirmHomeAction("return")
            else
                GodSystem.notify(GodSystem.text("Notify_HomeNoReturn", "No return point"))
            end
        end
        return
    end
    if self.mode == "waist" then
        local sent = GodSystem.upgradeAutoRecycler()
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "shop" then
        if not payload or payload.kind ~= "shop" or not payload.data or payload.data.unlocked ~= true then
            GodSystem.notify(GodSystem.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
            return
        end
        local fullType = payload.data.fullType
        if not fullType and payload.data.items and payload.data.items[1] then
            fullType = payload.data.items[1].fullType
        end
        local sent = GodSystem.removeUnlockedShopItem(fullType)
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "tasks" then
        GodSystemUI.toggleTaskTracker()
        self:populateList()
        return
    end
    if self.mode ~= "recycle" or not payload or payload.kind ~= "recycle" then
        if self.mode == "recycle" then
            local sent = GodSystem.toggleRecycleUnlockMode()
            self:finishMultiplayerCommand(sent)
            return
        end
        GodSystem.notify(GodSystem.text("Notify_SelectRecycle", "Select a recyclable item"))
        return
    end
    local sent = GodSystem.toggleRecycleUnlockMode()
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:onFourthAction()
    if self.mode == "companion" then
        if GodSystemCompanion and GodSystemCompanion.recall then GodSystemCompanion.recall() end
        self:populateList()
        return
    end
    if self.mode == "shop" then
        self:changeShopPage(-1)
        return
    end
    if self.mode == "bank" then
        local sent = GodSystem.performBankAction("toggleAutoDeposit")
        self:finishMultiplayerCommand(sent)
        if not gsIsMultiplayer() then self:populateList() end
        return
    end
    if self.mode == "tasks" then
        local sent = GodSystem.toggleAutoTaskClaim()
        self:finishMultiplayerCommand(sent)
        if not gsIsMultiplayer() then self:populateList() end
        return
    end
    if self.mode == "waist" then
        local sent = GodSystem.toggleWaistAutoRecycle()
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "home" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
        return
    end
    self:populateList()
end

function GodSystemWindow:onFifthAction()
    if self.mode == "bank" then
        local sent = GodSystem.consolidateCurrency()
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "shop" then
        self:changeShopPage(1)
        return
    end
    if self.mode == "waist" then
        local sent = GodSystem.toggleWaistRecycleUnlockMode()
        self:finishMultiplayerCommand(sent)
        return
    end
    self:populateList()
end

function GodSystemWindow:close()
    local data = GodSystem.getData()
    data.ui.windowX = math.floor(self.x or 0)
    data.ui.windowY = math.floor(self.y or 0)
    data.ui.windowScale = self:getUIScale()
    GodSystem.save()
    ISCollapsableWindow.close(self)
    GodSystemUI.window = nil
end

function GodSystemUI.toggleWindow()
    if GodSystemUI.window then
        GodSystemUI.window:close()
        GodSystemUI.window = nil
        return
    end
    local data = GodSystem.getData()
    if GodSystemNetwork and GodSystemNetwork.requestState then
        GodSystemNetwork.requestState(true)
    end
    local win = (gsTheme().window or {})
    local baseW = win.baseWidth or win.fixedWidth or win.defaultWidth or 1240
    local baseH = win.baseHeight or win.fixedHeight or win.defaultHeight or 690
    local minScale = win.scaleMin or 0.75
    local maxScale = win.scaleMax or 1.15
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
    if GodSystemUI.shortcutWindow and GodSystemUI.shortcutWindow.getIsVisible and GodSystemUI.shortcutWindow:getIsVisible() then
        GodSystemUI.shortcutWindow:close()
        return false
    end
    local data = GodSystem.getData()
    local w, h = 280, 218
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.floor(tonumber(data.ui.shortcutX) or ((owner and owner.x or (screenW / 2)) + 40))
    local y = math.floor(tonumber(data.ui.shortcutY) or ((owner and owner.y or (screenH / 2)) + 60))
    x = gsClamp(x, 0, math.max(0, screenW - w))
    y = gsClamp(y, 0, math.max(0, screenH - h))
    local window = GodSystemShortcutWindow:new(x, y, w, h)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    GodSystemUI.shortcutWindow = window
    return true
end

function GodSystemUI.isTaskTrackerVisible()
    return GodSystemUI.taskTracker ~= nil and GodSystemUI.taskTracker:getIsVisible() == true
end

function GodSystemUI.createTaskTracker()
    if GodSystemUI.taskTracker then
        local data = GodSystem.getData()
        local w = math.max(260, math.floor(tonumber(data.ui.taskTrackerW) or GodSystemUI.taskTracker.width or 340))
        local h = math.max(70, math.floor(tonumber(data.ui.taskTrackerH) or GodSystemUI.taskTracker.height or 92))
        gsSetBounds(GodSystemUI.taskTracker, nil, nil, w, h)
        GodSystemUI.taskTracker:setVisible(true)
        return GodSystemUI.taskTracker
    end
    local data = GodSystem.getData()
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
    local data = GodSystem.getData()
    if GodSystemUI.isTaskTrackerVisible() then
        GodSystemUI.taskTracker:close()
        GodSystem.notify(GodSystem.text("Notify_TaskTrackerOff", "Task tracker hidden"))
        return false
    end
    GodSystemUI.createTaskTracker()
    data.ui.taskTrackerVisible = true
    GodSystem.save()
    GodSystem.notify(GodSystem.text("Notify_TaskTrackerOn", "Task tracker shown"))
    return true
end

function GodSystemUI.createFloatingButton()
    if GodSystemUI.floating then
        return
    end
    local data = GodSystem.getData()
    local cfg = GodSystemConfig.FloatingButton
    local button = GodSystemFloatingButton:new(data.ui.x or cfg.x, data.ui.y or cfg.y, cfg.width, cfg.height)
    button:initialise()
    button:addToUIManager()
    button:setVisible(true)
    GodSystemUI.floating = button
end

function GodSystemUI.onGameStart()
    GodSystemUI.createFloatingButton()
    local data = GodSystem.getData()
    if data.ui.taskTrackerVisible == true then
        GodSystemUI.createTaskTracker()
    end
end

if Events.OnGameStart then
    Events.OnGameStart.Add(GodSystemUI.onGameStart)
end
