_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Details"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Details then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Details = true
    setfenv(1, runtimeEnvironment)

function GodSystemWindow:populateList()
    self:resetActionButtonEnabledState()
    if self.mode == "recycle" then
        self.mode = "shop"
    end
    self:captureSelection()
    self:clearList()
    self.thirdButton:setVisible(false)
    self.secondaryButton:setVisible(true)
    self.primaryButton:setVisible(true)
    self:applyBaseLayout()
    self:setTaskLayout(self.mode == "tasks" and self:getActivePageSection("tasks") == "tasks")
    self:setShopLayout(self.mode == "shop" or self.mode == "recycle" or self.mode == "attribute")
    self:setTextPageLayout(self.mode == "settings" or self.mode == "history" or self.mode == "info" or self.mode == "diagnostics")
    self:updateModeButtonStyles()

    if self:needsServerState() then
        self:addSyncPlaceholder()
        if GodSystemNetwork and GodSystemNetwork.requestState then
            GodSystemNetwork.requestState(false)
        end
        self:setActionBar({})
        self:updateDetail()
        return
    end

    if self.mode == "shop" then
        self:populateShop()
    elseif self.mode == "rangeRecycle" then
        self:populateRangeRecycle()
    elseif self.mode == "recycle" then
        self:populateRecycle()
    elseif self.mode == "bank" then
        self:populateBank()
    elseif self.mode == "traits" then
        self:populateTraits()
    elseif self.mode == "attribute" then
        self:populateAttributes()
    elseif self.mode == "home" then
        self:populateHome()
    elseif self.mode == "tasks" then
        self:populateTasks()
    elseif self.mode == "upgrades" then
        self:populateUpgrades()
    elseif self.mode == "companion" then
        self:populateCompanion()
    elseif self.mode == "settings" then
        self:populateSettings()
    elseif self.mode == "history" then
        self:populateHistory()
    elseif self.mode == "info" then
        self:populateInfo()
    elseif self.mode == "diagnostics" then
        self:populateDiagnostics()
    elseif self.mode == "attribute" then
        self:applyAttributeActionBar(self:getSelectedPayload())
    end

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
    local selectionRestored = self:restoreSelection()
    local listStateRestored = self:restoreScrollState()
    self:restoreActiveListState()
    if not self:hasPendingListRestore() then
        self:restorePageSectionState(self.mode)
    end
    self:updateDetail()
    self:restoreDetailListState()
    if (selectionRestored or listStateRestored) and self.pendingRestoreMode == self.mode then
        self:clearPendingActionSelection()
    end
end

function GodSystemWindow:getSelectedPayload()
    if self.mode == "tasks" and self.selectedTaskList == "active" and self.activeList then
        local index = math.floor(tonumber(self.activeList.selected) or 0)
        local selected = index > 0 and self.activeList.items[index] or nil
        local payload = selected and selected.item or nil
        return gsIsSelectablePayload(payload) and payload or nil
    end
    local index = math.floor(tonumber(self.list.selected) or 0)
    local selected = index > 0 and self.list.items[index] or nil
    local payload = selected and selected.item or nil
    return gsIsSelectablePayload(payload) and payload or nil
end

function GodSystemWindow:getPayloadFromListCallback(item)
    if item and item.kind then
        return item
    end
    if item and item.item then
        return item.item
    end
    return self:getSelectedPayload()
end

function GodSystemWindow:selectListRowAt(x, y, list, taskListName)
    list = list or self.list
    if list and list.rowAt then
        local row = list:rowAt(x, y)
        if row and row > 0 and list.items[row] then
            local payload = list.items[row].item
            if not gsIsSelectablePayload(payload) then return nil end
            list.selected = row
            if list == self.activeList then
                self.lastSelectableActiveRow = row
            else
                self.lastSelectableListRow = row
            end
            if self.mode == "tasks" and taskListName then
                self:clearOppositeTaskSelection(taskListName)
            end
            return payload
        end
    end
    return self:getSelectedPayload()
end

