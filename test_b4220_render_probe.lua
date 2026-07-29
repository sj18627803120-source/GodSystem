-- GodSystem B42.20 渲染接口最小探针
-- 用法：放入 Mod 的 media/lua/client/ 目录，或通过 --load-lua 加载
-- 不依赖任何 GodSystem 存档数据，仅测试事件和绘制 API

local PROBE = {}

-- 每个事件只触发一次
PROBE.fired = {}
PROBE.texture = nil
PROBE.textureAttempted = false

local function once(name)
    if PROBE.fired[name] then return false end
    PROBE.fired[name] = true
    return true
end

-- 安全打印
local function probeLog(msg)
    if print then print("[B42.20_PROBE] " .. tostring(msg)) end
end

-- 安全获取纹理
local function safeTexture()
    if PROBE.texture then return PROBE.texture end
    if PROBE.textureAttempted then return nil end
    PROBE.textureAttempted = true
    if getTexture then
        PROBE.texture = getTexture("media/textures/mask_white.png")
        if PROBE.texture then
            probeLog("mask_white.png: TEXTURE_OK")
        else
            probeLog("mask_white.png: TEXTURE_NIL")
        end
    else
        probeLog("getTexture: FUNCTION_NOT_FOUND")
    end
    return PROBE.texture
end

-- 安全获取渲染器
local function safeRenderer()
    if getRenderer then
        local r = getRenderer()
        if r then return r end
    end
    return nil
end

-- 世界坐标转屏幕
local function safeToScreen(x, y, z)
    if ISCoordConversion and ISCoordConversion.ToScreen then
        return ISCoordConversion.ToScreen(x, y, z)
    end
    return nil, nil
end

-- 绘制测试线
local function drawTestLine(renderer, texture, x1, y1, x2, y2, r, g, b, a)
    if not renderer or not texture then return false end
    local ok, err = pcall(function()
        -- 尝试 renderline（旧 API）
        if renderer.renderline then
            renderer:renderline(texture, math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), r, g, b, a)
            return true
        end
    end)
    if ok then return true end
    -- 尝试 renderRect 作为替代
    ok, err = pcall(function()
        if renderer.renderRect then
            renderer:renderRect(math.floor(x1), math.floor(y1), 2, 2, r, g, b, a)
        end
    end)
    return ok
end

-- ============ OnPreUIDraw ============
local function onPreUIDraw()
    if not once("OnPreUIDraw") then return end
    probeLog("OnPreUIDraw: FIRED")
    local renderer = safeRenderer()
    probeLog("OnPreUIDraw: renderer=" .. tostring(renderer ~= nil))
    local tex = safeTexture()
    probeLog("OnPreUIDraw: texture=" .. tostring(tex ~= nil))
    if renderer and tex then
        drawTestLine(renderer, tex, 100, 100, 300, 100, 1.0, 1.0, 1.0, 1.0)
        probeLog("OnPreUIDraw: line_drawn")
    end
    -- 世界坐标测试
    if isIngameState and isIngameState() then
        local player = getPlayer and getPlayer()
        if player then
            local sx, sy = safeToScreen(player:getX(), player:getY(), player:getZ())
            probeLog("OnPreUIDraw: world_to_screen=(" .. tostring(sx) .. "," .. tostring(sy) .. ")")
        end
    end
end

-- ============ OnPostUIDraw ============
local function onPostUIDraw()
    if not once("OnPostUIDraw") then return end
    probeLog("OnPostUIDraw: FIRED")
    local renderer = safeRenderer()
    probeLog("OnPostUIDraw: renderer=" .. tostring(renderer ~= nil))
    local tex = safeTexture()
    if renderer and tex then
        drawTestLine(renderer, tex, 100, 120, 300, 120, 1.0, 1.0, 0.0, 1.0)
        probeLog("OnPostUIDraw: line_drawn")
    end
end

-- ============ OnRenderTick ============
local function onRenderTick()
    if not once("OnRenderTick") then return end
    probeLog("OnRenderTick: FIRED")
    local renderer = safeRenderer()
    probeLog("OnRenderTick: renderer=" .. tostring(renderer ~= nil))
    local tex = safeTexture()
    if renderer and tex then
        drawTestLine(renderer, tex, 100, 140, 300, 140, 0.0, 1.0, 1.0, 1.0)
        probeLog("OnRenderTick: line_drawn")
    end
    -- 检查 renderline 方法是否存在
    if renderer then
        probeLog("OnRenderTick: renderer.renderline=" .. tostring(renderer.renderline ~= nil))
        probeLog("OnRenderTick: renderer.renderRect=" .. tostring(renderer.renderRect ~= nil))
        probeLog("OnRenderTick: renderer.render=" .. tostring(renderer.render ~= nil))
        probeLog("OnRenderTick: renderer.renderPoly=" .. tostring(renderer.renderPoly ~= nil))
    end
