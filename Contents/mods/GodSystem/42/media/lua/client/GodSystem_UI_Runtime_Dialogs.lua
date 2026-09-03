_G.GodSystemUIRuntimeInstallers = _G.GodSystemUIRuntimeInstallers or {}
GodSystemUIRuntimeInstallers["GodSystem_UI_Runtime_Dialogs"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Dialogs then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_UI_Runtime_Dialogs = true
    setfenv(1, runtimeEnvironment)

function GodSystemWindow:confirmMedicalService(service)
    if not service or not service.action then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectOne", "Select an item first"))
        return
    end
    local message = gsFormatTemplate(GodSystemApp.services.runtime.text("Confirm_MedicalService", "Confirm medical service: {1}\nCost: {2}"), {
        tostring(service.label or service.action),
        tostring(service.cost or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"),
    })
    if service.desc and tostring(service.desc) ~= "" then
        local lines = gsWrapText(service.desc, UIFont.Small, 430)
        local desc = {}
        for i = 1, math.min(#lines, 5) do
            desc[#desc + 1] = lines[i]
        end
        message = message .. "\n\n" .. table.concat(desc, "\n")
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 140)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 280, message, true, self, self.onMedicalServiceConfirm, playerNum, { action = service.action })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        local sent = GodSystemApp.services.runtime.performMedicalService(service.action)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onMedicalServiceConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local sent = GodSystemApp.services.runtime.performMedicalService(payload and payload.action)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:confirmTraitModification(entry)
    if not entry then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectTrait", "Select a trait first"))
        return
    end
    if entry.disabledReason then
        GodSystemApp.services.runtime.notify(entry.disabledReason)
        return
    end

    local actionText = entry.action == "remove" and GodSystemApp.services.runtime.text("Trait_ActionRemove", "Remove negative trait") or GodSystemApp.services.runtime.text("Trait_ActionBuy", "Buy positive trait")
    local message = actionText .. "\n" ..
        tostring(entry.label or entry.traitType) .. "\n" ..
        GodSystemApp.services.runtime.text("Trait_PointCost", "Trait points ") .. tostring(entry.costPoints or 0) .. "\n" ..
        GodSystemApp.services.runtime.text("Trait_ConfirmCost", "Cost: ") .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    if entry.description and tostring(entry.description) ~= "" then
        local descLines = gsWrapText(entry.description, UIFont.Small, 430)
        local desc = {}
        for i = 1, math.min(#descLines, 5) do
            table.insert(desc, descLines[i])
        end
        message = message .. "\n\n" .. table.concat(desc, "\n")
    end
    if entry.action == "buy" then
        message = message .. "\n\n" .. GodSystemApp.services.runtime.text("Trait_EffectWarning", "Trait effect warning: skill bonuses and recipes are attempted immediately; carry capacity, body changes and starting items may require reloading, and items are not guaranteed.")
    end
    if entry.risk then
        message = message .. "\n" .. GodSystemApp.services.runtime.text("Trait_RiskConfirm", "Risk: experimental trait, test carefully.")
    end
    if entry.conflictLabels and #entry.conflictLabels > 0 then
        message = message .. "\n" .. GodSystemApp.services.runtime.text("Trait_Conflicts", "Conflicts: ") .. table.concat(entry.conflictLabels, ", ")
    end

    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 150)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 300, message, true, self, self.onTraitConfirm, playerNum, { action = entry.action, traitType = entry.traitType })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitConfirmMissing", "Confirmation dialog unavailable"))
    end
end

function GodSystemWindow:onTraitConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    if payload then
        local sent = GodSystemApp.services.runtime.performTraitModification(payload.action, payload.traitType)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:confirmAbandonTask(task)
    if not task or task.status ~= "active" then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_SelectTask", "Select a task first"))
        return
    end
    local message = GodSystemApp.services.runtime.text("Confirm_AbandonTask", "Abandon this task? This counts as failure.") .. "\n" ..
        GodSystemApp.services.runtime.getTaskListTitle(task) .. "\n" ..
        GodSystemApp.services.runtime.text("Task_Progress", "Progress") .. ": " .. GodSystemApp.services.runtime.getTaskListStatusLine(task) .. "\n" ..
        GodSystemApp.services.runtime.text("Task_Penalty", "Penalty") .. ": " .. tostring(task.penaltyPoints or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 125)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 250, message, true, self, self.onAbandonTaskConfirm, playerNum, { taskId = task.taskId })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        local sent = GodSystemApp.services.runtime.abandonTask(task)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onAbandonTaskConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local task = nil
    local tasks = GodSystemApp.services.runtime.getData().tasks or {}
    local taskId = payload and payload.taskId
    for i = 1, #tasks do
        if tostring(tasks[i].taskId or "") == tostring(taskId or "") then
            task = tasks[i]
            break
        end
    end
    local sent = GodSystemApp.services.runtime.abandonTask(task)
    self:finishMultiplayerCommand(sent)
