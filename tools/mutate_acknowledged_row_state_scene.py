#!/usr/bin/env python3
"""Create noncanonical acknowledged-row-state Scene variants for Rust admission regression."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: mutate_acknowledged_row_state_scene.py INPUT mode OUTPUT")
    source = Path(sys.argv[1])
    mode = sys.argv[2]
    target = Path(sys.argv[3])
    document = json.loads(source.read_text(encoding="utf-8"))
    plan = document["acknowledged_row_state_plan"]
    if mode == "abi":
        document["abi_contracts"]["acknowledged_row_state_plan"]["revision"] = 99
    elif mode == "disable":
        document["acknowledged_row_state_plan"] = False
    elif mode == "words":
        plan["word_count"] += 1
    elif mode == "owner":
        plan["owner_view_id"] = document["material_observability_workbench_plan"]["views"][0]["view_root_id"]
    else:
        raise SystemExit("mode must be abi, disable, words, or owner")
    target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
