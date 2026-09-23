GodSystemUtilityGenerator = GodSystemUtilityGenerator or {}

local U = GodSystemUtilityGenerator
U.FullType = "GodSystem.UtilityGenerator"
U.ItemMarker = "GodSystemUtilityGeneratorId"
U.ObjectMarker = "GodSystemUtilityGeneratorId"
U.WaterMarker = "GodSystemUtilityWaterDevice"
U.WaterFree = "GodSystemUtilityWaterFree"
U.WaterPaid = "GodSystemUtilityWaterPaid"
U.WaterPaidCents = "GodSystemUtilityWaterPaidCents"
U.WaterLast = "GodSystemUtilityWaterLast"
U.WaterPrice = "GodSystemUtilityWaterPrice"
U.WaterFixturesLimit = 256
U.WaterBufferLiters = 10
U.PowerPollMs = 30000
U.WaterScanMs = 60000
U.ScanSquaresPerStep = 96
U.ScanTimeBudgetMs = 2
U.jobs = U.jobs or {}

local function bindWorldJobs(root)
    if U._jobsRoot ~= root then
        U.jobs = {}
        U._jobsRoot = root
    end
end

local EPSILON = 0.001
local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

function U.tableCount(values)
    local count = 0
    for _ in pairs(type(values) == "table" and values or {}) do count = count + 1 end
    return count
end

function U.call(target, method, ...)
    local bridge = GodSystemB42JavaCalls
    if bridge and bridge.try then return bridge.try(target, method, ...) end
    if type(target) ~= "table" or type(target[method]) ~= "function" then return false, nil end
    return pcall(target[method], target, ...)
end

function U.value(target, method, fallback, ...)
    local bridge = GodSystemB42JavaCalls
    if bridge and bridge.value then return bridge.value(target, method, fallback, ...) end
    local ok, result = U.call(target, method, ...)
    return ok and result ~= nil and result or fallback
end

function U.itemId(item)
    local id = U.value(item, "getID", nil)
    return id ~= nil and tostring(id) or nil
end

function U.itemFullType(item)
    return tostring(U.value(item, "getFullType", "") or "")
end

function U.deviceId(object)
    local data = U.value(object, "getModData", nil)
    local id = type(data) == "table" and tostring(data[U.ObjectMarker] or "") or ""
    return id ~= "" and id or nil
end

function U.itemDeviceId(item)
    local data = U.value(item, "getModData", nil)
    local id = type(data) == "table" and tostring(data[U.ItemMarker] or "") or ""
    return id ~= "" and id or nil
end

function U.worldData()
    local key = tostring(GodSystemConfig and GodSystemConfig.DataKey or "GodSystem_CN_Data") .. "_UtilityGenerators"
    local root
    if ModData and ModData.getOrCreate then root = ModData.getOrCreate(key) end
    if type(root) ~= "table" then
        _G.__GodSystemUtilityGeneratorData = _G.__GodSystemUtilityGeneratorData or {}
        root = _G.__GodSystemUtilityGeneratorData
    end
    root.devices = type(root.devices) == "table" and root.devices or {}
    root.nextId = math.max(0, math.floor(tonumber(root.nextId) or 0))
    root.operations = type(root.operations) == "table" and root.operations or {}
    root.operationOrder = type(root.operationOrder) == "table" and root.operationOrder or {}
    return root
end

function U.ensureDevice(root, id)
    if type(root) ~= "table" or type(root.devices) ~= "table" then return nil end
    id = tostring(id or "")
    if id == "" then return nil end
    local row = root.devices[id]
    if type(row) ~= "table" then
        row = { id = id, balanceCents = 0, powerReserveCents = 0, powerReserveFuel = 0,
            waterFixtures = {}, active = false, placed = false }
        root.devices[id] = row
    end
    row.id = id
    row.balanceCents = math.max(0, math.floor(tonumber(row.balanceCents) or 0))
    row.powerReserveCents = math.max(0, math.floor(tonumber(row.powerReserveCents) or 0))
    row.powerReserveFuel = math.max(0, tonumber(row.powerReserveFuel) or 0)
    row.waterFixtures = type(row.waterFixtures) == "table" and row.waterFixtures or {}
    row.active = row.active == true
    row.placed = row.placed == true
    return row
end

function U.newDeviceId(root)
    root.nextId = math.max(0, math.floor(tonumber(root.nextId) or 0)) + 1
    local now = GameTime and GameTime.getInstance and GameTime:getInstance()
    local worldHour = now and U.value(now, "getWorldAgeHours", 0) or 0
    return "UG-" .. tostring(math.floor((tonumber(worldHour) or 0) * 1000)) .. "-" .. tostring(root.nextId)
end

