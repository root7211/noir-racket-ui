# noir-winit-host

`noir-winit-host` 是 `#lang noir/ui` 的最小原生窗口宿主。它直接消费 Racket 宏导出的 Scene JSON，在 `winit` 事件循环中使用 compiler Event Map 进行 hit-test，并通过 `wgpu::Surface` 呈现一个 persistent canvas。

当前版本已经迁入真实数字 **Glyph Atlas text-run**：动态数字不是色块或 CPU 重绘文本，而是 compiler 分配的 glyph storage range、`R8Unorm` atlas texture、WGSL sampling 和固定 glyph quad draw。

## 端到端路径

```text
WindowEvent::CursorMoved / MouseInput
  -> compiler Event Map fixed-rect hit-test
  -> action state write
  -> exact queue.write_buffer range
       refresh-fps      -> glyph storage [0, 96)
       refresh-latency  -> glyph storage [96, 192)
       advance-progress -> instance size.x [316, 320)
  -> compiler Tile / DrawRange redraw into persistent canvas
  -> canvas blit to wgpu Surface + present
```

| 层 | 运行时职责 | 明确不做的工作 |
|---|---|---|
| `winit` | 创建窗口并接收原生 pointer 事件。 | 不维护组件树。 |
| Event Map | 对预编译矩形命中并选择 action。 | 不扫描 listener 或节点树。 |
| Glyph Atlas | 从 `glyph_words` storage 读取 digit，采样 atlas。 | 不做动态字体 shaping。 |
| `wgpu::Queue` | 写入 compiler 固定的 glyph/instance byte range。 | 不重建 buffer/pipeline/bind group。 |
| Render Schedule | 将预编译 tile/range 画入 persistent canvas。 | 不执行运行时 layout solve。 |
| Surface blit | 将 canvas present 到窗口。 | 不改变 compiler viewport profile。 |

## 构建

当前依赖锁定为 Rust 1.75 兼容的 `winit 0.29.15` X11-only configuration：

```bash
cd wgpu-verify
cargo build --release --bin noir_winit_host
```

## 导出编译 Scene

```bash
cd noir-racket-ui
PLTCOLLECTS="$PWD:/usr/share/racket/collects" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
  racket tools/export-dashboard.rkt out/registry-match.scene.json
```

## 运行

在 X11 会话中：

```bash
cd wgpu-verify
DISPLAY=:0 XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin noir_winit_host -- ../out/registry-match.scene.json
```

脚本化端到端验证使用 Xvfb 和 xdotool：

```bash
cd noir-racket-ui
./tools/verify_winit_host.sh
```

该脚本真实点击 Event Map 的三个固定按钮坐标，断言两条独立 glyph patch 与一条 progress instance patch。它输出：

```text
glyph-patch fps: [0..96)
glyph-patch latency: [96..192)
instance-patch progress: [316..320)
```

## Viewport 与性能边界

窗口 resize 只 reconfigure Surface。host 保留 compiler 生成的 640×360 canvas，随后做 nearest blit；**不会**在窗口尺寸变化时引入隐式 layout solve。其它 viewport 需通过显式的预编译 Scene/profile 提供。

数字 atlas 当前仅覆盖 `0–9`，每个 cell 固定 32 bytes；它用于验证 text-run 资源计划和增量 glyph patch。下一阶段可在保持相同 range/atlas/page 模型的情况下接入 shaping、更多字符、多个 atlas page 和纹理 eviction 策略。
