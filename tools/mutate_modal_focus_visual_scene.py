#!/usr/bin/env python3
"""Create targeted modal_focus_visual_plan v1 proof-violation scenes."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


def mutate(scene: dict, mode: str) -> dict:
    result = copy.deepcopy(scene)
    if mode == "disable":
        result["modal_focus_visual_plan"] = False
        return result

    entry = result["modal_focus_visual_plan"]["entries"][0]
    if mode == "source":
        # Preserve 44-byte alignment but break the Event Map reverse witness.
        entry["source_instance_offset"] += 44
    elif mode == "geometry":
        # Break the fixed 3px halo expansion while leaving a plausible positive rect.
        entry["width"] += 1.0
    elif mode == "tile":
        # Escape the admitted overlay-local tile scope.
        entry["tile_ids"] = [1]
    else:
        raise ValueError(f"unknown mutation mode {mode!r}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("mode", choices=("source", "geometry", "tile", "disable"))
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with args.input.open(encoding="utf-8") as stream:
        scene = json.load(stream)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        json.dump(mutate(scene, args.mode), stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(f"modal focus visual mutation {args.mode}: {args.output}")


if __name__ == "__main__":
    main()
