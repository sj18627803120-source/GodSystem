require "GodSystem_App"
require "GodSystem_UITheme"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

GodSystemItemEconomyUI = GodSystemItemEconomyUI or {}

local Theme = GodSystemUITheme or {}
local Colors = Theme.colors or {}
local service = GodSystemApp.services.itemConfig
local MAX_RESULTS = service.MAX_RESULTS
local SHOP_MODES = { "auto", "forced", "disabled" }
local VALUE_LABELS = {
    auto = { "EconomyValue_Auto", "Automatic" },
    forced = { "EconomyValue_Forced", "Forced" },
    disabled = { "EconomyValue_Disabled", "Disabled" },
}

local function color(name, fallback)
    return Colors[name] or fallback or { r = 1, g = 1, b = 1, a = 1 }
end

local function text(key, fallback)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.text then
        return GodSystemApp.services.runtime.text(key, fallback)
    end
    return fallback or key
end

local function valueLabel(value)
    local row = VALUE_LABELS[tostring(value or "")]
    return row and text(row[1], row[2]) or tostring(value or "")
end

local function entryText(entry)
    return entry and entry.getInternalText and tostring(entry:getInternalText() or "") or ""
end

local function addLabel(owner, x, y, label)
    local value = ISLabel:new(x, y, 20, label, 0.86, 0.84, 0.76, 1, UIFont.Small, true)
    value:initialise()
    owner:addChild(value)
    return value
end

GodSystemItemEconomyWindow = ISCollapsableWindow:derive("GodSystemItemEconomyWindow")

function GodSystemItemEconomyWindow:new(x, y, width, height, owner)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = text("EconomyAdmin_Title", "GodSystem Item Economy")
    o.owner = owner
    o.resizable = false
    o.searchText = ""
    o.selectedKey = nil
    o.detailsKey = nil
    o.detailsPending = false
    o.editShopMode = "auto"
    o.visibleRows = {}
    return o
end

function GodSystemItemEconomyWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.searchBox = ISTextEntryBox:new("", 12, 30, 696, 28)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.target = self
    self.searchBox.onTextChange = function(entry) self:onSearchChanged(entry) end
    self:addChild(self.searchBox)

    self.list = ISScrollingListBox:new(12, 68, 300, 326)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 34
    self.list.doDrawItem = function(list, y, row, alt) return self:drawCatalogItem(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onCatalogSelected)
    self:addChild(self.list)

    self.detail = ISScrollingListBox:new(324, 68, 384, 108)
    self.detail:initialise()
    self.detail:instantiate()
    self.detail.itemheight = 20
    self.detail.doDrawItem = function(list, y, row)
        local c = row and row.item and row.item.warning and color("red") or color("text")
        list:drawText(tostring(row and row.text or ""), 6, y + 3, c.r, c.g, c.b, c.a, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.detail)

    addLabel(self, 324, 184, text("EconomyAdmin_BuyOverride", "Shop price override"))
    self.buyEntry = ISTextEntryBox:new("", 324, 204, 116, 28)
    self.buyEntry:initialise(); self.buyEntry:instantiate(); self:addChild(self.buyEntry)

    addLabel(self, 448, 184, text("EconomyAdmin_SellOverride", "Recycle override"))
    self.sellEntry = ISTextEntryBox:new("", 448, 204, 116, 28)
    self.sellEntry:initialise(); self.sellEntry:instantiate(); self:addChild(self.sellEntry)

    addLabel(self, 572, 184, text("EconomyAdmin_CategoryOverride", "Category override"))
    self.categoryEntry = ISTextEntryBox:new("", 572, 204, 136, 28)
    self.categoryEntry:initialise(); self.categoryEntry:instantiate(); self:addChild(self.categoryEntry)

    addLabel(self, 324, 244, text("EconomyAdmin_ShopMode", "Shop listing mode"))
    self.shopModeButtons = {}
    local modeWidth = 124
    for index = 1, #SHOP_MODES do
        local mode = SHOP_MODES[index]
        local button = ISButton:new(324 + ((index - 1) * (modeWidth + 6)), 264, modeWidth, 30, valueLabel(mode), self, self.onShopModeOption)
        button:initialise()
        button.mode = mode
        self:addChild(button)
        self.shopModeButtons[mode] = button
    end

    addLabel(self, 324, 282, text("EconomyAdmin_Note", "Administrator note"))
    self.noteEntry = ISTextEntryBox:new("", 324, 302, 384, 28)
    self.noteEntry:initialise(); self.noteEntry:instantiate(); self:addChild(self.noteEntry)

    self.saveButton = ISButton:new(324, 402, 105, 34, text("Btn_Save", "Save"), self, self.onSave)
    self.saveButton:initialise(); self:addChild(self.saveButton)
    self.resetButton = ISButton:new(437, 402, 160, 34, text("EconomyAdmin_Reset", "Restore automatic"), self, self.onReset)
    self.resetButton:initialise(); self:addChild(self.resetButton)
    self.closeButton = ISButton:new(605, 402, 103, 34, text("Btn_Close", "Close"), self, self.close)
    self.closeButton:initialise(); self:addChild(self.closeButton)

    self:clearEditor()
    self:populate()
    self.unsubscribe = GodSystemApp.services.itemConfig:subscribe(0, function(event)
        if not (self.getIsVisible and self:getIsVisible()) then return end
        if event and event.topic == "detailsChanged" then
            self:applySelectedDetails()
        elseif event and event.topic == "catalogChanged" then
            self:populate()
        else
            if self.owner and self.owner.requestDeferredPopulate then
                self.owner:requestDeferredPopulate(1)
            end
            self:refreshSelected(true)
        end
    end)
