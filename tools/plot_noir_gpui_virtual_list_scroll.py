#!/usr/bin/env python3
import json
import sys
from pathlib import Path
import matplotlib.pyplot as plt

src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json')
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('wgpu-verify/out/noir-gpui-virtual-list-scroll-comparison.png')
data = json.loads(src.read_text())
keys = ['noir', 'gpui']
labels = ['Noir', 'GPUI']
median = [data['frameworks'][key]['median_ns'] / 1e6 for key in keys]
p95 = [data['frameworks'][key]['p95_ns'] / 1e6 for key in keys]
fig, ax = plt.subplots(figsize=(8, 4.8), constrained_layout=True)
x = [0, 1]
w = 0.34
ax.bar([v - w / 2 for v in x], median, w, color='#2d73b9', label='Median')
ax.bar([v + w / 2 for v in x], p95, w, color='#df8b35', label='P95')
ax.set_xticks(x, labels)
ax.set_ylabel('ms to viewport rows 5–7')
ax.set_title('Virtual-list scroll endpoint: X11 wheel input to visible-range completion')
ax.set_ylim(0, max(p95) * 1.22)
for xs, values in (([v - w / 2 for v in x], median), ([v + w / 2 for v in x], p95)):
    for pos, value in zip(xs, values):
        ax.text(pos, value + max(p95) * .018, f'{value:.3f}', ha='center', va='bottom', fontsize=9)
ax.legend()
ax.text(.5, -.22, '15 samples; 3 zero-delay X11 wheel clicks/sample; excludes GPU timestamps and presentation', transform=ax.transAxes, ha='center', fontsize=8)
fig.savefig(out, dpi=180)
print(out)
