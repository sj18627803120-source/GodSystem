local luaRoot = assert(arg[1], "lua root is required")
package.path = luaRoot .. "/client/?.lua;" .. package.path

local handlers = {}
local function event()
    return {
        Add = function(handler) handlers[#handlers + 1] = handler end,
        Remove = function() end,
    }
end
Events = {
    OnFillWorldObjectContextMenu = event(), OnFillInventoryObjectContextMenu = event(),
    OnPreUIDraw = event(), OnTick = event(), OnDisconnect = event(), OnMainMenuEnter = event(),
    LoadGridsquare = event(),
}

GodSystemStorage = {
    integer = function(value, fallback) return math.floor(tonumber(value) or fallback or 0) end,
}
GodSystemStorageClient = {}
GodSystemStorageUI = {}
package.loaded.GodSystem_StorageUI = true
package.loaded["ISUI/ISInventoryPaneContextMenu"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true

isIngameState = function() return true end
getCore = function() return { getZoom = function() return 1 end } end
ISCoordConversion = { ToScreen = function(x, y) return x, y end }
getTexture = function() return "line" end

local lines = {}
local renderer = {}
function renderer:renderline(_, x1, y1, x2, y2, red, green, blue)
    lines[#lines + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, r = red, g = green, b = blue }
end
getRenderer = function() return renderer end

local Layout = require "GodSystem_StorageMarkerLayout"
assert(Layout.number(0) == 1 and Layout.number(3.8) == 3, "marker numbers must normalize to positive integers")
local x, y = Layout.position(100, 200, 3, 14)
assert(x == 100 and y == 172, "third same-square marker must remain on the same x and move upward twice")

local Context = require "GodSystem_StorageContext"
Context.connectMode = true
Context.lineTexture = nil
Context.markerCount = 3
Context.markers = {
    bottom = { x = 0, y = 0, z = 0, number = 1, connected = false, coreHost = false },
    middle = { x = 0, y = 0, z = 0, number = 2, connected = true, coreHost = false },
    top = { x = 0, y = 0, z = 0, number = 3, connected = false, coreHost = true },
}
Context.renderMarkers()

assert(#lines == 6, "three same-square markers must draw exactly one chevron each")
local apexes, colors = {}, {}
for index = 1, #lines, 2 do
    local left, right = lines[index], lines[index + 1]
    assert(left.x2 == right.x1 and left.y2 == right.y1, "each marker must draw one joined chevron")
    apexes[left.y2] = left.x2
    colors[string.format("%.2f,%.2f,%.2f", left.r, left.g, left.b)] = true
end
assert(apexes[-46] == 0 and apexes[-60] == 0 and apexes[-74] == 0,
    "same-square marker positions must share one x and increase upward by the stable step")
assert(colors["0.86,0.26,0.28"] and colors["0.12,0.48,0.92"] and colors["0.12,0.82,0.42"],
    "disconnected, connected, and core-host marker colors must remain red, blue, and green")

print("Test-GodSystemV422013StorageMarkerRuntime passed")
