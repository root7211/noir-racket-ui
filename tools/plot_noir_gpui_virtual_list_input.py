#!/usr/bin/env python3
import json
import sys
from pathlib import Path
import matplotlib.pyplot as plt

src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("wgpu-verify/out/noir-gpui-virtual-list-input-summary.json")
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("wgpu-verify/out/noir-gpui-virtual-list-input-comparison.png")
data = json.loads(src.read_text())
labels = ["Noir", "GPUI"]
keys = ["noir", "gpui"]
median = [data["frameworks"][key]["median_ns_per_handler"] / 1e6 for key in keys]
p95 = [data["frameworks"][key]["p95_ns_per_handler"] / 1e6 for key in keys]

fig, ax = plt.subplots(figsize=(8, 4.8), constrained_layout=True)
x = [0, 1]
width = 0.34
ax.bar([v - width / 2 for v in x], median, width, label="Median", color="#3a78c2")
ax.bar([v + width / 2 for v in x], p95, width, label="P95", color="#e08a33")
ax.set_xticks(x, labels)
ax.set_ylabel("ms per REFRESH handler")
ax.set_title("Virtual-list X11 input burst: handler completion only")
ax.set_ylim(0, max(p95) * 1.24)
for pos, value in zip([v - width / 2 for v in x], median):
    ax.text(pos, value + 0.025, f"{value:.3f}", ha="center", va="bottom", fontsize=9)
for pos, value in zip([v + width / 2 for v in x], p95):
    ax.text(pos, value + 0.025, f"{value:.3f}", ha="center", va="bottom", fontsize=9)
ax.legend()
ax.text(0.5, -0.22, "15 samples; 25 zero-delay X11 clicks/sample; excludes GPU present and frame timestamps", transform=ax.transAxes, ha="center", fontsize=8)
fig.savefig(out, dpi=180)
print(out)
