#!/usr/bin/env python3
"""Structural oracle for noir-workbench/app v1 Scene output."""
import json
import sys
from pathlib import Path


def check(path: Path, app: str, capacities: tuple[int, int], slots: tuple[int, int]) -> None:
    scene = json.loads(path.read_text(encoding="utf-8"))
    assert scene["material_observability_workbench_required"] is True
    plan = scene["material_observability_workbench_plan"]
    assert plan["abi_schema"] == "noir-material-observability-workbench-plan-v2"
    assert plan["id"] == f"{app}-workbench"
    assert plan["rail_id"] == f"{app}-rail"
    assert plan["initial_value"] == 0
    data_views = plan["data_views"]
    assert [entry["id"] for entry in data_views] == [f"{app}-systems-data-view", f"{app}-alerts-data-view"]
    assert [entry["list_id"] for entry in data_views] == [f"{app}-systems-stream", f"{app}-alerts-stream"]
    assert [entry["view_id"] for entry in data_views] == [f"{app}-systems-view", f"{app}-alerts-view"]
    assert [entry["logical_capacity"] for entry in data_views] == list(capacities)
    assert [entry["physical_slots"] for entry in data_views] == list(slots)
    assert [entry["visible_rows"] for entry in data_views] == list(slots)
    transaction = scene["workbench_cross_view_transaction_plan"]
    assert scene["workbench_cross_view_transaction_required"] is True
    assert transaction["id"] == f"{app}-acknowledge-alert-transaction"
    assert transaction["action_id"] == f"{app}-acknowledge-alert"
    assert transaction["state"] == f"{app}-alert-ack-count"
    assert transaction["source_data_view_id"] == f"{app}-alerts-data-view"
    assert transaction["source_view_id"] == f"{app}-alerts-view"
    assert transaction["target_view_id"] == f"{app}-overview-view"
    assert len(transaction["source_row_color_offsets"]) == slots[1]
    assert len(transaction["source_detail_glyph_offsets"]) == 29
    assert len(transaction["target_count_glyph_offsets"]) == 8
    print(f"APPLICATION_DSL_ORACLE: {path.name}: PASS")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: verify_application_layer_dsl_v1.py STANDARD APP COMPACT APP")
    check(Path(sys.argv[1]), sys.argv[2], (10000, 2048), (4, 3))
    check(Path(sys.argv[3]), sys.argv[4], (2048, 512), (3, 3))
