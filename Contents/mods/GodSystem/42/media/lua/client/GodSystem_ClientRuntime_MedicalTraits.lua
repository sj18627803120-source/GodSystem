_G.GodSystemClientRuntimeInstallers = _G.GodSystemClientRuntimeInstallers or {}
GodSystemClientRuntimeInstallers["GodSystem_ClientRuntime_MedicalTraits"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_MedicalTraits then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ClientRuntime_MedicalTraits = true
    setfenv(1, runtimeEnvironment)

function GodSystemApp.services.runtime.ensureRecycleDailyLimit()
    local data = GodSystemApp.services.runtime.getData()
    local day = gsCurrentDay()
    if data.recycleLimitDay ~= day then
        data.recycleLimitDay = day
        data.recycleLimitUsed = 0
        GodSystemApp.services.runtime.save()
    end
    return data
end

function GodSystemApp.services.runtime.getRecycleDailyRemaining()
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then
        return 999999
    end
    local data = GodSystemApp.services.runtime.ensureRecycleDailyLimit()
    return math.max(0, cap - (data.recycleLimitUsed or 0))
end

function GodSystemApp.services.runtime.isRecycleUnlockMode()
    local data = GodSystemApp.services.runtime.getData()
    if data.recycleUnlockMode == nil then
        data.recycleUnlockMode = true
    end
    return data.recycleUnlockMode == true
end

function GodSystemApp.services.runtime.toggleRecycleUnlockMode()
    local data = GodSystemApp.services.runtime.getData()
    data.recycleUnlockMode = not GodSystemApp.services.runtime.isRecycleUnlockMode()
    GodSystemApp.services.runtime.save()
    if data.recycleUnlockMode then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleModeUnlock", "Recycle mode: unlock shop"))
    else
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_RecycleModeOnly", "Recycle mode: recycle only"))
    end
    return data.recycleUnlockMode
end

function GodSystemApp.services.runtime.getDailyTaskRefreshCountdown()
    local now = gsNowHours()
    local nextDay = (math.floor(now / 24) + 1) * 24
    local remain = math.max(0, nextDay - now)
    local hours = math.floor(remain)
    local minutes = math.floor((remain - hours) * 60)
    return hours, minutes, remain
end

function GodSystemApp.services.runtime.getDailyTaskRefreshText()
    local hours, minutes = GodSystemApp.services.runtime.getDailyTaskRefreshCountdown()
    return string.format("%02d:%02d", hours, minutes)
end

function GodSystemApp.services.runtime.previewRecycleDailyPayout(rawValue)
    rawValue = math.max(0, math.floor(tonumber(rawValue) or 0))
    if rawValue <= 0 then
        return 0, false
    end
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap <= 0 then
        return rawValue, false
    end
    local remaining = GodSystemApp.services.runtime.getRecycleDailyRemaining()
    if remaining > 0 then
        local payout = math.min(rawValue, remaining)
        return payout, payout < rawValue
    end
    return math.max(1, GodSystemConfig.DiminishedRecyclePayout or 1), true
end

function GodSystemApp.services.runtime.applyRecycleDailyPayout(rawValue)
    local payout, diminished = GodSystemApp.services.runtime.previewRecycleDailyPayout(rawValue)
    local cap = GodSystemConfig.DailyRecycleSoftCap or 0
    if cap > 0 and payout > 0 then
        local data = GodSystemApp.services.runtime.ensureRecycleDailyLimit()
        local remaining = math.max(0, cap - (data.recycleLimitUsed or 0))
        if remaining > 0 then
            data.recycleLimitUsed = math.min(cap, (data.recycleLimitUsed or 0) + math.min(payout, remaining))
        end
    end
    return payout, diminished
end

function GodSystemApp.services.runtime.itemExists(fullType)
    if not fullType then
        return false
    end
    if getScriptManager and getScriptManager() then
        return getScriptManager():FindItem(fullType) ~= nil
    end
    return true
end

function GodSystemApp.services.runtime.getItemDisplayName(fullType, fallback)
    if getText and fullType then
        local key = "ItemName_" .. tostring(fullType)
        local value = getText(key)
        if value and value ~= key then
            return value
        end
    end
    if GodSystemFallbackItems and GodSystemFallbackItems[fullType] then
        return GodSystemFallbackItems[fullType]
    end
    if getScriptManager and getScriptManager() then
        local scriptItem = getScriptManager():FindItem(fullType)
        if scriptItem and scriptItem:getDisplayName() then
            return scriptItem:getDisplayName()
        end
    end
    return fallback or fullType
end

function GodSystemApp.services.runtime.shopItemIsAvailable(shopItem)
    if not shopItem then
        return false, GodSystemApp.services.runtime.text("Error_ShopItemMissing", "Shop item missing")
    end
    local items = shopItem.items or {}
    if #items == 0 then
        return true, "", {}, {}
    end
    local availableItems = {}
    local missingItems = {}
    for i = 1, #items do
        if GodSystemItemConfig.isShopItemEnabled(items[i].fullType, true) == false then
            return false, GodSystemApp.services.runtime.text("Error_ShopItemDisabled", "Shop item disabled"), {}, {}
        elseif not GodSystemApp.services.runtime.itemExists(items[i].fullType) then
            table.insert(missingItems, tostring(items[i].fullType))
        else
            table.insert(availableItems, { fullType = items[i].fullType, worldSprite = items[i].worldSprite, count = items[i].count or 1 })
        end
    end
    if #availableItems == 0 then
        return false, GodSystemApp.services.runtime.text("Error_AllItemsMissing", "All items missing"), availableItems, missingItems
    end
    if #missingItems > 0 then
        return true, GodSystemApp.services.runtime.text("Error_MissingSome", "Some missing: ") .. tostring(#missingItems), availableItems, missingItems
    end
    return true, "", availableItems, missingItems
end

function GodSystemApp.services.runtime.giveItem(fullType, count)
    local player = gsPlayer()
    if not player or not fullType then
        return false, {}
    end
    if not GodSystemApp.services.runtime.itemExists(fullType) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Error_ItemNotFound", "Item not found: ") .. tostring(fullType))
        return false, {}
    end

    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if not okInventory or not inventory or not inventory.AddItem then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Error_ItemGiveFailed", "Item grant failed: ") .. tostring(fullType))
        return false, {}
    end
    count = math.max(1, math.floor(count or 1))
    local addedItems = {}
    local failed = false
    for _ = 1, count do
        local okAdd, item = pcall(function() return inventory:AddItem(fullType) end)
        if okAdd and item then
            table.insert(addedItems, item)
        else
            failed = true
            break
        end
    end
    if failed then
        for i = 1, #addedItems do
            pcall(function() inventory:Remove(addedItems[i]) end)
        end
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Error_ItemGiveFailed", "Item grant failed: ") .. tostring(fullType))
        return false, {}
    end
    return #addedItems > 0, addedItems
end

function GodSystemApp.services.runtime.giveItems(items, silentMissing)
    if not items then
        return 0, {}, {}
    end
    local given = 0
    local missing = {}
    local addedItems = {}
    local player = gsPlayer()
    local inventory = player and player.getInventory and player:getInventory() or nil
    for i = 1, #items do
        if GodSystemApp.services.runtime.itemExists(items[i].fullType) then
            local ok, added = nil, nil
            if items[i].worldSprite then
                ok, added = GodSystemShopVariants.addItems(inventory, items[i].fullType, items[i].worldSprite, items[i].count or 1)
            else
                ok, added = GodSystemApp.services.runtime.giveItem(items[i].fullType, items[i].count or 1)
            end
            if ok then
                for j = 1, #(added or {}) do
                    table.insert(addedItems, added[j])
                end
                given = given + #(added or {})
            end
        else
            table.insert(missing, tostring(items[i].fullType))
        end
    end
    if #missing > 0 and not silentMissing then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Error_MissingSome", "Some missing: ") .. tostring(#missing))
    end
    return given, missing, addedItems
end

function GodSystemApp.services.runtime.removeAddedItems(addedItems)
    local player = gsPlayer()
    if not player or not addedItems then
        return
    end
    for i = 1, #addedItems do
        local item = addedItems[i]
        if item then
            local container = nil
            if item.getContainer then
                local ok, found = pcall(function() return item:getContainer() end)
                if ok then
                    container = found
                end
            end
            if container and container.Remove then
                pcall(function() container:Remove(item) end)
            else
                pcall(function() player:getInventory():Remove(item) end)
            end
        end
    end
end

function gsSafeGetText(key)
    if not key or not getText then
        return nil
    end
    local ok, value = pcall(function() return getText(key) end)
    if ok and value and tostring(value) ~= tostring(key) then
        return tostring(value)
    end
    return nil
end

function gsSafeCall(object, methodName, fallback, ...)
    return GodSystemB42JavaCalls.value(object, methodName, fallback, ...)
end

function gsArrayFromList(list)
    local result = {}
    if not list then
        return result
    end

    if type(list) == "table" then
        for _, value in pairs(list) do
            table.insert(result, value)
        end
        return result
    end

    if not list.size or not list.get then
        return result
    end

    local size = tonumber(list:size()) or 0
    if not size then
        return result
    end
    for i = 0, size - 1 do
        local value = list:get(i)
        if value ~= nil then
            table.insert(result, value)
        end
    end
    return result
end

function gsArrayFromMapValues(map)
    local result = {}
    if not map then
        return result
    end
    if type(map) == "table" then
        for _, value in pairs(map) do
            table.insert(result, value)
        end
        return result
    end
    if map.values then
        local values = map:values()
        if values then
            local list = gsArrayFromList(values)
            for i = 1, #list do
                table.insert(result, list[i])
            end
        end
    end
    return result
end

MEDICAL_SERVICE_ORDER = {
    "checkInfection",
    "healInjuries",
    "cureInfection",
}

function gsMedicalPlayer(targetPlayer)
    if targetPlayer then
        return targetPlayer
    end
    if getPlayer then
        return getPlayer()
    end
    return nil
end

function gsMedicalBody(targetPlayer)
    local p = gsMedicalPlayer(targetPlayer)
    if not p then
        return nil
    end
    return gsSafeCall(p, "getBodyDamage", nil)
end

function gsMedicalBool(object, methods)
    for i = 1, #(methods or {}) do
        local value = gsSafeCall(object, methods[i], nil)
        if value == true then
            return true
        elseif value == false then
            return false
        end
    end
    return false
end

function gsMedicalNumber(object, methods, fallback)
    for i = 1, #(methods or {}) do
        local value = tonumber(gsSafeCall(object, methods[i], nil))
        if value ~= nil then
            return value
        end
    end
    return fallback
end

function gsMedicalBodyParts(body)
    local parts = gsSafeCall(body, "getBodyParts", nil)
    return gsArrayFromList(parts)
end

function gsMedicalCaptureInfection(body)
    return {
        infected = gsMedicalBool(body, { "IsInfected", "isInfected" }),
        fakeInfected = gsMedicalBool(body, { "IsFakeInfected", "isFakeInfected" }),
        infectionTime = gsMedicalNumber(body, { "getInfectionTime" }, nil),
        mortalityDuration = gsMedicalNumber(body, { "getInfectionMortalityDuration" }, nil),
        infectionLevel = gsMedicalNumber(body, { "getInfectionLevel" }, nil),
    }
end

function gsMedicalRestoreInfection(body, snapshot)
    if not body or not snapshot or snapshot.infected ~= true then
        return
    end
    gsSafeCall(body, "setInfected", nil, true)
    gsSafeCall(body, "setIsFakeInfected", nil, snapshot.fakeInfected == true)
    if snapshot.infectionTime ~= nil then
        gsSafeCall(body, "setInfectionTime", nil, snapshot.infectionTime)
    end
    if snapshot.mortalityDuration ~= nil then
        gsSafeCall(body, "setInfectionMortalityDuration", nil, snapshot.mortalityDuration)
    end
    if snapshot.infectionLevel ~= nil then
        gsSafeCall(body, "setInfectionLevel", nil, snapshot.infectionLevel)
    end
end

function gsMedicalIsInfected(body)
    if not body then
        return false
    end
    if gsMedicalBool(body, { "IsInfected", "isInfected" }) then
        return true
    end
    local level = gsMedicalNumber(body, { "getInfectionLevel" }, 0) or 0
    if level > 0 then
        return true
    end
    local time = gsMedicalNumber(body, { "getInfectionTime" }, -1) or -1
    return time > 0
end

function gsMedicalHasInjury(body)
    if not body then
        return false
    end
    local overall = gsMedicalNumber(body, { "getOverallBodyHealth", "getHealth" }, nil)
    if overall and overall < 99.5 then
        return true
    end

    local boolMethods = {
        "HasInjury",
        "hasInjury",
        "isBleeding",
        "IsBleeding",
        "bleeding",
        "isDeepWounded",
        "deepWounded",
        "haveBullet",
        "haveGlass",
        "isBurnt",
        "stitched",
    }
    local timeMethods = {
        "getBleedingTime",
        "getDeepWoundTime",
        "getScratchTime",
        "getCutTime",
        "getBiteTime",
        "getBurnTime",
        "getFractureTime",
        "getWoundInfectionLevel",
        "getAdditionalPain",
    }
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        local part = parts[i]
        local health = gsMedicalNumber(part, { "getHealth" }, nil)
        if health and health < 99.5 then
            return true
        end
        for j = 1, #boolMethods do
            if gsSafeCall(part, boolMethods[j], false) == true then
                return true
            end
        end
        for j = 1, #timeMethods do
            local value = tonumber(gsSafeCall(part, timeMethods[j], 0)) or 0
            if value > 0 then
                return true
            end
        end
    end
    return false
end

function gsMedicalClearBodyPartInfection(part)
    if not part then
        return
    end
    gsSafeCall(part, "SetInfected", nil, false)
    gsSafeCall(part, "SetFakeInfected", nil, false)
    gsSafeCall(part, "setInfectedWound", nil, false)
    gsSafeCall(part, "setWoundInfectionLevel", nil, -1)
end

function gsMedicalClearInfection(body, targetPlayer)
    if not body then
        return false
    end
    local p = gsMedicalPlayer(targetPlayer)
    if p and CharacterStat and CharacterStat.ZOMBIE_INFECTION ~= nil then
        local stats = gsSafeCall(p, "getStats", nil)
        if stats then
            pcall(function()
                stats:set(CharacterStat.ZOMBIE_INFECTION, 0)
            end)
        end
    end
    gsSafeCall(body, "setInfectionTime", nil, -1.0)
    gsSafeCall(body, "setInfectionLevel", nil, 0)
    gsSafeCall(body, "setInfected", nil, false)
    gsSafeCall(body, "setIsFakeInfected", nil, false)
    gsSafeCall(body, "setInfectionMortalityDuration", nil, -1.0)
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        gsMedicalClearBodyPartInfection(parts[i])
    end
    return gsMedicalIsInfected(body) ~= true
end

function gsMedicalFormatTemplate(template, args)
    local text = tostring(template or "")
    args = args or {}
    for i = 1, #args do
        text = string.gsub(text, "{" .. tostring(i) .. "}", function()
            return tostring(args[i] or "")
        end)
    end
    return text
end

function gsMedicalHealPart(part)
    if not part then
        return
    end
    gsSafeCall(part, "SetHealth", nil, 100)
    gsSafeCall(part, "setHealth", nil, 100)
    gsSafeCall(part, "setBleedingTime", nil, 0)
    gsSafeCall(part, "setDeepWoundTime", nil, 0)
    gsSafeCall(part, "setScratchTime", nil, 0)
    gsSafeCall(part, "setCutTime", nil, 0)
    gsSafeCall(part, "setBiteTime", nil, 0)
    gsSafeCall(part, "setBurnTime", nil, 0)
    gsSafeCall(part, "setFractureTime", nil, 0)
    gsSafeCall(part, "setAdditionalPain", nil, 0)
    gsSafeCall(part, "setWoundInfectionLevel", nil, 0)
    gsSafeCall(part, "setHaveBullet", nil, false, 0)
    gsSafeCall(part, "setHaveGlass", nil, false)
    gsSafeCall(part, "setStitched", nil, false)
    gsSafeCall(part, "setSplint", nil, false, 0)
end

function gsMedicalHealInjuries(targetPlayer, body)
    body = body or gsMedicalBody(targetPlayer)
    if not body then
        return false
    end
    local snapshot = gsMedicalCaptureInfection(body)
    local parts = gsMedicalBodyParts(body)
    for i = 1, #parts do
        gsMedicalHealPart(parts[i])
    end
    gsSafeCall(body, "setOverallBodyHealth", nil, 100)
    local p = gsMedicalPlayer(targetPlayer)
    if p then
        gsSafeCall(p, "setHealth", nil, 1.0)
    end
    gsMedicalRestoreInfection(body, snapshot)
    return true
end

function GodSystemApp.services.runtime.getMedicalStatus(targetPlayer)
    local body = gsMedicalBody(targetPlayer)
    if not body then
        return { hasBody = false, infected = false, hasInjury = false }
    end
    return {
        hasBody = true,
        infected = gsMedicalIsInfected(body),
        hasInjury = gsMedicalHasInjury(body),
        infectionTime = gsMedicalNumber(body, { "getInfectionTime" }, nil),
        infectionLevel = gsMedicalNumber(body, { "getInfectionLevel" }, nil),
        mortalityDuration = gsMedicalNumber(body, { "getInfectionMortalityDuration" }, nil),
    }
end

function GodSystemApp.services.runtime.getMedicalServiceInfo(action)
    action = tostring(action or "")
    if action == "checkInfection" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalCheckInfectionCost) or 50)),
            label = GodSystemApp.services.runtime.text("Upgrade_Medical_CheckInfection", "Check infection"),
            desc = GodSystemApp.services.runtime.text("Upgrade_Medical_CheckInfectionDesc", "Pay to check whether this character has zombie infection."),
            button = GodSystemApp.services.runtime.text("Btn_Medical_CheckInfection", "Check"),
        }
    elseif action == "healInjuries" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalHealInjuriesCost) or 5000)),
            label = GodSystemApp.services.runtime.text("Upgrade_Medical_HealInjuries", "Heal injuries"),
            desc = GodSystemApp.services.runtime.text("Upgrade_Medical_HealInjuriesDesc", "Clear wounds and restore health. This does not remove zombie infection."),
            button = GodSystemApp.services.runtime.text("Btn_Medical_HealInjuries", "Heal"),
        }
    elseif action == "cureInfection" then
        return {
            action = action,
            cost = math.max(0, math.floor(tonumber(GodSystemConfig.MedicalCureInfectionCost) or 2000)),
            label = GodSystemApp.services.runtime.text("Upgrade_Medical_CureInfection", "Cure infection"),
            desc = GodSystemApp.services.runtime.text("Upgrade_Medical_CureInfectionDesc", "Fully remove zombie infection. Wounds are not healed."),
            button = GodSystemApp.services.runtime.text("Btn_Medical_CureInfection", "Cure"),
        }
    end
    return nil
