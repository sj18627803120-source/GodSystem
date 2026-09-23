GodSystemMimicKey = GodSystemMimicKey or {}

local Mimic = GodSystemMimicKey

Mimic.FullType = "GodSystem.MimicKey"

local function value(target, method, fallback, ...)
    local Bridge = GodSystemB42JavaCalls
    if Bridge and Bridge.value then return Bridge.value(target, method, fallback, ...) end
    if type(target) ~= "table" or type(target[method]) ~= "function" then return fallback end
    local ok, result = pcall(target[method], target, ...)
    return ok and result ~= nil and result or fallback
end

local function invoke(target, method, ...)
    local Bridge = GodSystemB42JavaCalls
    if Bridge and Bridge.try then return Bridge.try(target, method, ...) end
    if type(target) ~= "table" or type(target[method]) ~= "function" then return false, nil end
    return pcall(target[method], target, ...)
end

local function isInstance(object, className)
    return object ~= nil and instanceof and instanceof(object, className) == true
end

local function integer(raw, fallback)
    local number = tonumber(raw)
    return number == nil and fallback or math.floor(number)
end

function Mimic.itemId(item)
    local id = value(item, "getID", nil)
    return id ~= nil and tostring(id) or nil
end

function Mimic.isMimic(item)
    return item ~= nil and tostring(value(item, "getFullType", "") or "") == Mimic.FullType
end

function Mimic.vehicleLocked(vehicle)
    local count = math.max(0, integer(value(vehicle, "getPartCount", 0), 0))
    for index = 0, count - 1 do
        local part = value(vehicle, "getPartByIndex", nil, index)
        local door = value(part, "getDoor", nil)
        if door and value(door, "isLocked", false) == true then return true end
    end
    return false
end

function Mimic.inspectObject(object)
    if isInstance(object, "IsoDoor") then
        if value(object, "isLocked", false) ~= true then return nil, "MimicKeyNotLocked" end
        return { kind = "door", object = object, keyId = integer(value(object, "checkKeyId", -1), -1) }
    end
    if isInstance(object, "IsoThumpable") then
        local code = integer(value(object, "getLockedByCode", 0), 0)
        if code > 0 then return { kind = "code", object = object, code = code } end
        if value(object, "getLockedByPadlock", false) == true then
            return { kind = "padlock", object = object, keyId = integer(value(object, "getKeyId", -1), -1) }
        end
        return nil, "MimicKeyNotLocked"
    end
    return nil, "MimicKeyUnsupportedTarget"
end

function Mimic.inspectVehicle(vehicle)
    if not vehicle then return nil, "MimicKeyInvalidVehicle" end
    if Mimic.vehicleLocked(vehicle) ~= true then return nil, "MimicKeyNotLocked" end
    return { kind = "vehicle", vehicle = vehicle, vehicleId = integer(value(vehicle, "getId", -1), -1) }
end

function Mimic.describeObject(object)
    local detail, code = Mimic.inspectObject(object)
    if not detail then return nil, code end
    local square = value(object, "getSquare", nil)
    local objects = value(square, "getObjects", nil)
    local count = integer(value(objects, "size", 0), 0)
    local objectIndex = nil
    for index = 0, count - 1 do
        if value(objects, "get", nil, index) == object then objectIndex = index break end
    end
    if objectIndex == nil then return nil, "MimicKeyTargetChanged" end
    detail.x = integer(value(square, "getX", nil), nil)
    detail.y = integer(value(square, "getY", nil), nil)
    detail.z = integer(value(square, "getZ", nil), nil)
    detail.objectIndex = objectIndex
    if detail.x == nil or detail.y == nil or detail.z == nil then return nil, "MimicKeyTargetChanged" end
    return detail
end

function Mimic.describeVehicle(vehicle)
    local detail, code = Mimic.inspectVehicle(vehicle)
    if not detail or detail.vehicleId == nil or detail.vehicleId < 0 then return nil, code or "MimicKeyInvalidVehicle" end
    return detail
end

function Mimic.fingerprint(args)
    args = type(args) == "table" and args or {}
    local kind = tostring(args.targetKind or "")
    if kind == "vehicle" then
        return "mimic|" .. tostring(args.mimicItemId or "") .. "|vehicle|" .. tostring(integer(args.vehicleId, -1))
    end
    return table.concat({
        "mimic", tostring(args.mimicItemId or ""), kind,
        tostring(integer(args.x, -1)), tostring(integer(args.y, -1)), tostring(integer(args.z, -1)),
        tostring(integer(args.objectIndex, -1)),
    }, "|")
end

function Mimic.inRange(player, target)
    local square = target and target.object and value(target.object, "getSquare", nil) or nil
    local source = target and target.vehicle or square
    local tx, ty, tz = value(source, "getX", nil), value(source, "getY", nil), value(source, "getZ", nil)
    if not player or tx == nil or ty == nil or tz == nil then return false, "MimicKeyTargetChanged" end
    if integer(value(player, "getZ", -999), -999) ~= integer(tz, -998) then return false, "MimicKeyWrongFloor" end
    local dx = (tonumber(value(player, "getX", 0)) or 0) - (tonumber(tx) or 0)
    local dy = (tonumber(value(player, "getY", 0)) or 0) - (tonumber(ty) or 0)
    if dx * dx + dy * dy > 16 then return false, "MimicKeyTooFar" end
    return true
