local luaRoot = assert(arg[1], "42.20.2.2 lua root is required")
package.path = luaRoot .. "/client/?.lua;" .. luaRoot .. "/shared/?.lua;" .. package.path

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local scripts = {}
local function addScript(fullType, label)
    scripts[#scripts + 1] = {
        getFullName = function() return fullType end,
        getDisplayName = function() return label or fullType end,
    }
end
for i = 1, 205 do addScript("Base.TestItem" .. tostring(i), "Test item " .. tostring(i)) end
addScript("Base.MoneyBundle", "Money bundle")
addScript("Moveables.Moveable", "Moveable furniture")
addScript("Base.Hidden", "Internal item")

getScriptManager = function()
    return { getAllItems = function() return javaList(scripts) end }
end
getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
getPlayer = function() return { getPlayerNum = function() return 0 end } end
getMouseX = function() return 400 end
getMouseY = function() return 300 end
UIFont = { Small = "small" }

local function control(x, y, width, height, title)
    local value = { x = x, y = y, width = width, height = height, title = title or "", enabled = true }
    function value:initialise() end
    function value:instantiate() end
    function value:setTitle(nextTitle) self.title = nextTitle end
    function value:setEnable(nextEnabled) self.enabled = nextEnabled == true end
    function value:setText(nextText) self.text = tostring(nextText or "") end
    function value:getInternalText() return tostring(self.text or "") end
    return value
end

ISCollapsableWindow = {}
function ISCollapsableWindow:derive()
    local value = {}
    value.__index = value
    return setmetatable(value, { __index = self })
end
function ISCollapsableWindow.new(class, x, y, width, height)
    local value = setmetatable({ x = x, y = y, width = width, height = height, children = {} }, { __index = class })
    return value
