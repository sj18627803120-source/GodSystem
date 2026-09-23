"""Exercise installed PZ methods through Kahlua without loading a world.

Requires a local game and an Eclipse Java compiler JAR. Optionally accepts the
user's UCWF shared Lua source; no game or third-party source is distributed.
Fixtures replace player construction, strength and moodles, so this is not a
live SP/MP test. Outputs stay in the ignored .test-runtime directory.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TESTS = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True, help="Local ECJ compiler JAR")
    parser.add_argument("--ucwf", type=Path, help="Optional UCWF shared Lua source")
    args = parser.parse_args()
    game = args.game.resolve()
    jar = game / "projectzomboid.jar"
    java = game / "jre64/bin/java.exe"
    compiler = args.compiler.resolve()
    for path in (jar, java, compiler, game / "stdlib.lua"):
        if not path.is_file():
            parser.error(f"Missing required file: {path}")
    work = ROOT / ".test-runtime/native-carry"
    work.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(game / "stdlib.lua", work / "stdlib.lua")
    subprocess.run([str(java), "-jar", str(compiler), "-17", "-nowarn", "-classpath", str(jar),
                    "-d", str(work), str(TESTS / "CarryNativeProbe.java")], cwd=work, check=True)
    source = (ROOT / "Contents/mods/GodSystem/42/media/lua/shared/GodSystem_CarryCapacity.lua").read_text(encoding="utf-8")
    framework = args.ucwf.read_text(encoding="utf-8-sig") if args.ucwf else "return nil"
    probe = (TESTS / "native_carry_probe.lua.in").read_text(encoding="utf-8")
    probe = probe.replace("-- @CARRY_SOURCE@", source).replace("-- @UCWF_SOURCE@", framework)
    script = work / "probe.lua"
    script.write_text(probe, encoding="utf-8")
    for name, content in (("game JAR", jar.read_bytes()), ("carry source", source.encode("utf-8"))):
        print(f"SHA256 {name}: {hashlib.sha256(content).hexdigest()}", flush=True)
    if args.ucwf:
        print(f"SHA256 UCWF: {hashlib.sha256(args.ucwf.read_bytes()).hexdigest()}", flush=True)
    subprocess.run([str(java), "-Djava.awt.headless=true", f"-Duser.home={work}", "-cp",
                    os.pathsep.join((str(work), str(jar))), "CarryNativeProbe", str(script)], cwd=work, check=True)


if __name__ == "__main__":
    main()
