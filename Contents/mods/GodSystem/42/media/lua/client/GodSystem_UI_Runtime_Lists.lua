_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Lists"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Lists then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Lists = true
    setfenv(1, runtimeEnvironment)

function GodSystemWindow:hasPendingListRestore()
    return self.pendingRestoreMode == self.mode and type(self.pendingRestoreScroll) == "table"
end

function GodSystemWindow:resetScrollingListState(list)
    if not list then
        return
    end
    if list.clear then
        list:clear()
    end
    list.selected = 0
    list.mouseoverselected = -1
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
    if list.setYScroll then
        list:setYScroll(0)
    end
    if list.setScrollHeight then
        list:setScrollHeight(0)
    end
    gsSyncScrollingListGeometry(list)
end

function GodSystemWindow:clearList()
    self:resetScrollingListState(self.list)
    self.lastSelectableListRow = 0
    if self.activeList then
        self:resetScrollingListState(self.activeList)
        self.lastSelectableActiveRow = 0
    end
    if self.detailList then
        self:resetScrollingListState(self.detailList)
    end
    self:setDetailText("")
end

function GodSystemWindow:addListItem(text, payload)
    payload = payload or {}
    if GS_NON_SELECTABLE_KINDS[payload.kind] then payload.selectable = false end
    payload.displayText = tostring(text or "")
    self.list:addItem(text, payload)
end

function GodSystemWindow:addActiveListItem(text, payload)
    payload = payload or {}
    if GS_NON_SELECTABLE_KINDS[payload.kind] then payload.selectable = false end
    payload.displayText = tostring(text or "")
    self.activeList:addItem(text, payload)
end

function GodSystemWindow:addWrappedListText(text, payload)
    local width = math.max(self:S(120), (self.list and self.list.width or self.mainW or self:S(300)) - self:S(18))
    local lines = gsWrapText(text, UIFont.Small, width)
    if payload and payload.kind == "spacer" and #lines == 1 and lines[1] == "" then
        self:addListItem("", payload)
        return
    end
    for i = 1, #lines do
        local rowPayload = {}
        local source = payload or {}
        for key, value in pairs(source) do
            rowPayload[key] = value
        end
        if i > 1 and source.kind == "history" then
            rowPayload.detail = ""
        end
        self:addListItem(lines[i], rowPayload)
    end
end

function GodSystemWindow:formatHistoryEntry(entry)
    if not entry then
        return GodSystemApp.services.runtime.text("Tab_History", "History")
    end
    if entry.code then
        local template = GodSystemApp.services.runtime.text("HistoryMP_" .. tostring(entry.code), "")
        if template and template ~= "" then
            local args = {}
            for i = 1, #(entry.args or {}) do
                args[i] = entry.args[i]
            end
            if entry.taskId then
                args = { GodSystemApp.services.runtime.getTaskTitle({ sourceId = entry.taskId, title = entry.taskTitle }) }
                if entry.args then
                    for i = 1, #entry.args do args[#args + 1] = entry.args[i] end
                end
            elseif entry.shopId then
                args = { GodSystemApp.services.runtime.getShopLabel({ id = entry.shopId, items = entry.shopItems }) }
                if entry.args then
                    for i = 1, #entry.args do args[#args + 1] = entry.args[i] end
                end
            end
            if entry.code == "UpgradeSystem" and args[1] then
                local info = GodSystemApp.services.runtime.getSystemUpgradeInfo(tostring(args[1]))
                if info and info.label then
                    args[1] = info.label
                end
            elseif entry.code == "MedicalService" and args[1] then
                local info = GodSystemApp.services.runtime.getMedicalServiceInfo and GodSystemApp.services.runtime.getMedicalServiceInfo(tostring(args[1])) or nil
                if info and info.label then
                    args[1] = info.label
                end
            elseif (entry.code == "ListOnlyAutoShop" or entry.code == "ShopItemHidden"
                or entry.code == "ShopItemVisible" or entry.code == "ShopItemDeleted") and args[1] then
                args[1] = GodSystemApp.services.runtime.getItemDisplayName(tostring(args[1]))
            elseif (entry.code == "BankInvestmentCreated" or entry.code == "BankInvestmentRedeemed" or entry.code == "BankInvestmentSettled") and args[1] then
                args[1] = GodSystemApp.services.runtime.getBankInvestmentLabel(tostring(args[1]))
            end
            return gsFormatTemplate(template, args)
        end
    end
    return tostring(entry.text or GodSystemApp.services.runtime.text("Tab_History", "History"))
