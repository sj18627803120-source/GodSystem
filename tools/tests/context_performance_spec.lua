-- Real Lua modules, isolated PZ/Java boundaries. This is not a B42 game test.
local passed = 0
local function eq(actual, expected, message)
    assert(actual == expected, (message or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, fn)
    local started = os.clock()
    fn()
    passed = passed + 1
    print(string.format("PASS %s (%.2f ms)", name, (os.clock() - started) * 1000))
end
local function noop() end
local function load(e, path)
    local chunk = assert(loadstring(readSource(path), "@" .. path))
    setfenv(chunk, e)
    return chunk()
end
local function event()
    local callbacks = {}
    return { Add = function(f) callbacks[f] = true end, Remove = function(f) callbacks[f] = nil end,
        fire = function(...) for f in pairs(callbacks) do f(...) end end }
end
local function environment()
    local e = setmetatable({}, { __index = _G })
    e._G = e
    e.require = noop
    e.Events = setmetatable({}, { __index = function(t, k) local v = event(); t[k] = v; return v end })
    e.clock, e.clockStep = 0, 0
    e.getTimestampMs = function() e.clock = e.clock + e.clockStep; return e.clock end
    e.isClient = function() return e.mp == true end
    e.isServer = function() return true end
    e.getSpecificPlayer = function() return e.player end
    e.getPlayer = e.getSpecificPlayer
    e.instanceof = function(v, name) return type(v) == "table" and v.kind == name end
    e.data = { stats = {}, unlockedShopItems = {} }
    e.features = {}
    e.calls = { ids = 0, types = 0, sprites = 0, scans = 0, configured = 0, classification = 0, prices = 0, notify = 0 }
    local runtime = {
        text = function(_, fallback) return fallback end,
        isFeatureEnabled = function(key) return e.features[key] ~= false end,
        getData = function() return e.data end,
        notify = function(message) e.calls.notify = e.calls.notify + 1; e.lastMessage = message end,
        getConfiguredShopKeySet = function() e.calls.configured = e.calls.configured + 1; return {} end,
        canContextRecycleItem = function(item)
            e.calls.classification = e.calls.classification + 1
            return not item.protected, item.protected and "protected" or nil
        end,
        canContextListItem = function(item) return not item.listed, item.listed and "alreadyListed" or nil end,
        getItemSellPrice = function(_, item) e.calls.prices = e.calls.prices + 1; return item.price or 3 end,
        getAutoShopListOnlyCost = function(_, sell) return sell * 2 end,
    }
    e.runtime = runtime
    e.GodSystemApp = { services = { runtime = runtime } }
    e.GodSystemApp.getService = function(name) return e.GodSystemApp.services[name] end
    e.GodSystemApp.createService = function(name)
        local s = { publish = noop }
        function s:setViewModelProvider(fn) self.getViewModel = function(_, n) return fn(n) end end
        function s:setExecutor(fn) self.execute = function(_, ...) return fn(...) end end
        e.GodSystemApp.services[name] = s
        return s
    end
    e.GodSystemRuntimeConfig = { Current = {}, isFeatureEnabled = runtime.isFeatureEnabled, get = function(_, fallback) return fallback end }
    e.GodSystemItemConfig = { Current = { economyRevision = 1 } }
    e.GodSystemNetwork = { isStateReady = function() return e.networkReady ~= false end, send = function() error("unexpected menu network request") end }
    e.ISInventoryPaneContextMenu = { addToolTip = function() return {} end }
    e.ISToolTip = { new = function() return { initialise = noop, setVisible = noop, setName = noop } end }
    load(e, "shared/GodSystem_Scheduler.lua")
    load(e, "shared/GodSystem_B42JavaCalls.lua")
    load(e, "shared/GodSystem_ShopVariants.lua")
    load(e, "shared/GodSystem_InventoryIndex.lua")
    load(e, "client/GodSystem_InventoryContext.lua")
    return e
end
local function container(e)
    local c = { rows = {} }
    c.list = { size = function() return #c.rows end, get = function(_, i) return c.rows[i + 1] end }
    function c:getItems() e.calls.scans = e.calls.scans + 1; return self.list end
    function c:AddItem(item) self.rows[#self.rows + 1] = item; item.source = self; return item end
    function c:contains(item) for _, v in ipairs(self.rows) do if v == item then return true end end; return false end
    function c:Remove(item)
        if item.failDelete then return end
        for i, v in ipairs(self.rows) do if v == item then table.remove(self.rows, i); item.source = nil; return end end
    end
    return c
end
local function item(e, id, source, fullType, sprite)
    local v = { kind = "InventoryItem", id = id, fullType = fullType or "Base.Nails", sprite = sprite }
    function v:getID() e.calls.ids = e.calls.ids + 1; return self.id end
    function v:getFullType() e.calls.types = e.calls.types + 1; return self.fullType end
    function v:getWorldSprite() e.calls.sprites = e.calls.sprites + 1; return self.sprite end
    function v:getContainer() return self.source end
    function v:getInventory() return self.inventory end
    function v:getDisplayName() return self.fullType end
    source:AddItem(v)
    return v
end
local function selection(e, count)
    local inv = container(e)
    local player = { getInventory = function() return inv end, getPlayerNum = function() return 0 end,
        isDead = function() return false end, getVehicle = function() return e.vehicle end }
    e.player, e.inventory = player, inv
    local values = {}
    for i = 1, count do values[i] = item(e, i, inv) end
    return values, e.GodSystemInventoryContext.createSnapshot(0, values)
end
local function menu()
    local c = { options = {} }
    function c:addOption(label, target, fn, arg)
        local option = { label = label, target = target, fn = fn, arg = arg }
        self.options[#self.options + 1] = option
        return option
    end
    return c
end
local function preparation(e)
    load(e, "client/GodSystem_ContextContent.lua")
    load(e, "client/GodSystem_RecyclePreparation.lua")
    load(e, "client/GodSystem_RecycleContext.lua")
    return e.GodSystemRecyclePreparation
end
local function drain(prep, job, target)
    local frames, maxSteps = 0, 0
    while job.status ~= target and (job.status == "analyzing" or job.status == "verifying") do
        maxSteps = math.max(maxSteps, prep.step(job)); frames = frames + 1
        assert(frames < 20000, "preparation stuck")
    end
    eq(job.status, target, job.reason)
    assert(maxSteps <= 64, "frame item budget exceeded")
    return frames
end

test("selection 1/200/201/1000/10000: immutable refs, lazy identity, threshold", function()
    for _, n in ipairs({1, 200, 201, 1000, 10000}) do
        local e = environment()
        local values, snapshot = selection(e, n)
        eq(#snapshot.items, n); eq(snapshot.bulk, n > 200)
        eq(e.calls.ids, 0); eq(e.calls.sprites, 0); eq(e.calls.types, n)
        local selected = snapshot.items[1]; values[1] = nil
        eq(snapshot.items[1], selected)
        local stacked = e.GodSystemInventoryContext.createSnapshot(0, { selected, { items = snapshot.items }, selected })
        eq(#stacked.items, n)
        e.GodSystemInventoryContext.getEntries(snapshot)
        eq(e.calls.ids, n); eq(e.calls.sprites, n)
        e.GodSystemInventoryContext.getEntries(snapshot)
        eq(e.calls.ids, n)
    end
end)

test("bulk menus: no classification, prices, IDs, file/network or unselected inventory scans", function()
    local e = environment(); local values, snapshot = selection(e, 10000); preparation(e)
    e.GodSystemApp.services.rangeRecycle = { getContextMenuState = function() return { enabled = true, ready = false } end }
    local c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot)
    eq(#c.options, 4); eq(c.options[4].notAvailable, true)
    eq(e.calls.ids, 0); eq(e.calls.scans, 0); eq(e.calls.classification, 0); eq(e.calls.prices, 0); eq(e.calls.configured, 0)
    e.features.EnableShop = false; c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot); eq(#c.options, 2)
    e.features.EnableRecycle = false; c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot); eq(#c.options, 0)
    e.features.EnableRecycle = true; e.mp = true; e.networkReady = false
    c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot); eq(c.options[1].notAvailable, true)
end)

test("small menus retain counts and ordinary recycle has no new confirmation", function()
    local e = environment(); local values, snapshot = selection(e, 200); preparation(e)
    values[1].fullType, values[1].protected = "Base.Protected", true
    snapshot = e.GodSystemInventoryContext.createSnapshot(0, values)
    local c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot)
    eq(#c.options, 3); eq(#c.options[1].target.items, 199)
    eq(e.calls.classification, 2); eq(e.calls.prices, 0); eq(e.calls.scans, 0)
    local executed = 0
    e.GodSystemRecycleContext.queueTransfers = function(payload) executed = executed + #payload.items; return true end
    eq(c.options[1].fn(c.options[1].target, c.options[1].arg), true); eq(executed, 199)
end)

test("world menu: ground skips module lookup; vehicle without module is grey", function()
    local e = environment(); selection(e, 1); e.module = false
    local searches = 0
    e.inventory.getFirstTypeRecurse = function() searches = searches + 1; return e.module end
    e.GodSystemMaintenance = { vehicleDamageSummary = function() return { damaged = e.damaged or 2 } end }
    load(e, "client/GodSystem_VehicleRepairContext.lua")
    local c = menu(); e.GodSystemVehicleRepairContext.fillWorldMenu(0, c, {}); eq(searches, 0); eq(#c.options, 0)
    e.vehicle = {}; c = menu(); e.GodSystemVehicleRepairContext.fillWorldMenu(0, c, {}); eq(searches, 1); eq(c.options[1].notAvailable, true)
    e.module = {}; c = menu(); e.GodSystemVehicleRepairContext.fillWorldMenu(0, c, {}); eq(c.options[1].notAvailable, nil)
    e.damaged = 0; c = menu(); e.GodSystemVehicleRepairContext.fillWorldMenu(0, c, {}); eq(c.options[1].notAvailable, true)
end)

test("ID index: single traversal, nested inventory, ambiguous IDs fail closed", function()
    local e = environment(); local values = selection(e, 10000)
    values[1].inventory = container(e); local nested = item(e, 10001, values[1].inventory)
    local index = e.GodSystemInventoryIndex.build(e.inventory)
    eq(index.itemsVisited, 10001); eq(index.containersVisited, 2); eq(e.calls.scans, 2)
    for i = 1, 10000 do eq(e.GodSystemInventoryIndex.find(index, i), values[i]) end
    eq(e.GodSystemInventoryIndex.find(index, 10001), nested); eq(e.calls.scans, 2)
    item(e, 10001, e.inventory)
    eq(e.GodSystemInventoryIndex.find(e.GodSystemInventoryIndex.build(e.inventory), 10001), nil)
end)

test("range list 20000: cached reads, edit/import/ack and session isolation", function()
    local e = environment(); selection(e, 1)
    load(e, "shared/GodSystem_RangeFilter.lua")
    local normalizations, loads = 0, 0
    local normalize = e.GodSystemRangeFilter.normalize
    e.GodSystemRangeFilter.normalize = function(...) normalizations = normalizations + 1; return normalize(...) end
    local types = {}; for i = 1, 20000 do types[i] = "Base.Type" .. i end
    e.GodSystemRangeFilterProfile = { load = function() loads = loads + 1; return normalize({ activeFullTypes = types }), true end, save = function() return true end }
    load(e, "client/GodSystem_RangeRecycleService.lua")
    local service = e.GodSystemApp.services.rangeRecycle
    eq(service:getContextMenuState(0).ready, false); eq(loads, 0)
    service:getViewModel(0)
    local view = service:getContextMenuState(0); eq(view.ready, true); eq(view.members["Base.Type20000"], true)
    local before = normalizations
    for i = 1, 1000 do eq(service:getContextMenuState(0).token, view.token) end
    eq(normalizations, before); eq(loads, 1)
    service:execute(0, "filterDelta", { baseRevision = view.revision, op = "removeMany", fullTypes = { "Base.Type20000" } })
    view = service:getContextMenuState(0); eq(view.members["Base.Type20000"], nil)
    service:execute(0, "filterReplace", { state = { mode = "denylist", activeFullTypes = { "Base.New" } } })
    view = service:getContextMenuState(0); eq(view.members["Base.New"], true); eq(view.mode, "denylist")
    service:handleFilterAck({ mode = "allowlist", activeFullTypes = {} }, true)
    eq(service:getContextMenuState(0).members["Base.New"], nil)
    service:resetSession(); eq(service:getContextMenuState(0).ready, false); eq(loads, 1)
    service:getViewModel(0); eq(loads, 2)
    e.player = {}; eq(service:getContextMenuState(0).ready, false)
end)

test("batch preparation 201/1000/10000: budgets, no side effects until confirmed", function()
    for _, n in ipairs({201, 1000, 10000}) do
        local e = environment(); local _, snapshot = selection(e, n); local prep = preparation(e)
        local executed = 0
        local job = prep.start(snapshot, "recycle", { execute = function(j) executed = executed + #j.items end })
        local frames = drain(prep, job, "ready"); eq(executed, 0); eq(#job.items, n)
        eq(e.calls.classification, 2); eq(e.calls.prices, 0)
        assert(prep.confirm(job)); drain(prep, job, "completed"); eq(executed, n)
        eq(prep.confirm(job), false); eq(executed, n)
        print(string.format("  selected=%d preparationFrames=%d steps=%d", n, frames, job.steps))
    end
    local e = environment(); local _, snapshot = selection(e, 201); local prep = preparation(e)
    e.clockStep = 1
    local job = prep.start(snapshot, "recycle", {}); assert(prep.step(job) <= 2, "time budget ignored")
end)

test("cancel/replacement/player/config/move/delete and price changes invalidate preparation", function()
    for _, cause in ipairs({ "cancel", "replace", "player", "config", "move", "delete", "price", "disconnect" }) do
        local e = environment(); local values, snapshot = selection(e, 201); local prep = preparation(e)
        local executed = 0
        local job = prep.start(snapshot, cause == "price" and "listOnly" or "recycle", { execute = function() executed = executed + 1 end })
        prep.step(job)
        if cause == "cancel" then prep.cancel(job)
        elseif cause == "replace" then prep.start(snapshot, "recycle", {})
        elseif cause == "player" then e.player = nil
        elseif cause == "config" then e.GodSystemItemConfig.Current.economyRevision = 2
        elseif cause == "move" then values[1].source = container(e)
        elseif cause == "delete" then e.inventory:Remove(values[1])
        elseif cause == "price" then values[1].price = 99
        elseif cause == "disconnect" then e.Events.OnDisconnect.fire() end
        for i = 1, 30 do prep.step(job) end
        assert(job.status == "cancelled" or job.status == "failed", cause .. " did not invalidate")
        eq(executed, 0)
    end
end)

test("incremental content signature matches original; equal-size content replacement invalidates", function()
    local e = environment(); local values, snapshot = selection(e, 201); local prep = preparation(e)
    load(e, "client/GodSystem_ClientRuntime_Foundation.lua")
    -- Installer only defines functions; its getData is not used by this fixture.
    local cachedGetData = e.runtime.getData
    e.GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Foundation(e)
    e.runtime.getData = cachedGetData
    values[1].inventory = container(e)
    for i = 1, 70 do item(e, 1000 + i, values[1].inventory, "Base.Content" .. (i % 7)) end
    local child = values[1].inventory.rows[1]; child.inventory = container(e); item(e, 9000, child.inventory)
    local reader = e.GodSystemContextContent.new(values[1]); local count = 0
    while not reader:step() do count = count + 1; assert(count < 10000) end
    eq(reader.signature, e.runtime.getContextContainerSignature(values[1]))
    local job = prep.start(snapshot, "recycle", {})
    drain(prep, job, "ready"); eq(job.hasContents, true); eq(job.containerContentSignatures["1"], reader.signature)
    values[1].inventory:Remove(values[1].inventory.rows[2]); item(e, 9999, values[1].inventory)
    prep.confirm(job)
    for i = 1, 100 do prep.step(job) end
    eq(job.status, "failed")
end)

test("furniture variants: separate listing fees, same variant counted once", function()
    local e = environment(); local values = selection(e, 201); local prep = preparation(e)
    for i = 1, 201 do values[i].fullType = "Moveables.Moveable"; values[i].sprite = i % 2 == 0 and "tile_a" or "tile_b" end
    local snapshot = e.GodSystemInventoryContext.createSnapshot(0, values)
    local job = prep.start(snapshot, "listOnly", {})
    drain(prep, job, "ready"); eq(job.typeCount, 2); eq(job.cost, 12); eq(e.calls.prices, 4)
end)

test("shop pagination: 101/121 listings expose page 6/7 without a fixed cap", function()
    for _, n in ipairs({101, 121}) do
        local e = environment(); e.GodSystemWindow = {}; e.GodSystemConfig = { ShopItems = {} }
        load(e, "client/GodSystem_UI_Runtime_Pages.lua"); e.GodSystemUIRuntimeInstallers.GodSystem_UI_Runtime_Pages(e)
        local listings = {}; for i = 1, n do listings[i] = { fullType = "Base.Item" .. i, id = i } end
        e.runtime.getUnlockedShopItemsList = function() return listings end
        e.runtime.getShopPrimaryCategory = function() return { key = "all", label = "All" } end
        local rows = {}; for i = 1, #listings do rows[i] = { item = listings[i], key = tostring(listings[i].id), category = { key = "all", label = "All" }, favoriteRank = 0, order = i } end
        e.GodSystemShopCatalog = {
            view = function() return rows end,
            price = function() return 1 end,
            snapshot = { categories = {} },
        }
        e.runtime.getShopLabel = function(v) return v.fullType end
        e.runtime.getShopItemUnitPrice = function() return 1 end
        e.gsSetButtonTitle, e.gsIsMultiplayer = noop, function() return false end
        local window = setmetatable({ shopPage = math.ceil(n / 20), shopCategoryKey = "all", rows = {} }, { __index = e.GodSystemWindow })
        for _, name in ipairs({ "primary", "secondary", "third", "fourth", "fifth", "sixth" }) do window[name .. "Button"] = { setVisible = noop } end
        window.syncSearchBoxText, window.updateShopCategoryButton, window.applyShopActionLayout = noop, noop, noop
        window.shopItemMatchesSearch = function() return true end
        window.addListItem = function(self, label, payload) self.rows[#self.rows + 1] = { label = label, payload = payload } end
        window:populateShop()
        eq(#window.rows, 2); eq(window.rows[2].payload.data.id, n); eq(window.shopPage, math.ceil(n / 20))
        assert(window.rows[1].label:find(tostring(window.shopPage) .. "/" .. tostring(window.shopPage), 1, true))
    end
end)

local function transactionFixture(mp, count)
    local e = environment(); local values = selection(e, count)
    load(e, "shared/GodSystem_ManualRecycle.lua")
    e.GodSystemConfig = { AutoUnlockShopFromRecycle = true }
    load(e, "client/GodSystem_ClientRuntime_Foundation.lua")
    local getData = e.runtime.getData
    e.GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Foundation(e)
    e.runtime.getData, e.gsPlayer = getData, e.getPlayer
    load(e, "client/GodSystem_ClientRuntime_Recycle.lua")
    e.GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Recycle(e)
    e.runtime.getContextRecycleValue = function() return 3 end
    e.runtime.isAutoShopUnlockAllowed = function() return true end
    e.GodSystemItemConfig.getShopVariantMode = function() return "default" end
    e.runtime.calculateRecyclePayout = function(_, raw) return raw end
    e.runtime.applyRecycleDailyPayout = function(raw) e.data.recycleLimitUsed = 999; return raw end
    e.data.recycleLimitUsed = 7
    e.runtime.save = noop
    e.gsAppendHistory = noop
    e.gsFormatText = function(v) return v end
    e.runtime.containerContainsItem = function(c, v) return c:contains(v) end
    e.player.primary = values[1]
    e.player.getPrimaryHandItem = function(self) return self.primary end
    e.player.getSecondaryHandItem = function() return nil end
    e.player.setPrimaryHandItem = function(self, v) self.primary = v end
    e.player.getWornItems = function() return { contains = function() return false end } end
    e.player.getAttachedItems = e.player.getWornItems
    e.balance, e.payoutCalls, e.paid, e.refunded = 0, 0, 0, 0
    e.runtime.giveCurrency = function(amount)
        e.payoutCalls = e.payoutCalls + 1
        if e.failPayout then return false end
        e.balance = e.balance + amount; return true
    end
    e.runtime.spendCurrency = function(amount) e.paid = e.paid + amount; return true, amount - 2, 2 end
    e.runtime.refundCurrencySources = function(bank, cash) e.refunded = e.refunded + bank + cash; e.refundBank, e.refundCash = bank, cash end
    e.runtime.unlockAutoShopItem = function(fullType, _, _, v, configured)
        assert(configured, "transaction configured set not reused")
        if v.failList then return false end
        e.data.unlockedShopItems[e.GodSystemShopVariants.getKey(fullType, v)] = {}; return true
    end
    local originalIndex = e.GodSystemInventoryIndex.build
    e.indexBuilds, e.indexMs, e.nativeDeleteMs = 0, 0, 0
    e.GodSystemInventoryIndex.build = function(c)
        local start = os.clock(); local index = originalIndex(c)
        e.indexBuilds = e.indexBuilds + 1; e.indexMs = e.indexMs + (os.clock() - start) * 1000
        e.lastIndex = index; return index
    end
    local originalRemove = e.inventory.Remove
    e.inventory.Remove = function(c, v)
        local start = os.clock(); originalRemove(c, v); e.nativeDeleteMs = e.nativeDeleteMs + (os.clock() - start) * 1000
    end
    if mp then
        e.Commands = {}; e.root = {}; e.mp = true
        e.GodSystemServer = { getConfiguredShopKeySet = e.runtime.getConfiguredShopKeySet,
            refundCurrencySources = function(_, _, b, c) e.runtime.refundCurrencySources(b, c) end }
        e.playerData, e.store, e.userKey = getData, function() return e.root end, function() return "player" end
        e.guard, e.unguard, e.storeCheckpoint = function() return true end, noop, function() return true end
        e.finishCode = function(_, ok, code, _, payload) e.result = { ok = ok, code = code, payload = payload }; return e.result end
        e.errorMessage = function(_, message) error(message) end
        e.floor = function(n, fallback) return math.floor(tonumber(n) or fallback or 0) end
        e.canContextRecycleItem = e.runtime.canContextRecycleItem
        e.canContextListItem = function(data, v, keys) return e.runtime.canContextListItem(v, { data = data, configuredShopKeySet = keys }) end
        e.itemInventoryCount = e.gsItemInventoryCount
        e.GodSystemServerContainerContentSignature = e.runtime.getContextContainerSignature
        e.recycleValue = e.runtime.getContextRecycleValue
        e.calculateRecyclePayout = e.runtime.calculateRecyclePayout
        e.applyRecycleDailyPayout = function(_, raw) return e.runtime.applyRecycleDailyPayout(raw) end
        e.giveCurrency = function(_, amount) return e.runtime.giveCurrency(amount) end
        e.GodSystemServerContainerContainsItem = e.runtime.containerContainsItem
        e.removeItemFromContainer = function(c, v) c:Remove(v); return not c:contains(v) end
        e.markInventoryDirty, e.appendHistory, e.historyEntry, e.applyRuntimeStores = noop, noop, noop, noop
        e.itemSellPrice, e.autoShopListOnlyCost = e.runtime.getItemSellPrice, e.runtime.getAutoShopListOnlyCost
        e.spendCurrency = function(_, _, amount) return e.runtime.spendCurrency(amount) end
        e.unlockAutoShopItem = function(_, ...) return e.runtime.unlockAutoShopItem(...) end
        load(e, "shared/GodSystem_RecycleFingerprint.lua")
        load(e, "server/GodSystem_TransactionOps.lua")
        load(e, "server/GodSystem_ServerRuntime_Commerce.lua")
        e.GodSystemServerRuntimeInstallers.GodSystem_ServerRuntime_Commerce(e)
    end
    e.run = function(mode, ids, extra)
        if mp then
            local args = extra or {}; args.mode, args.itemIds, args.opId = mode, ids, args.opId or "gs-1-2-3"
            e.Commands.recycle(nil, nil, e.player, args)
            return e.result.ok
        end
        local a = extra or {}
        return e.runtime.recycleSelectedItems(mode, ids, a.allowDestroyContents, a.containerContentSignatures, 0)
    end
    return e, values
end

test("SP/MP actual batch handlers: one index, one payout, duplicate selection deduped", function()
    for _, count in ipairs({1000, 10000}) do
    for _, mp in ipairs({false, true}) do
        local e, values = transactionFixture(mp, count)
        local ids = {}; for i = 1, count do ids[i] = tostring(i) end; ids[count + 1] = "1"
        local start = os.clock()
        eq(e.run("recycle", ids), true)
        eq(e.indexBuilds, 1); eq(e.lastIndex.itemsVisited, count); eq(e.lastIndex.containersVisited, 1)
        eq(e.calls.configured, 1); eq(e.balance, count * 3); eq(e.payoutCalls, 1); eq(#e.inventory.rows, 0)
        print(string.format("  %s items=%d index=%.2fms nativeDeleteMock=%.2fms transaction=%.2fms", mp and "MP" or "SP", count, e.indexMs, e.nativeDeleteMs, (os.clock() - start) * 1000))
        if mp then
            eq(e.run("recycle", ids), true); eq(e.payoutCalls, 1); eq(e.indexBuilds, 1)
            eq(e.run("listOnly", ids), false); eq(e.result.code, "TransactionOperationInvalid"); eq(e.paid, 0)
        end
    end
    end
end)

test("SP/MP deletion or currency failure restores items/equipment/daily limit", function()
    for _, mp in ipairs({false, true}) do
        for _, failure in ipairs({ "delete", "payout", "missing", "contents" }) do
            local e, values = transactionFixture(mp, 3)
            local ids = { "1", "2", "3" }
            if failure == "delete" then values[2].failDelete = true
            elseif failure == "payout" then e.failPayout = true
            elseif failure == "missing" then ids[3] = "999"
            elseif failure == "contents" then values[1].inventory = container(e); item(e, 99, values[1].inventory) end
            eq(e.run("recycle", ids), false, failure)
            eq(e.balance, 0); eq(#e.inventory.rows, 3); eq(e.player.primary, values[1]); eq(e.data.recycleLimitUsed, 7)
            for _, v in ipairs(values) do eq(e.inventory:contains(v), true) end
            if mp then
                local attempts = e.payoutCalls; eq(e.run("recycle", ids), false); eq(e.payoutCalls, attempts); eq(#e.inventory.rows, 3)
            end
        end
    end
end)

test("SP/MP list-only failure refunds original sources and removes partial listing", function()
    for _, mp in ipairs({false, true}) do
        local e, values = transactionFixture(mp, 3)
        values[2].fullType, values[2].failList = "Base.Other", true
        eq(e.run("listOnly", { "1", "2", "3" }), false)
        eq(e.paid, 12); eq(e.refunded, 12); eq(e.refundBank, 10); eq(e.refundCash, 2)
        eq(e.data.unlockedShopItems["Base.Nails"], nil); eq(#e.inventory.rows, 3); eq(e.payoutCalls, 0)
        if mp then eq(e.run("listOnly", { "1", "2", "3" }), false); eq(e.paid, 12); eq(e.refunded, 12) end
    end
end)

test("client transfer completion resolves actual item references with a fresh index", function()
    local e = environment(); local values = selection(e, 201); preparation(e)
    local calls = 0; e.runtime.recycleSelectedItems = function() calls = calls + 1; return true end
    eq(e.GodSystemRecycleContext.execute({ playerNum = 0, items = values, mode = "recycle" }), true)
    eq(calls, 1); eq(e.calls.scans, 1)
    e.inventory:Remove(values[1]); item(e, 1, e.inventory)
    eq(e.GodSystemRecycleContext.execute({ playerNum = 0, items = values, mode = "recycle" }), false)
    eq(calls, 1); eq(e.calls.scans, 2)
end)

test("ordinary recycle count does not include listing-only skips", function()
    local e = environment(); local values, snapshot = selection(e, 1); preparation(e)
    values[1].listed = true
    local c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot)
    eq(c.options[1].target.skippedCount, 0); eq(c.options[2].target.skippedCount, 1)
    eq(c.options[3].notAvailable, true)
end)

test("repair/loader/lottery menus use selected types and shallow ownership only", function()
    local e = environment(); local values = selection(e, 1)
    e.GodSystemAutoLoader = { FullType = "GodSystem.SystemAutoLoader" }
    e.GodSystemAutoLoaderClient = {}; e.GodSystemAutoLoaderUI = {}
    e.GodSystemLottery = { isTicket = function(t) return t == "GodSystem.Ticket" end }
    load(e, "shared/GodSystem_Maintenance.lua")
    load(e, "client/GodSystem_MaintenanceContext.lua")
    load(e, "client/GodSystem_AutoLoaderContext.lua")
    load(e, "client/GodSystem_LotteryContext.lua")
    e.player.getPrimaryHandItem = function() return e.held end
    e.ISContextMenu = { getNew = function() return menu() end }
    local function context() local c = menu(); c.addSubMenu = noop; return c end
    local handlers = { e.GodSystemMaintenanceContext, e.GodSystemAutoLoaderContext, e.GodSystemLotteryContext }
    for _, h in ipairs(handlers) do
        local c = context(); h.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(#c.options, 0)
    end
    values[1].fullType = e.GodSystemMaintenance.RepairItemType
    local c = context(); e.GodSystemMaintenanceContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(#c.options, 1); eq(c.options[1].notAvailable, true)
    e.held = item(e, 2, e.inventory, "Base.Hammer")
    e.held.getCondition = function() return 5 end; e.held.getConditionMax = function() return 10 end
    c = context(); e.GodSystemMaintenanceContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(c.options[1].notAvailable, nil)
    values[1].fullType = e.GodSystemAutoLoader.FullType
    c = context(); e.GodSystemAutoLoaderContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(#c.options, 1)
    values[1].source = container(e)
    c = context(); e.GodSystemAutoLoaderContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(c.options[1].notAvailable, true)
    values[1].fullType = "GodSystem.Ticket"
    c = context(); e.GodSystemLotteryContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(c.options[1].notAvailable, true)
    values[1].source = e.inventory
    c = context(); e.GodSystemLotteryContext.fillInventoryMenu(0, c, e.GodSystemInventoryContext.createSnapshot(0, values)); eq(c.options[1].notAvailable, nil)
    eq(e.calls.scans, 0); eq(e.calls.ids, 0); eq(e.calls.sprites, 0)
end)

test("bulk range list: sorted 256-type cap and ready-token invalidation", function()
    local e = environment(); local values = selection(e, 1000); local prep = preparation(e)
    for i = 1, 1000 do values[i].fullType = string.format("Base.T%04d", 1001 - i) end
    local snapshot = e.GodSystemInventoryContext.createSnapshot(0, values)
    local state = { enabled = true, ready = true, members = { ["Base.T0001"] = true }, token = {}, mode = "allowlist" }
    e.GodSystemApp.services.rangeRecycle = { getContextMenuState = function()
        return { enabled = state.enabled, ready = state.ready, members = state.members, token = state.token, mode = state.mode }
    end }
    local job = prep.start(snapshot, "rangeFilter", {})
    drain(prep, job, "ready"); eq(#job.rangeTypes, 256); eq(job.rangeTypes[1], "Base.T0002"); eq(job.rangeTypes[256], "Base.T0257"); eq(job.rangeSkipped, 744)
    state.token = {}; prep.step(job); eq(job.status, "failed")
end)

test("preparation window callbacks: progress, cancel, confirm and close", function()
    local e = environment(); local _, snapshot = selection(e, 201); local prep = preparation(e)
    local base = {}
    function base:derive() return setmetatable({}, { __index = self }) end
    function base:new() return setmetatable({}, { __index = self }) end
    base.createChildren, base.addChild, base.addToUIManager, base.setVisible, base.setAlwaysOnTop, base.bringToTop = noop, noop, noop, noop, noop, noop
    base.initialise = function(self) self:createChildren() end
    base.close = function(self) self.closed = true end
    e.ISCollapsableWindow = base
    e.ISLabel = { new = function(_, _, _, _, name) return { name = name, initialise = noop } end }
    e.ISButton = { new = function(_, _, _, _, _, title, target, fn) return { title = title, target = target, fn = fn, initialise = noop } end }
    e.UIFont = { Small = 1 }; e.getCore = function() return { getScreenWidth = function() return 1280 end, getScreenHeight = function() return 720 end } end
    load(e, "client/GodSystem_RecyclePreparationUI.lua")
    local executed = 0; e.GodSystemRecycleContext.queueTransfers = function() executed = executed + 1; return true end
    eq(e.GodSystemRecycleContext.startBulk({ snapshot = snapshot }, "recycle"), true)
    local job = prep.active["0"]; local window = job.window
    eq(window.confirmButton.enable, false); drain(prep, job, "ready"); eq(window.confirmButton.enable, true)
    window:onAction(window.confirmButton); eq(window.confirmButton.enable, false); drain(prep, job, "completed")
    eq(executed, 1); eq(window.closed, true); eq(job.window, nil)
    e.GodSystemRecycleContext.startBulk({ snapshot = snapshot }, "recycle"); job = prep.active["0"]; window = job.window
    window:close(); eq(job.status, "cancelled"); eq(window.closed, true); eq(executed, 1)
end)

test("unselected inventory size does not affect menu scans", function()
    for _, count in ipairs({1, 10000}) do
        local e = environment(); local values = selection(e, count); preparation(e)
        local snapshot = e.GodSystemInventoryContext.createSnapshot(0, { values[1] })
        e.calls.types = 0
        local c = menu(); e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot)
        eq(e.calls.scans, 0); eq(e.calls.ids, 1); eq(e.calls.types, 0); eq(e.calls.classification, 1)
    end
end)

test("nested container replacement is detected even when signatures would match", function()
    local e = environment(); local values, snapshot = selection(e, 201); local prep = preparation(e)
    values[1].inventory = container(e)
    local child = item(e, 9000, values[1].inventory); child.inventory = container(e)
    local job = prep.start(snapshot, "recycle", {})
    drain(prep, job, "ready"); child.inventory = container(e)
    prep.confirm(job); for i = 1, 50 do prep.step(job) end; eq(job.status, "failed")
end)

test("MP range edit is unavailable until acknowledgement, reconnect resets readiness", function()
    local e = environment(); selection(e, 1); e.mp = true
    load(e, "shared/GodSystem_RangeFilter.lua")
    e.GodSystemRangeFilterProfile = { load = function() return e.GodSystemRangeFilter.normalize({}), true end, save = function() return true end }
    e.GodSystemNetwork.send = function() return true end
    load(e, "client/GodSystem_RangeRecycleService.lua")
    local service = e.GodSystemApp.services.rangeRecycle
    service:getViewModel(0); eq(service:getContextMenuState(0).ready, false)
    service:handleFilterAck({ activeFullTypes = {}, revision = 1 }, true)
    service:execute(0, "filterDelta", { baseRevision = 1, op = "addMany", fullTypes = { "Base.New" } })
    eq(service:getContextMenuState(0).ready, false)
    service:handleFilterAck({ activeFullTypes = { "Base.New" }, revision = 2 }, true)
    eq(service:getContextMenuState(0).ready, true)
    e.Events.OnDisconnect.fire(); eq(service:getContextMenuState(0).ready, false)
end)

test("multiple local players share the per-frame 64-entry budget", function()
    local e = environment(); local values, snapshot = selection(e, 201); local prep = preparation(e)
    local player0 = e.player
    local player1 = { getInventory = player0.getInventory, isDead = function() return false end }
    e.getSpecificPlayer = function(n) return n == 0 and player0 or n == 1 and player1 or nil end
    local one = prep.start(snapshot, "recycle", {})
    local two = prep.start(e.GodSystemInventoryContext.createSnapshot(1, values), "recycle", {})
    for i = 1, 4 do
        local before = (one.steps or 0) + (two.steps or 0)
        prep.onTick()
        assert(one.steps + two.steps - before <= 64)
    end
    assert(one.cursor > 1 and two.cursor > 1)
    prep.clear(); eq(one.status, "cancelled"); eq(two.status, "cancelled")
end)

test("range context menu swaps add for remove when types are already listed", function()
    local e = environment(); local values = selection(e, 3); preparation(e)
    local deltas = {}
    local state = {
        enabled = true, ready = true, revision = 1, token = {}, mode = "denylist",
        members = { ["Base.Nails"] = true },
    }
    e.GodSystemApp.services.rangeRecycle = {
        getContextMenuState = function()
            return {
                enabled = state.enabled, ready = state.ready, members = state.members,
                token = state.token, mode = state.mode, revision = state.revision,
            }
        end,
        execute = function(_, playerNum, intent, payload, callback)
            deltas[#deltas + 1] = { playerNum = playerNum, intent = intent, payload = payload }
            if callback then callback({ ok = true }) end
            return true
        end,
    }
    local function rangeOptions(snapshot)
        local c = menu()
        e.GodSystemRecycleContext.fillInventoryMenu(0, c, snapshot)
        local found = {}
        for i = 1, #c.options do
            local option = c.options[i]
            if option.fn == e.GodSystemRecycleContext.addToRangeFilter
                or option.fn == e.GodSystemRecycleContext.removeFromRangeFilter then
                found[#found + 1] = option
            end
        end
        return found
    end
    -- All selected types are already in the denylist: only a remove option.
    local options = rangeOptions(e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(#options, 1)
    eq(options[1].fn, e.GodSystemRecycleContext.removeFromRangeFilter)
    eq(options[1].label, "Remove from forbidden range recycle")
    eq(options[1].notAvailable, nil)
    eq(#options[1].target.existingTypes, 1)
    eq(options[1].target.existingTypes[1], "Base.Nails")
    options[1].fn(options[1].target)
    eq(deltas[1].intent, "filterDelta")
    eq(deltas[1].payload.op, "removeMany")
    eq(deltas[1].payload.baseRevision, 1)
    eq(deltas[1].payload.fullTypes[1], "Base.Nails")
    eq(e.lastMessage, "Removed 1 item types from the range list")

    -- Mixed selection: add (missing) and remove (existing) options together.
    values[2].fullType = "Base.New"
    options = rangeOptions(e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(#options, 2)
    eq(options[1].fn, e.GodSystemRecycleContext.addToRangeFilter)
    eq(options[1].label, "Add to forbidden range recycle (1/2)")
    eq(options[2].fn, e.GodSystemRecycleContext.removeFromRangeFilter)

    -- Allowlist mode: listed types get no context-menu option at all (no add,
    -- no remove) so a type can never be moved out of the allowed list by accident.
    state.mode = "allowlist"
    values[1].fullType, values[2].fullType, values[3].fullType = "Base.Nails", "Base.Nails", "Base.Nails"
    options = rangeOptions(e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(#options, 0)
    state.mode = "denylist"

    -- Nothing listed yet: only the add option, with no remove option.
    values[1].fullType, values[2].fullType, values[3].fullType = "Base.A", "Base.B", "Base.C"
    options = rangeOptions(e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(#options, 1)
    eq(options[1].fn, e.GodSystemRecycleContext.addToRangeFilter)
    eq(#options[1].target.fullTypes, 3)

    -- While the list is syncing, every range option is greyed.
    state.ready = false
    options = rangeOptions(e.GodSystemInventoryContext.createSnapshot(0, values))
    eq(options[1].notAvailable, true)
end)

print(string.format("Behavior specs passed: %d", passed))
