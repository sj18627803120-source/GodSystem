if (isClient and isClient()) or (isServer and isServer()) then return end

GodSystemCompanionVisual = GodSystemCompanionVisual or {}

local Visual = GodSystemCompanionVisual

Visual.CanvasWidth = 32
Visual.CanvasHeight = 24
Visual.FrameCount = 2
Visual.ParticleCap = 24
Visual.MaxBodySegments = 36
Visual.Directions = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local ORIGIN_X = 15.5
local ORIGIN_Y = 8
local TEXTURE_RETRY_MS = 1000

local HULL_ROWS = {
    "................................",
    "................................",
    "..............BBBB..............",
    "..........DDDDDDDDDDDD..........",
    "......DDDDDDBBBBBBBBDDDDDD......",
    "DDDDDDDDD.BBBBBBBBBBBB.DDDDDDDDD",
    "DDDDDDD.BBBBBBBBBBBBBBBB.DDDDDDD",
    "..DDDDDDD.BBBBBBBBBBBB.DDDDDDD..",
    "....DDDDDDDBBBBBBBBBBDDDDDDD....",
    "......DDDDDDBBBBBBBBDDDDDD......",
    "........DDDDDBBBBBBDDDDD........",
    "..........DDDBBBBBBDDD..........",
    "............DDBBBBDD............",
    "...........DDD....DDD...........",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
}

local CORE_SEGMENTS = {
    { 14, 17, 6, "C" },
    { 12, 19, 7, "C" },
    { 13, 18, 8, "W" },
    { 13, 18, 9, "W" },
    { 14, 17, 10, "C" },
}

local FRAME_OVERLAYS = {
    [0] = {
        { 11, 13, 14, "C" }, { 18, 20, 14, "C" },
        { 12, 12, 15, "T" }, { 19, 19, 15, "T" },
    },
    [1] = {
        { 11, 13, 14, "C" }, { 18, 20, 14, "C" },
        { 12, 13, 15, "T" }, { 18, 19, 15, "T" },
        { 12, 12, 16, "T" }, { 19, 19, 16, "T" },
        { 12, 12, 17, "T" }, { 19, 19, 17, "T" },
    },
}

local DIRECTION_OVERLAYS = {
    N = { { 15, 16, 0, "R" }, { 15, 16, 1, "R" }, { 14, 17, 2, "C" } },
    NE = { { 22, 23, 2, "R" }, { 24, 25, 3, "R" }, { 20, 23, 4, "C" } },
    E = { { 30, 31, 5, "R" }, { 30, 31, 6, "R" }, { 26, 29, 7, "C" } },
    SE = { { 22, 23, 12, "R" }, { 22, 23, 13, "R" }, { 18, 21, 11, "C" } },
    S = { { 15, 16, 13, "R" }, { 15, 16, 14, "R" }, { 14, 17, 12, "C" } },
    SW = { { 8, 9, 12, "R" }, { 8, 9, 13, "R" }, { 10, 13, 11, "C" } },
    W = { { 0, 1, 5, "R" }, { 0, 1, 6, "R" }, { 2, 5, 7, "C" } },
    NW = { { 8, 9, 2, "R" }, { 6, 7, 3, "R" }, { 8, 11, 4, "C" } },
}

local GUARDIAN_OVERLAY = {
    { 0, 5, 8, "C" }, { 26, 31, 8, "C" },
    { 2, 6, 9, "B" }, { 25, 29, 9, "B" },
}

local PALETTE = {
    D = { 0.04, 0.14, 0.30, 0.96 },
    B = { 0.08, 0.42, 0.92, 0.98 },
    C = { 0.20, 0.88, 1.00, 1.00 },
    R = { 1.00, 0.10, 0.06, 1.00 },
    T = { 0.18, 0.74, 1.00, 0.90 },
}

local PARTICLE_COLORS = {
    cyan = { 0.20, 0.90, 1.00 },
    blue = { 0.12, 0.52, 1.00 },
    red = { 1.00, 0.10, 0.04 },
    orange = { 1.00, 0.48, 0.08 },
    white = { 0.88, 0.98, 1.00 },
}

local DIRECTION_VECTOR = {
    N = { 0, -1 }, NE = { 1, -1 }, E = { 1, 0 }, SE = { 1, 1 },
    S = { 0, 1 }, SW = { -1, 1 }, W = { -1, 0 }, NW = { -1, -1 },
}

local particles = {}
local nextParticle = 1
local cachedTexture = nil
local nextTextureAttemptMs = 0
local segmentCache = {}
local guardianScaleCache = {}

for index = 1, Visual.ParticleCap do
    particles[index] = { active = false }
end

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor((os and os.time and os.time() or 0) * 1000)
end

local function randomBetween(minimum, maximum)
    if ZombRandFloat then return ZombRandFloat(minimum, maximum) end
    return minimum
end

local function screenPoint(x, y, z)
    if not ISCoordConversion or not ISCoordConversion.ToScreen then return nil, nil, nil end
    local sx, sy = ISCoordConversion.ToScreen(x, y, z)
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom, zoom
end

