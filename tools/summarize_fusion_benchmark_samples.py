#!/usr/bin/env python3
"""Summarize independent fusion benchmark JSONL samples."""
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: summarize_fusion_benchmark_samples.py <samples.jsonl> <summary.json>")

samples_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
groups = defaultdict(lambda: {"baseline": defaultdict(list), "fused": defaultdict(list), "matches": []})
with samples_path.open() as handle:
    for line in handle:
        if not line.strip():
            continue
        row = json.loads(line)
        group = groups[row["id"]]
        group["matches"].append(row["expectations_match"])
        for executor in ("baseline", "fused"):
            measurement = row[executor]
            for key in ("request_count", "packet_activity_dispatch_count", "queue_submit_count", "cpu_event_to_submit_ns", "gpu_elapsed_ns"):
                value = measurement[key]
                if value is not None:
                    group[executor][key].append(float(value))

def percentile(values, p):
    ordered = sorted(values)
    if not ordered:
        return None
    index = (len(ordered) - 1) * p
    lo, hi = math.floor(index), math.ceil(index)
    return ordered[lo] if lo == hi else ordered[lo] + (ordered[hi] - ordered[lo]) * (index - lo)

def stats(values):
    return {"n": len(values), "median": statistics.median(values), "p95": percentile(values, 0.95), "mean": statistics.fmean(values)}

cases = []
for case_id in sorted(groups):
    group = groups[case_id]
    baseline = {key: stats(values) for key, values in group["baseline"].items()}
    fused = {key: stats(values) for key, values in group["fused"].items()}
    reductions = {}
    for metric in ("request_count", "packet_activity_dispatch_count", "queue_submit_count", "cpu_event_to_submit_ns", "gpu_elapsed_ns"):
        before = baseline.get(metric, {}).get("median")
        after = fused.get(metric, {}).get("median")
        reductions[metric] = None if before in (None, 0) or after is None else (after - before) / before
    cases.append({
        "id": case_id,
        "all_expectations_match": all(group["matches"]),
        "baseline": baseline,
        "fused": fused,
        "relative_change_fused_vs_baseline": reductions,
    })

summary = {"schema": "noir-fusion-benchmark-samples-v1", "cases": cases}
summary_path.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