end

function GodSystemWindow:setTextPageLayout(enabled)
    if not enabled then
        return
    end
    local width = math.max(self:S(300), (self.actionRight or self.panelRight or (self.mainX + self.mainW)) - self.mainX)
    gsSetBounds(self.list, self.mainX, self.mainY, width, self.mainH)
    self.list.itemheight = self:S(24)
    if self.detailList then
        self.detailList:setVisible(false)
        self.detailList:clear()
    end
    if self.detailHeaderLabel then
        self.detailHeaderLabel:setVisible(false)
    end
end

function GodSystemWindow:formatHomeSource(source)
    local key = tostring(source or "")
    if key ~= "" then
        local text = GodSystemApp.services.runtime.text("HomeSource_" .. key, "")
        if text and text ~= "" then
            return text
        end
        return key
    end
    return GodSystemApp.services.runtime.text("Home_ReturnPoint", "return point")
end

function GodSystemWindow:getPayloadId(payload)
    if not payload then
        return nil
    end
    if payload.kind == "task" and payload.data then
        return "task:" .. tostring(payload.data.taskId or payload.data.sourceId or "")
    end
    if payload.kind == "shop" and payload.data then
        if payload.data.unlocked == true then
            return "shop:unlocked:" .. tostring(payload.data.variantKey or payload.data.id or payload.data.fullType or "")
        end
        return "shop:configured:" .. tostring(payload.data.id or payload.data.fullType or GodSystemApp.services.runtime.getShopPrimaryFullType(payload.data) or "")
    end
    if payload.kind == "recycle" and payload.data then
        return "recycle:" .. tostring(payload.data.fullType or "")
    end
    if payload.kind == "rangeFilterItem" and payload.fullType then
        return "rangeFilterItem:" .. tostring(payload.fullType)
    end
    if payload.kind == "bankTerm" and payload.data then
        return "bankTerm:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankFixed" and payload.data then
        return "bankFixed:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankInvestment" then
        local profile = payload.profile or {}
        local account = payload.data or {}
        return "bankInvestment:" .. tostring(profile.id or account.tierId or "")
    end
    if payload.kind == "bankLoanPlan" and payload.data then
        return "bankLoanPlan:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "bankLoanActive" and payload.data then
        return "bankLoanActive:" .. tostring(payload.data.id or "")
    end
    if payload.kind == "trait" and payload.data then
        return "trait:" .. tostring(payload.data.action or "") .. ":" .. tostring(payload.data.traitType or "")
    end
    if payload.kind == "attribute" and payload.data then
        return "attribute:" .. tostring(payload.data.index or "")
    end
    if payload.kind == "upgrade" and payload.data then
        return "upgrade:" .. tostring(payload.data.upgradeType or "")
    end
    if payload.kind == "medicalService" and payload.data then
        return "medical:" .. tostring(payload.data.action or "")
    end
    if payload.kind == "companionNode" then
        return "companionNode:" .. tostring(payload.id or "")
    end
    if payload.kind == "homePoint" and payload.data then
        return "home:" .. tostring(payload.data.kind or "") .. ":" .. tostring(payload.data.index or "")
    end
    return nil
end

function GodSystemWindow:captureSelection()
    if self.pendingRestoreSelectedId and self.pendingRestoreMode == self.mode then
        return
    end
    local payload = self:getSelectedPayload()
    self.restoreSelectedId = self:getPayloadId(payload)
    self.restoreSelectedTaskList = self.selectedTaskList
end

