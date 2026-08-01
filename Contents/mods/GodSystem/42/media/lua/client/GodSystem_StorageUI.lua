require "GodSystem_StorageClient"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISContextMenu"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISWaitWhileGettingUp"
require "TimedActions/ISWearClothing"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISAttachItemHotbar"
require "GodSystem_ListState"

GodSystemStorageUI = GodSystemStorageUI or {}

local UI = GodSystemStorageUI
local Storage = GodSystemStorage
local Client = GodSystemStorageClient
local ListState = GodSystemListState

UI.window = UI.window or nil

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function isMultiplayerSession()
    return isClient and isClient() == true
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(value, query)
    return query == "" or string.find(lower(value), query, 1, true) ~= nil
end

local function cycleValue(values, current)
    local index = 1
    for i = 1, #values do if tostring(values[i]) == tostring(current) then index = i; break end end
    index = index + 1
    if index > #values then index = 1 end
    return values[index]
end

local function localizedGameText(key)
    if not getTextOrNull then return nil end
    local ok, value = pcall(getTextOrNull, tostring(key or ""))
    if ok and value and tostring(value) ~= "" then return tostring(value) end
    return nil
end

local function categoryLabel(category)
    category = tostring(category or "other")
    return text("Storage_Category_" .. category, category)
end

local function stateLabel(state)
    state = tostring(state or "")
    return text("Storage_State_" .. state, state)
end

local function roleLabel(role)
    role = Storage.normalizeRole(role)
    return text("Storage_Role_" .. role, role)
end

local function priorityLabel(tier)
    tier = Storage.normalizePriorityTier(tier)
    return text("Storage_Priority_" .. tier, tier)
end

local function containerDisplayName(row)
    row = type(row) == "table" and row or {}
    local slotType = tostring(row.slotType or row.containerType or "")
    local localized = localizedGameText("IGUI_ContainerTitle_" .. slotType)
        or localizedGameText("IGUI_Container_" .. slotType)
    local base = tostring(row.baseName or row.name or "")
    if localized and localized ~= slotType then
        if base ~= "" and base ~= slotType and base ~= "Container" and base ~= localized then
            return base .. " / " .. localized
        end
        return localized
    end
    if base ~= "" then return base end
    return slotType ~= "" and slotType or text("Storage_ContainerFallback", "容器")
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.01 then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end

local function styleButton(button, accent)
    button.backgroundColor = accent and { r = 0.06, g = 0.26, b = 0.34, a = 0.95 }
        or { r = 0.08, g = 0.14, b = 0.17, a = 0.95 }
    button.backgroundColorMouseOver = { r = 0.08, g = 0.32, b = 0.40, a = 0.98 }
    button.borderColor = { r = 0.12, g = 0.58, b = 0.72, a = 0.9 }
end

local function isControlDown()
    return Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LCONTROL) or isKeyDown(Keyboard.KEY_RCONTROL))
end

