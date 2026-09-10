"""B42.20.4 locomotion variants, generated from the locally installed XML.

No game files, clips or textures are changed/copied. Inheritance is resolved at
build time: cross-package relative x_extends paths are not portable in PZ.
Only a namespaced, conditional derivative is shipped. --check never writes.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "Contents/mods/GodSystem/42/media"
STATES = {"zombie": ("walktoward", "walktoward-network", "pathfind", "lunge", "lunge-network"),
          "zombie-crawler": ("walktoward", "walktoward-network", "pathfind")}


def inherited(path, sources, stack=()):
    path = path.resolve()
    if path in stack:
        raise ValueError(f"Cyclic animation inheritance: {path}")
    raw = path.read_bytes()
    sources[path] = hashlib.sha256(raw).hexdigest()
    child = ET.fromstring(raw)
    parent = child.get("x_extends")
    if not parent:
        return child
    result = copy.deepcopy(inherited(path.parent / parent, sources, (*stack, path)))
    for node in child:
        identity = (node.tag, node.get("x_name"))
        previous = next((v for v in result if (v.tag, v.get("x_name")) == identity), None)
        if previous is not None:
            if node.get("x_name"):
                merged = copy.deepcopy(previous)
                for part in node:
                    old = merged.find(part.tag)
                    if old is not None:
                        merged.remove(old)
                    merged.append(copy.deepcopy(part))
                result.remove(previous)
                result.append(merged)
                continue
            result.remove(previous)
        result.append(copy.deepcopy(node))
    return result


def outputs(game):
    sources, result, scales = {}, {}, {}
    for family, states in STATES.items():
        for state in states:
            for path in sorted((game / "media/AnimSets" / family / state).glob("*.xml")):
                node = inherited(path, sources)
                clip = node.findtext("m_AnimName", "")
                name = node.findtext("m_Name", path.stem)
                # Several B42 locomotion states select a clip-less default node
                # (for example zombie/walktoward/defaultWalktoward.xml).  Those
                # nodes are the normal fallback for the vast majority of
                # zombies, so a missing m_AnimName does *not* mean that this is
                # an abstract template.  The state allow-list above limits the
                # input to movement states; only explicit waiting/idle nodes
                # are excluded from that small set.
                if any(v in (path.stem + name + clip).lower() for v in ("wait", "idle")):
                    continue
                speed = float(node.findtext("m_SpeedScale", "1"))
                assert 0 < speed < 10, (path, speed)
                variable = "GSFreezeScale_" + str(round(speed * 10000))
                scales[variable] = speed
                for phase in (1, 2):
                    clone = copy.deepcopy(node)
                    clone.attrib.clear()
                    name = f"GodSystemFreeze_{phase}_{path.stem}"
                    clone.find("m_Name").text = name
                    element = clone.find("m_SpeedScale")
                    if element is None:
                        element = ET.SubElement(clone, "m_SpeedScale")
                    element.text = variable
                    condition = ET.SubElement(clone, "m_Conditions", {"x_name": "GodSystemFreezePhase"})
                    ET.SubElement(condition, "m_Name").text = "GSFreezePhase"
                    ET.SubElement(condition, "m_Type").text = "STRING"
                    ET.SubElement(condition, "m_Value").text = str(phase)
                    ET.indent(clone, space="    ")
                    content = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(clone, encoding="unicode") + "\n"
                    result[MEDIA / "AnimSets" / family / state / (name + ".xml")] = content
    assert len(result) > 50, "Missing native animation inputs"
    # Guard the regression that made the first in-game experiment appear to
    # do nothing: these clip-less defaults are selected for ordinary zombies.
    required_defaults = {
        MEDIA / "AnimSets/zombie/walktoward/GodSystemFreeze_1_defaultWalktoward.xml",
        MEDIA / "AnimSets/zombie/pathfind/GodSystemFreeze_1_default.xml",
        MEDIA / "AnimSets/zombie/lunge/GodSystemFreeze_1_defaultLunge.xml",
    }
    assert required_defaults <= set(result), "Missing default locomotion freeze nodes"
    lines = ["-- Generated B42.20.4 locomotion scales; do not edit by hand.", "GodSystemFreezeAnimationScales = {"]
    lines += [f'    {key} = {value},' for key, value in sorted(scales.items())]
    lines += ["}", "return GodSystemFreezeAnimationScales", ""]
    result[MEDIA / "lua/shared/GodSystem_FreezeAnimationScales.lua"] = "\n".join(lines)
    manifest = {"patch": "42.20.4", "nodes": len(result) - 1,
                "sources": {p.relative_to(game).as_posix(): h for p, h in sorted(sources.items())}}
    result[ROOT / "tools/equipment/freeze_native_manifest.json"] = json.dumps(manifest, indent=2) + "\n"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=Path(r"C:\APPS\Steam\steamapps\common\ProjectZomboid"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = outputs(args.game.resolve())
    for path, content in expected.items():
        if args.check:
            assert path.read_text(encoding="utf-8") == content, f"Stale generated animation: {path}"
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    actual = set((MEDIA / "AnimSets").rglob("GodSystemFreeze_*.xml"))
    assert actual == {p for p in expected if p.suffix == ".xml"}, "Unexpected stale freeze nodes"
    print(f"Freeze animation {'check' if args.check else 'generation'} passed: {len(actual)} conditional nodes")


if __name__ == "__main__":
    main()
