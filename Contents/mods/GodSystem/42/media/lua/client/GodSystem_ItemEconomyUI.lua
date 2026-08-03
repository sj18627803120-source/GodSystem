require "GodSystem_Config"
require "GodSystem_EconomyPolicy"
require "GodSystem_AdminConfig"
require "GodSystem_ShopVariants"
require "GodSystem_UITheme"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

GodSystemItemEconomyUI = GodSystemItemEconomyUI or {}

local Theme = GodSystemUITheme or {}
local Colors = Theme.colors or {}
local PAGE_SIZE = 200

local function color(name, fallback)
    return Colors[name] or fallback or { r = 1, g = 1, b = 1, a = 1 }
end

local function text(key, fallback)
    if GodSystem and GodSystem.text then return GodSystem.text(key, fallback) end
    return fallback or key
end

local function safeMethod(object, methodName, fallback)
    if not object or type(object[methodName]) ~= "function" then return fallback end
    local ok, value = pcall(function() return object[methodName](object) end)
    if ok and value ~= nil then return value end
    return fallback
end

local function listSize(list)
    if not list then return 0 end
    if type(list) == "table" and type(list.size) ~= "function" then return #list end
    return math.max(0, math.floor(tonumber(safeMethod(list, "size", 0)) or 0))
end

local function listGet(list, index)
    if type(list) == "table" and type(list.get) ~= "function" then return list[index + 1] end
    local ok, value = pcall(function() return list:get(index) end)
    if ok then return value end
    return nil
end

local function fullTypeForScript(script)
    local fullType = safeMethod(script, "getFullName", nil) or safeMethod(script, "getFullType", nil)
    if fullType then return tostring(fullType) end
    local moduleName = safeMethod(script, "getModuleName", nil)
    local name = safeMethod(script, "getName", nil)
    if moduleName and name then return tostring(moduleName) .. "." .. tostring(name) end
    return nil
end

local function displayName(script, fullType)
    local value = safeMethod(script, "getDisplayName", nil)
    if value and tostring(value) ~= "" then return tostring(value) end
    if GodSystem and GodSystem.getItemDisplayName then return GodSystem.getItemDisplayName(fullType, fullType) end
    return fullType
end

local function buildCatalog()
    local result, seen = {}, {}
    local manager = getScriptManager and getScriptManager() or nil
    local scripts = manager and safeMethod(manager, "getAllItems", nil) or nil
    for i = 0, listSize(scripts) - 1 do
        local script = listGet(scripts, i)
        local fullType = fullTypeForScript(script)
        if fullType and fullType ~= "" and not seen[fullType] then
            seen[fullType] = true
            local quote = GodSystemEconomyPolicy.quote(fullType, nil, { kind = "admin" })
            local override = GodSystemAdminConfig.getItemOverride(fullType)
            result[#result + 1] = {
                key = fullType,
                fullType = fullType,
                label = displayName(script, fullType),
                moduleName = fullType:match("^([^%.]+)%.") or "",
                category = quote.category,
                quote = quote,
                override = override,
                shopMode = GodSystemAdminConfig.getShopMode(fullType),
                eligible = quote.eligible == true,
            }
        end
    end
    local data = GodSystem and GodSystem.getData and GodSystem.getData() or {}
    for variantKey, row in pairs((data and data.unlockedShopItems) or {}) do
        local fullType = row and row.fullType or nil
        local worldSprite = row and row.worldSprite or nil
        if fullType and worldSprite then
            local key = tostring(variantKey)
            local quote = GodSystemEconomyPolicy.quote(fullType, nil, { kind = "admin" })
            local variantOverride = GodSystemAdminConfig.getShopVariantOverride(key)
            result[#result + 1] = {
                key = key,
                variantKey = key,
                fullType = fullType,
                worldSprite = worldSprite,
                label = (row.label or fullType) .. " [" .. tostring(worldSprite) .. "]",
                moduleName = fullType:match("^([^%.]+)%.") or "",
                category = quote.category,
                quote = quote,
                override = GodSystemAdminConfig.getItemOverride(fullType),
                variantOverride = variantOverride,
                shopMode = GodSystemAdminConfig.getShopVariantMode(key, fullType),
                eligible = quote.eligible == true,
            }
        end
    end
    table.sort(result, function(a, b)
        local left, right = tostring(a.label or a.key), tostring(b.label or b.key)
        if left == right then return tostring(a.key) < tostring(b.key) end
        return left < right
    end)
    return result
