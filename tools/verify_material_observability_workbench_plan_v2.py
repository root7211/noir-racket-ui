#!/usr/bin/env python3
"""Structural oracle for material_observability_workbench_plan v2."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def assert_disjoint(entries: list[dict], key: str, label: str, *, nonempty: bool = True) -> None:
    values = [value for entry in entries for value in entry[key]]
    if nonempty:
        assert values, f"{label}.{key} must not be empty"
    assert len(values) == len(set(values)), f"{label}.{key} aliases across fixed compiler addresses"


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_material_observability_workbench_plan_v2.py SCENE.json")
    scene = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    expected_contract = {"schema": "noir-material-observability-workbench-plan-v2", "revision": 2}
    assert scene["abi_contracts"]["material_observability_workbench_plan"] == expected_contract
    assert scene["material_observability_workbench_required"] is True
    plan = scene["material_observability_workbench_plan"]
    assert {"schema": plan["abi_schema"], "revision": plan["abi_revision"]} == expected_contract
    assert (plan["id"], plan["rail_id"], plan["state"], plan["initial_view"], plan["initial_value"]) == (
        "observability-workbench", "observability-rail", "workbench-view", "observability-overview", 0
    )
    state_slots = {slot["id"]: slot for slot in scene["state_slots"]}
    assert state_slots["workbench-view"] == {"index": plan["state_index"], "id": "workbench-view", "initial": 0}

    views = plan["views"]
    assert [view["destination_id"] for view in views] == ["observability-overview", "observability-systems", "observability-alerts"]
    assert [view["target_value"] for view in views] == [0, 1, 2]
    assert [view["view_root_id"] for view in views] == ["overview-view", "systems-view", "alerts-view"]
    for view in views:
        assert view["node_ids"][0] == view["view_root_id"]
        assert len(view["instance_offsets"]) == len(view["instance_alphas"])
        assert view["instance_offsets"] == sorted(view["instance_offsets"])
        assert view["glyph_slots"] == sorted(view["glyph_slots"])
        assert view["event_slots"] == sorted(view["event_slots"])
        assert view["tile_ids"] == sorted(view["tile_ids"])
        assert all(offset > 0 and offset % 44 == 0 for offset in view["instance_offsets"])
        assert all(0.0 <= alpha <= 1.0 for alpha in view["instance_alphas"])
        assert view["glyph_slots"] and view["tile_ids"]
    for key in ("instance_offsets", "glyph_slots", "event_slots"):
        assert_disjoint(views, key, "views")

    data_views = plan["data_views"]
    assert [(entry["id"], entry["list_id"], entry["view_id"], entry["list_index"]) for entry in data_views] == [
        ("systems-data-view", "observability-log", "systems-view", 0),
        ("alerts-data-view", "observability-alert-stream", "alerts-view", 1),
    ]
    assert [(entry["logical_capacity"], entry["physical_slots"], entry["visible_rows"]) for entry in data_views] == [
        (10000, 4, 4), (2048, 3, 3)
    ]
    assert [(entry["scrollbar_id"], entry["navigation_id"], entry["log_browser_id"], entry["row_activation_action"]) for entry in data_views] == [
        ("observability-scrollbar", "observability-list-navigation", "observability-log-browser", "workbench-open-detail"),
        ("observability-alert-scrollbar", "observability-alert-list-navigation", "observability-alert-log-browser", "workbench-open-alert-detail"),
    ]
    owner_nodes = {view["view_root_id"]: set(view["node_ids"]) for view in views}
    for entry in data_views:
        assert entry["node_ids"][0] == entry["list_id"]
        assert set(entry["node_ids"]).issubset(owner_nodes[entry["view_id"]])
        assert entry["instance_offsets"] == sorted(entry["instance_offsets"])
        assert entry["glyph_slots"] == sorted(entry["glyph_slots"])
        assert entry["event_slots"] == sorted(entry["event_slots"])
        assert entry["tile_ids"] == sorted(entry["tile_ids"])
        assert entry["instance_offsets"] and entry["glyph_slots"] and entry["tile_ids"]
    for key in ("instance_offsets", "glyph_slots"):
        assert_disjoint(data_views, key, "data_views")
    assert_disjoint(data_views, "event_slots", "data_views", nonempty=False)

    virtual = scene["virtual_list_plans"]
    assert [(entry["id"], entry["logical_capacity"], entry["physical_slots"], entry["visible_rows"]) for entry in virtual] == [
        ("observability-log", 10000, 4, 4), ("observability-alert-stream", 2048, 3, 3)
    ]
    assert {entry["list_id"] for entry in scene["scrollbar_plans"]} == {entry["list_id"] for entry in data_views}
    assert {entry["list_id"] for entry in scene["list_navigation_plans"]} == {entry["list_id"] for entry in data_views}
    assert {entry["list_id"] for entry in scene["log_browser_plans"]} == {entry["list_id"] for entry in data_views}
    assert {entry["list_id"] for entry in scene["row_activation_plans"]} == {entry["list_id"] for entry in data_views}
    assert scene["navigation_selection_plan"]["state"] == plan["state"]
    assert scene["navigation_selection_plan"]["initial_value"] == plan["initial_value"]
    assert scene["overlay_state_required"] is True
    assert scene["modal_focus_visual_required"] is True
    assert len(scene["modal_focus_visual_plan"]["entries"]) == 5
    print("material_observability_workbench_plan v2 structural oracle: PASS")


if __name__ == "__main__":
    main()
