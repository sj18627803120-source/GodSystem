local root = assert(arg[1], "repository root required")
local luaRoot = root .. "/Contents/mods/GodSystem/42/media/lua"
package.path = table.concat({
    luaRoot .. "/client/?.lua",
    luaRoot .. "/client/?/?.lua",
    luaRoot .. "/client/?/?/?.lua",
    luaRoot .. "/client/?/?/?/?.lua",
    package.path,
}, ";")

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local texture = { id = "white-pixel" }
local availableTexture = nil
local calls = { reset = 0, emit = {}, update = {}, robot = 0, particles = 0, lines = {} }

GodSystemCompanionVisual = {
    getLineTexture = function() return availableTexture end,
    reset = function() calls.reset = calls.reset + 1 end,
    emit = function(kind, x, y, z)
        calls.emit[#calls.emit + 1] = { kind = kind, x = x, y = y, z = z }
    end,
    update = function(delta) calls.update[#calls.update + 1] = delta end,
    renderRobot = function(renderer, lineTexture)
        expect(lineTexture == texture, "robot received wrong texture")
        calls.robot = calls.robot + 1
        renderer:renderline(lineTexture, 1, 2, 3, 4, 0.1, 0.2, 0.3, 0.4)
    end,
    renderParticles = function(renderer, lineTexture)
        expect(lineTexture == texture, "particles received wrong texture")
        calls.particles = calls.particles + 1
        renderer:renderline(lineTexture, 4, 3, 2, 1, 0.4, 0.3, 0.2, 0.1)
    end,
}
package.loaded["GodSystem_CompanionVisual"] = GodSystemCompanionVisual

require "GodSystem/Platform/Companion/PZVisuals"

local clock = 1000
local renderer = {}
function renderer:renderline(lineTexture, x1, y1, x2, y2, red, green, blue, alpha)
    expect(lineTexture == texture, "renderline received wrong texture")
    for _, value in ipairs({ x1, y1, x2, y2, red, green, blue, alpha }) do
        expect(type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge, "renderline argument is not finite")
    end
    expect(x1 == math.floor(x1) and y1 == math.floor(y1)
        and x2 == math.floor(x2) and y2 == math.floor(y2), "screen coordinates are not integers")
    calls.lines[#calls.lines + 1] = { x1, y1, x2, y2, red, green, blue, alpha }
end

local binding = {
    visual = GodSystemCompanionVisual,
    nowMs = function() return clock end,
    renderer = function() return renderer end,
    zoom = function() return 1 end,
    toScreen = function(x, y) return x * 20, y * 20 end,
}

local missing = GodSystemCompanionPZVisualsPlatform.create({}, { binding = binding })
local started, code = missing:start()
expect(started == false and code == "textureMissing", "missing texture did not fail explicitly")
expect(missing:health().ok == false and missing:health().code == "textureMissing",
    "missing texture health is not actionable")

availableTexture = texture
local instance = GodSystemCompanionPZVisualsPlatform.create({}, { binding = binding })
expect(instance:start() == true, "visual adapter failed to start")

local source = { x = 3, y = 4, z = 0 }
local target = { x = 6, y = 5, z = 0 }
local runtime = {
    robotX = 2,
    robotY = 3,
    robotZ = 0,
    behaviorState = "charging",
    sightTargets = { { target = target, expiresAt = 3000 } },
    markStates = { [target] = 3000 },
    projectiles = {
        { target = target, startX = 2, startY = 3, startZ = 0, elapsed = 0.2, duration = 0.35 },
    },
    effectVisuals = {
        { kind = "chain", source = source, target = target, createdAt = 900, expiresAt = 1300 },
        { kind = "guardian", source = source, createdAt = 900, expiresAt = 1400 },
        { kind = "blast", source = source, createdAt = 900, expiresAt = 1400 },
        { kind = "corrosion", source = source, createdAt = 900, expiresAt = 1400 },
        { kind = "shock", source = source, createdAt = 900, expiresAt = 1400 },
    },
}
local data = { unlocked = true, visible = true }

expect(instance.public.emit("charge", runtime, data, nil, target) == true, "visual emit failed")
expect(calls.emit[1].kind == "charge" and calls.emit[1].x == 2
    and calls.emit[1].y == 3 and calls.emit[1].z == 0, "visual emit parameters drifted")
expect(instance.public.update(0.5) == true, "explicit visual update failed")
expect(calls.update[#calls.update] == 0.25, "visual update was not bounded")

expect(instance.public.render(runtime, data, {}) == true, "first visual render failed")
clock = 1100
expect(instance.public.render(runtime, data, {}) == true, "second visual render failed")
expect(calls.robot == 2 and calls.particles == 2, "robot or particles were not rendered")
expect(#calls.update >= 3 and math.abs(calls.update[#calls.update] - 0.1) < 0.0001,
    "render did not advance particle time")
expect(#calls.lines >= 100, "combat, guardian, sight, mark and beam drawing was incomplete")

expect(instance.public.reset(runtime) == true, "visual reset failed")
local beforeStop = calls.reset
expect(instance:stop() == true, "visual stop failed")
expect(calls.reset == beforeStop + 1, "visual stop did not clear particles")
expect(instance:health().code == "stopped", "visual stop health drifted")

print("Test-GodSystemV422012CompanionPZVisualsRuntime passed")
