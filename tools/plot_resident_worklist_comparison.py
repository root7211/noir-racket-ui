#!/usr/bin/env python3
import json
import sys
from pathlib import Path
import matplotlib.pyplot as plt

report = json.loads(Path(sys.argv[1]).read_text())
rows = report["rows"]
labels = [row["id"].replace("coalesced-activate-", "").replace("-button", "") for row in rows]
base_cpu = [row["cpu"]["baseline"]["median"] / 1_000 for row in rows]
opt_cpu = [row["cpu"]["optimized"]["median"] / 1_000 for row in rows]
base_gpu = [row["gpu"]["baseline"]["median"] / 1_000 for row in rows]
opt_gpu = [row["gpu"]["optimized"]["median"] / 1_000 for row in rows]

fig, axes = plt.subplots(2, 1, figsize=(12, 8), constrained_layout=True)
for ax, base, opt, title, unit in [
    (axes[0], base_cpu, opt_cpu, "CPU event-to-submit median", "µs"),
    (axes[1], base_gpu, opt_gpu, "GPU timestamp median", "µs"),
]:
    x = list(range(len(labels)))
    width = 0.36
    ax.bar([v - width / 2 for v in x], base, width, label="baseline: per-request worklist upload", color="#a8b0bc")
    ax.bar([v + width / 2 for v in x], opt, width, label="resident compiler worklist", color="#4d7cfe")
    ax.set_title(title)
    ax.set_ylabel(unit)
    if title.startswith("CPU"):
        ax.set_yscale("log")
    ax.set_xticks(x, labels, rotation=16, ha="right")
    ax.grid(axis="y", alpha=0.25)
    ax.legend(loc="upper right")
fig.suptitle("Noir GPU-resident packet worklist experiment — 12 independent Vulkan/llvmpipe runs", fontsize=14, fontweight="bold")
fig.savefig(sys.argv[2], dpi=180)
