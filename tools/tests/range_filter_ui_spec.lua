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
