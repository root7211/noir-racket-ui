# Noir：编译期 Coverage Partitioning

## 结论

Noir 已从“完全遮挡时删除整个节点”推进到**部分遮挡时切分可见区域**。当一个高 z、完全不透明的 tooltip 覆盖 progress bar 左半区时，Racket 宏不会保留完整 progress quad，也不会错误删除整个 progress。它在展开期计算矩形差集，并将下层 composite 降低为右半区的固定 fragment clip range。

> **局部可见性不再只是 tile 级别的提示；它已成为每条 draw range 的编译期几何约束。**

## 场景与差集

实验中的嵌套 clip 有效矩形为 `(34,180,572,22)`。高 z tooltip 是固定不透明 overlay，尺寸为 `(286,22)`，因此覆盖左半区 `(34,180,286,22)`。对每个下层 composite，宏计算：

```text
visible = effective_rect(lower) − effective_rect(opaque-tooltip)
        = (320,180,286,22)
```

`effective_rect(node)` 始终先计算 layout rect 与两层 clip stack 的交集。于是 fragment 不会越过 `progress-shell > progress-layer` 的限制，也不会依赖 host 的运行时几何计算。

| Composite | 原有效矩形 | 可见 fragment | Z 层 |
|---|---|---|---:|
| `progress-shell` | `(34,180,572,22)` | `(320,180,286,22)` | 0 |
| `progress-layer` | `(34,180,572,22)` | `(320,180,286,22)` | 0 |
| `throughput` | `(34,180,572,22)` | `(320,180,286,22)` | 0 |
| `progress-alert` | `(34,180,286,22)` | 原样保留 | 10 |

## 编译产物

每个 fragment 保留原 instance slot，但获得新、稳定的 `clip_stack_id` 与 `batch_key`，例如：

```text
progress-shell>progress-layer|fragment:0
shared-quad-atlas|clip:progress-shell>progress-layer|fragment:0|blend:opaque
```

这保证 fragment 不会与完整范围错误 batch；wgpu 通过 `tile scissor ∩ fragment clip rect` 执行实际绘制。当前矩形差集最多产出四个 fragment，因而算法的复杂度在该受限 DSL 中有静态上界。

## 验证

| 项目 | 结果 |
|---|---:|
| Scene nodes / 预分配 instances | 13 / 13 |
| 嵌套 clip 深度 | 2 |
| Tooltip 覆盖 | progress 左半区 286×22 px |
| 下层 fragment | progress 右半区 286×22 px |
| Render tiles / 覆盖率 | 3 / 12.7396% |
| Tile draw instances | 8 |
| 参考全量提交 | 39 |
| Host layout solver calls | 0 |
| 与整屏 oracle readback | 完全一致 |
| 共享 pipeline | 1 |

`8` 个 instance 提交与半透明对照相同；这是因为当前优化目标是**减少 fragment 的像素覆盖与正确切分绘制区域**，而不是减少下层 logical instance 数量。后续若要进一步减少实例提交，应将 fragment 几何下沉为专用 clipped-quad instance，或引入由 shader 直接消费的 tile-local rect list。

| 部分不透明遮挡后的局部渲染 | 同状态整屏 oracle |
|---|---|
| ![partition](out/noir-partition-concurrent-040ms.png) | ![oracle](out/noir-partition-oracle.png) |

局部帧左半区为不透明红色 tooltip，右半区保留 progress 的绿色已填充部分与深色未填充部分。该图与同状态整屏 oracle 的 readback 完全一致。

## 当前边界

目前仅支持 axis-aligned rectangle 差集和固定不透明覆盖物；多个交叠 tooltip 会导致 fragment 数量增长。下一阶段应加入**Fragment Budget 与退化策略**：宏对每个 tile 设定最大 fragment 数；当差集导致过多碎片时，自动回退为完整 lower range 或整 tile 重绘，并将该选择作为可审计 Render Schedule 决策输出。
