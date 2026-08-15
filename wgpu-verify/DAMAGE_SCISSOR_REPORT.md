# Noir 编译期 Damage Region 合并与 Scissor/Tile Render Scheduling

## 结论

Noir 现已将编译期 Action/Animation Damage Plan 降低为真实的 wgpu 局部重绘计划。Racket 宏输出固定 `render_schedule`：任务集合、合并后的 scissor tile、覆盖率和整屏降级标记；Rust/wgpu host 不做布局求解或运行时区域推断，而是直接执行这些 tile。每个 tile 先以同一 pipeline 的背景 quad 清除旧帧像素，再在同一 scissor 内重绘预编译 Scene，避免几何移动时留下残影。

> **Noir 的运行时路径现在包含三层局部性：局部状态写入、局部 GPU buffer patch、局部屏幕 tile 重绘。**

## 宏输出的 Render Schedule

当前并发帧由三个已编译任务构成：`advance-progress`、`hover-refresh-fps-button` 与 `release-advance-progress-button`。宏从它们的固定 Damage Plan 得到三块不相交的 tile：

| Tile | 来源 | Scissor rect（px） | 面积（px²） |
|---|---|---:|---:|
| Progress | `advance-progress` | `(34, 180, 572, 22)` | 12,584 |
| FPS 按钮 | `hover-refresh-fps-button` | `(46, 230, 174.67, 46)` | 8,034.67 |
| 第三按钮 | `release-advance-progress-button` | `(411.33, 230, 174.67, 50)` | 8,733.33 |

第三 tile 的 `50px` 高度包括 base rect、高 2px 的 pressed 位移和 2px 栅格化安全边界。这个 guard 不是运行时修补：它是宏在生成 release Damage Plan 时固定的保守包围盒。

三块 tile 的总覆盖面积为 `29,352px²`，占 640×360 target（230,400px²）的 **12.7396%**，显著低于编译器设置的 `60%` 整屏降级阈值。因此 `full_redraw = false`，runtime 执行 3 个 scissor tile 而不是全屏 pass。

## Racket 的核心编译契约

运行时 Scene JSON 中的核心形态为：

```racket
(render-schedule 'concurrent-frame
  '(advance-progress hover-refresh-fps-button release-advance-progress-button)
  (list
    (render-tile 34.0 180.0 572.0 22.0 '(throughput))
    (render-tile 46.0 230.0 174.6667 46.0 '(refresh-fps-button))
    (render-tile 411.3333 230.0 174.6667 50.0 '(advance-progress-button)))
  0.1273958333
  #f)
```

宏的区域算法按如下规则工作：相交或边界相接的 rect 反复合并为最小 union tile；未相交的 rect 保持独立；以 tile 面积和除以固定 viewport 面积得到 coverage；超过阈值时，用 `(0,0,640,360)` 的 full-frame tile 替代局部 tiles。当前 demo 触发的是局部路径，但 full redraw 判断已经是正式 IR 字段，不由 host 自行决定。

## wgpu Scissor 执行路径

wgpu 后端消费 Render Schedule 时，对每个编译期 tile 执行：

```text
set_scissor_rect(tile)
→ draw 1 个预分配背景 clear quad
→ draw 所有预编译 Scene instances（受当前 scissor 裁剪）
```

背景 clear quad 与主 Scene 共享同一条 pipeline、同一 QuadInstance ABI 和同一 shader；区别仅是它的 NDC rect 覆盖全屏、背景色固定，而 scissor 将其限制在当前 tile。这样局部 pass 能正确擦除 release/pressed 几何移动后留下的旧像素，且不新增第二套画布或通用合成器。

| 验证项 | 结果 |
|---|---|
| 编译期 Render Schedule | 1 个 |
| 局部 tiles | 3 个 |
| 覆盖率 | 12.7396% |
| 整屏降级 | `false` |
| Host layout solver | 0 次调用 |
| wgpu pipeline | 1 条共享 pipeline |
| 局部 scissor vs 整屏 oracle | 完全相同的 readback tuple |

## 并发与冲突路径

40ms 同帧的无冲突版本执行以下 GPU writes：

```text
progress size.x     [228,232)
FPS hover color     [324,340)
release position    [396,404)
release color       [412,428)
```

相应 tile 只覆盖这些视觉变化所在区域。独立的同节点冲突场景中，第三按钮的 hover color 与 release color 都请求 `[412,428)`；Conflict Graph 选择 hover 为 winner，release color 被屏蔽、release position 仍执行。该场景也使用第三 tile 局部重绘，并与整屏 oracle 一致。

| 局部并发帧 | 同节点冲突局部帧 |
|---|---|
| ![并发 Scissor 帧](out/noir-damage-concurrent-040ms.png) | ![冲突 Scissor 帧](out/noir-damage-conflict-040ms.png) |

## 验证方法和边界

回归在 wgpu 0.20.1、Vulkan backend、llvmpipe CPU adapter 运行。验证器先读取 Racket JSON 并检查 tile 数、边界、覆盖率、任务顺序和 full redraw 标记；之后将局部 scissor 输出与同状态整屏 oracle 输出逐像素 readback 对照。完成之前曾出现 release 下缘残影；差异定位显示为第三按钮下缘两个像素行，促使编译器将 release Damage Tile 扩为 `pressed offset + rasterization guard`。修复后局部与整屏输出一致。

这证明的是**正确的局部重绘语义和有限的覆盖面积**，不是 GPU 性能跑分。当前实现仍对每个 tile 重绘所有 Scene instances；下一步的性能阶段应让宏同时输出每个 tile 的 `draw_range`/batch membership，使 scissor pass 不仅缩小像素工作量，也缩小实际 draw instance 范围。
