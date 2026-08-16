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
    "material-icon",
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
    "material-overview$icon",
    "material-systems$icon",
    "material-alerts$icon",
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

    shadow = scene["shadow_surface_plan"]
    if not isinstance(shadow, dict):
        fail("desktop Material Scene may not disable shadow_surface_plan")
    if (shadow["abi_schema"], shadow["abi_revision"]) != ("noir-shadow-surface-plan-v1", 1):
        fail(f"unexpected shadow contract {shadow}")
    elevated = {entry["id"]: entry for entry in layout if int(entry.get("elevation", 0)) > 0}
    if set(elevated) != {"material-summary-card", "material-performance-card", "material-activity-card"}:
        fail(f"unexpected fixed Material elevation domain {sorted(elevated)}")
    by_source: dict[str, list[dict]] = {}
    for layer in shadow["layers"]:
        by_source.setdefault(layer["source_id"], []).append(layer)
    if set(by_source) != set(elevated) or len(shadow["layers"]) != 2 * len(elevated):
        fail("shadow plan must contain exactly two static layers for each elevated Material card")
    for source_id, source_layers in by_source.items():
        layout_entry = elevated[source_id]
        if sorted(int(layer["layer"]) for layer in source_layers) != [1, 2]:
            fail(f"shadow source {source_id} has noncanonical layer IDs")
        for layer in source_layers:
            index = int(layer["layer"])
            blur, opacity = {1: (3.0, 0.14), 2: (7.0, 0.055)}[index]
            if not (
                int(layer["elevation"]) == 1
                and int(layer["source_instance_offset"]) == int(layout_entry["instance_offset"])
                and close(layer["blur_px"], blur)
                and close(layer["opacity"], opacity)
                and close(layer["x"], float(layout_entry["x"]) - blur)
                and close(layer["y"], float(layout_entry["y"]) - blur)
                and close(layer["width"], float(layout_entry["width"]) + 2.0 * blur)
                and close(layer["height"], float(layout_entry["height"]) + 2.0 * blur)
                and float(layer["radius_px"]) > 0.0
            ):
                fail(f"shadow source {source_id} layer {index} disagrees with fixed layout recipe")

    if [entry["node"] for entry in scene["event_map"]] != [
        "material-overview$target", "material-systems$target", "material-alerts$target", "material-refresh-button"
    ]:
        fail("Material controls did not lower to the expected fixed rail/button event targets")
    if list(scene["actions"].keys()) != [
        "material-refresh", "material-select-alerts", "material-select-overview", "material-select-systems"
    ]:
        fail("Material action table changed")
    if scene["state_slots"] != [
        {"id": "material-navigation", "index": 0, "initial": 0},
        {"id": "refresh-count", "index": 1, "initial": 0},
    ]:
        fail("Material fixture must retain its fixed navigation and refresh state slots")
    page2 = [entry for entry in scene["glyph_placement_plan"] if entry["atlas_page"] == 2]
    if len(page2) != 224:
        fail(f"Material icon fixture must contain exactly 224 static page-2 glyphs, got {len(page2)}")
    assets = scene["font_assets"]
    if len(assets) != 1 or assets[0]["face_id"] != "noir-desktop-sans-18" or assets[0]["glyph_domain_count"] != 102:
        fail("Material icon domain must be the 102-glyph page-2 desktop asset")
    icons = {entry["node"]: entry for entry in page2 if entry["node"].endswith("$icon")}
    expected_icons = {
        "material-overview$icon": 99,
        "material-systems$icon": 101,
        "material-alerts$icon": 97,
    }
    if set(icons) != set(expected_icons):
        fail(f"unexpected icon placement nodes {sorted(icons)}")
    for node, glyph_index in expected_icons.items():
        icon = icons[node]
        if icon["glyph_id"] != (2 << 16) | glyph_index or icon["face_id"] != "noir-desktop-sans-18" or icon["dynamic"]:
            fail(f"icon placement {node} is not a static page-2 glyph witness")

    print(json.dumps({
        "scene": str(path),
        "layout_nodes": len(layout),
        "rounded_surfaces": len(rounded["surfaces"]),
        "shadow_layers": len(shadow["layers"]),
        "static_page2_glyphs": len(page2),
        "status": "PASS",
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
