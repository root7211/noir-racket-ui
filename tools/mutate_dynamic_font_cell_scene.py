#!/usr/bin/env python3
"""Create precise negative Scene samples for dynamic_font_cell_plan v1."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("kind", choices=("face", "uv", "word-offset"))
    args = parser.parse_args()

    scene = json.loads(args.source.read_text(encoding="utf-8"))
    plan = scene["dynamic_font_cell_plan"]
    table = plan["tables"][0]
    placement_slot = table["placement_slots"][0]

    if args.kind == "face":
        plan["face_id"] = "forged-tabular-face"
    elif args.kind == "uv":
        table["cell_uv"][0][0] += 1.0 / 256.0
    else:
        table["glyph_word_offsets"][0] += 4

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(json.dumps(scene, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
