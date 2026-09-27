local function load(path) return assert(loadstring(readSource(path)))() end
local currentTest = ""
local function eq(a, b, message) assert(a == b, currentTest .. ": " .. (message or (tostring(a) .. " ~= " .. tostring(b)))) end
local function test(name, fn) currentTest = name; fn(); print("PASS utility generator: " .. name) end

GodSystemB42JavaCalls = {
    try = function(target, method, ...)
        if not target or type(target[method]) ~= "function" then return false, nil end
        return pcall(target[method], target, ...)
    end,
    value = function(target, method, fallback, ...)
        local ok, value = GodSystemB42JavaCalls.try(target, method, ...)
        if ok and value ~= nil then return value end
        return fallback
    end,
}
GodSystemConfig = { DataKey = "TestData" }
SandboxVars = { GodSystem = {
    EnableUtilityGenerator = true,
    EnableUtilityGeneratorWater = true,
    EnableUtilityGeneratorElectricity = true,
    UtilityGeneratorWaterPricePer100L = 20,
    UtilityGeneratorElectricityPricePerFuelUnit = 5,
}, GeneratorTileRange = 1, GeneratorVerticalPowerRange = 0 }
IsoFlagType = { waterPiped = "waterPiped" }
FluidType = { Water = "water" }
local originalWaterCheck
local U = load("shared/GodSystem_UtilityGenerator.lua")
originalWaterCheck = U.publicUtilityOn
U.publicUtilityOn = function() return false, true end

local function square()
    return { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
end

local function waterFixture()
    local properties = { has = function(_, flag) return flag == IsoFlagType.waterPiped end }
    local fluid = { getCapacity = function() return 100 end }
    local object = {
        amount = 0,
        modData = {},
        getModData = function(self) return self.modData end,
        getProperties = function() return properties end,
        getFluidAmount = function(self) return self.amount end,
        getFluidCapacity = function() return 100 end,
        getFluidContainer = function() return fluid end,
        addFluid = function(self, _, amount) self.amount = self.amount + amount end,
        useFluid = function(self, amount) self.amount = math.max(0, self.amount - amount) end,
        transmitModData = function(self) self.transmits = (self.transmits or 0) + 1 end,
        getUsesExternalWaterSource = function() return false end,
    }
    return object
end

test("water uses exact cents, settles consumption, and refunds unused reserve", function()
    local root = { devices = {} }
    local device = { id = "UG-1", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 8000); eq(device.waterReserveCents, 2000)
    eq(fixture.modData[U.WaterPaid], 100); eq(device.waterFixtures["5:6:0:1"].paidCents, 2000)
    fixture.amount = 95
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 7900); eq(device.waterReserveCents, 2000)
    assert(U.releaseWaterFixture(root, device, fixture, "5:6:0:1", fixture.modData, fixture:getFluidContainer()))
    eq(fixture.amount, 0); eq(device.waterBalanceCents, 9900); eq(device.waterReserveCents, 0)
    eq(fixture.modData[U.WaterMarker], nil)
end)

test("water price changes preserve prepaid stock and price only new refills", function()
    local root = { devices = {} }
    local device = { id = "UG-1c", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 8000); eq(device.waterReserveCents, 2000)
    SandboxVars.GodSystem.UtilityGeneratorWaterPricePer100L = 40
    fixture.amount = 95
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 7800); eq(device.waterReserveCents, 2100)
    SandboxVars.GodSystem.UtilityGeneratorWaterPricePer100L = 20
end)

test("water limits a partial refill to the remaining cent balance", function()
    local root = { devices = {} }
    local device = { id = "UG-1b", active = true, waterBalanceCents = 10, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 0.5)
    eq(device.waterBalanceCents, 0)
    eq(device.waterReserveCents, 10)
end)

test("existing third-party water ownership is left untouched", function()
    local root = { devices = {} }
    local device = { id = "UG-2", active = true, waterBalanceCents = 10000, waterFixtures = {} }
    local fixture = waterFixture()
    fixture.modData.OrangeTradingModUtilityWater = true
    assert(not U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 0); eq(device.waterBalanceCents, 10000); eq(fixture.modData[U.WaterMarker], nil)
end)

