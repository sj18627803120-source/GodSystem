"""Install pinned, development-only analyzers. Never writes to Contents/."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".test-runtime/analysis"


def main():
    lock = json.loads((ROOT / "tools/analysis/toolchain.json").read_text(encoding="utf8"))
    BASE.mkdir(parents=True, exist_ok=True)
    for name, spec in lock.items():
        archive = BASE / (name + ".zip")
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != spec["sha256"]:
            data = urllib.request.urlopen(spec["url"], timeout=90).read()
            if hashlib.sha256(data).hexdigest() != spec["sha256"]:
                raise RuntimeError(name + " checksum differs from reviewed toolchain")
            archive.write_bytes(data)
        destination = BASE / name
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                if not (destination / entry.filename).resolve().is_relative_to(destination.resolve()):
                    raise RuntimeError("Archive path escapes tool directory")
            bundle.extractall(destination)
        print(name, spec["version"], "verified and installed")


if __name__ == "__main__":
    main()