function GodSystemWindow:updateDetail()
    local payload = self:getSelectedPayload()
    if self.mode == "tasks" then
        self:updateTaskPrimaryButton(payload)
    end
    if self.mode == "settings" then
        self:updateSettingsActionButtons(payload)
    end
    if self.mode == "shop" and self.thirdButton then
        local removable = payload and payload.kind == "shop" and payload.data and payload.data.unlocked == true
        self.thirdButton:setVisible(removable == true)
        self:applyShopActionLayout()
    end
    if self.mode == "home" then
        self:applyHomeActionBar(payload)
    end
    if self.mode == "bank" then
        self:updateBankActionButtons(payload)
    end
    if self.mode == "upgrades" then
        self:applyUpgradeActionBar(payload)
    end
    if self.mode == "companion" then
        self:applyCompanionActionBar(payload)
    end
    if self.mode == "attribute" then
        self:applyAttributeActionBar(payload)
    end
    if not payload then
        if self.mode == "recycle" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Recycle", "Click an item to view prices. Use button or right click to sell."))
        elseif self.mode == "shop" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Shop", "Only existing basic items are shown. Recycled vanilla items appear as unlocked entries."))
        elseif self.mode == "bank" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Bank", "Deposit cash into current account, move current balance into fixed deposits, and withdraw when needed. Death penalty only deducts current account."))
        elseif self.mode == "traits" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Traits", "Buy positive traits or remove owned negative traits. Risk traits are experimental."))
        elseif self.mode == "attribute" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Attributes", "Select a standard skill, then buy XP by amount or upgrade to the next level."))
        elseif self.mode == "tasks" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_TasksSplit", "Available tasks are on the left. Active tasks are on the right."))
        elseif self.mode == "upgrades" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Upgrades", "Upgrade system task limits here."))
        elseif self.mode == "companion" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Companion", "Select an ability to unlock or upgrade. Use the controls below for visibility, shortcuts and recall."))
        elseif self.mode == "home" then
            self:setDetailText(GodSystemApp.services.runtime.text("Hint_Home", "Set a home or temp teleport point, then teleport with confirmation."))
        elseif self.mode == "admin" then
            self:setDetailText("Select a setting or item override.")
        else
            self:setDetailText("")
        end
        return
    end
    if payload.kind == "shop" then
        local item = payload.data
        local fullType = GodSystemApp.services.runtime.getShopPrimaryFullType(item)
        local quoteText = fullType and GodSystemApp.services.runtime.getEconomyQuoteDetail(fullType, nil, false) or ""
        self:setDetailText(tostring(GodSystemApp.services.runtime.getShopDescription(item)) .. " " .. GodSystemApp.services.runtime.text("Detail_Content", "Content: ") .. GodSystemApp.services.runtime.getShopRewardText(item)
            .. (quoteText ~= "" and ("\n\n" .. quoteText) or ""))
    elseif payload.kind == "recycle" then
        local group = payload.data
        local buyRef = GodSystemApp.services.runtime.getShopBuyReference(group.fullType)
        local buyText = buyRef and (GodSystemApp.services.runtime.text("Detail_BuyRef", "Buy ref: ") .. tostring(buyRef.label) .. " " .. tostring(buyRef.price) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")) or GodSystemApp.services.runtime.text("Detail_BuyRefNone", "Buy ref: none")
        local priceText = GodSystemApp.services.runtime.text("Price_Sell", "Sell") .. " " .. tostring(group.valueEach) .. GodSystemApp.services.runtime.text("Unit_CoinEach", "c each")
        local quoteText = GodSystemApp.services.runtime.getEconomyQuoteDetail(group.fullType, group.items and group.items[1] or nil, false)
        self:setDetailText(GodSystemApp.services.runtime.text("Detail_Sell", "Sell: ") .. group.label .. " | " .. priceText .. ", " .. GodSystemApp.services.runtime.text("Detail_Count", "count ") .. tostring(group.count) .. " | " .. buyText .. "\n\n" .. quoteText)
    elseif payload.kind == "attribute" then
        local row = payload.data or {}
        local nextLevel = math.min(tonumber(row.maxLevel) or 10, (tonumber(row.currentLevel) or 0) + 1)
        local quote = GodSystemApp.services.runtime.getAttributeQuote(row.index, "targetLevel", nextLevel)
        local nextText = quote and (tostring(math.floor(quote.actualXp or 0)) .. " XP / " .. tostring(quote.cost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")) or GodSystemApp.services.runtime.text("Attribute_Maxed", "Maxed")
        self:setDetailText(tostring(row.label or "") .. "\n" ..
            GodSystemApp.services.runtime.text("Attribute_CurrentLevel", "Current level") .. ": " .. tostring(row.currentLevel or 0) .. "/" .. tostring(row.maxLevel or 10) .. "\n" ..
            GodSystemApp.services.runtime.text("Attribute_TotalXP", "Total XP") .. ": " .. tostring(math.floor(row.currentXp or 0)) .. "/" .. tostring(math.floor(row.maxXp or 0)) .. "\n" ..
            GodSystemApp.services.runtime.text("Attribute_NextCost", "Next level") .. ": " .. nextText .. "\n" ..
            GodSystemApp.services.runtime.text("Attribute_Rate", "Rate") .. ": 1" .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") .. " = " .. tostring(GodSystemAttributes.getXpPerCoin()) .. " XP")
    elseif payload.kind == "bankSummary" or payload.kind == "bankCurrent" then
        local summary = GodSystemApp.services.runtime.getBankSummary()
        local text = GodSystemApp.services.runtime.text("Bank_DetailSummaryV2", "Cash {1} | Current {2} | Investment {3} | Legacy fixed principal {4} | Legacy mature value {5} | Death deducts current only, preview {6}")
        self:setDetailText(gsFormatTemplate(text, { summary.cash or 0, summary.current or 0, summary.investmentTotal or 0, summary.fixedPrincipal or 0, summary.fixedMatureValue or 0, summary.deathPenalty or 0 }))
    elseif payload.kind == "bankTerm" then
        local term = payload.data or {}
        local days = math.max(1, math.floor(tonumber(term.days) or 1))
        local rate = math.floor((tonumber(term.interestRate) or 0) * 100)
        self:setDetailText(gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_DetailTerm", "Move current account balance or carried cash into a {1}-day fixed deposit. Interest {2}%. Early withdrawal has no interest and loses part of principal."), { days, rate }))
    elseif payload.kind == "bankInvestment" then
        local account = payload.data or {}
        local profile = payload.profile or GodSystemApp.services.runtime.getBankInvestmentProfile(account.tierId) or {}
        local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
        local status = account.redeemUnlocked == true and GodSystemApp.services.runtime.text("Bank_InvestmentRedeemable", "Redeemable") or GodSystemApp.services.runtime.text("Bank_InvestmentLocked", "Locked until first settlement")
        local rule = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_InvestmentRule", "Gain {1}% chance +{2}% | Loss {3}% chance -{4}% | Flat {5}%"), {
            profile.gainChance or 0,
            profile.gainPercent or 0,
            profile.lossChance or 0,
            profile.lossPercent or 0,
            math.max(0, 100 - (profile.gainChance or 0) - (profile.lossChance or 0)),
        })
        local progress = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_InvestmentProgress", "Online progress {1}/{2}h"), { math.floor(tonumber(account.onlineHours) or 0), settlementHours })
        self:setDetailText(GodSystemApp.services.runtime.getBankInvestmentLabel(profile.id or account.tierId) .. " | " .. tostring(account.balance or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") .. "\n" .. rule .. "\n" .. progress .. " | " .. status)
    elseif payload.kind == "bankFixed" then
        local entry = payload.data
        local payout, interestOrPenalty, mature = GodSystemApp.services.runtime.getBankFixedPayout(entry)
        local text = mature and GodSystemApp.services.runtime.text("Bank_DetailFixedMature", "Matured. Withdraw to current account with interest.") or GodSystemApp.services.runtime.text("Bank_DetailFixedEarly", "Not mature. Early withdrawal gives no interest and applies penalty.")
        self:setDetailText(text .. " | " .. GodSystemApp.services.runtime.text("Bank_Payout", "payout") .. " " .. tostring(payout) .. " | " .. GodSystemApp.services.runtime.text("Bank_InterestPenalty", "interest/penalty") .. " " .. tostring(interestOrPenalty))
    elseif payload.kind == "bankLoanSummary" then
        local s = payload.data or GodSystemApp.services.runtime.getBankLoanSummary and GodSystemApp.services.runtime.getBankLoanSummary() or {}
        local text = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanSummary", "Loan credit {1} | Available {2} | Debt {3} | Frozen {4}"), {
            tostring(s.creditTotal or 0),
            tostring(s.creditAvailable or 0),
            tostring(s.unpaidTotal or 0),
            tostring(s.freezeLeftHours or 0) .. GodSystemApp.services.runtime.text("Unit_Hour", "h"),
        })
        self:setDetailText(text)
    elseif payload.kind == "bankLoanPlan" then
        local plan = payload.data or {}
        local s = payload.summary or GodSystemApp.services.runtime.getBankLoanSummary and GodSystemApp.services.runtime.getBankLoanSummary() or {}
        local rate = math.floor((tonumber(plan.totalInterestRate) or 0) * 100)
        local days = math.max(1, math.floor((tonumber(plan.dueHours) or 72) / 24))
        local periods = math.max(1, math.floor(tonumber(plan.periods) or 1))
        local text = GodSystemApp.services.runtime.text("Bank_LoanPrompt", "Enter loan amount. Loan goes to current account; overdue more than 10 days causes bankruptcy.") ..
            " | " .. GodSystemApp.services.runtime.text("Bank_LoanDueNow", "Due now") .. ": " .. tostring(days) .. "d x " .. tostring(periods) ..
            " | " .. GodSystemApp.services.runtime.text("Bank_Interest", "interest") .. ": " .. tostring(rate) .. "%" ..
            " | " .. GodSystemApp.services.runtime.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(s.creditAvailable or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        self:setDetailText(text)
    elseif payload.kind == "bankLoanActive" then
        local loan = payload.data or {}
        local s = payload.summary or GodSystemApp.services.runtime.getBankLoanSummary and GodSystemApp.services.runtime.getBankLoanSummary() or {}
        local text = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanActive", "Active loan {1} | Paid {2}/{3}"), {
            tostring(loan.id or ""),
            tostring(loan.paid or 0),
            tostring(loan.totalDue or 0),
        }) .. " | " .. GodSystemApp.services.runtime.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(s.dueNow or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") ..
            " | " .. GodSystemApp.services.runtime.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(s.payoff or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        if s.bankruptcyInHours then
            text = text .. " | " .. GodSystemApp.services.runtime.text("Bank_LoanFrozen", "Loan frozen, remaining {1} hours"):gsub("{1}", tostring(s.bankruptcyInHours))
        end
        self:setDetailText(text)
    elseif payload.kind == "task" then
        self:setDetailText(GodSystemApp.services.runtime.getTaskDetailText(payload.data))
    elseif payload.kind == "trait" then
        self:setDetailText(GodSystemApp.services.runtime.getTraitDetailText(payload.data))
    elseif payload.kind == "upgrade" then
        local upgradeType = payload.data and payload.data.upgradeType
        self:setDetailText(GodSystemApp.services.runtime.getSystemUpgradeDetailText(upgradeType))
    elseif payload.kind == "medicalService" then
        local info = payload.data or {}
        self:setDetailText(tostring(info.desc or "") .. " | " .. GodSystemApp.services.runtime.text("Upgrade_Cost", "Cost") .. " " .. tostring(info.cost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
    elseif payload.kind == "companionNode" or payload.kind == "companionState" then
        local detail = tostring(payload.detail or "")
        local state = GodSystemCompanion and GodSystemCompanion.getStateDetail and GodSystemCompanion.getStateDetail() or ""
        if state ~= "" and payload.kind ~= "companionState" then detail = detail .. "\n\n" .. state end
        self:setDetailText(detail)
    elseif payload.kind == "homePoint" then
        local entry = payload.data
        self:setDetailText((entry and entry.label or GodSystemApp.services.runtime.text("Tab_Home", "Home/Teleport")) .. " | " .. GodSystemApp.services.runtime.getHomeEntryDetail(entry))
    elseif payload.kind == "traitHeader" then
        self:setDetailText(payload.detail or "")
    elseif payload.kind == "history" then
        self:setDetailText(payload.data and payload.data.text or GodSystemApp.services.runtime.text("Tab_History", "History"))
    elseif payload.kind == "info" then
        self:setDetailText(payload.data or "")
    elseif payload.kind == "rangeStatus" or payload.kind == "rangeFilterItem" then
        self:setDetailText(payload.detail or "")
    elseif payload.kind == "empty" then
        self:setDetailText(payload.detail or "")
    else
        self:setDetailText("")
    end
end

function GodSystemWindow:updateSettingsActionButtons(payload)
    local isHeadUpToggle = payload and payload.target == "headUpNotifications"
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text(isHeadUpToggle and "Settings_Toggle" or "Settings_ChangeKey", isHeadUpToggle and "Toggle" or "Change key"))
    gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_Close", "Close"))
    if isHeadUpToggle then
        self:setActionBar({
            { id = "primary", width = 150 },
            { id = "third", width = 120 },
        })
        return
    end
    local rangeSelected = payload and payload.target == "range"
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text(rangeSelected and "Settings_RangeKeyReset" or "Settings_KeyReset", rangeSelected and "Range recycle key restored to G" or "Panel key restored to N"))
    self:setActionBar({
        { id = "primary", width = 150 },
        { id = "secondary", width = 150 },
        { id = "third", width = 120 },
    })
end
end
