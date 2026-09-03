_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Window"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Window then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Window = true
    setfenv(1, runtimeEnvironment)

function gsIsSelectablePayload(payload)
    return payload ~= nil and payload.selectable ~= false and GS_NON_SELECTABLE_KINDS[payload.kind] ~= true
end

function GodSystemWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    local win = (gsTheme().window or {})
    o.title = GodSystemApp.services.runtime.text("Title", "God System") .. " v" .. tostring(GodSystemConfig.Version)
    o.mode = "tasks"
    o.selectedTaskList = "open"
    o.pageSections = {
        tasks = PageSections.new("tasks"),
    }
    o.shopSearchText = ""
    o.recycleSearchText = ""
    o.attributeSearchText = ""
    o.shopSearchPurpose = "shop"
    o.taskInfoExpanded = true
    o.moreInfoExpanded = false
    o.lastSelectableListRow = 0
    o.lastSelectableActiveRow = 0
    o.pendingRestoreSelectedId = nil
    o.pendingRestoreSelectedTaskList = nil
    o.pendingRestoreMode = nil
    o.pendingRestoreScroll = nil
    o.resizable = false
    o.resizeAspect = (win.baseWidth or win.fixedWidth or 1240) / math.max(1, (win.baseHeight or win.fixedHeight or 690))
    o.minimumScale = win.scaleMin or 0.60
    o.maximumScale = win.scaleMax or 1.50
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
    local minScale = self.minimumScale or ((gsTheme().window or {}).scaleMin) or 0.60
    local maxScale = self.maximumScale or ((gsTheme().window or {}).scaleMax) or 1.50
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
    self.navGroupH = self:S(win.navGroupHeight or 22)
    self.navMoreHeaderH = self:S(win.navMoreHeaderHeight or 38)
    self.navPadding = self:S(win.navPadding or 8)
    self.navListX = self.navX + self.navPadding
    self.navListY = self.navY
    self.navListW = math.max(self:S(80), self.navW - (self.navPadding * 2))
    self.navListH = math.max(self.navItemH, self.navH)
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

function GodSystemWindow:isNavigationTabVisible(tab)
    return tab ~= nil and (tab.id ~= "itemConfig" or GodSystemApp.services.runtime.isItemConfigAllowed() == true)
end

function GodSystemWindow:navigationTabById(id)
    for _, tab in ipairs(self.navigationTabs or {}) do
        if tab.id == id then return tab end
    end
    for _, tab in ipairs(self.moreNavigationTabs or {}) do
        if tab.id == id then return tab end
    end
    return nil
end

function GodSystemWindow:addNavigationRow(text, payload, height)
    local list = self.navigationList
    if not list then return end
    local row = list:addItem(text, payload)
    row.height = math.max(1, math.floor(tonumber(height) or list.itemheight or 1))
    return row
end

function GodSystemWindow:layoutNavigation(preserveScroll)
    local list = self.navigationList
    if not list then return end
    local scrollY = preserveScroll ~= false and (tonumber(list:getYScroll()) or 0) or 0
    list:clear()
    list.selected = 0
    list:setScrollHeight(0)
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
    local contentH = 0
    local function add(text, payload, height)
        self:addNavigationRow(text, payload, height)
        contentH = contentH + height
    end
    local lastGroup = nil
    for _, tab in ipairs(self.navigationTabs or {}) do
        if self:isNavigationTabVisible(tab) then
            local group = tab.group or "core"
            if group ~= lastGroup then
                add((self.navigationGroupLabels or {})[group] or group, { kind = "navGroup", selectable = false }, self.navGroupH)
                lastGroup = group
            end
            if tab.sections then
                add((self.taskInfoExpanded and "v " or "> ") .. tab.label, {
                    kind = "navTask",
                    id = tab.id,
                    label = tab.label,
                    selectable = false,
                }, self.navMoreHeaderH)
                contentH = contentH + self.navItemGap
                if self.taskInfoExpanded == true then
                    for _, section in ipairs(tab.sections) do
                        add("  " .. section.label, {
                            kind = "navTaskSection",
                            id = tab.id,
                            sectionId = section.id,
                            label = section.label,
                            tool = true,
                        }, self.navToolH)
                        contentH = contentH + self.navItemGap
                    end
                end
            else
                add(tab.label, { kind = "navTab", id = tab.id, label = tab.label }, self.navItemH)
                contentH = contentH + self.navItemGap
            end
        end
    end
    contentH = contentH + self.navItemGap
    local moreLabel = GodSystemApp.services.runtime.text("Nav_MoreInfo", "More information")
    add((self.moreInfoExpanded and "v " or "> ") .. moreLabel, { kind = "navMore", selectable = false }, self.navMoreHeaderH)
    contentH = contentH + self.navItemGap
    if self.moreInfoExpanded == true then
        for _, tab in ipairs(self.moreNavigationTabs or {}) do
            if self:isNavigationTabVisible(tab) then
                add("  " .. tab.label, { kind = "navTab", id = tab.id, label = tab.label, tool = true }, self.navToolH)
                contentH = contentH + self.navItemGap
            end
        end
    end
    list:setScrollHeight(math.max(list.height or 1, contentH + self.navPadding))
    local overflow = math.max(0, (list:getScrollHeight() or 0) - (list.height or 1))
    list:setYScroll(gsClamp(scrollY, -overflow, 0))
    if self.navigationList.vscroll then
        self.navigationList.vscroll:refresh()
        self.navigationList.vscroll:updatePos()
    end
