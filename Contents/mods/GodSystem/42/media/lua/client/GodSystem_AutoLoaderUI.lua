require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "GodSystem_AutoLoader"
require "GodSystem_AutoLoaderClient"

GodSystemAutoLoaderUI = GodSystemAutoLoaderUI or {}

local UI = GodSystemAutoLoaderUI
local AutoLoader = GodSystemAutoLoader
local Client = GodSystemAutoLoaderClient

UI.fixedWidth = 500
UI.fixedHeight = 420
UI.window = UI.window or nil
UI.loaderId = UI.loaderId or nil

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function textureForType(fullType)
    if not instanceItem then return nil end
    local ok, item = pcall(instanceItem, fullType)
    if not ok or not item then return nil end
    return AutoLoader.safeCall(item, "getTex", nil) or AutoLoader.safeCall(item, "getTexture", nil)
end

GodSystemAutoLoaderWindow = ISCollapsableWindow:derive("GodSystemAutoLoaderWindow")

function GodSystemAutoLoaderWindow:new(x, y, loaderId, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, UI.fixedWidth, UI.fixedHeight)
    o.resizable = false
    o.loaderId = tostring(loaderId or "")
    o.playerNum = playerNum or 0
    o.selectedFullType = nil
    o.title = text("AutoLoader_Title", "System auto-loader")
    return o
end

function GodSystemAutoLoaderWindow:createButton(x, y, width, label, internal)
    local button = ISButton:new(x, y, width, 34, label, self, self.onAction)
    button.internal = internal
    button:initialise()
    button.backgroundColor = { r = 0.06, g = 0.11, b = 0.14, a = 0.92 }
    button.backgroundColorMouseOver = { r = 0.08, g = 0.27, b = 0.38, a = 0.96 }
    button.borderColor = { r = 0.16, g = 0.55, b = 0.72, a = 0.82 }
    self:addChild(button)
    return button
end

function GodSystemAutoLoaderWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.statusLabel = ISLabel:new(14, 34, 20, "", 0.62, 0.82, 0.90, 1, UIFont.Small, true)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    self.list = ISScrollingListBox:new(14, 58, 472, 274)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 48
    self.list:setOnMouseDownFunction(self, self.onSelection)
    self.list.doDrawItem = function(list, y, row, alternate) return self:drawAmmoRow(list, y, row, alternate) end
    self:addChild(self.list)

    self.depositButton = self:createButton(14, 344, 144, text("AutoLoader_DepositAll", "Store all loose ammo"), "deposit")
    self.fillButton = self:createButton(166, 344, 132, text("AutoLoader_FillAll", "Fill all magazines"), "fill")
    self.amountEntry = ISTextEntryBox:new("100", 306, 344, 58, 34)
    self.amountEntry:initialise()
    self.amountEntry:instantiate()
    self.amountEntry:setOnlyNumbers(true)
    self.amountEntry:setTooltip(text("AutoLoader_WithdrawAmount", "Withdraw amount (1-500)"))
    self:addChild(self.amountEntry)
    self.withdrawButton = self:createButton(372, 344, 114, text("AutoLoader_Withdraw", "Withdraw"), "withdraw")
    self:rebuild(Client.states[self.loaderId])
end

function GodSystemAutoLoaderWindow:drawAmmoRow(list, y, row, alternate)
    if not row then return y end
    local payload = row.item or {}
    if payload.kind ~= "ammo" then
        list:drawText(tostring(payload.text or row.text or ""), 10, y + 15, 0.54, 0.66, 0.70, 1, UIFont.Small)
        return y + row.height
    end
    if self.selectedFullType == payload.fullType then
        list:drawRect(0, y, list.width, row.height, 0.82, 0.04, 0.24, 0.34)
    elseif alternate then
        list:drawRect(0, y, list.width, row.height, 0.28, 0.03, 0.07, 0.09)
    end
    if payload.texture then list:drawTextureScaledAspect(payload.texture, 7, y + 7, 32, 32, 1, 1, 1, 1) end
    local nameColor = payload.available and { 0.84, 0.91, 0.94 } or { 0.88, 0.38, 0.30 }
    list:drawText(tostring(payload.name or payload.fullType), 47, y + 5, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)
    local status = tostring(payload.count or 0) .. "/" .. tostring(payload.capacity or 0)
    if not payload.available then status = status .. " | " .. text("AutoLoader_Unavailable", "Unavailable") end
    list:drawText(status, 47, y + 23, 0.50, 0.68, 0.76, 1, UIFont.Small)
    local barX, barY, barW = 286, y + 29, math.max(40, list.width - 300)
    list:drawRect(barX, barY, barW, 8, 0.82, 0.03, 0.05, 0.06)
    local ratio = math.max(0, math.min(1, (tonumber(payload.count) or 0) / math.max(1, tonumber(payload.capacity) or 1)))
    list:drawRect(barX, barY, barW * ratio, 8, 0.95, 0.04, 0.46, 0.68)
    return y + row.height