local function sandboxNumber(name, fallback)
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.get then
        local configured = GodSystemRuntimeConfig.get(name, nil)
        if finite(configured) then return tonumber(configured) end
    end
    local vars = SandboxVars and SandboxVars.GodSystem or nil
    local value = vars and vars[name] or nil
    if finite(value) then return tonumber(value) end
    return fallback
end

function U.waterPrice()
    return math.max(0, math.min(1000000, sandboxNumber("UtilityGeneratorWaterPricePer100L", 20)))
end

function U.electricityPrice()
    return math.max(0, math.min(1000000, sandboxNumber("UtilityGeneratorElectricityPricePerFuelUnit", 5)))
end

function U.featureEnabled(name)
    if GodSystemRuntimeConfig and GodSystemRuntimeConfig.isFeatureEnabled then
        return GodSystemRuntimeConfig.isFeatureEnabled(name, true)
    end
    local vars = SandboxVars and SandboxVars.GodSystem or nil
    return not vars or vars[name] ~= false
end

local function sandboxShutoffDay(kind)
    local options = getSandboxOptions and getSandboxOptions() or nil
    if not options then return nil end
    local modifier
    if kind == "water" then
        modifier = U.value(options, "getWaterShutModifier", nil)
    else
        modifier = U.value(options, "getElecShutModifier", nil)
    end
    return finite(modifier) and tonumber(modifier) or nil
end

function U.publicUtilityOn(kind)
    local day = 0
    local gameTime = GameTime and GameTime.getInstance and GameTime:getInstance() or nil
    if gameTime then day = (tonumber(U.value(gameTime, "getWorldAgeHours", 0)) or 0) / 24 end
    local sandbox = getSandboxOptions and getSandboxOptions() or nil
    local months = sandbox and tonumber(U.value(sandbox, "getTimeSinceApo", nil)) or 1
    day = day + math.max(0, (months or 1) - 1) * 30
    local stopDay = sandboxShutoffDay(kind)
    if kind == "electricity" then
        local world = getWorld and getWorld() or nil
        local hydroOk, hydro = U.call(world, "isHydroPowerOn")
        if hydroOk and hydro ~= nil then return hydro == true, true end
    end
    if stopDay ~= nil and stopDay < 0 then return true, true end
    if stopDay ~= nil then
        local scheduled = day < stopDay
        if kind == "water" then return scheduled, true end
        return scheduled, true
    end
    -- Unknown supply state is treated as public supply: do not bill players.
    return true, false
end

local function location(square)
    if not square then return nil end
    local x, y, z = U.value(square, "getX", nil), U.value(square, "getY", nil), U.value(square, "getZ", nil)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return math.floor(x), math.floor(y), math.floor(z)
end

function U.playerNear(player, x, y, z, maxDistance)
    if not player or not finite(x) or not finite(y) or not finite(z) then return false end
    local px, py, pz = U.value(player, "getX", nil), U.value(player, "getY", nil), U.value(player, "getZ", nil)
    if not finite(px) or not finite(py) or not finite(pz) or math.floor(pz) ~= math.floor(z) then return false end
    local dx, dy = px - x, py - y
    maxDistance = tonumber(maxDistance) or 4
    return dx * dx + dy * dy <= maxDistance * maxDistance
end

function U.describeStatus(row, generator)
    local waterOn = U.publicUtilityOn("water")
    local powerOn = U.publicUtilityOn("electricity")
    local active = row and row.active == true
    local balance = math.max(0, tonumber(row and row.balanceCents) or 0)
    local waterReason
    if waterOn then waterReason = "public"
    elseif not U.featureEnabled("EnableUtilityGenerator") or not U.featureEnabled("EnableUtilityGeneratorWater") then waterReason = "disabled"
    elseif not active then waterReason = "stopped"
    elseif balance <= 0 and (tonumber(row and row.waterReserveCents) or 0) <= 0 then waterReason = "insufficient"
    elseif not IsoFlagType or not IsoFlagType.waterPiped then waterReason = "unsupported"
    else waterReason = "ready" end
    local electricityReason
    if powerOn then electricityReason = "public"
    elseif not U.featureEnabled("EnableUtilityGenerator") or not U.featureEnabled("EnableUtilityGeneratorElectricity") then electricityReason = "disabled"
    elseif not active then electricityReason = "stopped"
    elseif not generator or not finite(U.value(generator, "getFuel", nil))
        or not finite(U.value(generator, "getMaxFuel", nil)) then electricityReason = "unsupported"
    elseif U.value(generator, "isActivated", false) ~= true then
        electricityReason = balance <= 0 and "insufficient" or "stopped"
    else electricityReason = "ready" end
    return {
        deviceId = row and row.id or nil,
        balanceCents = balance,
        active = active,
        waterReason = waterReason,
        electricityReason = electricityReason,
        waterPrice = U.waterPrice(),
        electricityPrice = U.electricityPrice(),
    }
end

