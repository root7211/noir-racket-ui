#!/usr/bin/env python3
"""Compare two Noir benchmark reports without averaging unrelated workloads."""
import json
import sys
from pathlib import Path

baseline_path = Path(sys.argv[1])
optimized_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

baseline = json.loads(baseline_path.read_text())
optimized = json.loads(optimized_path.read_text())
base_rows = {row["id"]: row for row in baseline["cases"]}
opt_rows = {row["id"]: row for row in optimized["cases"]}
rows = []
for case_id in sorted(base_rows.keys() & opt_rows.keys()):
    before, after = base_rows[case_id], opt_rows[case_id]
    def delta(metric):
        old, new = before[metric], after[metric]
        return {"baseline": old, "optimized": new, "delta": new - old,
                "delta_percent": ((new - old) / old * 100.0) if old else None}
    rows.append({
        "id": case_id,
        "correctness": before["expectations_match"] and after["expectations_match"],
        "cpu_event_to_submit_ns": delta("cpu_event_to_submit_ns"),
        "gpu_elapsed_ns": delta("gpu_elapsed_ns"),
    })
summary = {
    "schema": "noir-resident-worklist-comparison-v1",
    "baseline": str(baseline_path),
    "optimized": str(optimized_path),
    "adapter_name": optimized["adapter_name"],
    "backend": optimized["backend"],
    "rows": rows,
}
output_path.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
