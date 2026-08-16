#!/usr/bin/env python3
"""Create focused attacks against Noir's compiler-owned release_motion v1 tracks."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("duration", "offset", "damage", "drop"))
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    scene = json.loads(args.source.read_text(encoding="utf-8"))
    tracks = scene["animation_tracks"]
    if not tracks:
        raise SystemExit("source scene has no animation tracks")
    if args.mode == "duration":
        tracks[0]["duration_ms"] = 81
    elif args.mode == "offset":
        tracks[0]["pos_offset"] += 44
    elif args.mode == "damage":
        tracks[0]["damage"]["x"] += 1.0
    elif args.mode == "drop":
        scene["animation_tracks"] = tracks[1:]
    args.output.write_text(json.dumps(scene, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"mode": args.mode, "output": str(args.output)}, sort_keys=True))


if __name__ == "__main__":
    main()