end

function Mimic.resolveTarget(args)
    args = type(args) == "table" and args or {}
    if tostring(args.targetKind or "") == "vehicle" then
        return Mimic.inspectVehicle(getVehicleById and getVehicleById(integer(args.vehicleId, -1)) or nil)
    end
    local cell = getCell and getCell() or nil
    local square = cell and cell.getGridSquare and cell:getGridSquare(integer(args.x, -1), integer(args.y, -1), integer(args.z, -1)) or nil
    local object = value(value(square, "getObjects", nil), "get", nil, integer(args.objectIndex, -1))
    local target, code = Mimic.inspectObject(object)
    if not target or tostring(target.kind) ~= tostring(args.targetKind or "") then return nil, code or "MimicKeyTargetChanged" end
    return target
end

local function newKeyId()
    return ZombRand and ZombRand(100000000) or math.floor(math.random() * 100000000)
end

local function collectDoorGroup(door)
    local result, seen = {}, {}
    local function add(object)
        if object and not seen[object] then seen[object] = true; result[#result + 1] = object end
    end
    add(door)
    if buildUtil then
        for _, method in ipairs({ "getDoubleDoorObjects", "getGarageDoorObjects" }) do
            local fn = buildUtil[method]
            if type(fn) == "function" then
                local ok, objects = pcall(fn, door)
                if ok then for i = 1, #(objects or {}) do add(objects[i]) end end
            end
        end
    end
    return result
end

local function syncObject(object)
    invoke(object, "sync")
end

-- The adapters touch live inventory and network-backed containers.  Keep an
-- unexpected adapter error inside the transaction so the rollback below can
-- restore the consumed Mimic Key instead of leaving an unknown half-operation.
local function authorityCall(authority, name, ...)
    local callback = authority and authority[name]
    if type(callback) ~= "function" then return false end
    local ok, result = pcall(callback, ...)
    return ok and result == true
end

local function makeOutput(target)
    if target.kind == "vehicle" then
        local ok, key = invoke(target.vehicle, "createVehicleKey")
        return ok and key or nil
    end
    local fullType = target.kind == "padlock" and "Base.KeyPadlock" or target.kind == "code" and "Base.CombinationPadlock" or "Base.Key1"
    local item = instanceItem and instanceItem(fullType) or nil
    if not item then return nil end
    if target.kind ~= "code" and invoke(item, "setKeyId", target.keyId) == false then return nil end
    return item
end

function Mimic.execute(player, args, authority)
    authority = authority or {}
    local target, targetCode = (authority.resolveTarget or Mimic.resolveTarget)(args)
    if not target then return false, targetCode or "MimicKeyTargetChanged" end
    local inRange, rangeCode = Mimic.inRange(player, target)
    if not inRange then return false, rangeCode end
    local consumable, source = nil, nil
    if authority.findItem then consumable, source = authority.findItem(player, tostring(args and args.mimicItemId or "")) end
    if not Mimic.isMimic(consumable) or not source then return false, "MimicKeyMissing" end
    if (target.kind == "door" or target.kind == "padlock") and (target.keyId == nil or target.keyId < 0) then target.keyId = newKeyId() end
    local output = makeOutput(target)
    if not output then return false, "MimicKeyCreateFailed" end

    local changes = { doors = nil, code = nil }
    if target.kind == "door" then
        changes.doors, changes.keyIds = collectDoorGroup(target.object), {}
        for i = 1, #changes.doors do changes.keyIds[i] = integer(value(changes.doors[i], "checkKeyId", -1), -1) end
    elseif target.kind == "code" then
        changes.code = target.code
    end

    if authorityCall(authority, "remove", player, source, consumable) ~= true then return false, "MimicKeyConsumeFailed" end
    local applied = true
    if changes.doors then
        for i = 1, #changes.doors do
            if invoke(changes.doors[i], "setKeyId", target.keyId) == false then applied = false break end
            syncObject(changes.doors[i])
        end
    elseif changes.code then
        applied = invoke(target.object, "setLockedByCode", 0) == true
        syncObject(target.object)
    end
    if applied and authorityCall(authority, "add", player, output) ~= true then applied = false end
    if applied then
        local codes = { door = "MimicKeyDoorCreated", padlock = "MimicKeyPadlockCreated", code = "MimicKeyCodeRemoved", vehicle = "MimicKeyVehicleCreated" }
        return true, codes[target.kind] or "MimicKeyCreated", {}, { kind = "mimicKey", targetKind = target.kind }
    end
    if changes.doors then
        for i = 1, #changes.doors do invoke(changes.doors[i], "setKeyId", changes.keyIds[i]); syncObject(changes.doors[i]) end
    elseif changes.code then
        invoke(target.object, "setLockedByCode", changes.code)
        syncObject(target.object)
    end
    authorityCall(authority, "removeOutput", player, output)
    authorityCall(authority, "refund", player)
    return false, "MimicKeyFailedRefunded"
end

return Mimic
