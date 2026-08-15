#!/usr/bin/env python3
"""Create one deliberately invalid page-2 placement Scene for startup-proof tests."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[1] not in {"face", "uv"}:
        raise SystemExit("usage: mutate_font_placement_scene.py {face|uv} INPUT.json OUTPUT.json")
    mode, input_path, output_path = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    scene = json.loads(input_path.read_text(encoding="utf-8"))
    placement = next(item for item in scene["glyph_placement_plan"] if item["atlas_page"] == 2)
    if mode == "face":
        placement["face_id"] = "tampered-font-face"
    else:
        placement["atlas_uv"][0] += 0.03125
    output_path.write_text(json.dumps(scene, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
