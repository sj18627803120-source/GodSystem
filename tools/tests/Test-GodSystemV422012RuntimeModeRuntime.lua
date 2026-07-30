local luaRoot = assert(arg[1], "lua root required")
package.path = table.concat({
    luaRoot .. "/shared/?.lua",
    luaRoot .. "/shared/?/?.lua",
    package.path,
}, ";")

local Mode = require "GodSystem_RuntimeMode"
assert(Mode.targetVersion == "42.20.1.2", "runtime mode target")
assert(Mode.legacyBusinessEnabled(), "legacy runtime should remain active during staged migration")
Mode.enableModular()
assert(Mode.modularEnabled and not Mode.legacyBusinessEnabled(),
    "modular runtime activation")

print("Test-GodSystemV422012RuntimeModeRuntime passed")
