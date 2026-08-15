#!/usr/bin/env python3
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def load_stream(path):
    decoder = json.JSONDecoder()
    text = Path(path).read_text()
    offset = 0
    items = []
    while offset < len(text):
        while offset < len(text) and text[offset].isspace():
            offset += 1
        if offset >= len(text):
            break
        value, offset = decoder.raw_decode(text, offset)
        items.append(value)
    return items


def stats(values):
    values = sorted(values)
    p95 = values[max(0, math.ceil(len(values) * 0.95) - 1)]
    return {
        "count": len(values),
        "min": values[0],
        "median": statistics.median(values),
        "p95": p95,
        "max": values[-1],
        "mean": statistics.fmean(values),
    }


def group(items):
    result = defaultdict(lambda: {"cpu": [], "gpu": [], "correct": []})
    for item in items:
        bucket = result[item["id"]]
        bucket["cpu"].append(item["cpu_event_to_submit_ns"])
        bucket["gpu"].append(item["gpu_elapsed_ns"])
        bucket["correct"].append(item["expectations_match"])
    return result

baseline = group(load_stream(sys.argv[1]))
optimized = group(load_stream(sys.argv[2]))
rows = []
for case_id in sorted(baseline.keys() & optimized.keys()):
    row = {"id": case_id}
    row["correctness"] = all(baseline[case_id]["correct"]) and all(optimized[case_id]["correct"])
    for key in ("cpu", "gpu"):
        before, after = stats(baseline[case_id][key]), stats(optimized[case_id][key])
        row[key] = {
            "baseline": before,
            "optimized": after,
            "median_delta": after["median"] - before["median"],
            "median_delta_percent": ((after["median"] - before["median"]) / before["median"] * 100.0)
                if before["median"] else None,
        }
    rows.append(row)
report = {"schema": "noir-resident-worklist-sampling-v1", "rows": rows}
Path(sys.argv[3]).write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