end

function GodSystemWindow:drawNavigationItem(list, y, row, alt)
    local data = row and row.item or {}
    local h = row and row.height or list.itemheight
    if data.kind == "navGroup" then
        gsDrawRect(list, 0, y, list.width, h - 1, gsThemeColor("panelDeep"))
        gsDrawText(list, tostring(row.text or ""), self:S(8), y + math.max(self:S(3), math.floor((h - self:S(16)) / 2)), gsThemeColor("dimText"), UIFont.Small)
    else
        local active = (data.kind == "navTab" and data.id == self.mode)
            or (data.kind == "navTaskSection" and self.mode == "tasks"
                and data.sectionId == self:getActivePageSection("tasks"))
        gsDrawRect(list, 0, y, list.width, h - 1, active and gsThemeColor("rowSelect") or (alt and gsThemeColor("rowAlt") or gsThemeColor("row")))
        gsDrawRectBorder(list, 0, y, list.width, h - 1, active and gsThemeColor("borderStrong") or gsThemeColor("border"))
        local accordionHeader = data.kind == "navMore" or data.kind == "navTask"
        local color = active and gsThemeColor("text") or (accordionHeader and gsThemeColor("gold") or gsThemeColor("text"))
        gsDrawText(list, gsTruncateText(tostring(row.text or ""), data.tool and UIFont.Small or UIFont.Medium, list.width - self:S(18)), self:S(10), y + math.max(self:S(5), math.floor((h - self:S(18)) / 2)), color, data.tool and UIFont.Small or UIFont.Medium)
    end
    return y + h
end

function GodSystemWindow:onNavigationListMouseDown(row)
    local data = row and (row.item or row) or nil
    if not data then return end
    if data.kind == "navTask" then
        self.taskInfoExpanded = self.taskInfoExpanded ~= true
        self:layoutNavigation(true)
        return
    end
    if data.kind == "navMore" then
        self.moreInfoExpanded = self.moreInfoExpanded ~= true
        self:layoutNavigation(true)
        return
    end
    if data.kind == "navTaskSection" then
        self:selectTaskNavigationSection(data.sectionId, data.label)
        return
    end
    if data.kind == "navTab" then
        self:onModeButton({ internal = data.id, modeLabel = data.label })
    end
end

