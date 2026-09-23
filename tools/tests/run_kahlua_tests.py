"""Native-VM regressions for the real-game Chinese/impact feedback."""
from pathlib import Path
import argparse
from kahlua_runner import run

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / 'Contents/mods/GodSystem/42/media/lua'


def quote(value):
    # Kahlua's compiler decodes the byte escapes as UTF-8, like our generators.
    return '"' + ''.join(chr(b) if 32 <= b <= 126 and b not in (34, 92) else '\\%03d' % b for b in value.encode('utf-8')) + '"'


def bundle(spec, overrides=None):
    overrides = overrides or {}
    code = ['local sources={}', 'local output={}; function print(s) output[#output+1]=tostring(s) end']
    for path in sorted(LUA.rglob('*.lua')):
        rel = path.relative_to(LUA).as_posix()
        code.append('sources[' + quote(rel) + ']=function()\n' + overrides.get(rel, path.read_text(encoding='utf-8-sig')) + '\nend')
    # The bare J2SE platform has no loadstring global. Compile each unmodified
    # module as a function above; adapt only the specs' fixture-loading boundary.
    fixture = (ROOT/'tools/tests/terminal_fixture.lua').read_text(encoding='utf-8')
    code += ['local fixture=function()\n'+fixture+'\nend',
             'function readFixture(name) assert(name=="terminal_fixture.lua"); return fixture end',
             'function readSource(path) return assert(sources[path],path) end',
             'function loadstring(fn) assert(type(fn)=="function"); return fn end',
             spec, 'return table.concat(output,"\\n").."\\nKahlua regression passed"']
    return '\n'.join(code)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--game', required=True)
    args = parser.parse_args()
    for name in ('text_runtime_spec.lua', 'impact_runtime_spec.lua', 'splash_runtime_spec.lua', 'utility_generator_spec.lua', 'terminal_spec.lua', 'carry_capacity_spec.lua', 'equipment_spec.lua', 'shop_catalog_spec.lua', 'shop_inflation_spec.lua', 'recycle_fingerprint_spec.lua', 'v38_regression_spec.lua', 'death_protection_spec.lua'):
        print('Running native ' + name, flush=True)
        print(run(bundle((ROOT/'tools/tests'/name).read_text(encoding='utf-8')), args.game))