function U.fingerprint(args)
    args = type(args) == "table" and args or {}
    return table.concat({ tostring(args.action or ""), tostring(args.deviceId or ""),
        tostring(args.itemId or ""), tostring(args.amount or ""), tostring(args.active == true),
        tostring(math.floor(tonumber(args.x) or -1)), tostring(math.floor(tonumber(args.y) or -1)),
        tostring(math.floor(tonumber(args.z) or -1)) }, "|")
end

local function syncGenerator(generator, modData)
    if modData then U.call(generator, "transmitModData") end
    U.call(generator, "sync")
end

local function setFuel(generator, amount)
    local ok = U.call(generator, "setFuel", math.max(0, amount or 0))
    return ok and math.abs((tonumber(U.value(generator, "getFuel", -1)) or -1) - amount) < 0.05
end

function U.releasePowerReserve(row, generator)
    if not row then return false end
    local held = math.max(0, math.floor(tonumber(row.powerReserveCents) or 0))
    local fuel = math.max(0, tonumber(U.value(generator, "getFuel", 0)) or 0)
    local reservedFuel = math.max(0, tonumber(row.powerReserveFuel) or 0)
    if fuel <= EPSILON and held <= 0 then
        U.call(generator, "setActivated", false)
        return true
    end
    local ok = setFuel(generator, 0)
    if not ok then return false end
    local refund = reservedFuel > EPSILON and math.min(held,
        math.floor(held * math.min(fuel, reservedFuel) / reservedFuel + 0.5)) or 0
    row.balanceCents = math.max(0, tonumber(row.balanceCents) or 0) + refund
    row.powerReserveCents, row.powerReserveFuel, row.powerUnitPrice = 0, 0, nil
    U.call(generator, "setActivated", false)
    syncGenerator(generator, false)
    return true
end

local function centsForFuel(fuel, price)
    return math.max(0, math.ceil(math.max(0, fuel) * math.max(0, price) * 100 - 0.00001))
end

function U.updatePower(row, generator)
    if not row or not generator then return false end
    local publicOn = U.publicUtilityOn("electricity")
    local enabled = U.featureEnabled("EnableUtilityGenerator") and U.featureEnabled("EnableUtilityGeneratorElectricity")
    if not row.active or publicOn or not enabled then
        U.call(generator, "setActivated", false)
        if (tonumber(U.value(generator, "getFuel", 0)) or 0) > EPSILON then return U.releasePowerReserve(row, generator) end
        return false
    end
    local price = U.electricityPrice()
    local oldPrice = tonumber(row.powerUnitPrice)
    if oldPrice ~= nil and math.abs(oldPrice - price) > EPSILON then
        if not U.releasePowerReserve(row, generator) then return false end
    end
    local fuel = tonumber(U.value(generator, "getFuel", nil))
    local maximum = tonumber(U.value(generator, "getMaxFuel", nil))
    if not fuel or not maximum or maximum <= 0 then return false end
    fuel = math.max(0, fuel)
    local reservedFuel = math.max(0, tonumber(row.powerReserveFuel) or 0)
    if fuel > reservedFuel + 0.05 then
        -- An unmetered vanilla fuel action or another mod changed the reservoir.
        if not setFuel(generator, reservedFuel) then return false end
        fuel = reservedFuel
    elseif fuel < reservedFuel - 0.05 then
        local consumed = math.min(reservedFuel - fuel, reservedFuel)
        local oldCents = math.max(0, math.floor(tonumber(row.powerReserveCents) or 0))
        local consumedCents = reservedFuel > EPSILON and math.min(oldCents,
            math.floor(oldCents * consumed / reservedFuel + 0.5)) or 0
        row.powerReserveFuel = math.max(0, reservedFuel - consumed)
        row.powerReserveCents = math.max(0, oldCents - consumedCents)
        fuel = tonumber(U.value(generator, "getFuel", fuel)) or fuel
    end
    local room = math.max(0, maximum - fuel)
    local available = math.max(0, tonumber(row.balanceCents) or 0)
    local add = room
    if price > 0 then add = math.min(room, available / (price * 100)) end
    if add > EPSILON then
        local reserve = centsForFuel(add, price)
        if reserve > available then
            add = math.max(0, (available - 0.001) / (price * 100))
            reserve = centsForFuel(add, price)
        end
        if add > EPSILON and reserve <= available then
            row.balanceCents = available - reserve
            local expected = fuel + add
            if setFuel(generator, expected) then
                local actual = math.max(0, (tonumber(U.value(generator, "getFuel", fuel)) or fuel) - fuel)
                local actualCents = centsForFuel(actual, price)
                row.balanceCents = row.balanceCents + math.max(0, reserve - actualCents)
                row.powerReserveFuel = row.powerReserveFuel + actual
                row.powerReserveCents = row.powerReserveCents + actualCents
                row.powerUnitPrice = price
                fuel = fuel + actual
            else
                row.balanceCents = row.balanceCents + reserve
                return false
            end
        end
    end
    U.call(generator, "setConnected", true)
    U.call(generator, "setActivated", fuel > EPSILON)
    syncGenerator(generator, false)
    return true
