GodSystemFloatingButtonLifecycle = GodSystemFloatingButtonLifecycle or {}

local Lifecycle = GodSystemFloatingButtonLifecycle

function Lifecycle.isValid(button)
    return button ~= nil
        and type(button.addToUIManager) == "function"
        and type(button.setVisible) == "function"
        and type(button.setX) == "function"
        and type(button.setY) == "function"
        and tonumber(button.width) and tonumber(button.width) > 0
        and tonumber(button.height) and tonumber(button.height) > 0
end

function Lifecycle.clampPosition(x, y, width, height, screenWidth, screenHeight)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    width = math.max(1, tonumber(width) or 1)
    height = math.max(1, tonumber(height) or 1)
    screenWidth = math.max(0, tonumber(screenWidth) or 0)
    screenHeight = math.max(0, tonumber(screenHeight) or 0)

    if screenWidth > 0 then
        if x + width <= 0 then x = 0 end
        if x >= screenWidth then x = math.max(0, screenWidth - width) end
    end
    if screenHeight > 0 then
        if y + height <= 0 then y = 0 end
        if y >= screenHeight then y = math.max(0, screenHeight - height) end
    end
    return math.floor(x), math.floor(y)
end

function Lifecycle.ensure(button, createButton, x, y, width, height, screenWidth, screenHeight)
    local recreated = false
    if not Lifecycle.isValid(button) then
        button = createButton(x, y, width, height)
        recreated = true
    end
    if not Lifecycle.isValid(button) then return nil, recreated, false end

    local nextX, nextY = Lifecycle.clampPosition(button.x, button.y, button.width, button.height, screenWidth, screenHeight)
    local moved = nextX ~= button.x or nextY ~= button.y
    if moved then
        button:setX(nextX)
        button:setY(nextY)
    end
    button:addToUIManager()
    button:setVisible(true)
    return button, recreated, moved
end

return Lifecycle