end

function GodSystemWindow:showTaskTurnInDialog(task)
    if not task or not GodSystemApp.services.runtime.isTurnInTask or not GodSystemApp.services.runtime.isTurnInTask(task) then
        return
    end
    if GodSystemUI.taskTurnInDialog and GodSystemUI.taskTurnInDialog.getIsVisible and GodSystemUI.taskTurnInDialog:getIsVisible() then
        GodSystemUI.taskTurnInDialog:close()
    end
    local candidates = GodSystemApp.services.runtime.getTurnInCandidates(task)
    local width, height = 560, 430
    local x = math.max(40, (getCore():getScreenWidth() - width) / 2)
    local y = math.max(40, (getCore():getScreenHeight() - height) / 2)
    local dialog = GodSystemTaskTurnInDialog:new(x, y, width, height, self, task, candidates)
    dialog:initialise()
    GodSystemUI.presentOverlay(dialog)
    GodSystemUI.taskTurnInDialog = dialog
end

function GodSystemWindow:onInfoDialogClose(button, payload)
end

function GodSystemWindow:showInfoDialog(message)
    message = tostring(message or "")
    if message == "" then
        return
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 120)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 240, message, false, self, self.onInfoDialogClose, playerNum, nil)
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        GodSystemApp.services.runtime.notify(message)
    end
end

function GodSystemWindow:getHomeConfirmMessage(action, index)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local cost = 0
    local line = ""
    if action == "setHome" then
        cost = GodSystemConfig.HomeSetCost or 100
        line = GodSystemApp.services.runtime.text("Confirm_HomeSet", "Set current position as home?")
    elseif action == "buyTemp" then
        cost = GodSystemConfig.TempTeleportSlotCost or 500
        line = GodSystemApp.services.runtime.text("Confirm_HomeBuyTemp", "Buy temp teleport point ") .. tostring(index) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    elseif action == "setTemp" then
        cost = GodSystemConfig.TempTeleportSetCost or 100
        line = GodSystemApp.services.runtime.text("Confirm_HomeSetTemp", "Set or overwrite temp teleport point ") .. tostring(index) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    elseif action == "teleportHome" then
        cost = GodSystemConfig.HomeTravelCost or 10
        line = GodSystemApp.services.runtime.text("Confirm_HomeTeleport", "You are teleporting home. Confirm?")
    elseif action == "teleportTemp" then
        cost = GodSystemConfig.HomeTravelCost or 10
        line = GodSystemApp.services.runtime.text("Confirm_HomeTeleportTemp", "You are teleporting to temp point ") .. tostring(index) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    elseif action == "return" then
        cost = GodSystemConfig.HomeTravelCost or 10
        local home = GodSystemApp.services.runtime.getHomeSystem()
        local source = self:formatHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystemApp.services.runtime.text("Confirm_HomeReturn", "You are returning to the departure point: ") .. tostring(source) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    elseif action == "clearReturn" then
        cost = 0
        local home = GodSystemApp.services.runtime.getHomeSystem()
        local source = self:formatHomeSource(home and home.returnPoint and home.returnPoint.source)
        line = GodSystemApp.services.runtime.text("Confirm_HomeClearReturn", "You are clearing the current departure point: ") .. tostring(source) .. GodSystemApp.services.runtime.text("Confirm_Question", ". Confirm?")
    elseif action == "unlockSafeZone" then
        local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
        cost = info.unlockCost or 0
        line = GodSystemApp.services.runtime.text("Confirm_HomeSafeUnlock", "Unlock home safe zone?")
    elseif action == "upgradeSafeZone" then
        local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
        cost = info.nextLevel and (info.nextLevel.upgradeCost or 0) or 0
        line = GodSystemApp.services.runtime.text("Confirm_HomeSafeUpgrade", "Upgrade home safe zone range?")
    elseif action == "clearSafeZone" then
        local info = GodSystemApp.services.runtime.getHomeSafeZoneInfo()
        cost = info.clearCost or 0
        line = GodSystemApp.services.runtime.text("Confirm_HomeSafeClear", "Clear zombies in home safe zone now?")
    end
    local pos = GodSystemApp.services.runtime.formatPosition((getPlayer() and { x = getPlayer():getX(), y = getPlayer():getY(), z = getPlayer():getZ() }) or nil)
    return line .. "\n" .. GodSystemApp.services.runtime.text("Home_CurrentPosition", "Current: ") .. pos .. "\n" .. GodSystemApp.services.runtime.text("Trait_ConfirmCost", "Cost: ") .. tostring(cost) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c")
