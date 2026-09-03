require "GodSystem_App"
require "GodSystem_ItemCatalog"
require "GodSystem_RangeFilter"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"

local GodSystemRangeFilterListViewport = ISPanel:derive("GodSystemRangeFilterListViewport")

function GodSystemRangeFilterListViewport:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    return o
end

function GodSystemRangeFilterListViewport:prerender()
    self:setStencilRect(0, 0, self.width, self.height)
end

function GodSystemRangeFilterListViewport:render()
    self:clearStencilRect()
end

GodSystemRangeFilterWindow = ISCollapsableWindow:derive("GodSystemRangeFilterWindow")
GodSystemRangeFilterWindow.PAGE_SIZE = 40
GodSystemRangeFilterWindow.CATALOG_REFRESH_MS = 250

local MARGIN = 12
local TOP = 30
local INPUT_GAP = 8
local SEARCH_Y = TOP + 38
local FILTER_Y = SEARCH_Y + 32
local SUMMARY_Y = FILTER_Y + 32
-- Keep the native scrolling viewport below both combo boxes and the summary line.
local LIST_Y = SUMMARY_Y + 42
local LIST_ACTION_GAP = 12
local ACTION_HEIGHT = 28
local ACTION_BOTTOM_SPACE = 106

local function text(key, fallback)
    local runtime = GodSystemApp.services and GodSystemApp.services.runtime or nil
    return runtime and runtime.text and runtime.text(key, fallback) or fallback
end

local function formatText(template, args)
    local value = tostring(template or "")
    for index = 1, #(args or {}) do
        value = value:gsub("{" .. tostring(index) .. "}", function() return tostring(args[index] or "") end)
    end
    return value
end

local function notify(message)
    local runtime = GodSystemApp.services and GodSystemApp.services.runtime or nil
    if runtime and runtime.notify then runtime.notify(message) end
end

local function nowMs()
    return GodSystemScheduler and GodSystemScheduler.nowMs and GodSystemScheduler.nowMs() or 0
end

local function playerNum()
    local player = getPlayer and getPlayer() or nil
    return player and player.getPlayerNum and player:getPlayerNum() or 0
end

local function color(active)
    if active then return { r = 0.28, g = 0.68, b = 0.82, a = 0.95 } end
    return { r = 0.13, g = 0.18, b = 0.25, a = 0.95 }
end

local function setBounds(element, x, y, width, height)
    if not element then return end
    if x ~= nil then
        element.x = x
        if element.setX then element:setX(x) end
    end
    if y ~= nil then
        element.y = y
        if element.setY then element:setY(y) end
    end
    if width ~= nil then
        element.width = width
        if element.setWidth then element:setWidth(width) end
    end
    if height ~= nil then
        element.height = height
        if element.setHeight then element:setHeight(height) end
    end
end

local function resetListViewport(list)
    if not list then return end
    if list.setYScroll then list:setYScroll(0) end
    if list.setScrollHeight then list:setScrollHeight(0) end
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
end

function GodSystemRangeFilterWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = text("RangeFilter_Title", "Range recycle item filter")
    o.resizable = false
    -- ISCollapsableWindow only draws its content background when this is true.
    -- The filter is opened over a live item list, so partial transparency makes
    -- that list look as though it is painting through the filter controls.
    o.background = true
    o.backgroundColor = { r = 0.025, g = 0.055, b = 0.085, a = 1 }
    o.borderColor = { r = 0.24, g = 0.58, b = 0.72, a = 1 }
    o.activePage = "forbidden"
    o.page = 1
    o.selected = {}
    o.searchText = ""
    o.moduleName = ""
    o.displayCategory = ""
    o.lastCatalogBuilt = -1
    o.catalogRefreshAt = 0
    o.filterUnsubscribe = nil
    return o
end

function GodSystemRangeFilterWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function GodSystemRangeFilterWindow:layoutMetrics()
    local innerWidth = math.max(1, self.width - (MARGIN * 2))
    local actionY = math.max(LIST_Y + 1 + LIST_ACTION_GAP, self.height - ACTION_BOTTOM_SPACE)
    local listHeight = math.max(1, actionY - LIST_Y - LIST_ACTION_GAP)
    local searchWidth = innerWidth
    local moduleWidth = math.max(1, math.floor((innerWidth - INPUT_GAP) / 2))
    local categoryWidth = math.max(1, innerWidth - moduleWidth - INPUT_GAP)
    local closeWidth = math.max(72, math.min(100, math.floor(innerWidth * 0.14)))
    local navWidth = math.max(52, math.min(85, math.floor(innerWidth * 0.12)))
    local moveWidth = math.max(2, innerWidth - closeWidth - (navWidth * 2) - (INPUT_GAP * 4))
    local selectedWidth = math.max(1, math.floor(moveWidth * 0.45))
    local allWidth = math.max(1, moveWidth - selectedWidth)
    local actionX = MARGIN
    local selectedX = actionX
    local allX = selectedX + selectedWidth + INPUT_GAP
    local previousX = allX + allWidth + INPUT_GAP
    local nextX = previousX + navWidth + INPUT_GAP
    local closeX = nextX + navWidth + INPUT_GAP
    return {
        tabWidth = math.min(135, math.max(1, math.floor((innerWidth - INPUT_GAP) / 2))),
        searchX = MARGIN,
        searchWidth = searchWidth,
        moduleX = MARGIN,
        moduleWidth = moduleWidth,
        categoryX = MARGIN + moduleWidth + INPUT_GAP,
        categoryWidth = categoryWidth,
        listY = LIST_Y,
        listWidth = innerWidth,
        listHeight = listHeight,
        modeX = MARGIN,
        modeWidth = math.max(180, math.min(260, math.floor(innerWidth * 0.34))),
        summaryX = MARGIN + math.max(180, math.min(260, math.floor(innerWidth * 0.34))) + INPUT_GAP,
        summaryWidth = math.max(1, innerWidth - math.max(180, math.min(260, math.floor(innerWidth * 0.34))) - INPUT_GAP),
        actionY = actionY,
        selectedX = selectedX,
        selectedWidth = selectedWidth,
        allX = allX,
        allWidth = allWidth,
        previousX = previousX,
        nextX = nextX,
        navWidth = navWidth,
        closeX = closeX,
        closeWidth = closeWidth,
    }
end

function GodSystemRangeFilterWindow:applyLayout()
    if not self.list then return end
    local layout = self:layoutMetrics()
    setBounds(self.listViewport, MARGIN, layout.listY, layout.listWidth, layout.listHeight)
    setBounds(self.list, 0, 0, layout.listWidth, layout.listHeight)
    setBounds(self.headerShield, 0, TOP - 2, self.width, LIST_Y - TOP + 2)
    setBounds(self.allowedButton, MARGIN, TOP, layout.tabWidth, ACTION_HEIGHT)
    setBounds(self.forbiddenButton, MARGIN + layout.tabWidth + INPUT_GAP, TOP, layout.tabWidth, ACTION_HEIGHT)
    setBounds(self.searchBox, layout.searchX, SEARCH_Y, layout.searchWidth, 24)
    setBounds(self.moduleBox, layout.moduleX, FILTER_Y, layout.moduleWidth, 24)
    setBounds(self.categoryBox, layout.categoryX, FILTER_Y, layout.categoryWidth, 24)
    setBounds(self.modeButton, layout.modeX, SUMMARY_Y, layout.modeWidth, ACTION_HEIGHT)
    setBounds(self.summary, layout.summaryX, SUMMARY_Y + 5, layout.summaryWidth, ACTION_HEIGHT)
    setBounds(self.moveSelectedButton, layout.selectedX, layout.actionY, layout.selectedWidth, ACTION_HEIGHT)
    setBounds(self.moveAllButton, layout.allX, layout.actionY, layout.allWidth, ACTION_HEIGHT)
    setBounds(self.previousButton, layout.previousX, layout.actionY, layout.navWidth, ACTION_HEIGHT)
    setBounds(self.nextButton, layout.nextX, layout.actionY, layout.navWidth, ACTION_HEIGHT)
    setBounds(self.closeButton, layout.closeX, layout.actionY, layout.closeWidth, ACTION_HEIGHT)
    if gsSyncScrollingListGeometry then gsSyncScrollingListGeometry(self.list) end
end

function GodSystemRangeFilterWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local layout = self:layoutMetrics()

    self.listViewport = GodSystemRangeFilterListViewport:new(MARGIN, layout.listY, layout.listWidth, layout.listHeight)
    self.listViewport:initialise()
    self:addChild(self.listViewport)
    self.list = ISScrollingListBox:new(0, 0, layout.listWidth, layout.listHeight)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 26
    self.list.doDrawItem = function(list, y, row, alt) return self:drawItem(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onListMouseDown)
    if gsInstallSafeScrollingListPrerender then gsInstallSafeScrollingListPrerender(self.list) end
    self.listViewport:addChild(self.list)

    -- This opaque header is intentionally above the scrolling list. It is a
    -- second containment layer for B42 UI stacks where nested stencils leak.
    self.headerShield = ISPanel:new(0, TOP - 2, self.width, LIST_Y - TOP + 2)
    self.headerShield.backgroundColor = { r = 0.025, g = 0.055, b = 0.085, a = 1 }
    self.headerShield.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.headerShield:initialise()
    self:addChild(self.headerShield)

    self.allowedButton = ISButton:new(MARGIN, TOP, layout.tabWidth, ACTION_HEIGHT, text("RangeFilter_Allowed", "Allowed recycle"), self, self.onPage)
    self.allowedButton.internal = "allowed"
    self.allowedButton:initialise()
    self:addChild(self.allowedButton)
    self.forbiddenButton = ISButton:new(MARGIN + layout.tabWidth + INPUT_GAP, TOP, layout.tabWidth, ACTION_HEIGHT, text("RangeFilter_Forbidden", "Forbidden recycle"), self, self.onPage)
    self.forbiddenButton.internal = "forbidden"
    self.forbiddenButton:initialise()
    self:addChild(self.forbiddenButton)

    self.searchBox = ISTextEntryBox:new("", layout.searchX, SEARCH_Y, layout.searchWidth, 24)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.onTextChange = function(entry) self:onSearchChanged(entry) end
    self:addChild(self.searchBox)

    self.moduleBox = ISComboBox:new(layout.moduleX, FILTER_Y, layout.moduleWidth, 24, self, self.onFilterChanged)
    self.moduleBox:initialise()
    self.moduleBox:instantiate()
    self:addChild(self.moduleBox)
    self.categoryBox = ISComboBox:new(layout.categoryX, FILTER_Y, layout.categoryWidth, 24, self, self.onFilterChanged)
    self.categoryBox:initialise()
    self.categoryBox:instantiate()
    self:addChild(self.categoryBox)

    self.summary = ISLabel:new(MARGIN, SUMMARY_Y, 18, "", 0.78, 0.86, 0.9, 1, UIFont.Small, true)
    self.summary:initialise()
    self:addChild(self.summary)

    self.modeButton = ISButton:new(layout.modeX, SUMMARY_Y, layout.modeWidth, ACTION_HEIGHT, "", self, self.onModeButton)
    self.modeButton:initialise()
    self:addChild(self.modeButton)

    self.moveSelectedButton = ISButton:new(layout.selectedX, layout.actionY, layout.selectedWidth, ACTION_HEIGHT, "", self, self.onMoveSelected)
    self.moveSelectedButton:initialise()
    self:addChild(self.moveSelectedButton)
    self.moveAllButton = ISButton:new(layout.allX, layout.actionY, layout.allWidth, ACTION_HEIGHT, "", self, self.onMoveAll)
    self.moveAllButton:initialise()
    self:addChild(self.moveAllButton)
    self.previousButton = ISButton:new(layout.previousX, layout.actionY, layout.navWidth, ACTION_HEIGHT, text("Btn_ShopPrevPage", "Prev"), self, self.onPreviousPage)
    self.previousButton:initialise()
    self:addChild(self.previousButton)
    self.nextButton = ISButton:new(layout.nextX, layout.actionY, layout.navWidth, ACTION_HEIGHT, text("Btn_ShopNextPage", "Next"), self, self.onNextPage)
    self.nextButton:initialise()
    self:addChild(self.nextButton)
    self.closeButton = ISButton:new(layout.closeX, layout.actionY, layout.closeWidth, ACTION_HEIGHT, text("Btn_Close", "Close"), self, self.onClose)
    self.closeButton:initialise()
    self:addChild(self.closeButton)

    self.catalogUnsubscribe = GodSystemItemCatalog.subscribe(function(catalog)
        if catalog == GodSystemItemCatalog.Shared then
            self.catalogRefreshAt = math.max(self.catalogRefreshAt or 0, nowMs() + self.CATALOG_REFRESH_MS)
        end
    end)
    local service = GodSystemApp.services and GodSystemApp.services.rangeRecycle or nil
    if service and service.subscribe then
        self.filterUnsubscribe = service:subscribe(playerNum(), function(event)
            local topic = event and tostring(event.topic or "") or ""
            if topic == "filter" or topic == "filterMode" or topic == "filterSyncing"
                or topic == "filterSyncQueued" then
                self.page = 1
                self.selected = {}
                self:refresh(true)
            end
        end)
    end
    self:applyLayout()
    self:refresh(true)
