local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path

GodSystemConfig = {
    DataKey = "GodSystem_Test_Context_11672",
    RecycleBlacklist = { ["GodSystem.SystemAutoLoader"] = true },
}
package.loaded.GodSystem_Config = true

local handlers = {}
local inventoryEvent = {}
function inventoryEvent.Add(handler) handlers[#handlers + 1] = handler end
function inventoryEvent.Remove(handler)
    for index = #handlers, 1, -1 do
        if handlers[index] == handler then table.remove(handlers, index) end
    end
end
Events = { OnFillInventoryObjectContextMenu = inventoryEvent }

local Storage = require "GodSystem_Storage"
local function item(fullType, id)
    local value = { fullType = fullType, id = id, data = {}, inventoryItem = true }
    function value:getFullType() return self.fullType end
    function value:getID() return self.id end
    function value:getModData() return self.data end
    return value
end

instanceof = function(value, className)
    return className == "InventoryItem" and value and value.inventoryItem == true
end

GodSystem = {
    text = function(_, fallback) return fallback end,
    isFeatureEnabled = function() return true end,
    isAutoRecyclerContainer = function(value)
        return value and value:getFullType() == "GodSystem.SystemSpaceTerminal"
    end,
}
function GodSystem.canContextRecycleItem(value)
    if not value or not value.getFullType then return false, "invalid" end
    if GodSystem.isAutoRecyclerContainer(value) or Storage.isProtected(value) then return false, "protected" end
    if GodSystemConfig.RecycleBlacklist[value:getFullType()] then return false, "protected" end
    return true, nil
end
function GodSystem.canContextListItem(value)
    return GodSystem.canContextRecycleItem(value)
end
package.preload.GodSystem_Core = function() return GodSystem end

ISInventoryPaneContextMenu = {
    addToolTip = function() return {} end,
}
package.loaded["ISUI/ISInventoryPaneContextMenu"] = true
package.loaded["ISUI/ISModalDialog"] = true
package.loaded["TimedActions/ISInventoryTransferUtil"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["TimedActions/ISWaitWhileGettingUp"] = true

GodSystemAutoLoader = {
    isLoader = function(value)
        return value and value:getFullType() == "GodSystem.SystemAutoLoader"
    end,
}
GodSystemAutoLoaderClient = { requestState = function() end, startDeposit = function() end, manualFill = function() end }
GodSystemAutoLoaderUI = { open = function() end }
package.loaded.GodSystem_AutoLoader = true
package.loaded.GodSystem_AutoLoaderClient = true
package.loaded.GodSystem_AutoLoaderUI = true

ISContextMenu = {}
function ISContextMenu:getNew()
    return {
        options = {},
        addOption = function(self, label)
            local option = { name = label }
            self.options[#self.options + 1] = option
            return option
        end,
    }
end

local function contextMenu()
    local context = { options = {}, submenus = {} }
    function context:addOption(label)
        local option = { name = label }
        self.options[#self.options + 1] = option
        return option
    end
    function context:addSubMenu(parent, submenu) self.submenus[parent] = submenu end
    return context
end

require "GodSystem_RecycleContext"
require "GodSystem_AutoLoaderContext"
assert(#handlers == 2, "recycle and auto-loader context handlers must both be registered")

local ordinary = item("Base.Hammer", 1)
local ordinaryAllowed = GodSystem.canContextRecycleItem(ordinary)
assert(ordinaryAllowed == true, "ordinary items must reach the recycle context without a missing-interface error")
local ordinaryMenu = contextMenu()
for index = 1, #handlers do handlers[index](0, ordinaryMenu, { ordinary }) end
assert(#ordinaryMenu.options == 3, "ordinary items must retain the three recycle/list context options")

local core = item(Storage.CoreFullType, 2)
local terminal = item("GodSystem.SystemSpaceTerminal", 3)
local loader = item("GodSystem.SystemAutoLoader", 4)
assert(select(1, GodSystem.canContextRecycleItem(core)) == false, "the storage core must remain recycle-protected")
assert(select(1, GodSystem.canContextRecycleItem(terminal)) == false, "the space terminal must remain recycle-protected")
assert(select(1, GodSystem.canContextRecycleItem(loader)) == false, "the auto-loader must remain recycle-protected")

local loaderMenu = contextMenu()
local ok, err = pcall(function()
    for index = 1, #handlers do handlers[index](0, loaderMenu, { loader }) end
end)
assert(ok, "one context handler must not prevent the later auto-loader handler: " .. tostring(err))
assert(#loaderMenu.options == 4, "the auto-loader menu must be added after the three protected recycle options")
local autoLoaderOption = loaderMenu.options[4]
local submenu = loaderMenu.submenus[autoLoaderOption]
assert(autoLoaderOption.name == "System auto-loader" and submenu and #submenu.options == 3,
    "the auto-loader right-click submenu must expose open, deposit, and fill actions")

print("Test-GodSystemV11672ContextRuntime passed")