function GodSystemWindow:prepareActionSelection(payload)
    local selectedId = self:getPayloadId(payload or self:getSelectedPayload())
    self.pendingRestoreSelectedId = selectedId and selectedId ~= "" and selectedId or nil
    self.pendingRestoreSelectedTaskList = self.selectedTaskList
    self.pendingRestoreMode = self.mode
    self.restoreSelectedId = self.pendingRestoreSelectedId
    self.restoreSelectedTaskList = self.selectedTaskList
    self:captureScrollState()
    self.pendingRestoreScroll = {
        mode = self.restoreScrollMode,
        category = self.restoreScrollCategory,
        shopSearch = self.restoreScrollShopSearch,
        recycleSearch = self.restoreScrollRecycleSearch,
        y = self.restoreScrollY,
        listState = self.restoreListState,
        activeListState = self.restoreActiveListSnapshot,
        detailListState = self.restoreDetailListSnapshot,
    }
end

function GodSystemWindow:restoreSelection()
    local selectedId = self.pendingRestoreMode == self.mode and self.pendingRestoreSelectedId or self.restoreSelectedId
    if not selectedId or selectedId == "" then
        return false
    end
    local function selectInList(list)
        if not list or not list.items then
            return false
        end
        for i = 1, #list.items do
            local item = list.items[i]
            if self:getPayloadId(item and item.item) == selectedId then
                list.selected = i
                if list == self.activeList then
                    self.lastSelectableActiveRow = i
                else
                    self.lastSelectableListRow = i
                end
                return true
            end
        end
        return false
    end
    if self.mode == "tasks" and self.restoreSelectedTaskList == "active" and selectInList(self.activeList) then
        self:clearOppositeTaskSelection("active")
        return true
    end
    if selectInList(self.list) then
        if self.mode == "tasks" then
            self:clearOppositeTaskSelection("open")
        end
        return true
    end
    if self.mode == "tasks" and selectInList(self.activeList) then
        self:clearOppositeTaskSelection("active")
        return true
    end
    return false
end

function GodSystemWindow:addSyncPlaceholder(detail)
    self:addListItem(GodSystemApp.services.runtime.text("State_Syncing", "正在同步服务器数据..."), { kind = "empty", detail = detail or GodSystemApp.services.runtime.text("State_SyncingHint", "请稍等，服务器状态返回后会自动刷新。") })
end

function GodSystemWindow:needsServerState()
    if self.mode == "settings" then
        return false
    end
    if not gsIsMultiplayer() then
        return false
    end
    return not gsHasServerState()
end

function GodSystemWindow:finishMultiplayerCommand(sent)
    if not self:hasPendingListRestore() then
        self:prepareActionSelection()
    end
    if not gsIsMultiplayer() then
        self:populateList()
        return sent ~= false
    end
    if sent == false then
        self.waitingForServerState = false
        GodSystemNetwork.requestState(true)
        self:populateList()
        return false
    end
    self.waitingForServerState = true
    local ids = { "primary", "secondary", "third", "fourth", "fifth", "sixth", "seventh" }
    for i = 1, #ids do
        local control = self:getActionControl(ids[i])
        if control then control.enable = false end
    end
    if GodSystemNetwork and GodSystemNetwork.requestState then
        GodSystemNetwork.requestState(false)
    end
    return true
end

function GodSystemWindow:requestServerRefresh()
    if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.requestState then
        self.waitingForServerState = true
        GodSystemNetwork.requestState(true)
        return true
    end
    return false
end

function GodSystemWindow:getActionControl(id)
    if id == "primary" then
        return self.primaryButton
    elseif id == "secondary" then
        return self.secondaryButton
    elseif id == "third" then
        return self.thirdButton
    elseif id == "fourth" then
        return self.fourthButton
    elseif id == "fifth" then
        return self.fifthButton
    elseif id == "sixth" then
        return self.sixthButton
    elseif id == "seventh" then
        return self.seventhButton
    elseif id == "category" then
        return self.categoryButton
    elseif id == "searchLabel" then
        return self.shopSearchLabel
    elseif id == "searchBox" then
        return self.shopSearchBox
    end
    return nil
end

