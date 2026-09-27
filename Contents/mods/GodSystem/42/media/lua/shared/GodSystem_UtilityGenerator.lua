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
U.WaterOriginalMax = "GodSystemUtilityWaterOriginalMax"
U.WaterOriginalMaxSet = "GodSystemUtilityWaterOriginalMaxSet"
U.TargetMarker = "GodSystemUtilityWaterTarget"
U.GhostMarker = "GodSystemUtilityWaterGhost"
U.GhostDeviceMarker = "GodSystemUtilityWaterGhostDevice"
U.WaterFixturesLimit = 256
U.WaterBufferLiters = 10
U.FixtureWaterBufferLiters = 100
U.PowerBufferFuel = 10
U.PowerPollMs = 30000
U.WaterScanMs = 60000
U.ScanSquaresPerStep = 96
U.ScanTimeBudgetMs = 2
U.GeneratorWaterCapacity = 50
U.DrinkLiters = 0.5
U.DefaultTargetLiters = 10
U.jobs = U.jobs or {}

local function hasEntries(values)
    if type(values) ~= "table" then return false end
    for _ in pairs(values) do return true end
    return false
end

local function needsDeviceWatch(row)
    return type(row) == "table" and (row.placed == true or hasEntries(row.waterFixtures)
        or (row.destroyed == true and hasEntries(row.waterTargets)))
end

local function hasUnreleasedWater(row)
    for _, record in pairs(type(row.waterTargets) == "table" and row.waterTargets or {}) do
        if record.kind == "fixture" and record.ghostActive == true then return true end
    end
    return false
end

local function bindWorldJobs(root)
    if U._jobsRoot ~= root then
        U.jobs = {}
        U._jobsRoot = root
        U.nextDeviceCheckMs = 0
        U._targetSquareIndex = nil
        U._targetIndexRoot = nil
        U.enabledStates = {}
        U.waterStateChanged = {}
        U.inactiveCleanupNeeded = {}
        U._nextJobReadyMs = math.huge
        U._watchedDeviceIds = {}
        for id, row in pairs(root and root.devices or {}) do
            if needsDeviceWatch(row) then U._watchedDeviceIds[tostring(id)] = true end
            if type(row) == "table" and hasUnreleasedWater(row) then
                U.inactiveCleanupNeeded[tostring(id)] = true
            end
        end
    end
end

local function refreshDeviceWatch(root, row)
    bindWorldJobs(root)
    if not row then return end
    if needsDeviceWatch(row) then
        U._watchedDeviceIds[row.id] = true
    else
        U._watchedDeviceIds[row.id] = nil
        U.enabledStates[row.id] = nil
        U.waterStateChanged[row.id] = nil
        U.inactiveCleanupNeeded[row.id] = nil
    end
end

function U.hasPendingWork(nowMs)
    nowMs = tonumber(nowMs) or (getTimestampMs and getTimestampMs()) or math.floor(os.time() * 1000)
    return nowMs >= (tonumber(U._nextJobReadyMs) or math.huge)
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
        row = { id = id, waterBalanceCents = 0, powerBalanceCents = 0,
            powerReserveCents = 0, powerReserveFuel = 0,
            waterFixtures = {}, waterTargets = {}, waterTargetLiters = U.DefaultTargetLiters,
            active = false, placed = false }
        root.devices[id] = row
    end
    row.id = id
    row.waterBalanceCents = math.max(0, math.floor(tonumber(row.waterBalanceCents) or 0))
    row.powerBalanceCents = math.max(0, math.floor(tonumber(row.powerBalanceCents) or 0))
    -- Existing shared credit belongs to water. Keep any excess legacy credit
    -- until the water account has room, so migration cannot discard coins.
    if row.balanceCents ~= nil then
        local legacy = math.max(0, math.floor(tonumber(row.balanceCents) or 0))
        local moved = math.min(legacy, math.max(0, 214748364700 - row.waterBalanceCents))
        row.waterBalanceCents = row.waterBalanceCents + moved
        row.balanceCents = legacy > moved and legacy - moved or nil
    end
    row.powerReserveCents = math.max(0, math.floor(tonumber(row.powerReserveCents) or 0))
    row.powerReserveFuel = math.max(0, tonumber(row.powerReserveFuel) or 0)
    row.waterReserveCents = math.max(0, math.floor(tonumber(row.waterReserveCents) or 0))
    row.waterFixtures = type(row.waterFixtures) == "table" and row.waterFixtures or {}
    row.waterTargets = type(row.waterTargets) == "table" and row.waterTargets or {}
    row.waterTargetLiters = math.max(1, math.min(1000,
        math.floor(tonumber(row.waterTargetLiters) or U.DefaultTargetLiters)))
    row.waterTargetSequence = math.max(0, math.floor(tonumber(row.waterTargetSequence) or 0))
    if row.waterTargetSchema ~= 1 then
        -- Existing automatic fixtures are legacy cleanup work, never new bindings.
        row.waterTargets = {}
        row.waterTargetSchema = 1
    end
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
    local active = row and row.active == true
    local waterBalance = math.max(0, tonumber(row and row.waterBalanceCents) or 0)
    local powerBalance = math.max(0, tonumber(row and row.powerBalanceCents) or 0)
    local waterReason
    if not U.featureEnabled("EnableUtilityGenerator") or not U.featureEnabled("EnableUtilityGeneratorWater") then waterReason = "disabled"
    elseif not active then waterReason = "stopped"
    elseif waterBalance <= 0 and (tonumber(row and row.waterReserveCents) or 0) <= 0 then waterReason = "insufficient"
    elseif not IsoFlagType or not IsoFlagType.waterPiped then waterReason = "unsupported"
    else waterReason = "ready" end
    local electricityReason
    if not U.featureEnabled("EnableUtilityGenerator") or not U.featureEnabled("EnableUtilityGeneratorElectricity") then electricityReason = "disabled"
    elseif not active then electricityReason = "stopped"
    elseif not generator or not finite(U.value(generator, "getFuel", nil))
        or not finite(U.value(generator, "getMaxFuel", nil)) then electricityReason = "unsupported"
    elseif U.value(generator, "isActivated", false) ~= true then
        electricityReason = powerBalance <= 0 and "insufficient" or "stopped"
    else electricityReason = "ready" end
    return {
        deviceId = row and row.id or nil,
        waterBalanceCents = waterBalance,
        powerBalanceCents = powerBalance,
        waterReserveCents = math.max(0, tonumber(row and row.waterReserveCents) or 0),
        powerReserveCents = math.max(0, tonumber(row and row.powerReserveCents) or 0),
        active = active,
        waterReason = waterReason,
        electricityReason = electricityReason,
        waterPrice = U.waterPrice(),
        electricityPrice = U.electricityPrice(),
    }
end

