# Event Map 视觉核验

已检查由编译期 Event Map 驱动的 wgpu 回读帧。

- **基线帧**含三块固定按钮区域，分别对应 slot `0`、`1`、`2`。它们的位置来自 Racket 宏生成的 hit rect，而不是 runtime UI tree search。
- **第三个事件后的帧**来自合成坐标 `(500, 250)`。该坐标命中 slot `2` 的 `advance-progress-button`，分发到 `advance-progress` action。最终图像中进度条由 40% 扩展为 72%，两个 text-run 则保留之前由前两次合成点击触发的 `144` / `015`。

视觉变化与日志严格一致：点击 third button 后 glyph 写入为空，instance 写入仅为 `[228, 4)`，Damage Plan 为 `throughput` 的完整最大 rect。
