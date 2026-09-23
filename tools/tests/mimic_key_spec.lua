-- Regression coverage for mimic-key target identity, rollback, and bounded work.
local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a, b, message) assert(a == b, message or (tostring(a) .. " ~= " .. tostring(b))) end
local function test(name, fn) fn(); print("PASS mimic key: " .. name) end

GodSystemB42JavaCalls = nil
function instanceof(object, className) return object and object.className == className end
load("shared/GodSystem_MimicKey.lua")
local Mimic = GodSystemMimicKey

local function item(id, fullType)
    return {
        id = id,
        fullType = fullType,
        getID = function(self) return self.id end,
        getFullType = function(self) return self.fullType end,
        setKeyId = function(self, keyId) self.keyId = keyId end,
    }
end

local function player()
    return {
        getX = function() return 10 end,
        getY = function() return 10 end,
        getZ = function() return 0 end,
    }
end

local function authority(target, consumable, source, result)
    return {
        resolveTarget = function() return target end,
        findItem = function() return consumable, source end,
        remove = function(_, container, value) container.removed = value; return true end,
        add = function(_, value) result.output = value; return result.allowAdd ~= false end,
        removeOutput = function(_, value) result.removedOutput = value; return true end,
        refund = function() result.refunded = (result.refunded or 0) + 1; return true end,
    }
end

test("fingerprints are stable and target-sensitive", function()
    local a = { mimicItemId = "20", targetKind = "door", x = 1, y = 2, z = 0, objectIndex = 3 }
    local b = { mimicItemId = "20", targetKind = "door", x = 1, y = 2, z = 0, objectIndex = 3 }
    eq(Mimic.fingerprint(a), Mimic.fingerprint(b))
    b.objectIndex = 4
    assert(Mimic.fingerprint(a) ~= Mimic.fingerprint(b))
end)

test("unassigned doors get one durable key id and stay locked", function()
    local square = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end }
    local door = { className = "IsoDoor", keyId = -1, isLocked = function() return true end,
        checkKeyId = function(self) return self.keyId end, setKeyId = function(self, value) self.keyId = value end,
        getSquare = function() return square end }
    local originalInstanceItem = instanceItem
    instanceItem = function(fullType) return item("new", fullType) end
    local source, result = {}, {}
    local success, code = Mimic.execute(player(), { mimicItemId = "1" }, authority({ kind = "door", object = door, keyId = -1 }, item("1", Mimic.FullType), source, result))
    instanceItem = originalInstanceItem
    assert(success); eq(code, "MimicKeyDoorCreated"); assert(door.keyId >= 0); eq(result.output.fullType, "Base.Key1"); eq(result.output.keyId, door.keyId)
end)

test("combination lock restores its code and refunds when delivery fails", function()
    local square = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end }
    local lock = { className = "IsoThumpable", code = 9999, setLockedByCode = function(self, value) self.code = value end,
        getSquare = function() return square end }
    local originalInstanceItem = instanceItem
    instanceItem = function(fullType) return item("new", fullType) end
    local source, result = {}, { allowAdd = false }
    local success, code = Mimic.execute(player(), { mimicItemId = "2" }, authority({ kind = "code", object = lock, code = 9999 }, item("2", Mimic.FullType), source, result))
    instanceItem = originalInstanceItem
    assert(not success); eq(code, "MimicKeyFailedRefunded"); eq(lock.code, 9999); eq(result.refunded, 1); assert(result.removedOutput ~= nil)
end)

test("only locked vehicle doors qualify", function()
    local vehicle = {
        getId = function() return 7 end,
        getPartCount = function() return 2 end,
        getPartByIndex = function(_, index)
            return { getDoor = function() return { isLocked = function() return index == 1 end } end }
        end,
    }
    local detail = assert(Mimic.inspectVehicle(vehicle))
    eq(detail.kind, "vehicle"); eq(detail.vehicleId, 7)
end)

test("no background worker is introduced", function()
    local source = readSource("client/GodSystem_MimicKeyContext.lua")
    assert(not string.find(source, "Events.OnTick", 1, true))
    assert(not string.find(source, "Events.OnPlayerUpdate", 1, true))
end)
