#!/usr/bin/env python3
"""Structural oracle for Noir modal_focus_subgraph v1 Scene artifacts."""
from __future__ import annotations

import json
import sys
from pathlib import Path


SCHEMA = "noir-modal-focus-subgraph-v1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def verify(path: Path) -> None:
    scene = json.loads(path.read_text(encoding="utf-8"))
    require(scene["modal_focus_subgraph_required"] is True,
            "modal overlay Scene must require modal_focus_subgraph_plan")
    contract = scene["abi_contracts"]["modal_focus_subgraph"]
    require(contract == {"schema": SCHEMA, "revision": 1},
            f"unexpected modal focus ABI contract: {contract!r}")
    plan = scene["modal_focus_subgraph_plan"]
    require(plan["abi_schema"] == SCHEMA and plan["abi_revision"] == 1,
            "modal focus plan ABI mismatch")
    entries = plan["entries"]
    require(len(entries) == 1, "fixture must have exactly one modal focus subgraph")
    entry = entries[0]
    require(entry["id"] == "deployment-overlay", "unexpected modal id")
    require(entry["state"] == "overlay-visible" and entry["state_index"] == 0,
            "modal focus must bind fixed overlay-visible state slot 0")
    require(entry["restore_event_slot"] == 0,
            "open event slot 0 must be the fixed focus restoration target")
    focus = entry["focus_event_slots"]
    require(focus == [3, 2, 4, 5, 6], f"unexpected declared Tab order: {focus!r}")
    require(entry["next_slots"] == [2, 4, 5, 6, 3], "forward Tab ring is not canonical")
    require(entry["previous_slots"] == [6, 3, 2, 4, 5], "reverse Tab ring is not canonical")
    require(entry["allowed_event_slots"] == [1, 2, 3, 4, 5, 6],
            "allowed modal events must include only scrim plus close targets, never background open")
    require(entry["tile_ids"] == [0], "modal focus must preserve the fixed local overlay tile")

    event_map = scene["event_map"]
    require(event_map[0]["action"] == "overlay-open", "restore event must be the unique open action")
    actions = [event_map[index]["action"] for index in focus]
    require(actions == ["overlay-confirm", "overlay-dismiss", "overlay-pin", "overlay-copy", "overlay-export"],
            f"Tab ring targets are not fixed overlay close actions: {actions!r}")
    require(event_map[1]["action"] == "overlay-dismiss", "scrim must retain fixed dismiss action")
    require(all(event_map[index]["action"] != "overlay-open" for index in entry["allowed_event_slots"]),
            "background open event escaped modal isolation")

    overlay = scene["overlay_state_plan"]
    require(overlay and overlay["entries"][0]["event_slots"] == list(range(7)),
            "modal plan must be paired with the admitted overlay-state event domain")
    require(overlay["entries"][0]["tile_ids"] == entry["tile_ids"],
            "modal focus widened overlay render scope")
    print("MODAL_FOCUS_SUBGRAPH_V1_ORACLE: PASS")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_modal_focus_subgraph_v1.py <scene.json>")
    verify(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
