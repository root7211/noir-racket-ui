# Glyph Atlas 双绑定视觉核验

已检查 Glyph Atlas 的真实 wgpu 离屏回读工件。

- **基线帧**显示两组由 `R8Unorm` 数字 atlas 采样得到的 3-glyph text-run：左组为 `060`，右组为 `008`。虽然字体是 3×5 的极简位图，所有笔画来自 texture sampling，而不是数值到色块的 shader 分支。
- **执行 `refresh-fps` 后**，左组变为 `144`，右组仍为 `008`。这对应单次 `queue.write_buffer` 的 `[0,96)` 区间更新；延迟 text-run 的 `[96,192)` 数据没有改写。

两帧中的几何容器与按钮区域一致，动态文本字形的局部变化与 action audit 完全对应。
