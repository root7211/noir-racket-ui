# Dynamic Geometry / Instance-Patch 视觉核验

已检查真实 wgpu 离屏回读的两个关键帧。

- **基线帧**：`throughput` progress node 位于宏生成的固定 instance slot `220`（instance byte range `[220,264)`），初始状态 `progress = 40` 被编译为 `size.x = 0.715` NDC，即最大 rect 的 40%。
- **`advance-progress` 后**：进度条在同一 `pos`、同一 `size.y`、同一颜色和同一 Layout Plan rect 内扩展为 72%。可见改变来自 action plan 中唯一的 `queue.write_buffer(instance_buffer, 228, 4 bytes)`；`228 = 220 + 8`，即 QuadInstance 的 `size.x` 字段。

文字 text-run 在最终帧中保持之前 action 造成的 `144` / `015`，按钮和所有容器几何也保持不变。此视觉结论与 JSON Damage Plan `(x=34, y=180, width=572, height=22, instance_offset=220)` 和 wgpu 写入审计一致。
