# `rounded_surface_plan v1` ABI

## 目的

`rounded_surface_plan v1` 为Noir的**静态quad surface**提供真实圆角和抗锯齿coverage。它不修改`QuadInstance`的44-byte ABI，不改变事件、glyph、tile、worklist或instance patch地址；它只是一个独立、不可变的metadata表，按固定quad instance index由WGSL fragment阶段消费。

> 运行时不能请求新的radius、改变surface集合、移动rounded quad或改变AA规则。所有这些值由Racket宏展开期输出，并在Rust首帧前反向证明。

## Scene字段

每个Scene必须显式导出`rounded_surface_plan`。无rounded surface的fixture输出`false`；不能省略该字段。

```json
{
  "abi_schema": "noir-rounded-surface-plan-v1",
  "abi_revision": 1,
  "aa_width_px": 1.0,
  "surfaces": [
    {
      "id": "log-table-card",
      "instance_offset": 484,
      "x": 236.0,
      "y": 228.0,
      "width": 996.0,
      "height": 300.0,
      "radius_px": 12.0,
      "aa_width_px": 1.0
    }
  ]
}
```

| 字段 | 类型 | 不变量 |
|---|---|---|
| `abi_schema` | string | 精确为`noir-rounded-surface-plan-v1`。 |
| `abi_revision` | integer | 精确为`1`。 |
| `aa_width_px` | float | 精确为`1.0`；这是v1固定抗锯齿下限。 |
| `surfaces` | array | 按`instance_offset`严格升序，无重复`id`或offset。 |
| `id` | string | 必须精确匹配Scene的静态surface/button layout ID。 |
| `instance_offset` | integer | 必须是44-byte QuadInstance ABI的对齐地址，且不得指向root clear quad、动态列表row、scrollbar或glyph。 |
| `x/y/width/height` | float | 必须逐项精确匹配同ID layout entry；宽高必须大于0。 |
| `radius_px` | float | 必须为已声明theme radius；`0 < radius_px <= min(width,height)/2`。 |
| `aa_width_px` | float | 必须精确为plan的`1.0`。 |

## 允许目标

v1只允许由下列静态视觉组件lower的quad：

- `surface`，且其ID以`-tile`、`-card`、`-shell`或`-rail`结尾；
- `action-button`的button ID；
- `workspace-shell`、`page-header`与`metric-tile`生成的静态surface。

不允许目标包括root clear quad、`virtual-list` physical row、scrollbar track/thumb、focus/caret、placeholder、动态state text、page 2/3 glyph placement以及任何可由事件更新颜色或位置的quad。

## GPU消费

Rust在启动期将每一个合法surface降低为固定`vec4<f32>` metadata slot：

```text
[radius_px, aa_width_px, width_px, height_px]
```

metadata buffer的slot等于`instance_offset / 44`。未列入plan的slot为全零，fragment shader走普通矩形路径。计划内slot以unit quad的`corner`生成局部像素坐标，并计算rounded-rectangle SDF：

```text
coverage = 1 - smoothstep(0, max(aa_width_px, fwidth(distance)), distance)
alpha = quad_alpha * coverage
```

该规则只改变fragment coverage；quad的实例地址、顶点数、draw range与alpha field byte offset保持不变。

## Rust启动期proof

Rust必须在创建rounded metadata buffer、pipeline与首帧前证明：

1. Scene ABI contracts含`rounded_surface_plan`且schema/revision完全匹配；
2. plan中的每个ID唯一、layout存在、`instance_offset`与layout相等；
3. plan geometry与layout的`x/y/width/height`逐项一致；
4. offset以44-byte ABI对齐、落在resource budget内，并且其slot不是event map、virtual row、scrollbar或动态glyph关联实例；
5. radius、AA和尺寸满足上表；
6. layout中的每个带正radius的允许静态surface都恰好有一个plan entry；无radius或不允许目标不得拥有entry。

任一失败均必须在窗口、surface或GPU resource副作用前拒绝。

## 兼容性边界

`rounded_surface_plan v1`不能添加shadow、border blur、运行时hover radius或自定义per-corner radius。shadow属于后续独立`shadow_surface_plan`；hover/pressed仍使用现有固定QuadInstance color/pos patch。v1不会修改page 2、page 3、dynamic font cell、virtual list或frame worklist ABI。
