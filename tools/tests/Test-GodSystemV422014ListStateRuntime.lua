local scheduledTick = nil

Events = {
    OnTick = {
        Add = function(callback) scheduledTick = callback end,
        Remove = function(callback)
            if scheduledTick == callback then scheduledTick = nil end
        end,
    },
}

dofile(arg[1])

local function list(rows, selected, yScroll, height)
    local value = {
        items = rows,
        selected = selected or 0,
        yScroll = yScroll or 0,
        height = height or 100,
        itemheight = 20,
    }
    function value:getYScroll() return self.yScroll end
    function value:setYScroll(nextValue) self.yScroll = nextValue end
    function value:getScrollHeight()
        local total = 0
        for i = 1, #self.items do total = total + (self.items[i].height or self.itemheight) end
        return total
    end
    return value
end

local function row(key, height)
    return { item = { key = key }, height = height or 20 }
end

local function keyOf(payload)
    return payload and payload.key or nil
end

local original = list({ row("a"), row("b"), row("c"), row("d"), row("e"), row("f"), row("g"), row("h"), row("i"), row("j") }, 6, -80)
local state = GodSystemListState.capture(original, "shop|all", keyOf)
assert(state.selectedKey == "f", "capture must retain the stable selected key")
assert(state.selectedIndex == 6, "capture must retain the selected row index")
assert(state.scrollY == -80, "capture must retain scroll position")

local rebuilt = list({ row("a"), row("b"), row("c"), row("d"), row("e"), row("f"), row("g"), row("h"), row("i"), row("j") }, 0, 0)
assert(GodSystemListState.restore(rebuilt, state, "shop|all", keyOf) == true, "same context must restore")
assert(rebuilt.selected == 6 and rebuilt.yScroll == -80, "stable selection and scroll must be restored")

local changedContext = list({ row("a"), row("b"), row("c") }, 0, 0)
assert(GodSystemListState.restore(changedContext, state, "shop|weapons", keyOf) == false, "different context must not restore")
assert(changedContext.selected == 0 and changedContext.yScroll == 0, "different context must keep its fresh state")

local deleted = list({ row("a"), row("b"), row("c"), row("d"), row("e"), row("g"), row("h") }, 0, 0)
assert(GodSystemListState.restore(deleted, state, "shop|all", keyOf) == true, "row deletion must still restore the list context")
assert(deleted.selected == 6, "missing selection must choose the nearest valid row")

local short = list({ row("a"), row("b"), row("c"), row("d"), row("e"), row("f"), row("g"), row("h") }, 0, 0, 100)
state.scrollY = -900
assert(GodSystemListState.restore(short, state, "shop|all", keyOf) == true, "short list restore must succeed")
assert(short.yScroll == -60, "restored scroll must clamp to the new list range")

local deferred = list({ row("a"), row("b"), row("c"), row("d"), row("e"), row("f"), row("g"), row("h"), row("i"), row("j") }, 0, 0)
assert(GodSystemListState.restoreNextTick(deferred, state, "shop|all", keyOf) == true, "next-tick restore must be queued")
assert(scheduledTick ~= nil, "next-tick restore must register OnTick once")
deferred.yScroll = 0
scheduledTick()
assert(deferred.yScroll == -100, "next-tick restore must clamp and restore once")
assert(scheduledTick == nil, "next-tick restore must unregister after one pass")

print("Test-GodSystemV422014ListStateRuntime passed")
