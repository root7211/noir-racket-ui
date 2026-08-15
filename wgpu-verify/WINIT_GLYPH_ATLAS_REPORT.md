# noir-winit-host：Glyph Atlas text-run 与局部 glyph patch

## 结论

`noir-winit-host` 已从纯色矩形文本占位路径升级为真实数字 Glyph Atlas text-run。窗口宿主现在使用与离屏验证器相同的 44-byte `QuadInstance` ABI、32-byte glyph cell、`R8Unorm` atlas texture 和 WGSL atlas sampling；Racket compiler 生成的 text-run range 在真实 `winit` 输入到 `wgpu::Surface` present 路径中保持精确隔离。

> **真实点击 FPS 按钮只写 glyph storage `[0,96)`；真实点击 Latency 按钮只写 `[96,192)`；Progress 仍只写 instance 的 4-byte `size.x` 字段。**

## 迁移内容

| 组件 | 迁入后的实现 | 目的 |
|---|---|---|
| 实例 ABI | `pos`、`size`、`color`、`glyph_word_offset`、`glyph_enabled`、`glyph_count`，共 44 bytes。 | 让静态 quad 和 text-run 共享 instance buffer。 |
| Glyph storage | 每个 glyph 固定 32 bytes，首个 `u32` 为数字 atlas index。 | 保持 compiler 分配的 byte range 可审计。 |
| Atlas | 10 个数字位图写入 `R8Unorm`、nearest sampler。 | 以真实纹理采样生成数字，而非色块编码。 |
| WGSL | `host_text.wgsl` 按 glyph count 展开 quad，从 storage 读取 digit 后采样 atlas。 | 将 text-run 纳入 Surface render path。 |
| 事件分发 | `dispatch_action` 执行 state write 后只对 action 指定的 `GpuUpdate` 写 storage range。 | 保证 action 因果隔离。 |
| 呈现 | text/static pipeline 渲染 persistent canvas，再 blit 到 `wgpu::Surface`。 | 不引入 runtime layout solve。 |

## 资源与 ABI

```text
fps          glyph offset = 0,  length = 96 bytes, 3 glyph cells
latency      glyph offset = 96, length = 96 bytes, 3 glyph cells
throughput   instance size.x offset = 316, length = 4 bytes
```

其中 `fps`、`latency` 与 `throughput` 三个更新集合互不相交。动态 text instance 带有 `glyph_word_offset` 与 `glyph_count`；static pipeline 会跳过该 instance 的静态 quad，而 text pipeline 只对其执行 `glyph_count × 6` 顶点 draw。

## 已验证的真实窗口闭环

验证脚本在 Xvfb 中启动 `noir-winit-host`，再使用 xdotool 在 compiler Event Map 的固定坐标点击三个按钮。所有事件均来自真实 `winit` X11 event loop，而非 Rust 中直接调用 action。

| 点击坐标 | Event Map action | 观测到的精确 GPU 写入 |
|---|---|---|
| `(100, 250)` | `refresh-fps` | `glyph-patch fps: [0..96)` |
| `(280, 250)` | `refresh-latency` | `glyph-patch latency: [96..192)` |
| `(500, 250)` | `advance-progress` | `instance-patch progress: [316..320)` |

端到端日志：

```text
noir-winit-host: 15 instances, Glyph Atlas text-runs,
                 profile=noir-vulkan-gpu-matrix-v1
event-map hover: slot 0 / refresh-fps-button
event-map dispatch: refresh-fps
glyph-patch fps: [0..96)
event-map hover: slot 1 / refresh-latency-button
event-map dispatch: refresh-latency
glyph-patch latency: [96..192)
event-map hover: slot 2 / advance-progress-button
event-map dispatch: advance-progress
instance-patch progress: [316..320)
```

## 验证边界

测试在 Vulkan llvmpipe + Xvfb 环境完成，因此它证明了真实窗口、Surface、shader、atlas resource、input dispatch 和 range write 的可执行正确性，但不应被解释为独立显卡上的绝对性能基准。此前的 profile calibration 和离屏 oracle 仍负责策略/合成输出的精确对比；本实验扩展了它们的用户输入与 Surface present 维度。

## 复现

```bash
cd noir-racket-ui/wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh
```

## 下一步

下一项正确的工程工作是**文本 shaping、更多字符与多 atlas page**。重要原则是维持现有 compiler contract：Shaped text run 仍须获得固定 glyph range、atlas page 与 draw range；字形缓存增长或 page eviction 必须以编译期预算和显式退化策略约束，不能退回无界 runtime 字符串渲染。
