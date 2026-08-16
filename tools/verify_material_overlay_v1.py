#!/usr/bin/env python3
"""Structural oracle for the bounded Material dialog/menu showcase."""
from __future__ import annotations

import json
import sys
from pathlib import Path


ZERO = [0.0, 0.0, 0.0, 0.0]
ACTIONS = ["overlay-confirm", "overlay-dismiss", "overlay-pin", "overlay-copy", "overlay-export"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_material_overlay_v1.py <scene.json>")
    scene = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    require(scene["visual_language_plan"]["preset"] == "desktop-wide", "showcase must be desktop-wide")
    require(scene["navigation_selection_plan"] is False, "dialog/menu fixture may not synthesize a rail plan")
    layout = {entry["id"]: entry for entry in scene["layout_plan"]}
    for node_id in [
        "deployment-dialog$layer", "deployment-scrim", "deployment-dialog", "deployment-menu",
        "deployment-confirm", "deployment-dismiss", "menu-pin", "menu-copy", "menu-export",
    ]:
        require(node_id in layout, f"missing static node {node_id}")
    require(layout["deployment-dialog$layer"]["width"] == 1216 and layout["deployment-dialog$layer"]["height"] == 656,
            "dialog layer must remain within compiler-owned desktop frame")
    require(layout["deployment-scrim"]["width"] == 1216 and layout["deployment-scrim"]["height"] == 656,
            "scrim geometry must equal the static desktop frame")
    # Scene layout coordinates are absolute within the 1280×720 canvas: component
    # local anchors are offset by the compiler-owned 32px desktop frame margin.
    require(layout["deployment-dialog"]["x"] == 392 and layout["deployment-dialog"]["y"] == 216,
            "dialog anchor changed")
    require(layout["deployment-menu"]["x"] == 928 and layout["deployment-menu"]["y"] == 164,
            "menu anchor changed")
    events = {event["node"]: event for event in scene["event_map"]}
    require(events["deployment-confirm"]["action"] == "overlay-confirm", "confirm action mismatch")
    require(events["deployment-dismiss"]["action"] == "overlay-dismiss", "dismiss action mismatch")
    for node, action in [("menu-pin$target", "overlay-pin"), ("menu-copy$target", "overlay-copy"),
                         ("menu-export$target", "overlay-export")]:
        event = events[node]
        require(event["action"] == action, f"menu action mismatch for {node}")
        require(event["base_color"] == ZERO and event["hover_color"] == ZERO and event["pressed_color"] == ZERO,
                f"menu event witness {node} must remain transparent")
    require(sorted(scene["actions"].keys()) == sorted(ACTIONS), "unexpected action surface")
    for action in ACTIONS:
        record = scene["actions"][action]
        require(record["writes"] == [{"state": "overlay-count", "state_index": 0, "op": "add", "value": 1}],
                f"{action} must be one literal counter increment")
        require(len(record["gpu_updates"]) == 1 and record["instance_updates"] == [],
                f"{action} must only patch the preallocated counter glyph run")
    shadows = scene["shadow_surface_plan"]
    require(isinstance(shadows, dict) and len(shadows["layers"]) == 6, "expected six static shadow layers")
    sources = {layer["source_id"] for layer in shadows["layers"]}
    require(sources == {"overlay-context-card", "deployment-dialog", "deployment-menu"},
            "shadow sources are not the fixed elevated surfaces")
    forbidden_tags = {"material-dialog", "material-menu", "material-menu-item"}
    require(not any(entry["tag"] in forbidden_tags for entry in scene["layout_plan"]),
            "high-level overlay component tag leaked into Scene")
    print("MATERIAL_DIALOG_MENU_SCENE_ORACLE: PASS static-overlay=1 menu-items=3 actions=5 shadows=6")


if __name__ == "__main__":
    main()
