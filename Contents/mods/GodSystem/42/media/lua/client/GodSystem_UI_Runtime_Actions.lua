_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Actions"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Actions then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Actions = true
    setfenv(1, runtimeEnvironment)

function GodSystemWindow:getSelectedHomeEntry()
    local payload = self:getSelectedPayload()
    if payload and payload.kind == "homePoint" then
        return payload.data
    end
    return nil
end

function GodSystemWindow:onPrimaryAction()
    local payload = self:getSelectedPayload()
    if self.mode == "settings" then
        if payload and payload.target == "headUpNotifications" then
            GodSystemApp.services.runtime.setHeadUpNotificationsEnabled(not GodSystemApp.services.runtime.getHeadUpNotificationsEnabled())
            self:populateList()
            return
        end
        self:beginPanelKeyCapture(payload and payload.target or "panel")
        return
    end
    if self.mode == "rangeRecycle" then
        local player = getPlayer and getPlayer() or nil
        local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
        local service = GodSystemApp.services.rangeRecycle
        local model = service:getViewModel(playerNum)
        service:execute(playerNum, model.status == "running" and "cancel" or "start", {}, function(result)
            if result and result.ok == false then
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("NotifyMP_" .. tostring(result.code), tostring(result.code)))
            end
        end)
        self:requestDeferredPopulate(1)
        return
    end
    if self.mode == "attribute" then
        self:showAttributeAmountDialog(payload)
        return
    end
    if self.mode == "companion" then
        if not payload or payload.kind ~= "companionNode" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CompanionSelectAbility", "Select a companion ability"))
            return
        end
        self:prepareActionSelection(payload)
        if GodSystemApp.services.runtime.purchaseCompanionNode(payload.id) then
            self:populateList()
        else
            self:clearPendingActionSelection()
        end
        return
    end
    if self.mode == "info" or self.mode == "history" or self.mode == "diagnostics" then
        self:close()
        return
    end
    if self.mode == "bank" then
        if payload and payload.kind == "bankLoanPlan" then
            local plan = payload.data or {}
            self:showBankAmountDialog("borrowLoan", GodSystemApp.services.runtime.text("Bank_LoanPrompt", "Enter loan amount. Loan goes to current account; overdue more than 10 days causes bankruptcy."), plan.id)
            return
        elseif payload and payload.kind == "bankLoanActive" then
            local sent = GodSystemApp.services.runtime.performBankAction("repayLoanDue", 1)
            self:finishMultiplayerCommand(sent)
            return
        elseif payload and payload.kind == "bankInvestment" then
            local profile = payload.profile or {}
            self:showBankAmountDialog("investFromCurrent", GodSystemApp.services.runtime.text("Bank_InvestCurrentPrompt", "Enter amount to invest from current account"), profile.id)
            return
        elseif payload and payload.kind == "bankFixed" then
            self:confirmBankFixedWithdraw(payload.data)
            return
        end
        self:showBankAmountDialog("deposit", GodSystemApp.services.runtime.text("Bank_DepositPrompt", "Deposit cash into current account"))
        return
    end
    if self.mode == "upgrades" then
        if not payload then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectOne", "Select an item first"))
            return
        end
        if payload.kind == "medicalService" then
            self:confirmMedicalService(payload.data)
            return
        elseif payload.kind == "upgrade" then
            self:prepareActionSelection(payload)
            local sent = GodSystemApp.services.runtime.upgradeSystem(payload.data and payload.data.upgradeType)
            self:finishMultiplayerCommand(sent)
            return
        end
    end
    if self.mode == "traits" then
        if not payload or payload.kind ~= "trait" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectTrait", "Select a trait first"))
            return
        end
        self:confirmTraitModification(payload.data)
        return
    end
    if self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if not entry then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectOne", "Select an item first"))
            return
        end
        if entry.kind == "home" then
            self:confirmHomeAction("setHome")
        elseif entry.kind == "return" then
            self:confirmHomeAction("return")
        elseif entry.kind == "temp" then
            if not entry.owned then
                self:confirmHomeAction("buyTemp", entry.index)
            else
                self:confirmHomeAction("setTemp", entry.index)
            end
        elseif entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
            if not info.homeSet then
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_NeedHome", "Set a home first."))
            elseif not info.unlocked then
                self:confirmHomeAction("unlockSafeZone")
            else
                local sent = GodSystemApp.services.runtime.performHomeAction("toggleSafeZone")
                self:finishMultiplayerCommand(sent)
            end
        end
        return
    end
    if not payload then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectOne", "Select an item first"))
        return
    end
    if payload.kind == "shop" then
        self:prepareActionSelection(payload)
        local sent = GodSystemApp.services.runtime.buyShopItem(payload.data, 1)
        self:finishMultiplayerCommand(sent)
        return
    elseif payload.kind == "recycle" then
        self:recyclePayload(payload, 1)
        return
    elseif payload.kind == "task" then
        local task = payload.data
        if task.status == "open" then
            local sent = GodSystemApp.services.runtime.acceptTask(task)
            self:finishMultiplayerCommand(sent)
            return
        elseif task.status == "active" then
            if GodSystemApp.services.runtime.isTaskComplete(task) then
                if GodSystemApp.services.runtime.isTurnInTask and GodSystemApp.services.runtime.isTurnInTask(task) then
                    self:showTaskTurnInDialog(task)
                else
                    local sent = GodSystemApp.services.runtime.claimTask(task)
                    self:finishMultiplayerCommand(sent)
                end
            else
                self:confirmAbandonTask(task)
            end
            return
        elseif task.status == "failed" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TaskAlreadyFailed", "Task already failed"))
        elseif task.status == "claimed" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RewardClaimed", "Reward already claimed"))
        end
    elseif payload.kind == "upgrade" then
        self:prepareActionSelection(payload)
        local sent = GodSystemApp.services.runtime.upgradeSystem(payload.data and payload.data.upgradeType)
        self:finishMultiplayerCommand(sent)
        return
    end
    self:populateList()