end

local function compact(value)
    return tostring(value or ""):lower()
end

local FILTER_SAFETY = { "all", "verified", "unverified", "not_applicable", "excluded" }
local FILTER_SHOP = { "all", "auto", "forced", "disabled" }
local FILTER_OVERRIDE = { "all", "overridden", "automatic" }
local SHOP_MODES = { "auto", "forced", "disabled" }
local TRI_STATES = { "default", "enabled", "disabled" }

local FILTER_LABELS = {
    all = { "EconomyValue_All", "All" },
    verified = { "EconomyValue_Verified", "Verified" },
    unverified = { "EconomyValue_Unverified", "Unverified" },
    not_applicable = { "EconomyValue_NotApplicable", "No conversion" },
    excluded = { "EconomyValue_Excluded", "Excluded" },
    auto = { "EconomyValue_Auto", "Automatic" },
    forced = { "EconomyValue_Forced", "Forced" },
    disabled = { "EconomyValue_Disabled", "Disabled" },
    overridden = { "EconomyValue_Overridden", "Overridden" },
    automatic = { "EconomyValue_AutomaticOnly", "Automatic only" },
    default = { "EconomyValue_Default", "Default" },
    enabled = { "EconomyValue_Enabled", "Enabled" },
}

local function valueLabel(value)
    local row = FILTER_LABELS[tostring(value or "")]
    return row and text(row[1], row[2]) or tostring(value or "")
end

local function categoryLabel(value)
    if tostring(value or "") == "all" then return valueLabel("all") end
    if GodSystem and GodSystem.getShopCategoryLabel then return GodSystem.getShopCategoryLabel(value) end
    return tostring(value or "")
end

GodSystemItemEconomyWindow = ISCollapsableWindow:derive("GodSystemItemEconomyWindow")

function GodSystemItemEconomyWindow:new(x, y, width, height, owner)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = text("EconomyAdmin_Title", "GodSystem Item Economy")
    o.owner = owner
    o.resizable = false
    o.catalog = buildCatalog()
    o.filtered = {}
    o.page = 1
    o.categoryFilter = "all"
    o.safetyFilter = "all"
    o.shopFilter = "all"
    o.overrideFilter = "all"
    o.searchText = ""
    o.selectedKey = nil
    o.editShopMode = "auto"
    o.editRecycleState = "default"
    o.editLotteryState = "default"
    return o
end

function GodSystemItemEconomyWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = 30
    self.searchBox = ISTextEntryBox:new("", 12, top, 250, 28)
    self.searchBox:initialise(); self.searchBox:instantiate(); self.searchBox.target = self
    self.searchBox.onTextChange = function(entry) self:onSearchChanged(entry) end
    self:addChild(self.searchBox)

    self.categoryButton = ISButton:new(270, top, 150, 28, "", self, self.onCategory)
    self.categoryButton:initialise(); self:addChild(self.categoryButton)
    self.safetyButton = ISButton:new(428, top, 150, 28, "", self, self.onSafety)
    self.safetyButton:initialise(); self:addChild(self.safetyButton)
    self.shopFilterButton = ISButton:new(586, top, 150, 28, "", self, self.onShopFilter)
    self.shopFilterButton:initialise(); self:addChild(self.shopFilterButton)
    self.overrideFilterButton = ISButton:new(744, top, 150, 28, "", self, self.onOverrideFilter)
    self.overrideFilterButton:initialise(); self:addChild(self.overrideFilterButton)
    self.refreshButton = ISButton:new(902, top, 146, 28, text("Btn_Refresh", "Refresh"), self, self.onRefresh)
    self.refreshButton:initialise(); self:addChild(self.refreshButton)

    self.list = ISScrollingListBox:new(12, 68, 510, 530)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight = 30
    self.list.doDrawItem = function(list, y, row, alt) return self:drawCatalogItem(list, y, row, alt) end
    self.list:setOnMouseDownFunction(self, self.onCatalogSelected)
    self:addChild(self.list)

    self.detail = ISScrollingListBox:new(534, 68, 514, 190)
    self.detail:initialise(); self.detail:instantiate(); self.detail.itemheight = 22
    self.detail.doDrawItem = function(list, y, row, alt)
        local c = color("text")
        if row and row.item and row.item.warning then c = color("red") end
        list:drawText(tostring(row and row.text or ""), 8, y + 4, c.r, c.g, c.b, c.a, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.detail)

    local function addLabel(owner, x, y, label)
        local value = ISLabel:new(x, y, 20, label, 0.86, 0.84, 0.76, 1, UIFont.Small, true)
        value:initialise(); owner:addChild(value); return value
    end
    addLabel(self, 534, 272, text("EconomyAdmin_BuyOverride", "Shop price override"))
    self.buyEntry = ISTextEntryBox:new("", 534, 292, 150, 28); self.buyEntry:initialise(); self.buyEntry:instantiate(); self:addChild(self.buyEntry)
    addLabel(self, 700, 272, text("EconomyAdmin_SellOverride", "Recycle override"))
    self.sellEntry = ISTextEntryBox:new("", 700, 292, 150, 28); self.sellEntry:initialise(); self.sellEntry:instantiate(); self:addChild(self.sellEntry)
    addLabel(self, 866, 272, text("EconomyAdmin_CategoryOverride", "Category override"))
    self.categoryEntry = ISTextEntryBox:new("", 866, 292, 182, 28); self.categoryEntry:initialise(); self.categoryEntry:instantiate(); self:addChild(self.categoryEntry)

    self.shopModeButton = ISButton:new(534, 338, 160, 30, "", self, self.onShopMode)
    self.shopModeButton:initialise(); self:addChild(self.shopModeButton)
    self.recycleButton = ISButton:new(704, 338, 160, 30, "", self, self.onRecycleState)
    self.recycleButton:initialise(); self:addChild(self.recycleButton)
    self.lotteryButton = ISButton:new(874, 338, 174, 30, "", self, self.onLotteryState)
    self.lotteryButton:initialise(); self:addChild(self.lotteryButton)

    addLabel(self, 534, 382, text("EconomyAdmin_Note", "Administrator note"))
    self.noteEntry = ISTextEntryBox:new("", 534, 402, 514, 28); self.noteEntry:initialise(); self.noteEntry:instantiate(); self:addChild(self.noteEntry)

    self.saveButton = ISButton:new(534, 450, 160, 34, text("Btn_Save", "Save"), self, self.onSave)
    self.saveButton:initialise(); self:addChild(self.saveButton)
    self.resetButton = ISButton:new(704, 450, 160, 34, text("EconomyAdmin_Reset", "Restore automatic"), self, self.onReset)
    self.resetButton:initialise(); self:addChild(self.resetButton)
    self.prevButton = ISButton:new(12, 610, 110, 34, text("Btn_ShopPrevPage", "Prev"), self, self.onPrev)
    self.prevButton:initialise(); self:addChild(self.prevButton)
    self.nextButton = ISButton:new(132, 610, 110, 34, text("Btn_ShopNextPage", "Next"), self, self.onNext)
    self.nextButton:initialise(); self:addChild(self.nextButton)
    self.pageLabel = ISLabel:new(254, 618, 20, "", 0.86, 0.84, 0.76, 1, UIFont.Small, true)
    self.pageLabel:initialise(); self:addChild(self.pageLabel)
    self.closeButton = ISButton:new(908, 610, 140, 34, text("Btn_Close", "Close"), self, self.close)
    self.closeButton:initialise(); self:addChild(self.closeButton)
    self:refreshFilters()
    self:populate()
