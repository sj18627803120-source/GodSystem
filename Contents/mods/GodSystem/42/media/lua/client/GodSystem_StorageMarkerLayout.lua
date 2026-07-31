GodSystemStorageMarkerLayout = GodSystemStorageMarkerLayout or {}

local Layout = GodSystemStorageMarkerLayout

function Layout.number(value)
    return math.max(1, math.floor(tonumber(value) or 1))
end

function Layout.position(baseX, baseY, number, verticalStep)
    local step = math.max(1, tonumber(verticalStep) or 1)
    return baseX, baseY - ((Layout.number(number) - 1) * step)
end

return Layout