end

-- ============ OnRenderUpdate ============
local function onRenderUpdate()
    if not once("OnRenderUpdate") then return end
    probeLog("OnRenderUpdate: FIRED")
end

-- ============ OnPostRender ============
local function onPostRender()
    if not once("OnPostRender") then return end
    probeLog("OnPostRender: FIRED")
    local renderer = safeRenderer()
    probeLog("OnPostRender: renderer=" .. tostring(renderer ~= nil))
end

-- ============ OnPostFloorSquareDraw ============
local function onPostFloorSquareDraw(square)
    if not once("OnPostFloorSquareDraw") then return end
    probeLog("OnPostFloorSquareDraw: FIRED, square=" .. tostring(square ~= nil))
end

-- ============ OnPostFloorLayerDraw ============
local function onPostFloorLayerDraw(z)
    if not once("OnPostFloorLayerDraw") then return end
    probeLog("OnPostFloorLayerDraw: FIRED, z=" .. tostring(z))
end

-- ============ OnGameStart（环境检查）============
local function onGameStart()
    probeLog("OnGameStart: checking environment")
    probeLog("getRenderer=" .. tostring(getRenderer ~= nil))
    probeLog("getTexture=" .. tostring(getTexture ~= nil))
    probeLog("ISCoordConversion=" .. tostring(ISCoordConversion ~= nil))
    if ISCoordConversion then
        probeLog("ISCoordConversion.ToScreen=" .. tostring(ISCoordConversion.ToScreen ~= nil))
        probeLog("ISCoordConversion.ToWorld=" .. tostring(ISCoordConversion.ToWorld ~= nil))
    end
    probeLog("Events.OnPreUIDraw=" .. tostring(Events.OnPreUIDraw ~= nil))
    probeLog("Events.OnPostUIDraw=" .. tostring(Events.OnPostUIDraw ~= nil))
    probeLog("Events.OnRenderTick=" .. tostring(Events.OnRenderTick ~= nil))
    probeLog("Events.OnRenderUpdate=" .. tostring(Events.OnRenderUpdate ~= nil))
    probeLog("Events.OnPostRender=" .. tostring(Events.OnPostRender ~= nil))
    probeLog("Events.OnPostFloorSquareDraw=" .. tostring(Events.OnPostFloorSquareDraw ~= nil))
    probeLog("Events.OnPostFloorLayerDraw=" .. tostring(Events.OnPostFloorLayerDraw ~= nil))
end

-- ============ 注册所有事件 ============
if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
if Events.OnPreUIDraw then Events.OnPreUIDraw.Add(onPreUIDraw) end
if Events.OnPostUIDraw then Events.OnPostUIDraw.Add(onPostUIDraw) end
if Events.OnRenderTick then Events.OnRenderTick.Add(onRenderTick) end
if Events.OnRenderUpdate then Events.OnRenderUpdate.Add(onRenderUpdate) end
if Events.OnPostRender then Events.OnPostRender.Add(onPostRender) end
if Events.OnPostFloorSquareDraw then Events.OnPostFloorSquareDraw.Add(onPostFloorSquareDraw) end
if Events.OnPostFloorLayerDraw then Events.OnPostFloorLayerDraw.Add(onPostFloorLayerDraw) end

probeLog("Probe registered: " ..
    "OnPreUIDraw=" .. tostring(Events.OnPreUIDraw ~= nil) .. "," ..
    "OnPostUIDraw=" .. tostring(Events.OnPostUIDraw ~= nil) .. "," ..
    "OnRenderTick=" .. tostring(Events.OnRenderTick ~= nil) .. "," ..
    "OnRenderUpdate=" .. tostring(Events.OnRenderUpdate ~= nil) .. "," ..
    "OnPostRender=" .. tostring(Events.OnPostRender ~= nil) .. "," ..
    "OnPostFloorSquareDraw=" .. tostring(Events.OnPostFloorSquareDraw ~= nil) .. "," ..
    "OnPostFloorLayerDraw=" .. tostring(Events.OnPostFloorLayerDraw ~= nil))

return PROBE