end

function GodSystemWindow:recyclePayload(payload, count)
    if not payload or payload.kind ~= "recycle" or not payload.data then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    count = math.max(1, math.floor(count or 1))
    count = math.min(count, payload.data.count or count)
    self:prepareActionSelection(payload)
    local sent = GodSystemApp.services.runtime.recycleInventoryItems(payload.data.fullType, count)
    self:finishMultiplayerCommand(sent)
    return true
end

function GodSystemWindow:confirmListOnlyAutoShop(payload)
    if not payload or payload.kind ~= "recycle" or not payload.data then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    local fullType = payload.data.fullType
    if not fullType then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return false
    end
    local cost, buyPrice = GodSystemApp.services.runtime.getAutoShopListOnlyCost(fullType, payload.data.sellPrice or payload.data.valueEach or payload.data.value or 1)
    local message = gsFormatTemplate(GodSystemApp.services.runtime.text("Confirm_ListOnlyAutoShop", "List {1} in shop?\nFee: {2}\nShop price: {3}\nThe item will not be removed or sold."), {
        tostring(payload.data.label or payload.text or fullType),
        tostring(cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"),
        tostring(buyPrice) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"),
    })
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, message, true, self, self.onListOnlyAutoShopConfirm, playerNum, { payload = payload })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        self:onListOnlyAutoShopConfirm({ internal = "YES" }, { payload = payload })
    end
    return true
end

function GodSystemWindow:onListOnlyAutoShopConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local row = payload and payload.payload
    if not row or not row.data then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return
    end
    self:prepareActionSelection(row)
    if not row.data.listItemId then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_ListItemChanged", "The selected item changed; reopen the recycle page"))
        return
    end
    local sent = GodSystemApp.services.runtime.listOnlyAutoShopItem(row.data.fullType, row.data.listItemId)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:buyShopPayload(payload, count)
    if not payload or payload.kind ~= "shop" or not payload.data then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectOne", "Select an item first"))
        return false
    end
    self:prepareActionSelection(payload)
    local sent = GodSystemApp.services.runtime.buyShopItem(payload.data, count or 1)
    self:finishMultiplayerCommand(sent)
    return true
end

function GodSystemWindow:hideShopPayload(payload)
    if not payload or payload.kind ~= "shop" or not payload.data or payload.data.unlocked ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select a player-listed shop item"))
        return false
    end
    local variantKey = payload.data.variantKey or payload.data.fullType
    if not variantKey then return false end
    self:prepareActionSelection(payload)
    local sent = GodSystemApp.services.runtime.setShopItemHidden(variantKey, true)
    self:finishMultiplayerCommand(sent)
    return true
end

