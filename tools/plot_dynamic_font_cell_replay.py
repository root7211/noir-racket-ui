#!/usr/bin/env python3
"""Render a compact audit chart from a Noir replay matrix report."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt


def main() -> None:
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    report = json.loads(source.read_text(encoding="utf-8"))
    rows = report["rows"]
    modes = [row["mode"] for row in rows]
    medians = [row["gpu_elapsed_ns"]["median_ns"] / 1_000_000 for row in rows]
    instances = [row["submitted_glyph_instance_count"] for row in rows]

    fig, (time_ax, instance_ax) = plt.subplots(1, 2, figsize=(11.8, 4.6), gridspec_kw={"width_ratios": [1.55, 1]})
    colors = ["#64748b", "#38bdf8", "#a78bfa", "#34d399", "#fbbf24"]
    bars = time_ax.bar(modes, medians, color=colors, width=0.66)
    time_ax.set_ylabel("GPU median (ms)")
    time_ax.set_title("Page-3 tabular body replay")
    time_ax.grid(axis="y", alpha=0.25)
    time_ax.set_axisbelow(True)
    time_ax.tick_params(axis="x", rotation=20)
    for bar, value in zip(bars, medians):
        time_ax.text(bar.get_x() + bar.get_width() / 2, value + max(medians) * 0.025, f"{value:.3f}", ha="center", va="bottom", fontsize=9)

    instance_ax.bar(modes, instances, color=colors, width=0.66)
    instance_ax.set_ylabel("Submitted glyph instances")
    instance_ax.set_title("Compiler-fixed submission")
    instance_ax.grid(axis="y", alpha=0.25)
    instance_ax.set_axisbelow(True)
    instance_ax.tick_params(axis="x", rotation=20)
    for index, value in enumerate(instances):
        instance_ax.text(index, value + max(instances) * 0.025, str(value), ha="center", va="bottom", fontsize=9)

    fig.suptitle("Noir dynamic_font_cell_plan v1 — llvmpipe Vulkan, 5 warmup + 25 samples", fontsize=12, fontweight="bold")
    fig.text(0.5, 0.01, "Comparative replay evidence only; not a real-GPU or input-to-photon claim.", ha="center", color="#475569", fontsize=9)
    fig.tight_layout(rect=(0, 0.06, 1, 0.92))
    destination.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(destination, dpi=180, facecolor="white")


if __name__ == "__main__":
    main()
