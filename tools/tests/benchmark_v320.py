"""Lua 5.1 simulation only: phase costs, not in-game frame/network latency."""
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".test-runtime"))
from lupa.lua51 import LuaRuntime

vm = LuaRuntime(unpack_returned_tuples=True)
vm.globals().readSource = lambda name: (ROOT / "Contents/mods/GodSystem/42/media/lua" / name).read_text(encoding="utf8")
results = []
vm.globals().record = lambda kind, count, layout, phase, ms, calls: results.append(
    dict(kind=kind, count=count, layout=layout, phase=phase, milliseconds=ms, calls=calls))
vm.globals().clockMs = lambda: time.perf_counter() * 1000
fixture = (ROOT / "tools/tests/external_recycle_spec.lua").read_text(encoding="utf8").split("\ndo\n", 1)[0]
vm.execute(fixture + r'''
for _,count in ipairs({100,500,2000,5000}) do
 for _,squares in ipairs({1,4}) do
    local groups,lookup={},{}
    for n=1,squares do
        local p,first,floor,square,cell,world=fixture()
        square.x=10+(n-1)%2; square.y=20+math.floor((n-1)/2)
        square.isBlockedTo=function() return false end
        world[1]=nil; groups[n]={first=first,floor=floor,square=square,world=world,rows={}}
        lookup[square.x..":"..square.y]=square
    end
    local player={getX=function() return 10.5 end,getY=function() return 20.5 end,getZ=function() return 0 end,
        getCurrentSquare=function() return groups[1].square end,getUsername=function() return "benchmark" end}
    local visits,packets=0,0
    for _,g in ipairs(groups) do
        g.square.getWorldObjects=function() return {size=function() return #g.world end,
            get=function(_,i) visits=visits+1;return g.world[i+1] end} end
        g.square.transmitRemoveItemFromSquare=function() packets=packets+1 end
    end
    local descriptors={}
    for i=1,count do
        local g=groups[(i-1)%squares+1]
        local item={id=i,container=g.floor,getID=g.first.getID,getContainer=g.first.getContainer,
            getWorldItem=g.first.getWorldItem,setWorldItem=g.first.setWorldItem}
        g.floor.rows[item]=true;g.square:AddWorldInventoryItem(item)
        descriptors[i]=assert(E.describe(item))
    end
    getCell=function() return {getGridSquare=function(_,x,y,z) return z==0 and lookup[x..":"..y] end} end
    isServer=function() return true end;SafeHouse={isSafeHouse=function() return nil end}
    local cache,rows={},{}
    local started=clockMs()
    for i=1,count do rows[i]=assert(E.resolve(player,descriptors[i],cache)) end
    record("ground",count,squares,"locate",clockMs()-started,visits)
    assert(visits==count)
    started=clockMs();visits=0
    for i=1,count do assert(E.remove(rows[i])) end
    record("ground",count,squares,"remove_and_sync",clockMs()-started,visits)
    record("ground",count,squares,"mock_remove_packets",0,packets)
    started=clockMs();visits=0
    for i=1,count do assert(E.restore(rows[i])) end
    record("ground",count,squares,"restore",clockMs()-started,visits)
 end
end
''')
vm.execute(r'''
require=function(name) return assert(loadstring(readSource("shared/"..name..".lua")))() end
require("GodSystem_Pinyin")
for _,size in ipairs({5000,20000}) do
    local fields={}
    for i=1,size do fields[i]={"盒装垃圾袋"..i,"Base.Bag"..i} end
    local queries={"hezhuang","ljd","bag"}
    local t=clockMs()
    for _,q in ipairs(queries) do for i=1,size do GodSystemPinyin.matchFields(fields[i],q) end end
    record("search",size,1,"rebuild_each_query",clockMs()-t,size*#queries)
    GodSystemPinyin.clearCaches("recycle");t=clockMs()
    for i=1,size do GodSystemPinyin.matchCached("recycle",i,fields[i],"ljd") end
    record("search",size,1,"cold_cache",clockMs()-t,size)
    t=clockMs()
    for _,q in ipairs(queries) do for i=1,size do GodSystemPinyin.matchCached("recycle",i,fields[i],q) end end
    record("search",size,1,"warm_cache",clockMs()-t,size*#queries)
end
''')
vm.execute(r'''
local previousRequire=require
require=function(name)
    if name=="GodSystem_Pinyin" then return GodSystemPinyin end
    return previousRequire(name)
end
assert(loadstring(readSource("client/GodSystem_ItemCatalog.lua")))()
getTimestampMs=clockMs
local language="CN"
Translator={getLanguage=function() return language end}
getItemNameFromFullType=function(fullType) return language..fullType end
for _,size in ipairs({5000,20000}) do
    local c=GodSystemItemCatalog.new({count=function() return size end,
        metadata=function(_,i) return {fullType="Base.Catalog"..(size-i)} end})
    local start,maxStep=clockMs(),0
    while not c.complete do
        local t=clockMs();c:buildStep(64);maxStep=math.max(maxStep,clockMs()-t)
    end
    record("catalog",size,1,"initial_total",clockMs()-start,size)
    record("catalog",size,1,"initial_max_step",maxStep,0)
    start=clockMs()
    for i=1,5 do c:query("catalog",i,20) end
    record("catalog",size,1,"five_queries",clockMs()-start,5)
    language=language=="CN" and "EN" or "CN"
    c:query("",1,20);start=clockMs();maxStep=0
    while c.rebuild do
        local t=clockMs();c:buildStep(64);maxStep=math.max(maxStep,clockMs()-t)
    end
    record("catalog",size,1,"language_total",clockMs()-start,size)
    record("catalog",size,1,"language_max_step",maxStep,0)
end
''')
out = ROOT / ".test-runtime/v320-performance.json"
out.write_text(json.dumps({"environment": "lupa.lua51 synthetic fixtures; network is counted, not timed", "results": results},
                          ensure_ascii=False, indent=2), encoding="utf8")
for row in results:
    print(row)
print("Report:", out)