end

local function currentWater(object, modData)
    local amount = tonumber(U.value(object, "getFluidAmount", nil))
    return math.max(0, amount or 0)
end

local function waterCapacity(object, modData)
    local amount = tonumber(U.value(object, "getFluidCapacity", nil))
    local container = U.value(object, "getFluidContainer", nil)
    if container then amount = math.max(amount or 0, tonumber(U.value(container, "getCapacity", 0)) or 0) end
    if not amount or amount <= 0 then
        local props = U.value(object, "getProperties", nil)
        if not props then
            local sprite = U.value(object, "getSprite", nil)
            props = sprite and U.value(sprite, "getProperties", nil) or nil
        end
        local maxWater = IsoPropertyType and IsoPropertyType.MAXIMUM_WATER_AMOUNT or nil
        if props and maxWater ~= nil then amount = tonumber(U.value(props, "get", nil, maxWater)) end
        if (not amount or amount <= 0) and props then amount = tonumber(U.value(props, "get", nil, "waterMaxAmount")) end
    end
    if not amount or amount <= 0 then amount = tonumber(type(modData) == "table" and modData.waterMaxAmount or 0) end
    return math.max(0, amount or 0), container
end

local function hasForeignWaterMarker(modData)
    if type(modData) ~= "table" then return false end
    for key, value in pairs(modData) do
        local name = tostring(key):lower()
        if (string.find(name, "water", 1, true) or string.find(name, "utility", 1, true))
            and key ~= "waterAmount" and key ~= "waterMaxAmount"
            and key ~= U.WaterMarker and key ~= U.WaterFree and key ~= U.WaterPaid
            and key ~= U.WaterPaidCents and key ~= U.WaterLast and key ~= U.WaterPrice
            and value ~= nil and value ~= false then return true end
    end
    return false
end

local function isPipedFixture(object)
    if not object or not IsoFlagType or not IsoFlagType.waterPiped then return false end
    if instanceof and instanceof(object, "IsoFeedingTrough") then return false end
    local props = U.value(object, "getProperties", nil)
    if not props then
        local sprite = U.value(object, "getSprite", nil)
        props = sprite and U.value(sprite, "getProperties", nil) or nil
    end
    return props ~= nil and U.value(props, "has", false, IsoFlagType.waterPiped) == true
end

local function externalWaterAvailable(object, amount)
    if U.value(object, "getUsesExternalWaterSource", false) ~= true then return false end
    U.call(object, "doFindExternalWaterSource")
    return U.value(object, "hasExternalWaterSource", false) == true and amount > EPSILON
end

local function setWaterAmount(object, modData, container, amount)
    amount = math.max(0, amount)
    if not FluidType or not FluidType.Water then return false end
    local current = tonumber(U.value(object, "getFluidAmount", nil))
    if current == nil then return false end
    local delta = amount - current
    if delta > EPSILON then
        local ok = U.call(object, "addFluid", FluidType.Water, delta)
        if not ok then return false end
    elseif delta < -EPSILON then
        local ok = U.call(object, "useFluid", -delta)
        if not ok then return false end
    end
    local updated = tonumber(U.value(object, "getFluidAmount", nil))
    return updated ~= nil and math.abs(updated - amount) <= 0.05
end

local function supportsMethod(object, method)
    if not object then return false end
    if type(object) == "table" then return type(object[method]) == "function" end
    local ok, value = pcall(function() return object[method] end)
    return ok and value ~= nil
end

local function hasNativeFluidInterface(object)
    if not supportsMethod(object, "getFluidAmount") or not supportsMethod(object, "getFluidCapacity")
        or not supportsMethod(object, "addFluid") or not supportsMethod(object, "useFluid") then return false end
    local amountOk, amount = U.call(object, "getFluidAmount")
    local capacityOk, capacity = U.call(object, "getFluidCapacity")
    return amountOk and capacityOk and finite(amount) and finite(capacity) and tonumber(capacity) > 0
end

local function fixtureKey(x, y, z, index)
    return table.concat({ tostring(x), tostring(y), tostring(z), tostring(index) }, ":")
end

