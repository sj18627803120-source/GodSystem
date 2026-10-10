"""Reproducible LuaLS report; errors are distinguished from unmodeled PZ APIs."""
import collections
import argparse
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".test-runtime/analysis"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=ROOT)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    source = source_root / "Contents/mods/GodSystem/42/media/lua"
    if not source.is_dir():
        raise SystemExit("LuaLS NOT RUN: packaged Lua directory is missing: " + str(source))
    config = json.loads((ROOT / ".luarc.json").read_text(encoding="utf8"))
    config["workspace.library"] = [str(ROOT / p) for p in config["workspace.library"]]
    binary = BASE / "luals/bin/lua-language-server.exe"
    if not binary.is_file() or not all(Path(p).is_dir() for p in config["workspace.library"]):
        raise SystemExit("LuaLS NOT RUN: run python tools/analysis/setup.py first")
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    if "3.19.1" not in version:
        raise SystemExit("Unexpected LuaLS version: " + version)
    path = BASE / "check.json"
    path.write_text(json.dumps(config), encoding="utf8")
    output = BASE / "diagnostics.json"
    if output.exists():
        output.unlink()
    with (BASE / "check.log").open("w", encoding="utf8") as log:
        result = subprocess.run([str(binary), "--check=" + str(source), "--checklevel=Hint",
            "--check_format=json", "--check_out_path=" + str(output), "--configpath=" + str(path),
            "--logpath=" + str(BASE / "logs"), "--metapath=" + str(BASE / "meta")],
            stdout=log, stderr=subprocess.STDOUT, text=True, timeout=300)
    if result.returncode not in (0, 1) or not output.exists():
        raise SystemExit("LuaLS did not produce a report; see " + str(BASE / "check.log"))
    diagnostics = json.loads(output.read_text(encoding="utf8"))
    rows = []
    for uri, entries in diagnostics.items():
        file = Path(unquote(uri.removeprefix("file:///"))).resolve()
        if not file.is_relative_to(source):
            continue
        for entry in entries:
            rows.append({"file": file.relative_to(source_root).as_posix(),
                "line": entry["range"]["start"]["line"] + 1,
                "code": entry["code"], "message": entry["message"]})
    counts = collections.Counter(row["code"] for row in rows)
    # These rules are actionable without guessing the types of injected runtime globals.
    blocking = {"redundant-parameter", "duplicate-index", "err-esc"}
    failed = [row for row in rows if row["code"] in blocking or row["code"].startswith("syntax")
        or row["code"] == "unused-function"
        or (row["code"] == "unused-local" and "`_" not in row["message"])]
    reviewed = json.loads((ROOT / "tools/analysis/reviewed-parameters.json").read_text(encoding="utf8"))
    parameter_codes = {"param-type-mismatch", "missing-parameter"}
    for row in rows:
        if row["code"] in parameter_codes:
            key = row["file"] + "|" + row["code"] + "|" + row["message"]
            if key not in reviewed:
                failed.append(row)
    (BASE / "summary.json").write_text(json.dumps({"version": version, "counts": counts,
        "blocking": failed, "diagnostics": rows}, ensure_ascii=False, indent=2), encoding="utf8")
    print("LuaLS diagnostics:", dict(counts))
    for row in failed:
        print(row["file"], row["line"], row["code"], row["message"])
    print("LuaLS report:", BASE / "summary.json")
    if failed:
        raise SystemExit(1)
    print("LuaLS actionable and reviewed parameter checks passed; other diagnostics remain visible in the report.")


if __name__ == "__main__":
    main()
