#!/usr/bin/env python3
"""Strict structural oracle for the Noir Material Profile v1 fixture."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path


HIGH_LEVEL_TAGS = {
    "material-app-bar",
    "material-card",
    "material-filled-button",
    "material-nav-rail",
    "material-destination",
}
REQUIRED_LAYOUT_IDS = {
    "material-profile-dashboard",
    "material-nav-rail",
    "material-overview",
    "material-app-bar",
    "material-summary-card",
    "material-performance-card",
    "material-activity-card",
    "material-refresh-button",
}
REQUIRED_ROUNDED_IDS = {
    "material-nav-rail",
    "material-overview",
    "material-summary-card",
    "material-performance-card",
    "material-activity-card",
    "material-refresh-button",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def close(actual: float, wanted: float) -> bool:
    return math.isclose(float(actual), wanted, rel_tol=0.0, abs_tol=1e-5)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_material_profile_v1.py <scene.json>")
    path = Path(sys.argv[1])
    scene = json.loads(path.read_text(encoding="utf-8"))

    visual = scene["visual_language_plan"]
    if (visual["abi_schema"], visual["abi_revision"], visual["preset"]) != (
        "noir-visual-language-plan-v1", 1, "desktop-wide"
    ):
        fail(f"unexpected visual contract {visual}")
    canvas = visual["canvas"]
    if not (close(canvas["width"], 1280.0) and close(canvas["height"], 720.0) and close(canvas["margin"], 32.0)):
        fail(f"unexpected desktop-wide canvas {canvas}")

    layout = scene["layout_plan"]
    by_id = {entry["id"]: entry for entry in layout}
    if len(by_id) != len(layout):
        fail("layout ids are not unique")
    missing = sorted(REQUIRED_LAYOUT_IDS - set(by_id))
    if missing:
        fail(f"missing Material layout nodes {missing}")
    leaked = sorted({entry["tag"] for entry in layout} & HIGH_LEVEL_TAGS)
    if leaked:
        fail(f"Material component tags leaked into runtime Scene {leaked}")
    escaped = [
        entry["id"] for entry in layout
        if float(entry["x"]) < 0 or float(entry["y"]) < 0
        or float(entry["x"]) + float(entry["width"]) > 1280.0
        or float(entry["y"]) + float(entry["height"]) > 720.0
    ]
    if escaped:
        fail(f"layout escapes fixed canvas {escaped}")

    rounded = scene["rounded_surface_plan"]
    if not isinstance(rounded, dict):
        fail("desktop Material Scene may not disable rounded_surface_plan")
    if (rounded["abi_schema"], rounded["abi_revision"], rounded["aa_width_px"]) != (
        "noir-rounded-surface-plan-v1", 1, 1.0
    ):
        fail(f"unexpected rounded contract {rounded}")
    rounded_ids = {entry["id"] for entry in rounded["surfaces"]}
    missing_rounded = sorted(REQUIRED_ROUNDED_IDS - rounded_ids)
    if missing_rounded:
        fail(f"missing static rounded Material surfaces {missing_rounded}")
    if any(float(entry["radius_px"]) <= 0 or float(entry["aa_width_px"]) != 1.0 for entry in rounded["surfaces"]):
        fail("rounded Material metadata must contain positive radius and fixed 1px AA")

    if [entry["node"] for entry in scene["event_map"]] != ["material-refresh-button"]:
        fail("filled Material button did not lower to the expected fixed event target")
    if list(scene["actions"].keys()) != ["material-refresh"]:
        fail("Material action table changed")
    if scene["state_slots"] != [{"id": "refresh-count", "index": 0, "initial": 0}]:
        fail("Material fixture must retain one fixed state slot")
    if sum(1 for entry in scene["glyph_placement_plan"] if entry["atlas_page"] == 2) < 100:
        fail("Material chrome page-2 placement unexpectedly small")

    print(json.dumps({
        "scene": str(path),
        "layout_nodes": len(layout),
        "rounded_surfaces": len(rounded["surfaces"]),
        "static_page2_glyphs": sum(1 for entry in scene["glyph_placement_plan"] if entry["atlas_page"] == 2),
        "status": "PASS",
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
