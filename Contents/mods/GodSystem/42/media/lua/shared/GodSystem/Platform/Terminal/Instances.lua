require "GodSystem/Platform/Terminal/Support"

GodSystemTerminalInstancesPlatform = GodSystemTerminalInstancesPlatform or {}

local Descriptor = GodSystemTerminalInstancesPlatform
local Support = GodSystemTerminalPlatformSupport

Descriptor.id = "terminal.instances"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

function Descriptor.create(_, context)
    context = context or {}
    local binding = Support.binding(context)
    local config = type(context.configSnapshot) == "table"
        and context.configSnapshot or {}
    local terminalFullType = tostring(config.AutoRecyclerFullType
        or "GodSystem.SystemSpaceTerminal")
    local reliefFullType = tostring(config.TerminalReliefFullType
        or "GodSystem.SystemTerminalRelief")
    local markerKey = tostring(config.AutoRecyclerMarkerKey
        or "GodSystemAutoRecycler")
    local capacityLevelKey = tostring(config.AutoRecyclerCapacityLevelKey
        or "GodSystemTerminalCapacityLevel")
    local reductionLevelKey = tostring(config.AutoRecyclerReductionLevelKey
        or "GodSystemTerminalReductionLevel")
    local reliefLevelKey = tostring(config.TerminalReliefLevelKey
        or "GodSystemTerminalReliefLevel")
    local reliefMarkerKey = tostring(config.TerminalReliefMarkerKey
        or "GodSystemTerminalRelief")
    local reliefOwnerKey = tostring(config.TerminalReliefOwnerKey
        or "GodSystemTerminalReliefOwner")
    local reliefOffsetKey = tostring(config.TerminalReliefOffsetKey
        or "GodSystemTerminalReliefOffset")
    local reliefVersionKey = tostring(config.TerminalReliefVersionKey
        or "GodSystemTerminalReliefVersion")
    local counters = {
        searches = 0, creates = 0, applies = 0, restores = 0,
        removals = 0, escapedRemoved = 0, failures = 0,
    }
    local public = {}

    local function isTerminal(item)
        return Support.fullType(item) == terminalFullType
    end

    local function isRelief(item)
        return Support.fullType(item) == reliefFullType
    end

    local function rootInventory(actor)
        return Support.read(actor, { "getInventory" }, nil)
    end

    local function candidateRows(actor)
        if type(binding.terminalCandidates) == "function" then
            local called, rows = pcall(binding.terminalCandidates, actor)
            if called and type(rows) == "table" then return rows end
        end
        local result, seen = {}, {}
        local root = rootInventory(actor)
        local function add(item, container)
            if item and not seen[item] and isTerminal(item) then
                seen[item] = true
                result[#result + 1] = { item = item, container = container }
            end
        end
        local function scan(container, depth, visited)
            if not container or visited[container] or depth > 32 then return end
            visited[container] = true
            local rows = Support.items(container)
            for index = 1, #rows do
                add(rows[index], container)
                scan(Support.child(rows[index]), depth + 1, visited)
            end
        end
        scan(root, 0, {})
        add(Support.read(actor, { "getPrimaryHandItem" }, nil), nil)
        add(Support.read(actor, { "getSecondaryHandItem" }, nil), nil)
        local worn = Support.values(Support.read(actor, { "getWornItems" }, nil))
        for index = 1, #worn do
            add(Support.read(worn[index], { "getItem" }, worn[index]), nil)
        end
        local attached = Support.values(Support.read(actor, { "getAttachedItems" }, nil))
        for index = 1, #attached do
            add(Support.read(attached[index], { "getItem" }, attached[index]), nil)
        end
        return result
    end

    local function reliefRows(inventory)
        local result = {}
        local rows = Support.items(inventory)
        for index = 1, #rows do
            if isRelief(rows[index]) then result[#result + 1] = rows[index] end
        end
        return result
    end

    local function readUnwanted(item, actor)
        local called, value = Support.call(item, "isUnwanted", actor)
        if called then return value == true end
        return Support.read(item, { "isUnwanted" }, false) == true
    end

    local function writeUnwanted(item, actor, value)
        local called = Support.call(item, "setUnwanted", actor, value)
        if called then return true end
        return Support.write(item, { "setUnwanted" }, value)
    end

    local function captureRelief(item, actor)
        local data = Support.modData(item) or {}
        return {
            item = item,
            actualWeight = Support.number(
                Support.read(item, { "getActualWeight" }, 0), 0),
            customWeight = Support.read(item, { "isCustomWeight" }, false) == true,
            hungChange = Support.number(
                Support.read(item, { "getHungChange" }, 0), 0),
            favorite = Support.read(item, { "isFavorite" }, false) == true,
            unwanted = readUnwanted(item, actor),
            marker = data[reliefMarkerKey],
            owner = data[reliefOwnerKey],
            level = data[reliefLevelKey],
            offset = data[reliefOffsetKey],
            version = data[reliefVersionKey],
        }
    end

    local function restoreReliefState(item, actor, state)
        local ok = true
        ok = Support.write(item, { "setActualWeight" }, state.actualWeight) and ok
        ok = Support.write(item, { "setCustomWeight" }, state.customWeight == true) and ok
        if item.setHungChange then
            ok = Support.write(item, { "setHungChange" }, state.hungChange or 0) and ok
        end
        ok = Support.write(item, { "setFavorite" }, state.favorite == true) and ok
        ok = writeUnwanted(item, actor, state.unwanted == true) and ok
        local data = Support.modData(item)
        if not data then return false end
        data[reliefMarkerKey] = state.marker
        data[reliefOwnerKey] = state.owner
        data[reliefLevelKey] = state.level
        data[reliefOffsetKey] = state.offset
        data[reliefVersionKey] = state.version
        return ok
    end

    local function configureRelief(item, terminal, actor, spec)
        local offset = math.max(0, Support.number(spec.reliefOffset, 0) or 0)
        local level = Support.integer(spec.reliefLevel, 0, 0)
        local ok = Support.write(item, { "setActualWeight" }, -offset)
        ok = Support.write(item, { "setCustomWeight" }, true) and ok
        if item.setHungChange then
            ok = Support.write(item, { "setHungChange" }, offset / 100) and ok
        end
        ok = Support.write(item, { "setFavorite" }, true) and ok
        ok = writeUnwanted(item, actor, true) and ok
        local data = Support.modData(item)
        if not data then return false, "modDataMissing" end
        data[reliefMarkerKey] = true
        data[reliefOwnerKey] = Support.itemId(terminal)
        data[reliefLevelKey] = level
        data[reliefOffsetKey] = offset
        data[reliefVersionKey] = 1
        local actual = Support.number(
            Support.read(item, { "getActualWeight" }, nil), nil)
        if not ok or actual == nil
            or math.abs(actual + offset) > math.max(0.0001, offset * 0.0001)
        then
            return false, "weightVerificationFailed"
        end
        if Support.read(item, { "isFavorite" }, false) ~= true
            or not readUnwanted(item, actor)
        then
            return false, "protectionVerificationFailed"
        end
        return true
    end

    local function terminalSnapshot(actor, terminal)
        local inventory = Support.read(terminal, { "getInventory" }, nil)
        if not inventory then return nil end
        local data = Support.modData(terminal) or {}
        local relief = {}
        local rows = reliefRows(inventory)
        for index = 1, #rows do
            relief[#relief + 1] = captureRelief(rows[index], actor)
        end
        return {
            terminal = terminal,
            inventory = inventory,
            outerCapacity = Support.number(
                Support.read(terminal, { "getCapacity" }, nil), nil),
            innerCapacity = Support.number(
                Support.read(inventory, { "getCapacity" }, nil), nil),
            outerReduction = Support.number(
                Support.read(terminal, { "getWeightReduction" }, nil), nil),
            innerReduction = Support.number(
                Support.read(inventory, { "getWeightReduction" }, nil), nil),
            marker = data[markerKey],
            capacityLevel = data[capacityLevelKey],
            reductionLevel = data[reductionLevelKey],
            reliefLevel = data[reliefLevelKey],
            name = Support.read(terminal, { "getName" }, nil),
            customName = Support.read(terminal, { "isCustomName" }, false) == true,
            relief = relief,
            actor = actor,
        }
    end

    local function restoreSnapshot(actor, terminal, snapshot)
        if type(snapshot) ~= "table"
            or snapshot.terminal ~= terminal
            or not snapshot.inventory
        then
            return false, "snapshotInvalid"
        end
        local ok = true
        local function restoreNumber(target, setter, getter, value)
            if value == nil then return end
            local written = Support.writeNumber(target, setter, getter, value)
            ok = written and ok
        end
        restoreNumber(terminal, "setCapacity", "getCapacity", snapshot.outerCapacity)
        restoreNumber(snapshot.inventory, "setCapacity", "getCapacity", snapshot.innerCapacity)
        restoreNumber(terminal, "setWeightReduction", "getWeightReduction", snapshot.outerReduction)
        restoreNumber(snapshot.inventory, "setWeightReduction", "getWeightReduction", snapshot.innerReduction)
        local expected = {}
        for index = 1, #(snapshot.relief or {}) do
            if snapshot.relief[index].item then expected[snapshot.relief[index].item] = true end
        end
        local current = reliefRows(snapshot.inventory)
        for index = #current, 1, -1 do
            if not expected[current[index]] then
                local removed = Support.remove(snapshot.inventory, current[index])
                if removed then Support.syncRemove(binding, snapshot.inventory, current[index]) end
                ok = removed and ok
            end
        end
        for index = 1, #(snapshot.relief or {}) do
            local state = snapshot.relief[index]
            local item = state.item
            if not Support.contains(snapshot.inventory, item) then
                item = Support.add(snapshot.inventory, item)
                    or Support.add(snapshot.inventory, reliefFullType)
                if item then Support.syncAdd(binding, snapshot.inventory, item) end
            end
            if not item or not restoreReliefState(item, actor or snapshot.actor, state) then
                ok = false
            end
        end
        local data = Support.modData(terminal)
        if not data then ok = false
        else
            data[markerKey] = snapshot.marker
            data[capacityLevelKey] = snapshot.capacityLevel
            data[reductionLevelKey] = snapshot.reductionLevel
            data[reliefLevelKey] = snapshot.reliefLevel
        end
        if snapshot.name ~= nil then
            ok = Support.write(terminal, { "setName" }, snapshot.name) and ok
            if terminal.setCustomName then
                ok = Support.write(terminal, { "setCustomName" },
                    snapshot.customName == true) and ok
            end
        end
        Support.write(snapshot.inventory, { "setDrawDirty" }, true)
        Support.write(terminal, { "transmitModData" })
        return ok, ok and nil or "restoreFailed"
    end

    function public.findOwned(actor, expectedId)
        counters.searches = counters.searches + 1
        expectedId = tostring(expectedId or "")
        local rows = candidateRows(actor)
        for index = 1, #rows do
            local item = rows[index].item
            if isTerminal(item) and Support.ownedBy(actor, item)
                and (expectedId == "" or Support.itemId(item) == expectedId)
            then
                return item
            end
        end
        return nil, "terminalMissing"
    end

    function public.create(actor, fullType)
        if tostring(fullType or "") ~= terminalFullType then
            return nil, "terminalTypeInvalid"
        end
        local inventory = rootInventory(actor)
        if not inventory then return nil, "inventoryMissing" end
        local item = Support.add(inventory, terminalFullType)
        if not item then counters.failures = counters.failures + 1; return nil, "createFailed" end
        if not Support.syncAdd(binding, inventory, item) then
            Support.remove(inventory, item)
            counters.failures = counters.failures + 1
            return nil, "syncFailed"
        end
        counters.creates = counters.creates + 1
        return item
    end

    function public.remove(actor, item)
        if not item or not isTerminal(item) or not Support.ownedBy(actor, item) then
            return false, "terminalMissing"
        end
        local container = Support.read(item, { "getContainer" }, nil)
        if not container or not Support.remove(container, item) then
            return false, "removeFailed"
        end
        if not Support.syncRemove(binding, container, item) then
            Support.add(container, item)
            return false, "syncFailed"
        end
        counters.removals = counters.removals + 1
        return true
    end

    function public.snapshot(actor, item)
        if not item or not isTerminal(item) or not Support.ownedBy(actor, item) then
            return nil, "terminalMissing"
        end
        return terminalSnapshot(actor, item)
    end

    function public.apply(actor, terminal, spec)
        if not terminal or not isTerminal(terminal)
            or not Support.ownedBy(actor, terminal)
            or type(spec) ~= "table"
        then
            return false, "terminalMissing"
        end
        local inventory = Support.read(terminal, { "getInventory" }, nil)
        if not inventory then return false, "inventoryMissing" end
        local ok, reason = Support.writeNumber(
            terminal, "setCapacity", "getCapacity", spec.capacity)
        if not ok then return false, "capacityWriteFailed", { reason = reason } end
        ok, reason = Support.writeNumber(
            inventory, "setCapacity", "getCapacity", spec.capacity)
        if not ok then return false, "capacityWriteFailed", { reason = reason } end
        ok, reason = Support.writeNumber(
            terminal, "setWeightReduction", "getWeightReduction", spec.reduction)
        if not ok then return false, "reductionWriteFailed", { reason = reason } end
        ok, reason = Support.writeNumber(
            inventory, "setWeightReduction", "getWeightReduction", spec.reduction)
        if not ok then return false, "reductionWriteFailed", { reason = reason } end

        local data = Support.modData(terminal)
        if not data then return false, "modDataMissing" end
        data[markerKey] = true
        data[capacityLevelKey] = Support.integer(spec.capacityLevel, 1, 1, 8)
        data[reductionLevelKey] = Support.integer(spec.reductionLevel, 1, 1, 8)
        data[reliefLevelKey] = Support.integer(spec.reliefLevel, 0, 0, 400)

        local added, removed = {}, {}
        local relief = reliefRows(inventory)
        if Support.number(spec.reliefOffset, 0) <= 0 then
            for index = #relief, 1, -1 do
                if not Support.remove(inventory, relief[index]) then
                    return false, "reliefRemoveFailed"
                end
                Support.syncRemove(binding, inventory, relief[index])
                removed[#removed + 1] = relief[index]
            end
        else
            local item = relief[1]
            if not item then
                item = Support.add(inventory, reliefFullType)
                if not item then return false, "reliefCreateFailed" end
                if not Support.syncAdd(binding, inventory, item) then
                    Support.remove(inventory, item)
                    return false, "reliefSyncFailed"
                end
                added[#added + 1] = item
            end
            for index = #relief, 2, -1 do
                if not Support.remove(inventory, relief[index]) then
                    return false, "reliefDuplicateRemoveFailed"
                end
                Support.syncRemove(binding, inventory, relief[index])
                removed[#removed + 1] = relief[index]
            end
            local configured, configureReason = configureRelief(
                item, terminal, actor, spec)
            if not configured then return false, configureReason end
        end
        local displayName = tostring(config.TerminalDisplayName or "System Space Terminal")
            .. " Lv." .. tostring(Support.integer(spec.capacityLevel, 1, 1, 8))
        Support.write(terminal, { "setName" }, displayName)
        if terminal.setCustomName then Support.write(terminal, { "setCustomName" }, true) end
        Support.write(inventory, { "setDrawDirty" }, true)
        Support.write(terminal, { "transmitModData" })
        counters.applies = counters.applies + 1
        return true, nil, {
            capacity = spec.capacity,
            reduction = spec.reduction,
            reliefLevel = spec.reliefLevel,
            reliefOffset = spec.reliefOffset,
            addedItems = added,
            removedItems = removed,
            inventory = inventory,
            terminalChanged = true,
        }
    end

    function public.restore(actor, item, snapshot)
        local ok, reason = restoreSnapshot(actor, item, snapshot)
        if ok then counters.restores = counters.restores + 1
        else counters.failures = counters.failures + 1 end
        return ok, reason
    end

    function public.cleanupEscapedRelief(actor, ownedTerminal)
        local root = rootInventory(actor)
        if not root then return 0 end
        local allowed = ownedTerminal
            and Support.read(ownedTerminal, { "getInventory" }, nil) or nil
        local removed, seen = 0, {}
        local function scan(container, depth)
            if not container or seen[container] or depth > 32 then return end
            seen[container] = true
            local rows = Support.items(container)
            for index = #rows, 1, -1 do
                local item = rows[index]
                if isRelief(item) and container ~= allowed then
                    if Support.remove(container, item) then
                        Support.syncRemove(binding, container, item)
                        removed = removed + 1
                    end
                else
                    scan(Support.child(item), depth + 1)
                end
            end
        end
        scan(root, 0)
        counters.escapedRemoved = counters.escapedRemoved + removed
        return removed
    end

    function public.inspect(actor, terminal, expected)
        if not terminal or not isTerminal(terminal)
            or not Support.ownedBy(actor, terminal)
        then
            return nil, "terminalMissing"
        end
        local inventory = Support.read(terminal, { "getInventory" }, nil)
        local relief = reliefRows(inventory)
        local actualRelief = #relief == 1 and -(
            Support.number(Support.read(relief[1], { "getActualWeight" }, 0), 0) or 0) or 0
        local outerCapacity = Support.number(
            Support.read(terminal, { "getCapacity" }, nil), nil)
        local innerCapacity = Support.number(
            Support.read(inventory, { "getCapacity" }, nil), nil)
        local outerReduction = Support.number(
            Support.read(terminal, { "getWeightReduction" }, nil), nil)
        local innerReduction = Support.number(
            Support.read(inventory, { "getWeightReduction" }, nil), nil)
        return {
            expectedCapacity = expected.capacity,
            expectedReduction = expected.reduction,
            expectedRelief = expected.reliefOffset,
            outerCapacity = outerCapacity,
            innerCapacity = innerCapacity,
            outerReduction = outerReduction,
            innerReduction = innerReduction,
            actualRelief = actualRelief,
            reliefItemCount = #relief,
            capacityApplied = outerCapacity == expected.capacity
                and innerCapacity == expected.capacity,
            reductionApplied = outerReduction == expected.reduction
                and innerReduction == expected.reduction,
            reliefApplied = expected.reliefOffset <= 0 and #relief == 0
                or (#relief == 1 and math.abs(actualRelief - expected.reliefOffset) <= 0.05),
        }
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
