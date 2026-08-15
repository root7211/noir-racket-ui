# Noir：编译期 Cost Model 与三档 Render Strategy Selection

## 结论

Noir 的 Render Schedule 已从固定 Fragment Budget 规则升级为**可审计的静态成本选择器**。每个 tile 在宏展开期比较三条候选路径，并将 `candidate_costs`、`selected_strategy` 与 `fallback_reason` 导出到 Scene JSON；wgpu host 不自行重新决定路径，只校验并执行 compiler 的计划。

> **运行时不猜测“局部还是全量更快”；它执行 compiler 已计算、可检查、可复现的策略。**

## 三档策略

| 策略 | 何时可选 | 当前含义 |
|---|---|---|
| `fragment` | 差集碎片未超预算，且该路径成本最低。 | 每条可见 fragment 使用固定 clip/batch range。 |
| `complete-lower-range` | 差集超预算，但完整 visible range 比 full tile 成本低。 | 放弃 fragment，保留完整 lower composite。 |
| `full-tile-redraw` | 差集超预算，且完整 tile 估计成本低于完整 lower-range 调度。 | 在本 tile 内使用未碎片化、正确 painter-order 的完整 composite 集。 |

完整 viewport 仍由既有 `full-redraw-threshold = 60%` 决定；这里的 `full-tile-redraw` 指一个已存在的局部 damage tile，而不是整屏无条件重绘。

## 静态成本模型

对于 fragment 与 complete 候选，成本为：

```text
cost = 600 × draw_range_count + Σ(clip_rect_area)
```

其中 `600` 是固定提交/状态变更权重，面积项代表像素覆盖工作。对 full-tile 路径，使用：

```text
cost = 600 × visible_composite_count + 4 × tile_area
```

`fragment-budget = 2` 仍是安全上限。若任一 lower composite 的可见差集超过该值，fragment 候选标记为 `1e30`，从而不可能被选中。这让成本选择始终发生在安全、有限的候选空间内。

## 实验选择结果

三个错开的 tooltip 使 progress 下层理论上产生三个差集 fragment。第一 tile 的 compiler 成本表满足：

| 候选 | 相对结果 | Compiler 决策 |
|---|---:|---|
| `fragment` | `1e30`，因预算超限不可用 | 拒绝。 |
| `complete-lower-range` | `296,920` | 可用但非最低。 |
| `full-tile-redraw` | `53,936` | **选中**。 |

同一并发帧的两个轻量按钮 tile 没有差集超限，其 `full-tile-redraw` 候选为 `1e30`（不开放），且 `fragment` 成本低于 `complete-lower-range`，因此选择 `fragment`。

| Tile | Selected strategy | Fallback/selection reason |
|---|---|---|
| 三 tooltip progress tile | `full-tile-redraw` | `cost-model-full-tile-redraw` |
| FPS hover tile | `fragment` | `cost-model-minimum` |
| Progress button release tile | `fragment` | `cost-model-minimum` |

## wgpu 验证

| 验证项 | 结果 |
|---|---:|
| Scene nodes / 预分配 instances | 15 / 15 |
| Render tiles / 覆盖率 | 3 / 12.7396% |
| 局部提交 instances | 10 |
| 全量参考提交 | 45 |
| Host layout solver calls | 0 |
| 共享 pipeline | 1 |
| 局部输出与全 Scene oracle | 完全一致 |

密集 progress tile 虽采用 full-tile-redraw，仍只重绘其局部 damage rect；后续轻量 tile 继续由 fragment 策略执行。这样，策略退化不会冲掉全局的局部更新收益。

| Cost Model 局部帧 | 同状态整屏 oracle |
|---|---|
| ![cost](out/noir-cost-concurrent-040ms.png) | ![oracle](out/noir-cost-oracle.png) |

## 当前边界

当前权重为明确、可审计的静态启发式，尚未以实测 GPU profiling 自动校准。下一阶段应增加**Profile-guided Cost Calibration**：在开发模式下采集每种 batch/clip 策略的 GPU timestamp 与 CPU submission 时间，将其编译为设备/后端相关但版本化的 cost profile；发布构建仍只消费冻结 profile，保持运行时无自适应抖动。
