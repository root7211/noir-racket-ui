#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
registry = json.loads((root / "profiles" / "registry.json").read_text())
benchmark = json.loads((root / "out" / "wgpu-benchmark.json").read_text())
profile = registry["profiles"][0]

print(f"adapter={profile['matcher']['adapter']}")
print(f"backend={profile['matcher']['backend']} resolution={profile['matcher']['width']}x{profile['matcher']['height']}")
print("strategy_reductions_vs_full_redraw")
for batch in profile["replay_strategy_costs"]["batches"]:
    candidates = {item["strategy_id"]: item for item in batch["candidates"]}
    full = candidates["full-redraw"]["gpu_median_ns"]
    coalesced = candidates["coalesced"]["gpu_median_ns"]
    reduction = 100.0 * (1.0 - coalesced / full)
    print(f"{batch['batch_id']}: full={full:.0f}ns coalesced={coalesced:.0f}ns reduction={reduction:.2f}%")

print("single_run_cpu_coldness_vs_registry_coalesced_median")
registry_by_id = {item["batch_id"]: {candidate["strategy_id"]: candidate for candidate in item["candidates"]}
                  for item in profile["replay_strategy_costs"]["batches"]}
for case in benchmark["cases"]:
    expected = registry_by_id[case["id"]]["coalesced"]["cpu_median_ns"]
    ratio = case["cpu_event_to_submit_ns"] / expected
    print(f"{case['id']}: single={case['cpu_event_to_submit_ns']}ns registry_median={expected:.0f}ns ratio={ratio:.2f}x")

print("calibration_proxy_spread")
for sample in profile["samples"]:
    ratio = sample["cpu_encode_submit_ns"] / sample["gpu_timestamp_ns"]
    print(f"{sample['name']}: cpu={sample['cpu_encode_submit_ns']:.3f}ns gpu={sample['gpu_timestamp_ns']:.3f}ns cpu_gpu_ratio={ratio:.2f}x")

scroll_rows = [json.loads(line) for line in (root / "wgpu-verify" / "out" / "noir-gpui-virtual-list-scroll-samples.jsonl").read_text().splitlines() if line]
paired = {}
for row in scroll_rows:
    paired.setdefault(row["sample"], {})[row["framework"]] = row["input_to_viewport_complete_ns"]
deltas = [values["noir"] - values["gpui"] for _, values in sorted(paired.items())]
ordered = sorted(deltas)
median_delta = ordered[len(ordered) // 2]
negative = sum(delta < 0 for delta in deltas)
positive = sum(delta > 0 for delta in deltas)
print("paired_scroll_endpoint_analysis")
print(f"median_noir_minus_goui_ns={median_delta} negative_pairs={negative} positive_pairs={positive}")
print(f"largest_gpui_endpoint_ns={max(values['gpui'] for values in paired.values())} largest_noir_endpoint_ns={max(values['noir'] for values in paired.values())}")