function GodSystemWindow:resetActionButtonEnabledState()
    local ids = { "primary", "secondary", "third", "fourth", "fifth", "sixth", "seventh" }
    for i = 1, #ids do
        local control = self:getActionControl(ids[i])
        if control then control.enable = true end
    end
end

function GodSystemWindow:hideActionControls()
    local ids = { "primary", "secondary", "third", "fourth", "fifth", "sixth", "seventh", "category", "searchLabel", "searchBox" }
    for i = 1, #ids do
        local control = self:getActionControl(ids[i])
        if control then
            control:setVisible(false)
        end
    end
end

function GodSystemWindow:setActionBar(actions)
    self:hideActionControls()
    local visibleActions = {}
    local requested = 0
    for i = 1, #(actions or {}) do
        local action = actions[i]
        local control = action and (action.control or self:getActionControl(action.id))
        if control and action.visible ~= false then
            action.control = control
            local title = tostring(action.title or control.fullTitle or control.title or "")
            local titleWidth = gsMeasureText(UIFont.Small, title) + self:S(20)
            local baseWidth = self:S(tonumber(action.width) or 120)
            action.requestedWidth = math.max(baseWidth, titleWidth)
            requested = requested + action.requestedWidth
            table.insert(visibleActions, action)
        end
    end
    local x = self.actionX or (self.contentX + self:S(12))
    local rowY = self.actionY + self:S(8)
    local actionTheme = (gsTheme().actionButtons or {})
    local gap = self:S(actionTheme.gap or ((#visibleActions > 4) and 8 or 14))
    local right = self.actionRight or (self.contentX + self.contentW - self:S(12))
    local available = math.max(self:S(80), right - x - (math.max(0, #visibleActions - 1) * gap))
    local scale = requested > available and (available / requested) or 1
    for i = 1, #visibleActions do
        local action = visibleActions[i]
        local control = action.control
        local minWidth = self:S(tonumber(action.minWidth) or 70)
        local width = math.floor(action.requestedWidth * scale)
        width = math.max(minWidth, width)
        if i == #visibleActions then
            width = math.max(minWidth, right - x)
        end
        local height = math.floor(tonumber(action.height) and self:S(action.height) or actionTheme.height and self:S(actionTheme.height) or self.actionButtonH or self:S(38))
        local title = action.title or control.fullTitle or control.title
        if control.setTitle and title and width > 0 then
            control:setTitle(gsTruncateText(title, UIFont.Small, width - self:S(12)))
        end
        if x + width > right then
            width = math.max(minWidth, right - x)
        end
        if width > 0 then
            control:setVisible(true)
            gsSetBounds(control, x, rowY + math.floor(tonumber(action.offsetY) or 0), width, height)
            x = x + width + gap
        end
        if x >= right then
            break
        end
    end
end

function GodSystemWindow:setStandardActionBar()
    local actions = {}
    if self.primaryButton and self.primaryButton:getIsVisible() then
        table.insert(actions, { id = "primary", width = 122 })
    end
    if self.secondaryButton and self.secondaryButton:getIsVisible() then
        table.insert(actions, { id = "secondary", width = 122 })
    end
    if self.thirdButton and self.thirdButton:getIsVisible() then
        table.insert(actions, { id = "third", width = 122 })
    end
    if self.fourthButton and self.fourthButton:getIsVisible() then
        table.insert(actions, { id = "fourth", width = 122 })
    end
    if self.fifthButton and self.fifthButton:getIsVisible() then
        table.insert(actions, { id = "fifth", width = 122 })
    end
    if self.sixthButton and self.sixthButton:getIsVisible() then
        table.insert(actions, { id = "sixth", width = 122 })
    end
    if self.seventhButton and self.seventhButton:getIsVisible() then
        table.insert(actions, { id = "seventh", width = 122 })
    end
    self:setActionBar(actions)
end

function GodSystemWindow:applyBaseLayout()
    self:setupLayoutMetrics()
    self:applyStaticLayout()
    self:hidePageSections()
    if self.openTaskLabel then
        self.openTaskLabel:setVisible(false)
    end
    if self.activeTaskLabel then
        self.activeTaskLabel:setVisible(false)
    end
    if self.activeList then
        self.activeList:setVisible(false)
    end
    if self.detailLabel then
        self.detailLabel:setVisible(false)
    end
    if self.detailList then
        self.detailList:setVisible(true)
        gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        self.detailList.itemheight = self:S(22)
    end
    if self.detailHeaderLabel then
        self.detailHeaderLabel:setVisible(true)
        gsSetBounds(self.detailHeaderLabel, self.detailX + self:S(8), self:S(88), nil, nil)
    end
    if self.categoryButton then
        self.categoryButton:setVisible(false)
    end
    if self.shopSearchLabel then
        self.shopSearchLabel:setVisible(false)
    end
    if self.shopSearchBox then
        self.shopSearchBox:setVisible(false)
    end
    if self.fourthButton then
        self.fourthButton:setVisible(false)
    end
    if self.fifthButton then
        self.fifthButton:setVisible(false)
    end
    if self.sixthButton then
        self.sixthButton:setVisible(false)
    end
    if self.seventhButton then
        self.seventhButton:setVisible(false)
    end
    gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
    self.list.itemheight = self:S((gsTheme().window and gsTheme().window.rowHeight) or 44)
    self:setStandardActionBar()
end

function GodSystemWindow:relayoutVisiblePage()
    if self.relayouting then
        return
    end
    self.relayouting = true
    self:applyBaseLayout()
    self:setTaskLayout(self.mode == "tasks" and self:getActivePageSection("tasks") == "tasks")
    self:setShopLayout(self.mode == "shop" or self.mode == "recycle" or self.mode == "attribute")
    self:setTextPageLayout(self.mode == "settings" or self.mode == "history" or self.mode == "info" or self.mode == "diagnostics")
    if self.mode == "shop" then
        self:applyShopActionLayout()
    elseif self.mode == "recycle" then
        self:applyRecycleActionLayout()
    elseif self.mode == "home" then
        self:applyHomeActionBar(self:getSelectedPayload())
    elseif self.mode == "rangeRecycle" then
        self:setActionBar({
            { id = "primary", width = 140 },
            { id = "secondary", width = 160 },
        })
    else
        self:setStandardActionBar()
    end
    self:updateDetail()
    self.relayouting = false
end

function GodSystemWindow:applyShopActionLayout()
    local thirdVisible = self.thirdButton and self.thirdButton:getIsVisible()
    self:setActionBar({
        { id = "category", width = 112, minWidth = 96 },
        { id = "searchBox", width = 122, minWidth = 96 },
        { id = "primary", width = 74, minWidth = 58 },
        { id = "secondary", width = 82, minWidth = 68, visible = not gsIsMultiplayer() },
        { id = "third", width = 88, minWidth = 72, visible = thirdVisible == true },
        { id = "fourth", width = 78, minWidth = 62 },
        { id = "fifth", width = 78, minWidth = 62 },
        { id = "sixth", width = 102, minWidth = 82 },
    })
end

function GodSystemWindow:applyRecycleActionLayout()
    self:setActionBar({
        { id = "searchBox", width = 210, minWidth = 140 },
        { id = "primary", width = 90, minWidth = 72 },
        { id = "secondary", width = 100, minWidth = 82, visible = not gsIsMultiplayer() },
        { id = "third", width = 118, minWidth = 96 },
    })
end

function GodSystemWindow:setTaskLayout(enabled)
    if self.openTaskLabel then
        self.openTaskLabel:setVisible(enabled)
    end
    if self.activeTaskLabel then
        self.activeTaskLabel:setVisible(enabled)
    end
    if self.activeList then
        self.activeList:setVisible(enabled)
    end
    if self.detailList then
        self.detailList:setVisible(true)
        gsSetBounds(self.detailList, self.detailX, self:S(136), self.detailW, self.actionY - self:S(146))
        self.detailList.itemheight = self:S(22)
    end
    if self.detailLabel then
        self.detailLabel:setVisible(false)
    end
    if enabled then
        local gap = self:S(12)
        local colW = math.floor((self.mainW - gap) / 2)
        local win = (gsTheme().window or {})
        local taskHeaderH = self:S(win.taskHeaderHeight or 18)
        local taskHeaderGap = self:S(win.taskHeaderGap or 8)
        local taskY = self.mainY
        local taskH = math.max(self:S(160), self.mainH)
        gsSetBounds(self.list, self.mainX, taskY, colW, taskH)
        self.list.itemheight = self:S((gsTheme().window and gsTheme().window.taskRowHeight) or 44)
        if self.activeList then
            gsSetBounds(self.activeList, self.mainX + colW + gap, taskY, colW, taskH)
            self.activeList.itemheight = self:S((gsTheme().window and gsTheme().window.taskRowHeight) or 44)
        end
        if self.openTaskLabel then
            gsSetBounds(self.openTaskLabel, self.list.x, self.mainY - taskHeaderH - taskHeaderGap, nil, nil)
        end
        if self.activeTaskLabel then
            gsSetBounds(self.activeTaskLabel, self.activeList and self.activeList.x or (self.mainX + colW + gap), self.mainY - taskHeaderH - taskHeaderGap, nil, nil)
        end
    else
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if self.activeList then
            gsSetBounds(self.activeList, nil, nil, nil, self.mainH)
        end
    end
end

function GodSystemWindow:setShopLayout(enabled)
    local adminMode = self.mode == "admin"
    local attributeMode = self.mode == "attribute"
    local searchEnabled = enabled or adminMode or attributeMode
    local shopMode = enabled and self.mode == "shop"
    if self.categoryButton then
        self.categoryButton:setVisible(shopMode)
    end
    if self.shopSearchLabel then
        self.shopSearchLabel:setVisible(false)
    end
    if self.shopSearchBox then
        self.shopSearchBox:setVisible(searchEnabled)
    end
    if searchEnabled then
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if adminMode then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        elseif attributeMode then
            self:setStandardActionBar()
        elseif shopMode then
            self:applyShopActionLayout()
        else
            self:applyRecycleActionLayout()
        end
        if self.detailList then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        end
    elseif self.mode ~= "tasks" then
        gsSetBounds(self.list, self.mainX, self.mainY, self.mainW, self.mainH)
        if self.detailList then
            gsSetBounds(self.detailList, self.detailX, self.mainY, self.detailW, self.mainH)
        end
    end
end

function GodSystemWindow:updateShopCategoryButton(categories)
    self.shopCategories = categories or {}
    local selectedLabel = GodSystemApp.services.runtime.text("ShopCategory_All", "All categories")
    for i = 1, #(categories or {}) do
        local category = categories[i]
        if category.key == self.shopCategoryKey then
            selectedLabel = category.label
        end
    end
    if selectedLabel == GodSystemApp.services.runtime.text("ShopCategory_All", "All categories") and self.shopCategoryKey ~= "all" then
        self.shopCategoryKey = "all"
    end
    if self.categoryButton then
        gsSetButtonTitle(self.categoryButton, tostring(selectedLabel))
    end
end

function GodSystemWindow:updateTaskPrimaryButton(payload)
    if self.mode ~= "tasks" or not self.primaryButton then
        return
    end
    if (payload and payload.kind == "upgrade") or self:getActivePageSection("tasks") == "taskExtensions" then
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_UpgradeSystem", "Upgrade"))
        gsStyleActionButton(self.primaryButton, "primary")
        return
    end
    local title = GodSystemApp.services.runtime.text("Btn_TaskAccept", "Accept")
    local variant = "primary"
    if payload and payload.kind == "task" and payload.data then
        local task = payload.data
        if task.status == "open" then
            title = GodSystemApp.services.runtime.text("Btn_TaskAccept", "Accept")
            variant = "primary"
        elseif task.status == "active" then
            if GodSystemApp.services.runtime.isTaskComplete(task) then
                title = GodSystemApp.services.runtime.text("Btn_TaskClaim", "Claim reward")
                variant = "primary"
            else
                title = GodSystemApp.services.runtime.text("Btn_TaskAbandon", "Abandon")
                variant = "danger"
            end
        elseif task.status == "failed" then
            title = GodSystemApp.services.runtime.text("Status_Failed", "Failed")
            variant = false
        elseif task.status == "claimed" then
            title = GodSystemApp.services.runtime.text("Status_Claimed", "Claimed")
            variant = false
        end
    end
    gsSetButtonTitle(self.primaryButton, title)
    gsStyleActionButton(self.primaryButton, variant)
end

function GodSystemWindow:setShopCategory(key)
    key = key or "all"
    if key ~= self.shopCategoryKey then
        self.shopCategoryKey = key
        self.shopPage = 1
        self:populateList()
    end
end

function GodSystemWindow:changeShopPage(delta)
    self.shopPage = math.max(1, math.floor((self.shopPage or 1) + (delta or 0)))
    self:populateList()
end

function GodSystemWindow:onShopCategoryButton()
    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(GodSystemApp.services.runtime.text("ShopCategory_All", "All categories"), self, self.setShopCategory, "all")
    for i = 1, #(self.shopCategories or {}) do
        local category = self.shopCategories[i]
        context:addOption(tostring(category.label or category.key), self, self.setShopCategory, category.key)
    end
end

function GodSystemWindow:onCategoryButton()
    return self:onShopCategoryButton()
end

function GodSystemWindow:onShopSearchChange(entry)
    if self.suppressSearchChange == true then
        return
    end
    if self.mode ~= "shop" and self.mode ~= "recycle"
        and self.mode ~= "attribute" then
        return
    end
    local text = ""
    if entry and entry.getInternalText then
        text = entry:getInternalText() or ""
    elseif self.shopSearchBox and self.shopSearchBox.getInternalText then
        text = self.shopSearchBox:getInternalText() or ""
    end
    if self.shopSearchPurpose == "recycle" then
        if text ~= self.recycleSearchText then
            self.recycleSearchText = text
            self:populateList()
        end
    elseif self.shopSearchPurpose == "attribute" then
        if text ~= self.attributeSearchText then
            self.attributeSearchText = text
            self:populateList()
        end
    else
        if text ~= self.shopSearchText then
            self.shopSearchText = text
            self.shopPage = 1
            self:populateList()
        end
    end
end

function GodSystemWindow:syncSearchBoxText(purpose)
    self.shopSearchPurpose = purpose or "shop"
    if not self.shopSearchBox or not self.shopSearchBox.setText then
        return
    end
    local text = self.shopSearchText or ""
    if self.shopSearchPurpose == "recycle" then
        text = self.recycleSearchText or ""
    elseif self.shopSearchPurpose == "attribute" then
        text = self.attributeSearchText or ""
    elseif self.shopSearchPurpose ~= "shop" then
        text = ""
    end
    if self.shopSearchBox.getInternalText then
        local current = self.shopSearchBox:getInternalText() or ""
        if current == text then
            return
        end
    end
    self.suppressSearchChange = true
    self.shopSearchBox:setText(text)
    self.suppressSearchChange = false
end

function GodSystemWindow:shopItemMatchesSearch(item, category)
    local query = gsTrim(self.shopSearchText or "")
    if query == "" then
        return true
    end
    local haystack = tostring(GodSystemApp.services.runtime.getShopLabel(item)) .. " " ..
        tostring(GodSystemApp.services.runtime.getShopDescription(item)) .. " " ..
        tostring(GodSystemApp.services.runtime.getShopRewardText(item)) .. " " ..
        tostring(category and category.label or "") .. " " ..
        tostring(GodSystemApp.services.runtime.getShopPrimaryFullType(item) or "")
    return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(query or "")), 1, true) ~= nil
end

function GodSystemWindow:recycleItemMatchesSearch(group)
    local query = gsTrim(self.recycleSearchText or "")
    if query == "" then
        return true
    end
    local haystack = tostring(group and group.label or "") .. " " ..
        tostring(group and group.fullType or "") .. " " ..
        tostring(group and group.valueEach or "") .. " " ..
        tostring(group and group.totalValue or "") .. " " ..
        tostring(group and group.count or "")
    return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(query or "")), 1, true) ~= nil
end
end
