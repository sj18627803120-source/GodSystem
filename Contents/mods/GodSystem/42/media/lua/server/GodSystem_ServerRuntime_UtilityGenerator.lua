_G.GodSystemServerRuntimeInstallers = _G.GodSystemServerRuntimeInstallers or {}
GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_UtilityGenerator"] = function(runtimeEnvironment)
    if runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_UtilityGenerator then return end
    runtimeEnvironment.__GodSystemInstalled_GodSystem_ServerRuntime_UtilityGenerator = true
    setfenv(1, runtimeEnvironment)

local Utility = GodSystemUtilityGenerator
local function cell()
    if getCell then return getCell() end
    local world = getWorld and getWorld() or nil
    return world and GodSystemB42JavaCalls.value(world, "getCell", nil) or nil
end

local function squareAt(x, y, z)
    if not x or not y or not z then return nil end
    local currentCell = cell()
    return currentCell and GodSystemB42JavaCalls.value(currentCell, "getGridSquare", nil,
        math.floor(tonumber(x) or -999999), math.floor(tonumber(y) or -999999), math.floor(tonumber(z) or -999999)) or nil
end

local function generatorAt(square, deviceId)
    if not square then return nil end
    local candidate = GodSystemB42JavaCalls.value(square, "getGenerator", nil)
    if candidate and Utility.deviceId(candidate) == tostring(deviceId or "") then return candidate end
    local collections = {
        GodSystemB42JavaCalls.value(square, "getSpecialObjects", nil),
        GodSystemB42JavaCalls.value(square, "getObjects", nil),
    }
    for collectionIndex = 1, 2 do
        local list = collections[collectionIndex]
        local count = math.max(0, math.floor(tonumber(GodSystemB42JavaCalls.value(list, "size", 0)) or 0))
        for i = 0, count - 1 do
            candidate = GodSystemB42JavaCalls.value(list, "get", nil, i)
            if candidate and Utility.deviceId(candidate) == tostring(deviceId or "") then return candidate end
        end
    end
    return nil
end

local function fixtureAt(record, deviceId)
    local square = squareAt(record and record.x, record and record.y, record and record.z)
    if not square then return nil end
    local list = GodSystemB42JavaCalls.value(square, "getObjects", nil)
    local count = math.max(0, math.floor(tonumber(GodSystemB42JavaCalls.value(list, "size", 0)) or 0))
    for i = 0, count - 1 do
        local object = GodSystemB42JavaCalls.value(list, "get", nil, i)
        local modData = object and GodSystemB42JavaCalls.value(object, "getModData", nil) or nil
        if type(modData) == "table" and tostring(modData[Utility.WaterMarker] or "") == tostring(deviceId or "") then
            return object
        end
    end
    return nil
end

local function findDevice(deviceId, x, y, z)
    local root = Utility.worldData()
    local row = Utility.ensureDevice(root, deviceId)
    if not row or not row.placed or not row.x or not row.y or not row.z then return nil end
    if x ~= nil and (math.floor(tonumber(x) or -999999) ~= math.floor(row.x)
        or math.floor(tonumber(y) or -999999) ~= math.floor(row.y)
        or math.floor(tonumber(z) or -999999) ~= math.floor(row.z)) then return nil end
    return generatorAt(squareAt(row.x, row.y, row.z), deviceId)
end

