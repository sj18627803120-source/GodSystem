require "GodSystem_App"
require "GodSystem_UITheme"
require "GodSystem_ItemConfig"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"

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

local function multiplayer() return isClient and isClient() == true end

local function trimmed(value) return tostring(value or ""):match("^%s*(.-)%s*$") or "" end

local function notify(message)
    if GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
        GodSystemApp.services.runtime.notify(message)
    end
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
    o.searchDueMs = nil
    o.riskConfirmation = nil
    o.presetOrder = {}
    o.presetActive = GodSystemItemConfig.PRESET_DEFAULT
    o.presetConfirmation = nil
    o.presetNameBox = nil
    return o
end

function GodSystemItemEconomyWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.presetBox = ISComboBox:new(12, 30, 260, 28, self, self.onPresetSelected)
    self.presetBox:initialise()
    self.presetBox:instantiate()
    self:addChild(self.presetBox)

    self.savePresetButton = ISButton:new(280, 30, 105, 28, text("EconomyAdmin_PresetSave", "保存预设"), self, self.onSavePreset)
    self.savePresetButton:initialise()
    self:addChild(self.savePresetButton)

    self.deletePresetButton = ISButton:new(393, 30, 105, 28, text("EconomyAdmin_PresetDelete", "删除预设"), self, self.onDeletePreset)
    self.deletePresetButton:initialise()
    self:addChild(self.deletePresetButton)

    self.searchBox = ISTextEntryBox:new("", 12, 70, self.width - 24, 28)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.target = self
    self.searchBox.onTextChange = function(entry) self:onSearchChanged(entry) end
    self:addChild(self.searchBox)

    self.list = ISScrollingListBox:new(12, 108, 430, self.height - 166)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 42
    self.list.doDrawItem = function(list, y, row, alt) return self:drawCatalogItem(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onCatalogSelected)
    self:addChild(self.list)

    self.detail = ISScrollingListBox:new(454, 108, self.width - 466, 108)
    self.detail:initialise()
    self.detail:instantiate()
    self.detail.itemheight = 20
    self.detail.doDrawItem = function(list, y, row)
        local nextY = y + list.itemheight
        local scroll = list:getYScroll()
        if math.min(nextY - 1 + scroll, list.height) <= math.max(y + scroll, 0) then return nextY end
        local fontHeight = getTextManager():getFontHeight(UIFont.Small)
        local textY = y + 3
        if textY + scroll >= 1 and textY + scroll + fontHeight <= list.height - 1 then
            local c = row and row.item and row.item.warning and color("red") or color("text")
            list:drawText(tostring(row and row.text or ""), 6, textY, c.r, c.g, c.b, c.a, UIFont.Small)
        end
        return nextY
    end
    self:addChild(self.detail)

    addLabel(self, 454, 224, text("EconomyAdmin_BuyOverride", "Shop price override"))
    self.buyEntry = ISTextEntryBox:new("", 454, 244, 140, 28)
    self.buyEntry:initialise(); self.buyEntry:instantiate(); self:addChild(self.buyEntry)

    addLabel(self, 604, 224, text("EconomyAdmin_SellOverride", "Recycle override"))
    self.sellEntry = ISTextEntryBox:new("", 604, 244, 140, 28)
    self.sellEntry:initialise(); self.sellEntry:instantiate(); self:addChild(self.sellEntry)

    addLabel(self, 754, 224, text("EconomyAdmin_CategoryOverride", "Category override"))
    self.categoryEntry = ISTextEntryBox:new("", 754, 244, math.max(100, self.width - 766), 28)
    self.categoryEntry:initialise(); self.categoryEntry:instantiate(); self:addChild(self.categoryEntry)

    addLabel(self, 454, 284, text("EconomyAdmin_ShopMode", "Shop listing mode"))
    self.shopModeButtons = {}
    local modeWidth = 124
    for index = 1, #SHOP_MODES do
        local mode = SHOP_MODES[index]
        local button = ISButton:new(454 + ((index - 1) * (modeWidth + 6)), 304, modeWidth, 30, valueLabel(mode), self, self.onShopModeOption)
        button:initialise()
        button.mode = mode
        self:addChild(button)
        self.shopModeButtons[mode] = button
    end

    addLabel(self, 454, 342, text("EconomyAdmin_Note", "Administrator note"))
    self.noteEntry = ISTextEntryBox:new("", 454, 362, math.max(160, self.width - 466), 28)
    self.noteEntry:initialise(); self.noteEntry:instantiate(); self:addChild(self.noteEntry)

    self.saveButton = ISButton:new(454, self.height - 54, 105, 34, text("Btn_Save", "Save"), self, self.onSave)
    self.saveButton:initialise(); self:addChild(self.saveButton)
    self.resetButton = ISButton:new(567, self.height - 54, 160, 34, text("EconomyAdmin_Reset", "Restore automatic"), self, self.onReset)
    self.resetButton:initialise(); self:addChild(self.resetButton)
    self.relationsButton = ISButton:new(735, self.height - 54, 145, 34, text("EconomyAdmin_ConversionRisks", "转换风险"), self, self.onRelations)
    self.relationsButton:initialise(); self:addChild(self.relationsButton)
    self.closeButton = ISButton:new(self.width - 115, self.height - 54, 103, 34, text("Btn_Close", "Close"), self, self.close)
    self.closeButton:initialise(); self:addChild(self.closeButton)

    self:clearEditor()
    self:populate()
    self:loadPresets()
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

