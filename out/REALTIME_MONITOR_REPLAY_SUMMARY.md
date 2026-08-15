# 实时监控表格 Replay Matrix 摘要

该报告分析 `realtime-monitor.scene.json` 的 `coalesced-activate-refresh-telemetry` 激活工作负载。测量使用 wgpu timestamp query，在 `llvmpipe (LLVM 20.1.2, 256 bits)` 的 `Vulkan` 路径上完成，预热 5 次、采样 25 次。原始矩阵见 [realtime-monitor-replay-matrix.json](realtime-monitor-replay-matrix.json)。

![GPU replay strategy comparison](realtime-monitor-replay-matrix.png)

| 执行策略 | GPU样本 | GPU中位数（ms） | GPU p95（ms） | 相对全量重绘改善 | Tile | Draw | Glyph实例 | CPU事件至提交中位数（ms） |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `full-redraw` | 25 | 1.186 | 1.341 | 0.00% | 1 | 4 | 236 | 0.165 |
| `packet-aware` | 25 | 0.616 | 0.727 | 48.09% | 3 | 2 | 48 | 0.178 |
| `action-aware` | 25 | 0.316 | 0.392 | 73.35% | 1 | 1 | 29 | 0.108 |
| `coalesced` | 25 | 0.504 | 0.638 | 57.51% | 2 | 2 | 48 | 0.145 |
| `compiler-selected` | 25 | 0.507 | 0.699 | 57.25% | 2 | 2 | 48 | 0.140 |

`compiler-selected` 固定选择 `coalesced`。其启动期proof、实际执行器、tile mask、draw数、glyph实例数及winner-write字节数均一致：`self_consistent=true`，tile `0x0000000000000003`，draw `2`，glyph实例 `48`，winner writes `140` bytes。相对于全量重绘，其GPU中位数改善为 **57.25%**。

## 对实时刷新路径的独立证据

实时监控回归另外验证了固定容量 `data-update-batch` 的可见性分流：编译期bootstrap批次包含3条记录，其中2条在视口内，因此仅写入68个glyph ID word；命令注入批次包含1条可见记录和1条不可见记录，因此仅写入34个glyph ID word。不可见记录只更新固定CPU arena，不产生glyph GPU write或render request。这是数据更新路径的地址范围证据，不应与上述激活工作负载的GPU时间戳混为同一种指标。

> **解释边界。** 这里的adapter是llvmpipe软件Vulkan，而非AMD 780M的Dozen硬件路径；该矩阵证明编译选择与局部提交的相对执行形状在当前环境中成立，不能直接作为真实GPU端到端延迟或通用桌面性能结论。
