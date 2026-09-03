GodSystemListState = GodSystemListState or {}

local ListState = GodSystemListState
local pendingRestores = {}
local tickInstalled = false

local function number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    return value
end

local function readScroll(list)
    if not list or not list.getYScroll then return 0 end
    local ok, value = pcall(function() return list:getYScroll() end)
    return ok and number(value, 0) or 0
end

local function readHeight(list)
    if not list then return 0 end
    if list.getHeight then
        local ok, value = pcall(function() return list:getHeight() end)
        if ok then return math.max(0, number(value, 0)) end
    end
    return math.max(0, number(list.height, 0))
end

local function readScrollHeight(list)
    if not list then return 0 end
    if list.getScrollHeight then
        local ok, value = pcall(function() return list:getScrollHeight() end)
        if ok then return math.max(0, number(value, 0)) end
    end
    local total = 0
    for i = 1, #(list.items or {}) do
        total = total + math.max(0, number(list.items[i] and list.items[i].height, number(list.itemheight, 0)))
    end
    return total
end

local function keyFor(list, index, keyOf)
    local row = list and list.items and list.items[index] or nil
    if not row or not keyOf then return nil end
    local ok, value = pcall(keyOf, row.item or row, row, index, list)
    if not ok or value == nil then return nil end
    value = tostring(value)
    return value ~= "" and value or nil
end

local function isSelectable(list, index, keyOf, options)
    local row = list and list.items and list.items[index] or nil
    if not row then return false end
    if options and options.isSelectable then
        local ok, value = pcall(options.isSelectable, row.item or row, row, index, list)
        return ok and value == true
    end
    return keyFor(list, index, keyOf) ~= nil
end

local function clampScroll(list, value)
    local maximum = math.max(0, readScrollHeight(list) - readHeight(list))
    value = math.min(0, math.max(-maximum, number(value, 0)))
    if list and list.setYScroll then list:setYScroll(value) end
    if list then
        list.smoothScrollTargetY = nil
        list.smoothScrollY = nil
    end
    return value
end

local function nearestSelectable(list, index, keyOf, options)
    local count = #(list and list.items or {})
    if count <= 0 then return 0 end
    index = math.max(1, math.min(count, math.floor(number(index, 1))))
    if isSelectable(list, index, keyOf, options) then return index end
    for distance = 1, count do
        local after = index + distance
        if after <= count and isSelectable(list, after, keyOf, options) then return after end
        local before = index - distance
        if before >= 1 and isSelectable(list, before, keyOf, options) then return before end
    end
    return 0
end

function GodSystemListState.capture(list, context, keyOf)
    local selectedIndex = math.floor(number(list and list.selected, 0))
    return {
        context = tostring(context or ""),
        selectedKey = keyFor(list, selectedIndex, keyOf),
        selectedIndex = selectedIndex,
        scrollY = readScroll(list),
    }
end

function GodSystemListState.restore(list, state, context, keyOf, options)
    if not list or type(state) ~= "table" then return false end
    if tostring(state.context or "") ~= tostring(context or "") then return false end

    local selectedIndex = 0
    local wantedKey = state.selectedKey and tostring(state.selectedKey) or nil
    if wantedKey then
        for i = 1, #(list.items or {}) do
            if keyFor(list, i, keyOf) == wantedKey and isSelectable(list, i, keyOf, options) then
                selectedIndex = i
                break
            end
        end
    end
    if selectedIndex == 0 and number(state.selectedIndex, 0) > 0 then
        selectedIndex = nearestSelectable(list, state.selectedIndex, keyOf, options)
    end
    list.selected = selectedIndex
    clampScroll(list, state.scrollY)
    return true
end

function GodSystemListState.onTick()
    if Events and Events.OnTick and tickInstalled then
        Events.OnTick.Remove(ListState.onTick)
        tickInstalled = false
    end
    local queued = pendingRestores
    pendingRestores = {}
    for i = 1, #queued do
        local entry = queued[i]
        ListState.restore(entry.list, entry.state, entry.context, entry.keyOf, entry.options)
    end
end

function GodSystemListState.restoreNextTick(list, state, context, keyOf, options)
    if not list or type(state) ~= "table" then return false end
    if tostring(state.context or "") ~= tostring(context or "") then return false end
    pendingRestores[#pendingRestores + 1] = {
        list = list,
        state = state,
        context = context,
        keyOf = keyOf,
        options = options,
    }
    if Events and Events.OnTick and not tickInstalled then
        Events.OnTick.Remove(ListState.onTick)
        Events.OnTick.Add(ListState.onTick)
        tickInstalled = true
    end
    return true
end

return ListState