end

function GodSystemItemEconomyWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local shell, border = color("shell"), color("borderStrong")
    self:drawRect(0, 16, self.width, self.height - 16, shell.a, shell.r, shell.g, shell.b)
    self:drawRectBorder(1, 17, self.width - 2, self.height - 18, border.a, border.r, border.g, border.b)
end

function GodSystemItemEconomyWindow:drawCatalogItem(list, y, row, alt)
    local item = row and row.item or nil
    local background = alt and color("rowAlt") or color("row")
    list:drawRect(0, y, list.width, list.itemheight - 1, background.a, background.r, background.g, background.b)
    if list.selected == row.index then
        local selected = color("rowSelect")
        list:drawRect(0, y, list.width, list.itemheight - 1, selected.a, selected.r, selected.g, selected.b)
    end
    local c = item and item.eligible and color("text") or color("dimText")
    list:drawText(tostring(row and row.text or ""), 8, y + 7, c.r, c.g, c.b, c.a, UIFont.Small)
    return y + list.itemheight
end

function GodSystemItemEconomyWindow:refreshFilters()
    self.categoryButton:setTitle(text("EconomyFilter_Category", "Category") .. ": " .. categoryLabel(self.categoryFilter))
    self.safetyButton:setTitle(text("EconomyFilter_Safety", "Safety") .. ": " .. valueLabel(self.safetyFilter))
    self.shopFilterButton:setTitle(text("EconomyFilter_Shop", "Shop") .. ": " .. valueLabel(self.shopFilter))
    self.overrideFilterButton:setTitle(text("EconomyFilter_Override", "Override") .. ": " .. valueLabel(self.overrideFilter))
end

local function nextValue(values, current)
    for i = 1, #values do if values[i] == current then return values[(i % #values) + 1] end end
    return values[1]
end

