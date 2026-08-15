# Noir 编译期 Layout Plan 与固定 Instance Offset 验证

## 结论

本阶段已把示例中最后一块主要运行时 UI 工作——递归 Scene tree 布局与像素到 NDC 的坐标转换——从 Rust/wgpu host 移到 Racket 宏展开期。`#lang noir/ui` 现在为每个 node 生成不可变 Layout Entry；host 只反序列化这些 Entry、按固定 `instance_offset` 填充 instance buffer，并执行既有的 text-run action patch。

> **运行时不再递归遍历 `root`、不再计算 row/column 宽度、不再计算 NDC。它只消费编译器输出的 `layout_plan`。**

## Racket 宏：受限布局编译

在宏展开期，`compile-layout-plan` 对已解析的 `c-node` tree 执行受限 layout solver。其输入不包含运行时测量或任意回调，仅使用 DSL 已允许的 `column`、`row`、固定高度和稳定子节点顺序。因此 rect 可以在编译期得到确定值。

```racket
(define (compile-layout-plan root)
  (define-values (raw-layouts ignored-y)
    (node-layout root 0 16.0 16.0 608.0))
  (for/list ([layout (in-list raw-layouts)] [index (in-naturals)])
    (struct-copy c-layout layout
      [instance-offset (* index quad-instance-bytes)])))
```

每个 Layout Entry 包含像素 rect 与已经计算好的 NDC rect。宏以 640×360 作为本 MVP 的 target viewport，在展开期执行：

```racket
(define ndc-pos
  (list (- (* 2.0 (/ x 640.0)) 1.0)
        (- 1.0 (* 2.0 (/ (+ y height) 360.0)))))
(define ndc-size
  (list (* 2.0 (/ width 640.0))
        (* 2.0 (/ height 360.0))))
```

`QuadInstance` 的 ABI 是 44 bytes，因此第 `i` 个 Layout Entry 的 `instance_offset` 固定为 `i × 44`。动态 text-run 同时携带已分配的 `glyph_offset`、`glyph_count` 与 `vertex_count = glyph_count × 6`。

| Node | Instance offset | Glyph range | Vertex count | 编译期 NDC rect |
|---|---:|---:|---:|---|
| `dashboard` | `0` | — | 6 | `(-0.95, 0.678)` / `(1.90, 0.233)` |
| `title` | `44` | — | 6 | `(-0.894, 0.467)` / `(1.788, 0.156)` |
| `metrics` | `88` | — | 6 | `(-0.894, 0.056)` / `(1.788, 0.356)` |
| `fps` | `132` | `[0, 96)` | 18 | `(-0.856, 0.156)` / `(0.831, 0.156)` |
| `latency` | `176` | `[96, 192)` | 18 | `(0.000, 0.156)` / `(0.831, 0.156)` |
| `actions` | `220` | — | 6 | `(-0.894, -0.356)` / `(1.788, 0.356)` |
| `refresh-fps-button` | `264` | — | 6 | `(-0.856, -0.356)` / `(0.831, 0.256)` |
| `refresh-latency-button` | `308` | — | 6 | `(0.000, -0.356)` / `(0.831, 0.256)` |

## wgpu host：只解码计划

Rust 删除了 `LayoutCursor`、`lower_node`、`px_to_ndc` 与 host-side `color_for`。新增的 `precompiled_instances` 不观察 Scene tree；它只对 `layout_plan` 做 ABI 和一致性验证，然后写入固定 slot：

```rust
let slot = entry.instance_offset / std::mem::size_of::<QuadInstance>();
instances[slot] = QuadInstance {
    pos: entry.ndc_pos,
    size: entry.ndc_size,
    color: entry.color,
    glyph_word_offset: (entry.glyph_offset / 4) as u32,
    glyph_enabled: u32::from(entry.glyph_count > 0),
    glyph_count: entry.glyph_count as u32,
};
```

host 在首次上传时执行一次完整 instance-buffer 写入。随后两个 action 的增量路径保持不变：`refresh-fps` 只写 `[0,96)`，`refresh-latency` 只写 `[96,192)`；`instance_writes_after_initial` 保持 `0`。

## 自动化检查

Racket 侧断言覆盖：8 个 Layout Entry、固定 offset 序列 `(0 44 88 132 176 220 264 308)`、`fps` 与 `latency` 的 glyph range / vertex count，以及 `fps` 的预编译 NDC 坐标。

Rust 侧拒绝：Layout Entry 数量与 instance budget 不符、非 44-byte 对齐 offset、重复或越界 slot、未占用 slot、非法 node tag、动态 entry 与 action binding 的 range 不一致、静态 entry 非零 glyph offset、vertex count 与 glyph count 不一致。换言之，host 不是盲目信任 JSON，而是在**不计算布局**的前提下验证 compiler contract。

## 实测结果

在 wgpu 0.20.1、Vulkan backend、llvmpipe CPU adapter 上，端到端运行通过：

```text
Noir Glyph Atlas → wgpu text-run isolation verification
  instance budget : 8 (used 8)
  exact bindings  : [("fps", 0, 96), ("latency", 96, 96)]
  compiler layout entries: 8
  host layout solver calls: 0

  action refresh-fps
    gpu writes  : [(0, 96)]
    checksum    : 30052419 → 29780069

  action refresh-latency
    gpu writes  : [(96, 96)]
    checksum    : 29780069 → 29630486

  shared pipelines : 1
```

图像工件显示，三帧的所有结构性几何与固定 instance slot 保持不变；第一条 action 仅将左侧 atlas text-run 从 `060` 改为 `144`，第二条 action 仅将右侧 text-run 从 `008` 改为 `015`。

| 基线：`060` / `008` | FPS 后：`144` / `008` | 延迟后：`144` / `015` |
|---|---|---|
| ![baseline](out/noir-layout-baseline.png) | ![fps](out/noir-layout-refresh-fps.png) | ![latency](out/noir-layout-refresh-latency.png) |

## 当前边界与下一阶段

Layout Plan 仍是为固定 viewport、固定 row/column 模板设计的受限 MVP。它不应被误写为通用 CSS/Flexbox solver；多分辨率、窗口 resize、动态内容测量和复杂 clip 尚未实现。正确的下一步是以 **viewport class** 为单位编译多个 Layout Plan，并让 runtime 在窗口创建/尺寸类别切换时选择计划，而不是重新求解整个 UI tree。