end

function GodSystemRangeFilterWindow:onResize()
    if not self.list then return end
    self:applyLayout()
end

function GodSystemRangeFilterWindow:update()
    ISCollapsableWindow.update(self)
    if self.catalogRefreshAt > 0 and nowMs() >= self.catalogRefreshAt then
        self.catalogRefreshAt = 0
        self:refresh(true)
    end
end

function GodSystemRangeFilterWindow:allowedSet()
    local service = GodSystemApp.services.rangeRecycle
    local state = service and service:getViewModel(playerNum()) or {}
    local filter = GodSystemRangeFilter.normalize(state.filter)
    local set = {}
    for i = 1, #filter.activeFullTypes do set[filter.activeFullTypes[i]] = true end
    return set, state, filter
end

function GodSystemRangeFilterWindow:activeCachePage(filter)
    return filter.mode == "denylist" and "forbidden" or "allowed"
end

function GodSystemRangeFilterWindow:criteria()
    local allowed, _, filter = self:allowedSet()
    return {
        search = self.searchText,
        moduleName = self.moduleName,
        displayCategory = self.displayCategory,
        membership = function(row)
            local member = allowed[row.fullType] == true
            local allowedToRecycle = filter.mode == "denylist" and not member or filter.mode ~= "denylist" and member
            return self.activePage == "allowed" and allowedToRecycle or self.activePage == "forbidden" and not allowedToRecycle
        end,
    }
end

