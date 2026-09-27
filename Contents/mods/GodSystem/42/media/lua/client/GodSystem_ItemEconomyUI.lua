require "GodSystem_App"
require "GodSystem_UITheme"
require "GodSystem_UISafety"
require "GodSystem_ItemConfig"
require "GodSystem_ItemConfigPresetLibrary"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
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

GodSystemPresetSlotDialog = ISCollapsableWindow:derive("GodSystemPresetSlotDialog")

function GodSystemPresetSlotDialog:new(owner, slot)
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    local width, height = 480, 230
    local o = ISCollapsableWindow.new(self, math.max(12, (screenW - width) / 2),
        math.max(12, (screenH - height) / 2), width, height)
    o.title = text("EconomyAdmin_PresetSlot", "Preset") .. " " .. slot
    o.owner, o.slot, o.resizable = owner, slot, false
    return o
end

function GodSystemPresetSlotDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.statusLabel = addLabel(self, 18, 42, "")
    self.remarkLabel = addLabel(self, 18, 76, "")
    self.readButton = ISButton:new(18, 126, 108, 32, text("EconomyAdmin_PresetRead", "Read"), self, self.onRead)
    self.readButton:initialise(); self:addChild(self.readButton)
    self.overwriteButton = ISButton:new(134, 126, 108, 32, text("EconomyAdmin_PresetOverwrite", "Overwrite"), self, self.onOverwrite)
    self.overwriteButton:initialise(); self:addChild(self.overwriteButton)
    self.remarkButton = ISButton:new(250, 126, 108, 32, text("EconomyAdmin_PresetEditRemark", "Edit remark"), self, self.onRemark)
    self.remarkButton:initialise(); self:addChild(self.remarkButton)
    self.cancelButton = ISButton:new(366, 126, 96, 32, text("Btn_Close", "Close"), self, self.close)
    self.cancelButton:initialise(); self:addChild(self.cancelButton)
    self:refresh()
end

function GodSystemPresetSlotDialog:refresh()
    local hasData = self.owner and self.owner.presetSaved[self.slot] == true
    local reason = text("EconomyAdmin_PresetEmpty", "No saved data in this slot; read is unavailable.")
    local status = hasData and text("EconomyAdmin_PresetHasData", "Saved configuration is available.") or reason
    self.statusLabel:setName(GodSystemUISafety.fitText(status, UIFont.Small, 444))
    local remark = self.owner and self.owner.presetRemarks[self.slot] or ""
    self.remarkLabel:setName(GodSystemUISafety.fitText(text("EconomyAdmin_PresetRemark", "Remark") .. ": " ..
        (remark ~= "" and remark or text("EconomyAdmin_PresetNoRemark", "(empty)")), UIFont.Small, 444))
    self.readButton:setEnable(hasData)
    self.readButton.tooltip = not hasData and reason or nil
end

function GodSystemPresetSlotDialog:onRead()
    if not self.owner or not self.owner.presetSaved[self.slot] then return end
    self.owner:requestPresetApply(self.slot)
    self:close()
end

function GodSystemPresetSlotDialog:onOverwrite()
    if self.owner then self.owner:requestPresetSave(self.slot) end
    self:close()
end

function GodSystemPresetSlotDialog:onRemark()
    if self.owner then self.owner:editPresetRemark(self.slot) end
end

function GodSystemPresetSlotDialog:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if self.owner and self.owner.presetDialog == self then self.owner.presetDialog = nil end
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
    o.presetSaved = {}
    o.presetRemarks = {}
    o.presetDialog = nil
    o.presetConfirmation = nil
    o.presetRemarkBox = nil
    o.presetRemarkSlot = nil
    return o
end

function GodSystemItemEconomyWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.presetButtons = {}
    for index = 0, 3 do
        local slot = index == 0 and GodSystemItemConfig.PRESET_DEFAULT or tostring(index)
        local button = ISButton:new(12 + index * 130, 30, 122, 28, "", self, self.onPresetButton)
        button:initialise()
        button.presetSlot = slot
        self:addChild(button)
        self.presetButtons[slot] = button
    end

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
    self.presetRemarks = (type(presets.remarks) == "table") and presets.remarks or {}
    self.presetSaved = {}
    for _, slot in ipairs(self.presetOrder) do
        if GodSystemItemConfig.isPresetSlot(slot) then self.presetSaved[slot] = true end
    end
    self.presetActive = (type(presets.active) == "string" and presets.active ~= "")
        and presets.active or GodSystemItemConfig.PRESET_DEFAULT
    if GodSystemApp.services.runtime then
        GodSystemApp.services.runtime.itemConfigPresets = {
            order = self.presetOrder, remarks = self.presetRemarks, active = self.presetActive }
    end
    for index = 0, 3 do
        local slot = index == 0 and GodSystemItemConfig.PRESET_DEFAULT or tostring(index)
        local button = self.presetButtons and self.presetButtons[slot]
        if button then
            local label = index == 0 and text("EconomyAdmin_PresetDefault", "默认")
                or (text("EconomyAdmin_PresetSlot", "预设") .. " " .. slot)
            button:setTitle((slot == self.presetActive and "[x] " or "") .. label)
        end
    end
    if self.presetDialog then self.presetDialog:refresh() end
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
    local loaded = GodSystemItemConfigPresetLibrary.load(data.itemConfig)
    if not loaded then notify(text("EconomyAdmin_PresetLibraryFailed", "Preset library unavailable")) end
    self:applyPresets(GodSystemItemConfig.presetListPayload(data.itemConfig))
