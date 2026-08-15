#!/usr/bin/env python3
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('wgpu-verify/out/noir-gpui-virtual-list-scroll-samples.jsonl')
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json')
rows = [json.loads(line) for line in src.read_text().splitlines() if line.strip()]
groups = defaultdict(list)
for row in rows:
    groups[row['framework']].append(row)

def pctl(values, p):
    values = sorted(values)
    k = (len(values) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)

def summarize(items):
    values = [item['input_to_viewport_complete_ns'] for item in items]
    return {
        'sample_count': len(values),
        'wheel_clicks_per_sample': items[0]['wheel_clicks'],
        'endpoint_viewport': items[0]['end_viewport'],
        'median_ns': statistics.median(values),
        'p95_ns': pctl(values, 0.95),
        'min_ns': min(values),
        'max_ns': max(values),
        'mean_ns': statistics.mean(values),
        'stdev_ns': statistics.stdev(values) if len(values) > 1 else 0.0,
    }

result = {
    'metric': 'x11_wheel_to_endpoint_viewport_excluding_gpu_present',
    'method': 'Three zero-delay X11 wheel-down clicks; timer ends when each framework logs viewport rows 5..7.',
    'frameworks': {name: summarize(items) for name, items in groups.items()},
    'limitations': [
        'Not GPU frame time, GPU timestamp, or input-to-present latency.',
        'The external metric includes X11 injection, process scheduling, output logging, and polling.',
        'Noir scrolls through compiler-fixed row patch tables; GPUI uses native uniform_list scrolling. Both present a fixed capacity-8 list with a three-row viewport.'
    ]
}
if 'noir' in result['frameworks'] and 'gpui' in result['frameworks']:
    result['median_relative_change_noir_vs_gpui_pct'] = (result['frameworks']['noir']['median_ns'] / result['frameworks']['gpui']['median_ns'] - 1.0) * 100.0
out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
