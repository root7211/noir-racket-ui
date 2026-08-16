#!/usr/bin/env python3
"""Strict structural oracle for Noir Visual Language v2 Scenes."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

PRIMITIVE_TAGS = {
    "button", "overlay", "row", "scrollbar", "scrollbar-thumb",
    "stack", "text", "virtual-list",
}

EXPECTED = {
    "log": {
        "root": "log-browser-dashboard",
        "rail": "log-brand-rail",
        "header": "log-app-bar",
        "table": "log-table-card",
        "list": "system-log",
        "detail": "log-detail-card",
        "action": "log-append-action",
        "list_id": "system-log",
        "table_id": "system-log-data",
        "page3_cells": 128,
        "rects": {
            "log-browser-dashboard": (32.0, 32.0, 1216.0, 656.0),
            "log-brand-rail": (32.0, 32.0, 168.0, 656.0),
            "log-table-card": (236.0, 228.0, 996.0, 300.0),
            "system-log": (236.0, 312.0, 996.0, 128.0),
            "log-detail-card": (236.0, 544.0, 996.0, 128.0),
            "log-append-action": (1024.0, 616.0, 176.0, 40.0),
        },
    },
    "monitor": {
        "root": "monitor-shell",
        "rail": "monitor-brand-rail",
        "header": "monitor-app-bar",
        "table": "monitor-table-card",
        "list": "telemetry-grid",
        "detail": "monitor-detail-card",
        "action": "monitor-refresh-action",
        "list_id": "telemetry-grid",
        "table_id": "telemetry-registers",
        "page3_cells": 144,
        "rects": {
            "monitor-shell": (32.0, 32.0, 1216.0, 656.0),
            "monitor-brand-rail": (32.0, 32.0, 168.0, 656.0),
            "monitor-table-card": (236.0, 228.0, 996.0, 300.0),
            "telemetry-grid": (236.0, 312.0, 996.0, 128.0),
            "monitor-detail-card": (236.0, 544.0, 996.0, 128.0),
            "monitor-refresh-action": (1024.0, 616.0, 176.0, 40.0),
        },
    },
}


def close(a: float, b: float, eps: float = 1e-5) -> bool:
    return math.isclose(float(a), float(b), rel_tol=0.0, abs_tol=eps)


def fail(message: str) -> None:
    raise AssertionError(message)


def verify(scene_path: Path, kind: str) -> dict:
    if kind not in EXPECTED:
        fail(f"unknown Scene kind {kind!r}")
    expected = EXPECTED[kind]
    scene = json.loads(scene_path.read_text(encoding="utf-8"))

    visual = scene["visual_language_plan"]
    if visual["abi_schema"] != "noir-visual-language-plan-v1" or visual["abi_revision"] != 1:
        fail("visual language ABI contract changed")
    if visual["preset"] != "desktop-wide":
        fail("visual v2 requires desktop-wide preset")
    canvas = visual["canvas"]
    if not (close(canvas["width"], 1280.0) and close(canvas["height"], 720.0) and close(canvas["margin"], 32.0)):
        fail(f"unexpected visual canvas {canvas}")

    layout = scene["layout_plan"]
    by_id = {entry["id"]: entry for entry in layout}
    if len(by_id) != len(layout):
        fail("layout IDs are not unique")
    tags = {entry["tag"] for entry in layout}
    unexpected_tags = sorted(tags - PRIMITIVE_TAGS)
    if unexpected_tags:
        fail(f"high-level component tags leaked into Scene: {unexpected_tags}")

    for required in ("root", "rail", "header", "table", "list", "detail", "action"):
        node_id = expected[required]
        if node_id not in by_id:
            fail(f"missing visual v2 node {node_id}")

    for node_id, wanted in expected["rects"].items():
        entry = by_id[node_id]
        actual = (entry["x"], entry["y"], entry["width"], entry["height"])
        if not all(close(a, b) for a, b in zip(actual, wanted)):
            fail(f"{node_id} rect {actual} != {wanted}")

    violations = []
    for entry in layout:
        x, y, width, height = map(float, (entry["x"], entry["y"], entry["width"], entry["height"]))
        if x < -1e-5 or y < -1e-5 or x + width > 1280.0 + 1e-5 or y + height > 720.0 + 1e-5:
            violations.append((entry["id"], (x, y, width, height)))
    if violations:
        fail(f"layout escapes visual canvas: {violations[:4]}")

    list_plan = next(plan for plan in scene["virtual_list_plans"] if plan["id"] == expected["list_id"])
    if (list_plan["logical_capacity"], list_plan["physical_slots"], list_plan["visible_rows"], list_plan["row_height"]) != (10000, 4, 4, 32):
        fail(f"frozen list geometry changed: {list_plan}")

    dynamic_plan = scene["dynamic_font_cell_plan"]
    if dynamic_plan["atlas_page"] != 3 or dynamic_plan["glyph_domain_count"] != 37 or not close(dynamic_plan["fixed_advance"], 10.0):
        fail("dynamic page-3 tabular contract changed")
    tables = {table["table_id"]: table for table in dynamic_plan["tables"]}
    if expected["table_id"] not in tables:
        fail(f"dynamic font table {expected['table_id']} missing")

    pages: dict[int, int] = {}
    for placement in scene["glyph_placement_plan"]:
        page = int(placement["atlas_page"])
        pages[page] = pages.get(page, 0) + 1
    if pages.get(3) != expected["page3_cells"]:
        fail(f"page-3 fixed cell count {pages.get(3)} != {expected['page3_cells']}")
    if pages.get(2, 0) < 200:
        fail(f"visual v2 static chrome unexpectedly small: page2={pages.get(2, 0)}")
    if pages.get(1) != 29:
        fail(f"fixed detail cell count changed: page1={pages.get(1)}")

    return {
        "scene": str(scene_path),
        "kind": kind,
        "layout_nodes": len(layout),
        "primitive_tags": sorted(tags),
        "canvas_violations": 0,
        "glyph_pages": {str(key): value for key, value in sorted(pages.items())},
        "list_geometry": "10000 logical / 4 physical / 4x32 viewport",
        "status": "PASS",
    }


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_visual_language_v2.py <log|monitor> <scene.json>")
    result = verify(Path(sys.argv[2]), sys.argv[1])
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