end

-- Single-player preset mutations mirror the server commands: mutate the migrated
-- store, re-apply runtime pricing, persist, then republish through the service.
function GodSystemItemEconomyWindow:localPreset(op, name)
    local runtime = GodSystemApp.services.runtime
    local data = runtime.getData()
    data.itemConfig = GodSystemItemConfig.migrate(data.itemConfig, data.adminConfig)
    local config = data.itemConfig
    local loaded = GodSystemItemConfigPresetLibrary.load(config)
    if not loaded then notify(text("EconomyAdmin_PresetLibraryFailed", "Preset library unavailable")); return false, "Library" end
    local previous = GodSystemItemConfigPresetLibrary.copy(config.itemConfigPresets)
    local store, err
    if op == "save" then
        store, err = GodSystemItemConfig.savePreset(config, name)
    elseif op == "remark" then
        store, err = GodSystemItemConfig.setPresetRemark(config, name, self.pendingPresetRemark)
    else
        store = GodSystemItemConfig.applyPreset(config, name)
    end
    if not store then return false, err end
    if op ~= "apply" and not GodSystemItemConfigPresetLibrary.commit(config) then
        config.itemConfigPresets = previous
        notify(text("EconomyAdmin_PresetLibraryFailed", "Preset library unavailable"))
        return false, "Library"
    end
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

function GodSystemItemEconomyWindow:confirmPresetApply(name)
    if self.presetConfirmation then return end
    if name ~= GodSystemItemConfig.PRESET_DEFAULT then return end
    local prompt = text("EconomyAdmin_PresetDefaultConfirm", "恢复默认会覆盖当前物品配置，确定吗？")
    local modal = ISModalDialog:new(0, 0, 480, 160, prompt, true, self,
        function(target, button, slot)
            target.presetConfirmation = nil
            if button and button.internal == "YES" then target:requestPresetApply(slot) end
        end, 0, name)
    modal:initialise()
    self.presetConfirmation = modal
    GodSystemUI.presentOverlay(modal)
end

function GodSystemItemEconomyWindow:requestPresetSave(name)
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then GodSystemNetwork.send("itemConfigPresetSave", { name = name }) end
        return
    end
    if self:localPreset("save", name) then notify(text("EconomyAdmin_PresetSaved", "预设已保存")) end
end

function GodSystemItemEconomyWindow:requestPresetRemark(name, remark)
    if multiplayer() then
        if GodSystemNetwork and GodSystemNetwork.send then
            GodSystemNetwork.send("itemConfigPresetRemark", { name = name, remark = remark })
        end
        return
    end
    self.pendingPresetRemark = remark
    local ok = self:localPreset("remark", name)
    self.pendingPresetRemark = nil
    if ok then notify(text("EconomyAdmin_PresetRemarkSaved", "备注已保存")) end
end

function GodSystemItemEconomyWindow:onPresetButton(button)
    local slot = button and button.presetSlot
    if slot == GodSystemItemConfig.PRESET_DEFAULT then
        if self.presetDialog then self.presetDialog:close() end
        self:confirmPresetApply(slot)
        return
    end
    if not GodSystemItemConfig.isPresetSlot(slot) then return end
    if self.presetDialog then self.presetDialog:close() end
    local dialog = GodSystemPresetSlotDialog:new(self, slot)
    dialog:initialise()
    self.presetDialog = dialog
    GodSystemUI.presentOverlay(dialog)
end

function GodSystemItemEconomyWindow:editPresetRemark(slot)
    if self.presetRemarkBox then return end
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    local box = ISTextBox:new(math.max(12, (screenW - 420) / 2), math.max(12, (screenH - 180) / 2), 420, 180,
        text("EconomyAdmin_PresetRemarkPrompt", "输入预设备注，可留空"),
        self.presetRemarks[slot] or "", self, self.onPresetRemarkResult, 0)
    box.maxChars = 120
    box:initialise()
    self.presetRemarkBox, self.presetRemarkSlot = box, slot
    GodSystemUI.presentOverlay(box)
end

function GodSystemItemEconomyWindow:onPresetRemarkResult(button)
    local box, slot = self.presetRemarkBox, self.presetRemarkSlot
    self.presetRemarkBox, self.presetRemarkSlot = nil, nil
    if not (button and button.internal == "OK") then return end
    local remark = box and box.entry and box.entry.getInternalText and tostring(box.entry:getInternalText() or "") or ""
    self:requestPresetRemark(slot, remark)
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
    if self.presetConfirmation then
        self.presetConfirmation:destroy()
        self.presetConfirmation = nil
    end
    if self.presetDialog then self.presetDialog:close() end
    if self.presetRemarkBox then
        self.presetRemarkBox:destroy()
        self.presetRemarkBox, self.presetRemarkSlot = nil, nil
    end
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
