require "GodSystem_B42JavaCalls"
require "GodSystem_MimicKey"
require "GodSystem_Protocol"
require "ISUI/ISModalDialog"
require "ISUI/ISToolTip"

if isServer and isServer() and not (isClient and isClient()) then return end

GodSystemMimicKeyContext = GodSystemMimicKeyContext or {}

local Context = GodSystemMimicKeyContext
local Mimic = GodSystemMimicKey
local Protocol = GodSystemProtocol or {}

local function text(key, fallback)
    local runtime = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime or nil
    return runtime and runtime.text and runtime.text(key, fallback) or fallback or key
end

local function notifyCode(code)
    local runtime = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime or nil
    if runtime and runtime.notify then runtime.notify(text("Notify_" .. tostring(code or ""), tostring(code or ""))) end
end

local function findMimic(player)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory or not inventory.getFirstTypeRecurse then return nil end
    local ok, item = pcall(function() return inventory:getFirstTypeRecurse(Mimic.FullType) end)
    return ok and item or nil
end

local function selectedVehicle(player)
    if not player then return nil end
    local vehicle = player.getVehicle and player:getVehicle() or nil
    if vehicle then return vehicle end
    if IsoObjectPicker and IsoObjectPicker.Instance and IsoObjectPicker.Instance.PickVehicle then
        local ok, picked = pcall(function() return IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled()) end)
        if ok then return picked end
    end
    return nil
end

local function targetLabel(detail)
    local labels = {
        door = text("MimicKey_TargetDoor", "locked door"),
        padlock = text("MimicKey_TargetPadlock", "padlocked object"),
        code = text("MimicKey_TargetCode", "combination lock"),
        vehicle = text("MimicKey_TargetVehicle", "locked vehicle"),
    }
    return labels[detail and detail.kind] or text("MimicKey_TargetUnknown", "target")
end

local function resultLabel(detail)
    if detail and detail.kind == "code" then return text("MimicKey_ResultPadlock", "remove the code lock and return a combination padlock") end
    if detail and detail.kind == "vehicle" then return text("MimicKey_ResultVehicle", "create a matching vehicle key") end
    return text("MimicKey_ResultKey", "create a matching key")
end

local function makeArgs(item, detail)
    local args = {
        mimicItemId = Mimic.itemId(item),
        targetKind = detail.kind,
    }
    if detail.kind == "vehicle" then
        args.vehicleId = detail.vehicleId
    else
        args.x, args.y, args.z, args.objectIndex = detail.x, detail.y, detail.z, detail.objectIndex
    end
    return args
end

local function findById(container, itemId)
    if not container or not container.getItems then return nil, nil end
    local items = container:getItems()
    local count = items and items.size and items:size() or 0
    for index = 0, count - 1 do
        local item = items:get(index)
        if item and Mimic.itemId(item) == itemId then return item, container end
        local child = item and item.getInventory and item:getInventory() or nil
        local found, source = findById(child, itemId)
        if found then return found, source end
    end
    return nil, nil
end

local function localRemove(_, container, item)
    local ok = pcall(function() container:Remove(item) end)
    if ok and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
    return ok == true
end

local function localAdd(player, item)
    local inventory = player and player:getInventory() or nil
    if not inventory then return false end
    local ok, added = pcall(function() return inventory:AddItem(item) end)
    if ok and added and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
    return ok == true and added ~= nil
end

local function localRemoveOutput(player, item)
    return localRemove(player, player and player:getInventory() or nil, item)
end

local function localRefund(player)
    local inventory = player and player:getInventory() or nil
    local ok, item = pcall(function() return inventory and inventory:AddItem(Mimic.FullType) or nil end)
    if not ok then item = nil end
    if item and triggerEvent then pcall(triggerEvent, "OnContainerUpdate") end
    return item ~= nil
end

function Context.execute(player, args)
    if isClient and isClient() then
        local network = GodSystemNetwork
        local command = (Protocol.C2S and Protocol.C2S.UseMimicKey) or "useMimicKey"
        if not network or not network.send or network.send(command, args) ~= true then notifyCode("MimicKeyFailed") end
        return
    end
    local success, code = Mimic.execute(player, args, {
        findItem = function(target, itemId) return findById(target:getInventory(), itemId) end,
        remove = localRemove,
        add = localAdd,
        removeOutput = localRemoveOutput,
        refund = localRefund,
    })
    notifyCode(code)
    return success
end

function Context.onConfirm(_, button, payload)
    if not button or button.internal ~= "YES" or not payload then return end
    local player = getSpecificPlayer and getSpecificPlayer(payload.playerNum) or getPlayer()
    local item = findMimic(player)
    if not item then return notifyCode("MimicKeyMissing") end
    Context.execute(player, makeArgs(item, payload.detail))
end

function Context.confirm(playerNum, detail)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
    local item = findMimic(player)
    if not player or not item or not detail then return end
    local message = text("Confirm_MimicKey", "Consume one mimic key?") .. "\n\n" ..
        text("MimicKey_Target", "Target") .. ": " .. targetLabel(detail) .. "\n" ..
        text("MimicKey_Result", "Result") .. ": " .. resultLabel(detail) .. "\n\n" ..
        text("MimicKey_StaysLocked", "The target remains locked after the key is created.")
    if detail.kind == "code" then message = message .. "\n" .. text("MimicKey_CodeNote", "Combination locks are removed because they have no key.") end
    local x = math.max(40, (getCore():getScreenWidth() - 500) / 2)
    local y = math.max(40, (getCore():getScreenHeight() - 260) / 2)
    local modal = ISModalDialog:new(x, y, 500, 260, message, true, Context, Context.onConfirm, playerNum, { playerNum = playerNum, detail = detail })
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
end

local function addOption(playerNum, context, detail)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    local item = findMimic(player)
    local option = context:addOption(text("Context_MimicKey", "Use mimic key"), playerNum, Context.confirm, detail)
    if item then return option end
    option.notAvailable = true
    local tooltip = ISToolTip:new()
    tooltip:initialise(); tooltip:setVisible(false); tooltip:setName(text("Context_MimicKey", "Use mimic key"))
    tooltip.description = text("Notify_MimicKeyMissing", "No mimic key in inventory")
    option.toolTip = tooltip
    return option
end

function Context.fillWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    local vehicleDetail = Mimic.describeVehicle(selectedVehicle(player))
    if vehicleDetail then return addOption(playerNum, context, vehicleDetail) end
    for index = 1, #(worldobjects or {}) do
        local detail = Mimic.describeObject(worldobjects[index])
        if detail then return addOption(playerNum, context, detail) end
    end
end

Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldMenu)
Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldMenu)
