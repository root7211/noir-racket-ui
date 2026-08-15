# Noir Hover / Pressed 瞬态状态与多字段 Instance-Patch 验证

## 结论

Noir 现已将常见 GUI 瞬态反馈编译为 Event Map 驱动的固定字段更新。对第三个按钮的输入序列不再需要通用组件状态机或重新布局：`pointer-move` 仅修改 `color`；`pointer-down` 仅修改 `pos` 和 `color`；`pointer-up` 先恢复 `pos` / `color`，再从同一 Event Map binding 分发 `advance-progress` 的业务 action。

> **hover、pressed 和 release 都只改写已知 `QuadInstance` 的固定字节范围；业务 action 仍只改写自己的已编译 glyph 或 instance patch。**

## 编译期 Event Map 样式契约

Racket 宏原本已经为按钮生成 hit rect、slot、z-index、action 和 instance slot。本阶段将 base/hover/pressed style 一并编译进 Event Map，而不是由 host 自己决定颜色或位移：

```racket
(c-event slot node-id action
         x y width height z-index instance-offset
         base-color
         '(0.15 0.86 0.58 1.0)  ; hover color
         '(0.045 0.52 0.30 1.0) ; pressed color
         base-pos
         pressed-pos)
```

第三按钮的编译期产物如下：

| 属性 | 编译值 |
|---|---|
| Node / slot | `advance-progress-button` / `2` |
| Action | `advance-progress` |
| Hit rect | `(411.33, 230, 174.67, 46)` |
| Instance slot / byte range | `396` / `[396, 440)` |
| Base color | `(0.08, 0.72, 0.47, 1.0)` |
| Hover color | `(0.15, 0.86, 0.58, 1.0)` |
| Pressed color | `(0.045, 0.52, 0.30, 1.0)` |
| Pressed displacement | `2px` 向下，即 NDC `y - 4/360` |

这里的 `instance_offset=396` 是 Layout Plan 内稳定的第 9 个 slot；host 不再需要通过 node ID 遍历 Scene tree 查找它。

## wgpu 瞬态更新器

`apply_interaction_patch` 只接受已通过 Event Map hit-test 得到的 binding。它固定使用 `QuadInstance` ABI：`pos` 在 slot 内偏移 `0`、长度 `8`，`color` 在偏移 `16`、长度 `16`。

```rust
match phase {
    InteractionPhase::Hover =>
        write(COLOR_OFFSET, bytemuck::cast_slice(&event.hover_color))?,
    InteractionPhase::Pressed => {
        write(POS_OFFSET, bytemuck::cast_slice(&event.pressed_pos))?;
        write(COLOR_OFFSET, bytemuck::cast_slice(&event.pressed_color))?;
    }
    InteractionPhase::Release => {
        write(POS_OFFSET, bytemuck::cast_slice(&event.base_pos))?;
        write(COLOR_OFFSET, bytemuck::cast_slice(&event.base_color))?;
    }
}
```

所有 `offset` 都等于 `event.instance_offset + field_offset`。对 slot 2，这产生唯一允许的更新范围：

| 阶段 | GPU instance writes | 含义 |
|---|---|---|
| `hover` | `[(412, 16)]` | 只写 color。 |
| `pressed` | `[(396, 8), (412, 16)]` | 写 pos，再写 color。 |
| `release` | `[(396, 8), (412, 16)]` | 恢复 pos 与 color。 |
| release action | `[(228, 4)]` | `progress` 的 `size.x`；与按钮 slot 无关。 |

## 合成输入闭环

验证器首先通过 pointer `(100,250)` 和 `(280,250)` 分发两个 text action，使 text-run 显示 `144` / `015`。之后 pointer `(500,250)` 命中 slot 2，并运行完整瞬态状态机：

```text
pointer-move (500,250) → slot 2 → hover color write [412,16]
pointer-down (500,250) → slot 2 → pos [396,8] + color [412,16]
pointer-up   (500,250) → slot 2 → restore pos/color
                            → advance-progress action
                            → progress size.x [228,4] + Damage Plan
```

回归运行在 wgpu 0.20.1、Vulkan backend、llvmpipe CPU adapter 上通过。每个阶段都具有可见帧变化；同时 `host layout solver calls: 0`，共享 render pipeline 数量保持 `1`。

## 可视化工件

Hover 帧仅使第三按钮变亮；pressed 帧使其变暗并向下移动；release/action 帧恢复按钮视觉并把 progress 从 40% 扩展为 72%。

| Hover：只改 color | Pressed：只改 pos + color | Release + action：恢复后只更新 progress |
|---|---|---|
| ![hover](out/noir-transient-hover.png) | ![pressed](out/noir-transient-pressed.png) | ![release](out/noir-transient-release-action.png) |

## 当前边界与下一步

该实验验证了单 pointer 的命中、hover、pressed 和 release。它尚未支持 pointer capture、drag threshold、多个 pointer、键盘 focus、残障语义或动画曲线。下一阶段应先实现 **编译期 animation track + frame-clock patch**：例如 pressed 到 base color/position 的 80ms 插值仍应只作用于同一固定 instance fields，并在每帧写入明确的 8/16-byte 范围，而非引入通用 scene animation runtime。