end

function GodSystemItemEconomyWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local shell, border = color("shell"), color("borderStrong")
    self:drawRect(0, 16, self.width, self.height - 16, shell.a, shell.r, shell.g, shell.b)
    self:drawRectBorder(1, 17, self.width - 2, self.height - 18, border.a, border.r, border.g, border.b)
end

function GodSystemItemEconomyWindow:drawCatalogItem(list, y, row, alt)
    local background = alt and color("rowAlt") or color("row")
    list:drawRect(0, y, list.width, list.itemheight - 1, background.a, background.r, background.g, background.b)
    if list.selected == row.index then
        local selected = color("rowSelect")
        list:drawRect(0, y, list.width, list.itemheight - 1, selected.a, selected.r, selected.g, selected.b)
    end
    local c = color("text")
    list:drawText(tostring(row and row.text or ""), 8, y + 8, c.r, c.g, c.b, c.a, UIFont.Small)
    return y + list.itemheight
end

function GodSystemItemEconomyWindow:clearEditor()
    self.detailsKey = nil
    self.detailsPending = false
    self.editShopMode = "auto"
    if self.buyEntry then self.buyEntry:setText("") end
    if self.sellEntry then self.sellEntry:setText("") end
    if self.categoryEntry then self.categoryEntry:setText("") end
    if self.noteEntry then self.noteEntry:setText("") end
    if self.detail then self.detail:clear() end
    self:updateEditorButtons()
end

function GodSystemItemEconomyWindow:onSearchChanged(entry)
    local nextSearch = entry and entry.getInternalText and entry:getInternalText() or ""
    if nextSearch == self.searchText then return end
    self.searchText = nextSearch
    self.selectedKey = nil
    self:clearEditor()
    self:populate()
end

