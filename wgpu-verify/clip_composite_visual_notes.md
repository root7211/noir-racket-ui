# Clip / Z-order / Alpha Composite 视觉核验

已检查真实 wgpu 的 640×360 输出。

- `progress-layer` 是一个编译期 `stack #:clip #t`。其 `throughput` instance 先以 z=0、opaque batch 绘制；`progress-alert` instance 随后以 z=10、alpha batch 绘制。基线帧中 progress 左段与红色半透明 overlay 的混合可见，且 overlay 不会越出 progress 的 `(34,180,572,22)` clip rect。
- 并发 40ms 帧中，progress action、第一按钮 hover、第三按钮 release 可与 progress overlay 同时存在。局部 Scissor/Tile 输出与整屏 oracle 的 readback tuple 相同。
- 发现并修复了分数 pixel 边界问题：per-range clip 交集采用 `floor(left/top)` 与 `ceil(right/bottom)` 的保守外扩，防止 Tile Cull 漏掉 full rasterizer 的边缘样本。
- 该实现维持一条共享 quad pipeline、12 个已分配实例、3 个局部 tile、7 个 tile draw instances，以及 0 次 host layout solver 调用。
