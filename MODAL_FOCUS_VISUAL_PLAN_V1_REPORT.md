# Modal Focus Visual Plan v1 — 交付报告

**状态：** 完成。
**交付日期：** 2026-08-17。
**作者：** Manus AI。
**范围：** `#lang noir/ui` 编译期 ring lowering、Rust/wgpu host proof 与执行器、独立 WGSL outline pass、真实 X11/Vulkan 交互证据、篡改拒绝和兼容回归。

## 1. 交付结论

`modal_focus_visual_plan v1` 已把受限 Material overlay 的固定键盘焦点从“只有状态机”推进为“状态机、几何、GPU 资源与视觉输出同样固定”。对于 `material-overlay-showcase` 中的 5 个 Tab 目标，编译器在 Scene 导出时给出 5 枚 outline quad 的全部信息；Rust 在启动期反向验证这些信息，然后仅执行预计算的 alpha 写入和一个局部 tile 重绘请求。[1] [2]

> **结论。** 打开 modal 时初始 ring 可见；`Tab` 把 ring 从 Deploy 移至 Cancel；`Escape` 后 overlay 和全部 ring 消失。三种状态均在真实 X11/Vulkan framebuffer 中截图确认，且对应宿主日志记录了固定 ring 地址与 tile mask。[3]

| 目标 | 结果 |
|---|---|
| 编译期固定的 ring 配方 | 通过：5 个条目，3 px halo、12 px radius、2 px outline、固定蓝色。 |
| Scene ABI 与 required gate | 通过：`noir-modal-focus-visual-plan-v1@1`，object-or-false 解码。 |
| 启动期反向 proof | 通过：source offset、几何、颜色、子图归属、tile 等逐项检查。 |
| GPU 资源 | 通过：5 个独立 44-byte QuadInstance、5 个 16-byte SDF metadata、独立 pipeline。 |
| 键盘热路径 | 通过：open 1 次 alpha 写，Tab/Shift+Tab 2 次，close 清零预分配集合。 |
| 真实视觉 | 通过：X11/Xvfb + Vulkan 成功渲染并保存截图。 |
| 篡改拒绝 | 通过：source、geometry、tile、disable 四种攻击均在启动期被拒绝。 |
| 既有圆角兼容 | 通过：rounded surface 的 log-browser 与 realtime-monitor 双应用回归。 |

## 2. 实现构成

Racket 侧新增 ABI contract、运行时 plan/entry 结构、编译期 `c-modal-focus-visual-*` 结构、从 modal focus subgraph 到 ring recipe 的 lowering、Scene JSON serializer，以及 `ui`/`noir-app` 两种 Scene 构造的显式 required 字段。新的 language regression 对 `material-overlay-showcase` 固化了 ring ID、event slot、source instance offset、外扩像素几何、radius、thickness、颜色和 tile 集合。[1] [4]

Rust 侧新增 wire 结构与 object-or-false decoder，并把 schema/revision 纳入统一 ABI gate。`compiler_modal_focus_visual_plan` 的 proof 不信任 JSON 中的 source pointer 或几何：每个条目必须重新与 Event Map、modal Tab 子图、overlay plan 和已编译 render tiles 对照。proof 成功后才生成 `ring_for_event_slot` 数组，事件热路径可以直接从 event slot 获得 ring buffer index。[2]

| 层 | 新增产物 | 关键不变量 |
|---|---|---|
| 宏编译器 | `compile-modal-focus-visual-plan` | 不改变 layout、glyph、action 或 packet ABI；只消费冻结的 modal/event/tile 结果。 |
| Scene wire | `modal_focus_visual_plan` / `modal_focus_visual_required` | required 的 Scene 不可将计划替换成 `false`。 |
| Host proof | `CompiledModalFocusVisualPlan` | 每个 Tab slot 有且仅有一个 canonical ring。 |
| GPU | `GpuFocusRingMeta` / `host_focus_ring.wgsl` | 16-byte immutable metadata；alpha 在独立 QuadInstance byte 28。 |
| Render | `draw_focus_rings` | 固定为 static surface 后、glyph 前；tile path 仅在关联 mask 相交时调用。 |
| Event executor | `set_focus_ring_for_event` | 不做 node/rect 搜索；只改已证明 buffer slot 的 f32 alpha。 |

## 3. 实际编译产物

`out/material-overlay-showcase.scene.json` 的 v1 plan 含 5 个 entries。5 个 ring 共占 `5 × 44 = 220 bytes` 的 GPU instance 存储，以及 `5 × 16 = 80 bytes` 的 immutable SDF metadata；它们不占用静态 UI instance table，也不会与 overlay alpha 表冲突。[2] [5]

| Buffer slot | Tab event slot | 控件 | Source offset | Geometry | 初始 alpha |
|---:|---:|---|---:|---|---:|
| 0 | 3 | Deploy | 924 | `(757, 393, 110, 46)` | 0 |
| 1 | 2 | Cancel | 836 | `(641, 393, 110, 46)` | 0 |
| 2 | 4 | Pin build | 1144 | `(933, 169, 214, 46)` | 0 |
| 3 | 5 | Copy artifact | 1320 | `(933, 213, 214, 46)` | 0 |
| 4 | 6 | Export manifest | 1496 | `(933, 257, 214, 46)` | 0 |

