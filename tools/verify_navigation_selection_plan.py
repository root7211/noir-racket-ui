#!/usr/bin/env python3
"""Structural oracle for noir-navigation-selection-plan-v1 Scene artifacts."""
from __future__ import annotations

import json
import sys
from pathlib import Path


ZERO = [0.0, 0.0, 0.0, 0.0]
EXPECTED_IDS = ["material-overview", "material-systems", "material-alerts"]
EXPECTED_ACTIONS = [
    "material-select-overview",
    "material-select-systems",
    "material-select-alerts",
]
EXPECTED_TILES = [[1], [2], [3]]
EXPECTED_OFFSETS = [88, 264, 440]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_navigation_selection_plan.py <scene.json>")
    scene_path = Path(sys.argv[1])
    scene = json.loads(scene_path.read_text(encoding="utf-8"))
    contracts = scene["abi_contracts"]
    require(contracts["navigation_selection_plan"] == {
        "schema": "noir-navigation-selection-plan-v1", "revision": 1
    }, "navigation selection ABI contract mismatch")
    require(scene["visual_language_plan"]["preset"] == "desktop-wide", "fixture must use desktop-wide canvas")
    plan = scene["navigation_selection_plan"]
    require(isinstance(plan, dict), "desktop scene must carry a navigation selection plan")
    require(plan["abi_schema"] == "noir-navigation-selection-plan-v1" and plan["abi_revision"] == 1,
            "navigation selection payload ABI mismatch")
    require(plan["rail_id"] == "material-nav-rail", "unexpected rail binding")
    require(plan["state"] == "material-navigation" and plan["state_index"] == 0,
            "selection state slot mismatch")
    require(plan["initial_destination"] == "material-overview" and plan["initial_value"] == 0,
            "initial destination/value mismatch")
    destinations = plan["destinations"]
    require(len(destinations) == 3, "fixture must have exactly three static destinations")
    require([entry["id"] for entry in destinations] == EXPECTED_IDS, "destination order mismatch")
    require([entry["action"] for entry in destinations] == EXPECTED_ACTIONS, "selection action mapping mismatch")
    require([entry["target_value"] for entry in destinations] == [0, 1, 2], "selection target values are not canonical")
    require([entry["instance_offset"] for entry in destinations] == EXPECTED_OFFSETS,
            "destination source instance addresses changed")
    require([entry["tile_ids"] for entry in destinations] == EXPECTED_TILES,
            "destination tile scope changed")
    require(len({entry["event_node"] for entry in destinations}) == 3,
            "destination event nodes must be unique")
    require(all(entry["event_node"] == f"{entry['id']}$target" for entry in destinations),
            "event targets must be compiler-derived destination children")
    layout = {entry["id"]: entry for entry in scene["layout_plan"]}
    for entry in destinations:
        source = layout[entry["id"]]
        require(source["tag"] == "stack" and source["instance_offset"] == entry["instance_offset"],
                f"source witness mismatch for {entry['id']}")
    events = {entry["node"]: entry for entry in scene["event_map"]}
    for entry in destinations:
        event = events[entry["event_node"]]
        require(event["action"] == entry["action"] and event["action_index"] == entry["action_slot_index"],
                f"event/action slot mismatch for {entry['id']}")
        require(event["base_color"] == ZERO and event["hover_color"] == ZERO and event["pressed_color"] == ZERO,
                f"event witness for {entry['id']} is not transparent")
    actions = scene["actions"]
    for entry in destinations:
        writes = actions[entry["action"]]["writes"]
        require(writes == [{
            "state": "material-navigation", "state_index": 0,
            "op": "set", "value": entry["target_value"]
        }], f"selection action {entry['action']} is not a literal state set")
        require(actions[entry["action"]]["gpu_updates"] == [] and actions[entry["action"]]["instance_updates"] == [],
                f"selection action {entry['action']} widened the generic GPU write path")
    print("NAVIGATION_SELECTION_SCENE_ORACLE: PASS destinations=3 static-color-patches=2 no-packets")


if __name__ == "__main__":
    main()
