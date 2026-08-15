# 多层 Clip 与遮挡消除视觉核验

在相同的两层 clip 几何中，opaque 与 alpha 对照场景得到不同但均正确的结果。完全不透明的 `progress-alert` 覆盖 progress 区域；其局部并发帧显示整个 bar 为红色最终合成，compiler 因而只提交高 z overlay instance。半透明对照场景显示 progress 的左侧填充和右侧底色仍透过红色 overlay 可见；compiler 保留 outer stack、inner stack、progress 与 overlay 的完整 painter order。

两条路径均由同一 wgpu 验证器产生，且各自的 scissor/range draw 输出均已与同状态整屏 oracle 的 readback 完全一致。差异来自编译期 blend/opaque 证明和批次选择，而非 host 重新布局或人工重绘；两场景均保持 host layout solver 为 0 次调用。
