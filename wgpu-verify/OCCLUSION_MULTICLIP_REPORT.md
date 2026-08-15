# Noir：编译期 Opaque Occlusion Culling 与多层 Clip Stack

## 结论

本次实现将 Noir 的 GUI 编译路径推进到**多层裁剪与可证明安全的遮挡消除**。Racket 宏现在追踪嵌套 `stack #:clip #t` 的 ancestry，在展开期对 clip rect 求交；随后为每个 tile 中的 composite 计算有效可见矩形。只有当高 z 的节点为完全不透明、其有效矩形完整覆盖下层有效矩形时，编译器才移除下层 draw range。半透明节点永远不会触发此优化。

> **Noir 不以“更快”为理由删除 draw work；它只在编译期得到“高层不透明、完整覆盖、正确 clip 交集”三项证据后才删除。**

## 两层 Clip 模型

实验场景使用相同尺寸的两层嵌套容器：`progress-shell` 包含 `progress-layer`，二者均为 clip stack。`throughput` 与 `progress-alert` 位于内层；最终可用裁剪区是 outer 与 inner clip 的交集，当前为 `(34,180,572,22)`。

```racket
(stack #:id progress-shell #:clip #t
  (stack #:id progress-layer #:clip #t
    (progress #:id throughput #:dynamic progress #:max 100)
    (overlay #:id progress-alert #:opacity 1.0 #:z 10)))
```

每个 composite range 都携带编译期产物 `z_layer`、`clip_stack_id`、`clip_rect`、`blend_mode`、`opaque` 和 `batch_key`。不透明场景中 overlay 的合成身份为：

| 字段 | 编译结果 |
|---|---|
| `z_layer` | `10` |
| `clip_stack_id` | `progress-shell>progress-layer` |
| `clip_rect` | `(34,180,572,22)` |
| `blend_mode` | `opaque` |
| `opaque` | `true` |

## 编译期遮挡规则

对同一 tile 中任意 lower/upper pair，宏仅在下表条件全部成立时消除 lower：

| 条件 | 含义 |
|---|---|
| `upper.z > lower.z` | 覆盖层在 painter order 中更靠前。 |
| `upper.opaque?` | 上层 alpha 为 1，不能透出 lower。 |
| `effective_rect(upper)` 覆盖 `effective_rect(lower)` | 覆盖判断在 layout rect 与多层 clip 交集后进行。 |

`effective_rect(node) = layout_rect(node) ∩ final_clip_rect(node)`。这使得一个在原始 layout 上看似很大的 overlay，在被父 clip 截断后仍不会错误地消除 clip 之外或仅部分覆盖的下层内容。

## Alpha 与 Opaque 对照

| 场景 | Progress tile 的编译 draw ranges | 三个 tile 合计 instance 提交 | 语义 |
|---|---|---:|---|
| `opacity = 0.42` | outer shell、inner layer、progress、alpha overlay | 8 | **保留**完整 painter order。 |
| `opacity = 1.0` | 仅高 z opaque overlay | 5 | **安全剔除**被完整覆盖的 stack/progress ranges。 |
| 若每个 tile 全量绘制 | 13 instances × 3 tiles | 39 | 不使用 Tile Cull/occlusion 的参考工作量。 |

对 opaque 模式，progress tile 从四条可见 range 缩减为 `(slot 8, count 1)`。对 alpha 模式，compiler 保留 `(5,1)、(6,1)、(7,1)、(8,1)`，因此不存在将半透明覆盖物错误当作遮挡物的风险。

| Opaque：下层可安全剔除 | Alpha：下层必须保留 |
|---|---|
| ![opaque](out/noir-occlusion-concurrent-040ms.png) | ![alpha](out/noir-alpha-concurrent-040ms.png) |

## wgpu 验证

两种 Scene JSON 均由同一 wgpu host 消费。host 不做布局求解；它只校验 compiler 产出的 layout plan、event map、frame schedule、render schedule 及每条 range 的 nested clip ID。随后以 scissor tile 清除背景、按编译 z-order 提交 range，并在每条 range 上执行 `tile_scissor ∩ range_clip_rect`。

| 验证项 | Opaque 场景 | Alpha 对照 |
|---|---:|---:|
| Scene nodes / preallocated instances | 13 / 13 | 13 / 13 |
| Host layout solver calls | 0 | 0 |
| Render tiles / coverage | 3 / 12.7396% | 3 / 12.7396% |
| 局部 draw instances | 5 | 8 |
| 全量参考 draw instances | 39 | 39 |
| 与整屏 oracle | 完全一致 | 完全一致 |
| 共享 pipeline | 1 | 1 |

实验使用 llvmpipe Vulkan CPU adapter，因而这些结果证明的是**语义、资源范围和局部绘制等价性**，而不是独立硬件性能基准。

## 本阶段边界

当前实现支持 axis-aligned rectangular clip、固定 alpha、单 atlas page 与标准 alpha blend。它尚未涵盖 rounded clip、transform、复杂 mask、多纹理资源或 partial opaque coverage。下一个合理阶段是编译期 **Coverage Partitioning**：将一个上层不透明 rect 与下层 rect 做区域切分，只删除被覆盖的子区域，并把剩余可见部分降低为新的 tile/draw fragment，而不是要求全覆盖后才执行 cull。