end

function GodSystemApp.services.runtime.getMedicalServiceList()
    local result = {}
    for i = 1, #MEDICAL_SERVICE_ORDER do
        local info = GodSystemApp.services.runtime.getMedicalServiceInfo(MEDICAL_SERVICE_ORDER[i])
        if info then
            result[#result + 1] = info
        end
    end
    return result
end

function GodSystemApp.services.runtime.applyMedicalServiceLocally(action, targetPlayer)
    local body = gsMedicalBody(targetPlayer)
    if not body then
        return false, "bodyMissing"
    end
    action = tostring(action or "")
    if action == "checkInfection" then
        return true, gsMedicalIsInfected(body) and "infected" or "clean"
    elseif action == "healInjuries" then
        return gsMedicalHealInjuries(targetPlayer, body), "healed"
    elseif action == "cureInfection" then
        if not gsMedicalIsInfected(body) then
            return true, "notInfected"
        end
        return gsMedicalClearInfection(body, targetPlayer), "cured"
    end
    return false, "unknown"
end

function GodSystemApp.services.runtime.performMedicalService(action)
    local info = GodSystemApp.services.runtime.getMedicalServiceInfo(action)
    if not info then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end
    local status = GodSystemApp.services.runtime.getMedicalStatus()
    if status.hasBody ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end
    if action == "cureInfection" and status.infected ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Medical_NotInfected", "No zombie infection detected"))
        return false
    end
    if action == "healInjuries" and status.hasInjury ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Medical_NoInjury", "No injuries need treatment"))
        return false
    end
    if not GodSystemApp.services.runtime.canAfford(info.cost or 0) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    if (info.cost or 0) > 0 and not GodSystemApp.services.runtime.addPoints(-info.cost) then
        return false
    end

    local ok, result = GodSystemApp.services.runtime.applyMedicalServiceLocally(action)
    if not ok then
        if (info.cost or 0) > 0 then
            GodSystemApp.services.runtime.addPoints(info.cost)
        end
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_Medical_Failed", "Medical service failed"))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + (info.cost or 0)
    local messageKey = "Notify_Medical_Healed"
    if action == "checkInfection" then
        messageKey = result == "infected" and "Notify_Medical_CheckResultInfected" or "Notify_Medical_CheckResultClean"
    elseif action == "cureInfection" then
        messageKey = "Notify_Medical_Cured"
    end
    local message = GodSystemApp.services.runtime.text(messageKey, "Medical service complete")
    gsAppendHistory(data, { kind = "medical", text = GodSystemApp.services.runtime.text("History_MedicalService", "Medical service: ") .. tostring(info.label) .. " -" .. tostring(info.cost or 0) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") })
    GodSystemApp.services.runtime.notify(message)
    GodSystemApp.services.runtime.save()
    return true
end

function GodSystemApp.services.runtime.getAttributePerks(query)
    if GodSystemAttributes.isEnabled() ~= true then return {} end
    local rows = GodSystemAttributes.enumerate(gsPlayer())
    query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return rows end
    local filtered = {}
    for i = 1, #rows do
        local row = rows[i]
        local haystack = (tostring(row.label or "") .. " " .. tostring(row.parentLabel or "")):lower()
        if string.find(haystack, query, 1, true) then filtered[#filtered + 1] = row end
    end
    return filtered
end

function GodSystemApp.services.runtime.getAttributeQuote(perkIndex, mode, value)
    return GodSystemAttributes.quote(gsPlayer(), perkIndex, mode, value, GodSystemAttributes.getXpPerCoin())
end

function GodSystemApp.services.runtime.performAttributePurchase(perkIndex, mode, value)
    if GodSystemAttributes.isEnabled() ~= true then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_AttributesDisabled", "Attribute purchases are disabled"))
        return false
    end
    if GodSystemNetwork and GodSystemNetwork.isMultiplayer == true and GodSystemNetwork.send then
        return GodSystemNetwork.send((GodSystemProtocol and GodSystemProtocol.C2S and GodSystemProtocol.C2S.Attribute) or "attribute", {
            perkIndex = math.floor(tonumber(perkIndex) or -1),
            mode = tostring(mode or "amount"),
            value = math.floor(tonumber(value) or 0),
        })
    end

    local player = gsPlayer()
    local quote, reason = GodSystemAttributes.quote(player, perkIndex, mode, value, GodSystemAttributes.getXpPerCoin())
    if not quote then
        local key = reason == "maxed" and "Notify_AttributeMaxed" or "Notify_AttributeInvalid"
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(key, "Unable to purchase attribute XP"))
        return false
    end
    if not GodSystemApp.services.runtime.canAfford(quote.cost) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end
    local paid, fromBank, fromCash = GodSystemApp.services.runtime.spendCurrency(quote.cost)
    if not paid then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local before = quote.currentXp
    local xp = player and player.getXp and player:getXp() or nil
    if xp and xp.AddXP then
        pcall(function() xp:AddXP(quote.info.perk, quote.actualXp, false, false, false, false) end)
    end
    local state = GodSystemAttributes.getPlayerState(player, quote.info)
    local appliedXp = state and math.max(0, state.currentXp - before) or 0
    if appliedXp <= 0 then
        local originalSourcesRestored = GodSystemApp.services.runtime.refundCurrencySources(fromBank, fromCash)
        local key = originalSourcesRestored and "Notify_AttributeApplyFailed" or "Notify_AttributeApplyFailedBankRefund"
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(key, "Attribute XP could not be applied; payment was refunded"))
        GodSystemApp.services.runtime.save()
        return false
    end

    local chargedCost = quote.cost
    if appliedXp + 0.0001 < quote.actualXp then
        chargedCost = math.max(1, math.min(quote.cost, math.ceil(appliedXp / GodSystemAttributes.getXpPerCoin())))
        local refund = quote.cost - chargedCost
        local refundCash = math.min(math.max(0, math.floor(tonumber(fromCash) or 0)), refund)
        GodSystemApp.services.runtime.refundCurrencySources(refund - refundCash, refundCash)
    end
    if type(SyncXp) == "function" then pcall(function() SyncXp(player) end) end
    local data = GodSystemApp.services.runtime.getData()
    data.stats = data.stats or {}
    data.stats.spentPoints = (data.stats.spentPoints or 0) + chargedCost
    gsAppendHistory(data, {
        kind = "attribute",
        text = GodSystemApp.services.runtime.text("History_AttributePurchased", "Attribute XP purchased: ") .. tostring(quote.info.label) .. " +" .. tostring(math.floor(appliedXp)) .. " XP -" .. tostring(chargedCost) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"),
    })
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_AttributePurchased", "Attribute XP purchased: ") .. tostring(quote.info.label) .. " +" .. tostring(math.floor(appliedXp)) .. " XP")
    GodSystemApp.services.runtime.save()
    return true
end

function gsTraitTokenString(token)
    if token == nil then
        return ""
    end
    local tokenType = type(token)
    if tokenType == "string" or tokenType == "number" or tokenType == "boolean" then
        return tostring(token)
    end
    if token.toString then
        local value = token:toString()
        return tostring(value)
    end
    return tostring(token)
end

function gsNormalizeTraitType(traitType)
    return tostring(traitType or ""):gsub("[%s_%-]", ""):lower()
end

function gsTraitMapLookup(map, traitType)
    if not map or not traitType then
        return nil
    end
    local direct = map[traitType]
    if direct ~= nil then
        return direct
    end
    if type(map) == "table" then
        local target = gsNormalizeTraitType(traitType)
        for key, value in pairs(map) do
            if gsNormalizeTraitType(key) == target then
                return value
            end
        end
    end
    return nil
end

GodSystemTraitDefinitionCache = nil

function gsBuildCharacterTraitDefinitionCache()
    local cache = { list = {}, byType = {}, byToken = {} }
    if not CharacterTraitDefinition then
        return cache
    end
    local traits = nil
    if CharacterTraitDefinition.getTraits then
        traits = CharacterTraitDefinition.getTraits()
    end
    if traits then
        cache.list = gsArrayFromList(traits)
    end
    for i = 1, #cache.list do
        local trait = cache.list[i]
        if trait and trait.getType then
            local token = trait:getType()
            local traitType = gsTraitTokenString(token)
            local key = gsNormalizeTraitType(traitType)
            if key ~= "" then
                cache.byType[key] = trait
                cache.byToken[key] = token
            end
        end
    end
    return cache
end

function gsCharacterTraitDefinitionCache()
    if not GodSystemTraitDefinitionCache then
        GodSystemTraitDefinitionCache = gsBuildCharacterTraitDefinitionCache()
    end
    return GodSystemTraitDefinitionCache
end

function gsCharacterTraitDefinitionList()
    return gsCharacterTraitDefinitionCache().list or {}
end

function gsCharacterTraitDefinitionByType(traitType)
    local target = gsNormalizeTraitType(traitType)
    if target == "" then
        return nil
    end
    local cache = gsCharacterTraitDefinitionCache()
    return cache.byType[target], cache.byToken[target]
end

function gsTraitFactory()
    if TraitFactory then
        return TraitFactory
    end
    if GodSystemTraitFactoryClass then
        return GodSystemTraitFactoryClass
    end
    if luajava and luajava.bindClass then
        local ok, factory = pcall(function() return luajava.bindClass("zombie.characters.traits.TraitFactory") end)
        if ok and factory then
            GodSystemTraitFactoryClass = factory
            return factory
        end
    end
    return nil
end

function gsFallbackTraitByType(traitType)
    if not traitType then
        return nil
    end
    local catalog = GodSystemConfig.TraitFallbackCatalog or {}
    for i = 1, #catalog do
        local entry = catalog[i]
        if entry and gsNormalizeTraitType(entry.type) == gsNormalizeTraitType(traitType) then
            return entry
        end
    end
    return nil
end

function gsFallbackTraitList()
    local result = {}
    local catalog = GodSystemConfig.TraitFallbackCatalog or {}
    for i = 1, #catalog do
        if catalog[i] and catalog[i].type then
            table.insert(result, catalog[i])
        end
    end
    return result
end

function gsTraitFactoryGetTrait(traitType)
    if not traitType then
        return nil
    end
    local characterTrait = gsCharacterTraitDefinitionByType(traitType)
    if characterTrait then
        return characterTrait
    end
    local token = gsTraitTokenForType(traitType)
    if CharacterTraitDefinition and CharacterTraitDefinition.getCharacterTraitDefinition and token and type(token) ~= "string" then
        characterTrait = CharacterTraitDefinition.getCharacterTraitDefinition(token)
        if characterTrait then
            return characterTrait
        end
    end
    local factory = gsTraitFactory()
    local trait = nil
    if factory and factory.getTrait and type(traitType) == "string" then
        trait = factory.getTrait(traitType)
    end
    if trait then
        return trait
    end
    return gsFallbackTraitByType(traitType)
end

function gsTraitTokenForType(traitType)
    if not traitType then
        return nil
    end
    if type(traitType) ~= "string" then
        return traitType
    end

    local trait, token = gsCharacterTraitDefinitionByType(traitType)
    if token then
        return token
    end
    if trait and trait.getType then
        return trait:getType()
    end

    if CharacterTrait then
        local found = gsTraitMapLookup(CharacterTrait, traitType)
        if found then
            return found
        end
    end
    return traitType
end

function gsTraitFactoryList()
    local traitList = gsCharacterTraitDefinitionList()
    if #traitList > 0 then
        return traitList, "CharacterTraitDefinition"
    end

    local factory = gsTraitFactory()
    local traits = nil
    if factory and factory.getTraits then
        traits = factory.getTraits()
    end
    traitList = gsArrayFromList(traits)
    if #traitList > 0 then
        return traitList, "TraitFactory"
    end

    if BaseGameCharacterDetails and BaseGameCharacterDetails.traits then
        traitList = gsArrayFromList(BaseGameCharacterDetails.traits)
        if #traitList > 0 then
            return traitList, "BaseGameCharacterDetails"
        end
    end

    return gsFallbackTraitList(), "FallbackCatalog"
end

function gsTraitType(trait)
    if type(trait) == "table" then
        return tostring(trait.type or trait.traitType or "")
    end
    if trait and trait.getType then
        local traitType = trait:getType()
        if traitType ~= nil then
            return gsTraitTokenString(traitType)
        end
    end
    return tostring(trait or "")
end

function gsTraitLabel(trait, traitType)
    traitType = traitType or gsTraitType(trait)
    if type(trait) == "table" then
        local label = gsSafeGetText(trait.labelKey)
        if label and label ~= "" then
            return label
        end
        if trait.label and tostring(trait.label) ~= "" then
            return tostring(trait.label)
        end
        return tostring(traitType or "")
    end
    if trait and trait.getLabel then
        local label = trait:getLabel()
        if label and tostring(label) ~= "" then
            return tostring(label)
        end
    end
    return tostring(traitType or "")
end

function gsTraitLabelByType(traitType)
    local trait = gsTraitFactoryGetTrait(traitType)
    if trait then
        return gsTraitLabel(trait, traitType)
    end
    return tostring(traitType or "")
end

function gsTraitCost(trait)
    if type(trait) == "table" then
        return math.floor(tonumber(trait.cost or trait.costPoints) or 0)
    end
    if trait and trait.getCost then
        local cost = tonumber(trait:getCost())
        if cost then
            return math.floor(cost)
        end
    end
    return 0
end

function gsTraitIsFree(trait)
    if type(trait) == "table" then
        return trait.free == true
    end
    if trait and trait.isFree then
        return trait:isFree() == true
    end
    return false
end

function gsTraitIsProfession(trait)
    if not trait then
        return false
    end
    if type(trait) == "table" then
        return trait.prof == true or trait.profession == true
    end
    return false
end

function gsTraitDescription(trait)
    if type(trait) == "table" then
        local description = gsSafeGetText(trait.descriptionKey)
        if description and description ~= "" then
            return description
        end
        return tostring(trait.description or "")
    end
    if trait and trait.getDescription then
        local description = trait:getDescription()
        if description and tostring(description) ~= "" then
            return tostring(description)
        end
    end
    return ""
end

function gsTraitMutualTypes(trait)
    if type(trait) == "table" then
        return gsArrayFromList(trait.mutual or trait.mutualTypes or {})
    end
    local raw = nil
    if trait and trait.getMutuallyExclusiveTraits then
        raw = trait:getMutuallyExclusiveTraits()
    end
    local values = gsArrayFromList(raw)
    local result = {}
    for i = 1, #values do
        local traitType = gsTraitTokenString(values[i])
        if traitType ~= "" then
            table.insert(result, traitType)
        end
    end
    return result
end

function gsJoinLabels(labels)
    if not labels or #labels == 0 then
        return GodSystemApp.services.runtime.text("None", "None")
    end
    return table.concat(labels, ", ")
end

function GodSystemApp.services.runtime.getPlayerTraits()
    local player = gsPlayer()
    if player then
        if player.getCharacterTraits then
            return player:getCharacterTraits()
        end
        if player.getTraits then
            return player:getTraits()
        end
    end
    return nil
end

function GodSystemApp.services.runtime.playerHasTrait(traitType)
    if not traitType then
        return false
    end
    local player = gsPlayer()
    local token = gsTraitTokenForType(traitType)
    if player and player.hasTrait and token and type(token) ~= "string" then
        return player:hasTrait(token) == true
    end
    local traits = GodSystemApp.services.runtime.getPlayerTraits()
    if traits then
        local known = nil
        if traits.getKnownTraits then
            known = traits:getKnownTraits()
        end
        local knownList = gsArrayFromList(known)
        local target = gsNormalizeTraitType(traitType)
        for i = 1, #knownList do
            if gsNormalizeTraitType(gsTraitTokenString(knownList[i])) == target then
                return true
            end
        end
    end
    return false
end

function gsApplyTraitBenefits(traitType)
    local player = gsPlayer()
    local trait = gsCharacterTraitDefinitionByType(traitType)
    if not player or not trait then
        return
    end

    local boosts = trait.getXpBoosts and trait:getXpBoosts() or nil
    if boosts then
        local boostTable = nil
        if transformIntoKahluaTable then
            boostTable = transformIntoKahluaTable(boosts)
        elseif type(boosts) == "table" then
            boostTable = boosts
        end
        if boostTable then
            for perk, value in pairs(boostTable) do
                local count = tonumber(tostring(value)) or 0
                for _ = 1, count do
                    local level = player.getPerkLevel and player:getPerkLevel(perk) or 0
                    if tonumber(level) and tonumber(level) >= 10 then
                        break
                    end
                    if player.LevelPerk then
                        player:LevelPerk(perk)
                    end
                    if luautils and luautils.updatePerksXp then
                        luautils.updatePerksXp(perk, player)
                    end
                end
            end
        end
    end

    local hasRecipes = trait.hasGrantedRecipes and trait:hasGrantedRecipes() or false
    if hasRecipes then
        local recipes = trait.getGrantedRecipes and trait:getGrantedRecipes() or nil
        local recipeList = gsArrayFromList(recipes)
        for i = 1, #recipeList do
            if player.learnRecipe then
                player:learnRecipe(recipeList[i])
            end
        end
    end
end

function GodSystemApp.services.runtime.setPlayerTrait(traitType, enabled)
    local traits = GodSystemApp.services.runtime.getPlayerTraits()
    if not traits or not traitType then
        return false
    end

    local token = gsTraitTokenForType(traitType)
    if type(token) == "string" then
        return false
    end
    if enabled and not GodSystemApp.services.runtime.playerHasTrait(traitType) then
        if traits.add then
            traits:add(token)
        end
    elseif not enabled and GodSystemApp.services.runtime.playerHasTrait(traitType) then
        if traits.remove then
            traits:remove(token)
        end
    end

    local success = GodSystemApp.services.runtime.playerHasTrait(traitType) == (enabled == true)
    if success and enabled then
        gsApplyTraitBenefits(traitType)
    end
    return success
end

function GodSystemApp.services.runtime.getTraitOperationCost(costPoints, action)
    costPoints = math.floor(tonumber(costPoints) or 0)
    if action == "buy" then
        return math.max(0, costPoints) * (GodSystemConfig.PositiveTraitCostPerPoint or 800)
    end
    return math.abs(math.min(0, costPoints)) * (GodSystemConfig.NegativeTraitRemoveCostPerPoint or 500)
end

function GodSystemApp.services.runtime.getTraitRiskText(entry)
    if not entry or entry.risk ~= true then
        return GodSystemApp.services.runtime.text("Trait_RiskStable", "Stable")
    end
    return GodSystemApp.services.runtime.text("Trait_RiskExperimental", "Risk")
end

function GodSystemApp.services.runtime.isTraitBlocked(traitType, trait, cost)
    if not traitType or traitType == "" then
        return true, GodSystemApp.services.runtime.text("Trait_BlockUnknown", "Unknown trait")
    end
    if gsTraitMapLookup(GodSystemConfig.TraitBlockedTypes or {}, traitType) then
        return true, GodSystemApp.services.runtime.text("Trait_BlockBodySkill", "Body weight / strength / fitness traits are not available yet")
    end
    if gsTraitIsFree(trait) or gsTraitIsProfession(trait) or (tonumber(cost) or 0) == 0 then
        return true, GodSystemApp.services.runtime.text("Trait_BlockFree", "Free or profession trait")
    end
    return false, ""
end

function GodSystemApp.services.runtime.getTraitEntryFromTrait(trait, action)
    if not trait then
        return nil
    end
    local traitType = gsTraitType(trait)
    local cost = gsTraitCost(trait)
    local blocked, reason = GodSystemApp.services.runtime.isTraitBlocked(traitType, trait, cost)
    if blocked then
        return nil, reason
    end
    if action == "buy" and cost <= 0 then
        return nil, ""
    end
    if action == "remove" and cost >= 0 then
        return nil, ""
    end

    local label = gsTraitLabel(trait, traitType)
    local mutualTypes = gsTraitMutualTypes(trait)
    local conflictLabels = {}
    local ownedConflictLabels = {}
    for i = 1, #mutualTypes do
        local conflictType = mutualTypes[i]
        local conflictLabel = gsTraitLabelByType(conflictType)
        table.insert(conflictLabels, conflictLabel)
        if GodSystemApp.services.runtime.playerHasTrait(conflictType) then
            table.insert(ownedConflictLabels, conflictLabel)
        end
    end

    local owned = GodSystemApp.services.runtime.playerHasTrait(traitType)
    local entry = {
        kind = "trait",
        action = action,
        traitType = traitType,
        label = label,
        description = gsTraitDescription(trait),
        costPoints = cost,
        price = GodSystemApp.services.runtime.getTraitOperationCost(cost, action),
        risk = not (gsTraitMapLookup(GodSystemConfig.TraitStableTypes or {}, traitType) == true),
        conflictTypes = mutualTypes,
        conflictLabels = conflictLabels,
        ownedConflictLabels = ownedConflictLabels,
        owned = owned,
        disabledReason = nil,
    }

    if action == "buy" then
        if owned then
            entry.disabledReason = GodSystemApp.services.runtime.text("Trait_StatusOwned", "Owned")
        elseif #ownedConflictLabels > 0 then
            entry.disabledReason = GodSystemApp.services.runtime.text("Trait_StatusConflict", "Conflict: ") .. gsJoinLabels(ownedConflictLabels)
        end
    elseif action == "remove" and not owned then
        entry.disabledReason = GodSystemApp.services.runtime.text("Trait_StatusNotOwned", "Not owned")
    end

    return entry, ""
end

function GodSystemApp.services.runtime.getTraitModificationLists()
    local traitList, source = gsTraitFactoryList()

    local function collectTraits(list)
        local positive = {}
        local negative = {}
        local blockedCount = 0
        for i = 1, #list do
            local trait = list[i]
            local cost = gsTraitCost(trait)
            local traitType = gsTraitType(trait)
            local blocked = GodSystemApp.services.runtime.isTraitBlocked(traitType, trait, cost)
            if blocked then
                blockedCount = blockedCount + 1
            elseif cost > 0 then
                local entry = GodSystemApp.services.runtime.getTraitEntryFromTrait(trait, "buy")
                if entry then
                    table.insert(positive, entry)
                end
            elseif cost < 0 and GodSystemApp.services.runtime.playerHasTrait(traitType) then
                local entry = GodSystemApp.services.runtime.getTraitEntryFromTrait(trait, "remove")
                if entry then
                    table.insert(negative, entry)
                end
            end
        end
        return positive, negative, blockedCount
    end

    local positive, negative, blockedCount = collectTraits(traitList)
    if #positive == 0 and source ~= "FallbackCatalog" then
        local fallbackList = gsFallbackTraitList()
        local fallbackPositive, fallbackNegative, fallbackBlocked = collectTraits(fallbackList)
        if #fallbackPositive > 0 then
            positive = fallbackPositive
            negative = fallbackNegative
            blockedCount = fallbackBlocked
            traitList = fallbackList
            source = "FallbackCatalog"
        end
    end

    local function sortTraits(a, b)
        if a.risk ~= b.risk then
            return a.risk ~= true
        end
        if math.abs(a.costPoints or 0) ~= math.abs(b.costPoints or 0) then
            return math.abs(a.costPoints or 0) < math.abs(b.costPoints or 0)
        end
        return tostring(a.label or "") < tostring(b.label or "")
    end
    table.sort(positive, sortTraits)
    table.sort(negative, sortTraits)
    GodSystemApp.services.runtime.lastTraitRead = {
        source = source,
        total = #traitList,
        positive = #positive,
        negative = #negative,
        blocked = blockedCount,
    }
    return positive, negative, blockedCount
end

function GodSystemApp.services.runtime.getTraitModificationEntry(action, traitType)
    local positive, negative = GodSystemApp.services.runtime.getTraitModificationLists()
    local list = action == "remove" and negative or positive
    for i = 1, #list do
        if list[i].traitType == traitType then
            return list[i]
        end
    end
    return nil
end

function GodSystemApp.services.runtime.getTraitDetailText(entry)
    if not entry then
        return ""
    end
    local parts = {}
    table.insert(parts, GodSystemApp.services.runtime.text("Trait_PointCost", "Trait points ") .. tostring(entry.costPoints or 0))
    table.insert(parts, GodSystemApp.services.runtime.text("Trait_Price", "Cost ") .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_CoinShort", "c"))
    table.insert(parts, GodSystemApp.services.runtime.text("Trait_Risk", "Risk: ") .. GodSystemApp.services.runtime.getTraitRiskText(entry))
    if entry.conflictLabels and #entry.conflictLabels > 0 then
        table.insert(parts, GodSystemApp.services.runtime.text("Trait_Conflicts", "Conflicts: ") .. gsJoinLabels(entry.conflictLabels))
    end
    if entry.disabledReason then
        table.insert(parts, GodSystemApp.services.runtime.text("Trait_Status", "Status: ") .. tostring(entry.disabledReason))
    end
    if entry.description and entry.description ~= "" then
        table.insert(parts, entry.description)
    end
    return table.concat(parts, " | ")
end

function GodSystemApp.services.runtime.performTraitModification(action, traitType)
    if GodSystemApp.services.runtime.isFeatureEnabled("EnableTraits") == false then
        GodSystemApp.services.runtime.notify("Traits disabled")
        return false
    end
    local entry = GodSystemApp.services.runtime.getTraitModificationEntry(action, traitType)
    if not entry then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitUnavailable", "Trait is not available"))
        return false
    end
    if entry.disabledReason then
        GodSystemApp.services.runtime.notify(entry.disabledReason)
        return false
    end
    if not GodSystemApp.services.runtime.canAfford(entry.price or 0) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_CurrencyNotEnough", "Not enough currency"))
        return false
    end

    local enable = action == "buy"
    if not GodSystemApp.services.runtime.setPlayerTrait(entry.traitType, enable) then
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitFailed", "Trait modification failed"))
        return false
    end
    if not GodSystemApp.services.runtime.addPoints(-(entry.price or 0)) then
        GodSystemApp.services.runtime.setPlayerTrait(entry.traitType, not enable)
        GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text("Notify_TraitFailed", "Trait modification failed"))
        return false
    end

    local data = GodSystemApp.services.runtime.getData()
    data.stats.spentPoints = (data.stats.spentPoints or 0) + (entry.price or 0)
    data.stats.modifiedTraits = (data.stats.modifiedTraits or 0) + 1
    local historyKey = enable and "History_TraitBought" or "History_TraitRemoved"
    local notifyKey = enable and "Notify_TraitBought" or "Notify_TraitRemoved"
    local riskText = entry.risk and (" | " .. GodSystemApp.services.runtime.text("Trait_RiskExperimental", "Risk")) or ""
    gsAppendHistory(data, { kind = "trait", text = GodSystemApp.services.runtime.text(historyKey, "Trait modified: ") .. tostring(entry.label) .. " -" .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins") .. riskText })
    GodSystemApp.services.runtime.save()
    GodSystemApp.services.runtime.notify(GodSystemApp.services.runtime.text(notifyKey, "Trait modified: ") .. tostring(entry.label) .. " -" .. tostring(entry.price or 0) .. GodSystemApp.services.runtime.text("Unit_Coin", " coins"))
    return true
end
end
