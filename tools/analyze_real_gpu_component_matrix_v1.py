#!/usr/bin/env python3
"""Analyze real-GPU Noir Material component replay matrices.

This tool intentionally refuses CPU adapters, mixed adapters/backends, absent timestamp
queries, and compiler-selected proof failures. It is not a cross-framework comparison;
it measures the fixed Noir component workloads emitted by the current compiler commit.
"""
from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt


def median(values: list[float]) -> float:
    return float(statistics.median(values))


def percentile(values: list[float], p: float) -> float:
    if not values:
        raise ValueError("empty samples")
    ordered = sorted(values)
    index = (len(ordered) - 1) * p
    lo, hi = int(index), min(int(index) + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (index - lo)


def reject(condition: bool, message: str) -> None:
    if condition:
        raise SystemExit(f"REAL_GPU_COMPONENT_ANALYSIS_REJECTED: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: analyze_real_gpu_component_matrix_v1.py <result-directory>")
    root = Path(sys.argv[1])
    manifest = json.loads((root / "run-manifest.json").read_text(encoding="utf-8"))
    reject(manifest.get("schema") != "noir-real-gpu-component-matrix-v1", "manifest schema")
    reports = sorted(root.glob("session-*-*-replay-matrix.json"))
    reject(not reports, "no replay matrix reports")

    adapter_pairs: set[tuple[str, str]] = set()
    grouped: dict[tuple[str, str], dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    report_count = 0
    for path in reports:
        payload = json.loads(path.read_text(encoding="utf-8"))
        reject(payload.get("schema") != "noir-wgpu-replay-matrix-v2", f"{path.name}: schema")
        reject(payload.get("timestamp_query_supported") is not True, f"{path.name}: timestamp query unavailable")
        adapter = str(payload.get("adapter_name", ""))
        backend = str(payload.get("backend", ""))
        reject(any(token in adapter.lower() for token in ("llvmpipe", "lavapipe", "cpu")), f"{path.name}: CPU adapter {adapter}")
        adapter_pairs.add((adapter, backend))
        fixture = "dashboard" if "-dashboard-" in path.name else "overlay" if "-overlay-" in path.name else "unknown"
        reject(fixture == "unknown", f"{path.name}: fixture cannot be inferred")
        for row in payload.get("rows", []):
            if row.get("mode") != "compiler-selected":
                continue
            proof = row.get("compiler_selected", {})
            reject(proof.get("self_consistent") is not True, f"{path.name}: compiler-selected proof failed for {row.get('workload_id')}")
            gpu = row.get("gpu_elapsed_ns")
            cpu = row.get("cpu_event_to_submit_ns")
            reject(not isinstance(gpu, dict) or not isinstance(cpu, dict), f"{path.name}: missing timestamp distributions")
            key = (fixture, str(row["workload_id"]))
            grouped[key]["gpu_median_ns"].append(float(gpu["median_ns"]))
            grouped[key]["gpu_p95_ns"].append(float(gpu["p95_ns"]))
            grouped[key]["cpu_median_ns"].append(float(cpu["median_ns"]))
            grouped[key]["tile_count"].append(float(row["submitted_tile_count"]))
            grouped[key]["glyph_draw_count"].append(float(row["submitted_glyph_draw_count"]))
            grouped[key]["winner_write_bytes"].append(float(row["expected_write_bytes"]))
        report_count += 1

    reject(len(adapter_pairs) != 1, f"mixed adapters/backends: {sorted(adapter_pairs)}")
    adapter, backend = next(iter(adapter_pairs))
    rows = []
    for (fixture, workload), metrics in sorted(grouped.items()):
        rows.append({
            "fixture": fixture,
            "workload_id": workload,
            "sessions": len(metrics["gpu_median_ns"]),
            "gpu_median_of_session_medians_ns": median(metrics["gpu_median_ns"]),
            "gpu_p95_of_session_p95_ns": percentile(metrics["gpu_p95_ns"], 0.95),
            "cpu_submit_median_of_session_medians_ns": median(metrics["cpu_median_ns"]),
            "submitted_tile_count": median(metrics["tile_count"]),
            "submitted_glyph_draw_count": median(metrics["glyph_draw_count"]),
            "winner_write_bytes": median(metrics["winner_write_bytes"]),
        })
    reject(not rows, "no compiler-selected rows")
    result = {
        "schema": "noir-real-gpu-component-matrix-summary-v1",
        "git_commit": manifest["git_commit"],
        "adapter_name": adapter,
        "backend": backend,
        "reports": report_count,
        "sessions_configured": manifest["sessions"],
        "warmup": manifest["warmup"],
        "samples": manifest["samples"],
        "rows": rows,
    }
    (root / "component-gpu-summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    markdown = [
        "# Noir Real-GPU Component Matrix v1", "",
        f"**Commit:** `{manifest['git_commit']}`  ",
        f"**Adapter:** `{adapter}` via `{backend}`  ",
        f"**Protocol:** {manifest['sessions']} sessions; {manifest['warmup']} warm-up iterations; {manifest['samples']} samples per replay row.", "",
        "| Fixture | Compiler-selected workload | Sessions | GPU median of session medians (µs) | GPU P95 of session P95s (µs) | CPU submit median (µs) | Tiles | Glyph draws | Winner writes (bytes) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        markdown.append("| {fixture} | `{workload_id}` | {sessions} | {gpu:.2f} | {p95:.2f} | {cpu:.2f} | {tiles:.0f} | {glyphs:.0f} | {writes:.0f} |".format(
            fixture=row["fixture"], workload_id=row["workload_id"], sessions=row["sessions"],
            gpu=row["gpu_median_of_session_medians_ns"] / 1e3,
            p95=row["gpu_p95_of_session_p95_ns"] / 1e3,
            cpu=row["cpu_submit_median_of_session_medians_ns"] / 1e3,
            tiles=row["submitted_tile_count"], glyphs=row["submitted_glyph_draw_count"], writes=row["winner_write_bytes"],
        ))
    markdown.extend(["", "> This report is valid only for the single non-CPU adapter admitted by the runner. It is a Noir component-path measurement, not a cross-framework claim.", ""])
    (root / "component-gpu-summary.md").write_text("\n".join(markdown), encoding="utf-8")

    labels = [f"{row['fixture']}\n{row['workload_id'].replace('coalesced-activate-', '')}" for row in rows]
    values = [row["gpu_median_of_session_medians_ns"] / 1e3 for row in rows]
    fig, ax = plt.subplots(figsize=(max(10, len(rows) * 1.2), 5.5), constrained_layout=True)
    bars = ax.bar(range(len(rows)), values, color="#74d3ae")
    ax.set_ylabel("GPU median of session medians (µs)")
    ax.set_title("Noir compiler-selected Material component workloads")
    ax.set_xticks(range(len(rows)), labels, rotation=35, ha="right")
    for bar, value in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{value:.1f}", ha="center", va="bottom", fontsize=8)
    ax.grid(axis="y", alpha=0.25)
    fig.savefig(root / "component-gpu-median.png", dpi=180)
    print(f"REAL_GPU_COMPONENT_ANALYSIS: PASS reports={report_count} rows={len(rows)} adapter={adapter} backend={backend}")


if __name__ == "__main__":
    main()
