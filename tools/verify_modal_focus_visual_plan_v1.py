#!/usr/bin/env python3
"""Structural oracle for the modal_focus_visual_plan v1 showcase artifact."""
from __future__ import annotations

import json
import sys
from pathlib import Path


EXPECTED = [
    ("deployment-confirm$focus-ring", 3, 924, (757.0, 393.0, 110.0, 46.0)),
    ("deployment-dismiss$focus-ring", 2, 836, (641.0, 393.0, 110.0, 46.0)),
    ("menu-pin$target$focus-ring", 4, 1144, (933.0, 169.0, 214.0, 46.0)),
    ("menu-copy$target$focus-ring", 5, 1320, (933.0, 213.0, 214.0, 46.0)),
    ("menu-export$target$focus-ring", 6, 1496, (933.0, 257.0, 214.0, 46.0)),
]
COLOR = [0.36, 0.72, 1.0, 1.0]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_modal_focus_visual_plan_v1.py SCENE.json")
    scene_path = Path(sys.argv[1])
    scene = json.loads(scene_path.read_text(encoding="utf-8"))
    assert scene["abi_contracts"]["modal_focus_visual_plan"] == {
        "schema": "noir-modal-focus-visual-plan-v1", "revision": 1
    }
    assert scene["modal_focus_visual_required"] is True
    plan = scene["modal_focus_visual_plan"]
    assert plan["abi_schema"] == "noir-modal-focus-visual-plan-v1"
    assert plan["abi_revision"] == 1
    assert len(plan["entries"]) == len(EXPECTED) == 5
    for entry, (identifier, slot, source_offset, geometry) in zip(plan["entries"], EXPECTED, strict=True):
        assert entry["id"] == identifier
        assert entry["focus_event_slot"] == slot
        assert entry["source_instance_offset"] == source_offset
        assert entry["source_instance_offset"] % 44 == 0 and entry["source_instance_offset"] > 0
        observed_geometry = (entry["x"], entry["y"], entry["width"], entry["height"])
        assert observed_geometry == geometry
        assert entry["radius_px"] == 12.0
        assert entry["thickness_px"] == 2.0
        assert entry["color"] == COLOR
        assert entry["tile_ids"] == [0]
    print("modal_focus_visual_plan v1 structural oracle: PASS")


if __name__ == "__main__":
    main()