local function getEnv(player)
    local root = Utility.worldData()
    return {
        root = root,
        square = squareAt,
        findItem = inventoryItemById,
        removeItem = function(target, item, container)
            local removed = removeItemFromContainer(container, item)
            if removed then markInventoryDirty(target, container) end
            return removed
        end,
        createGenerator = function(sourceItem, id, square)
            if not IsoGenerator or not IsoGenerator.new or not instanceItem then return false, nil end
            local placedItem = instanceItem(Utility.FullType)
            if not placedItem then return false, nil end
            local condition = GodSystemB42JavaCalls.value(sourceItem, "getCondition", 100)
            pcall(function() placedItem:setCondition(condition) end)
            local itemData = GodSystemB42JavaCalls.value(placedItem, "getModData", nil)
            if type(itemData) ~= "table" then return false, nil end
            itemData[Utility.ItemMarker] = tostring(id)
            itemData.fuel = 0
            local created, generator = pcall(function() return IsoGenerator.new(placedItem, cell(), square) end)
            if not created or not generator then return false, nil end
            local modData = GodSystemB42JavaCalls.value(generator, "getModData", nil)
            if type(modData) ~= "table" then
                pcall(function() generator:remove() end)
                return false, nil
            end
            modData[Utility.ObjectMarker] = tostring(id)
            local fuelSet = GodSystemB42JavaCalls.try(generator, "setFuel", 0)
            local activationSet = GodSystemB42JavaCalls.try(generator, "setActivated", false)
            local connectionSet = GodSystemB42JavaCalls.try(generator, "setConnected", true)
            GodSystemB42JavaCalls.try(generator, "transmitModData")
            local transmitSet = GodSystemB42JavaCalls.try(generator, "transmitCompleteItemToClients")
            if not fuelSet or not activationSet or not connectionSet or not transmitSet
                or Utility.deviceId(generator) ~= tostring(id) then
                pcall(function() generator:remove() end)
                return false, nil
            end
            return true, generator
        end,
        removeGenerator = function(generator)
            if not generator then return false end
            GodSystemB42JavaCalls.try(generator, "setActivated", false)
            GodSystemB42JavaCalls.try(generator, "setFuel", 0)
            local removed = GodSystemB42JavaCalls.try(generator, "remove")
            if not removed then
                local square = GodSystemB42JavaCalls.value(generator, "getSquare", nil)
                if square then GodSystemB42JavaCalls.try(square, "transmitRemoveItemFromSquare", generator) end
            end
            return true
        end,
        findDevice = findDevice,
        spendCurrency = function(target, amount)
            local data = playerData(target)
            return spendCurrency(target, data, amount)
        end,
        repair = function(target, generator, scrap, container)
            if GodSystemB42JavaCalls.value(generator, "isActivated", false) == true then return false end
            if not removeItemFromContainer(container, scrap) then return false end
            markInventoryDirty(target, container)
            local condition = tonumber(GodSystemB42JavaCalls.value(generator, "getCondition", 0)) or 0
            local level = tonumber(GodSystemB42JavaCalls.value(target, "getPerkLevel", 0, Perks and Perks.Electricity or "Electricity")) or 0
            local repaired = GodSystemB42JavaCalls.try(generator, "setCondition", math.min(100, condition + 4 + level / 2))
            if not repaired then
                giveItem(target, "Base.ElectronicsScrap", 1)
                return false
            end
            if type(addXp) == "function" and Perks and Perks.Electricity then pcall(addXp, target, Perks.Electricity, 5) end
            GodSystemB42JavaCalls.try(generator, "sync")
            return true
        end,
        pickup = function(target, generator, id)
            local inventory = target and target:getInventory() or nil
            if not inventory or not instanceItem then return false, nil end
            local item = instanceItem(Utility.FullType)
            if not item then return false, nil end
            local itemData = GodSystemB42JavaCalls.value(item, "getModData", nil)
            if type(itemData) ~= "table" then return false, nil end
            itemData[Utility.ItemMarker] = tostring(id)
            local condition = GodSystemB42JavaCalls.value(generator, "getCondition", 100)
            pcall(function() item:setCondition(condition) end)
            itemData.fuel = 0
            local addedOk, added = pcall(function() return inventory:AddItem(item) end)
            if not addedOk or not added then return false, nil end
            if sendAddItemToContainer then pcall(sendAddItemToContainer, inventory, item) end
            local removed = GodSystemB42JavaCalls.try(generator, "remove")
            if not removed then
                pcall(function() inventory:Remove(item) end)
                if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, inventory, item) end
                return false, nil
            end
            markInventoryDirty(target, inventory)
            return true, item
        end,
        cleanupWater = function(id, generator, row)
            local pending, processed = false, 0
            for key, record in pairs(row.waterFixtures or {}) do
                if processed >= 32 then pending = true; break end
                processed = processed + 1
                local object = fixtureAt(record, id)
                if object then
                    local data = GodSystemB42JavaCalls.value(object, "getModData", nil)
                    local container = GodSystemB42JavaCalls.value(object, "getFluidContainer", nil)
                    if not Utility.releaseWaterFixture(root, row, object, key, data, container) then pending = true end
                else
                    local square = squareAt(record.x, record.y, record.z)
                    if square then
                        row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0)
                            - math.max(0, math.floor(tonumber(record.paidCents) or 0)))
                        row.waterFixtures[key] = nil
                    else
                        pending = true
                    end
                end
            end
            return not pending and Utility.tableCount(row.waterFixtures) == 0
        end,
        persist = function() return storeCheckpoint() end,
    }