test("fixed piped sink without a FluidContainer uses verified native reserve and restores its capacity", function()
    local root = { devices = {} }
    local device = { id = "UG-sink", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    local fixture = { modData = { canBeWaterPiped = false }, transmits = 0,
        getModData = function(self) return self.modData end,
        getProperties = function() return { has = function(_, flag) return flag == IsoFlagType.waterPiped end } end,
        getFluidAmount = function(self) return self.modData.waterAmount or 0 end,
        getFluidCapacity = function() return 0 end,
        getFluidContainer = function() return nil end,
        addFluid = function() end, useFluid = function() end,
        transmitModData = function(self) self.transmits = self.transmits + 1 end,
        getUsesExternalWaterSource = function() return false end }
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture:getFluidAmount(), 100); eq(fixture.modData.waterMaxAmount, 100)
    eq(device.waterBalanceCents, 8000); eq(device.waterReserveCents, 2000)
    fixture.modData.waterAmount = 80
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture:getFluidAmount(), 100); eq(device.waterBalanceCents, 7600)
    eq(device.waterReserveCents, 2000)
    assert(U.releaseWaterFixture(root, device, fixture, "5:6:0:1", fixture.modData))
    eq(fixture:getFluidAmount(), 0); eq(fixture.modData.waterMaxAmount, nil)
    eq(device.waterBalanceCents, 9600); eq(device.waterReserveCents, 0)
    assert(fixture.transmits >= 3)
end)