local function settleWaterConsumption(device, modData, amount)
    local last = tonumber(modData[U.WaterLast])
    if last == nil or amount >= last - EPSILON then return false end
    local consumed = last - amount
    local free = math.max(0, tonumber(modData[U.WaterFree]) or 0)
    local freeUsed = math.min(free, consumed)
    modData[U.WaterFree] = math.max(0, free - freeUsed)
    local paid = math.max(0, tonumber(modData[U.WaterPaid]) or 0)
    local paidUsed = math.min(paid, math.max(0, consumed - freeUsed))
    if paidUsed > 0 then
        local held = math.max(0, math.floor(tonumber(modData[U.WaterPaidCents]) or 0))
        local spent = paid > EPSILON and math.min(held, math.floor(held * paidUsed / paid + 0.5)) or 0
        modData[U.WaterPaid] = math.max(0, paid - paidUsed)
        modData[U.WaterPaidCents] = math.max(0, held - spent)
        device.waterReserveCents = math.max(0, (tonumber(device.waterReserveCents) or 0) - spent)
        return true
    end
    return freeUsed > 0
end

function U.updateWaterFixture(root, device, object, x, y, z, index)
    if not device or not object or not isPipedFixture(object) then return false end
    if not hasNativeFluidInterface(object) then return false end
    local modData = U.value(object, "getModData", nil)
    if type(modData) ~= "table" then return false end
    local owner = tostring(modData[U.WaterMarker] or "")
    if owner ~= "" and owner ~= device.id then return false end
    if owner == "" and hasForeignWaterMarker(modData) then return false end
    local amount = currentWater(object, modData)
    if externalWaterAvailable(object, amount) then
        if owner == device.id then
            return U.releaseWaterFixture(root, device, object, fixtureKey(x, y, z, index), modData)
        end
        return false
    end
    local enabled = device.active and U.featureEnabled("EnableUtilityGenerator")
        and U.featureEnabled("EnableUtilityGeneratorWater")
    local publicOn = U.publicUtilityOn("water")
    local capacity, container = waterCapacity(object, modData)
    if capacity <= EPSILON then return false end
    local key = fixtureKey(x, y, z, index)
    if not enabled or publicOn then
        if owner == device.id then return U.releaseWaterFixture(root, device, object, key, modData, container) end
        return false
    end
    if owner == "" then
        if U.tableCount(device.waterFixtures) >= U.WaterFixturesLimit then return false end
        modData[U.WaterMarker] = device.id
        modData[U.WaterFree] = amount
        modData[U.WaterPaid] = 0
        modData[U.WaterPaidCents] = 0
        modData[U.WaterLast] = amount
        modData[U.WaterPrice] = U.waterPrice()
        device.waterFixtures[key] = { x = x, y = y, z = z, index = index }
    end
    local changed = owner == ""
    local price = U.waterPrice()
    local oldLast = tonumber(modData[U.WaterLast])
    if oldLast == nil or math.abs(oldLast - amount) > EPSILON then changed = true end
    if settleWaterConsumption(device, modData, amount) then changed = true end
    modData[U.WaterLast] = amount
    local paid = math.max(0, tonumber(modData[U.WaterPaid]) or 0)
    local free = math.max(0, tonumber(modData[U.WaterFree]) or 0)
    local room = math.max(0, capacity - amount)
    local want = math.min(room, math.max(0, U.WaterBufferLiters - paid), 10)
    local availableCents = math.max(0, tonumber(device.balanceCents) or 0)
    -- waterPrice is configured in coins per 100 L; after multiplying by
    -- 100 cents per coin and dividing by 100 L, the numeric value is cents/L.
    if price > 0 then want = math.min(want, availableCents / price) end
    if want > EPSILON then
        local costCents = math.ceil(want * price - 0.000001) -- price is cents per liter after unit conversion
        if costCents <= availableCents then
            local actual = amount + want
            if setWaterAmount(object, modData, container, actual) then
                local updated = currentWater(object, modData)
                local added = math.max(0, updated - amount)
                local actualCost = price > 0 and math.ceil(added * price - 0.000001) or 0
                device.balanceCents = math.max(0, availableCents - actualCost)
                device.waterReserveCents = (tonumber(device.waterReserveCents) or 0) + actualCost
                modData[U.WaterPaid] = paid + added
                modData[U.WaterPaidCents] = (tonumber(modData[U.WaterPaidCents]) or 0) + actualCost
                modData[U.WaterLast] = updated
                modData[U.WaterPrice] = price
                changed = changed or added > EPSILON or actualCost > 0
            end
        end
    end
    modData[U.WaterPrice] = price
    device.waterFixtures[key] = {
        x = math.floor(tonumber(x) or 0), y = math.floor(tonumber(y) or 0), z = math.floor(tonumber(z) or 0),
        index = math.floor(tonumber(index) or 0),
        paidCents = math.max(0, math.floor(tonumber(modData[U.WaterPaidCents]) or 0)),
    }
    if changed then U.call(object, "transmitModData") end
    return true
end

