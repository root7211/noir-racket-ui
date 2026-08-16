#!/usr/bin/env python3
"""Generate focused negative Scene fixtures for shadow_surface_plan v1."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_shadow_surface_scene.py <input.json> <blur|offset|geometry|disable> <output.json>")
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    output = Path(sys.argv[3])
    scene = json.loads(source.read_text(encoding="utf-8"))
    shadow = scene.get("shadow_surface_plan")
    if not isinstance(shadow, dict) or not shadow.get("layers"):
        fail("input Scene must contain a nonempty shadow_surface_plan")
    scene = copy.deepcopy(scene)
    shadow = scene["shadow_surface_plan"]
    layer = shadow["layers"][0]
    if mode == "blur":
        layer["blur_px"] = float(layer["blur_px"]) + 1.0
    elif mode == "offset":
        layer["source_instance_offset"] = int(layer["source_instance_offset"]) + 44
    elif mode == "geometry":
        layer["width"] = float(layer["width"]) + 1.0
    elif mode == "disable":
        scene["shadow_surface_plan"] = False
    else:
        fail(f"unknown mutation {mode}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(scene, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"shadow mutation={mode} output={output}")


if __name__ == "__main__":
    main()
