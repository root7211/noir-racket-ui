#!/usr/bin/env python3
"""Audit compiler-emitted layout bounds against visual_language_plan canvas."""
import json
import sys
from pathlib import Path

scene_path = Path(sys.argv[1])
scene = json.loads(scene_path.read_text(encoding="utf-8"))
canvas = scene["visual_language_plan"]["canvas"]
width = float(canvas["width"])
height = float(canvas["height"])
violations = []
for entry in scene["layout_plan"]:
    x_ndc, y_ndc = entry["ndc_pos"]
    w_ndc, h_ndc = entry["ndc_size"]
    x = (x_ndc + 1.0) * width * 0.5
    y = (1.0 - y_ndc - h_ndc) * height * 0.5
    w = w_ndc * width * 0.5
    h = h_ndc * height * 0.5
    if x < -0.001 or y < -0.001 or x + w > width + 0.001 or y + h > height + 0.001:
        violations.append({"id": entry["id"], "tag": entry.get("tag"), "rect": [x, y, w, h]})
print(json.dumps({"preset": scene["visual_language_plan"]["preset"], "canvas": canvas, "violation_count": len(violations), "violations": violations}, indent=2))
