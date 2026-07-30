GodSystemStoragePlatformSupport = GodSystemStoragePlatformSupport or {}

local Support = GodSystemStoragePlatformSupport

function Support.finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

function Support.number(value, fallback)
    if not Support.finite(value) then value = fallback end
    value = tonumber(value)
    return Support.finite(value) and value or nil
end

function Support.integer(value, fallback, minimum, maximum)
    value = math.floor(Support.number(value, fallback or 0) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Support.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[Support.copy(key, seen)] = Support.copy(child, seen)
    end
    return result
end

function Support.call(target, methodName, ...)
    if not target or type(target[methodName]) ~= "function" then return false, nil end
    return pcall(target[methodName], target, ...)
end

function Support.read(target, methods, fallback, ...)
    for index = 1, #(methods or {}) do
        local called, value = Support.call(target, methods[index], ...)
        if called and value ~= nil then return value end
    end
    return fallback
end

function Support.write(target, methods, ...)
    for index = 1, #(methods or {}) do
        if target and type(target[methods[index]]) == "function" then
            local called = pcall(target[methods[index]], target, ...)
            if called then return true end
        end
    end
    return false
end

function Support.binding(context)
    return type(context and context.binding) == "table" and context.binding or {}
end

function Support.api(binding, name)
    if type(binding) == "table" and type(binding[name]) == "function" then
        return binding[name]
    end
    return type(_G) == "table" and _G[name] or nil
end

function Support.identity(actor, binding)
    if type(binding.identity) == "function" then
        local called, value = pcall(binding.identity, actor)
        if called and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    local username = Support.read(actor, { "getUsername" }, nil)
    if username ~= nil and tostring(username) ~= "" then return tostring(username) end
    local onlineId = Support.read(actor, { "getOnlineID" }, nil)
    if onlineId ~= nil then return "id:" .. tostring(onlineId) end
    if type(actor) == "table" and actor.id ~= nil then return tostring(actor.id) end
    return "local"
end

function Support.modData(target)
    local called, value = Support.call(target, "getModData")
    return called and type(value) == "table" and value or nil
end

function Support.values(list)
    local result = {}
    if not list then return result end
    if type(list.size) == "function" and type(list.get) == "function" then
        local called, count = pcall(list.size, list)
        count = called and Support.integer(count, 0, 0) or 0
        for index = 0, count - 1 do
            local got, value = pcall(list.get, list, index)
            if got and value then result[#result + 1] = value end
        end
    elseif type(list) == "table" then
        local source = type(list.values) == "table" and list.values or list
        for index = 1, #source do result[#result + 1] = source[index] end
    end
    return result
end

function Support.items(container)
    return Support.values(Support.read(container, { "getItems" }, nil))
end

function Support.itemId(item)
    local value = Support.read(item, { "getID" }, nil)
    return value ~= nil and tostring(value) or nil
end

function Support.fullType(item)
    return tostring(Support.read(item, { "getFullType" }, "") or "")
end

function Support.contains(container, item)
    if not container or not item then return false end
    local expectedId = Support.itemId(item)
    local rows = Support.items(container)
    for index = 1, #rows do
        if rows[index] == item then return true end
        if expectedId and Support.itemId(rows[index]) == expectedId then return true end
    end
    return false
end

function Support.add(container, value)
    if not container then return nil end
    local called, item = Support.call(container, "AddItem", value)
    if not called or not item then return nil end
    return Support.contains(container, item) and item or nil
end

function Support.remove(container, item)
    if not container or not item or not Support.contains(container, item) then return false end
    if not Support.write(container, { "Remove" }, item) then return false end
    return not Support.contains(container, item)
end

function Support.child(item)
    return Support.read(item, { "getInventory" }, nil)
end

function Support.findRecursive(container, expectedId, maximumDepth)
    expectedId = tostring(expectedId or "")
    local seen = {}
    local function visit(current, depth)
        if not current or seen[current] or depth > (maximumDepth or 32) then return nil, nil end
        seen[current] = true
        local rows = Support.items(current)
        for index = 1, #rows do
            local item = rows[index]
            if Support.itemId(item) == expectedId then return item, current end
            local found, owner = visit(Support.child(item), depth + 1)
            if found then return found, owner end
        end
        return nil, nil
    end
    return visit(container, 0)
end

function Support.position(value)
    if not value then return nil end
    local square = Support.read(value, { "getSquare" }, nil)
    local target = square or value
    local x = Support.number(Support.read(target, { "getX" }, nil), nil)
    local y = Support.number(Support.read(target, { "getY" }, nil), nil)
    local z = Support.integer(Support.read(target, { "getZ" }, nil), nil)
    if x == nil or y == nil or z == nil then return nil end
    return { x = x, y = y, z = z }
end

function Support.spriteName(object)
    local sprite = Support.read(object, { "getSprite" }, nil)
    return tostring(Support.read(sprite, { "getName" }, "") or "")
end

function Support.squareObjects(square)
    local result, seen = {}, {}
    for _, methodName in ipairs({ "getSpecialObjects", "getWorldObjects", "getObjects" }) do
        local rows = Support.values(Support.read(square, { methodName }, nil))
        for index = 1, #rows do
            if not seen[rows[index]] then
                seen[rows[index]] = true
                result[#result + 1] = rows[index]
            end
        end
    end
    return result
end

function Support.square(binding, x, y, z)
    if type(binding.getSquare) == "function" then
        local called, square = pcall(binding.getSquare, x, y, z)
        if called then return square end
    end
    local getCell = Support.api(binding, "getCell")
    if type(getCell) ~= "function" then return nil end
    local called, cell = pcall(getCell)
    if not called or not cell then return nil end
    return Support.read(cell, { "getGridSquare" }, nil,
        Support.integer(x, 0), Support.integer(y, 0), Support.integer(z, 0))
end

function Support.safehouses(binding)
    if type(binding.safehouses) == "function" then
        local called, value = pcall(binding.safehouses)
        if called then return Support.values(value) end
    end
    local safeHouse = type(binding) == "table" and binding.SafeHouse or nil
    if not safeHouse and type(_G) == "table" then safeHouse = _G.SafeHouse end
    if not safeHouse or type(safeHouse.getSafehouseList) ~= "function" then
        return {}
    end
    local called, value = pcall(safeHouse.getSafehouseList)
    return called and Support.values(value) or {}
end

function Support.safehouseAt(binding, x, y)
    if type(binding.safehouseAt) == "function" then
        local called, value = pcall(binding.safehouseAt, x, y)
        if called then return value end
    end
    x, y = Support.number(x, 0), Support.number(y, 0)
    local rows = Support.safehouses(binding)
    for index = 1, #rows do
        local safehouse = rows[index]
        local sx = Support.number(Support.read(safehouse, { "getX" }, 0), 0)
        local sy = Support.number(Support.read(safehouse, { "getY" }, 0), 0)
        local width = Support.number(Support.read(safehouse, { "getW" }, 0), 0)
        local height = Support.number(Support.read(safehouse, { "getH" }, 0), 0)
        if x >= sx and x < sx + width and y >= sy and y < sy + height then
            return safehouse
        end
    end
    return nil
end

function Support.safehouseKey(safehouse)
    if not safehouse then return nil end
    local id = Support.read(safehouse, { "getId" }, nil)
    if id ~= nil and tostring(id) ~= "" then return "safehouse:" .. tostring(id) end
    return table.concat({
        "safehouse",
        Support.integer(Support.read(safehouse, { "getX" }, 0), 0),
        Support.integer(Support.read(safehouse, { "getY" }, 0), 0),
        Support.integer(Support.read(safehouse, { "getW" }, 0), 0),
        Support.integer(Support.read(safehouse, { "getH" }, 0), 0),
    }, ":")
end

function Support.safehouseAllowed(actor, safehouse, binding)
    if not actor or not safehouse then return false end
    if type(binding.safehouseAllowed) == "function" then
        local called, value = pcall(binding.safehouseAllowed, actor, safehouse)
        if called then return value == true end
    end
    local identity = Support.identity(actor, binding)
    if Support.read(safehouse, { "isOwner" }, false, actor) == true then return true end
    if Support.read(safehouse, { "playerAllowed" }, false, identity) == true then return true end
    if tostring(Support.read(safehouse, { "getOwner" }, "") or "") == identity then
        return true
    end
    local players = Support.values(Support.read(safehouse, { "getPlayers" }, nil))
    for index = 1, #players do
        if tostring(players[index] or "") == identity then return true end
    end
    return false
end

function Support.isAdmin(actor, binding)
    if type(binding.isAdmin) == "function" then
        local called, value = pcall(binding.isAdmin, actor)
        if called then return value == true end
    end
    local accessLevel = tostring(Support.read(actor, { "getAccessLevel" }, "") or "")
    return accessLevel ~= "" and accessLevel ~= "None" and accessLevel ~= "none"
end

function Support.nowMs(binding)
    if type(binding.nowMs) == "function" then
        local called, value = pcall(binding.nowMs)
        if called and Support.finite(value) then return math.floor(value) end
    end
    local callback = Support.api(binding, "getTimestampMs")
    if type(callback) == "function" then
        local called, value = pcall(callback)
        if called and Support.finite(value) then return math.floor(value) end
    end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

function Support.newId(binding, prefix, seed)
    if type(binding.newId) == "function" then
        local called, value = pcall(binding.newId, prefix, seed)
        if called and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    local raw = tostring(seed or "") .. ":" .. tostring(Support.nowMs(binding))
    local hash = 5381
    for index = 1, #raw do
        hash = ((hash * 33) + string.byte(raw, index)) % 2147483647
    end
    return tostring(prefix or "storage") .. "-" .. tostring(Support.nowMs(binding))
        .. "-" .. tostring(hash)
end

function Support.lifecycle(moduleId, public, counters)
    local instance = {
        started = false,
        public = public or {},
        counters = counters or { failures = 0 },
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and (self.counters.failures or 0) == 0,
            code = (self.counters.failures or 0) > 0 and "adapterFailure"
                or (self.started and "healthy" or "stopped"),
            data = Support.copy(self.counters),
            moduleId = moduleId,
        }
    end
    if type(instance.public.health) ~= "function" then
        instance.public.health = function() return instance:health() end
    end
    return instance
end

return Support