end

local function sendUtilityStatus(player, args)
    local id = tostring(args and args.deviceId or "")
    local root = Utility.worldData()
    local row = Utility.ensureDevice(root, id)
    local generator = row and findDevice(id, args and args.x, args and args.y, args and args.z) or nil
    local square = generator and GodSystemB42JavaCalls.value(generator, "getSquare", nil) or nil
    local x, y, z = square and GodSystemB42JavaCalls.value(square, "getX", nil),
        square and GodSystemB42JavaCalls.value(square, "getY", nil), square and GodSystemB42JavaCalls.value(square, "getZ", nil)
    if not row or not generator or not x or not Utility.playerNear(player, x, y, z, 4) then
        sendServerCommand(player, MODULE, Protocol.S2C.UtilityGeneratorStatus, { ok = false, code = "UtilityGeneratorUnavailable" })
        return
    end
    sendServerCommand(player, MODULE, Protocol.S2C.UtilityGeneratorStatus, {
        ok = true, status = Utility.status(root, row, generator),
    })
end

function Commands.utilityGeneratorStatus(_, _, player, args)
    if not player then return end
    sendUtilityStatus(player, args)
end

function Commands.utilityGenerator(_, _, player, args)
    args = type(args) == "table" and args or {}
    local txKind, txRoot, txOwner = "utilityGenerator", store(), userKey(player)
    local cached = GodSystemTransactionOps.get(txRoot, txOwner, txKind, args)
    if cached then
        local status = tostring(cached.status or "")
        if status == "invalid" or status == "mismatch" then return finishCode(player, false, "TransactionOperationInvalid") end
        if status == "processing" then return finishCode(player, false, "TransactionOperationPending", {}, { opId = args.opId }) end
        if status == "unknown" then return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args.opId }) end
        if status == "done" then
            local payload = type(cached.payload) == "table" and cached.payload or {}
            payload.opId = args.opId
            return finishCode(player, cached.ok == true, cached.code, cached.args, payload)
        end
    end
    if not guard(player) then return end
    if not GodSystemTransactionOps.begin(txRoot, txOwner, txKind, args) then
        unguard(player)
        return finishCode(player, false, "TransactionOperationPending", {}, { opId = args.opId })
    end
    if not storeCheckpoint() then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        unguard(player)
        return finishCode(player, false, "TransactionOperationUnknown", {}, { opId = args.opId })
    end
    local success, code, payload
    local ok, err = pcall(function()
        success, code, payload = Utility.execute(player, args, getEnv(player))
        payload = type(payload) == "table" and payload or {}
        payload.opId = args.opId
        GodSystemTransactionOps.remember(txRoot, txOwner, txKind, args, success, code, {}, payload)
        finishCode(player, success, code, {}, payload)
    end)
    unguard(player)
    if not ok then
        GodSystemTransactionOps.markUnknown(txRoot, txOwner, txKind, args)
        errorMessage(player, tostring(err))
    end
end

local lastUtilityTick = 0
local function utilityGeneratorTick()
    local now = GodSystemScheduler.nowMs()
    if now - lastUtilityTick < 1000 and not Utility.hasPendingWork(now) then return end
    if now - lastUtilityTick >= 1000 then lastUtilityTick = now end
    local root = Utility.worldData()
    Utility.tick(root, {
        square = squareAt,
        findDevice = findDevice,
        fixture = fixtureAt,
        persist = function() return storeCheckpoint() end,
    }, now)
end

Events.OnTick.Add(utilityGeneratorTick)
if Events.OnObjectAdded then
    Events.OnObjectAdded.Add(function(object)
        Utility.onObjectAdded(Utility.worldData(), object, { square = squareAt, authoritative = true })
    end)
end
if Events.OnLoadGridsquare then
    Events.OnLoadGridsquare.Add(function(square)
        Utility.onSquareLoaded(Utility.worldData(), square)
    end)
end
if Events.OnWaterAmountChange then
    Events.OnWaterAmountChange.Add(function(object)
        local data = GodSystemB42JavaCalls.value(object, "getModData", nil)
        local id = type(data) == "table" and tostring(data[Utility.GhostMarker] or data[Utility.TargetMarker] or "") or ""
        if id ~= "" then Utility.markWaterTargetDirty(Utility.worldData(), id) end
    end)
end

end
return GodSystemServerRuntimeInstallers["GodSystem_ServerRuntime_UtilityGenerator"]
