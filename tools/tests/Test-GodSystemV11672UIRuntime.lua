local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/client/?.lua;" .. package.path

GodSystemStorage = {
    number = function(value, fallback) return tonumber(value) or fallback or 0 end,
    safeCall = function(target, methodName, fallback, ...)
        if target and target[methodName] then return target[methodName](target, ...) end
        return fallback
    end,
}
GodSystemStorageClient = {}
package.loaded.GodSystem_StorageClient = true

ISCollapsableWindow = {}
function ISCollapsableWindow:derive()
    local value = {}
    value.__index = value
    return setmetatable(value, { __index = self })
end
ISButton, ISLabel, ISScrollingListBox, ISTextEntryBox, ISContextMenu = {}, {}, {}, {}, {}
ISTimedActionQueue, ISUnequipAction, ISWaitWhileGettingUp = {}, {}, {}
ISWearClothing, ISEquipWeaponAction, ISAttachItemHotbar = {}, {}, {}
for _, moduleName in ipairs({
    "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISLabel", "ISUI/ISScrollingListBox",
    "ISUI/ISTextEntryBox", "ISUI/ISContextMenu", "TimedActions/ISTimedActionQueue",
    "TimedActions/ISUnequipAction", "TimedActions/ISWaitWhileGettingUp", "TimedActions/ISWearClothing",
    "TimedActions/ISEquipWeaponAction", "TimedActions/ISAttachItemHotbar",
}) do package.loaded[moduleName] = true end

UIFont = { Small = "small" }
Events = { OnContainerUpdate = { Add = function() end, Remove = function() end } }

local UI = require "GodSystem_StorageUI"

local function fakeList(scrollY)
    local list = { width = 320, height = 100, itemheight = 46, scrollY = scrollY, draws = {}, stencils = {} }
    function list:getYScroll() return self.scrollY end
    function list:getHeight() return self.height end
    function list:setStencilRect(x, y, width, height)
        self.stencils[#self.stencils + 1] = { x = x, y = y, width = width, height = height }
    end
    function list:drawRect(...) self.draws[#self.draws + 1] = { kind = "rect", args = { ... } } end
    function list:drawText(...) self.draws[#self.draws + 1] = { kind = "text", args = { ... } } end
    function list:drawTextRight(...) self.draws[#self.draws + 1] = { kind = "textRight", args = { ... } } end
    function list:drawTextureScaledAspect(...) self.draws[#self.draws + 1] = { kind = "texture", args = { ... } } end
    return list
end

local row = {
    height = 46,
    text = "9mm rounds",
    item = { key = "ammo", displayText = "9mm rounds", subtext = "Ammo", count = 2, texture = "icon" },
}

local above = fakeList(-60)
assert(UI.drawListRow(above, 0, row, false, {}) == 46, "culled rows must preserve list layout height")
assert(#above.draws == 0 and #above.stencils == 0,
    "a row fully above the inventory viewport must not draw text, icon, or selection background")

local partial = fakeList(-50)
assert(UI.drawListRow(partial, 40, row, false, {}) == 86, "partially visible rows must preserve list layout height")
assert(#partial.draws > 0 and #partial.stencils == 2, "partially visible rows must draw inside a temporary stencil")
assert(partial.stencils[1].y == 0 and partial.stencils[1].height == 36,
    "the top partial row stencil must stop at the inventory-list boundary")
assert(partial.stencils[2].y == 0 and partial.stencils[2].height == partial.height,
    "row drawing must restore the list viewport stencil for later rows")

local below = fakeList(0)
assert(UI.drawListRow(below, 100, row, true, { ammo = true }) == 146,
    "rows below the viewport must preserve list layout height")
assert(#below.draws == 0, "a row below the viewport must not render")

print("Test-GodSystemV11672UIRuntime passed")
