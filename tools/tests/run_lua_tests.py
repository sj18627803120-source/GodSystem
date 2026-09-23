"""Compile packaged Lua and run isolated behavior specs with the Lua 5.1 VM.

Test-only dependency: pip install --target .test-runtime lupa==2.8
The runtime and fixtures are never included in Contents/.
"""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".test-runtime"))
try:
    from lupa.lua51 import LuaRuntime
except ImportError as exc:
    raise SystemExit("Lua 5.1 test runtime unavailable; install lupa into .test-runtime") from exc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-only", action="store_true")
    args = parser.parse_args()
    lua_root = ROOT / "Contents/mods/GodSystem/42/media/lua"
    vm = LuaRuntime(unpack_returned_tuples=True)
    assert vm.eval("_VERSION") == "Lua 5.1"
    compile_source = vm.eval("function(source, name) local f, err = loadstring(source, name); assert(f, err); return true end")
    sources = sorted(lua_root.rglob("*.lua"))
    for source in sources:
        compile_source(source.read_text(encoding="utf-8-sig"), "@" + source.relative_to(ROOT).as_posix())
    print(f"Lua 5.1 compilation passed: {len(sources)} packaged files", flush=True)
    if not args.compile_only:
        # Restrict the fixture loader to this repository's packaged Lua files.
        def read_source(relative):
            path = (lua_root / relative).resolve()
            if not path.is_relative_to(lua_root.resolve()):
                raise ValueError("Source path must remain under the packaged Lua root")
            return path.read_text(encoding="utf-8-sig")
        for spec in sorted((ROOT / "tools/tests").glob("*_spec.lua")):
            spec_vm = LuaRuntime(unpack_returned_tuples=True)
            # B42.20.4 Kahlua has pairs(), but no global next(). Keep that
            # constraint for every behavior spec, including SP/MP adapters.
            spec_vm.execute("next = nil")
            spec_vm.globals().readSource = read_source
            def read_fixture(name):
                path = (ROOT / 'tools/tests' / name).resolve()
                if not path.is_relative_to((ROOT / 'tools/tests').resolve()):
                    raise ValueError('Fixture path must remain under tools/tests')
                return path.read_text(encoding='utf-8-sig')
            spec_vm.globals().readFixture = read_fixture
            print(f"Running {spec.name}", flush=True)
            spec_vm.execute(spec.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
