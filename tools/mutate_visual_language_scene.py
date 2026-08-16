#!/usr/bin/env python3
"""Create focused visual_language_plan v1 admission attacks."""
import copy
import json
import sys
from pathlib import Path

kind, source, target = sys.argv[1:]
scene = json.loads(Path(source).read_text(encoding="utf-8"))
mutated = copy.deepcopy(scene)
plan = mutated["visual_language_plan"]
if kind == "schema":
    plan["abi_schema"] = "noir-visual-language-plan-v9"
elif kind == "preset":
    plan["preset"] = "unbounded-desktop"
elif kind == "canvas":
    plan["canvas"]["width"] = 1279.0
else:
    raise SystemExit("kind must be schema, preset, or canvas")
Path(target).write_text(json.dumps(mutated, separators=(",", ":")), encoding="utf-8")
print(f"mutated visual language scene: {kind} -> {target}")
