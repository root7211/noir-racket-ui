#!/usr/bin/env python3
"""Structural oracle for Noir overlay_state_plan v1 scenes."""
from __future__ import annotations

import json
import sys
from pathlib import Path

SCHEMA = "noir-overlay-state-plan-v1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def verify(path: Path) -> None:
    scene = json.loads(path.read_text(encoding="utf-8"))
    plan = scene["overlay_state_plan"]
    require(plan["abi_schema"] == SCHEMA and plan["abi_revision"] == 1,
            "overlay_state_plan ABI is not v1")
    entries = plan["entries"]
    require(len(entries) == 1, "overlay showcase must contain exactly one overlay transition table")
    entry = entries[0]
    require(entry["id"] == "deployment-overlay", "unexpected overlay id")
    require(entry["state"] == "overlay-visible" and entry["state_index"] == 0
            and entry["initial_visible"] == 0, "overlay initial closed-state proof mismatch")
    require(entry["open_action"] == "overlay-open", "missing fixed open action")
    require(entry["close_actions"] == ["overlay-confirm", "overlay-dismiss", "overlay-pin", "overlay-copy", "overlay-export"],
            "close actions are not the compiler-fixed v1 sequence")
    require(entry["event_slots"] == list(range(7)), "overlay event slots are not a dense fixed table")
    offsets = entry["instance_offsets"]
    require(len(offsets) == 26 and offsets == sorted(offsets) and all(value > 0 and value % 44 == 0 for value in offsets),
            "overlay quad alpha addresses are not fixed QuadInstance slots")
    glyph_slots = entry["glyph_slots"]
    require(len(glyph_slots) == 120 and glyph_slots == list(range(110, 230)),
            "overlay glyph alpha addresses do not cover the fixed dialog/menu subtree")
    require(entry["tile_ids"] == [0], "overlay transition widened beyond its fixed local tile")

    high_level = {"material-overlay-state", "material-dialog", "material-menu", "material-menu-item"}
    require(not any(item["tag"] in high_level for item in scene["layout_plan"]),
            "high-level overlay components leaked into Scene layout")
    actions = scene["actions"]
    for action_id, target in [("overlay-open", 1), *[(action, 0) for action in entry["close_actions"]]]:
        action = actions[action_id]
        require(action["writes"] == [{"op": "set", "state": "overlay-visible", "state_index": 0, "value": target}],
                f"{action_id} is not a literal overlay visibility transition")
        require(action["gpu_updates"] == [] and action["instance_updates"] == []
                and action["tile_ids"] == [0], f"{action_id} widened its compiler-owned work scope")

    events = scene["event_map"]
    require([event["slot"] for event in events] == list(range(7)), "event slots are not stable")
    require([event["action"] for event in events] == ["overlay-open", "overlay-dismiss", "overlay-dismiss", "overlay-confirm", "overlay-pin", "overlay-copy", "overlay-export"],
            "event action mapping disagrees with transition table")
    transparent_nodes = {"deployment-scrim$target", "menu-pin$target", "menu-copy$target", "menu-export$target"}
    require(all(event["base_color"] == [0.0, 0.0, 0.0, 0.0]
                and event["hover_color"] == [0.0, 0.0, 0.0, 0.0]
                and event["pressed_color"] == [0.0, 0.0, 0.0, 0.0]
                for event in events if event["node"] in transparent_nodes),
            "overlay transparent hit targets have visual color")

    shadow_sources = {layer["source_id"] for layer in scene["shadow_surface_plan"]["layers"]}
    require({"deployment-dialog", "deployment-menu"} <= shadow_sources,
            "overlay lacks compiler-owned dialog/menu elevation shadows")
    print("OVERLAY_STATE_PLAN_V1_SCENE_ORACLE: PASS")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} <scene.json>")
    verify(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
