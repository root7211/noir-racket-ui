#!/usr/bin/env python3
"""Create one deliberately noncanonical material workbench Scene mutation."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_material_observability_workbench_scene.py INPUT.json MODE OUTPUT.json")
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    target = Path(sys.argv[3])
    scene = json.loads(source.read_text(encoding="utf-8"))
    mutated = copy.deepcopy(scene)
    plan = mutated["material_observability_workbench_plan"]
    if mode == "offset":
        plan["views"][0]["instance_offsets"][0] += 44
    elif mode == "node":
        plan["views"][1]["node_ids"][-1] = "forged-workbench-node"
    elif mode == "tile":
        plan["views"][2]["tile_ids"] = [1]
    elif mode == "disable":
        mutated["material_observability_workbench_plan"] = False
        mutated["material_observability_workbench_required"] = True
    else:
        raise SystemExit(f"unknown mode {mode}; expected offset, node, tile, or disable")
    target.write_text(json.dumps(mutated, separators=(",", ":")), encoding="utf-8")
    print(f"material workbench mutation={mode} output={target}")


if __name__ == "__main__":
    main()
