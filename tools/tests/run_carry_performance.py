"""Measure isolated Lua 5.1 carry field maintenance; never an in-game FPS claim."""
from pathlib import Path
import json
import sys
import time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.test-runtime'))
from lupa.lua51 import LuaRuntime
vm = LuaRuntime(unpack_returned_tuples=True)
vm.execute('next=nil; function require()end; function isClient()return false end; function isServer()return true end; clock=0; function getTimestampMs()return clock end; CharacterTrait={STRONG=1,WEAK=2,FEEBLE=3,STOUT=4}; Events={OnTick={Add=function()end,Remove=function()end}}')
vm.execute((ROOT/'Contents/mods/GodSystem/42/media/lua/shared/GodSystem_CarryCapacity.lua').read_text(encoding='utf-8'))
vm.execute('''
function setup(count)
    GodSystemCarryCapacity.resetClient(); metrics={reads=0,writes=0,recomputes=0}; players={}
    for i=1,count do
        local p={base=8,delta=1,final=12}
        function p:getMaxWeightBase() metrics.reads=metrics.reads+1;return self.base end
        function p:getMaxWeightDelta() metrics.reads=metrics.reads+1;return self.delta end
        function p:getMaxWeight() metrics.reads=metrics.reads+1;return self.final end
        function p:getWeightMod() metrics.reads=metrics.reads+1;return 1.58 end
        function p:isDead()metrics.reads=metrics.reads+1;return false end
        function p:setMaxWeightBase(v)metrics.writes=metrics.writes+1;self.base=v end
        function p:setMaxWeightDelta(v)metrics.writes=metrics.writes+1;self.delta=v end
        function p:setMaxWeight(v)metrics.writes=metrics.writes+1;self.final=v end
        function p:getModData()error('stable guard must never request moddata')end
        local md={};p.getModData=function()return md end
        function p:getCharacterTraits()return {get=function()return false end}end
        local body={UpdateStrength=function()metrics.recomputes=metrics.recomputes+1;p.final=math.floor(p.base*1.58)end}
        function p:getBodyDamage()return body end
        assert(GodSystemCarryCapacity.restore(p,3));players[i]=p
        p.getModData=function()error('stable guard must never request moddata')end
        p.getInventory=function()error('guard must never scan inventory')end
    end
    metrics.reads,metrics.writes,metrics.recomputes=0,0,0
end
function step(interference)
    clock=clock+100
    if interference then for _,p in ipairs(players)do p.base=99;p.final=1 end end
    GodSystemCarryCapacity.onGuardTick()
end
''')
results=[]
for count in (1,20,100):
    for interference in (False,True):
        vm.globals().setup(count)
        steps=1000 if interference else 10000
        maximum=0.0; started=time.perf_counter()
        for _ in range(steps):
            one=time.perf_counter();vm.globals().step(interference);maximum=max(maximum,time.perf_counter()-one)
        elapsed=time.perf_counter()-started; m=vm.globals().metrics
        row=dict(players=count,mode='interference' if interference else 'stable',steps=steps,elapsed_ms=round(elapsed*1000,3),max_step_ms=round(maximum*1000,3),reads=m.reads,writes=m.writes,recomputes=m.recomputes,backpack_scans=0,guard_messages=0)
        if not interference:assert m.writes==0 and m.recomputes==0 and m.reads==steps*count*4
        results.append(row)
        print(json.dumps(row))
work=ROOT/'.test-runtime/native-carry';work.mkdir(parents=True,exist_ok=True)
(work/'performance-lua51.json').write_text(json.dumps({'kind':'Lua 5.1 mock; no world/network','results':results},indent=2),encoding='utf-8')
