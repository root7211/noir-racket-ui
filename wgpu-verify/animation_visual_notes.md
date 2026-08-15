# Animation Track / Frame-Clock 视觉核验

已检查真实 wgpu 离屏渲染的 release animation 中间态和终点。

- **40ms 帧**：第三按钮处于 pressed → base 的局部 ease-out 插值。host 只写该按钮 slot `396` 的 `pos` `[396,404)` 与 `color` `[412,428)`；其它按钮、文本和 progress geometry 均未变化。
- **80ms 帧**：轨道到达编译期 base keyframe，第三按钮恢复初始绿色与位置。此时 progress 仍保留 40%，证明 frame-clock patch 与业务 action 分离。
- **随后 action 帧**：在轨道终点之后，`advance-progress` 才写独立的 `[228,232)` `size.x` 字段并使 progress 扩展至 72%。

视觉序列与 frame-clock 审计一致：0ms / 40ms / 80ms 每帧固定写入 `[(396,8),(412,16)]`，business action 只写 `[(228,4)]`。