function U.releaseWaterFixture(root, device, object, key, modData, container)
    modData = modData or U.value(object, "getModData", nil)
    if type(modData) ~= "table" or tostring(modData[U.WaterMarker] or "") ~= tostring(device and device.id or "") then return false end
    local paid = math.max(0, tonumber(modData[U.WaterPaid]) or 0)
    local paidCents = math.max(0, math.floor(tonumber(modData[U.WaterPaidCents]) or 0))
    local amount = currentWater(object, modData)
    settleWaterConsumption(device, modData, amount)
    paid = math.max(0, tonumber(modData[U.WaterPaid]) or 0)
    paidCents = math.max(0, math.floor(tonumber(modData[U.WaterPaidCents]) or 0))
    if paid > EPSILON then setWaterAmount(object, modData, container, math.max(0, amount - paid)) end
    if device then
        device.balanceCents = math.max(0, tonumber(device.balanceCents) or 0) + paidCents
        device.waterReserveCents = math.max(0, (tonumber(device.waterReserveCents) or 0) - paidCents)
        device.waterFixtures[key or ""] = nil
    end
    modData[U.WaterMarker], modData[U.WaterFree], modData[U.WaterPaid] = nil, nil, nil
    modData[U.WaterPaidCents], modData[U.WaterLast], modData[U.WaterPrice] = nil, nil, nil
    U.call(object, "transmitModData")
    return true
end

function U.status(root, row, generator)
    local result = U.describeStatus(row, generator)
    local count = 0
    for _ in pairs(row and row.waterFixtures or {}) do count = count + 1 end
    result.waterFixtureCount = count
    if result.waterReason == "ready" and count == 0 then
        local job = row and U.jobs[tostring(row.id)]
        result.waterReason = job and job.kind == "scan" and "scanning" or "noFixture"
    end
    result.reservedCents = math.max(0, tonumber(row and row.powerReserveCents) or 0)
        + math.max(0, tonumber(row and row.waterReserveCents) or 0)
    return result
end

local function generatorRange()
    local vars = SandboxVars or {}
    local radius = math.max(1, math.min(100, math.floor(tonumber(vars.GeneratorTileRange) or 20)))
    local vertical = math.max(0, math.min(16, math.floor(tonumber(vars.GeneratorVerticalPowerRange) or 3)))
    return radius, vertical
end