test("unplumbed moveable sink and unrelated vanilla water data are handled correctly", function()
    local root = { devices = {} }
    local device = { id = "UG-pipe", active = true, waterBalanceCents = 10000, waterFixtures = {} }
    local fixture = waterFixture()
    fixture.modData.canBeWaterPiped = true
    assert(not U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    fixture.modData.canBeWaterPiped = false
    fixture.modData.waterFilterRemaining = 10
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
end)

test("failed native water removal cannot refund a still-filled fixture", function()
    local root = { devices = {} }
    local device = { id = "UG-stuck", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    local fixture = waterFixture()
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    fixture.useFluid = function() end
    assert(not U.releaseWaterFixture(root, device, fixture, "5:6:0:1", fixture.modData, fixture:getFluidContainer()))
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 8000)
    eq(device.waterReserveCents, 2000); eq(fixture.modData[U.WaterMarker], device.id)
end)

test("water uses the native fluid API and ignores marker-only objects", function()
    local root = { devices = {} }
    local device = { id = "UG-2b", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local unsupported = { modData = { waterAmount = 0, waterMaxAmount = 100 },
        getModData = function(self) return self.modData end,
        getProperties = function() return { has = function() return true end } end }
    assert(not U.updateWaterFixture(root, device, unsupported, 5, 6, 0, 1))
    eq(device.waterBalanceCents, 10000)
    eq(unsupported.modData[U.WaterMarker], nil)
    local native = waterFixture()
    native.getFluidContainer = function() return nil end
    assert(U.updateWaterFixture(root, device, native, 5, 6, 0, 1))
    eq(native.amount, 100)
end)

test("water and power remain enabled while public utilities are available", function()
    local root = { devices = {} }
    local device = { id = "UG-3", active = true, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    local fixture = waterFixture()
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    U.publicUtilityOn = function(kind) return kind == "water", true end
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 100); eq(device.waterBalanceCents, 8000); eq(fixture.modData[U.WaterMarker], device.id)
    local status = U.describeStatus(device, { getFuel = function() return 1 end,
        getMaxFuel = function() return 100 end, isActivated = function() return true end })
    eq(status.waterReason, "ready"); eq(status.electricityReason, "ready")
    U.publicUtilityOn = function() return false, true end
end)

test("generator water is billed on authoritative fill and drink, then unused reserve is refunded", function()
    local root = { devices = { ["UG-tank"] = { id = "UG-tank", placed = true, active = true,
        x = 5, y = 6, z = 0, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} } } }
    local row = root.devices["UG-tank"]
    local generator = { modData = { [U.ObjectMarker] = "UG-tank" },
        getModData = function(self) return self.modData end, getSquare = square,
        transmitModData = function() end }
    local fluid = { amount = 0, capacity = 2,
        getAmount = function(self) return self.amount end,
        getCapacity = function(self) return self.capacity end,
        addFluid = function(self, _, amount) self.amount = self.amount + amount end }
    local item = { getID = function() return 77 end, getFluidContainer = function() return fluid end,
        syncItemFields = function(self) self.synced = true end }
    local player = { getX = function() return 5 end, getY = function() return 6 end,
        getZ = function() return 0 end, DrinkFluid = function(self) self.drank = true end }
    local env = { root = root, findDevice = function() return generator end,
        findItem = function(_, id) if tostring(id) == "77" then return item end end,
        persist = function() return true end }
    assert(U.refillGeneratorWater(root, row, generator))
    eq(U.generatorWater(generator), 10); eq(row.waterBalanceCents, 9800); eq(row.waterReserveCents, 200)
    local ok, code = U.execute(player, { action = "fill", deviceId = row.id, itemId = "77" }, env)
    assert(ok); eq(code, "UtilityGeneratorFillDone"); eq(fluid.amount, 2)
    eq(U.generatorWater(generator), 8); eq(row.waterBalanceCents, 9800); eq(row.waterReserveCents, 160)
    assert(item.synced)
    local oldFluidContainer = FluidContainer
    FluidContainer = { CreateContainer = function()
        return { amount = 0, setCapacity = function(self, value) self.capacity = value end,
            addFluid = function(self, _, amount) self.amount = self.amount + amount end,
            getAmount = function(self) return self.amount end }
    end, DisposeContainer = function() end }
    ok, code = U.execute(player, { action = "drink", deviceId = row.id }, env)
    FluidContainer = oldFluidContainer
    assert(ok); eq(code, "UtilityGeneratorDrinkDone"); assert(player.drank)
    eq(U.generatorWater(generator), 7.5); eq(row.waterBalanceCents, 9800); eq(row.waterReserveCents, 150)
    assert(U.releaseGeneratorWaterReserve(row, generator))
    eq(row.waterBalanceCents, 9950); eq(row.waterReserveCents, 0); eq(U.generatorWater(generator), 0)
end)

test("one fill can draw more than the idle tank buffer when the container has room", function()
    local root = { devices = { ["UG-large-fill"] = { id = "UG-large-fill", placed = true, active = true,
        x = 5, y = 6, z = 0, waterBalanceCents = 10000, waterReserveCents = 0, waterFixtures = {} } } }
    local row = root.devices["UG-large-fill"]
    local generator = { modData = { [U.ObjectMarker] = row.id },
        getModData = function(self) return self.modData end, getSquare = square,
        transmitModData = function() end }
    local fluid = { amount = 0, getAmount = function(self) return self.amount end,
        getCapacity = function() return 20 end,
        addFluid = function(self, _, amount) self.amount = self.amount + amount end }
    local item = { getID = function() return 78 end, getFluidContainer = function() return fluid end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local env = { root = root, findDevice = function() return generator end,
        findItem = function() return item end }
    assert(U.refillGeneratorWater(root, row, generator))
    local ok = U.execute(player, { action = "fill", deviceId = row.id, itemId = "78" }, env)
    assert(ok); eq(fluid.amount, 20); eq(U.generatorWater(generator), 0)
    eq(row.waterBalanceCents, 9600); eq(row.waterReserveCents, 0)
end)

test("non-fluid items and failed fill cannot spend device water", function()
    local root = { devices = { ["UG-safe"] = { id = "UG-safe", placed = true, active = true,
        x = 5, y = 6, z = 0, waterBalanceCents = 1000, waterReserveCents = 0, waterFixtures = {} } } }
    local row = root.devices["UG-safe"]
    local generator = { modData = { [U.ObjectMarker] = row.id },
        getModData = function(self) return self.modData end, getSquare = square,
        transmitModData = function() end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    U.refillGeneratorWater(root, row, generator)
    local before = U.generatorWater(generator)
    local env = { root = root, findDevice = function() return generator end,
        findItem = function() return { getUsedDelta = function() return 0 end } end }
    local ok, code = U.execute(player, { action = "fill", deviceId = row.id, itemId = "bad" }, env)
    assert(not ok); eq(code, "UtilityGeneratorNoContainer"); eq(U.generatorWater(generator), before)
end)

test("legacy shared balance migrates once to water without changing prepaid reserves", function()
    local root = { devices = { ["UG-legacy"] = { id = "UG-legacy", balanceCents = 12345,
        powerReserveCents = 500, waterReserveCents = 250, waterFixtures = {} } } }
    local row = U.ensureDevice(root, "UG-legacy")
    eq(row.waterBalanceCents, 12345); eq(row.powerBalanceCents, 0)
    eq(row.balanceCents, nil); eq(row.powerReserveCents, 500); eq(row.waterReserveCents, 250)
    eq(U.ensureDevice(root, "UG-legacy").waterBalanceCents, 12345)
    local old = U.fingerprint({ action = "charge", amount = 100 })
    eq(old, "charge|||100|false|-1|-1|-1")
    assert(old ~= U.fingerprint({ action = "charge", amount = 100, utility = "water" }))
    assert(U.fingerprint({ action = "charge", amount = 100, utility = "water" })
        ~= U.fingerprint({ action = "charge", amount = 100, utility = "power" }))
end)

test("charging chooses one account, validates its limit, and never moves the other account", function()
    local root = { devices = { ["UG-4"] = { id = "UG-4", placed = true, active = false, x = 5, y = 6, z = 0, waterBalanceCents = 0, waterFixtures = {} } } }
    local generator = { modData = { [U.ObjectMarker] = "UG-4" }, getModData = function(self) return self.modData end,
        getSquare = square, getActivated = function() return false end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local spent = 0
    local env = { root = root, findDevice = function() return generator end,
        spendCurrency = function(_, amount) spent = spent + amount; return true end,
        persist = function() return true end }
    local ok = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 500, utility = "water" }, env)
    assert(ok); eq(spent, 500); eq(root.devices["UG-4"].waterBalanceCents, 50000)
    ok = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 100, utility = "power" }, env)
    assert(ok); eq(spent, 600); eq(root.devices["UG-4"].waterBalanceCents, 50000)
    eq(root.devices["UG-4"].powerBalanceCents, 10000)
    root.devices["UG-4"].waterBalanceCents = 214748364650
    local second = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 1, utility = "water" }, env)
    assert(not second); eq(spent, 600)
    second = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 1, utility = "invalid" }, env)
    assert(not second); eq(spent, 600)
    second = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 0 / 0, utility = "power" }, env)
    assert(not second); eq(spent, 600)
    ok = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 1, utility = "power" }, env)
    assert(ok); eq(spent, 601); eq(root.devices["UG-4"].powerBalanceCents, 10100)
