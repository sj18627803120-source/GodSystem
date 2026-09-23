local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a, b, message) assert(a == b, message or (tostring(a) .. " ~= " .. tostring(b))) end
local function test(name, fn) fn(); print("PASS utility generator: " .. name) end

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
    local device = { id = "UG-1", active = true, balanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 10); eq(device.balanceCents, 9800); eq(device.waterReserveCents, 200)
    eq(fixture.modData[U.WaterPaid], 10); eq(device.waterFixtures["5:6:0:1"].paidCents, 200)
    fixture.amount = 5
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 10); eq(device.balanceCents, 9700); eq(device.waterReserveCents, 200)
    assert(U.releaseWaterFixture(root, device, fixture, "5:6:0:1", fixture.modData, fixture:getFluidContainer()))
    eq(fixture.amount, 0); eq(device.balanceCents, 9900); eq(device.waterReserveCents, 0)
    eq(fixture.modData[U.WaterMarker], nil)
end)

test("water price changes preserve prepaid stock and price only new refills", function()
    local root = { devices = {} }
    local device = { id = "UG-1c", active = true, balanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 10); eq(device.balanceCents, 9800); eq(device.waterReserveCents, 200)
    SandboxVars.GodSystem.UtilityGeneratorWaterPricePer100L = 40
    fixture.amount = 5
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 10); eq(device.balanceCents, 9600); eq(device.waterReserveCents, 300)
    SandboxVars.GodSystem.UtilityGeneratorWaterPricePer100L = 20
end)

test("water limits a partial refill to the remaining cent balance", function()
    local root = { devices = {} }
    local device = { id = "UG-1b", active = true, balanceCents = 10, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local fixture = waterFixture()
    assert(U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 0.5)
    eq(device.balanceCents, 0)
    eq(device.waterReserveCents, 10)
end)

test("existing third-party water ownership is left untouched", function()
    local root = { devices = {} }
    local device = { id = "UG-2", active = true, balanceCents = 10000, waterFixtures = {} }
    local fixture = waterFixture()
    fixture.modData["OtherModWaterController"] = true
    assert(not U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1))
    eq(fixture.amount, 0); eq(device.balanceCents, 10000); eq(fixture.modData[U.WaterMarker], nil)
end)

test("water uses the native fluid API and ignores marker-only objects", function()
    local root = { devices = {} }
    local device = { id = "UG-2b", active = true, balanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    root.devices[device.id] = device
    local unsupported = { modData = { waterAmount = 0, waterMaxAmount = 100 },
        getModData = function(self) return self.modData end,
        getProperties = function() return { has = function() return true end } end }
    assert(not U.updateWaterFixture(root, device, unsupported, 5, 6, 0, 1))
    eq(device.balanceCents, 10000)
    eq(unsupported.modData[U.WaterMarker], nil)
    local native = waterFixture()
    native.getFluidContainer = function() return nil end
    assert(U.updateWaterFixture(root, device, native, 5, 6, 0, 1))
    eq(native.amount, 10)
end)

test("water fixture is released when public water returns", function()
    local root = { devices = {} }
    local device = { id = "UG-3", active = true, balanceCents = 10000, waterReserveCents = 0, waterFixtures = {} }
    local fixture = waterFixture()
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    U.publicUtilityOn = function(kind) return kind == "water", true end
    U.updateWaterFixture(root, device, fixture, 5, 6, 0, 1)
    eq(fixture.amount, 0); eq(device.balanceCents, 10000); eq(fixture.modData[U.WaterMarker], nil)
    U.publicUtilityOn = function() return false, true end
end)

test("charging is server supplied and balance has a safe upper bound", function()
    local root = { devices = { ["UG-4"] = { id = "UG-4", placed = true, active = false, x = 5, y = 6, z = 0, balanceCents = 0, waterFixtures = {} } } }
    local generator = { modData = { [U.ObjectMarker] = "UG-4" }, getModData = function(self) return self.modData end,
        getSquare = square, getActivated = function() return false end }
    local player = { getX = function() return 5 end, getY = function() return 6 end, getZ = function() return 0 end }
    local spent = 0
    local env = { root = root, findDevice = function() return generator end,
        spendCurrency = function(_, amount) spent = spent + amount; return true end,
        persist = function() return true end }
    local ok = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 500 }, env)
    assert(ok); eq(spent, 500); eq(root.devices["UG-4"].balanceCents, 50000)
    root.devices["UG-4"].balanceCents = 214748364650
    local second = U.execute(player, { action = "charge", deviceId = "UG-4", amount = 1 }, env)
    assert(not second); eq(spent, 500)
end)

test("electricity bills actual native fuel use and refunds unused reserve on stop", function()
    local oldPublic = U.publicUtilityOn
    U.publicUtilityOn = function(kind) return kind == "water", true end
    local row = { id = "UG-power", active = true, balanceCents = 50000,
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
    eq(generator.fuel, 100); eq(row.balanceCents, 0); eq(row.powerReserveCents, 50000)
    generator.fuel = 80
    assert(U.updatePower(row, generator))
    eq(row.powerReserveFuel, 80); eq(row.powerReserveCents, 40000)
    row.active = false
    U.updatePower(row, generator)
    eq(generator.fuel, 0); eq(generator.active, false)
    eq(row.balanceCents, 40000); eq(row.powerReserveCents, 0)
    U.publicUtilityOn = oldPublic
end)

test("placement and pickup preserve the shared device identity and balance", function()
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
    root.devices[payload.deviceId].balanceCents = 12345
    local pickedUp = U.execute(player, { action = "pickup", deviceId = payload.deviceId, x = 5, y = 6, z = 0 }, env)
    assert(pickedUp)
    eq(root.devices[payload.deviceId].placed, false)
    eq(root.devices[payload.deviceId].balanceCents, 12345)
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

test("scan is bounded and does not checkpoint once per square", function()
    U.jobs = {}
    local root = { devices = { ["UG-5"] = { id = "UG-5", placed = true, active = true, x = 0, y = 0, z = 0, waterFixtures = {} } } }
    assert(U.scheduleScan(root, "UG-5"))
    local scanned, persisted = 0, 0
    U.tick(root, { square = function() scanned = scanned + 1; return nil end,
        persist = function() persisted = persisted + 1 end }, 1000)
    assert(scanned <= U.ScanSquaresPerStep)
    eq(persisted, 0)
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

U.publicUtilityOn = originalWaterCheck