local function compileRows(rows)
    local segments = {}
    for rowIndex = 1, #rows do
        local row = rows[rowIndex]
        local column = 1
        while column <= #row do
            local key = string.sub(row, column, column)
            if key == "." then
                column = column + 1
            else
                local first = column
                while column + 1 <= #row and string.sub(row, column + 1, column + 1) == key do
                    column = column + 1
                end
                segments[#segments + 1] = { first - 1, column - 1, rowIndex - 1, key }
                column = column + 1
            end
        end
    end
    return segments
end

local HULL_SEGMENTS = compileRows(HULL_ROWS)

local function maximumOverlaySegments(overlays)
    local maximum = 0
    for _, segments in pairs(overlays) do maximum = math.max(maximum, #segments) end
    return maximum
end

Visual.CompiledBodySegments = #HULL_SEGMENTS + #CORE_SEGMENTS
    + maximumOverlaySegments(FRAME_OVERLAYS) + maximumOverlaySegments(DIRECTION_OVERLAYS)
if Visual.CompiledBodySegments > Visual.MaxBodySegments then error("GodSystem companion body exceeds segment budget") end

local function appendScaled(target, source, scale)
    for index = 1, #source do
        local segment = source[index]
        target[#target + 1] = {
            math.floor((segment[1] - ORIGIN_X) * scale + 0.5),
            math.floor((segment[2] - ORIGIN_X) * scale + 0.5) + scale - 1,
            math.floor((segment[3] - ORIGIN_Y) * scale + 0.5),
            segment[4],
            scale,
        }
    end
end

local function getBodySegments(direction, frame, scale)
    direction = DIRECTION_OVERLAYS[direction] and direction or "SE"
    frame = frame == 1 and 1 or 0
    scale = scale == 2 and 2 or 1
    local key = direction .. ":" .. tostring(frame) .. ":" .. tostring(scale)
    local cached = segmentCache[key]
    if cached then return cached end
    cached = {}
    appendScaled(cached, HULL_SEGMENTS, scale)
    appendScaled(cached, CORE_SEGMENTS, scale)
    appendScaled(cached, FRAME_OVERLAYS[frame], scale)
    appendScaled(cached, DIRECTION_OVERLAYS[direction], scale)
    segmentCache[key] = cached
    return cached
end

local function getGuardianSegments(scale)
    scale = scale == 2 and 2 or 1
    local cached = guardianScaleCache[scale]
    if cached then return cached end
    cached = {}
    appendScaled(cached, GUARDIAN_OVERLAY, scale)
    guardianScaleCache[scale] = cached
    return cached
end

local function drawLine(renderer, texture, x1, y1, x2, y2, red, green, blue, alpha)
    if math.floor(x1) == math.floor(x2) then x2 = x2 + 1 end
    renderer:renderline(texture, math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2),
        red, green, blue, alpha or 1.0)
end

local function coreColor(runtime, now, pulse)
    local state = runtime.behaviorState or "idle"
    if state == "charging" then
        local started = tonumber(runtime.chargeStartedMs) or now
        local ending = tonumber(runtime.chargeEndsMs) or now
        local duration = math.max(1, ending - started)
        local progress = math.max(0, math.min(1, (now - started) / duration))
        return 1.0, 0.48 * (1 - progress), 0.08 * (1 - progress), 1.0
    end
    if now < (tonumber(runtime.fireFlashUntilMs) or 0) then return 1.0, 0.96, 0.72, 1.0 end
    if now < (tonumber(runtime.sightFlashUntilMs) or 0) then return 0.48, 1.0, 1.0, pulse end
    if state == "recovery" then return 0.42, 0.78, 1.0, pulse end
    return 0.70, 0.94, 1.0, pulse
end

local function segmentColor(segment, runtime, now, pulse)
    if segment[4] == "W" then return coreColor(runtime, now, pulse) end
    local color = PALETTE[segment[4]] or PALETTE.C
    return color[1], color[2], color[3], color[4]
end

local function drawSegments(renderer, texture, segments, cx, cy, runtime, now, pulse)
    for index = 1, #segments do
        local segment = segments[index]
        local red, green, blue, alpha = segmentColor(segment, runtime, now, pulse)
        for thickness = 0, (segment[5] or 1) - 1 do
            drawLine(renderer, texture, cx + segment[1], cy + segment[3] + thickness,
                cx + segment[2], cy + segment[3] + thickness, red, green, blue, alpha)
        end
    end
end

local function acquireParticle()
    local particle = particles[nextParticle]
    nextParticle = nextParticle % Visual.ParticleCap + 1
    return particle
end

local function configureParticle(particle, x, y, z, offsetX, offsetY, velocityX, velocityY, duration, color, size)
    particle.active = true
    particle.x, particle.y, particle.z = x, y, z
    particle.offsetX, particle.offsetY = offsetX or 0, offsetY or 0
    particle.velocityX, particle.velocityY = velocityX or 0, velocityY or 0
    particle.age = 0
    particle.duration = math.max(0.05, duration or 0.25)
    particle.color = color or "cyan"
    particle.size = size or 1
end

local function emitRadial(x, y, z, count, duration, color, speedMinimum, speedMaximum, inward)
    for _ = 1, count do
        local angle = randomBetween(0, math.pi * 2)
        local radius = inward and randomBetween(5, 9) or randomBetween(0, 2)
        local speed = randomBetween(speedMinimum, speedMaximum)
        local offsetX, offsetY = math.cos(angle) * radius, math.sin(angle) * radius
        local direction = inward and -1 or 1
        configureParticle(acquireParticle(), x, y, z, offsetX, offsetY,
            math.cos(angle) * speed * direction, math.sin(angle) * speed * direction,
            duration, color, 1)
    end
end

function Visual.reset()
    for index = 1, Visual.ParticleCap do particles[index].active = false end
    nextParticle = 1
end

function Visual.getLineTexture(now)
    if cachedTexture then return cachedTexture end
    now = tonumber(now) or nowMs()
    if now < nextTextureAttemptMs then return nil end
    nextTextureAttemptMs = now + TEXTURE_RETRY_MS
    cachedTexture = getTexture and getTexture("media/textures/mask_white.png") or nil
    return cachedTexture
end

function Visual.emit(kind, x, y, z)
    if x == nil or y == nil or z == nil then return end
    if kind == "trail" or kind == "catchup" then
        local count = kind == "catchup" and 2 or 1
        for _ = 1, count do
            configureParticle(acquireParticle(), x, y, z, randomBetween(-4, 4), randomBetween(7, 11),
                randomBetween(-5, 5), randomBetween(12, 24), kind == "catchup" and 0.36 or 0.28,
                kind == "catchup" and "white" or "cyan", 1)
        end
        return
    end
    if kind == "charge" then emitRadial(x, y, z, 1, 0.20, "red", 24, 38, true); return end
    if kind == "fire" then
        emitRadial(x, y, z, 3, 0.26, "red", 24, 46, false)
        emitRadial(x, y, z, 2, 0.22, "orange", 28, 52, false)
        return
    end
    if kind == "recall" then emitRadial(x, y, z, 8, 0.42, "cyan", 18, 34, false); return end
    if kind == "sight" then emitRadial(x, y, z, 8, 0.46, "cyan", 22, 40, false); return end
    if kind == "guardian" then emitRadial(x, y, z, 10, 0.50, "blue", 26, 48, false); return end
end

function Visual.update(delta)
    delta = math.max(0, tonumber(delta) or 0)
    for index = 1, Visual.ParticleCap do
        local particle = particles[index]
        if particle.active then
            particle.age = (particle.age or 0) + delta
            if particle.age >= particle.duration then
                particle.active = false
            else
                particle.offsetX = particle.offsetX + particle.velocityX * delta
                particle.offsetY = particle.offsetY + particle.velocityY * delta
            end
        end
    end
end

function Visual.renderRobot(renderer, texture, runtime, data)
    if not renderer or not texture or not runtime or not runtime.robotX or not data or not data.visible then return end
    local sx, sy, zoom = screenPoint(runtime.robotX, runtime.robotY, runtime.robotZ)
    if not sx or not sy or not zoom then return end
    local now = nowMs()
    local bob = math.sin(runtime.bobPhase or 0) * 3 / zoom
    local pulse = 0.88 + (math.sin((runtime.bobPhase or 0) * 0.75) + 1) * 0.06
    local direction = now < (runtime.attackFacingUntilMs or 0)
        and runtime.attackDirection or runtime.direction or "SE"
    local scale = zoom <= 0.60 and 2 or 1
    local cx = math.floor(sx + 0.5)
    local cy = math.floor(sy - 48 / zoom + bob + 0.5)
    if now < (runtime.recoilUntilMs or 0) then
        local vector = DIRECTION_VECTOR[direction] or DIRECTION_VECTOR.SE
        cx = cx - vector[1] * 2
        cy = cy - vector[2] * 2
    end
    drawSegments(renderer, texture, getBodySegments(direction, runtime.animationFrame, scale),
        cx, cy, runtime, now, pulse)
    if now < (runtime.guardianFlashUntilMs or 0) then
        drawSegments(renderer, texture, getGuardianSegments(scale), cx, cy, runtime, now, pulse)
    end
end

function Visual.renderParticles(renderer, texture)
    if not renderer or not texture then return end
    for index = 1, Visual.ParticleCap do
        local particle = particles[index]
        if particle.active then
            local sx, sy, zoom = screenPoint(particle.x, particle.y, particle.z)
            if sx and sy and zoom then
                local progress = math.max(0, math.min(1, particle.age / particle.duration))
                local alpha = 1 - progress
                local color = PARTICLE_COLORS[particle.color] or PARTICLE_COLORS.cyan
                local size = particle.size or 1
                drawLine(renderer, texture, sx + particle.offsetX, sy - 48 / zoom + particle.offsetY,
                    sx + particle.offsetX + size, sy - 48 / zoom + particle.offsetY,
                    color[1], color[2], color[3], alpha)
            end
        end
    end
end

return GodSystemCompanionVisual
