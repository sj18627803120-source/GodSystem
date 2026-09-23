"""Real Network callback checks. Original failed probes are recorded in handoff 92.

Shared/server regressions now run in v38_regression_spec.lua in both VMs.
This checks current client callbacks with the native B42 modal argument order.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.test-runtime'))
from lupa.lua51 import LuaRuntime

LUA = ROOT / 'Contents/mods/GodSystem/42/media/lua'
network = (LUA / 'client/GodSystem_Network.lua').read_text(encoding='utf-8-sig')
vm = LuaRuntime(unpack_returned_tuples=True)
vm.execute((LUA / 'shared/GodSystem_Protocol.lua').read_text(encoding='utf-8-sig'))
vm.execute('''
GodSystemNetwork={}; Protocol=GodSystemProtocol; requests={}; commands={}
send=function(name,args) requests[#requests+1]={name=name,args=args};return true end
SendCommandToServer=function(command)commands[#commands+1]=command end
''')
callback = network.split('function GodSystemNetwork.onShopQuoteConfirm', 1)[1].split(
    'function GodSystemNetwork.resetInvestmentRuntime', 1)[0]
vm.execute('function GodSystemNetwork.onShopQuoteConfirm' + callback)
vm.execute('''
local q={id='axe',quantity=3,quoteId='1'}
GodSystemNetwork.onShopQuoteConfirm(GodSystemNetwork,{internal='NO'},q)
assert(#requests==0)
GodSystemNetwork.onShopQuoteConfirm(GodSystemNetwork,{internal='YES'},q)
assert(#requests==1 and requests[1].name=='buyShop' and requests[1].args.quantity==3)
''')
print('PASS native modal target/button/quote callback; cancel does not buy')
handler = network.split('local function handleTeleportPayload', 1)[1].split('local function nowMs', 1)[0]
vm.execute('local function handleTeleportPayload' + handler + '\nhandleTeleport=handleTeleportPayload')
vm.execute('''
requests={}
local p={id='server-issued-1',native=true,targetUsername='Player One',pos={x=10,y=20,z=0}}
handleTeleport(p);handleTeleport(p)
assert(#commands==1 and commands[1]=='/teleportto "Player One" 10,20,0')
assert(#requests==2 and requests[1].args.ok==true)
handleTeleport({id='old-direct-move',pos={x=999,y=999,z=0}})
assert(#commands==1 and requests[3].args.ok==false)
''')
print('PASS MP native command execution, duplicate suppression and refusal of direct-move payloads')
vm.execute((LUA / 'shared/GodSystem_B42JavaCalls.lua').read_text(encoding='utf-8-sig'))
vm.execute('''
local moves=0
local methods={getUsername=function()return 'Player One' end,isDead=function()return false end,getVehicle=function()return nil end}
local p=newproxy(true)
getmetatable(p).__index=methods
getPlayer=function()return p end
methods.teleportTo=function(target,x,y,z)
    assert(target==p and x==10 and y==20 and z==0)
    moves=moves+1;return true
end
local q={id='fallback-1',native=false,fallback='approvedClient',targetUsername='Player One',pos={x=10.5,y=20.5,z=0}}
handleTeleport(q);handleTeleport(q)
assert(moves==1 and requests[#requests].args.ok==true)
q.id='wrong-target';q.targetUsername='Someone Else';handleTeleport(q)
assert(moves==1 and requests[#requests].args.ok==false)
q.id='invalid-position';q.targetUsername='Player One';q.pos.x=math.huge;handleTeleport(q)
assert(moves==1 and requests[#requests].args.ok==false)
q.id='in-vehicle';q.pos.x=10.5;methods.getVehicle=function()return {}end;handleTeleport(q)
assert(moves==1 and requests[#requests].args.ok==false)
''')
print('PASS approved MP fallback: target validation, bounded receipt deduplication, invalid position and vehicle refusal')