function GodSystemItemEconomyWindow:applyPresets(presets)
    presets = (type(presets) == "table") and presets or {}
    self.presetOrder = (type(presets.order) == "table") and presets.order or {}
    self.presetActive = (type(presets.active) == "string" and presets.active ~= "")
        and presets.active or GodSystemItemConfig.PRESET_DEFAULT
    if GodSystemApp.services.runtime then
        GodSystemApp.services.runtime.itemConfigPresets = { order = self.presetOrder, active = self.presetActive }
    end
    if not self.presetBox then return end
    self.presetBox:clear()
    self.presetBox:addOptionWithData(text("EconomyAdmin_PresetDefault", "默认"), GodSystemItemConfig.PRESET_DEFAULT)
    for _, name in ipairs(self.presetOrder) do
        self.presetBox:addOptionWithData(tostring(name), tostring(name))
    end
    self.presetBox:selectData(self.presetActive)
end

function GodSystemItemEconomyWindow:loadPresets()
    if multiplayer() then
        local runtime = GodSystemApp.services.runtime
        self:applyPresets(runtime and runtime.itemConfigPresets or nil)
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigPresetsGet", {}) end
        return
    end
    local data = GodSystemApp.services.runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    self:applyPresets(GodSystemItemConfig.presetListPayload(data.itemConfig))
end

-- Single-player preset mutations mirror the server commands: mutate the migrated
-- store, re-apply runtime pricing, persist, then republish through the service.
function GodSystemItemEconomyWindow:localPreset(op, name)
    local runtime = GodSystemApp.services.runtime
    local data = runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    local config = data.itemConfig
    local store, err
    if op == "save" then
        store, err = GodSystemItemConfig.savePreset(config, name)
    elseif op == "delete" then
        store = GodSystemItemConfig.deletePreset(config, name)
    else
        store = GodSystemItemConfig.applyPreset(config, name)
    end
    if not store then return false, err end
    if op == "apply" then
        GodSystemItemConfig.applyRuntime(config.itemOverrides, config.shopVariantOverrides, config.economyRevision, config)
        if GodSystemEconomyPolicy and GodSystemEconomyPolicy.rebuildConversionFloors then GodSystemEconomyPolicy.rebuildConversionFloors() end
    end
    runtime.economySnapshot = nil
    runtime.save()
    self:applyPresets(GodSystemItemConfig.presetListPayload(config))
    if service and service.handleChanged then service:handleChanged() end
    return true
end

function GodSystemItemEconomyWindow:requestPresetApply(name)
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigPresetApply", { name = name }) end
        return
    end
    if self:localPreset("apply", name) then notify(text("EconomyAdmin_PresetApplied", "预设已切换")) end
end

function GodSystemItemEconomyWindow:requestPresetDelete(name)
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigPresetDelete", { name = name }) end
        return
    end
    if self:localPreset("delete", name) then notify(text("EconomyAdmin_PresetDeleted", "预设已删除")) end
end

function GodSystemItemEconomyWindow:onPresetSelected(box)
    if self.presetConfirmation then return end
    local index = box and tonumber(box.selected) or 0
    local name = index > 0 and box:getOptionData(index) or nil
    name = name and tostring(name) or ""
    if name == "" or name == self.presetActive then
        if box then box:selectData(self.presetActive) end
        return
    end
    -- Revert the visual selection until the switch is confirmed; selectData does
    -- not re-enter this callback (only popup clicks fire onChange).
    box:selectData(self.presetActive)
    local modal = ISModalDialog:new(0, 0, 480, 200,
        text("EconomyAdmin_PresetSwitchConfirm", "切换预设将覆盖当前未保存为预设的修改，确定继续吗？"),
        true, self, function(target, pressed, payload)
            target.presetConfirmation = nil
            if pressed and pressed.internal == "YES" then target:requestPresetApply(tostring(payload)) end
        end, 0, name)
    modal:initialise()
    self.presetConfirmation = modal
    GodSystemUI.presentOverlay(modal)
end

function GodSystemItemEconomyWindow:onSavePreset()
    if self.presetConfirmation or self.presetNameBox then return end
    local current = self.presetActive == GodSystemItemConfig.PRESET_DEFAULT and "" or tostring(self.presetActive)
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    local box = ISTextBox:new(math.max(12, (screenW - 420) / 2), math.max(12, (screenH - 180) / 2), 420, 180,
        text("EconomyAdmin_PresetNamePrompt", "输入预设名称，同名预设将被覆盖"), current,
        self, self.onPresetNameResult, 0)
    box.noEmpty = true
    box.maxChars = GodSystemItemConfig.PRESET_NAME_MAX
    box:initialise()
    self.presetNameBox = box
    GodSystemUI.presentOverlay(box)
