assert(loadstring(readFixture("terminal_fixture.lua")))()
assert(loadstring(readSource("shared/GodSystem_RangeFilter.lua")))()

ISComboBox = ISPanel:derive("ISComboBox")
function ISComboBox:new(x, y, width, height, target, callback)
    local box = ISPanel.new(self, x, y, width, height)
    box.options, box.selected = {}, 1
    return box
end
function ISComboBox:clear() self.options = {}; self.selected = 1 end
function ISComboBox:addOption(label) self.options[#self.options + 1] = label end
function ISComboBox:select(index) self.selected = index end
function ISComboBox:getOptionText(index) return self.options[index] end
ISCollapsableWindow.update = function() end
ISTextEntryBox.getInternalText = function(self) return self.text end

local time = 10000
GodSystemScheduler = { nowMs = function() return time end }
local syncGeometry = 0
gsSyncScrollingListGeometry = function() syncGeometry = syncGeometry + 1 end

local catalogListener, filterListener
local catalog = { rows = {}, complete = false }
for index = 1, 95 do
    catalog.rows[index] = {
        fullType = string.format("Base.Item%03d", index),
        label = string.format("Item %03d", index),
        moduleName = "Base", displayCategory = "Other",
    }
end
function catalog:queryFiltered(criteria, page, pageSize)
    local matching = {}
    for _, row in ipairs(self.rows) do
        local search = tostring(criteria.search or ""):lower()
        if criteria.membership(row) and (search == "" or row.fullType:lower():find(search, 1, true))
            and (criteria.moduleName == "" or criteria.moduleName == row.moduleName)
            and (criteria.displayCategory == "" or criteria.displayCategory == row.displayCategory) then
            matching[#matching + 1] = row
        end
    end
    local pages = math.max(1, math.ceil(#matching / pageSize))
    page = math.max(1, math.min(page, pages))
    local rows = {}
    for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #matching) do
        rows[#rows + 1] = matching[index]
    end
    return { rows = rows, page = page, pageCount = pages, total = #matching, complete = self.complete }
end
GodSystemItemCatalog.Shared = catalog
GodSystemItemCatalog.getShared = function() return catalog end
GodSystemItemCatalog.subscribe = function(callback)
    catalogListener = callback
    return function() catalogListener = nil end
end

local filter = { mode = "allowlist", activeFullTypes = {} }
GodSystemApp.services.rangeRecycle = {
    getViewModel = function() return { filter = filter, filterReady = true } end,
    subscribe = function(_, _, callback)
        filterListener = callback
        return function() filterListener = nil end
    end,
}
assert(loadstring(readSource("client/GodSystem_RangeFilterUI.lua")))()
local window = GodSystemRangeFilterWindow:new(40, 40, 730, 560)
window:initialise()
window:addToUIManager()
assert(#window.list.items == 40 and window.result.pageCount == 3)

local list = window.list
local function position(scroll, selected)
    assert(list:getYScroll() == scroll, "scroll position changed")
    assert(list.selected == selected, "selected row changed")
    assert(list.smoothScrollTargetY == nil and list.smoothScrollY == nil, "smooth scroll remained active")
end
list.selected = 20
list:setYScroll(-300)
list.smoothScrollTargetY, list.smoothScrollY = -900, -900
window:onListMouseDown(list.items[20])
assert(window.selected["Base.Item020"] == true)
position(-300, 20)
window:onListMouseDown(list.items[20])
assert(window.selected["Base.Item020"] == false)
position(-300, 20)
local bottom = -math.max(0, list:getScrollHeight() - list:getHeight())
list.selected = 40
list:setYScroll(bottom)
window:onListMouseDown(list.items[40])
assert(window.selected["Base.Item040"] == true)
position(bottom, 40)
window:onListMouseDown(list.items[40])
position(bottom, 40)
list.selected = 20
list:setYScroll(-300)

-- Catalog completion and a delayed multiplayer acknowledgement must retain the viewport.
catalog.complete = true
catalogListener(catalog)
time = time + window.CATALOG_REFRESH_MS + 1
window:update()
position(-300, 20)
filterListener({ topic = "filterSyncing" })
filterListener({ topic = "filterSyncQueued" })
filterListener({ topic = "filter" })
position(-300, 20)
filter.activeFullTypes = { "Base.Item020" }
filterListener({ topic = "filter" })
assert(window.result.total == 94 and list.items[list.selected].item.fullType == "Base.Item021",
    "multiplayer result change should retain the nearby selected row")
assert(list:getYScroll() == -300)
filter.activeFullTypes = {}
filterListener({ topic = "filter" })

window:onNextPage()
assert(window.page == 2 and list:getYScroll() == 0, "explicit page change starts at top")
list.selected = 15
list:setYScroll(-200)
filterListener({ topic = "filter" })
assert(window.page == 2)
position(-200, 15)

-- A shortened page clamps scroll, then an invalid page falls back to the last valid page.
for index = #catalog.rows, 45 + 1, -1 do table.remove(catalog.rows, index) end
filterListener({ topic = "filter" })
assert(window.page == 2 and #list.items == 5 and list:getYScroll() == 0)
for index = #catalog.rows, 25 + 1, -1 do table.remove(catalog.rows, index) end
filterListener({ topic = "filter" })
assert(window.page == 1 and #list.items == 25 and list:getYScroll() == 0)

list:setYScroll(-100)
window.searchBox.text = "Item02"
window:onSearchChanged(window.searchBox)
time = time + 181
window:update()
assert(window.page == 1 and list:getYScroll() == 0, "search change starts at top")
window:onPage(window.allowedButton)
assert(window.page == 1 and list:getYScroll() == 0, "tab change starts at top")
assert(syncGeometry > 0, "scrollbar geometry must be synchronized")
window:close()
assert(catalogListener == nil and filterListener == nil, "closed window left subscriptions behind")
print("range filter scroll regression passed")

do
    local Filter = GodSystemRangeFilter
    -- The bare Kahlua probe has no os library; the timing guard only really
    -- runs under Lua 5.1 (run_lua_tests.py).
    local clock = (os and os.clock) or function() return 0 end
    local function sorted(values)
        local copy = {}
        for i = 1, #values do copy[i] = values[i] end
        table.sort(copy)
        return copy
    end
    local function assertArray(actual, expected)
        assert(#actual == #expected, "length " .. #actual .. " ~= " .. #expected)
        for i = 1, #expected do
            assert(actual[i] == expected[i], "index " .. i .. ": " .. tostring(actual[i]) .. " ~= " .. tostring(expected[i]))
        end
    end

    -- addMany merges in sorted order with deduplication.
    local base = Filter.normalize({ mode = "denylist", revision = 3, activeFullTypes = sorted { "Base.A", "Base.C", "Base.E" } })
    local r = Filter.applyDelta(base, { baseRevision = 3, op = "addMany", fullTypes = sorted { "Base.B", "Base.D", "Base.F", "Base.A" } })
    assert(r.ok and r.code == "RangeFilterUpdated", r.code)
    assertArray(r.state.activeFullTypes, { "Base.A", "Base.B", "Base.C", "Base.D", "Base.E", "Base.F" })
    assert(r.state.revision == 4)

    -- removeMany preserves order; single add/remove and unchanged deltas work.
    r = Filter.applyDelta(r.state, { baseRevision = 4, op = "removeMany", fullTypes = { "Base.B", "Base.E" } })
    assertArray(r.state.activeFullTypes, { "Base.A", "Base.C", "Base.D", "Base.F" })
    r = Filter.applyDelta(r.state, { baseRevision = 5, op = "remove", fullType = "Base.A" })
    assertArray(r.state.activeFullTypes, { "Base.C", "Base.D", "Base.F" })
    r = Filter.applyDelta(r.state, { baseRevision = 6, op = "add", fullType = "Base.Z" })
    assertArray(r.state.activeFullTypes, { "Base.C", "Base.D", "Base.F", "Base.Z" })
    r = Filter.applyDelta(r.state, { baseRevision = 7, op = "add", fullType = "Base.Z" })
    assert(r.code == "RangeFilterUnchanged" and #r.state.activeFullTypes == 4)

    -- Trust boundary: a marker produced by the module fast-paths validation,
    -- while a network-originated table (allowTrusted=false) is fully rechecked.
    local marked = Filter.normalize({ mode = "denylist", activeFullTypes = { "Base.A" } })
    marked.activeFullTypes[#marked.activeFullTypes + 1] = "Bad Type"
    local trusted = Filter.normalize(marked)
    assert(#trusted.activeFullTypes == 2 and trusted.activeFullTypes[2] == "Bad Type")
    local untrusted = Filter.normalize(marked, false)
    assert(#untrusted.activeFullTypes == 0, "bad network entry must fail closed")
    assert(untrusted.__godSystemFilterTrusted == true)

    -- Performance guard: deltas on a large filter must not re-validate or
    -- re-sort all N existing entries.
    local many = {}
    for i = 1, 10000 do many[i] = string.format("Base.M%05d", i) end
    local big = Filter.normalize({ mode = "denylist", activeFullTypes = many })
    local started = clock()
    r = Filter.applyDelta(big, { baseRevision = big.revision, op = "addMany", fullTypes = { "Base.ZzzNew" } })
    assert(clock() - started < 0.2, "large addMany too slow")
    assert(#r.state.activeFullTypes == 10001)
    assert(r.state.activeFullTypes[1] == "Base.M00001")
    assert(r.state.activeFullTypes[10001] == "Base.ZzzNew")
    started = clock()
    r = Filter.applyDelta(r.state, { baseRevision = r.state.revision, op = "removeMany", fullTypes = { "Base.M05000" } })
    assert(clock() - started < 0.2, "large removeMany too slow")
    assert(#r.state.activeFullTypes == 10000)
    print("range filter delta merge and trust regression passed")
end
