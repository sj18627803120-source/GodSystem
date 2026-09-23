local source = readSource("client/GodSystem_ShopCatalog.lua")
GodSystemConfig = { ShopItems = {} }
GodSystemItemConfig = { getItemOverrides = function() return {} end, getShopVariantOverrides = function() return {} end, getShopVariantMode = function() return "auto" end }
GodSystemItemEligibility = { isEconomicItemAllowed = function() return true end }
GodSystemRuntimeConfig = { isFeatureEnabled = function() return true end }
GodSystemShopInflation = { key = function(item) return tostring(item.id) end }
local data = { ui = { shopFavorites = {}, shopRecent = {} }, unlockedShopItems = {} }
local availabilityChecks, quoteChecks = 0, 0
for i = 1, 125 do GodSystemConfig.ShopItems[i] = { id = "item" .. i, items = { { fullType = "Base.Item" .. i, count = 1 } } } end
GodSystemApp = { services = { runtime = {
    getData = function() return data end,
    shopItemIsAvailable = function() availabilityChecks = availabilityChecks + 1; return true, nil, nil, {} end,
    getShopPrimaryCategory = function(item) return { key = tonumber(item.id:match("(%d+)$")) % 2 == 0 and "even" or "odd", label = "Category" } end,
    getShopLabel = function(item) return item.id end,
    getShopInflationQuote = function(item) quoteChecks = quoteChecks + 1; return { total = tonumber(item.id:match("(%d+)$")), basePrice = 1 } end,
    getShopBaseUnitPrice = function() return 1 end,
} } }
assert(loadstring(source, "@GodSystem_ShopCatalog"))()
local C = GodSystemShopCatalog
assert(C.view("all", "") == nil, "first view must start an incremental build")
assert(C.step(50, 999) == false and availabilityChecks == 50, "first step must be bounded to 50 records")
while C.isBuilding() do C.step(50, 999) end
local all = C.view("all", "")
assert(#all == 125 and availabilityChecks == 125, "completed snapshot must contain every validated listing once")
local before = availabilityChecks
local even = C.view("even", "")
assert(#even > 0 and availabilityChecks == before, "cached filtering must not revalidate the catalogue")
local price = C.price(all[1])
assert(price > 0 and quoteChecks == 1, "only a requested page row may request a price")
C.invalidate("test")
assert(C.view("all", "") == nil, "invalidated data must not be offered for purchase")
while C.isBuilding() do C.step(50, 999) end
assert(#C.view("all", "") == 125, "new generation must atomically replace the snapshot")
print("PASS shop catalogue: bounded build, cached filters, current-row prices and invalidation")

GodSystemNetwork = { isMultiplayer = true }
local snapshot = C.snapshot
data = { ui = { shopFavorites = {}, shopRecent = {} }, unlockedShopItems = {} }
assert(C.ensure() == snapshot, "equivalent MP projection replacement must preserve the directory")
assert(availabilityChecks == 250, "MP projection must not repeat native validation")
for i = 1, 100 do C.view("all", "item" .. i) end
local cacheCount = 0
for _ in pairs(C.snapshot.filters) do cacheCount = cacheCount + 1 end
assert(cacheCount <= 1, "arbitrary search strings must not retain unbounded filter arrays")
local row = C.view("all", "")[1]
C.price(row); local quotes = quoteChecks
C.invalidatePrices(); C.price(row)
assert(quoteChecks == quotes + 1, "successful mutations must expire cached prices immediately")
assert(C.snapshot == snapshot, "price invalidation must preserve catalogue snapshot")
assert(loadstring(readSource("client/GodSystem_UIRefresh.lua")))()
local R = GodSystemUIRefresh
local revisions = { shopCatalog = 1, shopPreferences = 1, walletBank = 1, tasks = 1, equipment = 1 }
assert(not R.onState(nil, revisions, revisions))
assert(C.ensure() == snapshot)
local changed = { shopCatalog = 2, shopPreferences = 1, walletBank = 1, tasks = 1, equipment = 1 }
R.onState(nil, changed, revisions)
assert(C.ensure() == nil, "directory changes must invalidate even without an open window")
while C.isBuilding() do C.step(50, 999) end
R.onState(nil, {}, changed)
assert(C.ensure() == nil, "legacy empty revisions must conservatively invalidate")
local rebuilds = 0
local window = { mode = "bank", getIsVisible = function() return true end, populateList = function() rebuilds = rebuilds + 1 end }
R.mark(window, "numbers"); R.mark(window, "numbers"); R.flush(window)
assert(rebuilds == 1, "bank updates must refresh once, not silently disappear")
print("PASS shop audit: MP projection identity, bounded searches, immediate prices, closed-window invalidation and bank refresh")
assert(loadstring(readSource("shared/GodSystem_StateProjection.lua")))()
local projectionData={ui={shopView={category="all"}},tasks={{taskId="a",status="active",kind="kill",target=50,progress=1}},unlockedShopItems={}}
local options={equipmentRevision=1}
local revisions=GodSystemStateProjection.updateUIRevisions(projectionData,options)
local taskRevision,shopRevision,equipmentRevision=revisions.tasks,revisions.shopCatalog,revisions.equipment
projectionData.tasks[1].progress=20
GodSystemStateProjection.updateUIRevisions(projectionData,options)
assert(revisions.tasks==taskRevision, "progress alone must not rebuild task membership")
projectionData.tasks[1].status="claimed"
options.equipmentRevision=2
GodSystemStateProjection.updateUIRevisions(projectionData,options)
assert(revisions.tasks==taskRevision+1 and revisions.equipment==equipmentRevision+1)
assert(revisions.shopCatalog==shopRevision, "unrelated task and equipment changes must not invalidate shop")
assert(projectionData.uiRevisions==nil and projectionData.uiRevisionSignatures==nil, "presentation revision cache must not enter the save")
assert(GodSystemStateProjection.build(projectionData).uiRevisions.shopCatalog==shopRevision)
assert(GodSystemStateProjection.build({}).uiRevisions==nil, "uninitialized legacy projections must remain identifiable")
print("PASS projection audit: transient revisions, task membership, equipment authority revision and domain isolation")

local sentChunks={}
GodSystemNetwork.send=function(_,payload) sentChunks[#sentChunks+1]=payload; return true end
assert(loadstring(readSource("client/GodSystem_ShopListingStore.lua")))()
local S=GodSystemShopListingStore
S.reset(2,2)
S.request()
local first=sentChunks[#sentChunks]
assert(S.receive({revision=2,requestId=first.requestId,items={{variantKey="a"}},nextCursor="a",done=false}))
S.step(50,999)
assert(not S.ready and S.rows.a==nil,"partial catalogue must not be published")
local second=sentChunks[#sentChunks]
assert(second.cursor=="a" and second.requestId~=first.requestId)
S.prices.old={price=123}
S.onState({shopCatalogRevision=3,shopCatalogCount=1})
assert(not S.done and S.nextCursor==nil and S.prices.old==nil)
assert(S.receive({revision=2,requestId=second.requestId,items={{variantKey="stale"}},done=true})==false)
S.request()
local current=sentChunks[#sentChunks]
assert(current.cursor==nil and current.requestId~=second.requestId)
assert(S.receive({revision=3,requestId=second.requestId,items={{variantKey="stale"}},done=true})==false)
assert(S.receive({revision=3,requestId=current.requestId,items={{variantKey="fresh"}},done=true}))
S.step(50,999)
assert(S.ready and S.rows.fresh and not S.rows.stale and not S.rows.a)
S.resetSession()
assert(not S.ready and S.pendingId==nil and S.rows.fresh==nil)
local originalClock=C.nowMs
local tick=0
C.nowMs=function()return tick end
S.onState({shopCatalogRevision=4,shopCatalogCount=1})
S.request()
local timedOut=sentChunks[#sentChunks]
tick=10001; S.step(50,999)
local retried=sentChunks[#sentChunks]
assert(retried.requestId~=timedOut.requestId and retried.cursor==timedOut.cursor)
assert(S.receive({revision=4,requestId=timedOut.requestId,items={{variantKey="late"}},done=true})==false)
assert(S.receive({revision=5,total=1,requestId=retried.requestId,reset=true}))
assert(S.revision==5 and not S.ready and S.nextCursor==nil)
C.nowMs=originalClock
print("PASS shop transport: atomic replacement, stale chunk rejection, cursor reset and reconnect isolation")
GodSystemShopListingStore=nil -- scale checks below exercise the catalogue builder independently

for _,size in ipairs({100,500,2000,5000}) do
    GodSystemConfig.ShopItems = {}
    for i = 1, size do GodSystemConfig.ShopItems[i] = { id = "item" .. i } end
    C.clear(); local before = availabilityChecks
    C.ensure()
    assert(availabilityChecks == before, "opening must not synchronously validate any records")
    local steps = 0
    while C.isBuilding() do
        local previous = availabilityChecks
        C.step(50,999); steps = steps + 1
        assert(availabilityChecks - previous <= 50)
        assert(steps < 10000)
    end
    assert(#C.view("all", "") == size)
    before = availabilityChecks
    for i=1,100 do C.view("all", "") end
    assert(availabilityChecks == before, "100 cached page accesses must perform no validation")
    print("PASS shop scale: " .. size .. " listings, " .. steps .. " bounded steps, 100 cached accesses without validation")
end