end

function GodSystemAutoLoaderWindow:onSelection()
    local row = self.list.items[self.list.selected]
    local payload = row and row.item or nil
    self.selectedFullType = payload and payload.kind == "ammo" and payload.fullType or nil
    self:updateButtons()
end

function GodSystemAutoLoaderWindow:updateButtons()
    local row = self.list.items[self.list.selected]
    local payload = row and row.item or nil
    self.withdrawButton.enable = payload ~= nil and payload.kind == "ammo" and payload.available == true and (payload.count or 0) > 0
end

function GodSystemAutoLoaderWindow:loader()
    local player = Client.player(self.playerNum)
    return AutoLoader.findCarriedItem(player, self.loaderId)
end

function GodSystemAutoLoaderWindow:onAction(button)
    local loader = self:loader()
    if button.internal == "deposit" then
        Client.startDeposit(loader or self.loaderId, self.playerNum)
    elseif button.internal == "fill" then
        Client.manualFill(loader or self.loaderId, self.playerNum)
    elseif button.internal == "withdraw" then
        local amount = math.max(1, math.min(500, math.floor(tonumber(self.amountEntry:getText()) or 100)))
        self.amountEntry:setText(tostring(amount))
        if self.selectedFullType then Client.withdraw(loader or self.loaderId, self.selectedFullType, amount, self.playerNum) end
    end
end

function GodSystemAutoLoaderWindow:rebuild(state)
    if not self.list then return end
    local selected = self.selectedFullType
    self.list:clear()
    self.list.selected = 0
    state = type(state) == "table" and state or { total = 0, capacity = AutoLoader.getCapacity(), ammo = {} }
    self.statusLabel.name = text("AutoLoader_StoredTotal", "Stored rounds: {1}"):gsub("{1}", tostring(state.total or 0))
    for index = 1, #(state.ammo or {}) do
        local source = state.ammo[index]
        local payload = {
            kind = "ammo",
            fullType = tostring(source.fullType or ""),
            name = tostring(source.name or source.fullType or ""),
            count = math.max(0, math.floor(tonumber(source.count) or 0)),
            capacity = math.max(1, math.floor(tonumber(source.capacity) or state.capacity or 1)),
            available = source.available == true,
            texture = source.available == true and textureForType(source.fullType) or nil,
        }
        self.list:addItem(payload.name, payload)
        if payload.fullType == selected then self.list.selected = #self.list.items end
    end
    if #self.list.items <= 0 then self.list:addItem(text("AutoLoader_Empty", "No stored ammo"), { kind = "empty", text = text("AutoLoader_Empty", "No stored ammo") }) end
    if self.list.selected <= 0 then self.selectedFullType = nil end
    self:updateButtons()
end

function GodSystemAutoLoaderWindow:close()
    ISCollapsableWindow.close(self)
    if UI.window == self then UI.window = nil; UI.loaderId = nil end
end

function UI.open(loader, playerNum)
    local loaderId = AutoLoader.itemId(loader) or tostring(loader or "")
    if loaderId == "" then return nil end
    if UI.window and UI.window.loaderId ~= loaderId then UI.window:close() end
    if UI.window then
        UI.window:setVisible(true)
        UI.window:addToUIManager()
        UI.window:rebuild(Client.states[loaderId])
        return UI.window
    end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(12, math.floor((screenW - UI.fixedWidth) / 2))
    local y = math.max(12, math.floor((screenH - UI.fixedHeight) / 2))
    local window = GodSystemAutoLoaderWindow:new(x, y, loaderId, playerNum)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    UI.window = window
    UI.loaderId = loaderId
    return window
end

function UI.onState(loaderId, state, ok, code)
    if not UI.window or tostring(loaderId or "") ~= tostring(UI.window.loaderId or "") then return end
    if ok then UI.window:rebuild(state) else UI.window.statusLabel.name = text("AutoLoader_Error_NotCarried", "The auto-loader is no longer carried") end
end

function UI.onResult(action, ok, code)
    if not UI.window then return end
    if action == "startDeposit" and ok then UI.window.statusLabel.name = text("AutoLoader_DepositStarted", "Deposit started")
    elseif not ok then UI.window.statusLabel.name = Client.text(Client.codeKey(code), tostring(code or "")) end
end

return UI
