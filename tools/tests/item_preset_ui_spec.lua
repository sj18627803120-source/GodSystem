assert(loadstring(readFixture("terminal_fixture.lua")))()
assert(loadstring(readSource("shared/GodSystem_ItemConfig.lua")))()
assert(loadstring(readSource("shared/GodSystem_ItemConfigPresetLibrary.lua")))()

local fileText = ""
getFileReader = function()
    local offset = 1
    return { readLine = function()
        if offset > #fileText then return nil end
        local finish = fileText:find("\n", offset, true) or (#fileText + 1)
        local line = fileText:sub(offset, finish - 1)
        offset = finish + 1
        return line
    end, close = function() end }
end
getFileWriter = function()
    local parts = {}
    return { write = function(_, part) parts[#parts + 1] = part end,
        close = function() fileText = table.concat(parts) end }
end

GodSystemApp.services.itemConfig = {
    MAX_RESULTS = 20,
    execute = function() end,
    getViewModel = function() return { allowed = true, page = { rows = {} }, details = {} } end,
    subscribe = function() return function() end end,
    handleChanged = function() end,
}
ISTextBox = ISPanel:derive("ISTextBox")
function ISTextBox:new(x, y, width, height, prompt, value, target, callback)
    local box = ISPanel.new(self, x, y, width, height)
    box.entry = { getInternalText = function() return box.value end }
    box.value, box.target, box.callback = value, target, callback
    return box
end
function ISTextBox:destroy() self:setVisible(false); self:removeFromUIManager() end
assert(loadstring(readSource("client/GodSystem_ItemEconomyUI.lua")))()

local window = GodSystemItemEconomyUI.open()
local function answer(internal)
    local modal = window.presetConfirmation
    assert(modal, "a preset restore must open a confirmation")
    modal.callback(modal.target, { internal = internal }, modal.payload)
end
assert(window.presetButtons.default and window.presetButtons["1"] and
    window.presetButtons["2"] and window.presetButtons["3"], "four fixed buttons are visible")
window:onPresetButton(window.presetButtons["1"])
local dialog = window.presetDialog
assert(dialog and dialog.readButton.enable == false and dialog.readButton.tooltip,
    "an empty slot disables load and explains why")

fixtureData.itemConfig.itemOverrides = { ["Base.Axe"] = { buyPrice = 73 } }
dialog:onOverwrite()
assert(window.presetSaved["1"] and window.presetActive == "1" and #fileText > 0,
    "overwrite saves the current configuration into the shared file")

window:onPresetButton(window.presetButtons["1"])
dialog = window.presetDialog
assert(dialog.readButton.enable == true, "a populated slot can be loaded")
dialog:onRemark()
local box = window.presetRemarkBox
box.value = "跨存档测试"
window:onPresetRemarkResult({ internal = "OK" })
assert(window.presetRemarks["1"] == "跨存档测试", "remark edit callback persists the text")
assert(fileText:find("E8B7A8E5AD98E6A1A3E6B58BE8AF95", 1, true),
    "Lua and Kahlua write the same UTF-8 bytes for a Chinese remark")

window:onPresetButton(window.presetButtons.default)
assert(window.presetConfirmation and fixtureData.itemConfig.itemOverrides["Base.Axe"].buyPrice == 73,
    "default button waits for confirmation before changing settings")
answer("NO")
assert(fixtureData.itemConfig.itemOverrides["Base.Axe"].buyPrice == 73,
    "cancel leaves current settings unchanged")
window:onPresetButton(window.presetButtons.default)
answer("YES")
assert(window.presetActive == "default" and fixtureData.itemConfig.itemOverrides["Base.Axe"] == nil,
    "confirming default restores default item settings")
fixtureData.itemConfig.itemOverrides["Base.Axe"] = { buyPrice = 99 }
window:onPresetButton(window.presetButtons.default)
answer("YES")
assert(fixtureData.itemConfig.itemOverrides["Base.Axe"] == nil,
    "confirmed default also clears unsaved changes while already selected")
window:onPresetButton(window.presetButtons["1"])
window.presetDialog:onRead()
assert(window.presetActive == "1" and fixtureData.itemConfig.itemOverrides["Base.Axe"].buyPrice == 73,
    "existing slot read behavior immediately restores the snapshot")

GodSystemItemConfigPresetLibrary.resetForTests()
local otherSave = {}
assert(GodSystemItemConfigPresetLibrary.load(otherSave), "another save opens the shared file")
assert(otherSave.itemConfigPresets.remarks["1"] == "跨存档测试",
    "another save reads the same Chinese remark")
assert(GodSystemItemConfig.applyPreset(otherSave, "1") and
    otherSave.itemOverrides["Base.Axe"].buyPrice == 73,
    "another save applies the shared snapshot")
local sentCommand, sentArgs
isClient = function() return true end
GodSystemNetwork.send = function(command, args) sentCommand, sentArgs = command, args end
window:onPresetButton(window.presetButtons.default)
assert(sentCommand == nil, "multiplayer restore sends no command before confirmation")
answer("NO")
assert(sentCommand == nil, "multiplayer cancellation sends no command")
window:onPresetButton(window.presetButtons.default)
answer("YES")
assert(sentCommand == "itemConfigPresetApply" and sentArgs.name == "default",
    "multiplayer restore sends one intent only after confirmation")
window:requestPresetRemark("3", "服务器备注")
assert(sentCommand == "itemConfigPresetRemark" and sentArgs.name == "3"
    and sentArgs.remark == "服务器备注", "multiplayer sends only slot and remark intent")
window:close()
print("PASS item preset UI: fixed slots, confirmation and cancel, overwrite, remark and cross-save file")
