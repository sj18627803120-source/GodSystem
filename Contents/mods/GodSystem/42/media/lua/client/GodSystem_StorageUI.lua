require "GodSystem_StorageClient"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISContextMenu"

GodSystemStorageUI = GodSystemStorageUI or {}

local UI = GodSystemStorageUI
local Storage = GodSystemStorage
local Client = GodSystemStorageClient

UI.window = UI.window or nil

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(value, query)
    if query == "" then return true end
    return string.find(lower(value), query, 1, true) ~= nil
end

local function listContains(list, value)
    for i = 1, #(list or {}) do if tostring(list[i]) == tostring(value) then return true end end
    return false
end

local function cycleValue(values, current, direction)
    local index = 1
    for i = 1, #values do if tostring(values[i]) == tostring(current) then index = i; break end end
    index = index + (direction or 1)
    if index > #values then index = 1 end
    if index < 1 then index = #values end
    return values[index]
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.01 then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end

local function formatIndexTime(value)
    local seconds = math.floor((tonumber(value) or 0) / 1000)
    if seconds <= 0 or not os or not os.date then return "-" end
    local ok, result = pcall(os.date, "%H:%M:%S", seconds)
    return ok and tostring(result or "-") or "-"
end

local function styleButton(button, accent)
    button.backgroundColor = accent and { r = 0.06, g = 0.26, b = 0.38, a = 0.9 } or { r = 0.08, g = 0.12, b = 0.17, a = 0.9 }
    button.backgroundColorMouseOver = { r = 0.08, g = 0.34, b = 0.48, a = 0.95 }
    button.borderColor = { r = 0.12, g = 0.62, b = 0.78, a = 0.85 }
end

GodSystemStorageWindow = ISCollapsableWindow:derive("GodSystemStorageWindow")

function GodSystemStorageWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.resizable = true
    o.minimumWidth = 900
    o.minimumHeight = 560
    o.page = "storage"
    o.category = "all"
    o.state = "all"
    o.source = "all"
    o.modName = "all"
    o.sortMode = "name"
    o.containerStatus = "all"
    o.selectedGroupKey = nil
    o.selectedLinkId = nil
    o.selectedInstanceId = nil
    o.withdrawTargetItemId = nil
    o.filteredGroups = {}
    o.filteredContainers = {}
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

function GodSystemStorageWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local margin = 14
    local top = 30
    self.storageTab = self:createButton(margin, top, 130, 30, text("Storage_Tab_Storage", "Storage"), "storage", self.onPage, true)
    self.manageTab = self:createButton(margin + 138, top, 160, 30, text("Storage_Tab_Containers", "Container management"), "manage", self.onPage, false)
    self.statusLabel = ISLabel:new(margin + 310, top + 7, 20, "", 0.7, 0.86, 0.92, 1, UIFont.Small, true)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    self.searchLabel = ISLabel:new(margin, top + 46, 20, text("Storage_Search", "Search"), 0.75, 0.78, 0.82, 1, UIFont.Small, true)
    self.searchLabel:initialise()
    self:addChild(self.searchLabel)
    self.searchBox = ISTextEntryBox:new("", margin + 54, top + 42, 260, 26)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.target = self
    self.searchBox.onTextChange = function() self:rebuild() end
    self:addChild(self.searchBox)

    self.categoryButton = self:createButton(margin + 324, top + 42, 120, 26, "", "category", self.onFilter)
    self.stateButton = self:createButton(margin + 450, top + 42, 120, 26, "", "state", self.onFilter)
    self.sourceButton = self:createButton(margin + 576, top + 42, 145, 26, "", "source", self.onFilter)
    self.modButton = self:createButton(margin + 727, top + 42, 120, 26, "", "mod", self.onFilter)

    self.containerStatusButton = self:createButton(margin + 324, top + 42, 160, 26, "", "containerStatus", self.onFilter)
    self.containerStatusButton:setVisible(false)

    local listY = top + 78
    local actionH = 78
    local availableH = self.height - listY - actionH - 12
    local leftW = math.floor((self.width - (margin * 3)) * 0.58)
    local rightX = margin + leftW + margin
    local rightW = self.width - rightX - margin

    self.mainList = ISScrollingListBox:new(margin, listY, leftW, availableH)
    self.mainList:initialise()
    self.mainList:instantiate()
    self.mainList.itemheight = 38
    self.mainList:setOnMouseDownFunction(self, self.onMainSelection)
    local originalRightMouseUp = self.mainList.onRightMouseUp
    self.mainList.onRightMouseUp = function(list, x, y)
        if self:onMainRightMouseUp(x, y) then return true end
        if originalRightMouseUp then return originalRightMouseUp(list, x, y) end
        return false
    end
    self.mainList.doDrawItem = function(list, y, item, alt)
        if not item then return y end
        local selected = list.selected == item.index
        if selected then list:drawRect(0, y, list.width, item.height, 0.35, 0.04, 0.32, 0.45)
        elseif alt then list:drawRect(0, y, list.width, item.height, 0.16, 0.05, 0.08, 0.11) end
        list:drawText(tostring(item.text or ""), 8, y + 5, 0.85, 0.9, 0.94, 1, UIFont.Small)
        local sub = item.item and item.item.subtext
        if sub then list:drawText(tostring(sub), 8, y + 21, 0.5, 0.68, 0.74, 1, UIFont.Small) end
        return y + item.height
    end
    self:addChild(self.mainList)

    self.detailList = ISScrollingListBox:new(rightX, listY, rightW, availableH)
    self.detailList:initialise()
    self.detailList:instantiate()
    self.detailList.itemheight = 24
    self.detailList:setOnMouseDownFunction(self, self.onDetailSelection)
    self.detailList.doDrawItem = function(list, y, item, alt)
        if alt then list:drawRect(0, y, list.width, item.height, 0.12, 0.05, 0.08, 0.11) end
        list:drawText(tostring(item.text or ""), 7, y + 5, 0.74, 0.82, 0.86, 1, UIFont.Small)
        return y + item.height
    end
    self:addChild(self.detailList)

    local actionY = listY + availableH + 10
    self.refreshButton = self:createButton(margin, actionY, 100, 30, text("Storage_Refresh", "Refresh"), "refresh", self.onAction, true)
    self.depositAllButton = self:createButton(margin + 108, actionY, 150, 30, text("Storage_DepositAll", "Safe deposit all"), "depositAll", self.onAction, true)
    self.withdraw1Button = self:createButton(margin + 266, actionY, 86, 30, text("Storage_Withdraw1", "Take 1"), "withdraw1", self.onAction)
    self.withdraw5Button = self:createButton(margin + 360, actionY, 86, 30, text("Storage_Withdraw5", "Take 5"), "withdraw5", self.onAction)
    self.withdrawAllButton = self:createButton(margin + 454, actionY, 96, 30, text("Storage_WithdrawAll", "Take all"), "withdrawAll", self.onAction)
    self.countBox = ISTextEntryBox:new("1", margin + 558, actionY, 58, 30)
    self.countBox:initialise()
    self.countBox:instantiate()
    self.countBox:setOnlyNumbers(true)
    self:addChild(self.countBox)
    self.withdrawCustomButton = self:createButton(margin + 624, actionY, 110, 30, text("Storage_WithdrawCustom", "Take amount"), "withdrawCustom", self.onAction)
    self.sortButton = self:createButton(margin + 742, actionY, 120, 30, "", "sort", self.onAction)
    self.targetButton = self:createButton(margin + 266, actionY + 34, 250, 28, "", "target", self.onAction)
    self.exactButton = self:createButton(margin + 524, actionY + 34, 150, 28, text("Storage_WithdrawExact", "Take selected instance"), "withdrawExact", self.onAction)

    self.connectModeButton = self:createButton(margin, actionY, 145, 30, text("Storage_ConnectMode", "Connection mode"), "connectMode", self.onManageAction, true)
    self.roleButton = self:createButton(margin + 153, actionY, 130, 30, "", "role", self.onManageAction)
    self.priorityDownButton = self:createButton(margin + 291, actionY, 42, 30, "-10", "priorityDown", self.onManageAction)
    self.priorityUpButton = self:createButton(margin + 341, actionY, 42, 30, "+10", "priorityUp", self.onManageAction)
    self.unlinkButton = self:createButton(margin + 391, actionY, 120, 30, text("Storage_Unlink", "Remove link"), "unlink", self.onManageAction)
    self.radiusDownButton = self:createButton(margin + 519, actionY, 42, 30, "-5", "radiusDown", self.onManageAction)
    self.radiusUpButton = self:createButton(margin + 569, actionY, 42, 30, "+5", "radiusUp", self.onManageAction)
    self.limitDownButton = self:createButton(margin + 619, actionY, 42, 30, "-8", "limitDown", self.onManageAction)
    self.limitUpButton = self:createButton(margin + 669, actionY, 42, 30, "+8", "limitUp", self.onManageAction)
    self.takeOverButton = self:createButton(margin + 719, actionY, 130, 30, text("Storage_TakeOver", "Admin take over"), "takeOver", self.onManageAction)

    self:updatePageVisibility()
    self:rebuild()
