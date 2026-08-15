# 编译期 Layout Plan 视觉核验

已检查 Layout Plan 版本的真实 wgpu 离屏 PNG。

- **基线帧**：Racket 宏生成的固定 NDC rect 和 8 个 instance slot 正确绘制出 dashboard、两个 3-glyph text-run 与两个按钮区域。
- **执行 `refresh-fps` 后**：只有 `fps` text-run 的前三个数字从 `060` 变为 `144`；`latency` 的后三区 glyph、所有容器几何、按钮实例位置均保持不变。

该视觉结果与 host 审计一致：host 不再遍历 Scene tree 或计算 rect/NDC；它只解码 8 个预编译 Layout Entry，并在动作后写入 glyph buffer `[0,96)`。
