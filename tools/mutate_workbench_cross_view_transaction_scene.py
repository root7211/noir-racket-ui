#!/usr/bin/env python3
"""Create noncanonical cross-view transaction Scene variants for Rust ABI-gate regression."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_workbench_cross_view_transaction_scene.py INPUT mode OUTPUT")
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    target = Path(sys.argv[3])
    document = json.loads(source.read_text(encoding="utf-8"))
    plan = document["workbench_cross_view_transaction_plan"]
    if mode == "abi":
        document["abi_contracts"]["workbench_cross_view_transaction_plan"]["revision"] = 99
    elif mode == "disable":
        document["workbench_cross_view_transaction_plan"] = False
    elif mode == "action":
        plan["action_slot_index"] += 1
    elif mode == "target":
        plan["target_count_glyph_offsets"][0] += 32
    else:
        raise SystemExit("mode must be abi, disable, action, or target")
    target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
