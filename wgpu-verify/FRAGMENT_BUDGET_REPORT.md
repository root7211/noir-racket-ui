# Noir：编译期 Fragment Budget 与可预测退化

## 结论

Coverage Partitioning 不能无界地产生 fragment。本次实现为 Noir 引入固定 `fragment-budget = 2`，并将预算决策写入 Render Schedule。当单个 lower composite 经多个不透明覆盖物切分后得到超过两个可见 fragment 时，宏不继续传播碎片；它退化为该 lower composite 的完整 range，并在对应 tile 上记录：

```text
fallback_reason = fragment-budget-full-lower-range
```

> **Noir 的局部绘制优化现在具有静态上界：碎片化超过预算时，compiler 明确退化，而不是让复杂 UI 以隐性方式放大 draw/clip 工作。**

## 触发场景

`progress-shell > progress-layer` 的有效 clip 区为 `(34,180,572,22)`。场景在其中放置三个错开的不透明 tooltip：

| Tooltip | Rect | Z 层 |
|---|---|---:|
| `tooltip-a` | `(34,180,120,22)` | 10 |
| `tooltip-b` | `(214,180,120,22)` | 11 |
| `tooltip-c` | `(394,180,120,22)` | 12 |

若不设预算，`progress − {tooltip-a, tooltip-b, tooltip-c}` 得到三个可见段：`[154,214)`、`[334,394)` 与 `[514,606)`。这个数量 `3` 超过 `fragment-budget = 2`。

## 宏的退化规则

对每一个 lower composite，Racket 宏依次计算 `effective_rect(lower) − effective_rect(opaque-upper)`。若最终 fragment 数量不超过预算，则为每个 fragment 生成独立 `clip_stack_id` 和 batch key。若超过预算，则保留原 composite 的完整 lower range，且返回 `fragment-budget-full-lower-range`。

| 情况 | 编译计划 |
|---|---|
| fragment 数 `≤ 2` | 输出 fragment-aware clip ranges。 |
| fragment 数 `> 2` | 保留完整 lower range；tile 写入 `fallback_reason`。 |
| coverage `≥ 60%` | 使用既有 `full-redraw-threshold` 升级为完整目标重绘。 |

这不是运行时猜测：fragment 数、预算、range、退化原因与最终 scissor tile 都在宏展开期确定，并随 Scene JSON 导出到 wgpu host。

## 实测结果

| 验证项 | 结果 |
|---|---:|
| Scene nodes / 预分配 instances | 15 / 15 |
| 动态状态节点 | 3 |
| Fragment Budget | 2 |
| 候选 progress fragments | 3 |
| 选定策略 | `fragment-budget-full-lower-range` |
| Render tiles / 覆盖率 | 3 / 12.7396% |
| 局部 draw instances | 10 |
| 全量参考提交 | 45 |
| Host layout solver calls | 0 |
| 与整屏 oracle readback | 完全一致 |
| 共享 pipeline | 1 |

进度 tile 保留三个未碎片化 lower range（outer shell、inner layer、progress）以及三个 tooltip range；后两块 button tile 保持 Tile Cull。尽管局部提交量从简单 fragment 场景的 8 增加到 10，仍远低于每个 tile 提交全部 15 个实例的参考值 45，并且退化原因可被后端、测试和用户工具直接审计。

| Fragment Budget 局部帧 | 同状态整屏 oracle |
|---|---|
| ![budget](out/noir-budget-concurrent-040ms.png) | ![oracle](out/noir-budget-oracle.png) |

图中三个红色 tooltip 段与其间仍可见的 progress 片段共存。由于 compiler 采用完整 lower range 回退，而非产生超过预算的 clip fragments，局部 Scissor 输出仍与全量 oracle 逐像素一致。

## 当前边界与下一步

当前预算按**单个 lower composite 的 fragment 数**判定，退化策略为完整 lower range。下一步应加入**成本模型驱动的三档选择**：比较 fragment 个数、fragment 覆盖面积、tile draw ranges 与重绘面积，在 `fragment`、`complete-lower-range`、`full-tile-redraw` 三条路径之间选择预期 GPU 工作量最低者，并把估计成本一并写入 Render Schedule。
