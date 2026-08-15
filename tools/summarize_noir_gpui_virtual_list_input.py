#!/usr/bin/env python3
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("wgpu-verify/out/noir-gpui-virtual-list-input-samples.jsonl")
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("wgpu-verify/out/noir-gpui-virtual-list-input-summary.json")
rows = [json.loads(line) for line in src.read_text().splitlines() if line.strip()]
groups = defaultdict(list)
for row in rows:
    groups[row["framework"]].append(row)

def percentile(values, p):
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    k = (len(values) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)

def stats(rows):
    values = [r["ns_per_handler"] for r in rows]
    return {
        "sample_count": len(values),
        "clicks_per_sample": rows[0]["clicks"],
        "completed_events_per_sample": rows[0]["completed_events"],
        "median_ns_per_handler": statistics.median(values),
        "p95_ns_per_handler": percentile(values, 0.95),
        "min_ns_per_handler": min(values),
        "max_ns_per_handler": max(values),
        "mean_ns_per_handler": statistics.mean(values),
        "stdev_ns_per_handler": statistics.stdev(values) if len(values) > 1 else 0.0,
    }

summary = {"metric": "x11_input_to_handler_excluding_gpu_present", "method": "25 zero-delay X11 mouse clicks per sample; timing ends only after all handler logs are observed", "frameworks": {name: stats(items) for name, items in groups.items()}, "limitations": ["This is not GPU frame time, presentation latency, or an apples-to-apples rendering benchmark.", "Noir reports separate wgpu GPU timestamps; the minimal GPUI comparator does not expose an equivalent portable timestamp path.", "X11 injection, process scheduling and log polling remain in the end-to-end metric."]}
if "noir" in summary["frameworks"] and "gpui" in summary["frameworks"]:
    noir = summary["frameworks"]["noir"]["median_ns_per_handler"]
    gpui = summary["frameworks"]["gpui"]["median_ns_per_handler"]
    summary["median_relative_change_noir_vs_gpui_pct"] = (noir / gpui - 1.0) * 100.0
out.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
