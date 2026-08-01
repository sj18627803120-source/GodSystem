require "PZAPI/ModOptions"

GodSystemKeybind = GodSystemKeybind or {}

local Keybind = GodSystemKeybind
local DEFAULT_KEY = Keyboard.KEY_N
local DISABLED_KEY = 0

Keybind.moduleId = "keybind"
Keybind.options = Keybind.options or PZAPI.ModOptions:create("GodSystem_CN", "God System")
Keybind.binding = Keybind.binding or Keybind.options:addKeyBind(
    "OpenPanelKey",
    "打开/关闭神级系统面板",
    DEFAULT_KEY,
    "在游戏中打开或关闭神级系统主面板；设为无按键可禁用。"
)
Keybind.captureTarget = nil
Keybind.lastError = nil

local function result(ok, code, data)
    return { ok = ok == true, code = tostring(code or ""), data = data, moduleId = Keybind.moduleId }
end

local function focusedTextEntry(element, seen)
    if not element or seen[element] then return false end
    seen[element] = true
    if tostring(element.Type or "") == "ISTextEntryBox" and element.isFocused and element:isFocused() then
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

local function textInputActive()
    if ISChat and ISChat.instance and ISChat.instance.chatText
        and ISChat.instance.chatText.isFocused and ISChat.instance.chatText:isFocused() then
        return true
    end
    local roots = UIManager and UIManager.getUI and UIManager.getUI() or nil
    if roots and roots.size and roots.get then
        local seen = {}
        for i = 0, roots:size() - 1 do
            if focusedTextEntry(roots:get(i), seen) then return true end
        end
    end
    return false
end

function Keybind.getKey()
    return Keybind.binding and tonumber(Keybind.binding:getValue()) or DEFAULT_KEY
end

function Keybind.keyName(key)
    key = tonumber(key) or DISABLED_KEY
    if key == DISABLED_KEY then return "已禁用" end
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

function Keybind.setKey(key)
    key = math.max(0, math.floor(tonumber(key) or DEFAULT_KEY))
    Keybind.binding:setValue(key)
    PZAPI.ModOptions:save()
    return result(true, key == DISABLED_KEY and "disabled" or "saved", {
        key = key,
        name = Keybind.keyName(key),
    })
end

function Keybind.reset()
    return Keybind.setKey(DEFAULT_KEY)
end

function Keybind.disable()
    return Keybind.setKey(DISABLED_KEY)
end

function Keybind.beginCapture(target)
    Keybind.captureTarget = target
    return result(true, "capturing", { key = Keybind.getKey() })
end

function Keybind.cancelCapture()
    local target = Keybind.captureTarget
    Keybind.captureTarget = nil
    if target and target.onGodSystemKeyCapture then
        target:onGodSystemKeyCapture(false, nil, "cancelled")
    end
    return result(true, "cancelled")
end

function Keybind.isCapturing()
    return Keybind.captureTarget ~= nil
end

function Keybind.isBlocked()
    if not getPlayer or not getPlayer() then return true end
    if textInputActive() then return true end
    if UIManager and UIManager.getModal and UIManager.getModal() then return true end
    return false
end

function Keybind.onKeyPressed(key)
    key = tonumber(key) or DISABLED_KEY
    if Keybind.captureTarget then
        if key == Keyboard.KEY_ESCAPE then
            Keybind.cancelCapture()
            return
        end
        local target = Keybind.captureTarget
        Keybind.captureTarget = nil
        local saved = Keybind.setKey(key)
        if target and target.onGodSystemKeyCapture then
            target:onGodSystemKeyCapture(saved.ok, key, saved.code)
        end
        return
    end
    local configured = Keybind.getKey()
    if configured == DISABLED_KEY or key ~= configured or Keybind.isBlocked() then return end
    if GodSystemUI and GodSystemUI.toggleWindow then GodSystemUI.toggleWindow() end
end

function Keybind.health()
    local key = Keybind.getKey()
    return result(Keybind.binding ~= nil, Keybind.binding and "ok" or "bindingMissing", {
        key = key,
        name = Keybind.keyName(key),
        capturing = Keybind.isCapturing(),
    })
end

Events.OnKeyPressed.Add(Keybind.onKeyPressed)

return Keybind
