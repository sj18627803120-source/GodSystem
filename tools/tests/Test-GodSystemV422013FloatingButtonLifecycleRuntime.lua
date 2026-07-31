local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/client/?.lua;" .. package.path

local Lifecycle = require "GodSystem_FloatingButtonLifecycle"

local x, y = Lifecycle.clampPosition(-60, 20, 40, 40, 1920, 1080)
assert(x == 0 and y == 20, "a button completely beyond the left edge must return to the screen")
x, y = Lifecycle.clampPosition(1920, 1080, 40, 40, 1920, 1080)
assert(x == 1880 and y == 1040, "a button completely beyond the right or bottom edge must return to the screen")
x, y = Lifecycle.clampPosition(-10, 20, 40, 40, 1920, 1080)
assert(x == -10 and y == 20, "a partially visible button must preserve the player's saved placement")

local created = 0
local function makeButton(x0, y0, width, height)
    created = created + 1
    local button = { x = x0, y = y0, width = width, height = height, addCalls = 0 }
    function button:addToUIManager() self.addCalls = self.addCalls + 1 end
    function button:setVisible(value) self.visible = value end
    function button:setX(value) self.x = value end
    function button:setY(value) self.y = value end
    return button
end

local button, recreated, moved = Lifecycle.ensure(nil, makeButton, -60, 20, 40, 40, 1920, 1080)
assert(recreated == true and moved == true and created == 1, "a missing button must be created and recovered")
assert(button.x == 0 and button.y == 20 and button.visible == true and button.addCalls == 1,
    "a recovered button must be visible and registered with the UI manager")

local same, secondRecreated, secondMoved = Lifecycle.ensure(button, makeButton, 0, 20, 40, 40, 1920, 1080)
assert(same == button and secondRecreated == false and secondMoved == false and created == 1,
    "a valid button must be reused rather than recreated")
assert(button.addCalls == 2 and button.visible == true,
    "a valid button must still be re-registered during the low-frequency health check")

print("Test-GodSystemV422013FloatingButtonLifecycleRuntime passed")