function U.fingerprint(args)
    args = type(args) == "table" and args or {}
    local parts = { tostring(args.action or ""), tostring(args.deviceId or ""),
        tostring(args.itemId or ""), tostring(args.amount or ""), tostring(args.active == true),
        tostring(math.floor(tonumber(args.x) or -1)), tostring(math.floor(tonumber(args.y) or -1)),
        tostring(math.floor(tonumber(args.z) or -1)) }
    if args.action == "charge" and args.utility ~= nil then parts[#parts + 1] = tostring(args.utility) end
    if args.action == "bindWaterTarget" then
        parts[#parts + 1] = tostring(args.targetX or "")
        parts[#parts + 1] = tostring(args.targetY or "")
        parts[#parts + 1] = tostring(args.targetZ or "")
        parts[#parts + 1] = tostring(args.targetIndex or "")
        parts[#parts + 1] = tostring(args.targetSprite or "")
    elseif args.action == "unbindWaterTarget" then
        parts[#parts + 1] = tostring(args.targetId or "")
    elseif args.action == "setWaterTargetLiters" then
        parts[#parts + 1] = tostring(args.liters or "")
    end
    return table.concat(parts, "|")
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
    row.powerBalanceCents = math.max(0, tonumber(row.powerBalanceCents) or 0) + refund
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
    local enabled = U.featureEnabled("EnableUtilityGenerator") and U.featureEnabled("EnableUtilityGeneratorElectricity")
    if not enabled then
        U.call(generator, "setActivated", false)
        if (tonumber(U.value(generator, "getFuel", 0)) or 0) > EPSILON then return U.releasePowerReserve(row, generator) end
        return false
    end
    if not row.active then
        U.call(generator, "setActivated", false)
        if (tonumber(U.value(generator, "getFuel", 0)) or 0) > EPSILON then return U.releasePowerReserve(row, generator) end
        return false
    end
    local price = U.electricityPrice()
    local fuel = tonumber(U.value(generator, "getFuel", nil))
    local maximum = tonumber(U.value(generator, "getMaxFuel", nil))
    if not fuel or not maximum or maximum <= 0 then
        U.call(generator, "setActivated", false)
        return false
    end
    fuel = math.max(0, fuel)
    local reservedFuel = math.max(0, tonumber(row.powerReserveFuel) or 0)
    if fuel > reservedFuel + 0.05 then
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
    local oldPrice = tonumber(row.powerUnitPrice)
    if oldPrice ~= nil and math.abs(oldPrice - price) > EPSILON then
        if not U.releasePowerReserve(row, generator) then return false end
        fuel = tonumber(U.value(generator, "getFuel", 0)) or 0
    end
    local room = math.max(0, math.min(maximum, U.PowerBufferFuel) - fuel)
    local available = math.max(0, tonumber(row.powerBalanceCents) or 0)
    local add = math.min(room, U.PowerBufferFuel)
    if price > 0 then add = math.min(add, available / (price * 100)) end
    if add > EPSILON then
        local reserve = centsForFuel(add, price)
        if reserve > available then
            add = math.max(0, (available - 0.001) / (price * 100))
            reserve = centsForFuel(add, price)
        end
        if add > EPSILON and reserve <= available then
            row.powerBalanceCents = available - reserve
            local expected = fuel + add
            if setFuel(generator, expected) then
                local actual = math.max(0, (tonumber(U.value(generator, "getFuel", fuel)) or fuel) - fuel)
                local actualCents = centsForFuel(actual, price)
                row.powerBalanceCents = row.powerBalanceCents + math.max(0, reserve - actualCents)
                row.powerReserveFuel = row.powerReserveFuel + actual
                row.powerReserveCents = row.powerReserveCents + actualCents
                row.powerUnitPrice = price
                fuel = fuel + actual
            else
                row.powerBalanceCents = row.powerBalanceCents + reserve
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
    if (not amount or amount <= 0) and props then
        local waterAmount = IsoPropertyType and IsoPropertyType.WATER_AMOUNT or nil
        if waterAmount then amount = tonumber(U.value(props, "get", nil, waterAmount)) end
        if not amount or amount <= 0 then amount = tonumber(U.value(props, "get", nil, "waterAmount")) end
    end
    return math.max(0, amount or 0), container
end

local function hasForeignWaterMarker(modData)
    if type(modData) ~= "table" then return false end
    -- Only a verified ownership marker is evidence of another mod's control.
    return modData.OrangeTradingModUtilityWater ~= nil
        and modData.OrangeTradingModUtilityWater ~= false
end

local function isPipedFixture(object)
    if not object or not IsoFlagType or not IsoFlagType.waterPiped then return false end
    if instanceof and instanceof(object, "IsoFeedingTrough") then return false end
    local props = U.value(object, "getProperties", nil)
    if not props then
        local sprite = U.value(object, "getSprite", nil)
        props = sprite and U.value(sprite, "getProperties", nil) or nil
    end
    if props == nil or U.value(props, "has", false, IsoFlagType.waterPiped) ~= true then return false end
    local modData = U.value(object, "getModData", nil)
    if type(modData) == "table" and modData.canBeWaterPiped == true
        and U.value(object, "getUsesExternalWaterSource", false) ~= true then return false end
    return true
end

local function externalWaterAvailable(object, amount)
    if U.value(object, "getUsesExternalWaterSource", false) ~= true then return false end
    U.call(object, "doFindExternalWaterSource")
    return U.value(object, "hasExternalWaterSource", false) == true and amount > EPSILON
end

local function setWaterAmount(object, modData, container, amount)
    amount = math.max(0, amount)
    local current = tonumber(U.value(object, "getFluidAmount", nil))
    if current == nil then return false end
    local delta = amount - current
    if container and (tonumber(U.value(container, "getCapacity", 0)) or 0) > EPSILON then
        if not FluidType or not FluidType.Water then return false end
        if delta > EPSILON then
            local ok = U.call(object, "addFluid", FluidType.Water, delta)
            if not ok then return false end
        elseif delta < -EPSILON then
            local ok = U.call(object, "useFluid", -delta)
            if not ok then return false end
        end
    elseif math.abs(delta) > EPSILON then
        local nativeOk
        if delta > 0 and FluidType and FluidType.Water then
            nativeOk = U.call(object, "addFluid", FluidType.Water, delta)
        elseif delta < 0 then
            nativeOk = U.call(object, "useFluid", -delta)
        end
        local nativeAmount = tonumber(U.value(object, "getFluidAmount", nil))
        if nativeOk and nativeAmount and math.abs(nativeAmount - amount) <= 0.05 then return true end
        if nativeAmount == nil or math.abs(nativeAmount - current) > 0.05 then return false end
        local previous = modData.waterAmount
        modData.waterAmount = amount
        local updated = tonumber(U.value(object, "getFluidAmount", nil))
        if updated == nil or math.abs(updated - amount) > 0.05 then
            modData.waterAmount = previous
            return false
        end
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
    if not supportsMethod(object, "getFluidAmount") then return false end
    local amountOk, amount = U.call(object, "getFluidAmount")
    if not amountOk or not finite(amount) then return false end
    local container = U.value(object, "getFluidContainer", nil)
    if container and (tonumber(U.value(container, "getCapacity", 0)) or 0) > EPSILON then
        return supportsMethod(object, "addFluid") and supportsMethod(object, "useFluid")
    end
    return type(U.value(object, "getModData", nil)) == "table"
end

local function genWaterKey()
    return U.WaterMarker .. "_Gen"
end

local function genWaterPaidKey()
    return U.WaterMarker .. "_GenPaid"
end

local function genWaterCentsKey()
    return U.WaterMarker .. "_GenCents"
end

function U.generatorWater(generator)
    if not generator then return 0 end
    local modData = U.value(generator, "getModData", nil)
    return math.max(0, tonumber(type(modData) == "table" and modData[genWaterKey()] or 0) or 0)
end

function U.setGeneratorWater(generator, amount)
    if not generator then return false end
    local modData = U.value(generator, "getModData", nil)
    if type(modData) ~= "table" then return false end
    amount = math.max(0, math.min(amount, U.GeneratorWaterCapacity))
    modData[genWaterKey()] = amount
    return true
end

local function genWaterPaid(generator)
    local modData = U.value(generator, "getModData", nil)
    return math.max(0, tonumber(type(modData) == "table" and modData[genWaterPaidKey()] or 0) or 0)
end

local function genWaterCents(generator)
    local modData = U.value(generator, "getModData", nil)
    return math.max(0, tonumber(type(modData) == "table" and modData[genWaterCentsKey()] or 0) or 0)
end

function U.refillGeneratorWater(root, device, generator, requestedLiters)
    if not device or not generator then return false end
    local modData = U.value(generator, "getModData", nil)
    if type(modData) ~= "table" then return false end
    local capacity = U.GeneratorWaterCapacity
    local current = U.generatorWater(generator)
    local room = math.max(0, capacity - current)
    if room < EPSILON then return false end
    if not device.active then return false end
    if not U.featureEnabled("EnableUtilityGenerator") or not U.featureEnabled("EnableUtilityGeneratorWater") then
        return false
    end
    local price = U.waterPrice()
    local available = math.max(0, tonumber(device.waterBalanceCents) or 0)
    local want = math.min(room, math.max(U.WaterBufferLiters, tonumber(requestedLiters) or 0))
    if price > 0 then want = math.min(want, available / price) end
    if want < EPSILON then return false end
    local costCents = math.ceil(want * price - 0.000001)
    if costCents > available then
        want = math.max(0, available / price)
        costCents = math.ceil(want * price - 0.000001)
    end
    if want < EPSILON or costCents > available then return false end
    device.waterBalanceCents = available - costCents
    device.waterReserveCents = (tonumber(device.waterReserveCents) or 0) + costCents
    local newAmount = current + want
    modData[genWaterKey()] = newAmount
    modData[genWaterPaidKey()] = genWaterPaid(generator) + want
    modData[genWaterCentsKey()] = genWaterCents(generator) + costCents
    device.generatorWaterHeld = true
    U.call(generator, "transmitModData")
    return true
end

function U.withdrawGeneratorWater(device, generator, amount)
    if not device or not generator then return false, 0 end
    local current = U.generatorWater(generator)
    if current < amount - EPSILON then return false, 0 end
    local actual = math.min(amount, current)
    local newAmount = current - actual
    local modData = U.value(generator, "getModData", nil)
    if type(modData) == "table" then
        modData[genWaterKey()] = newAmount
        local paid = genWaterPaid(generator)
        local cents = genWaterCents(generator)
        local paidReduction = math.min(paid, actual)
        local spent = 0
        if paid > EPSILON and cents > 0 then
            spent = math.floor(cents * paidReduction / paid + 0.5)
            spent = math.min(spent, cents)
        end
        modData[genWaterPaidKey()] = math.max(0, paid - paidReduction)
        modData[genWaterCentsKey()] = math.max(0, cents - spent)
        device.waterReserveCents = math.max(0, (tonumber(device.waterReserveCents) or 0) - spent)
        device.generatorWaterHeld = newAmount > EPSILON or cents > spent
        U.call(generator, "transmitModData")
    end
    return true, actual
end

function U.releaseGeneratorWaterReserve(device, generator)
    local modData = U.value(generator, "getModData", nil)
    if not device or type(modData) ~= "table" then return false end
    local cents = genWaterCents(generator)
    device.waterBalanceCents = math.max(0, tonumber(device.waterBalanceCents) or 0) + cents
    device.waterReserveCents = math.max(0, (tonumber(device.waterReserveCents) or 0) - cents)
    modData[genWaterKey()], modData[genWaterPaidKey()], modData[genWaterCentsKey()] = nil, nil, nil
    device.generatorWaterHeld = false
    U.call(generator, "transmitModData")
    return true
end

function U.fillCapacity(item)
    local fluid = U.value(item, "getFluidContainer", nil)
    if not fluid then return 0, nil end
    local capacity = tonumber(U.value(fluid, "getCapacity", nil))
    local amount = tonumber(U.value(fluid, "getAmount", nil))
    if not finite(capacity) or not finite(amount) or amount < 0 or capacity <= amount + EPSILON then return 0, nil end
    if amount > EPSILON then
        local primary = U.value(fluid, "getPrimaryFluid", nil)
        if tostring(U.value(primary, "getFluidTypeString", "")) ~= "Water" then return 0, nil end
    end
    return math.max(0, capacity - amount), fluid
end

function U.findFillableContainer(player)
    if not player then return nil end
    local inventory = U.value(player, "getInventory", nil)
    if not inventory or not inventory.getItems then return nil end
    local items = U.value(inventory, "getItems", nil)
    local count = math.max(0, math.floor(tonumber(U.value(items, "size", 0)) or 0))
    for i = 0, count - 1 do
        local item = U.value(items, "get", nil, i)
        if item and U.fillCapacity(item) > EPSILON then return item end
    end
    return nil
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
    local capacity, container = waterCapacity(object, modData)
    local key = fixtureKey(x, y, z, index)
    if not enabled then
        if owner == device.id then return U.releaseWaterFixture(root, device, object, key, modData, container) end
        return false
    end
    if not container or (tonumber(U.value(container, "getCapacity", 0)) or 0) <= EPSILON then
        if modData[U.WaterOriginalMaxSet] ~= true then
            modData[U.WaterOriginalMax] = modData.waterMaxAmount
            modData[U.WaterOriginalMaxSet] = true
        end
        capacity = math.max(capacity, U.FixtureWaterBufferLiters)
        modData.waterMaxAmount = capacity
    end
    if capacity <= EPSILON then return false end
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
    local want = math.min(room, math.max(0, U.FixtureWaterBufferLiters - paid))
    local availableCents = math.max(0, tonumber(device.waterBalanceCents) or 0)
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
                device.waterBalanceCents = math.max(0, availableCents - actualCost)
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
    if paid > EPSILON and not setWaterAmount(object, modData, container, math.max(0, amount - paid)) then
        return false
    end
    if modData[U.WaterOriginalMaxSet] == true then
        modData.waterMaxAmount = modData[U.WaterOriginalMax]
        modData[U.WaterOriginalMax], modData[U.WaterOriginalMaxSet] = nil, nil
    end
    if device then
        device.waterBalanceCents = math.max(0, tonumber(device.waterBalanceCents) or 0) + paidCents
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
    local count, targets = 0, {}
    for id, record in pairs(row and row.waterTargets or {}) do
        count = count + 1
        targets[#targets + 1] = { id = id, label = record.label, kind = record.kind,
            x = record.x, y = record.y, z = record.z }
    end
    table.sort(targets, function(a, b) return a.id < b.id end)
    result.waterFixtureCount = count
    result.waterTargets = targets
    result.waterTargetLiters = row and row.waterTargetLiters or U.DefaultTargetLiters
    if result.waterReason == "ready" and count == 0 and U.generatorWater(generator) <= EPSILON then
        result.waterReason = "noFixture"
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

local function targetSprite(object)
    local name = U.value(object, "getSpriteName", nil)
    if name == nil then
        local sprite = U.value(object, "getSprite", nil)
        name = sprite and U.value(sprite, "getName", nil) or nil
    end
    return tostring(name or "")
end

function U.waterTargetKind(object)
    if not object or U.deviceId(object) or U.value(object, "getModData", nil) == nil then
        return nil, "UtilityGeneratorTargetInvalid"
    end
    local props = U.value(object, "getProperties", nil)
    if not props then
        local sprite = U.value(object, "getSprite", nil)
        props = sprite and U.value(sprite, "getProperties", nil) or nil
    end
    if props and IsoFlagType and IsoFlagType.waterPiped
        and U.value(props, "has", false, IsoFlagType.waterPiped) == true then
        if U.value(object, "getUsesExternalWaterSource", false) ~= true
            or (U.value(object, "getModData", nil) or {}).canBeWaterPiped == true then
            return nil, "UtilityGeneratorTargetNotPlumbed"
        end
        return "fixture"
    end
    if instanceof and not instanceof(object, "IsoThumpable") then
        return nil, "UtilityGeneratorTargetInvalid"
    end
    local fluid = U.value(object, "getFluidContainer", nil)
    local capacity = fluid and tonumber(U.value(fluid, "getCapacity", nil)) or nil
    local amount = fluid and tonumber(U.value(fluid, "getAmount", nil)) or nil
    if not finite(capacity) or not finite(amount) or capacity <= 0 or amount < 0 then
        return nil, "UtilityGeneratorTargetInvalid"
    end
    if amount > EPSILON then
        local primary = U.value(fluid, "getPrimaryFluid", nil)
        if tostring(U.value(primary, "getFluidTypeString", "")) ~= "Water" then
            return nil, "UtilityGeneratorTargetOtherFluid"
        end
    end
    return "container"
end

function U.findWaterTarget(record, adapter)
    local square = adapter and adapter.square and adapter.square(record.x, record.y, record.z) or nil
    if not square then return nil, false end
    local objects = U.value(square, "getObjects", nil)
    local count = math.max(0, math.floor(tonumber(U.value(objects, "size", 0)) or 0))
    for i = 0, count - 1 do
        local object = U.value(objects, "get", nil, i)
        local data = object and U.value(object, "getModData", nil) or nil
        if type(data) == "table" and data[U.TargetMarker] == record.id then return object, true end
    end
    return nil, true
end

function U.bindWaterTarget(root, row, args, env)
    local x, y, z, index = tonumber(args.targetX), tonumber(args.targetY),
        tonumber(args.targetZ), tonumber(args.targetIndex)
    if not finite(x) or not finite(y) or not finite(z) or not finite(index)
        or x ~= math.floor(x) or y ~= math.floor(y) or z ~= math.floor(z)
        or index ~= math.floor(index) or index < 0 or index > 255 then
        return false, "UtilityGeneratorTargetInvalid"
    end
    if not U.isGeneratorSquareAffected(row.x, row.y, row.z, x, y, z) then
        return false, "UtilityGeneratorTargetOutOfRange"
    end
    local square = env.square and env.square(x, y, z) or nil
    local objects = square and U.value(square, "getObjects", nil) or nil
    local object = U.value(objects, "get", nil, index)
    if not object or (args.targetSprite and targetSprite(object) ~= args.targetSprite) then
        return false, "UtilityGeneratorTargetChanged"
    end
    local kind, reason = U.waterTargetKind(object)
    if not kind then return false, reason end
    local data = U.value(object, "getModData", nil)
    if type(data) ~= "table" or hasForeignWaterMarker(data) then
        return false, "UtilityGeneratorTargetOccupied"
    end
    if data[U.WaterMarker] ~= nil then return false, "UtilityGeneratorCleanupPending" end
    local existing = tostring(data[U.TargetMarker] or "")
    if existing ~= "" then
        if row.waterTargets[existing] then return true, "UtilityGeneratorTargetAlreadyBound", { targetId = existing } end
        return false, "UtilityGeneratorTargetOccupied"
    end
    if U.tableCount(row.waterTargets) >= U.WaterFixturesLimit then
        return false, "UtilityGeneratorTargetLimit"
    end
    row.waterTargetSequence = row.waterTargetSequence + 1
    local targetId = row.id .. ":" .. tostring(row.waterTargetSequence)
    local record = { id = targetId, kind = kind, x = x, y = y, z = z,
        label = tostring(U.value(object, "getName", nil) or targetSprite(object)),
        sprite = targetSprite(object) }
    data[U.TargetMarker] = targetId
    row.waterTargets[targetId] = record
    U._targetSquareIndex = nil
    U.call(object, "transmitModData")
    if env.persist then env.persist(root) end
    row.nextWaterTargetMs = 0
    return true, "UtilityGeneratorTargetBound", { targetId = targetId }
end

function U.unbindWaterTarget(root, row, targetId, adapter)
    local record = row.waterTargets[tostring(targetId or "")]
    if not record then return false, "UtilityGeneratorTargetMissing" end
    local object, loaded = U.findWaterTarget(record, adapter)
    if not loaded then return false, "UtilityGeneratorCleanupPending" end
    if record.kind == "fixture" and not U.releaseWaterGhost(row, record, adapter) then
        return false, "UtilityGeneratorCleanupPending"
    end
    if object then
        local data = U.value(object, "getModData", nil)
        if type(data) == "table" and data[U.TargetMarker] == record.id then
            data[U.TargetMarker] = nil
            U.call(object, "transmitModData")
        end
    end
    row.waterTargets[record.id] = nil
    U._targetSquareIndex = nil
    return true, "UtilityGeneratorTargetUnbound"
end

local GHOST_SPRITE = "GodSystem_water_proxy"

function U.ensureWaterGhostSprite()
    if not IsoSpriteManager or not IsoSpriteManager.instance then return false end
    local ok, sprite = pcall(function() return IsoSpriteManager.instance:getSprite(GHOST_SPRITE) end)
    if not ok or not sprite then return false end
    local prepared = pcall(function()
        if sprite:getName() == nil then sprite:setName(GHOST_SPRITE) end
        local props = sprite:getProperties()
        if IsoFlagType and IsoFlagType.blueprint and not props:has(IsoFlagType.blueprint) then
            props:set(IsoFlagType.blueprint)
            props:CreateKeySet()
        end
    end)
    return prepared
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(U.ensureWaterGhostSprite) end

function U.dressWaterGhost(object)
    local data = object and U.value(object, "getModData", nil) or nil
    if type(data) ~= "table" or data[U.GhostMarker] == nil then return false end
    if not U.ensureWaterGhostSprite() then return false end
    U.call(object, "setSpriteFromName", GHOST_SPRITE)
    U.call(object, "setDoRender", false)
    U.call(object, "setOutlineOnMouseover", false)
    U.call(object, "setIsThumpable", false)
    U.call(object, "setSpecialTooltip", false)
    U.call(object, "setName", "")
    U.call(object, "setCanPassThrough", true)
    U.call(object, "setBlockAllTheSquare", false)
    U.call(object, "setCrossSpeed", 1)
    U.call(object, "setCanBarricade", false)
    U.call(object, "setIsContainer", false)
    U.call(object, "setIsDoor", false)
    U.call(object, "setIsDoorFrame", false)
    return true
end

function U.findWaterGhost(record, adapter)
    local square = adapter and adapter.square and adapter.square(record.x, record.y, record.z + 1) or nil
    if not square then return nil, false end
    local objects = U.value(square, "getObjects", nil)
    local count = math.max(0, math.floor(tonumber(U.value(objects, "size", 0)) or 0))
    for i = 0, count - 1 do
        local object = U.value(objects, "get", nil, i)
        local data = object and U.value(object, "getModData", nil) or nil
        if type(data) == "table" and data[U.GhostMarker] == record.id then return object, true end
    end
    return nil, true
end

function U.createWaterGhost(record, adapter)
    local square = adapter and adapter.square and adapter.square(record.x, record.y, record.z + 1) or nil
    if not square or not U.ensureWaterGhostSprite() or not IsoThumpable or not IsoThumpable.new
        or not GameEntityFactory or not ComponentType or not ComponentType.FluidContainer then return nil end
    local currentCell = getCell and getCell() or nil
    if not currentCell then return nil end
    local ok, ghost = pcall(function()
        return IsoThumpable.new(currentCell, square, GHOST_SPRITE, false)
    end)
    if not ok or not ghost then return nil end
    local data = U.value(ghost, "getModData", nil)
    if type(data) ~= "table" then return nil end
    data[U.GhostMarker] = record.id
    data[U.GhostDeviceMarker] = tostring(record.id):match("^(.-):%d+$")
    if not U.dressWaterGhost(ghost) then return nil end
    local added = pcall(function()
        GameEntityFactory.AddComponent(ghost, true, ComponentType.FluidContainer:CreateComponent())
    end)
    local fluid = U.value(ghost, "getFluidContainer", nil)
    if not added or not fluid then return nil end
    U.call(fluid, "setRainCatcher", 0)
    U.call(fluid, "setInputLocked", false)
    U.call(fluid, "setCanPlayerEmpty", true)
    if not U.call(fluid, "setCapacity", U.DefaultTargetLiters) then return nil end
    if not U.call(square, "transmitAddObjectToSquare", ghost, 0)
        or (tonumber(U.value(ghost, "getObjectIndex", -1)) or -1) < 0 then return nil end
    return ghost
end

local function sourceOtherThanOurGhost(record, adapter, fixture)
    local known = U.publicUtilityOn("water")
    if known == true then return true end
    local nativeSource = U.value(fixture, "FindExternalWaterSource", nil)
    if nativeSource then
        local data = U.value(nativeSource, "getModData", nil)
        if not (type(data) == "table" and data[U.GhostMarker] == record.id)
            and (tonumber(U.value(nativeSource, "getFluidAmount", 0)) or 0) > EPSILON then return true end
    end
    for x = record.x - 1, record.x + 1 do
        for y = record.y - 1, record.y + 1 do
            local square = adapter.square and adapter.square(x, y, record.z + 1) or nil
            local objects = square and U.value(square, "getObjects", nil) or nil
            local count = math.max(0, math.floor(tonumber(U.value(objects, "size", 0)) or 0))
            for i = 0, count - 1 do
                local object = U.value(objects, "get", nil, i)
                local data = object and U.value(object, "getModData", nil) or nil
                if object and (not instanceof or instanceof(object, "IsoThumpable"))
                    and not (type(data) == "table" and data[U.GhostMarker] == record.id)
                    and (tonumber(U.value(object, "getFluidCapacity", 0)) or 0) > EPSILON
                    and (tonumber(U.value(object, "getFluidAmount", 0)) or 0) > EPSILON
                    and U.value(object, "getUsesExternalWaterSource", false) ~= true then return true end
            end
        end
    end
    return false
end

local function settleGhostWater(row, record, ghost)
    local current = math.max(0, tonumber(U.value(ghost, "getFluidAmount", 0)) or 0)
    local last = math.max(0, tonumber(record.ghostLastAmount) or current)
    local paid = math.max(0, tonumber(record.ghostPaidLiters) or 0)
    local cents = math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
    local free = math.max(0, tonumber(record.ghostFreeLiters) or 0)
    local changed = math.abs(last - current) > EPSILON
    if current < last - EPSILON then
        local used = last - current
        local freeUsed = math.min(free, used)
        free = free - freeUsed
        local paidUsed = math.min(paid, used - freeUsed)
        local spent = paid > EPSILON and math.min(cents,
            math.ceil(cents * paidUsed / paid - 0.000001)) or 0
        paid, cents = paid - paidUsed, cents - spent
        row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0) - spent)
    elseif current > last + EPSILON then
        free = free + current - last
    end
    record.ghostPaidLiters, record.ghostPaidCents, record.ghostFreeLiters = paid, cents, free
    record.ghostLastAmount = current
    return changed
end

function U.releaseWaterGhost(row, record, adapter)
    local ghost, loaded = U.findWaterGhost(record, adapter)
    if not loaded then return false end
    local missingHeld = 0
    if ghost then
        settleGhostWater(row, record, ghost)
        local square = U.value(ghost, "getSquare", nil)
        if not square or not U.call(square, "transmitRemoveItemFromSquare", ghost) then return false end
        if (tonumber(U.value(ghost, "getObjectIndex", -1)) or -1) >= 0 then return false end
        row.waterBalanceCents = (tonumber(row.waterBalanceCents) or 0)
            + math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
    elseif record.ghostActive then
        -- The source disappeared outside this module. Its water may have been used;
        -- never credit the account for an amount we can no longer verify.
        missingHeld = math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
        record.ghostPaidCents = 0
    end
    local held = math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
    row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0) - held - missingHeld)
    record.ghostPaidLiters, record.ghostPaidCents, record.ghostFreeLiters = 0, 0, 0
    record.ghostLastAmount, record.ghostActive = 0, false
    return true
end

local function refillWaterAmount(row, desired)
    local price = U.waterPrice() -- configured coins / 100 L, numerically cents / L
    local available = math.max(0, math.floor(tonumber(row.waterBalanceCents) or 0))
    if price > 0 then desired = math.min(desired, available / price) end
    desired = math.max(0, math.floor(desired * 1000) / 1000)
    local cost = math.max(0, math.ceil(desired * price - 0.000001))
    if cost > available then return 0, 0 end
    return desired, cost
end

function U.serviceWaterTarget(root, row, record, adapter)
    if row.destroyed then
        local ok = U.unbindWaterTarget(root, row, record.id, adapter)
        return ok == true
    end
    local object, loaded = U.findWaterTarget(record, adapter)
    if not loaded then return false end
    if not object then
        if record.kind == "fixture" and not U.releaseWaterGhost(row, record, adapter) then return false end
        row.waterTargets[record.id] = nil
        U._targetSquareIndex = nil
        return true
    end
    if record.kind == "fixture" then
        local shouldSupply = row.placed and row.active and U.featureEnabled("EnableUtilityGenerator")
            and U.featureEnabled("EnableUtilityGeneratorWater")
            and U.isGeneratorSquareAffected(row.x, row.y, row.z, record.x, record.y, record.z)
            and U.value(object, "getUsesExternalWaterSource", false) == true
            and not sourceOtherThanOurGhost(record, adapter, object)
        if not shouldSupply then return U.releaseWaterGhost(row, record, adapter) end
        local ghost, ghostLoaded = U.findWaterGhost(record, adapter)
        if not ghostLoaded then return false end
        if ghost and not record.ghostActive then
            local unverified = math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
            row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0) - unverified)
            record.ghostPaidLiters, record.ghostPaidCents = 0, 0
            if not U.releaseWaterGhost(row, record, adapter) then return false end
            row.nextWaterTargetMs = 0
            return true
        end
        if not ghost then
            if record.ghostActive then
                local missingHeld = math.max(0, math.floor(tonumber(record.ghostPaidCents) or 0))
                row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0) - missingHeld)
                record.ghostPaidLiters, record.ghostPaidCents, record.ghostFreeLiters = 0, 0, 0
                record.ghostLastAmount, record.ghostActive = 0, false
            end
            ghost = U.createWaterGhost(record, adapter)
            if not ghost then return false end
            record.ghostActive = true
            record.ghostLastAmount = 0
        else
            record.ghostActive = true
        end
        local changed = settleGhostWater(row, record, ghost)
        local fluid = U.value(ghost, "getFluidContainer", nil)
        local current = math.max(0, tonumber(U.value(ghost, "getFluidAmount", 0)) or 0)
        if not fluid then return changed end
        local target = math.max(1, math.min(1000, tonumber(row.waterTargetLiters) or U.DefaultTargetLiters))
        if (tonumber(U.value(fluid, "getCapacity", 0)) or 0) < target then
            U.call(fluid, "setCapacity", target)
        end
        local liters, cost = refillWaterAmount(row, math.max(0, target - current))
        if liters > EPSILON and FluidType and FluidType.Water then
            local before = current
            local ok = U.call(ghost, "addFluid", FluidType.Water, liters)
            local after = math.max(0, tonumber(U.value(ghost, "getFluidAmount", before)) or before)
            local actual = math.max(0, after - before)
            if ok and actual > EPSILON then
                cost = math.max(0, math.ceil(actual * U.waterPrice() - 0.000001))
                if cost <= row.waterBalanceCents then
                    row.waterBalanceCents = row.waterBalanceCents - cost
                    row.waterReserveCents = (tonumber(row.waterReserveCents) or 0) + cost
                    record.ghostPaidLiters = (tonumber(record.ghostPaidLiters) or 0) + actual
                    record.ghostPaidCents = (tonumber(record.ghostPaidCents) or 0) + cost
                    record.ghostLastAmount = after
                    U.call(ghost, "sync")
                    changed = true
                else
                    U.call(ghost, "useFluid", actual)
                    U.call(ghost, "sync")
                end
            end
        end
        return changed
    end
    if not row.placed or not row.active or not U.featureEnabled("EnableUtilityGenerator")
        or not U.featureEnabled("EnableUtilityGeneratorWater")
        or not U.isGeneratorSquareAffected(row.x, row.y, row.z, record.x, record.y, record.z) then return false end
    local fluid = U.value(object, "getFluidContainer", nil)
    local capacity = fluid and tonumber(U.value(fluid, "getCapacity", 0)) or 0
    local current = fluid and tonumber(U.value(fluid, "getAmount", 0)) or 0
    if not finite(capacity) or not finite(current) or current < 0 then return false end
    if current > EPSILON then
        local primary = U.value(fluid, "getPrimaryFluid", nil)
        if tostring(U.value(primary, "getFluidTypeString", "")) ~= "Water" then return false end
    end
    local desired = math.min(math.max(0, capacity - current),
        math.max(0, row.waterTargetLiters - current))
    local liters = refillWaterAmount(row, desired)
    if liters <= EPSILON or not FluidType or not FluidType.Water then return false end
    if not U.call(fluid, "addFluid", FluidType.Water, liters) then return false end
    local after = tonumber(U.value(fluid, "getAmount", current)) or current
    local actual = math.max(0, after - current)
    local cost = math.max(0, math.ceil(actual * U.waterPrice() - 0.000001))
    if actual <= EPSILON then return false end
    if cost > row.waterBalanceCents then
        U.call(fluid, "removeFluid", actual)
        U.call(object, "sync")
        return false
    end
    row.waterBalanceCents = row.waterBalanceCents - cost
    U.call(object, "sync")
    return true
