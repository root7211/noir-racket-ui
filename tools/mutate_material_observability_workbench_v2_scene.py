#!/usr/bin/env python3
"""Create noncanonical workbench v2 Scene variants for startup-proof regression."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_material_observability_workbench_v2_scene.py INPUT mode OUTPUT")
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    target = Path(sys.argv[3])
    document = json.loads(source.read_text(encoding="utf-8"))
    plan = document["material_observability_workbench_plan"]
    if mode == "offset":
        plan["data_views"][1]["instance_offsets"][0] += 44
    elif mode == "node":
        plan["data_views"][1]["node_ids"][0] = "observability-log"
    elif mode == "tile":
        plan["data_views"][1]["tile_ids"] = [63]
    elif mode == "disable":
        document["material_observability_workbench_plan"] = False
    else:
        raise SystemExit("mode must be offset, node, tile, or disable")
    target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
