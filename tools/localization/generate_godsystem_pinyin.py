"""Generate a compact kMandarin lookup for GodSystem from Unicode 17.0.0.

Source: https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip
Unicode data license: https://www.unicode.org/copyright.html
Only the first kMandarin reading of BMP CJK ideographs is included.
"""

from __future__ import annotations

import hashlib
import io
from pathlib import Path
import unicodedata
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
URL = "https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip"
SHA256 = "f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e"
OUTPUT = ROOT / "Contents/mods/GodSystem/42/media/lua/shared/GodSystem_PinyinData.lua"
CACHE = ROOT / ".test-runtime/Unihan-17.0.0.zip"


def main() -> None:
    if CACHE.exists():
        archive = CACHE.read_bytes()
    else:
        archive = urllib.request.urlopen(URL, timeout=120).read()
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_bytes(archive)
    digest = hashlib.sha256(archive).hexdigest()
    if digest != SHA256:
        raise SystemExit(f"Unihan SHA-256 mismatch: {digest}")
    readings = zipfile.ZipFile(io.BytesIO(archive)).read("Unihan_Readings.txt").decode("utf-8")
    table: dict[int, str] = {}
    for line in readings.splitlines():
        if "\tkMandarin\t" not in line:
            continue
        point, _, value = line.split("\t", 2)
        number = int(point[2:], 16)
        if not (0x3400 <= number <= 0x9FFF or 0xF900 <= number <= 0xFAFF):
            continue
        first = value.split()[0]
        plain = "".join(
            char for char in unicodedata.normalize("NFD", first).lower()
            if "a" <= char <= "z"
        )
        if plain:
            table[number] = plain
    lines = [
        "-- Generated from Unicode 17.0.0 Unihan kMandarin; do not edit by hand.",
        "-- Unicode data license: https://www.unicode.org/copyright.html",
        f"-- Source SHA-256: {SHA256}",
        "GodSystemPinyinData = {",
    ]
    lines.extend(f"    [0x{point:X}] = {reading!r},".replace("'", '"') for point, reading in sorted(table.items()))
    lines.extend(["}", "return GodSystemPinyinData"])
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {len(table)} readings in {OUTPUT}")


if __name__ == "__main__":
    main()
