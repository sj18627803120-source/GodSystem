require "PZAPI/ModOptions"

GodSystemPanelKey = GodSystemPanelKey or {}

local PanelKey = GodSystemPanelKey
local DEFAULT_KEY = Keyboard.KEY_N
local DEFAULT_RANGE_KEY = Keyboard.KEY_G

PanelKey.moduleId = "panelKey"
PanelKey.options = PanelKey.options or PZAPI.ModOptions:create("GodSystem_CN", getText("IGUI_GodSystem_Settings_ModOptionsTitle"))
PanelKey.binding = PanelKey.binding or PanelKey.options:addKeyBind(
    "OpenPanelKey",
    getText("IGUI_GodSystem_Settings_PanelKey"),
    DEFAULT_KEY,
    getText("IGUI_GodSystem_Settings_PanelKeyHint")
)
PanelKey.rangeBinding = PanelKey.rangeBinding or PanelKey.options:addKeyBind(
    "RangeRecycleKey",
    getText("IGUI_GodSystem_Settings_RangeRecycleKey"),
    DEFAULT_RANGE_KEY,
    getText("IGUI_GodSystem_Settings_RangeRecycleKeyHint")
)
PanelKey.toggleCallback = nil
PanelKey.rangeRecycleCallback = nil
PanelKey.captureCallback = nil
PanelKey.captureTarget = nil
PanelKey.lastPanelKey = PanelKey.lastPanelKey or math.floor(tonumber(PanelKey.binding:getValue()) or DEFAULT_KEY)
PanelKey.lastRangeKey = PanelKey.lastRangeKey or math.floor(tonumber(PanelKey.rangeBinding:getValue()) or DEFAULT_RANGE_KEY)

local function focusedTextEntry(element, seen)
    if not element or seen[element] then return false end
    seen[element] = true
    if tostring(element.Type or "") == "ISTextEntryBox"
        and element.isFocused and element:isFocused() then
        return true
    end
    local children = element.children
    if type(children) == "table" then
        for i = 1, #children do
            if focusedTextEntry(children[i], seen) then return true end
        end
    end
    return false
end

local function hasFocusedTextEntry()
    if ISChat and ISChat.instance and ISChat.instance.chatText
        and ISChat.instance.chatText.isFocused and ISChat.instance.chatText:isFocused() then
        return true
    end
    local roots = UIManager and UIManager.getUI and UIManager.getUI() or nil
    if not roots then return false end
    local seen = {}
    if roots.size and roots.get then
        for i = 0, roots:size() - 1 do
            if focusedTextEntry(roots:get(i), seen) then return true end
        end
    elseif type(roots) == "table" then
        for i = 1, #roots do
            if focusedTextEntry(roots[i], seen) then return true end
        end
    end
    return false
end

function PanelKey.registerToggle(callback)
    PanelKey.toggleCallback = callback
end

function PanelKey.registerRangeRecycle(callback)
    PanelKey.rangeRecycleCallback = callback
end

function PanelKey.getDefaultKey()
    return DEFAULT_KEY
end

function PanelKey.getDefaultRangeKey()
    return DEFAULT_RANGE_KEY
end

local function distinctKeys()
    local panel = math.floor(tonumber(PanelKey.binding:getValue()) or DEFAULT_KEY)
    local range = math.floor(tonumber(PanelKey.rangeBinding:getValue()) or DEFAULT_RANGE_KEY)
    if panel == range then
        range = math.floor(tonumber(PanelKey.lastRangeKey) or DEFAULT_RANGE_KEY)
        if range == panel then range = DEFAULT_RANGE_KEY end
        if range == panel then range = DEFAULT_KEY end
        if range == panel then range = 0 end
        PanelKey.rangeBinding:setValue(range)
        PanelKey.options:apply()
        PZAPI.ModOptions:save()
    end
    PanelKey.lastPanelKey = panel
    PanelKey.lastRangeKey = range
    return panel, range
end

function PanelKey.getKey()
    local panel = distinctKeys()
    return panel
end

function PanelKey.getRangeKey()
    local _, range = distinctKeys()
    return range
end

function PanelKey.getKeyName(key)
    key = math.floor(tonumber(key) or PanelKey.getKey())
    if getKeyName then
        local name = getKeyName(key)
        if name and tostring(name) ~= "" then return tostring(name) end
    end
    if Keyboard and Keyboard.getKeyName then
        local name = Keyboard.getKeyName(key)
        if name and tostring(name) ~= "" then return tostring(name) end
    end
    return tostring(key)
end

function PanelKey.setKey(key)
    key = math.max(0, math.floor(tonumber(key) or DEFAULT_KEY))
    if key == PanelKey.getRangeKey() then return false, "conflict" end
    PanelKey.binding:setValue(key)
    PanelKey.lastPanelKey = key
    PanelKey.options:apply()
    PZAPI.ModOptions:save()
    return key
end

function PanelKey.setRangeKey(key)
    key = math.max(0, math.floor(tonumber(key) or DEFAULT_RANGE_KEY))
    if key == PanelKey.getKey() then return false, "conflict" end
    PanelKey.rangeBinding:setValue(key)
    PanelKey.lastRangeKey = key
    PanelKey.options:apply()
    PZAPI.ModOptions:save()
    return key
end

function PanelKey.reset()
    return PanelKey.setKey(DEFAULT_KEY)
end

function PanelKey.resetRange()
    return PanelKey.setRangeKey(DEFAULT_RANGE_KEY)
end

function PanelKey.isCapturing()
    return PanelKey.captureCallback ~= nil
end

function PanelKey.beginCapture(target, callback)
    if type(target) == "function" then callback, target = target, "panel" end
    PanelKey.captureTarget = target == "range" and "range" or "panel"
    PanelKey.captureCallback = callback
end

function PanelKey.cancelCapture(reason)
    local callback = PanelKey.captureCallback
    PanelKey.captureCallback = nil
    PanelKey.captureTarget = nil
    if callback then callback(false, nil, reason or "cancelled") end
end

function PanelKey.isBlocked()
    if not getPlayer or not getPlayer() then return true end
    if hasFocusedTextEntry() then return true end
    if UIManager and UIManager.getModal and UIManager.getModal() then return true end
    return false
end

function PanelKey.onKeyPressed(key)
    key = math.floor(tonumber(key) or 0)
    if PanelKey.captureCallback then
        if key == Keyboard.KEY_ESCAPE then
            PanelKey.cancelCapture("cancelled")
            return
        end
        local callback = PanelKey.captureCallback
        local target = PanelKey.captureTarget
        PanelKey.captureCallback = nil
        PanelKey.captureTarget = nil
        local saved, reason
        if target == "range" then
            saved, reason = PanelKey.setRangeKey(key)
        else
            saved, reason = PanelKey.setKey(key)
        end
        if saved == false then
            callback(false, key, reason or "conflict")
        else
            callback(true, key, "saved")
        end
        return
    end
    if PanelKey.isBlocked() then return end
    if key == PanelKey.getKey() then
        if PanelKey.toggleCallback then PanelKey.toggleCallback() end
    elseif key == PanelKey.getRangeKey() and PanelKey.rangeRecycleCallback then
        PanelKey.rangeRecycleCallback()
    end
end

Events.OnKeyPressed.Add(PanelKey.onKeyPressed)

return PanelKey
