# Noir 编译期 Draw Range、Batch Membership 与 Tile Cull

## 结论

Noir 现已在 Scissor Tile 之上完成第二层渲染裁剪：**每块局部 tile 不再提交整个 Scene 的 instance buffer，而只提交宏在编译期分析得到的可见 instance ranges。** Racket 宏基于 Layout Plan 的稳定 rect 与 instance offset，计算 tile/节点的几何相交关系，按 instance slot 排序并压缩连续区间；wgpu 后端只执行这些 range draw，同时继续用整屏 oracle 验证输出等价。

> **Noir 的局部更新路径已经从“少更新、少重绘”进一步变成“少提交 draw work”。**

## 编译期可见性与 Range 压缩

每个 Layout entry 都已有编译期确定的 `(x, y, width, height, instance_offset)`。宏对每个 Render Tile 执行严格矩形相交测试；可见 entry 的 slot 由 `instance_offset / 44` 得到，排序后压缩成连续 `draw-range`：

```racket
(draw-range first-instance instance-count vertex-count batch-key)
```

当前 MVP 中所有 quad/text-run 都使用同一条 WGSL pipeline、同一数字 atlas 和同一裁剪模型，因此 batch key 固定为 `shared-quad-atlas`。`vertex-count` 固定为 18：text-run 可以绘制三个 glyph quad；静态 quad 的 shader 会在第六个顶点之后移至 clip 外。这让 host 不需要按 node 类型重新分组。

| Tile | 宏生成的可见 instance range | 提交 instance 数 | 说明 |
|---|---:|---:|---|
| Progress | `(5, 1)` | 1 | 只绘制 progress quad。 |
| FPS hover | `(6, 2)` | 2 | row 背景与第一按钮。 |
| 第三按钮 release | `(6, 1)`、`(9, 1)` | 2 | row 背景和非连续的第三按钮。 |

第三 tile 特意保留两条 range，而没有把 slot 7–8 一并提交。这是 batch membership 的关键证据：可见性不是“取从最小到最大 slot 的大区间”，而是精确保留必要成员。

## 编译期 Render Schedule

并发帧的完整运行时产物包含 3 个 tile、12.7396% coverage、`full_redraw = false`，以及合计 5 个提交实例：

```text
progress tile:   draw(0..18, 5..6)
FPS tile:        draw(0..18, 6..8)
third tile:      draw(0..18, 6..7)
                 draw(0..18, 9..10)
```

若保持前一版行为，每个 tile 都会提交全量 10 个 Scene instances，即 `3 × 10 = 30` 个 instance 提交。Tile Cull 将该数字缩小为 **5**，减少 **83.33%** 的实例提交量；这是本示例的编译产物计数，**不是通用 GPU 性能跑分**。

## wgpu 执行路径

每块 tile 在 wgpu 中使用固定顺序：先在 scissor 内绘制一个预分配背景 clear quad，清除上一帧残留；再把主 instance buffer 绑定到同一 pipeline，并迭代该 tile 的宏生成 draw ranges。后端不会遍历 UI tree，不会进行运行时 rect 相交测试，也不会根据 tag 重新 batching。

| 验证项 | 实测结果 |
|---|---|
| Scene instances | 10 |
| Scissor tiles | 3 |
| Tile 覆盖率 | 12.7396% |
| Tile Cull draw instances | 5 |
| 旧全量 tile draw instances | 30 |
| Host layout solver calls | 0 |
| Shared pipeline | 1 |
| 局部 range draw vs 整屏 oracle | readback 完全一致 |

| 并发 Tile Cull 帧 | 同节点冲突 Tile Cull 帧 |
|---|---|
| ![concurrent](out/noir-tile-concurrent-040ms.png) | ![conflict](out/noir-tile-conflict-040ms.png) |

## 验证边界

当前 demo 的 parent row background 会与两个按钮 tile 相交，因此它被列为必要 batch member。真实生产框架还需要处理 clip stack、透明混合、z-order、overdraw 合并、纹理切换与文本 atlas page 等更复杂的 batching 条件。当前实现的贡献是把最关键的契约固定下来：**可见性、instance membership、range 连续性和 batch key 都是编译器输出，runtime 只负责执行并核验。**

下一步应实现 **Clip Stack + Z-order + Overlap-aware Batch Scheduling**：让宏为每个 tile 产生正确的绘制层次、裁剪栈和透明度依赖，然后在仍保证视觉等价的前提下合并相邻相同 batch 的范围。
