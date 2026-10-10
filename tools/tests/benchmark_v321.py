"""Before/after phase measurements: Lua 5.1 mocks, never game FPS or MP latency."""
from pathlib import Path
import json
import sys
import time
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.test-runtime'))
from lupa.lua51 import LuaRuntime
LUA=ROOT/'Contents/mods/GodSystem/42/media/lua'
BASE=ROOT/'.test-runtime/v321-baseline'
if not (BASE/'shared/GodSystem_ExternalRecycle.lua').is_file():
 raise SystemExit('Before/after benchmark NOT RUN: pre-3.21 source snapshot is missing in '+str(BASE))
OUT=ROOT/'docs/开发技术支援/3.21_回收性能模拟数据.json'
fixture=(ROOT/'tools/tests/external_recycle_spec.lua').read_text(encoding='utf8')
def extract(name):
 start=fixture.index('local function '+name+'(')
 end=fixture.index('\nend\n',start)+5
 return fixture[start:end]
rows=[]
for version in ('before','after'):
 vm=LuaRuntime(unpack_returned_tuples=True)
 def read(name):
  old=BASE/name
  return (old if version=='before' and old.is_file() else LUA/name).read_text(encoding='utf8')
 vm.globals().readSource=read
 vm.globals().clockMs=lambda:time.perf_counter()*1000
 vm.globals().record=lambda kind,n,layout,phase,ms,gets,sync,weight,dirty:rows.append(dict(
  version=version,source=kind,count=n,squares=layout,phase=phase,milliseconds=round(ms,3),listGets=gets,syncCalls=sync,weightCalls=weight,dirtyCalls=dirty))
 vm.execute('local function load(path) return assert(loadstring(readSource(path)))() end\nload("shared/GodSystem_B42JavaCalls.lua")\nload("shared/GodSystem_ExternalRecycle.lua")\nE=GodSystemExternalRecycle\n'+extract('fixture')+'\n'+extract('containerFixture')+r'''
 for _,count in ipairs({100,500,2000,5000}) do
  for _,squares in ipairs({1,4}) do
   local groups,lookup={},{}
   local visits,packets=0,0
   for n=1,squares do
    local p,first,floor,square,cell,world=fixture()
    square.x=10+(n-1)%2; square.y=20+math.floor((n-1)/2)
    square.isBlockedTo=function() return false end
    world[1]=nil; groups[n]={first=first,square=square,world=world}
    lookup[square.x..":"..square.y]=square
    square.getWorldObjects=function() return {size=function() return #world end,
     get=function(_,i) visits=visits+1;return world[i+1] end,
     contains=function(_,obj) for _,v in ipairs(world) do if v==obj then return true end end return false end} end
    square.transmitRemoveItemFromSquare=function() packets=packets+1 end
   end
   local player={getX=function() return 10.5 end,getY=function() return 20.5 end,getZ=function() return 0 end,
    getCurrentSquare=function() return groups[1].square end,getUsername=function() return "benchmark" end}
   getCell=function() return {getGridSquare=function(_,x,y,z) return z==0 and lookup[x..":"..y] end} end
   isServer=function() return true end; SafeHouse={isSafeHouse=function() return nil end}
   local descriptors={}
   for i=1,count do
    local g=groups[(i-1)%squares+1]
    local item={id=i,getID=g.first.getID,getContainer=g.first.getContainer,getWorldItem=g.first.getWorldItem,setWorldItem=g.first.setWorldItem}
    g.square:AddWorldInventoryItem(item);descriptors[i]=assert(E.describe(item))
   end
   local rows,cache={},{}
   local started=clockMs()
   for i=1,count do rows[i]=assert(E.resolve(player,descriptors[i],cache)) end
   record("ground",count,squares,"locate",clockMs()-started,visits,0,0,0)
   assert(visits==count);visits=0;started=clockMs()
   local batch=E.newBatch and E.newBatch()
   for i=1,count do assert(E.remove(rows[i],batch)) end
   record("ground",count,squares,"delete_verify",clockMs()-started,visits,packets,0,0)
   visits=0;started=clockMs()
   if batch then assert(E.flushBatch(batch)) end
   record("ground",count,squares,"flush",clockMs()-started,visits,0,0,0)
   visits=0;started=clockMs()
   for i=1,count do assert(E.restore(rows[i])) end
   record("ground",count,squares,"restore",clockMs()-started,visits,0,0,0)
  end
  local player,first,root,parent=containerFixture("vehicle",false)
  root.rows={}
  local sync,weight,dirty,visits=0,0,0,0
  parent.part.setContainerContentAmount=function() weight=weight+1 end
  root.setDrawDirty=function() dirty=dirty+1 end
  local previous=root.getItems
  root.getItems=function(self)
   local list=previous(self);local get=list.get
   list.get=function(l,i) visits=visits+1;return get(l,i) end
   return list
  end
  sendRemoveItemFromContainer=function() sync=sync+1 end
  sendAddItemToContainer=function() end
  ArrayList={new=function() return {rows={},add=function(self,v) self.rows[#self.rows+1]=v end} end}
  sendRemoveItemsFromContainer=function(_,items) assert(items.rows);sync=sync+1 end
  local descriptors={}
  for i=1,count do
   local item={id=i,container=root,getID=first.getID,getContainer=first.getContainer,getInventory=first.getInventory}
   root.rows[item]=true;descriptors[i]=assert(E.describe(item))
  end
  local cache,items={},{}
  local started=clockMs()
  for i=1,count do items[i]=assert(E.resolve(player,descriptors[i],cache)) end
  record("vehicle",count,1,"locate",clockMs()-started,visits,sync,weight,dirty)
  visits=0;started=clockMs();local batch=E.newBatch and E.newBatch()
  for i=1,count do assert(E.remove(items[i],batch)) end
  record("vehicle",count,1,"delete_verify",clockMs()-started,visits,sync,weight,dirty)
  sync=0;weight=0;dirty=0;started=clockMs()
  if batch then assert(E.flushBatch(batch)) end
  record("vehicle",count,1,"flush",clockMs()-started,0,sync,weight,dirty)
  sync=0;weight=0;dirty=0;started=clockMs()
  local updates=E.newBatch and E.newBatch()
  for i=1,count do assert(E.restore(items[i],updates)) end
  if updates then assert(E.flushUpdates(updates)) end
  record("vehicle",count,1,"restore",clockMs()-started,0,sync,weight,dirty)
 end
 ''')
OUT.write_text(json.dumps({'environment':'Lua 5.1 Lupa mock; not game frame time; contains/delete are simulated',
 'baseline':'saved pre-3.21 ExternalRecycle in .test-runtime/v321-baseline', 'rows':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
for row in rows:
 if row['count']==5000 and row['squares']==1: print(row)
print('Report:',OUT)