end

function U.scheduleScan(root, id)
    return U.scheduleTargets(root, id)
end

function U.scheduleTargets(root, id)
    bindWorldJobs(root)
    local row = U.ensureDevice(root, id)
    if not row then return false end
    refreshDeviceWatch(root, row)
    local keys = {}
    for key in pairs(row.waterTargets) do keys[#keys + 1] = key end
    table.sort(keys)
    U.jobs[row.id .. ":targets"] = { kind = "targets", id = row.id, keys = keys, cursor = 1 }
    U._nextJobReadyMs = 0
    return true
end

function U.markWaterTargetDirty(root, targetId)
    bindWorldJobs(root)
    targetId = tostring(targetId or "")
    local deviceId = targetId:match("^(.-):%d+$")
    local row = deviceId and root and root.devices and root.devices[deviceId] or nil
    if not row or not row.waterTargets or not row.waterTargets[targetId] then return false end
    local key = deviceId .. ":dirty"
    local job = U.jobs[key]
    if not job then
        job = { kind = "targets", id = deviceId, keys = {}, cursor = 1, queued = {} }
        U.jobs[key] = job
    end
    if not job.queued[targetId] then
        job.keys[#job.keys + 1] = targetId
        job.queued[targetId] = true
    end
    U._nextJobReadyMs = 0
    return true
end

function U.scheduleCleanup(root, id)
    bindWorldJobs(root)
    local row = U.ensureDevice(root, id)
    if not row then return false end
    refreshDeviceWatch(root, row)
    local keys = {}
    for key in pairs(row.waterFixtures) do keys[#keys + 1] = key end
    table.sort(keys)
    U.jobs[tostring(id)] = { kind = "cleanup", id = tostring(id), keys = keys, cursor = 1 }
    U._nextJobReadyMs = 0
    return true
end

local function processCleanup(root, job, adapter, budget, nowMs)
    if nowMs < (tonumber(job.retryAfterMs) or 0) then return false, 0 end
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
                if not U.releaseWaterFixture(root, row, object, key, modData, container) then
                    job.cursor = job.cursor - 1
                    job.retryAfterMs = nowMs + 1000
                    return false, count
                end
            elseif adapter.square and adapter.square(fixture.x, fixture.y, fixture.z) then
                -- The original object is gone. Its unmeasured water may have been used.
                local held = math.max(0, math.floor(tonumber(fixture.paidCents) or 0))
                row.waterReserveCents = math.max(0, (tonumber(row.waterReserveCents) or 0) - held)
                row.waterFixtures[key] = nil
            else
                job.cursor = job.cursor - 1
                job.retryAfterMs = nowMs + 1000
                return false, count
            end
        end
    end
    if job.cursor > #job.keys then return true, count end
    return false, count
end

local function refreshJobReadyTime()
    local earliest = math.huge
    for _, job in pairs(U.jobs) do
        local readyAt = job.kind == "cleanup" and (tonumber(job.retryAfterMs) or 0) or 0
        if readyAt < earliest then earliest = readyAt end
    end
    U._nextJobReadyMs = earliest
end

function U.tick(root, adapter, nowMs)
    root, adapter = root or U.worldData(), adapter or {}
    bindWorldJobs(root)
    nowMs = tonumber(nowMs) or (getTimestampMs and getTimestampMs()) or math.floor(os.time() * 1000)
    root.devices = type(root.devices) == "table" and root.devices or {}
    if nowMs >= (tonumber(U.nextDeviceCheckMs) or 0) then
        U.nextDeviceCheckMs = nowMs + 1000
        local ids = {}
        for id in pairs(U._watchedDeviceIds) do ids[#ids + 1] = id end
        table.sort(ids)
        for i = 1, #ids do
            local row = root.devices[ids[i]] and U.ensureDevice(root, ids[i]) or nil
            if not row then U._watchedDeviceIds[ids[i]] = nil end
            if row and row.placed and adapter.square and adapter.square(row.x, row.y, row.z)
                and adapter.findDevice and not adapter.findDevice(row.id, row.x, row.y, row.z) then
                -- A loaded square without the native generator proves destruction.
                row.placed, row.active, row.destroyed = false, false, true
                row.waterBalanceCents, row.powerBalanceCents = 0, 0
                row.nextWaterTargetMs = 0
                if adapter.persist then adapter.persist(root) end
            end
            if row and U.tableCount(row.waterFixtures) > 0
                and (not U.jobs[row.id] or U.jobs[row.id].kind ~= "cleanup") then
                U.scheduleCleanup(root, row.id)
            end
            if row and row.placed then
                if nowMs >= (tonumber(row.nextPowerPollMs) or 0) then
                    row.nextPowerPollMs = nowMs + U.PowerPollMs
                    local generator = adapter.findDevice and adapter.findDevice(row.id, row.x, row.y, row.z) or nil
                    if generator then U.updatePower(row, generator) end
                end
                local wantsWater = row.active and U.featureEnabled("EnableUtilityGenerator")
                    and U.featureEnabled("EnableUtilityGeneratorWater")
                if U.enabledStates[row.id] ~= wantsWater then
                    U.enabledStates[row.id] = wantsWater
                    row.nextWaterTargetMs = 0
                    U.waterStateChanged[row.id] = true
                end
                if not wantsWater and row.generatorWaterHeld == true then
                    local gen = adapter.findDevice and adapter.findDevice(row.id, row.x, row.y, row.z) or nil
                    if gen then U.releaseGeneratorWaterReserve(row, gen) end
                end
                if hasEntries(row.waterTargets) and (wantsWater or U.waterStateChanged[row.id]
                    or U.inactiveCleanupNeeded[row.id])
                    and not U.jobs[row.id .. ":targets"]
                    and nowMs >= (tonumber(row.nextWaterTargetMs) or 0) then
                    row.nextWaterTargetMs = nowMs + U.WaterScanMs
                    U.scheduleTargets(root, row.id)
                    U.waterStateChanged[row.id] = nil
                end
                if wantsWater and nowMs >= (tonumber(row.nextGeneratorWaterMs) or 0) then
                    row.nextGeneratorWaterMs = nowMs + U.WaterScanMs
                    local gen = adapter.findDevice and adapter.findDevice(row.id, row.x, row.y, row.z) or nil
                    if gen then U.refillGeneratorWater(root, row, gen) end
                end
            elseif row and row.destroyed and U.tableCount(row.waterTargets) > 0
                and not U.jobs[row.id .. ":targets"]
                and nowMs >= (tonumber(row.nextWaterTargetMs) or 0) then
                row.nextWaterTargetMs = nowMs + U.WaterScanMs
                U.scheduleTargets(root, row.id)
            end
            if row then refreshDeviceWatch(root, row) end
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
                local done, processed = processCleanup(root, job, adapter, math.min(32, remaining), nowMs)
                remaining = remaining - processed
                if done then U.jobs[id] = nil end
            elseif job.kind == "targets" then
                local row = U.ensureDevice(root, job.id)
                local processed, dirty = 0, false
                while row and job.cursor <= #job.keys and processed < remaining do
                    local targetId = job.keys[job.cursor]
                    if job.queued then job.queued[targetId] = nil end
                    local record = row.waterTargets[targetId]
                    job.cursor, processed = job.cursor + 1, processed + 1
                    if record then
                        local before = U.tableCount(row.waterTargets)
                        dirty = U.serviceWaterTarget(root, row, record, adapter) or dirty
                        dirty = U.tableCount(row.waterTargets) ~= before or dirty
                    end
                    if getTimestampMs and getTimestampMs() - started >= U.ScanTimeBudgetMs then break end
                end
                remaining = remaining - processed
                if dirty and adapter.persist then adapter.persist(root) end
                if row and row.destroyed then
                    row.waterBalanceCents, row.waterReserveCents = 0, 0
                    if adapter.persist then adapter.persist(root) end
                end
                if not row or job.cursor > #job.keys then
                    U.jobs[id] = nil
                    if row then U.inactiveCleanupNeeded[row.id] = hasUnreleasedWater(row) or nil end
                end
                if U.jobs[id] and job.queued and job.cursor > 64 and job.cursor > #job.keys / 2 then
                    local pending = {}
                    for pendingIndex = job.cursor, #job.keys do
                        pending[#pending + 1] = job.keys[pendingIndex]
                    end
                    job.keys, job.cursor = pending, 1
                end
            end
            if getTimestampMs and getTimestampMs() - started >= U.ScanTimeBudgetMs then break end
        end
    end
    refreshJobReadyTime()
end

function U.onObjectAdded(root, object, adapter)
    bindWorldJobs(root)
    if U.dressWaterGhost(object) then
        local data = U.value(object, "getModData", nil)
        if type(data) == "table" then U.markWaterTargetDirty(root, data[U.GhostMarker]) end
        return true
    end
    local data = U.value(object, "getModData", nil)
    local id = type(data) == "table" and tostring(data[U.TargetMarker] or "") or ""
    local deviceId = id:match("^(.-):%d+$")
    local row = deviceId and root and root.devices and root.devices[deviceId] or nil
    if row and row.waterTargets[id] then U.markWaterTargetDirty(root, id); return true end
    if id ~= "" and type(data) == "table" and adapter and adapter.authoritative then
        data[U.TargetMarker] = nil
        U.call(object, "transmitModData")
    end
    return false
end

function U.onSquareLoaded(root, square)
    if U._targetIndexRoot ~= root or not U._targetSquareIndex then
        local index = {}
        for _, row in pairs(root and root.devices or {}) do
            for _, record in pairs(row.waterTargets or {}) do
                local key = tostring(record.x) .. ":" .. tostring(record.y) .. ":" .. tostring(record.z)
                index[key] = true
                if record.kind == "fixture" then
                    index[tostring(record.x) .. ":" .. tostring(record.y) .. ":" .. tostring(record.z + 1)] = true
                end
            end
        end
        U._targetSquareIndex, U._targetIndexRoot = index, root
    end
    local key = tostring(U.value(square, "getX", "")) .. ":"
        .. tostring(U.value(square, "getY", "")) .. ":" .. tostring(U.value(square, "getZ", ""))
    if not U._targetSquareIndex[key] and not (isClient and isClient()) then return end
    local objects = U.value(square, "getObjects", nil)
    local count = math.max(0, math.floor(tonumber(U.value(objects, "size", 0)) or 0))
    for i = 0, count - 1 do
        local object = U.value(objects, "get", nil, i)
        local data = U.value(object, "getModData", nil)
        if type(data) == "table" then
            if data[U.GhostMarker] then U.dressWaterGhost(object) end
            local id = tostring(data[U.TargetMarker] or data[U.GhostMarker] or "")
            local deviceId = id:match("^(.-):%d+$")
            local row = deviceId and root and root.devices and root.devices[deviceId] or nil
            if row and row.waterTargets[id] then U.markWaterTargetDirty(root, id) end
        end
    end
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
        refreshDeviceWatch(root, row)
        row.waterFixtures = row.waterFixtures or {}
        if U.tableCount(row.waterFixtures) > 0 then U.scheduleCleanup(root, id) end
        row.nextWaterTargetMs = 0
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
    if action == "bindWaterTarget" then
        local ok, code, payload = U.bindWaterTarget(root, row, args, env)
        if ok then row.nextWaterTargetMs = 0 end
        return ok, code, payload
    end
    if action == "unbindWaterTarget" then
        local ok, code = U.unbindWaterTarget(root, row, args.targetId, env)
        if ok and env.persist then env.persist(root) end
        return ok, code
    end
    if action == "setWaterTargetLiters" then
        local liters = tonumber(args.liters)
        if not finite(liters) or liters ~= math.floor(liters) or liters < 1 or liters > 1000 then
            return false, "UtilityGeneratorTargetAmountInvalid"
        end
        row.waterTargetLiters = liters
        row.nextWaterTargetMs = 0
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorTargetAmountSaved", { liters = liters }
    end
    if action == "fill" then
        if not row.active or not U.featureEnabled("EnableUtilityGenerator")
            or not U.featureEnabled("EnableUtilityGeneratorWater") then return false, "UtilityGeneratorStopped" end
        local item = env.findItem and env.findItem(player, args.itemId) or nil
        local capacity, fluid = U.fillCapacity(item)
        if not fluid then return false, "UtilityGeneratorNoContainer" end
        local current = U.generatorWater(generator)
        if current + EPSILON < capacity then
            U.refillGeneratorWater(root, row, generator, capacity - current)
            current = U.generatorWater(generator)
        end
        local liters = math.min(capacity, current)
        if liters < EPSILON then return false, "UtilityGeneratorNoWater" end
        if not FluidType or not FluidType.Water then return false, "UtilityGeneratorUnavailable" end
        local before = tonumber(U.value(fluid, "getAmount", nil))
        local added = U.call(fluid, "addFluid", FluidType.Water, liters)
        local after = tonumber(U.value(fluid, "getAmount", nil))
        if not added or not after or not before or after <= before + EPSILON then
            return false, "UtilityGeneratorFillFailed"
        end
        local actual = math.min(current, after - before)
        if not U.withdrawGeneratorWater(row, generator, actual) then return false, "UtilityGeneratorFillFailed" end
        U.call(item, "syncItemFields")
        if sendItemStats then pcall(sendItemStats, item) end
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorFillDone", { amount = actual, itemId = U.itemId(item) }
    end
    if action == "drink" then
        if not row.active or not U.featureEnabled("EnableUtilityGenerator")
            or not U.featureEnabled("EnableUtilityGeneratorWater") then return false, "UtilityGeneratorStopped" end
        local current = U.generatorWater(generator)
        if current < U.DrinkLiters - EPSILON then return false, "UtilityGeneratorNoWater" end
        if not FluidContainer or not FluidContainer.CreateContainer or not FluidType or not FluidType.Water
            then return false, "UtilityGeneratorUnavailable" end
        local temporary = FluidContainer.CreateContainer()
        if not temporary then return false, "UtilityGeneratorUnavailable" end
        if not U.call(temporary, "setCapacity", U.DrinkLiters) then
            FluidContainer.DisposeContainer(temporary)
            return false, "UtilityGeneratorDrinkFailed"
        end
        local filled = U.call(temporary, "addFluid", FluidType.Water, U.DrinkLiters)
        local volume = tonumber(U.value(temporary, "getAmount", 0)) or 0
        if not filled or volume < U.DrinkLiters - EPSILON then
            FluidContainer.DisposeContainer(temporary)
            return false, "UtilityGeneratorDrinkFailed"
        end
        local drank = U.call(player, "DrinkFluid", temporary, 1)
        FluidContainer.DisposeContainer(temporary)
        if not drank then return false, "UtilityGeneratorDrinkFailed" end
        local ok, actual = U.withdrawGeneratorWater(row, generator, U.DrinkLiters)
        if not ok then return false, "UtilityGeneratorDrinkFailed" end
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorDrinkDone", { amount = actual }
    end
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
        local utility = args.utility or "water" -- older in-flight requests keep their original destination
        if utility ~= "water" and utility ~= "power" then return false, "UtilityGeneratorAmountInvalid" end
        if not finite(args.amount) then return false, "UtilityGeneratorAmountInvalid" end
        local amount = math.max(0, math.min(1000000, math.floor(tonumber(args.amount) or 0)))
        if amount <= 0 then return false, "UtilityGeneratorAmountInvalid" end
        local field = utility == "power" and "powerBalanceCents" or "waterBalanceCents"
        local balance = math.max(0, math.floor(tonumber(row[field]) or 0))
        if balance > 214748364700 - amount * 100 then return false, "UtilityGeneratorBalanceLimit" end
        if not env.spendCurrency or not env.spendCurrency(player, amount) then return false, "CurrencyNotEnough" end
        row[field] = balance + amount * 100
        if row.active then
            U.updatePower(row, generator)
            U.refillGeneratorWater(root, row, generator)
        end
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorCharged", { amount = amount, utility = utility,
            waterBalanceCents = row.waterBalanceCents, powerBalanceCents = row.powerBalanceCents }
    end
    if action == "active" then
        row.active = args.active == true
        if not row.active then
            U.call(generator, "setActivated", false)
            if not U.releasePowerReserve(row, generator) then return false, "UtilityGeneratorStopFailed" end
            U.releaseGeneratorWaterReserve(row, generator)
        else
            U.updatePower(row, generator)
            U.refillGeneratorWater(root, row, generator)
        end
        row.nextWaterTargetMs = 0
        U.scheduleTargets(root, id)
        if env.persist then env.persist(root) end
        return true, row.active and "UtilityGeneratorStarted" or "UtilityGeneratorStopped", { active = row.active }
    end
    if action == "pickup" then
        row.active = false
        U.call(generator, "setActivated", false)
        if not U.releasePowerReserve(row, generator) then return false, "UtilityGeneratorStopFailed" end
        U.releaseGeneratorWaterReserve(row, generator)
        for _, record in pairs(row.waterTargets or {}) do
            if record.kind == "fixture" and not U.releaseWaterGhost(row, record, env) then
                if env.persist then env.persist(root) end
                return false, "UtilityGeneratorCleanupPending"
            end
        end
        if env.cleanupWater and env.cleanupWater(id, generator, row) ~= true then
            U.scheduleCleanup(root, id)
            if env.persist then env.persist(root) end
            return false, "UtilityGeneratorCleanupPending"
        end
        local success, item = false, nil
        if env.pickup then success, item = env.pickup(player, generator, id) end
        if not success then return false, "UtilityGeneratorPickupFailed" end
        row.placed, row.x, row.y, row.z = false, nil, nil, nil
        refreshDeviceWatch(root, row)
        if env.persist then env.persist(root) end
        return true, "UtilityGeneratorPickedUp", { deviceId = id }
    end
    return false, "UtilityGeneratorActionInvalid"
end

return U
