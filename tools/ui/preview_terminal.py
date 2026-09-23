"""Exercise real packaged UI controllers and export their drawing calls to SVG.

The ISUI fixture approximates font metrics; this is not an in-game screenshot.
"""
import html
import json
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.test-runtime'))
sys.path.insert(0,str(ROOT.parent/'GodSystem-main/.test-runtime'))
from lupa.lua51 import LuaRuntime

def create_vm(font_scale=1):
    vm=LuaRuntime(unpack_returned_tuples=True)
    lua_root=ROOT/'Contents/mods/GodSystem/42/media/lua'
    vm.globals().readSource=lambda p:(lua_root/p).read_text(encoding='utf-8-sig')
    tr={}
    for line in (ROOT/'tools/localization/godsystem_v11645_localization.yml').read_text(encoding='utf-8-sig').splitlines():
        if ': ' in line and not line.startswith('#'):
            key,value=line.split(': ',1);tr[key]=json.loads(value)
    tr.update(json.loads((lua_root/'shared/Translate/CN/IG_UI.json').read_text(encoding='utf-8-sig')))
    vm.globals().translations=vm.table_from(tr)
    vm.execute((lua_root/'shared/GodSystem_Localization.lua').read_text(encoding='utf-8-sig'))
    vm.execute((lua_root/'shared/GodSystem_Localization_Override.lua').read_text(encoding='utf-8-sig'))
    vm.execute('for k,v in pairs(GodSystemFallbackText.zh) do if not translations[k] then translations[k]=v end end')
    vm.execute('next=nil')
    vm.execute((ROOT/'tools/tests/terminal_fixture.lua').read_text(encoding='utf-8'))
    # Local native font metadata is read only; no game font assets are packaged.
    fonts=Path('C:/APPS/Steam/steamapps/common/ProjectZomboid/media/fonts/CN')/f'{font_scale}x'
    advances,baselines={},{}
    for name in ('Small','Medium','Large'):
        path=fonts/f'zomboid{name}Chinese.fnt'
        if not path.exists(): continue
        source=path.read_text(encoding='utf-8-sig')
        vm.globals().fixtureFontHeights[name]=int(re.search(r'common lineHeight=(\d+)',source)[1])
        baselines[name]=int(re.search(r'common lineHeight=\d+ base=(\d+)',source)[1])
        advances[name]=vm.table_from({chr(int(k)):int(v) for k,v in re.findall(r'^char id=(\d+) .*?xadvance=(-?\d+)',source,re.M)})
    vm.globals().fixtureFontAdvances=vm.table_from(advances)
    vm.globals().fixtureFontBaselines=vm.table_from(baselines)
    return vm

def svg(vm):
    g=vm.globals();w=g.GodSystemUI.window
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w.width}" height="{w.height}" viewBox="{w.x} {w.y} {w.width} {w.height}">', f'<rect x="{w.x}" y="{w.y}" width="{w.width}" height="{w.height}" fill="#090e0e"/>']
    for d in g.draws.values():
        color='#'+''.join(f'{max(0,min(255,round((d[k] or 0)*255))):02x}' for k in ('r','g','b'))
        opacity=d.a if d.a is not None else 1
        if d.kind in ('rect','border'):
            out.append(f'<rect x="{d.x:.2f}" y="{d.y:.2f}" width="{d.w:.2f}" height="{d.h:.2f}" '+(f'fill="{color}"' if d.kind=='rect' else f'fill="none" stroke="{color}" stroke-width="1"')+f' opacity="{opacity}"/>')
        elif d.kind=='text':
            metrics=g.fixtureFontAdvances[d.font]
            size=(metrics and metrics['任']) or (g.fixtureFontHeights[d.font] or 19)*.7
            baseline=g.fixtureFontBaselines[d.font] or (g.fixtureFontHeights[d.font] or 19)*.8
            width=g.getTextManager().MeasureStringX(None,d.font,d.value)
            if width<=0: continue
            out.append(f'<text x="{d.x:.2f}" y="{d.y+baseline:.2f}" font-family="Microsoft YaHei, sans-serif" font-size="{size}" textLength="{width:.2f}" lengthAdjust="spacingAndGlyphs" fill="{color}" opacity="{opacity}">{html.escape(str(d.value))}</text>')
    return '\n'.join(out+['</svg>'])

def main():
    vm=create_vm();vm.execute('GodSystemUI.toggleWindow()')
    out=ROOT/'ui-preview';out.mkdir(exist_ok=True)
    pages=[('tasks','任务'),('shop','商店'),('bank','银行'),('equipment','装备'),('home','家园'),('traits','特质'),('attribute','技能'),('upgrades','升级'),('companion','机械同伴'),('rangeRecycle','回收'),('info','手册'),('settings','设置')]
    for mode,label in pages:
        print('Rendering',mode,flush=True)
        vm.execute(f'GodSystemUI.openMode("{mode}"); draws={{}}; renderTree(GodSystemUI.window)')
        (out/(mode+'.svg')).write_text(svg(vm),encoding='utf-8')
    buttons=''.join(f'<button onclick="show(\'{mode}\',this)">{label}</button>' for mode,label in pages)
    (out/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>God System · 终端预览</title><style>body{margin:0;background:#0a100e;color:#cad6cd;font:14px "Microsoft YaHei",sans-serif}header{padding:18px 24px;border-bottom:1px solid #293b31;display:flex;gap:12px;align-items:center;flex-wrap:wrap}b{letter-spacing:2px;margin-right:22px}button{background:#14221c;color:#abc3b4;border:1px solid #354c3f;padding:8px 16px;cursor:pointer}button.active{border-color:#85bea0;color:#d8eddf}p{margin:15px 24px;color:#889c90}main{padding:0 16px 20px;overflow:auto}img{display:block;max-width:100%;margin:auto;border:1px solid #2b4033}</style><header><b>GOD SYSTEM / TERMINAL</b>'''+buttons+'''</header><p>由正式目录 Lua 绘图指令生成的离线预览；使用示例数据与近似字体度量。游戏内最终效果仍需验证。</p><main><img id="screen" src="tasks.svg"></main><script>function show(page,button){document.querySelector('#screen').src=page+'.svg';document.querySelectorAll('button').forEach(x=>x.classList.remove('active'));button.classList.add('active')}document.querySelector('button').classList.add('active')</script></html>''',encoding='utf-8')
    print(out/'index.html')

if __name__=='__main__':main()
