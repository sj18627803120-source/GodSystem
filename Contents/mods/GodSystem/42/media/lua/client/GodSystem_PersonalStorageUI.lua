require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISModalDialog"
require "GodSystem_PersonalStorageClient"

GodSystemPersonalStorageUI = GodSystemPersonalStorageUI or {}

local UI = GodSystemPersonalStorageUI
local Client = GodSystemPersonalStorageClient
local Personal = GodSystemPersonalStorage
local Storage = GodSystemStorage

UI.moduleId = "personalStorageUI"
UI.window = UI.window or nil

local colors = {
    shell = { r = 0.025, g = 0.025, b = 0.022, a = 0.97 },
    panel = { r = 0.045, g = 0.05, b = 0.048, a = 0.94 },
    border = { r = 0.58, g = 0.40, b = 0.08, a = 0.9 },
    cyan = { r = 0.15, g = 0.78, b = 0.85, a = 1 },
    text = { r = 0.86, g = 0.84, b = 0.76, a = 1 },
    muted = { r = 0.62, g = 0.64, b = 0.61, a = 1 },
}

local function text(key, fallback)
    return GodSystem and GodSystem.text and GodSystem.text(key, fallback) or fallback or key
end

local function controlDown()
    return Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LCONTROL) or isKeyDown(Keyboard.KEY_RCONTROL))
end

local function shiftDown()
    return Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
end

local function itemName(item)
    return tostring(Storage.safeCall(item, "getName", Storage.itemFullType(item)) or Storage.itemFullType(item))
end

local function itemRows(container)
    local rows = {}
    local items = Storage.safeCall(container, "getItems", nil)
    local size = Storage.integer(Storage.safeCall(items, "size", 0), 0)
    for i = 0, size - 1 do
        local item = Storage.safeCall(items, "get", nil, i)
        if item and Storage.isManualDepositItem(nil, item) then
            rows[#rows + 1] = {
                item = item,
                itemId = Storage.itemId(item),
                name = itemName(item),
                fullType = Storage.itemFullType(item),
                category = Storage.categoryOf(item),
                modName = Storage.itemModName(item),
                itemCount = Storage.integer(Storage.safeCall(item, "getCount", 1), 1),
                states = Storage.statesOf(item, container),
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.itemId) < tostring(b.itemId)
    end)
    return rows
end