function GodSystemItemEconomyWindow:populate()
    local catalogService = GodSystemApp.services.itemConfig
    catalogService:execute(0, "catalogQuery", { search = self.searchText })
    local model = catalogService:getViewModel(0)
    local page = model.page or { rows = {} }
    self.list:clear()
    self.visibleRows = {}

    if not model.allowed then
        self.list:addItem(text("Admin_Only", "Admin only"), {})
        return
    end
    for index = 1, math.min(#(page.rows or {}), MAX_RESULTS) do
        local item = page.rows[index]
        self.visibleRows[#self.visibleRows + 1] = item
        self.list:addItem(tostring(item.label or item.fullType), item)
        if item.key == self.selectedKey then self.list.selected = #self.list.items end
    end
    if #self.visibleRows == 0 then
        self.list:addItem(text("Shop_EmptyHint", "No items match this search"), {})
    end
end

function GodSystemItemEconomyWindow:getSelected()
    local index = self.list and math.floor(tonumber(self.list.selected) or 0) or 0
    local row = index > 0 and self.list.items[index] or nil
    local item = row and row.item or nil
    if type(item) ~= "table" or tostring(item.fullType or "") == "" then return nil end
    return item
end

function GodSystemItemEconomyWindow:onCatalogSelected(item)
    item = item and (item.item or item) or self:getSelected()
    if type(item) ~= "table" or tostring(item.fullType or "") == "" then return end
    self.selectedKey = tostring(item.key or item.variantKey or item.fullType)
    self.detailsKey = tostring(item.variantKey or item.fullType)
    self.detailsPending = true
    self:updateEditorButtons()
    GodSystemApp.services.itemConfig:execute(0, "detailsGet", {
        key = item.key,
        fullType = item.fullType,
        label = item.label,
        variantKey = item.variantKey,
        worldSprite = item.worldSprite,
    })
    self:applySelectedDetails()
end

function GodSystemItemEconomyWindow:getSelectedDetails()
    local details = GodSystemApp.services.itemConfig:getViewModel(0).details or {}
    return self.detailsKey and details[self.detailsKey] or nil
end

function GodSystemItemEconomyWindow:applySelectedDetails()
    local details = self:getSelectedDetails()
    if not details then return end
    self.detailsPending = details.ready ~= true
    local override = details.override or {}
    local variantOverride = details.variantOverride or {}
    self.editShopMode = details.variantKey and tostring(variantOverride.shopMode or details.shopMode or "auto")
        or tostring(override.shopMode or details.shopMode or "auto")
    self.buyEntry:setText(override.buyPrice ~= nil and tostring(override.buyPrice) or "")
    self.sellEntry:setText(override.sellPrice ~= nil and tostring(override.sellPrice) or "")
    self.categoryEntry:setText(override.category ~= nil and tostring(override.category) or "")
    self.noteEntry:setText(override.note ~= nil and tostring(override.note) or "")
    self:updateDetail(details)
    self:updateEditorButtons()
end

function GodSystemItemEconomyWindow:updateDetail(details)
    self.detail:clear()
    self.detail:addItem(tostring(details.label or details.fullType or ""), {})
    self.detail:addItem(tostring(details.fullType or ""), {})
    if details.worldSprite then self.detail:addItem("worldSprite: " .. tostring(details.worldSprite), {}) end
    for line in tostring(details.detail or ""):gmatch("[^\n]+") do self.detail:addItem(line, {}) end
    if details.eligible ~= true then
        self.detail:addItem(text("EconomyAdmin_ReadOnly", "This internal or unsafe item is read-only."), { warning = true })
    end
    local quote = details.quote or {}
    for index = 1, #(quote.warnings or {}) do
        if quote.warnings[index] == "admin_below_safe_minimum" then
            self.detail:addItem(text("EconomyWarning_Arbitrage", "Administrator price is below the safe minimum."), { warning = true })
        end
    end
end

function GodSystemItemEconomyWindow:onShopModeOption(button)
    local mode = button and button.mode or nil
    if mode == nil then return end
    self:setShopMode(mode)
end

function GodSystemItemEconomyWindow:setShopMode(value)
    self.editShopMode = value
    self:updateEditorButtons()
end

function GodSystemItemEconomyWindow:updateEditorButtons()
    if self.shopModeButtons then
        for _, mode in ipairs(SHOP_MODES) do
            local button = self.shopModeButtons[mode]
            if button then
                button:setTitle((mode == self.editShopMode and "[x] " or "[ ] ") .. valueLabel(mode))
                button:setEnable(self:getSelected() ~= nil)
            end
        end
    end
    local item = self:getSelected()
    local details = self:getSelectedDetails()
    local enabled = item ~= nil and details ~= nil and details.ready == true and details.eligible == true
    if self.saveButton then self.saveButton:setEnable(enabled) end
    if self.resetButton then self.resetButton:setEnable(enabled) end
end

function GodSystemItemEconomyWindow:onSave()
    local item = self:getSelected()
    local details = self:getSelectedDetails()
    if not item or not details or details.ready ~= true or details.eligible ~= true then return end
    if self.editShopMode == "forced" and item.fullType == "Moveables.Moveable" and not item.worldSprite then
        if GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
            GodSystemApp.services.runtime.notify(text("EconomyAdmin_FurnitureNeedsVariant", "Furniture must use a known world-sprite variant before it can be forced into the shop."))
        end
        return
    end
    local override = {
        buyPrice = entryText(self.buyEntry) ~= "" and tonumber(entryText(self.buyEntry)) or nil,
        sellPrice = entryText(self.sellEntry) ~= "" and tonumber(entryText(self.sellEntry)) or nil,
        category = entryText(self.categoryEntry) ~= "" and entryText(self.categoryEntry) or nil,
        shopMode = item.variantKey and "auto" or self.editShopMode,
        note = entryText(self.noteEntry) ~= "" and entryText(self.noteEntry) or nil,
    }
    local sent = GodSystemApp.services.itemConfig:execute(0, "set", {
        fullType = item.fullType,
        override = override,
        variantKey = item.variantKey,
        worldSprite = item.worldSprite,
        shopMode = self.editShopMode,
    })
    if sent and GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
        GodSystemApp.services.runtime.notify(text("EconomyAdmin_Saved", "Item economy configuration saved."))
    end
end

function GodSystemItemEconomyWindow:onReset()
    local item = self:getSelected()
    local details = self:getSelectedDetails()
    if not item or not details or details.ready ~= true or details.eligible ~= true then return end
    local sent = GodSystemApp.services.itemConfig:execute(0, "clear", {
        fullType = item.fullType,
        variantKey = item.variantKey,
    })
    if sent and GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
        GodSystemApp.services.runtime.notify(text("EconomyAdmin_ResetDone", "Automatic pricing restored."))
    end
end

function GodSystemItemEconomyWindow:refreshSelected(requestDetails)
    local stableKey = self.selectedKey
    self:populate()
    if not stableKey then return end
    for index = 1, #self.visibleRows do
        local item = self.visibleRows[index]
        if tostring(item.key or item.variantKey or item.fullType) == stableKey then
            self.list.selected = index
            if requestDetails then self:onCatalogSelected(item) end
            return
        end
    end
    self.selectedKey = nil
    self:clearEditor()
end

function GodSystemItemEconomyWindow:close()
    if self.unsubscribe then self.unsubscribe(); self.unsubscribe = nil end
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if GodSystemItemEconomyUI.window == self then GodSystemItemEconomyUI.window = nil end
end

function GodSystemItemEconomyUI.open(owner)
    if GodSystemItemEconomyUI.window then
        return GodSystemUI.presentOverlay(GodSystemItemEconomyUI.window)
    end
    local width, height = 720, 460
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    local window = GodSystemItemEconomyWindow:new(
        math.max(20, (screenW - width) / 2),
        math.max(20, (screenH - height) / 2),
        width,
        height,
        owner
    )
    window:initialise()
    GodSystemUI.presentOverlay(window)
    GodSystemItemEconomyUI.window = window
    return window
end

return GodSystemItemEconomyUI
