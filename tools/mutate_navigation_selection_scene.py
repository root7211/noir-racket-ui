#!/usr/bin/env python3
"""Generate focused negative Scene fixtures for navigation_selection_plan v1."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: mutate_navigation_selection_scene.py "
            "<input.json> <target|offset|tile|disable> <output.json>"
        )
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    output = Path(sys.argv[3])
    scene = json.loads(source.read_text(encoding="utf-8"))
    plan = scene.get("navigation_selection_plan")
    if not isinstance(plan, dict) or not plan.get("destinations"):
        fail("input Scene must contain a nonempty navigation_selection_plan")
    scene = copy.deepcopy(scene)
    plan = scene["navigation_selection_plan"]
    destination = plan["destinations"][1]
    if mode == "target":
        destination["target_value"] = int(destination["target_value"]) + 10
    elif mode == "offset":
        destination["instance_offset"] = int(destination["instance_offset"]) + 44
    elif mode == "tile":
        destination["tile_ids"] = [0]
    elif mode == "disable":
        scene["navigation_selection_plan"] = False
    else:
        fail(f"unknown mutation {mode}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(scene, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"navigation selection mutation={mode} output={output}")


if __name__ == "__main__":
    main()
