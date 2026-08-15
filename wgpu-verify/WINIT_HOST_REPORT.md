# noir-winit-host：真实窗口、Surface 与 Event Map 闭环

## 结论

`noir-winit-host` 已将 Noir 的离屏验证链路接入真实 `winit` 窗口和 `wgpu::Surface`。它加载 Racket 宏输出的 Scene JSON，使用已编译的 Event Map 完成 hit-test，按固定 byte offset 写入 hover/pressed/action patch，将预编译 Render Schedule 绘制到持久 canvas，并通过 Surface present 到窗口。

> **窗口宿主不负责理解 UI 结构；它只执行 compiler 已经确定的输入、资源写入和绘制计划。**

## 架构

```text
OS WindowEvent::CursorMoved / MouseInput
  -> Event Map fixed-rect hit-test
  -> queue.write_buffer at compiler-fixed offsets
  -> precompiled Tile / DrawRange render to persistent 640×360 canvas
  -> blit canvas to wgpu Surface
  -> present
```

| 组件 | 职责 | 明确不做的工作 |
|---|---|---|
| `winit::Window` | 提供原生窗口、指针事件和 resize 通知。 | 不保存 UI tree。 |
| `Event Map` | 按编译期 rect/slot/action 选择目标。 | 不动态搜索组件或监听器。 |
| `wgpu::Queue` | 对固定 instance field range 做局部写入。 | 不重建 instance buffer。 |
| persistent canvas | 保留上一帧，允许 Render Schedule 做 tile/range draw。 | 不重新 layout。 |
| Surface blit | 将 canvas 作为最终窗口帧 present。 | 不改变 profile viewport。 |

## 实现内容

新增文件如下：

| 文件 | 内容 |
|---|---|
| `wgpu-verify/src/bin/noir_winit_host.rs` | winit 事件循环、Surface 配置、persistent canvas、Event Map 分发与 present。 |
| `wgpu-verify/src/host_quad.wgsl` | 基于预编译 `QuadInstance` 的共享 quad pipeline。 |
| `wgpu-verify/src/host_blit.wgsl` | canvas 到 Surface 的三角形 blit。 |
| `tools/verify_winit_host.sh` | Xvfb + xdotool 的真实鼠标事件回归。 |
| `wgpu-verify/WINIT_HOST_README.md` | 构建、运行和边界说明。 |

宿主使用 X11-only `winit 0.29.15` feature 与 `rwh_06`，以兼容当前 Rust 1.75，并避免 Wayland scanner 的高 MSRV 依赖。真实 Wayland 支持应在升级 Rust 或锁定一个兼容的 Wayland 依赖链后单独启用。

## 已验证的真实窗口输入闭环

脚本在 Xvfb 中启动 `noir-winit-host`，等待窗口创建后，用 `xdotool` 注入坐标 `(500, 250)` 的 cursor move、mouse down 和 mouse up。该坐标位于 compiler Event Map 中第三个按钮的固定 hit rect。

| 断言 | 实测结果 |
|---|---|
| winit EventLoop 创建 | 通过，强制 X11 backend。 |
| wgpu Surface 初始化与 initial present | 通过。 |
| CursorMoved 命中 Event Map | `slot 2 / advance-progress-button`。 |
| MouseInput down/up 回环 | 通过。 |
| action 分发 | `advance-progress`。 |
| 宿主构建警告 | 0。 |
| Host layout solve | 0；resize 只做 Surface reconfigure。 |

实际日志：

```text
noir-winit-host: 15 precompiled nodes, 3 Event Map bindings,
                 profile=noir-vulkan-gpu-matrix-v1
event-map hover: slot 2 / advance-progress-button
event-map dispatch: advance-progress
winit host Event Map roundtrip verified.
```

## Viewport 与性能边界

当前 compiler profile 固定为 640×360。窗口 resize 会 reconfigure Surface，但**不会触发 layout solve**：宿主保留同一 640×360 persistent canvas，再做 nearest blit。这样保持了 Noir 的编译期几何保证，但也意味着应用需要为其它 viewport 显式生成 profile，而不是在 host 内部静默自适应。

当前 host 是一条可点击的最小纵向切片。为了缩小实现并保证可观察性，文字在宿主 renderer 中仍使用 rectangle-compatible visual path；完整 Glyph Atlas text-run shader 可作为下一步从离屏验证器移植的任务。

## 复现

```bash
cd noir-racket-ui
PLTCOLLECTS="$PWD:/usr/share/racket/collects" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
  racket tools/export-dashboard.rkt out/registry-match.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host

cd ..
./tools/verify_winit_host.sh
```

在真实桌面会话中运行：

```bash
cd wgpu-verify
DISPLAY=:0 XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin noir_winit_host -- ../out/registry-match.scene.json
```

## 下一步

最直接的下一步是将离屏验证器中已验证的 **Glyph Atlas text-run shader、storage glyph range 与 text-run patch** 迁移到 `noir-winit-host`。这样真实窗口闭环就不会只展示 rect-compatible demo，而是能在 Surface 上呈现并局部更新真实 atlas 数字文本，同时继续沿用已经证明的 `[0,96)` / `[96,192)` glyph range 隔离。