end)

test("electricity bills actual native fuel use and refunds unused reserve on stop", function()
    local oldPublic = U.publicUtilityOn
    U.publicUtilityOn = function(kind) return kind == "water", true end
    local row = { id = "UG-power", active = true, waterBalanceCents = 12345, powerBalanceCents = 50000,
        powerReserveCents = 0, powerReserveFuel = 0 }
    local generator = { fuel = 0, active = false,
        getFuel = function(self) return self.fuel end,
        getMaxFuel = function() return 100 end,
        setFuel = function(self, value) self.fuel = value end,
        setActivated = function(self, value) self.active = value end,
        isActivated = function(self) return self.active end,
        setConnected = function() end,
        sync = function() end,
    }
    assert(U.updatePower(row, generator))
    eq(generator.fuel, 10); eq(row.powerBalanceCents, 45000); eq(row.powerReserveCents, 5000)
    generator.fuel = 8
    assert(U.updatePower(row, generator))
    eq(row.powerReserveFuel, 10); eq(row.powerReserveCents, 5000)
    eq(row.powerBalanceCents, 44000); eq(row.waterBalanceCents, 12345)
    row.active = false
    U.updatePower(row, generator)
    eq(generator.fuel, 0); eq(generator.active, false)
    eq(row.powerBalanceCents, 49000); eq(row.waterBalanceCents, 12345); eq(row.powerReserveCents, 0)
    U.publicUtilityOn = oldPublic
end)

test("water credit cannot be spent on electricity", function()
    local row = { id = "UG-water-only", active = true, waterBalanceCents = 10000,
        powerBalanceCents = 0, powerReserveCents = 0, powerReserveFuel = 0 }
    local generator = { fuel = 0, active = false,
        getFuel = function(self) return self.fuel end, getMaxFuel = function() return 100 end,
        setFuel = function(self, value) self.fuel = value end,
        setActivated = function(self, value) self.active = value end,
        isActivated = function(self) return self.active end,
        setConnected = function() end, sync = function() end }
    assert(U.updatePower(row, generator))
    eq(generator.fuel, 0); eq(generator.active, false)
    eq(row.waterBalanceCents, 10000); eq(row.powerBalanceCents, 0)
    eq(U.describeStatus(row, generator).electricityReason, "insufficient")
end)

test("one start enables both funded services and one stop clears both reserves", function()
    local row = { id = "UG-both", active = true, placed = true, x = 5, y = 6, z = 0,
        waterBalanceCents = 10000, powerBalanceCents = 10000,
        powerReserveCents = 0, powerReserveFuel = 0, waterReserveCents = 0, waterFixtures = {} }
    local root = { devices = { [row.id] = row } }
    local generator = { fuel = 0, active = false, modData = { [U.ObjectMarker] = row.id },
        getModData = function(self) return self.modData end, getSquare = square,
        getFuel = function(self) return self.fuel end, getMaxFuel = function() return 100 end,
        setFuel = function(self, value) self.fuel = value end,
        setActivated = function(self, value) self.active = value end,
        isActivated = function(self) return self.active end,
        setConnected = function() end, sync = function() end, transmitModData = function() end }
    local fixture = waterFixture()
    assert(U.updatePower(row, generator))
    assert(U.updateWaterFixture(root, row, fixture, 5, 6, 0, 1))
    assert(U.refillGeneratorWater(root, row, generator))
    eq(generator.active, true); eq(fixture.amount, 100)
    eq(row.powerBalanceCents, 5000); eq(row.waterBalanceCents, 7800)
    local status = U.status(root, row, generator)
    eq(status.powerBalanceCents, 5000); eq(status.waterBalanceCents, 7800)
    eq(status.powerReserveCents, 5000); eq(status.waterReserveCents, 2200)
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local ok = U.execute(player, { action = "active", active = false, deviceId = row.id },
        { root = root, findDevice = function() return generator end,
            scheduleScan = function(id) return U.scheduleScan(root, id) end })
    assert(ok); eq(generator.active, false); eq(generator.fuel, 0)
    eq(U.generatorWater(generator), 0)
    U.tick(root, { fixture = function() return fixture end }, 1000)
    U.tick(root, { fixture = function() return fixture end }, 1001)
    eq(fixture.amount, 0); eq(fixture.modData[U.WaterMarker], nil)
    eq(row.powerBalanceCents, 10000); eq(row.waterBalanceCents, 10000)
end)

