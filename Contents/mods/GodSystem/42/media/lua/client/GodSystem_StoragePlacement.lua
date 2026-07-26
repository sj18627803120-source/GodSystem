require "BuildingObjects/ISBuildingObject"
require "GodSystem_StorageClient"

GodSystemStoragePlacement = ISBuildingObject:derive("GodSystemStoragePlacement")

local Placement = GodSystemStoragePlacement
local Storage = GodSystemStorage
local Client = GodSystemStorageClient

local function playerByNumber(playerNum)
    return getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer()
end

function Placement:isValid(square)
    local player = playerByNumber(self.player)
    if not square or not player or not self.item then return false end
    if Storage.itemId(self.item) ~= tostring(self.itemId or "") then return false end
    local networkId, token = Storage.getControllerIdentity(self.item)
    if networkId == "" or token == "" then return false end
    local position = {
        x = Storage.integer(Storage.safeCall(square, "getX", 0), 0),
        y = Storage.integer(Storage.safeCall(square, "getY", 0), 0),
        z = Storage.integer(Storage.safeCall(square, "getZ", 0), 0),
    }
    local playerPosition = Storage.positionOfPlayer(player)
    if not playerPosition
        or Storage.integer(playerPosition.z, -1) ~= position.z
        or Storage.distance2D(playerPosition, position) > Storage.ControllerPlacementDistance then
        return false
    end
    if Storage.safeCall(square, "isVehicleIntersecting", false) == true then return false end
    if not Storage.safeCall(square, "getFloor", nil) then return false end
    local objects = Storage.squareObjects(square)
    for i = 1, #objects do
        local object = objects[i]
        if Storage.isInstalledController(object)
            or Storage.isController(Storage.safeCall(object, "getItem", nil)) then
            return false
        end
    end
    return true
end

function Placement:render(x, y, z, square)
    local cursor = self:getFloorCursorSprite()
    if not cursor then return end
    if self:isValid(square) then
        cursor:RenderGhostTileColor(x, y, z, 0, 0, 0.12, 0.72, 0.95, 0.75)
    else
        cursor:RenderGhostTileColor(x, y, z, 0, 0, 0.85, 0.12, 0.12, 0.75)
    end
end

function Placement:create(x, y, z)
    if getCell then getCell():setDrag(nil, self.player) end
    Client.installController(self.item, x, y, z)
end

function Placement:tryBuild(x, y, z)
    local square = getCell and getCell():getGridSquare(x, y, z) or nil
    if not self:isValid(square) then return nil end
    self:create(x, y, z)
    return nil
end

function Placement:new(playerNum, item)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    o.player = playerNum or 0
    o.character = playerByNumber(o.player)
    o.item = item
    o.itemId = Storage.itemId(item)
    o.name = "GodSystem Storage Controller"
    o.noNeedHammer = true
    o.skipBuildAction = true
    o.dragNilAfterPlace = true
    o.canBeAlwaysPlaced = true
    o.blockAllTheSquare = false
    o.canPassThrough = true
    o:setSprite("carpentry_02_56")
    o:setNorthSprite("carpentry_02_56")
    return o
end

function Placement.start(playerNum, item)
    if not item or not Storage.isController(item) then return false end
    local cursor = Placement:new(playerNum, item)
    if not cursor or not getCell then return false end
    getCell():setDrag(cursor, playerNum or 0)
    return true
end

return Placement
