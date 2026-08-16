#!/usr/bin/env python3
"""Derive review metrics from real-GPU component matrix v1 replay summaries."""
from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def percent(numerator: float, denominator: float) -> float:
    return (numerator / denominator - 1.0) * 100.0


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: inspect_component_matrix_v1.py <matrix-directory>")
    root = Path(sys.argv[1])
    reports = sorted(root.glob("session-*-replay-matrix.json"))
    by_workload: dict[str, list[dict]] = defaultdict(list)
    for path in reports:
        document = json.loads(path.read_text(encoding="utf-8"))
        for row in document["rows"]:
            if row["mode"] == "compiler-selected":
                by_workload[row["workload_id"]].append(row)

    workloads = []
    for workload_id, rows in sorted(by_workload.items()):
        gpu_medians = [r["gpu_elapsed_ns"]["median_ns"] for r in rows]
        gpu_p95s = [r["gpu_elapsed_ns"]["p95_ns"] for r in rows]
        cpu_medians = [r["cpu_event_to_submit_ns"]["median_ns"] for r in rows]
        gpu = statistics.median(gpu_medians)
        workloads.append({
            "workload_id": workload_id,
            "sessions": len(rows),
            "gpu_median_ns": gpu,
            "gpu_p95_ns": max(gpu_p95s),
            "cpu_submit_median_ns": statistics.median(cpu_medians),
            "cpu_to_gpu_ratio": statistics.median(cpu_medians) / gpu,
            "session_median_spread_pct": percent(max(gpu_medians), min(gpu_medians)) if len(gpu_medians) > 1 else 0.0,
            "p95_over_median_pct": percent(max(gpu_p95s), gpu),
            "tiles": rows[0]["submitted_tile_count"],
            "glyph_draws": rows[0]["submitted_glyph_draw_count"],
            "glyph_instances": rows[0]["submitted_glyph_instance_count"],
            "winner_write_bytes": rows[0]["expected_write_bytes"],
        })

    nav = [r["gpu_median_ns"] for r in workloads if "material-" in r["workload_id"] and "$target" in r["workload_id"]]
    refresh = next(r["gpu_median_ns"] for r in workloads if r["workload_id"].endswith("material-refresh-button"))
    deploy = [r["gpu_median_ns"] for r in workloads if "deployment-" in r["workload_id"]]
    menu = [r["gpu_median_ns"] for r in workloads if "menu-" in r["workload_id"]]
    result = {
        "schema": "noir-component-matrix-inspection-v1",
        "workloads": workloads,
        "comparisons": {
            "dashboard_refresh_vs_navigation_avg_pct": percent(refresh, statistics.mean(nav)),
            "menu_vs_deployment_avg_pct": percent(statistics.mean(menu), statistics.mean(deploy)),
            "menu_gpu_avg_ns": statistics.mean(menu),
            "deployment_gpu_avg_ns": statistics.mean(deploy),
            "overall_cpu_to_gpu_ratio_min": min(r["cpu_to_gpu_ratio"] for r in workloads),
            "overall_cpu_to_gpu_ratio_max": max(r["cpu_to_gpu_ratio"] for r in workloads),
            "max_session_median_spread_pct": max(r["session_median_spread_pct"] for r in workloads),
            "max_p95_over_median_pct": max(r["p95_over_median_pct"] for r in workloads),
        },
    }
    output = root / "component-gpu-inspection.json"
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
