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
    local list = {
        width = 320, height = 100, itemheight = 46, scrollY = scrollY, draws = {}, stencils = {},
        smoothScrollTargetY = -80, smoothScrollY = -80,
        vscroll = { x = 1, height = 1 },
    }
    function list:getYScroll() return self.scrollY end
    function list:getHeight() return self.height end
    function list:setYScroll(value) self.scrollY = value end
    function list:setScrollHeight(value) self.scrollHeight = value end
    function list:clear() self.cleared = true end
    function list.vscroll:setX(value) self.x = value end
    function list.vscroll:setHeight(value) self.height = value end
    function list:setStencilRect(x, y, width, height)
        local nextStencil = { x = x, y = y, width = width, height = height }
        if self.activeStencil then
            local left = math.max(self.activeStencil.x, nextStencil.x)
            local top = math.max(self.activeStencil.y, nextStencil.y)
            local right = math.min(self.activeStencil.x + self.activeStencil.width, nextStencil.x + nextStencil.width)
            local bottom = math.min(self.activeStencil.y + self.activeStencil.height, nextStencil.y + nextStencil.height)
            nextStencil = { x = left, y = top, width = math.max(0, right - left), height = math.max(0, bottom - top) }
        end
        self.activeStencil = nextStencil
        self.stencils[#self.stencils + 1] = nextStencil
    end
    function list:clearStencilRect() self.activeStencil = nil; self.stencilClears = (self.stencilClears or 0) + 1 end
    local function record(self, kind, ...)
        if self.activeStencil and (self.activeStencil.width <= 0 or self.activeStencil.height <= 0) then return end
        self.draws[#self.draws + 1] = { kind = kind, args = { ... } }
    end
    function list:drawRect(...) record(self, "rect", ...) end
    function list:drawText(...) record(self, "text", ...) end
    function list:drawTextRight(...) record(self, "textRight", ...) end
    function list:drawTextureScaledAspect(...) record(self, "texture", ...) end
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
assert(#partial.draws > 0 and #partial.stencils == 1, "partially visible rows must draw inside one temporary stencil")
assert(partial.stencils[1].y == 0 and partial.stencils[1].height == 36,
    "the top partial row stencil must stop at the inventory-list boundary")
assert(partial.stencilClears == 1 and partial.activeStencil == nil,
    "row drawing must clear its temporary stencil before drawing the next row")

local sequential = fakeList(-10)
UI.drawListRow(sequential, 0, row, false, {})
UI.drawListRow(sequential, 46, row, true, {})
local sequentialText = 0
for index = 1, #sequential.draws do
    if sequential.draws[index].kind == "text" then sequentialText = sequentialText + 1 end
end
assert(sequentialText == 4 and sequential.stencilClears == 2,
    "clearing the first row stencil must keep every later visible inventory row drawable")

local below = fakeList(0)
assert(UI.drawListRow(below, 100, row, true, { ammo = true }) == 146,
    "rows below the viewport must preserve list layout height")
assert(#below.draws == 0, "a row below the viewport must not render")

local stale = fakeList(-80)
UI.clearList(stale)
assert(stale.cleared == true and stale.scrollY == 0 and stale.scrollHeight == 0,
    "list rebuilds must reset stale scroll position and scroll height")
assert(stale.smoothScrollTargetY == nil and stale.smoothScrollY == nil,
    "list rebuilds must reset B42 smooth-scroll state")
UI.syncListScrollBar(stale)
assert(stale.vscroll.x == stale.width - 16 and stale.vscroll.height == stale.height,
    "reused list scrollbars must follow the current list geometry")

print("Test-GodSystemV11672UIRuntime passed")
