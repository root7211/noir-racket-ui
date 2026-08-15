#!/usr/bin/env python3
"""Create deliberate, narrowly scoped realtime-monitor Scene corruption samples."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_realtime_monitor_scene.py lowercase <input.scene.json> <output.scene.json>")
    kind, source, destination = sys.argv[1:]
    if kind != "lowercase":
        raise SystemExit(f"unsupported mutation kind: {kind}")
    payload = json.loads(Path(source).read_text(encoding="utf-8"))
    plans = payload["virtual_list_plans"]
    monitor = next(plan for plan in plans if plan["id"] == "telemetry-grid")
    batches = monitor["data_update_batches"]
    bootstrap = next(batch for batch in batches if batch["id"] == "bootstrap-telemetry")
    bootstrap["updates"][0]["value"] = "Warn ALPHA 042 731 018 012 005"
    Path(destination).write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
