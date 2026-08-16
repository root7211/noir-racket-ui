#!/usr/bin/env python3
"""Create targeted overlay_state_plan v1 attack scenes for startup-proof regression."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


def mutate(scene: dict, mode: str) -> dict:
    result = copy.deepcopy(scene)
    plan = result["overlay_state_plan"]
    if mode == "initial":
        plan["entries"][0]["initial_visible"] = 2
    elif mode == "offset":
        plan["entries"][0]["instance_offsets"][0] += 4
    elif mode == "tile":
        plan["entries"][0]["tile_ids"] = [1]
    elif mode == "disable":
        result["overlay_state_plan"] = False
    else:
        raise ValueError(f"unknown mutation mode {mode!r}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("mode", choices=("initial", "offset", "tile", "disable"))
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with args.input.open(encoding="utf-8") as stream:
        scene = json.load(stream)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        json.dump(mutate(scene, args.mode), stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(f"overlay mutation {args.mode}: {args.output}")


if __name__ == "__main__":
    main()
