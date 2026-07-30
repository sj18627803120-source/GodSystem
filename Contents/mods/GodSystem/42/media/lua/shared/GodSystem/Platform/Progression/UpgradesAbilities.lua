require "GodSystem/Platform/Progression/Support"

GodSystemUpgradesAbilitiesPlatform = GodSystemUpgradesAbilitiesPlatform or {}

local Descriptor = GodSystemUpgradesAbilitiesPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "upgrades.abilities"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local DEFAULTS = {
    CarryCapacityPerLevel = 2,
    TerminalCapacityLevels = {
        { level = 1, value = 10 }, { level = 2, value = 15 },
        { level = 3, value = 20 }, { level = 4, value = 25 },
        { level = 5, value = 30 }, { level = 6, value = 35 },
        { level = 7, value = 42 }, { level = 8, value = 49 },
    },
    TerminalReductionLevels = {
        { level = 1, value = 50 }, { level = 2, value = 55 },
        { level = 3, value = 60 }, { level = 4, value = 65 },
        { level = 5, value = 70 }, { level = 6, value = 80 },
        { level = 7, value = 90 }, { level = 8, value = 99 },
    },
    TerminalReliefFullType = "GodSystem.SystemTerminalRelief",
    TerminalReliefPerLevel = 5,
    TerminalReliefMaxOffset = 2000,
    TerminalCapacityLevelKey = "GodSystemTerminalCapacityLevel",
    TerminalReductionLevelKey = "GodSystemTerminalReductionLevel",
    TerminalReliefLevelKey = "GodSystemTerminalReliefLevel",
    TerminalReliefItemMarkerKey = "GodSystemTerminalRelief",
    TerminalReliefOwnerKey = "GodSystemTerminalReliefOwner",
    TerminalReliefOffsetKey = "GodSystemTerminalReliefOffset",
    TerminalReliefVersionKey = "GodSystemTerminalReliefVersion",
}

local CARRY_KEYS = {
    bonus = "GodSystemCarryAppliedBonus",
    delta = "GodSystemCarryAppliedDelta",
    factor = "GodSystemCarryAppliedFactor",
    baseline = "GodSystemCarryBaseline",
}

local function terminalInventory(terminal)
    local ok, inventory = Support.call(terminal, "getInventory")
    return ok and inventory or nil
end

local function contains(inventory, wanted)
    local items = Support.values(Support.read(inventory, { "getItems" }, nil))
    for index = 1, #items do
        if items[index] == wanted then return true end
    end
    return false
end

local function removeItem(inventory, item)
    if not item or not Support.write(inventory, { "Remove" }, item) then return false end
    return not contains(inventory, item)
end

local function addItem(inventory, value)
    local ok, item = Support.call(inventory, "AddItem", value)
    return ok and item or nil
end

local function itemType(item)
    return tostring(Support.read(item, { "getFullType" }, "") or "")
end

local function itemId(item)
    local value = Support.read(item, { "getID" }, nil)
    return value ~= nil and tostring(value) or ""
end

local function replaceTable(target, source)
    if type(target) ~= "table" then return false end
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source or {}) do target[key] = Support.copy(value) end
    return true
end

