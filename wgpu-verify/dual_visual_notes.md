# 双绑定视觉核验笔记

已查看两帧真实 wgpu 离屏回读 PNG：

- **基线帧**：左侧 `fps` 动态 tile 为绿色编码，对应 `frame-rate = 60`；右侧 `latency` 动态 tile 为蓝色编码，对应 `latency-ms = 8`。
- **仅执行 `refresh-fps` 后**：左侧 tile 变为青色编码，对应 `frame-rate = 144`；右侧 tile 保持与基线完全相同的蓝色编码，对应 `latency-ms = 8`。

这与 GPU 审计一致：`refresh-fps` 仅写入 glyph buffer `[0, 96)`，没有写入延迟绑定的 `[96, 192)`，也没有重写 instance buffer。