end

function GodSystemItemEconomyWindow:onPresetNameResult(button)
    local box = self.presetNameBox
    self.presetNameBox = nil
    if not (button and button.internal == "OK") then return end
    local name = trimmed(box and box.entry and box.entry:getText() or "")
    if name == "" then return end
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigPresetSave", { name = name }) end
        return
    end
    local ok, err = self:localPreset("save", name)
    if ok then
        notify(text("EconomyAdmin_PresetSaved", "预设已保存"))
    elseif err == "Limit" then
        notify(text("EconomyAdmin_PresetLimit", "预设数量已达上限"))
    else
        notify(text("EconomyAdmin_PresetNameInvalid", "预设名称无效"))
    end
end

function GodSystemItemEconomyWindow:onDeletePreset()
    if self.presetConfirmation then return end
    local name = tostring(self.presetActive or "")
    if name == "" or name == GodSystemItemConfig.PRESET_DEFAULT then
        notify(text("EconomyAdmin_PresetDefaultProtected", "默认预设无法删除"))
        return
    end
    local modal = ISModalDialog:new(0, 0, 480, 200,
        text("EconomyAdmin_PresetDeleteConfirm", "确定删除当前预设吗？此操作不可撤销。"),
        true, self, function(target, pressed, payload)
            target.presetConfirmation = nil
            if pressed and pressed.internal == "YES" then target:requestPresetDelete(tostring(payload)) end
        end, 0, name)
    modal:initialise()
    self.presetConfirmation = modal
    GodSystemUI.presentOverlay(modal)
end

function GodSystemItemEconomyWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local shell, border = color("shell"), color("borderStrong")
    self:drawRect(0, 16, self.width, self.height - 16, shell.a, shell.r, shell.g, shell.b)
    self:drawRectBorder(1, 17, self.width - 2, self.height - 18, border.a, border.r, border.g, border.b)
    if self.searchDueMs and (getTimestampMs and getTimestampMs() or 0) >= self.searchDueMs then
        self.searchDueMs = nil
        self:populate()
    end
end

function GodSystemItemEconomyWindow:drawCatalogItem(list, y, row, alt)
    local nextY = y + list.itemheight
    local scroll = list:getYScroll()
    local top = math.max(y + scroll, 0)
    local bottom = math.min(nextY - 1 + scroll, list.height)
    if bottom <= top then return nextY end
    local background = alt and color("rowAlt") or color("row")
    list:drawRect(0, top - scroll, list.width, bottom - top, background.a, background.r, background.g, background.b)
    if list.selected == row.index then
        local selected = color("rowSelect")
        list:drawRect(0, top - scroll, list.width, bottom - top, selected.a, selected.r, selected.g, selected.b)
    end
    local c = color("text")
    local item = row and row.item or {}
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local labelY = y + 4
    if labelY + scroll >= 1 and labelY + scroll + fontHeight <= list.height - 1 then
        list:drawText(tostring(item.label or row and row.text or ""), 8, labelY, c.r, c.g, c.b, c.a, UIFont.Small)
    end
    local typeY = y + 22
    if typeY + scroll >= 1 and typeY + scroll + fontHeight <= list.height - 1 then
        list:drawText(tostring(item.fullType or ""), 8, typeY, c.r, c.g, c.b, c.a, UIFont.Small)
    end
    return nextY
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
    self.searchDueMs = (getTimestampMs and getTimestampMs() or 0) + 250
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
    local lowKey = tostring(item.fullType) .. ":" .. tostring(override.buyPrice or "")
    local safe = math.max(0, tonumber(details.quote and details.quote.safeMinimum) or 0)
    local acknowledge = false
    if override.buyPrice and override.buyPrice < safe then
        if self.riskConfirmation ~= lowKey then
            self.riskConfirmation = lowKey
            if GodSystemApp.services.runtime and GodSystemApp.services.runtime.notify then
                GodSystemApp.services.runtime.notify(text("EconomyWarning_Arbitrage", "Price is below the safe minimum. Save again to confirm."))
            end
            return
        end
        acknowledge = true
    end
    local sent = GodSystemApp.services.itemConfig:execute(0, "set", {
        fullType = item.fullType,
        override = override,
        variantKey = item.variantKey,
        worldSprite = item.worldSprite,
        shopMode = self.editShopMode,
        expectedRevision = details.revision,
        acknowledgeRisk = acknowledge,
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

function GodSystemItemEconomyWindow:onRelations()
    if GodSystemConversionRelationsUI and GodSystemConversionRelationsUI.open then GodSystemConversionRelationsUI.open() end
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
    local width, height = 1040, 680
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    width, height = math.min(width, math.max(640, screenW - 24)), math.min(height, math.max(460, screenH - 24))
    local window = GodSystemItemEconomyWindow:new(
        math.max(12, (screenW - width) / 2),
        math.max(12, (screenH - height) / 2),
        width, height,
        owner
    )
    window:initialise()
    GodSystemUI.presentOverlay(window)
    GodSystemItemEconomyUI.window = window
    return window
end

return GodSystemItemEconomyUI