function Descriptor.create(_, context)
    local config, binding = Support.config(context, DEFAULTS)
    local counters = { snapshots = 0, applies = 0, restores = 0, failures = 0 }
    local public = {}

    local function resolveTerminal(actor, request)
        if type(request) == "table" and request.terminal then return request.terminal end
        if type(binding.resolveTerminal) == "function" then
            local ok, terminal = pcall(binding.resolveTerminal, actor, request)
            if ok then return terminal end
        end
        return nil
    end

    local function syncTerminal(actor, terminal, report, request)
        if type(binding.syncTerminal) == "function" then
            local ok, synced = pcall(binding.syncTerminal, actor, terminal, report, request)
            return ok and synced ~= false
        end
        if terminal and type(terminal.syncItemFields) == "function" then pcall(terminal.syncItemFields, terminal) end
        if terminal and type(terminal.transmitModData) == "function" then pcall(terminal.transmitModData, terminal) end
        for index = 1, #((report and report.items) or {}) do
            local item = report.items[index]
            if item and type(item.syncItemFields) == "function" then pcall(item.syncItemFields, item) end
            if item and type(item.transmitModData) == "function" then pcall(item.transmitModData, item) end
        end
        return true
    end

    local function carrySnapshot(actor)
        local delta = Support.number(Support.read(actor, { "getMaxWeightDelta" }, nil), nil)
        local base = Support.number(Support.read(actor, { "getMaxWeightBase" }, nil), nil, 0.0001)
        local final = Support.number(Support.read(actor, { "getMaxWeight" }, nil), nil, 0)
        if delta == nil or base == nil or final == nil then return nil, "carryUnsupported" end
        local markers, data = {}, Support.modData(actor)
        for name, key in pairs(CARRY_KEYS) do markers[name] = data and data[key] or nil end
        return { kind = "carryCapacity", actor = actor, delta = delta, base = base, final = final, markers = markers }
    end

    local function restoreCarry(snapshot)
        local actor = snapshot and snapshot.actor
        if not actor then return false end
        local deltaOk = Support.write(actor, { "setMaxWeightDelta" }, snapshot.delta)
        local finalOk = Support.write(actor, { "setMaxWeight" }, snapshot.final)
        local data = Support.modData(actor)
        if data then
            for name, key in pairs(CARRY_KEYS) do data[key] = snapshot.markers and snapshot.markers[name] or nil end
        end
        local delta = Support.number(Support.read(actor, { "getMaxWeightDelta" }, nil), nil)
        local final = Support.number(Support.read(actor, { "getMaxWeight" }, nil), nil)
        return deltaOk and finalOk and delta ~= nil and final ~= nil
            and math.abs(delta - snapshot.delta) <= 0.001 and math.abs(final - snapshot.final) <= 0.01
    end

    local function applyCarry(actor, level)
        level = Support.integer(level, nil, 0)
        local perLevel = Support.number(config.CarryCapacityPerLevel, nil, 0)
        local current = Support.number(Support.read(actor, { "getMaxWeightDelta" }, nil), nil)
        local base = Support.number(Support.read(actor, { "getMaxWeightBase" }, nil), nil, 0.0001)
        local currentFinal = Support.number(Support.read(actor, { "getMaxWeight" }, nil), nil, 0)
        if level == nil or perLevel == nil or current == nil or base == nil or currentFinal == nil then
            return false, "carryUnsupported"
        end
        local bonus = level * perLevel
        if not Support.finite(bonus) or bonus > 9007199254740991 then return false, "carryOverflow" end
        local data = Support.modData(actor)
        local previousFactor = data and Support.number(data[CARRY_KEYS.factor], 0) or 0
        local previousDelta = data and Support.number(data[CARRY_KEYS.delta], nil) or nil
        if previousDelta == nil or math.abs(previousDelta - current) > 0.001 then previousFactor = 0 end
        local externalDelta = current - previousFactor
        local factor = bonus / base
        local targetDelta = externalDelta + factor
        local baseline = math.max(0, math.floor(base * (1 + externalDelta) + 0.001))
        local targetFinal = baseline + bonus
        if not Support.finite(targetDelta) or not Support.finite(targetFinal)
            or targetFinal > 9007199254740991 then return false, "carryOverflow" end
        if not Support.write(actor, { "setMaxWeightDelta" }, targetDelta) then return false, "carryWriteFailed" end
        if not Support.write(actor, { "setMaxWeight" }, targetFinal) then return false, "carryWriteFailed" end
        local afterDelta = Support.number(Support.read(actor, { "getMaxWeightDelta" }, nil), nil)
        local afterFinal = Support.number(Support.read(actor, { "getMaxWeight" }, nil), nil)
        if afterDelta == nil or afterFinal == nil or math.abs(afterDelta - targetDelta) > 0.001
            or math.abs(afterFinal - targetFinal) > 0.01 then return false, "carryVerificationFailed" end
        if data then
            data[CARRY_KEYS.bonus] = bonus
            data[CARRY_KEYS.delta] = afterDelta
            data[CARRY_KEYS.factor] = factor
            data[CARRY_KEYS.baseline] = baseline
        end
        return true, { level = level, bonus = bonus, base = baseline, total = afterFinal }
    end

    local function reliefItems(inventory)
        local result = {}
        local fullType = tostring(config.TerminalReliefFullType or "")
        local items = Support.values(Support.read(inventory, { "getItems" }, nil))
        for index = 1, #items do
            if itemType(items[index]) == fullType then result[#result + 1] = items[index] end
        end
        return result
    end

    local function captureRelief(item, actor)
        return {
            item = item,
            fullType = itemType(item),
            hungChange = Support.number(Support.read(item, { "getHungChange" }, nil), nil),
            favorite = Support.read(item, { "isFavorite" }, nil),
            unwanted = actor and Support.read(item, { "isUnwanted" }, nil, actor) or nil,
            modData = Support.copy(Support.modData(item) or {}),
        }
    end

    local function terminalSnapshot(actor, terminal)
        local inventory = terminalInventory(terminal)
        if not terminal or not inventory then return nil, "terminalMissing" end
        local states = {}
        local items = reliefItems(inventory)
        for index = 1, #items do states[index] = captureRelief(items[index], actor) end
        return {
            kind = "terminal",
            actor = actor,
            terminal = terminal,
            inventory = inventory,
            outerCapacity = Support.number(Support.read(terminal, { "getCapacity" }, nil), nil),
            innerCapacity = Support.number(Support.read(inventory, { "getCapacity" }, nil), nil),
            outerReduction = Support.number(Support.read(terminal, { "getWeightReduction" }, nil), nil),
            innerReduction = Support.number(Support.read(inventory, { "getWeightReduction" }, nil), nil),
            terminalData = Support.copy(Support.modData(terminal) or {}),
            relief = states,
        }
    end

    local function restoreReliefState(item, state, actor)
        local ok = true
        if state.hungChange ~= nil then ok = Support.write(item, { "setHungChange" }, state.hungChange) and ok end
        if state.favorite ~= nil then ok = Support.write(item, { "setFavorite" }, state.favorite == true) and ok end
        if state.unwanted ~= nil and actor then
            ok = Support.write(item, { "setUnwanted" }, actor, state.unwanted == true) and ok
        end
        if Support.modData(item) then ok = replaceTable(Support.modData(item), state.modData) and ok end
        return ok
    end

    local function restoreTerminal(snapshot, request)
        if type(snapshot) ~= "table" or not snapshot.terminal or not snapshot.inventory then return false end
        local ok = true
        local function restoreNumber(target, setter, getter, value)
            if value ~= nil then
                local restored = Support.writeNumber(target, setter, getter, value)
                ok = restored and ok
            end
        end
        restoreNumber(snapshot.terminal, "setCapacity", "getCapacity", snapshot.outerCapacity)
        restoreNumber(snapshot.inventory, "setCapacity", "getCapacity", snapshot.innerCapacity)
        restoreNumber(snapshot.terminal, "setWeightReduction", "getWeightReduction", snapshot.outerReduction)
        restoreNumber(snapshot.inventory, "setWeightReduction", "getWeightReduction", snapshot.innerReduction)
        local expected = {}
        for index = 1, #(snapshot.relief or {}) do expected[snapshot.relief[index].item] = true end
        local current = reliefItems(snapshot.inventory)
        for index = #current, 1, -1 do
            if not expected[current[index]] then ok = removeItem(snapshot.inventory, current[index]) and ok end
        end
        local syncedItems = {}
        for index = 1, #(snapshot.relief or {}) do
            local state = snapshot.relief[index]
            local item = state.item
            if not contains(snapshot.inventory, item) then
                item = addItem(snapshot.inventory, item) or addItem(snapshot.inventory, state.fullType)
            end
            ok = item ~= nil and restoreReliefState(item, state, snapshot.actor) and ok
            if item then syncedItems[#syncedItems + 1] = item end
        end
        if Support.modData(snapshot.terminal) then
            ok = replaceTable(Support.modData(snapshot.terminal), snapshot.terminalData) and ok
        end
        syncTerminal(snapshot.actor, snapshot.terminal, { items = syncedItems }, request)
        return ok
    end

    local function applyCapacity(terminal, inventory, level)
        local row = type(config.TerminalCapacityLevels) == "table" and config.TerminalCapacityLevels[level] or nil
        local value = row and Support.number(row.value, nil, 0) or nil
        if value == nil then return false, "terminalLevelInvalid" end
        local outer = Support.writeNumber(terminal, "setCapacity", "getCapacity", value)
        local inner = Support.writeNumber(inventory, "setCapacity", "getCapacity", value)
        if not outer or not inner then return false, "terminalCapacityFailed" end
        local data = Support.modData(terminal)
        if data then data[tostring(config.TerminalCapacityLevelKey)] = level end
        return true, { capacity = value, items = {} }
    end

    local function applyReduction(terminal, inventory, level)
        local row = type(config.TerminalReductionLevels) == "table" and config.TerminalReductionLevels[level] or nil
        local value = row and Support.number(row.value, nil, 0, 100) or nil
        if value == nil then return false, "terminalLevelInvalid" end
        local outer = Support.writeNumber(terminal, "setWeightReduction", "getWeightReduction", value)
        local inner = Support.writeNumber(inventory, "setWeightReduction", "getWeightReduction", value)
        if not outer or not inner then return false, "terminalReductionFailed" end
        local data = Support.modData(terminal)
        if data then data[tostring(config.TerminalReductionLevelKey)] = level end
        return true, { reduction = value, items = {} }
    end

    local function applyRelief(actor, terminal, inventory, level)
        local perLevel = Support.integer(config.TerminalReliefPerLevel, 5, 1)
        local maximum = Support.integer(config.TerminalReliefMaxOffset, 2000, 0)
        local offset = math.min(maximum, level * perLevel)
        local items = reliefItems(inventory)
        local report = { offset = offset, items = {} }
        if offset <= 0 then
            for index = #items, 1, -1 do
                if not removeItem(inventory, items[index]) then return false, "terminalReliefRemoveFailed" end
            end
        else
            local item = items[1] or addItem(inventory, tostring(config.TerminalReliefFullType))
            if not item then return false, "terminalReliefCreateFailed" end
            for index = #items, 2, -1 do
                if not removeItem(inventory, items[index]) then return false, "terminalReliefRemoveFailed" end
            end
            if not Support.write(item, { "setHungChange" }, offset / 100) then
                return false, "terminalReliefUnsupported"
            end
            if type(item.setFavorite) == "function" then Support.write(item, { "setFavorite" }, true) end
            if actor and type(item.setUnwanted) == "function" then
                Support.write(item, { "setUnwanted" }, actor, true)
            end
            local data = Support.modData(item)
            if not data then return false, "terminalReliefDataMissing" end
            data[tostring(config.TerminalReliefItemMarkerKey)] = true
            data[tostring(config.TerminalReliefOwnerKey)] = itemId(terminal)
            data[tostring(config.TerminalReliefLevelKey)] = level
            data[tostring(config.TerminalReliefOffsetKey)] = offset
            data[tostring(config.TerminalReliefVersionKey)] = 1
            local actual = Support.number(Support.read(item, { "getActualWeight" }, nil), nil)
            if actual == nil or math.abs(actual + offset) > math.max(0.05, offset * 0.0001) then
                return false, "terminalReliefVerificationFailed"
            end
            report.items[1] = item
        end
        local terminalData = Support.modData(terminal)
        if terminalData then terminalData[tostring(config.TerminalReliefLevelKey)] = level end
        return true, report
    end

    function public.snapshot(actor, upgradeType, _, _, request)
        counters.snapshots = counters.snapshots + 1
        if upgradeType == "carryCapacity" then return carrySnapshot(actor) end
        if upgradeType == "terminalCapacity" or upgradeType == "terminalReduction"
            or upgradeType == "terminalRelief" then
            return terminalSnapshot(actor, resolveTerminal(actor, request))
        end
        return { kind = tostring(upgradeType or "") }
    end

    function public.apply(actor, upgradeType, level, _, request)
        counters.applies = counters.applies + 1
        if upgradeType == "carryCapacity" then return applyCarry(actor, level) end
        local terminal = resolveTerminal(actor, request)
        local inventory = terminalInventory(terminal)
        level = Support.integer(level, nil, 0)
        if not terminal or not inventory then return false, "terminalMissing" end
        if level == nil then return false, "terminalLevelInvalid" end
        local ok, reportOrCode
        if upgradeType == "terminalCapacity" then
            ok, reportOrCode = applyCapacity(terminal, inventory, level)
        elseif upgradeType == "terminalReduction" then
            ok, reportOrCode = applyReduction(terminal, inventory, level)
        elseif upgradeType == "terminalRelief" then
            ok, reportOrCode = applyRelief(actor, terminal, inventory, level)
        else
            return false, "abilityUnsupported"
        end
        if ok then syncTerminal(actor, terminal, reportOrCode, request) end
        return ok, reportOrCode
    end

    function public.restore(_, _, snapshot, request)
        counters.restores = counters.restores + 1
        local ok
        if snapshot and snapshot.kind == "carryCapacity" then
            ok = restoreCarry(snapshot)
        elseif snapshot and snapshot.kind == "terminal" then
            ok = restoreTerminal(snapshot, request)
        else
            ok = true
        end
        if not ok then counters.failures = counters.failures + 1 end
        return ok
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
