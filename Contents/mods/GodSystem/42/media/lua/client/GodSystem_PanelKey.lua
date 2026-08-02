require "PZAPI/ModOptions"

GodSystemPanelKey = GodSystemPanelKey or {}

local PanelKey = GodSystemPanelKey
local DEFAULT_KEY = Keyboard.KEY_N

PanelKey.moduleId = "panelKey"
PanelKey.options = PanelKey.options or PZAPI.ModOptions:create("GodSystem_CN", getText("IGUI_GodSystem_Settings_ModOptionsTitle"))
PanelKey.binding = PanelKey.binding or PanelKey.options:addKeyBind(
    "OpenPanelKey",
    getText("IGUI_GodSystem_Settings_PanelKey"),
    DEFAULT_KEY,
    getText("IGUI_GodSystem_Settings_PanelKeyHint")
)
PanelKey.toggleCallback = nil
PanelKey.captureCallback = nil

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

function PanelKey.getDefaultKey()
    return DEFAULT_KEY
end

function PanelKey.getKey()
    return math.floor(tonumber(PanelKey.binding:getValue()) or DEFAULT_KEY)
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
    PanelKey.binding:setValue(key)
    PanelKey.options:apply()
    PZAPI.ModOptions:save()
    return key
end

function PanelKey.reset()
    return PanelKey.setKey(DEFAULT_KEY)
end

function PanelKey.isCapturing()
    return PanelKey.captureCallback ~= nil
end

function PanelKey.beginCapture(callback)
    PanelKey.captureCallback = callback
end

function PanelKey.cancelCapture(reason)
    local callback = PanelKey.captureCallback
    PanelKey.captureCallback = nil
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
        PanelKey.captureCallback = nil
        PanelKey.setKey(key)
        callback(true, key, "saved")
        return
    end
    if key ~= PanelKey.getKey() or PanelKey.isBlocked() then return end
    if PanelKey.toggleCallback then PanelKey.toggleCallback() end
end

Events.OnKeyPressed.Add(PanelKey.onKeyPressed)

return PanelKey
