if (isClient and isClient()) or (isServer and isServer()) then return end

require "GodSystem_Core"
require "GodSystem_Companion"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

GodSystemCompanionUI = GodSystemCompanionUI or {}
GodSystemCompanionShortcutWindow = ISCollapsableWindow:derive("GodSystemCompanionShortcutWindow")

local UI = GodSystemCompanionUI
local Companion = GodSystemCompanion

local function textKey(key, fallback)
    return GodSystem.text(key, fallback)
end

local function buttonStyle(button, selected)
    button.backgroundColor = selected and { r = 0.05, g = 0.23, b = 0.38, a = 0.95 } or { r = 0.06, g = 0.09, b = 0.13, a = 0.92 }
    button.backgroundColorMouseOver = { r = 0.07, g = 0.31, b = 0.50, a = 0.95 }
    button.borderColor = selected and { r = 0.18, g = 0.82, b = 1.0, a = 1 } or { r = 0.25, g = 0.48, b = 0.65, a = 0.9 }
    button.textColor = { r = 0.72, g = 0.92, b = 1.0, a = 1 }
end

function GodSystemCompanionShortcutWindow:new(x, y)
    local o = ISCollapsableWindow.new(self, x, y, 452, 184)
    o.title = textKey("Companion_ShortcutTitle", "Robot controls")
    o.resizable = false
    o.actionButtons = {}
    o.lastSecond = -1
    return o
end

function GodSystemCompanionShortcutWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local rows = {
        {
            { "active", "Companion_ActionActive", "Active" },
            { "defensive", "Companion_ActionDefensive", "Defensive" },
            { "ceasefire", "Companion_ActionCeasefire", "Ceasefire" },
        },
        {
            { "follow3", "Companion_ActionFollow3", "3m" },
            { "follow5", "Companion_ActionFollow5", "5m" },
            { "follow10", "Companion_ActionFollow10", "10m" },
            { "guard", "Companion_ActionGuard", "Guard" },
        },
        {
            { "sight", "Companion_ActionSight", "Sight" },
            { "guardian", "Companion_ActionGuardian", "Guardian" },
            { "recall", "Companion_ActionRecall", "Recall" },
            { "visible", "Companion_ActionVisible", "Visible" },
        },
    }
    local margin, gap, height = 10, 6, 36
    local available = self.width - margin * 2
    for rowIndex = 1, #rows do
        local row = rows[rowIndex]
        local width = math.floor((available - gap * (#row - 1)) / #row)
        for colIndex = 1, #row do
            local slot = row[colIndex]
            local x = margin + (colIndex - 1) * (width + gap)
            local y = 34 + (rowIndex - 1) * (height + 7)
            local button = ISButton:new(x, y, width, height, textKey(slot[2], slot[3]), self, self.onAction)
            button.internal = slot[1]
            button.baseKey = slot[2]
            button.baseFallback = slot[3]
            button:initialise()
            buttonStyle(button, false)
            self:addChild(button)
            self.actionButtons[#self.actionButtons + 1] = button
        end
    end
    self:refreshButtons()
end

function GodSystemCompanionShortcutWindow:refreshButtons()
    local data = GodSystem.getCompanionData()
    if not data or not data.unlocked then self:close(); return end
    for i = 1, #self.actionButtons do
        local button = self.actionButtons[i]
        local action = button.internal
        if action then
            local title = textKey(button.baseKey, button.baseFallback)
            local selected = action == data.combatMode or action == data.followMode
            if action == "guardian" then
                selected = data.guardianEnabled == true
                local cooldown = math.ceil(Companion.remainingCooldown("guardian"))
                if cooldown > 0 then title = title .. " " .. tostring(cooldown) .. "s" end
                button.enable = data.unlocks.guardian == true
            elseif action == "sight" then
                local cooldown = math.ceil(Companion.remainingCooldown("sight"))
                if cooldown > 0 then title = title .. " " .. tostring(cooldown) .. "s" end
                button.enable = data.unlocks.sight == true
            elseif action == "visible" then
                selected = data.visible == true
                title = data.visible and textKey("Companion_ActionHide", "Hide") or textKey("Companion_ActionShow", "Show")
                button.enable = true
            else
                button.enable = true
            end
            button:setTitle(title)
            buttonStyle(button, selected)
        end
    end
end

function GodSystemCompanionShortcutWindow:update()
    if ISCollapsableWindow.update then ISCollapsableWindow.update(self) end
    local second = math.floor((getTimestampMs and getTimestampMs() or 0) / 1000)
    if second ~= self.lastSecond then self.lastSecond = second; self:refreshButtons() end
end

function GodSystemCompanionShortcutWindow:prerender()
    ISCollapsableWindow.prerender(self)
    self:drawRect(0, 16, self.width, self.height - 16, 0.94, 0.035, 0.055, 0.075)
    self:drawRectBorder(1, 17, self.width - 2, self.height - 18, 0.95, 0.15, 0.55, 0.78)
end

function GodSystemCompanionShortcutWindow:onAction(button)
    local action = button and button.internal
    if action == "active" or action == "defensive" or action == "ceasefire" then
        Companion.setCombatMode(action)
    elseif action == "follow3" or action == "follow5" or action == "follow10" or action == "guard" then
        Companion.setFollowMode(action)
    elseif action == "sight" then
        Companion.activateSight()
    elseif action == "guardian" then
        Companion.toggleGuardian()
    elseif action == "recall" then
        Companion.recall()
    elseif action == "visible" then
        Companion.toggleVisible()
    end
    self:refreshButtons()
end

function GodSystemCompanionShortcutWindow:close()
    local data = GodSystem.getCompanionData()
    if data and data.ui then
        data.ui.shortcutVisible = false
        data.ui.shortcutX = math.floor(self.x or 0)
        data.ui.shortcutY = math.floor(self.y or 0)
        GodSystem.save()
    end
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if UI.shortcutWindow == self then UI.shortcutWindow = nil end
end

function UI.setShortcutVisible(visible, owner)
    local data = GodSystem.getCompanionData()
    if not data or not data.unlocked then return false end
    visible = visible == true
    if not visible then
        if UI.shortcutWindow then UI.shortcutWindow:close() end
        data.ui.shortcutVisible = false
        GodSystem.save()
        return true
    end
    if UI.shortcutWindow and UI.shortcutWindow:getIsVisible() then return true end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.floor(tonumber(data.ui.shortcutX) or ((owner and owner.x or screenW / 2) + 40))
    local y = math.floor(tonumber(data.ui.shortcutY) or ((owner and owner.y or screenH / 2) + 60))
    x = math.max(0, math.min(screenW - 452, x))
    y = math.max(0, math.min(screenH - 184, y))
    local window = GodSystemCompanionShortcutWindow:new(x, y)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    UI.shortcutWindow = window
    data.ui.shortcutVisible = true
    GodSystem.save()
    return true
end

function UI.toggleShortcut(owner)
    return UI.setShortcutVisible(not (UI.shortcutWindow and UI.shortcutWindow:getIsVisible()), owner)
end

local function restoreShortcut()
    local data = GodSystem.getCompanionData()
    if data and data.unlocked and data.ui and data.ui.shortcutVisible then UI.setShortcutVisible(true, nil) end
end

if Events.OnGameStart then Events.OnGameStart.Add(restoreShortcut) end

return GodSystemCompanionUI