其中的几何已经包括 compiler 所加的 3 px halo；因此 shader 只执行 SDF coverage，而不会在运行时查询原控件的 rect 或 radius。outline shader 使用外圆角矩形减去按 2 px 厚度内缩的圆角矩形；其 antialias 阈值来自 `fwidth` 并下限为 0.5 px。[2] [6]

## 4. 固定状态转换与写集

| 输入 | 焦点状态 | GPU 写入 | RenderRequest |
|---|---|---|---|
| open overlay | `current_index = 0`，event 3 | slot 0 alpha `0 → 1`，4 bytes | tile mask `0x1`，`NO_PACKETS` |
| `Tab` | `3 → 2`（后续继续环） | slot 0 `1 → 0`；slot 1 `0 → 1`，共 8 bytes | tile mask `0x1`，`NO_PACKETS` |
| `Shift+Tab` | 使用既有 `previous_slots` | 当前与前一 ring 共 8 bytes | tile mask `0x1`，`NO_PACKETS` |
| `Enter` | 激活当前 close action | overlay close + 全部 ring 隐藏 endpoint | 既有 overlay tile mask |
| `Escape` / scrim close | 恢复 slot 0 上下文 | 全部 5 个 ring 清零 | 既有 overlay tile mask |

虽然 close 遍历的 ring 数是编译期固定的 5，运行时依然不枚举 UI 树或动态资源。该小循环只是对 resident alpha lane 的恒定写集合执行存储；其地址、数量和局部 tile 范围都已经由 Scene proof 固定。[2]

## 5. 验证结果

完整一键入口是：

```bash
cd /path/to/noir-racket-ui-statistical-analysis
bash tools/verify_modal_focus_visual_plan_v1.sh
```

该入口的执行顺序为 Racket language checks、Scene structural oracle、Rust 1.87 release build、真实 X11/Vulkan 的 mouse/Tab/Shift+Tab/Enter/Escape 输入、三张截图、4 个攻击 Scene，以及 rounded surface 双应用回归。[3] [7]

| 验证项 | 结果 | 证据 |
|---|---|---|
| Racket macro/language regression | PASS | `Noir Cost Model language checks passed.` |
| Scene structural oracle | PASS | `modal_focus_visual_plan v1 structural oracle: PASS` |
| Rust release build | PASS | `cargo build --release --bin noir_winit_host`，Rust 1.87。 |
| X11/Vulkan open | PASS | 日志：`focus-ring=Some(0) alpha-patches=1`。 |
| X11/Vulkan Tab / Shift+Tab | PASS | 日志：`rings=0=>1 alpha-patches=2`，以及 canonical reverse edge。 |
| X11/Vulkan close | PASS | 日志：`focus-ring-alpha-clears=5`。 |
| Screenshot evidence | PASS | `out/modal-focus-visual-evidence/01..03*.png`。 |
| source tamper | REJECTED | `invalid source instance offset`。 |
| geometry tamper | REJECTED | `violates the fixed halo/outline/color recipe`。 |
| tile tamper | REJECTED | `tile ID 1 exceeds compiled tile table`。 |
| disable tamper | REJECTED | `marked modal_focus_visual_required may not disable`。 |
| rounded two-app compatibility | PASS | `ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS`。 |

截图审阅记录在 [`out/modal-focus-visual-evidence/VISUAL_CHECKS.md`](out/modal-focus-visual-evidence/VISUAL_CHECKS.md)。打开帧只在 Deploy 上有蓝色圆角空心 ring；一个 Tab 后 ring 精确移至 Cancel；Escape 帧没有残余 outline。[3]

## 6. 局限与后续工作

v1 仅解决 modal focus subgraph 的可视化；它刻意不把常规 Focus Graph、列表行、文本字段或可动态变更的控件纳入同一 ring 系统。下一步应维持相同 proof discipline，把 navigation、overlay、10,000 行虚拟数据视图与固定焦点子图组合为单一 Material observability workbench，而不是把 ABI 放宽为运行时 UI 搜索或通用 retained component graph。

## References

[1] [Racket compiler and Scene serializer](noir/ui/main.rkt)
[2] [Rust host proof, GPU resources, renderer and alpha executor](wgpu-verify/src/bin/noir_winit_host.rs)
[3] [X11/Vulkan screenshots and review](out/modal-focus-visual-evidence/VISUAL_CHECKS.md)
[4] [Language regression](tests/run.rkt)
[5] [Compiled overlay Scene](out/material-overlay-showcase.scene.json)
[6] [Focus-ring WGSL shader](wgpu-verify/src/host_focus_ring.wgsl)
[7] [One-command full regression](tools/verify_modal_focus_visual_plan_v1.sh)