function GodSystemWindow:onListRightMouseUp(x, y)
    if self.mode ~= "recycle" and self.mode ~= "shop" then
        return false
    end
    local payload = self:selectListRowAt(x, y, self.list, self.mode == "tasks" and "open" or nil)
    if not payload or not payload.data then
        return false
    end

    if self.mode == "shop" then
        if payload.kind ~= "shop" then
            return false
        end
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
        context:addOption(GodSystemApp.services.runtime.text("Menu_BuyOne", "Buy 1"), self, self.buyShopPayload, payload, 1)
        context:addOption(GodSystemApp.services.runtime.text("Menu_BuyTen", "Buy 10"), self, self.buyShopPayload, payload, 10)
        context:addOption(GodSystemApp.services.runtime.text("Menu_BuyFifty", "Buy 50"), self, self.buyShopPayload, payload, 50)
        if payload.data.unlocked == true then
            context:addOption(GodSystemApp.services.runtime.text("Menu_HideShopItem", "Hide this item"), self, self.hideShopPayload, payload)
        end
        return true
    end

    if payload.kind ~= "recycle" then
        return false
    end
    local count = payload.data.count or 0
    if count <= 0 then
        return false
    end

    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(GodSystemApp.services.runtime.text("Menu_SellOne", "Sell 1"), self, self.recyclePayload, payload, 1)

    local half = math.floor(count / 2)
    if half > 0 then
        context:addOption(GodSystemApp.services.runtime.text("Menu_SellHalf", "Sell half") .. " (" .. tostring(half) .. ")", self, self.recyclePayload, payload, half)
    end
    context:addOption(GodSystemApp.services.runtime.text("Menu_SellAll", "Sell all") .. " (" .. tostring(count) .. ")", self, self.recyclePayload, payload, count)
    context:addOption(GodSystemApp.services.runtime.text("Menu_ListOnly", "List only"), self, self.confirmListOnlyAutoShop, payload)
    return true
end

function GodSystemWindow:onSecondaryAction()
    if self.mode == "settings" then
        GodSystemPanelKey.cancelCapture("reset")
        local selected = self:getSelectedPayload()
        if selected and selected.target == "headUpNotifications" then
            return
        end
        if selected and selected.target == "range" then
            GodSystemPanelKey.resetRange()
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Settings_RangeKeyReset", "Range recycle key restored to G"))
        else
            GodSystemPanelKey.reset()
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Settings_KeyReset", "Panel key restored to N"))
        end
        self:populateList()
        return
    end
    if self.mode == "rangeRecycle" then
        GodSystemUI.openRangeFilterWindow(self)
        return
    end
    if self.mode == "attribute" then
        self:showAttributeNextLevelConfirm(self:getSelectedPayload())
        return
    end
    if self.mode == "companion" then
        if GodSystemCompanion and GodSystemCompanion.toggleVisible then GodSystemCompanion.toggleVisible() end
        self:populateList()
        return
    end
    if self.mode == "bank" then
        local payload = self:getSelectedPayload()
        if payload and payload.kind == "bankLoanActive" then
            local sent = GodSystemApp.services.runtime.performBankAction("payoffLoan", 1)
            self:finishMultiplayerCommand(sent)
            return
        elseif payload and payload.kind == "bankInvestment" then
            local profile = payload.profile or {}
            self:showBankAmountDialog("investFromCash", GodSystemApp.services.runtime.text("Bank_InvestCashPrompt", "Enter carried cash amount to invest"), profile.id)
            return
        end
        self:showBankAmountDialog("withdraw", GodSystemApp.services.runtime.text("Bank_WithdrawPrompt", "Withdraw current account to cash"))
        return
    elseif self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if entry and entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
            if info.unlocked then
                self:confirmHomeAction("clearSafeZone")
            else
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("HomeSafe_Locked", "Locked"))
            end
        elseif entry and entry.kind == "return" then
            self:confirmHomeAction("clearReturn")
        elseif entry and entry.kind == "home" and entry.point then
            self:confirmHomeAction("teleportHome")
        elseif entry and entry.kind == "temp" and entry.owned and entry.point then
            self:confirmHomeAction("teleportTemp", entry.index)
        else
            if self:requestServerRefresh() then
                return
            end
            self:populateList()
        end
    elseif self.mode == "shop" or self.mode == "recycle" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "traits" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "upgrades" then
        local payload = self:getSelectedPayload()
        if payload and payload.kind == "upgrade" and payload.data and payload.data.upgradeType == "carryCapacity" then
            local sent = GodSystemApp.services.runtime.refreshCarryCapacity()
            self:finishMultiplayerCommand(sent)
            return
        end
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
    elseif self.mode == "tasks" then
        if self:getActivePageSection("tasks") == "taskExtensions" then
            if self:requestServerRefresh() then return end
            self:populateList()
            return
        end
        local sent = GodSystemApp.services.runtime.refreshOpenTasks()
        self:finishMultiplayerCommand(sent)
    elseif self.mode == "diagnostics" then
        if gsIsMultiplayer() and GodSystemNetwork and GodSystemNetwork.requestDiagnostics then
            local sent = GodSystemNetwork.requestDiagnostics()
            self:finishMultiplayerCommand(sent)
        else
            self:populateList()
        end
    elseif self.mode == "info" and GodSystemConfig.EnableDebugTools then
        local sent = GodSystemApp.services.runtime.debugAddPoints()
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onThirdAction()
    local payload = self:getSelectedPayload()
    if self.mode == "settings" then
        GodSystemPanelKey.cancelCapture("closed")
        self:close()
        return
    end
    if self.mode == "companion" then
        if GodSystemCompanionUI and GodSystemCompanionUI.toggleShortcut then GodSystemCompanionUI.toggleShortcut(self) end
        self:populateList()
        return
    end
    if self.mode == "bank" then
        if not payload or payload.kind ~= "bankInvestment" then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankInvestmentSelect", "Select an investment account"))
            return
        end
        local profile = payload.profile or {}
        self:showBankAmountDialog("redeemInvestment", GodSystemApp.services.runtime.text("Bank_RedeemInvestmentPrompt", "Enter amount to redeem to current account"), profile.id)
        return
    end
    if self.mode == "home" then
        local entry = self:getSelectedHomeEntry()
        if entry and entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
            if info.nextLevel then
                self:confirmHomeAction("upgradeSafeZone")
            else
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeSafeMaxLevel", "Home safe zone is already at max level"))
            end
        else
            local home = GodSystemApp.services.runtime.getHomeSystem()
            if home and home.returnPoint then
                self:confirmHomeAction("return")
            else
                GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_HomeNoReturn", "No return point"))
            end
        end
        return
    end
    if self.mode == "shop" then
        if not payload or payload.kind ~= "shop" or not payload.data or payload.data.unlocked ~= true then
            GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectUnlocked", "Select an unlocked shop item"))
            return
        end
        local variantKey = payload.data.variantKey or payload.data.fullType
        if not variantKey and payload.data.items and payload.data.items[1] then
            variantKey = GodSystemShopVariants.getKey(payload.data.items[1].fullType, payload.data.items[1].worldSprite)
        end
        self:prepareActionSelection(payload)
        local sent = GodSystemApp.services.runtime.setShopItemHidden(variantKey, true)
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "tasks" then
        if self:getActivePageSection("tasks") == "taskExtensions" then
            return
        end
        GodSystemUI.toggleTaskTracker()
        self:populateList()
        return
    end
    if self.mode ~= "recycle" or not payload or payload.kind ~= "recycle" then
        if self.mode == "recycle" then
            local sent = GodSystemApp.services.runtime.toggleRecycleUnlockMode()
            self:finishMultiplayerCommand(sent)
            return
        end
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectRecycle", "Select a recyclable item"))
        return
    end
    local sent = GodSystemApp.services.runtime.toggleRecycleUnlockMode()
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:onFourthAction()
    if self.mode == "companion" then
        if GodSystemCompanion and GodSystemCompanion.recall then GodSystemCompanion.recall() end
        self:populateList()
        return
    end
    if self.mode == "shop" then
        self:changeShopPage(-1)
        return
    end
    if self.mode == "bank" then
        local sent = GodSystemApp.services.runtime.performBankAction("toggleAutoDeposit")
        self:finishMultiplayerCommand(sent)
        if not gsIsMultiplayer() then self:populateList() end
        return
    end
    if self.mode == "tasks" then
        local sent = GodSystemApp.services.runtime.toggleAutoTaskClaim()
        self:finishMultiplayerCommand(sent)
        if not gsIsMultiplayer() then self:populateList() end
        return
    end
    if self.mode == "home" then
        if self:requestServerRefresh() then
            return
        end
        self:populateList()
        return
    end
    self:populateList()
