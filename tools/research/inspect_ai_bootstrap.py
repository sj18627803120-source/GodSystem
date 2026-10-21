"""Inspect an installed PZ JAR and run harmless isolated bootstrap checks.

Does not install software, send HTTP, launch installers, edit game launchers,
or start a game/server. Game classes are inspected locally, never distributed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name("AIBootstrapProbe.java")


def run(command, work, name):
    result = subprocess.run(command, cwd=work, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=60)
    output = result.stdout + result.stderr
    (work / name).write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{name} failed ({result.returncode}):\n{output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True, help="Local ECJ JAR")
    args = parser.parse_args()
    game = args.game.resolve()
    compiler = args.compiler.resolve()
    jar = game / "projectzomboid.jar"
    java = game / "jre64/bin/java.exe"
    for path in (jar, java, compiler, game / "stdlib.lua", SOURCE):
        if not path.is_file():
            parser.error(f"Missing required local file: {path}")
    work = ROOT / ".test-runtime/ai-bootstrap"
    work.mkdir(parents=True, exist_ok=True)
    home = work / "home"
    home.mkdir(exist_ok=True)
    shutil.copyfile(game / "stdlib.lua", work / "stdlib.lua")
    needles = ("java/net/URL", "java/net/http/HttpClient", "java/lang/ProcessBuilder",
               "java/net/Socket", "java/net/URLClassLoader", "javaJarFile", "javaPkgName")
    references = {needle: [] for needle in needles}
    classes = 0
    with ZipFile(jar) as archive:
        for name in archive.namelist():
            if not name.startswith("zombie/") or not name.endswith(".class"):
                continue
            classes += 1
            data = archive.read(name)
            for needle in needles:
                if needle.encode("ascii") in data:
                    references[needle].append(name)
    run([str(java), "-jar", str(compiler), "-17", "-nowarn", "-classpath",
         str(jar), "-d", str(work), str(SOURCE)], work, "compile.log")
    output = run([str(java), "-Djava.awt.headless=true", f"-Duser.home={home}",
                  "-cp", os.pathsep.join((str(work), str(jar))),
                  "AIBootstrapProbe"], work, "native-probe.log")
    if "CHECKS=19" not in output:
        raise RuntimeError("Native checks did not complete; inspect native-probe.log")
    version = run([str(java), "-version"], work, "java-version.log").strip()
    report = {
        "gameJar": str(jar),
        "gameJarSha256": hashlib.sha256(jar.read_bytes()).hexdigest(),
        "compilerSha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "probeSha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "javaVersion": version,
        "zombieClassCount": classes,
        "constantPoolReferenceCandidates": references,
        "checksPassed": 19,
        "scope": "isolated real methods and global Kahlua registration, not a full game",
        "networkRequests": 0,
        "installerLaunches": 0,
        "gameConfigurationWrites": 0,
        "limitations": "Reference matches are candidates, not proof of Lua access or callability.",
    }
    destination = work / "result.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output, end="")
    print(f"zombie classes inspected: {classes}")
    print(f"game JAR SHA256: {report['gameJarSha256']}")
    print(f"report: {destination}")


if __name__ == "__main__":
    main()
