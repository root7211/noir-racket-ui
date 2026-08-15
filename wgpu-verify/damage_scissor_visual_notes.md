# Damage / Scissor Tile 视觉核验

已检查两个由真实 wgpu scissor render pass 生成的 640×360 离屏帧。

- **并发 40ms 帧**：progress bar 已扩展至 72%，第一按钮保持 hover 高亮，第三按钮执行 40ms release 位移/颜色插值。Racket 生成的三块 tile 覆盖率为 `0.1273958333`，即约 **12.74%** 屏幕面积；host 先用同一 pipeline 的背景 quad 清除每块 tile，再重绘预编译 instance，输出与整屏 oracle 的 readback tuple 完全一致。
- **同节点冲突帧**：第三按钮 hover color 作为 compiler winner 生效，release 仅更新不冲突的 position。局部 tile 输出没有旧 pressed 几何残影，且与整屏 oracle 一致。
- **边缘处理**：release tile 高度为 50px，包含 2px pressed 位移与 2px rasterization guard；此前的下缘残影由此修复。

全部验证维持 `host layout solver calls: 0`。
