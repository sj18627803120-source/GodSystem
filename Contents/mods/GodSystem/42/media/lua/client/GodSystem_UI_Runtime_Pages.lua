_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Pages"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Pages then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Pages = true
    setfenv(1, runtimeEnvironment)

function GodSystemWindow:populateShop()
    self.shopSearchPurpose = "shop"
    self:syncSearchBoxText(self.shopSearchPurpose)
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_Buy", "Buy"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_HideUnlocked", "Hide listing"))
    self.thirdButton:setVisible(false)
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text("Btn_ShopPrevPage", "Prev"))
    self.fourthButton:setVisible(true)
    gsSetButtonTitle(self.fifthButton, GodSystemApp.services.runtime.text("Btn_ShopNextPage", "Next"))
    self.fifthButton:setVisible(true)
    gsSetButtonTitle(self.sixthButton, GodSystemApp.services.runtime.text("Btn_ShopHiddenManager", "Hidden manager"))
    self.sixthButton:setVisible(true)
    local shopItems = {}
    local seenShopKeys = {}
    local categoryMap = {}
    local categories = {}
    for i = 1, #GodSystemConfig.ShopItems do
        local item = GodSystemConfig.ShopItems[i]
        local available, reason, availableItems, missingItems = GodSystemApp.services.runtime.shopItemIsAvailable(item)
        local featureEnabled = not item.featureKey
            or GodSystemRuntimeConfig.isFeatureEnabled(item.featureKey) ~= false
        if featureEnabled and available and (not missingItems or #missingItems == 0) then
            table.insert(shopItems, item)
            local one = item.items and item.items[1]
            if one and #(item.items or {}) == 1 and math.max(1, math.floor(tonumber(one.count) or 1)) == 1 then
                seenShopKeys[GodSystemShopVariants.getKey(one.fullType, one.worldSprite)] = true
            end
        end
    end

    local unlocked = GodSystemApp.services.runtime.getUnlockedShopItemsList()
    for i = 1, #unlocked do
        local key = unlocked[i].variantKey or GodSystemShopVariants.getKey(unlocked[i].fullType, unlocked[i].worldSprite)
        if not seenShopKeys[key] then table.insert(shopItems, unlocked[i]); seenShopKeys[key] = true end
    end
    local forced = GodSystemApp.services.runtime.getForcedShopItemsList and GodSystemApp.services.runtime.getForcedShopItemsList() or {}
    for i = 1, #forced do
        local key = forced[i].variantKey or GodSystemShopVariants.getKey(forced[i].fullType, forced[i].worldSprite)
        if not seenShopKeys[key] then table.insert(shopItems, forced[i]); seenShopKeys[key] = true end
    end

    for i = 1, #shopItems do
        local category = GodSystemApp.services.runtime.getShopPrimaryCategory(shopItems[i])
        if not categoryMap[category.key] then
            categoryMap[category.key] = true
            table.insert(categories, category)
        end
    end
    table.sort(categories, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)
    self:updateShopCategoryButton(categories)

    local filteredShopItems = {}
    for i = 1, #shopItems do
        local item = shopItems[i]
        local category = GodSystemApp.services.runtime.getShopPrimaryCategory(item)
        if (self.shopCategoryKey == "all" or category.key == self.shopCategoryKey) and self:shopItemMatchesSearch(item, category) then
            filteredShopItems[#filteredShopItems + 1] = { item = item, category = category }
        end
    end
    local pageSize = self.ShopPageSize or 20
    local totalPages = math.max(1, math.ceil(#filteredShopItems / pageSize))
    self.shopPage = math.max(1, math.min(math.floor(self.shopPage or 1), totalPages))
    local startIndex = ((self.shopPage - 1) * pageSize) + 1
    local endIndex = math.min(#filteredShopItems, startIndex + pageSize - 1)
    if #filteredShopItems > 0 then
        self:addListItem(string.format("%s %d/%d | %d %s", GodSystemApp.services.runtime.text("Shop_Page", "Page"), self.shopPage, totalPages, #filteredShopItems, GodSystemApp.services.runtime.text("Shop_Items", "items")), { kind = "shopPager", detail = GodSystemApp.services.runtime.text("Shop_PageHint", "Use page buttons below") })
    end
    for i = startIndex, endIndex do
        local row = filteredShopItems[i]
        local item = row.item
        local category = row.category
        local text = string.format("[%s] %s", category.label or GodSystemApp.services.runtime.getShopGroup(item), GodSystemApp.services.runtime.getShopLabel(item))
        local detail = tostring(GodSystemApp.services.runtime.getShopItemUnitPrice(item) or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        self:addListItem(text, { kind = "shop", data = item, detail = detail })
    end
    if #filteredShopItems == 0 then
        local detail = GodSystemApp.services.runtime.text("Shop_EmptyHint", "No shop item matches this category or search.")
        self:addListItem(GodSystemApp.services.runtime.text("Shop_EmptyCategory", "No item in this category"), { kind = "empty", detail = detail })
    end
    self:applyShopActionLayout()
    self:updateShopCategoryButton(categories)
end

function GodSystemWindow:populateRecycle()
    self.shopSearchPurpose = "recycle"
    self:syncSearchBoxText(self.shopSearchPurpose)
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_SellOne", "Sell 1"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshBag", "Refresh bag"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    if GodSystemApp.services.runtime.isRecycleUnlockMode() then
        gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_RecycleModeUnlock", "Mode: unlock"))
    else
        gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_RecycleModeOnly", "Mode: recycle only"))
    end
    self.thirdButton:setVisible(true)
    local groups, order = GodSystemApp.services.runtime.getInventoryRecycleGroups()
    local shown = 0
    for i = 1, #order do
        local group = groups[order[i]]
        if self:recycleItemMatchesSearch(group) then
            shown = shown + 1
            local text = string.format("%s x%d", group.label, group.count)
            local buyRef = GodSystemApp.services.runtime.getShopBuyReference(group.fullType)
            local buyText = buyRef and (GodSystemApp.services.runtime.text("Price_Buy", "Buy ") .. tostring(buyRef.price) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") .. "/" .. tostring(buyRef.label)) or GodSystemApp.services.runtime.text("Price_BuyNone", "Buy none")
            local sellText = string.format("%s %d%s", GodSystemApp.services.runtime.text("Price_Sell", "Sell"), group.valueEach, GodSystemApp.services.runtime.text("Unit_CoinEach", "c each"))
            local detail = string.format("%s | %s", sellText, buyText)
            self:addListItem(text, { kind = "recycle", data = group, detail = detail })
        end
    end
    if shown == 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Recycle_Empty", "No recyclable item"), { kind = "empty", detail = "" })
    end
end

function GodSystemWindow:populateBank()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankDeposit", "Deposit"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_BankWithdraw", "Withdraw"))
    self.thirdButton:setVisible(false)
    local bank = GodSystemApp.services.runtime.getBank()
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text(bank.autoDepositEnabled and "Btn_BankAutoDepositOn" or "Btn_BankAutoDepositOff", bank.autoDepositEnabled and "Auto deposit: ON" or "Auto deposit: OFF"))
    gsSetButtonTitle(self.fifthButton, GodSystemApp.services.runtime.text("Btn_BankConsolidateCurrency", "Sort coins"))
    self.secondaryButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(true)

    local summary = GodSystemApp.services.runtime.getBankSummary()
    local line = GodSystemApp.services.runtime.text("Bank_SummaryV2", "Cash {1} | Current {2} | Investment {3} | Legacy fixed {4} | Death penalty preview {5}")
    line = gsFormatTemplate(line, { summary.cash or 0, summary.current or 0, summary.investmentTotal or 0, summary.fixedPrincipal or 0, summary.deathPenalty or 0 })
    self:addListItem(line, { kind = "bankSummary", data = summary, detail = "" })

    local currentText = GodSystemApp.services.runtime.text("Bank_Current", "Current account")
    self:addListItem(currentText, { kind = "bankCurrent", data = summary, detail = tostring(summary.current or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") })

    local loanSummary = GodSystemApp.services.runtime.getBankLoanSummary and GodSystemApp.services.runtime.getBankLoanSummary() or {}
    local freezeText = (loanSummary.freezeLeftHours or 0) > 0 and tostring(loanSummary.freezeLeftHours or 0) .. GodSystemApp.services.runtime.text("Unit_Hour", "h") or "0"
    local loanLine = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanSummary", "Loan credit {1} | Available {2} | Debt {3} | Frozen {4}"), {
        loanSummary.creditTotal or 0,
        loanSummary.creditAvailable or 0,
        loanSummary.unpaidTotal or 0,
        freezeText,
    })
    self:addListItem(loanLine, { kind = "bankLoanSummary", data = loanSummary, detail = "" })

    local loan = loanSummary.loan
    if loan then
        local activeText = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanActive", "Active loan {1} | Paid {2}/{3}"), {
            tostring(loan.id or ""),
            tostring(loan.paid or 0),
            tostring(loan.totalDue or 0),
        })
        local activeDetail = GodSystemApp.services.runtime.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(loanSummary.dueNow or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c") ..
            " | " .. GodSystemApp.services.runtime.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(loanSummary.payoff or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        if loanSummary.overdueStartHour then
            local nowHours = GameTime and GameTime:getInstance() and GameTime:getInstance():getWorldAgeHours() or 0
            activeDetail = activeDetail .. " | " .. gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanOverdue", "Overdue {1} hours"), { tostring(math.max(0, math.ceil(nowHours - (loanSummary.overdueStartHour or nowHours)))) })
        end
        self:addListItem(activeText, { kind = "bankLoanActive", data = loan, summary = loanSummary, detail = activeDetail })
    else
        self:addListItem(GodSystemApp.services.runtime.text("Bank_LoanNoDebt", "No active loan"), { kind = "empty", detail = "" })
    end

    local loanPlans = GodSystemApp.services.runtime.getBankLoanPlans and GodSystemApp.services.runtime.getBankLoanPlans() or {}
    for i = 1, #loanPlans do
        local plan = loanPlans[i]
        local label
        if plan.kind == "single" then
            label = GodSystemApp.services.runtime.text("Bank_LoanPlanSingle", "Short loan | 3 days | interest 5%")
        else
            label = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_LoanPlanInstallment", "{1} period loan | every 3 days | interest {2}%"), {
                tostring(plan.periods or 1),
                tostring(math.floor((tonumber(plan.totalInterestRate) or 0) * 100)),
            })
        end
        local detail = GodSystemApp.services.runtime.text("Bank_LoanDueNow", "Due now") .. " " .. tostring(math.max(1, math.floor((tonumber(plan.dueHours) or 72) / 24))) .. "d" ..
            " | " .. GodSystemApp.services.runtime.text("Bank_LoanPayoff", "Payoff") .. " " .. tostring(math.floor((tonumber(plan.totalInterestRate) or 0) * 100)) .. "%"
        self:addListItem(label, { kind = "bankLoanPlan", data = plan, summary = loanSummary, detail = detail })
    end

    if GodSystemApp.services.runtime.isFeatureEnabled("EnableBankInvestments") ~= false then
        local profiles = GodSystemApp.services.runtime.getBankInvestmentProfiles()
        local settlementHours = math.max(1, tonumber(GodSystemConfig.BankInvestmentSettlementHours) or 24)
        for i = 1, #profiles do
            local profile = profiles[i]
            local account = GodSystemApp.services.runtime.getBankInvestmentAccount(profile.id) or {}
            local progress = math.min(settlementHours, math.max(0, tonumber(account.onlineHours) or 0))
            local label = GodSystemApp.services.runtime.getBankInvestmentLabel(profile.id) .. " | " .. tostring(account.balance or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            local status = account.redeemUnlocked == true and GodSystemApp.services.runtime.text("Bank_InvestmentRedeemable", "Redeemable") or GodSystemApp.services.runtime.text("Bank_InvestmentLocked", "Locked until first settlement")
            local detail = gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_InvestmentProgress", "Online progress {1}/{2}h"), { math.floor(progress), settlementHours }) .. " | " .. status
            if (account.settlementCount or 0) > 0 then
                detail = detail .. " | " .. gsFormatTemplate(GodSystemApp.services.runtime.text("Bank_InvestmentLastResult", "Last {1}"), { account.lastDelta or 0 })
            end
            self:addListItem(label, { kind = "bankInvestment", data = account, profile = profile, detail = detail })
        end
    end

    if #(bank.fixed or {}) <= 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Bank_NoLegacyFixed", "No legacy fixed deposits"), { kind = "empty", detail = "" })
        self:setStandardActionBar()
        return
    end
    for i = 1, #(bank.fixed or {}) do
        local entry = bank.fixed[i]
        local payout, interestOrPenalty, mature = GodSystemApp.services.runtime.getBankFixedPayout(entry)
        local state = mature and GodSystemApp.services.runtime.text("Bank_Mature", "Mature") or (GodSystemApp.services.runtime.text("Bank_NotMature", "Not mature") .. " " .. tostring(math.max(0, math.ceil((tonumber(entry.matureHour) or 0) - (GameTime and GameTime:getInstance() and GameTime:getInstance():getWorldAgeHours() or 0)))) .. GodSystemApp.services.runtime.text("Unit_Hour", "h"))
        local text = GodSystemApp.services.runtime.text("Bank_LegacyFixed", "Legacy fixed") .. " " .. tostring(entry.id or i) .. " | " .. tostring(entry.principal or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        local detail = state .. " | " .. GodSystemApp.services.runtime.text("Bank_Payout", "payout") .. " " .. tostring(payout)
        if interestOrPenalty < 0 then
            detail = detail .. " | " .. GodSystemApp.services.runtime.text("Bank_Penalty", "penalty") .. " " .. tostring(math.abs(interestOrPenalty))
        elseif interestOrPenalty > 0 then
            detail = detail .. " | " .. GodSystemApp.services.runtime.text("Bank_Interest", "interest") .. " " .. tostring(interestOrPenalty)
        end
        self:addListItem(text, { kind = "bankFixed", data = entry, detail = detail })
    end
    self:setStandardActionBar()
end

function GodSystemWindow:updateBankActionButtons(payload)
    if self.mode ~= "bank" then
        return
    end
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankDeposit", "Deposit"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_BankWithdraw", "Withdraw"))
    self.thirdButton:setVisible(false)
    local bank = GodSystemApp.services.runtime.getBank()
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text(bank.autoDepositEnabled and "Btn_BankAutoDepositOn" or "Btn_BankAutoDepositOff", bank.autoDepositEnabled and "Auto deposit: ON" or "Auto deposit: OFF"))
    gsSetButtonTitle(self.fifthButton, GodSystemApp.services.runtime.text("Btn_BankConsolidateCurrency", "Sort coins"))
    self.secondaryButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(true)
    if payload and payload.kind == "bankLoanPlan" then
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankBorrowLoan", "Borrow"))
        self.secondaryButton:setVisible(false)
        self.thirdButton:setVisible(false)
    elseif payload and payload.kind == "bankLoanActive" then
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankRepayLoan", "Repay due"))
        gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_BankPayoffLoan", "Pay off"))
        self.secondaryButton:setVisible(true)
        self.thirdButton:setVisible(false)
    elseif payload and payload.kind == "bankInvestment" then
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankInvestCurrent", "Invest current"))
        gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_BankInvestCash", "Invest cash"))
        gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_BankInvestmentRedeem", "Redeem"))
        self.secondaryButton:setVisible(true)
        self.thirdButton:setVisible(true)
    elseif payload and payload.kind == "bankFixed" then
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_BankWithdrawFixed", "Withdraw fixed"))
        self.secondaryButton:setVisible(false)
        self.thirdButton:setVisible(false)
    end
    self:setStandardActionBar()
end

function GodSystemWindow:populateTraits()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_TraitModify", "Modify"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(false)

    local positive, negative, blockedCount = GodSystemApp.services.runtime.getTraitModificationLists()
    local positiveRule = GodSystemApp.services.runtime.text("Trait_PricePerPointPrefix", "Each point ") .. tostring(GodSystemConfig.PositiveTraitCostPerPoint or 800) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    local negativeRule = GodSystemApp.services.runtime.text("Trait_PricePerPointPrefix", "Each point ") .. tostring(GodSystemConfig.NegativeTraitRemoveCostPerPoint or 500) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    self:addListItem(GodSystemApp.services.runtime.text("Trait_PositiveHeader", "Positive traits") .. " | " .. positiveRule, { kind = "traitHeader", detail = "" })
    if #positive == 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Trait_PositiveEmpty", "No positive trait available"), { kind = "empty", detail = "" })
    else
        for i = 1, #positive do
            local entry = positive[i]
            local risk = entry.risk and (GodSystemApp.services.runtime.text("Trait_RiskTag", "[Risk] ") or "[Risk] ") or ""
            local owned = entry.owned and (" " .. GodSystemApp.services.runtime.text("Trait_StatusOwnedTag", "[Owned]")) or ""
            local text = risk .. tostring(entry.label or entry.traitType) .. owned
            local detail = "+" .. tostring(entry.costPoints or 0) .. " | " .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            if entry.disabledReason then
                detail = GodSystemApp.services.runtime.text("Trait_DisabledShort", "Disabled") .. " | " .. detail
            end
            self:addListItem(text, { kind = "trait", data = entry, detail = detail })
        end
    end

    self:addListItem(GodSystemApp.services.runtime.text("Trait_NegativeHeader", "Remove negative traits") .. " | " .. negativeRule, { kind = "traitHeader", detail = "" })
    if #negative == 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Trait_NegativeEmpty", "No negative trait owned"), { kind = "empty", detail = "" })
    else
        for i = 1, #negative do
            local entry = negative[i]
            local risk = entry.risk and (GodSystemApp.services.runtime.text("Trait_RiskTag", "[Risk] ") or "[Risk] ") or ""
            local text = risk .. tostring(entry.label or entry.traitType)
            local detail = tostring(entry.costPoints or 0) .. " | " .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            self:addListItem(text, { kind = "trait", data = entry, detail = detail })
        end
    end

    if blockedCount and blockedCount > 0 then
        self:setDetailText(GodSystemApp.services.runtime.text("Trait_BlockedSummary", "Hidden free/profession/body traits: ") .. tostring(blockedCount))
    end
end

function GodSystemWindow:applyAttributeActionBar(payload)
    local selected = payload and payload.kind == "attribute" and payload.data or nil
    local enabled = selected ~= nil and selected.maxed ~= true
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Attribute_BuyXP", "Buy XP"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Attribute_NextLevel", "Next level"))
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)
    self.primaryButton.enable = enabled
    self.secondaryButton.enable = enabled
    self:setActionBar({
        { id = "searchBox", width = 230, minWidth = 140 },
        { id = "primary", width = 140 },
        { id = "secondary", width = 160 },
    })
end

function GodSystemWindow:populateAttributes()
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableAttributes") == false then
        self.mode = "traits"
        self:populateTraits()
        return
    end
    self.shopSearchPurpose = "attribute"
    self:syncSearchBoxText("attribute")
    local rows = GodSystemApp.services.runtime.getAttributePerks(self.attributeSearchText or "")
    local groupKeys = {
        body = "Attribute_GroupBody",
        combat = "Attribute_GroupCombat",
        survival = "Attribute_GroupSurvival",
        crafting = "Attribute_GroupCrafting",
        mod = "Attribute_GroupMod",
    }
    local lastGroup = nil
    for i = 1, #rows do
        local row = rows[i]
        if row.group ~= lastGroup then
            lastGroup = row.group
            self:addListItem(GodSystemApp.services.runtime.text(groupKeys[row.group] or "Attribute_GroupMod", tostring(row.parentLabel or row.group)), { kind = "attributeHeader", detail = "" })
        end
        local status = row.maxed and GodSystemApp.services.runtime.text("Attribute_Maxed", "Maxed") or ("Lv." .. tostring(row.currentLevel or 0) .. "/" .. tostring(row.maxLevel or 10))
        local detail = status .. " | XP " .. tostring(math.floor(row.currentXp or 0)) .. "/" .. tostring(math.floor(row.maxXp or 0))
        self:addListItem(tostring(row.label), { kind = "attribute", data = row, detail = detail })
    end
    if #rows == 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Attribute_Empty", "No matching standard skills"), { kind = "empty", detail = "" })
    end
    self:applyAttributeActionBar(self:getSelectedPayload())
end

function GodSystemWindow:populateTaskMain()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_TaskAccept", "Accept"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshOpenTasksShort", "Refresh tasks -") .. tostring(GodSystemConfig.RefreshTaskCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
    self.thirdButton:setVisible(true)
    if GodSystemUI.isTaskTrackerVisible and GodSystemUI.isTaskTrackerVisible() then
        gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_TaskTrackerHide", "Hide tracker"))
    else
        gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_TaskTrackerShow", "Show tracker"))
    end
    local data = GodSystemApp.services.runtime.getData()
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text(data.autoTaskClaimEnabled and "Btn_TaskAutoClaimOn" or "Btn_TaskAutoClaimOff", data.autoTaskClaimEnabled and "Auto claim: ON" or "Auto claim: OFF"))
    self.fourthButton:setVisible(true)
    if not (GodSystemNetwork and GodSystemNetwork.isMultiplayer) then
        GodSystemApp.services.runtime.generateDailyTasks(false)
    end
    local tasks = data.tasks or {}
    local openTasks = TaskOrder.sortedCopy(tasks, "open", GodSystemApp.services.runtime.getTaskTitle)
    local activeTasks = TaskOrder.sortedCopy(tasks, "active", GodSystemApp.services.runtime.getTaskTitle)
    local openCount = 0
    local activeCount = 0
    for i = 1, #openTasks do
        local task = openTasks[i]
        local progress = GodSystemApp.services.runtime.getTaskDisplayProgress(task)
        local text = GodSystemApp.services.runtime.getTaskListTitle(task)
        local remain = ""
        local detail = string.format("%d/%d%s", math.min(progress, task.target or 1), task.target or 1, remain)
        openCount = openCount + 1
        self:addListItem(text, { kind = "task", data = task, detail = detail })
    end
    for i = 1, #activeTasks do
        local task = activeTasks[i]
        local progress = GodSystemApp.services.runtime.getTaskDisplayProgress(task)
        local text = GodSystemApp.services.runtime.getTaskListTitle(task)
        local remain = " " .. GodSystemApp.services.runtime.text("Short_Remain", "Left") .. tostring(GodSystemApp.services.runtime.getRemainingHours(task)) .. "h"
        local detail = string.format("%d/%d%s", math.min(progress, task.target or 1), task.target or 1, remain)
        activeCount = activeCount + 1
        self:addActiveListItem(text, { kind = "task", data = task, detail = detail })
    end
    if openCount == 0 then
        self:addListItem(GodSystemApp.services.runtime.text("Task_OpenEmpty", "No available task"), { kind = "empty", detail = "" })
    end
    if activeCount == 0 then
        self:addActiveListItem(GodSystemApp.services.runtime.text("Task_ActiveEmpty", "No active task"), { kind = "empty", detail = "" })
    end
    local labelWidth = math.max(120, (self.list and self.list.width or 180) - 6)
    gsSetLabel(self.openTaskLabel, gsTruncateText(GodSystemApp.services.runtime.text("Task_OpenColumn", "Available") .. " | " .. GodSystemApp.services.runtime.text("Task_NextRefresh", "Next refresh ") .. GodSystemApp.services.runtime.getDailyTaskRefreshText(), UIFont.Small, labelWidth))
    gsSetLabel(self.activeTaskLabel, gsTruncateText(GodSystemApp.services.runtime.text("Task_ActiveColumn", "Active") .. " " .. tostring(activeCount) .. "/" .. tostring(GodSystemApp.services.runtime.getMaxActiveTasks()), UIFont.Small, labelWidth))
    self:setStandardActionBar()
