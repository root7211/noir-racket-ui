# Hover / Pressed 瞬态交互视觉核验

已检查真实 wgpu 离屏渲染的 transient 阶段。

- **Hover**：合成 pointer `(500,250)` 命中 slot 2。输出帧中仅第三按钮由 base green 变为 hover green。验证器审计的 GPU 写入为 `[(412,16)]`，即第三按钮 instance slot `396` 的 `color` 字段。
- **Pressed**：同一 binding 的第三按钮显示 pressed dark green，并按下移 2 px。审计写入为 `[(396,8),(412,16)]`，分别为 `pos` 与 `color` 字段。

数字 `144` / `015`、进度条的 40% 宽度、前两个按钮和所有容器几何在两个瞬态帧中保持不变。这与编译期 Event Map 中的 `instance_offset=396`、base/hover/pressed style 以及 host 的零布局求解约束一致。