function GodSystemWindow:selectTaskNavigationSection(sectionId, label)
    sectionId = tostring(sectionId or "tasks")
    if self.mode == "tasks" then
        self:selectPageSection(sectionId)
        self:updateModeButtonStyles()
        return
    end
    PageSections.select(self:getPageSections("tasks"), sectionId)
    self:onModeButton({ internal = "tasks", modeLabel = label })
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
        if self.navigationList and self.navigationList:onMouseWheel(tonumber(del) or 0) then
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
        self:relayoutVisiblePage()
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
        local data = GodSystemApp.services.runtime.getData()
        data.ui.windowX = math.floor(self.x or 0)
        data.ui.windowY = math.floor(self.y or 0)
        data.ui.windowScale = self:getUIScale()
        GodSystemApp.services.runtime.save()
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
        gsSetLabel(self.navTitleLabel, gsTruncateText(GodSystemApp.services.runtime.text("Title", "God System"), UIFont.Large, self:S(210)))
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
    if self.navigationList then
        gsSetBounds(self.navigationList, self.navListX, self.navListY, self.navListW, self.navListH)
        self:layoutNavigation(true)
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

    self.navTitleLabel = ISLabel:new(self.topX + 78, self.topY + 19, 28, GodSystemApp.services.runtime.text("Title", "God System"), 0.86, 0.84, 0.76, 1, UIFont.Large, true)
    self.navTitleLabel:initialise()
    self.navTitleLabel:setVisible(false)
    self:addChild(self.navTitleLabel)

    self.pointsLabel = ISLabel:new(self.topX + 320, self.topY + 18, 18, GodSystemApp.services.runtime.text("CurrencyLabel", "Currency: ") .. "0", 1, 0.68, 0.2, 1, UIFont.Small, true)
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

    self.navigationList = ISScrollingListBox:new(self.navListX, self.navListY, self.navListW, self.navListH)
    self.navigationList:initialise()
    self.navigationList:instantiate()
    self.navigationList.itemheight = self.navItemH
    self.navigationList.doDrawItem = function(list, y, row, alt) return self:drawNavigationItem(list, y, row, alt) end
    self.navigationList:setOnMouseDownFunction(self, self.onNavigationListMouseDown)
    gsInstallSafeScrollingListPrerender(self.navigationList)
    self:addChild(self.navigationList)

    self.taskNavigationSections = {
        { id = "tasks", label = GodSystemApp.services.runtime.text("Section_Tasks", "Task board") },
        { id = "taskExtensions", label = GodSystemApp.services.runtime.text("Section_TaskExtensions", "Task upgrades") },
    }
    local tabs = {
        { id = "tasks", label = GodSystemApp.services.runtime.text("Tab_Tasks", "Tasks"), group = "core", sections = self.taskNavigationSections },
        { id = "shop", label = GodSystemApp.services.runtime.text("Tab_Shop", "Shop"), group = "core" },
        { id = "rangeRecycle", label = GodSystemApp.services.runtime.text("Tab_RangeRecycle", "Range recycle"), group = "core" },
        { id = "bank", label = GodSystemApp.services.runtime.text("Tab_Bank", "Bank"), group = "core" },
        { id = "home", label = GodSystemApp.services.runtime.text("Tab_Home", "Home/Teleport"), group = "systems" },
        { id = "traits", label = GodSystemApp.services.runtime.text("Tab_Traits", "Traits"), group = "systems" },
        { id = "upgrades", label = GodSystemApp.services.runtime.text("Tab_Upgrades", "Upgrades"), group = "systems" },
    }
    local attributesEnabled = GodSystemApp.services.runtime.isFeatureEnabled("EnableAttributes")
    if attributesEnabled then
        table.insert(tabs, 8, { id = "attribute", label = GodSystemApp.services.runtime.text("Tab_Attributes", "Attributes"), group = "systems" })
    end
    if not gsIsMultiplayer() and GodSystemCompanionConfig.isEnabled() then
        -- Append to the dense array. A sparse insertion makes ipairs stop before
        -- the companion row, which hid it in SP whenever attributes were enabled.
        tabs[#tabs + 1] = { id = "companion", label = GodSystemApp.services.runtime.text("Tab_Companion", "Companion"), group = "systems" }
    end
    self.navigationTabs = tabs
    self.moreNavigationTabs = {
        { id = "shortcuts", label = GodSystemApp.services.runtime.text("Btn_Shortcuts", "Shortcuts"), group = "more" },
        { id = "settings", label = GodSystemApp.services.runtime.text("Tab_Keys", "Keys"), group = "more" },
        { id = "history", label = GodSystemApp.services.runtime.text("Tab_History", "History"), group = "more" },
        { id = "info", label = GodSystemApp.services.runtime.text("Tab_Info", "Info"), group = "more" },
        { id = "itemConfig", label = GodSystemApp.services.runtime.text("Tab_ItemConfig", "Item config"), group = "more" },
        { id = "diagnostics", label = GodSystemApp.services.runtime.text("Tab_Diagnostics", "Diagnostics"), group = "more" },
    }
    self.navigationGroupLabels = {
        core = GodSystemApp.services.runtime.text("Nav_Group_Core", "CORE"),
        systems = GodSystemApp.services.runtime.text("Nav_Group_Systems", "SYSTEMS"),
    }
    self.shopCategoryKey = "all"
    self.shopCategories = {}

    self.shopSearchLabel = ISLabel:new(self.mainX + self:S(168), self.actionY + self:S(18), 18, GodSystemApp.services.runtime.text("Search_Label", "Search"), 0.78, 0.78, 0.78, 1, UIFont.Small, true)
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

    self.detailHeaderLabel = ISLabel:new(self.detailX + self:S(12), self.contentY + self:S(10), 18, GodSystemApp.services.runtime.text("Panel_Detail", "Detail"), 1, 0.68, 0.2, 1, UIFont.Small, true)
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

    self.openTaskLabel = ISLabel:new(self.mainX, self.mainY - self:S(26), 18, GodSystemApp.services.runtime.text("Task_OpenColumn", "Available"), 0.95, 0.68, 0.22, 1, UIFont.Small, true)
    self.openTaskLabel:initialise()
    self.openTaskLabel:setVisible(false)
    self:addChild(self.openTaskLabel)

    self.activeTaskLabel = ISLabel:new(self.mainX + self:S(210), self.mainY - self:S(26), 18, GodSystemApp.services.runtime.text("Task_ActiveColumn", "Active"), 0.95, 0.68, 0.22, 1, UIFont.Small, true)
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

    self.primaryButton = ISButton:new(self.actionX, self.actionY + self:S(8), self:S(142), self.actionButtonH or self:S(38), GodSystemApp.services.runtime.text("Btn_Buy", "Buy"), self, self.onPrimaryAction)
    self.primaryButton:initialise()
    gsStyleActionButton(self.primaryButton, "primary")
    self:addChild(self.primaryButton)

    self.secondaryButton = ISButton:new(self.actionX + self:S(156), self.actionY + self:S(8), self:S(156), self.actionButtonH or self:S(38), GodSystemApp.services.runtime.text("Btn_Refresh", "Refresh"), self, self.onSecondaryAction)
    self.secondaryButton:initialise()
    gsStyleActionButton(self.secondaryButton, false)
    self:addChild(self.secondaryButton)

    self.thirdButton = ISButton:new(self.actionX + self:S(326), self.actionY + self:S(8), self:S(156), self.actionButtonH or self:S(38), GodSystemApp.services.runtime.text("Btn_RecycleBatch", "Batch recycle"), self, self.onThirdAction)
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

    self.sixthButton = ISButton:new(self.actionX + self:S(776), self.actionY + self:S(8), self:S(126), self.actionButtonH or self:S(38), "", self, self.onSixthAction)
    self.sixthButton:initialise()
    gsStyleActionButton(self.sixthButton, false)
    self.sixthButton:setVisible(false)
    self:addChild(self.sixthButton)

    self.seventhButton = ISButton:new(self.actionX + self:S(916), self.actionY + self:S(8), self:S(126), self.actionButtonH or self:S(38), "", self, self.onSeventhAction)
    self.seventhButton:initialise()
    gsStyleActionButton(self.seventhButton, false)
    self.seventhButton:setVisible(false)
    self:addChild(self.seventhButton)

    self.categoryButton = ISButton:new(self.mainX, self.actionY + self:S(12), self:S(158), self:S(30), GodSystemApp.services.runtime.text("ShopCategory_ButtonAll", "Category: All"), self, self.onCategoryButton)
    self.categoryButton:initialise()
    gsStyleActionButton(self.categoryButton, false)
    self.categoryButton:setVisible(false)
    self:addChild(self.categoryButton)

    self.sectionButtons = {}
    for i = 1, 3 do
        local button = ISButton:new(self.contentX + self:S(220), self.contentY + self:S(8), self:S(96), self:S(28), "", self, self.onPageSectionButton)
        button:initialise()
        gsStyleButton(button, false)
        button:setVisible(false)
        self:addChild(button)
        self.sectionButtons[i] = button
    end

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
    if GodSystemApp.services.runtime.getPlayerLoadText then
        return GodSystemApp.services.runtime.getPlayerLoadText()
    end
    return "-"
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
    local data = GodSystemApp.services.runtime.getData()
    local stats = data.stats or {}
    local bankSummary = GodSystemApp.services.runtime.getBankSummary and GodSystemApp.services.runtime.getBankSummary() or {}
    local currency = GodSystemApp.services.runtime.getCurrencyDisplayTotal and GodSystemApp.services.runtime.getCurrencyDisplayTotal() or (GodSystemApp.services.runtime.getCurrencyTotal and GodSystemApp.services.runtime.getCurrencyTotal() or 0)
    local completed = stats.completedTasks or 0
    local failed = stats.failedTasks or 0

    self:drawFramePanel(self.topX, self.topY, self.topW, self.topH, gsThemeColor("topBar"), gsThemeColor("borderStrong"))
    gsDrawRect(self, self.topX + self:S(18), self.topY + self:S(10), self:S(48), self:S(48), gsThemeColor("panelWarm"))
    gsDrawRectBorder(self, self.topX + self:S(18), self.topY + self:S(10), self:S(48), self:S(48), gsThemeColor("borderStrong"))
    gsDrawTextCentre(self, "GS", self.topX + self:S(18), self.topY + self:S(23), self:S(48), 1, 0.68, 0.2, 1, UIFont.Medium)

    gsDrawText(self, GodSystemApp.services.runtime.text("Title", "God System"), self.topX + self:S(78), self.topY + self:S(16), gsThemeColor("text"), UIFont.Large)
    gsDrawText(self, "v" .. tostring(GodSystemConfig.Version or "?"), self.topX + self:S(78), self.topY + self:S(44), gsThemeColor("dimText"), UIFont.Small)

    local startX = self.topX + self:S(270)
    local cellW = self:S(108)
    self:drawTopStatusCell(GodSystemApp.services.runtime.text("CurrencyLabel", "Currency"), gsFormatCompactNumber(currency), startX, self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystemApp.services.runtime.text("Tab_Bank", "Bank"), gsFormatCompactNumber(bankSummary.current or 0), startX + self:S(116), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystemApp.services.runtime.text("Task_ActiveColumn", "Active"), tostring(activeCount or 0) .. "/" .. tostring(GodSystemApp.services.runtime.getMaxActiveTasks()), startX + self:S(232), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystemApp.services.runtime.text("Stats_Completed", "Done"), tostring(completed), startX + self:S(348), self.topY + self:S(12), cellW)
    self:drawTopStatusCell(GodSystemApp.services.runtime.text("Stats_Failed", "Failed"), tostring(failed), startX + self:S(464), self.topY + self:S(12), cellW)
    self:drawTopStatusCell("Load", self:getPlayerLoadText(), startX + self:S(580), self.topY + self:S(12), cellW)
    self:drawTopStatusCell("Time", self:getGameTimeText(), startX + self:S(696), self.topY + self:S(12), self:S(132))
end

function GodSystemWindow:prerender()
    self:relayoutIfNeeded(false)
    ISCollapsableWindow.prerender(self)
    local data = GodSystemApp.services.runtime.getData()
    gsSetLabel(self.pointsLabel, "")
    local stats = data.stats or {}
    local statsText = GodSystemApp.services.runtime.text("Stats_Completed", "Completed ") .. tostring(stats.completedTasks or 0) .. " | " .. GodSystemApp.services.runtime.text("Stats_Failed", "Failed ") .. tostring(stats.failedTasks or 0) .. " | " .. GodSystemApp.services.runtime.text("Stats_Daily", "Daily ") .. tostring(GodSystemApp.services.runtime.getDailyTaskCount())
    if (GodSystemConfig.DailyRecycleSoftCap or 0) > 0 then
        statsText = statsText .. " | " .. GodSystemApp.services.runtime.text("Stats_RecycleRemain", "Recycle left ") .. tostring(GodSystemApp.services.runtime.getRecycleDailyRemaining())
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
    if GodSystemPanelKey.isCapturing() then
        GodSystemPanelKey.cancelCapture("pageChanged")
    end
    if button and button.internal == "shortcuts" then
        if GodSystemUI.toggleShortcutWindow then
            GodSystemUI.toggleShortcutWindow(self)
        end
        return
    end
    if button and button.internal == "itemConfig" then
        if GodSystemApp.services.runtime.isItemConfigAllowed() == true then
            GodSystemItemEconomyUI.open(self)
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
    GodSystemUI.presentOverlay(dialog)
    GodSystemUI.secretGrantDialog = dialog
end

function GodSystemWindow:updateModeButtonStyles()
    self:layoutNavigation(true)
    local tab = self:navigationTabById(self.mode)
    if self.pageTitleLabel and tab then
        local label = tab.label or ""
        if self.mode == "tasks" then
            local sectionId = self:getActivePageSection("tasks")
            for _, section in ipairs(self.taskNavigationSections or {}) do
                if section.id == sectionId then label = section.label; break end
            end
        end
        gsSetLabel(self.pageTitleLabel, label)
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
        local progress = math.min(GodSystemApp.services.runtime.getTaskDisplayProgress(task), target)
        local status = GodSystemApp.services.runtime.getTaskStatusText(task)
        local titleWidth = math.max(self:S(80), list.width - self:S(22))
        local title = gsTruncateText(GodSystemApp.services.runtime.getTaskListTitle(task), UIFont.Small, titleWidth)
        local line = gsTruncateText(GodSystemApp.services.runtime.getTaskListStatusLine(task), UIFont.Small, titleWidth)
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

function GodSystemWindow:getPageSections(mode)
    mode = tostring(mode or self.mode or "")
    self.pageSections = self.pageSections or {}
    if (mode == "tasks") and not self.pageSections[mode] then
        self.pageSections[mode] = PageSections.new("tasks")
    end
    return self.pageSections[mode]
end

function GodSystemWindow:getActivePageSection(mode)
    return PageSections.active(self:getPageSections(mode))
end

function GodSystemWindow:capturePageSectionState(mode)
    local sections = self:getPageSections(mode)
    if not sections or not ListState then return end
    local sectionId = PageSections.active(sections)
    PageSections.capture(sections, sectionId, {
        main = self:captureListState(self.list, "main"),
        active = self:captureListState(self.activeList, "active"),
        detail = self:captureListState(self.detailList, "detail"),
        selectedTaskList = self.selectedTaskList,
    })
end

function GodSystemWindow:restorePageSectionState(mode)
    local sections = self:getPageSections(mode)
    local state = PageSections.restore(sections)
    if not state or not ListState then return false end
    if mode == "tasks" and state.selectedTaskList then
        self.selectedTaskList = state.selectedTaskList
    end
    local function restore(list, snapshot, listName, idFn)
        if not list or not snapshot then return false end
        local context = self:listStateContext(listName)
        local restored = ListState.restore(list, snapshot, context, idFn)
        if restored then ListState.restoreNextTick(list, snapshot, context, idFn) end
        return restored
    end
    local restored = restore(self.list, state.main, "main", function(payload) return self:getPayloadId(payload) end)
    restored = restore(self.activeList, state.active, "active", function(payload) return self:getPayloadId(payload) end) or restored
    restored = restore(self.detailList, state.detail, "detail", function(payload, row, index)
        return payload and payload.detailKey or (row and row.text and ("detail:" .. tostring(index)))
    end) or restored
    return restored
end

function GodSystemWindow:showPageSections(mode, definitions)
    local sections = self:getPageSections(mode)
    if not self.sectionButtons then return end
    local activeId = PageSections.active(sections)
    for i = 1, #self.sectionButtons do
        local button = self.sectionButtons[i]
        local definition = definitions and definitions[i] or nil
        button.sectionMode = mode
        button.sectionId = definition and definition.id or nil
        button.sectionLabel = definition and definition.label or ""
        button:setVisible(definition ~= nil)
        if definition then
            gsSetButtonTitle(button, definition.label)
            gsStyleButton(button, activeId == definition.id)
        end
    end
end

function GodSystemWindow:hidePageSections()
    for i = 1, #(self.sectionButtons or {}) do
        self.sectionButtons[i]:setVisible(false)
    end
end

function GodSystemWindow:onPageSectionButton(button)
    if not button or button.sectionMode ~= self.mode or not button.sectionId then return end
    self:selectPageSection(button.sectionId)
end

function GodSystemWindow:selectPageSection(id)
    local mode = self.mode
    local sections = self:getPageSections(mode)
    if not sections or tostring(id or "") == PageSections.active(sections) then return false end
    self:capturePageSectionState(mode)
    if not PageSections.select(sections, id) then return false end
    self:populateList()
    self:requestDeferredPopulate(1)
    return true
end

function GodSystemWindow:listStateContext(listName)
    listName = tostring(listName or "main")
    local parts = { "mode=" .. tostring(self.mode or ""), "list=" .. listName }
    if self.mode == "shop" then
        parts[#parts + 1] = "category=" .. tostring(self.shopCategoryKey or "all")
        parts[#parts + 1] = "search=" .. tostring(self.shopSearchText or "")
        parts[#parts + 1] = "page=" .. tostring(self.shopPage or 1)
    elseif self.mode == "recycle" then
        parts[#parts + 1] = "search=" .. tostring(self.recycleSearchText or "")
    elseif self.mode == "attribute" then
        parts[#parts + 1] = "search=" .. tostring(self.attributeSearchText or "")
    elseif self.mode == "tasks" then
        parts[#parts + 1] = "taskList=" .. tostring(listName)
    end
    if self.mode == "tasks" then
        parts[#parts + 1] = "section=" .. self:getActivePageSection(self.mode)
    end
    if listName == "detail" then
        parts[#parts + 1] = "selected=" .. tostring(self:getPayloadId(self:getSelectedPayload()) or "")
    end
    return table.concat(parts, "\30")
end

function GodSystemWindow:captureListState(list, listName)
    if not ListState then return nil end
    return ListState.capture(list, self:listStateContext(listName), function(payload)
        return self:getPayloadId(payload)
    end)
end

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
    self.restoreListState = self:captureListState(self.list, "main")
    self.restoreActiveListSnapshot = self:captureListState(self.activeList, "active")
    self.restoreDetailListSnapshot = self:captureListState(self.detailList, "detail")
end

function GodSystemWindow:restoreScrollState()
    local pending = self.pendingRestoreMode == self.mode and self.pendingRestoreScroll or nil
    local listState = pending and pending.listState or self.restoreListState
    local restoreMode = pending and pending.mode or self.restoreScrollMode
    local restoreCategory = pending and pending.category or self.restoreScrollCategory
    local restoreShopSearch = pending and pending.shopSearch or self.restoreScrollShopSearch
    local restoreRecycleSearch = pending and pending.recycleSearch or self.restoreScrollRecycleSearch
    local restoreY = pending and pending.y or self.restoreScrollY
    if restoreMode ~= self.mode then return false end
    if self.mode == "shop" then
        if restoreCategory ~= self.shopCategoryKey then return false end
        if restoreShopSearch ~= self.shopSearchText then return false end
    elseif self.mode == "recycle" then
        if restoreRecycleSearch ~= self.recycleSearchText then return false end
    end
    if ListState and listState then
        local context = self:listStateContext("main")
        local restored = ListState.restore(self.list, listState, context, function(payload)
            return self:getPayloadId(payload)
        end)
        if restored then
            ListState.restoreNextTick(self.list, listState, context, function(payload)
                return self:getPayloadId(payload)
            end)
            self.lastSelectableListRow = math.floor(tonumber(self.list.selected) or 0)
        end
        return restored
    end
    if self.list and self.list.setYScroll and restoreY then
        self.list:setYScroll(restoreY)
    end
    return true
end

function GodSystemWindow:restoreActiveListState()
    local pending = self.pendingRestoreMode == self.mode and self.pendingRestoreScroll or nil
    local state = pending and pending.activeListState or self.restoreActiveListSnapshot
    if not ListState or not state then return false end
    local context = self:listStateContext("active")
    local restored = ListState.restore(self.activeList, state, context, function(payload)
        return self:getPayloadId(payload)
    end)
    if restored then
        ListState.restoreNextTick(self.activeList, state, context, function(payload)
            return self:getPayloadId(payload)
        end)
        self.lastSelectableActiveRow = math.floor(tonumber(self.activeList.selected) or 0)
    end
    return restored
end

function GodSystemWindow:restoreDetailListState()
    local pending = self.pendingRestoreMode == self.mode and self.pendingRestoreScroll or nil
    local state = pending and pending.detailListState or self.restoreDetailListSnapshot
    if not ListState or not state then return false end
    local context = self:listStateContext("detail")
    local restored = ListState.restore(self.detailList, state, context, function(payload, row, index)
        return payload and payload.detailKey or (row and row.text and ("detail:" .. tostring(index)))
    end)
    if restored then
        ListState.restoreNextTick(self.detailList, state, context, function(payload, row, index)
            return payload and payload.detailKey or (row and row.text and ("detail:" .. tostring(index)))
        end)
    end
    return restored
end

function GodSystemWindow:clearPendingActionSelection()
    self.pendingRestoreSelectedId = nil
    self.pendingRestoreSelectedTaskList = nil
    self.pendingRestoreMode = nil
    self.pendingRestoreScroll = nil
end
end