local function sourceRows(player)
    local rows = { { label = text("PersonalStorage_MainInventory", "人物主背包"), container = player:getInventory(), itemId = nil } }
    local rootItems = Storage.safeCall(player:getInventory(), "getItems", nil)
    local size = Storage.integer(Storage.safeCall(rootItems, "size", 0), 0)
    for i = 0, size - 1 do
        local item = Storage.safeCall(rootItems, "get", nil, i)
        local inventory = Storage.safeCall(item, "getInventory", nil)
        if inventory and Storage.isPlayerSourceItem(player, item) then
            rows[#rows + 1] = { label = itemName(item), container = inventory, itemId = Storage.itemId(item) }
        end
    end
    return rows
end

GodSystemPersonalStorageWindow = ISCollapsableWindow:derive("GodSystemPersonalStorageWindow")

function GodSystemPersonalStorageWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = text("PersonalStorage_Title", "个人分类仓")
    o.resizable = false
    o.minimumWidth = 920
    o.minimumHeight = 600
    o.selectedInventory = {}
    o.selectedEntries = {}
    o.currentGroupKey = nil
    o.sourceIndex = 1
    o.bridgeMode = false
    o.inventoryAnchorId = nil
    o.entryAnchorId = nil
    o.stateFilter = "all"
    o.sortMode = "name"
    return o
end

function GodSystemPersonalStorageWindow:createList(x, y, w, h, handler)
    local list = ISScrollingListBox:new(x, y, w, h)
    list:initialise()
    list.itemheight = 24
    list.font = UIFont.Small
    list.drawBorder = true
    list.backgroundColor = colors.panel
    list.borderColor = colors.border
    list.doDrawItem = function(target, yy, row, alt)
        local payload = row and row.item or {}
        if alt then target:drawRect(0, yy, target.width, target.itemheight, 0.12, 0.22, 0.26, 0.26) end
        if payload.selected then target:drawRect(0, yy, target.width, target.itemheight, 0.20, 0.08, 0.50, 0.58) end
        target:drawText(tostring(row and row.text or ""), 8, yy + 4, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
        return yy + target.itemheight
    end
    list.onmousedown = handler
    self:addChild(list)
    return list
end

function GodSystemPersonalStorageWindow:createButton(x, y, w, label, action)
    local button = ISButton:new(x, y, w, 30, label, self, self.onAction)
    button.internal = action
    button:initialise()
    button.backgroundColor = { r = 0.07, g = 0.08, b = 0.075, a = 0.95 }
    button.borderColor = colors.border
    self:addChild(button)
    return button
end

function GodSystemPersonalStorageWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.statusLabel = ISLabel:new(16, 34, 18, "", colors.cyan.r, colors.cyan.g, colors.cyan.b, 1, UIFont.Small, true)
    self.statusLabel:initialise(); self:addChild(self.statusLabel)

    self.sourceCombo = ISComboBox:new(16, 60, 260, 28, self, self.onSourceChanged)
    self.sourceCombo:initialise(); self:addChild(self.sourceCombo)
    self.searchBox = ISTextEntryBox:new("", 292, 60, self.width - 480, 28)
    self.searchBox:initialise(); self.searchBox.onTextChange = function() self:rebuildLists() end; self:addChild(self.searchBox)
    self.categoryCombo = ISComboBox:new(self.width - 172, 60, 156, 28, self, self.onCategoryChanged)
    self.categoryCombo:initialise(); self.categoryCombo:addOptionWithData(text("Storage_FilterAll", "全部分类"), "all")
    for i = 1, #Personal.Categories do
        local category = Personal.Categories[i]
        self.categoryCombo:addOptionWithData(text("PersonalStorage_Category_" .. category, category), category)
    end
    self:addChild(self.categoryCombo)

    self.stateCombo = ISComboBox:new(16, 96, 180, 28, self, self.onFilterChanged)
    self.stateCombo:initialise()
    for _, state in ipairs({ "all", "fresh", "stale", "rotten", "chilled", "frozen", "damaged", "favorite", "simplified" }) do
        self.stateCombo:addOptionWithData(text(state == "simplified" and "PersonalStorage_State_simplified" or "Storage_State_" .. state, state), state)
    end
    self:addChild(self.stateCombo)
    self.sortCombo = ISComboBox:new(206, 96, 210, 28, self, self.onFilterChanged)
    self.sortCombo:initialise()
    for _, mode in ipairs({ "name", "count", "fullType", "mod" }) do
        self.sortCombo:addOptionWithData(text("PersonalStorage_Sort_" .. mode, mode), mode)
    end
    self:addChild(self.sortCombo)

    local mid = math.floor(self.width * 0.45)
    local upperHeight = math.floor((self.height - 237) * 0.48)
    self.inventoryList = self:createList(16, 136, mid - 24, self.height - 222, function(_, row) self:onInventoryRow(row) end)
    self.groupList = self:createList(mid, 136, self.width - mid - 16, upperHeight, function(_, row) self:onGroupRow(row) end)
    self.entryList = self:createList(mid, 148 + upperHeight, self.width - mid - 16,
        self.height - (234 + upperHeight), function(_, row) self:onEntryRow(row) end)

    self.depositButton = self:createButton(16, self.height - 70, 180, text("PersonalStorage_DepositSelected", "存入所选"), "deposit")
    self.withdrawButton = self:createButton(206, self.height - 70, 180, text("PersonalStorage_WithdrawSelected", "取出所选"), "withdraw")
    self.buyButton = self:createButton(396, self.height - 70, 230, text("PersonalStorage_BuyGeneral", "购买通用容量 10000"), "buyGeneral")
    self.refreshButton = self:createButton(self.width - 166, self.height - 70, 150, text("Storage_Refresh", "刷新"), "refresh")
    self:rebuildSources()
    Client.requestState()
    self:rebuild(true)
end

function GodSystemPersonalStorageWindow:prerender()
    ISCollapsableWindow.prerender(self)
    self:drawRect(0, 16, self.width, self.height - 16, colors.shell.a, colors.shell.r, colors.shell.g, colors.shell.b)
    self:drawRectBorder(1, 17, self.width - 2, self.height - 18, colors.border.a, colors.border.r, colors.border.g, colors.border.b)
end

function GodSystemPersonalStorageWindow:onResize()
    ISCollapsableWindow.onResize(self)
    self:setWidth(math.max(self.minimumWidth, self.width)); self:setHeight(math.max(self.minimumHeight, self.height))
end

function GodSystemPersonalStorageWindow:rebuildSources()
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    self.sources = sourceRows(player)
    self.sourceCombo:clear()
    for i = 1, #self.sources do self.sourceCombo:addOptionWithData(self.sources[i].label, i) end
    self.sourceCombo.selected = math.min(self.sourceIndex or 1, #self.sources)
end

function GodSystemPersonalStorageWindow:onSourceChanged()
    self.sourceIndex = self.sourceCombo.selected or 1
    self.selectedInventory = {}
    self:rebuildInventory()
end

function GodSystemPersonalStorageWindow:onCategoryChanged()
    self:rebuildLists()
end

function GodSystemPersonalStorageWindow:onFilterChanged()
    self.stateFilter = self:comboData(self.stateCombo, "all")
    self.sortMode = self:comboData(self.sortCombo, "name")
    self:rebuildLists()
end

function GodSystemPersonalStorageWindow:comboData(combo, fallback)
    if combo and combo.getOptionData then return combo:getOptionData(combo.selected) or fallback end
    local option = combo and combo.options and combo.options[combo.selected]
    return option and option.data or fallback
end

function GodSystemPersonalStorageWindow:query()
    return string.lower(tostring(self.searchBox and self.searchBox:getText() or ""))
end

function GodSystemPersonalStorageWindow:selectedCategory()
    return self:comboData(self.categoryCombo, "all")
end

function GodSystemPersonalStorageWindow:matches(row)
    local category = self:selectedCategory()
    if category ~= "all" and tostring(row.category or "") ~= category then return false end
    local state = self.stateFilter or "all"
    if state ~= "all" then
        local matched = state == "simplified" and (row.simplified == true or (tonumber(row.simplified) or 0) > 0)
        for i = 1, #(row.states or {}) do if tostring(row.states[i]) == state then matched = true; break end end
        if not matched then return false end
    end
    local query = self:query()
    if query == "" then return true end
    local source = string.lower(table.concat({ tostring(row.name or row.displayName or ""), tostring(row.fullType or ""), tostring(row.modName or ""), tostring(row.category or ""), table.concat(row.states or {}, " ") }, " "))
    return string.find(source, query, 1, true) ~= nil
end

function GodSystemPersonalStorageWindow:sortRows(rows)
    local mode = self.sortMode or "name"
    table.sort(rows, function(a, b)
        local av, bv
        if mode == "count" then av, bv = tonumber(a.items or a.itemCount or a.entries) or 0, tonumber(b.items or b.itemCount or b.entries) or 0
        elseif mode == "fullType" then av, bv = tostring(a.fullType or ""), tostring(b.fullType or "")
        elseif mode == "mod" then av, bv = tostring(a.modName or ""), tostring(b.modName or "")
        else av, bv = tostring(a.name or a.displayName or ""), tostring(b.name or b.displayName or "") end
        if av ~= bv then return av < bv end
        return tostring(a.itemId or a.entryId or a.groupKey or "") < tostring(b.itemId or b.entryId or b.groupKey or "")
    end)
    return rows
end

function GodSystemPersonalStorageWindow:rebuildInventory()
    self.inventoryList:clear()
    local source = self.sources and self.sources[self.sourceIndex or 1]
    local rows = {}
    for _, row in ipairs(itemRows(source and source.container)) do
        if self:matches(row) then
            rows[#rows + 1] = row
        end
    end
    self:sortRows(rows)
    for _, row in ipairs(rows) do
        row.selected = self.selectedInventory[row.itemId] == true
        self.inventoryList:addItem(row.name .. "  [" .. row.category .. "]", row)
    end
end

function GodSystemPersonalStorageWindow:rebuildGroups()
    self.groupList:clear()
    local summary = Client.getSummary() or {}
    local rows = {}
    for i = 1, #(summary.groups or {}) do
        local row = summary.groups[i]
        if self:matches(row) then
            rows[#rows + 1] = row
        end
    end
    self:sortRows(rows)
    for _, row in ipairs(rows) do
        self.groupList:addItem(tostring(row.name) .. " x" .. tostring(row.entries) .. "  [" .. tostring(row.category) .. "]", row)
    end
end

function GodSystemPersonalStorageWindow:rebuildEntries()
    self.entryList:clear()
    if not self.currentGroupKey then return end
    local page = Client.details[tostring(self.currentGroupKey)]
    local rows = {}
    for i = 1, #((page and page.rows) or {}) do if self:matches(page.rows[i]) then rows[#rows + 1] = page.rows[i] end end
    self:sortRows(rows)
    for i = 1, #rows do
        local row = rows[i]
        row.selected = self.selectedEntries[row.entryId] == true
        local suffix = row.simplified and "  [" .. text("PersonalStorage_Simplified", "简化保存") .. "]" or ""
        self.entryList:addItem(tostring(row.displayName) .. "  #" .. tostring(row.entryId) .. suffix, row)
    end
end

function GodSystemPersonalStorageWindow:updateStatus()
    local summary = Client.getSummary() or {}
    local usage = summary.usage or {}
    self.statusLabel.name = text("PersonalStorage_Status", "个人仓") .. ": " .. tostring(usage.total or 0)
        .. " | " .. text("PersonalStorage_General", "通用") .. " " .. tostring(usage.generalUsed or 0) .. "/" .. tostring(usage.generalCapacity or 0)
        .. " | " .. text("PersonalStorage_Simplified", "简化保存") .. " " .. tostring(summary.simplifiedEntries or 0)
end

function GodSystemPersonalStorageWindow:rebuild(preserve)
    if not preserve then self.selectedInventory = {}; self.selectedEntries = {} end
    self:rebuildInventory(); self:rebuildGroups(); self:rebuildEntries(); self:updateStatus()
end

function GodSystemPersonalStorageWindow:rebuildLists()
    self:rebuild(true)
end

function GodSystemPersonalStorageWindow:onInventoryRow(row)
    local payload = row and row.item
    if not payload then return end
    local control = controlDown()
    local shift = shiftDown()
    if shift and self.inventoryAnchorId then
        if not control then self.selectedInventory = {} end
        local first, last
        for i = 1, #self.inventoryList.items do
            local item = self.inventoryList.items[i].item
            if tostring(item.itemId) == tostring(self.inventoryAnchorId) then first = i end
            if tostring(item.itemId) == tostring(payload.itemId) then last = i end
        end
        if first and last then
            for i = math.min(first, last), math.max(first, last) do
                self.selectedInventory[self.inventoryList.items[i].item.itemId] = true
            end
        end
    else
        if not control then self.selectedInventory = {} end
        self.selectedInventory[payload.itemId] = not self.selectedInventory[payload.itemId]
        self.inventoryAnchorId = payload.itemId
    end
    self:rebuildInventory()
end

function GodSystemPersonalStorageWindow:onGroupRow(row)
    local payload = row and row.item
    if not payload then return end
    self.currentGroupKey = payload.groupKey
    self.selectedEntries = {}
    Client.requestDetails(payload.groupKey, 0, 100)
end

function GodSystemPersonalStorageWindow:onEntryRow(row)
    local payload = row and row.item
    if not payload then return end
    local control = controlDown()
    local shift = shiftDown()
    if shift and self.entryAnchorId then
        if not control then self.selectedEntries = {} end
        local first, last
        for i = 1, #self.entryList.items do
            local item = self.entryList.items[i].item
            if tostring(item.entryId) == tostring(self.entryAnchorId) then first = i end
            if tostring(item.entryId) == tostring(payload.entryId) then last = i end
        end
        if first and last then
            for i = math.min(first, last), math.max(first, last) do
                self.selectedEntries[self.entryList.items[i].item.entryId] = true
            end
        end
    else
        if not control then self.selectedEntries = {} end
        self.selectedEntries[payload.entryId] = not self.selectedEntries[payload.entryId]
        self.entryAnchorId = payload.entryId
    end
    self:rebuildEntries()
end

function GodSystemPersonalStorageWindow:selectedKeys(source)
    local rows = {}
    for key, selected in pairs(source or {}) do if selected then rows[#rows + 1] = key end end
    table.sort(rows)
    return rows
end

function GodSystemPersonalStorageWindow:onSimplifiedConfirm(button, payload)
    if button and button.internal == "YES" then Client.deposit(payload.itemIds, true) end
end

function GodSystemPersonalStorageWindow:depositSelected()
    local itemIds = self:selectedKeys(self.selectedInventory)
    if #itemIds == 0 then return end
    local simplified = {}
    for _, row in ipairs(Client.previewDeposit(itemIds)) do if row.simplified then simplified[#simplified + 1] = row end end
    if #simplified == 0 then Client.deposit(itemIds, false); return end
    local names = {}
    for i = 1, math.min(#simplified, 8) do names[#names + 1] = tostring(simplified[i].name) end
    local message = text("PersonalStorage_SimplifiedConfirm", "以下物品包含无法完整保存的第三方状态，确认后将简化保存：")
        .. "\n" .. table.concat(names, "、") .. ( #simplified > 8 and "…" or "")
    local modal = ISModalDialog:new(self.x + 120, self.y + 120, 560, 240, message, true, self, self.onSimplifiedConfirm, 0, { itemIds = itemIds })
    modal:initialise(); modal:addToUIManager()
end

function GodSystemPersonalStorageWindow:onBuyConfirm(button)
    if button and button.internal == "YES" then Client.buyGeneral() end
end

function GodSystemPersonalStorageWindow:onAction(button)
    local action = button and button.internal
    if action == "deposit" then self:depositSelected()
    elseif action == "withdraw" then
        local entryIds = self:selectedKeys(self.selectedEntries)
        local source = self.sources and self.sources[self.sourceIndex or 1]
        if self.bridgeMode then Client.bridgeWithdraw(entryIds) else Client.withdraw(entryIds, source and source.itemId) end
    elseif action == "buyGeneral" then
        local summary = Client.getSummary() or {}; local usage = summary.usage or {}
        local message = text("PersonalStorage_BuyConfirm", "确认花费 10000 系统币购买 10 点通用容量？")
            .. "\n" .. tostring(usage.generalCapacity or 0) .. " → " .. tostring((usage.generalCapacity or 0) + Personal.GeneralPurchaseCapacity)
        local modal = ISModalDialog:new(self.x + 150, self.y + 130, 520, 210, message, true, self, self.onBuyConfirm, 0)
        modal:initialise(); modal:addToUIManager()
    elseif action == "refresh" then Client.requestState(); self:rebuildSources() end
end

function GodSystemPersonalStorageWindow:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if UI.window == self then UI.window = nil end
end

function UI.open(options)
    options = type(options) == "table" and options or {}
    local summary = Client.getSummary()
    if not summary then
        Client.requestState()
        if GodSystem and GodSystem.notify then
            GodSystem.notify(text("PersonalStorage_Syncing", "个人仓状态同步中，请稍后再试"))
        end
        return nil
    end
    if summary.unlocked ~= true then
        if GodSystem and GodSystem.notify then
            GodSystem.notify(text("PersonalStorage_Locked", "请先使用一张分类扩容许可，或在系统仓库页购买通用容量"))
        end
        return nil
    end
    if UI.window and UI.window:getIsVisible() then UI.window:bringToTop(); return UI.window end
    local width, height = math.min(1180, getCore():getScreenWidth() - 60), math.min(760, getCore():getScreenHeight() - 60)
    local window = GodSystemPersonalStorageWindow:new(math.floor((getCore():getScreenWidth() - width) / 2),
        math.floor((getCore():getScreenHeight() - height) / 2), width, height)
    window.bridgeMode = options.bridgeMode == true
    window:initialise(); window:addToUIManager(); window:setVisible(true)
    if window.bridgeMode then
        window.depositButton:setVisible(false)
        window.sourceCombo:setVisible(false)
        window.inventoryList:setVisible(false)
        window.groupList:setX(16); window.groupList:setWidth(window.width - 32)
        window.entryList:setX(16); window.entryList:setWidth(window.width - 32)
        window.withdrawButton:setTitle(text("PersonalStorage_ToPhysical", "转入实体网络"))
        window.title = text("PersonalStorage_BridgeTitle", "个人仓 → 实体网络")
    end
    UI.window = window
    return window
end

function UI.openBridge()
    return UI.open({ bridgeMode = true })
end

function UI.close()
    if UI.window then UI.window:close() end
end

function UI.onState()
    if UI.window then UI.window:rebuild(true) end
end

function UI.onDetails(groupKey)
    if UI.window and tostring(UI.window.currentGroupKey or "") == tostring(groupKey or "") then UI.window:rebuildEntries() end
end

function UI.onOperationResult(_, outcome)
    if UI.window and outcome and outcome.ok then
        UI.window.selectedInventory = {}; UI.window.selectedEntries = {}
        Client.requestState(); UI.window:rebuildSources(); UI.window:rebuild(true)
    end
end

function UI.health()
    return { ok = Client ~= nil, code = Client and "ok" or "clientMissing", moduleId = UI.moduleId }
end

return UI