function U.isGeneratorSquareAffected(centerX, centerY, centerZ, x, y, z)
    if IsoGenerator and IsoGenerator.isPoweringSquare then
        local ok, result = pcall(IsoGenerator.isPoweringSquare,
            math.floor(tonumber(centerX) or 0), math.floor(tonumber(centerY) or 0), math.floor(tonumber(centerZ) or 0),
            math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
        if ok and result ~= nil then return result == true end
    end
    local radius, vertical = generatorRange()
    local dx, dy, dz = (tonumber(x) or 0) - (tonumber(centerX) or 0),
        (tonumber(y) or 0) - (tonumber(centerY) or 0), (tonumber(z) or 0) - (tonumber(centerZ) or 0)
    return math.abs(dx) <= radius and math.abs(dy) <= radius and math.abs(dz) <= vertical
end

function U.scheduleScan(root, id)
    bindWorldJobs(root)
    local row = U.ensureDevice(root, id)
    if not row or not row.placed or not finite(row.x) or not finite(row.y) or not finite(row.z) then return false end
    local radius, vertical = generatorRange()
    local current = U.jobs[tostring(id)]
    if current and current.kind == "scan" then return true end
    U.jobs[tostring(id)] = {
        kind = "scan", id = tostring(id), centerX = math.floor(row.x), centerY = math.floor(row.y), centerZ = math.floor(row.z),
        radius = radius, minZ = math.floor(row.z) - vertical, maxZ = math.floor(row.z) + vertical,
        cursor = 0, total = (radius * 2 + 1) * (radius * 2 + 1) * (vertical * 2 + 1),
    }
    return true
end

function U.scheduleCleanup(root, id)
    bindWorldJobs(root)
    local row = U.ensureDevice(root, id)
    if not row then return false end
    local keys = {}
    for key in pairs(row.waterFixtures) do keys[#keys + 1] = key end
    table.sort(keys)
    U.jobs[tostring(id)] = { kind = "cleanup", id = tostring(id), keys = keys, cursor = 1 }
    return true
end

local function processScanSquare(root, job, adapter, x, y, z)
    local row = U.ensureDevice(root, job.id)
    if not row then return end
    if not U.isGeneratorSquareAffected(job.centerX, job.centerY, job.centerZ, x, y, z) then return end
    local square = adapter.square and adapter.square(x, y, z) or nil
    local objects = square and U.value(square, "getObjects", nil) or nil
    local count = math.max(0, math.floor(tonumber(U.value(objects, "size", 0)) or 0))
    for index = 0, count - 1 do
        local object = U.value(objects, "get", nil, index)
        if object and U.deviceId(object) ~= row.id then
            U.updateWaterFixture(root, row, object, x, y, z, index)
        end
    end
end

function U.scanSquare(root, id, adapter, x, y, z)
    local row = U.ensureDevice(root, id)
    if not row or not row.placed or not row.active then return false end
    if not U.isGeneratorSquareAffected(row.x, row.y, row.z, x, y, z) then return false end
    processScanSquare(root, { id = tostring(id), centerX = row.x, centerY = row.y, centerZ = row.z }, adapter or {}, math.floor(tonumber(x) or 0),
        math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
    return true
end

local function processCleanup(root, job, adapter, budget)
    local row = U.ensureDevice(root, job.id)
    if not row then return true, 0 end
    local count = 0
    while job.cursor <= #job.keys and count < budget do
        local key = job.keys[job.cursor]
        local fixture = row.waterFixtures[key]
        job.cursor, count = job.cursor + 1, count + 1
        if fixture then
            local object = adapter.fixture and adapter.fixture(fixture, row.id) or nil
            if object then
                local modData = U.value(object, "getModData", nil)
                local _, container = waterCapacity(object, modData)
                U.releaseWaterFixture(root, row, object, key, modData, container)
            end
        end
    end
    if job.cursor > #job.keys then return true, count end
    return false, count
end

function U.tick(root, adapter, nowMs)
    root, adapter = root or U.worldData(), adapter or {}
    bindWorldJobs(root)
    nowMs = tonumber(nowMs) or (getTimestampMs and getTimestampMs()) or math.floor(os.time() * 1000)
    root.devices = type(root.devices) == "table" and root.devices or {}
    local ids = {}
    for id in pairs(root.devices) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    for i = 1, #ids do
        local row = U.ensureDevice(root, ids[i])
        if row and row.placed then
            if row.active and nowMs >= (tonumber(row.nextPowerPollMs) or 0) then
                row.nextPowerPollMs = nowMs + U.PowerPollMs
                local generator = adapter.findDevice and adapter.findDevice(row.id, row.x, row.y, row.z) or nil
                if generator then U.updatePower(row, generator) end
            end
            local wantsWater = row.active and U.featureEnabled("EnableUtilityGenerator")
                and U.featureEnabled("EnableUtilityGeneratorWater") and not U.publicUtilityOn("water")
            local hasManagedWater = U.tableCount(row.waterFixtures) > 0
            local shouldScan = wantsWater or hasManagedWater
            if shouldScan and nowMs >= (tonumber(row.nextWaterScanMs) or 0) and not U.jobs[row.id] then
                row.nextWaterScanMs = nowMs + U.WaterScanMs
                if wantsWater then U.scheduleScan(root, row.id) else U.scheduleCleanup(root, row.id) end
            end
        end
    end
    local jobIds = {}
    for id in pairs(U.jobs) do jobIds[#jobIds + 1] = id end
    table.sort(jobIds)
    local remaining = U.ScanSquaresPerStep
    local started = (getTimestampMs and getTimestampMs()) or nowMs
    for index = 1, #jobIds do
        if remaining <= 0 then break end
        local id = jobIds[index]
        local job = U.jobs[id]
        if job then
            if job.kind == "cleanup" then
                local done, processed = processCleanup(root, job, adapter, math.min(32, remaining))
                remaining = remaining - processed
                if done then U.jobs[id] = nil end
            elseif job.kind == "scan" then
                local row = U.ensureDevice(root, job.id)
                if not row or not row.placed or not row.active then
                    U.scheduleCleanup(root, id)
                else
                    local processed = 0
                    while job.cursor < job.total and processed < remaining do
                        local offset = job.cursor
                        job.cursor, processed = job.cursor + 1, processed + 1
                        local width = job.radius * 2 + 1
                        local plane = width * width
                        local z = job.minZ + math.floor(offset / plane)
                        local within = offset % plane
                        local y = job.centerY - job.radius + math.floor(within / width)
                        local x = job.centerX - job.radius + within % width
                        processScanSquare(root, job, adapter, x, y, z)
                        if getTimestampMs and getTimestampMs() - started >= U.ScanTimeBudgetMs then break end
                    end
                    remaining = remaining - processed
                    if job.cursor >= job.total then U.jobs[id] = nil end
                end
            end
            if getTimestampMs and getTimestampMs() - started >= U.ScanTimeBudgetMs then break end
        end
    end
end

function U.onObjectAdded(root, object, adapter)
    bindWorldJobs(root)
    local square = U.value(object, "getSquare", nil)
    local x, y, z = location(square)
    if not x then return false end
    local changed = false
    for id in pairs((root and root.devices) or {}) do
        local row = U.ensureDevice(root, id)
        if row and row.placed and row.active and U.isGeneratorSquareAffected(row.x, row.y, row.z, x, y, z) then
            changed = U.scanSquare(root, id, adapter or {}, x, y, z) or changed
        end
    end
    return changed
end

function U.execute(player, args, env)
    args = type(args) == "table" and args or {}
    env = env or {}
    local action = tostring(args.action or "")
    local root = env.root or U.worldData()
    root.devices = type(root.devices) == "table" and root.devices or {}
    if action == "place" then
        local item, container
        if env.findItem then item, container = env.findItem(player, args.itemId) end
        if not item or U.itemFullType(item) ~= U.FullType then return false, "UtilityGeneratorItemMissing" end
        local square = env.square and env.square(args.x, args.y, args.z) or nil
        if not square or not U.playerNear(player, args.x, args.y, args.z, 3) then return false, "UtilityGeneratorInvalidPlace" end
        local existingId = U.itemDeviceId(item)
        local id = existingId or U.newDeviceId(root)
        local row = U.ensureDevice(root, id)
        if row.placed then return false, "UtilityGeneratorAlreadyPlaced" end
        local created, generator = false, nil
        if env.createGenerator then created, generator = env.createGenerator(item, id, square) end
        if not created or not generator then
            if not existingId then root.devices[id] = nil end
            return false, "UtilityGeneratorPlaceFailed"
        end
        local removed = env.removeItem and env.removeItem(player, item, container) == true
        if not removed then
            if env.removeGenerator then env.removeGenerator(generator) end
            if not existingId then root.devices[id] = nil end
            return false, "UtilityGeneratorItemMissing"
        end
        row.placed, row.x, row.y, row.z = true, math.floor(args.x), math.floor(args.y), math.floor(args.z)
        row.active = false
        row.waterFixtures = row.waterFixtures or {}
        if env.scheduleScan then env.scheduleScan(id) end
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorPlaced", { deviceId = id }
    end
    local id = tostring(args.deviceId or "")
    local row = U.ensureDevice(root, id)
    local generator = env.findDevice and env.findDevice(id, args.x, args.y, args.z) or nil
    if not row or not generator or U.deviceId(generator) ~= id then return false, "UtilityGeneratorUnavailable" end
    local x, y, z = location(U.value(generator, "getSquare", nil))
    if not x or not U.playerNear(player, x, y, z, 4) then return false, "UtilityGeneratorTooFar" end
    if action == "status" then return true, "UtilityGeneratorStatusReady", U.status(root, row, generator) end
    if action == "repair" then
        if row.active or U.value(generator, "isActivated", false) == true then return false, "UtilityGeneratorStopBeforeRepair" end
        local scrap, container
        if env.findItem then scrap, container = env.findItem(player, args.itemId) end
        if not scrap or U.itemFullType(scrap) ~= "Base.ElectronicsScrap" then return false, "UtilityGeneratorRepairMaterialMissing" end
        if not env.repair or env.repair(player, generator, scrap, container) ~= true then
            return false, "UtilityGeneratorRepairFailed"
        end
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorRepairSuccess", { condition = U.value(generator, "getCondition", 0) }
    end
    if action == "charge" then
        local amount = math.max(0, math.min(1000000, math.floor(tonumber(args.amount) or 0)))
        if amount <= 0 then return false, "UtilityGeneratorAmountInvalid" end
        local balance = math.max(0, math.floor(tonumber(row.balanceCents) or 0))
        if balance > 214748364700 - amount * 100 then return false, "UtilityGeneratorBalanceLimit" end
        if not env.spendCurrency or not env.spendCurrency(player, amount) then return false, "CurrencyNotEnough" end
        row.balanceCents = balance + amount * 100
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorCharged", { amount = amount, balanceCents = row.balanceCents }
    end
    if action == "active" then
        row.active = args.active == true
        if not row.active then
            U.call(generator, "setActivated", false)
            if not U.releasePowerReserve(row, generator) then return false, "UtilityGeneratorStopFailed" end
        else
            U.updatePower(row, generator)
        end
        if env.scheduleScan then env.scheduleScan(id) end
        if env.persist then env.persist(root) end
        return true, row.active and "UtilityGeneratorStarted" or "UtilityGeneratorStopped", { active = row.active }
    end
    if action == "pickup" then
        row.active = false
        U.call(generator, "setActivated", false)
        if not U.releasePowerReserve(row, generator) then return false, "UtilityGeneratorStopFailed" end
        if env.cleanupWater and env.cleanupWater(id, generator, row) ~= true then
            U.scheduleCleanup(root, id)
            if env.persist then env.persist(root) end
            return false, "UtilityGeneratorCleanupPending"
        end
        local success, item = false, nil
        if env.pickup then success, item = env.pickup(player, generator, id) end
        if not success then return false, "UtilityGeneratorPickupFailed" end
        row.placed, row.x, row.y, row.z = false, nil, nil, nil
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorPickedUp", { deviceId = id }
    end
    return false, "UtilityGeneratorActionInvalid"
end

return U
