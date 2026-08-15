#!/usr/bin/env python3
import json
import sys
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

if len(sys.argv) != 3:
    raise SystemExit('usage: plot_fusion_benchmark.py <summary.json> <output.png>')
summary = json.loads(Path(sys.argv[1]).read_text())
labels = [case['id'].replace('coalesced-activate-', '') for case in summary['cases']]
metrics = [
    ('CPU event-to-submit median (ms)', 'cpu_event_to_submit_ns', 1e6),
    ('GPU timestamp median (ms)', 'gpu_elapsed_ns', 1e6),
]
fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
colors = ('#bf5af2', '#30d158')
for ax, (title, metric, divisor) in zip(axes, metrics):
    baseline = [case['baseline'][metric]['median'] / divisor for case in summary['cases']]
    fused = [case['fused'][metric]['median'] / divisor for case in summary['cases']]
    x = np.arange(len(labels))
    width = 0.35
    bars_a = ax.bar(x - width/2, baseline, width, label='3-request baseline', color=colors[0])
    bars_b = ax.bar(x + width/2, fused, width, label='1-request fusion', color=colors[1])
    for b, f, case in zip(bars_a, fused, summary['cases']):
        reduction = -100 * case['relative_change_fused_vs_baseline'][metric]
        ax.text(b.get_x() + b.get_width()/2, b.get_height(), f'-{reduction:.1f}%', ha='center', va='bottom', fontsize=9)
    ax.set_title(title, weight='bold')
    ax.set_xticks(x, labels)
    ax.set_ylabel('milliseconds')
    ax.grid(axis='y', alpha=.25)
    ax.legend(frameon=False)
fig.suptitle('Noir compiler-proved batch fusion — 15 independent Vulkan/llvmpipe runs', weight='bold')
fig.savefig(sys.argv[2], dpi=180, facecolor='white')
