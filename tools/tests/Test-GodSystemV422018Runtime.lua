local taskOrderPath = assert(arg[1], "task order path is required")
local panelKeyPath = assert(arg[2], "panel key path is required")

local function ids(tasks)
    local result = {}
    for i = 1, #tasks do
        result[#result + 1] = tostring(tasks[i].taskId)
    end
    return table.concat(result, ",")
end

dofile(taskOrderPath)
local Order = assert(GodSystemTaskOrder, "task order module did not load")

assert(Order.difficultyRank({ penaltyPoints = 29 }) == 1, "29 must be D1")
assert(Order.difficultyRank({ penaltyPoints = 30 }) == 2, "30 must be D2")
assert(Order.difficultyRank({ penaltyPoints = 79 }) == 2, "79 must be D2")
assert(Order.difficultyRank({ penaltyPoints = 80 }) == 3, "80 must be D3")
assert(Order.difficultyRank({ penaltyPoints = 149 }) == 3, "149 must be D3")
assert(Order.difficultyRank({ penaltyPoints = 150 }) == 4, "150 must be D4")

local tasks = {
    { taskId = "unknown", kind = "futureType", status = "open", penaltyPoints = 0, title = "Unknown" },
    { taskId = "move", kind = "moveDistance", status = "open", penaltyPoints = 0, title = "Move" },
    { taskId = "buy", kind = "buyItems", status = "open", penaltyPoints = 0, title = "Buy" },
    { taskId = "spend", kind = "spendPoints", status = "open", penaltyPoints = 0, title = "Spend" },
    { taskId = "turn", kind = "turnInItem", status = "open", penaltyPoints = 0, title = "Turn" },
    { taskId = "survive", kind = "surviveHours", status = "open", penaltyPoints = 0, title = "Survive" },
    { taskId = "recycleD4", kind = "recycleItems", status = "open", penaltyPoints = 150, title = "Recycle Z" },
    { taskId = "recycleD1B", kind = "recyclePoints", status = "open", penaltyPoints = 0, title = "Recycle B" },
    { taskId = "recycleD1A", kind = "recycleItems", status = "open", penaltyPoints = 0, title = "Recycle A" },
    { taskId = "killD3", kind = "kill", status = "open", penaltyPoints = 80, title = "Kill C" },
    { taskId = "killD1", kind = "kill", status = "open", penaltyPoints = 0, title = "Kill A" },
    { taskId = "activeKill", kind = "kill", status = "active", penaltyPoints = 30, title = "Active" },
}

local before = ids(tasks)
local sorted = Order.sortedCopy(tasks, "open", function(task) return task.title end)
local expected = "killD1,killD3,recycleD1A,recycleD1B,recycleD4,survive,turn,spend,buy,move,unknown"
assert(ids(sorted) == expected, "category, difficulty and title order is wrong: " .. ids(sorted))
assert(ids(tasks) == before, "sorting must not mutate the source task array")
assert(#Order.sortedCopy(tasks, "active") == 1, "status filtering must isolate active tasks")

tasks[#tasks + 1] = { taskId = "newKill", kind = "kill", status = "open", penaltyPoints = 0, title = "Kill 0" }
assert(Order.sortedCopy(tasks, "open", function(task) return task.title end)[1].taskId == "newKill", "a new task must enter its sorted position immediately")

local reversed = {}
for i = #tasks, 1, -1 do reversed[#reversed + 1] = tasks[i] end
assert(ids(Order.sortedCopy(reversed, "open", function(task) return task.title end)) == ids(Order.sortedCopy(tasks, "open", function(task) return task.title end)), "MP input order must not affect display order")

local savedCount = 0
local appliedCount = 0
local registeredKeyHandler = nil
local binding = { value = 49 }
function binding:getValue() return self.value end
function binding:setValue(value) self.value = value end

Keyboard = {
    KEY_N = 49,
    KEY_ESCAPE = 1,
    getKeyName = function(key) return "KEY_" .. tostring(key) end,
}

local options = {}
function options:addKeyBind(id, name, key, tooltip)
    assert(id == "OpenPanelKey", "keybind ID must stay stable")
    binding.value = key
    return binding
end
function options:apply() appliedCount = appliedCount + 1 end

PZAPI = {
    ModOptions = {
        create = function(self, id, name)
            assert(id == "GodSystem_CN", "ModOptions must use the stable Mod ID")
            return options
        end,
        save = function(self) savedCount = savedCount + 1 end,
    },
}

package.preload["PZAPI/ModOptions"] = function() return true end
getText = function(key) return key end
getKeyName = function(key) return "KEY_" .. tostring(key) end
Events = { OnKeyPressed = { Add = function(handler) registeredKeyHandler = handler end } }
UIManager = {
    getUI = function() return {} end,
    getModal = function() return nil end,
}
local player = {}
getPlayer = function() return player end
ISChat = nil

dofile(panelKeyPath)
local PanelKey = assert(GodSystemPanelKey, "panel key module did not load")
assert(registeredKeyHandler == PanelKey.onKeyPressed, "OnKeyPressed handler was not registered")
assert(PanelKey.getKey() == Keyboard.KEY_N, "default key must be N")

PanelKey.setKey(77)
assert(PanelKey.getKey() == 77 and savedCount == 1 and appliedCount == 1, "changed key must apply and save immediately")
binding.value = 78
assert(PanelKey.getKey() == 78, "system page and Mod Options must share one binding value")
PanelKey.reset()
assert(PanelKey.getKey() == Keyboard.KEY_N and savedCount == 2, "reset must restore and save N")

local toggles = 0
PanelKey.registerToggle(function() toggles = toggles + 1 end)
registeredKeyHandler(PanelKey.getKey())
assert(toggles == 1, "configured key must toggle the registered panel callback")

player = nil
registeredKeyHandler(PanelKey.getKey())
assert(toggles == 1, "no-player state must block the panel key")
player = {}

UIManager.getModal = function() return {} end
registeredKeyHandler(PanelKey.getKey())
assert(toggles == 1, "modal UI must block the panel key")
UIManager.getModal = function() return nil end

local focusedEntry = { Type = "ISTextEntryBox", isFocused = function() return true end }
UIManager.getUI = function() return { focusedEntry } end
registeredKeyHandler(PanelKey.getKey())
assert(toggles == 1, "focused text input must block the panel key")
UIManager.getUI = function() return {} end

local captureOk = nil
local captureKey = nil
PanelKey.beginCapture(function(ok, key) captureOk, captureKey = ok, key end)
registeredKeyHandler(88)
assert(captureOk == true and captureKey == 88 and PanelKey.getKey() == 88, "capture must save the next key without toggling the panel")
assert(toggles == 1, "capture must not toggle the panel")

local cancelReason = nil
PanelKey.beginCapture(function(ok, key, reason)
    assert(ok == false and key == nil, "Esc capture result must be cancelled")
    cancelReason = reason
end)
registeredKeyHandler(Keyboard.KEY_ESCAPE)
assert(cancelReason == "cancelled" and not PanelKey.isCapturing(), "Esc must cancel capture")

print("Test-GodSystemV422018Runtime OK")