end

function GodSystemWindow:populateTaskExtensions()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_UpgradeSystem", "Upgrade"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)
    local upgrades = { "activeTasks", "dailyTasks" }
    for i = 1, #upgrades do
        local info = GodSystemApp.services.runtime.getSystemUpgradeInfo(upgrades[i])
        if info then
            local costText = info.cost and (tostring(info.cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
                or GodSystemApp.services.runtime.text("Upgrade_Maxed", "Maxed")
            self:addListItem(info.label, {
                kind = "upgrade",
                data = info,
                detail = tostring(info.current) .. "/" .. tostring(info.maxValue) .. " | " .. costText,
            })
        end
    end
    self:setStandardActionBar()
end

function GodSystemWindow:populateTasks()
    if self:getActivePageSection("tasks") == "taskExtensions" then
        self:populateTaskExtensions()
    else
        self:populateTaskMain()
    end
end

function GodSystemWindow:populateUpgrades()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_UpgradeSystem", "Upgrade"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    self.secondaryButton:setVisible(not gsIsMultiplayer())
    self.thirdButton:setVisible(false)

    local upgrades = { "carryCapacity" }
    for i = 1, #upgrades do
        local info = GodSystemApp.services.runtime.getSystemUpgradeInfo(upgrades[i])
        if info then
            local costText = info.cost and (tostring(info.cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
                or (info.upgradeType == "carryCapacity" and GodSystemApp.services.runtime.text("Upgrade_CostOverflow", "Unavailable") or GodSystemApp.services.runtime.text("Upgrade_Maxed", "Maxed"))
            local detail = nil
            if info.upgradeType == "carryCapacity" then
                local status = info.carryStatus or {}
                local bonus = tonumber(status.bonus) or 0
                local bonusText = bonus >= 0 and ("+" .. tostring(bonus)) or tostring(bonus)
                detail = GodSystemApp.services.runtime.text("Upgrade_CarryProtocolBonus", "Protocol base bonus") .. "(" .. bonusText .. ")"
                    .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryExternalBase", "External base") .. "(" .. tostring(status.externalBase or "?") .. ")"
                    .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryWrittenBase", "Written base") .. "(" .. tostring(status.currentBase or "?") .. ")"
                    .. " | " .. GodSystemApp.services.runtime.text("Upgrade_CarryGameFinal", "Game final carry") .. "(" .. tostring(status.finalCarry or "?") .. ")"
                    .. " | Lv." .. tostring(info.current) .. " | " .. costText
            else
                detail = tostring(info.current) .. "/" .. tostring(info.maxValue) .. " | " .. costText
            end
            self:addListItem(info.label, { kind = "upgrade", data = info, detail = detail })
        end
    end
    local services = GodSystemApp.services.runtime.getMedicalServiceList and GodSystemApp.services.runtime.getMedicalServiceList() or {}
    for i = 1, #services do
        local info = services[i]
        local detail = tostring(info.cost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        self:addListItem(info.label, { kind = "medicalService", data = info, detail = detail })
    end
end

function GodSystemWindow:applyCompanionActionBar(payload)
    local data = GodSystemApp.services.runtime.getCompanionData()
    local unlocked = data and data.unlocked == true
    local canPurchase = payload and payload.kind == "companionNode" and payload.unlocked == true and payload.maxed ~= true
    local unlockDefinition = payload and GodSystemCompanionConfig.Unlocks[payload.id] or nil
    if unlockDefinition then
        local data = GodSystemApp.services.runtime.getCompanionData()
        local requiresMet = not unlockDefinition.requires or GodSystemCompanionConfig.isUnlocked(data, unlockDefinition.requires)
        canPurchase = payload.unlocked ~= true and requiresMet
    end
    if payload and payload.id == "resonance" then canPurchase = payload.unlocked == true end

    local primaryTitle = GodSystemApp.services.runtime.text("Companion_Upgrade", "Unlock / upgrade")
    if payload and payload.cost and canPurchase then
        primaryTitle = primaryTitle .. " -" .. tostring(payload.cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    elseif payload and payload.maxed then
        primaryTitle = GodSystemApp.services.runtime.text("Upgrade_Maxed", "Maxed")
    end
    gsSetButtonTitle(self.primaryButton, primaryTitle)
    gsSetButtonTitle(self.secondaryButton, data and data.visible and GodSystemApp.services.runtime.text("Companion_ActionHide", "Hide") or GodSystemApp.services.runtime.text("Companion_ActionShow", "Show"))
    gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Companion_ShortcutToggle", "Shortcut bar"))
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text("Companion_ActionRecall", "Recall"))
    self.primaryButton.enable = canPurchase == true
    self.secondaryButton.enable = unlocked
    self.thirdButton.enable = unlocked
    self.fourthButton.enable = unlocked
    self.primaryButton:setVisible(true)
    self.secondaryButton:setVisible(true)
    self.thirdButton:setVisible(true)
    self.fourthButton:setVisible(true)
    self.fifthButton:setVisible(false)
    self:setStandardActionBar()
end

function GodSystemWindow:populateCompanion()
    if gsIsMultiplayer() or not GodSystemCompanionConfig.isEnabled() then
        self.mode = "upgrades"
        self:populateUpgrades()
        return
    end
    if not GodSystemCompanion then
        self:addListItem(GodSystemApp.services.runtime.text("Companion_DiagnosticUnavailable", "Companion module is unavailable; check the MOD load order and client log."), {
            kind = "companionDiagnostic",
            selectable = false,
            detail = GodSystemApp.services.runtime.text("Companion_DiagnosticUnavailableDetail", "The SP companion entry is enabled, but its runtime module did not load."),
        })
        self:applyCompanionActionBar(nil)
        return
    end
    local state = GodSystemCompanion.getStateDetail and GodSystemCompanion.getStateDetail() or ""
    self:addListItem(GodSystemApp.services.runtime.text("Companion_Title", "Blue pixel floating robot"), { kind = "companionState", detail = state })
    local rows = GodSystemCompanion.getRows and GodSystemCompanion.getRows() or {}
    for i = 1, #rows do
        local row = rows[i]
        self:addListItem(row.label, row)
    end
    self:applyCompanionActionBar(self:getSelectedPayload())
end

function GodSystemWindow:applyUpgradeActionBar(payload)
    self.primaryButton:setVisible(true)
    local carrySelected = payload and payload.kind == "upgrade" and payload.data and payload.data.upgradeType == "carryCapacity"
    self.secondaryButton:setVisible(carrySelected or not gsIsMultiplayer())
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(false)
    self.fifthButton:setVisible(false)
    if payload and payload.kind == "medicalService" and payload.data then
        local info = payload.data
        local title = tostring(info.button or GodSystemApp.services.runtime.text("Btn_Confirm", "Confirm")) .. " -" .. tostring(info.cost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
        gsSetButtonTitle(self.primaryButton, title)
        self.secondaryButton:setVisible(false)
    else
        gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_UpgradeSystem", "Upgrade"))
        gsSetButtonTitle(self.secondaryButton, carrySelected and GodSystemApp.services.runtime.text("Btn_RefreshCarryCapacity", "Restore carry") or GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    end
    self:setStandardActionBar()
end

function GodSystemWindow:getHomeActionTitles(payload)
    local primary = nil
    local secondary = nil
    local third = nil
    local fourth = gsIsMultiplayer() and nil or GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh")
    local fifth = nil
    local home = GodSystemApp.services.runtime.getHomeSystem()
    local travelCost = GodSystemConfig.HomeTravelCost or 10
    if home and home.returnPoint then
        third = GodSystemApp.services.runtime.text("Btn_HomeReturn", "Return") .. " -" .. tostring(travelCost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    end
    if payload and payload.kind == "homePoint" and payload.data then
        local entry = payload.data
        if entry.kind == "home" then
            primary = GodSystemApp.services.runtime.text("Btn_HomeSet", "Set home") .. " -" .. tostring(GodSystemConfig.HomeSetCost or 100) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            if entry.point then
                secondary = GodSystemApp.services.runtime.text("Btn_HomeTeleport", "Go home") .. " -" .. tostring(travelCost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            end
        elseif entry.kind == "temp" then
            if not entry.owned then
                primary = GodSystemApp.services.runtime.text("Btn_HomeBuyTemp", "Buy slot") .. " -" .. tostring(GodSystemConfig.TempTeleportSlotCost or 500) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            else
                primary = GodSystemApp.services.runtime.text("Btn_HomeSetTemp", "Set point") .. " -" .. tostring(GodSystemConfig.TempTeleportSetCost or 100) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
                if entry.point then
                    secondary = GodSystemApp.services.runtime.text("Btn_HomeTeleportTemp", "Teleport") .. " -" .. tostring(travelCost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
                end
            end
        elseif entry.kind == "return" then
            primary = GodSystemApp.services.runtime.text("Btn_HomeReturn", "Return") .. " -" .. tostring(travelCost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            secondary = GodSystemApp.services.runtime.text("Btn_HomeClearReturn", "Clear departure")
            third = nil
        elseif entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
            third = nil
            if not info.homeSet then
                primary = nil
            elseif not info.unlocked then
                primary = GodSystemApp.services.runtime.text("Btn_HomeSafeUnlock", "Unlock safe zone") .. " -" .. tostring(info.unlockCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
            else
                primary = info.enabled and GodSystemApp.services.runtime.text("Btn_HomeSafeDisable", "Pause safe zone") or GodSystemApp.services.runtime.text("Btn_HomeSafeEnable", "Enable safe zone")
                secondary = GodSystemApp.services.runtime.text("Btn_HomeSafeClear", "Clear now") .. " -" .. tostring(info.clearCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
                if info.nextLevel then
                    third = GodSystemApp.services.runtime.text("Btn_HomeSafeUpgrade", "Upgrade range") .. " -" .. tostring(info.nextLevel.upgradeCost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
                end
            end
        end
    end
    return primary, secondary, third, fourth, fifth
end

function GodSystemWindow:applyHomeActionBar(payload)
    local primary, secondary, third, fourth, fifth = self:getHomeActionTitles(payload)
    if primary then gsSetButtonTitle(self.primaryButton, primary) end
    if secondary then gsSetButtonTitle(self.secondaryButton, secondary) end
    if third then gsSetButtonTitle(self.thirdButton, third) end
    if fourth then gsSetButtonTitle(self.fourthButton, fourth) end
    if fifth then gsSetButtonTitle(self.fifthButton, fifth) end
    self:setActionBar({
        { id = "primary", width = 156, minWidth = 92, visible = primary ~= nil },
        { id = "secondary", width = 156, minWidth = 92, visible = secondary ~= nil },
        { id = "third", width = 156, minWidth = 92, visible = third ~= nil },
        { id = "fourth", width = 126, minWidth = 82, visible = fourth ~= nil },
        { id = "fifth", width = 110, minWidth = 76, visible = fifth ~= nil },
    })
end

function GodSystemWindow:populateHome()
    self.primaryButton:setVisible(false)
    self.secondaryButton:setVisible(false)
    self.thirdButton:setVisible(false)
    self.fourthButton:setVisible(not gsIsMultiplayer())
    gsSetButtonTitle(self.fourthButton, GodSystemApp.services.runtime.text("Btn_RefreshDisplay", "Refresh"))
    local entries = GodSystemApp.services.runtime.getHomeEntries()
    for i = 1, #entries do
        local entry = entries[i]
        local label = entry.label or GodSystemApp.services.runtime.text("Tab_Home", "Home/Teleport")
        if entry.kind == "safeZone" then
            local info = entry.safeZone or GodSystemApp.services.runtime.getHomeSafeZoneInfo()
            if not info.homeSet then
                label = label .. " [" .. GodSystemApp.services.runtime.text("HomeSafe_NeedHomeShort", "Set home first") .. "]"
            elseif not info.unlocked then
                label = label .. " [" .. GodSystemApp.services.runtime.text("HomeSafe_Locked", "Locked") .. "]"
            else
                local state = info.enabled and GodSystemApp.services.runtime.text("HomeSafe_Enabled", "Enabled") or GodSystemApp.services.runtime.text("HomeSafe_Disabled", "Paused")
                label = label .. " [Lv." .. tostring(info.level) .. " R" .. tostring(info.radius) .. " " .. state .. "]"
            end
        elseif entry.kind == "temp" and not entry.owned then
            label = label .. " [" .. GodSystemApp.services.runtime.text("Home_TempLocked", "Locked") .. "]"
        elseif entry.point then
            label = label .. " [" .. GodSystemApp.services.runtime.text("Home_Set", "Set") .. "]"
        end
        self:addListItem(label, { kind = "homePoint", data = entry, detail = GodSystemApp.services.runtime.getHomeEntryDetail(entry) })
    end
    self:applyHomeActionBar(self:getSelectedPayload())
end

function GodSystemWindow:populateHistory()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(false)
    local history = GodSystemApp.services.runtime.getData().history or {}
    if #history == 0 then
        self:addWrappedListText(GodSystemApp.services.runtime.text("History_Empty", "No history"), { kind = "history", detail = "" })
        return
    end
    for i = 1, #history do
        self:addWrappedListText(self:formatHistoryEntry(history[i]), { kind = "history", data = history[i], detail = history[i].kind or "" })
    end
end

function GodSystemWindow:populateSettings()
    self:addWrappedListText(
        GodSystemApp.services.runtime.text("Settings_PanelKeyCurrent", "Panel key: ") .. GodSystemPanelKey.getKeyName(GodSystemPanelKey.getKey()),
        { kind = "keyBinding", target = "panel", detail = GodSystemApp.services.runtime.text("Settings_PanelKeyHint", "Open or close the panel.") }
    )
    self:addWrappedListText(
        GodSystemApp.services.runtime.text("Settings_RangeKeyCurrent", "Range recycle key: ") .. GodSystemPanelKey.getKeyName(GodSystemPanelKey.getRangeKey()),
        { kind = "keyBinding", target = "range", detail = GodSystemApp.services.runtime.text("Settings_RangeKeyHint", "Start or cancel range recycle.") }
    )
    local headUpShown = GodSystemApp.services.runtime.getHeadUpNotificationsEnabled()
    self:addWrappedListText(
        GodSystemApp.services.runtime.text("Settings_HeadUpNotifications", "Head-up notifications") .. ": "
            .. GodSystemApp.services.runtime.text(headUpShown and "Settings_HeadUpNotificationsShown" or "Settings_HeadUpNotificationsHidden", headUpShown and "Shown" or "Hidden"),
        { kind = "settingToggle", target = "headUpNotifications", detail = GodSystemApp.services.runtime.text("Settings_HeadUpNotificationsHint", "Show God System head-up messages above this character. Logs, dialogs, server results and other mods are unaffected.") }
    )
    self:addWrappedListText(
        GodSystemApp.services.runtime.text("Settings_PanelKeyHint", "Use Change key, then press a key. Esc cancels. Conflicting bindings are not overwritten."),
        { kind = "info", detail = "" }
    )
    self:addWrappedListText(
        GodSystemApp.services.runtime.text("Settings_ModOptionsHint", "The same binding is also available in the game's Mod Options."),
        { kind = "info", detail = "" }
    )
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Settings_ChangeKey", "Change key"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Settings_ResetKey", "Reset to N"))
    gsSetButtonTitle(self.thirdButton, GodSystemApp.services.runtime.text("Btn_Close", "Close"))
    self:setActionBar({
        { id = "primary", width = 150 },
        { id = "secondary", width = 150 },
        { id = "third", width = 120 },
    })
end

function GodSystemWindow:onPanelKeyCaptured(ok, key, reason, target)
    if ok then
        local prefix = target == "range" and GodSystemApp.services.runtime.text("Settings_RangeKeySaved", "Range recycle key changed to: ")
            or GodSystemApp.services.runtime.text("Settings_KeySaved", "Panel key changed to: ")
        GodSystemApp.services.runtime.notify(prefix .. GodSystemPanelKey.getKeyName(key))
    elseif reason == "cancelled" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Settings_KeyCaptureCancelled", "Key capture cancelled"))
    elseif reason == "conflict" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Settings_KeyConflict", "That key is already used by the other God System binding."))
    else
        return
    end
    if self.mode == "settings" and self.getIsVisible and self:getIsVisible() then
        self:populateList()
    end
end

function GodSystemWindow:beginPanelKeyCapture(target)
    target = target == "range" and "range" or "panel"
    GodSystemPanelKey.beginCapture(target, function(ok, key, reason)
        self:onPanelKeyCaptured(ok, key, reason, target)
    end)
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Settings_PressKey", "Press a key (Esc to cancel)"))
end

function GodSystemWindow:populateInfo()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(GodSystemConfig.EnableDebugTools == true)
    if GodSystemConfig.EnableDebugTools then
        gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_DebugCurrency", "Debug +500"))
    end
    local text = GodSystemApp.services.runtime.text("Info_Kill", "Zombie kill reward: +") .. tostring(GodSystemConfig.KillPointReward or 0)
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Shop", "Shop uses currency items in your inventory.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Unlock", "Recycle allowed vanilla items to unlock single-item shop entries.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Recycle", "Manual recycle accepts every valid item; non-empty containers require confirmation.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Traits", "Traits can be modified with currency. Risk traits are experimental.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Tasks", "Daily tasks: ") .. tostring(GodSystemApp.services.runtime.getDailyTaskCount()) .. " / " .. GodSystemApp.services.runtime.text("Info_MaxActive", "max active: ") .. tostring(GodSystemApp.services.runtime.getMaxActiveTasks())
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_Failure", "Expired unfinished tasks deduct currency.")
    self:addWrappedListText(text, { kind = "info", data = text })
    text = GodSystemApp.services.runtime.text("Info_HomeSafe", "Home safe zone clears loaded zombies without kill rewards or task progress.")
    self:addWrappedListText(text, { kind = "info", data = text })
end

function gsBoolText(value)
    return value == true and "true" or "false"
end

function GodSystemWindow:populateDiagnostics()
    gsSetButtonTitle(self.primaryButton, GodSystemApp.services.runtime.text("Btn_Close", "Close"))
    self.secondaryButton:setVisible(gsIsMultiplayer())
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("Btn_DiagnosticsRefresh", "Refresh diagnostics"))

    local data = GodSystemApp.services.runtime.getData() or {}
    local server = data.serverDiagnostics or {}
    local client = {}
    if GodSystemNetwork and GodSystemNetwork.getDiagnostics then
        client = GodSystemNetwork.getDiagnostics() or {}
    end

    local lines = {
        GodSystemApp.services.runtime.text("Diag_Header", "Diagnostics"),
        "mode=" .. (gsIsMultiplayer() and "MP" or "SP") .. " version=" .. tostring(GodSystemConfig.Version or "?"),
        "balance=" .. tostring(GodSystemApp.services.runtime.getCurrencyTotal and GodSystemApp.services.runtime.getCurrencyTotal() or 0),
        "client.hasServerState=" .. gsBoolText(client.hasServerState),
        "client.pendingState=" .. gsBoolText(client.pendingState),
        "client.pendingCommand=" .. tostring(client.pendingCommand or "-"),
        "client.pendingElapsed=" .. tostring(math.floor((tonumber(client.pendingElapsedMs) or 0) / 1000)) .. "s/" .. tostring(math.floor((tonumber(client.pendingTimeoutMs) or 0) / 1000)) .. "s",
        "client.pendingTimeouts=" .. tostring(client.pendingTimeouts or 0) .. " last=" .. tostring(client.lastPendingTimeoutCommand or "-"),
        "client.pendingClearReason=" .. tostring(client.lastPendingClearReason or "-"),
        "client.stateSerial=" .. tostring(client.stateSerial or 0),
        "client.sentCommands=" .. tostring(client.sentCommands or 0) .. " failed=" .. tostring(client.failedCommands or 0),
        "client.receivedStates=" .. tostring(client.receivedStates or 0),
        "client.lastSentCommand=" .. tostring(client.lastSentCommand or "-"),
        "client.lastResultOk=" .. tostring(client.lastResultOk),
        "client.lastResultMessage=" .. tostring(client.lastResultMessage or "-"),
        "client.lastError=" .. tostring(client.lastError or "-"),
        "client.lastNotifyCode=" .. tostring(client.lastNotifyCode or "-"),
        "server.handledCommands=" .. tostring(server.handledCommands or 0) .. " failed=" .. tostring(server.failedCommands or 0),
        "server.lastCommand=" .. tostring(server.lastCommand or "-"),
        "server.lastResultOk=" .. tostring(server.lastResultOk),
        "server.lastResultMessage=" .. tostring(server.lastResultMessage or "-"),
        "server.lastError=" .. tostring(server.lastError or "-"),
        "server.lastTraitBenefitsOk=" .. tostring(server.lastTraitBenefitsOk),
        "server.lastTraitBenefitsApplied=" .. tostring(server.lastTraitBenefitsApplied or 0),
        "server.lastTraitBenefitsType=" .. tostring(server.lastTraitBenefitsType or "-"),
    }

    for i = 1, #lines do
        self:addWrappedListText(lines[i], { kind = "diagnostics", data = lines[i] })
    end
end

function GodSystemWindow:populateRangeRecycle()
    local service = GodSystemApp.services.rangeRecycle
    local player = getPlayer and getPlayer() or nil
    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    if not self.rangeRecycleUnsubscribe then
        self.rangeRecycleUnsubscribe = service:subscribe(playerNum, function()
            if self.mode == "rangeRecycle" and self.getIsVisible and self:getIsVisible() then
                self:requestDeferredPopulate(1)
            end
        end)
    end
    local model = service:getViewModel(playerNum)
    local running = model.status == "running"
    gsSetButtonTitle(self.primaryButton, running
        and GodSystemApp.services.runtime.text("RangeRecycle_Cancel", "Cancel")
        or GodSystemApp.services.runtime.text("RangeRecycle_Start", "Start"))
    gsSetButtonTitle(self.secondaryButton, GodSystemApp.services.runtime.text("RangeFilter_Open", "Item filter"))
    self.secondaryButton.enable = true
    self.thirdButton:setVisible(false)

    local status = tostring(model.status or "idle")
    local stage = tostring(model.stage or "verifying")
    local summary = GodSystemApp.services.runtime.text("RangeRecycle_Status", "Status") .. ": "
        .. GodSystemApp.services.runtime.text("RangeStatus_" .. status, status)
        .. " | " .. GodSystemApp.services.runtime.text("RangeRecycle_Stage", "Stage") .. ": "
        .. GodSystemApp.services.runtime.text("RangeStage_" .. stage, stage)
        .. " | " .. GodSystemApp.services.runtime.text("RangeRecycle_Processed", "Processed") .. ": " .. tostring(model.processed or 0)
        .. " | " .. GodSystemApp.services.runtime.text("RangeRecycle_Payout", "Payout") .. ": " .. tostring(model.payout or 0)
        .. " | " .. GodSystemApp.services.runtime.text("RangeRecycle_Skipped", "Skipped") .. ": " .. tostring(model.skipped or 0)
    self:addWrappedListText(summary, { kind = "rangeStatus", selectable = false, detail = summary })

    if model.filterReady ~= true then
        local syncingText = GodSystemApp.services.runtime.text("RangeFilter_Syncing", "Item filter syncing")
        self:addWrappedListText(syncingText, { kind = "empty", selectable = false, detail = syncingText })
        return
    end
    local filter = model.filter or {}
    local allowedCount = #(filter.activeFullTypes or filter.allowedFullTypes or {})
    local filterText = GodSystemApp.services.runtime.text("RangeFilter_AllowedCount", "Allowed items")
        .. ": " .. tostring(allowedCount)
    self:addWrappedListText(filterText, { kind = "rangeFilterSummary", selectable = false, detail = filterText })
    local hintText = GodSystemApp.services.runtime.text("RangeFilter_OpenHint", "Open item filter to choose recyclable item types")
    self:addWrappedListText(hintText, { kind = "rangeFilterHint", selectable = false, detail = hintText })
end

end
