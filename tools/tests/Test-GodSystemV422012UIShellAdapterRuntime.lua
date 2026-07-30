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
    setPreferences = function(_, values, options)
        preferences[#preferences + 1] = values
        if options and options.callback then
            options.callback({ ok = true, code = "preferencesChanged" })
        end
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
value.ui.visible = false
value.ui.nested.changed = true
assert(target.save() == 2, "shell preference change count")
assert(#preferences == 1 and preferences[1].visible == false
    and preferences[1].windowX == 20,
    "shell batched primitive preferences")
assert(adapter:stop(), "shell stop")
assert(target.getData() == value, "shell reopened legacy data path")
assert(saved == 0, "legacy save path was restored")

print("Test-GodSystemV422012UIShellAdapterRuntime passed")