end

function GodSystemWindow:onFifthAction()
    if self.mode == "bank" then
        local sent = GodSystemApp.services.runtime.consolidateCurrency()
        self:finishMultiplayerCommand(sent)
        return
    end
    if self.mode == "shop" then
        self:changeShopPage(1)
        return
    end
    self:populateList()
end

function GodSystemWindow:onSixthAction()
    if self.mode == "shop" then
        GodSystemUI.openShopHiddenManager(self)
        return
    end
    self:populateList()
end

function GodSystemWindow:onSeventhAction()
    self:populateList()
end

function GodSystemWindow:close()
    if GodSystemPanelKey.isCapturing() then
        GodSystemPanelKey.cancelCapture("windowClosed")
    end
    if GodSystemUI.shopHiddenWindow then GodSystemUI.shopHiddenWindow:close() end
    if GodSystemItemEconomyUI and GodSystemItemEconomyUI.window then GodSystemItemEconomyUI.window:close() end
    if self.rangeRecycleUnsubscribe then
        self.rangeRecycleUnsubscribe()
        self.rangeRecycleUnsubscribe = nil
    end
    local data = GodSystemApp.services.runtime.getData()
    data.ui.windowX = math.floor(self.x or 0)
    data.ui.windowY = math.floor(self.y or 0)
    data.ui.windowScale = self:getUIScale()
    GodSystemApp.services.runtime.save()
    ISCollapsableWindow.close(self)
    GodSystemUI.window = nil
end
end
