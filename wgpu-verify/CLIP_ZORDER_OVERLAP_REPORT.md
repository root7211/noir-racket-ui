# Noir 编译期 Clip Stack、Z-order 与 Overlap-aware Batch Scheduling

## 结论

Noir 现已具备受限 GUI 合成所需的三个编译期契约：**clip stack、painter's z-order，以及透明重叠下不可随意重排的 batch membership**。新增的 `stack #:clip #t` 和 `overlay #:opacity … #:z …` 不在 runtime 解释；Racket 宏把节点 ancestry、固定 layout、透明度与显式层级降低为每条 `draw-range` 的合成上下文。wgpu host 只读取、校验并执行该上下文。

> **对每一条 GPU draw，Noir 现在不仅知道“画哪几个 instance”，还知道“在什么裁剪层里、以什么透明度、在谁之前或之后画”。**

## 受限 DSL 场景

dashboard 的 progress 区域由一个 `stack` 构成。`throughput` 为动态 progress；`progress-alert` 为静态半透明 overlay。两者 layout rect 相同，但 overlay 声明 `#:z 10`，并继承 `progress-layer` 的 clip stack。

```racket
(stack #:id progress-layer #:clip #t
  (progress #:id throughput #:dynamic progress #:max 100)
  (overlay #:id progress-alert #:opacity 0.42 #:z 10))
```

| 节点 | Z 层 | Clip stack | Blend | 是否可覆盖下层 |
|---|---:|---|---|---|
| `progress-layer` | 0 | `root` | opaque | 否，作为局部背景。 |
| `throughput` | 0 | `progress-layer` | opaque | 否，必须在 overlay 前绘制。 |
| `progress-alert` | 10 | `progress-layer` | alpha | 是，但不能把底层 progress 从 batch 中剔除。 |

该限制是当前版本的“overlap-aware”核心：透明 overlay 与下层 instance 相交时，宏保留双方，并将 overlay 作为单独 alpha batch 放在更高 z-layer；它不会像不透明覆盖物那样把底层内容错误 cull 掉。

## 编译期 Draw Range

运行时 JSON 中的每条 `draw-range` 具有以下字段：

```text
first_instance, instance_count, vertex_count,
batch_key, z_layer, clip_stack_id, clip_rect,
blend_mode, opaque
```

progress tile 生成三个稳定且有序的 range：

| 顺序 | Instance | Batch key | Z | Clip | Blend |
|---:|---:|---|---:|---|---|
| 1 | `(5,1)` | `…clip:root…opaque` | 0 | viewport | opaque |
| 2 | `(6,1)` | `…clip:progress-layer…opaque` | 0 | `(34,180,572,22)` | opaque |
| 3 | `(7,1)` | `…clip:progress-layer…alpha` | 10 | `(34,180,572,22)` | alpha |

另两块 button tile 继续使用 root clip。三个 scissor tile 的范围不变，覆盖率为 **12.7396%**；12 instance 场景合计提交 **7 个 tile draw instances**，而若每个 tile 全量绘制则会提交 `3 × 12 = 36` 个 instance。该数字描述本实验的编译产物工作量，不是通用 GPU 性能基准。

## wgpu 执行路径

后端保留一条共享 alpha-blended quad pipeline。每个 tile 的运行流程为：以 scissor 限制 tile、绘制预分配 clear quad、按已编译 `(z_layer, stable slot)` 顺序遍历 draw ranges、取 tile scissor 与 range 的 `clip_rect` 交集、最后提交 range 内的实例。

```text
Tile scissor
  → background clear quad
  → range 1: root/opaque
  → range 2: progress-layer/opaque
  → range 3: progress-layer/alpha
```

range clip 使用保守的像素量化：`floor(left/top)` 与 `ceil(right/bottom)`。这是必要的 rasterization guard：初版使用向内取整时，分数 pixel button 边界少覆盖了一列像素，导致局部结果与全屏 oracle 不同。扩展边界后，局部和全量输出再次完全一致。

## 验证结果

| 验证项 | 结果 |
|---|---|
| Racket 静态节点 / 动态节点 | 9 / 3 |
| 预分配 GPU instances | 12 |
| Render tiles | 3 |
| 局部覆盖率 | 12.7396% |
| Tile Cull instance 提交 | 7，而非 36 |
| 共享 pipeline | 1 条 |
| Host layout solver | 0 次调用 |
| Alpha overlay | `z=10`、`progress-layer` clip、`blend=alpha` |
| 局部 Scissor + range draw vs 全 Scene oracle | readback tuple 完全一致 |

| Clip/Z-order 基线 | 同帧局部 action / hover / release |
|---|---|
| ![baseline](out/noir-clip-baseline.png) | ![concurrent](out/noir-clip-concurrent-040ms.png) |

## 边界与下一步

当前 DSL 的 clip stack 仅覆盖 axis-aligned `stack` 矩形；batch key 也只有一个 atlas page 和两种 blend mode。它尚未处理嵌套 rounded clip、复杂遮罩、多纹理 atlas page、transform、或真正的 opaque occlusion elimination。下一步应是**多层 Clip Stack 与 Opaque Occlusion Culling**：宏为嵌套 clip 生成 stack ID/交集，同时只对被完整不透明覆盖的下层 range 做可证明安全的移除；半透明层仍保留严格 painter order。
