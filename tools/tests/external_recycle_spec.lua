local function load(path) return assert(loadstring(readSource(path)))() end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
load("shared/GodSystem_B42JavaCalls.lua")
load("shared/GodSystem_ExternalRecycle.lua")
local E = GodSystemExternalRecycle

do
    -- A Lua table can mask a missing explicit Java wrapper. Simulate the
    -- userdata-only branch for the newly required native contracts.
    local native = { isExistYet=function() return false end,
        isRemoveItemAllowed=function() return true end,
        haveThisKeyId=function() return { key=true } end }
    local oldType=type
    type=function(value) if value==native then return "userdata" end return oldType(value) end
    local exists, value=GodSystemB42JavaCalls.try(native,"isExistYet")
    local allowed, permitted=GodSystemB42JavaCalls.try(native,"isRemoveItemAllowed")
    local keyRead, key=GodSystemB42JavaCalls.try(native,"haveThisKeyId",15)
    type=oldType
    assert(exists and value==false and allowed and permitted==true and keyRead and key.key,
        "explicit Java wrappers must preserve false and object returns")
end

local function fixture()
    local world, objects, floor = {}, {}, { rows = {} }
    function floor:isRemoveItemAllowed() return true end
    function floor:getType() return "floor" end
    function floor:contains(item) return self.rows[item] == true end
    function floor:DoRemoveItem(item) self.rows[item] = nil end
    function floor:DoAddItemBlind(item) self.rows[item] = true end
    local square = { x = 10, y = 20, z = 0 }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getWorldObjects() return { size = function() return #world end,
        get = function(_, index) return world[index + 1] end,
        contains = function(_, obj) for _, value in ipairs(world) do if obj == value then return true end end return false end } end
    function square:getObjects() return { contains = function(_, obj)
        for _, value in ipairs(objects) do if obj == value then return true end end return false end } end
    function square:transmitRemoveItemFromSquare(object)
        self.removedPacket = object
        object:removeFromWorld(); object:removeFromSquare()
        return 0
    end
    function square:removeWorldObject(object)
        object:removeFromWorld(); object:removeFromSquare()
    end
    function square:AddWorldInventoryItem(item)
        local object = { square = square, getItem = function() return item end, getSquare = function(self) return self.square end,
            transmitCompleteItemToClients = function() square.addedPacket = true end }
        function object:removeFromWorld() self.removeWorldCalls = (self.removeWorldCalls or 0) + 1 end
        function object:removeFromSquare()
            for i = #world, 1, -1 do if world[i] == self then table.remove(world, i) end end
            for i = #objects, 1, -1 do if objects[i] == self then table.remove(objects, i) end end
        end
        function object:setSquare(value) self.square = value end
        item.world = object
        world[#world + 1] = object
        objects[#objects + 1] = object
        return object
    end
    local item = { id = 42, container = floor }
    function item:getID() return self.id end
    function item:getFullType() return "Base.Bullets9mm" end
    function item:getContainer() return self.container end
    function item:getWorldItem() return self.world end
    function item:setWorldItem(value) self.world = value end
    floor.rows[item] = true
    square:AddWorldInventoryItem(item)
    local player = { getX = function() return 10 end, getY = function() return 20 end,
        getZ = function() return 0 end, getCurrentSquare = function() return square end,
        getUsername = function() return "tester" end }
    local cell = { getGridSquare = function(_, x, y, z)
        if x == 10 and y == 20 and z == 0 then return square end
    end }
    return player, item, floor, square, cell, world
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local object=item.world
    local row=assert(E.resolve(player,E.describe(item)))
    assert(E.remove(row)); eq(object.removeWorldCalls,1)
    eq(#world,0); eq(item.world,nil); eq(object.square,nil)
    print("PASS ground deletion: native transmit lifecycle is not executed twice")
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    local transmit=square.transmitRemoveItemFromSquare
    square.transmitRemoveItemFromSquare=function(self,obj) transmit(self,obj); error("post-remove event failed") end
    local ok,reason,detail=E.remove(row)
    eq(ok,true); eq(reason,nil); eq(#world,0); eq(item.world,nil)
    eq(detail.step,"worldTransmit"); eq(detail.mutation,"complete")
    assert(detail.error:find("post%-remove event failed"))
    print("PASS ground deletion: SP post-removal exception reconciles verified complete removal")
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    local read=square.getWorldObjects
    local failed=false
    square.getWorldObjects=function(self)
        local result=read(self)
        if #world==0 and not failed then failed=true; result.contains=function() error("transient verification read") end end
        return result
    end
    local ok,_,detail=E.remove(row)
    eq(ok,true); eq(#world,0); eq(item.world,nil)
    assert(detail.error:find("transient verification read",1,true))
    print("PASS ground deletion: bounded recheck handles transient native verification reads")
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return true end; SafeHouse={isSafeHouse=function() return nil end}
    local row=assert(E.resolve(player,E.describe(item)))
    local transmit=square.transmitRemoveItemFromSquare
    square.transmitRemoveItemFromSquare=function(self,obj) transmit(self,obj); error("server packet failed") end
    local ok,reason,detail=E.remove(row)
    eq(ok,false); eq(reason,"deleteFailed"); eq(detail.mutation,"unverified")
    assert(E.restore(row)); eq(#world,1)
    print("PASS ground deletion: server transmit exceptions never authorize payment")
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    square.transmitRemoveItemFromSquare=function() error("remove was not performed") end
    local ok,reason,detail=E.remove(row)
    eq(ok,false); eq(reason,"deleteFailed"); eq(detail.step,"worldTransmit"); eq(#world,1)
    assert(E.restore(row)); eq(#world,1)
    print("PASS ground deletion: unchanged targets fail and restore without duplicate objects")
end

do
    local player, item, floor, square, cell, world = fixture()
    item.container = nil
    getCell = function() return cell end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return false end }
    local source = assert(E.describe(item))
    eq(source.containerType, "floor")
    local row = assert(E.resolve(player, source))
    assert(E.remove(row)); eq(#world, 0)
    assert(E.restore(row)); eq(#world, 1)
    print("PASS external recycle: server world item needs no client-only floor container")
end

do
    local player, item, floor, square, cell, world = fixture()
    getCell = function() return cell end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return false end }
    local source = E.describe(item)
    local row = assert(E.resolve(player, source))
    assert(E.remove(row))
    eq(#world, 0); eq(item:getWorldItem(), nil)
    assert(E.restore(row))
    eq(#world, 1); eq(floor:contains(item), true)
    eq(E.describe(item).itemId, "42")
    assert(square.removedPacket and square.addedPacket)
    print("PASS external recycle: world object removal and restore do not depend on floor view")
end

do
    local player, item, floor, square, cell, world = fixture()
    getCell = function() return cell end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return false end }
    -- The loot window's floor container is a transient view. Vanilla ground
    -- pickup checks the world object, not membership in that container.
    floor.rows[item] = nil
    floor.isRemoveItemAllowed = function() return false end
    local source = assert(E.describe(item))
    local row = assert(E.resolve(player, source))
    eq(row.container, nil)
    assert(E.remove(row)); eq(#world, 0)
    assert(E.restore(row)); eq(#world, 1)
    player.getX = function() return 9.8 end
    player.getY = function() return 20.8 end
    assert(E.resolve(player, source), "adjacent tile with fractional coordinates must be reachable")
    player.getX = function() return 8.9 end
    local distant, reason = E.resolve(player, source)
    eq(distant, nil); eq(reason, "distance")
    print("PASS external recycle: loose world item ignores transient floor container and uses tile distance")
end

do
    local player, item, floor, square, cell = fixture()
    getCell = function() return cell end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return true end }
    local source = E.describe(item)
    local row, reason = E.resolve(player, source)
    eq(row, nil); eq(reason, "protected")
    SafeHouse.isSafeHouse = function() return false end
    player.getX = function() return 100 end
    row, reason = E.resolve(player, source)
    eq(row, nil); eq(reason, "distance")
    print("PASS external recycle: server rejects protected and distant floor items")
end

do
    local player, item, floor, square, cell, world = fixture()
    getCell = function() return cell end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return false end }
    square.transmitRemoveItemFromSquare = function() error("network send interrupted") end
    local row = assert(E.resolve(player, E.describe(item)))
    assert(not E.remove(row), "partial native removal must not report success")
    eq(#world, 1)
    assert(E.restore(row), "original floor entry and object must be recoverable")
    eq(floor:contains(item), true); eq(#world, 1)
    assert(square.addedPacket, "restored object must be resent after an interrupted remove")
    print("PASS external recycle: partial removal restores floor entry and resends object")
end

local function containerFixture(kind, nested)
    local square = { x = 10, y = 20, z = 0 }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    local rows = {}
    local function container(typeName, parent, containing)
        local result = { typeName = typeName, parent = parent, containing = containing, rows = {} }
        function result:getType() return self.typeName end
        function result:getParent() return self.parent end
        function result:getContainingItem() return self.containing end
        function result:getSourceGrid() return square end
        function result:isExistYet() return true end
        function result:isRemoveItemAllowed() return true end
        function result:contains(item) return self.rows[item] == true end
        function result:DoRemoveItem(item) self.rows[item] = nil end
        function result:AddItem(item) self.rows[item] = true; item.container = self; return item end
        function result:getItems()
            local list = {}
            for item in pairs(self.rows) do list[#list + 1] = item end
            return { size = function() return #list end, get = function(_, index) return list[index + 1] end }
        end
        return result
    end
    local parent = { kind = kind, getSquare = function() return square end }
    local root = container(kind == "vehicle" and "Trunk" or "crate", parent)
    function parent:getObjectIndex() return 0 end
    function parent:getContainerCount() return 1 end
    function parent:getContainerByIndex(index) if index == 0 then return root end end
    function parent:getContainer() return root end
    function parent:getStaticMovingObjectIndex() return 0 end
    function parent:getId() return 7 end
    function parent:getPartCount() return 1 end
    function parent:getPartById(id) if id == "Trunk" then return self.part end end
    function parent:getPartByIndex(index) if index == 0 then return self.part end end
    function parent:canAccessContainer() return self.access ~= false end
    parent.part = { getId = function() return "Trunk" end,
        getItemContainer = function() return root end,
        setContainerContentAmount = function() end }
    function root:getCapacityWeight() return 0 end
    local item = { id = 42, container = root }
    function item:getID() return self.id end
    function item:getContainer() return self.container end
    function item:getInventory() return self.inventory end
    root.rows[item] = true
    if nested then
        local bag = { id = 9, container = root }
        function bag:getID() return self.id end
        function bag:getContainer() return self.container end
        function bag:getInventory() return self.inventory end
        root.rows[item] = nil
        root.rows[bag] = true
        local inside = container("bag", bag, bag)
        bag.inventory, item.container = inside, inside
        inside.rows[item] = true
    end
    local objectList = kind == "worldContainer" and { parent } or {}
    local corpseList = kind == "corpse" and { parent } or {}
    function square:getObjects() return { size = function() return #objectList end,
        get = function(_, index) return objectList[index + 1] end } end
    function square:getStaticMovingObjects() return { size = function() return #corpseList end,
        get = function(_, index) return corpseList[index + 1] end } end
    local player = { getX = function() return 10 end, getY = function() return 20 end,
        getZ = function() return 0 end, getCurrentSquare = function() return square end,
        getUsername = function() return "tester" end }
    getCell = function() return { getGridSquare = function(_, x, y, z)
        if x == 10 and y == 20 and z == 0 then return square end
    end } end
    isServer = function() return true end
    SafeHouse = { isSafeHouse = function() return false end }
    instanceof = function(object, class)
        return object and object.kind == class or class == "BaseVehicle" and object == parent and kind == "vehicle"
            or class == "IsoDeadBody" and object == parent and kind == "corpse"
    end
    getVehicleById = function(id) if id == 7 and kind == "vehicle" then return parent end end
    return player, item, root, parent
end

for _, kind in ipairs({ "worldContainer", "corpse", "vehicle" }) do
    for _, nested in ipairs({ false, true }) do
        local player, item, root, parent = containerFixture(kind, nested)
        local descriptor = assert(E.describe(item), kind .. " describe")
        eq(descriptor.kind, kind)
        local row = assert(E.resolve(player, descriptor, {}), kind .. " resolve")
        assert(E.remove(row), kind .. " remove")
        eq(row.container:contains(item), false)
        assert(E.restore(row), kind .. " restore")
        eq(row.container:contains(item), true)
        if kind == "vehicle" then
            parent.access = false
            local denied = E.resolve(player, descriptor, {})
            eq(denied, nil)
        end
        print("PASS external recycle: " .. kind .. (nested and " nested" or " direct") .. " resolve/remove/restore")
    end
end

-- Native returns must retain their types, including false and Java-like objects.
for _, method in ipairs({ "isExistYet", "isRemoveItemAllowed" }) do
    for _, behavior in ipairs({ "false", "nil", "missing", "error" }) do
        local player, item, root = containerFixture("worldContainer", false)
        root[method] = behavior ~= "missing" and function()
            if behavior == "error" then error("native unavailable") end
            if behavior == "false" then return false end
        end or nil
        assert(not E.resolve(player, E.describe(item), {}), method..":"..behavior)
    end
end

do
    local player, item = containerFixture("worldContainer", false)
    SafeHouse.isSafeHouse = function() return { nativeSafeHouse=true } end
    local row, reason = E.resolve(player, E.describe(item), {})
    eq(row,nil); eq(reason,"protected")
    SafeHouse.isSafeHouse = function() return nil end
    assert(E.resolve(player,E.describe(item),{}), "nil means no protected safehouse")
    local invalid = setmetatable({}, {__index=function() error("invalid object") end})
    assert(E.describe(invalid)==nil, "member lookup must be protected")
    assert(E.describe({getID=function() return nil end})==nil)
end

do
    local player, item, root, object = containerFixture("worldContainer", false)
    local previous = instanceof
    instanceof=function(value,class) return class=="IsoThumpable" and value==object or previous(value,class) end
    object.isLockedToCharacter=function() return false end
    object.isLockedByPadlock=function() return true end
    object.getKeyId=function() return 15 end
    local key = { fullType="Base.KeyPadlock" }
    local inventory={haveThisKeyId=function(_,id) if id==15 then return key end end}
    player.getInventory=function() return inventory end
    assert(E.resolve(player,E.describe(item),{}), "native key object grants access")
    inventory.haveThisKeyId=function() return nil end
    assert(not E.resolve(player,E.describe(item),{}), "missing key denies access")
    object.isLockedToCharacter=function() error("lock read failed") end
    assert(not E.resolve(player,E.describe(item),{}), "unreadable lock denies access")
end

do
    local player,item,root=containerFixture("worldContainer",false)
    local row=assert(E.resolve(player,E.describe(item),{}))
    root.isRemoveItemAllowed=function() return false end
    assert(not E.remove(row) and root:contains(item), "revalidate immediately before mutation")
end

for _, size in ipairs({100,500,2000,5000}) do
    local player, first, floor, square, cell, world = fixture()
    local items, descriptors, visits = {}, {}, 0
    for i=#world,1,-1 do world[i]=nil end
    for i=1,size do
        local item={id=i,container=floor,getID=first.getID,getContainer=first.getContainer,
            getWorldItem=first.getWorldItem,setWorldItem=first.setWorldItem}
        floor.rows[item]=true; square:AddWorldInventoryItem(item)
        items[i]=item; descriptors[i]=assert(E.describe(item))
    end
    square.getWorldObjects=function() return {size=function() return #world end,
        get=function(_,i) visits=visits+1; return world[i+1] end,
        contains=function(_, obj) for _,v in ipairs(world) do if v==obj then return true end end return false end} end
    getCell=function() return cell end
    SafeHouse={isSafeHouse=function() return nil end}
    local cache={}
    local started=os and os.clock and os.clock() or 0
    for i=1,size do assert(E.resolve(player,descriptors[i],cache)) end
    assert(visits==size, "one world list traversal per transaction/square")
    print("RECYCLE_LOCATE_SIM n="..size.." visits="..visits.." ms="..
        tostring(((os and os.clock and os.clock() or 0)-started)*1000))
    local row=assert(E.resolve(player,descriptors[1],cache))
    assert(E.remove(row)); assert(not E.resolve(player,descriptors[1],cache))
    assert(E.restore(row)); assert(E.resolve(player,descriptors[1],cache))
    -- A fresh request detects duplicate native IDs rather than choosing an object.
    items[2].id=items[1].id
    assert(not E.resolve(player,descriptors[1],{}), "duplicate ID ambiguous")
end
print("PASS external recycle: typed native returns, denial, stale targets, bounded request index")

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    local read=square.getWorldObjects
    square.getWorldObjects=function(self)
        local result=read(self)
        if #world==0 then result.contains=function() error("persistent verify failure") end end
        return result
    end
    local ok,reason,detail=E.remove(row)
    eq(ok,false); eq(reason,"deleteFailed"); eq(detail.world,"unknown")
    assert(not E.restore(row),"uncertain world state cannot claim restored or create duplicates")
    eq(#world,0)
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    item.setWorldItem=function() error("world link setter failed") end
    local ok,reason,detail=E.remove(row)
    eq(ok,false); eq(reason,"deleteFailed"); eq(detail.step,"clearItemWorld")
    eq(detail.itemLink,"linked"); assert(E.restore(row)); eq(#world,1)
end

do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return true end; SafeHouse={isSafeHouse=function() return nil end}
    local row=assert(E.resolve(player,E.describe(item)))
    square.transmitRemoveItemFromSquare=function() return -1 end
    local ok,reason,detail=E.remove(row)
    eq(ok,false); eq(reason,"deleteFailed"); eq(detail.step,"worldTransmit")
    eq(#world,1); assert(E.restore(row))
end

assert(E.canFallbackSources({{kind="worldItem"}}))
assert(not E.canFallbackSources(nil))
assert(not E.canFallbackSources({{kind="worldItem"},{kind="vehicle"}}))
print("PASS ground verification: persistent read/link errors and server -1 keep rollback protection")

for _,change in ipairs({"inventory", "otherSquare", "partialMembership"}) do
    local player,item,_,square,cell,world=fixture()
    getCell=function() return cell end; isServer=function() return false end; SafeHouse=nil
    local row=assert(E.resolve(player,E.describe(item)))
    if change=="inventory" then
        item.container={getType=function() return "inventory" end}
    elseif change=="otherSquare" then item.world.square={}
    else table.remove(world,1) end
    local count, object = #world, item.world
    assert(not E.restore(row),"moved or partially removed objects cannot authorize backup pickup")
    eq(#world,count); eq(item.world,object)
end
print("PASS ground restore: new inventory owner, moved world object and inconsistent lists never duplicate items")

do
    local player,item,floor,square,cell=fixture()
    getCell=function() return cell end
    SafeHouse={isSafeHouse=function() return nil end}
    local row=assert(E.resolve(player,E.describe(item)))
    square.getWorldObjects=function() return {contains=function() error("native contains read failed") end} end
    local ok,reason=E.remove(row)
    eq(ok,false); eq(reason,"nativeReadFailed"); assert(item:getWorldItem())
    assert(not E.restore(row), "unknown membership must not add a duplicate world object")
end

do
    local player,item,root,parent=containerFixture("vehicle",false)
    local counts={weight=0,dirty=0,sync=0}
    root.setDrawDirty=function() counts.dirty=counts.dirty+1 end
    parent.part.setContainerContentAmount=function() counts.weight=counts.weight+1 end
    ArrayList={new=function() return {rows={},add=function(self,v) self.rows[#self.rows+1]=v end} end}
    sendRemoveItemsFromContainer=function(container,items) eq(container,root); assert(items.rows); counts.sync=counts.sync+1 end
    local batch=E.newBatch()
    local row=assert(E.resolve(player,E.describe(item)))
    assert(E.remove(row,batch)); eq(counts.weight,0); eq(counts.sync,0)
    assert(E.flushBatch(batch)); eq(counts.weight,1); eq(counts.dirty,1); eq(counts.sync,1)
    local updates=E.newBatch(); assert(E.restore(row,updates)); eq(counts.weight,1)
    assert(E.flushUpdates(updates)); eq(counts.weight,2)
end
