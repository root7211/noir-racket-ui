# `shadow_surface_plan v1` ABI

## 目的与范围

`shadow_surface_plan v1` 将 Noir 已冻结的 `surface #:elevation 1..5` 编译为**独立、不可变的 SDF shadow pass**。它借鉴 Material 的 elevation token 表达层级关系，但不复制 Material 的运行时主题、光照或模糊系统。[1]

> v1 的 shadow 是编译器输出的有限 quad 层，而不是运行时效果。应用不能在事件处理期间申请新阴影、修改 blur、改变 alpha、移动 shadow 或重新计算 surface 几何。

该计划不修改 `QuadInstance` 的 44-byte ABI，也不改写静态 surface instance、glyph placement、virtual list ring、tile、worklist、event slot 或 action patch 地址。每个层拥有自己的只读 instance buffer 和 16-byte SDF metadata；它仅在完整静态 canvas 重建或已清除的静态 tile 内绘制。

## Scene 字段

每个 Scene 必须明确导出 `shadow_surface_plan`。`bench` preset 可以输出 `false` 以保持轻量fixture兼容；`desktop-wide` Scene 不得禁用该字段。

```json
{
  "abi_schema": "noir-shadow-surface-plan-v1",
  "abi_revision": 1,
  "layers": [
    {
      "id": "material-summary-card$shadow-2",
      "source_id": "material-summary-card",
      "source_instance_offset": 704,
      "elevation": 1,
      "layer": 2,
      "x": 229.0,
      "y": 113.0,
      "width": 496.0,
      "height": 252.0,
      "radius_px": 12.0,
      "blur_px": 7.0,
      "opacity": 0.055
    }
  ]
}
```

| 字段 | 类型 | v1 不变量 |
|---|---|---|
| `abi_schema` | string | 必须为 `noir-shadow-surface-plan-v1`。 |
| `abi_revision` | integer | 必须为 `1`。 |
| `layers` | array | 只能包含 compiler-emitted immutable layer；不得为空，且数量有 resource budget 上界。 |
| `id` | string | 由 `source_id` 和 layer 编号唯一确定。 |
| `source_id` | string | 必须指向同 Scene 的静态、正 elevation `stack` layout。 |
| `source_instance_offset` | integer | 必须精确匹配 source layout 的 44-byte quad 地址；只作反向proof witness，shader不跟随它。 |
| `elevation` | integer | 必须是固定 1–5，并与 layout 公开的编译期 elevation 一致。 |
| `layer` | integer | 每个 source 恰好拥有 recipe 指定的一组层号。 |
| `x/y/width/height` | float | 必须是 source rect 以 `blur_px` 四向扩张后的精确几何。 |
| `radius_px` | float | 必须为 source surface 的已证明圆角；`0 < radius <= min(source width, source height)/2`。 |
| `blur_px`、`opacity` | float | 必须精确匹配下表的有限 recipe，不接受任意视觉参数。 |

## 固定配方

v1 采用对称 ambient shadow，而不是可配置的方向光。两层的外层先绘制、内层后绘制；source surface 随后覆盖阴影内部，因此仅其边界以外的软化带影响最终像素。

| Elevation | Layer | `blur_px` | `opacity` |
|---:|---:|---:|---:|
| 1 | 1 | 3 | 0.140 |
| 1 | 2 | 7 | 0.055 |
| 2 | 1 | 4 | 0.170 |
| 2 | 2 | 10 | 0.070 |
| 3 | 1 | 6 | 0.190 |
| 3 | 2 | 14 | 0.080 |
| 4 | 1 | 8 | 0.210 |
| 4 | 2 | 18 | 0.090 |
| 5 | 1 | 10 | 0.230 |
| 5 | 2 | 22 | 0.100 |

Material elevation 的 level 表达 relative surface relationship，而非承诺特定的运行时 shadow 算法；因此 Noir 固定上述 recipe 是一个受限 implementation profile，而非宣称其等同于所有 Material 平台实现。[1]

## GPU 消费与固定顺序

Rust 将每个 layer 降低为一个不可变 `QuadInstance`，颜色恒定为 `[0, 0, 0, opacity]`。对应 metadata 为：

```text
[radius_px, blur_px, source_width_px, source_height_px]
```

Shadow WGSL 在扩展 quad 的局部像素空间计算 source rounded box 的 SDF；在 `[0, blur_px]` 区间内以 `smoothstep` 与 `fwidth(distance)` 形成软边。它不执行采样型Gaussian blur、不读取可变state，也不查询layout。

完整 canvas 固定顺序为：**root canvas quad → shadow layers → 剩余静态 instance → glyph placement**。该次序是 ABI 语义的一部分：root 必须先提供不透明背景，否则会覆盖shadow pass；source surface 必须后绘制以遮蔽其内部阴影。

## Rust 启动期 proof

在 GPU metadata buffer、shadow instance buffer、shadow pipeline 和首帧创建前，host 必须证明以下命题：

1. Scene ABI contract 与 payload schema/revision 精确匹配；
2. `desktop-wide` Scene 不得以 `false` 禁用 shadow plan；
3. 每个 layer ID 与 `(source_id, layer)` 地址唯一；
4. source layout 存在、tag 为 `stack`、固定 elevation 与 source instance offset 均逐项匹配；
5. layer 编号、blur 与 opacity 精确匹配当前 elevation recipe；
6. source rect 由冻结 NDC layout 反算，且 layer rect 必须是其按 blur 四向扩张的精确结果；
7. radius、几何和所有数值均有限；
8. 每个正 elevation source 都拥有其 recipe 要求的每一个 layer，且不存在额外source。

任一失败都必须在 adapter、device、storage buffer、pipeline 或 render pass 的GPU副作用之前拒绝。

## 非目标与兼容性边界

v1 不实现方向性 drop shadow、颜色阴影、动态 elevation、hover elevation、blur filter、runtime theme switching、per-corner radius、ripple 或任意组件的自由层数。hover、pressed、selection 仍只能通过既有固定 state/action slot 对 `QuadInstance` 的颜色/位置字段进行局部 patch。

`rounded_surface_plan v1` 继续负责 source surface 自身的边界 coverage；`shadow_surface_plan v1` 只负责其扩张外缘。两份计划保持独立，从而不会扩大字体、列表与渲染调度 ABI。

## 参考资料

[1]: https://m3.material.io/styles/elevation/tokens "Material Design 3 — Elevation tokens"
[2]: https://m3.material.io/foundations/design-tokens "Material Design 3 — Design tokens"
