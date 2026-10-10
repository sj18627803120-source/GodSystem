require "GodSystem_Scheduler"
require "GodSystem_ContextContent"
require "GodSystem_InventoryContext"
require "GodSystem_ExternalRecycle"

GodSystemRecyclePreparation = GodSystemRecyclePreparation or {}
local Prep = GodSystemRecyclePreparation
Prep.active = Prep.active or {}
Prep.MAX_STEP_ITEMS = 64
Prep.BUDGET_MS = 2
Prep.sessionGeneration = Prep.sessionGeneration or 0
local tickInstalled = false

local function playerFor(num)
    if getSpecificPlayer then return getSpecificPlayer(num) end
    return getPlayer()
end

local function keyFor(num) return tostring(num or 0) end

function Prep.cancel(job, reason)
    if not job or Prep.active[keyFor(job.playerNum)] ~= job then return end
    Prep.active[keyFor(job.playerNum)] = nil
    job.status = reason and "failed" or "cancelled"
    job.reason = reason
    if job.callbacks.close then job.callbacks.close(job) end
    if reason and job.callbacks.failed then job.callbacks.failed(job, reason) end
end

local function beginVerify(job)
    job.status = "verifying"
    job.cursor = 1
    job.verifyCache = GodSystemRecycleContext.newAnalysis()
    job.verifyTypes, job.verifyCost = {}, 0
end

function Prep.confirm(job)
    if not job or Prep.active[keyFor(job.playerNum)] ~= job or job.status ~= "ready" then return false end
    job.confirmed = true
    beginVerify(job)
    if job.callbacks.progress then job.callbacks.progress(job) end
    return true
end

local function isCurrent(job)
    local runtime = GodSystemApp.services.runtime
    local player = playerFor(job.playerNum)
    if job.sessionGeneration ~= Prep.sessionGeneration or player ~= job.player or not player
        or (player.isDead and player:isDead()) then return false, "sessionChanged" end
    if isClient and isClient() and (not GodSystemNetwork or not GodSystemNetwork.isStateReady()) then return false, "sessionChanged" end
    local data = runtime.getData() -- may replace same-valued runtime configuration
    if not data then return false, "sessionChanged" end
    if not runtime.isFeatureEnabled("EnableRecycle") then return false, "disabled" end
    if job.mode ~= "recycle" and job.mode ~= "rangeFilter"
        and (not runtime.isFeatureEnabled("EnableShop") or not runtime.isFeatureEnabled("EnableRecycleListing")) then return false, "disabled" end
    if GodSystemRuntimeConfig.recyclePreparationToken(job.mode) ~= job.configToken
        or tonumber(GodSystemItemConfig.Current and GodSystemItemConfig.Current.economyRevision) ~= job.economyRevision
        or (job.catalogRevision ~= nil and tonumber(data.shopCatalogRevision or 0) ~= job.catalogRevision) then
        return false, "configChanged"
    end
    if job.range then
        local current = GodSystemApp.services.rangeRecycle:getContextMenuState(job.playerNum)
        if not current.enabled or not current.ready or current.token ~= job.range.token then return false, "configChanged" end
    end
    return true
end

local function verifyEntry(entry)
    local item = entry.item
    local sameLocation
    if entry.worldObject then
        local descriptor = GodSystemExternalRecycle.describe(item)
        sameLocation = item:getWorldItem() == entry.worldObject
            and entry.worldObject:getSquare() == entry.worldSquare
            and descriptor and descriptor.kind == "worldItem"
            and (not entry.externalSource or GodSystemExternalRecycle.sameSource(descriptor, entry.externalSource))
        if sameLocation and not entry.externalSource then entry.externalSource = descriptor end
    else
        sameLocation = entry.source and item:getContainer() == entry.source
    end
    if not (sameLocation and tostring(item:getID()) == entry.id and item:getFullType() == entry.fullType
        and GodSystemShopVariants.getWorldSprite(item) == entry.worldSprite) then return false, "changed" end
    local container = item.getInventory and item:getInventory() or nil
    if entry.inventoryChecked and container ~= entry.inventory then return false, "contentsChanged" end
    entry.inventory, entry.inventoryChecked = container, true
    return true
end

