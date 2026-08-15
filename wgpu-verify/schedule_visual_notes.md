# 并发 Animation Track 调度视觉核验

已检查 wgpu 离屏并发调度工件。

- **40ms 并发帧**：同一帧中 `advance-progress` 将 progress 从 40% 扩至 72%，`hover-refresh-fps-button` 使第一按钮变亮，`release-advance-progress-button` 仅写第三按钮 position。运行时有效写集为 `[(228,4),(324,16),(396,8)]`，三段互不重叠。
- **Conflict Graph**：第三按钮的 release color `[412,428)` 与其 hover color `[412,428)` 静态重叠。因为 hover priority 为 20、大于 release priority 10，scheduler 在 40ms 显式屏蔽 release color，而没有依赖后写覆盖。
- **80ms 终点帧**：第三按钮 release 轨道恢复 base position/color；第一按钮 hover 与 progress action 的结果保持，验证不同 instance ranges 的更新没有相互破坏。

所有帧均由预编译 Layout Plan 渲染；host layout solver 调用数保持 0。