end

function GodSystemWindow:confirmHomeAction(action, index)
    if not action then
        return
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 130)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 260, self:getHomeConfirmMessage(action, index), true, self, self.onHomeConfirm, playerNum, { action = action, index = index })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitConfirmMissing", "Confirmation dialog unavailable"))
    end
end

function GodSystemWindow:onHomeConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    if payload then
        local sent = GodSystemApp.services.runtime.performHomeAction(payload.action, payload.index)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:showBankAmountDialog(action, message, termId, entryId)
    local w, h = 340, 150
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemBankAmountDialog:new(x, y, w, h, self, {
        action = action,
        message = message,
        termId = termId,
        entryId = entryId,
    })
    dialog:initialise()
    GodSystemUI.presentOverlay(dialog)
end

function GodSystemWindow:showAttributeAmountDialog(payload)
    payload = payload or self:getSelectedPayload()
    local row = payload and payload.kind == "attribute" and payload.data or nil
    if not row or row.maxed == true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(row and "Notify_AttributeMaxed" or "Notify_AttributeSelect", row and "This skill is already maxed" or "Select a skill first"))
        return
    end
    self:prepareActionSelection(payload)
    local title = GodSystemApp.services.runtime.text("Attribute_BuyXP", "Buy XP")
    local message = GodSystemApp.services.runtime.text("Attribute_AmountPrompt", "Enter the amount of currency to spend")
    local w, h = 380, 150
    local x = math.max(80, (getCore():getScreenWidth() / 2) - (w / 2))
    local y = math.max(80, (getCore():getScreenHeight() / 2) - (h / 2))
    local dialog = GodSystemBankAmountDialog:new(x, y, w, h, self, {
        kind = "attribute",
        title = title,
        message = message,
        perkIndex = row.index,
        mode = "amount",
    })
    dialog:initialise()
    GodSystemUI.presentOverlay(dialog)
end

