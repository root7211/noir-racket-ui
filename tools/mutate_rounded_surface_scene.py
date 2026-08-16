#!/usr/bin/env python3
"""Create precise rounded_surface_plan v1 negative-test Scene variants."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("dest", type=Path)
    parser.add_argument("mode", choices=("radius", "offset", "geometry", "disable"))
    args = parser.parse_args()

    scene = json.loads(args.source.read_text(encoding="utf-8"))
    plan = scene.get("rounded_surface_plan")
    if not isinstance(plan, dict) or not plan.get("surfaces"):
        raise SystemExit("source Scene lacks a nonempty rounded_surface_plan")
    surface = plan["surfaces"][0]
    if args.mode == "radius":
        surface["radius_px"] = max(float(surface["width"]), float(surface["height"]))
    elif args.mode == "offset":
        surface["instance_offset"] = int(surface["instance_offset"]) + 44
    elif args.mode == "geometry":
        surface["width"] = float(surface["width"]) + 1.0
    else:
        scene["rounded_surface_plan"] = False
    args.dest.parent.mkdir(parents=True, exist_ok=True)
    args.dest.write_text(json.dumps(scene, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"mutated rounded_surface_plan mode={args.mode} output={args.dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