end
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:initialise() end
function ISCollapsableWindow:addChild(child) self.children[#self.children + 1] = child end
function ISCollapsableWindow:addToUIManager() self.added = true end
function ISCollapsableWindow:removeFromUIManager() self.removed = true end
function ISCollapsableWindow:setVisible(value) self.visible = value == true end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:drawRect() end
function ISCollapsableWindow:drawRectBorder() end

ISButton, ISLabel, ISScrollingListBox, ISTextEntryBox, ISContextMenu = {}, {}, {}, {}, {}
function ISButton:new(x, y, width, height, title, target, callback)
    local value = control(x, y, width, height, title); value.target = target; value.callback = callback; return value
end
function ISLabel:new(x, y, height, title) local value = control(x, y, 0, height, title); value.name = title; return value end
function ISTextEntryBox:new(text, x, y, width, height) local value = control(x, y, width, height); value.text = text or ""; return value end
function ISScrollingListBox:new(x, y, width, height)
    local value = control(x, y, width, height)
    value.items = {}; value.selected = 0
    function value:clear() self.items = {}; self.selected = 0 end
    function value:addItem(text, item) self.items[#self.items + 1] = { text = text, item = item, index = #self.items + 1 } end
    function value:setOnMouseDownFunction(target, callback) self.mouseTarget = target; self.mouseCallback = callback end
    function value:drawRect() end
    function value:drawText() end
    return value
end

local lastContext = nil
function ISContextMenu.get()
    local context = { options = {} }
    function context:addOption(label, target, callback, value)
        local option = { label = label, target = target, callback = callback, value = value, checkMark = false }
        self.options[#self.options + 1] = option
        return option
    end
    lastContext = context
    return context
end

local function choose(value)
    assert(lastContext, "a choice menu must be open")
    for i = 1, #lastContext.options do
        local option = lastContext.options[i]
        if option.value == value then
            option.callback(option.target, option.value)
            return
        end
    end
    error("choice was not found: " .. tostring(value))
end

for _, moduleName in ipairs({
    "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISLabel", "ISUI/ISScrollingListBox", "ISUI/ISTextEntryBox", "ISUI/ISContextMenu",
    "GodSystem_Config", "GodSystem_EconomyPolicy", "GodSystem_AdminConfig", "GodSystem_ShopVariants", "GodSystem_UITheme",
}) do package.loaded[moduleName] = true end

GodSystemUITheme = { colors = {} }
local overrides = { ["Base.MoneyBundle"] = { buyPrice = 50, note = "unsafe test" } }
local saved, cleared, notifications = {}, {}, {}
GodSystemAdminConfig = {
    getItemOverride = function(fullType) return overrides[fullType] end,
    getShopMode = function(fullType) return overrides[fullType] and overrides[fullType].shopMode or "auto" end,
    getShopVariantOverride = function() return nil end,
    getShopVariantMode = function(_, fullType) return GodSystemAdminConfig.getShopMode(fullType) end,
}
GodSystemEconomyPolicy = {
    quote = function(fullType)
        local eligible = fullType ~= "Base.Hidden"
        local override = overrides[fullType]
        local finalBuy = override and override.buyPrice or (fullType == "Base.MoneyBundle" and 110 or 200)
        return {
            eligible = eligible,
            category = fullType == "Base.MoneyBundle" and "other" or "material",
            verificationStatus = fullType == "Base.MoneyBundle" and "verified" or "not_applicable",
            finalBuy = finalBuy,
            recycleValue = 1,
            safeMinimum = fullType == "Base.MoneyBundle" and 110 or 0,
            warnings = finalBuy < (fullType == "Base.MoneyBundle" and 110 or 0) and { "admin_below_safe_minimum" } or {},
        }
    end,
    rebuildTransformIndex = function() GodSystemEconomyPolicy.rebuilds = (GodSystemEconomyPolicy.rebuilds or 0) + 1 end,
}
GodSystem = {
    text = function(_, fallback) return fallback end,
    getData = function() return { unlockedShopItems = {} } end,
    getItemDisplayName = function(fullType) return fullType end,
    getShopCategoryLabel = function(category) return category end,
    getEconomyQuoteDetail = function(fullType)
        local quote = GodSystemEconomyPolicy.quote(fullType)
        return "Buy=" .. tostring(quote.finalBuy) .. " Recycle=" .. tostring(quote.recycleValue), quote
    end,
    saveEconomyOverride = function(fullType, override, variantKey, worldSprite, shopMode)
        saved[#saved + 1] = { fullType = fullType, override = override, variantKey = variantKey, worldSprite = worldSprite, shopMode = shopMode }
        overrides[fullType] = override
        return true
    end,
    clearEconomyOverride = function(fullType, variantKey)
        cleared[#cleared + 1] = { fullType = fullType, variantKey = variantKey }
        overrides[fullType] = nil
        return true
    end,
    notify = function(message) notifications[#notifications + 1] = message end,
}

local UI = dofile(luaRoot .. "/client/GodSystem_ItemEconomyUI.lua")
local window = UI.open({})
window:createChildren()

assert(window.visible == true and window.width == 1060 and window.height == 660, "administrator economy window must open at its intended size")
assert(#window.filtered == #scripts and #window.list.items == 200, "catalog must enumerate loaded scripts and paginate at 200 rows")
assert(window.nextButton.enabled == true and window.prevButton.enabled == false, "first catalog page must expose only the valid paging direction")

local originalCategory = window.categoryFilter
window:onCategory()
assert(window.categoryFilter == originalCategory and #lastContext.options >= 2,
    "clicking the category filter must open all choices without cycling the current value")
choose("material")
assert(window.categoryFilter == "material", "category menu must apply the selected category directly")
window:setCategoryFilter("all")

window:onSafety()
assert(#lastContext.options == 5 and window.safetyFilter == "all", "safety filter must open all choices without cycling")
choose("verified")
assert(window.safetyFilter == "verified", "safety menu must apply the selected state directly")
window:setSafetyFilter("all")

window:onShopFilter()
assert(#lastContext.options == 4 and window.shopFilter == "all", "shop filter must open all choices without cycling")
choose("disabled")
assert(window.shopFilter == "disabled", "shop filter menu must apply the selected state directly")
window:setShopFilter("all")

window:onOverrideFilter()
assert(#lastContext.options == 3 and window.overrideFilter == "all", "override filter must open all choices without cycling")
choose("automatic")
assert(window.overrideFilter == "automatic", "override filter menu must apply the selected state directly")
window:setOverrideFilter("all")

window:onShopMode(); assert(#lastContext.options == 3, "shop-mode editor must expose all values")
choose("forced"); assert(window.editShopMode == "forced", "shop-mode editor must select a value directly")
window:onRecycleState(); assert(#lastContext.options == 3, "recycle editor must expose all values")
choose("enabled"); assert(window.editRecycleState == "enabled", "recycle editor must select a value directly")
window:onLotteryState(); assert(#lastContext.options == 3, "lottery editor must expose all values")
choose("disabled"); assert(window.editLotteryState == "disabled", "lottery editor must select a value directly")

window:onNext()
assert(window.page == 2 and #window.list.items == #scripts - 200, "second page must contain the remaining loaded items")

window.searchBox:setText("MoneyBundle")
window:onSearchChanged(window.searchBox)
assert(#window.filtered == 1 and #window.list.items == 1 and window.list.items[1].item.fullType == "Base.MoneyBundle",
    "search must filter the cached catalog by fullType")
window.list.selected = 1
window:onCatalogSelected(window.list.items[1].item)
assert(window.buyEntry:getInternalText() == "50" and window.noteEntry:getInternalText() == "unsafe test",
    "selecting an overridden item must populate the editor")
local warningFound = false
for i = 1, #window.detail.items do if window.detail.items[i].item.warning then warningFound = true end end
assert(warningFound, "a price below the conversion-safe minimum must display a warning")

window.buyEntry:setText("120")
window.sellEntry:setText("2")
window.categoryEntry:setText("material")
window.noteEntry:setText("player journey admin edit")
window.editShopMode = "forced"
window.editRecycleState = "enabled"
window.editLotteryState = "disabled"
window:onSave()
local save = saved[#saved]
assert(save and save.fullType == "Base.MoneyBundle" and save.override.buyPrice == 120 and save.override.sellPrice == 2,
    "save must submit the selected item and both price overrides as one request")
assert(save.override.category == "material" and save.override.shopMode == "forced"
    and save.override.recycleEnabled == true and save.override.lotteryEnabled == false,
    "save must submit category, shop, recycle and lottery settings together")

window:onReset()
assert(cleared[#cleared] and cleared[#cleared].fullType == "Base.MoneyBundle", "restore automatic must clear the selected override")
assert(GodSystemEconomyPolicy.rebuilds and GodSystemEconomyPolicy.rebuilds >= 2, "save and reset refreshes must rebuild the conversion quote cache")

window.searchBox:setText("Moveables.Moveable")
window:onSearchChanged(window.searchBox)
window.list.selected = 1
window:onCatalogSelected(window.list.items[1].item)
window.editShopMode = "forced"
local savesBeforeFurniture = #saved
window:onSave()
assert(#saved == savesBeforeFurniture and #notifications > 0, "generic furniture without a world sprite must not be forced into the shop")

window.searchBox:setText("Base.Hidden")
window:onSearchChanged(window.searchBox)
window.list.selected = 1
window:onCatalogSelected(window.list.items[1].item)
assert(window.saveButton.enabled == false, "internal or unsafe items must remain read-only")

window:close()
assert(window.visible == false and window.removed == true, "administrator economy window must close cleanly")

print("Test-GodSystemV422022EconomyUIRuntime OK")
