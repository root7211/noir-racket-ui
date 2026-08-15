# Tile Cull 视觉核验

已检查 Tile Cull 版本的真实 wgpu 离屏帧。

- **并发 40ms 帧**：Render Schedule 保持 3 块 scissor tile、覆盖率 12.7396%，但 tile 内的 Scene draw 不再全量提交 10 个 instance。宏生成的 ranges 合计仅提交 5 个 instance：progress `(5,1)`、FPS tile `(6,2)`、第三按钮 tile `(6,1)+(9,1)`。
- **同节点冲突帧**：第三 tile 的两个非连续 range 包含 row 背景和目标按钮，保证 hover winner 与 release position 的局部更新没有视觉裁剪或残影。
- **等价性**：两个局部 range-draw 帧均通过与全 Scene 整屏 oracle 的 readback 等价检查；host layout solver 调用仍为 0。

这说明当前实验同时减少了像素覆盖（12.74%）和 Scene instance draw work（5 次而非 3 个 tile 各绘制 10 次，即 30 次）。
