local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    luaRoot .. "/shared/?/?/?.lua",
    luaRoot .. "/shared/?/?/?/?.lua",
    package.path,
}, ";")

local ShellAdapter = require "GodSystem/UI/ShellAdapter"

local value = { ui = { windowX = 10, visible = true, nested = {} } }
local preferences = {}
local facade = {
    data = function() return value end,
    setPreference = function(_, key, nextValue)
        preferences[#preferences + 1] = { key = key, value = nextValue }
        return { ok = true }
    end,
}
local oldData = {}
local saved = 0
local target = {
    getData = function() return oldData end,
    save = function() saved = saved + 1 return true end,
}
local adapter = ShellAdapter.new({ facade = facade, target = target })
assert(adapter:install(), "shell install")
assert(target.getData() == value, "shell read model")
value.ui.windowX = 20
value.ui.visible = nil
value.ui.nested.changed = true
assert(target.save() == 2, "shell preference change count")
local changed = {}
for index = 1, #preferences do
    changed[preferences[index].key] = preferences[index].value == nil
        and "<nil>" or preferences[index].value
end
assert(#preferences == 2 and changed.visible == "<nil>" and changed.windowX == 20,
    "shell primitive preferences")
assert(adapter:stop(), "shell stop")
assert(target.getData() == oldData, "shell getData restoration")
target.save()
assert(saved == 1, "shell save restoration")

print("Test-GodSystemV422012UIShellAdapterRuntime passed")
