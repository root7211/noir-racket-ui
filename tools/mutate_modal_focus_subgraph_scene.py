#!/usr/bin/env python3
"""Create targeted modal_focus_subgraph v1 attack scenes for startup-proof regression."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


def mutate(scene: dict, mode: str) -> dict:
    result = copy.deepcopy(scene)
    plan = result["modal_focus_subgraph_plan"]
    if mode == "edge":
        # Break the compiler-emitted cyclic Tab successor for the first target.
        plan["entries"][0]["next_slots"][0] = plan["entries"][0]["next_slots"][1]
    elif mode == "allowed":
        # Illegally admit the background open event while the overlay is visible.
        plan["entries"][0]["allowed_event_slots"] = [0, *plan["entries"][0]["allowed_event_slots"]]
    elif mode == "tile":
        # Widen the compiler-proved local overlay tile set.
        plan["entries"][0]["tile_ids"] = [1]
    elif mode == "disable":
        result["modal_focus_subgraph_plan"] = False
    else:
        raise ValueError(f"unknown mutation mode {mode!r}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("mode", choices=("edge", "allowed", "tile", "disable"))
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with args.input.open(encoding="utf-8") as stream:
        scene = json.load(stream)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        json.dump(mutate(scene, args.mode), stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(f"modal focus mutation {args.mode}: {args.output}")


if __name__ == "__main__":
    main()
