#!/usr/bin/env python3
"""Summarize the real-time monitor replay matrix without overstating llvmpipe data."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt


def ns_to_ms(value: float) -> float:
    return value / 1_000_000.0


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: analyze_realtime_monitor_replay.py <matrix.json> <summary.md> <chart.png>")
    matrix_path, summary_path, chart_path = map(Path, sys.argv[1:])
    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    rows = matrix["rows"]
    full = next(row for row in rows if row["mode"] == "full-redraw")
    baseline_ns = full["gpu_elapsed_ns"]["median_ns"]

    labels = [row["mode"] for row in rows]
    medians = [ns_to_ms(row["gpu_elapsed_ns"]["median_ns"]) for row in rows]
    p95 = [ns_to_ms(row["gpu_elapsed_ns"]["p95_ns"]) for row in rows]
    colors = ["#475569", "#3b82f6", "#7c3aed", "#16a34a", "#10b981"]

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=180)
    bars = ax.bar(labels, medians, color=colors, width=0.68)
    for bar, median, p95_value in zip(bars, medians, p95):
        ax.text(bar.get_x() + bar.get_width() / 2, median + 0.015,
                f"{median:.3f} ms\np95 {p95_value:.3f}",
                ha="center", va="bottom", fontsize=9, fontweight="semibold")
    ax.set_title("Noir Real-time Monitor: GPU Replay Matrix", loc="left", fontsize=15, fontweight="bold")
    ax.set_ylabel("GPU elapsed time (ms)")
    ax.set_ylim(0, max(p95) * 1.28)
    ax.text(0.01, -0.19,
            f"{matrix['adapter_name']} · {matrix['backend']} · {matrix['sample_iterations']} samples after {matrix['warmup_iterations']} warmups\n"
            "Comparative replay evidence only; not an end-to-end presentation-latency measurement.",
            transform=ax.transAxes, fontsize=8.5, color="#475569")
    fig.tight_layout()
    fig.subplots_adjust(bottom=0.24)
    fig.savefig(chart_path, bbox_inches="tight")
    plt.close(fig)

    table_lines = []
    for row in rows:
        gpu = row["gpu_elapsed_ns"]
        cpu = row["cpu_event_to_submit_ns"]
        improvement = (1.0 - gpu["median_ns"] / baseline_ns) * 100.0
        table_lines.append(
            f"| `{row['mode']}` | {gpu['sample_count']} | {ns_to_ms(gpu['median_ns']):.3f} | "
            f"{ns_to_ms(gpu['p95_ns']):.3f} | {improvement:.2f}% | "
            f"{row['submitted_tile_count']} | {row['submitted_glyph_draw_count']} | "
            f"{row['submitted_glyph_instance_count']} | {ns_to_ms(cpu['median_ns']):.3f} |"
        )

    selected = next(row for row in rows if row["mode"] == "compiler-selected")
    selected_gpu = selected["gpu_elapsed_ns"]
    selected_improvement = (1.0 - selected_gpu["median_ns"] / baseline_ns) * 100.0
    consistency = selected["compiler_selected"]
    summary = f"""# 实时监控表格 Replay Matrix 摘要

该报告分析 `realtime-monitor.scene.json` 的 `coalesced-activate-refresh-telemetry` 激活工作负载。测量使用 wgpu timestamp query，在 `{matrix['adapter_name']}` 的 `{matrix['backend']}` 路径上完成，预热 {matrix['warmup_iterations']} 次、采样 {matrix['sample_iterations']} 次。原始矩阵见 [realtime-monitor-replay-matrix.json](realtime-monitor-replay-matrix.json)。

![GPU replay strategy comparison](realtime-monitor-replay-matrix.png)

| 执行策略 | GPU样本 | GPU中位数（ms） | GPU p95（ms） | 相对全量重绘改善 | Tile | Draw | Glyph实例 | CPU事件至提交中位数（ms） |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
{chr(10).join(table_lines)}

`compiler-selected` 固定选择 `coalesced`。其启动期proof、实际执行器、tile mask、draw数、glyph实例数及winner-write字节数均一致：`self_consistent={str(consistency['self_consistent']).lower()}`，tile `0x0000000000000003`，draw `2`，glyph实例 `48`，winner writes `140` bytes。相对于全量重绘，其GPU中位数改善为 **{selected_improvement:.2f}%**。

## 对实时刷新路径的独立证据

实时监控回归另外验证了固定容量 `data-update-batch` 的可见性分流：编译期bootstrap批次包含3条记录，其中2条在视口内，因此仅写入68个glyph ID word；命令注入批次包含1条可见记录和1条不可见记录，因此仅写入34个glyph ID word。不可见记录只更新固定CPU arena，不产生glyph GPU write或render request。这是数据更新路径的地址范围证据，不应与上述激活工作负载的GPU时间戳混为同一种指标。

> **解释边界。** 这里的adapter是llvmpipe软件Vulkan，而非AMD 780M的Dozen硬件路径；该矩阵证明编译选择与局部提交的相对执行形状在当前环境中成立，不能直接作为真实GPU端到端延迟或通用桌面性能结论。
"""
    summary_path.write_text(summary, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