function GodSystemItemEconomyWindow:onCategory()
    local categories, seen = { "all" }, { all = true }
    for i = 1, #self.catalog do
        local key = tostring(self.catalog[i].category or "normal")
        if not seen[key] then seen[key] = true; categories[#categories + 1] = key end
    end
    table.sort(categories, function(a, b) if a == "all" then return true elseif b == "all" then return false end return a < b end)
    self.categoryFilter = nextValue(categories, self.categoryFilter); self.page = 1; self:refreshFilters(); self:populate()
end

function GodSystemItemEconomyWindow:onSafety() self.safetyFilter = nextValue(FILTER_SAFETY, self.safetyFilter); self.page = 1; self:refreshFilters(); self:populate() end
function GodSystemItemEconomyWindow:onShopFilter() self.shopFilter = nextValue(FILTER_SHOP, self.shopFilter); self.page = 1; self:refreshFilters(); self:populate() end
function GodSystemItemEconomyWindow:onOverrideFilter() self.overrideFilter = nextValue(FILTER_OVERRIDE, self.overrideFilter); self.page = 1; self:refreshFilters(); self:populate() end
function GodSystemItemEconomyWindow:onShopMode() self.editShopMode = nextValue(SHOP_MODES, self.editShopMode); self:updateEditorButtons() end
function GodSystemItemEconomyWindow:onRecycleState() self.editRecycleState = nextValue(TRI_STATES, self.editRecycleState); self:updateEditorButtons() end
function GodSystemItemEconomyWindow:onLotteryState() self.editLotteryState = nextValue(TRI_STATES, self.editLotteryState); self:updateEditorButtons() end

function GodSystemItemEconomyWindow:onSearchChanged(entry)
    self.searchText = entry and entry.getInternalText and entry:getInternalText() or ""
    self.page = 1
    self:populate()
end

function GodSystemItemEconomyWindow:matches(item)
    local query = compact(self.searchText)
    if query ~= "" then
        local haystack = compact(item.label) .. " " .. compact(item.fullType) .. " " .. compact(item.moduleName)
            .. " " .. compact(item.category) .. " " .. compact(item.worldSprite)
        if not haystack:find(query, 1, true) then return false end
    end
    if self.categoryFilter ~= "all" and item.category ~= self.categoryFilter then return false end
    local safety = item.eligible and item.quote.verificationStatus or "excluded"
    if self.safetyFilter ~= "all" and safety ~= self.safetyFilter then return false end
    if self.shopFilter ~= "all" and item.shopMode ~= self.shopFilter then return false end
    local overridden = item.override ~= nil or item.variantOverride ~= nil
    if self.overrideFilter == "overridden" and not overridden then return false end
    if self.overrideFilter == "automatic" and overridden then return false end
    return true
end

function GodSystemItemEconomyWindow:populate()
    self.filtered = {}
    for i = 1, #self.catalog do if self:matches(self.catalog[i]) then self.filtered[#self.filtered + 1] = self.catalog[i] end end
    local pages = math.max(1, math.ceil(#self.filtered / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page, pages))
    self.list:clear()
    local first = ((self.page - 1) * PAGE_SIZE) + 1
    local last = math.min(#self.filtered, first + PAGE_SIZE - 1)
    for i = first, last do
        local item = self.filtered[i]
        self.list:addItem("[" .. categoryLabel(item.category) .. "][" .. valueLabel(item.shopMode) .. "] " .. tostring(item.label), item)
        if item.key == self.selectedKey then self.list.selected = #self.list.items end
    end
    self.pageLabel.name = tostring(self.page) .. "/" .. tostring(pages) .. "  " .. tostring(#self.filtered)
    self.prevButton:setEnable(self.page > 1)
    self.nextButton:setEnable(self.page < pages)
end

function GodSystemItemEconomyWindow:getSelected()
    local index = self.list and math.floor(tonumber(self.list.selected) or 0) or 0
    local row = index > 0 and self.list.items[index] or nil
    return row and row.item or nil
end

function GodSystemItemEconomyWindow:onCatalogSelected(item)
    item = item and (item.item or item) or self:getSelected()
    if not item then return end
    self.selectedKey = item.key
    local override = item.override or {}
    self.editShopMode = item.shopMode or "auto"
    self.editRecycleState = override.recycleEnabled == nil and "default" or (override.recycleEnabled and "enabled" or "disabled")
    self.editLotteryState = override.lotteryEnabled == nil and "default" or (override.lotteryEnabled and "enabled" or "disabled")
    self.buyEntry:setText(override.buyPrice ~= nil and tostring(override.buyPrice) or "")
    self.sellEntry:setText(override.sellPrice ~= nil and tostring(override.sellPrice) or "")
    self.categoryEntry:setText(override.category ~= nil and tostring(override.category) or "")
    self.noteEntry:setText(override.note ~= nil and tostring(override.note) or "")
    self:updateEditorButtons()
    self:updateDetail(item)
end

function GodSystemItemEconomyWindow:updateEditorButtons()
    self.shopModeButton:setTitle(text("EconomyAdmin_ShopMode", "Shop") .. ": " .. valueLabel(self.editShopMode))
    self.recycleButton:setTitle(text("EconomyAdmin_RecycleMode", "Recycle") .. ": " .. valueLabel(self.editRecycleState))
    self.lotteryButton:setTitle(text("EconomyAdmin_LotteryMode", "Lottery") .. ": " .. valueLabel(self.editLotteryState))
    local item = self:getSelected()
    local enabled = item ~= nil and item.eligible == true
    self.saveButton:setEnable(enabled)
    self.resetButton:setEnable(item ~= nil)
end

function GodSystemItemEconomyWindow:updateDetail(item)
    self.detail:clear()
    local detail, quote = GodSystem.getEconomyQuoteDetail(item.fullType, nil, true)
    for line in tostring(item.label .. "\n" .. detail):gmatch("[^\n]+") do self.detail:addItem(line, {}) end
    if item.worldSprite then self.detail:addItem("worldSprite: " .. tostring(item.worldSprite), {}) end
    if item.eligible ~= true then self.detail:addItem(text("EconomyAdmin_ReadOnly", "This internal or unsafe item is read-only."), { warning = true }) end
    for i = 1, #(quote.warnings or {}) do
        if quote.warnings[i] == "admin_below_safe_minimum" then
            self.detail:addItem(text("EconomyWarning_Arbitrage", "Warning: administrator price is below the safe minimum and may allow repeated profit."), { warning = true })
        end
    end
end

local function entryText(entry)
    return entry and entry.getInternalText and tostring(entry:getInternalText() or "") or ""
end

local function triValue(value)
    if value == "enabled" then return true end
    if value == "disabled" then return false end
    return nil
end

function GodSystemItemEconomyWindow:onSave()
    local item = self:getSelected()
    if not item or item.eligible ~= true then return end
    if self.editShopMode == "forced" and item.fullType == "Moveables.Moveable" and not item.worldSprite then
        if GodSystem and GodSystem.notify then GodSystem.notify(text("EconomyAdmin_FurnitureNeedsVariant", "Furniture must use a known world-sprite variant before it can be forced into the shop.")) end
        return
    end
    local override = {
        buyPrice = entryText(self.buyEntry) ~= "" and tonumber(entryText(self.buyEntry)) or nil,
        sellPrice = entryText(self.sellEntry) ~= "" and tonumber(entryText(self.sellEntry)) or nil,
        category = entryText(self.categoryEntry) ~= "" and entryText(self.categoryEntry) or nil,
        shopMode = item.variantKey and "auto" or self.editShopMode,
        recycleEnabled = triValue(self.editRecycleState),
        lotteryEnabled = triValue(self.editLotteryState),
        note = entryText(self.noteEntry) ~= "" and entryText(self.noteEntry) or nil,
    }
    local sent = GodSystem.saveEconomyOverride(item.fullType, override, item.variantKey, item.worldSprite, self.editShopMode)
    if sent and GodSystem and GodSystem.notify then GodSystem.notify(text("EconomyAdmin_Saved", "Item economy configuration saved.")) end
    self:onRefresh()
end

function GodSystemItemEconomyWindow:onReset()
    local item = self:getSelected()
    if not item then return end
    local sent = GodSystem.clearEconomyOverride(item.fullType, item.variantKey)
    if sent and GodSystem and GodSystem.notify then GodSystem.notify(text("EconomyAdmin_ResetDone", "Automatic pricing restored.")) end
    self:onRefresh()
end

function GodSystemItemEconomyWindow:onRefresh()
    GodSystemEconomyPolicy.rebuildTransformIndex()
    self.catalog = buildCatalog()
    self:populate()
    local selected = nil
    for i = 1, #self.catalog do if self.catalog[i].key == self.selectedKey then selected = self.catalog[i]; break end end
    if selected then self:updateDetail(selected) end
end

function GodSystemItemEconomyWindow:onPrev() self.page = math.max(1, self.page - 1); self:populate() end
function GodSystemItemEconomyWindow:onNext() self.page = self.page + 1; self:populate() end

function GodSystemItemEconomyWindow:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    if GodSystemItemEconomyUI.window == self then GodSystemItemEconomyUI.window = nil end
end

function GodSystemItemEconomyUI.open(owner)
    if GodSystemItemEconomyUI.window then GodSystemItemEconomyUI.window:close() end
    local width, height = 1060, 660
    local screenW = getCore and getCore():getScreenWidth() or 1280
    local screenH = getCore and getCore():getScreenHeight() or 720
    local window = GodSystemItemEconomyWindow:new(math.max(20, (screenW - width) / 2), math.max(20, (screenH - height) / 2), width, height, owner)
    window:initialise(); window:addToUIManager(); window:setVisible(true)
    GodSystemItemEconomyUI.window = window
    return window
end

return GodSystemItemEconomyUI
