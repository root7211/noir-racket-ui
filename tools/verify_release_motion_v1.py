#!/usr/bin/env python3
"""Structural oracle for Noir's finite compiler-owned release_motion v1."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path


def close(a: float, b: float) -> bool:
    return math.isclose(float(a), float(b), rel_tol=0.0, abs_tol=1e-7)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_release_motion_v1.py <scene.json>")
    path = Path(sys.argv[1])
    scene = json.loads(path.read_text(encoding="utf-8"))
    events = scene["event_map"]
    tracks = scene["animation_tracks"]
    tasks = {task["id"]: task for task in scene["frame_schedule"]}
    if len(tracks) != len(events):
        raise AssertionError(f"expected one release track per event: tracks={len(tracks)} events={len(events)}")
    by_node = {track["node"]: track for track in tracks}
    if len(by_node) != len(tracks):
        raise AssertionError("duplicate release track node")
    for event in events:
        node = event["node"]
        track = by_node.get(node)
        if track is None:
            raise AssertionError(f"missing release track for {node}")
        if track["id"] != f"release-{node}" or track["duration_ms"] != 80 or track["easing"] != "ease-out":
            raise AssertionError(f"noncanonical recipe for {node}")
        offset = event["instance_offset"]
        if (track["instance_offset"], track["pos_offset"], track["color_offset"]) != (offset, offset, offset + 16):
            raise AssertionError(f"fixed instance field witness failed for {node}")
        for left, right in ((track["pos_from"], event["pressed_pos"]), (track["pos_to"], event["base_pos"]),
                            (track["color_from"], event["pressed_color"]), (track["color_to"], event["base_color"])):
            if len(left) != len(right) or not all(close(a, b) for a, b in zip(left, right)):
                raise AssertionError(f"track endpoints disagree with event map for {node}")
        damage = track["damage"]
        if damage["kind"] != "rect" or damage["node"] != node or damage["instance_offset"] != offset:
            raise AssertionError(f"damage identity witness failed for {node}")
        for field in ("x", "y", "width", "height"):
            if not close(damage[field], event[field]):
                raise AssertionError(f"damage {field} disagrees with event {node}")
        task = tasks.get(track["id"])
        writes = {(write["offset"], write["byte_length"]) for write in task.get("writes", [])} if task else set()
        if not task or task["kind"] != "release" or writes != {(offset, 8), (offset + 16, 16)}:
            raise AssertionError(f"release frame task does not own exactly pos/color for {node}")
    print(json.dumps({"scene": str(path), "tracks": len(tracks), "duration_ms": 80,
                      "easing": "ease-out", "status": "PASS"}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
