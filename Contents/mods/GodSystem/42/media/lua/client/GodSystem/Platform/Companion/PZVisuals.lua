require "GodSystem_CompanionVisual"

GodSystemCompanionPZVisualsPlatform = GodSystemCompanionPZVisualsPlatform or {}

local Descriptor = GodSystemCompanionPZVisualsPlatform

Descriptor.id = "companion.visuals"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local RED_BEAM_OUTER = { 0.86, 0.04, 0.02, 0.55 }
local RED_BEAM_CORE = { 1.00, 0.72, 0.45, 0.98 }
local CYAN = { 0.20, 0.92, 1.00, 0.92 }
local MARK = { 1.00, 0.76, 0.12, 0.88 }

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function readPosition(target)
    if not target then return nil end
    local x = type(target.getX) == "function" and target:getX() or target.x
    local y = type(target.getY) == "function" and target:getY() or target.y
    local z = type(target.getZ) == "function" and target:getZ() or target.z
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

function Descriptor.create(_, context)
    context = context or {}
    local binding = type(context.binding) == "table" and context.binding or {}
    local visual = binding.visual or GodSystemCompanionVisual
    local instance = {
        started = false,
        texture = nil,
        emitted = 0,
        rendered = 0,
        updated = 0,
        resets = 0,
        failures = 0,
        lastIssue = nil,
        lastRenderMs = nil,
    }

    local function fail(code, stage)
        instance.failures = instance.failures + 1
        instance.lastIssue = { code = code, stage = stage }
        return false, code
    end

    local function nowMs()
        if type(binding.nowMs) == "function" then return tonumber(binding.nowMs()) or 0 end
        if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
        return 0
    end

    local function renderer()
        if type(binding.renderer) == "function" then return binding.renderer() end
        if type(getRenderer) == "function" then return getRenderer() end
        return nil
    end

    local function zoom()
        if type(binding.zoom) == "function" then return tonumber(binding.zoom()) end
        local core = type(getCore) == "function" and getCore() or nil
        if core and type(core.getZoom) == "function" then return tonumber(core:getZoom(0)) end
        return nil
    end

    local function screenPoint(x, y, z)
        local sx, sy
        if type(binding.toScreen) == "function" then
            sx, sy = binding.toScreen(x, y, z)
        elseif ISCoordConversion and type(ISCoordConversion.ToScreen) == "function" then
            sx, sy = ISCoordConversion.ToScreen(x, y, z)
        end
        local scale = zoom()
        if not finite(sx) or not finite(sy) or not finite(scale) or scale <= 0 then return nil end
        return tonumber(sx) / scale, tonumber(sy) / scale, scale
    end

    local function line(targetRenderer, x1, y1, x2, y2, color)
        targetRenderer:renderline(instance.texture,
            math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2),
            color[1], color[2], color[3], color[4])
    end

    local function cornerBox(targetRenderer, target, color)
        local position = readPosition(target)
        if not position then return false end
        local sx, sy, scale = screenPoint(position.x, position.y, position.z)
        if not sx then return false end
        local halfWidth, halfHeight, arm = 18 / scale, 38 / scale, 8 / scale
        sy = sy - 38 / scale
        local left, right = sx - halfWidth, sx + halfWidth
        local top, bottom = sy - halfHeight, sy + halfHeight
        line(targetRenderer, left, top, left + arm, top, color)
        line(targetRenderer, left, top, left, top + arm, color)
        line(targetRenderer, right, top, right - arm, top, color)
        line(targetRenderer, right, top, right, top + arm, color)
        line(targetRenderer, left, bottom, left + arm, bottom, color)
        line(targetRenderer, left, bottom, left, bottom - arm, color)
        line(targetRenderer, right, bottom, right - arm, bottom, color)
        line(targetRenderer, right, bottom, right, bottom - arm, color)
        return true
    end

    local function ring(targetRenderer, sx, sy, radius, color)
        local previousX, previousY = sx + radius, sy
        for index = 1, 12 do
            local angle = math.pi * 2 * index / 12
            local nextX = sx + math.cos(angle) * radius
            local nextY = sy + math.sin(angle) * radius * 0.55
            line(targetRenderer, previousX, previousY, nextX, nextY, color)
            previousX, previousY = nextX, nextY
        end
    end

    local function effectVisual(targetRenderer, entry, now)
        if type(entry) ~= "table" then return false end
        local source = readPosition(entry.source)
        if not source then return false end
        local sx, sy, scale = screenPoint(source.x, source.y, source.z)
        if not sx then return false end
        local duration = math.max(1, (tonumber(entry.expiresAt) or now)
            - (tonumber(entry.createdAt) or now))
        local progress = math.max(0, math.min(1,
            (now - (tonumber(entry.createdAt) or now)) / duration))
        local alpha = math.max(0.08, 1 - progress)
        sy = sy - ((entry.kind == "guardian" and 12 or 38) / scale)
        if entry.kind == "chain" then
            local target = readPosition(entry.target)
            if not target then return false end
            local tx, ty, targetScale = screenPoint(target.x, target.y, target.z)
            if not tx then return false end
            ty = ty - 38 / targetScale
            line(targetRenderer, sx, sy, tx, ty, { 0.20, 0.92, 1.00, alpha })
            line(targetRenderer, sx + 1, sy, tx + 1, ty, { 0.72, 1.00, 1.00, alpha * 0.8 })
            return true
        end
        if entry.kind == "guardian" then
            local radius = (14 + progress * 42) / scale
            ring(targetRenderer, sx, sy, radius, { 0.42, 0.86, 1.00, alpha })
            ring(targetRenderer, sx, sy, math.max(2, radius - 2 / scale),
                { 0.82, 0.96, 1.00, alpha * 0.72 })
            return true
        end
        if entry.kind == "blast" then
            local radius = (12 + progress * 30) / scale
            ring(targetRenderer, sx, sy, radius, { 1.00, 0.12, 0.04, alpha })
            ring(targetRenderer, sx, sy, math.max(2, radius - 2 / scale),
                { 1.00, 0.52, 0.12, alpha * 0.70 })
            return true
        end
        local radius = (7 + progress * 8) / scale
        local color = entry.kind == "corrosion"
            and { 1.00, 0.28, 0.04, alpha } or { 0.35, 0.88, 1.00, alpha }
        line(targetRenderer, sx, sy - radius, sx + radius, sy, color)
        line(targetRenderer, sx + radius, sy, sx, sy + radius, color)
        line(targetRenderer, sx, sy + radius, sx - radius, sy, color)
        line(targetRenderer, sx - radius, sy, sx, sy - radius, color)
        return true
    end

    local function projectile(targetRenderer, entry)
        if type(entry) ~= "table" then return false end
        local target = readPosition(entry.target)
        if not target or not finite(entry.startX) or not finite(entry.startY)
            or not finite(entry.startZ)
        then
            return false
        end
        local sx, sy, sourceScale = screenPoint(entry.startX, entry.startY, entry.startZ)
        local tx, ty, targetScale = screenPoint(target.x, target.y, target.z)
        if not sx or not tx then return false end
        sy, ty = sy - 48 / sourceScale, ty - 38 / targetScale
        local progress = math.max(0, math.min(1,
            (tonumber(entry.elapsed) or 0) / math.max(0.01, tonumber(entry.duration) or 0.35)))
        local currentX, currentY = sx + (tx - sx) * progress, sy + (ty - sy) * progress
        local dx, dy = tx - sx, ty - sy
        local length = math.sqrt(dx * dx + dy * dy)
        if length <= 0.01 then return false end
        local beamLength = math.min(30, length)
        local tailX = currentX - dx / length * beamLength
        local tailY = currentY - dy / length * beamLength
        for offset = -1, 1 do
            line(targetRenderer, tailX, tailY + offset, currentX, currentY + offset, RED_BEAM_OUTER)
        end
        line(targetRenderer, tailX, tailY, currentX, currentY, RED_BEAM_CORE)
        return true
    end

    local function update(delta)
        if not instance.started then return fail("visualStopped", "update") end
        if type(visual.update) ~= "function" then return fail("visualUpdateMissing", "update") end
        visual.update(math.max(0, math.min(0.25, tonumber(delta) or 0)))
        instance.updated = instance.updated + 1
        return true
    end

    local function emit(kind, runtime)
        if not instance.started then return fail("visualStopped", "emit") end
        if type(visual.emit) ~= "function" then return fail("visualEmitMissing", "emit") end
        if type(runtime) ~= "table" or not finite(runtime.robotX)
            or not finite(runtime.robotY) or not finite(runtime.robotZ)
        then
            return fail("robotPositionMissing", "emit")
        end
        visual.emit(tostring(kind or ""), runtime.robotX, runtime.robotY, runtime.robotZ)
        instance.emitted = instance.emitted + 1
        return true
    end

    local function reset()
        if type(visual.reset) ~= "function" then return fail("visualResetMissing", "reset") end
        visual.reset()
        instance.lastRenderMs = nil
        instance.resets = instance.resets + 1
        return true
    end

    local function render(runtime, data)
        if not instance.started then return fail("visualStopped", "render") end
        local targetRenderer = renderer()
        if not targetRenderer or type(targetRenderer.renderline) ~= "function" then
            return fail("rendererMissing", "render")
        end
        if not instance.texture then return fail("textureMissing", "render") end
        local now = nowMs()
        local previous = instance.lastRenderMs or now
        instance.lastRenderMs = now
        update((now - previous) / 1000)
        if type(data) ~= "table" or data.visible ~= true
            or type(runtime) ~= "table" or runtime.vehicleSuspended == true
        then
            return true
        end
        if type(visual.renderRobot) ~= "function" or type(visual.renderParticles) ~= "function" then
            return fail("visualRendererMissing", "render")
        end
        visual.renderRobot(targetRenderer, instance.texture, runtime, data)
        for index = 1, #(runtime.sightTargets or {}) do
            cornerBox(targetRenderer, runtime.sightTargets[index].target, CYAN)
        end
        for target, expiresAt in pairs(runtime.markStates or {}) do
            if now < (tonumber(expiresAt) or 0) then cornerBox(targetRenderer, target, MARK) end
        end
        for index = 1, #(runtime.projectiles or {}) do
            projectile(targetRenderer, runtime.projectiles[index])
        end
        for index = 1, #(runtime.effectVisuals or {}) do
            effectVisual(targetRenderer, runtime.effectVisuals[index], now)
        end
        visual.renderParticles(targetRenderer, instance.texture)
        instance.rendered = instance.rendered + 1
        return true
    end

    instance.public = {
        emit = emit,
        reset = reset,
        update = update,
        render = render,
    }

    function instance:start()
        if type(visual) ~= "table" then return fail("visualModuleMissing", "start") end
        if type(visual.getLineTexture) ~= "function" then
            return fail("textureLoaderMissing", "start")
        end
        local texture = visual.getLineTexture(nowMs())
        if not texture then return fail("textureMissing", "start") end
        self.texture = texture
        self.lastIssue = nil
        self.started = true
        return true
    end

    function instance:stop()
        if type(visual) == "table" and type(visual.reset) == "function" then visual.reset() end
        self.resets = self.resets + 1
        self.texture = nil
        self.lastRenderMs = nil
        self.started = false
        return true
    end

    function instance:health()
        return {
            ok = self.started and self.failures == 0,
            code = self.lastIssue and self.lastIssue.code or (self.started and "healthy" or "stopped"),
            data = {
                emitted = self.emitted,
                rendered = self.rendered,
                updated = self.updated,
                resets = self.resets,
                failures = self.failures,
                lastIssue = self.lastIssue,
            },
            moduleId = Descriptor.id,
        }
    end

    return instance
end

return Descriptor
