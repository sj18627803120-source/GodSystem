require "GodSystem_AutoLoader"
require "GodSystem_AutoLoaderClient"
require "GodSystem_AutoLoaderUI"

GodSystemAutoLoaderContext = GodSystemAutoLoaderContext or {}

local Context = GodSystemAutoLoaderContext
local AutoLoader = GodSystemAutoLoader
local Client = GodSystemAutoLoaderClient

function Context.text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

function Context.selectedLoader(items)
    local selected
    for _, value in ipairs(items or {}) do
        local candidates = {}
        if value and value.items then
            for index = 1, #(value.items or {}) do candidates[#candidates + 1] = value.items[index] end
        else
            candidates[1] = value
        end
        for index = 1, #candidates do
            local item = candidates[index]
            if item and AutoLoader.isLoader(item) then
                if selected and selected ~= item then return nil end
                selected = item
            end
        end
    end
    return selected
end

function Context.open(loader, playerNum)
    GodSystemAutoLoaderUI.open(loader, playerNum)
    Client.requestState(loader, playerNum)
end

function Context.deposit(loader, playerNum)
    Client.startDeposit(loader, playerNum)
end

function Context.fill(loader, playerNum)
    Client.manualFill(loader, playerNum)
end

function Context.fillInventoryMenu(playerNum, context, items)
    local loader = Context.selectedLoader(items)
    if not loader then return end
    local parent = context:addOption(Context.text("AutoLoader_Context", "System auto-loader"))
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, submenu)
    submenu:addOption(Context.text("AutoLoader_Open", "Open"), loader, Context.open, playerNum)
    submenu:addOption(Context.text("AutoLoader_DepositAll", "Store all loose ammo"), loader, Context.deposit, playerNum)
    submenu:addOption(Context.text("AutoLoader_FillAll", "Fill all magazines"), loader, Context.fill, playerNum)
end

if Events.OnFillInventoryObjectContextMenu then
    Events.OnFillInventoryObjectContextMenu.Remove(Context.fillInventoryMenu)
    Events.OnFillInventoryObjectContextMenu.Add(Context.fillInventoryMenu)
end

return Context