end

function GodSystemStorageWindow:onResize()
    ISCollapsableWindow.onResize(self)
    if self.mainList then
        local margin = 14
        local listY = 108
        local actionH = 78
        local availableH = self.height - listY - actionH - 12
        local leftW = math.floor((self.width - (margin * 3)) * 0.58)
        local rightX = margin + leftW + margin
        self.mainList:setWidth(leftW)
        self.mainList:setHeight(availableH)
        self.detailList:setX(rightX)
        self.detailList:setWidth(self.width - rightX - margin)
        self.detailList:setHeight(availableH)
    end
end

function GodSystemStorageWindow:onPage(button)
    self.page = button.internal
    self:updatePageVisibility()
    self:rebuild()
end

function GodSystemStorageWindow:updatePageVisibility()
    local storagePage = self.page == "storage"
    self.categoryButton:setVisible(storagePage)
    self.stateButton:setVisible(storagePage)
    self.sourceButton:setVisible(storagePage)
    self.modButton:setVisible(storagePage)
    self.containerStatusButton:setVisible(not storagePage)
    local storageButtons = {
        self.depositAllButton, self.withdraw1Button, self.withdraw5Button,
        self.withdrawAllButton, self.countBox, self.withdrawCustomButton, self.sortButton,
        self.targetButton,
        self.exactButton,
    }
    for i = 1, #storageButtons do storageButtons[i]:setVisible(storagePage) end
    local manageButtons = {
        self.connectModeButton, self.roleButton, self.priorityDownButton, self.priorityUpButton,
        self.unlinkButton, self.radiusDownButton, self.radiusUpButton, self.limitDownButton, self.limitUpButton,
        self.takeOverButton,
    }
    for i = 1, #manageButtons do manageButtons[i]:setVisible(not storagePage) end
    styleButton(self.storageTab, storagePage)
    styleButton(self.manageTab, not storagePage)
end