local function isShiftDown()
    return Keyboard and isKeyDown
        and (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
end

local function clearSet(values)
    for key in pairs(values) do values[key] = nil end
end

local function setCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

function UI.syncListScrollBar(list)
    if not list or not list.vscroll then return end
    list.vscroll:setX(math.max(0, list.width - 16))
    list.vscroll:setHeight(list.height)
end

function UI.clearList(list)
    if not list then return end
    list:clear()
    list:setYScroll(0)
    list:setScrollHeight(0)
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
    UI.syncListScrollBar(list)
end

local function resizeList(list, x, y, width, height)
    if not list then return end
    list:setX(x)
    list:setY(y)
    list:setWidth(math.max(40, width))
    list:setHeight(math.max(40, height))
    UI.syncListScrollBar(list)
end

local function textureForType(fullType)
    if not getScriptManager then return nil end
    local ok, result = pcall(function()
        local script = getScriptManager():FindItem(tostring(fullType or ""))
        return script and script:getNormalTexture() or nil
    end)
    return ok and result or nil
end

local function textureForItem(item)
    return Storage.safeCall(item, "getTex", nil)
        or Storage.safeCall(item, "getTexture", nil)
        or textureForType(Storage.itemFullType(item))
end

function UI.listRowClip(list, y, row)
    local rowHeight = Storage.number(row and row.height, Storage.number(list and list.itemheight, 0))
    if rowHeight <= 0 then return nil, nil, rowHeight end
    local scrollY = Storage.number(Storage.safeCall(list, "getYScroll", 0), 0)
    local viewportHeight = Storage.number(Storage.safeCall(list, "getHeight", list and list.height or 0), 0)
    local rowTop = Storage.number(y, 0) + scrollY
    local rowBottom = rowTop + rowHeight
    if rowBottom <= 0 or rowTop >= viewportHeight then return nil, nil, rowHeight end
    return math.max(0, rowTop), math.min(viewportHeight, rowBottom), rowHeight
end

function UI.drawListRow(list, y, row, alternate, selectedSet, forceSelected)
    if not row then return y end
    local clipY, clipY2, rowHeight = UI.listRowClip(list, y, row)
    if clipY == nil then return y + rowHeight end
    list:setStencilRect(0, clipY, list.width, clipY2 - clipY)
    local payload = row.item or {}
    local selected = forceSelected == true or (payload.key and selectedSet and selectedSet[payload.key] == true)
    if payload.kind == "divider" then
        list:drawRect(0, y, list.width, rowHeight, 0.82, 0.035, 0.055, 0.065)
        list:drawText(tostring(payload.label or row.text or ""), 7, y + 6, 0.67, 0.76, 0.80, 1, UIFont.Small)
        list:clearStencilRect()
        return y + rowHeight
    end
    if selected then
        list:drawRect(0, y, list.width, rowHeight, 0.88, 0.06, 0.28, 0.35)
        list:drawRect(0, y, 3, rowHeight, 1, 0.22, 0.68, 0.82)
    elseif alternate then
        list:drawRect(0, y, list.width, rowHeight, 0.28, 0.08, 0.12, 0.14)
    end
    local textX = 8
    if payload.texture then
        list:drawTextureScaledAspect(payload.texture, 6, y + 6, 32, 32, 1, 1, 1, 1)
        textX = 44
    end
    list:drawText(tostring(payload.displayText or row.text or ""), textX, y + 5, 0.86, 0.91, 0.93, 1, UIFont.Small)
    if payload.subtext then list:drawText(tostring(payload.subtext), textX, y + 23, 0.50, 0.66, 0.72, 1, UIFont.Small) end
    if payload.count and payload.count > 1 then
        list:drawTextRight("x" .. tostring(payload.count), list.width - 20, y + 7, 0.35, 0.80, 0.92, 1, UIFont.Small)
    end
    list:clearStencilRect()
    return y + rowHeight
end

local drawListRow = UI.drawListRow

local function listItemAt(list, x, y)
    if not list or not list.rowAt then return nil, nil end
    local index = list:rowAt(x, y)
    return index, index and list.items[index] and list.items[index].item or nil
end

local function sourceItemLabel(item)
    return tostring(Storage.safeCall(item, "getDisplayName", Storage.itemFullType(item)) or Storage.itemFullType(item))
end

local function sourceIsKeyRing(item)
    local fullType = lower(Storage.itemFullType(item))
    return string.find(fullType, "keyring", 1, true) ~= nil or string.find(fullType, "key_ring", 1, true) ~= nil
end

local function inventorySources(player)
    local result = {}
    local root = Storage.safeCall(player, "getInventory", nil)
    if not root then return result end
    result[1] = {
        key = "main",
        itemId = nil,
        item = nil,
        container = root,
        label = text("Storage_Target_Main", "Main inventory"),
    }
    local items = Storage.safeCall(root, "getItems", nil)
    local size = Storage.integer(Storage.safeCall(items, "size", 0), 0)
    for i = 0, size - 1 do
        local item = Storage.safeCall(items, "get", nil, i)
        local nested = Storage.safeCall(item, "getInventory", nil)
        if nested and (Storage.isEquippedItem(player, item) or sourceIsKeyRing(item)) then
            local id = Storage.itemId(item)
            if id then
                result[#result + 1] = {
                    key = "item:" .. id,
                    itemId = id,
                    item = item,
                    container = nested,
                    label = sourceItemLabel(item),
                    texture = textureForItem(item),
                }
            end
        end
    end
    return result
end

local function findSource(sources, key)
    for i = 1, #sources do if tostring(sources[i].key) == tostring(key) then return sources[i], i end end
    return sources[1], 1
end

local function sourceDisplayLabel(linkId, snapshot)
    if tostring(linkId or "all") == "all" then return text("Storage_All", "All") end
    for i = 1, #((snapshot and snapshot.containers) or {}) do
        local row = snapshot.containers[i]
        if tostring(row.linkId or "") == tostring(linkId or "") then
            return tostring(row.name or text("Storage_Container", "Container")) .. " #" .. tostring(i)
        end
    end
    local value = tostring(linkId or "")
    return value ~= "" and ("#" .. value:sub(-6)) or text("Storage_All", "All")
end

local function truncateUtf8(value, maxCharacters)
    value = tostring(value or "")
    local byteIndex, characters = 1, 0
    while byteIndex <= #value and characters < maxCharacters do
        local lead = string.byte(value, byteIndex) or 0
        local width = lead >= 240 and 4 or (lead >= 224 and 3 or (lead >= 192 and 2 or 1))
        byteIndex = byteIndex + width
        characters = characters + 1
    end
    if byteIndex > #value then return value end
    return value:sub(1, byteIndex - 1) .. "..."
end

local function compactSourceNames(values)
    local result = {}
    for i = 1, math.min(#(values or {}), 2) do
        local value = truncateUtf8(values[i], 24)
        if value ~= "" then result[#result + 1] = value end
    end
    if #(values or {}) > 2 then result[#result + 1] = "+" .. tostring(#values - 2) end
    return table.concat(result, ", ")
end

local function warehouseRowSelected(window, payload)
    if not window or not payload or not payload.key then return false end
    if window.page == "manage" then return tostring(payload.key) == tostring(window.selectedLinkId or "") end
    return window.selectedWarehouseKeys[payload.key] == true
end

local function groupDirectItems(player, source)
    local groups, order = {}, {}
    local items = Storage.safeCall(source and source.container, "getItems", nil)
    local size = Storage.integer(Storage.safeCall(items, "size", 0), 0)
    for i = 0, size - 1 do
        local item = Storage.safeCall(items, "get", nil, i)
        if item then
            local equipped = source.itemId == nil and Storage.isEquippedItem(player, item)
            local section = equipped and "equipped" or "carried"
            local groupKey = Storage.itemGroupKey(item)
            local key = section .. ":" .. groupKey
            local group = groups[key]
            if not group then
                group = {
                    key = key,
                    groupKey = groupKey,
                    section = section,
                    fullType = Storage.itemFullType(item),
                    name = tostring(Storage.safeCall(item, "getDisplayName", Storage.itemFullType(item)) or ""),
                    category = Storage.categoryOf(item),
                    instances = {},
                    texture = textureForItem(item),
                    totalWeight = 0,
                }
                groups[key] = group
                order[#order + 1] = key
            end
            group.instances[#group.instances + 1] = item
            group.totalWeight = group.totalWeight + Storage.number(Storage.safeCall(item, "getActualWeight", 0), 0)
        end
    end
    table.sort(order, function(a, b)
        local ga, gb = groups[a], groups[b]
        if ga.section ~= gb.section then return ga.section == "equipped" end
        if lower(ga.name) ~= lower(gb.name) then return lower(ga.name) < lower(gb.name) end
        return tostring(ga.key) < tostring(gb.key)
    end)
    return groups, order
end

local function selectedGroupsInOrder(rows, selected)
    local result = {}
    for i = 1, #rows do
        local row = rows[i]
        if row and row.key and selected[row.key] then result[#result + 1] = row end
    end
    return result
end

local function chooseFromGroup(group, mode)
    local count = #(group and group.instances or {})
    if mode == "one" then count = math.min(1, count)
    elseif mode == "half" then count = math.ceil(count / 2) end
    local result = {}
    for i = 1, count do
        local id = Storage.itemId(group.instances[i])
        if id then result[#result + 1] = id end
    end
    return result
end

local function equipmentState(player, item)
    if not Storage.isEquippedItem(player, item) then return nil end
    local state = {
        itemId = Storage.itemId(item),
        primary = Storage.safeCall(player, "getPrimaryHandItem", nil) == item,
        secondary = Storage.safeCall(player, "getSecondaryHandItem", nil) == item,
    }
    local worn = Storage.safeCall(player, "getWornItems", nil)
    local size = Storage.integer(Storage.safeCall(worn, "size", 0), 0)
    for i = 0, size - 1 do
        local entry = Storage.safeCall(worn, "get", nil, i)
        if Storage.safeCall(entry, "getItem", entry) == item then
            state.wornLocation = tostring(Storage.safeCall(entry, "getLocation", Storage.safeCall(item, "getBodyLocation", "")) or "")
            break
        end
    end
    local hotbar = getPlayerHotbar and getPlayerHotbar(Storage.integer(Storage.safeCall(player, "getPlayerNum", 0), 0)) or nil
    if hotbar and type(hotbar.attachedItems) == "table" then
        for slotIndex, attached in pairs(hotbar.attachedItems) do
            if attached == item then
                local slotRow = type(hotbar.availableSlot) == "table" and hotbar.availableSlot[slotIndex] or nil
                state.hotbar = {
                    slotIndex = slotIndex,
                    slot = Storage.safeCall(item, "getAttachedToModel", nil),
                    slotDef = slotRow and slotRow.def or nil,
                }
                break
            end
        end
    end
    return state
end

local function queueRestoreState(player, state)
    if not player or type(state) ~= "table" then return end
    local root = Storage.safeCall(player, "getInventory", nil)
    local item = root and Storage.findItemRecursive(root, state.itemId) or nil
    if not item then return end
    if state.wornLocation and state.wornLocation ~= "" then
        local occupied = Storage.safeCall(player, "getWornItem", nil, state.wornLocation)
        if not occupied then ISTimedActionQueue.add(ISWearClothing:new(player, item)) end
    end
    local primary = Storage.safeCall(player, "getPrimaryHandItem", nil)
    local secondary = Storage.safeCall(player, "getSecondaryHandItem", nil)
    if state.primary and state.secondary and not primary and not secondary then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(player, item, 50, true, true))
    else
        if state.primary and not primary then ISTimedActionQueue.add(ISEquipWeaponAction:new(player, item, 50, true, false)) end
        if state.secondary and not secondary then ISTimedActionQueue.add(ISEquipWeaponAction:new(player, item, 50, false, false)) end
    end
    if state.hotbar then
        local hotbar = getPlayerHotbar and getPlayerHotbar(Storage.integer(Storage.safeCall(player, "getPlayerNum", 0), 0)) or nil
        local slotIndex = state.hotbar.slotIndex
        local slotRow = hotbar and type(hotbar.availableSlot) == "table" and hotbar.availableSlot[slotIndex] or nil
        if hotbar and slotRow and not hotbar.attachedItems[slotIndex] then
            local slotDef = state.hotbar.slotDef or slotRow.def
            local slot = state.hotbar.slot
            if slotDef and slotDef.attachments and Storage.safeCall(item, "getAttachmentType", nil) then
                slot = slotDef.attachments[Storage.safeCall(item, "getAttachmentType", nil)] or slot
            end
            if slot and slotDef then ISTimedActionQueue.add(ISAttachItemHotbar:new(player, item, slot, slotIndex, slotDef)) end
        end
    end
end

GodSystemStorageWindow = ISCollapsableWindow:derive("GodSystemStorageWindow")

function GodSystemStorageWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.resizable = true
    o.minimumWidth = 1120
    o.minimumHeight = 650
    o.page = "storage"
    o.category = "all"
    o.state = "all"
    o.sourceFilter = "all"
    o.modName = "all"
    o.sortMode = "name"
    o.containerStatus = "all"
    o.currentSourceKey = "main"
    o.selectedInventoryKeys = {}
    o.selectedWarehouseKeys = {}
    o.inventoryAnchorKey = nil
    o.warehouseAnchorKey = nil
    o.selectedLinkId = nil
    o.selectedInstanceId = nil
    o.inventoryRows = {}
    o.warehouseRows = {}
    o.sources = {}
    o.pendingEquipment = nil
    o.title = text("Storage_Title", "System Storage Network")
    return o
end

function GodSystemStorageWindow:createButton(x, y, width, height, label, internal, handler, accent)
    local button = ISButton:new(x, y, width, height, label, self, handler)
    button.internal = internal
    button:initialise()
    styleButton(button, accent)
    self:addChild(button)
    return button
end

function GodSystemStorageWindow:createList(x, y, width, height, itemHeight, clickHandler, selectedSet)
    local list = ISScrollingListBox:new(x, y, width, height)
    list:initialise()
    list:instantiate()
    list.itemheight = itemHeight
    list:setOnMouseDownFunction(self, clickHandler)
    list.doDrawItem = function(owner, rowY, row, alternate)
        return drawListRow(owner, rowY, row, alternate, selectedSet)
    end
    local originalPrerender = list.prerender
    list.prerender = function(owner)
        UI.syncListScrollBar(owner)
        local result = originalPrerender(owner)
        UI.syncListScrollBar(owner)
        return result
    end
    self:addChild(list)
    return list
end

function GodSystemStorageWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.storageTab = self:createButton(14, 30, 120, 30, text("Storage_Tab_Storage", "Storage"), "storage", self.onPage, true)
    self.personalTab = self:createButton(142, 30, 176, 30, text("Storage_Tab_Personal", "实体网络 ↔ 个人仓"), "personal", self.onPage)
    self.manageTab = self:createButton(326, 30, 160, 30, text("Storage_Tab_Containers", "Container management"), "manage", self.onPage)
    self.statusLabel = ISLabel:new(500, 37, 20, "", 0.66, 0.82, 0.88, 1, UIFont.Small, true)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    self.searchBox = ISTextEntryBox:new("", 14, 68, 250, 28)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.target = self
    self.searchBox.onTextChange = function() self:rebuildLists(false) end
    self:addChild(self.searchBox)
    self.categoryButton = self:createButton(272, 68, 118, 28, "", "category", self.onFilter)
    self.categoryButton.onRightMouseUp = function(_, x, y)
        return self:onCategoryRightMouseUp(x, y)
    end
    self.stateButton = self:createButton(396, 68, 118, 28, "", "state", self.onFilter)
    self.sourceFilterButton = self:createButton(520, 68, 136, 28, "", "source", self.onFilter)
    self.modButton = self:createButton(662, 68, 116, 28, "", "mod", self.onFilter)
    self.containerStatusButton = self:createButton(272, 68, 160, 28, "", "containerStatus", self.onFilter)
    self.sortButton = self:createButton(784, 68, 120, 28, "", "sort", self.onFilter)
    self.refreshButton = self:createButton(912, 68, 86, 28, text("Storage_Refresh", "Refresh"), "refresh", self.onAction, true)

    self.sourceList = self:createList(14, 104, 320, 102, 30, self.onSourceSelection, nil)
    self.sourceList.doDrawItem = function(list, y, row, alternate)
        if not row then return y end
        local payload = row.item or {}
        local selected = tostring(payload.key or "") == tostring(self.currentSourceKey or "")
        if selected then list:drawRect(0, y, list.width, row.height, 0.88, 0.06, 0.28, 0.35)
        elseif alternate then list:drawRect(0, y, list.width, row.height, 0.25, 0.08, 0.12, 0.14) end
        local textX = 7
        if payload.texture then list:drawTextureScaledAspect(payload.texture, 5, y + 3, 24, 24, 1, 1, 1, 1); textX = 34 end
        list:drawText(tostring(payload.label or row.text or ""), textX, y + 7, 0.84, 0.91, 0.94, 1, UIFont.Small)
        return y + row.height
    end
    self.inventoryList = self:createList(14, 212, 320, 300, 46, self.onInventorySelection, self.selectedInventoryKeys)
    self.warehouseList = self:createList(342, 104, 470, 408, 46, self.onWarehouseSelection, self.selectedWarehouseKeys)
    self.warehouseList.doDrawItem = function(list, y, row, alternate)
        local payload = row and row.item or nil
        return drawListRow(list, y, row, alternate, self.selectedWarehouseKeys,
            warehouseRowSelected(self, payload))
    end
    self.detailList = self:createList(820, 104, 286, 408, 26, self.onDetailSelection, nil)
    self.detailList.doDrawItem = function(list, y, row, alternate)
        if not row then return y end
        local payload = row.item or {}
        local selected = payload.kind == "instance" and tostring(payload.itemId) == tostring(self.selectedInstanceId)
        if selected then list:drawRect(0, y, list.width, row.height, 0.78, 0.06, 0.28, 0.35)
        elseif alternate then list:drawRect(0, y, list.width, row.height, 0.20, 0.08, 0.12, 0.14) end
        list:drawText(tostring(payload.displayText or row.text or ""), 7, y + 6, 0.72, 0.82, 0.86, 1, UIFont.Small)
        return y + row.height
    end

    local oldInventoryRight = self.inventoryList.onRightMouseUp
    self.inventoryList.onRightMouseUp = function(_, x, y)
        if self:onInventoryRightMouseUp(x, y) then return true end
        if oldInventoryRight then return oldInventoryRight(self.inventoryList, x, y) end
        return false
    end
    local oldWarehouseRight = self.warehouseList.onRightMouseUp
    self.warehouseList.onRightMouseUp = function(_, x, y)
        if self:onWarehouseRightMouseUp(x, y) then return true end
        if oldWarehouseRight then return oldWarehouseRight(self.warehouseList, x, y) end
        return false
    end

    self.depositSelectedButton = self:createButton(14, self.height - 44, 132, 32,
        text("Storage_DepositSelected", "Deposit selected"), "depositSelected", self.onAction, true)
    self.depositSourceAllButton = self:createButton(152, self.height - 44, 190, 32,
        text("Storage_DepositSourceAll", "Deposit current container"), "depositSourceAll", self.onAction)
    self.withdrawSelectedButton = self:createButton(self.width - 152, self.height - 44, 138, 32,
        text("Storage_WithdrawSelected", "Withdraw selected"), "withdrawSelected", self.onAction, true)
    self.bridgeDepositButton = self:createButton(14, self.height - 44, 220, 32,
        text("PersonalStorage_FromPhysical", "转入个人仓"), "bridgeDeposit", self.onAction, true)
    self.bridgeWithdrawButton = self:createButton(242, self.height - 44, 220, 32,
        text("PersonalStorage_OpenBridge", "从个人仓转入实体网络"), "bridgeWithdraw", self.onAction)

    self.connectModeButton = self:createButton(14, self.height - 44, 145, 32,
        text("Storage_ConnectMode", "Connection mode"), "connectMode", self.onManageAction, true)
    self.roleButton = self:createButton(167, self.height - 44, 142, 32, text("Storage_Role", "Role"), "role", self.onManageAction)
    self.priorityDownButton = self:createButton(317, self.height - 44, 68, 32,
        text("Storage_PriorityDown", "降一档"), "priorityDown", self.onManageAction)
    self.priorityUpButton = self:createButton(393, self.height - 44, 68, 32,
        text("Storage_PriorityUp", "升一档"), "priorityUp", self.onManageAction)
    self.unlinkButton = self:createButton(469, self.height - 44, 126, 32, text("Storage_Unlink", "Remove link"), "unlink", self.onManageAction)
    self.takeOverButton = self:createButton(603, self.height - 44, 130, 32, text("Storage_TakeOver", "Admin take over"), "takeOver", self.onManageAction)
    self.organizerButton = self:createButton(741, self.height - 44, 132, 32,
        text("Storage_Organizer_Start", "整理仓库"), "organizerStart", self.onManageAction, true)
    self.organizerStopButton = self:createButton(881, self.height - 44, 132, 32,
        text("Storage_Organizer_Stop", "停止整理"), "organizerStop", self.onManageAction)

    self:layoutColumns()
    self:updatePageVisibility()
    self:rebuild()
end

function GodSystemStorageWindow:layoutColumns()
    if not self.sourceList then return end
    local margin, gap, top, bottom = 14, 8, 104, 54
    local innerWidth = self.width - (margin * 2)
    local contentHeight = math.max(220, self.height - top - bottom)
    local detailWidth = math.max(290, math.floor(innerWidth * 0.27))
    local inventoryWidth = math.max(320, math.floor(innerWidth * 0.30))
    if self.page ~= "storage" then inventoryWidth = 0 end
    local warehouseWidth = innerWidth - detailWidth - gap - (inventoryWidth > 0 and (inventoryWidth + gap) or 0)
    local warehouseX = margin + (inventoryWidth > 0 and (inventoryWidth + gap) or 0)
    local detailX = warehouseX + warehouseWidth + gap
    local sourceHeight = math.min(112, math.max(90, math.floor(contentHeight * 0.22)))
    resizeList(self.sourceList, margin, top, inventoryWidth, sourceHeight)
    resizeList(self.inventoryList, margin, top + sourceHeight + 6, inventoryWidth, contentHeight - sourceHeight - 6)
    resizeList(self.warehouseList, warehouseX, top, warehouseWidth, contentHeight)
    resizeList(self.detailList, detailX, top, detailWidth, contentHeight)

    self.searchBox:setWidth(math.max(180, math.min(260, math.floor(self.width * 0.20))))
    self.refreshButton:setX(self.width - margin - self.refreshButton.width)
    self.sortButton:setX(self.refreshButton.x - gap - self.sortButton.width)
    self.withdrawSelectedButton:setX(self.width - margin - self.withdrawSelectedButton.width)
    local actionY = self.height - 44
    local buttons = {
        self.depositSelectedButton, self.depositSourceAllButton, self.withdrawSelectedButton,
        self.bridgeDepositButton, self.bridgeWithdrawButton,
        self.connectModeButton, self.roleButton, self.priorityDownButton, self.priorityUpButton, self.unlinkButton, self.takeOverButton,
        self.organizerButton, self.organizerStopButton,
    }
    for i = 1, #buttons do buttons[i]:setY(actionY) end
end

function GodSystemStorageWindow:onResize()
    ISCollapsableWindow.onResize(self)
    self:layoutColumns()
end

function GodSystemStorageWindow:onPage(button)
    self.page = button.internal
    self:updatePageVisibility()
    self:layoutColumns()
    self:rebuild(false)
end

function GodSystemStorageWindow:updatePageVisibility()
    local storagePage = self.page == "storage"
    local personalPage = self.page == "personal"
    local managePage = self.page == "manage"
    self.sourceList:setVisible(storagePage)
    self.inventoryList:setVisible(storagePage)
    self.categoryButton:setVisible(storagePage or personalPage)
    self.stateButton:setVisible(storagePage or personalPage)
    self.sourceFilterButton:setVisible(storagePage or personalPage)
    self.modButton:setVisible(storagePage or personalPage)
    self.containerStatusButton:setVisible(managePage)
    local storageButtons = { self.depositSelectedButton, self.depositSourceAllButton, self.withdrawSelectedButton }
    for i = 1, #storageButtons do storageButtons[i]:setVisible(storagePage) end
    self.bridgeDepositButton:setVisible(personalPage)
    self.bridgeWithdrawButton:setVisible(personalPage)
    local manageButtons = {
        self.connectModeButton, self.roleButton, self.priorityDownButton, self.priorityUpButton,
        self.unlinkButton, self.organizerButton, self.organizerStopButton,
    }
    for i = 1, #manageButtons do manageButtons[i]:setVisible(managePage) end
    self.takeOverButton:setVisible(managePage and isMultiplayerSession()
        and (Client.networkState or {}).isAdmin == true)
    styleButton(self.storageTab, storagePage)
    styleButton(self.personalTab, personalPage)
    styleButton(self.manageTab, managePage)
end

function GodSystemStorageWindow:onFilter(button)
    if button.internal == "category" then
        local values = { "all" }
        for i = 1, #Storage.Categories do values[#values + 1] = Storage.Categories[i] end
        self.category = cycleValue(values, self.category)
    elseif button.internal == "state" then
        self.state = cycleValue({ "all", "fresh", "stale", "rotten", "chilled", "frozen", "damaged", "favorite" }, self.state)
    elseif button.internal == "source" then
        local values = { "all" }
        for i = 1, #(((Client.snapshot or {}).containers) or {}) do
            values[#values + 1] = tostring(Client.snapshot.containers[i].linkId)
        end
        self.sourceFilter = cycleValue(values, self.sourceFilter)
    elseif button.internal == "mod" then
        local values, seen = { "all" }, { all = true }
        for i = 1, #(((Client.snapshot or {}).groups) or {}) do
            local value = tostring(Client.snapshot.groups[i].modName or "")
            if value ~= "" and not seen[value] then seen[value] = true; values[#values + 1] = value end
        end
        self.modName = cycleValue(values, self.modName)
    elseif button.internal == "containerStatus" then
        self.containerStatus = cycleValue({ "all", "online", "offline", "full", "cold" }, self.containerStatus)
    elseif button.internal == "sort" then
        self.sortMode = cycleValue({ "name", "count", "weight", "condition", "spoilage", "source" }, self.sortMode)
    end
    self:rebuildLists(false)
end

function GodSystemStorageWindow:selectCategory(category)
    category = tostring(category or "all")
    if category ~= "all" then
        local valid = false
        for i = 1, #Storage.Categories do
            if category == tostring(Storage.Categories[i]) then
                valid = true
                break
            end
        end
        if not valid then return false end
    end
    if self.category == category then return false end
    self.category = category
    self:rebuildLists(false)
    return true
end

function GodSystemStorageWindow:onCategoryRightMouseUp(_, _)
    if self.page ~= "storage" then return false end
    local player = getPlayer and getPlayer() or nil
    local playerNum = Storage.integer(Storage.safeCall(player, "getPlayerNum", 0), 0)
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(text("Storage_Category_all", "All"), self, self.selectCategory, "all")
    for i = 1, #Storage.Categories do
        local category = tostring(Storage.Categories[i])
        context:addOption(text("Storage_Category_" .. category, category), self, self.selectCategory, category)
    end
    return true
end

function GodSystemStorageWindow:filterGroup(group, query)
    if self.category ~= "all" and tostring(group.category) ~= self.category then return false end
    if self.state ~= "all" then
        local found = false
        for i = 1, #(group.states or {}) do if tostring(group.states[i]) == self.state then found = true; break end end
        if not found then return false end
    end
    if self.sourceFilter ~= "all" then
        local found = false
        for i = 1, #(group.sources or {}) do if tostring(group.sources[i]) == self.sourceFilter then found = true; break end end
        if not found then return false end
    end
    if self.modName ~= "all" and tostring(group.modName) ~= self.modName then return false end
    return contains(table.concat({
        tostring(group.name or ""), tostring(group.fullType or ""), tostring(group.modName or ""),
        tostring(group.category or ""), table.concat(group.sourceNames or {}, " "),
    }, " "), query)
end

function GodSystemStorageWindow:sortGroups(groups)
    local mode = self.sortMode
    table.sort(groups, function(a, b)
        if mode == "count" and a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
        if mode == "weight" and a.totalWeight ~= b.totalWeight then return (a.totalWeight or 0) > (b.totalWeight or 0) end
        if mode == "condition" and a.bestCondition ~= b.bestCondition then return (a.bestCondition or 0) > (b.bestCondition or 0) end
        if mode == "spoilage" and a.earliestSpoilage ~= b.earliestSpoilage then return (a.earliestSpoilage or 0) < (b.earliestSpoilage or 0) end
        if mode == "source" then
            local as, bs = tostring((a.sourceNames or {})[1] or ""), tostring((b.sourceNames or {})[1] or "")
            if as ~= bs then return as < bs end
        end
        if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
        return tostring(a.key) < tostring(b.key)
    end)
end

function GodSystemStorageWindow:currentSource()
    return findSource(self.sources or {}, self.currentSourceKey)
end

function GodSystemStorageWindow:listStateContext(listName)
    listName = tostring(listName or "")
    local query = lower(self.searchBox and self.searchBox:getText() or "")
    local parts = {
        "page=" .. tostring(self.page or "storage"),
        "list=" .. listName,
        "query=" .. query,
        "category=" .. tostring(self.category or "all"),
        "state=" .. tostring(self.state or "all"),
        "sourceFilter=" .. tostring(self.sourceFilter or "all"),
        "mod=" .. tostring(self.modName or "all"),
        "sort=" .. tostring(self.sortMode or "name"),
        "containerStatus=" .. tostring(self.containerStatus or "all"),
    }
    if listName == "source" or listName == "inventory" then
        parts[#parts + 1] = "source=" .. tostring(self.currentSourceKey or "main")
    elseif listName == "detail" then
        parts[#parts + 1] = "link=" .. tostring(self.selectedLinkId or "")
        parts[#parts + 1] = "instance=" .. tostring(self.selectedInstanceId or "")
        parts[#parts + 1] = "warehouse=" .. tostring(self.warehouseAnchorKey or "")
    end
    return table.concat(parts, "\30")
end

function GodSystemStorageWindow:listStateKey(listName, payload, row, index)
    if listName == "detail" then
        if payload and payload.itemId ~= nil then return "instance:" .. tostring(payload.itemId) end
        return payload and payload.displayText and ("detail:" .. tostring(index)) or nil
    end
    return payload and payload.key and tostring(payload.key) or nil
end

function GodSystemStorageWindow:captureListState(listName, list)
    if not ListState then return nil end
    return ListState.capture(list, self:listStateContext(listName), function(payload, row, index)
        return self:listStateKey(listName, payload, row, index)
    end)
end

function GodSystemStorageWindow:restoreListState(listName, list, state)
    if not ListState or not state then return false end
    local context = self:listStateContext(listName)
    local keyOf = function(payload, row, index)
        return self:listStateKey(listName, payload, row, index)
    end
    local restored = ListState.restore(list, state, context, keyOf)
    if restored then ListState.restoreNextTick(list, state, context, keyOf) end
    return restored
end

function GodSystemStorageWindow:captureListStates()
    return {
        source = self:captureListState("source", self.sourceList),
        inventory = self:captureListState("inventory", self.inventoryList),
        warehouse = self:captureListState("warehouse", self.warehouseList),
        detail = self:captureListState("detail", self.detailList),
    }
end

function GodSystemStorageWindow:restoreListStates(states)
    if type(states) ~= "table" then return end
    self:restoreListState("source", self.sourceList, states.source)
    self:restoreListState("inventory", self.inventoryList, states.inventory)
    self:restoreListState("warehouse", self.warehouseList, states.warehouse)
    self:restoreListState("detail", self.detailList, states.detail)
end

function GodSystemStorageWindow:rebuildSources(preserveState)
    local listState = preserveState == true and self:captureListState("source", self.sourceList) or nil
    local player = getPlayer and getPlayer() or nil
    self.sources = inventorySources(player)
    local current, selectedIndex = findSource(self.sources, self.currentSourceKey)
    self.currentSourceKey = current and current.key or "main"
    UI.clearList(self.sourceList)
    for i = 1, #self.sources do
        local source = self.sources[i]
        self.sourceList:addItem(source.label, source)
        if tostring(source.key) == tostring(self.currentSourceKey) then selectedIndex = i end
    end
    self.sourceList.selected = selectedIndex or 1
    self:restoreListState("source", self.sourceList, listState)
end

function GodSystemStorageWindow:rebuildInventory(preserveState)
    local listState = preserveState == true and self:captureListState("inventory", self.inventoryList) or nil
    local player = getPlayer and getPlayer() or nil
    local source = self:currentSource()
    local groups, order = groupDirectItems(player, source)
    self.inventoryRows = {}
    UI.clearList(self.inventoryList)
    local query = lower(self.searchBox and self.searchBox:getText() or "")
    local valid, lastSection = {}, nil
    for i = 1, #order do
        local group = groups[order[i]]
        if contains(group.name .. " " .. group.fullType .. " " .. group.category, query) then
            if group.section ~= lastSection then
                lastSection = group.section
                local label = group.section == "equipped" and text("Storage_InventoryEquipped", "Equipped")
                    or text("Storage_InventoryCarried", "Contents")
                local row = self.inventoryList:addItem(label, { kind = "divider", label = label })
                row.height = 28
            end
            local payload = {
                kind = "inventoryGroup",
                key = group.key,
                group = group,
                displayText = group.name,
                subtext = tostring(group.category) .. " | " .. formatNumber(group.totalWeight) .. " kg",
                count = #group.instances,
                texture = group.texture,
            }
            self.inventoryList:addItem(group.name, payload)
            self.inventoryRows[#self.inventoryRows + 1] = group
            valid[group.key] = true
        end
    end
    for key in pairs(self.selectedInventoryKeys) do if not valid[key] then self.selectedInventoryKeys[key] = nil end end
    self:restoreListState("inventory", self.inventoryList, listState)
end

function GodSystemStorageWindow:rebuildWarehouse(preserveState)
    local listState = preserveState == true and self:captureListState("warehouse", self.warehouseList) or nil
    UI.clearList(self.warehouseList)
    self.warehouseRows = {}
    local snapshot = Client.snapshot
    if not snapshot then
        self.warehouseList:addItem(text("Storage_Loading", "Building storage index..."), { displayText = text("Storage_Loading", "Building storage index...") })
        self:restoreListState("warehouse", self.warehouseList, listState)
        return
    end
    local query = lower(self.searchBox and self.searchBox:getText() or "")
    local valid = {}
    if self.page ~= "manage" then
        local groups = {}
        for i = 1, #(snapshot.groups or {}) do if self:filterGroup(snapshot.groups[i], query) then groups[#groups + 1] = snapshot.groups[i] end end
        self:sortGroups(groups)
        for i = 1, #groups do
            local group = groups[i]
            local payload = {
                kind = "warehouseGroup",
                key = tostring(group.key),
                group = group,
                displayText = tostring(group.name or group.fullType),
                subtext = categoryLabel(group.category) .. " | " .. compactSourceNames(group.sourceNames)
                    .. " | " .. formatNumber(group.totalWeight) .. " kg",
                count = tonumber(group.count) or 0,
                texture = textureForType(group.fullType),
            }
            self.warehouseList:addItem(payload.displayText, payload)
            self.warehouseRows[#self.warehouseRows + 1] = group
            valid[payload.key] = true
        end
    else
        local rows = {}
        for i = 1, #(snapshot.containers or {}) do
            local row = snapshot.containers[i]
            local statusOk = self.containerStatus == "all"
                or (self.containerStatus == "online" and row.online == true)
                or (self.containerStatus == "offline" and row.online ~= true)
                or (self.containerStatus == "full" and row.online == true and (tonumber(row.used) or 0) >= (tonumber(row.capacity) or 0))
                or (self.containerStatus == "cold" and row.powered == true)
            local displayName = containerDisplayName(row)
            if statusOk and contains(table.concat({ displayName, row.name or "", roleLabel(row.role), row.linkId or "", row.objectId or "" }, " "), query) then
                row.displayName = displayName
                rows[#rows + 1] = row
            end
        end
        table.sort(rows, function(a, b)
            if a.isCoreHost ~= b.isCoreHost then return a.isCoreHost == true end
            if a.online ~= b.online then return a.online == true end
            if (a.priorityRank or 0) ~= (b.priorityRank or 0) then return (a.priorityRank or 0) > (b.priorityRank or 0) end
            return lower(a.displayName or a.name) < lower(b.displayName or b.name)
        end)
        for i = 1, #rows do
            local row = rows[i]
            local status = row.online and text("Storage_Online", "Online") or text("Storage_Offline", "Offline")
            local name = tostring(row.displayName or containerDisplayName(row))
            if row.isCoreHost then name = text("Storage_CoreHost", "Core host") .. " | " .. name end
            local payload = {
                kind = "container", key = tostring(row.linkId), container = row, displayText = name,
                subtext = status .. " | " .. roleLabel(row.role) .. " | " .. priorityLabel(row.priorityTier)
                    .. " | " .. formatNumber(row.used) .. "/" .. formatNumber(row.capacity),
            }
            self.warehouseList:addItem(name, payload)
            self.warehouseRows[#self.warehouseRows + 1] = row
            valid[payload.key] = true
            if tostring(row.linkId) == tostring(self.selectedLinkId) then self.warehouseList.selected = i end
        end
    end
    for key in pairs(self.selectedWarehouseKeys) do if not valid[key] then self.selectedWarehouseKeys[key] = nil end end
    if self.page == "manage" and self.selectedLinkId and not valid[tostring(self.selectedLinkId)] then
        self.selectedLinkId = nil
    end
    self:restoreListState("warehouse", self.warehouseList, listState)
end

function GodSystemStorageWindow:rebuildLists(preserveState)
    local states = preserveState == true and self:captureListStates() or nil
    self:rebuildSources(false)
    self:rebuildInventory(false)
    self:rebuildWarehouse(false)
    self:updateDetails(false)
    self:updateLabels()
    self:restoreListStates(states)
end

function GodSystemStorageWindow:rebuild(preserveState)
    self:rebuildLists(preserveState ~= false)
end

function GodSystemStorageWindow:updateMultiSelection(rows, selected, anchorField, key)
    if not key then return end
    if isShiftDown() and self[anchorField] then
        local first, last
        for i = 1, #rows do
            if tostring(rows[i].key) == tostring(self[anchorField]) then first = i end
            if tostring(rows[i].key) == tostring(key) then last = i end
        end
        if first and last then
            if not isControlDown() then clearSet(selected) end
            for i = math.min(first, last), math.max(first, last) do selected[rows[i].key] = true end
        end
    elseif isControlDown() then
        selected[key] = selected[key] ~= true and true or nil
        self[anchorField] = key
    else
        clearSet(selected)
        selected[key] = true
        self[anchorField] = key
    end
end

function GodSystemStorageWindow:onSourceSelection()
    local row = self.sourceList.items[self.sourceList.selected]
    local source = row and row.item
    if not source or not source.key then return end
    self.currentSourceKey = source.key
    clearSet(self.selectedInventoryKeys)
    self.inventoryAnchorKey = nil
    self:rebuildInventory(false)
    self:updateLabels()
end

function GodSystemStorageWindow:onInventorySelection()
    local row = self.inventoryList.items[self.inventoryList.selected]
    local payload = row and row.item
    if not payload or payload.kind ~= "inventoryGroup" then return end
    self:updateMultiSelection(self.inventoryRows, self.selectedInventoryKeys, "inventoryAnchorKey", payload.key)
end

function GodSystemStorageWindow:onWarehouseSelection()
    local row = self.warehouseList.items[self.warehouseList.selected]
    local payload = row and row.item
    if not payload then return end
    if self.page == "manage" and payload.kind == "container" then
        self.selectedLinkId = payload.key
    elseif payload.kind == "warehouseGroup" then
        self:updateMultiSelection(self.warehouseRows, self.selectedWarehouseKeys, "warehouseAnchorKey", payload.key)
        self.selectedInstanceId = nil
        Client.requestDetails(payload.key)
    end
    self:updateDetails(false)
    self:updateLabels()
end

function GodSystemStorageWindow:onDetailSelection()
    local row = self.detailList.items[self.detailList.selected]
    local payload = row and row.item
    if payload and payload.kind == "instance" then
        self.selectedInstanceId = payload.itemId
        self:updateWithdrawButton()
    end
end

function GodSystemStorageWindow:ensureInventoryRowSelected(payload)
    if not self.selectedInventoryKeys[payload.key] then
        clearSet(self.selectedInventoryKeys)
        self.selectedInventoryKeys[payload.key] = true
        self.inventoryAnchorKey = payload.key
    end
end

function GodSystemStorageWindow:ensureWarehouseRowSelected(payload)
    if not self.selectedWarehouseKeys[payload.key] then
        clearSet(self.selectedWarehouseKeys)
        self.selectedWarehouseKeys[payload.key] = true
        self.warehouseAnchorKey = payload.key
    end
end

function GodSystemStorageWindow:depositAmount(payload)
    if not payload then return end
    self:ensureInventoryRowSelected(payload)
    self:depositSelection(payload.mode)
end

function GodSystemStorageWindow:withdrawAmount(payload)
    if not payload then return end
    self:ensureWarehouseRowSelected(payload)
    self:withdrawSelection(payload.mode)
end

function GodSystemStorageWindow:onInventoryRightMouseUp(x, y)
    local index, payload = listItemAt(self.inventoryList, x, y)
    if not payload or payload.kind ~= "inventoryGroup" then return false end
    self.inventoryList.selected = index
    self:ensureInventoryRowSelected(payload)
    local context = ISContextMenu.get(Storage.integer(Storage.safeCall(getPlayer and getPlayer(), "getPlayerNum", 0), 0), getMouseX(), getMouseY())
    if setCount(self.selectedInventoryKeys) > 1 then
        context:addOption(text("Storage_Context_DepositSelectedAll", "Deposit all selected items"), self, self.depositAmount, { mode = "all", key = payload.key })
    else
        context:addOption(text("Storage_Context_DepositOne", "Deposit one"), self, self.depositAmount, { mode = "one", key = payload.key })
        context:addOption(text("Storage_Context_DepositHalf", "Deposit half"), self, self.depositAmount, { mode = "half", key = payload.key })
        context:addOption(text("Storage_Context_DepositAll", "Deposit all"), self, self.depositAmount, { mode = "all", key = payload.key })
    end
    return true
end

function GodSystemStorageWindow:onWarehouseRightMouseUp(x, y)
    local index, payload = listItemAt(self.warehouseList, x, y)
    if not payload then return false end
    self.warehouseList.selected = index
    if self.page == "manage" then
        if payload.kind ~= "container" then return false end
        self.selectedLinkId = payload.key
        self:showContainerRules(payload.container)
        return true
    end
    if payload.kind ~= "warehouseGroup" then return false end
    self.selectedInstanceId = nil
    self:updateWithdrawButton()
    self:ensureWarehouseRowSelected(payload)
    local context = ISContextMenu.get(Storage.integer(Storage.safeCall(getPlayer and getPlayer(), "getPlayerNum", 0), 0), getMouseX(), getMouseY())
    if setCount(self.selectedWarehouseKeys) > 1 then
        context:addOption(text("Storage_Context_WithdrawSelectedAll", "Withdraw all selected items"), self, self.withdrawAmount, { mode = "all", key = payload.key })
    else
        context:addOption(text("Storage_Context_WithdrawOne", "Withdraw one"), self, self.withdrawAmount, { mode = "one", key = payload.key })
        context:addOption(text("Storage_Context_WithdrawHalf", "Withdraw half"), self, self.withdrawAmount, { mode = "half", key = payload.key })
        context:addOption(text("Storage_Context_WithdrawAll", "Withdraw all"), self, self.withdrawAmount, { mode = "all", key = payload.key })
    end
    return true
end

function GodSystemStorageWindow:submitQueuedDeposit(itemIds, sourceItemId, states)
    self.pendingEquipment = { states = states or {}, itemIds = itemIds, sourceItemId = sourceItemId }
    local dispatched = Client.depositItems(itemIds, sourceItemId)
    if dispatched == false and self.pendingEquipment then
        local player = getPlayer and getPlayer() or nil
        for i = 1, #(states or {}) do queueRestoreState(player, states[i]) end
        self.pendingEquipment = nil
    end
end

function GodSystemStorageWindow.finishQueuedDeposit(window, itemIds, sourceItemId, states)
    if not window then return end
    local player = getPlayer and getPlayer() or nil
    local source = player and Storage.resolvePlayerContainer(player, sourceItemId) or nil
    local stateById, eligibleIds, eligibleStates = {}, {}, {}
    for i = 1, #(states or {}) do
        stateById[tostring(states[i].itemId or "")] = states[i]
    end
    for i = 1, #(itemIds or {}) do
        local itemId = tostring(itemIds[i] or "")
        local item = source and Storage.findDirectItem(source, itemId) or nil
        local state = stateById[itemId]
        if item and not Storage.isEquippedItem(player, item) then
            eligibleIds[#eligibleIds + 1] = itemId
            if state then eligibleStates[#eligibleStates + 1] = state; stateById[itemId] = nil end
        end
    end
    for _, state in pairs(stateById) do queueRestoreState(player, state) end
    if #eligibleIds == 0 then
        Client.notifyReason("nothingMoved")
        window:rebuildInventory(true)
        return
    end
    window:submitQueuedDeposit(eligibleIds, sourceItemId, eligibleStates)
end

function GodSystemStorageWindow:queueManualDeposit(itemIds)
    local player = getPlayer and getPlayer() or nil
    local source = self:currentSource()
    if not player or not source or #itemIds == 0 then return end
    if Client.hasPendingOperation and Client.hasPendingOperation("deposit") then
        Client.notifyReason("operationPending")
        return
    end
    local states, actions = {}, {}
    for i = 1, #itemIds do
        local item = Storage.findDirectItem(source.container, itemIds[i])
        local state = equipmentState(player, item)
        if state then states[#states + 1] = state; actions[#actions + 1] = item end
    end
    if #actions == 0 then self:submitQueuedDeposit(itemIds, source.itemId, states); return end
    for i = 1, #actions do ISTimedActionQueue.add(ISUnequipAction:new(player, actions[i], 50)) end
    local barrier = ISWaitWhileGettingUp:new(player)
    barrier:setOnComplete(GodSystemStorageWindow.finishQueuedDeposit, self, itemIds, source.itemId, states)
    ISTimedActionQueue.add(barrier)
end

function GodSystemStorageWindow:depositSelection(mode)
    local groups = selectedGroupsInOrder(self.inventoryRows, self.selectedInventoryKeys)
    if #groups == 0 then return end
    local itemIds = {}
    for i = 1, #groups do
        local selectedMode = #groups > 1 and "all" or (mode or "all")
        local ids = chooseFromGroup(groups[i], selectedMode)
        for j = 1, #ids do itemIds[#itemIds + 1] = ids[j] end
    end
    self:queueManualDeposit(itemIds)
end

function GodSystemStorageWindow:withdrawSelection(mode)
    if Client.hasPendingOperation and Client.hasPendingOperation("withdraw") then
        Client.notifyReason("operationPending")
        return
    end
    local groups = selectedGroupsInOrder(self.warehouseRows, self.selectedWarehouseKeys)
    if #groups == 0 then return end
    local source = self:currentSource()
    if #groups == 1 and self.selectedInstanceId then
        Client.withdrawRequests({ { groupKey = groups[1].key, itemIds = { self.selectedInstanceId } } },
            source and source.itemId or nil)
        return
    end
    local requests = {}
    for i = 1, #groups do
        local count = tonumber(groups[i].count) or 0
        local selectedMode = #groups > 1 and "all" or (mode or "all")
        if selectedMode == "one" then count = math.min(1, count)
        elseif selectedMode == "half" then count = math.ceil(count / 2) end
        requests[#requests + 1] = { groupKey = groups[i].key, count = count }
    end
    Client.withdrawRequests(requests, source and source.itemId or nil)
end

function GodSystemStorageWindow:bridgeRequests(mode)
    local groups = selectedGroupsInOrder(self.warehouseRows, self.selectedWarehouseKeys)
    if #groups == 0 then return {} end
    if #groups == 1 and self.selectedInstanceId then
        return { { groupKey = groups[1].key, itemIds = { self.selectedInstanceId } } }
    end
    local requests = {}
    for i = 1, #groups do
        local count = tonumber(groups[i].count) or 0
        local selectedMode = #groups > 1 and "all" or (mode or "all")
        if selectedMode == "one" then count = math.min(1, count)
        elseif selectedMode == "half" then count = math.ceil(count / 2) end
        requests[#requests + 1] = { groupKey = groups[i].key, count = count }
    end
    return requests
end

function GodSystemStorageWindow:bridgeSelection()
    local requests = self:bridgeRequests("all")
    if #requests == 0 then return end
    self.pendingBridgeRequests = requests
    GodSystemPersonalStorageClient.previewBridgeDeposit(requests)
end

function GodSystemStorageWindow:onBridgeConfirm(button)
    if button and button.internal == "YES" and self.pendingBridgeRequests then
        GodSystemPersonalStorageClient.bridgeDeposit(self.pendingBridgeRequests, true)
    end
end

function GodSystemStorageWindow:updateWithdrawButton()
    if not self.withdrawSelectedButton then return end
    self.withdrawSelectedButton:setTitle(self.selectedInstanceId
        and text("Storage_WithdrawExact", "Withdraw instance")
        or text("Storage_WithdrawSelected", "Withdraw selected"))
end

function GodSystemStorageWindow:restoreFailedEquipment(ok, payload)
    local pending = self.pendingEquipment
    if not pending then return end
    self.pendingEquipment = nil
    local success = {}
    if ok and type(payload) == "table" then
        for i = 1, #(payload.successItemIds or {}) do success[tostring(payload.successItemIds[i])] = true end
    end
    local player = getPlayer and getPlayer() or nil
    for i = 1, #(pending.states or {}) do
        local state = pending.states[i]
        if not success[tostring(state.itemId)] then queueRestoreState(player, state) end
    end
end

function GodSystemStorageWindow:updateDetails(preserveState)
    local listState = preserveState == true and self:captureListState("detail", self.detailList) or nil
    UI.clearList(self.detailList)
    if self.page == "manage" then
        local selected
        for i = 1, #(((Client.snapshot or {}).containers) or {}) do
            local row = Client.snapshot.containers[i]
            if tostring(row.linkId) == tostring(self.selectedLinkId) then selected = row; break end
        end
        if not selected then
            self.detailList:addItem(text("Storage_SelectContainer", "Select a connected container"), { displayText = text("Storage_SelectContainer", "Select a connected container") })
            self:restoreListState("detail", self.detailList, listState)
            return
        end
        local details = {
            containerDisplayName(selected),
            text("Storage_Status", "Status") .. ": " .. (selected.online and text("Storage_Online", "Online") or text("Storage_Offline", "Offline")),
            text("Storage_CoreHost", "Core host") .. ": " .. tostring(selected.isCoreHost == true),
            text("Storage_Role", "Role") .. ": " .. roleLabel(selected.role),
            text("Storage_Priority", "Priority") .. ": " .. priorityLabel(selected.priorityTier),
            text("Storage_Position", "Position") .. string.format(": %d,%d,%d", selected.x or 0, selected.y or 0, selected.z or 0),
            text("Storage_Capacity", "Capacity") .. ": " .. formatNumber(selected.used) .. "/" .. formatNumber(selected.capacity),
            text("Storage_Sources", "Sources") .. ": " .. sourceDisplayLabel(selected.linkId, Client.snapshot),
        }
        for i = 1, #details do self.detailList:addItem(details[i], { displayText = details[i] }) end
        self.unlinkButton.enable = selected.isCoreHost ~= true
        self:restoreListState("detail", self.detailList, listState)
        return
    end
    local selectedGroups = selectedGroupsInOrder(self.warehouseRows, self.selectedWarehouseKeys)
    local selected = selectedGroups[1]
    if not selected then
        self.detailList:addItem(text("Storage_SelectType", "Select an item type"), { displayText = text("Storage_SelectType", "Select an item type") })
        self:restoreListState("detail", self.detailList, listState)
        return
    end
    local rows = {
        tostring(selected.name or selected.fullType), tostring(selected.fullType or ""),
        text("Storage_Count", "Count") .. ": " .. tostring(selected.count or 0),
        text("Storage_Mod", "Mod") .. ": " .. tostring(selected.modName or ""),
        text("Storage_Category", "Category") .. ": " .. categoryLabel(selected.category),
        text("Storage_State", "State") .. ": " .. (function()
            local labels = {}
            for i = 1, #(selected.states or {}) do labels[#labels + 1] = stateLabel(selected.states[i]) end
            return table.concat(labels, ", ")
        end)(),
        text("Storage_Sources", "Sources") .. ": " .. compactSourceNames(selected.sourceNames),
    }
    for i = 1, #rows do self.detailList:addItem(rows[i], { displayText = rows[i] }) end
    local instances = Client.details[tostring(selected.key or "")] or {}
    local selectedInstanceFound = self.selectedInstanceId == nil
    for i = 1, math.min(#instances, 250) do
        local row = instances[i]
        if tostring(row.id) == tostring(self.selectedInstanceId) then selectedInstanceFound = true end
        local label = string.format("#%s | %s | %.0f%% | %.2fkg", tostring(row.id or "?"),
            compactSourceNames({ row.sourceName }), (tonumber(row.conditionRatio) or 0) * 100, tonumber(row.weight) or 0)
        self.detailList:addItem(label, { kind = "instance", itemId = row.id, displayText = label })
    end
    if #instances > 0 and not selectedInstanceFound then self.selectedInstanceId = nil end
    self:restoreListState("detail", self.detailList, listState)
end

function GodSystemStorageWindow:updateLabels()
    self.categoryButton:setTitle(text("Storage_Filter_Category", "Category") .. ": " .. text("Storage_Category_" .. self.category, self.category))
    self.stateButton:setTitle(text("Storage_Filter_State", "State") .. ": " .. text("Storage_State_" .. self.state, self.state))
    self.modButton:setTitle(text("Storage_Filter_Mod", "Mod") .. ": " .. tostring(self.modName))
    self.containerStatusButton:setTitle(text("Storage_Filter_Status", "Status") .. ": " .. text("Storage_ContainerStatus_" .. self.containerStatus, self.containerStatus))
    self.sortButton:setTitle(text("Storage_Sort", "Sort") .. ": " .. text("Storage_Sort_" .. self.sortMode, self.sortMode))
    local snapshot = Client.snapshot or {}
    self.statusLabel.name = string.format("%s %d | %s %d | %s %d/%d | %s %s/%s",
        text("Storage_Types", "Types"), tonumber(snapshot.groupCount) or #(snapshot.groups or {}),
        text("Storage_Instances", "Items"), tonumber(snapshot.itemCount) or 0,
        text("Storage_Containers", "Containers"), tonumber(snapshot.onlineLinks) or 0,
        (tonumber(snapshot.onlineLinks) or 0) + (tonumber(snapshot.offlineLinks) or 0),
        text("Storage_Capacity", "Capacity"), formatNumber(snapshot.usedCapacity), formatNumber(snapshot.totalCapacity))
    local selected
    for i = 1, #(snapshot.containers or {}) do
        if tostring(snapshot.containers[i].linkId) == tostring(self.selectedLinkId) then selected = snapshot.containers[i]; break end
    end
    self.roleButton:setTitle(text("Storage_Role", "Role") .. (selected and (": " .. roleLabel(selected.role)) or ""))
    local organizer = Client.organizer or { state = "idle" }
    local organizing = organizer.state == "running"
    local canManage = (Client.networkState or {}).canManage == true
    self.unlinkButton.enable = not organizing and (not selected or selected.isCoreHost ~= true)
    self.roleButton.enable = not organizing and selected ~= nil
    self.priorityDownButton.enable = not organizing and selected ~= nil
    self.priorityUpButton.enable = not organizing and selected ~= nil
    self.connectModeButton.enable = not organizing
    self.depositSelectedButton.enable = not organizing
    self.depositSourceAllButton.enable = not organizing
    self.withdrawSelectedButton.enable = not organizing
    self.organizerButton.enable = canManage and not organizing
    self.organizerStopButton.enable = canManage and organizing
    self.organizerStopButton:setVisible(self.page == "manage" and organizing)
    if organizing then
        self.statusLabel.name = text("Storage_Organizer_Progress", "整理中 {1}/{2}，已移动 {3}")
            :gsub("{1}", tostring(organizer.processed or 0))
            :gsub("{2}", tostring(organizer.total or 0))
            :gsub("{3}", tostring(organizer.moved or 0))
    end
    self.takeOverButton.enable = (Client.networkState or {}).isAdmin == true
    self.takeOverButton:setVisible(self.page == "manage" and isMultiplayerSession()
        and (Client.networkState or {}).isAdmin == true)
    self.sourceFilterButton:setTitle(text("Storage_Filter_Source", "Source") .. ": "
        .. sourceDisplayLabel(self.sourceFilter, snapshot))
    self:updateWithdrawButton()
end

function GodSystemStorageWindow:applyContainerSetting(payload)
    if not payload or not payload.linkId then return end
    Client.updateLink({
        linkId = payload.linkId,
        role = payload.role,
        priorityTier = payload.priorityTier,
    })
end

function GodSystemStorageWindow:showContainerRules(container)
    local context = ISContextMenu.get(Storage.integer(Storage.safeCall(getPlayer and getPlayer(), "getPlayerNum", 0), 0), getMouseX(), getMouseY())
    local roleRoot = context:addOption(text("Storage_Role", "Role"), nil, nil)
    local roleMenu = ISContextMenu:getNew(context)
    context:addSubMenu(roleRoot, roleMenu)
    for i = 1, #Storage.Roles do
        local role = Storage.Roles[i]
        local option = roleMenu:addOption(roleLabel(role), self, self.applyContainerSetting, {
            linkId = container.linkId,
            role = role,
        })
        if option and Storage.normalizeRole(container.role) == role then option.notAvailable = true end
    end
    local priorityRoot = context:addOption(text("Storage_Priority", "Priority"), nil, nil)
    local priorityMenu = ISContextMenu:getNew(context)
    context:addSubMenu(priorityRoot, priorityMenu)
    for i = #Storage.PriorityTiers, 1, -1 do
        local tier = Storage.PriorityTiers[i]
        local option = priorityMenu:addOption(priorityLabel(tier), self, self.applyContainerSetting, {
            linkId = container.linkId,
            priorityTier = tier,
        })
        if option and Storage.normalizePriorityTier(container.priorityTier) == tier then option.notAvailable = true end
    end
end

function GodSystemStorageWindow:onAction(button)
    if button.internal == "refresh" then Client.refresh(); self:rebuildInventory(true)
    elseif button.internal == "depositSelected" then self:depositSelection("all")
    elseif button.internal == "depositSourceAll" then
        local source = self:currentSource()
        if Client.hasPendingOperation and Client.hasPendingOperation("deposit") then
            Client.notifyReason("operationPending")
        else
            Client.depositAll(source and source.itemId or nil)
        end
    elseif button.internal == "withdrawSelected" then self:withdrawSelection("all")
    elseif button.internal == "bridgeDeposit" then self:bridgeSelection()
    elseif button.internal == "bridgeWithdraw" then GodSystemPersonalStorageUI.openBridge()
    end
end

function GodSystemStorageWindow:onManageAction(button)
    if button.internal == "connectMode" then
        if GodSystemStorageContext and GodSystemStorageContext.toggleConnectMode then GodSystemStorageContext.toggleConnectMode() end
        return
    end
    if button.internal == "takeOver" then Client.takeOver(); return end
    if button.internal == "organizerStart" then Client.startOrganizer(); return end
    if button.internal == "organizerStop" then Client.stopOrganizer(); return end
    if not self.selectedLinkId then return end
    local selected
    for i = 1, #(((Client.snapshot or {}).containers) or {}) do
        if tostring(Client.snapshot.containers[i].linkId) == tostring(self.selectedLinkId) then selected = Client.snapshot.containers[i]; break end
    end
    if not selected then return end
    if button.internal == "unlink" then
        if selected.isCoreHost ~= true then Client.unlink(self.selectedLinkId) end
    elseif button.internal == "role" then
        Client.updateLink({ linkId = self.selectedLinkId, role = cycleValue(Storage.Roles, Storage.normalizeRole(selected.role)) })
    elseif button.internal == "priorityDown" then
        local index = Storage.priorityRank(selected.priorityTier)
        Client.updateLink({ linkId = self.selectedLinkId, priorityTier = Storage.PriorityTiers[math.max(1, index - 1)] })
    elseif button.internal == "priorityUp" then
        local index = Storage.priorityRank(selected.priorityTier)
        Client.updateLink({ linkId = self.selectedLinkId, priorityTier = Storage.PriorityTiers[math.min(#Storage.PriorityTiers, index + 1)] })
    end
end

function GodSystemStorageWindow:close()
    ISCollapsableWindow.close(self)
    if UI.window == self then UI.window = nil end
end

function UI.open()
    if UI.window then UI.window:setVisible(true); UI.window:addToUIManager(); UI.window:rebuild(); return UI.window end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width = math.min(1480, math.max(1120, screenW - 80))
    local height = math.min(820, math.max(650, screenH - 80))
    local window = GodSystemStorageWindow:new(math.floor((screenW - width) / 2), math.floor((screenH - height) / 2), width, height)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    UI.window = window
    Client.requestOrganizerStatus()
    return window
end

function UI.depositExternalSelection(items, sourceItemId)
    if not UI.window then return false end
    local ids = {}
    for i = 1, #(items or {}) do local id = Storage.itemId(items[i]); if id then ids[#ids + 1] = id end end
    UI.window.currentSourceKey = sourceItemId and ("item:" .. tostring(sourceItemId)) or "main"
    UI.window:rebuildSources(false)
    UI.window:queueManualDeposit(ids)
    return #ids > 0
end

function UI.close()
    if UI.window then UI.window:close() end
end

function UI.onSnapshot()
    if UI.window then UI.window:rebuild(true) end
end

function UI.onDetails(groupKey)
    if UI.window and UI.window.selectedWarehouseKeys[tostring(groupKey or "")] then UI.window:updateDetails(true) end
end

function UI.onNetworkState()
    if UI.window then UI.window:updateLabels() end
end

function UI.onIndexStarted()
    if UI.window then UI.window.statusLabel.name = text("Storage_Loading", "Building storage index...") end
end

function UI.onOperationResult(command, ok, reason, payload)
    if UI.window and command == "deposit" then UI.window:restoreFailedEquipment(ok, payload) end
    if payload and GodSystem and GodSystem.notify and (command == "deposit" or command == "withdraw") then
        GodSystem.notify(text("Storage_TransferResult", "Moved {1}; skipped {2}; failed {3}; cold downgrade {4}")
            :gsub("{1}", tostring(payload.success or 0)):gsub("{2}", tostring(payload.skipped or 0))
            :gsub("{3}", tostring(payload.failed or 0)):gsub("{4}", tostring(payload.coldDowngrade or 0)))
    end
    if UI.window then
        if ok then UI.window.statusLabel.name = text("Storage_Refreshing", "Refreshing...") end
        UI.window:rebuildInventory(true)
    end
end

function UI.onPersonalPreview(payload)
    if not UI.window or not payload or payload.command ~= "bridgePreview" then return end
    if payload.ok ~= true then
        Client.notifyReason(payload.code or "internalError")
        return
    end
    local simplified = payload.simplified or {}
    if #simplified == 0 then
        GodSystemPersonalStorageClient.bridgeDeposit(UI.window.pendingBridgeRequests or {}, false)
        return
    end
    local names = {}
    for i = 1, math.min(#simplified, 8) do
        names[#names + 1] = tostring(simplified[i].name or simplified[i].fullType or "?")
    end
    local message = text("PersonalStorage_SimplifiedConfirm", "以下物品只能简化保存，是否继续：")
        .. "\n" .. table.concat(names, "、") .. (#simplified > 8 and "…" or "")
    local modal = ISModalDialog:new(UI.window.x + 120, UI.window.y + 120, 560, 240,
        message, true, UI.window, UI.window.onBridgeConfirm, 0)
    modal:initialise()
    modal:addToUIManager()
end

function UI.onPersonalOperationResult(command, outcome)
    if not UI.window or (command ~= "bridgeDeposit" and command ~= "bridgeWithdraw") then return end
    local stats = outcome and outcome.data or {}
    if GodSystem and GodSystem.notify then
        GodSystem.notify(text("PersonalStorage_BridgeResult", "转换完成：成功 {1}，跳过 {2}，失败 {3}")
            :gsub("{1}", tostring(stats.success or 0)):gsub("{2}", tostring(stats.skipped or 0))
            :gsub("{3}", tostring(stats.failed or 0)))
    end
    UI.window.pendingBridgeRequests = nil
end

function UI.onOrganizerStatus()
    if UI.window then UI.window:updateLabels() end
end

function UI.onError(args)
    if UI.window then
        if args and args.command == "deposit" and args.reason ~= "operationPending" then
            UI.window:restoreFailedEquipment(false, args.payload)
        end
        UI.window:updateLabels()
    end
end

function UI.onContainerUpdate()
    if UI.window and UI.window:isVisible() then UI.window:rebuild(true) end
end

if Events.OnContainerUpdate then
    Events.OnContainerUpdate.Remove(UI.onContainerUpdate)
    Events.OnContainerUpdate.Add(UI.onContainerUpdate)
end

return UI
