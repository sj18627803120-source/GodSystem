require "GodSystem_App"
require "GodSystem_Core"
require "GodSystem_InventoryContext"
require "GodSystem_Lottery"
require "GodSystem_Network"
require "GodSystem_Protocol"
require "ISUI/ISModalDialog"
require "ISUI/ISInventoryPaneContextMenu"

GodSystemLotteryContext = GodSystemLotteryContext or {}

local Context = GodSystemLotteryContext
local Protocol = GodSystemProtocol or {}
local Cache = GodSystemLotteryItemCache

local function text(key, fallback)
    local runtime = GodSystemApp.services and GodSystemApp.services.runtime or nil
    return runtime and runtime.text and runtime.text(key, fallback) or fallback or key
end

local function formatText(template, args)
    local value = tostring(template or "")
    for index = 1, #(args or {}) do value = value:gsub("{" .. tostring(index) .. "}", tostring(args[index])) end
    return value
end

local function itemId(item)
    if not item or not item.getID then return nil end
    local ok, value = pcall(function() return item:getID() end)
    return ok and value ~= nil and tostring(value) or nil
end

local function selectedItems(values)
    local result, seen = {}, {}
    for _, value in ipairs(values or {}) do
        local source = instanceof(value, "InventoryItem") and { value } or (value and value.items) or {}
        for _, item in ipairs(source) do
            if instanceof(item, "InventoryItem") then
                local id = itemId(item)
                if id and not seen[id] then seen[id] = true; result[#result + 1] = item end
            end
        end
    end
    return result
end

local function isCarried(player, targetId)
    local function find(container, depth)
        if not container or depth > 32 or not container.getItems then return false end
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item then
                if itemId(item) == targetId then return true end
                if item.getInventory then
                    local ok, child = pcall(function() return item:getInventory() end)
                    if ok and child and find(child, depth + 1) then return true end
                end
            end
        end
        return false
    end
    return player and player.getInventory and find(player:getInventory(), 1) or false
end

local function isCarriedShallow(player, item)
    local container = item and item.getContainer and item:getContainer() or nil
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not container or not inventory then return false end
    if container == inventory then return true end
    if container.isInCharacterInventory then
        local ok, value = pcall(function() return container:isInCharacterInventory(player) end)
        if ok and value == true then return true end
    end
    return false
end

local function notify(key, fallback, args)
    local runtime = GodSystemApp.services and GodSystemApp.services.runtime or nil
    if runtime and runtime.notify then runtime.notify(formatText(text(key, fallback), args or {})) end
end

local function isMultiplayer()
    return isClient and isClient() == true
end

local function removeTicket(container, ticket)
    if not container or not ticket or not container.Remove then return false end
    local ok = pcall(function() container:Remove(ticket) end)
    if not ok or container.getItems == nil then return false end
    local items = container:getItems()
    for index = 0, items:size() - 1 do if items:get(index) == ticket then return false end end
    return true
end

local function restoreTicket(fullType)
    local runtime = GodSystemApp.services and GodSystemApp.services.runtime or nil
    if not runtime or not runtime.giveItem then return false end
    local ok, items = runtime.giveItem(fullType, 1)
    return ok == true and #(items or {}) == 1
end

local function prepareReward(fullType)
    return GodSystemShopVariants and GodSystemShopVariants.createItem and GodSystemShopVariants.createItem(fullType, nil) or nil
end

local function prepareRewards(drawCount)
    local rewards, types = {}, {}
    for draw = 1, drawCount do
        local reward, fullType = nil, nil
        for _ = 1, 8 do
            fullType = GodSystemLottery and GodSystemLottery.drawCandidate and GodSystemLottery.drawCandidate() or nil
            if not fullType then break end
            reward = prepareReward(fullType)
            if reward then break end
            if GodSystemLottery.evict then GodSystemLottery.evict(fullType) end
            reward, fullType = nil, nil
        end
        if not reward or not fullType then return nil, nil end
        rewards[#rewards + 1] = reward
        types[#types + 1] = fullType
    end
    return rewards, types
end

function Context.useLocalTicket(item, player)
    local fullType = item and item.getFullType and item:getFullType() or ""
    local ticket = GodSystemLottery and GodSystemLottery.ticketForFullType and GodSystemLottery.ticketForFullType(fullType) or nil
    local container = item and item.getContainer and item:getContainer() or nil
    if not ticket or not player or not isCarried(player, itemId(item)) or not container then
        notify("LotteryTicketInvalid", "This ticket is no longer carried.")
        return false
    end
    local ready, status = Cache.ensureStarted("sp")
    if not ready then
        local progress = Cache.status()
        notify(status == "unavailable" and "LotteryPoolUnavailable" or "LotteryPoolPreparing", "The prize pool is preparing. Please try again shortly.", { progress.processed or 0, progress.total or 0 })
        return false
    end

    local drawCount = math.max(1, math.min(10, math.floor(tonumber(ticket.draws) or 1)))
    local rewards, rewardTypes = prepareRewards(drawCount)
    if not rewards or #rewards ~= drawCount then
        notify("LotteryPoolEmpty", "No eligible prize is currently available.")
        return false
    end
    if not removeTicket(container, item) then
        notify("LotteryTicketInvalid", "This ticket is no longer carried.")
        return false
    end

    local inventory = player:getInventory()
    local added = {}
    for index = 1, #rewards do
        local ok, received = pcall(function() return inventory:AddItem(rewards[index]) end)
        if not ok or not received then
            for rollback = #added, 1, -1 do pcall(function() inventory:Remove(added[rollback]) end) end
            if not restoreTicket(ticket.fullType) then notify("LotteryRestoreFailed", "Prize delivery failed while restoring the ticket.") end
            notify("LotteryRewardUnavailable", "Prize delivery failed; the ticket was not consumed.")
            return false
        end
        added[#added + 1] = received
    end

    return Context.handleResult({
        lottery = true,
        ticketFullType = ticket.fullType,
        ticketKind = ticket.kind,
        drawCount = drawCount,
        rewards = rewardTypes,
        rewardFullType = rewardTypes[1],
    })
end

function Context.useTicket(item, playerNum)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
    local id = itemId(item)
    if not id or not isCarried(player, id) then
        notify("LotteryTicketInvalid", "This ticket is no longer carried.")
        return
    end
    if not isMultiplayer() then return Context.useLocalTicket(item, player) end
    local command = (Protocol.C2S and Protocol.C2S.UseLotteryTicket) or "useLotteryTicket"
    if GodSystemNetwork and type(GodSystemNetwork.send) == "function" then
        return GodSystemNetwork.send(command, { itemId = id })
    end
    notify("Lottery_NetworkUnavailable", "Lottery service is unavailable. Reload the MOD and try again.")
    return false
end

function Context.fillInventoryMenu(playerNum, context, items)
    local selected = items and items.__godSystemInventorySnapshot and items.items or selectedItems(items)
    if #selected ~= 1 then return end
    local item = selected[1]
    local entry = items and items.__godSystemInventorySnapshot and items.entries and items.entries[1] or nil
    local fullType = entry and entry.fullType or (item and item.getFullType and item:getFullType() or "")
    local ticket = entry and entry.isLotteryTicket
    if ticket == nil and GodSystemLottery and GodSystemLottery.isTicket then
        local ok, value = pcall(function() return GodSystemLottery.isTicket(fullType) end)
        ticket = ok and value == true or false
    end
    if ticket ~= true then return end
    local option = context:addOption(text("Context_UseLotteryTicket", "Use lottery ticket"), item, Context.useTicket, playerNum)
    -- Ownership is checked again by useTicket; do not recursively scan the whole inventory here.
    if items.__godSystemInventorySnapshot then
        local player = getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
        if not isCarriedShallow(player, item) then
            option.notAvailable = true
            option.toolTip = ISInventoryPaneContextMenu.addToolTip()
            option.toolTip.description = text("LotteryTicketInvalid", "This ticket is no longer carried.")
        end
    elseif not isCarried(getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer(), itemId(item)) then
        option.notAvailable = true
        option.toolTip = ISInventoryPaneContextMenu.addToolTip()
        option.toolTip.description = text("LotteryTicketInvalid", "This ticket is no longer carried.")
    end
end

local function itemLabel(fullType)
    if fullType and getItemNameFromFullType then
        local ok, value = pcall(getItemNameFromFullType, fullType)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    return tostring(fullType or "")
end

function Context.onResultClose()
end

function Context.handleResult(payload)
    if type(payload) ~= "table" or payload.lottery ~= true then return false end
    local lines = { text("Lottery_ResultTitle", "Lottery result"), "" }
    local rewards = type(payload.rewards) == "table" and payload.rewards or {}
    if #rewards == 0 and payload.rewardFullType then rewards[1] = payload.rewardFullType end
    if #rewards == 0 then
        lines[#lines + 1] = text("Lottery_ResultEmpty", "No item was obtained.")
    else
        for index = 1, #rewards do
            lines[#lines + 1] = formatText(text("Lottery_ResultItem", "Received: {1}"), { itemLabel(rewards[index]) })
        end
    end
    local height = math.min(520, math.max(160, 92 + (#rewards * 22)))
    local dialog = ISModalDialog:new(getCore():getScreenWidth() / 2 - 170, getCore():getScreenHeight() / 2 - (height / 2), 340, height, table.concat(lines, "\n"), false, Context, Context.onResultClose, nil, nil)
    dialog:initialise()
    GodSystemUI.presentOverlay(dialog)
    return true
end

if not isMultiplayer() and Cache then Cache.install("sp") end
GodSystemInventoryContext.register("lottery", Context.fillInventoryMenu)

return Context
