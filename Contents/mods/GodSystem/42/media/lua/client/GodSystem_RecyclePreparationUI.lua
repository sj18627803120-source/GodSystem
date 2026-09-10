require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"

GodSystemRecyclePreparationUI = GodSystemRecyclePreparationUI or {}
local UI = GodSystemRecyclePreparationUI
local function text(key, fallback, a, b)
    local value = GodSystemApp.services.runtime.text(key, fallback)
    value = tostring(value):gsub("{1}", tostring(a or "")):gsub("{2}", tostring(b or ""))
    return value
end

GodSystemRecyclePreparationWindow = ISCollapsableWindow:derive("GodSystemRecyclePreparationWindow")
local Window = GodSystemRecyclePreparationWindow

function Window:new(job)
    local x = math.max(20, (getCore():getScreenWidth() - 600) / 2)
    local y = math.max(20, (getCore():getScreenHeight() - 300) / 2)
    local o = ISCollapsableWindow.new(self, x, y, 600, 300)
    o.job, o.resizable = job, false
    o.title = text("RecyclePrep_Title", "Prepare batch operation")
    return o
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.lines = {}
    for i = 1, 6 do
        local label = ISLabel:new(16, 38 + (i - 1) * 29, 22, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        label:initialise()
        self:addChild(label)
        self.lines[i] = label
    end
    self.confirmButton = ISButton:new(320, 248, 126, 32, text("RecyclePrep_Confirm", "Confirm"), self, self.onAction)
    self.confirmButton.internal = "confirm"
    self.confirmButton:initialise()
    self:addChild(self.confirmButton)
    self.cancelButton = ISButton:new(458, 248, 126, 32, text("RecyclePrep_Cancel", "Cancel"), self, self.onAction)
    self.cancelButton.internal = "cancel"
    self.cancelButton:initialise()
    self:addChild(self.cancelButton)
    self:refresh()
end

function Window:refresh()
    if not self.lines then return end
    local job = self.job
    local ready = job.status == "ready"
    local phase = ready and text("RecyclePrep_Ready", "Ready to confirm")
        or job.status == "verifying" and text("RecyclePrep_Verifying", "Checking for changes")
        or text("RecyclePrep_Analyzing", "Analyzing selection")
    self.lines[1].name = phase .. " (" .. tostring(math.min(job.cursor - 1, #job.snapshot.items)) .. "/" .. tostring(#job.snapshot.items) .. ")"
    self.lines[2].name = text("Context_EligibleSummary", "Eligible: {1}; skipped: {2}", #job.items, job.skipped)
    if job.mode == "listOnly" then
        self.lines[3].name = text("RecyclePrep_Cost", "List {1} types; fee: {2} coins", job.typeCount, job.cost)
    elseif job.mode == "rangeFilter" then
        self.lines[3].name = text("RecyclePrep_Range", "New types: {1}; existing/over limit: {2}", #job.rangeTypes, job.rangeSkipped)
    else
        self.lines[3].name = text("RecyclePrep_Settlement", "Final reward is checked at settlement")
    end
    self.lines[4].name = job.reader and text("RecyclePrep_ContentProgress", "Container checking steps: {1}", job.reader.steps or 0)
        or job.hasContents and text("RecyclePrep_Contents", "Warning: non-empty containers are selected") or ""
    self.lines[5].name = job.hasContents and text("RecyclePrep_Destroy", "Recycling destroys all contents; confirm only if intended") or ""
    self.lines[6].name = text("RecyclePrep_NoChanges", "No items are moved or traded before confirmation")
    self.confirmButton.enable = ready
end

function Window:onAction(button)
    if button.internal == "confirm" then GodSystemRecyclePreparation.confirm(self.job)
    else GodSystemRecyclePreparation.cancel(self.job) end
end

function Window:close()
    GodSystemRecyclePreparation.cancel(self.job)
end

function UI.dismiss(job)
    local window = job.window
    job.window = nil
    if window then ISCollapsableWindow.close(window) end
end

function UI.update(job)
    if job.window then job.window:refresh() end
end

function UI.open(job)
    local window = Window:new(job)
    job.window = window
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:setAlwaysOnTop(true)
    window:bringToTop()
end

return UI
