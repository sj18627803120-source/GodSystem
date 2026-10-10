GodSystemItemCatalog = GodSystemItemCatalog or {}
require "GodSystem_Pinyin"

local Catalog = {}
Catalog.__index = Catalog
local listeners = {}
local persistentListeners = {}
local function clockMs()
    if getTimestampMs then return getTimestampMs() end
    return os and os.clock and os.clock()*1000 or 0
end
local function languageToken()
    if Translator and Translator.getLanguage then return tostring(Translator.getLanguage()) end
    return "default"
end

local function rowLess(a, b)
    local left, right = a.sortLabel or tostring(a.label):lower(), b.sortLabel or tostring(b.label):lower()
    if left == right then return tostring(a.key) < tostring(b.key) end
    return left < right
end

local function beginSort(self)
    self.sorting = { phase = "runs", cursor = 1, width = 64, output = {} }
end

local function sortStep(self, started)
    started = started or clockMs()
    local state, rows = self.sorting, self.rows
    if not state then beginSort(self); state = self.sorting end
    local total = #rows
    if state.phase == "runs" then
        local first = state.cursor
        if first <= total then
            local last = math.min(total, first + 63)
            local chunk = {}
            for index = first, last do chunk[#chunk + 1] = rows[index] end
            table.sort(chunk, rowLess)
            for index = first, last do rows[index] = chunk[index - first + 1] end
            state.cursor = last + 1
        end
        if state.cursor > total then
            state.phase, state.cursor, state.left, state.right = "merge", 1, 1, 65
        end
        return false
    end
    if state.width >= total then self.sorting = nil; self.complete = true; return true end
    local handled = 0
    while handled < 128 and state.cursor <= total and (handled == 0 or clockMs()-started < 2) do
        local start = math.floor((state.cursor - 1) / (state.width * 2)) * (state.width * 2) + 1
        local middle = math.min(total, start + state.width - 1)
        local finish = math.min(total, start + state.width * 2 - 1)
        if state.start ~= start then
            state.start, state.left, state.right = start, start, middle + 1
        end
        local takeLeft = state.left <= middle
            and (state.right > finish or rowLess(rows[state.left], rows[state.right]))
        if takeLeft then
            state.output[state.cursor] = rows[state.left]
            state.left = state.left + 1
        else
            state.output[state.cursor] = rows[state.right]
            state.right = state.right + 1
        end
        state.cursor, handled = state.cursor + 1, handled + 1
    end
    if state.cursor > total then
        self.rows, state.output = state.output, rows
        state.output, state.width, state.cursor, state.start = {}, state.width * 2, 1, nil
        if state.width >= total then self.sorting = nil; self.complete = true; return true end
    end
    return false
end

function GodSystemItemCatalog.new(provider)
    assert(type(provider) == "table", "item catalog provider is required")
    local catalog = setmetatable({
        provider = provider,
        rows = {},
        seen = {},
        cursor = 0,
        complete = false,
        pinnedLoaded = false,
        labelsReady = true,
        language = languageToken(),
    }, Catalog)
    catalog:loadPinned()
    return catalog
end

local function usableLabel(value, fullType)
    value = value and tostring(value) or ""
    fullType = tostring(fullType or "")
    return value ~= "" and value ~= fullType and value ~= ("ItemName_" .. fullType)
end

local function localizedItemLabel(fullType, fallback)
    fullType = tostring(fullType or "")
    if getItemNameFromFullType then
        local ok, value = pcall(getItemNameFromFullType, fullType)
        if ok and usableLabel(value, fullType) then return tostring(value) end
    end

    local key = "ItemName_" .. fullType
    if getText then
        local ok, value = pcall(getText, key)
        if ok and usableLabel(value, fullType) then
            return tostring(value)
        end
    end

    if GodSystemFallbackItems and usableLabel(GodSystemFallbackItems[fullType], fullType) then
        return tostring(GodSystemFallbackItems[fullType])
    end

    if getScriptManager and getScriptManager() then
        local manager = getScriptManager()
        local scriptItem = manager and manager.FindItem and manager:FindItem(fullType) or nil
        if scriptItem and scriptItem.getDisplayName then
            local ok, value = pcall(scriptItem.getDisplayName, scriptItem)
            if ok and usableLabel(value, fullType) then return tostring(value) end
        end
    end

    return tostring(fallback or fullType)
end

function Catalog:loadPinned()
    if self.pinnedLoaded then return 0 end
    self.pinnedLoaded = true
    local configured = GodSystemConfig and GodSystemConfig.ItemConfigPinnedFullTypes or {}
    local added = 0
    for index = 1, #configured do
        local fullType = tostring(configured[index] or "")
        if fullType ~= "" and not self.seen[fullType] then
            self.seen[fullType] = true
            local row = {
                key = fullType,
                fullType = fullType,
                label = localizedItemLabel(fullType),
                moduleName = tostring(fullType:match("^([^%.]+)%.") or ""),
            }
            row.sortLabel = tostring(row.label):lower()
            row.searchIndex = GodSystemPinyin.buildIndex({ row.fullType, row.label, row.moduleName })
            self.rows[#self.rows + 1] = row
            added = added + 1
        end
    end
    return added
end

function Catalog:buildStep(requested)
    if self.cancelled or self.paused then return 0 end
    local started = clockMs()
    self:ensureLocalizedLabels()
    if self.rebuild then
        local work = self.rebuild
        local built = 0
        if work.cursor < #self.rows then
            while built < 64 and work.cursor < #self.rows and (built == 0 or clockMs()-started < 2) do
                work.cursor = work.cursor + 1
                local source = self.rows[work.cursor]
                local row = {}
                for key,value in pairs(source) do row[key]=value end
                row.label = localizedItemLabel(row.fullType, row.baseLabel or row.label)
                row.baseLabel = row.label
                if row.worldSprite then row.label = row.label.." ["..tostring(row.worldSprite).."]" end
                row.sortLabel = tostring(row.label):lower()
                row.searchIndex = GodSystemPinyin.buildIndex({row.fullType,row.label,row.moduleName})
                work.rows[#work.rows+1] = row
                built = built + 1
            end
            return 0
        end
        if sortStep(work, started) then
            if self.rebuild == work and work.language == languageToken() then
                self.rows, self.language = work.rows, work.language
                self.rebuild = nil
                return 1
            end
        end
        return 0
    end
    if self.complete then return 0 end
    if self.cursor >= math.max(0, math.floor(tonumber(self.provider:count()) or 0)) then
        return sortStep(self, started) and 1 or 0
    end
    local limit = math.max(1, math.min(64, math.floor(tonumber(requested) or 64)))
    local count = math.max(0, math.floor(tonumber(self.provider:count()) or 0))
    local built = 0
    while built < limit and self.cursor < count and (built == 0 or clockMs()-started < 2) do
        local metadata = self.provider:metadata(self.cursor)
        self.cursor = self.cursor + 1
        if type(metadata) == "table" then
            local fullType = tostring(metadata.fullType or "")
            local identity = tostring(metadata.key or metadata.variantKey or fullType)
            if fullType ~= "" and identity ~= "" and not self.seen[identity] then
                self.seen[identity] = true
                local row = {
                    key = tostring(metadata.key or fullType),
                    fullType = fullType,
                    label = localizedItemLabel(fullType, metadata.label),
                    moduleName = tostring(metadata.moduleName or fullType:match("^([^%.]+)%.") or ""),
                    displayCategory = tostring(metadata.displayCategory or ""),
                    variantKey = metadata.variantKey,
                    worldSprite = metadata.worldSprite,
                }
                row.baseLabel = row.label
                if row.worldSprite then row.label=row.label.." ["..tostring(row.worldSprite).."]" end
                row.sortLabel = tostring(row.label):lower()
                row.searchIndex = GodSystemPinyin.buildIndex({ row.fullType, row.label, row.moduleName })
                self.rows[#self.rows + 1] = row
            end
        end
        built = built + 1
    end
    if self.cursor >= count then
        beginSort(self)
    end
    return built
end

function Catalog:refreshLocalizedLabels()
    -- Work on a separate snapshot; readers never see half-translated rows.
    self.rebuild = { rows={}, cursor=0, language=languageToken() }
    return true
end

function Catalog:ensureLocalizedLabels()
    local language = languageToken()
    if self.complete and language ~= self.language
        and (not self.rebuild or self.rebuild.language ~= language) then
        self:refreshLocalizedLabels()
    end
end

function Catalog:query(search, page, requestedPageSize, priceProvider)
    self:ensureLocalizedLabels()
    search = tostring(search or ""):lower()
    page = math.max(1, math.floor(tonumber(page) or 1))
    local pageSize = math.max(1, math.min(50, math.floor(tonumber(requestedPageSize) or 50)))
    local matches = {}
    for index = 1, #self.rows do
        local row = self.rows[index]
        if GodSystemPinyin.matches(row.searchIndex, search) then
            matches[#matches + 1] = row
        end
    end
    local pageCount = math.max(1, math.ceil(#matches / pageSize))
    if page > pageCount then page = pageCount end
    local first = ((page - 1) * pageSize) + 1
    local result = {}
    for index = first, math.min(#matches, first + pageSize - 1) do
        local source = matches[index]
        local row = {}
        for key, value in pairs(source) do row[key] = value end
        if type(priceProvider) == "function" then row.price = priceProvider(row) end
        result[#result + 1] = row
    end
    return {
        rows = result,
        total = #matches,
        page = page,
        pageCount = pageCount,
        complete = self.complete,
        built = #self.rows,
    }
end

local function matchesCriteria(row, criteria)
    criteria = type(criteria) == "table" and criteria or {}
    local search = tostring(criteria.search or ""):lower()
    local moduleName = tostring(criteria.moduleName or "")
    local displayCategory = tostring(criteria.displayCategory or "")
    local membership = criteria.membership
    if search ~= "" and not GodSystemPinyin.matches(row.searchIndex, search) then
        return false
    end
    if moduleName ~= "" and tostring(row.moduleName) ~= moduleName then return false end
    if displayCategory ~= "" and tostring(row.displayCategory) ~= displayCategory then return false end
    if type(membership) == "function" and membership(row) ~= true then return false end
    return true
end

function Catalog:queryFiltered(criteria, page, requestedPageSize)
    self:ensureLocalizedLabels()
    page = math.max(1, math.floor(tonumber(page) or 1))
    local pageSize = math.max(1, math.min(50, math.floor(tonumber(requestedPageSize) or 50)))
    local matches = {}
    for index = 1, #self.rows do
        local row = self.rows[index]
        if matchesCriteria(row, criteria) then matches[#matches + 1] = row end
    end
    local pageCount = math.max(1, math.ceil(#matches / pageSize))
    if page > pageCount then page = pageCount end
    local first = ((page - 1) * pageSize) + 1
    local rows = {}
    for index = first, math.min(#matches, first + pageSize - 1) do rows[#rows + 1] = matches[index] end
    return { rows = rows, total = #matches, page = page, pageCount = pageCount, complete = self.complete, built = #self.rows }
end

function Catalog:collectFilteredFullTypes(criteria)
    self:ensureLocalizedLabels()
    local result = {}
    for index = 1, #self.rows do
        local row = self.rows[index]
        if matchesCriteria(row, criteria) then result[#result + 1] = row.fullType end
    end
    return result
end

local function defaultProvider()
    local manager = getScriptManager and getScriptManager() or nil
    local scripts = manager and GodSystemB42JavaCalls.value(manager, "getAllItems", nil) or nil
    local provider = { scripts = scripts }
    function provider:scriptCount()
        if not self.scripts then return 0 end
        if type(self.scripts) == "table" and type(self.scripts.size) ~= "function" then return #self.scripts end
        return math.max(0, math.floor(tonumber(GodSystemB42JavaCalls.value(self.scripts, "size", 0)) or 0))
    end
    function provider:loadVariants()
        if self.variants then return end
        self.variants = {}
        local runtime = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime or nil
        local data = runtime and runtime.getData and runtime.getData() or {}
        for variantKey, row in pairs((data and data.unlockedShopItems) or {}) do
            if row and row.fullType and row.worldSprite then
                self.variants[#self.variants + 1] = {
                    key = tostring(variantKey),
                    variantKey = tostring(variantKey),
                    fullType = tostring(row.fullType),
                    worldSprite = tostring(row.worldSprite),
                    label = localizedItemLabel(row.fullType),
                }
            end
        end
        table.sort(self.variants, function(left, right) return tostring(left.key) < tostring(right.key) end)
    end
    function provider:count()
        self:loadVariants()
        return self:scriptCount() + #self.variants
    end
    function provider:metadata(index)
        local scriptCount = self:scriptCount()
        if index >= scriptCount then
            self:loadVariants()
            return self.variants[index - scriptCount + 1]
        end
        local script
        if type(self.scripts) == "table" and type(self.scripts.get) ~= "function" then
            script = self.scripts[index + 1]
        else
            script = GodSystemB42JavaCalls.value(self.scripts, "get", nil, index)
        end
        if not script then return nil end
        local fullType = GodSystemB42JavaCalls.value(script, "getFullName", nil)
            or GodSystemB42JavaCalls.value(script, "getFullType", nil)
        if not fullType then
            local moduleName = GodSystemB42JavaCalls.value(script, "getModuleName", nil)
            local name = GodSystemB42JavaCalls.value(script, "getName", nil)
            if moduleName and name then fullType = tostring(moduleName) .. "." .. tostring(name) end
        end
        if not fullType then return nil end
        local label = GodSystemB42JavaCalls.value(script, "getDisplayName", nil)
        local moduleName = GodSystemB42JavaCalls.value(script, "getModuleName", nil)
        local displayCategory = GodSystemB42JavaCalls.value(script, "getDisplayCategory", nil)
        return {
            fullType = tostring(fullType),
            label = tostring(label or fullType),
            moduleName = tostring(moduleName or ""),
            displayCategory = tostring(displayCategory or ""),
        }
    end
    return provider
end

function GodSystemItemCatalog.getShared()
    if not GodSystemItemCatalog.Shared then
        GodSystemItemCatalog.Shared = GodSystemItemCatalog.new(defaultProvider())
    end
    GodSystemItemCatalog.Shared.paused = false
    return GodSystemItemCatalog.Shared
end

function GodSystemItemCatalog.resetSession()
    -- Consumers fetch the shared instance when rendering; subscribers compare
    -- against Shared, so an old build cannot publish into the next session.
    if GodSystemItemCatalog.Shared then GodSystemItemCatalog.Shared.cancelled = true end
    GodSystemItemCatalog.Shared = nil
    listeners = {}
end

function GodSystemItemCatalog.subscribe(listener, persistent)
    assert(type(listener) == "function", "item catalog listener is required")
    local target = persistent and persistentListeners or listeners
    target[#target + 1] = listener
    local active = true
    return function()
        if not active then return end
        active = false
        for index = #target, 1, -1 do
            if target[index] == listener then table.remove(target, index) end
        end
        if not persistent and #listeners == 0 and GodSystemItemCatalog.Shared then
            GodSystemItemCatalog.Shared.paused = true
            GodSystemItemCatalog.Shared.rebuild = nil
        end
    end
end

function GodSystemItemCatalog.buildOnTick()
    local catalog = GodSystemItemCatalog.Shared
    if catalog and not catalog.paused and (not catalog.complete or catalog.rebuild) then
        local built = catalog:buildStep(64)
        if built > 0 then
            for index = 1, #listeners do listeners[index](catalog, built) end
            for index = 1, #persistentListeners do persistentListeners[index](catalog, built) end
        end
    end
end

if Events and Events.OnTick then Events.OnTick.Add(GodSystemItemCatalog.buildOnTick) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(GodSystemItemCatalog.resetSession) end

return GodSystemItemCatalog
