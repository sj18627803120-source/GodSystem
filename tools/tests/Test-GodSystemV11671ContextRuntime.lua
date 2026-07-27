local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path
GodSystemConfig = { DataKey = "GodSystem_Test_Context_11671" }
package.loaded.GodSystem_Config = true

local function list(values)
    local result = { values = values or {} }
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    return result
end

local square = { x = 10, y = 20, z = 0, objects = list({}), special = list({}), world = list({}) }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end
function square:getObjects() return self.objects end
function square:getSpecialObjects() return self.special end
function square:getWorldObjects() return self.world end

local function object(index)
    local slot = { parent = nil }
    function slot:getType() return "crate" end
    function slot:getParent() return self.parent end
    local value = { index = index, data = {}, slot = slot, square = square, highlighted = false }
    slot.parent = value
    function value:getObjectIndex() return self.index end
    function value:getModData() return self.data end
    function value:transmitModData() end
    function value:getSquare() return self.square end
    function value:getContainerCount() return 1 end
    function value:getContainerByIndex() return self.slot end
    function value:getSprite() return { getName = function() return "fixture_" .. tostring(index) end } end
    function value:setHighlightColor(playerNum, color)
        assert(type(playerNum) == "number" and type(color) == "table",
            "B42 context-menu highlight color must use the player-index overload")
        self.highlightPlayer = playerNum
        self.highlightColor = color
    end
    function value:setHighlighted(playerNum, enabled, outline)
        assert(type(playerNum) == "number" and type(enabled) == "boolean",
            "B42 context-menu highlighted state must use the player-index overload")
        self.highlightPlayer = playerNum
        self.highlighted = enabled
        self.highlightOutline = outline
    end
    return value
end

local objects = { object(0), object(1), object(2), object(3) }
for i = 1, #objects do square.objects.values[i] = objects[i] end

getCell = function()
    return { getGridSquare = function(_, x, y, z) if x == 10 and y == 20 and z == 0 then return square end end }
end
getPlayer = function()
    return {
        getX = function() return 10 end,
        getY = function() return 20 end,
        getZ = function() return 0 end,
        getPlayerNum = function() return 0 end,
    }
end
getSpecificPlayer = function() return getPlayer() end
ColorInfo = { new = function(r, g, b, a) return { red = r, green = g, blue = b, alpha = a } end }

local function event()
    return { Add = function() end, Remove = function() end }
end
Events = {
    OnFillWorldObjectContextMenu = event(), OnFillInventoryObjectContextMenu = event(),
    OnPreUIDraw = event(), OnDisconnect = event(), OnMainMenuEnter = event(), LoadGridsquare = event(),
}

local Storage = require "GodSystem_Storage"
Storage.setNetworkContainerMarker(objects[1], { scopeKey = "personal:tester", owner = "tester", name = "Core" })
Storage.setNetworkContainerMarker(objects[2], { scopeKey = "personal:tester", owner = "tester", name = "Connected" })
Storage.setNetworkContainerMarker(objects[3], { scopeKey = "personal:tester", owner = "tester", name = "Disconnected" })
local coreMarker = Storage.getNetworkContainerMarker(objects[1])
objects[1].data[Storage.CoreHostKey] = {
    installed = true, hostVersion = Storage.CoreHostVersion, capacityMode = "networkStorage",
    networkId = "network", token = "token", objectId = coreMarker.objectId,
}

GodSystemStorageClient = {
    networkState = { connectedObjectIds = { [coreMarker.objectId] = true, [Storage.getObjectId(objects[2], false)] = true } },
}
GodSystemStorageUI = { open = function() end, depositExternalSelection = function() end }
GodSystemStorageManager = { calibrateLoadedSquare = function() end }
package.loaded.GodSystem_StorageUI = true
package.loaded["ISUI/ISInventoryPaneContextMenu"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true

local Context = require "GodSystem_StorageContext"
assert(Context.candidateNumber(objects[1]) == 1 and Context.candidateNumber(objects[4]) == 4,
    "same-square candidates must use stable object-index numbering")
local r1, g1, b1 = Context.colorForObject(objects[1])
local r2, g2, b2 = Context.colorForObject(objects[2])
local r3, g3, b3 = Context.colorForObject(objects[3])
local r4, g4, b4 = Context.colorForObject(objects[4])
assert(g1 == 0.82 and b1 == 0.42, "core host must be green")
assert(r2 == 0.12 and b2 == 0.92, "connected ordinary container must be blue")
assert(r3 == 0.86 and g3 == 0.26, "disconnected marked container must be red")
assert(r4 == 0.80 and g4 == 0.74, "unmarked candidates must use the temporary neutral highlight")

Context.onOptionHighlight(nil, { player = 0 }, true, objects[4])
assert(objects[4].highlighted == true and Context.highlighted[objects[4]] == 0,
    "menu hover must enable native object highlighting")
assert(objects[4].highlightPlayer == 0, "menu hover must bind highlighting to the context-menu player")
assert(objects[4].highlightColor.red == 0.80 and objects[4].highlightColor.green == 0.74,
    "menu hover must apply the object's state color")
Context.onOptionHighlight(nil, { player = 0 }, false, objects[4])
assert(objects[4].highlighted == false and Context.highlighted[objects[4]] == nil,
    "menu exit must clear native object highlighting")

print("Test-GodSystemV11671ContextRuntime passed")