test("placement and pickup preserve device identity and both balances", function()
    local root = { devices = {} }
    local item = { id = "item-1", fullType = U.FullType, modData = {},
        getID = function(self) return self.id end,
        getFullType = function(self) return self.fullType end,
        getModData = function(self) return self.modData end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local generator
    local env = { root = root, findItem = function() return item, {} end,
        square = function() return square() end,
        createGenerator = function(_, id)
            generator = { modData = { [U.ObjectMarker] = id }, getModData = function(self) return self.modData end,
                getSquare = square, getFuel = function() return 0 end, setFuel = function() end,
                setActivated = function() end, sync = function() end }
            return true, generator
        end,
        removeItem = function() return true end,
        removeGenerator = function() return true end,
        findDevice = function() return generator end,
        cleanupWater = function() return true end,
        pickup = function(_, _, id)
            return true, { modData = { [U.ItemMarker] = id } }
        end,
        persist = function() return true end,
    }
    local placed, _, payload = U.execute(player, { action = "place", itemId = "item-1", x = 5, y = 6, z = 0 }, env)
    assert(placed); assert(root.devices[payload.deviceId].placed)
    root.devices[payload.deviceId].waterBalanceCents = 12345
    root.devices[payload.deviceId].powerBalanceCents = 6789
    local pickedUp = U.execute(player, { action = "pickup", deviceId = payload.deviceId, x = 5, y = 6, z = 0 }, env)
    assert(pickedUp)
    eq(root.devices[payload.deviceId].placed, false)
    eq(root.devices[payload.deviceId].waterBalanceCents, 12345)
    eq(root.devices[payload.deviceId].powerBalanceCents, 6789)
end)

test("failed first placement does not leave an orphan device record", function()
    local root = { devices = {} }
    local item = { id = "item-fail", fullType = U.FullType, modData = {},
        getID = function(self) return self.id end,
        getFullType = function(self) return self.fullType end,
        getModData = function(self) return self.modData end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local env = { root = root, findItem = function() return item, {} end,
        square = function() return square() end, createGenerator = function() return false, nil end }
    local ok = U.execute(player, { action = "place", itemId = "item-fail", x = 5, y = 6, z = 0 }, env)
    assert(not ok); eq(U.tableCount(root.devices), 0)
end)

test("manual targets never scan the generator range", function()
    U.jobs = {}
    SandboxVars.GeneratorTileRange = 20
    local root = { devices = { ["UG-5"] = { id = "UG-5", placed = true, active = true, x = 0, y = 0, z = 0, waterFixtures = {} } } }
    assert(U.scheduleScan(root, "UG-5"))
    local scanned, persisted = 0, 0
    U.tick(root, { square = function() scanned = scanned + 1; return nil end,
        persist = function() persisted = persisted + 1 end }, 1000)
    assert(scanned <= 1)
    eq(persisted, 0)
    assert(not U.hasPendingWork())
    local first = scanned
    U.tick(root, { square = function() scanned = scanned + 1; return nil end }, 1001)
    eq(scanned, first)
    SandboxVars.GeneratorTileRange = 1
end)

test("binding is server-validated, persists by device, and direct container fills only to target", function()
    U.jobs = {}; U._jobsRoot = nil
    local root = { devices = { ["UG-manual"] = { id = "UG-manual", placed = true, active = true,
        x = 5, y = 6, z = 0, waterBalanceCents = 1000 } } }
    local row = U.ensureDevice(root, "UG-manual")
    local fluid = { amount = 3,
        getCapacity = function() return 50 end,
        getAmount = function(self) return self.amount end,
        getPrimaryFluid = function() return { getFluidTypeString = function() return "Water" end } end,
        addFluid = function(self, _, amount) self.amount = self.amount + amount end,
        removeFluid = function(self, amount) self.amount = self.amount - amount end }
    local target = { modData = {}, getModData = function(self) return self.modData end,
        getFluidContainer = function() return fluid end,
        getSpriteName = function() return "barrel_01" end,
        getName = function() return "Rain Barrel" end,
        transmitModData = function() end, sync = function() end }
    local objects = { size = function() return 1 end, get = function(_, index) return index == 0 and target or nil end }
    local grid = { getObjects = function() return objects end }
    local adapter = { square = function(x, y, z) return x == 6 and y == 6 and z == 0 and grid or nil end }
    local args = { targetX = 6, targetY = 6, targetZ = 0, targetIndex = 0, targetSprite = "barrel_01" }
    local ok, _, payload = U.bindWaterTarget(root, row, args, adapter)
    assert(ok and payload.targetId == target.modData[U.TargetMarker])
    assert(not U.bindWaterTarget(root, row, { targetX = 6, targetY = 6, targetZ = 0,
        targetIndex = 0, targetSprite = "wrong" }, adapter))
    assert(U.serviceWaterTarget(root, row, row.waterTargets[payload.targetId], adapter))
    eq(fluid.amount, 10); eq(row.waterBalanceCents, 860); eq(row.waterReserveCents, 0)
    row.active = false
    eq(fluid.amount, 10)
    local removed = U.unbindWaterTarget(root, row, payload.targetId, adapter)
    assert(removed); eq(target.modData[U.TargetMarker], nil)
    eq(U.tableCount(row.waterTargets), 0)
end)

test("fixture reserve settles use and refunds unused stock on stop", function()
    U.jobs = {}; U._jobsRoot = nil
    local root = { devices = { ["UG-tap"] = { id = "UG-tap", placed = true, active = true,
        x = 5, y = 6, z = 0, waterBalanceCents = 1000 } } }
    local row = U.ensureDevice(root, "UG-tap")
    local record = { id = "UG-tap:1", kind = "fixture", x = 6, y = 6, z = 0,
        ghostActive = true, ghostLastAmount = 0 }
    row.waterTargets[record.id] = record
    local fixture = { modData = { [U.TargetMarker] = record.id },
        getModData = function(self) return self.modData end,
        getUsesExternalWaterSource = function() return true end }
    local fluid = { capacity = 10,
        getCapacity = function(self) return self.capacity end,
        setCapacity = function(self, amount) self.capacity = amount end }
    local ghost = { amount = 0, modData = { [U.GhostMarker] = record.id },
        getModData = function(self) return self.modData end,
        getFluidContainer = function() return fluid end,
        getFluidAmount = function(self) return self.amount end,
        addFluid = function(self, _, amount) self.amount = self.amount + amount end,
        sync = function() end,
        getObjectIndex = function(self) return self.removed and -1 or 0 end }
    local upper = { getObjects = function() return { size = function() return 1 end,
        get = function() return ghost end } end,
        transmitRemoveItemFromSquare = function(_, object) object.removed = true end }
    ghost.getSquare = function() return upper end
    local lower = { getObjects = function() return { size = function() return 1 end,
        get = function() return fixture end } end }
    local adapter = { square = function(_, _, z) return z == 0 and lower or upper end }
    assert(U.serviceWaterTarget(root, row, record, adapter))
    eq(ghost.amount, 10); eq(row.waterBalanceCents, 800); eq(row.waterReserveCents, 200)
    ghost.amount = 6
    assert(U.serviceWaterTarget(root, row, record, adapter))
    eq(ghost.amount, 10); eq(row.waterBalanceCents, 720); eq(row.waterReserveCents, 200)
    row.active = false
    assert(U.releaseWaterGhost(row, record, adapter))
    eq(row.waterBalanceCents, 920); eq(row.waterReserveCents, 0)
end)

test("missing ghost cannot refund unverified reserved water", function()
    local row = { waterBalanceCents = 500, waterReserveCents = 200 }
    local record = { id = "UG-missing:1", x = 6, y = 6, z = 0, kind = "fixture",
        ghostActive = true, ghostPaidCents = 200, ghostPaidLiters = 10, ghostLastAmount = 10 }
    local upper = { getObjects = function() return { size = function() return 0 end } end }
    assert(U.releaseWaterGhost(row, record, { square = function() return upper end }))
    eq(row.waterBalanceCents, 500); eq(row.waterReserveCents, 0)
    eq(record.ghostPaidCents, 0)
end)

test("native external water source takes priority over a bound tap", function()
    local source = { getFluidAmount = function() return 5 end,
        getModData = function() return { ThirdPartySource = true } end }
    local fixture = { FindExternalWaterSource = function() return source end }
    local record = { id = "UG-priority:1", kind = "fixture", x = 1, y = 2, z = 0 }
    assert(U.publicUtilityOn("water") == false)
    local upper = { getObjects = function() return { size = function() return 0 end } end }
    local adapter = { square = function() return upper end }
    -- No hidden source is created while the native fixture already has water.
    local previous = U.createWaterGhost
    U.createWaterGhost = function() error("must not create a second source") end
    local root = { devices = {} }
    local device = U.ensureDevice(root, "UG-priority")
    device.placed, device.active, device.x, device.y, device.z = true, true, 1, 2, 0
    device.waterBalanceCents = 100
    device.waterTargets[record.id] = record
    local objects = { size = function() return 1 end, get = function() return fixture end }
    fixture.getModData = function() return { [U.TargetMarker] = record.id } end
    fixture.getUsesExternalWaterSource = function() return true end
    adapter.square = function(_, _, z) return z == 0 and { getObjects = function() return objects end } or upper end
    local ok, supplied = pcall(U.serviceWaterTarget, root, device, record, adapter)
    U.createWaterGhost = previous
    assert(ok and supplied and device.waterBalanceCents == 100,
        tostring(ok) .. "/" .. tostring(supplied) .. "/" .. tostring(device.waterBalanceCents))
end)

test("target identity and water setting participate in transaction fingerprints", function()
    local base = { action = "bindWaterTarget", deviceId = "UG-t", x = 5, y = 6, z = 0,
        targetX = 6, targetY = 6, targetZ = 0, targetIndex = 1, targetSprite = "sink_01" }
    local first = U.fingerprint(base)
    base.targetIndex = 2
    assert(U.fingerprint(base) ~= first)
    assert(U.fingerprint({ action = "setWaterTargetLiters", deviceId = "UG-t", liters = 10 })
        ~= U.fingerprint({ action = "setWaterTargetLiters", deviceId = "UG-t", liters = 20 }))
end)

test("client menu boots without the server-only building cursor module", function()
    local priorRequire = require
    require = function(name)
        assert(name ~= "BuildingObjects/ISBuildingObject", "server-only cursor dependency")
        return true
    end
    ISBaseObject = { derive = function(_, typeName)
        return { Type = typeName, initialise = function() end }
    end }
    local function event()
        return { Add = function() end, Remove = function() end }
    end
    Events = { OnFillWorldObjectContextMenu = event(), OnGameStart = event() }
    isServer = function() return false end
    isClient = function() return true end
    ISWorldObjectContextMenu = {}
    ISContextMenu = { getNew = function(_, parent) return parent:newSubMenu() end }
    local player = {}
    getSpecificPlayer = function() return player end
    local function menu()
        return { options = {}, addOption = function(self, label)
            local option = { name = label }
            self.options[#self.options + 1] = option
            return option
        end, addSubMenu = function() end, newSubMenu = menu }
    end
    local context = load("client/GodSystem_UtilityGeneratorContext.lua")
    local gen = { getModData = function() return { [U.ObjectMarker] = "UG-menu" } end,
        getSquare = function() return { getX = function() return 5 end,
            getY = function() return 6 end, getZ = function() return 0 end } end }
    local popup = menu()
    context.fillWorldMenu(0, popup, { gen }, false)
    assert(#popup.options > 0, "custom generator menu missing")
    require = priorRequire
end)

test("idle device maintenance runs at most once per second without delaying active scan jobs", function()
    U.jobs = {}; U._jobsRoot = nil
    local root = { devices = { ["UG-idle"] = { id = "UG-idle", placed = true, active = false,
        x = 0, y = 0, z = 0, waterFixtures = {} } } }
    local lookups = 0
    local adapter = { findDevice = function() lookups = lookups + 1; return nil end }
    U.tick(root, adapter, 1000)
    root.devices["UG-idle"].nextPowerPollMs = 0
    U.tick(root, adapter, 1001)
    eq(lookups, 1)
    U.tick(root, adapter, 2000)
    eq(lookups, 2)
end)

test("water changes revisit only the changed target and coalesce duplicate events", function()
    U.jobs = {}; U._jobsRoot = nil
    local id = "UG-dirty"
    local first, second = id .. ":1", id .. ":2"
    local row = { id = id, placed = true, active = true, x = 0, y = 0, z = 0,
        waterTargetSchema = 1, waterFixtures = {}, nextWaterTargetMs = 61000,
        waterTargets = { [first] = { id = first }, [second] = { id = second } } }
    local root = { devices = { [id] = row } }
    assert(U.markWaterTargetDirty(root, second))
    assert(U.markWaterTargetDirty(root, second))
    U.enabledStates[id] = true
    local calls = {}
    local original = U.serviceWaterTarget
    U.serviceWaterTarget = function(_, _, record)
        calls[record.id] = (calls[record.id] or 0) + 1
        return false
    end
    U.tick(root, {}, 1000)
    U.serviceWaterTarget = original
    eq(calls[first], nil)
    eq(calls[second], 1)
    eq(row.nextWaterTargetMs, 61000)
    assert(not U.hasPendingWork(1001))
end)

test("inactive devices skip periodic target work and historical rows leave the live index", function()
    U.jobs = {}; U._jobsRoot = nil
    local id = "UG-stopped"
    local target = id .. ":1"
    local row = { id = id, placed = true, active = false, x = 0, y = 0, z = 0,
        waterTargetSchema = 1, waterFixtures = {}, waterTargets = { [target] = { id = target } } }
    local root = { devices = { [id] = row, ["UG-history"] = { id = "UG-history", placed = false,
        waterFixtures = {}, waterTargets = {} } } }
    local count = 0
    local original = U.serviceWaterTarget
    U.serviceWaterTarget = function() count = count + 1; return false end
    U.tick(root, {}, 1000)
    eq(count, 1)
    eq(U._watchedDeviceIds["UG-history"], nil)
    eq(U._watchedDeviceIds[id], true)
    U.tick(root, {}, 61000)
    U.serviceWaterTarget = original
    eq(count, 1)
end)

test("stopped fixtures keep retrying until an unloaded ghost is cleared", function()
    U.jobs = {}; U._jobsRoot = nil
    local id = "UG-unloaded"
    local target = id .. ":1"
    local record = { id = target, kind = "fixture", ghostActive = true }
    local row = { id = id, placed = true, active = false, x = 0, y = 0, z = 0,
        waterTargetSchema = 1, waterFixtures = {}, waterTargets = { [target] = record } }
    local root = { devices = { [id] = row } }
    local count = 0
    local original = U.serviceWaterTarget
    U.serviceWaterTarget = function() count = count + 1; return false end
    U.tick(root, {}, 1000)
    U.tick(root, {}, 61000)
    eq(count, 2)
    record.ghostActive = false
    U.tick(root, {}, 121000)
    eq(U.inactiveCleanupNeeded[id], nil)
    U.tick(root, {}, 181000)
    U.serviceWaterTarget = original
    eq(count, 3)
end)

test("unloaded legacy cleanup waits until its retry deadline", function()
    U.jobs = {}; U._jobsRoot = nil
    local id = "UG-cleanup"
    local root = { devices = { [id] = { id = id, placed = false, waterTargetSchema = 1,
        waterFixtures = { ["0:0:0:1"] = { x = 0, y = 0, z = 0 } }, waterTargets = {} } } }
    assert(U.scheduleCleanup(root, id))
    U.tick(root, { fixture = function() return nil end, square = function() return nil end }, 1000)
    eq(U.jobs[id].retryAfterMs, 2000)
    eq(U._nextJobReadyMs, 2000)
    assert(not U.hasPendingWork(1500))
    assert(U.hasPendingWork(2000))
end)

test("scan jobs from one save are discarded when another save is active", function()
    U.jobs = {}
    U._jobsRoot = nil
    local oldRoot = { devices = { ["UG-old"] = { id = "UG-old", placed = true, active = true, x = 0, y = 0, z = 0, waterFixtures = {} } } }
    local newRoot = { devices = { ["UG-new"] = { id = "UG-new", placed = true, active = true, x = 0, y = 0, z = 0, waterFixtures = {} } } }
    assert(U.scheduleScan(oldRoot, "UG-old"))
    U.tick(newRoot, { square = function() return nil end }, 1000)
    eq(U.jobs["UG-old"], nil)
    eq(U._jobsRoot, newRoot)
end)

test("generator range uses the native B42 coverage helper when present", function()
    local calls = 0
    IsoGenerator = { isPoweringSquare = function(gx, gy, gz, x, y, z)
        calls = calls + 1
        eq(gx, 10); eq(gy, 20); eq(gz, 0)
        return x == 11 and y == 20 and z == 0
    end }
    assert(U.isGeneratorSquareAffected(10, 20, 0, 11, 20, 0))
    assert(not U.isGeneratorSquareAffected(10, 20, 0, 12, 20, 0))
    eq(calls, 2)
    IsoGenerator = nil
end)

test("native userdata bridge exposes generator water and drinking methods", function()
    local previous = GodSystemB42JavaCalls
    GodSystemB42JavaCalls = nil
    local bridge = load("shared/GodSystem_B42JavaCalls.lua")
    local fluid = { getAmount = function() return 0.5 end,
        getPrimaryFluid = function() return { getFluidTypeString = function() return "Water" end } end }
    local properties = { has = function(_, flag) return flag == "waterPiped" end }
    local player = { DrinkFluid = function(self) self.drank = true end }
    local nativeType = type
    type = function(value)
        if value == fluid or value == player or value == properties then return "userdata" end
        return nativeType(value)
    end
    local ok, err = pcall(function()
        eq(bridge.value(fluid, "getAmount", nil), 0.5)
        eq(bridge.value(properties, "has", false, "waterPiped"), true)
        local primary = bridge.value(fluid, "getPrimaryFluid", nil)
        eq(bridge.value(primary, "getFluidTypeString", nil), "Water")
        assert(bridge.try(player, "DrinkFluid", fluid, 1))
        assert(player.drank)
    end)
    type = nativeType
    GodSystemB42JavaCalls = previous
    if not ok then error(err) end
end)

U.publicUtilityOn = originalWaterCheck