function GodSystemStorageWindow:onFilter(button)
    if button.internal == "category" then
        local values = { "all" }
        for i = 1, #Storage.Categories do values[#values + 1] = Storage.Categories[i] end
        self.category = cycleValue(values, self.category, 1)
    elseif button.internal == "state" then
        self.state = cycleValue({
            "all", "fresh", "stale", "rotten", "chilled", "frozen",
            "cooking", "damaged", "lowCondition", "favorite",
        }, self.state, 1)
    elseif button.internal == "source" then
        local values = { "all" }
        local snapshot = Client.snapshot or {}
        for i = 1, #((snapshot.containers) or {}) do values[#values + 1] = tostring(snapshot.containers[i].linkId) end
        self.source = cycleValue(values, self.source, 1)
    elseif button.internal == "mod" then
        local values, seen = { "all" }, { all = true }
        for i = 1, #((Client.snapshot and Client.snapshot.groups) or {}) do
            local value = tostring(Client.snapshot.groups[i].modName or "")
            if value ~= "" and not seen[value] then seen[value] = true; values[#values + 1] = value end
        end
        self.modName = cycleValue(values, self.modName, 1)
    elseif button.internal == "containerStatus" then
        self.containerStatus = cycleValue({ "all", "online", "offline", "full", "cold" }, self.containerStatus, 1)
    end
    self:rebuild()
end

function GodSystemStorageWindow:filterGroup(group, query)
    if self.category ~= "all" and tostring(group.category) ~= self.category then return false end
    if self.state ~= "all" and not listContains(group.states, self.state) then return false end
    if self.source ~= "all" and not listContains(group.sources, self.source) then return false end
    if self.modName ~= "all" and tostring(group.modName) ~= self.modName then return false end
    if query ~= "" then
        local haystack = table.concat({
            tostring(group.name or ""), tostring(group.fullType or ""), tostring(group.modName or ""),
            table.concat(group.tags or {}, " "), table.concat(group.sources or {}, " "),
            table.concat(group.sourceNames or {}, " "),
            tostring(group.category or ""),
        }, " ")
        if not contains(haystack, query) then return false end
    end
    return true
end

function GodSystemStorageWindow:filterContainer(row, query)
    if query ~= "" and not contains(table.concat({
        tostring(row.name or ""), tostring(row.role or ""), tostring(row.linkId or ""),
        tostring(row.x or ""), tostring(row.y or ""), tostring(row.z or ""),
    }, " "), query) then return false end
    if self.containerStatus == "online" and row.online ~= true then return false end
    if self.containerStatus == "offline" and row.online == true then return false end
    if self.containerStatus == "full" and not (row.online == true and (tonumber(row.used) or 0) >= (tonumber(row.capacity) or 0)) then return false end
    if self.containerStatus == "cold" and row.powered ~= true then return false end
    return true
end

function GodSystemStorageWindow:sortGroups(groups)
    local mode = self.sortMode
    table.sort(groups, function(a, b)
        if mode == "count" and a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
        if mode == "weight" and a.totalWeight ~= b.totalWeight then return (a.totalWeight or 0) > (b.totalWeight or 0) end
        if mode == "condition" and a.bestCondition ~= b.bestCondition then return (a.bestCondition or 0) > (b.bestCondition or 0) end
        if mode == "spoilage" and a.earliestSpoilage ~= b.earliestSpoilage then return (a.earliestSpoilage or 0) < (b.earliestSpoilage or 0) end
        if mode == "source" then
            local as = tostring((a.sourceNames or {})[1] or (a.sources or {})[1] or "")
            local bs = tostring((b.sourceNames or {})[1] or (b.sources or {})[1] or "")
            if as ~= bs then return as < bs end
        end
        return lower(a.name) < lower(b.name)
    end)
end

function GodSystemStorageWindow:updateLabels()
    self.categoryButton:setTitle(text("Storage_Filter_Category", "Category") .. ": " .. text("Storage_Category_" .. self.category, self.category))
    self.stateButton:setTitle(text("Storage_Filter_State", "State") .. ": " .. text("Storage_State_" .. self.state, self.state))
    local sourceLabel = self.source
    for i = 1, #(((Client.snapshot or {}).containers) or {}) do
        local row = Client.snapshot.containers[i]
        if tostring(row.linkId) == tostring(self.source) then sourceLabel = tostring(row.name or row.linkId); break end
    end
    self.sourceButton:setTitle(text("Storage_Filter_Source", "Source") .. ": " .. (self.source == "all" and text("Storage_All", "All") or sourceLabel:sub(1, 16)))
    self.modButton:setTitle(text("Storage_Filter_Mod", "Mod") .. ": " .. self.modName)
    self.containerStatusButton:setTitle(text("Storage_Filter_Status", "Status") .. ": " .. text("Storage_ContainerStatus_" .. self.containerStatus, self.containerStatus))
    self.sortButton:setTitle(text("Storage_Sort", "Sort") .. ": " .. text("Storage_Sort_" .. self.sortMode, self.sortMode))
    self.targetButton:setTitle(text("Storage_Target", "Target") .. ": " .. self:getWithdrawTargetLabel())
    local state = Client.networkState or {}
    local snapshot = Client.snapshot or {}
    self.statusLabel.name = string.format(
        "%s %d | %s %d | %s %d/%d | %s %s/%s | %s%s",
        text("Storage_Types", "Types"), tonumber(snapshot.groupCount) or #(snapshot.groups or {}),
        text("Storage_Instances", "Items"), tonumber(snapshot.itemCount) or 0,
        text("Storage_Containers", "Containers"), tonumber(snapshot.onlineLinks) or 0, (tonumber(snapshot.onlineLinks) or 0) + (tonumber(snapshot.offlineLinks) or 0),
        text("Storage_Capacity", "Capacity"), formatNumber(snapshot.usedCapacity), formatNumber(snapshot.totalCapacity),
        text("Storage_IndexTime", "Indexed"), formatIndexTime(snapshot.indexedAtMs),
        snapshot.incomplete == true and (" | " .. text("Storage_Incomplete", "Results incomplete")) or ""
    )
    self.roleButton:setTitle(text("Storage_Role", "Role"))
    local selected
    for i = 1, #((snapshot.containers) or {}) do
        if tostring(snapshot.containers[i].linkId) == tostring(self.selectedLinkId) then selected = snapshot.containers[i]; break end
    end
    if selected then self.roleButton:setTitle(text("Storage_Role", "Role") .. ": " .. text("Storage_Role_" .. tostring(selected.role), selected.role)) end
    local admin = state.isAdmin == true
    self.radiusDownButton.enable = admin
    self.radiusUpButton.enable = admin
    self.limitDownButton.enable = admin
    self.limitUpButton.enable = admin
    self.takeOverButton.enable = admin
end

function GodSystemStorageWindow:getWithdrawTargets()
    local result = { { id = nil, label = text("Storage_Target_Main", "Main inventory") } }
    local p = getPlayer and getPlayer() or nil
    local worn = Storage.safeCall(p, "getWornItems", nil)
    local size = Storage.integer(Storage.safeCall(worn, "size", 0), 0)
    for i = 0, size - 1 do
        local entry = Storage.safeCall(worn, "get", nil, i)
        local item = Storage.safeCall(entry, "getItem", entry)
        local inventory = Storage.safeCall(item, "getInventory", nil)
        local id = Storage.itemId(item)
        if inventory and id then
            result[#result + 1] = {
                id = id,
                label = tostring(Storage.safeCall(item, "getDisplayName", Storage.itemFullType(item)) or id),
            }
        end
    end
    return result
end

function GodSystemStorageWindow:getWithdrawTargetLabel()
    local targets = self:getWithdrawTargets()
    for i = 1, #targets do
        if tostring(targets[i].id or "") == tostring(self.withdrawTargetItemId or "") then return targets[i].label end
    end
    self.withdrawTargetItemId = nil
    return targets[1].label
end

function GodSystemStorageWindow:cycleWithdrawTarget()
    local targets = self:getWithdrawTargets()
    local current = 1
    for i = 1, #targets do
        if tostring(targets[i].id or "") == tostring(self.withdrawTargetItemId or "") then current = i; break end
    end
    current = current + 1
    if current > #targets then current = 1 end
    self.withdrawTargetItemId = targets[current].id
    self:updateLabels()
end

function GodSystemStorageWindow:rebuild()
    if not self.mainList then return end
    local previous = self.page == "storage" and self.selectedGroupKey or self.selectedLinkId
    self.mainList:clear()
    self.detailList:clear()
    local query = lower(self.searchBox and self.searchBox:getText() or "")
    local snapshot = Client.snapshot
    if not snapshot then
        self.mainList:addItem(text("Storage_Loading", "Building storage index..."), { selectable = false })
        self:updateLabels()
        return
    end
    if self.page == "storage" then
        local groups = {}
        for i = 1, #(snapshot.groups or {}) do
            if self:filterGroup(snapshot.groups[i], query) then groups[#groups + 1] = snapshot.groups[i] end
        end
        self:sortGroups(groups)
        self.filteredGroups = groups
        for i = 1, #groups do
            local group = groups[i]
            local item = self.mainList:addItem(
                tostring(group.name or group.fullType) .. "  x" .. tostring(group.count or 0),
                {
                    kind = "group",
                    group = group,
                    key = group.key,
                    subtext = tostring(group.category or "other") .. " | " .. tostring(group.fullType or "") .. " | " .. formatNumber(group.totalWeight) .. " kg",
                }
            )
            if tostring(group.key) == tostring(previous) then self.mainList.selected = item.index end
        end
    else
        local rows = {}
        for i = 1, #(snapshot.containers or {}) do
            if self:filterContainer(snapshot.containers[i], query) then rows[#rows + 1] = snapshot.containers[i] end
        end
        table.sort(rows, function(a, b)
            if a.online ~= b.online then return a.online == true end
            if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
            return lower(a.name) < lower(b.name)
        end)
        self.filteredContainers = rows
        for i = 1, #rows do
            local row = rows[i]
            local state = row.online == true and text("Storage_Online", "Online") or text("Storage_Offline", "Offline")
            local item = self.mainList:addItem(
                tostring(row.name or "Container") .. " [" .. state .. "]",
                {
                    kind = "container",
                    container = row,
                    key = row.linkId,
                    subtext = string.format("%s | P%d | %d,%d,%d | %s/%s",
                        text("Storage_Role_" .. tostring(row.role), row.role),
                        tonumber(row.priority) or 0,
                        tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0,
                        formatNumber(row.used), formatNumber(row.capacity)
                    ),
                }
            )
            if tostring(row.linkId) == tostring(previous) then self.mainList.selected = item.index end
        end
    end
    self:updateLabels()
    self:updateDetails()
end

function GodSystemStorageWindow:onMainSelection()
    local selected = self.mainList.items[self.mainList.selected]
    local payload = selected and selected.item
    if not payload then return end
    if payload.kind == "group" then
        self.selectedGroupKey = payload.key
        self.selectedInstanceId = nil
        Client.requestDetails(payload.key)
    elseif payload.kind == "container" then
        self.selectedLinkId = payload.key
    end
    self:updateDetails()
    self:updateLabels()
end

function GodSystemStorageWindow:onDetailSelection()
    local row = self.detailList.items[self.detailList.selected]
    local payload = row and row.item
    if payload and payload.kind == "instance" then self.selectedInstanceId = payload.itemId end
end

local function copyRuleTable(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if value == true then result[key] = true end
    end
    return result
end

function GodSystemStorageWindow:applyCategoryRule(payload)
    if not payload or not payload.linkId then return end
    local allow = copyRuleTable(payload.allowCategories)
    local deny = copyRuleTable(payload.denyCategories)
    if payload.mode == "allowOnly" then
        allow = { [payload.category] = true }
        deny[payload.category] = nil
    elseif payload.mode == "toggleDeny" then
        deny[payload.category] = deny[payload.category] ~= true and true or nil
        allow[payload.category] = nil
    elseif payload.mode == "clear" then
        allow, deny = {}, {}
    end
    Client.updateLink({
        linkId = payload.linkId,
        allowCategories = allow,
        denyCategories = deny,
    })
end

function GodSystemStorageWindow:onMainRightMouseUp(x, y)
    if self.page ~= "manage" or not self.mainList.rowAt then return false end
    local rowIndex = self.mainList:rowAt(x, y)
    local row = rowIndex and self.mainList.items[rowIndex] or nil
    local payload = row and row.item
    if not payload or payload.kind ~= "container" then return false end
    self.mainList.selected = rowIndex
    self.selectedLinkId = payload.key
    self:updateDetails()
    local container = payload.container or {}
    local context = ISContextMenu.get(getPlayer() and getPlayer():getPlayerNum() or 0, getMouseX(), getMouseY())
    local allowRoot = context:addOption(text("Storage_Rule_AllowOnly", "Allow only category"), nil, nil)
    local allowMenu = ISContextMenu:getNew(context)
    context:addSubMenu(allowRoot, allowMenu)
    local denyRoot = context:addOption(text("Storage_Rule_Deny", "Toggle denied category"), nil, nil)
    local denyMenu = ISContextMenu:getNew(context)
    context:addSubMenu(denyRoot, denyMenu)
    for i = 1, #Storage.Categories do
        local category = Storage.Categories[i]
        local label = text("Storage_Category_" .. category, category)
        local base = {
            linkId = container.linkId,
            category = category,
            allowCategories = container.allowCategories,
            denyCategories = container.denyCategories,
        }
        local allowPayload = copyRuleTable(base)
        for key, value in pairs(base) do allowPayload[key] = value end
        allowPayload.mode = "allowOnly"
        allowMenu:addOption(label, self, self.applyCategoryRule, allowPayload)
        local denyPayload = {}
        for key, value in pairs(base) do denyPayload[key] = value end
        denyPayload.mode = "toggleDeny"
        local denied = type(container.denyCategories) == "table" and container.denyCategories[category] == true
        denyMenu:addOption((denied and "[x] " or "[ ] ") .. label, self, self.applyCategoryRule, denyPayload)
    end
    context:addOption(text("Storage_Rule_Clear", "Clear category rules"), self, self.applyCategoryRule, {
        mode = "clear",
        linkId = container.linkId,
    })
    return true
end

function GodSystemStorageWindow:updateDetails()
    self.detailList:clear()
    if self.page == "storage" then
        local selected
        for i = 1, #((Client.snapshot and Client.snapshot.groups) or {}) do
            if tostring(Client.snapshot.groups[i].key) == tostring(self.selectedGroupKey) then selected = Client.snapshot.groups[i]; break end
        end
        if not selected then
            self.detailList:addItem(text("Storage_SelectType", "Select an item type to view details"), {})
            return
        end
        self.detailList:addItem(tostring(selected.name or selected.fullType), {})
        self.detailList:addItem(tostring(selected.fullType or ""), {})
        self.detailList:addItem(text("Storage_Count", "Count") .. ": " .. tostring(selected.count or 0), {})
        self.detailList:addItem(text("Storage_Mod", "Mod") .. ": " .. tostring(selected.modName or ""), {})
        self.detailList:addItem(text("Storage_Category", "Category") .. ": " .. tostring(selected.category or ""), {})
        self.detailList:addItem(text("Storage_State", "State") .. ": " .. table.concat(selected.states or {}, ", "), {})
        self.detailList:addItem(text("Storage_Sources", "Sources") .. ": " .. tostring(#(selected.sources or {})), {})
        self.detailList:addItem("", {})
        local instances = Client.details[tostring(self.selectedGroupKey or "")] or {}
        for i = 1, math.min(#instances, 250) do
            local row = instances[i]
            self.detailList:addItem(string.format(
                "#%s | %s | %.0f%% | %.2fkg",
                tostring(row.id or "?"), tostring(row.sourceName or ""),
                (tonumber(row.conditionRatio) or 0) * 100, tonumber(row.weight) or 0
            ), { kind = "instance", itemId = row.id })
        end
    else
        local selected
        for i = 1, #((Client.snapshot and Client.snapshot.containers) or {}) do
            if tostring(Client.snapshot.containers[i].linkId) == tostring(self.selectedLinkId) then selected = Client.snapshot.containers[i]; break end
        end
        if not selected then
            local state = Client.networkState or {}
            self.detailList:addItem(text("Storage_SelectContainer", "Select a connected container"), {})
            self.detailList:addItem(text("Storage_Radius", "Radius") .. ": " .. tostring(state.radius or Storage.DefaultRadius), {})
            self.detailList:addItem(text("Storage_LinkLimit", "Connection limit") .. ": " .. tostring(state.maxLinks or Storage.DefaultMaxLinks), {})
            self.detailList:addItem(text("Storage_LinkCount", "Connected") .. ": " .. tostring(state.linkCount or 0), {})
            return
        end
        self.detailList:addItem(tostring(selected.name or "Container"), {})
        self.detailList:addItem(text("Storage_Status", "Status") .. ": " .. (selected.online and text("Storage_Online", "Online") or text("Storage_Offline", "Offline")), {})
        self.detailList:addItem(text("Storage_Role", "Role") .. ": " .. tostring(selected.role or "auto"), {})
        self.detailList:addItem(text("Storage_Priority", "Priority") .. ": " .. tostring(selected.priority or 50), {})
        self.detailList:addItem(text("Storage_Position", "Position") .. string.format(": %d,%d,%d", selected.x or 0, selected.y or 0, selected.z or 0), {})
        self.detailList:addItem(text("Storage_Capacity", "Capacity") .. ": " .. formatNumber(selected.used) .. "/" .. formatNumber(selected.capacity), {})
        self.detailList:addItem(text("Storage_Powered", "Powered cold storage") .. ": " .. tostring(selected.powered == true), {})
        if selected.reason then self.detailList:addItem(text("Storage_DisconnectReason", "Disconnect reason") .. ": " .. tostring(selected.reason), {}) end
    end
end

function GodSystemStorageWindow:onAction(button)
    if button.internal == "refresh" then
        Client.refresh()
    elseif button.internal == "depositAll" then
        Client.depositAll()
    elseif button.internal == "sort" then
        self.sortMode = cycleValue({ "name", "count", "weight", "condition", "spoilage", "source" }, self.sortMode, 1)
        self:rebuild()
    elseif button.internal == "target" then
        self:cycleWithdrawTarget()
    elseif button.internal == "withdrawExact" then
        if not self.selectedGroupKey or not self.selectedInstanceId then
            if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_SelectInstance", "Select a specific instance in the details list")) end
            return
        end
        Client.withdrawExact(self.selectedGroupKey, self.selectedInstanceId, self.withdrawTargetItemId)
    else
        if not self.selectedGroupKey then
            if GodSystem and GodSystem.notify then GodSystem.notify(text("Storage_SelectType", "Select an item type")) end
            return
        end
        local selected
        for i = 1, #((Client.snapshot and Client.snapshot.groups) or {}) do
            if tostring(Client.snapshot.groups[i].key) == tostring(self.selectedGroupKey) then selected = Client.snapshot.groups[i]; break end
        end
        local count = 1
        if button.internal == "withdraw5" then count = 5
        elseif button.internal == "withdrawAll" then count = selected and selected.count or 1
        elseif button.internal == "withdrawCustom" then count = math.max(1, math.floor(tonumber(self.countBox:getText()) or 1)) end
        Client.withdraw(self.selectedGroupKey, count, self.withdrawTargetItemId)
    end
end

function GodSystemStorageWindow:onManageAction(button)
    if button.internal == "connectMode" then
        if GodSystemStorageContext and GodSystemStorageContext.toggleConnectMode then
            GodSystemStorageContext.toggleConnectMode()
        end
        return
    end
    if button.internal == "takeOver" then
        Client.takeOver()
        return
    end
    local state = Client.networkState or {}
    if button.internal == "radiusDown" or button.internal == "radiusUp" or button.internal == "limitDown" or button.internal == "limitUp" then
        local radius = tonumber(state.radius) or Storage.DefaultRadius
        local limit = tonumber(state.maxLinks) or Storage.DefaultMaxLinks
        if button.internal == "radiusDown" then radius = radius - 5 end
        if button.internal == "radiusUp" then radius = radius + 5 end
        if button.internal == "limitDown" then limit = limit - 8 end
        if button.internal == "limitUp" then limit = limit + 8 end
        Client.updateLimits(radius, limit)
        return
    end
    if not self.selectedLinkId then return end
    local selected
    for i = 1, #((Client.snapshot and Client.snapshot.containers) or {}) do
        if tostring(Client.snapshot.containers[i].linkId) == tostring(self.selectedLinkId) then selected = Client.snapshot.containers[i]; break end
    end
    if not selected then return end
    if button.internal == "unlink" then
        Client.unlink(self.selectedLinkId)
    elseif button.internal == "role" then
        Client.updateLink({ linkId = self.selectedLinkId, role = cycleValue(Storage.Roles, selected.role or "auto", 1) })
    elseif button.internal == "priorityDown" then
        Client.updateLink({ linkId = self.selectedLinkId, priority = math.max(0, (tonumber(selected.priority) or 50) - 10) })
    elseif button.internal == "priorityUp" then
        Client.updateLink({ linkId = self.selectedLinkId, priority = math.min(100, (tonumber(selected.priority) or 50) + 10) })
    end
end

function GodSystemStorageWindow:close()
    ISCollapsableWindow.close(self)
    if GodSystemStorageContext and GodSystemStorageContext.setConnectMode then GodSystemStorageContext.setConnectMode(false) end
    if UI.window == self then UI.window = nil end
end

function UI.open()
    if UI.window then
        UI.window:setVisible(true)
        UI.window:addToUIManager()
        UI.window:rebuild()
        return UI.window
    end
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local width = math.min(1120, math.max(900, screenW - 160))
    local height = math.min(760, math.max(600, screenH - 140))
    local window = GodSystemStorageWindow:new(math.floor((screenW - width) / 2), math.floor((screenH - height) / 2), width, height)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    UI.window = window
    return window
end

function UI.close()
    if UI.window then UI.window:close() end
end

function UI.onSnapshot()
    if UI.window then UI.window:rebuild() end
end

function UI.onDetails(groupKey)
    if UI.window and tostring(UI.window.selectedGroupKey or "") == tostring(groupKey or "") then UI.window:updateDetails() end
end

function UI.onNetworkState()
    if UI.window then UI.window:updateLabels() end
end

function UI.onIndexStarted()
    if UI.window then
        UI.window.statusLabel.name = text("Storage_Loading", "Building storage index...")
    end
end

function UI.onOperationResult(command, ok, reason, payload)
    if payload and GodSystem and GodSystem.notify and (command == "deposit" or command == "withdraw") then
        GodSystem.notify(
            text("Storage_TransferResult", "Moved {1}; skipped {2}; failed {3}; cold downgrade {4}")
                :gsub("{1}", tostring(payload.success or 0))
                :gsub("{2}", tostring(payload.skipped or 0))
                :gsub("{3}", tostring(payload.failed or 0))
                :gsub("{4}", tostring(payload.coldDowngrade or 0))
        )
    end
    if UI.window and ok then UI.window.statusLabel.name = text("Storage_Refreshing", "Refreshing...") end
end

function UI.onError()
    if UI.window then UI.window:updateLabels() end
end

return UI
