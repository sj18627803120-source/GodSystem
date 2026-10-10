-- Real client runtime and hidden-window controller, using the MP projection
-- which deliberately omits the saved listing table. No Java/world mutation.
assert(loadstring(readFixture("terminal_fixture.lua")))()
local function load(path) return assert(loadstring(readSource(path)))() end
load("shared/GodSystem_ShopVariants.lua")
load("shared/GodSystem_StateProjection.lua")
load("client/GodSystem_ShopListingStore.lua")
local r = GodSystemApp.services.runtime
local store = GodSystemShopListingStore
local sent, actions = {}, 0
GodSystemNetwork = { isMultiplayer = true, stateSerial = 1, send = function(command, args)
    sent[#sent + 1] = { command = command, args = args }; return true
end }
GodSystemItemConfig = { getShopVariantMode = function() return "auto" end }
local variant = "Moveables.Moveable@worldSprite=fixture_sink"
local data = { shopCatalogSchemaVersion = 1, shopCatalogRevision = 2, shopCatalogCount = 2,
    unlockedShopItems = {
        ["Base.Test"] = { fullType = "Base.Test", label = "Test", hidden = true, sellPrice = 2 },
        [variant] = { fullType = "Moveables.Moveable", worldSprite = "fixture_sink", label = "Sink", hidden = false, sellPrice = 3 },
    } }
local view = GodSystemStateProjection.build(data, { includeShopPayload = false })
assert(view.unlockedShopItems == nil)
r.getData = function() return view end
local env = setmetatable({ GodSystemApp = GodSystemApp }, { __index = _G })
load("client/GodSystem_ClientRuntime_Economy.lua")
GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Economy(env)
load("client/GodSystem_ClientRuntime_Recycle.lua")
GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Recycle(env)
r.getAutoShopBuyPriceForItem = function() return 20 end
r.itemExists = function() return true end
r.canContextRecycleItem = function() return true end
r.isAutoShopUnlockAllowed = function() return true end
r.getConfiguredShopKeySet = function() return {} end
r.setShopItemsHidden = function(keys, hidden)
    actions = actions + 1
    for i = 1, #keys do assert(GodSystemShopVariants.setHidden(data, keys[i], hidden)) end
    return true
end
r.deleteShopItem = function() actions = actions + 1; return true end
local item = { getFullType = function() return "Base.Test" end }
store.onState(view)
local rows, ready = r.getUnlockedShopItemsList(true)
assert(#rows == 0 and ready == false and #sent == 1, "unknown catalogue must not claim to be empty")
assert(select(2, r.canContextListItem(item)) == "catalogLoading", "unknown is not unlisted")
GodSystemInventoryContext = { register = function() end }
load("client/GodSystem_RecycleContext.lua")
local analysis = { allowed = true, listable = false, listReason = "catalogLoading" }
assert(GodSystemRecycleContext.classifyItem(item, "recycle", analysis))
assert(not GodSystemRecycleContext.classifyItem(item, "recycleAndList", analysis))
assert(not GodSystemRecycleContext.classifyItem(item, "listOnly", analysis))
local w = GodSystemUI.openShopHiddenManager()
assert(w.catalogLoading and w.list.items[1].item.empty)
assert(not w.hideButton.enable and not w.showButton.enable and not w.deleteButton.enable)
assert(#sent == 1, "repeated loading reads must reuse one in-flight request")
local function receive(items, done, cursor)
    local request = sent[#sent].args
    assert(store.receive({ requestId = request.requestId, revision = store.revision,
        items = items, done = done, nextCursor = cursor }))
    store.step(50, 999)
end
local hidden = { variantKey = "Base.Test", fullType = "Base.Test", label = "Test", hidden = true, sellPrice = 2 }
receive({ hidden }, false, "Base.Test")
w:onServerStateChanged()
assert(w.catalogLoading and w.list.items[1].item.empty, "partial snapshot stays unpublished")
local visible = { variantKey = variant, fullType = "Moveables.Moveable", worldSprite = "fixture_sink", label = "Sink", hidden = false, sellPrice = 3 }
local finalRequest, sentCount = sent[#sent].args, #sent
assert(store.receive({ requestId = finalRequest.requestId, revision = store.revision,
    items = { visible }, done = true }))
w:onServerStateChanged()
assert(w.catalogLoading and #sent == sentCount,
    "final chunk consumption must not request the same cursor again")
store.step(50, 999)
w:onServerStateChanged()
assert(not w.catalogLoading and #w.list.items == 2, "completed MP chunks must populate the actual window")
rows, ready = r.getUnlockedShopItemsList(true)
assert(ready and #rows == 2 and #r.getUnlockedShopItemsList(false) == 1)
assert(select(2, r.canContextListItem(item)) == "hiddenListed")
load("server/GodSystem_ServerRuntime_EconomyTasks.lua")
local serverEnv = setmetatable({ GodSystemConfig = {},
    GodSystemManualRecycle = { canRecycle = function() return true end },
    GodSystemServer = { getConfiguredShopKeySet = function() return {} end } }, { __index = _G })
GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_EconomyTasks(serverEnv)
serverEnv.isAutoShopListOnlyAllowed = function() return true end
assert(select(2, serverEnv.canContextListItem(data, item)) == "hiddenListed",
    "authoritative duplicate protection remains enabled")
assert(select(2, r.canContextListItem({ getFullType = function() return "Moveables.Moveable" end,
    getWorldSprite = function() return "fixture_sink" end })) == "alreadyListed")
assert(r.canContextListItem({ getFullType = function() return "Moveables.Moveable" end,
    getWorldSprite = function() return "fixture_other" end }), "furniture variants retain separate identities")
local function selectKey(key)
    for i, row in ipairs(w.list.items) do if row.item.variantKey == key then
        w.list.selected = i; w:applyVariantSelection(key, false); w:updateButtons(); return
    end end
    error("missing listing " .. key)
end
selectKey("Base.Test")
assert(w.showButton.enable and not w.hideButton.enable)
w:onShow()
assert(actions == 1 and data.unlockedShopItems["Base.Test"].hidden == false)
assert(select(2, serverEnv.canContextListItem(data, item)) == "alreadyListed")
view = GodSystemStateProjection.build(data, { includeShopPayload = false })
store.onState(view)
w:onServerStateChanged()
assert(w.catalogLoading and w.selectedVariantKeys["Base.Test"], "refresh keeps selected IDs while waiting")
assert(not w.showButton.enable and not w.deleteButton.enable)
w:onShow(); w:onDelete(); assert(actions == 1, "stale rows must not issue actions")
local request = sent[#sent].args
assert(store.receive({ requestId = request.requestId, revision = store.revision, done = true,
    items = { { variantKey = "Base.Test", fullType = "Base.Test", label = "Test", hidden = false }, visible } }))
store.step(50, 999); w:onServerStateChanged()
assert(w.selectedVariantKeys["Base.Test"] and w.hideButton.enable and not w.showButton.enable)
assert(select(2, r.canContextListItem(item)) == "alreadyListed", "restore does not create a second listing")
w:setStatus("hidden")
assert(w.list.items[1].item.empty, "empty is shown only for a completed filtered snapshot")
store.resetSession(); w:onServerStateChanged()
assert(w.catalogLoading and w.list.items[1].item.empty and not w.deleteButton.enable)
w:close()
GodSystemNetwork.isMultiplayer = false
view = data
rows, ready = r.getUnlockedShopItemsList(true)
assert(ready and #rows == 2, "SP keeps its local persisted listing table")
local count = #sent; r.getUnlockedShopItemsList(true); assert(#sent == count)
print("PASS hidden shop: MP projection, atomic chunks, restore, loading guard, furniture variants, reconnect and SP")