function GodSystemRangeFilterWindow:rebuildFilterChoices(catalog)
    local currentModule, currentCategory = self.moduleName, self.displayCategory
    local modules, categories = {}, {}
    for i = 1, #(catalog.rows or {}) do
        local row = catalog.rows[i]
        if row.moduleName and row.moduleName ~= "" then modules[row.moduleName] = true end
        if row.displayCategory and row.displayCategory ~= "" then categories[row.displayCategory] = true end
    end
    local function populate(box, values, selected, allLabel)
        box:clear()
        box:addOption(allLabel)
        local sorted = {}
        for value in pairs(values) do sorted[#sorted + 1] = value end
        table.sort(sorted)
        local select = 1
        for index = 1, #sorted do
            box:addOption(sorted[index])
            if sorted[index] == selected then select = index + 1 end
        end
        box:select(select)
        return selected ~= "" and select > 1 and selected or ""
    end
    self.moduleName = populate(self.moduleBox, modules, currentModule, text("RangeFilter_ModuleAll", "All mods"))
    self.displayCategory = populate(self.categoryBox, categories, currentCategory, text("RangeFilter_CategoryAll", "All categories"))
end

function GodSystemRangeFilterWindow:refresh(keepPage)
    local catalog = GodSystemItemCatalog.getShared()
    if self.lastCatalogBuilt ~= #catalog.rows then
        self.lastCatalogBuilt = #catalog.rows
        self:rebuildFilterChoices(catalog)
    end
    local result = catalog:queryFiltered(self:criteria(), self.page, self.PAGE_SIZE)
    self.page = result.page
    self.list:clear()
    resetListViewport(self.list)
    for index = 1, #result.rows do
        local row = result.rows[index]
        self.list:addItem(row.label, {
            fullType = row.fullType,
            label = row.label,
            moduleName = row.moduleName,
            displayCategory = row.displayCategory,
        })
    end
    self.result = result
    local selectedCount = 0
    for _ in pairs(self.selected) do selectedCount = selectedCount + 1 end
    local _, state, filter = self:allowedSet()
    local readyText = state.filterReady == true and "" or (" | " .. text("RangeFilter_Syncing", "Syncing"))
    self.summary:setName(string.format("%s %d/%d | %d | %d%s", text("RangeFilter_Page", "Page"), result.page, result.pageCount, result.total, #catalog.rows, readyText))
    local activeCachePage = self:activeCachePage(filter)
    local performanceMark = text("RangeFilter_PerformanceMark", "[Active]")
    self.allowedButton:setTitle(text("RangeFilter_Allowed", "Allowed recycle") .. (activeCachePage == "allowed" and performanceMark or ""))
    self.forbiddenButton:setTitle(text("RangeFilter_Forbidden", "Forbidden recycle") .. (activeCachePage == "forbidden" and performanceMark or ""))
    self.allowedButton.backgroundColor = color(self.activePage == "allowed")
    self.forbiddenButton.backgroundColor = color(self.activePage == "forbidden")
    local target = self.activePage == "allowed"
        and text("RangeFilter_MoveToForbidden", "Move selected items to forbidden recycle")
        or text("RangeFilter_MoveToAllowed", "Move selected items to allowed recycle")
    self.moveSelectedButton:setTitle(target .. " (" .. tostring(selectedCount) .. ")")
    self.moveAllButton:setTitle(self.activePage == "allowed"
        and text("RangeFilter_MoveAllToForbidden", "Move current results to forbidden recycle")
        or text("RangeFilter_MoveAllToAllowed", "Move current results to allowed recycle"))
    self.modeButton:setTitle(text("RangeFilter_ModeButton", "Mode switch"))
    local ready = state.filterReady == true
    self.moveSelectedButton.enable = ready and selectedCount > 0
    self.moveAllButton.enable = ready and result.complete == true and result.total > 0
    self.previousButton.enable = result.page > 1
    self.nextButton.enable = result.page < result.pageCount
end

function GodSystemRangeFilterWindow:drawItem(list, y, row, alt)
    local payload = row and row.item or {}
    local selected = self.selected[payload.fullType] == true
    local background = selected and { r = 0.14, g = 0.48, b = 0.56, a = 0.7 } or (alt and { r = 0.08, g = 0.12, b = 0.17, a = 0.85 } or { r = 0.05, g = 0.08, b = 0.12, a = 0.85 })
    list:drawRect(0, y, list.width, list.itemheight - 1, background.a, background.r, background.g, background.b)
    list:drawRectBorder(0, y, list.width, list.itemheight - 1, 0.7, 0.26, 0.48, 0.56)
    list:drawText(selected and "[x]" or "[ ]", 8, y + 5, 0.82, 0.94, 0.98, 1, UIFont.Small)
    list:drawText(tostring(payload.label or row.text or ""), 42, y + 5, 0.9, 0.94, 0.98, 1, UIFont.Small)
    local detail = tostring(payload.moduleName or "")
    if payload.displayCategory and payload.displayCategory ~= "" then detail = detail .. " | " .. payload.displayCategory end
    list:drawTextRight(detail, list.width - 8, y + 5, 0.52, 0.72, 0.8, 1, UIFont.Small)
    return y + list.itemheight
end

function GodSystemRangeFilterWindow:onListMouseDown(row)
    local payload = row and (row.item or row) or nil
    if not payload or not payload.fullType then return end
    self.selected[payload.fullType] = self.selected[payload.fullType] ~= true
    self:refresh(true)
end

function GodSystemRangeFilterWindow:onPage(button)
    if not button or button.internal == self.activePage then return end
    self.activePage = button.internal
    self.page = 1
    self.selected = {}
    self:refresh()
end

function GodSystemRangeFilterWindow:onModeButton()
    local _, state, filter = self:allowedSet()
    if state.filterReady ~= true then return end
    local targetMode = filter.mode == "denylist" and "allowlist" or "denylist"
    local message = targetMode == "denylist"
        and text("RangeFilter_ModeConfirmFast",
            "Switch to Quick Recycle?\nItems on the \"Forbidden Recycle\" list will not be range recycled; all other eligible items will.\nContinue?")
        or text("RangeFilter_ModeConfirmSafe",
            "Switch to Safe Recycle?\nOnly items on the \"Allowed Recycle\" list will be range recycled.\nContinue?")
    local x = math.max(80, (getCore():getScreenWidth() / 2) - 260)
    local y = math.max(80, (getCore():getScreenHeight() / 2) - 120)
    local modal = ISModalDialog:new(x, y, 520, 240, message, true, self, self.onModeConfirm, playerNum(), { mode = targetMode })
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
end

function GodSystemRangeFilterWindow:onModeConfirm(button, payload)
    if not button or button.internal ~= "YES" or not payload then return end
    local service = GodSystemApp.services.rangeRecycle
    if service then service:execute(playerNum(), "filterMode", { mode = payload.mode }) end
end

function GodSystemRangeFilterWindow:onSearchChanged(entry)
    self.searchText = tostring(entry:getInternalText() or "")
    self.page = 1
    self.catalogRefreshAt = nowMs() + 180
end

function GodSystemRangeFilterWindow:onFilterChanged(box)
    self.moduleName = self.moduleBox.selected > 1 and self.moduleBox:getOptionText(self.moduleBox.selected) or ""
    self.displayCategory = self.categoryBox.selected > 1 and self.categoryBox:getOptionText(self.categoryBox.selected) or ""
    self.page = 1
    self:refresh()
end

function GodSystemRangeFilterWindow:move(fullTypes, replace)
    if #fullTypes <= 0 then return end
    local service = GodSystemApp.services.rangeRecycle
    local _, _, filter = self:allowedSet()
    local activePage = self:activeCachePage(filter)
    local remove = self.activePage == activePage
    if replace or #fullTypes > 256 then
        local members = {}
        for i = 1, #filter.activeFullTypes do members[filter.activeFullTypes[i]] = true end
        for i = 1, #fullTypes do
            if remove then members[fullTypes[i]] = nil else members[fullTypes[i]] = true end
        end
        local values = {}
        for fullType in pairs(members) do values[#values + 1] = fullType end
        table.sort(values)
        if #values > GodSystemRangeFilter.MAX_ACTIVE_ITEMS then
            notify(formatText(text("RangeFilter_TooManyItems", "The range list supports at most {1} item types. Narrow the filter."), {
                GodSystemRangeFilter.MAX_ACTIVE_ITEMS,
            }))
            return
        end
        service:execute(playerNum(), "filterReplace", { state = { mode = filter.mode, activeFullTypes = values } })
    else
        service:execute(playerNum(), "filterDelta", {
            baseRevision = filter.revision,
            op = remove and "removeMany" or "addMany",
            fullTypes = fullTypes,
        })
    end
    self.selected = {}
    self:refresh(true)
end

function GodSystemRangeFilterWindow:onMoveSelected()
    local values = {}
    for fullType, checked in pairs(self.selected) do if checked then values[#values + 1] = fullType end end
    table.sort(values)
    self:move(values, false)
end

function GodSystemRangeFilterWindow:onMoveAll()
    local catalog = GodSystemItemCatalog.getShared()
    if not catalog.complete then return end
    self:move(catalog:collectFilteredFullTypes(self:criteria()), true)
end

function GodSystemRangeFilterWindow:onPreviousPage()
    self.page = math.max(1, self.page - 1)
    self:refresh(true)
end

function GodSystemRangeFilterWindow:onNextPage()
    self.page = math.min((self.result and self.result.pageCount) or 1, self.page + 1)
    self:refresh(true)
end

function GodSystemRangeFilterWindow:onClose()
    self:close()
end

function GodSystemRangeFilterWindow:close()
    if self.catalogUnsubscribe then self.catalogUnsubscribe(); self.catalogUnsubscribe = nil end
    if self.filterUnsubscribe then self.filterUnsubscribe(); self.filterUnsubscribe = nil end
    ISCollapsableWindow.close(self)
    if GodSystemUI then GodSystemUI.rangeFilterWindow = nil end
end

function GodSystemRangeFilterUI_open(owner)
    if GodSystemUI and GodSystemUI.rangeFilterWindow and GodSystemUI.rangeFilterWindow:getIsVisible() then
        GodSystemUI.rangeFilterWindow:bringToTop()
        return GodSystemUI.rangeFilterWindow
    end
    local defaultWidth, defaultHeight = 730, 560
    local screenW = getCore and getCore():getScreenWidth() or defaultWidth
    local screenH = getCore and getCore():getScreenHeight() or defaultHeight
    local width = math.min(730, math.max(1, screenW - 2))
    local height = math.min(560, math.max(1, screenH - 2))
    local window = GodSystemRangeFilterWindow:new(math.max(1, math.floor((screenW - width) / 2)), math.max(1, math.floor((screenH - height) / 2)), width, height)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:setAlwaysOnTop(true)
    window:bringToTop()
    if GodSystemUI then GodSystemUI.rangeFilterWindow = window end
    return window
end

return GodSystemRangeFilterWindow
