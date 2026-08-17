#!/usr/bin/env python3
"""Structural oracle for material_observability_workbench_plan v1."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def assert_disjoint(views: list[dict], key: str) -> None:
    values = [value for view in views for value in view[key]]
    assert values, f"{key} must not be empty"
    assert len(values) == len(set(values)), f"{key} aliases across fixed workbench views"


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_material_observability_workbench_plan_v1.py SCENE.json")
    scene = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    assert scene["abi_contracts"]["material_observability_workbench_plan"] == {
        "schema": "noir-material-observability-workbench-plan-v1", "revision": 1
    }
    assert scene["material_observability_workbench_required"] is True
    plan = scene["material_observability_workbench_plan"]
    assert plan["abi_schema"] == "noir-material-observability-workbench-plan-v1"
    assert plan["abi_revision"] == 1
    assert plan["id"] == "observability-workbench"
    assert plan["rail_id"] == "observability-rail"
    assert plan["state"] == "workbench-view"
    state_slots = {slot["id"]: slot for slot in scene["state_slots"]}
    assert state_slots["workbench-view"]["index"] == plan["state_index"]
    assert state_slots["workbench-view"]["initial"] == 0
    assert plan["systems_list_id"] == "observability-log"
    assert plan["initial_view"] == "observability-overview"
    assert plan["initial_value"] == 0
    views = plan["views"]
    assert [view["destination_id"] for view in views] == [
        "observability-overview", "observability-systems", "observability-alerts"
    ]
    assert [view["target_value"] for view in views] == [0, 1, 2]
    assert [view["view_root_id"] for view in views] == [
        "overview-view", "systems-view", "alerts-view"
    ]
    for view in views:
        assert len(view["instance_offsets"]) == len(view["instance_alphas"])
        assert view["instance_offsets"] == sorted(view["instance_offsets"])
        assert view["glyph_slots"] == sorted(view["glyph_slots"])
        assert view["event_slots"] == sorted(view["event_slots"])
        assert view["tile_ids"] == sorted(view["tile_ids"])
        assert all(offset > 0 and offset % 44 == 0 for offset in view["instance_offsets"])
        assert all(0.0 <= alpha <= 1.0 for alpha in view["instance_alphas"])
        assert view["glyph_slots"] and view["tile_ids"]
    assert_disjoint(views, "instance_offsets")
    assert_disjoint(views, "glyph_slots")
    assert_disjoint(views, "event_slots")
    systems = views[1]
    assert any(slot >= 0 for slot in systems["event_slots"])
    virtual = scene["virtual_list_plans"]
    assert len(virtual) == 1
    assert virtual[0]["id"] == "observability-log"
    assert virtual[0]["logical_capacity"] == 10000
    assert virtual[0]["physical_slots"] == 4
    assert virtual[0]["visible_rows"] == 4
    assert len(scene["log_browser_plans"]) == 1
    assert scene["log_browser_plans"][0]["list_id"] == "observability-log"
    assert scene["navigation_selection_plan"]["state"] == plan["state"]
    assert scene["navigation_selection_plan"]["initial_value"] == plan["initial_value"]
    assert scene["overlay_state_required"] is True
    assert scene["modal_focus_visual_required"] is True
    assert len(scene["modal_focus_visual_plan"]["entries"]) == 5
    print("material_observability_workbench_plan v1 structural oracle: PASS")


if __name__ == "__main__":
    main()
