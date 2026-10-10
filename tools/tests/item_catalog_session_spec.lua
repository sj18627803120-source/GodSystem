GodSystemConfig = { ItemConfigPinnedFullTypes = {} }
local originalRequire = require
function require(name)
    if name == "GodSystem_Pinyin" then
        assert(loadstring(readSource("shared/GodSystem_Pinyin.lua"), "@Pinyin"))()
        return GodSystemPinyin
    end
    if name == "GodSystem_PinyinData" then
        assert(loadstring(readSource("shared/GodSystem_PinyinData.lua"), "@PinyinData"))()
        return GodSystemPinyinData
    end
    return originalRequire(name)
end
assert(loadstring(readSource("client/GodSystem_ItemCatalog.lua"), "@ItemCatalog"), "catalog source")()
local chinese = GodSystemPinyin.buildIndex({ "垃圾袋", "Base.Garbagebag" })
assert(GodSystemPinyin.matches(chinese, "lajidai"), "full pinyin: " .. tostring(chinese[1].phonetic) .. "/" .. tostring(GodSystemPinyinData[0x5783]))
assert(GodSystemPinyin.matches(chinese, "ljd"), "initials")
assert(GodSystemPinyin.matches(chinese, "垃圾") and GodSystemPinyin.matches(chinese, "garbage"), "original text")
assert(not GodSystemPinyin.matches(chinese, "laGarbage"), "different fields must not concatenate")
local calls = 0
local provider = {
    count = function() return 2 end,
    metadata = function(_, index)
        calls = calls + 1
        return { fullType = "Base.Test" .. tostring(index) }
    end,
}
local old = GodSystemItemCatalog.new(provider)
GodSystemItemCatalog.Shared = old
old:buildStep(1)
assert(old.cursor == 1 and not old.complete, "old cursor")
GodSystemItemCatalog.resetSession()
GodSystemItemCatalog.buildOnTick()
assert(GodSystemItemCatalog.Shared == nil and old.cursor == 1 and calls == 1,
    "old session catalogue must stop building after reset")
local fresh = GodSystemItemCatalog.new(provider)
GodSystemItemCatalog.Shared = fresh
while not fresh.complete do GodSystemItemCatalog.buildOnTick() end
assert(fresh.complete and #fresh.rows == 2 and old.cursor == 1,
    "new session must build an independent catalogue")
print("PASS item catalogue: session reset cancels old build and creates fresh rows")

for _, size in ipairs({100, 500, 2000, 5000, 20000}) do
    local bulk = GodSystemItemCatalog.new({
        count = function() return size end,
        metadata = function(_, index)
            return { fullType = "Base.Perf" .. tostring(size - index), label = "Item" .. tostring(size - index) }
        end,
    })
    while bulk.cursor + 64 < size do bulk:buildStep(64) end
    local tailMs, steps = 0, 0
    local clockMs = function() return os and os.clock and os.clock() * 1000 or 0 end
    while not bulk.complete do
        local start = clockMs()
        bulk:buildStep(64)
        tailMs = math.max(tailMs, clockMs() - start)
        steps = steps + 1
        assert(steps < 10000, "incremental sort must terminate")
    end
    assert(bulk.complete and #bulk.rows == size, "sort completion")
    for i=2,#bulk.rows do assert(not (bulk.rows[i].key < bulk.rows[i-1].key)) end
    print(string.format("CATALOG_SORT_SIM size=%d max_step_ms=%.3f steps=%d", size, tailMs, steps))
end

-- Deterministic slow native metadata proves the time budget, not just row count.
do
    local time=0
    getTimestampMs=function() return time end
    local c=GodSystemItemCatalog.new({count=function() return 20 end,
        metadata=function(_,i) time=time+1; return {fullType="Base.Slow"..i} end})
    c:buildStep(64)
    assert(c.cursor==2, "2ms metadata budget")
    getTimestampMs=nil
end

do
    local lang,reads="CN",0
    Translator={getLanguage=function() return lang end}
    getItemNameFromFullType=function(fullType) reads=reads+1; return lang..fullType end
    local c=GodSystemItemCatalog.new({count=function() return 150 end,
        metadata=function(_,i) return {fullType="Base.Name"..i} end})
    while not c.complete do c:buildStep(64) end
    local oldRows=c.rows
    reads=0
    for i=1,10 do c:query("name",1,20) end
    assert(reads==0, "stable queries never re-read translated item labels")
    lang="EN";c:query("name",1,20)
    assert(c.rebuild and c.rows==oldRows and reads==0, "query only schedules language rebuild")
    c:buildStep(64)
    assert(c.rows==oldRows and reads<=64, "partial translated rows are private")
    lang="CH";c:query("name",1,20)
    while c.rebuild do c:buildStep(64) end
    assert(c.rows~=oldRows and c.rows[1].label:sub(1,2)=="CH", "late EN snapshot never wins")
    GodSystemItemCatalog.Shared=c
    local release=GodSystemItemCatalog.subscribe(function() end)
    lang="EN";c:query("",1,20);release()
    assert(c.paused and not c.rebuild, "last window closes: cancel private rebuild")
    GodSystemItemCatalog.getShared():query("",1,20)
    assert(not c.paused and c.rebuild, "reopen restarts invalidated language build")
    GodSystemItemCatalog.resetSession();c:buildStep(64)
    assert(c.cancelled and c.rows[1].label:sub(1,2)=="CH", "cancelled object cannot publish")
    Translator=nil; getItemNameFromFullType=nil
end

do
    local builds=0
    local original=GodSystemPinyin.buildIndex
    GodSystemPinyin.buildIndex=function(fields) builds=builds+1; return original(fields) end
    GodSystemPinyin.clearCaches()
    for i=1,10 do assert(GodSystemPinyin.matchCached("recycle","a",{"垃圾袋","20"},"ljd")) end
    assert(builds==1,"search input must reuse index")
    assert(GodSystemPinyin.matchCached("recycle","a",{"垃圾袋","30"},"30"))
    assert(builds==2,"updated amount invalidates cached numeric fields")
    GodSystemPinyin.clearCaches("recycle")
    GodSystemPinyin.matchCached("recycle","a",{"垃圾袋","30"},"30")
    assert(builds==3,"closed display releases index")
    GodSystemPinyin.buildIndex=original
end
print("PASS catalogue: time budget, atomic language change, cancellation, query index invalidation")