local function addRangeType(job, fullType)
    if job.rangeSeen[fullType] then return end
    job.rangeSeen[fullType] = true
    if job.range.members[fullType] then job.rangeSkipped = job.rangeSkipped + 1; return end
    -- Keep the same first 256 sorted types as the small-selection path, with bounded work.
    local types = job.rangeTypes
    local position = #types + 1
    while position > 1 and types[position - 1] > fullType do position = position - 1 end
    table.insert(types, position, fullType)
    if #types > 256 then table.remove(types); job.rangeSkipped = job.rangeSkipped + 1 end
end

local function processEntry(job)
    local Context = GodSystemRecycleContext
    local entry = GodSystemInventoryContext.getEntry(job.snapshot, job.cursor)
    if not entry or job.snapshot.invalid then return false, "identity" end
    local verified, failure = verifyEntry(entry)
    if not verified then return false, failure end
    local verifying = job.status == "verifying"
    local cache = verifying and job.verifyCache or job.cache
    local analysis = Context.analyzeItem(cache, entry.item, entry)
    local eligible, reason = Context.classifyItem(entry.item, job.mode == "rangeFilter" and "recycle" or job.mode, analysis)
    if verifying then
        local original = job.classifications[job.cursor]
        if original.eligible ~= eligible or original.reason ~= reason then return false, "configChanged" end
    else
        job.classifications[job.cursor] = { eligible = eligible, reason = reason }
        if not eligible or reason then job.skipped = job.skipped + 1 end
        if eligible then job.items[#job.items + 1] = entry.item end
    end
    if eligible and job.mode == "listOnly" then
        local types = verifying and job.verifyTypes or job.listTypes
        if not types[entry.variantKey] then
            types[entry.variantKey] = true
            local runtime = GodSystemApp.services.runtime
            local sell = runtime.getItemSellPrice(entry.fullType, entry.item)
            local cost = runtime.getAutoShopListOnlyCost(entry.fullType, sell)
            if verifying then job.verifyCost = job.verifyCost + cost
            else job.cost = job.cost + cost; job.typeCount = job.typeCount + 1 end
        end
    elseif eligible and job.mode == "rangeFilter" then
        if not verifying then addRangeType(job, entry.fullType) end
    elseif eligible and entry.inventory then
        if verifying then
            local reader = job.contents[entry.id]
            if not reader then return false, "contentsChanged" end
            reader:restartValidation()
            job.reader = reader
        else
            job.reader = GodSystemContextContent.new(entry.item)
            job.contents[entry.id] = job.reader
        end
        job.readerEntry = entry
    end
    if not job.reader then job.cursor = job.cursor + 1 end
    return true
end

local function finishPass(job)
    if job.status == "analyzing" then beginVerify(job); return end
    if job.mode == "listOnly" and job.verifyCost ~= job.cost then Prep.cancel(job, "configChanged"); return end
    if #job.items == 0 or (job.mode == "rangeFilter" and #job.rangeTypes == 0) then
        Prep.cancel(job, "empty")
    elseif job.confirmed then
        Prep.active[keyFor(job.playerNum)] = nil
        job.status = "completed"
        if job.callbacks.close then job.callbacks.close(job) end
        if job.callbacks.execute then
            local ok = pcall(job.callbacks.execute, job)
            if not ok and job.callbacks.failed then job.callbacks.failed(job, "submission") end
        end
    else
        job.status = "ready"
        if job.callbacks.ready then job.callbacks.ready(job) end
    end
end

function Prep.step(job, sliceLimit, frameStart)
    if Prep.active[keyFor(job.playerNum)] ~= job then return 0 end
    local start = frameStart or GodSystemScheduler.nowMs()
    sliceLimit = math.min(Prep.MAX_STEP_ITEMS, sliceLimit or Prep.MAX_STEP_ITEMS)
    local steps = 0
    local ok = pcall(function()
        local current, failure = isCurrent(job)
        if not current then Prep.cancel(job, failure); return end
        while job.status == "analyzing" or job.status == "verifying" do
            if steps >= sliceLimit or (steps > 0 and GodSystemScheduler.nowMs() - start >= Prep.BUDGET_MS) then break end
            steps = steps + 1
            if job.reader then
                local complete, readerFailure = job.reader:step()
                if readerFailure then Prep.cancel(job, readerFailure); break end
                if complete then
                    if job.status == "analyzing" and #job.reader.tokens > 0 then
                        job.containerContentSignatures[job.readerEntry.id] = job.reader.signature
                        job.hasContents = true
                    end
                    job.reader, job.readerEntry = nil, nil
                    job.cursor = job.cursor + 1
                end
            elseif job.cursor > #job.snapshot.items then finishPass(job)
            else
                local processed, reason = processEntry(job)
                if not processed then Prep.cancel(job, reason); break end
            end
        end
    end)
    job.maxSliceMs = math.max(job.maxSliceMs or 0, GodSystemScheduler.nowMs() - start)
    job.steps = (job.steps or 0) + steps
    if not ok then
        if GodSystemDiagnostics then GodSystemDiagnostics.issue(isClient and isClient() and "client" or "sp", "RecyclePreparation", "prepareRead", "nativeReadFailed") end
        Prep.cancel(job, "nativeReadFailed")
    elseif Prep.active[keyFor(job.playerNum)] == job and job.callbacks.progress then job.callbacks.progress(job) end
    return steps
end

function Prep.onTick()
    local jobs = {}
    for _, job in pairs(Prep.active) do jobs[#jobs + 1] = job end
    local count = #jobs
    if count > 0 then
        local start = GodSystemScheduler.nowMs()
        local quota = math.max(1, math.floor(Prep.MAX_STEP_ITEMS / count))
        local used = 0
        Prep.tickCursor = ((Prep.tickCursor or 0) % count) + 1
        for offset = 0, count - 1 do
            if used >= Prep.MAX_STEP_ITEMS or GodSystemScheduler.nowMs() - start >= Prep.BUDGET_MS then break end
            local index = ((Prep.tickCursor + offset - 1) % count) + 1
            used = used + Prep.step(jobs[index], math.min(quota, Prep.MAX_STEP_ITEMS - used), start)
        end
    end
    local hasJobs = false
    for _ in pairs(Prep.active) do hasJobs = true; break end
    if not hasJobs and tickInstalled then
        Events.OnTick.Remove(Prep.onTick)
        tickInstalled = false
    end
end

function Prep.start(snapshot, mode, callbacks)
    local player = playerFor(snapshot.playerNum)
    if not player then return nil end
    local key = keyFor(snapshot.playerNum)
    Prep.cancel(Prep.active[key])
    local cache = GodSystemRecycleContext.newAnalysis()
    local job = { snapshot = snapshot, playerNum = snapshot.playerNum, player = player, mode = mode,
        callbacks = callbacks or {}, cache = cache, data = cache.data,
        configToken = GodSystemRuntimeConfig.recyclePreparationToken(mode), sessionGeneration = Prep.sessionGeneration,
        catalogRevision = (mode == "listOnly" or mode == "recycleAndList") and tonumber(cache.data and cache.data.shopCatalogRevision or 0) or nil,
        economyRevision = tonumber(GodSystemItemConfig.Current and GodSystemItemConfig.Current.economyRevision),
        status = "analyzing", cursor = 1, classifications = {}, contents = {}, containerContentSignatures = {},
        items = {}, skipped = 0, cost = 0, typeCount = 0, listTypes = {}, rangeTypes = {}, rangeSeen = {}, rangeSkipped = 0 }
    if mode == "rangeFilter" then job.range = GodSystemApp.services.rangeRecycle:getContextMenuState(snapshot.playerNum) end
    local current, reason = isCurrent(job)
    if not cache.data or not current then return nil, reason or "sessionChanged" end
    Prep.active[key] = job
    if Events and Events.OnTick and not tickInstalled then
        Events.OnTick.Remove(Prep.onTick)
        Events.OnTick.Add(Prep.onTick)
        tickInstalled = true
    end
    return job
end

function Prep.clear()
    Prep.sessionGeneration = Prep.sessionGeneration + 1
    for _, job in pairs(Prep.active) do Prep.cancel(job) end
    if Events and Events.OnTick then Events.OnTick.Remove(Prep.onTick) end
    tickInstalled = false
end
if Events and Events.OnDisconnect then Events.OnDisconnect.Add(Prep.clear) end
if Events and Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(Prep.clear) end

return Prep