function GodSystemWindow:showAttributeNextLevelConfirm(payload)
    payload = payload or self:getSelectedPayload()
    local row = payload and payload.kind == "attribute" and payload.data or nil
    if not row or row.maxed == true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(row and "Notify_AttributeMaxed" or "Notify_AttributeSelect", row and "This skill is already maxed" or "Select a skill first"))
        return
    end
    self:prepareActionSelection(payload)
    local currentLevel = math.max(0, math.floor(tonumber(row.currentLevel) or 0))
    local quote = GodSystemApp.services.runtime.getAttributeQuote(row.index, "targetLevel", currentLevel + 1)
    if not quote or (tonumber(quote.actualXp) or 0) <= 0 then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_AttributeInvalid", "Unable to purchase skill XP"))
        return
    end
    local targetLevel = currentLevel + 1
    local message = GodSystemApp.services.runtime.text("Attribute_NextLevelConfirm", "Upgrade this skill to the next level?") .. "\n\n"
        .. tostring(row.label or quote.info and quote.info.label or "") .. "\n"
        .. GodSystemApp.services.runtime.text("Attribute_CurrentLevel", "Current level") .. ": " .. tostring(currentLevel) .. "\n"
        .. GodSystemApp.services.runtime.text("Attribute_TargetLevel", "Target level") .. ": " .. tostring(targetLevel) .. "\n"
        .. GodSystemApp.services.runtime.text("Attribute_RequiredXP", "Required XP") .. ": " .. tostring(math.floor(tonumber(quote.actualXp) or 0)) .. " XP\n"
        .. GodSystemApp.services.runtime.text("Attribute_Cost", "Cost") .. ": " .. tostring(math.floor(tonumber(quote.cost) or 0)) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins")
    local player = getPlayer()
    local playerNum = player and player:getPlayerNum() or 0
    local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
    local y = math.max(80, (getCore():getScreenHeight() / 2) - 140)
    local modal = ISModalDialog:new(x, y, 500, 280, message, true, self, self.onAttributeNextLevelConfirm, playerNum, {
        perkIndex = row.index,
        targetLevel = targetLevel,
    })
    modal:initialise()
    GodSystemUI.presentOverlay(modal)
end

function GodSystemWindow:onAttributeNextLevelConfirm(button, payload)
    if not button or button.internal ~= "YES" or not payload then
        self:clearPendingActionSelection()
        return
    end
    local sent = GodSystemApp.services.runtime.performAttributePurchase(payload.perkIndex, "targetLevel", payload.targetLevel)
    self:finishMultiplayerCommand(sent)
    if sent == false then self:clearPendingActionSelection() end
end

function GodSystemWindow:confirmBankFixedWithdraw(entry)
    if not entry then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_BankSelectFixed", "Select a fixed deposit first"))
        return
    end
    local payout, interestOrPenalty, mature = GodSystemApp.services.runtime.getBankFixedPayout(entry)
    local message = ""
    if mature then
        message = GodSystemApp.services.runtime.text("Confirm_BankFixedWithdraw", "Withdraw matured fixed deposit to current account?")
    else
        message = GodSystemApp.services.runtime.text("Confirm_BankFixedEarlyWithdraw", "Fixed deposit is not mature. Early withdrawal gives no interest and applies penalty. Continue?")
    end
    message = message .. "\n" .. GodSystemApp.services.runtime.text("Bank_Payout", "payout") .. ": " .. tostring(payout)
    if interestOrPenalty < 0 then
        message = message .. "\n" .. GodSystemApp.services.runtime.text("Bank_Penalty", "penalty") .. ": " .. tostring(math.abs(interestOrPenalty))
    elseif interestOrPenalty > 0 then
        message = message .. "\n" .. GodSystemApp.services.runtime.text("Bank_Interest", "interest") .. ": " .. tostring(interestOrPenalty)
    end
    if ISModalDialog then
        local x = math.max(80, (getCore():getScreenWidth() / 2) - 250)
        local y = math.max(80, (getCore():getScreenHeight() / 2) - 120)
        local player = getPlayer()
        local playerNum = player and player:getPlayerNum() or 0
        local modal = ISModalDialog:new(x, y, 500, 240, message, true, self, self.onBankFixedConfirm, playerNum, { entryId = entry.id })
        modal:initialise()
        GodSystemUI.presentOverlay(modal)
    else
        local sent = GodSystemApp.services.runtime.performBankAction("withdrawFixed", nil, nil, entry.id)
        self:finishMultiplayerCommand(sent)
    end
end

function GodSystemWindow:onBankFixedConfirm(button, payload)
    if not button or button.internal ~= "YES" then
        return
    end
    local sent = GodSystemApp.services.runtime.performBankAction("withdrawFixed", nil, nil, payload and payload.entryId)
    self:finishMultiplayerCommand(sent)
end
end
